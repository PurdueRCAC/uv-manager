# Research digest — lock-acquire-retake

Consolidated decisions from the three briefs, plus the measurements taken while drafting the design.
Where a brief and a later measurement disagree, the measurement wins and the disagreement is named.

## Decisions

1. **The restructure is structurally required, not stylistic.** A `continue` written after the
   existing `while ! mkdir "${lock}"; do … done` is lexically outside any loop: bash reports
   `continue: only meaningful in a 'for'/'while'/'until' loop`, falls through, and does not retry.
   `set -e` does not catch it. The owner write therefore has to move inside a loop for a retake to
   exist at all ([`01`](01-redirect-failure-semantics.md) Q8).

2. **A failed redirect is safe to branch on.** `if printf … > "${lock}/owner"; then` never trips
   `errexit`, on bash 3.2.57 and 5.2.37 alike. Status is 1 for both ENOENT and EACCES, for the
   builtin and for `/usr/bin/printf`. `set -u` and `pipefail` change nothing
   ([`01`](01-redirect-failure-semantics.md) Q1, Q5, Q6).

3. **Errno text is the discriminator the user sees, and it must stay unsuppressed.** Redirections
   apply strictly left to right, and a failure aborts the rest of that command's redirection list, so
   `> BAD 2>/dev/null` does *not* suppress the shell's diagnostic while `2>/dev/null > BAD` does. The
   write keeps its current order. `uvm_unlock`'s existing comment on this is correct
   ([`01`](01-redirect-failure-semantics.md) Q3, Q4).

4. **The stderr cleanup stays out of scope, and the seed's landmine is real.**
   `err=$( { printf … > "${lock}/owner"; } 2>&1 )` is fatal under `set -euo pipefail`, aborting
   before any `die`. `|| true` makes it safe and still captures the text. Neither is adopted: R5 asks
   only that a successful retake *add* nothing ([`01`](01-redirect-failure-semantics.md) Q9, and
   `GOAL.md` § *Non-goals*).

5. **The counters survive an outer retry unchanged.** `waited`, `absent` and `broke` are initialized
   once at `bin/uv-manager:289` and never reset inside the function. A new counter must be declared
   on that same line and never re-`local`'d inside the loop, which would silently reset it every pass
   and defeat R3 ([`03`](03-contract-surface.md) Part 2).

6. **`uvm_acquire_lock` has one caller and two return values.** `bin/uv-manager:548` inside
   `uvm_install`; `return 1` is the version-satisfied early-out and means no lock was ever held,
   `return 0` means the lock is held and the three globals are populated
   ([`03`](03-contract-surface.md) Part 1).

7. **The same-commit surface is two files, not five.** Only `AGENTS.md:154` and
   `.agents/factory/invariants.md:81` assert the owner write's fatality. `uvm_help`, `README.md`,
   `etc/uv-manager.conf.example` and `share/modulefiles/uv/main.lua` say nothing about it and need no
   edit ([`03`](03-contract-surface.md) Part 3).

8. **A prose anchor across those two files cannot be shared.** `AGENTS.md:154` carries
   `The owner write is fatal` on one line; `invariants.md` hard-wraps the same sentence between lines
   80 and 81, so that anchor matches there zero times. A gate must use a token no line wrap can
   split ([`03`](03-contract-surface.md) Part 3).

9. **Every gate the GOAL names is constructible, and the pre-change split is the one the GOAL
   predicted.** R1 and R3 are red today; R2, R4a, R4b, R4c and R6 are green today and must stay green
   ([`02`](02-gate-baselines.md)).

## Corrections to the briefs

- [`02`](02-gate-baselines.md) states that drives D and E (R4a, R4b) "cannot be driven through
  `temp_root.sh` directly", and hand-replicated its environment scrub to plant a lock before the
  first `uv` call. **This is wrong.** The drive script is itself the hook: `temp_root.sh` exports
  `UVM_ROOT` into the command it runs, so `mkdir -p "$UVM_ROOT/$(uname -m)/.install.lock"` inside a
  `sh -s` heredoc plants the lock with no duplicated logic. Measured: the R4a drive built that way
  reproduces the timeout message in 5.2s. Every gate in `TECH.md` uses this form, and no gate copies
  `temp_root.sh`'s scrub.

- [`02`](02-gate-baselines.md) backdates the owner file with `touch -t "$(date -v-120S …)"`, which is
  BSD-only and would not run on a cluster image. The committed R4b gate instead sets
  `UVM_LOCK_STALE=4` and sleeps 5, which needs no date arithmetic and is portable.

- [`02`](02-gate-baselines.md) records that drive C cannot distinguish "robbed once" from "robbed
  every time" against the current tree. Correct, and it is a property of the current code rather than
  of the drive: there is no retry to repeat. Against the patched probe the two diverge as intended —
  C dies after exactly three attempts in 0.25s.

## Measured against a patched probe

The design below was applied to a copy of the repository outside the working tree and every gate was
run against it. This is the evidence that each gate can reach the state it asserts, rather than being
red for its own reasons.

| Gate | Current tree | Patched probe |
|------|--------------|---------------|
| R1 — robbed once, retake | rc 1, stdout empty | rc 0, stdout `uv 9.9.9 (fixture)` |
| R2 — EACCES stays fatal | rc 1, `Permission denied` | rc 1, `Permission denied` |
| R3 — robbed every time | rc 1 (no retry exists) | rc 1 after exactly 3 attempts, 0.25s |
| R4a — foreign lock timeout | rc 1 at ~5s | rc 1 at 5.2s, holder named |
| R4b — one break note | exactly 1 | exactly 1 |
| R4c — absent bound | exactly 3 `mkdir` attempts | exactly 3 `mkdir` attempts |
| R6 — ordinary hold | `current -> versions/9.9.9`, no lock | `current -> versions/9.9.9`, no lock |

No collateral appeared in the probe. That is the claim `P2` exists to re-establish against the real
diff rather than against this one.

## Assumptions that stay unverified

- `mkdir` atomicity on Lustre, GPFS and NFS. Unchanged by this cycle and taken on trust, as declared
  by `lock-ownership-and-hold-time`. R6 pins the discipline rather than revisiting it.
- The real race that robs a winner is not reproduced here; every drive constructs the resulting
  filesystem state directly, single-process. That is what makes the gate deterministic, and it is
  also why this cycle cannot show the race is gone — it is not meant to.
  See `issues/lock-break-instance-identity.md` R2.
