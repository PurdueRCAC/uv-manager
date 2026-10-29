# GOAL — Stop breaking the lock, and split provisioning from repair

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** lock-simplification
- **kind:** fix
- **appetite:** big

## Problem

The provisioning lock has been the subject of three consecutive cycles, and each one closed a race by
adding state whose own abandonment became the next cycle's defect. `lock-ownership-and-hold-time`
added an `owner` file, a heartbeat and an ownership-qualified release; `lock-acquire-retake` gave a
robbed winner a bounded retake; `lock-break-instance-identity` added a persistence count and a `mark`
entry, and its review confirmed three CRITICALs, two of them failure classes the remedy introduced.
That branch was reverted and only its measurement instrument, `tests/lock-race.sh`, was kept.

Every one of those lines exists to answer *the holder might be dead — may I take its lock?* That is
failure detection, which no asynchronous system settles, and a network filesystem makes it worse:
attribute caches serve a stale `owner` line, clocks skew between nodes, `kill -0` answers for a pid
number rather than a process, and MDS failover can replay a metadata operation. On 2026-09-09 the
maintainer decided the wrapper stops asking. The decision, its reasoning and the list of rejected
designs are in [`issues/lock-simplification.md`](../../issues/lock-simplification.md) and are not
reopened here.

Who it hurts is a user inside a batch job. A job that starts N ranks of a wrapped `uv` or `uvx` on a
cold or damaged tree needs one rank to do the work and the rest to wait for it or do something safe —
and when something unexpected happens, a clear failure that a human clears with `uvm doctor` and
`uvm clean`, rather than a lock wedged across every node or a silent wrong answer. Today it gets
neither guarantee:

- **A crashed holder's lock is broken by inference**, and every defect across the three cycles traces
  to the inference.
- **A waiter past `UVM_LOCK_TIMEOUT` dies**, rc 1 with empty stdout, even for provisioning, where
  doing the work itself would have been safe — *if* publishing were safe.
- **Publishing is not safe.** `uvm_install` checks `[[ -d "${dest}" ]]` and then runs an unguarded
  `mv "${tmp}" "${dest}"` (`bin/uv-manager:614-619`). When a rival publishes between the two, `mv`
  moves the staging directory *inside* the published one and exits 0. A failed rename instead dies
  under `set -e` with a bare `mv:` line and leaves `versions/.incoming.*` that nothing collects.
- **A pinned rank can run the wrong version at rc 0.** The lock's early-out at `:570`
  (`uvm_acquire_lock … || return 0`) returns success without the `uvm_point_current` that the fast
  path (`:566`) and the re-check under the lock (`:574`) both perform. A pinned waiter that samples
  the tree between the publish at `:618` and the swap at `:620` returns with `current` wherever it was.
  Measured in `issues/pin-early-out-selects-nothing.md` and reproduced for this GOAL (R12): on a warm
  tree, 15 of 16 ranks pinned to 6.6.6 executed 9.9.9 at rc 0 with nothing on stderr; on a cold tree,
  15 of 16 failed rc 1. This contradicts `invariants.md` §4, "a pin is authoritative". **Pre-existing
  on `main`**, and it lives in the provisioning early-out this cycle rewrites to take a caller-named
  predicate (R6), which is why it is folded in rather than left for a later diff to the same lines.

A repair caller is coming (`issues/purge-tree-repair.md`, the next cycle). It wants the opposite of
provisioning: concurrent repair is destructive, so a repair waiter past its timeout must fail rather
than proceed. That is affordable only on a lock nobody takes by force.

**Drift against `main` (cf77b37), found re-confirming the seed.** The seed's line references and
sizes come from the reverted `lock-break-instance-identity` branch, not from `main`. On `main` the
lock is `bin/uv-manager:169-503` (335 of 1224 lines, 27%, not 512 and 37%), `uvm_acquire_lock` is
`:286-502` (217 lines, not 301), and the unguarded rename is `:618`, not `:794` (on `main`, `:794` is
the `uvm_global_takes_value` banner). `uvm_lock_removable` and `uvm_lock_still_forfeit` do not exist
on `main`; there the break decision and its re-read guard are inline in `uvm_acquire_lock`
(`:417-470`). The decision's case does not depend on those figures. `uvm doctor` and `uvm clean`
currently have no awareness of the lock at all, so R8 is new behavior rather than a change to an
existing one.

