# REVIEW — A losing breaker deletes the lock a third rank just won

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** b2be530  ·  **Base:** main  ·  **Date:** 2026-09-09
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3
- **Variant:** `debate` — two independent blind reviewers (ship-stance and block-stance), each with
  its own scratchpad, plus the separate completeness sub-pass. Reconciled by measurement; see
  *Reconciliation*.

## Verification run

Orchestrator measurements, run after both reviewers returned, to settle a contradiction between them.
Reviewer-run commands are cited inline in the findings.

- `bash -n bin/uv-manager` → OK (bash 3.2.57, arm64). Both reviewers concur.
- `.agents/factory/bin/lint.sh` → all checks passed, version single-source 0.6.1. Both concur.
- `tests/lock-race.sh --plant none --bursts 40 --quiet` ×3 on b2be530 → **rc 1, rc 1, rc 0.**
  Red runs: `concurrent_installers=3/2560 via_break=3` and `1/2560 via_break=1`; `stolen_holds=3`
  and `1`; `robbed_winners=1` and `0`. All three runs `progress=ok`, `locks_left_standing=0/40`,
  `nonzero_ranks=0` — no straggler or late-marker contamination.
- `tests/lock-race.sh --plant none --bursts 12 --quiet` on b2be530 → rc 0, `0/768` on all three
  counters. This is the shape the drive's own header prescribes for this plant.
- Fresh owner-less lock (`mkdir` only, age ~0 s, `UVM_LOCK_STALE=30`), branch versus a `main`
  worktree, both under `temp_root.sh --offline --arch probe`:
  branch → break note `no owner recorded`, `lock=DESTROYED`, rc 0 in ~2 s;
  main → no break note, `lock=STILL-PRESENT`, rc 1 at the 6 s timeout.
- Planted `${lock}/mark` with no `owner`, aged, three plants under `temp_root.sh --offline`:
  same-host **dead** pid → swept, rc 0, `current -> versions/9.9.9`, lock gone (control);
  **foreign-host** pin → rc 1, lock stands carrying `mark`;
  same-host **live/recycled** pid → rc 1, lock stands carrying `mark`.
- Five sequential ranks against a foreign-host pin in one sandbox → rc 1 ×5, lock never clears,
  `current: NONE` throughout.
- `rm` PATH shim sending `SIGKILL` to the wrapper on the first removal inside the lock directory →
  rank rc 137, `AFTER entries: . .. mark owner`, mark content
  `host=Geoffreys-MacBook-Pro-main.local pid=90077 nonce=…`. The pin outlives the process that wrote it.
- `python3` recomputation of the drive's false-green figures — see F7.

## Requirement → evidence matrix

| R-ID | Implemented by | Verified how | Status |
|------|----------------|--------------|--------|
| **R1** | `tests/lock-race.sh`, `tests/lock-race-burst.sh`, both `100755` and both added to `lint.sh` twice | Straggler injection → rc 3 with 0 bytes on stdout, naming the live installer; `--late` → rc 3, 0 bytes. Red against `main` on both plants. Guard-removal mutants on the branch's own code turn it red again (18/768 and 8/1280 with the guard chain neutered; 3/768 with only `set -C`→`set +C`), so the branch's green is caused by the guards, not by the drive failing to construct the state. Sizing arithmetic recomputed. | ✅ with **F5**, **F7** |
| **R2** | separate `stolen` / `robbed` / `over` counters, `over` split `via_break` / `no_break_in_burst` | `--plant control` ×5 → `break_notes=0`, all counters 0, `installer_entries=5` for 5 bursts. My own red runs attributed correctly: `via_break=3 no_break_in_burst=0`. The other-cause deferral landed as `issues/pin-early-out-selects-nothing.md` + a `ROADMAP.md` entry. **Limit:** only the `via_break` side was ever observed non-zero; `no_break_in_burst` is implemented and unexercised. | ✅ |
| **R3** | `uvm_lock_still_forfeit`, `${lock}/mark` under `set -C`, the `post == still` re-check, `uvm_lock_removable` | `--plant owner --bursts 40` → 0/2560 ✅. `--plant none --bursts 40` → **rc 1 in 2 of 3 orchestrator runs**, concurrent installers attributed to the break path. R3's check clause requires zero. A ~60× narrowing against `main`, not a closure. | ❌ **F1**, **F2** |
| **R4** | the identity test gating both removals, `last_holder`, the reworded note | Aged dead-holder lock plus a third-party entry: branch → exactly 1 break note, `owner` present and byte-identical, timeout names the recorded line. Same construction on `main` → `owner` gone, `<none recorded>`. R4's stated red state reproduced and closed. | ✅ |
| **R5** | untouched | `lock-acquire-retake` R1–R4 re-run by both reviewers with the `mkdir` PATH shim: rc 0 with `uv 9.9.9 (fixture)`; `chmod 500` → rc 1 with `Permission denied` + `cannot record ownership`; bounded robbery dies at 3 retakes; fresh foreign lock → rc 1 at exactly `UVM_LOCK_TIMEOUT`; exactly one break note across a wait; absent-lock retry names the permissions fault. Identical on branch and `main`. | ✅ |
| **R6** | untouched | `temp_root.sh --offline uv --version` → `uv 9.9.9 (fixture)` on stdout, rc 0, `current -> versions/9.9.9`, no lock and no `.install.mark.*` left. `git grep -n flock bin/uv-manager` → one match, `:172`, the rationale comment. | ✅ |

