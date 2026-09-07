# PLAN — A rank robbed of its fresh lock retakes it

> **Status:** Draft for review · **Last updated:** 2026-09-06
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).
> Every design element traces to a GOAL R-ID.

## 1. Summary

`uvm_acquire_lock` wins `mkdir`, then records ownership in a write that dies on any failure. The
failure has two causes and only one of them deserves a death. Moving the `mkdir` from the `while`
condition into the loop body puts the owner write inside the loop, so a rank whose lock directory was
removed out from under it can `continue` and take the lock again instead of exiting with empty
stdout. A directory that is still present when the write fails is a filesystem fault and still dies,
carrying its errno. The retake is bounded by a literal three, in the style of the `absent` counter
twenty lines above it, and shares the function's existing timeout accounting rather than adding any.

## 2. Design

One function changes: `uvm_acquire_lock` (`bin/uv-manager:286-480`). Nothing else in the script is
touched, no environment variable is added, no subcommand is added, and no file the user reads changes.

### The restructure

`bin/uv-manager:346` is today `while ! mkdir "${lock}" 2>/dev/null; do`, and the owner write sits
after the loop at `:462`. The write moves inside, under a `while :; do` whose first statement is the
`mkdir`:

```sh
while :; do
  if mkdir "${lock}" 2>/dev/null; then
    if printf '%s\n' "${owner}" > "${lock}/owner"; then
      break
    fi
    if [[ -d "${lock}" ]]; then
      rmdir "${lock}" 2>/dev/null || true
      die "cannot record ownership of the provisioning lock at ${lock}/owner"
    fi
    robbed=$(( robbed + 1 ))
    (( robbed >= 3 )) || continue
    die "cannot hold the provisioning lock at ${lock} …"
  fi
  … the existing wait-loop body, unchanged and at its current indentation …
done
```

The existing body — the `absent` retry, the version-satisfied early-out, the liveness probe, the
break block, the `waited` timeout and the trailing `sleep 1` — is not re-indented and not edited. It
runs exactly when it ran before: `mkdir` failed. That is the whole reason for this shape rather than
an outer `while` wrapped around the current loop, which would re-indent a hundred lines of graded
code and bury the change.

The shape is also structurally forced. A `continue` written after the current
`while ! mkdir; do … done` is lexically outside any loop; bash reports
`continue: only meaningful in a 'for'/'while'/'until' loop`, falls through, and does not retry, and
`set -e` does not catch it ([`research/01`](research/01-redirect-failure-semantics.md) Q8).

### The discriminator

The only evidence the shell has about a failed redirect is its status, which is 1 for ENOENT and for
EACCES alike ([`research/01`](research/01-redirect-failure-semantics.md) Q1). The state that
distinguishes them is the directory: absent means something removed the lock this process had already
won, which is a lost race; present means the write itself was refused, which is a fault. A present
directory keeps today's behavior exactly — `rmdir`, then `die`, with the shell's own diagnostic
already on stderr carrying the errno that names the fault.

The write keeps its current redirection order. Redirections apply strictly left to right and a
failure aborts the rest of the list, so `> "${lock}/owner" 2>/dev/null` would not suppress the
diagnostic anyway, while `2>/dev/null > "${lock}/owner"` would suppress it on both paths and cost R2
the errno ([`research/01`](research/01-redirect-failure-semantics.md) Q3, Q4).

### The bound

`robbed` is declared on the existing `local` line at `:289`, beside `waited`, `absent` and `broke`,
and never re-`local`'d inside the loop — declaring it in the body would silently reset it every pass
and make the retake unbounded ([`research/03`](research/03-contract-surface.md) Part 2). It is a
literal three and never an environment variable, and it never resets, so three is the total number of
extra iterations a robbed rank can add to the wait however the loop alternates between being robbed
and losing `mkdir`. The retake path does not sleep and does not touch `waited`, so a rank robbed
repeatedly exits in well under a second rather than consuming its timeout: measured 0.25s against
`UVM_LOCK_TIMEOUT=5`.

Its `die` is a distinct message, because "won the lock three times and had it removed three times"
is a different operational condition from `absent`'s "cannot create the lock at all", and pointing an
operator at permissions and quota would be wrong.