## Outcome / vision

A site operator reads the provisioning lock in one sitting. A rank that waits too long says so once,
naming the holder, and then does something safe rather than adjudicating: a provisioning rank installs
for itself and publishes without harm to anyone who got there first; a repair rank refuses. A crashed
holder costs a redundant download and a line in `uvm doctor`, not a wedged tree and a human walking
the nodes. Every call that returns success has selected the version it was asked for.

## Acceptance criteria (the contract)

R1–R9 keep the seed's numbering, so the cross-references already written in `ROADMAP.md` and the
sibling seeds stay true. R10–R15 are appended. Every sandbox drive below runs under
`.agents/factory/bin/temp_root.sh --offline`, where the fixture installs `uv 9.9.9 (fixture)`, and
"plant a lock" means creating `${UVM_ROOT}/<arch>/.install.lock` and an `owner` line by hand before
the call. Every **Observed on main** status was recorded on 2026-10-27 at `cf77b37`.

- **R1** — The wrapper SHALL NOT remove, overwrite or take a lock directory it did not create,
  however old the lock is and whatever its `owner` file records or omits.
  *Checked by a sandbox drive: plant a lock whose `owner` names this host and a reaped pid, both
  entries timestamped 2020, then run `UVM_LOCK_TIMEOUT=3 uv --version`; assert the plant still stands
  with its `owner` line byte-identical and that no stderr line announces a break. Repeat with no
  `owner` file. Across nodes the property rests on `mkdir` atomicity, taken on trust from the Slurm
  drive in R4. **Observed on main: red** — rc 0 after
  `breaking provisioning lock abandoned by a dead process`, plant removed.*
- **R2** — WHILE a waiter has waited longer than a notice threshold, it SHALL print exactly one notice
  on stderr naming the holder its `owner` file records and how to clear the lock, and SHALL NOT repeat
  it for the remainder of that wait.
  *Checked by a sandbox drive: plant a lock whose `owner` names a live process on this host, move the
  plant aside only after the plan's notice threshold has passed, under a `UVM_LOCK_TIMEOUT` well above
  it; assert rc 0, the fixture version on stdout, and exactly one stderr line carrying the planted
  `owner` line. The threshold's value is the plan's, and the drive's release time follows it.
  **Observed on main: red** — released at 8 s under `UVM_LOCK_TIMEOUT=30`: rc 0 and no line naming
  the holder. `main` is silent for the whole wait and speaks only at the timeout, as a fatal.*
- **R3** — WHEN a provisioning waiter reaches `UVM_LOCK_TIMEOUT` with the lock still held, it SHALL
  proceed with the install itself rather than fail or wait further, and the call SHALL exit 0 with the
  requested version on stdout.
  *Checked by a sandbox drive: plant a lock whose `owner` names a live process that never releases,
  run `UVM_LOCK_TIMEOUT=3 uv --version`; assert rc 0, `uv 9.9.9 (fixture)` on stdout,
  `current -> versions/9.9.9`, and the plant still standing (R1). **Observed on main: red** — rc 1,
  `timed out after 3s waiting for provisioning lock`, empty stdout, `current` absent.*
- **R4** — WHEN two or more processes publish the same version concurrently, the wrapper SHALL leave
  a correct tree whichever publishes first — `versions/<ver>` holding exactly one distribution with
  nothing nested inside it, no `versions/.incoming.*` surviving, `current` resolving — and every
  process SHALL exit 0 with the version it asked for on stdout. The losing copy SHALL be discarded.
  With R10, this discharges R3 of [`issues/invariant-audit-gaps.md`](../../issues/invariant-audit-gaps.md).
  *Checked three ways. (a) Deterministic sandbox drive: an `mv` shim first on `PATH` that, for a
  source under `versions/.incoming.*`, first publishes a complete copy at the destination — a rival
  winning between the existence check and the rename — then execs the real `mv`; assert the tree
  post-conditions above. (b) Statistical: the re-pointed `tests/lock-race.sh` (R15). (c) A multi-rank
  Slurm drive on Lustre (2 nodes) and GPFS (1 node) against a cold tree under a held lock, so the
  ranks proceed and publish at once; taken on trust. **Observed on main, (a): red** — rc 0 and the
  right version printed, but `versions/9.9.9/` holds `.incoming.78TbKHfa` beside `uv` and `uvx`: a
  staging tree nested inside a published one. (b) and (c) do not exist yet.*
