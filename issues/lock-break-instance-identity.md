---
status: unshaped
kind: fix
appetite: big
lane: public
---

# The break still deletes locks it did not judge, and nothing here can measure it yet

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

`uvm_acquire_lock` decides a lock is forfeit from an `owner` line it read up to a second earlier, and
then removes the directory at that path. A directory has no identity a shell can read, so the
decision and the act name different things: the instance judged may already be gone, broken by
another waiter, with a third waiter's fresh lock standing at the same path. The loser then deletes a
lock it never judged.

Two symptoms, both reproduced against the real wrapper under `temp_root.sh --offline` with a
pre-planted dead-holder lock and bursts of 32 to 64 concurrent ranks:

- **A robbed winner dies having done nothing wrong.** Its `mkdir` succeeded, a rival's `rmdir`
  removed the directory underneath it, and its `owner` write then opens `ENOENT`:
  `cannot record ownership of the provisioning lock`, preceded by the shell's own
  `No such file or directory`. Measured at 4 of 1280 ranks by review cycle 2, and 5 of 320 here.
- **Two ranks enter the installer at once**, which is mutual exclusion gone. Measured in 3 of 20
  bursts by review cycle 2, and reproduced here at burst 2 of 10 against the committed code.

**A partial narrowing already shipped** in `lock-ownership-and-hold-time` P8. The break now re-reads
`owner` immediately before acting and removes the file *and* the directory only while it still holds
the line the forfeiture was decided on (`bin/uv-manager:412-424`). Gating the `owner` removal is what
arms `rmdir`'s refusal of a non-empty directory as the second half of the same guard. It is a strict
narrowing — a declined break falls through to the timeout accounting and the next iteration
re-decides — but it is **not a closure**, and it was shipped on that basis rather than on evidence
that it works.

**The residual is known, and it is wider than the guard's shape suggests.** The identity test is
*vacuous when the judged lock carried no `owner` file at all*: an absent line matches an absent line,
and a breaker that judged an owner-less lock will still remove a fresh winner's directory inside the
0.10 ms window between its `mkdir` and its `owner` write. Owner-less locks are reachable —
`invariants.md` §5 keeps the directory-mtime fallback precisely for "a lock an older wrapper wrote,
or one caught inside the acquire window."

**The owner-present case is narrowed, not closed** — which an earlier draft of this section implied
it was, and which would have let a future cycle close the vacuous case and call the defect done. The
window is the interval between the re-read at `bin/uv-manager:423` and the `rm -f`/`rmdir` at
`:425-426`, and passing the identity test is exactly what licenses this process to delete a *new*
winner's `owner` and so clear the way for its own `rmdir`. Review cycle 3 measured a dead-holder
plant *carrying* an owner at 9 of 29 concurrent installer entries and 4 robbed winners of 1280 ranks,
against 41 of 61 for the owner-less plant. The vacuous case is roughly 4.5x hotter; it is not the
only case, and R2 below is gated on both.

**A rename does not fix this, and the reasons are worth keeping.** An exclusive `rename(2)` was
designed, approved, and then rejected on evidence:

- `mv` is not `rename(2)`. A shell can only call `mv`, `mv -T` does not exist at the portability
  floor — `uvm_point_current` already carries a documented non-atomic fallback for that reason, and
  it does not generalize here — and without `-T`, `mv` onto an existing name moves the source
  *inside* it and exits 0. Two breakers can then both believe they won, the second nesting a live
  tree inside a lock. `mv` is also documented to fall back to copy-and-delete for a directory, which
  is neither atomic nor exclusive.
- `rmdir` refusing a non-empty directory was load-bearing and unremarked. It is what stops a stale
  breaker destroying an *established* lock today, and what makes R7 of the shipped cycle true for
  the stray-entry construction. A rename removes a directory whatever it contains, so it widens the
  destructive window from the acquire gap to the whole hold, and defeats **both** of that cycle's
  denied-break constructions — the stray entry, and `chmod 500`, since a same-parent rename needs no
  write permission on the directory itself.