### What is removed

The nine-line `# Fatal, not best-effort:` comment and the `printf … || { rmdir; die; }` block after
the loop are deleted outright. Their content does not move wholesale: the sentence about ownership
being certain the instant `mkdir` returns, and the sentence about the write preceding `uvm_lock` so
the EXIT trap cannot leak, both still hold and belong beside the new write. The claim that the write
is fatal is what narrows.

### Comments to write

The repository's voice rules apply and the new block carries four *whys*, none of which the code
states: that a failed redirect cannot name its own errno to the shell, so the directory is the only
evidence; that absence is a lost race and presence is a fault; that the bound is a literal for the
same reason `absent`'s is, and never resets; and that the shell's diagnostic stays unsuppressed
because it carries the errno R2 depends on. No feature-scoped spec ids.

### The invariant text

`AGENTS.md:154` and `.agents/factory/invariants.md:81` both assert the owner write is fatal without
qualification. Both narrow, in the same commit as the code, to say that the fatality holds except
where the directory this process created is already gone — a lost race, retaken a bounded number of
times before it too becomes fatal. Nothing else in either file changes, and no other documentation
file mentions the owner write at all ([`research/03`](research/03-contract-surface.md) Part 3).

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | The `mkdir` moves into the loop body; a write that fails with the directory absent increments `robbed` and `continue`s, retaking the lock on the next pass. |
| R2 | The `[[ -d "${lock}" ]]` branch keeps today's `rmdir` + `die`, and the write keeps its redirection order so the shell's diagnostic still carries the errno. |
| R3 | `robbed` is a literal bound of three declared once at `:289`, never reset, never an environment variable; the retake path adds no `sleep` and does not touch `waited`. |
| R4 | `absent`, `waited` and `broke` are not edited, not re-indented, and not re-initialized; the wait-loop body is byte-identical. Gated separately in `P2`. |
| R5 | The retake path prints nothing. No `note`, no new stderr line. Provisioning's own installer output is unchanged and stays on stderr. |
| R6 | `mkdir` remains the discipline; the loop still holds the lock for one download; `uvm_install`, `uvm_point_current` and `uvm_unlock` are untouched. |

## 3. Invariant gate (AGENTS.md constitution check)

Checked against [`invariants.md`](../../.agents/factory/invariants.md) before research and again
against this drafted design.

- **§5 — the lock is `mkdir`.** Unchanged. The discipline, the path and the name are untouched, and
  `git grep flock bin/uv-manager` still matches only the rationale comment.
- **§5 — released on `EXIT`, `INT` and `TERM`, and only while ours.** `uvm_unlock` is not touched.
  `uvm_lock` is still assigned only after a successful write, so a signal in the `mkdir`-to-`owner`
  window still leaves a directory the trap declines to remove — the same behavior as today, discussed
  as a deviation below.
- **§5 — ownership, not path.** The owner line is still built from expansions above the loop, still
  written once, and `uvm_unlock` still matches on its content.
- **§5 — persistence, not a second look.** The retake is bounded by a monotonic literal that never
  resets, which is the discipline this rule prescribes. The `[[ -d ]]` test is a second look and is
  recorded as a deviation below.
- **§5 — the early-out tests the version asked for.** Untouched, and still inside the loop body,
  still reached only when `mkdir` fails.
- **§5 — age from the heartbeat, refresher leash, host token, timeout-under-stale guard, break
  notes, timeout message.** All untouched. The guard still sits inside the function above the loop,
  so `uvm help` and `uvm --version` still answer on a misconfigured node.
- **§7 — stdout belongs to the user's command.** The retake adds nothing to stdout; measured, a
  robbed rank's stdout is exactly `uv 9.9.9 (fixture)`. Both `die`s go to stderr through `die`.
- **§10 — portability floor.** `bash -n` passes under bash 3.2.57. No GNU-ism is introduced; `[[ ]]`,
  `(( ))` and `printf` are already used throughout the function. Behavior is identical on 3.2.57 and
  5.2.37 ([`research/01`](research/01-redirect-failure-semantics.md)).
