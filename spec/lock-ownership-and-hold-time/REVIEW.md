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
