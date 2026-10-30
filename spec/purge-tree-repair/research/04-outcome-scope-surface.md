# 04 — Outcome store, scope key, and the R14 surface census

## Conclusion

The decided design holds in its parts, with four defects the plan should settle:

1. **Range classes are locale-dependent.** `[^A-Za-z0-9._-]` keeps `é` under a UTF-8 locale on bash
   3.2 and 4.4 and replaces it on 5.1. Spell the set out (`[^ABC…xyz0123456789._-]`); that form gave
   identical output on all three. Also bound the key length: a value past about 230 bytes makes every
   outcome write fail `ENAMETOOLONG`.
2. **Concurrent distinct scopes serialize their walks.** Every Slurm job, and every array task, is its
   own scope, and every scope walks the tree under the one per-root repair lock. A waiter's predicate
   tests only its own scope, so N jobs starting together make the k-th wait k walks. With walk time
   `w`, any job past `UVM_LOCK_TIMEOUT / w` in line dies per R9 on a healthy tree. That is 90 tasks at
   `w` = 2 s and the default 180 s. GOAL R7 covers one scope only, so this is a gap in the GOAL as well
   as the plan.
3. **Job ids are not unique across clusters.** Two independent clusters sharing one filesystem, and
   one architecture, issue the same `SLURM_JOB_ID`, so one cluster's `.ok` file reads as a check on
   the other. That is a false clean. `SLURM_CLUSTER_NAME` is set alongside `SLURM_JOB_ID` and fixes it
   at no cost.
4. **Relying on the purge alone leaves non-purged roots growing without bound.** That is the
   combination `README.md` recommends: mitigation 1 plus the knob in a job template. Holder-side age
   pruning is cheap and also clears outcomes left over from job-id wraparound.

Doctor's WARN placement is correct under its banner rule. Two message details need care: the
provisioning-lock WARN, and reading `.failed` reasons in doctor.

## Q1. bash portability of the scope idiom

Measured on bash 3.2.57 (macOS `/bin/bash`), 4.4.20 and 5.1.8 (two cluster login nodes, since no
bash 5 is installed locally), under `LC_ALL=C` and `en_US.UTF-8`, with `set -euo pipefail`:

| value | 3.2 / 4.4 / 5.1, `C` and UTF-8 |
| --- | --- |
| `a/b c$..;x` | `value-a_b_c_.._x` |
| `..` / `...` | `value-..` / `value-...` |
| `-rf` / `-` | `value--rf` / `value--` |
| `../../etc` | `value-.._.._etc` |
| `a?b[c]` / `~user` / space / tab / newline | `value-a_b_c_` / `value-_user` / `value-_` / `value-x_y` / `value-a_b` |
| `é` | **`C`: `value-__` (bytes). UTF-8: `value-é` on 3.2 and 4.4, `value-_` on 5.1** |

The `[^…]` and `[!…]` forms agree everywhere. The `é` row is the defect. Range expressions follow
the locale's collation until bash 5.0 turned `globasciiranges` on by default. The explicit-list form
gave `value-_` under UTF-8 on all three versions, and `value-__` under `C`. A purely ASCII key also
makes `${#key}` a byte count.

The off test `[[ -z "${UVM_REPAIR:-}" || "${UVM_REPAIR}" == 0 ]]` is safe under `set -u`, because
the right operand runs only when the variable is set. It returns off for unset, empty and `0`, and on
for `00`, ` 0`, `1` and `false`, the same on all versions. The docs must say that `00` and `false`
mean on.

Danger and collisions. `/` is always replaced. The `job-` or `value-` prefix means a key never
begins with `-` or `.`, and is never `.` or `..`. `value-` (an empty value) cannot arise, because
empty means off. Distinct values can collide (`a/b`, `a b`, `a_b`), which only means a shared scope.
`job-*` and `value-*` never collide. Length: `NAME_MAX` is 255 bytes, and the key gains `.failed`
plus a temp suffix. Bound it with `(( ${#key} <= 200 ))`, as a builtin. Past the bound, either die
naming the variable or truncate. Dying matches the existing `UVM_LOCK_TIMEOUT` form check.

## Q2. Slurm semantics

Cited from slurm.schedmd.com:

- `sbatch`: `SLURM_JOB_ID` is "The ID of the job allocation."
- `srun`: "Job id of the executing job." `SLURM_JOB_ID` is also srun's input (`--jobid`), so a step
  inherits the allocation's id.
- `salloc` shells carry `SLURM_JOB_ID`, as the heterogeneous-jobs example shows.
- `SLURM_CLUSTER_NAME` is set by `sbatch` and `srun`.
- Arrays: each task "will have a unique JobId", with `SLURM_ARRAY_JOB_ID` shared. The example gives
  tasks 36, 37 and 38 under array id 36.
- Heterogeneous jobs: each component has its own job id, but "the `SLURM_JOB_ID` environment
  variable will contain the job ID of the heterogeneous job leader", even in a `--het-group=1` step.
  Component ids are in `SLURM_JOB_ID_HET_GROUP_<n>`.