- **§12 — same-commit rule.** The two invariant files land in the same commit as the code. No other
  user-facing surface is invalidated.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| `[[ -d "${lock}" ]]` decides fatal-vs-retake, which is the "second look" §5 warns against. | The shell cannot see the errno, so the directory is the only evidence available, and R2 requires the two causes be told apart. The rule's failure mode is one-directional here: a false *absent* is essentially unreachable, and a false *present* — the path re-created by a third rank between the write and the test — produces exactly today's death, never a new one. Persistence still governs the retake itself. | Retrying without discriminating breaks R2 both ways. With a `rmdir` before the retry, a genuine EACCES is *cured* by re-creating the directory and the fault ships as a success. Without one, the retry re-enters `mkdir`, fails `EEXIST`, falls into the wait loop and converts a prompt, correctly-named fault into a `UVM_LOCK_TIMEOUT`-long stall reporting `holder: <none recorded>`. |
| The `mkdir`-to-`uvm_lock` window, in which a signal leaks the lock directory, can now open up to three times per call instead of once. | It is the direct cost of having a retake at all. | Setting `uvm_lock` before the write is worse and is already rejected in the current comment: the EXIT trap would read an absent owner file, decline ownership, and leak the lock anyway. The window's mechanism and duration are unchanged; a leaked directory carries no `owner` file and is reclaimed by the stale breaker ([`research/03`](research/03-contract-surface.md) Part 1). |
| §5 and `AGENTS.md` stop asserting the owner write is unconditionally fatal. | This is the cycle's purpose, taken to a human in `GOAL.md` and cleared. Landing the code without the text would make correct code an auto-CRITICAL finding at review. | Leaving the text alone was rejected for exactly that reason. The narrowing is one clause; the rest of the sentence, including *why* the write is fatal, stands. |

## 4. Rabbit holes (resolved)

- Does a failed redirect trip `errexit` inside `if`, and does it differ on bash 3.2? → No, and no.
  Status 1 for ENOENT and EACCES alike, identical on 3.2.57 and 5.2.37, builtin and external
  ([`research/01`](research/01-redirect-failure-semantics.md)).
- Can the `2>/dev/null` ordering trick keep the diagnostic off a successful retake? → Only by
  suppressing it on the fatal path too, which costs R2 its errno. Not adopted
  ([`research/01`](research/01-redirect-failure-semantics.md) Q4).
- Is the seed's `err=$( … 2>&1 )` landmine real? → Yes, fatal under `set -euo pipefail` before any
  `die` runs; `|| true` makes it safe. Neither adopted, R5 not requiring it
  ([`research/01`](research/01-redirect-failure-semantics.md) Q9).
- Do the three graded counters survive an outer retry? → Yes, initialized once at `:289` and never
  reset ([`research/03`](research/03-contract-surface.md) Part 2).
- Can the R1 state be constructed deterministically in the sandbox, and is it red today? → Yes, with
  a `mkdir` shim on `PATH`; rc 1 and empty stdout today, rc 0 and the fixture version against a
  patched probe ([`research/02`](research/02-gate-baselines.md),
  [`research/00`](research/00-digest.md)).
- Which documentation does the same-commit rule pull in? → Two files, both invariant records; no
  user-facing file mentions the owner write ([`research/03`](research/03-contract-surface.md)).

## 5. Risks & open questions

- **The R1 and R3 gates are coupled to `mkdir` being an external command invoked with the lock path
  as its sole argument** (`bin/uv-manager:346`), because that is what the `PATH` shim intercepts. A
  future change to a shell builtin or a different call shape makes the gates stop constructing the
  state they exist to construct, and the failure mode is that they *pass*. `TECH.md` carries this
  note beside both gates, as `GOAL.md` § *Verification limit* requires.
- **The real race is not reproduced, and this cycle does not close it.** Every drive constructs the
  resulting filesystem state single-process. A robbed winner on a real cluster is still robbed; it
  now recovers. `issues/lock-break-instance-identity.md` R2 owns the race and stays blocked on the
  concurrency harness.
- **A successful retake still leaves the shell's raw `No such file or directory` line on stderr**,
  naming an internal script line, ahead of a run that then succeeds. Knowingly accepted: R5 requires
  only that the retake add nothing, and every way of removing it either costs R2 the errno or adds a
  captured-substitution construction the seed measured as a landmine. It is a cosmetic follow-up, not
  a defect in this design.