- It leaves litter no trap covers. A breaker holds no lock, so `uvm_unlock` early-returns and
  `EXIT`/`INT`/`TERM` do nothing; a breaker killed between the rename and the delete leaves a
  permanent sibling in the architecture directory that nothing sweeps.

Compose-and-restore variants are worse: verification after the rename is too late, because the
rename is itself the destructive act, and the restore can nest the doomed tree inside a lock that
was re-taken in the meantime — turning a transient race into a permanent, human-repair-only outage.

## The measurement debt, which blocks the fix

The reason P8 shipped unproven is that **this repository cannot currently measure a lock race well
enough to accept or reject a candidate fix.** That debt is the first work here, not a footnote:

- **The concurrency harness is unfaithful.** The simultaneity sentinel written for P8 emitted
  `violations: No such file or directory` on several bursts, because a straggling installer outlived
  the sandbox that `temp_root.sh` had already removed. Any count it produced is contaminated.
- **Burst sizes are guesses.** P8 ran 320 ranks and got 5 versus 2 robbed winners across the control
  and the candidate — a difference indistinguishable from noise. Phase P7 of the shipped cycle
  established the arithmetic for sizing a statistical gate (`1 - (1-p)^n` per burst, compounded);
  nothing applied it here.
- **Two signals are conflated.** "Two ranks in the installer" may be this defect or the pre-existing
  early-out at `bin/uv-manager:547`, where `uvm_acquire_lock … || return 0` returns before
  `uvm_point_current`. A prior review logged that separately as real, pre-existing and
  self-correcting. Until the two have separate assertions, a red gate cannot name what it caught,
  which is the failure mode `spec/lock-ownership-and-hold-time/META.md` F18 already records.
- **No red state is established for the residual.** The owner-less-lock case above has never been
  constructed, so there is no drive that would fail against today's code and pass against a fix.

### What review cycle 3 discharged, and what it did not

The debt above is real for **R2**, whose question is a rate — how often a losing breaker's `rmdir`
lands inside the acquire window — and a rate needs the harness, the sizing arithmetic, and a sentinel
that outlives the sandbox. It does **not** reach **R3**.

R3's question is a property of one code path given one filesystem state: `mkdir` returned 0 and
`${lock}` is absent at the owner write. The wrapper cannot tell a constructed instance of that state
from a raced one, because its only evidence is `$?` from `mkdir` and the result of the redirect. The
state is therefore directly buildable, in one process, with no burst, and a candidate is accepted or
rejected by pass/fail rather than by a rate against noise. Driven red against `b3f7491` and green
against a scratch patch, in about two seconds per drive:

```sh
shim=$(mktemp -d)
cat > "$shim/mkdir" <<'EOF'
#!/bin/sh
if [ $# -eq 1 ]; then case "$1" in *.install.lock)
  /bin/mkdir "$1" || exit $?
  [ -e "${UVM_SANDBOX}/fired" ] || { : > "${UVM_SANDBOX}/fired"; /bin/rmdir "$1"; }
  exit 0 ;; esac; fi
exec /bin/mkdir "$@"
EOF
chmod +x "$shim/mkdir"
# Drive `uv --version` with "$shim" first on PATH inside temp_root.sh --offline,
# asserting rc 0 and non-empty stdout. Red today: rc 1, stdout empty.
```

It is coupled to `mkdir` remaining an external command taking the lock path as its sole argument
(`bin/uv-manager:345`), which belongs in a comment wherever the gate lands. Its companion `chmod 500`s
the lock directory instead of removing it and asserts the write stays **fatal** with its errno intact
— which is what stops a fix for R3 turning a genuine filesystem fault into a silent retry.

