# REVIEW — Stop breaking the lock, and split provisioning from repair

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 0e5bbf6843099ad90abe4cf9351f48781fd32e8e  ·  **Base:** main  ·  **Date:** 2026-10-28
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md` (escalate on non-convergence)

## Review cycle 1 — changes-requested (2026-10-28)

**Mode:** `debate`. The diff rewrites `uvm_acquire_lock`, `uvm_unlock`, `uvm_install` and
`uvm_point_current`, so two fresh reviewers ran independently, one arguing "ship" and one "block".
Each had its own scratch directory and `TMPDIR`. Each received `GOAL.md` (as a copy outside `spec/`),
the spec-excluded diff, hash-only log, and `invariants.md`/`review-rubric.md` by path. The one
declared-readable record was `spec/lock-ownership-and-hold-time/REVIEW.md` (R15 cites its R8
technique). Both handed back a clean tree (`git status --porcelain` empty).

**Reconciliation.** The R-ID matrices *overlap* completely: both reviewers independently drove every
command-checkable criterion green on this branch and reproduced GOAL's recorded red state against
`main` (or a mutant) with the same construction. That is a confidence signal for R1–R15. The findings
are *disjoint*: only the block reviewer reported anything, and all of it is prose or scope. The ship
reviewer read the edited §4–§6 bullets as matching the code. The block reviewer constructed two
states those bullets mis-describe. The orchestrator settled that contradiction by reading the cited
lines: both constructions are concrete, and the bullets do overstate (F1, F2 below). No reviewer
found a code defect in the four high-blast-radius functions.

## Verification run

Both reviewers, macOS `/bin/bash` 3.2.57 (the floor), every drive through `temp_root.sh --offline`:

- `bash -n bin/uv-manager` → rc 0 (both).
- `.agents/factory/bin/lint.sh` → all checks pass: shellcheck via uvx, symlinks, version
  single-source, skill injections (both).
- R1: planted lock with a reaped owner pid and 2020 timestamps, `UVM_LOCK_TIMEOUT=3` → rc 0, plant
  standing, owner byte-identical, no break line; same with no `owner` file. `main`: "breaking …
  abandoned by a dead process" / "stale (…s old)", plant removed (both).
- R2/R3: live holder released at 33 s → exactly one notice carrying the owner line; released at 8 s
  → none; never released, timeout 3 → rc 0 in 3 s, fixture version, `current → versions/9.9.9`, plant
  intact. `main`: silent / rc 1 `timed out after 3s` (both).
- R4 (a): `mv` shims landing a rival before and during the rename → clean `versions/9.9.9 = [uv uvx]`,
  rc 0. `main`: nested `.incoming.*`, and on the during-rename case rc 1 with `current` missing.
- R4 (b), R14, R15: `tests/lock-race.sh` held 64×10 → 640/640 rc 0, `bad_trees=0/10`, plant intact
  10/10; control 32×2 and 128×5 → one installer per burst; a mixed held/pinned/`--timeout 0` race of
  640 ranks → all correct. Red against a guardless copy of the branch (`nested_staging` 11–34,
  `bad_trees` 6/10 and 9/10) and against the committed pre-guard build `1b7ee2a` (`bad_trees` 5/5).
- R5/R6: a scratch-only non-provisioning stub calling `uvm_acquire_lock fail <pred>` → rc 1 in 3 s
  naming the owner, critical section not run; predicate flipped true at 2 s → returns at 2 s holding
  nothing. A missing predicate → rc 1.
- R7/R9: GOAL's censuses → 0 hits (`main` 25 and 37); `UVM_LOCK_STALE=1` and `=abc` → rc 0.
- R8: doctor WARNs with the owner line, rc 0; `uvm clean lock` dry run keeps it; `--yes` removes the
  lock and leaves the tree selectable. `main`: lock not mentioned; `clean lock` refused.
- R10/R11: failing `mv` → rc 1 with `cannot publish uv 9.9.9 into …: mv: …`, no staging copy, no
  lock; the seed's `mkdir` shim → errno line plus `cannot record ownership`, no lock.
- R12: 16 pinned ranks with the `ln` shim, warm and cold → 16/16 print 6.6.6 (`main` 15/16 wrong);
  an installer delivering another version → 16/16 rc 1 `uv 6.6.6 is not installed after provisioning
  (the installer delivered …)`, nothing on stdout; `uvm install 6.6.6` and `uv self update 6.6.6` ×8–16
  → all 6.6.6 (`main` 7/8 and 15/16 wrong); `lock-race --pin 6.6.6` → 256–320/256–320 correct.
- Hot path: 200 warm calls per arm, twice → no measurable difference from `main`, pinned or not.
- Hostile `$(...)` in a planted owner line → printed literally by doctor, never executed.

## Requirement → evidence matrix

| R-ID | Implemented by | Verified how | Status |
|------|----------------|--------------|--------|
| R1 | `uvm_acquire_lock` (no break path) | Reaped-owner and ownerless plants survive; `main` breaks both | ✅ |
| R2 | `uvm_acquire_lock` notice at min(30, timeout) | One line at 33 s, none at 8 s | ✅ |
| R3 | `uvm_acquire_lock proceed` | rc 0 at the timeout holding nothing, tree correct | ✅ |
| R4 | publish block in `uvm_install`; `uvm_point_current` `mv -T`/`mv -h` | (a) rival shims; (b) lock-race held/mixed; (c) cluster evidence below | ✅ |
| R5 | `uvm_acquire_lock` non-`proceed` timeout | Scratch stub: rc 1 naming owner, nothing run | ✅ |
| R6 | predicate argument, `(( $# >= 2 ))` | Stub with predicate false/true; one call site | ✅ |
| R7 | heartbeat, age and liveness code removed | Census 0; `UVM_LOCK_STALE` ignored | ✅ |
| R8 | `uvm doctor`, `uvm clean lock` | WARN with owner; dry run; `--yes` removes lock only | ✅ |
| R9 | help, README, AGENTS.md, invariants.md, conf example | Census 0 | ✅ |
| R10 | publish error path | `mv` deny shim: no staging, no lock, named error | ✅ |
| R11 | `uvm_lock` set before the owner write | `mkdir` shim: no lock left | ✅ |
| R12 | `uvm_install` selection block; `uvm_ensure_uv` | `ln` shim warm/cold, failure branch, operator spellings | ✅ |
| R13 | `uvm_install` single fall-through selection | By reading (GOAL: no command) | ✅ |
| R14 | unpinned path unchanged | lock-race control: one installer per burst | ✅ |
| R15 | `tests/lock-race.sh` re-pointed | Red on two pre-guard builds, green on HEAD; counters 0 | ✅ |

**R4 (c), cluster evidence.** Both blind reviewers took it on trust because the evidence lives under
`spec/`. The orchestrator read [`evidence/lustre.txt`](evidence/lustre.txt) and
[`evidence/gpfs.txt`](evidence/gpfs.txt), which hold only key=value counts, versions and scenario names,
nothing identifying. On a Lustre cluster (2 nodes, 128 ranks, bash 5.1) and a GPFS cluster (1 node, 64
ranks, bash 4.4), control, held and pin all report `progress=ok`, every `rc_hist` all zero, every
`stdout_hist` the wanted version, `bad_trees=0`, `plant_intact=8/8` under held and
`locks_left_standing=0`. Under held, every waiter proceeds at the timeout and installs
(`concurrent_installers` 1016/1024 and 504/512), and the tree is correct in every burst.

Unmapped changes (possible scope creep):
- The doctor WARN for stranded `versions/.incoming.*` and `versions/*/.incoming.*` staging copies.
  No R-ID asks for it. It was added deliberately at the plan gate, as the maintainer-side amendment
  to the plan's deviation 2, so a killed loser's copy is reported rather than left to
  `uvm clean arch`. It is advisory only, verified working, and **accepted**, not a finding.
- README "Disk accounting": "breaks down" → "gives the cost of each". Trivial.
- `tests/lock-race.sh` `--launch srun`, `--pin` and `--summary` serve R4 (c) and R12. `mv -h` in
  `uvm_point_current` is load-bearing for R4 on BSD/macOS: removing it gave 113/192 non-zero ranks.

Requirements taken on trust: cross-node `mkdir` atomicity; GNU and busybox `mv` semantics (no GNU
`mv` on the review host); bash 4/5 on the local drives (the cluster evidence ran 4.4 and 5.1). All
are declared in GOAL § *Verification limits*.

## Findings

### [LOW/CONFIRMED] F1 — The lock's signal-release prose promises more than the code can keep
- **Where:** `.agents/factory/invariants.md` §5 ("Released on `EXIT`, `INT` **and** `TERM`" and "sets
  `uvm_lock` the instant `mkdir` wins"); `AGENTS.md` (the same "the instant `mkdir` wins" sentence);
  code at `bin/uv-manager` `uvm_acquire_lock` (`while ! mkdir …`, then `uvm_lock="${lock}"`).
- **Failure scenario:** a `TERM` that lands after the winning `mkdir` creates the directory but
  before `uvm_lock` is assigned exits 143 with an ownerless lock left standing. Nothing breaks locks
  now, so it stands until a human clears it, and every cold provisioning call waits the full
  `UVM_LOCK_TIMEOUT` until then.
- **Evidence:** block reviewer, a `mkdir` shim that creates the lock and then sleeps 2 s, with
  `kill -TERM` sent after the shim has won → `rc=143 lock=LEAKED`. `main` gives the same.
- **Disposition:** the window is pre-existing (`main` assigns even later) and one `mkdir` call wide.
  The design accepts it: a leaked lock is reported by `uvm doctor` and cleared by `uvm clean lock`.
  The defect is the prose this diff wrote, which says the release is unconditional. Fix the wording
  to say so; no code change.
- **Touches:** §5; region `uvm_acquire_lock` (prose only).

### [LOW/CONFIRMED] F2 — The non-atomic `current` fallback's hazard is understated
- **Where:** `.agents/factory/invariants.md` §4 ("can nest a `.current.<pid>` link"); the comment in
  `uvm_point_current` ("A concurrent swap … nests tmp inside a version directory"); `AGENTS.md`
  ("a concurrent reader never observes a missing … `current`"), which is unqualified.
- **Failure scenario:** on an `mv` with neither `-T` nor `-h`, timed-out ranks proceeding at once
  each run `rm -f current; mv tmp current`, and a reader in between finds `current` missing.
- **Evidence:** block reviewer, 32 ranks behind a held plant, timeout 1, on a branch copy with
  `mv -h` removed so macOS takes the fallback → 14 rc 0, 14 rc 127 (`No such file or directory`),
  4 rc 1, and 11 `.current.*` links nested in `versions/9.9.9`. `lock-race.sh --bursts 5` on that
  copy → `bad_trees=5/5`. The same drive on HEAD → 32/32 rc 0, clean tree.
- **Disposition:** GNU and BSD `mv` never reach the fallback, so the shipped behaviour is correct
  on both. The prose must say the fallback can also leave `current` briefly missing, and the
  `AGENTS.md` guarantee must be scoped to `mv` with `-T` or `-h`. No code change.
- **Touches:** §4/§6 prose; region `uvm_point_current` (prose only).

### [PLAUSIBLE, outside every R-ID] F4 — `issues/test-harness.md` still specifies removed machinery
- **Where:** `issues/test-harness.md` R3d (a live holder "SHALL NOT be breakable as stale", an
  inverted `UVM_LOCK_TIMEOUT`/`UVM_LOCK_STALE` "SHALL be refused") and R7 (the heartbeat's fork budget).
- **Disposition:** seeds are not graded. Already slated for `/uvm-roadmap` at landing (R3d/R3e/R3f/R7
  go stale with this cycle). Not a block.

(The block reviewer's F3, the unmapped doctor staging WARN, is disposed of above as an accepted plan
amendment.)

## Human-gate triggers

- **Triggered by F1 and F2**, as CONFIRMED findings in `uvm_acquire_lock` and `uvm_point_current`.
  **Cleared by the foreman** under the maintainer's standing delegation for this effort, on
  2026-10-28. Grounds: both are prose-only, and the remediation changes no executable line. The F1
  window predates this diff and is the accepted failure mode, cleared by a human through
  `uvm clean lock`. The F2 path is unreachable with GNU or BSD `mv`. Cycle 2 re-verifies that the
  remediation diff contains no code change.

## Optional completeness sub-pass

Not run.

## Review cycle 2 — changes-requested (2026-10-28)

**Mode:** scoped to the remediation delta, at the orchestrator's choice. Range
`git diff 0e5bbf6..HEAD -- . ':(exclude)spec/'` at HEAD `581a2ac`. The graded surface is 3 files
(`.agents/factory/invariants.md`, `AGENTS.md`, `bin/uv-manager`); the delta is prose and comments,
so findings are scoped to the hunks. One fresh blind reviewer was told the lock and publish/select
R-IDs (R1, R4, R5, R11, R12) were graded in cycle 1, and was given no finding ids, severities or
verdict. It handed back a clean tree.

### Verification run

- **No executable change.** With comment-only lines stripped, `bin/uv-manager` at `0e5bbf6` and at
  HEAD is 732 lines each and `diff` rc 0. Every changed line is a comment. `/bin/bash -n` rc 0.
  `lint.sh` passes all checks.
- **Each changed claim, driven:**
  - Fallback reader poll: 14,823 of 114,865 polls find `current` missing. On the host's `mv -h`
    path: 0 of 83,301, and 40/40 selections land.
  - Acquire-window shim with TERM/INT: rc 143/130 and an ownerless lock standing. `uvm doctor` then
    gives `WARN … (owner: <none recorded>)`. The next call proceeds at the timeout. `uvm clean lock
    --yes` removes the lock and leaves `current` intact.
  - "Set on the statement after the winning `mkdir`": true by reading.
- **§12:** no banned words, spec ids or over-width lines in the added hunks. `--word-diff` shows the
  rewrapped paragraphs change only the intended words.

### Findings

#### [MEDIUM/CONFIRMED] C2-F1 — A signal during the release also leaves the lock standing
- **Where:** `.agents/factory/invariants.md` §5 (the release bullet); `AGENTS.md` (the lock
  paragraph); `uvm_unlock`.
- **Failure scenario:** `uvm_unlock` clears `uvm_lock` and only then runs `rm -f owner` and `rmdir`.
  An INT or TERM that lands during those commands is handled after the command returns. The trap's
  release is then a no-op, and the lock stays standing. Under process-group delivery it keeps its
  owner line. The new prose names only the acquire window as the accepted one.
- **Evidence:** an `rm` shim pausing on `*.install.lock/owner`, with TERM/INT sent to the wrapper
  pid, gives rc 143/130 and a standing lock with no entries; the wrapper exits 2.98 s after the
  signal, so the trap ran and did not die by default action. With `kill -TERM -<pgid>`: rc 143,
  lock standing with `owner`. Control with no signal: rc 0, lock absent. Control with a signal while
  `uvm_lock` is set (an `ln` shim in `uvm_point_current`): lock absent.
- **Orchestrator's ruling:** the code is right. Clearing `uvm_lock` first is what keeps a trap from
  ever removing a lock this process no longer holds. With the opposite order, a signal arriving
  after the `rmdir` would make the trap remove whatever lock the next caller had just created, which
  is the R1 defect this cycle removes. The window is the price of R1. The prose must state the
  guarantee and its cost as a principle rather than enumerate windows: the wrapper never removes a
  lock it does not hold, and so a signal at any point where the hold and the variable disagree (the
  acquire and the release) can leave the lock standing for a human.

#### [LOW/CONFIRMED] C2-F2 — The acquire window opens before `mkdir(2)`, not after it
- **Where:** same paragraphs; the comment above `uvm_lock="${lock}"`.
- **Failure scenario:** bash defers a trapped signal until the foreground command returns. A signal
  that reaches only the shell while the winning `mkdir` command is still running is handled after
  `mkdir` has created the lock, so the lock is left ownerless.
- **Evidence:** a `mkdir` shim pausing before the real `mkdir`, with TERM/INT sent to the wrapper
  pid, gives rc 143/130 and an empty lock standing. Process-group control: no lock, because the
  child dies first.
- **Ruling:** folded into the C2-F1 rewrite. Signals are handled per command, so "after the winning
  `mkdir`" should read "around".

#### [LOW/CONFIRMED] C2-F3 — The fallback's worst consequence is omitted
- **Where:** `invariants.md` §4; `AGENTS.md` (the `current` paragraph); `uvm_point_current`'s
  fallback comment.
- **Failure scenario:** with an `mv` lacking both `-T` and `-h`, two concurrent pinned calls (6.6.6
  and 7.7.7) race the non-atomic replace. The 7.7.7 call exits 0 printing `uv 6.6.6`, and a
  `.current.<pid>` link to 7.7.7 is left nested in `versions/6.6.6`. So under the fallback a pin is
  not authoritative and a success can exec another version. The prose lists only a missing `current`
  and the nested link.
- **Evidence:** an `mv` shim rejecting `-T`/`-h`, then pausing 2 s before a plain `mv`. Control on
  the host `mv -h` path: the 7.7.7 call prints 7.7.7, with no nesting and no missing polls.
- **Ruling:** the behaviour predates the branch, and the reviewer found no supported host whose `mv`
  lacks both flags. Prose fix: name it, and scope "a pin is authoritative" and "every success has
  selected" to `mv` with `-T` or `-h`.

### Human-gate triggers

- **Triggered by C2-F1, C2-F2 and C2-F3** (`uvm_acquire_lock`, `uvm_unlock`, `uvm_point_current`).
  **Cleared by the foreman** under the maintainer's standing delegation for this effort,
  2026-10-28. The grounds are that all three are prose-only and the remediation again changes no
  executable line. The cycle-3 review re-verifies that.
- **Convergence note:** the next cycle is the last that may request changes. Cycle 2's findings are
  all omissions in the same sentences cycle 1 corrected. The remediation is therefore told to state
  each guarantee and its cost as a principle, not to add another enumerated case.

## Review cycle 3 — changes-requested (2026-10-28)

**Mode:** scoped to the cycle-2 remediation delta. The range is
`git diff 581a2ac..HEAD -- . ':(exclude)spec/'` at HEAD `022731e`. The graded surface is the same
3 files, prose and comments only, with findings scoped to the hunks plus any contradiction they
expose. One fresh blind reviewer was told the same graded R-ID list and given no prior findings or
verdict. It handed back a clean tree.

### Verification run

- **No executable change.** With comment-only lines stripped, `bin/uv-manager` at `581a2ac` and at
  HEAD is 732 lines each and `diff` gives rc 0. `bash -n` gives rc 0, and `lint.sh` passes all
  checks.
- **Signal matrix (D5).** TERM and INT were delivered shell-only and to the process group, at the
  lock's create, owner-write and rmdir steps:
  - Every residue matches the new prose: empty, carrying its owner line, or gone.
  - The holding control is released under both deliveries.
  - `uvm doctor` reports either residue as a WARN, and `uvm clean lock --yes` removes it with
    `current` intact.
- **Selection.** "A success return has selected the requested version" holds under `mv -h` (the
  call's swap lands). Under the fallback it fails as the hunks now say.

### Findings

#### [MEDIUM/CONFIRMED] C3-F1 — The pin exception names the `mv` path, but the cause is conflicting pins
- **Where:** the pin headlines (`invariants.md` §4, `AGENTS.md`) and their "only with an `mv` that
  takes `-T` or `-h`" qualifiers. Also the `uvm_point_current` comment, and the unchanged "A pin is
  honoured" comment in `bin/uv-manager`.
- **Failure scenario:** two concurrent calls on one root pinned to *different* versions each select
  their own, and the later swap wins. The earlier call then execs the later call's version at rc 0.
  This happens on the atomic `mv -h` path too.
- **Evidence:**
  - Shimmed (D3): A, pinned 6.6.6, is paused after its rename. B, pinned 9.9.9, runs. A then
    prints 9.9.9 at rc 0.
  - No shims (D4): 8-rank bursts alternating the two pins, 40 bursts, run twice. 13/320 and 19/320
    ranks printed the other version at rc 0. No rank failed and no link nested.
  - Same-pin control (D4c): 0/320 wrong.
- **Character:** pre-existing behaviour, outside the range. `current` is one per root, and a pin
  is per process. R12's same-pin case (every `srun` rank sharing one pin) is unaffected. The defect
  is the new qualifier, which names the `mv` path as the condition. The condition is two concurrent
  calls on one root that pin different versions.

#### [LOW/CONFIRMED] C3-F2 — The fallback's "execs the other version" needs a different-version swap
- **Where:** `invariants.md` §4's fallback sentence; the `uvm_point_current` fallback comment.
- **Evidence (D2):** a fallback shim with the same-pin rival leaves the link nested and `current`
  correct, and both calls print 6.6.6. `AGENTS.md`'s "another version directory" is already
  qualified.

#### [LOW/CONFIRMED] C3-F3 — The accepted failure mode's sentence is inexact
- **Where:** the new release paragraphs in `invariants.md` §5 and `AGENTS.md`.
- **What is wrong:**
  - "Nothing in the wrapper removes it: … `uvm clean lock` removes it" contradicts itself, since
    `uvm clean lock` is the wrapper.
  - "Every cold provisioning call … waits the full `UVM_LOCK_TIMEOUT`" is not the boundary. In D7, a
    cold call returned after 4.1 s of a 6 s timeout once another call published. In D8, a forced
    `uvm install` on a warm tree waited the full timeout.
  - The true boundary: a call whose request is unsatisfied waits until it is satisfied or the
    timeout passes. Unchanged lines saying *each* call pays have the same imprecision.

### Human-gate triggers

- **Triggered by C3-F1 and C3-F2** (`uvm_point_current`, `uvm_install` comments). The foreman
  does not clear this one: it is cycle 3.

### Bounded loop: handed to the maintainer

This is the last cycle that may set `changes-requested`. It is not routed to `/uvm-build`.

- **Standing findings:** C3-F1, C3-F2 and C3-F3. All are prose. None is a code defect.
- **Remediation delta since the cycle-1 review:** `0e5bbf6..022731e`, outside `spec/`. It changes
  3 files, comments and docs only, and every executable line is unchanged.
- **Convergence:** across all three cycles no reviewer found a code defect, and R1–R15 stayed
  green under every drive. Each cycle found a narrower omission in the same few sentences about
  signal windows and `current` selection.
- **The ship / abandon / rescope choice** goes to the maintainer.

## Maintainer override — approved after the bound (2026-10-28)

**The maintainer chose "ship with a final wording fix"** from the ship / abandon / rescope choice
the bounded loop handed over. The wording is verified by the foreman, with no fourth blind cycle.

**Remediation:** `3d17c6b` (parent `91a8a23`). It covers C3-F1, C3-F2 and C3-F3 in
`invariants.md` §4/§5, `AGENTS.md`, comments in `bin/uv-manager`, and the same claims in
`README.md` and `etc/uv-manager.conf.example`.

**What the foreman verified:**
- **Code unchanged.** With comment-only lines stripped, `bin/uv-manager` at HEAD is byte-identical
  (`cmp`) to `0e5bbf6`, the commit both cycle-1 reviewers graded. Every executable line shipped is
  one the debate pass drove. `bash -n` and `lint.sh` pass. All five phase gates are green after the
  last edit.
- **Wording matches the cycle-3 measurements.** Each changed sentence was read against them:
  - A pin is authoritative over which version a call selects. It is authoritative over `current`
    while no concurrent call on the same tree selects a different version. Differently-pinned
    concurrent calls race for `current` and the last swap wins. Calls sharing one pin (the ranks of
    an `srun` job) agree.
  - The fallback's wrong-version outcome is conditioned on a different-version swap. The nested link
    and the briefly missing `current` happen either way.
  - A standing lock is removed by no call on its own. `uvm doctor` reports it and a human runs
    `uvm clean lock`. Until then, a provisioning call whose request is not yet satisfied waits until
    it is or until the timeout passes.

**Deferred, not a defect of this branch:** pins that hold against a concurrent call with a different
pin on the same tree would need a code change (a pinned call exec'ing its own version's path rather
than `current`). That was offered as the rescope option and not taken.

**Verdict:** approved at `3d17c6b`, on the maintainer's override.