- **R4b's "exactly one break note" was measured through a narrower sub-path than the criterion
  describes.** The construction denies `rmdir` but not `rm -f` of the owner file, so the second
  iteration finds no owner and a fresh directory mtime rather than re-deciding a break and being
  denied again ([`research/02`](research/02-gate-baselines.md) § E). The gate is still a real
  regression check on the `[[ -n "${broke}" ]] ||` guard, but a reviewer should not read it as
  covering the both-halves-denied case. Constructing that needs `chflags`/`chattr`, which is not
  portable.
- **`mkdir` atomicity on Lustre, GPFS and NFS remains taken on trust.** Unchanged by this cycle;
  R6 pins the discipline rather than revisiting it. Only a real cluster can confirm it.
- **P2's gates are green before the change as well as after.** That is correct for a collateral
  criterion — R4 and R6 ask for *no* change — and it is the one place in this plan where a green gate
  is not evidence of work done. It is evidence that `P1` did not break something, which is precisely
  what the GOAL created R4 for.

## 6. Verification strategy

Three layers, as the methodology prescribes: `bash -n bin/uv-manager`, `.agents/factory/bin/lint.sh`,
and drives under `.agents/factory/bin/temp_root.sh --offline`. Every drive plants its own state
inside a `sh -s` heredoc, using the `UVM_ROOT` and `UVM_SANDBOX` that `temp_root.sh` exports; no gate
duplicates `temp_root.sh`'s environment scrub.

Post-conditions, per R-ID:

- **R1** — a `mkdir` shim that creates the lock directory and removes it once. Assert `uv --version`
  exits 0, stdout is exactly `uv 9.9.9 (fixture)`, and stderr contains neither
  `cannot record ownership` nor any word announcing a retake. Red today at rc 1 with empty stdout.
- **R2** — the same shim, `chmod 500` instead of removing. Assert non-zero exit,
  `Permission denied` on stderr, and `cannot record ownership` still present. Green today, and the
  clause that stops R1 turning a fault into a silent retry.
- **R3** — the shim removes the directory on every call. Assert non-zero exit and that the run
  finishes inside `UVM_LOCK_TIMEOUT` rather than consuming it.
- **R5** — folded into the R1 drive: the exact-stdout assertion is R5's stdout half, and the
  no-announcement grep is its stderr half. The pre-existing shell diagnostic is knowingly excluded
  and is inspection-only for review.
- **R4a** — a foreign-host `owner` line planted before the first `uv` call. Assert rc non-zero, the
  `timed out after 5s` message, and the holder line naming the planted owner. Timing is asserted as a
  window, not a value: `date`-resolution slop puts a 5s timeout at 5-7s measured.
- **R4b** — a foreign lock aged past `UVM_LOCK_STALE` with the parent directory read-only so the
  break is denied. Assert `grep -c` of the break note is exactly 1. Portable ageing via
  `UVM_LOCK_STALE=4` and `sleep 5`, not `touch -t` with BSD `date` arithmetic.
- **R4c** — a shim whose `mkdir` fails without creating. Assert the `cannot create provisioning lock`
  message and that the shim recorded exactly three attempts.
- **R6** — a plain offline drive. Assert stdout is exactly the fixture version, `current` is the
  relative target `versions/9.9.9`, no `.install.lock` survives, and `git grep flock bin/uv-manager`
  still matches only the rationale comment.
- **The invariant text** — a `git grep -i retak` presence check in each of `AGENTS.md` and
  `.agents/factory/invariants.md`. A single word is used deliberately: the sentence it belongs to is
  hard-wrapped differently in the two files, and a phrase-length anchor matches `invariants.md` zero
  times no matter how the sentence is worded
  ([`research/03`](research/03-contract-surface.md) Part 3). The gate proves the narrowing was
  written; whether it says the right thing is inspection-only, and `TECH.md` says so.

Every gate in `TECH.md` was run against the current tree before this plan was committed, and each was
also run against a patched copy of the repository outside the working tree to prove it can reach the
state it asserts. The results are tabulated in [`research/00-digest.md`](research/00-digest.md).

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
