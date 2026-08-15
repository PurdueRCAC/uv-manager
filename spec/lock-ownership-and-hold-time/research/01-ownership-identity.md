# Research — lock ownership: what makes a release provably ours

Scope: R1, and the `uvm_acquire_lock` / `uvm_unlock` high-blast-radius region. Every number below was
measured on this machine (bash 3.2.57, APFS) or by driving a modified copy of the wrapper outside the
working tree under `.agents/factory/bin/temp_root.sh --offline`. The working tree was not edited.

## Conclusion

**Record the exact owner line in a shell global at acquire, compare the whole line at unlock with the
`read` builtin, and treat every non-match — including absent, empty and unreadable — as "not ours,
leave it". Clear `uvm_lock` before the comparison. Confidence: high; the defect and the fix were both
driven end to end.** Host and pid alone are not a sufficient token; add a `$RANDOM` nonce, which costs
no fork. Because the line is compared against a copy this process kept, its *content* becomes a
diagnostic choice rather than a correctness one, which is what lets R5 keep `host=` and `pid=` in it
for a human to act on.

The baseline defect reproduces exactly as the GOAL describes: with a foreign `owner` written while the
holder slept in the installer, the holder's own release left `lock dir: GONE`. With the patch, the
same drive left the directory and the foreign `owner` intact, `uv 9.9.9 (fixture)` alone on stdout.

## 1. The identity token

`$$` is the right variable and needs no fallback. Measured under bash 3.2.57, it reports the same
value — the shell's own pid — inside `$( )`, inside `( )`, inside a pipeline subshell, inside a
function, inside the `INT` handler and inside the `EXIT` handler. `$BASHPID`, which would report the
subshell's real pid, is unset: it arrived in bash 4.0 and the portability floor is 3.2. That
stability is the property wanted here — the entity that owns the lock is the shell whose `EXIT` trap
will release it, and `$$` names exactly that from anywhere in the file.

`$$` also survives `exec`, so a pid identity cannot distinguish the wrapper from the `uv` that
replaced it. That is a second argument for R4 rather than a problem for R1.

Pid reuse is not negligible on this project's own stated workload. A single-threaded spawn loop on an
idle laptop consumed **694 pids/s**. Linux's common default `pid_max` of 32768 wraps in **47 s** at
that rate; `UVM_LOCK_STALE` defaults to 600 s, so the pid space can turn over a dozen times inside one
stale window. The hot-path note in `AGENTS.md` describes `uv run` inside loops calling it thousands of
times, which is precisely a pid-consuming workload on the node that also holds the lock. `host=` plus
`pid=` can therefore collide with a live foreign holder.

A start time would close it on Linux — `/proc/<pid>/stat` field 22, readable with the `read` builtin
and no fork — but there is no `/proc` on macOS and the parse is 22 fields deep. `${RANDOM}${RANDOM}${RANDOM}`
is a bash 3.2 builtin, roughly 45 bits, one expansion, no fork, and portable. Take the nonce.

Drop both command substitutions from the write at `:242`. `${HOSTNAME}` is set in a non-interactive
bash 3.2 and matched `uname -n` exactly here, and `time=` duplicates the directory mtime that
`uvm_age` already reads. This is not only a saving: it narrows a window (§3).

## 2. Reading the owner file without forking

Measured over 2000 iterations, against a 9.4 µs empty-loop baseline:

| Form | Cost |
|------|------|
| `read -r line < file` | 34.3 µs |
| `line="$(cat file)"` | 1686.2 µs |
| `read` plus a `[[ ]]` compare | 36.1 µs |

Sixty-seven times. `$(cat)` spends 1.7 ms — a third of the whole 5 ms budget — on a path the `EXIT`
trap runs on every invocation that provisioned. The builtin spends half a percent.

Three failure modes matter, all measured under `set -euo pipefail`:

**A failed redirect aborts the script.** An unguarded `read -r x < missing` killed the shell. Guard
with `|| true`.

**Redirect order is load-bearing.** `read -r x < missing 2>/dev/null` still prints
`No such file or directory` on the user's stderr, because redirections are applied left to right and
the input open fails before stderr has been redirected. `read -r x 2>/dev/null < missing` is silent.
The obvious spelling is the wrong one.

**A failed read leaves the variable untouched.** With `x=PRESET`, a missing file, an unreadable file
and a directory all returned rc=1 with `x` still `PRESET`. Initialize to empty in the same `local`.

Do not branch on the return code. A file with no trailing newline returns rc=1 *with the data
assigned*, so rc conflates a truncated write with a successful read of good data. Branching on the
string comparison instead collapses absent, empty, truncated and unreadable into one outcome, which
is the outcome §4 wants anyway.

## 3. The TOCTOU window