- **R5** — WHEN a non-provisioning (repair) waiter reaches its timeout with its predicate still
  unsatisfied, it SHALL exit non-zero naming the holder its `owner` file records, and SHALL NOT run
  the work it was waiting to do. This is the lock half of `purge-tree-repair` R9.
  *Checked by a sandbox drive that takes the lock as a non-provisioning caller — a test caller or stub
  the plan names; a repair implementation is a non-goal — against a planted lock that is never
  released: assert non-zero exit within the timeout, the planted `owner` line on stderr, and no trace
  of the caller's critical section. **Observed on main: not constructible.** `main` has one caller
  and one timeout behavior: every waiter dies at the timeout (R3's red), and a dead-holder lock is
  broken rather than waited on (R1's red).*
- **R6** — The caller SHALL name the predicate that decides "already satisfied" while it waits, so a
  non-provisioning caller does not early-out on the provisioning question; provisioning's calls SHALL
  keep testing the version they were asked for. Carried from R11 of
  [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md). The bash 3.2 floor rules out
  namerefs; the exact signature is the plan's.
  *Checked by the R5 drive: with `current` resolving, so the provisioning test is true, and the
  caller's predicate false, the waiter does not early-out; with the predicate made true mid-wait, it
  returns without running the critical section. The reviewer also reads every call site of the lock.
  **Observed on main: not constructible** — the early-out is fixed to `uvm_have "${want}"` (`:399`).*
- **R7** — The heartbeat (`uvm_lock_heartbeat`, `uvm_proc_start`), lock ageing (`uvm_age`), every path
  that breaks a lock, the ownership-qualified release, and the `UVM_LOCK_STALE` knob SHALL be
  removed. Nothing SHALL read a pid, a start time, a heartbeat or an mtime to decide whether another
  process is still working. A site that still exports `UVM_LOCK_STALE` SHALL NOT see a call fail or
  change behavior because of it.
  *Checked by
  `git grep -n -E 'uvm_lock_heartbeat|uvm_proc_start|uvm_age|lock_stale|UVM_LOCK_STALE|kill -0' -- bin/uv-manager`
  matching nothing, and by `temp_root.sh --offline sh -c 'UVM_LOCK_STALE=1 uv --version'` exiting 0
  with the fixture version. That release by path is sound is graded by the reviewer against the
  Clarification that verifies it. **Observed on main: red** — 25 matching lines; rc 1 with
  `UVM_LOCK_TIMEOUT must be less than UVM_LOCK_STALE` and empty stdout.*
- **R8** — `uvm doctor` SHALL report a standing lock, naming its path and the `owner` line it records,
  and `uvm clean` SHALL be able to remove it without removing the installed tree. Clearing a lock is a
  diagnostic action taken by a human or by tooling, never a decision a racing rank makes, and `uvm
  doctor` reports what the lock records without judging whether its holder is alive.
  *Checked by a sandbox drive: provision, plant a lock with a foreign `owner` line, run `uvm doctor`
  and assert its output names `.install.lock` and the planted line; then run `uvm clean <target> --yes`
  with the target the plan names, and assert the lock is gone and `current` still resolves to
  `versions/9.9.9`. **Observed on main: red** — `uvm doctor` exits 0 without mentioning the lock;
  `uvm clean` accepts only `cache`, `arch` and `all`, and `arch` removes the tree with the lock.*
- **R9** — `.agents/factory/invariants.md` §5 and `AGENTS.md` § *Invariants* SHALL assert the new
  contract and SHALL NOT retain a sentence describing a break, a stale threshold or a heartbeat. The
  same holds for the surfaces `AGENTS.md` § *Same-commit rule* names: the `uvm_help` heredoc,
  `README.md` and `etc/uv-manager.conf.example`. `/uvm-review` grades against `invariants.md`, so a
  leftover assertion turns correct code into an automatic CRITICAL.
  *Checked by
  `git grep -n -i -E 'UVM_LOCK_STALE|heartbeat|refresher|stale.?breaker|broken as stale|break(s|ing)? (itself|the lock|a lock|stale|its)|breaks itself' -- AGENTS.md .agents/factory/invariants.md README.md etc/uv-manager.conf.example`,
  every remaining hit read by the reviewer (the pattern over-matches on purpose), and by
  `temp_root.sh uvm help | grep -c UVM_LOCK_STALE` printing 0. **Observed on main: red** — 37 hits
  (19 in `invariants.md`, 9 in `AGENTS.md`, 6 in `README.md`, 3 in the config example); `uvm help`
  documents `UVM_LOCK_STALE`.*
- **R10** — IF the rename into `versions/<ver>` fails, THEN the wrapper SHALL remove its staging
  directory, release the lock, and exit non-zero with a `uv-manager:` message naming the failed
  publish.
  *Checked by a sandbox drive: an `mv` shim first on `PATH` that fails with `Permission denied` for a
  source under `versions/.incoming.*`; assert non-zero exit, a `uv-manager:` line naming the failure,
  no `versions/.incoming.*` left and no lock left. **Observed on main: red** — rc 1 under `set -e`
  with only the bare `mv: rename … Permission denied` line, and `versions/.incoming.rjJVs1Ly` left
  behind. The lock itself is released, by the EXIT trap.*
- **R11** — IF the wrapper wins `mkdir` and then cannot record its `owner` line, THEN it SHALL exit
  non-zero with the shell's errno diagnostic and `cannot record ownership` on stderr, as today, and
  SHALL leave no lock directory behind, including when the failed write left an entry inside it.
  *Checked by the `mkdir` shim from
  [`issues/lock-owner-write-errno.md`](../../issues/lock-owner-write-errno.md), which creates the lock
  directory and plants a dangling `owner` symlink, so the write fails `ENOENT` with the directory
  standing and non-empty; assert rc 1, both stderr lines, and `.install.lock` absent afterwards.
  **Observed on main: red** — rc 1 with both lines, and `.install.lock` left standing holding the
  `owner` entry. On `main` a stale break reclaims it 600 s later; once nothing breaks locks, nothing
  would.*
- **R12** — WHEN a pinned request is satisfied by another process's concurrent install, the wrapper
  SHALL select the pinned version before returning, or SHALL fail naming the version it could not
  select. It SHALL NOT exec a different version at rc 0. This covers `UVM_PIN` on `uv`/`uvx`,
  `uvm install <ver>` and `uv self update <ver>`.
  *Checked by the construction in
  [`issues/pin-early-out-selects-nothing.md`](../../issues/pin-early-out-selects-nothing.md): a
  fixture copy at `$UVM_FIXTURE_DIR/6.6.6/install.sh`, an `ln` shim first on `PATH`
  (`sleep 2; exec /bin/ln "$@"`) widening the interval between publish and the `current` swap, and 16
  concurrent `UVM_PIN=6.6.6 UVM_FIXTURE_VERSION=6.6.6 uv --version` ranks on one root, once on a warm
  tree already selecting 9.9.9 and once cold. Since 6.6.6 is installable, assert every rank, warm and
  cold, exits 0 printing `uv 6.6.6 (fixture)`. The failure branch is graded by a second drive in which
  the pinned version cannot be selected (the plan names how it constructs that); assert every rank
  exits non-zero naming 6.6.6 and none prints another version. **Observed on main: red** — warm: 15 of 16
  ranks rc 0 printing `uv 9.9.9 (fixture)`; cold: 15 of 16 rc 1, empty stdout,
  `uv is still missing after provisioning` without naming 6.6.6. `current` ended at `versions/6.6.6`
  both times: the tree self-corrects, the invocation does not.*
- **R13** — The paths in `uvm_install` that return success SHALL agree on whether the version has
  been selected, and that agreement SHALL be visible in the code rather than reconstructed by a reader.
  *Graded by the reviewer reading `uvm_install` and its three callers (`uvm_ensure_uv`, `uvm install`,
  `uvm_self_update`); no command decides it. **On main:** the fast path (`:565-568`) and the re-check
  under the lock (`:573-577`) select, and the lock's early-out (`:570`) returns 0 without selecting.*
- **R14** — Behavior on the unpinned path SHALL be unchanged: with no lock planted, a burst of
  unpinned ranks on a cold tree SHALL produce one installer entry per burst, every rank exiting 0
  with the fixture version, and no lock left standing. The discipline SHALL remain `mkdir`.
  *Checked by `tests/lock-race.sh --plant control --ranks 32 --bursts 2` exiting 0 with one installer
  entry per burst and `progress=ok`, and by `git grep -n flock bin/uv-manager` matching only the
  rationale comment. **Observed on main: green** — 2 entries for 2 bursts, 0 non-zero ranks, 0 locks
  left, 3 s; the `flock` grep matches only `:172`. Expected green after.*
- **R15** — `tests/lock-race.sh` SHALL assert the new contract. The counters that cannot fire once
  nothing takes a lock by force — `stolen_holds`, `robbed_winners` and `break_notes` — SHALL be
  removed, and `concurrent_installers` SHALL invert into an assertion that after a burst in which
  several ranks published concurrently the tree meets R4's post-conditions and every rank's stdout
  carries the version it asked for. Its progress check SHALL account for a plant that no rank ever
  clears. The tree assertion's red state SHALL be established against the unguarded publish before
  the guard lands, and recorded.
  *Checked by `git grep -n -E 'stolen_holds|robbed_winners|break_notes' -- tests/` matching nothing,
  and by the re-pointed drive under a held plant exiting 1 on the tree assertion against a build that
  proceeds on timeout but still publishes with `main`'s unguarded `mv` — the technique
  `spec/lock-ownership-and-hold-time/REVIEW.md` R8 records — then 0 against the finished branch.
  **Observed on main:** 3 matching lines. The tree assertion does not exist yet, and against `main`
  itself a held plant makes every rank time out, so the drive would stop at its progress check rather
  than reach the tree; R4 (a) is the same defect's red state observable on `main` today.*

## Non-goals (no-gos)

- **Repair itself.** `UVM_REPAIR`, damage detection and any repair implementation are
  [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md), the next cycle. R5 and R6 are
  lock contract, exercised by a test caller or stub, never by a repair.
- **Anything in the seed's § *Rejected — do not re-propose*:** the exclusive rename and its
  compose-and-restore variant, any readable identity for a directory instance, occupancy by a written
  entry, a persistence count standing in for age, a heartbeat, a refresher leash or `kill -0`
  staleness, and a `/tmp` fallback for the state root. A plan re-proposing one owes that list a
  rebuttal, not a design. This includes `uvm doctor`: it reports what a lock records and never infers
  whether its holder lives.
- **No new environment variable is expected.** The notice threshold and the repair caller's timeout
  are the plan's to set; a new knob proposed for either goes in the plan's deviation table in front of
  a human. `UVM_LOCK_STALE` goes away and nothing replaces it.
- **The lock's location, name and `mkdir` discipline do not change** (R14).
- **The owner-write classifier is not rebuilt.** R1, R2, R4 and R5 of
  `issues/lock-owner-write-errno.md` exist because a robbed winner was reachable, and it no longer is
  (Clarifications). R11 here is that seed's live half.
- **The two unrelated gaps in `issues/invariant-audit-gaps.md`** — `uvm_global_takes_value`'s missing
  options and the trampoline guard's `-x` — stay there. Its R4 (the heartbeat's leash degrading where
  `ps -o lstart=` cannot answer) is moot once the heartbeat is gone and is not measured here.
- **No committed suite beyond `tests/lock-race.sh`.** The sandbox drives in the *Checked by* clauses
  are this cycle's gates; `tests/lock-race.sh` is the one committed drive, and R15 re-points it.
- **The lock's performance claims** (the heartbeat's `ps` fork, the orphaned `sleep`) disappear with
  the heartbeat rather than being measured.

