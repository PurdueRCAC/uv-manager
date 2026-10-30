# REVIEW — Repair a purged tree under UVM_REPAIR

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 7b4c960  ·  **Base:** main  ·  **Date:** 2026-10-29
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md`

## Review cycle 1 — changes-requested (2026-10-29)

Mode: `debate`, because the diff touches `uvm_acquire_lock` and the dispatch tail. There were two
independent blind reviewers at xhigh, one arguing ship and one arguing block. Each had its own
scratch directory, and each received GOAL, the spec-excluded diff and the hash-only log. Both
handed back a clean tree.

### Verification run

Both reviewers ran these:

- `bash -n bin/uv-manager` → rc 0 (bash 3.2).
- `.agents/factory/bin/lint.sh` → rc 0, with `UV_CACHE_DIR` and `UV_TOOL_DIR` under scratch.
- `tests/lock-race.sh --plant control` (16 ranks × 2 bursts) and `--plant held` (8 ranks) → green.
  The provisioning lock has not regressed. Its messages are byte-identical to `main`.
- `tests/repair-race.sh`, run locally with the default launch:

  | Scenario | Ranks | Result |
  |---|---|---|
  | F | 64, 128 | exit 0, `progress=ok`, one repair per run |
  | T | 16 | exit 0, `progress=ok`, one repair per run |
  | P | 16, 64 | exit 0, `progress=ok`, one repair per run |
  | kill | 8, 16 | holder rc 137, every waiter rc 1 naming the lock; one repair on the clean pass |

  A mutant copy with the repair lock removed was caught (repairs=16, rc 1).
- Fixture stress under one scope, one repair every time:
  - 25 bursts × 32 ranks;
  - 10 bursts × 96 ranks;
  - 4 scopes × 24 ranks at once.
- Real uv 0.13.6 against damaged trees (R3–R5):
  - a pinned tool with a `--with` package keeps its version, its extra package and a byte-identical
    receipt;
  - a damaged 3.12.1 returns as 3.12.1;
  - an orphan tool fails the scope and leaves the base interpreter's site-packages identical.
- Timing of the unset path: 1200 interleaved warm `uv --version` calls per arm, against a
  byte-identical copy of `main` as control (F3).

### Cluster evidence (R12), graded by the orchestrator

The reviewers may not open `spec/purge-tree-repair/`, so they took the cross-node half of R12 on
trust (META F8 in `lock-simplification`, which recommends exactly this split). Both judged the drive
fit for purpose. The orchestrator graded `evidence/lustre.txt` and `evidence/gpfs.txt` against R12's
*Checked by* list.

| R12 item | Lustre, 2 nodes × 64 | GPFS, 1 node × 64 |
|---|---|---|
| P: repairs=1, outcomes=1 (ok), `rc_hist` all 0, expected stdout | ✅ 128 ranks | ✅ 64 ranks |
| T: the same, stdout `3.2.0` | ✅ | ✅ |
| `locks_left=0` | ✅ | ✅ |
| Holder seconds: P / T | 5 s / 1 s | 5 s / 1 s |
| Waiter wait, max: P / T | 5 s / 3 s | 5 s / 2 s |
| `notice_lines`, P and T | 0 | 0 |
| kill: holder rc 137 | ✅ | ✅ |
| kill: every waiter rc 1 naming the lock at the timeout | ✅ 127/127 | ✅ 63/63 |
| kill: no outcome; doctor WARNs the repair lock | ✅ | ✅ |
| Clean pass after `uvm clean lock --yes` | ✅ one repair, all rc 0, no lock | ✅ |

Nothing in either file identifies a site.

In the kill runs `repair_lines` reads 0 on Lustre and 1 on GPFS. The holder was killed before its
start line on one and after it on the other. Neither run recorded a repair.

**R12 is met at `4c08e9c`.** F1's remediation changes the interpreter arm, so this evidence must be
re-recorded at the remediated commit.

### Requirement → evidence matrix

| R-ID | Status | Basis (both reviewers unless noted) |
|---|---|---|
| R1 | ✅ SHALL met, prose overstated (F3) | Unset, empty and `0` give no repair, no outcome and no lock. The unset path adds no fork (xtrace diff against `main`). Parsing the added code costs ~0.4 ms per call (~3%). |
| R2 | ✅ | A planted repaired or failed outcome short-circuits before any walk. The failed reason reaches stderr and the command does not run. |
| R3 | ❌ F1 | Met when no Python request is configured. With one, the interpreter arm installs the requested version and records the scope repaired. |
| R4 | ✅ | Pin, `--with` and receipt survive. `tool upgrade` is the only tool repair. |
| R5 | ✅ | The orphan fails the scope. Nothing is rebuilt and the base site-packages are untouched. |
| R6 | ⚠️ F4 | 0/0/1 `python install` lines for none/passing/failing. A dangling shim with its directory gone triggers a repair that fixes nothing. |
| R7 | ✅ | One repair per scope under every burst. A failed holder's reason reaches every waiter within 0.1 s. |
| R8 | ✅ | The exit code passes through; stdout is exactly the command's. |
| R9 | ✅ | (a)–(d) driven, (c) with real uv and process-group KILL. |
| R10 | ⚠️ F2, F5 | Per-job and per-value behavior holds. An array scope departs from "ends with the job". Values differing outside the key's class share a scope. |
| R11 | Retired | — |
| R12 | ✅ at `4c08e9c` | Orchestrator grading above. Re-record after remediation. |
| R13 | ✅ | (a)–(d) driven. The two locks never nest. |
| R14 | ✅ collective reading | All six surfaces name the knob. README carries every listed item. The modulefile's "keyed on SLURM_JOB_ID" is wrong for arrays (F2). |

Unmapped changes:
- **Accepted:** `uvm clean outcomes` and doctor's failed-outcome WARNs (the planned human path for a
  value-scoped failure), the 200-byte key cap, the `SLURM_CLUSTER_NAME` qualifier, fixture knobs,
  `lint.sh` coverage, and the two new seeds.
- **Accepted:** `uvm clean … --yes` now skips an absent target silently, where `main` printed
  `removing`.

Taken on trust: the cross-node half of R12, by the reviewers only. The orchestrator graded it.

### Findings

#### F1 [HIGH/CONFIRMED] The interpreter repair follows the job's Python request, leaves the damaged interpreter broken, and records the scope repaired
- **Where:** `bin/uv-manager:1300` (`uvm_repair_run`): `python install --reinstall` with no targets.
  The record is written at `:1366`.
- **Failure scenario:** a damaged cpython 3.12, plus any Python request:
  - a `.python-version` in the working directory or a parent;
  - the global pin file;
  - `UV_PYTHON`.

  uv installs the requested version (3.13.18), exits 0, and leaves 3.12 damaged. The wrapper records
  the scope as repaired. The command fails with `ModuleNotFoundError`, and every later call in the
  scope trusts the record.
- **Evidence:** block reviewer, real uv 0.13.6:
  - `pyver.sh` (working-directory `.python-version`), `pyver2.sh` (global pin) and `pyver3.sh`
    (`UV_PYTHON`) each give rc 2 and leave a `.ok` record; `json/` is still absent.
  - Control: the same tree with no request restores 3.12.x, and every rank exits 0.

  Secondary: under `UV_PYTHON=3.13` the tool arm rebuilt every tool on 3.13 (`toolpy.sh`).
- **Touches:** R3. Region: `uvm_repair`, which the dispatch tail calls. The R12 drive's sandbox
  scrubs `UV_*` and `XDG_CONFIG_HOME`, so it cannot see this.

#### F2 [MEDIUM/CONFIRMED] Array tasks share one scope, a failed outcome included, and three messages say the record ends with the job
- **Where:** `bin/uv-manager:1326` (key), `:1329` (die text), `:1036` (doctor text),
  `share/modulefiles/uv/main.lua:95`.
- **Failure scenario:** task 501 of array 500 fails its repair, for example on transient egress.
  Every later task of the array then exits 1 with no repair attempt, possibly days later, and is told
  "the record ends with the job".
- **Evidence:** both reviewers (`array.sh`, `r10b.sh`). The control, plain jobs 400 then 401,
  repairs fresh.
- **Touches:** R10. The array key was the plan gate's ruling. It keeps a large array from walking
  the tree once per task under the repair lock. A failed record has no such benefit.

#### F3 [LOW/CONFIRMED] "Off costs one shell test and nothing else" overstates R1
- **Where:** `README.md:451`, `AGENTS.md:234`.
- **Evidence:** block `perf3.sh`; ship `hot2.sh`/`hot4.sh`. The unset path takes about 3% longer
  (~0.4 ms per call). Replacing the knob test with `:` does not change that, and `bash -n` alone is
  0.31 ms slower: the cost is parsing, not the test. R1's SHALL (builtin tests, no fork) holds.

#### F4 [MEDIUM/CONFIRMED] Damage the repair cannot fix triggers it in every scope and is recorded as repaired
- **Where:** `bin/uv-manager:868` (dangling-shim detection feeds the damaged flags), `:1292-1300`.
- **Failure scenario:** a tool's or interpreter's directory is removed whole while its shim
  survives. Each new scope runs the full tool rebuild or an interpreter install that restores
  nothing, then records the scope repaired. Doctor still FAILs the shim.
- **Evidence:** block `dangle.sh`, `dangle2.sh` (real uv) and `r6shim.sh` (fixture: 1 `python
  install` line in each of 3 scopes beside a passing interpreter).
- **Touches:** R6, R2.

#### F5 [LOW/CONFIRMED] Distinct `UVM_REPAIR` values that differ only outside the key's class share one scope
- **Where:** `bin/uv-manager:1339`.
- **Evidence:** both reviewers. `run/1`, `run 1`, `run_1` and `run:1` all map to
  `value-run_1.ok`: one repair, then three calls with 0 repair lines on a damaged fixture tree. R10
  says "the literal value", and the comment at `:1342` rejects truncation for this very reason.

#### F6 [LOW/CONFIRMED] AGENTS.md says no wrapper message names `tool upgrade` or `python install`
- **Where:** `AGENTS.md:243`.
- **Evidence:** ship reviewer, `git grep -n -E 'tool upgrade|python install' -- bin/uv-manager`.
  Doctor's remediation block (`:1062-1063`) names both. The sentence holds for the uv and uvx path,
  which is what the drives count.

Dropped after reconciliation:
- **Separately submitted jobs queue on the repair lock.** Reproduced, and documented in GOAL,
  README and `issues/repair-scope-queueing.md`.
- **TERM to the holder.** It follows the unchanged lock contract.
- **An unreadable RECORD.** Pre-existing on `main`.

### Human-gate triggers

- **Triggered:**
  - F1 and F4, in `uvm_repair`/`uvm_repair_run` behind the dispatch tail.
  - F2, a contract deviation in the same region.
- **Cleared by the foreman, 2026-10-29,** under the maintainer's autonomy decision for this effort.
  The grounds are the rulings below.

**Rulings for remediation:**
1. **F1.** The interpreter arm names its targets: exactly the damaged installed interpreters, by
   their install keys, so uv reinstalls each at its installed patch version. Both arms run with the
   job's Python request neutralized: `UV_PYTHON` unset, the global pin ignored, and a working
   directory that holds no `.python-version`. A repair restores what is installed; it never applies
   the job's request. A local gate drives all three request sources against both arms, and the R12
   drives are re-run at the remediated commit.
2. **F2.** A repaired record stays array-wide. A failed record is written per task
   (`SLURM_JOB_ID`), so the next task tries again. Doctor, the die text, README, the conf example and
   the modulefile say what an array shares. GOAL R10 gets a dated clarification recording the array
   key, and README concedes that a repaired record outlives a purge that lands partway through an
   array.
3. **F3.** The prose says what R1 actually measures: no fork, and a parsing cost of the added code.
4. **F4.** Repair is triggered only by damage it can repair. A dangling shim whose whole directory
   is gone is reported by doctor and does not trigger a repair.
5. **F5.** The value-to-key mapping becomes injective, using a pure-bash escape with no fork. The
   200-byte cap applies to the encoded name.
6. **F6.** The sentence is scoped to the uv and uvx path.

The next cycle is a fresh blind pass over the full spec-excluded diff.

## Review cycle 2 — changes-requested (2026-10-29)

- **Reviewed commit:** abf84b9
- **Mode:** `debate`, a fresh blind pass over the full spec-excluded diff. Both reviewers ran at xhigh, each with its own scratch directory, and each was handed the GOAL copy as amended by the cycle-1 clarification. Neither saw cycle 1's findings. Both handed back a clean tree.

### Verification run

Both reviewers ran these, all green:
- `bash -n bin/uv-manager` (bash 3.2.57);
- `.agents/factory/bin/lint.sh`;
- `tests/lock-race.sh --plant control` at 32 ranks × 2 and `--plant held` at 16 ranks. Provisioning messages are byte-identical to `main`.

Local `tests/repair-race.sh`:
- F at 16 and 64 ranks;
- T at 16;
- P at 16 and 64;
- kill at 8, run with real uv 0.13.6.

They also ran fixture and real-uv drives for every R-ID; the drive scripts are in each reviewer's scratch directory. The new cycle-1 behavior held under them:
- the job's Python request (`.python-version`, `UV_PYTHON`) no longer steers either arm;
- array tasks share a repaired record and keep their own failed ones;
- the value encoding is injective under bash 3.2 and UTF-8.

### Cluster evidence (R12) at `40e6120`, graded by the orchestrator

`evidence/lustre.txt` and `evidence/gpfs.txt` were checked against R12's *Checked by* list.

| Scenario | Lustre (2 nodes × 64) | GPFS (1 node × 64) |
|---|---|---|
| P | repairs=1, ok, `rc_hist=0:128`, expected stdout, no lock; hold 5 s | repairs=1, ok, `rc_hist=0:64`, no lock; **hold 34 s, `notice_lines=63`** |
| T | repairs=1, ok, `rc_hist=0:128`, stdout 3.2.0; hold 2 s | repairs=1, ok, `rc_hist=0:64`, stdout 3.2.0; hold 2 s |
| kill | 127/127 waiters fail at the timeout naming the lock; doctor WARNs; the clean pass repairs once, all rc 0 | 63/63 waiters fail the same way, doctor WARNs, and the clean pass repairs once with all rc 0 (hold 13 s) |

R12 is met. The slow GPFS holds coincide with slow setup in the same jobs (`prep_s` 12 s and 16 s, against 4 s before), so the node is the likelier cause. Both GPFS jobs were queued again to check. The cycle-2 findings below change `uvm_detect` and the tool arm, so the evidence is re-recorded at the remediated commit in any case.

### Requirement → evidence matrix

| R-ID | Status | Basis |
|---|---|---|
| R1 | ✅ SHALL met | No fork on the unset path. Parse cost is about 0.5 ms per call, documented. The *Checked by*'s literal "no measurable difference" is not met (C2-F8). |
| R2 | ✅ | Planted ok/failed outcomes short-circuit before any walk and take no lock. |
| R3 | ❌ C2-F1, C2-F2 | Holds on the GOAL's trees. Fails on a purged interpreter binary and on an unpinned, superseded tool. |
| R4 | ✅ as written | Pin, `--with` and receipt survive. C2-F2 is a consequence of the named command. |
| R5 | ✅ | Orphan fails the scope; base site-packages unchanged. |
| R6 | ⚠️ C2-F1 | Holds for the fixture stubs. A purged binary behind the minor-version link is not detected. |
| R7 | ✅ | One repair per scope. A failed holder's reason reaches every waiter within 0.04 s. |
| R8 | ✅ | — |
| R9 | ✅ | (a)–(d) driven. |
| R10 | ✅ | Every case, arrays and the encoding included. The length limit is undocumented (C2-F4). |
| R11 | Retired | — |
| R12 | ✅ at `40e6120` | Graded above. Both reviewers note that the drive's trees hide C2-F1 (P removes only `json/`) and C2-F2 (T pins its tool). |
| R13 | ✅ | (a)–(d) driven, plus per-architecture records. |
| R14 | ✅ collective reading | Per-surface reading raised as PLAUSIBLE again (C2-F6). |

Unmapped changes accepted as in cycle 1, plus doctor's rewritten remediation advice (cycle-1 F1's own fix).

### Findings

#### C2-F1 [HIGH/CONFIRMED] A purged interpreter binary is never repaired, and the scope is recorded repaired
- **Where:** `bin/uv-manager:886` (`uvm_detect`); the stdlib probe at `:979`.
- **Cause:** uv 0.13.6 points `bin/python-shims/python3.12` at the minor-version link `python/cpython-3.12-<platform>`. The dangling-shim branch skips any name that is a symlink, so the shim never becomes an install key. The probe skips an interpreter whose binary is gone.
- **Failure scenario:** a purge takes every file of an idle interpreter and leaves its directories. The `uv run` repair runs nothing, writes `.ok`, and exits 2 (`missing a _sysconfigdata_ file` / `Python interpreter not found`). With a tool on that interpreter, the tool arm runs on the broken interpreter, and the scope fails with a misleading reason.
- **Evidence:** both reviewers.
  - Ship reviewer: `findingA.sh`, `pyshim.sh`, `pyshim3.sh`, and the control `pyshim2.sh`.
  - Block reviewer: `real2.sh`, `real9.sh`, `real3.sh`.
  - Counterfactual: `python install --reinstall <install key>` restores the interpreter and the tool.
- **Touches:** R3, R6. The code comment at `:868-874` and the README's concession are both false for this layout.

#### C2-F2 [HIGH/CONFIRMED] The tool arm upgrades unpinned tools, and fails, scope after scope, when a newer release exists and the purge took `RECORD`
- **Where:** `bin/uv-manager:1406`, plus README, conf and doctor prose ("restores what is installed").
- **Cause:** `uv tool upgrade --all --reinstall` upgrades an unpinned tool. The upgrade must uninstall the old version, which needs its `RECORD`, the file a purge takes first.
- **Failure scenario:** `pyflakes` installed unpinned at 3.1.0 while 4.1.0 is current. With `checker.py` and `RECORD` purged, the repair exits 1 and records the scope failed, leaving two dist-info directories. Jobs 501, 502 and 503 each re-run the full rebuild and fail. With `RECORD` intact, the repair "succeeds" but moves pyflakes to 4.1.0, and it also upgrades a healthy, unpinned `pycodestyle` from 2.11.1 to 2.15.0.
- **Evidence:** block reviewer `real8.sh`, `real10.sh`, `real7.sh`. Controls: pinned tools repair cleanly (`real4.sh`, `real5.sh`, repair-race T).
- **Touches:** R3, R4. R4 names the command, so the fix needs a contract amendment.

#### C2-F3 [MEDIUM/CONFIRMED] Separately submitted jobs can time out at the repair lock on a healthy tree
- **Evidence:** block reviewer. A planted 1.5 s walk, 12 concurrent jobs, `UVM_LOCK_TIMEOUT=5`: 3 exit 0, 9 exit 1 naming the repair lock.
- **Status:** documented in README "Many jobs at once" and deferred to `issues/repair-scope-queueing.md`. This is introduced by the branch, so the rubric's pre-existing-only deferral exception does not cover it.

#### C2-F4 [LOW/CONFIRMED] A value whose record name passes 200 bytes dies, and the limit is not documented
- `bin/uv-manager:1440-1441`. A value of 194 characters repairs; one of 195 exits 1. The help, README and conf say "any other value is on".

#### C2-F5 [LOW/CONFIRMED] Doctor prints `uv python install --reinstall <install>...` when no interpreter is damaged
- `bin/uv-manager:1306-1320`. The placeholder appears beside a tool-only damage report, and `<install>` is a shell redirect if pasted.

#### C2-F6 [LOW/PLAUSIBLE] R14 read per surface
- Help, conf and modulefile carry subsets. README carries everything. Raised in cycle 1 (ship) and in this cycle (both reviewers).

#### C2-F7 [LOW/PLAUSIBLE] An array's first task (`SLURM_JOB_ID == SLURM_ARRAY_JOB_ID`) gets the plain-job failure wording
- `bin/uv-manager:1424`, found by reading. Cosmetic.

#### C2-F8 [LOW/CONFIRMED] R1's *Checked by* says "no measurable difference"; the parse cost is measurable
- Both reviewers, both cycles. The SHALL (no fork) holds, and the cost is documented. This is a contract-wording issue, not a code one.

### Human-gate triggers

- **Triggered:** C2-F1 and C2-F2, in `uvm_detect` and `uvm_repair_run` behind the dispatch tail; C2-F2 also amends R4.
- **Cleared by the foreman, 2026-10-29,** under the maintainer's autonomy decision, with the rulings below. The next cycle is the third and last that may request changes. A cycle-3 finding that requires changes goes to the maintainer as a ship/abandon/rescope choice.

**Rulings for remediation:**

1. **C2-F1.** An installed interpreter is a real directory under `python/`, not the minor-version link.
   - It is damaged when its binary is missing or fails the probe, and it is keyed by its own directory name.
   - A dangling python shim that reaches an install through the minor-version link maps to that install's key.
   - The interpreter arm runs before the tool arm, as now.
   - Fix the code comment and README concession to match.
2. **C2-F2.** The tool arm restores each damaged tool at its installed versions, every package in its environment included (`--with` extras), whether the tool is pinned or not.
   - A healthy tool's versions do not change.
   - The repair must work with `RECORD` and other per-file metadata gone. Directory names (`<name>-<version>.dist-info`) survive a purge, so they are the expected source of installed versions.
   - The mechanism is the builder's choice, by measurement with real uv. Candidates:
     - pins from the dist-info directory names, passed as constraints;
     - `--exclude-newer` at the receipt's mtime;
     - a per-tool reinstall from the receipt plus those pins.
   - If none restores an unpinned superseded tool without touching healthy tools, the builder stops and reports what it measured.
   - R4 is amended by a dated clarification to name the chosen command and keep R4's three properties (pin, `--with`, receipt).
   - The prose ("restores what is installed") must be true afterwards.
3. **C2-F3. Deferred by the foreman's ruling, against the rubric's pre-existing-only exception.** This is recorded here so the maintainer can overturn it. The grounds:
   - The GOAL's own-scope predicate was settled at the GOAL gate.
   - The failure is a prompt, named timeout with no damage done, and a resubmitted job succeeds.
   - At the default timeout it needs on the order of a hundred separately submitted jobs arriving within one walk-time window.
   - The fix (accept any outcome recorded after the waiter's arrival) changes the predicate, and belongs to `repair-scope-queueing`.

   README "Many jobs at once" must state the timeout arithmetic plainly.
4. **C2-F4.** Document the limit wherever the values are documented (help, README, conf).
5. **C2-F5.** Doctor prints the interpreter line only when an interpreter is damaged. The placeholder form stays only for damage it cannot key.
6. **C2-F6.** Settled by a dated GOAL clarification. README carries R14's full list; help, conf and modulefile carry the knob, its values, its scope and the length limit, and point to README for the rest. Add the pointer where absent.
7. **C2-F7.** Detect an array task by `SLURM_ARRAY_TASK_ID`, not by inequality of the two ids.
8. **C2-F8.** A dated GOAL clarification amends R1's *Checked by* to what the SHALL says: no fork on the unset path, and the parse cost measured and documented.
9. **R12 drive.** The trees are extended by a dated GOAL clarification so that the cluster drive exercises the real purge shapes:
   - (P) removes every file of the interpreter, keeping directories and links, which subsumes `json/`;
   - (T) adds an unpinned tool installed at an older release beside the pinned one.

   Local gates cover both, and the cluster drives are re-run at the remediated commit.

Cycle 3 is a fresh blind pass over the full spec-excluded diff.

## Review cycle 3 — changes-requested (2026-10-29)

- **Reviewed commit:** 5732d45
- **Mode:** `debate`, a fresh blind pass over the full spec-excluded diff. Both reviewers ran at xhigh, each with its own scratch directory and its own fresh uv cache, and each was given the GOAL copy as amended by the cycle-2 clarifications. Neither saw an earlier cycle's findings. Both handed back a clean tree.

### Verification run

Both reviewers ran these, all green:
- `bash -n bin/uv-manager` (bash 3.2.57);
- `.agents/factory/bin/lint.sh`;
- `tests/lock-race.sh --plant control` (32 ranks × 3 bursts, and 48 ranks) and `--plant held`. Provisioning is not regressed.

Local `tests/repair-race.sh`:
- F at 16 and 64 ranks;
- P and T at 8 and 16, with real uv 0.13.6;
- kill at 4 and 8.

They also ran fixture and real-uv drives for every R-ID, using the real purge shapes the cycle-2 rulings named:
- every file of an interpreter removed;
- bin-only removal;
- the minor-version link gone;
- unpinned tools and `--with` packages at older releases;
- whole dist-info directories emptied;
- two installed patches with the older one gutted;
- freethreaded and PyPy layouts.

All of these repaired with versions and receipts kept.

### Cluster evidence (R12) at `5e1e6d9`, graded by the orchestrator

`evidence/lustre.txt` and `evidence/gpfs.txt` were checked against R12's *Checked by* list.

| Scenario | Lustre (2 nodes × 64) | GPFS (1 node × 64) |
|---|---|---|
| P (every file removed) | repairs=1, ok, `rc_hist=0:128`, expected stdout, restored, no lock; hold 4 s, wait max 4 s, 0 notices | repairs=1, ok, `rc_hist=0:64`, restored, no lock; hold 4 s, wait max 5 s, 0 notices |
| T (pinned, plus unpinned at older releases) | repairs=1, ok, `rc_hist=0:128`, stdout 3.2.0; 2.11.1 / 1.16.0 kept, 0 second dist-info, 2 receipts identical; hold 2 s | the same on 64 ranks; hold 2 s |
| kill | 127/127 waiters fail at the timeout naming the lock; doctor WARNs; the clean pass repairs once, all rc 0, hold 5 s | 63/63 the same; the clean pass repairs once, all rc 0, hold 3 s |

R12 is met at `5e1e6d9`. `5732d45` adds only the evidence and spec text. The cycle-1 GPFS hold of 34 s did not recur.

### Requirement → evidence matrix

| R-ID | Status | Basis |
|---|---|---|
| R1 | ✅ | No fork on the unset path, by xtrace diff; about 0.7 ms parse per call, documented. |
| R2 | ✅ | Outcomes short-circuit before any walk or lock. |
| R3 | ✅ | Real-uv (P) and (T) on every purge shape listed above. |
| R4 | ⚠️ C3-F1 | Pins, `--with` and receipt survive on every registry-sourced shape. The URL/git/path refusal fires only while `direct_url.json` survives. |
| R5 | ✅ | Orphan fails the scope; base site-packages unchanged. |
| R6 | ✅ | Every interpreter shape keyed by its install directory. |
| R7 | ✅ | One repair per scope; a failed reason reaches every waiter. |
| R8 | ✅ | — |
| R9 | ✅ | (a)–(d) driven. |
| R10 | ✅ (C3-F2 caveat) | Every case, arrays, limit and encoding included. |
| R11 | Retired | — |
| R12 | ✅ | Local half by both reviewers; cluster half graded above. |
| R13 | ✅ | (a)–(d) driven. |
| R14 | ✅ | Per-surface reading holds. The refusal claims are overstated by C3-F1. |

The unmapped changes are accepted:
- `uvm clean outcomes`;
- doctor's failed-outcome WARNs and per-key remediation;
- `SLURM_CLUSTER_NAME` in the job scope;
- the queueing seed and its ROADMAP entry;
- the fixture knobs and `lint.sh` coverage.

### Findings

#### C3-F1 [MEDIUM/CONFIRMED] A tool installed from a path, git or URL source is replaced from the index when the purge also took `direct_url.json`
- **Where:** `bin/uv-manager:874-885` (`uvm_tool_pins`), used at `:1508-1520` (`uvm_repair_run`).
- **Failure scenario:** a tool is installed from a local fork that keeps upstream's version (2.11.1). A purge takes the module, `RECORD` and `direct_url.json`; nothing reads that file at run time.
  - The knob-set `uvx` installs `pycodestyle==2.11.1` from the index, exits 0 and records the scope repaired.
  - The tool now runs upstream code, while its receipt still names the fork.
  - With `direct_url.json` kept, the same drive fails the scope naming the tool and the distribution, as R4 requires.
- **Evidence:** block reviewer, `driveDU.sh {0,1}`, real uv 0.13.6.
- **Touches:** R4. The README, AGENTS.md, conf and invariants §8 claims ("otherwise the reinstall fails", "restores what is installed") are false in this case. The same mechanism is behind the conceded case: an index recorded in the receipt is not applied, so a name from a private index resolves from the public one.

#### C3-F2 [LOW/CONFIRMED] On a case-insensitive filesystem, two values that differ only in case share one record
- **Where:** `bin/uv-manager:1398-1410` (`uvm_repair_encode` passes `A-Z` unchanged).
- **Evidence:** block reviewer. `UVM_REPAIR=Run1` repaired, then `UVM_REPAIR=run1` read `value-Run1.ok` on default APFS.
- **Touches:** invariants §10 and AGENTS.md ("no two scopes share a name"), README ("compared exactly"). Lustre and GPFS are case-sensitive.

#### C3-F3 [LOW/CONFIRMED] The `--no-cache` tool repair stages its download under `TMPDIR`, and no surface says so
- **Where:** `bin/uv-manager:1518`; README's Network paragraph.
- **Evidence:** block reviewer. With `TMPDIR` read-only, the repair fails the scope with uv's permission error. The command is the one R4 names, so the remedy is documentation.

#### C3-F4 [LOW/CONFIRMED] Doctor's advice for a shim whose interpreter directory and minor link are both gone names no interpreter
- **Where:** `bin/uv-manager:924` (`uvm_detect`) → `:1146` and `:1177` (`uvm_doctor`).
- **Evidence:** ship reviewer, `r6f.sh` case g. Doctor prints `uv python install --reinstall <install>...` and "name each damaged interpreter reported above", but none is reported, and the "remove a shim" fallback a tool shim gets is not printed. The README already concedes that the shim is not repaired.

#### C3-F5 [LOW/CONFIRMED] `uvm clean <target> --yes` no longer prints a line for a target that is already absent
- **Evidence:** ship reviewer, `clean.sh`, against `main`. Accepted: the dry run lists each target, and there is nothing to remove. No change.

### Human-gate triggers

- **Triggered:** C3-F1, in `uvm_repair_run` behind the dispatch tail. This diff adds `uvm_repair` to the high-blast-radius list, and the remedy amends R4.
- **Cleared by the foreman, 2026-10-29,** under the maintainer's autonomy decision, with the rulings below. This is the last cycle that may request changes. The next cycle's verdict goes to the maintainer as a ship / abandon / rescope choice.

**Rulings for remediation:**

1. **C3-F1.** R4 is amended by a dated clarification. The repair may read `uv-receipt.toml` to refuse, and for nothing else. It never builds a spec from the receipt and never writes it, so the receipt stays byte-identical.
   - A damaged tool fails the scope, naming the tool and what was found, before any `uv` call for that tool, when its receipt records either:
     - a requirement (the tool or a `--with` package) from a directory, path, editable, git or URL source; or
     - an index or find-links option.
   - The `direct_url.json` refusal stays.
   - The builder measures uv 0.13.6's receipt keys with real installs of each source kind and each index option, and tests the recorded form, not a guess. A healthy registry-sourced tool's receipt must not trip the check.
   - A tool with no receipt is still repaired, as now. The README states the remaining concession plainly: with both the receipt and `direct_url.json` gone, the source cannot be known and the index release is installed.
   - Make the README, AGENTS.md, conf and invariants §8 claims true, and replace the "index is not applied" concession with the refusal.
2. **C3-F2.** Escape `A-Z` as `_xx` in the value encoding, so that no two values share a name on a case-insensitive filesystem. The 200-byte limit applies to the encoded name. Say where the limit is documented that an uppercase letter costs three bytes. Doctor decodes as before.
3. **C3-F3.** README's Network paragraph says the tool repair downloads into uv's temporary directory under `TMPDIR`, the size of the tool's environment, and that a non-writable or full `TMPDIR` fails the scope with uv's reason.
4. **C3-F4.** A shim whose interpreter cannot be keyed gets the same "remove the shim" fallback a tool shim gets. The `<install>` placeholder is not printed for it.
5. **C3-F5.** No change.
6. **R12.** C3-F1 changes the tool arm that scenario T drives, and C3-F2 changes record names, so the cluster drives are re-run at the remediated commit.
   - Local gates add a real-uv drive for each refused receipt form, with `direct_url.json` removed.
   - They add the case-collision drive on the local filesystem.

The next cycle is a fresh blind pass over the full spec-excluded diff.

**Ruling 1 amended by the foreman, 2026-10-29, after the remediation's measurement.**
- **What was measured:** uv 0.13.6 writes an index configured in `uv.toml` (user or system) or through `UV_INDEX`, `UV_INDEX_URL` or `UV_DEFAULT_INDEX` into every receipt's `[tool.options]`. Refusing on those keys would refuse every damaged tool at any site that configures a mirror, which is the setup the README recommends.
- **The amendment:**
  - The index and find-links refusal is withdrawn.
  - The repair runs under the user's `uv.toml` and environment, so a configured index is in effect there too. Only an index given on one install's command line is not re-applied. The README keeps that as the stated concession.
  - The source refusal stays, and it extends to a directory, path, editable, git or URL entry in the receipt's `constraints` and `overrides` as well as its `requirements`.

## Review cycle 4 — handed to the maintainer (2026-10-30)

- **Reviewed commit:** 7ba7f11
- **Mode:** `debate`, a fresh blind pass over the full spec-excluded diff. Both reviewers ran at xhigh, each with its own scratch directory and uv cache, and each was given the GOAL as amended by the cycle-3 clarifications. Both handed back a clean tree.
- **Ship reviewer:** no findings.
  - Every R-ID with a local *Checked by* was driven green, including the cycle-2 and cycle-3 shapes that had failed: 14 refused receipt sources and 5 index options repaired with receipts byte-identical.
  - §1: a repair touches only its own architecture's tree.
- **Block reviewer:** one HIGH finding and one LOW, below. It confirmed every other R-ID by drive.

### Cluster evidence (R12) at `7ba7f11`
- **Lustre (2 nodes × 64, 128 ranks): green.**
  - P: `rc_hist=0:128`, repairs=1, restored, hold 4 s.
  - T: `rc_hist=0:128`, versions 2.11.1 / 1.16.0 kept, 0 second dist-info, 2 receipts kept, hold 2 s.
  - kill: 127/127 waiters named the lock; the clean pass repaired once, hold 3 s.
- **GPFS:** jobs cancelled while queued, because C4-F1's fix changes both arms. The evidence is recorded at the fix commit.

### Findings

#### C4-F1 [HIGH/CONFIRMED] The repair resolves under the project config in the job's working directory
- **Where:** `bin/uv-manager:1577` (tool arm, `uv pip install`) and `:1525` (python arm) in `uvm_repair_run`, behind the dispatch tail.
- **Cause:** `uv pip install` reads `pyproject.toml` `[tool.uv]` / `[tool.uv.pip]` and `uv.toml` from the working directory and its parents; `uv tool install` does not. A job launched from a project directory is the usual case.
- **Failure scenarios (block reviewer, real uv 0.13.6):**
  - `[tool.uv.pip] target = "tgt"`: uv installs pycodestyle 2.11.1 into the user's project, the wrapper records the scope repaired, and the tool stays broken. The user's command exits 1 (`cwdcfg.sh`).
  - `[tool.uv] exclude-newer = 2023-01-01`: every rank of job 500 fails its scope on a repairable tool. `uv tool install --force` succeeds from the same directory, and job 501 run from a directory with no project config repairs (`excl.sh`).
- **Touches:** R3, R4, invariants §8 ("restores what is installed and changes no resolution").

#### C4-F2 [LOW/CONFIRMED] With the knob set, `uv self update --dry-run` repairs before answering
- **Where:** dispatch tail, `bin/uv-manager:1669` ahead of `:1672`.
- **Status:** the GOAL requires the repair on every invocation, but invariants §2 still says `--dry-run` and `-h/--help` answer without the network. This is drift between the GOAL and the invariants, not a code defect.

### Bounded loop: handed to the maintainer

Cycle 3 was the last that could set `changes-requested`. The ship / abandon / rescope choice went to the maintainer with C4-F1 and C4-F2 standing.

## Maintainer decision — fix, verify, ship (2026-10-30)

**The maintainer chose "fix, verify, ship":**
- the builder fixes C4-F1 and C4-F2 with local drives for both failure cases;
- the cluster drives are re-run at the fix commit;
- the foreman checks the delta itself, with no fifth blind cycle, then publishes to local `main`;
- pushing `main` needs the maintainer's go-ahead.

**Rulings for the fix:**
1. **C4-F1.** Both arms run from a working directory with no project configuration on its path to `/`, so project `pyproject.toml` and `uv.toml` cannot reach the repair. The user's and system `uv.toml` and the `UV_*` environment still apply, as the cycle-3 amendment requires.
   - The builder measures the mechanism with real uv 0.13.6. Candidates: a subshell `cd /`, or uv's `--directory`. Avoid `--no-config`, which would also drop the user and system config.
   - It confirms that a user-level `uv.toml` index still applies.
   - A real-uv drive reproduces both scenarios above from a project directory: the tool repaired in place, nothing written into the project, and the scope recorded repaired.
   - The python arm is checked the same way with a project `python-install-mirror` or `python-downloads = "never"`.
2. **C4-F2.** `invariants.md` §2 states the exception: with `UVM_REPAIR` on, the repair runs first on every invocation, help and dry-run included, as the knob's own contract says. No code change.
3. **R12.** The cluster drives re-run at the fix commit on both filesystems.

## Maintainer decision — approved after the bound (2026-10-30)

**The fix was verified by the foreman,** with no fifth blind cycle, as the maintainer's decision
above directs.

**Remediation:**
- `addb815` fixes C4-F1;
- `33dee22` fixes C4-F2;
- `bdc38d6` is P5 Run A;
- `55cddf7` is P5 Run B.

**What the foreman verified:**
- **The executable delta is two lines.** Outside `spec/`, `7ba7f11` (the commit both cycle-4
  reviewers graded) and `bdc38d6` differ in executable code only in the two repair calls. Each now
  runs as `(cd / && exec "${real_uv}" …)` in a subshell. Everything else in the delta is prose:
  - the comment over `uvm_repair_run`;
  - `invariants.md` §2 and §8;
  - `README.md`, `AGENTS.md`, and the config example.

  `bin/uv-manager` and the tests are unchanged from `bdc38d6` to `55cddf7`.
- **The gates pass after the last edit:**
  - `bash -n` and `lint.sh`;
  - the P3 gate, including the builder's real-uv drives. A project `pyproject.toml` or `uv.toml`
    in the caller's directory no longer reaches either arm, nothing is written into the project,
    the scope is recorded repaired, and a user-level `uv.toml` index still applies;
  - all five phase gates, run again at `55cddf7`.
- **C4-F2.** §2 now states the knob exception in the wording the ruling asked for.

**Rulings on the builder's open questions:**
1. **`UV_PROJECT` is accepted.** An explicit `UV_PROJECT` in the environment still reaches the
   repair. It is a `UV_*` setting the caller chose, which ruling 1 keeps on purpose, and the same as
   an explicit `UV_INDEX`.
2. **No change to doctor's advice.** The human commands doctor prints are run by a person, from a
   directory they choose. They stay as written.

**Cluster evidence (R12) at `bdc38d6`.** Both runs are green and recorded unedited in `evidence/`:

- **Lustre, 2 nodes × 64, 128 ranks** (`lustre.txt`, sha256 `fb59f5bf…`).
  - P: `rc_hist=0:128`, repairs=1, restored, hold 3 s.
  - T: `rc_hist=0:128`, 3.2.0 on every rank. Versions 2.11.1 / 1.16.0 kept, 0 second dist-info,
    2 receipts kept, hold 2 s.
  - kill: 127/127 waiters named the lock (median wait 60 s, slowest 66 s), and doctor WARNs. The
    clean pass repaired once, hold 4 s, 128/128 rc 0.
- **GPFS, 1 node × 64** (`gpfs.txt`, sha256 `6eb202ec…`).
  - P: `rc_hist=0:64`, repairs=1, restored, hold 5 s.
  - T: `rc_hist=0:64`, same version checks, hold 1 s.
  - kill: 63/63 waiters named the lock at 61 s, and doctor WARNs. The clean pass repaired once,
    hold 5 s, 64/64 rc 0.

The slowest Lustre waiter reported 66 s against the 60 s timeout. The median was 60 s, and every
waiter failed naming the lock. This matches launch skew across two nodes under `srun`, and it is
not a defect: the timeout bounds each waiter's own wait, not the job's wall clock.

**Still deferred, not a defect of this branch:** C2-F3 (queueing). The maintainer may overturn it.

**Verdict:** approved at `55cddf7`, on the maintainer's decision.