**A landmine, measured.** The obvious way to keep the shell's own diagnostic off stderr on a
successful retake — `err=$( { printf '%s\n' "${owner}" > "${lock}/owner"; } 2>&1 )` — is unsafe under
this script's `set -euo pipefail` (`bin/uv-manager:19`). A failing command substitution aborts the
shell before any `die` runs, so the fatal path loses `cannot record ownership` altogether and exits a
bare 1, which is worse than today. Either guard it explicitly with `|| { … }`, or leave the stray
line: on a successful retake stdout is clean, and the cold-provisioning path already writes installer
output to stderr.

**The collateral risk is the real one here, and no gate above covers it.** Every remediation to
`uvm_acquire_lock` on the shipped cycle produced collateral rather than a failure of its target — the
heartbeat produced an immortal-lock CRITICAL, its leash shipped an unverifiable `ps -o lstart=`
dependency, and P8 shipped with its own author misdescribing it. R3's remedy wraps an outer retry
around a loop body carrying three counters (`absent`, `waited`, `broke`) that reviewers graded
separately for exact behavior. Whoever takes R3 owes gates that pin all three unchanged: rc 1 at
exactly `UVM_LOCK_TIMEOUT` against a fresh foreign lock, exactly one break note across a denied
break, and `absent`'s bound of three intact.

## Performance claims that are asserted rather than measured

Standing debt from the same cycle, cheap to fold in once a harness exists:

- The wrapper's ~5 ms hot-path budget is below what a timing drive resolves on a shared machine.
  `GOAL.md` R4 of the shipped cycle says so and delegates the judgement to a reviewer reading the
  implementation. A location-controlled A/B measured ~0.6 ms of drift between `main` and the branch,
  of which ~0.2 ms is parse cost from the file growing 37,184 → 49,376 bytes, mostly comments. That
  is a real number nobody can currently act on.
- `uvm_proc_start` adds one `ps` fork per heartbeat beat. It is on the provisioning path only and the
  beat is `UVM_LOCK_STALE/10`, so the cost is believed negligible and has not been measured under a
  many-rank cold start.
- Each acquisition orphans one `sleep` for up to one beat, because `uvm_unlock` kills the refresher
  subshell and not the `sleep` it is blocked in. Recorded twice as bounded and self-reaping
  (`REVIEW.md` cycle 1 F5, re-observed in cycle 2). It matters only against a Slurm cgroup
  `pids.max`, which nothing here can exercise.

## Safety properties currently taken on trust

- **`mkdir` atomicity on Lustre, GPFS and NFS.** Declared up front as a verification limit; a
  `mktemp -d` on APFS cannot exercise it. Everything the lock claims rests on it.
- **NFS attribute caching** against the re-read the new guard performs: a client may serve a stale
  `owner` line, which would make the identity test pass when it should fail. Untested, and it is the
  one filesystem where the guard could be worse than useless.
- **The heartbeat's leash degrades silently.** `uvm_proc_start` compares a start time only when both
  the recorded and the live reading are non-empty, so on any system whose `ps` cannot answer
  `-o lstart=` the leash falls back to a bare `kill -0` and the immortal-lock defect returns. No
  drive establishes which platforms answer.
- **A denied break leaves an ownerless lock.** The removal of `owner` and the `rmdir` are now inside
  one guard, but a `rmdir` denied after a successful `rm -f` still strips the file. The timeout
  message then reports `<none recorded>` two lines below a break note that named the holder,
  contradicting `invariants.md` §5's requirement that the message name the holder the `owner` file
  records. Reachable in exactly the state R7 is about.

## Why it was deferred

**Pre-existing on `main`, and measurably worse there** — a matched A/B on an aged lock gave `main`
119 spurious installs and 65 of 1280 failing ranks against the branch's 87 and 19. Review cycle 2
graded it CONFIRMED and blocking on the reasoning that "the repair is small and disturbs no
criterion". The first half of that turned out to be false: the obvious repair is a regression, and
the correct one is a research problem gated behind measurement infrastructure that does not exist.
Deferring was the maintainer's decision on 2026-08-16, taken with the human sign-off gate on
`uvm_acquire_lock` still standing and unresolved.