- `MaxJobId` defaults to 67,043,328, and "Once MaxJobId is reached, the next job will be assigned
  FirstJobId". Federated ids are unique across the federation.

What follows, reasoned from those:

- One allocation is one scope: the batch script, its `srun` steps and every task.
- An array is one scope per task: no shared check, and the walk serialization in defect 2.
- A heterogeneous job is one scope (the leader's id). Outcomes live under the per-architecture root,
  so a job spanning two architectures checks each architecture's tree exactly once, which is correct.
- Independent clusters on shared storage collide (defect 3). Wraparound can resurrect an old id after
  years. On a purged root the old `.ok` is long gone; on a non-purged one it is a false clean, which
  pruning removes.

## Q3. Atime of an outcome file

POSIX `read()` marks the access timestamp for update when it transfers data. `stat()`, and `open()`
without a read, do not. bash's `-e` and `-f` tests call `stat()`. An `.ok` file is never opened, so
its atime equals its mtime and ctime at creation, and any atime-, mtime- or ctime-keyed purge ages it
from birth.

A `.failed` file is read on every failed arrival, by each waiter, and, if doctor prints reasons, by
every `uvm doctor`. Under `relatime` the first read after creation updates atime, and later reads
update it at most once a day. Two effects follow:

- Under a constant value, a failed outcome hit at least once per purge window never ages out. This
  matches GOAL R10's "stands until the value changes" and needs no new remedy.
- Doctor reading reasons would keep every failed outcome alive under the purge, including inert ones
  from finished jobs, wherever a prologue runs doctor daily, as `README.md` recommends.

Doctor should therefore name failed outcomes from the glob alone (a `readdir`, which touches no file
atime) and print the path for `cat`. Or it reads them, and the docs say the purge will not clear them.

## Q4. Accumulation

The steady state on a purged root is rate × window. A 10k-task array each week over a 30-day window
holds about 43k files, 4% of a 1M-inode quota and 2% of 2M. Each file is an inode, and on Lustre an
MDT entry. A per-name `stat` in a 43k-entry directory is hashed and cheap. A doctor glob reads all
43k entries.

A non-purged root has no steady state: 10k a week is 520k a year. A no-egress array makes the same
count of `.failed` files, and doctor would print one WARN per file.

- **(a) Purge, `uvm clean outcomes`, and docs.** No code. It relies on users following "leave
  `UVM_REPAIR` unset on non-purged storage", which a copied job template defeats, and it leaves the
  wraparound and doctor-flood cases open.
- **(b) Holder-side prune.** `find "${dir}" -type f -mtime +30 -exec rm -f {} +` after recording, on
  the holder path only. It is POSIX on GNU and BSD, costs one fork per scope that already forks a
  walk and possibly `uv`, and touches no hot path. It keys on mtime, so read-refreshed atime is
  irrelevant. The age must be a literal (GOAL forbids a new variable), well above any walltime.
  Pruning a live `.ok` costs a re-check. Pruning a live `.failed` re-admits one retry in that scope,
  so 30 days makes both effectively impossible.

**Recommendation:** (b) with a literal 30 days. Keep `uvm clean outcomes`. Doctor reports failed
outcomes as a count plus at most a few named lines.

## Q5. Surface census (R14)

**`bin/uv-manager`**

- `:168` banner "provisioning lock". The section now serves two locks, so rename it, and update the
  section list at `AGENTS.md:94-96`.
- `:240` hardcodes `.install.lock`, so the lock path becomes an argument.
- `:286`, `:307`, `:310`, `:315` and `:335` say "provisioning lock" or "If nothing is provisioning
  this tree". Each must name the lock in use.
- `:1137-1139`, "Nothing acquires the lock this late in the dispatch path today". This becomes
  **false**: repair acquires after `uvm_ensure_uv`, and the pre-exec `uvm_unlock` becomes
  load-bearing.
- `uvm_doctor`:
  - `:944-951` hardcodes `.install.lock`. Its remedy "once nothing is provisioning this tree, remove
    it with uvm clean lock --yes" is now **incomplete**, because that command also removes a live
    repair lock.
  - `:985-1007` remediation block must name `UVM_REPAIR=1` as the in-job route.
- `uvm_clean`:
  - `:1017` sets a single target, and `:1020` is the "expected one of" list.
  - The dry run at `:1028-1033` says "provision beside it" and "nothing is provisioning", and reads
    one owner line. It must print both owner lines and add `outcomes`.
- `uvm_help`:
  - `:1057` and `:1062` (the clean list) need `outcomes`.
  - `:1070-1071` "before installing without it" is **false** for repair waiters, which die.
  - Add a `UVM_REPAIR` row covering values, scope and the per-run advice.

**`README.md`**

- `:137-139`, "serialize on an atomic `mkdir` lock … installs for itself". Singular.
- `:186`, the table row "`lock` removes only the provisioning lock". This is **false**: it now
  removes both. Add an `outcomes` row.
- `:204-206`, "the one remaining problem the wrapper cannot fully solve". Point at the knob.
- `:374-375`, "The wrapper's own provisioning lock". Add the repair lock.
- `:415-433`, mitigations. Add a knob item covering what repair catches and concedes (cache,
  wholly deleted distributions, interpreter damage outside `import json, os, ssl`), the network it
  needs (PyPI and `files.pythonhosted.org` for tools, `releases.astral.sh` for interpreters), and
  its reach (`uv`/`uvx` under any subcommand, not a tool by its own name).
- `:514-516`, "Keep `uv run` off the hot path". Reconcile it with the knob's one-`stat` cost.
- Troubleshooting:
  - `:543-558`, "waiting for the provisioning lock". Add a "waiting for the repair lock" entry,
    including that a repair waiter fails at the timeout.
  - `:564-565`, the `ImportError` line. Name the knob.
  - Add the failed-outcome message.
- `:585-588`, the reference table. Add `UVM_REPAIR`. Fix the `UVM_LOCK_TIMEOUT` row, "before
  installing without it".
- Design notes `:437-474`:
  - `:463-464` "`mkdir` for the provisioning lock".
  - `:466-474`. Add a note on the scope choice: the job id ends a record with the job, while a
    constant value reads clean on a damaged tree. Add a second note that `uvx <script>.py` is not a uv
    form.

**`etc/uv-manager.conf.example`**

- `:71-79`, the `UVM_LOCK_TIMEOUT` block: "before installing without it", "at the timeout it
  downloads and installs for itself". Add that repair waiters fail at the timeout.
- Add a commented `UVM_REPAIR` entry in §3, with values, scope, the false-clean advice and the
  network it needs.

**`share/modulefiles/uv/main.lua`**

- `:78` doctor usage line.
- `:89-92`, "is not detected by uv. Run `uv-manager doctor`". Add `UVM_REPAIR=1` in job scripts.

**`AGENTS.md`**

- `:89`, "Currently one: the provisioning-lock race". Updated if R12 adds a sibling.
- `:94-96`, the section list.
- `:98-114`, the execution-model diagram. Add a repair step between `uvm_export_env` and the
  branches.
- `:146-160`, "**The provisioning lock is `mkdir`**". Change it to two locks; a rank never holds
  both.
- `:162-173`. Cover both.
- `:175-179`, "Nothing acquires the lock that late today". This becomes **false**.
- `:194-202`, "At `UVM_LOCK_TIMEOUT` a provisioning waiter (`proceed`) …". Name the repair waiter.
- `:253-266`. Add the repair function and the outcome store to the high-risk table.
- `:273`, "There is one so far". Same as `:89`.
- Unchanged: the `exec` invariant `:130-132` stays true, because repair runs before the exec.

**`.agents/factory/invariants.md`**

- `:22-26` high-blast list. Add the repair function.
- `:99` "## 5. Provisioning lock" and every singular bullet through `:166`.
- `:130-133` "Nothing acquires the lock that late". This becomes **false**.
- `:160-166`: "`uvm clean lock` removes the lock directory and nothing else". This becomes
  **false**: it removes two.
- §7 is unaffected if repair output goes to stderr.
- §10: no fork on the off path, and the scope key built by builtins.
- §2 `:47`, "Exactly two commands do not `exec`", stays **true**.

## Q6. Doctor's exit-status rule

Under the rule at `bin/uv-manager:814-820`, a failed outcome describes state, not the tree's
working condition. Doctor's own walk FAILs any damage that remains. A standing repair lock is seen by
every rank while one rank repairs. Both are WARN. Drafts:

```
WARN  repair lock standing: ${rlock} (owner: ${holder:-<none recorded>}). Its holder may still be running; once nothing is repairing this tree, remove it with uvm clean lock --yes.
WARN  repair failed for scope ${scope}: ${uvm_root}/.repair/${scope}.failed. Calls with UVM_REPAIR set in that scope exit non-zero and do not retry; once the cause is fixed, remove it with uvm clean outcomes --yes.
```

The provisioning WARN's tail should become "once nothing is provisioning or repairing this tree".

## Recommendations

1. Use an explicit character list, and bound the key at 200 bytes.
2. Use the key `job-${SLURM_CLUSTER_NAME:+${SLURM_CLUSTER_NAME}-}${SLURM_JOB_ID}`.
3. Settle cross-scope serialization before PLAN. Options:
   - Key arrays on `SLURM_ARRAY_JOB_ID`.
   - Let a waiter accept any repaired outcome written after its own arrival.
   - Accept the limit and document it, with R12 measuring `w` for a no-damage walk.
4. Add the holder-side 30-day prune.
5. Doctor names failed outcomes from the glob and caps the lines.
6. On NFS, a lock winner's re-test of the outcome can miss a just-written file for up to
   `acdirmax` (negative-lookup cache). The cost is one redundant walk or one retry. Lustre and GPFS
   are coherent. Document it; no code.
7. `uvm clean outcomes` during a live repair can make the holder's rename fail. Its dry run says
   "once nothing is repairing".

## Open questions

- Which mitigation for defect 2? This is a GOAL-level question, because R7 is silent on distinct
  scopes.
- Does reading `SLURM_CLUSTER_NAME` breach "no other scheduler variable is read"? It is the same
  scheduler, and it is the job id's namespace.
- Should an over-long `UVM_REPAIR` die or truncate?
