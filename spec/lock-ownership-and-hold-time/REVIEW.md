# REVIEW — The provisioning lock can be released by a process that does not hold it

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 34742e9  ·  **Base:** main  ·  **Date:** 2026-08-15
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md`
- **Mode:** full blind pass over the spec-excluded diff, **`debate` variant** — two independent fresh
  reviewers, one instructed to argue ship and one to argue block, reconciled here. Chosen by the
  maintainer because the diff sits in `uvm_acquire_lock`/`uvm_unlock` and the dispatch tail.

Contract note: `GOAL.md` moved after its shaping commit — R4 and R6's *Checked by* clauses were
repaired during planning, R7 and the base-10 requirement were added by `5fc4196`, and R8 by
`50b8cec`. Each carries a dated Q/A in § *Clarifications*. The maintainer confirmed the current
eight-criterion contract as the graded surface before delegation.

## Verification run

Both reviewers ran the gates and drove the script only through `.agents/factory/bin/temp_root.sh`.
Neither opened a file under `spec/`; both excluded it from every repository-wide search. Both
returned a clean tree, verified again here.

- `bash -n bin/uv-manager` → pass. `/bin/bash` on this machine is 3.2.57, so the portability floor is
  the shell every drive below ran under.
- `.agents/factory/bin/lint.sh` → pass.
- `git grep -n 'exec "\${real_' bin/uv-manager` → exactly four matches, `:808 :1145 :1147 :1151`.
- `git grep -n flock bin/uv-manager` → one match, the rationale comment at `:172`.
- `temp_root.sh --offline uv --version` → `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`.
- Ownership matrix across seven `owner` states, each with the fixture rewriting the file mid-hold.
- Hold-versus-stale drives at `UVM_LOCK_STALE` below the hold duration, sampling `owner` mtime
  against the directory's.
- Fourteen knob spellings, including `0600`, `0800`, `08`, `-1`, `1e3`, `+5`, whitespace, embedded
  newline and non-numeric.
- Injected-lock drives into the dispatch tail and into `uvm_self_update`, plus `bash -x` traces and
  warm timings.
- Concurrency: 2560 cold ranks at 64-way and a further 4608 at 128- and 256-way on this branch;
  1280 ranks at 64-way against `main` as the control.
- Signal paths (INT, TERM, `kill -9` of a holder), unwritable architecture directory, and adversarial
  `mkdir`/`rmdir` churn against the retry bound.

`main` was driven as a control throughout, from a copy outside the repository. Every criterion's
stated red state was reproduced on `main` and the corresponding green measured here — the branch is
not merely passing gates that pass on both sides.

## Requirement → evidence matrix

| R-ID | Implemented by | Verified how (command + post-condition) | Status |
|------|----------------|------------------------------------------|--------|
| R1 | `uvm_unlock` (`:222-247`) | Seven owner states driven. `match` → `lockdir=GONE`; `absent`, `empty`, `truncated`, `unreadable (000)`, `foreign`, `same-pid-different-nonce`, `dir-instead-of-file` → `lockdir=PRESENT`, owner byte-intact, one `no longer ours` note, user `rc=0`. Identical drive on `main` → `lock dir: GONE, owner: NONE`. | ✅ |
| R2 | refresher (`:228-247`, `:276`), `uvm_age` | 25–30 s hold with `STALE=10`: waiter printed `breaking` **0** times; `owner` mtime advanced every 1 s while the **directory** mtime stayed frozen at acquisition. `main` on the same state: `breaking stale provisioning lock (12s old)` and concurrent provisioning. Leash: after `kill -9` of the holder, owner age resumed growing and the next waiter broke it. Immortal-lock guard: a foreign `owner` planted mid-hold was never restamped over ten samples. | ✅ |
| R3 | numeric guard in `uvm_acquire_lock` | `0600/500`, `5/1`, `600/600` refused rc=1 naming both variables **in the base-10 seconds judged**; live lock still `PRESENT`. `500/0600` accepted, `current -> versions/9.9.9`. `STALE=0800` contended → zero `value too great for base` (`main` emitted it and **accepted**). `abc` → branch rc=1; **`main` rc=0 with `VER=[]`**, the "empty and true" red reproduced verbatim. `uvm help` and `uvm --version` still answer rc=0 with a broken knob and no state root. | ✅ |
| R4 | `uvm_unlock` call before each `exec` | Census returns exactly 4; the only other `exec` is inside the generated `/bin/sh` trampoline body. Lock injected into the dispatch tail → branch `RELEASED`, `main` `LEAKED`. Injected into `uvm_self_update`'s exec → `RELEASED`, version printed. Cost: `[[ -n "${uvm_lock}" ]] || return 0` is the first statement, ahead of every `local` — trace shows two builtins and **no fork**; warm timings 8.1 ms branch vs 7.9 ms main, inside noise. | ✅ |
| R5 | timeout message | stderr carries `holder, from the lock's owner file: host=… pid=… nonce=…` and `A pid recorded there is on that host, not this one.` Bare `rmdir` → `Directory not empty`, rc=1, lock survives; the advised `rm -f '<lock>/owner' && rmdir '<lock>'` → rc=0, lock gone. Break notes carry the same owner line. | ✅ |
| R6 | unchanged `mkdir` discipline | Fixture version and `current -> versions/9.9.9` intact; `flock` only in the `:172` comment. Cold provisioning 0.402 s; 40 warm invocations match `main`. `uv tool` rc **7** propagated, `uv python` rc 0. `VER=$(uv --version)` → `[uv 9.9.9 (fixture)]`, stdout clean including when the lock turns foreign mid-hold. | ✅ |
| R7 | break-denied accounting (`:370-389`) | Lock holding a stray entry, aged past `STALE`: branch `rc=1`, elapsed = the timeout, **6** stderr lines, **1** break note, **1** timeout message. `main`: 1257 break notes / never terminated, killed by the harness — red reproduced on both reviewers' runs. | ✅ |
| R8 | `absent` counter, bound 3 (`:322-326`) | Branch **2560 ranks at 64-way: 0 non-zero, 0 `check permissions and quota`, 2560/2560 correct stdout**; a further 4608 at 128- and 256-way, all clean. `main` control: **23–24 of 1280 (1.8–1.9%)** died with that message. Real fault (unwritable arch dir) still named, rc=1, **0 s** not `UVM_LOCK_TIMEOUT`. Bound headroom: 27 absence events over 1280 ranks, every one at `absent=1`. Monotonic count survives 20 s of adversarial churn with 8 waiters, 8/8 rc=0. | ✅ |