## Clarifications

- **Q:** Fold `issues/pin-early-out-selects-nothing.md` into this cycle? — **A:** Yes. It is the
  provisioning early-out this cycle already rewrites to take a caller-named predicate (R6), and the
  measurement — 31 of 32 pinned cold-start ranks failing, and on a warm tree running the wrong version
  at rc 0 — makes it a correctness defect in the lines under edit. Its draft R1–R3 become R12–R14. This
  takes the GOAL to fifteen criteria, past the soft 8–10 breaker; that is accepted, the fold being a
  bounded addition to lines already in scope rather than a second deliverable. The seed is promoted
  with this cycle: `status: adopted:lock-simplification` (foreman, per decision of the maintainer,
  resolved 2026-10-27).
- **Q:** Are `issues/lock-break-instance-identity.md` and `issues/lock-owner-write-errno.md`
  superseded, and does the owner-write fatal path's unqualified `rmdir` survive independently of the
  robbery? — **A:** Both are superseded, as the seed records; neither file is deleted here, and
  retiring both at landing is this cycle's obligation, discharged by `/uvm-roadmap`. Confirmed at
  promotion by reading `main`: once R1 and R7 hold, the only processes that remove `.install.lock`
  are its creator's release, its creator's fatal path, and a human through `uvm clean`. No rank can
  remove another rank's directory between that rank's `mkdir` and its `owner` write, so the robbery is
  unreachable and the classifier has nothing left to misclassify. The `rmdir` is therefore no longer
  unqualified in effect: a directory standing at that point is this rank's own. **One half survives
  independently, in a different form.** `rmdir` refuses a directory holding an entry, which is what a
  write failing after it created the file leaves (a quota or a full filesystem), and the lock then
  stands. On `main` a stale break reclaims it; after this cycle nothing does. That is R11, measured red
  on `main` with that seed's own shim (foreman, per decision of the maintainer, resolved 2026-10-27).
