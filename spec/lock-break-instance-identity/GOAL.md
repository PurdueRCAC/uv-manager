# GOAL — A losing breaker deletes the lock a third rank just won

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** lock-break-instance-identity
- **kind:** fix
- **appetite:** big

## Problem

`uvm_acquire_lock` decides a lock is forfeit from an `owner` line it read up to a second earlier
(`bin/uv-manager:407`, `:435`), and then removes a directory at a path (`:459-460`). A directory has
no identity a shell can read, so the decision and the act name different things. The instance judged
may already be gone — broken by another waiter — with a third rank's fresh lock standing at the same
path. The loser deletes a lock it never judged, and two ranks then hold one tree.

What the user sees is not an error. It is two installers writing into one architecture directory at
once, which is mutual exclusion gone: the tree the second one leaves behind is whatever interleaving
produced, and the rank that trusted the lock has no way to know. For a user inside a batch job this
surfaces later and elsewhere — a `current` pointing at a version another rank was still unpacking. For
a site operator it surfaces as a tree that has to be repaired by hand on a filesystem where the
repair is also a race. Measured at 3 of 20 bursts by review cycle 2 of
`lock-ownership-and-hold-time`, and reproduced at burst 2 of 10 against the committed code.

**A partial narrowing shipped in 0.6.0**, as P8 of that cycle. The break re-reads `owner`
immediately before acting and removes the file and the directory only while it still holds the line
the forfeiture was decided on (`bin/uv-manager:457-461`). Gating the `owner` removal is what arms
`rmdir`'s refusal of a non-empty directory as the second half of the same guard, and a declined break
falls through to the timeout accounting at `:469` and re-decides on the next iteration. It is a
strict narrowing. It was shipped on that basis rather than on evidence that it works.

**The residual is wider than the guard's shape suggests.** The identity test at `:458` is *vacuous
when the judged lock carried no `owner` file at all* — an absent line matches an absent line, and the
breaker will still remove a fresh winner's directory inside the interval between that winner's
`mkdir` and its `owner` write, measured at 0.10 ms. Owner-less locks are reachable, and
`invariants.md` §5 keeps the directory-mtime fallback at `:435` precisely for "a lock an older
wrapper wrote, or one caught inside the acquire window." The owner-present case is narrowed and not
closed: the window is the interval between the re-read at `:457` and the removals at `:459-460`, and
passing the identity test is exactly what licenses this process to delete a *new* winner's `owner`
and so clear the way for its own `rmdir`. Review cycle 3 measured a dead-holder plant carrying an
owner at 9 of 29 concurrent installer entries, against 41 of 61 for the owner-less plant. The vacuous
case is roughly 4.5x hotter; it is not the only case.

**The defect is pre-existing and measurably worse before 0.6.0** — a matched A/B on an aged lock gave
the pre-0.6.0 wrapper 119 spurious installs and 65 of 1280 failing ranks, against 87 and 19 for the
shipped code.

**This repository cannot currently measure a lock race well enough to accept or reject a candidate
fix, and that is the first work here rather than a footnote.** The simultaneity sentinel written for
P8 emitted `violations: No such file or directory` on several bursts, because a straggling installer
outlived the sandbox `temp_root.sh` had already removed, so any count it produced is contaminated.
Burst sizes were guesses: 320 ranks gave 5 robbed winners against 2 across the control and the
candidate, a difference indistinguishable from noise, while the arithmetic for sizing a statistical
gate was established one phase earlier and never applied here
([`PLAN.md:392-397`](../lock-ownership-and-hold-time/PLAN.md)). Two signals are conflated: "two ranks
in the installer" may be this defect or the pre-existing early-out at `bin/uv-manager:570`, where
`uvm_acquire_lock … || return 0` returns before `uvm_point_current`, which a prior review logged
separately as real, pre-existing and self-correcting. Until the two have separate assertions a red
gate cannot name what it caught, which is the failure mode
[`lock-ownership-and-hold-time/META.md`](../lock-ownership-and-hold-time/META.md) F18 records. And
the owner-less case has never been constructed at all, so no drive today fails against `main` and
passes against a fix.