Unmapped changes (possible scope creep): **none**. `issues/purge-tree-repair.md` R11 and
`issues/test-harness.md` R3d are required by § *Non-goals* to land in this same commit;
`issues/invariant-audit-gaps.md` and its `ROADMAP.md` entry are the deferral record the rubric
expects outside `spec/`, and its three claims are genuinely pre-existing on `main`. Same-commit rule
satisfied — `uvm_help`, `README.md`, `etc/uv-manager.conf.example`, `AGENTS.md` and `invariants.md`
all moved; `share/modulefiles/uv/main.lua` was owed nothing.

Requirements taken on trust: **`mkdir` atomicity on Lustre, GPFS and NFS** — declared up front in
`GOAL.md` § *Verification limit*; a `mktemp -d` on APFS cannot exercise it. Also unobservable: bash
4/5 behavior, since this machine carries only 3.2. Nothing was silently downgraded to trust during
review.

## Findings

Severity: **CRITICAL** (any `invariants.md` §1–§11 violation is auto-CRITICAL) · **HIGH** ·
**MEDIUM** · **LOW**. Verdict: **CONFIRMED** (reproduced) versus **PLAUSIBLE** (needs human triage).

### [CRITICAL/CONFIRMED] F1 — a recycled pid makes an abandoned lock permanently unbreakable

- **Where:** `bin/uv-manager:356-368` (`uvm_acquire_lock`)
- **Failure scenario:** the forfeiture decision is `if [[ -n "${pid}" ]] && ! kill -0 "${pid}"` /
  `elif [[ -z "${pid}" ]] && … (( age > lock_stale ))`. The age branch is gated on *no pid having
  been parsed*, so whenever a recorded pid parses **and answers `kill -0`**, `UVM_LOCK_STALE` is
  never consulted. A holder killed without running its traps — SIGKILL, OOM, `scancel -9`, node
  failure, the exact set `etc/uv-manager.conf.example` says the knob exists to cover — leaves an
  `owner` line naming `host=<this node> pid=P`. Any later same-user process occupying pid P makes the
  lock unbreakable for that process's lifetime. `kill -0` cannot distinguish the original holder from
  a reuse collision, and the nonce added at `:276` to defend against reuse is not consulted by the
  breaker. Every `uv` invocation for that user on that architecture then blocks the full
  `UVM_LOCK_TIMEOUT` (180 s at defaults) and fails, indefinitely.
- **Evidence:** both reviewers reproduced it independently with an A/B whose only variable is whether
  pid P is alive. With `owner` backdated to 2020 against `UVM_LOCK_STALE=10`:
  branch `rc=1 elapsed=4s`, `timed out after 4s`, `lock: STILL-PRESENT`; `main` on the identical
  state `rc=0 elapsed=0s`, `breaking stale provisioning lock (208985278s old)`, `lock: BROKEN`. A
  lock 6.6 years past a 5-second threshold is refused a break here and broken in 1 s by `main`. On a
  cold tree the user-visible consequence was measured as three consecutive invocations at
  `rc=1 elapsed=4s` with `current symlink: NONE`, then `invocation4 rc=0 elapsed=0s` the instant the
  recycled pid exited — isolating pid liveness as the sole determinant.