Unmapped changes (possible scope creep): **none.** Both reviewers and the completeness pass
independently mapped every non-script file to a named obligation — `lint.sh` to R1, `README.md` /
`AGENTS.md` / `invariants.md` to the same-commit rule, and the five `issues/` files plus `ROADMAP.md`
to the § *Non-goals* clauses that name them "in this same commit". No new environment variable, no new
subcommand, bounds are script literals, no rename-family construction anywhere in the diff.

Requirements taken on trust: `mkdir` atomicity on Lustre/GPFS/NFS; NFS attribute caching against the
`owner` re-reads at `:580` and `:623`. Both are declared up front in `GOAL.md` § *Verification limits*.
Note that **F2 lands inside the third declared limit** — "R1's drive measures a local filesystem" — which
is why the drive is an unreliable witness for it and a reviewer had to construct it directly.

## Findings

### [CRITICAL/CONFIRMED] R3 unmet — concurrent installers through the break path on the owner-less plant
- **Where:** `bin/uv-manager:544-546` (`uvm_acquire_lock`, the `elif (( husk >= 2 ))` branch)
- **Failure scenario:** Two ranks enter the installer and write into one architecture directory at
  once. A rank that recorded ownership finds its lock replaced at release. This is the outcome R3
  exists to forbid, reached on the plant R3 names.
- **Evidence:** `tests/lock-race.sh --plant none --bursts 40 --quiet` ×3 on b2be530 → rc 1, rc 1,
  rc 0. `concurrent_installers=3/2560 via_break=3 no_break_in_burst=0` and `1/2560 via_break=1`;
  `stolen_holds=3` and `1`. All runs `progress=ok`, `locks_left_standing=0/40`, `nonzero_ranks=0`.
  Reproduces the block-stance reviewer's 2-of-3 ratio independently.
- **Competing explanations ruled out:** the pre-existing early-out at `:570` cannot produce a stolen
  hold, and the drive's own attribution reports `no_break_in_burst=0`; straggler and late-marker
  contamination are excluded by the absence of rc 3 and by `locks_left_standing=0`; a drive artefact
  is excluded by `--plant control` ×5 green and `--plant owner --bursts 40` green on the same binary.
- **Touches:** R3; high-blast-radius region `uvm_acquire_lock`.

### [CRITICAL/CONFIRMED] The husk branch pre-empts the age test, so a lock with no age floor is broken
- **Where:** `bin/uv-manager:544-549` — `elif (( husk >= 2 ))` is evaluated *before* the
  `elif { age=… }` arm; `uvm_lock_still_forfeit`'s husk arm at `:376`
- **Failure scenario:** The mechanism behind the finding above. An owner-less directory is condemned
  on persistence alone, with no lower bound on the instance's age. A winner whose `owner` write has
  not landed within two observations is indistinguishable from a husk, and is condemned. On `main`
  the same directory falls through to the mtime age test, which spares a fresh one — so the
  discriminator that protected a live winner is removed rather than narrowed.
