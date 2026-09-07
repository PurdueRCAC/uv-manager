# Redirect-failure semantics for the lock-acquire retake

Empirical, not read-from-the-manual. Every claim below was run, not inferred. Test scripts and
harness output live in a throwaway scratch dir (not part of this repo) and are not retained.

Environments tested: `/bin/bash` 3.2.57(1)-release (macOS, arm64, the shell that parses
`bin/uv-manager`) and GNU bash 5.2.37(1)-release (Docker image `bash:5.2`, aarch64/musl). A stray
check also used bash 4.4.23 for one probe. **No behavioral difference was found between 3.2 and 5.2
on any of the nine questions.** The one apparent divergence (below, Q4) turned out to be a stdout/
stderr interleaving artifact of merged terminal capture, not a semantic difference — a rerun with
the two streams captured to separate files was byte-identical across both versions.

## Decisions

1. A failed redirect on `printf` never trips `errexit` inside `if CMD; then`, `CMD || ...`, or a
   `while`/`until` test — identical on 3.2 and 5.2. The candidate loop shape is safe as written.
2. The failed command's exit status is always **1** (ENOENT and EACCES alike, builtin and external
   `printf` alike).
3. The shell's own diagnostic text is exactly `<scriptname>: line N: <path>: No such file or
   directory` (ENOENT) or `...: Permission denied` (EACCES) — identical wording and format on 3.2
   and 5.2. A verify gate matching this string should match on the trailing `<path>: <reason>`
   suffix, since `<scriptname>` and the line number are not stable across call sites.
4. **Redirections apply strictly left to right, and a failure aborts the rest of that command's
   redirection list.** `> BADPATH 2>/dev/null` does **not** suppress the diagnostic (the bad
   redirect fails before `2>/dev/null` is ever applied); `2>/dev/null > BADPATH` **does** suppress
   it. Confirmed identically on both bash versions. `uvm_unlock`'s comment on this is correct.
5. ENOENT and EACCES are indistinguishable in control flow — same exit status (1), same branch
   taken, only the trailing diagnostic word differs. Nothing in the candidate needs to special-case
   one versus the other.
6. Neither `set -u` nor `set -o pipefail` changes any of the above, alone or combined with `set -e`.
   `printf` (non-special builtin) and `/usr/bin/printf` (external) behave identically — same
   diagnostic, same exit status, same non-fatality. (A genuine POSIX *special* builtin, `:`, was
   also probed for contrast: bash — on both 3.2 and 5.2 — does **not** implement POSIX's "special
   builtin redirection error kills a non-interactive shell" rule at all; it behaves exactly like a
   normal command. This is a bash-wide non-conformance, present on both tested versions, and is not
   load-bearing here since `printf` was never special to begin with.)
7. The full candidate loop (mkdir → if-write-then-break, else robbed-count-or-die) was run end to
   end under a `mkdir` shim that simulates a racer. Robbed-twice-then-succeeds converges with
   `rc=0`; robbed-three-times hits the `(( robbed >= 3 ))` bound and calls `die`; the EACCES variant
   (directory survives, chmod 500) reaches `die` on the **first** failure, never incrementing
   `robbed`. All three outcomes identical on 3.2 and 5.2.
8. `while :; do if mkdir; then ...; fi; wait-body; done` and `while ! mkdir; do wait-body; done;
   success-body` are behaviorally identical for the two cases with no retry logic (immediate success,
   fail-once-then-succeed). They are **not** interchangeable once the success path itself needs to
   loop back and retry `mkdir` (the robbed case): `continue` written after a `while ! mkdir; do...
   done` loop is lexically outside any loop, and bash's response is to print `continue: only
   meaningful in a 'for', 'while', or 'until' loop` to stderr and fall through to the *next*
   statement — it does **not** retry the mkdir, and (surprisingly) it does not abort under `set -e`
   either. This is silent breakage, not a syntax error, so the candidate's shape (mkdir inside the
   `if`, nested in one `while :` that hosts both success- and wait-handling) is required, not
   stylistic.
9. Confirmed exactly as the seed claims: `err=$( { printf ... > BAD; } 2>&1 )` with no `|| true` is
   fatal under `set -euo pipefail` — the script aborts on that line, before a later `die` ever runs.
   Appending `|| true` makes the assignment itself the (exempt) left operand of an OR list: the
   script survives, `$?` after the statement is 0, and — notably — `err` still contains the shell's
   diagnostic text, because `2>&1` on the group is applied *before* the inner redirect fails (same
   left-to-right rule as Q4), so the failing redirect's stderr is already pointed at the captured
   fd 1.

## Evidence

### Q1–Q3: if/else and `||` under errexit, and the diagnostic text

```
if printf '%s\n' X 2>capture.err > /nonexistent_dir_xyz/f; then echo THEN; else echo "ELSE rc=$?"; fi
```
→ `ELSE rc=1` on both versions; script continues; `capture.err` contains:
`./script.sh: line N: /nonexistent_dir_xyz/f: No such file or directory`

```
printf '%s\n' X 2>capture.err > /nonexistent_dir_xyz/f || echo HANDLED
```
→ `HANDLED`, same diagnostic text, script continues past it. Both forms behave the same whether
`printf` is the builtin or `/usr/bin/printf`.

Order matters for capture, too: `> BAD 2>file` never creates `file` (the first, failing, redirect
aborts the list before the second is set up); `2>file > BAD` does create `file` with the message
inside it. This is the same left-to-right rule as Q4, observed independently here.

### Q4: redirection order

Clean test (each stream to its own file, to eliminate terminal-interleaving noise):
`> BAD 2>/dev/null` — the diagnostic escapes to the script's real stderr (not suppressed).
`2>/dev/null > BAD` — nothing escapes (suppressed). Identical result, byte for byte, on 3.2 and 5.2.
(A first pass with merged terminal output showed the diagnostic landing in different visual
positions between bash 3.2 and 5.2 — that was pure stdout/stderr buffering interleaving from
`docker run`'s combined stream, not a semantic difference; the separated-file rerun eliminated it.)

### Q5: ENOENT vs EACCES

Ran as non-root (`id -u` = 501) against a missing parent dir and against a directory `chmod 500`.
Both: `rc=1`, `else`/`||` branch taken, script continues. Diagnostics: `No such file or directory`
vs `Permission denied`. No other difference, on either bash version.

### Q6: `set -u`, `set -o pipefail`, builtin vs external

Six flag combinations (`no flags`, `-e`, `-u`, `pipefail`, `-euo pipefail`, plus an unrelated unset
variable declared) × builtin/external `printf`, on both bash versions: every combination reached the
`else`/`HANDLED` branch with `rc=1` and let the subshell finish normally (`subshell exit status: 0`).
No combination changed the outcome.

### Q7: full candidate shape under a racing shim

A shell function named `mkdir` wraps `command mkdir`, then (on the first N attempts) either
`rmdir`s the just-created directory (ENOENT-on-write path) or `chmod 500`s it (EACCES-on-write
path), modeling a concurrent process that stole or restricted the lock between our `mkdir` success
and our `owner`-file write.

- Robbed twice, succeeds on the third attempt: `attempts=3 robbed=2`, owner file written, loop
  `break`s, script exits 0.
- Robbed on every attempt: `robbed` reaches 3 and `(( robbed >= 3 ))` short-circuits past
  `continue`, straight into `die "lock repeatedly stolen out from under us (robbed=3)"`, `rc=1`.
- EACCES (directory survives the "attack", just loses write permission): `[[ -d "${lock}" ]]` is
  true on the very first failed write, so it goes straight to the existing `die "cannot record
  ownership..."` path without ever touching `robbed`.