- **Competing explanations ruled out:** *"R2 working as designed"* — the constructed state has no live
  holder, and §5's own sentence is "a holder on this host whose pid is gone loses its lock at once".
  *"A later iteration breaks it"* — the waiter re-probes each second for the whole timeout; three
  consecutive invocations were refused. *"EPERM reads as dead, so a foreign owner breaks it anyway"* —
  measured `kill -0 1 → rc=1`, but on an exclusively-allocated compute node essentially every pid
  belongs to the job's user. *"Too rare to matter"* — the code's own comment models pid wrap as
  sub-minute on a node spawning `uv run` in a loop.
- **Not executed:** the recycled pid arriving by natural reuse rather than by construction. The code
  path is identical either way — the waiter reads a number from a file and probes it.
- **Touches invariant / requirement:** §5 (*Liveness is consulted before age*), and the regression is
  against `main`'s behavior on identical state. Not an R-ID gap: R2 is met.
- **Reviewer dissent on severity.** The ship-stance reviewer rated this MEDIUM, on the grounds that
  the failure is loud, names the holder, prints a recovery command that works, self-heals when the
  colliding process exits, and needs a conjunction of a leaked lock and a pid collision. The
  block-stance reviewer rated it CRITICAL. Graded CRITICAL here because the rubric's severity table
  keys on kind rather than likelihood: an unbreakable lock is a leaked lock, and §5 asserts the
  property the code lacks. The disagreement is about reachability, not about the mechanism — both
  reproduced it.

### [HIGH/CONFIRMED] F2 — node identity comes from `${HOSTNAME}`, which is environment-inheritable

- **Where:** `bin/uv-manager:276` and `bin/uv-manager:344`
- **Failure scenario:** `main` wrote `host=$(uname -n)` and never read it back. The diff writes
  `host=${HOSTNAME}` and makes it load-bearing — `:344` decides whether the recorded pid may be
  probed locally. Bash keeps an inherited exported `HOSTNAME` verbatim. If two nodes present the same
  token, a waiter on node B probes a pid that is live on node A, finds it absent locally, and breaks
  a live remote holder's lock on its first iteration with no age accounting — the exact failure R1
  and R2 exist to prevent, reintroduced through the identity field.
- **Evidence:** `HOSTNAME=login00.spoofed bash -c 'echo $HOSTNAME; uname -n'` →
  `login00.spoofed` / the real name, so the inherited value survives; the wrapper then wrote
  `owner file: [host=cn0123 pid=41727 nonce=…]`. Differential on one lock, age 0 s,
  `UVM_LOCK_STALE=600`, holder alive at a pid absent on the waiter's node: without the collision
  `rc=1, 0 break(s)`, with it `rc=0, 1 break(s)`,
  `breaking provisioning lock abandoned by a dead process`, `lock now: BROKEN-AND-TAKEN`. The two
  runs differ only in `HOSTNAME`.
- **Competing explanation ruled out:** *"`HOSTNAME` is always the kernel hostname"* — refuted by
  measurement; containers set it in the environment and `sbatch --export=ALL`, which `AGENTS.md`
  treats as first-class, propagates anything exported.
- **Narrowing:** the **mechanism** is CONFIRMED. The **premise** — that a real site presents one
  `HOSTNAME` on two nodes — is not executed; neither reviewer could show a default configuration in
  which it holds. `temp_root.sh` does not scrub `HOSTNAME`, and neither `README.md` nor
  `etc/uv-manager.conf.example` records the dependency.
- **Touches invariant / requirement:** §5 (*Ownership, not path*), R1, R2.

### [HIGH/CONFIRMED] F3 — the revised standard asserts a safety property the code does not have

- **Where:** `.agents/factory/invariants.md:112`
- **Failure scenario:** §5 now reads "The probe covers `kill -0`'s residual pid-reuse gap". The probe
  *is* `kill -0`, on the same recorded pid, so it cannot discriminate reuse — it is what introduces
  the gap, and `elif [[ -z "${pid}" ]]` is what stops the age net from covering it. `AGENTS.md`'s
  parallel paragraph makes no such claim and is accurate, so the derived file has drifted from the
  ground truth it is required to track. A later `/uvm-review` grades against this sentence.
- **Evidence:** the sentence, read against the F1 reproduction above.
- **Touches invariant / requirement:** §12 (same-commit rule, `AGENTS.md` wins on drift). Remediated
  with F1 — whichever way F1 is repaired, this sentence has to state what the code then does.

### [LOW/CONFIRMED] F4 — an unvalidated `HOSTNAME` containing a newline leaks the holder's own lock

- **Where:** `bin/uv-manager:238-247` (secondary consequence of F2)
- **Failure scenario:** the owner record is line-oriented and `HOSTNAME` is written into it
  unvalidated, so a value containing a newline makes the holder fail to recognize its own lock.