- **Evidence:** fresh owner-less lock, age ~0 s, `UVM_LOCK_STALE=30`, identical construction on both
  sides. Branch → `provisioning lock is forfeit and will be broken, no owner recorded`,
  `lock=DESTROYED`, rc 0 in ~2 s. `main` → no break note, `lock=STILL-PRESENT`, rc 1 at the 6 s
  timeout. The block-stance reviewer additionally drove this to a robbed winner on the ordinary
  cold-start path with no lock planted, by widening only the winner's acquire gap past one poll
  interval (branch 8/8 robbed at `WIDEN=1.1`, `main` 0/9 on the same shim).
- **Note on the reset:** `invariants.md` §5 as added by this diff justifies the branch by saying the
  count "resets the moment an `owner` appears … a count that carried over would eventually declare a
  live winner caught inside its acquire window forfeit, which is the whole defect the guard exists to
  prevent." The implemented reset is conditioned on *the observer seeing* an owner; a winner slower
  than the poll never supplies one, so the reset does not bound the case it is offered as bounding.
  The two passes are also not necessarily "a second apart": `[[ -d "${lock}" ]] || continue` at `:642`
  skips the `sleep 1` at `:660`.
- **Touches:** R3; `invariants.md` §5; high-blast-radius region `uvm_acquire_lock`.

### [CRITICAL/CONFIRMED] An abandoned `${lock}/mark` wedges provisioning permanently
- **Where:** `bin/uv-manager:620` (the pin), `:596-604` (the sweep), `uvm_unlock:236-243`
- **Failure scenario:** The diff introduces an entry *inside* the lock directory. While
  `${lock}/mark` stands, no rank can pin (`O_EXCL` → `EEXIST`) and no rank can `rmdir` (non-empty).
  Recovery is a human with `rm -f`, on every node, for that user, indefinitely. The wrapper's own
  comment at `:589-594` names this state and offers the sweep as its answer, but the sweep is a bare
  `kill -0` on a host-matched pid: a pin recording another node is never probed, and a pin whose pid
  has been reoccupied probes live. `uvm_unlock` clears `uvm_lock_mark`, which is
  `${uvm_root}/.install.mark.$$` — the outside freshness reference, a different path. No trap covers
  the entry inside the lock, and unlike the lock itself it has no age net behind it.
- **Evidence, reachability:** `rm` PATH shim sending `SIGKILL` to the wrapper at the first removal
  inside the lock directory → rank rc 137, `AFTER entries: . .. mark owner`, mark content
  `host=… pid=90077 nonce=…`.
- **Evidence, consequence:** three plants under `temp_root.sh --offline --arch probe`, lock aged,
  `mark` only. Same-host **dead** pid → swept, rc 0, `current -> versions/9.9.9`, lock gone.
  **Foreign-host** pin → rc 1, `lock present: YES`, `current: NONE`. Same-host **live** pid → rc 1,
  `lock present: YES`, `current: NONE`. Five sequential ranks against the foreign pin → rc 1 ×5,
  entries still `. .. mark`.
- **Competing explanation ruled out:** the dead-pid control recovers on the identical plant, so the
  wedge is caused by the sweep's probe and not by the plant or by the aging.
- **Touches:** `invariants.md` §5; high-blast-radius region `uvm_acquire_lock`/`uvm_unlock`. Also the
  failure class `GOAL.md` § *Non-goals* rejected the rename family for — "turning a transient race
  into a permanent outage only a human clears."

### [HIGH/CONFIRMED] `invariants.md`, `AGENTS.md` and a code comment assert properties the code does not have
- **Where:** `.agents/factory/invariants.md` §5, `AGENTS.md` § *Invariants*, `bin/uv-manager:594`
- **Failure scenario:** These are assertions *added by this diff*, so they are new rather than stale.
  `AGENTS.md` makes a section left asserting a decision the code did not implement a defect, and
  `/uvm-review` grades against `invariants.md`, so a false entry turns correct future code into an
  auto-CRITICAL finding and a defect into a pass.
  1. "A pin nobody stands behind is swept by probing that pid … recovery is **immediate** rather than
     a stale window away" / "so an abandoned one does not wedge the lock" — falsified above: recovery
     is never, for a cross-node or recycled pid.
  2. "A pin from another node is left standing and **named in the timeout message**" — the timeout
     message names neither the pin nor its holder.
  3. "a lock seen owner-less on **two consecutive passes a second apart**" — the `continue` at `:642`
     skips the `sleep 1`, so the passes can be microseconds apart.
  4. The reset clause quoted in the finding above.