**The exclusive rename is the obvious remedy and it is wrong twice over.** It was designed, approved
and then rejected on evidence; four of five design lenses returned `rename-is-unsound` independently.
`mv -T` does not exist at the portability floor, and without it `mv` onto an existing name moves the
source *inside* it and exits 0, so two breakers both believe they won and the second nests a live
tree inside a lock. And `rmdir` refusing a non-empty directory turned out to be load-bearing: it is
what stops a stale breaker destroying an *established* lock, so a rename widens the destructive
window from the acquire gap to the whole hold. The reasoning is in
[`issues/lock-break-instance-identity.md`](../../issues/lock-break-instance-identity.md), and it is
worth reading before proposing anything in that family.

## Outcome / vision

A break removes only the instance it judged, whether or not that instance recorded an owner, and the
claim is backed by a committed drive that can tell a one-in-a-thousand race from noise and name which
defect it caught. The drive is the first inhabitant of `tests/`, so the cycle that builds the suite
inherits a working case instead of writing one. A break that is denied leaves the lock it declined to
take exactly as it found it, including the file that answers whose lock it was.

## Acceptance criteria (the contract)

- **R1** — The repository SHALL carry a committed concurrency drive at `tests/` that constructs a
  lock race and reports a count no straggling rank can corrupt. IF a rank outlives the drive's
  collection window, THEN the drive SHALL fail rather than report a number. The burst size and count
  SHALL be derived from a stated per-rank rate with the resulting false-green probability written
  down, not chosen by taste.
  *Checked by running the drive against `main` and against the branch. It does not exist today, so
  its red state is established by the run against `main` carrying a non-zero count, and by surgically
  removing the guard at `bin/uv-manager:458` to prove the drive reaches the race — the technique
  [`REVIEW.md`](../lock-ownership-and-hold-time/REVIEW.md) R8 used for the `absent` counter. The
  straggler half is checked by making one rank sleep past the collection window and asserting the
  drive exits non-zero with no count on stdout. The sizing arithmetic is graded by the reviewer
  against the numbers written into the drive.*
- **R2** — The drive SHALL assert a robbed lock and two simultaneous installers separately, and its
  two-installer assertion SHALL distinguish an installer entry reachable only through a broken and
  retaken lock from one reachable with the break path never taken.
  *Checked by a control run with no lock planted, where the break path is never entered: the
  robbed-lock assertion SHALL be zero and any residual installer entries SHALL be attributed by the
  drive's own output to the other cause. A red gate that cannot name which defect it caught is what
  this criterion exists to prevent.*
- **R3** — WHEN a waiter's forfeiture decision names a lock instance that no longer exists, the
  wrapper SHALL NOT remove whatever occupies that path, **including** when the judged instance
  recorded no `owner` file.
  *Checked by the R1 drive under both plants — a dead-holder lock carrying an owner, and an
  owner-less lock — each aged past `UVM_LOCK_STALE`. Assert zero concurrent installer entries per
  burst across the sized run, red today at the rates cycle 3 measured (9 of 29 with an owner, 41 of
  61 without).*
- **R4** — IF a break is decided and then denied, THEN the lock SHALL be left carrying the `owner`
  file it had, so the timeout message at `bin/uv-manager:481` still names the holder.
  *Checked by a sandbox drive reproducing the state R7 of the shipped cycle covers — a lock whose
  removal is refused, aged past stale — asserting that `owner` is still present after the break note
  and that the timeout message reports the recorded line rather than `<none recorded>`. Red today:
  `rm -f` at `:459` succeeds, `rmdir` at `:460` is denied, and the message contradicts
  `invariants.md` §5 two lines under a break note that named the holder.*
- **R5** — The behavior of the wait loop's four counters — `absent`, `waited`, `broke` and `robbed` —
  and of the acquire-time retake SHALL be unchanged.
  *Checked by re-running the gates those contracts were graded against: R4 of
  [`lock-acquire-retake`](../lock-acquire-retake/GOAL.md) — a fresh foreign lock timing out at
  exactly `UVM_LOCK_TIMEOUT` with rc 1, a denied break emitting exactly one break note across the
  whole wait, the absent-lock retry still naming a real permissions fault after its bound of three —
  and R1 through R3 of that cycle, whose `mkdir` PATH shim constructs the robbed-winner state in one
  process and must still produce rc 0 with non-empty stdout. This criterion exists because every
  previous remediation to this function shipped collateral rather than failing at its target, and the
  R3 gate cannot see collateral.*