- **Evidence:** with `HOSTNAME=$'cn01\nspill'` under `temp_root.sh --offline` →
  `provisioning lock is no longer ours, leaving it in place`, `rc=0`, `lock: PRESENT --LEAKED`,
  `owner: [host=cn01 / spill pid=53995 nonce=…]`.
- **Why LOW:** bounded — the recorded first line does not match `$HOSTNAME`, so the age path applies
  and the stale breaker reclaims it after `UVM_LOCK_STALE`.

### [LOW/CONFIRMED] F5 — each acquisition orphans one `sleep` for up to `UVM_LOCK_STALE/10` seconds

- **Where:** `bin/uv-manager:228-230`
- **Failure scenario:** `uvm_unlock` kills the refresher subshell, not the `sleep` it is blocked in.
- **Evidence:** `sleeps before: 6 / after burst 1: 9 / after 40 bursts: 116` — about 2.75 orphans per
  64-rank cold burst, each exiting within one beat (60 s at defaults), each holding only
  `/dev/null`.
- **Why LOW:** bounded and self-reaping. Informational; it matters only against a Slurm cgroup
  `pids.max`.

### Candidates raised and dropped

Both reviewers ran the refutation protocol and dropped these after failing to reproduce them:
`wait "${beat}"` blocking on a heartbeat mid-`sleep` (cold provisioning measured at 0.402 s total);
an orphaned *refresher* outliving its parent (after SIGKILL the orphan reparented to PID 1 and exited
within one beat, `owner` mtime frozen thereafter, no stray wrapper processes); the retry bound
evading the deadline (`absent` is monotonic, caps at two free iterations, 8/8 waiters rc=0 under
churn); `absent >= 3` false-positiving at scale (4608 further ranks, zero hits); trap-reset in the
heartbeat subshell releasing the parent's lock; INT/TERM mid-hold (rc=130/143, lock GONE both times).

## Human-gate triggers

**Triggered, and not cleared.** F1 is a CONFIRMED finding in `uvm_acquire_lock`, a high-blast-radius
region named in `AGENTS.md` and `invariants.md`. F2 is CONFIRMED in the same function. Both reviewers
flagged the gate independently.

Per the rubric, this gate is cleared by the human and never by the agent's own reading of the
finding. **No clearance has been given, and none was sought** — the maintainer directed remediation
instead, so the gate stands and is re-evaluated against cycle 2's verdict.

- **Cleared by:** — · **Date:** — · **Grounds:** —
- **Disposition (2026-08-15):** remediate F1, F2 and F3 in cycle 2 rather than ship over them. The
  work is: consult the age net regardless of the probe's outcome rather than only when no pid parsed;
  source the host token from `uname -n`, hoisted above the `mkdir` loop so it stays outside the
  0.10 ms acquire window; and restate `invariants.md` §5 to describe what the repaired code does.
  F4 follows from F2's remedy. F5 is left as measured.

## Reconciliation note (debate variant)

The two reviewers were run blind to each other and given opposing instructions. They converged on the
same three defects — F1, F2 and F3 — from opposite stances, which is the strongest signal this pass
produces: the ship-stance reviewer reported F1 while arguing to ship, and its recommendation turns
entirely on reachability rather than on whether the mechanism exists.

They agreed R1–R8 are all met, with each criterion's stated red state reproduced on `main`. They
disagreed only on disposition: the ship reviewer would take F1 and F2 as a follow-up seed rather than
a `changes-requested` loop, on the grounds that the diff removes four reproduced defects and neither
finding is reachable at shipped defaults on a correctly-configured node. The block reviewer would
block on F1 as a regression against `main`, which self-heals the identical state in one second.

Graded as `changes-requested`. The rubric's single deferral exception requires that the finding
predate the diff — F1 and F2 are introduced by it, so the exception does not reach, and CONFIRMED
findings block by default. Both remedies named by the reviewers are small: consult the age net
regardless of the probe's outcome rather than only when no pid parsed, and source the host token from
`uname -n` hoisted above the `mkdir` loop, which does not enter the measured 0.10 ms acquire window.
Whether to take them this cycle is the maintainer's call at the gate above.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run — `/uvm-review` was invoked with `debate`, not `completeness`.

---

# Review cycle 2 — changes-requested (2026-08-15)

- **Reviewed commit:** fadd87e  ·  **Base:** main  ·  **Previously reviewed:** 34742e9
- **Cycle:** 2 of ≤3 — mirrors `review.cycle` in `TECH.md`
- **Mode:** full blind pass over the spec-excluded diff (`main...HEAD`, 10 files, 481 insertions),
  **`debate` variant** again — two fresh reviewers, one instructed to argue ship and one to argue
  block, reconciled here. Both chosen by the maintainer: a scoped pass over the remediation delta was
  offered and declined, because F1's remedy changes *when* the age test runs, which is the predicate
  four earlier phases' behavior rests on.

Contract note: `GOAL.md` has not moved since cycle 1. Its last commit (`50b8cec`, R8) predates
`34742e9`, so both cycles grade the same eight-criterion contract. No drift to reconcile.