- **Q:** What happens to `issues/invariant-audit-gaps.md`? — **A:** Its R3 (the unguarded rename) is
  absorbed here as R4 and R10, and its R4 (the heartbeat's leash) is moot once the heartbeat is
  deleted. Both are recorded in that seed in this commit so it shrinks to its two remaining gaps rather
  than drifting (foreman, per decision of the maintainer, resolved 2026-10-27).
- **Q:** How far does this cycle reach toward the job-launch goal it serves? — **A:** It is the lock
  half. The goal is that N ranks of a wrapped `uv`/`uvx` under `UVM_REPAIR` have one rank take the
  lock, repair and release while the rest skip repair and exec, and that unexpected faults fail
  clearly for a human to clear with `uvm doctor` and `uvm clean`. Repair is the next cycle. R5 and R6
  are in scope as lock contract only, and thresholds, timeout values and the predicate's exact
  signature are left to the plan (foreman, per decision of the maintainer, resolved 2026-10-27).
- **Q:** May a criterion be checked on a real cluster? — **A:** Yes. Besides sandbox drives and
  `tests/lock-race.sh`, the cycle runs a multi-rank Slurm drive on a Lustre filesystem (2 nodes) and a
  GPFS filesystem (1 node). A property only a real shared filesystem can show — `mkdir` atomicity
  across nodes, concurrent publish across nodes — may name that drive, and is then taken on trust
  (foreman, per decision of the maintainer, resolved 2026-10-27).
- **Q:** What is the gate's red state? — **A:** Per the seed's § *The instrument changes meaning*: the
  counters that become unreachable are removed, and `concurrent_installers` inverts into a correct-tree
  assertion whose red state is established against the unguarded rename. That is R15, with its
  observed status recorded; R4 (a) is the same defect's red state as observable on `main` (foreman,
  per decision of the maintainer, resolved 2026-10-27).