- **Evidence:** measured timeout text is
  `holder, as the lock's owner file recorded it: <none recorded>`; only the recovery command mentions
  the `mark` path, and it names it as a path to remove rather than as a holder. Full output in the
  *Verification run* section.
- **Touches:** §12 (project conventions) and the same-commit rule.

### [MEDIUM/CONFIRMED] The gate is sized against the pre-fix rate, so the prescribed run cannot see the residual
- **Where:** `tests/lock-race.sh:30-39` (the sizing note), `:44` (the defaults)
- **Failure scenario:** `p` is measured "against the wrapper before this fix", which sizes the gate to
  detect the *old* rate rather than to bound the *new* residual. The prescribed `none ×12` is green on
  the branch while `none ×40` is red — so the gate as specified reports success on a branch that still
  violates R3. Separately, the defaults are `plant=owner ranks=64 bursts=20`, and the header states
  that at 20 bursts the owner plant's false green is `1.9e-2`, "which is not a gate." No command in
  the repository runs the prescribed shape: `AGENTS.md` § *Commands* is unchanged and `lint.sh` only
  parses and shellchecks the two files, so a bare `tests/lock-race.sh` runs the configuration the file
  disowns. `issues/test-harness.md` R3f commits a future runner to folding this drive in, and a runner
  taking the defaults inherits that silently.
- **Evidence:** `--plant none --bursts 12` → rc 0, `0/768`. `--plant none --bursts 40` → rc 1 twice in
  three runs. `sed -n '36,38p;42p' tests/lock-race.sh`.
- **Touches:** R1.

### [LOW/CONFIRMED] `README.md`'s enumeration of when a lock is broken omits the husk trigger
- **Where:** `README.md:529-531`
- **Failure scenario:** The text tells an operator the wrapper breaks a lock "when that pid is dead on
  this node, or when nothing has refreshed it for `UVM_LOCK_STALE` seconds". The husk branch adds a
  third trigger that fires well inside `UVM_LOCK_STALE`. The lines sit two above a hunk this diff did
  revise, and this is the surface the same-commit rule names for describing lock behavior to an
  operator. `etc/uv-manager.conf.example:74` carries the same two-way phrasing.
- **Evidence:** the fresh-lock drive above breaks a 0-second-old lock with `UVM_LOCK_STALE=30`.
- **Touches:** the same-commit rule. Found independently by both reviewers and the completeness pass.

### [LOW/CONFIRMED] Two stated false-green figures for the owner plant are optimistic
- **Where:** `tests/lock-race.sh:36-38`
- **Failure scenario:** R1 makes the sizing arithmetic explicitly reviewer-graded. The header states
  `P_burst = 0.175` correctly, then reports the powers as if `1-P = 0.82` rather than `0.825`. Both
  errors are in the unsafe direction. Neither changes a conclusion: `4.6e-4` is still a gate and
  `2.1e-2` still is not.
- **Evidence:** `python3` → `(1-0.175)^40 = 4.552e-04` against a stated `3.5e-4`;
  `(1-0.175)^20 = 2.133e-02` against a stated `1.9e-2`; `(1-0.878)^12 = 1.087e-11` against a stated
  `1.2e-11`, which is conservative and therefore fine.
- **Note:** the two reviewers disagreed here — the block-stance reviewer computed `0.82^40 = 3.6e-4`
  and read the arithmetic as sound. Recomputed by the orchestrator: `0.825` is the correct base, so
  the ship-stance reading is the one that stands.

### [PLAUSIBLE] The judged→pin window remains open for an owner-less instance
- **Where:** `bin/uv-manager:587-624`
- Between `uvm_lock_still_forfeit`'s husk arm and the pin at `:620`, the judged instance can be
  removed and a third rank can `mkdir` at the same path; the pin then lands in the *new* instance, and
  because the judged instance carried no owner the `post == still` re-check at `:624` compares `""` to
  `""` and passes. Not reproduced. The window is a handful of builtins (~10 µs) against `main`'s
  two-fork ~2.97 ms — roughly a 300× narrowing — and an instance with no `owner` yet has nobody in the
  installer, so the reachable harm is one extra retake rather than two installers. Raised because
  `invariants.md` §5 states the occupancy property without the "once the pin lands" qualification.
  Human triage; does not auto-loop.