Findings continue cycle 1's numbering rather than restarting, so an id names one defect across the
whole record. Cycle 1's F1, F2 and F3 are remediated: the age test now runs whatever the liveness
probe answered (`bin/uv-manager:364-377`), the host token is `uname -n` resolved once above the
`mkdir` loop (`:277`), and `invariants.md` §5 states what the repaired code does. Both reviewers
graded R2 met for a live holder against that code. No cycle-1 finding was disproved or narrowed, so
no correction note is owed.

## Verification run

Both reviewers ran the gates and drove the script only through `.agents/factory/bin/temp_root.sh
--offline`. Neither opened a file under `spec/`; both excluded it from every repository-wide search.
Both returned a clean tree, verified again here (`git status --porcelain` empty, `git worktree list`
showing only the working tree — each reviewer had created detached `main` worktrees for A/B controls
and removed them).

- `bash -n bin/uv-manager` → pass, under bash 3.2.57, the portability floor itself.
- `.agents/factory/bin/lint.sh` → pass.
- `git grep -n 'exec "\${real_' bin/uv-manager` → four matches, each below a release guard.
- `git grep -n flock bin/uv-manager` → one match, the rationale comment at `:172`.
- Concurrency: 1280 + 3200 ranks (block) and 1280 + 1536 ranks (ship) on this branch; matched `main`
  worktrees as the control throughout.
- Pid-recycling construction with a matched control isolating pid occupancy as the sole variable.
- Knob-spelling matrices, timeout and stale-break drives, `bash -x` traces of the hot and cold paths.

**Each reviewer missed the other's headline finding.** The ship reviewer did not surface the
heartbeat leash; the block reviewer's candidate list does not contain the break-block race. Both
reproduced their own with matched controls, and each finding survives inspection here. Two
independent passes converging on nothing in common is the opposite of cycle 1, where both stances
reached F1 — it means the finding set for this function should not be assumed closed.

## Requirement → evidence matrix

Reconciled from two independent matrices. Both graded every R-ID met; the disagreements were about
disposition, not coverage.

| R-ID | Implemented by | Verified how (both reviewers, independently) | Status |
|------|----------------|-----------------------------------------------|--------|
| R1 | `uvm_unlock` (`:214-248`) | Foreign `owner` written mid-hold from inside the fixture → `provisioning lock is no longer ours, leaving it in place`, directory and `owner` both intact, user rc 0. Ordinary case → lock gone, `current -> versions/9.9.9`. stdout stayed `uv 9.9.9 (fixture)`. | ✅ |
| R2 | heartbeat (`:184-208`, `:439-440`), age from `owner` (`:376-377`) | 25 s hold against `STALE=10`: waiter printed `breaking` **0** times, `owner` age sampled 0–1 s throughout, holder's lock still its own at exit. **Met for a live holder; the same mechanism is the substrate of F6 for a dead one.** | ✅ |
| R3 | guard at `:286-315` | Twelve spellings across the two runs. `600/500`, `500/500`, `600/600`, `0600/500` refused rc 1 naming both variables **in the base-10 seconds judged**; `500/0600` accepted through to `current -> versions/9.9.9`; `abc` and `' '` refused on form; `STALE=0800` contended → zero `value too great for base`. `uvm help`, `uvm --version`, `uvm status` all rc 0 under broken knobs. | ✅ |
| R4 | `uvm_unlock` before `:819`, `:1156`, `:1158`, `:1162` | Census 4. A/B on instrumented untracked copies with a lock forced into the tail: guard present → `GONE`, guard removed → `PRESENT (leaked)`; same for `uvm_self_update`. Hot-path cost read from the trace: `[[ -n "${uvm_lock}" ]] || return 0` is the first statement, three trace lines, **no fork**. | ✅ |
| R5 | timeout `die` (`:409-412`) | stderr carries the `owner` line verbatim, `A pid recorded there is on that host, not this one`, and `rm -f '<lock>/owner' && rmdir '<lock>'`. Bare `rmdir` → `Directory not empty`; the advised two-step → rc 0. Break notes carry the same line. | ✅ |
| R6 | unchanged `mkdir` discipline | Fixture version and `current -> versions/9.9.9` intact; `flock` only in the `:172` comment; `uvm doctor`'s cold-sandbox rc 1 is parity with `main`, byte-identical tail. | ✅ |
| R7 | `[[ -d "${lock}" ]] \|\| continue` (`:398`), `broke=denied` (`:399`) | Three constructions — a stray entry blocking `rmdir`, a 0500 lock directory denying `rm -f` too, and a dead holder's lock — each rc 1 **inside** the timeout, **6** stderr lines, exactly **1** break note, **1** timeout message. Against the contract's red state of 825 lines still spinning. | ✅ |
| R8 | `absent` counter, literal bound 3 (`:330-334`) | Branch **0 of 1280** and **0 of 3200** ranks non-zero, zero `check permissions and quota`; matched `main` controls **36/1280 (2.8%)** and **10/640**. Unwritable arch directory still names the real fault, rc 1, in 18 ms rather than after `UVM_LOCK_TIMEOUT`. The monotonic-count objection — three *non-consecutive* absences accumulating across a long wait — was hunted across 5,760 contended ranks and found zero times. | ✅ |

