# REVIEW — A tool run by its own name gets the guarantees `uvx` gets

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only**. It does not see
> `PLAN.md` or `TECH.md`. Every finding cites an **executed** command. This repository has no test
> suite; this pass is the coverage.

## Review cycle 1 — changes-requested (2026-11-01)

- **Reviewed commit:** `7aecf40` · **Base:** `release/0.8.0`
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3
- **Mode:** `debate`. Two fresh blind reviewers, one arguing ship and one arguing block, each
  denied `PLAN.md`, `TECH.md` and every other file under this spec.

### Verification run

Both reviewers ran the same gates:

- `bash -n bin/uv-manager` (bash 3.2) exited 0.
- `.agents/factory/bin/lint.sh` exited 0.
- `tests/repair-race.sh` was green at 16–64 ranks with `--launch local` for scenarios F, T, P,
  kill, I and ikill.
  - I: `restores=1`, every equality at 5, `commit_kept=1`, `unpinned_upgrade=moved`.
  - ikill: every waiter failed naming the lock and its owner, and the clean pass restored once.

Each reviewer then drove every locally observable R-ID through `temp_root.sh` with real uv 0.13.6.
Their drive scripts stayed in their scratch directories.

### Cluster evidence (R11), graded by the orchestrator

Both runs were on a Lustre scratch, 2 nodes × 64 ranks, at `7aecf40`, staged by clone with file
hashes checked.

- **Scenario I: green.** `rc_hist=0:128`, `stdout_hist=expected:128`, `uv_resolved=wrapper:128`,
  `restores=1`, `hold_s=7`, `wait_max_s=13`, `notice_lines=0`, `locks_left=0`. Every equality is at 5,
  plus `commit_kept=1` and `unpinned_upgrade=moved`.
- **Scenario ikill: red in its clean pass.**
  - The killed pass is green: `rc_hist=1:127,137:1`, `timeout_named_lock=127`,
    `timeout_named_owner=127`, `outcomes=0`, `doctor_warn_repair_lock=1`.
  - After `clean lock`, the clean pass restored exactly once and every equality is at 5. But that
    restore held the lock for 209 s, against a 180 s timeout (`clean_hold_s=209`). Ninety-eight
    waiters timed out naming the lock: `clean_rc_hist=0:30,1:98`.
  - The killed pass's own wall time was 241 s, although its waiters were done by 97 s.
  - Leading hypothesis: the killed holder's `uv` child stayed alive in an uninterruptible
    filesystem call and held uv's own lock on the tool directory, so the clean holder's replay
    waited on it.
  - The drive removes its logs, so the cause is not yet established. A diagnostic rerun that keeps
    them is queued.

### Requirement → evidence matrix

| R-ID | Status | Evidence, in brief |
|------|--------|--------------------|
| R1 | ✅ for index and plain git sources; ❌ for a git subdirectory (C1-F4) | Every shape, by name and through `uvx`. Lists, records and receipts are byte-identical, and the upgrade still moves |
| R2 | ✅, with C1-F8 plausible | Failed install, upgrade, `upgrade --all`, uninstall; `SECRETMARK` in no record |
| R3 | ✅ | Knob-set call by name: one repair line, the tool's own stdout and exit status |
| R4 | ✅, but C1-F4 and C1-F5 fail whole scopes | All five shapes; unreachable index gives every waiter the reason |
| R5 | ✅ | Two keys, concurrent by-name restores, one per key |
| R6 | ✅, with C1-F7 | No wrapper fork with the knob unset, empty or `0`; 9.7 ms against 12.8 ms for the base trampoline |
| R7 | ✅ for one root; ❌ across roots that share `UVM_DATA` (C1-F3) | |
| R8 | partial (C1-F1, C1-F5, C1-F6, C1-S1) | Backfill on a 0.7.0-built tree |
| R9 | ✅, with C1-F2 | Default chain, status, modulefile order, migration before the first `uv` call |
| R10 | ✅ | Knob-set `uvx` for a tool that isn't installed writes nothing |
| R11 | I green; ikill red at the clean pass (above); C1-F9 | |
| R12 | ✅ | Census of the six surfaces; the release note in PLAN is taken on trust (blindness) |

