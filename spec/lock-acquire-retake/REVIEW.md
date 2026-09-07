# REVIEW — A rank robbed of its fresh lock retakes it

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** d4ef8236d9559b427b3adab264e3cc463f698193  ·  **Base:** `main`  ·  **Date:** 2026-09-06
- **Verdict:** approved
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md`
- **Mode:** `debate` — two independent blind reviewers, one briefed to argue ship and one to argue
  block, reconciled by the orchestrator against its own measurements. Chosen because the diff sits in
  `uvm_acquire_lock`, which `AGENTS.md` names the highest-blast-radius region in the repository.

The two reviewers returned opposite verdicts. The disagreement was settled by measurement, not by
preferring one account; see § *Reconciliation*.

## Verification run

Commands actually executed and their outcomes. This is the spine of the review.

- `bash -n bin/uv-manager` → clean.
- `.agents/factory/bin/lint.sh` → all checks passed, including `shellcheck` and `bash -n` under
  **3.2.57**, the portability floor. Every drive below ran on that bash.
- `temp_root.sh --offline --arch testarch` cold start → `rc=0`, stdout exactly `uv 9.9.9 (fixture)`,
  `current -> versions/9.9.9`, `versions/` holds only `9.9.9`, no lock left behind.
- `temp_root.sh --offline --arch aarch64 uvm status` → every exported path under `…/aarch64/`; the
  trampoline dir stays architecture-neutral.
- `/bin/sh -c "git grep -n flock -- bin/uv-manager"` → one match, `bin/uv-manager:172`, inside the
  rationale comment.

**A/B against `main`.** Every behavioral drive was run twice: once against the working tree and once
against `git show main:bin/uv-manager`, staged with its own `uv`/`uvx`/`uvm` symlinks and put first on
`PATH` inside the sandbox. "Changed" and "unchanged" below are measured, not asserted.

- **R1, rob once** — a `mkdir` shim first on `PATH` creates the lock directory and `rmdir`s it once,
  so the wrapper's own `owner` write opens `ENOENT`.
  HEAD: `rc=0`, stdout `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`, no lock left.
  MAIN: `rc=1`, stdout empty, no `current` — the contract's declared red state, reproduced.
- **R2, `EACCES`** — the shim `chmod 500`s the lock directory instead of removing it.
  HEAD and MAIN identical: `rc=1`, stderr carries `…/owner: Permission denied` **then**
  `uv-manager: cannot record ownership of the provisioning lock at …`. The errno survives.
- **R3, robbed on every attempt** — the shim removes the directory each time.
  `rc=1`, elapsed **0s**, exactly three `No such file or directory` diagnostics, then
  `cannot hold the provisioning lock … won it 3 times …`. Bounded, no spin, no lock left.
- **Contention, 64-way with a planted dead-holder lock** — the regime `GOAL.md` records as producing
  robberies. `$UVM_ROOT/testarch/.install.lock` holds an `owner` line naming this host and an exited
  pid, so every rank judges it dead and races to break it.
  - HEAD, 60 rounds × 64 ranks = **3840 ranks: 0 failures.**
  - MAIN, 12 rounds × 64 ranks = **768 ranks: 1 failure**, `rc=1` with empty stdout and exactly the
    signature `GOAL.md` names — `line 462: …/owner: No such file or directory` followed by
    `cannot record ownership`. This is what establishes the construction actually reaches the race;
    without it HEAD's zero would prove nothing.
- **Branch instrumentation** — an untracked copy of HEAD's script with a one-line probe in each of the
  two post-`mkdir` branches, run over the same 64-way contention: 30 rounds × 64 = **1920 ranks, 3
  real robberies, 3 retaken, 0 routed to the fatal branch, 0 rank failures.** This measures the
  discriminator directly rather than inferring it from exit codes.

HEAD totals across both burst sets: **5760 ranks, 0 failures.**

## Requirement → evidence matrix

| R-ID | Implemented by | Verified how (command + post-condition) | Status |
|------|----------------|------------------------------------------|--------|
| R1 | `uvm_acquire_lock`, `bin/uv-manager:366-374` | Rob-once shim A/B: HEAD `rc=0` + `current -> versions/9.9.9`; MAIN `rc=1` + empty stdout. Contention: 3 of 3 robberies retaken under instrumentation, 0 of 5760 ranks lost. | ✅ (narrow residual — see F1) |
| R2 | `bin/uv-manager:362-365` | `chmod 500` shim: `rc=1`, `Permission denied` then `cannot record ownership`. Identical on MAIN. | ✅ |
| R3 | literal `3` at `bin/uv-manager:374`; no new variable in the diff | Rob-every-attempt shim, `UVM_LOCK_TIMEOUT=5`: `rc=1` at **0s** after exactly 3 robberies. `robbed` never resets and adds no `sleep`. | ✅ |
| R4 | no change to the `absent`/`waited`/`broke` blocks | Both reviewers ran three A/B drives each, independently: fresh foreign lock times out at exactly `UVM_LOCK_TIMEOUT`; a denied break emits **exactly one** break note across the whole wait; the absent-lock retry dies after exactly three refused `mkdir`s with the permissions/quota message. HEAD ≡ MAIN on message, exit code, note count and timing. | ✅ |
| R5 | no `note` on the retake path | Rob-once drive: stdout is the fixture version and nothing else; wrapper stderr is **one** line, `installing uv (latest) for testarch` — the same single line the un-robbed baseline emits. The retake contributes nothing. | ✅ |
| R6 | untouched | Cold start leaves `current -> versions/9.9.9`, `versions/` clean, no lock. Concurrent bursts (8-way, 16-way, 64-way) produce exactly one installer run. `flock` matches only the rationale comment. | ✅ |

Unmapped changes (possible scope creep): **none.** `bin/uv-manager` maps to R1/R2/R3/R5; `AGENTS.md`
and `.agents/factory/invariants.md` §5 to the same-commit rule for a narrowed invariant; `ROADMAP.md`
and `issues/lock-acquire-retake.md` (`status: adopted:…`, plus a line-reference correction from `:345`
to `:346` that both reviewers verified against `main`) to the shaping step; `issues/test-harness.md`
R3e to the non-goal that lands the deferred regression test there. The `bin/uv-manager` diff is net
**+22 lines**, all inside `uvm_acquire_lock`, roughly two-thirds comment.

Requirements taken on trust (cannot be observed from the sandbox): **bash 5 behavior** — only bash
3.2.57 is present on this machine. The new constructs are form-identical to the `absent` block three
lines below, which ships today. **`mkdir` atomicity on Lustre, GPFS and NFS** — declared out of scope
by R6 and by `GOAL.md` § *Verification limit*, carried forward from `lock-ownership-and-hold-time`.
Both were declared up front in `GOAL.md`; neither was downgraded to trust during this review.

## Findings

Severity: **CRITICAL** (any `invariants.md` §1–§11 violation is auto-CRITICAL) · **HIGH** ·
**MEDIUM** · **LOW**. Verdict: **CONFIRMED** (reproduced) versus **PLAUSIBLE** (suspected, needs human
triage). Only CONFIRMED findings auto-loop to `uvm-build`.

**No CONFIRMED findings.** Two PLAUSIBLE findings are recorded for human triage; neither auto-loops.

### [HIGH/PLAUSIBLE] F1 — the retake discriminates on directory presence, not on the errno

- **Where:** `bin/uv-manager:362` (`uvm_acquire_lock`)
- **Failure scenario:** R1's WHEN clause is "the `owner` write fails **because the lock directory is
  no longer there**". The code does not test that. It tests `[[ -d "${lock}" ]]` one builtin *after*
  the failed redirect. If another rank wins `mkdir` in the gap between the two, the robbed winner sees
  a directory standing, takes the fatal branch, and exits 1 with empty stdout — the shape R1 exists to
  remove. The gap is a single builtin with no forks, so the second race is orders of magnitude
  narrower than the robbery it rides on.
- **Evidence, and its limit:** the branch selection is confirmed. A shim that makes `owner` a dangling
  symlink produces an `ENOENT` write with the directory standing, and the wrapper dies: `rc=1`, empty
  stdout, `No such file or directory` then `cannot record ownership`. **That construction is outside
  R1's WHEN clause** — the write failed because the symlink target was missing, not because the lock
  directory was gone — so it demonstrates the discriminator's shape, not a contract breach. The
  in-contract case was not reproduced: 5760 HEAD ranks in the 64-way dead-holder regime produced 0
  failures, and branch instrumentation over 1920 of them caught 3 real robberies, all 3 retaken, none
  routed to the fatal branch.
- **Competing explanation not ruled out:** that the residual rate is zero in practice rather than
  merely small. A negative result over 5760 ranks bounds it low but cannot establish it.
- **Touches:** R1; `uvm_acquire_lock` (high-blast-radius). `AGENTS.md:157` and
  `.agents/factory/invariants.md:83-87` state "a directory still standing means the write itself was
  refused" — true of every case measured here, and the code matches the prose, so this is not a
  code-versus-invariant violation. If a future cycle narrows the discriminator to the errno, both
  sentences move with it.

### [MEDIUM/PLAUSIBLE] F2 — the fatal branch's `rmdir` is unqualified by ownership

- **Where:** `bin/uv-manager:363` (`uvm_acquire_lock`)
- **Failure scenario:** on the F1 branch the code runs `rmdir "${lock}"` on a directory that, in that
  scenario, was created by another rank — removal by path, the shape `invariants.md` §5 forbids for
  `uvm_unlock`. It succeeds only while the new winner has not yet written its `owner` file.
- **Evidence:** not reproduced. `lock present: no` and `current -> versions/9.9.9` held in every one
  of the ~90 HEAD contention rounds; no cascade was observed.
- **Pre-existing, not a regression.** `main` runs `rmdir` unconditionally on *every* write failure, so
  HEAD performs strictly fewer such removals. Recorded because F1's remedy, if taken, has to decide
  what this branch does.

### Dropped after investigation

Recorded so the next cycle does not re-derive them.

- **The successful retake prints a raw `bin/uv: line 351: …: No such file or directory`.** Both
  reviewers raised it; both dropped it. `GOAL.md` § *Non-goals* names this exact line, states that the
  obvious suppression is measured-unsafe under `set -euo pipefail`, and scopes R5 to "a *successful*
  retake adds nothing" — which the measurement confirms (one wrapper stderr line, identical to the
  un-robbed baseline). Confirmed independently that a leading `2>/dev/null` would blind R2's fatal
  path as well: `bash -c 'printf x 2>/dev/null > /nonexistent/dir/f'` prints nothing.
- **The `mkdir`-coupling caveat is lost when `/uvm-roadmap` deletes the seed.** The premise is false:
  `spec/lock-acquire-retake/` is retained on merge and its `GOAL.md` § *Verification limit* carries
  the caveat, and the new `issues/test-harness.md` R3e names that `GOAL.md`. The obligation to put it
  "beside the gate" attaches to whoever lands the gate, which is the `test-harness` cycle, not this
  one.
- **The restructured `while :; do … done` changed control flow for non-robbed paths.** Refuted by
  R4's six A/B drives: messages, exit codes, note counts and timings are indistinguishable from
  `main`.
- **`robbed` extends the timeout accounting.** Refuted: bounded at 3, never resets, no `sleep`;
  a robbery followed by real contention still exits at the configured timeout.
- **`set -euo pipefail` aborts on the failed redirect, or on a false `(( robbed >= 3 ))`.** Refuted by
  execution — the wrapper reaches the branch and continues in every drive, on bash 3.2.
- **Hot-path cost.** `uvm_ensure_uv` short-circuits on `uvm_have` before `uvm_install`, so the warm
  path never enters `uvm_acquire_lock`. The added code is provisioning-only.

## Reconciliation

The ship reviewer returned clean; the block reviewer returned F1 as HIGH/CONFIRMED on the strength of
a 64-way burst reporting 4 failures in 6080 HEAD ranks against 3 in 1280 MAIN ranks.

Three things moved F1 from CONFIRMED to PLAUSIBLE, and none of them is a preference between reviewers:

1. **The ship reviewer's contrary evidence does not bear on it.** Its 8-way burst ran with no planted
   lock — the path `GOAL.md` itself records at 0 of 2304. A clean result there is not evidence about
   the robbery regime, so the two reports were never actually in contact.
2. **The orchestrator's own measurement contradicts the rate.** 5760 HEAD ranks in the same
   dead-holder regime produced 0 failures, on a construction proven live by 1 failure in 768 MAIN
   ranks carrying the exact documented signature. Branch instrumentation then measured the
   discriminator directly: 3 robberies, 3 retakes, 0 fatal-branch entries.
3. **The reported HEAD rate is mechanically implausible and has a known confound.** The
   misclassification needs a second race inside a fork-free window between a failed redirect and the
   next builtin; a rate only 3.5× below the robbery rate itself would require that window to be
   comparable to the 0.10 ms `mkdir`-to-`owner` window, which it is not. The ship reviewer separately
   reported that both agents were handed the same scratchpad directory and that its `mkdir` shim was
   overwritten mid-pass by the other's, which is a live route for some "HEAD" rounds to have executed
   `main`'s script. That is a harness defect, recorded in `META.md` as F1.

What survives is real and worth keeping: the discriminator is presence-based where R1 is written in
terms of the errno, and the residual window is narrow rather than closed. That is a genuine gap in R1,
bounded below anything this sandbox can measure, and it is the human's call whether to seed it.

## Human-gate triggers

The gate fires on a **CONFIRMED** finding touching a high-blast-radius region or a §1/§2/§6 invariant.
There are no CONFIRMED findings, so it is **not triggered** and no sign-off is required by the rubric.

Recorded anyway, because the rubric's trigger condition is not the same as the maintainer's interest:
F1 and F2 are both PLAUSIBLE findings sitting in `uvm_acquire_lock`, and the debate variant produced a
genuine split on this function.

**Disposition, decided by the maintainer on 2026-09-07:** both are deferred to
[`issues/lock-owner-write-errno.md`](../../issues/lock-owner-write-errno.md), with a `ROADMAP.md`
entry sequenced below `lock-break-instance-identity` — a residual rate this low is not observable from
a single-process construction, so `test-harness` R3d comes first. The seed carries the measured bound,
the dangling-symlink construction and its out-of-contract caveat, the `2>"$errfile"` sketch that avoids
the `set -euo pipefail` landmine, and the note that `AGENTS.md:157` and `invariants.md:83-87` move with
any fix. F2 travels in the same seed because whatever fixes the classifier decides what that branch
does.

The seed and its `ROADMAP.md` entry are committed **with** these artifacts, and
`review.last_reviewed_commit` is pinned to that commit rather than to the build head — both files live
outside `spec/`, so an approval pinned to `d4ef823` would make `uvm-publish`'s staleness gate read the
deferral as post-review drift and stop.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run. Invoke `/uvm-review completeness` if the did-we-ship-every-phase question is wanted.