Unmapped changes: **`issues/invariant-audit-gaps.md` and its `ROADMAP.md` entry**, flagged by both
reviewers. It maps to no R-ID and is not one of the two deferrals § *Non-goals* commits to landing in
this commit. Both concluded it is the correct destination under `AGENTS.md` § *Where a deferral goes*
rather than scope creep, and both verified its substantive claims against the real `uv 0.12.4`. It
carries F8. Reported, not blocking.

Requirements taken on trust: **`mkdir` atomicity on Lustre, GPFS and NFS**, declared up front in
`GOAL.md` § *Verification limit*. Also unobservable here: bash 4/5 behavior (this machine has only
3.2), and the README/`conf.example` NFS attribute-cache guidance. Nothing was silently downgraded to
trust during review.

## Findings

### [CRITICAL/CONFIRMED] F6 — a recycled pid keeps the refresher alive, and the lock becomes immortal

- **Where:** `bin/uv-manager:198` (the leash), with `:184-208`, `:439-440` and `:376-377`
- **Failure scenario:** `uvm_lock_heartbeat` decides whether its holder still lives with
  `kill -0 "$$"`, and `$$` inside a backgrounded subshell is the holder's pid *number* — confirmed
  here directly. A holder killed without running its traps leaves the refresher running. If that pid
  is reoccupied before the next beat, the refresher survives, re-reads an `owner` file that still
  matches what it wrote, and rewrites it every `UVM_LOCK_STALE/10` seconds. Both recovery paths then
  fail together: the age backstop at `:376-377` never fires because `owner`'s mtime is reset on every
  beat, and the dead-holder fast path at `:362-363` never fires because the waiter probes the
  recorded pid and finds the *reoccupying* process alive. The lock is removable only by hand. This is
  the pid-number-versus-process confusion cycle 1's F1 removed from the waiter, still present in the
  refresher's own leash.
- **Evidence:** at the shipped default `UVM_LOCK_STALE=600`, holder SIGKILLed, pid space wrapped by
  ~98k forks over 36 s until the pid was reoccupied by an unrelated long-lived process:
  `owner mtime advanced=120s` with the holder dead 132 s, `REFRESHER STILL RUNNING`, and a waiter at
  `TIMEOUT=5` dying `timed out after 5s` rather than breaking. Matched control, byte-identical drive
  with the pid burn removed: `advanced=0s`, `refresher EXITED`, and the waiter recovered in 0 s with
  `breaking provisioning lock abandoned by a dead process`. Pid occupancy is the only variable
  between the two runs.
- **Competing explanations ruled out:** *zombie, not running* — `ps` answered and the mtime advanced
  by exactly two beats, which a zombie cannot write; *something else touched `owner`* — no waiter ran
  before the read, the fixture writes nothing, and the control advanced 0 s; *the holder was
  resurrected* — the occupying process was `sleep`, the holder was `bash`; *the waiter timed out for
  an unrelated reason* — the control's waiter broke the same-age lock immediately.
- **Not executed:** the pid wrap arriving naturally rather than by construction. The code path is
  identical either way, and the reachability argument is the script's own: `:281-283` and
  `invariants.md` §5 both assert pid space wraps in under a minute on a node spawning `uv run` in a
  loop, against a 60 s default beat. Each survived beat extends the outage past `UVM_LOCK_STALE`; a
  recycled pid landing on a long-lived process makes it permanent.
- **Touches:** R2; `invariants.md` §5, whose *Age is measured from the heartbeat* bullet asserts the
  refresher "exits when `kill -0 "$$"` fails" and whose *Liveness* bullet names this exact outcome as
  the thing to avoid — auto-CRITICAL. `AGENTS.md` § *Invariants* carries the same claim, and
  `etc/uv-manager.conf.example:75` still promises `UVM_LOCK_STALE` covers a holder killed by SIGKILL
  or job cancellation.
- **Region:** `uvm_acquire_lock` / `uvm_lock_heartbeat` — high blast radius.

### [HIGH/CONFIRMED] F7 — the break removes the lock by path, so concurrent breakers destroy the winner's

- **Where:** `bin/uv-manager:381-400`, with the consequence landing at `:424`
- **Failure scenario:** once `reason` is set, `rm -f "${lock}/owner"` and `rmdir "${lock}"` run
  unqualified — nothing re-checks that the directory being deleted is still the one just judged
  forfeit. When several waiters declare the same lock forfeit in one tick, the first to win the
  re-`mkdir` has its fresh, still-empty directory removed by a loser still executing its own break.
  Two outcomes: the winner's owner write at `:424` opens `ENOENT` and it dies
  `cannot record ownership of the provisioning lock`, having done nothing wrong; or two ranks
  provision one tree at once, and the robbed holder's `uvm_unlock` correctly declines to delete the
  thief's lock — R1 working, after the fact.