- **R6** — Behavior under the existing single-download hold SHALL be unchanged, and the discipline
  SHALL remain `mkdir`.
  *Checked by `.agents/factory/bin/temp_root.sh --offline uv --version` still reporting the fixture
  version on stdout and leaving `current -> versions/<fixture>` with no lock left behind — green
  today at `uv 9.9.9 (fixture)`, rc 0, `versions/9.9.9` — plus
  `git grep -n flock bin/uv-manager` matching nothing outside the rationale comment at `:172`, which
  is its single match today.*

## Non-goals (no-gos)

- **No exclusive rename, and no compose-and-restore variant.** Rejected on evidence, twice over; the
  Problem section above and the seed carry the reasoning. Verification after a rename is too late,
  because the rename is itself the destructive act, and a restore can nest the doomed tree inside a
  lock retaken in the meantime — turning a transient race into a permanent outage only a human
  clears. A plan re-proposing this owes the seed a rebuttal, not a design.
- **No test runner, no corpus, no coverage measurement.**
  [`issues/test-harness.md`](../../issues/test-harness.md) owns all three. This cycle lands `tests/`
  and one case in it, deliberately at the location that seed's § *Notes* already chose, so the suite
  inherits a working drive rather than relocating one. That seed's R3d is where the obligation for
  the rest of the lock contract stays; this cycle discharges its concurrency half and no more.
- **The heartbeat's silently degrading leash is not fixed here.** `uvm_proc_start` compares a start
  time only when both readings are non-empty (`bin/uv-manager:218`), so on a platform whose `ps`
  cannot answer `-o lstart=` the refresher's leash falls back to bare `kill -0` and the immortal-lock
  defect returns — which `invariants.md` §5 does not concede. It is a different function, and telling
  an operator about it means choosing a new output surface. The obligation is landed as **R4** of
  [`issues/invariant-audit-gaps.md`](../../issues/invariant-audit-gaps.md) in this same commit.
- **The lock's unmeasured performance claims are not settled here.** The ~5 ms hot-path budget, the
  `ps` fork per heartbeat beat, and the one `sleep` orphaned per acquisition. A timing A/B is a
  different instrument from a race detector, and the cgroup `pids.max` interaction that makes the
  orphan matter is not reachable from a laptop at all. The obligation is landed as **R7** of
  [`issues/test-harness.md`](../../issues/test-harness.md) in this same commit, which is where the
  instrument will exist.
- **The early-out at `bin/uv-manager:570` is measured, not changed.** R2 attributes the two-installer
  signal; it does not oblige a repair. If any part of the signal lands there, this cycle writes the
  finding as a new `issues/{slug}.md` and a `ROADMAP.md` entry before it publishes, rather than
  naming a file that does not exist.
- **No new environment variable and no new subcommand.** Any bound this fix needs is a constant in
  the script, for the reason `invariants.md` §5 already gives for the `absent` and `robbed` bounds.
- **No change to the lock's location, its name, or the fatality of the `owner` write.**

## Clarifications

- **Q:** The seed's R1 describes a concurrency harness and
  [`issues/test-harness.md`](../../issues/test-harness.md) owns the runner, sequenced last. Does the
  harness fold into that seed, ship as its own cycle, or ship here? — **A:** Here, scoped to a
  lock-race drive only — a sentinel that outlives the sandbox, a sized burst, and separate assertions
  — and no further. Promoting `test-harness` first would take a `big` feature cycle for a runner, a
  corpus and coverage ahead of a live defect; splitting the drive into its own cycle would leave that
  defect on `main` for an extra lifecycle. The fix is unacceptable without the measurement and the
  drive is worthless without a defect to grade, so they are one cycle (resolved 2026-09-08).
- **Q:** Where does the drive live — `tests/` or `.agents/factory/bin/` beside `temp_root.sh`?
  — **A:** `tests/`. [`issues/test-harness.md`](../../issues/test-harness.md) § *Notes* already
  settled that the suite is product, and moving a gate later is how a gate silently stops
  constructing the state it exists to construct (resolved 2026-09-08).