It cannot be closed with `mkdir`-only primitives. A shell addresses the lock by path and has no way
to pin an inode. It can be narrowed, and it already sits behind a second guard worth keeping.

One fork+exec measured **1.34 ms** here. The release is `read` (builtin) → `rm -f owner` (fork) →
`rmdir` (fork), so the interval between the decision and the unlink is roughly 1.3–2.7 ms.

`rmdir` on a non-empty directory fails with `Directory not empty` and the directory survives —
measured. That is a genuine second guard: a breaker that re-acquires writes its `owner` file
immediately after `mkdir`, so a stale `rmdir` can only destroy the new lock if it lands inside the new
holder's `mkdir`-to-owner-write gap. **That gap is 3.0 ms today**, because the write at `:242` spends
two command substitutions before the file exists. Written from shell variables alone it measured
**0.10 ms** — a 29-fold narrowing of the only interval in which the race can bite, from a change made
for other reasons.

Two alternatives were considered and rejected. `rm -rf "${lock}"` is one fork instead of two and
halves the outer window, but it discards the `ENOTEMPTY` guard, which is worth more than the halving.
Rename-then-remove (`mv "${lock}" "${lock}.releasing.$$"`) does not help at all: rename addresses by
path too, so a victim would relocate the new holder's lock instead of deleting it — the same defect
with a worse recovery story.

The residual race is reachable only after a break has already fired against a live holder, which R2's
heartbeat and R3's ordering check exist to prevent. R1 is the last line of defense, not the only one.

## 4. Missing or unparseable owner

Leave the directory. The asymmetry is not close. A false leave is bounded: nothing refreshes the mtime
of a lock whose holder is gone, so the stale breaker reclaims it within `UVM_LOCK_STALE`, and a waiter
whose request is already satisfied returns through the early-out long before that. A false delete
destroys live mutual exclusion — the defect R1 exists to remove — and is bounded by nothing.

All three degenerate shapes were driven against the patched copy under `--offline`: `owner` truncated
to empty, `owner` deleted, `owner` at mode 000. Each left the directory in place, emitted one `note`
on stderr, exited 0, and returned `uv 9.9.9 (fixture)` alone on stdout, so §7 output discipline holds.

The `|| true` at `:243` is what makes the absent case legitimate, and it also makes it self-inflicted:
a holder whose owner write failed cannot later prove ownership and leaks its own lock for a stale
window. The alternative is to treat that write as fatal — at the instant after `mkdir` returns,
ownership is certain and the directory can be removed safely — which trades a rare silent leak for a
rare loud failure. That is a plan-level call, not a research one.

## 5. Clearing `uvm_lock` in every case

Yes, and *before* the ownership comparison, into a local. Measured under bash 3.2: the `EXIT` trap does
run after the `INT` handler's `exit 130`, and status 130 survives. With the clear placed first, the
second call is a single `[[ -n ]]` test — 4.3 µs — and prints nothing. With the clear left on the
success path, the declined case would re-read the file and re-print its note on the way out, and could
in principle reach a different verdict the second time. Both orderings were driven; only the first is
idempotent.

The same guard is what makes R4's release-before-`exec` free: on a path holding no lock, `uvm_unlock`
is one builtin test and no fork.

## What was driven

Against a copy at `$(mktemp -d)/probe`, `bash -n` clean, under `temp_root.sh --offline --keep` with a
`UVM_FIXTURE_SLEEP` knob added to the fixture so the hold could be raced:

- baseline, foreign `owner` injected mid-hold → `lock dir: GONE` (defect reproduced);
- patched, same injection → directory and foreign `owner` both survive, one note on stderr;
- patched, ordinary case → `current -> versions/9.9.9`, lock removed (R6 unaffected);
- patched, `owner` empty / absent / unreadable → directory survives, exit 0;
- trap harness, `INT` then `EXIT` → release once, second call a builtin no-op, rc 130.

## Not established

- `mkdir` and rename atomicity on Lustre, GPFS and NFS. APFS only; the GOAL declares this limit.
- Fork costs are macOS/APFS figures. Linux fork+exec is usually cheaper, so the absolute milliseconds
  do not transfer; the ratios and the ordering of the options do.
- `${HOSTNAME}` equalled `uname -n` on this host. Bash sets it from `gethostname()`, but a site whose
  login shell exports a short name while `uname -n` returns an FQDN would see them differ. Harmless
  for the comparison, which is against a copy of our own string, but it changes what a human reads in
  the R5 timeout message.
- Linux `pid_max` was not read from a cluster node; 32768 and 4194304 are the two common defaults, and
  694 pid/s is a laptop rate, not a login-node rate under real load.
- Whether the declined-path `note` is wanted. It is output on a path no ordinary user can provoke, and
  it is also the only signal that a lock was deliberately left behind.