- **Evidence:** dead-pid lock at shipped `UVM_LOCK_STALE=600`, 20 bursts × 64 ranks:
  `installs=23 (expect 1/burst) not_ours=3 nonzero=4 multi_install_bursts=3`, with every failing rank
  carrying `line 424: No such file or directory`. A second run of 4 bursts × 64 reproduced it.
- **Competing explanations ruled out:** *two `mkdir`s both succeeded* — impossible, and the
  `not_ours` line independently proves a holder's `owner` was replaced while it still believed it
  held the lock; *the second install is a legitimate sequential re-acquisition* — `uvm_install` calls
  `uvm_point_current` before `uvm_unlock` (`:560-561`), so a later waiter hits the under-lock
  `uvm_have` re-check and returns without printing `installing uv`; *`line 424` is a quota fault* —
  the errno is `ENOENT`, and the same tree takes 1280 ranks with zero failures when no lock is
  pre-planted.
- **Pre-existing, and the diff changes reachability rather than the mechanism.** `main` carries the
  identical unqualified `rm -f owner; rmdir`. Matched A/B on an aged lock, 20 × 64 ranks each: `main`
  119 spurious installs and 65/1280 failing ranks, this branch 87 and 19. What the diff adds is the
  dead-pid fast path, which fires *instantly* on a fresh lock instead of waiting out 600 s — so the
  common "a rank was cancelled" case now sends many waiters into the break window at once. The
  counterweight, measured: on `main` that same state is a 100% outage — `installs=0 timeouts=64
  ok_ranks=0/64` for the full stale window — where the branch recovers 63 of 64 ranks immediately.
- **Why HIGH and not auto-CRITICAL:** §5's *Ownership, not path* bullet is scoped to `uvm_unlock`,
  and the break bullet imposes no ownership qualification on the removal, so no §1–§11 section is
  violated. `uvm_install` stages into a `mktemp -d` and renames, and `uvm_point_current` swaps
  atomically, so concurrent installs waste work rather than corrupt the tree. The rank that dies is a
  real bug on a path this diff makes common. This severity is the *ship-stance* reviewer's own call,
  argued against its stance's interest.
- **Deferral exception does not reach.** The rubric requires both that the finding predate the diff
  *and* that a `GOAL.md` criterion be failed by repairing it. The first holds; the second fails — R6
  pins the `mkdir` discipline and single-download parity, and re-reading `owner` immediately before
  the `rmdir`, or verifying ownership after the re-`mkdir`, disturbs neither. The ship reviewer
  reached this conclusion unprompted and recorded it against its own recommendation.
- **Region:** `uvm_acquire_lock` — high blast radius.

### [LOW/CONFIRMED] F8 — the new seed's line citations are `main`'s, and are already wrong where they land

- **Where:** `issues/invariant-audit-gaps.md:30`, `:35`, `:43`
- **Failure scenario:** the seed cites `bin/uv-manager:533-538`, `:491-496` and `:361`. The lock
  section grew ~197 lines on this branch, so on the file the seed is committed against those lines
  are the installer-stderr comment, `printf '%s\n' "${ver}"`, and `reason=""`. A reader following
  them lands in unrelated code, and once this cycle squash-merges, `main` *is* this file.
- **Evidence:** `sed -n '361p;491,496p;533,538p' bin/uv-manager` against the branch returns none of
  the three; the real locations are `:558` (the unguarded `mv`), `:688-693` (the trampoline overwrite
  guard) and `:731-736` (the parser banner). `git show main:bin/uv-manager | sed -n '361p'` returns
  the `mv`, confirming the numbers were taken from `main`. Verified here as well as by both
  reviewers.
- **The seed's substance is sound** and both reviewers checked it against the real binary
  (`uv 0.12.4`): `--cache-dir DIR` and `--python-preference only-managed` are accepted before
  `tool dir`, `--python 3.12` is rejected, the overwrite guard at `:688-690` is a three-way
  conjunction including `-x`, and the `mv` at `:558` is unguarded. Only the coordinates drifted.
- **Touches:** §12, adjacent — accuracy of a graded diff file, not the same-commit rule itself.

### Cycle 1's F5, re-observed

The orphaned `sleep` grandchild — `uvm_unlock` kills the refresher subshell but not the `sleep` it is
blocked in — was independently re-found by the ship reviewer (`pid=81692 ppid=1 cmd=sleep 60`) and
raised then dropped by the block reviewer as bounded and self-clearing. Both measured that it holds
no pipe: `VER=$(uv --version)` returned in 238 ms and 355 ms on cold provisions. No new id; cycle 1
recorded it and left it as measured, and cycle 2 does not change that.