All three identical on bash 3.2 and 5.2.

### Q8: loop shape equivalence and the `continue` trap

For plain success/fail-then-succeed, `while :; do if mkdir; then break; fi; wait; done` and
`while ! mkdir; do wait; done` (success code after the loop) produce the same acquisition outcome
on both bash versions. The difference appears once the success path needs to retry: a `continue`
placed after `while ! mkdir; do...done` (i.e., not lexically inside any loop) prints `continue: only
meaningful in a 'for', 'while', or 'until' loop` to stderr, does **not** raise `$?` to something
`errexit` would catch, and does **not** retry — it just falls through to the next statement. That
failure mode is silent unless something is watching stderr; it is not a parse-time error. This is
why the robbed-retry logic must live inside the `if`-guarded body of a single `while :` loop, as the
candidate does, and cannot be hosted by the `while ! mkdir; do...done` idiom without wrapping that
whole construct in an outer loop (at which point it has become the candidate's shape anyway).

### Q9: command substitution with `2>&1`, with and without `|| true`

```
err=$( { printf '%s\n' "$owner" > "${lock}/owner"; } 2>&1 )
```
Aborts the script immediately (`set -euo pipefail`), before a later `die` call — confirmed on both
bash versions, output stops right after the line preceding the assignment.

```
err=$( { printf '%s\n' "$owner" > "${lock}/owner"; } 2>&1 ) || true
```
Survives; the later `die` (written into the test to prove reachability) runs; `err` contains the
diagnostic text (`.../owner: No such file or directory`) because the group's `2>&1` was already in
effect when the inner redirect failed, so the failure's own message went to the captured stream.

## Practical implication for the candidate patch

The three-way choice among `if printf ...; then`, `printf ... || { ...; }`, and
`err=$(...) 2>&1` is not a toss-up: the first two are safe and equivalent under
`set -euo pipefail` on both bash versions tested, need no `|| true` guard, and never lose the
diagnostic text if the capturing redirect is ordered before the failing one. The `err=$(...)` form
is fatal unless explicitly guarded, and is the one shape a reviewer should flag if it appears
without `|| true` immediately attached.