- **Q:** Which of the seed's remaining criteria does this contract carry? — **A:** Its R4
  (attribution) as **R2** here, because R1's separate-assertions requirement is unsatisfiable
  without it; and its R6 (the denied break stripping `owner`) as **R4** here, because it is the same
  eight lines R3 restructures and a second cycle for it means a second human sign-off gate on one
  edit. Its R5 and its performance debt are deferred to the seeds named in *Non-goals*
  (resolved 2026-09-08).
- **Q:** Does this contract keep the seed's R-ID numbering, which leaves R3 vacant? — **A:** No. The
  vacancy exists because `REVIEW.md`, the `ROADMAP.md` entry and the 0.6.0 human-gate clearance all
  cite "the seed's R3", and renumbering would falsify them. Those citations are to the *seed*, which
  stays as it is; this GOAL is a new contract with fresh IDs, and nothing cites it yet. The mapping
  is in the answer above (resolved 2026-09-08).
- **Q:** Is the shape of the fix settled? — **A:** No, and deliberately not. The rename family is
  ruled out and the bound must be a constant, which is the whole of what this contract constrains
  about mechanism. R3 is phrased on what a rank observes, because the remedy is a research problem
  and a criterion pinned to a guessed mechanism has to be reinterpreted mid-lifecycle
  (resolved 2026-09-08).
- **Q:** `lock-acquire-retake` § *Non-goals* says a cycle that closed this race would make its R1
  unreachable, and that the two must not be merged. Does R3 break it? — **A:** No. That cycle
  shipped, and its R1 gate constructs the robbed-winner state with a `mkdir` PATH shim in one
  process rather than through a real race, so closing the race leaves the gate reachable. R5 here
  requires it to still pass, which is the assertion that this answer is correct (resolved
  2026-09-08).

## Related materials

- Seed: [`issues/lock-break-instance-identity.md`](../../issues/lock-break-instance-identity.md) —
  carries the rename analysis, the cycle-2 and cycle-3 measurements, and the account of R3 leaving for
  `lock-acquire-retake`. Its `ROADMAP.md` entry is sequenced **first** in *Queued*.
- Origin: [`spec/lock-ownership-and-hold-time/`](../lock-ownership-and-hold-time/TECH.md) — P8's
  "Attempt 1" section, `REVIEW.md` cycles 1 and 2 where both reviewers found this, and
  `PLAN.md:392-397` for the burst-sizing arithmetic R1 must apply.
- Sibling: [`spec/lock-acquire-retake/`](../lock-acquire-retake/GOAL.md) — the robbed winner's *death*
  was split out of this seed and shipped; R5 above pins its contract.
- Downstream: [`issues/lock-owner-write-errno.md`](../../issues/lock-owner-write-errno.md) — its
  residue rides on the robbery R3 closes, so landing this changes the case for promoting it. A line
  saying so is landed in that seed in this same commit.
- `bin/uv-manager` § *provisioning lock*: the forfeiture decision at `:407` and `:435`, the guard at
  `:457-461`, the denied-break fall-through at `:469`, the timeout message at `:481`, and the
  early-out at `:570`.
- `AGENTS.md` names `uvm_acquire_lock` and `uvm_unlock` a high-blast-radius region: a confirmed
  finding here forces a human sign-off gate at review.

## Verification limits, declared up front

- **`mkdir` atomicity on Lustre, GPFS and NFS is taken on trust.** Everything the lock claims rests
  on it, and a `mktemp -d` on APFS cannot exercise it. Unchanged by this cycle; R6 pins the
  discipline rather than revisiting it.
- **NFS attribute caching is untested against the re-read at `:457`.** A client may serve a stale
  `owner` line, which makes the identity test pass when it should fail. It is the one filesystem
  where the shipped guard could be worse than useless, and whatever R3 lands inherits the same
  exposure unless the plan finds a construction that does not depend on re-reading. No drive here
  reaches it; a reviewer grades the reasoning, and a real cluster would be required to settle it.
- **R1's drive measures a local filesystem.** APFS on the development machine and whatever a CI
  runner provides. A rate measured there is evidence that a fix works, not evidence that it works on
  a parallel filesystem.
- **R2's attribution is measured in the sandbox.** A cause absent there may still be present under a
  real allocation, so a clean attribution bounds what the drive can see rather than what a cluster
  can produce.