Taking it inside the cycle that found it would also have meant a third review round against a
two-or-three-cycle bound, in the highest-blast-radius function in the repository, on evidence that
could not distinguish a fix from noise.

### R3 splits off and is taken first (2026-08-26)

Review cycle 3 isolated the robbed winner's death from the race that causes it and established that
the death is **authored by the shipped cycle**, not inherited: `main`'s owner write is
`> "${lock}/owner" 2>/dev/null || true` and its robbed winners continue, where the branch's is a
`die`. Matched A/B on the identical construction put `main` at zero robbed winners against the
branch's 4 of 1280 and 3 of 1280. So R3 fails the review rubric's deferral exception on its first
condition, and its deferral is a **maintainer override recorded as such**, cleared 2026-08-26 with
grounds in `spec/lock-ownership-and-hold-time/REVIEW.md` § *Human-gate triggers*.

The override was taken on the strength of two things, not on the defect being acceptable: R3's
remedy is a restructure of the acquire loop rather than the local edit cycle 2 supposed, and this
function's failure history is collateral rather than missed targets — so it wants a real review
behind it more than it wants to be rushed into an exhausted loop. **R3 is therefore promoted to its
own `small` cycle, taken immediately, ahead of R1 and R2 rather than behind them.** It does not need
the harness: see § *What review cycle 3 discharged*, which carries its gate.

R1 and R2 stay here, in this order, and still block on measurement.

## Outcome / vision

A break removes only the instance it judged, and that claim is backed by a harness that can tell a
one-in-a-thousand race from noise and name which defect it caught. The performance claims the lock
makes carry numbers instead of arguments, and the properties that cannot be measured on a laptop are
listed explicitly rather than assumed.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — The repository SHALL carry a concurrency harness that constructs a lock race
  deterministically enough to separate a candidate fix from noise: a simultaneity detector that
  cannot write into a removed sandbox, a burst size derived from the per-rank failure rate rather
  than guessed, and separate assertions for a robbed winner and for two simultaneous installers.
- **R2** — WHEN a waiter's forfeiture decision names an instance that no longer exists, the wrapper
  SHALL NOT remove whatever occupies that path, **including** when the judged lock carried no `owner`
  file.
- **R3** — WHEN a waiter's own `owner` write fails because the directory it created has been removed,
  the wrapper SHALL retake the lock rather than die, bounded by a constant in the style of the
  existing absent-lock retry, and SHALL still report a genuine filesystem fault with its errno.
- **R4** — The two-installer signal SHALL be attributed: either to this defect, or to the early-out
  at `bin/uv-manager:547`, with a drive that distinguishes them.
- **R5** — IF `ps -o lstart=` cannot answer on the running platform, THEN the wrapper SHALL say so
  somewhere an operator will see it, rather than silently reverting to a leash that cannot survive
  pid reuse.
- **R6** — A denied break SHALL NOT leave a lock whose `owner` file it has already removed.
- **R7** — Behavior under the existing single-download hold SHALL be unchanged, and the discipline
  SHALL remain `mkdir`.

## Notes

- Related: [`issues/test-harness.md`](test-harness.md) owns the runner this seed's R1 would live in —
  whoever promotes should decide whether R1 folds into it or ships first as a standalone drive;
  [`issues/purge-tree-repair.md`](purge-tree-repair.md) is the cycle that makes long holds real and
  therefore makes this defect matter more.
- The retained account of what shipped and why is
  [`spec/lock-ownership-and-hold-time/`](../spec/lock-ownership-and-hold-time/TECH.md) — P8's
  "Attempt 1" section, and `REVIEW.md` cycles 1 and 2.
- Found by: `uvm-review` cycle 2 of `lock-ownership-and-hold-time` (debate variant, both reviewers),
  narrowed and partially remediated in P8 of that cycle. The rename analysis came from a five-lens
  design fan-out during P8; four lenses returned `rename-is-unsound` independently.
- **Do not re-propose the rename** without reading the Problem section above. It is the obvious
  design and it is wrong for two reasons that are invisible until you look for them.