## Reconciliation (debate variant)

The two reviewers **contradicted** each other on the central question: ship-stance returned no
CRITICAL, HIGH or MEDIUM finding and measured 3,648 ranks green; block-stance returned three CRITICALs
and measured the same code red. Per the rubric a contradiction is a claim about reproducibility and is
settled by the orchestrator measuring, with a control proving the construction reaches the state at
all before a clean result is read as absence. Settled as follows:

- **Not a disagreement about the code — a disagreement about sample size.** Ship-stance ran the
  owner-less plant at the 12 bursts the drive's own header prescribes and got a true green.
  Block-stance ran it at 40 and got a true red. Both measurements reproduce. The prescribed shape is
  undersized for the post-fix residual because `p` was measured pre-fix, which is F5 — and F5 is
  therefore not a side observation but the reason the two passes disagreed.
- **On F3 the two reviewers observed the same thing and classified it oppositely.** Both planted a
  foreign `${lock}/mark` and both saw the lock left intact at rc 1. Ship-stance recorded it as a
  by-design mechanism check; block-stance recorded it as a permanent wedge. The orchestrator's
  dead-pid control settles it: the same plant with a sweepable pid recovers at rc 0, so the standing
  lock is the sweep declining, not the design absorbing it, and five sequential ranks never clear it.
- **Overlap** on the README omission (both) and on the drive's default configuration being the one its
  header disowns (both), which raises confidence in F5 and F6.
- **Disjointness** elsewhere is wide — ship-stance's judged→pin PLAUSIBLE has no counterpart in
  block-stance's set, and block-stance's three CRITICALs have no counterpart in ship-stance's. Per the
  rubric this is a coverage signal: **the union above should not be read as complete.**

The variant earned its cost here. A single blind pass drawing ship-stance's sample would have returned
`approved` on a branch that does not meet R3.

## Human-gate triggers

**TRIGGERED.** Four CONFIRMED findings sit in `uvm_acquire_lock` / `uvm_unlock`, a high-blast-radius
region, and three of them are `invariants.md` §5 violations.

- Fired by: the three CRITICALs and the HIGH above.
- Cleared by: — *(not cleared; awaiting maintainer)*
- Date: —
- Grounds: —

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Clean. All four phases shipped and all four `verify:` blocks re-run pass (4,480 ranks; the P3 and P4
gates run 2 m 14 s and 2 m 40 s). Per-commit file lists match each phase's declared *Touches* exactly.
No scope balloon: every wrapper hunk maps to P2/R4 or P3/R3, and the `issues/` and `ROADMAP.md` changes
are the § *Non-goals* deferral discharges. All four named deferral obligations are present
(`issues/invariant-audit-gaps.md` R4, `issues/test-harness.md` R7, the new
`issues/pin-early-out-selects-nothing.md` plus its `ROADMAP.md` entry, and the promotion line in
`issues/lock-owner-write-errno.md`). The same-commit rule is satisfied on every surface, with
`AGENTS.md` and `invariants.md` moving in lockstep — though see F4: moving in lockstep is not the same
as being true.

Two notes from that pass, both below finding threshold: one P1 checklist item is ticked for a sentence
`AGENTS.md:308` still opens with, and `issues/test-harness.md` R3f plus the corrected measurement in
`issues/lock-owner-write-errno.md` sit slightly wider than the letter of the contract while following
its intent.

Its one aside — that `uvm_lock_mark` is assigned after the `uvm_have` early-out, so the mark path is
registered only for callers reaching the wait loop — was deliberately withheld from the correctness
reviewers, since it came from an agent that had read the plan. Neither blind reviewer reached it
independently. It is recorded here as an untriaged observation, not a finding.

---

## Review cycle 2 — approved (2026-09-09)

- **Reviewed commit:** c8493a4  ·  **Base:** main  ·  **Mode:** scoped to the remediation delta,
  `7202dfa..c8493a4`, at the maintainer's direction.
- **Graded surface:** 11 files, 599 insertions. `bin/uv-manager` and `README.md` are **byte-identical
  to `main`** — `git diff main -- bin/uv-manager` is empty. The delta is one shell drive
  (`tests/lock-race.sh`, reviewed at depth in cycle 1 by two independent reviewers), its companion,
  the `lint.sh` wiring, two prose hunks in `AGENTS.md`, one in `invariants.md`, `ROADMAP.md`, and six
  `issues/` seeds. No executable wrapper code, so the high-blast-radius condition is not met by the
  landed diff.