### Candidates raised and dropped

Across both reviewers, dropped after failing to reproduce: the heartbeat stamping its identity over a
new holder's `owner` (guarded by the re-read at `:203-205`); `uvm_unlock` blocking the caller on the
killed refresher (cold `VER=$(uv --version)` at 238 ms, 640 ranks in 14.4 s wall); a truncated `owner`
from a refresher killed mid-`printf` (not seen in >2500 ranks; single `write(2)`); the monotonic
`absent` bound false-positiving under sustained contention (zero occurrences in 5,760 contended
ranks); the recovery command failing against a lock holding a foreign entry (R5 requires naming the
discriminator, which the message does — dropped as manufactured); `uvm_install`'s
`|| return 0` early-out skipping `uvm_point_current` (real, but pre-existing, untouched, and
self-correcting). A hot-path A/B measured ~0.6 ms, of which ~0.2 ms is parse cost from the file
growing 37,184 → 49,376 bytes; `GOAL.md` R4 pre-declares this unresolvable by a timing drive and
directs grading of the implementation, which passes. A §12 prose sweep of every added line found zero
banned constructions, zero feature-scoped spec ids in `bin/uv-manager` or `README.md`, and no emoji.

## Human-gate triggers

**Triggered, and not cleared.** F6 and F7 are both CONFIRMED in `uvm_acquire_lock` /
`uvm_lock_heartbeat`, a high-blast-radius region named in `AGENTS.md` and `invariants.md`. F6 is in
addition an `invariants.md` §5 violation, which is auto-CRITICAL on its own.

Per the rubric this gate is cleared by the human and never by the agent's own reading. No clearance
has been given.

- **Cleared by:** — · **Date:** — · **Grounds:** —
- **Disposition (2026-08-16):** F6 remediated and proven; F8 repaired; **F7 deferred** to
  [`issues/lock-break-instance-identity.md`](../../issues/lock-break-instance-identity.md) with a
  `ROADMAP.md` entry, both committed before this note. The gate stands and is re-evaluated against
  cycle 3's verdict.

  **The deferral rests on a premise cycle 2 got wrong, and the correction belongs here.** This
  section graded F7 blocking because the rubric's exception requires that repairing it fail a
  `GOAL.md` criterion, and reasoned that "both remedies named by the reviewers are small". The first
  remedy attempted — an exclusive rename — is not a remedy: `mv` is not `rename(2)`, `mv -T` is
  absent at the portability floor so `mv` nests instead of failing, and `rmdir` refusing a non-empty
  directory turned out to be what protects an established lock and what makes R7 true for its own
  gate's construction. Measured, the rename left robbed winners at 15 of 320 against the unfixed
  code's 16 of 208. The second remedy — the identity guard — shipped, and 320 ranks put robbed
  winners at 5 against 2, which is noise rather than a closure.

  So the finding is not small, and the reason is not one this cycle can retire: the repository
  cannot yet measure a lock race well enough to accept or reject a candidate. That is now the seed's
  first requirement. F7 remains CONFIRMED, remains pre-existing on `main` and measurably worse
  there, and the narrowing that shipped is recorded as a narrowing and not as a fix.

## Reconciliation note (debate variant)

The two reviewers agreed on the requirement matrix and on nothing else. Each reproduced a defect the
other never raised, and each recommended the disposition it was assigned. That is a weaker
convergence signal than cycle 1's, where both stances independently reached the same F1, and it
should be read as evidence about coverage rather than about severity: two passes over one 273-line
function surfaced two disjoint defects, so a third is not unlikely.

The dispositions, stated as each reviewer left them. **Ship:** take F7 as a seed rather than a loop,
because the mechanism is pre-existing, every metric says the branch improves on `main` (87 spurious
installs against 119, 19 failing ranks against 65), and the state that newly reaches it is one where
`main`'s alternative is a total outage for the full stale window. **Block:** F6 is a CONFIRMED
CRITICAL that inverts the cycle's own stated outcome — the age comes to reflect whether *some*
process holds the holder's pid number — and the diff ships `AGENTS.md` and `invariants.md` text
asserting a leash property the code lacks, which §12 makes a finding in itself.

Graded `changes-requested`. F6 decides it: it is auto-CRITICAL under §5 and the ship reviewer never
examined it, so no stance argued for shipping over it. F7 blocks independently by the letter of the
deferral exception, as its own finder recorded. Both remedies are small and neither touches R6's
pinned discipline — the refresher already re-reads `owner` before every write, so a leash keyed to
the recorded identity rather than to the bare pid number is close at hand; and the break can confirm
what it is deleting the same way `uvm_unlock` already does. Whether to take both, take one, or clear
the gate and ship is the maintainer's call.

**Loop bound.** This is cycle 2 of at most three. A third cycle is within bounds; a fourth is not,
and non-convergence there is an escalation rather than another pass.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run — `/uvm-review` was invoked with `debate`, not `completeness`.