- **Q:** The seed's R7 asks that release by path be verified sound at promotion rather than assumed.
  — **A:** Verified by reading `main`, with one residual. Against every wrapper path it is sound: a
  holder's lock is removed only by that holder, so the directory at the path while it holds is its
  own. The residual is a human running `uvm clean` against a *live* lock. The holder's later release
  then removes whatever lock the next rank took, which for provisioning costs a redundant download and
  for repair could admit a second repairer. The decision makes clearing a lock a human act; the plan
  owes R8's wording making plain that the lock may be held by a live process. Not reopened (shaping
  reading, 2026-10-27, for sign-off at the gate).
- **Q:** What should a site that still exports `UVM_LOCK_STALE` see? — **A:** Nothing. Removing the
  knob means it stops having an effect, and a site configuration copied from
  `etc/uv-manager.conf.example` must not start failing calls. On `main` an inherited `UVM_LOCK_STALE=1`
  is fatal. A warning would be a new output surface, so none is added (R7; shaping reading,
  2026-10-27, for sign-off at the gate).
- **Q:** What does R8's "removable by `uvm clean`" require? — **A:** Removal without the tree.
  `uvm clean arch --yes` already removes the lock on `main` by removing everything beside it, so a
  reading that accepted that would make the criterion vacuous. The spelling, whether a new target or
  some other form, is the plan's, under the bias toward the smallest surface (shaping reading,
  2026-10-27, for sign-off at the gate).