- **No blind subagent pass was run for this cycle,** and that is a deliberate scope call rather than
  an omission: the graded surface contains no wrapper code, and the one executable file in it was
  already graded by both cycle-1 reviewers against R1 and R2. Recorded here so a later reader does not
  mistake cycle 2 for a second full adversarial pass.

### Rescope — the contract moved, by maintainer decision

`GOAL.md` is locked and R3/R4 are **not met**. They are superseded rather than failed. On 2026-09-09
the maintainer decided that the wrapper will not break locks at all: distinguishing a slow holder from
a dead one is failure detection, no asynchronous system settles it, and a network filesystem adds
stale attribute caches, skewed clocks and recycled pids. A lock that is never broken has no break for
R3 to constrain and no denied break for R4 to preserve evidence through.

The wrapper was therefore reverted to `main` and only the measurement half kept. The replacement
design is seeded at [`issues/lock-simplification.md`](../../issues/lock-simplification.md) and
sequenced first in `ROADMAP.md`.

| R-ID | Cycle 1 | Cycle 2 disposition |
|------|---------|---------------------|
| R1 | ✅ with F5, F7 | ✅ **lands.** `tests/lock-race.sh` is committed and is the instrument the decision rested on. |
| R2 | ✅ | ✅ **lands.** Control run green at 0/320 with `break_notes=0`. |
| R3 | ❌ F1, F2 | **Superseded.** No break exists to constrain. |
| R4 | ✅ | **Superseded.** No denied break exists. |
| R5 | ✅ | ✅ **trivially.** The wrapper is byte-identical to `main`. |
| R6 | ✅ | ✅ **trivially.** Same. |

### Disposition of cycle 1's findings

All seven CONFIRMED findings were against code that no longer exists on this branch. They are
**moot by removal, not by repair** — none was fixed, and none should be read as having been. This is
not a `Correction to cycle 1`: cycle 1's measurements stand exactly as written, and the reverted code
would still exhibit every one of them.

The substance that outlives the revert is carried forward rather than dropped: F5's finding that the
gate was sized against the pre-fix rate, and F7's arithmetic error, both belong to
`tests/lock-race.sh`, which **lands with them unrepaired**. `lock-simplification` § *The instrument
changes meaning* is where they are addressed, together with the larger problem that three of the
drive's four counters become structurally unreachable under the new design. F6 (the `README.md`
omission) disappeared with the revert, since the husk trigger it failed to document no longer exists.

### Verification run (cycle 2)

- `git diff main -- bin/uv-manager` → empty. `git diff main -- README.md` → empty. Script length 1224,
  identical to `main`.
- `bash -n bin/uv-manager` → OK. `.agents/factory/bin/lint.sh` → all checks passed, version
  single-source 0.6.1, shellcheck clean over both new drives.
- `tests/lock-race.sh --plant control --ranks 64 --bursts 5` → rc 0; `stolen_holds=0/320`,
  `robbed_winners=0/320`, `concurrent_installers=0/320`, `break_notes=0`, `installer_entries=5` for 5
  bursts, `progress=ok`.
- `tests/lock-race.sh --plant none --ranks 64 --bursts 4` → rc 1; `concurrent_installers=10/256
  via_break=10`, `stolen_holds=10/256`, `progress=ok`. Red against the reverted wrapper, which is the
  honest landed state: the drive documents the defect `lock-simplification` removes, and R1 specified
  exactly this red-against-`main` behavior.

### Human-gate triggers (cycle 2)

**Discharged by removal.** Cycle 1's gate fired on four CONFIRMED findings in
`uvm_acquire_lock`/`uvm_unlock`. The landed diff contains no change to either function, or to any
other line of `bin/uv-manager`, so no CONFIRMED finding survives in the graded surface and the
condition no longer holds.

- Cleared by: the maintainer, 2026-09-09, inline.
- Grounds: the reverting of the entire wrapper change, directed by the maintainer, together with the
  decision to remove lock-breaking rather than harden it. The clearance is of the *cycle*, not of the
  findings — which were never repaired and are recorded above as moot by removal.