Unmapped changes: none. The `temp_root.sh` redirect of `XDG_DATA_HOME` is harness support, and the
reviewers judged it justified.

### Findings

#### C1-F1 [CRITICAL by rubric / CONFIRMED] Doctor writes uv's lock file under `UVM_ROOT`
- **Where:** `uvm_backfill`, called from `uvm_doctor`.
- **What fails:** the backfill runs `uv tool list`, which creates `tools/.lock` when it is missing.
  An access-time purge removes that idle, empty file, so this is the state doctor is run in.
- **Breaks:** R8 ("writes nothing under `UVM_ROOT`") and §8 as this branch amends it.

#### C1-F2 [HIGH / CONFIRMED] Retiring a 0.7.0 trampoline breaks a running script that has already hashed it
- **Where:** `uvm_trampolines migrate`, reached from the self-heal in the dispatch tail.
- **What fails:** a bash job script runs `fx; uv --version; fx`. The second `fx` exits 127, because
  bash execs the hashed path that the first `uv` call removed.
- **Breaks:** this is the first-job-after-upgrade failure the amended N6 forbids.

#### C1-F3 [HIGH / CONFIRMED] With `UVM_DATA` shared across roots, a sync on one root removes the other's trampolines
- **Where:** the removal loop in `uvm_trampolines`.
- **What fails:** managed interpreters and tools without a record have no shim in root A. A sync
  there, including from `doctor` or `uv tool list`, deletes their trampolines, so on root B they
  exit 127.