- **Q:** May R12's drive pass with pinned ranks failing cleanly when the pinned version was in fact
  installed by a rival? — **A:** No. The job-launch goal needs every pinned rank to run the pin, so a
  satisfiable pin succeeds on every rank; failing with the version named is reserved for a pin that
  cannot be selected, and a second drive grades it (foreman gate, 2026-10-27).
- **Q:** The seed's R-IDs or fresh numbering? — **A:** The seed's. R1–R9 keep their seed meaning
  because `ROADMAP.md` and `issues/purge-tree-repair.md` already cite them (R4, R5, R6); the folded
  and newly confirmed criteria are R10–R15 (resolved 2026-10-27).
- **Q:** Does the acquire-time retake (`lock-acquire-retake`, the `robbed` bound) stay? — **A:** The
  plan decides. Its premise, a losing stale-breaker, is gone, so the branch is reachable only through
  a human clearing a lock mid-acquire. R11 constrains the fatal path whichever way it goes (resolved
  2026-10-27).

## Related materials

- Seed: [`issues/lock-simplification.md`](../../issues/lock-simplification.md) — § *The decision* and
  § *Rejected — do not re-propose* are binding on the plan.
- Folded seed: [`issues/pin-early-out-selects-nothing.md`](../../issues/pin-early-out-selects-nothing.md)
  — the `ln` shim construction and its measured histograms.
- Superseded: [`issues/lock-break-instance-identity.md`](../../issues/lock-break-instance-identity.md)
  and its retained account [`spec/lock-break-instance-identity/`](../lock-break-instance-identity/GOAL.md),
  whose `REVIEW.md` carries the three CRITICALs; [`issues/lock-owner-write-errno.md`](../../issues/lock-owner-write-errno.md),
  whose `mkdir` shim R11 reuses.
- Written into: [`issues/invariant-audit-gaps.md`](../../issues/invariant-audit-gaps.md) (R3 absorbed,
  R4 moot) and [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md) (R11 moved here as
  R6; its R7 and R9 are what R5 and R6 serve).
- `bin/uv-manager` § *provisioning lock* (`:169-503`) and § *install* (`:517-636`); `.agents/factory/invariants.md`
  §4 (pins) and §5 (the lock); `AGENTS.md` names `uvm_acquire_lock` a high-blast-radius region, so a
  confirmed finding here forces a human sign-off gate at review.
- `tests/lock-race.sh` and `tests/lock-race-burst.sh` — the instrument R15 re-points.

## Verification limits, declared up front

- **The shims depend on call shape.** R4 (a) and R10 intercept an external `mv` called with the
  staging directory as its first argument, R11 an external `mkdir` called with the lock path alone,
  and R12 an external `ln`. A plan that publishes with another primitive, or changes a call shape,
  makes the drive silently stop constructing its state, and the failure mode is that it passes. The
  plan owes a construction that reaches whatever primitive it chooses, and says so beside the gate.
- **`mkdir` atomicity on Lustre, GPFS and NFS** remains taken on trust, as every lock cycle has
  declared. The Slurm drive in R4 (c) exercises it across two nodes on Lustre and on one GPFS node; it
  is evidence, not proof, and NFS is not exercised at all.
- **R13 has no command.** It is graded by reading.