- **Breaks:** R7 ("SHALL NOT be removed because a shim is missing … tools and managed interpreters
  alike") in the case N5 accepts as a feature. 0.7.0 did not do this.

#### C1-F4 [MEDIUM / CONFIRMED] A VCS constraint drops `#subdirectory=`
A git tool installed from a monorepo subdirectory cannot be restored, and its failure fails the
whole scope. Breaks R1 and R4 for VCS sources (N9).

#### C1-F5 [MEDIUM / CONFIRMED] Backfill records a `--with` direct URL in `uv tool list`'s rendering
The `--with` package is recorded as `six https://…`, which the replay cannot parse, and the scope
fails. Breaks R8 ("brings the tool back with its `--with` packages").

#### C1-F6 [MEDIUM / record CONFIRMED, consequence PLAUSIBLE] Backfill drops the receipt's index options
A tool installed in 0.7.0 from a custom index would replay against whatever index is configured.
R8 promises "its source".

#### C1-F7 [LOW / CONFIRMED] The knob-off entry recreates missing per-architecture directories
This happens when `UVM_ROOT` is unset and the cascade finds the root. §9's new text says the path
"creates nothing".

#### C1-F8 [LOW / PLAUSIBLE] The receipt-copy credential guard matches only `http`, `https` and `ftp` userinfo
A `git+ssh://user:pw@` source would carry a credential into the copied receipt (R2).

#### C1-F9 [LOW / CONFIRMED by reading] The R11 drive fixes `UVM_DATA` on the tree's filesystem
R11 asks for a second filesystem where the cluster offers one.

#### C1-S1 [MEDIUM / observation CONFIRMED] Backfill for a git tool whose `direct_url.json` was purged pins by version only
The receipt survived, so backfill wrote a record, and the walk then restored the tool from the
branch head. 0.7.0 refused this tool, which was safer.

#### C1-S2 [LOW / CONFIRMED] Unwritable `$UVM_DATA/bin` prose overclaims
The prose says nothing is removed there. The guard tests `mkdir -p`, which succeeds on an existing
read-only directory.

### Rulings (foreman, standing in for the human gate)

C1-F2 and C1-F3 touch `uvm_trampolines` and the dispatch tail, which are human-gate regions. The
maintainer delegated that gate to the foreman for this release.

1. **Trampolines (C1-F2, C1-F3, C1-S2). Contract amendment A2.**
   - `$UVM_DATA/bin` holds the trampolines generated **from the records**. A sync removes one only
     when no record names it, which in practice means a `uv tool uninstall`.
   - `$UVM_ROOT/bin` stays on `PATH` behind it, permanently rather than as a 0.8.x migration path. It
     holds this root's shim-derived trampolines: managed interpreters, and any tool without a record.
     The new trampoline text is used and the removal rule is 0.7.0's, per root.
   - A marked 0.7.0 trampoline that a shim still names is **rewritten in place**, never removed, so
     a hashed path keeps working.
   - R7, R9, N6 and §9 change together. A sync on one root then never touches another root's
     trampolines.
   - The "nothing is removed" prose must match what the guard checks.
2. **C1-F1:** doctor runs the backfill only when `tools/.lock` already exists. Otherwise it reports,
   as an advisory, the tools without a record and the command that writes them. R8 and §8 stand as
   written.
3. **C1-F4:** fix. Carry `subdirectory` into the VCS constraint.
4. **C1-F5:** fix. Record a `--with` direct URL as `name @ url`.
5. **C1-F6:** carry the receipt's `index-url` and `extra-index-url` into a backfilled request where
   the receipt holds them as single-line strings, with userinfo stripped. Anything uv writes in
   another form is not parsed: the README says a backfilled record replays under the current
   configuration for it.
6. **C1-F7:** make the knob-off path create nothing, or make §9's text say exactly what it does.
   Either is acceptable; prefer the code if it costs no fork.
7. **C1-F8:** fix. Match userinfo under any scheme.
8. **C1-S1:** backfill writes no record for a tool whose receipt names a VCS or URL source when
   `direct_url.json` is missing. The tool keeps 0.7.0's refusal, and doctor names it.
9. **C1-F9. Contract amendment A2, with ruling 1.** R11's "second filesystem" clause is dropped.
   The site's test envelope keeps every file of a test run on scratch, and nothing in `UVM_DATA`'s
   behaviour depends on which filesystem holds it.
10. **ikill clean pass:** held open until the diagnostic run reports. If uv's own lock outlives a
    killed holder, that is filesystem behaviour this cycle cannot change. The ruling will then
    concern the drive's clean pass and the README's account of a killed restorer, not the restore.

### Human-gate triggers

C1-F2 and C1-F3 are in `uvm_trampolines` and the dispatch tail. The foreman's rulings above are the
gate, under the maintainer's delegation for this release, and the maintainer reviews the result in
the release PR.

## Review cycle 2 — changes-requested (2026-11-01)

- **Reviewed commit:** `1a0d680` · **Base:** `release/0.8.0` · **Delta:** `8504ac4..1a0d680`
- **Verdict:** changes-requested
- **Cycle:** 2 of ≤3
- **Mode:** `debate`. Two fresh blind reviewers against the amended GOAL (A2), each given cycle 1's
  findings.

### Verification run

- **Static checks:** `bash -n`, `lint.sh`.
- **Real-uv drives:** every R-ID's *Checked by* drive was rerun with real uv 0.13.6 through
  `temp_root.sh`.
- **Concurrency:** `tests/repair-race.sh` I and ikill at 64 ranks, local launch. Both green.
- **The ship reviewer:** all twelve R-IDs pass their *Checked by* drives.
- **The block reviewer:** found reachable states, outside those drives, that the A2 remediation
  introduced.

### Cycle-1 findings

Fixed: C1-F1, F2, F3, F4, F5, F7, F8 and F9, each reproduced red at `8504ac4` and green at `1a0d680`.

Partly fixed:

- **C1-F6:** only the legacy index forms are carried (C2-F5).
- **C1-S1:** the direct case is fixed; a transitive direct-URL dependency defeats the check (C2-F3).
- **C1-S2:** the code is fixed, but the CLI message still overclaims (C2-F6).

### Findings

#### C2-F1 [HIGH / CONFIRMED] The walk's backfill writes a record but not its trampoline
- **Where:** the holder's `uvm_backfill`.
- **What fails:** the self-heal runs before the walk, so it creates an empty `$UVM_DATA/bin`. The
  walk then writes the record, and nothing on the `uv`/`uvx`/knob path syncs again.
- **Impact:** a jobs-only user who upgrades ends up with records and no durable trampoline. After a
  purge, the tool is "command not found" even after a restore. This breaks R7. It worked at
  `8504ac4`.

#### C2-F2 [HIGH / CONFIRMED] The self-heal keys on the shared `$UVM_DATA/bin`, which doctor creates
- **What fails:** following the README's "run doctor once after upgrading" before any `uv` call
  turns off the rewrite of this root's 0.7.0 trampolines. A knob-set call by name then skips the
  scope check. The same happens on a second root after another root upgraded.
- **Breaks:** R3 by name, and R9's "until a sync rewrites it", since none comes.

#### C2-F3 [CRITICAL by rubric class, narrow trigger / CONFIRMED] `uvm_unpinnable` compares totals
- **What fails:** a transitive direct-URL dependency whose `direct_url.json` survived stands in for
  the tool's own, which is gone.
- **Consequence:** backfill pins the tool by version, and the restore runs a new commit at rc 0.
  0.7.0 refused this tool.

#### C2-F4 [MEDIUM / CONFIRMED] An unwritable `$UVM_DATA` makes every call run a full root sync
- **Measured:** about 490 ms per `uv --version` with 30 shims, against 15 ms.
- **Breaks:** R9's "once".

#### C2-F5 [MEDIUM / record CONFIRMED] `--index`/`--default-index` are dropped
uv writes them as `index = [{ url = …, default = … }]` on one line. `--index-strategy` is dropped
too.

#### C2-F6 [LOW / CONFIRMED] `uvm trampolines` reports a sync of a directory its guard skipped

#### C2-S2 [MEDIUM / CONFIRMED, accepted] Doctor writes no record while `tools/.lock` is missing
This is the trade-off ruling 2 of cycle 1 chose: R8's "write nothing under `UVM_ROOT`" over its
backfill clause in that one state. It is documented, and doctor names the remedy. No change.

#### C2-P1 [LOW / PLAUSIBLE] Trampoline temp names are `.<name>.$$`
Ranks on two nodes can share a PID. With the self-heal syncing from hot-path calls across nodes,
two writers could collide on one temp name in shared scratch.

### Rulings (foreman, standing in for the human gate)

1. **C2-F1.** Writing a record and writing its `$UVM_DATA/bin` trampolines are one step, wherever a
   record is written: the intercept, doctor, the walk's holder, and the restore by name. The holder
   also syncs `$UVM_DATA/bin` once per scope.
2. **C2-F2 and C2-F4.** The self-heal's trigger becomes **per root**. A marker in `$UVM_ROOT/bin`,
   written by a successful root sync, gates it. Doctor never writes under `UVM_ROOT`, so it can
   neither set nor clear the marker.
   - The heal runs at most once per root while that root is writable, never on every call.
   - Doctor running first, or another root upgrading first, does not disable it.
   - An unwritable `$UVM_DATA` costs one failed attempt, not one per call.
   - The hot path stays one `stat`.
3. **C2-F3.** Check pinnability per requirement name: the tool's own distribution, and each
   `--with` requirement that has a source, each against its own `direct_url.json`.
4. **C2-F5.** Carry `index = [ … ]` entries that the receipt writes on one line, as `--index URL` or
   `--default-index URL` with userinfo stripped, and a one-line `index-strategy`. Any other form
   stays documented as not carried.
5. **C2-F6.** The message names only the directories actually synced.
6. **C2-P1.** Put the host in the temp name (`.<name>.$HOSTNAME.$$`), which costs no fork.
7. **Cycle-1 ruling 10 (the ikill clean pass), closed.** A diagnostic rerun with logs kept and a
   process sampler on both nodes was green: the killed pass took 61 s, and the clean pass restored
   once in 22 s with 128 of 128 ranks at rc 0. No member of the killed group outlived it. The 209 s
   hold is read as network and filesystem variance in a five-tool, uncached restore.
   - The product concern stands. A job whose purge took many tools holds the repair lock for the
     sum of their restores.
   - The README states the measured per-tool restore cost, and says to raise `UVM_LOCK_TIMEOUT`
     for jobs that run many recorded tools.
   - The drive keeps its clean timeout.

## Review cycle 3 — approved (2026-11-01)

- **Reviewed commit:** `a49e6d9`, then the foreman's direct verification of `0883c7d` ·
  **Base:** `release/0.8.0` · **Delta:** `1a0d680..a49e6d9`, then `a49e6d9..0883c7d`
- **Verdict:** approved
- **Cycle:** 3 of ≤3
- **Mode:** `debate`, two fresh blind reviewers.

### Verification run

- **Ship reviewer:** all twelve R-IDs green under real uv 0.13.6, re-run as a full matrix, and all
  eighteen earlier findings fixed, each reproduced.
- **Block reviewer:** no block case, every cycle-2 finding fixed, and no R-ID red. It cleared these
  scenarios without a finding:
  - 64 concurrent first calls against hashed-path executions;
  - a concurrent heal racing a knob-set restore;
  - `uv python install` and `uninstall`;
  - a by-name restore on a second key;
  - a shared `UVM_DATA` across roots;
  - the hashed-path job script, both doctor-first and other-root-first;
  - the credential guard;
  - the knob-off entry with no root.
- **Both reviewers:** `tests/repair-race.sh` I and ikill green at 64 ranks, local launch.

### Cluster evidence (R11) at `a49e6d9`, graded by the orchestrator

Lustre scratch, 2 nodes × 64 ranks, staged by clone with hashes checked; summaries in
[`evidence/lustre.txt`](evidence/lustre.txt), hash-verified and free of identifying text.

- **Scenario I:** `rc_hist=0:128`, `stdout_hist=expected:128`, `uv_resolved=wrapper:128`,
  `restores=1`, `hold_s=9`, `wait_max_s=11`, `notice_lines=0`, `locks_left=0`. All five equalities
  are at 5, `commit_kept=1` and `unpinned_upgrade=moved`.
- **Scenario ikill, killed pass:** `rc_hist=1:127,137:1`, `timeout_named_lock=127`,
  `timeout_named_owner=127`, `outcomes=0`, `doctor_warn_repair_lock=1`.
- **Scenario ikill, clean pass:** `clean_rc_hist=0:128`, `clean_restores=1`, `clean_hold_s=12`, and
  every equality at 5.

`0883c7d` changes only the trampoline write's failure path and the heal trigger, so the restore path
this drive measures is unchanged, and the evidence stands for R11.

### Findings

#### C3-F1 [MEDIUM / CONFIRMED by injected write failure] A failed trampoline write renames an empty file over a working trampoline
- **What fails:** `cat > tmp` was unchecked. On a block quota or a full filesystem, the tool then
  exits 0 and runs nothing. The defect predates this cycle on the `uv tool` intercept; the self-heal
  and the holder made it reachable from more paths.
- **Fixed in `0883c7d`:** a failed write, `chmod` or rename removes the temporary file and stops
  that directory's sync, and the root's marker is not written.

#### C3-F2 [LOW / PLAUSIBLE, mechanism CONFIRMED on an analog] A marker that cannot be created cost a full sync per call
- **Fixed in `0883c7d`:** the heal creates the marker first and skips the sync when it cannot. A
  sync that fails to write the root's directory removes the marker.

### Foreman's verification of `0883c7d` (in place of a fourth blind cycle)

The loop is at its cap of three cycles. As with `purge-tree-repair`'s cycle 4, the foreman verified
the delta directly:

- **Diff read:** about 60 lines in `uvm_trampolines`, `uvm_trampoline_dir` and the heal trigger,
  plus the comments, `AGENTS.md` and `invariants.md` §8 and §9 moving with them.
- **Builder's drives:** each finding red at `a49e6d9` and green after. C3-F1 used the reviewer's
  failing-`cat` drive through the heal, the holder and the intercept. C3-F2 used the reviewer's
  dangling-marker drive and a variant.
- **Gates at `4b84eab`:** `bash -n`, `lint.sh`, and the P1 to P5 gates, all green. P2 gained
  clauses for both findings, each seen red against `a49e6d9`.

Accepted trade-offs, documented in `invariants.md` §8:

- A heal killed mid-sync leaves its marker. The old trampolines it did not reach run their tools
  until the next `uv tool` command or `uvm trampolines`.
- Under a lasting block quota on the root, each call that finds no marker retries the sync once.

### Human-gate triggers

`0883c7d` touches `uvm_trampolines` and the dispatch tail. The foreman's verification above is the
gate, under the maintainer's delegation for this release, and the maintainer reviews the result in
the release PR.
