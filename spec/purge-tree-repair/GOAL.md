# GOAL — `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** purge-tree-repair
- **kind:** feature
- **appetite:** big

## Problem

A scratch purge is per-file on access time, so it removes a tool environment or a managed
interpreter piecemeal while uv still records it as installed. uv runs no integrity check on an
environment it believes is present. It execs the half-deleted tree, and the user gets an
`ImportError`. `uvm_doctor` finds this and prints commands for a human (`bin/uv-manager:984-1008`).
Nobody reads that from a compute node at 03:00, and automation cannot act on it.

Who it hurts is a user inside a batch job. The requirement, in the maintainer's words: put `uv run
...` in a script that launches an application and have it just work, rehydrating whatever the purge
removed, with `UVM_REPAIR` as the approval to do the expensive part. It runs where it runs, inside
the job on the node doing the work, never as a step outside job submission. That clause is
load-bearing. A bring-up subcommand was proposed and rejected: `uvm repair` in a login-node prologue
repairs `$UVM_ROOT/x86_64/` while the job runs against `$UVM_ROOT/aarch64/`. A knob on the dispatch
fires inside `uv`/`uvx` after `uvm_init` has resolved the platform key on the executing node, so it
is architecture-correct by construction.

**Pre-existing** on `main`: the gap has been there since `uvm_doctor` was written to report rather
than repair. The decisions record is
[`spec/purge-resilient-run/research/00-digest.md`](../purge-resilient-run/research/00-digest.md);
the seed's *Notes* carry its findings and are not repeated here.

**Re-confirmed against `main` (`ee38682`), 2026-10-29.** The seed's scope holds. What has moved:

- **The lock it needed has shipped.** `lock-simplification` landed `uvm_acquire_lock ON_TIMEOUT
  PREDICATE [ARG...]` (the seed's R11, shipped there as R6), a timeout that fails any caller not
  passing `proceed`, `uvm doctor`'s WARN for a standing lock and `uvm clean lock`. It left two
  questions here, settled below: which lock repair takes, and with what timeout.
- **`uv run <script>` does not touch tool environments.** Measured on `main` with a real uv: with an
  installed tool gutted, `uv run --no-project t.py` exits 0. A script runs on an interpreter
  (managed or system) and, when it declares dependencies, on an environment uv keeps in its cache
  (`${UV_CACHE_DIR}/environments-v2/`, inside the tree). So the damage that breaks the maintainer's
  `uv run` is a managed interpreter, the seed's python arm, or the cache, which no seed criterion
  names. The tool arm is what breaks `uvx <tool>`.
- **`uvx <script>.py` is not a uv form.** uv 0.13.6 refuses it, rc 2, with `hint: Use uv run
  thing.py instead`. The two forms a user really types are `uv run <script>` and `uvx <tool>`.
- **The repair's hold time is not measured on a cluster.** The seed puts it at 1-30 s, but
  `--no-cache` is load-bearing (D3), so the tool arm re-downloads every tool's full dependency set
  and the python arm re-fetches interpreters. The timeout choice below leans on this, and R12
  records it.
- Line references still hold within a line or two: doctor's remediation block is `:984-1008`, the
  trampoline heredoc `:641-655`, `README.md:514` the "keep `uv run` off the hot path" advice. The
  stale **7 ms** figure D9 named is already 5 ms in both files.
  `share/modulefiles/uv/main.lua:89-92` still tells users partial damage "is not detected by uv. Run
  `uv-manager doctor`".

## Outcome / vision

The claim this cycle is shaped to support, to be made publicly:

1. A job launches the wrapped command under `srun` with `UVM_REPAIR` set, on a tree a purge has
   damaged. One rank gets the repair lock first.
2. That rank holds the lock and repairs the tree, once, in a single whole-tree pass.
3. It records that the repair ran for this job, then releases the lock.
4. The other ranks do **not** repair or walk the tree. They wait, see the record, and exec directly.
5. A fault leaves a clear failure: a rank exits non-zero naming the cause or the holder, and when
   the fault is a leaked lock, a human clears it with `uvm doctor` and `uvm clean lock`.

The forms covered are `uv run <script>`, scenario (P), whose damage is a managed interpreter, and
`uvx <tool>`, scenario (T), whose damage is an installed tool environment. `uvx <file>.py` is not a
uv form: uv refuses it and points at `uv run`. The knob fires on every invocation through `uv` or
`uvx`, whatever the subcommand, because it sits on the dispatch rather than on a subcommand. It does
not reach a tool run by its own name through a trampoline. Nothing is spent when the knob is unset,
and nothing beyond one existence test is spent by the second and later invocations in the same
job. The claim is spelled `UVM_REPAIR=1`.

## Acceptance criteria (the contract)

The seed's R1-R10 keep their numbers. R11 moved to `lock-simplification` and shipped; its number is
retired. R12-R14 are new. Drives run under `.agents/factory/bin/temp_root.sh`. Terms used below:

- **Fixture drive:** `temp_root.sh --offline`. The stub `uv` prints any non-`--version` command line
  on its stdout, so a repair command is countable as a line naming `tool upgrade` or `python
  install`. Since the clarification of 2026-10-29 (review cycle 2) the tool arm's line names `pip
  install`, one per damaged tool; read `tool upgrade` below as that line.
- **Real-uv drive:** a sandbox whose `versions/` holds a real uv, with PyPI and the interpreter
  download host reachable. The plan names how the sandbox gets the binary. During shaping, the
  installer's `mktemp -d` was denied by the agent sandbox, and seeding `versions/<ver>` and
  `current` from a local binary worked.
- **Damaged tree (T):** an installed tool with one module file and its `RECORD` removed. **(P):** a
  managed interpreter with a stdlib package removed. **(F):** for fixture drives, a planted tool
  directory with `pyvenv.cfg`, `uv-receipt.toml` and a `RECORD` naming a file that is absent, which
  `uvm doctor` reports as `missing 1 of 1 files`. For R12 the trees take the shapes a real purge
  leaves (clarification of 2026-10-29, review cycle 2): (P) removes every file of the interpreter
  and keeps its directories and links, which subsumes the stdlib package; (T) adds, beside the
  pinned tool, an unpinned tool installed at an older release with an unpinned `--with` package at
  an older release, damaged the same way, its `--with` package's `RECORD` included.
- **Scope:** what a scope's outcome is keyed by (R10): the batch scheduler's job id when one is
  present, else the literal value of `UVM_REPAIR`. In a Slurm array a repaired outcome is keyed by
  the array's id and a failed one by the task's own job id (clarification of 2026-10-29, review
  cycle 1).
- **Outcome:** the record the holder writes for a scope before it releases the lock: *repaired*
  (including "checked, nothing to repair"), or *failed* with the reason. The seed's "receipt" is a
  repaired outcome. Neither ever records that the tree is intact.

Every **Observed on main** status was recorded on 2026-10-29 at `ee38682`.

- **R1** — WHILE `UVM_REPAIR` is unset, empty or `0`, the wrapper SHALL run no damage check, take no
  repair lock, write no outcome, and behave exactly as it does today. The added cost on that path
  SHALL be builtin tests, with no fork.
  *Checked by a fixture drive on tree (F) with the knob unset: 16 concurrent `uv --version` ranks
  all exit 0 printing the fixture version, no repair command line appears on either stream, and the
  root holds no outcome and no lock. The hot path is checked by 200 warm calls per arm against
  `main`, as `lock-simplification`'s review measured, which measures the unset path's added cost,
  bash parsing the added code, and the documentation states it (clarification of 2026-10-29, review
  cycle 2). The reviewer reads that the unset path forks nothing. **Observed on main: green** — 16/16 fixture version, 0
  repair lines, root holds only `bin cache current python tools versions`. Expected green after.*
- **R2** — WHERE `UVM_REPAIR` is set and an outcome for the current scope exists, the invocation
  SHALL do no filesystem work beyond that test and the read of a failed outcome's reason: no
  detection walk and no lock. On a repaired outcome it SHALL proceed to the user's command; on a
  failed one it SHALL exit non-zero with the recorded reason and run nothing (R9).
  *Checked by a fixture drive on tree (F) with a repaired outcome for the scope planted (the plan
  names its path): rc 0, the fixture version, zero repair lines, and no lock created. With a failed
  outcome planted instead: rc non-zero, the planted reason on stderr, the command not run, zero
  repair lines. It is paired with the same drive with no outcome, which must repair (R3, R7). The
  pair is the gate, because the first half alone is satisfied by a wrapper that ignores the knob.
  The reviewer reads that the outcome test precedes every walk. **Observed on main:** the repaired
  half is vacuously green (the knob is ignored); the failed half is red — rc 0 and the fixture
  version, since nothing reads an outcome; the paired half is red under R7.*
- **R3** — WHERE `UVM_REPAIR` is set and no outcome for the scope exists, the wrapper SHALL run the
  detection `uvm doctor` performs, repair what it detects (R4, R6), record a repaired outcome for
  the scope, and then run the user's command. It SHALL run no repair command when it detects no
  damage. It SHALL leave the selected uv version and `current` as they were, since a repair that
  provisions does so through the pin (invariant §4). What it catches is what `uvm doctor` catches. A
  distribution deleted entirely, a managed interpreter damaged outside `import json, os, ssl`, and
  anything inside uv's cache are conceded and documented (R14). Cache damage is deferred to
  [`issues/uv-cache-purge-damage.md`](../../issues/uv-cache-purge-damage.md) (M3).
  *Checked by real-uv drives. (T): `UVM_REPAIR=<scope> uvx <tool> --version` exits 0 printing the
  tool's version; every path in the manifest captured before the damage exists again; the console
  script runs. (P): `UVM_REPAIR=<scope> uv run --no-project -p <ver> t.py`, where `t.py` imports the
  removed package, exits 0 with the script's output. A repaired outcome exists after both. Then a
  fixture drive with the knob set on an intact tree shows zero repair lines and a repaired outcome
  written. Last, with `UVM_PIN` naming the installed version and the fixture offering a newer one,
  `current` is unchanged. **Observed on main: red.** (T) pyflakes 3.2.0 with `checker.py` and
  `RECORD` removed: `UVM_REPAIR=1 uvx pyflakes --version` gives rc 1, nothing on stdout, and the
  package raises `ImportError: cannot import name 'checker'`. (P) cpython 3.12 with `json/` removed,
  under `UV_PYTHON_PREFERENCE=only-managed`: `UVM_REPAIR=1 uv run --no-project -p 3.12 t.py` gives
  rc 2 and `ModuleNotFoundError: No module named 'json'`. `uvm doctor` FAILs both trees.
  (P) is also driven on the shape a real purge leaves (clarification of 2026-10-29, review cycle 2):
  every file of the interpreter removed, its directories and links kept; then only its `bin/` files;
  then every file with the minor-version link gone too; and with a tool on that interpreter damaged
  as (T), through `uvx <tool>`, so both arms run. Each exits 0 with the expected output and leaves
  the interpreter importing `json, os, ssl`. **Observed at `abf84b9`: red** — every file removed,
  `UVM_REPAIR=x uv run --no-project -p 3.12 t.py` gives rc 2 (`missing a _sysconfigdata_ file`),
  runs no repair and records the scope repaired.*
- **R4** — Tool environments SHALL be repaired one damaged tool at a time with `uv pip install
  --python <tools>/<tool>/bin/python --reinstall --no-cache <name>==<version>...`, naming every
  distribution in the tool's environment at the version its dist-info directory names, and SHALL NOT
  be repaired by reconstructing a spec from `uv-receipt.toml`, which the repair reads only to refuse
  and never writes (clarification of 2026-10-29, review cycle 3). A tool's version pin, its `--with` packages and its receipt, byte for byte, SHALL survive
  the repair, and every distribution in a damaged tool's environment SHALL keep its installed
  version whether the tool is pinned or not. A tool that is not damaged SHALL NOT be touched. The arm
  SHALL NOT run against a tool whose `bin/python` does not run inside the tool's own environment, and
  a distribution installed from a URL, git or path source SHALL fail the scope naming the tool and
  the distribution (clarification of 2026-10-29, review cycle 2). So SHALL a damaged tool whose
  receipt records a requirement (the tool or a `--with` package), a constraint or an override from a
  directory, path, editable, git or URL source, naming the tool and what was found, before any `uv`
  call for that tool; a tool with no receipt is still repaired (clarification of 2026-10-29, review
  cycle 3).
  *Checked by a real-uv drive: install `<tool>==<older version> --with <pkg>`, damage it as (T),
  repair through the knob, and assert that the tool reports the pinned version, that `<pkg>` imports
  from the tool's interpreter, and that `uv-receipt.toml` is byte-identical. Then a real-uv drive on
  the trees a purge leaves: an unpinned tool installed at an older release with an unpinned `--with`
  package at an older release, damaged as (T) with that package's `RECORD` gone too, beside a
  healthy unpinned tool at an older release and a pinned tool with `--with`, also damaged. After the
  knob-set call every tool's dist-info listing is what it was, no second dist-info directory exists,
  every receipt is byte-identical, and the damaged tool runs. A dependency whose whole dist-info
  directory is gone comes back. A tool holding a distribution installed from a local path fails the
  scope naming both, and records no repair. A fixture drive shows the command carries `--no-cache`,
  names no healthy tool, and that a tool whose `bin/python` does not run fails the scope naming it.
  The reviewer reads that the named command is the only tool repair. Then a real-uv drive on tools
  installed from each source a receipt records (a directory; a wheel and an sdist by path; editable;
  git; a URL), each as the tool and as a `--with` package, and with a URL constraint and a URL
  override: each damaged as (T) with every `direct_url.json` removed, one at a time, fails its scope
  naming the tool and what its receipt records, runs no `uv pip`, leaves the damage, and keeps its
  receipt byte-identical. Tools installed with each of `--index`, `--index-url`,
  `--extra-index-url`, `--default-index` and `--find-links`, damaged the same way, are repaired with
  their versions kept and their receipts byte-identical. A fixture drive shows registry receipts
  repaired: pinned, unpinned, with a `--with` package, with extras, a marker spelling a source key,
  a registry constraint, every index option, and an empty receipt (clarification of 2026-10-29,
  review cycle 3, revised the same day by the amended ruling). **Observed on main: not
  constructible** (no repair). **Observed at `abf84b9`: red** — the unpinned tool moves from 3.1.0
  to 4.1.0, the arm exits 1 on the missing `RECORD` and leaves two dist-info directories, and the
  healthy unpinned tool moves from 2.11.1 to 2.15.0.*
- **R5** — IF a tool directory is missing `pyvenv.cfg`, THEN the wrapper SHALL NOT run the tool
  repair, SHALL name that tool and the reason on stderr, and SHALL fail as R9 requires. The base
  interpreter's `site-packages` SHALL be unchanged.
  *Checked by a real-uv drive with two tools, one damaged as (T) and the other missing `pyvenv.cfg`:
  rc non-zero, stderr names the orphan and `pyvenv.cfg`, the listing of the base interpreter's
  `site-packages` is identical before and after, and the scope's outcome is *failed* naming the
  orphan. A fixture variant shows no `tool upgrade` line. **Observed on main: not constructible.***
- **R6** — Managed pythons SHALL be repaired only when managed pythons are installed and damage is
  detected in one, never unconditionally.
  *Checked by fixture drives: with no managed interpreter, no `python install` line; with a planted
  interpreter stub that passes the stdlib probe, none; with one that fails it, exactly one. An
  install is a real directory under `python/`, never the minor-version link, and one whose binary
  is gone is damaged too: a planted install with no binary gives exactly one line naming its key,
  and a dangling python shim that reaches an install through the minor-version link names that
  install's key (clarification of 2026-10-29, review cycle 2). Repair of a real damaged interpreter
  is R3 (P). **Observed on main: not constructible.***
- **R7** — WHEN several processes in one scope find no outcome, exactly one SHALL detect and repair.
  The others SHALL wait on the repair lock, test once a second whether an outcome exists for the
  scope, and SHALL NOT detect or repair. On a repaired outcome they SHALL run their commands; on a
  failed one they SHALL exit non-zero promptly with the holder's reason (R9). The holder SHALL
  record the outcome before it releases the lock.
  *Checked by fixture drives on tree (F): 16 concurrent `SLURM_JOB_ID=100 UVM_REPAIR=1 uv --version`
  ranks, with the repair command slowed past several poll intervals (the plan names how). Exactly
  one repair line appears across all ranks, 16/16 exit 0 printing the fixture version, one repaired
  outcome exists, and no lock is left. With the slowed repair made to fail instead, exactly one
  repair line appears, 16/16 exit non-zero, and the 15 waiters' stderr carries the holder's reason
  within a few seconds of the failure. The reviewer reads that the walk runs only once the lock is
  won. R12 carries it across nodes. **Observed on main: red** — with `UVM_REPAIR=t` and with
  `SLURM_JOB_ID=100 UVM_REPAIR=1`, 16/16 rc 0 with the fixture version, doctor FAILs the planted
  tool, 0 repair lines where exactly 1 is required, no outcome.*
- **R8** — WHEN a repair completes, the user's command SHALL run and the exit status SHALL be that
  command's own. All repair output, uv's included, SHALL go to stderr.
  *Checked by a fixture drive where the repair succeeds and the user's command exits 7 (the plan
  names how the stub tells the two apart): rc 7, stdout exactly the command's own output, every
  repair line on stderr. Also by R3 (T): stdout is exactly the tool's version line. **Observed on
  main:** the fixture's own output and status pass through, vacuously; the paired red is R3 (T)'s rc
  1.*
- **R9** — IF the repair cannot proceed or cannot finish, THEN the wrapper SHALL report the cause on
  stderr, exit non-zero, and SHALL NOT run the user's command. A holder whose repair fails — a
  refusal under R5, a repair command that fails — SHALL record a failed outcome for the scope with
  its reason before it releases, and the ranks waiting on it and arriving after it SHALL exit
  non-zero with that reason. Nobody SHALL retry within the scope. A holder that dies records
  nothing, so its waiters SHALL exit non-zero at `UVM_LOCK_TIMEOUT` naming the lock and its owner
  line, the decided contract.
  *Checked by fixture drives. (a) The stub fails `tool upgrade`: rc non-zero, a `uv-manager:` line
  naming the failed repair, the user's command not run (a marker file it would write is absent), a
  failed outcome recorded, and a second call in the same scope failing with the same reason and no
  repair line. (b) A planted repair lock never released, `UVM_LOCK_TIMEOUT=3`: rc non-zero shortly
  after 3 s, stderr names the lock and the planted owner line, command not run, plant intact. (c)
  Four ranks, the holder killed with `KILL` mid-repair: every waiter exits non-zero at the timeout
  naming the lock and owner line, no outcome exists, `uvm doctor` WARNs the repair lock, and after
  `uvm clean lock --yes` the next knob-set call repairs and exits 0. (d) Four ranks, the holder's
  repair command fails: R7's failing variant. **Observed on main: not constructible** as written,
  since `main` reads no outcome and takes no repair lock. With a lock planted at the stand-in path
  `.repair.lock`, `UVM_LOCK_TIMEOUT=3 UVM_REPAIR=1 uv --version` exits 0 in 0 s.*
- **R10** — The knob's accepted values SHALL be explicit and documented: unset, empty and `0` mean
  off, and any other value means on. A value whose record name would pass 200 bytes SHALL be refused
  with a message saying so, and the limit SHALL be documented with the values (clarification of
  2026-10-29, review cycle 2). The scope SHALL be the batch scheduler's job id when one is
  present — at least Slurm's `SLURM_JOB_ID`; the plan may add others — and the literal value of
  `UVM_REPAIR` when none is. So `UVM_REPAIR=1` inside a job checks once per job, and its outcome,
  failed or repaired, ends with the job. In a Slurm array a repaired outcome SHALL be shared by
  every task, keyed by `SLURM_ARRAY_JOB_ID`, and a failed one SHALL end with its task, keyed by the
  task's `SLURM_JOB_ID`, so the array's next task checks again; the documentation SHALL say what an
  array shares and that a repaired outcome outlives a purge landing partway through the array. The
  documentation SHALL tell users outside a batch job to give a per-run value, because a constant
  value reuses one outcome across purges: an outcome file is only tested, so its atime is its
  creation time, and a purge can take older tool files while it survives, which reads as clean on a
  damaged tree. Under a constant value a failed outcome likewise stands until the value changes.
  *Checked by fixture drives on tree (F), whose damage the stub repair never removes, so every fresh
  detect repairs again: `UVM_REPAIR=0` gives zero repair lines, no outcome and no lock;
  `SLURM_JOB_ID=100 UVM_REPAIR=1` twice gives one repair line in total; then `SLURM_JOB_ID=101
  UVM_REPAIR=1` gives one more (a fresh detect for a new job). Two tasks of one array give one
  repair line and one repaired outcome under the array's id. With the repair failing, two tasks of
  an array each try once, each recording a failed outcome under its own job id, and a third task
  then repairs; ranks of two tasks racing on a failing repair give exactly two repair lines. With no
  `SLURM_JOB_ID`, `UVM_REPAIR=a` twice gives one, then `UVM_REPAIR=b` one more. `temp_root.sh uvm
  help | grep -c UVM_REPAIR` prints at least 1. **Observed on main: red** — every one of these
  drives gives 0 repair lines and rc 0, and the help census prints 0. `UVM_REPAIR=0` gives rc 0 and
  the fixture version, vacuously green.*
- **R11** — *Retired.* Moved to [`lock-simplification`](../lock-simplification/GOAL.md) as R6 and
  shipped there as the required predicate argument of `uvm_acquire_lock`.
- **R12** — WHEN a job launches N ranks under `srun` across two or more nodes with `UVM_REPAIR=1`
  against a damaged tree on a parallel filesystem, exactly one rank SHALL repair while holding the
  repair lock and then release it. Every other rank SHALL run no repair and exec its command once
  the repaired outcome appears. Every rank SHALL exit 0 with the command's expected output, and no
  lock SHALL be left standing. This holds for `uv run <script>` on tree (P) and for `uvx <tool>` on
  tree (T).
  *Checked by a Slurm drive, extending `tests/lock-race.sh --launch srun` or as a sibling under
  `tests/` (the plan's choice), on a Lustre filesystem across 2 nodes and a GPFS filesystem on 1
  node, at 64 ranks or more per scenario. Its summary holds counts only, committed as evidence the
  way `lock-simplification`'s was: repairs=1, outcomes=1, `rc_hist` all 0, `stdout_hist` the
  expected output, nodes, locks left 0, the holder's repair seconds, the waiters' added wait, and
  notice lines. For (T) it also holds the unpinned tool's and its `--with` package's versions after
  the repair, the count of distributions left with a second dist-info directory, and how many
  receipts are byte-identical; for (P) and (T), whether the damage is gone. A fault scenario kills
  the holder with `KILL` and records R9 (c)'s outcome, then a
  clean pass after `uvm clean lock --yes`. The repair needs `pypi.org` and `files.pythonhosted.org`
  for the tool arm and, for the python arm, the host uv 0.13.6 names in `uv python list
  --only-downloads --show-urls`: `releases.astral.sh`, serving python-build-standalone's GitHub
  release assets directly, with no redirect to `github.com`. Egress is present from compute nodes on
  both target filesystems' clusters, probed for PyPI, `files.pythonhosted.org`, `astral.sh` and
  `github.com`; `releases.astral.sh` is a separate host that the drive's (P) scenario exercises
  first. Where egress is missing, the drive records R9's failure instead. Taken on trust. **Observed
  on main: not constructible**; the local reds of R3 and R7 stand for it.*
- **R13** — A repair SHALL NOT wait on, or be failed by, a provisioning hold, and a provisioning
  call SHALL NOT wait on a repair hold. No call SHALL hold both at once. A repair waiter at
  `UVM_LOCK_TIMEOUT` fails as R9 requires and never proceeds. The repair hold follows
  `lock-simplification`'s contract: only its creator removes it, `uvm doctor` reports it standing
  with its owner line, `uvm clean lock` removes it without the tree, and its messages call it the
  repair lock, never the provisioning lock.
  *Checked by fixture drives. (a) `.install.lock` planted and never released, uv present, tree (F),
  `UVM_LOCK_TIMEOUT=10`, knob set: rc 0 in under 5 s, one repair line, plant intact. (b) A repair
  lock planted and never released, no uv provisioned, knob unset, `UVM_LOCK_TIMEOUT=10`: rc 0 in
  under 5 s with the fixture version. (c) `uvm doctor` names the planted repair lock and its owner
  line; `uvm clean lock --yes` removes it and `current` still resolves. (d) A knob-set waiter's
  notice and timeout lines say "repair lock" and never "provisioning lock". **Observed on main:**
  (a) red — rc 0 in 0 s with the plant intact, but 0 repair lines where one is required; (b)
  vacuously green — rc 0 in 0 s with the fixture version, against a stand-in `.repair.lock`; (c) red
  — `uvm doctor` does not mention the stand-in lock; (d) not constructible.*
- **R14** — Read per surface (clarification of 2026-10-29, review cycle 2): `README.md` SHALL carry
  the full list below; the `uvm_help` heredoc, `etc/uv-manager.conf.example` and
  `share/modulefiles/uv/main.lua` SHALL each carry the knob, its values, its scope and the length
  limit, and point to `README.md` for the rest. The surfaces `AGENTS.md` § *Same-commit rule* names
  SHALL document the knob and its values, its scope (the job id, else the literal value, with the per-run advice and the false-clean
  reason R10 gives), what repair detects and what it concedes (cache damage among them), the network
  it needs, the repair lock (`uvm doctor`, `uvm clean lock`), and its reach: `uv` and `uvx` under
  any subcommand, not a tool run by its own name through a trampoline. They SHALL also say that `uvx
  <script>.py` is not a uv form. That covers the `uvm_help` heredoc, `README.md` (the reference
  table, the purge section's mitigations and troubleshooting lines, the design notes),
  `etc/uv-manager.conf.example` and `share/modulefiles/uv/main.lua`. Because a second lock overturns
  §5's single-lock wording, it also covers `AGENTS.md` § *Invariants* and
  `.agents/factory/invariants.md` §5. `uvm doctor`'s remediation block SHALL name the knob.
  *Checked by `git grep -c UVM_REPAIR -- bin/uv-manager README.md etc/uv-manager.conf.example
  share/modulefiles/uv/main.lua AGENTS.md .agents/factory/invariants.md` naming all six files, each
  hit read by the reviewer against the list above, and by the R10 help census. **Observed on main:
  red** — 0 hits in all six files (`git grep` rc 1); help census 0.*

## Non-goals (no-gos)

- **A bring-up subcommand** (`uvm repair` or similar). Rejected during planning for repairing the
  wrong architecture's tree. A plan re-proposing it owes that a rebuttal.
- **Detection past `uvm doctor`'s floor.** A distribution deleted entirely and an interpreter
  damaged outside the stdlib probe stay undetected and are documented as such (R3, R14).
- **uv's cache and project `.venv` directories.** Script and `--with` environments under
  `${UV_CACHE_DIR}` and a project's own `.venv` are not repaired; the limit is documented (R14). The
  cache is deferred to [`issues/uv-cache-purge-damage.md`](../../issues/uv-cache-purge-damage.md),
  whose R1-R4 carry it. A project `.venv` lives outside the tree the wrapper owns.
- **Tools invoked by their own name.** The trampoline execs the shim directly and never enters the
  wrapper. Documented, not fixed.
- **Per-tool repair from the receipt.** Rebuilding a tool from its receipt is ruled out by D3: the
  receipt holds what was asked for, not what was resolved, so a rebuilt spec loses a tool's pin and
  its `--with` packages. One orphan still blocks the tool arm (R5). Amended 2026-10-29, review cycle
  2: the repair is per damaged tool, pinned from the environment's own dist-info names (R4).
- **Making callers without the knob wait for a repair.** R1 takes no lock when the knob is unset, so
  such a call, from another job or an interactive shell, may run against a tree mid-repair.
- **Any change to the lock contract.** Nothing breaks a lock, reads liveness or qualifies release by
  ownership; the rejected designs listed in `spec/lock-simplification/GOAL.md` § *Non-goals* bind
  the plan. A human clearing a live repair lock admits a second repairer; the dry run says so, and
  that is outside the contract.
- **An offline repair mode.** Where compute nodes have no egress, the repair fails per R9.
- **No new environment variable** beyond `UVM_REPAIR`. Repair reuses `UVM_LOCK_TIMEOUT`.
- **Concurrent pins.** Differently-pinned calls racing for `current` stay with
  `issues/pin-holds-against-concurrent-pins.md`, unchanged by this cycle.
- **No committed suite beyond the R12 drive.** The other *Checked by* drives are this cycle's gates
  and are not committed.

## Clarifications

Rulings at the GOAL gate are the foreman's, as the maintainer's delegated judge for this effort.

- **M1 — Q:** Does repair take `.install.lock` or a lock of its own? — **A:** Its own, beside
  `.install.lock` in the same per-architecture root. The two locks guard disjoint parts of the tree
  (`versions/` and `current`, against `tools/` and `python/`), so sharing one serializes work that
  does not conflict. Sharing also costs correctness under the contract: a repair waiter must fail at
  its timeout, so behind a shared lock it would fail because of an unrelated slow download, and a
  provisioning waiter past `UVM_LOCK_TIMEOUT`, or one whose predicate came true, would exec
  mid-repair. The `uvm clean lock` chain (`lock-simplification` research Q5) survives either answer;
  a lock of its own keeps a chain within one class. The cost, accepted: `uvm_acquire_lock` gains a
  lock-path argument, `uvm doctor` and `uvm clean lock` cover two locks, the messages name which
  lock, and §5's single-lock wording changes (R13, R14). A rank never holds both, since
  provisioning returns before repair begins (foreman, 2026-10-29).
- **M2 — Q:** What is the scope, and what does `UVM_REPAIR=1` mean? — **A:** `UVM_REPAIR=1` works as
  the maintainer will say it on stage. Unset, empty or `0` is off; any other value is on. The scope
  is the batch scheduler's job id when one is present — at least Slurm's `SLURM_JOB_ID`, and the
  plan may add others — and the literal value when there is none. This settles the
  receipt-versus-stamp contest the seed parked (D2): inside a job the record says "a check ran in
  this job" and ends with it, so a purge that eats it costs a re-check, never a false clean. It
  keeps the stage spelling, matches the seed's "nothing spent on the second and later invocations
  within the same job", and ends a recorded failure (M4) with the job. It overrides the seed's note
  that scheduler names stay out of the wrapper. Outside a job the documentation tells users to give
  a per-run value, and says why: an outcome is only tested, so its atime is its creation time, and a
  purge can take older tool files while it survives, so a constant value can read clean on a damaged
  tree. Amended: R2, R7, R10 (and R12's spelling); R10 carries the scope-derivation drive (foreman,
  2026-10-29).
- **M3 — Q:** Is damage inside uv's cache in scope? — **A:** No, conceded this cycle. A PEP 723
  script's environment lives in `${UV_CACHE_DIR}/environments-v2/`, inside the purged tree, and uv
  runs no integrity check on its unpacked archive store (D3), so `uv run <script>` can fail on a
  cache the repair never touches. Repairing it means clearing a shared cache under the lock, after
  which every rank rebuilds at once on a filesystem where uv's own `flock` may not hold. It is
  documented as conceded (R3, R14) and filed in this cycle's shaping as
  [`issues/uv-cache-purge-damage.md`](../../issues/uv-cache-purge-damage.md), whose R1-R4 carry the
  work. The claim covers a script on a managed interpreter (P) and an installed tool (T) (foreman,
  2026-10-29).
- **M4 — Q:** When a holder's repair *fails* (it does not die), do the others retry in turn or fail
  promptly? — **A:** Promptly. The holder records the scope's outcome, repaired or failed with its
  reason, before it releases. The waiters' predicate is "an outcome exists for this scope": on a
  repaired outcome they exec, on a failed one they exit non-zero with the holder's reason, and
  nobody retries within the scope. Without it, each waiter would win the lock in turn and repeat a
  deterministic failure (no egress, an orphan without `pyvenv.cfg`) until its timeout. A holder that
  *dies* records nothing, so its waiters fail at `UVM_LOCK_TIMEOUT` naming the lock, which is the
  decided contract. Amended: R2, R7, R9 (foreman, 2026-10-29).
- **M5 — Q:** Is the per-rank 30 s notice acceptable for a many-rank repair? — **A:** Yes,
  unchanged. Each waiter prints one five-line notice if a hold passes 30 s, about 640 lines at 128
  ranks. It is bounded at one per rank and fires only on the event a human should see, and changing
  it would edit the shared, high-blast-radius `uvm_acquire_lock` for a cosmetic gain. R12 counts the
  notice lines (foreman, 2026-10-29).
- **Q:** What is repair's timeout? — **A:** `UVM_LOCK_TIMEOUT`, no new knob. A repair waiter fails
  at its timeout, so the costs are asymmetric: too short turns a slow but healthy repair into N-1
  failed ranks, the worst outcome for the claim, and too long only delays the failure when a holder
  has died. The repair hold is unmeasured on a cluster and, with `--no-cache`, is a download, so a
  figure sized for a download is the right order. R12 records the hold; if it nears the timeout that
  is a finding, not a reason for a knob now (shaping reading, confirmed by the foreman, 2026-10-29).
- **Q:** What is the repair waiter's predicate? — **A:** One existence test for an outcome in the
  waiter's scope. It is cheap, has no side effects and follows the lock's rules for a predicate. It
  is the test R2 makes on arrival, so a rank arriving after the release takes the R2 path and no
  lock (shaping reading under M4, 2026-10-29).
- **Q:** What does a repair caller's message say? — **A:** "repair lock" wherever the provisioning
  path says "provisioning lock", with the same owner line and the same two-step removal; the
  notice's "if nothing is provisioning this tree" becomes "if nothing is repairing this tree"
  (shaping reading under M1, 2026-10-29).
- **Q:** Which invocations trigger repair, and which forms does the claim cover? — **A:** Every
  invocation through `uv` or `uvx`, any subcommand, checked once `uvm_ensure_uv` has returned and
  before the exec. The claim's forms are `uv run <script>` (scenario P, a damaged interpreter) and
  `uvx <tool>` (scenario T, a damaged tool), measured above to depend on different damage. The
  shorthand `uvx thing.py` is not a uv form: uv refuses it (rc 2, pointing at `uv run`), and with
  the knob set the wrapper would repair before uv refuses (foreman, 2026-10-29).
- **Q:** What does "repairs efficiently" commit to? — **A:** One rank walks and repairs, once per
  scope, with whole-tree commands and only the arms whose damage was detected (R3, R6, R7). Waiters
  never walk. R12 records the hold time; no threshold is set (shaping reading, 2026-10-29).
- **Q:** Is the R12 drive feasible from compute nodes? — **A:** Egress is present on both target
  filesystems' clusters, probed for PyPI, `files.pythonhosted.org`, `astral.sh` and `github.com`.
  uv 0.13.6 downloads interpreters from `releases.astral.sh` (its `--show-urls` listing; the host
  serves the python-build-standalone release assets itself, with no redirect to `github.com`). That
  host was not among those probed, so R12's (P) scenario exercises it first, and a failure there is
  R9's failure, not a gap in the claim (foreman, 2026-10-29; host read from uv during shaping).
- **Q:** (review cycle 1, F2) What does a Slurm array share? — **A:** A repaired outcome, not a
  failed one. The plan keyed the scope on `SLURM_ARRAY_JOB_ID`, so that a large array does not walk
  the tree once per task under the repair lock, and the review found that a failed outcome then
  stops every later task of the array, days later perhaps, without a try, on a failure that may have
  been transient egress. A repaired outcome stays array-wide, keyed by `SLURM_ARRAY_JOB_ID`; a
  failed one is written per task, keyed by the task's `SLURM_JOB_ID`, so the next task tries again,
  and a waiter in another task that sees no repaired outcome takes the lock and tries itself. For a
  failed outcome the scope is the task, so R9's "nobody retries within the scope" holds per task.
  The cost, accepted and documented: an array-wide repaired outcome outlives a purge that lands
  partway through the array. This departs from M2's "ends with the job" for an array's repaired
  outcome. Amended: R10 and its *Checked by*, the *Scope* term (foreman, 2026-10-29).
- **Q:** (review cycle 2, C2-F1) What is an installed interpreter, and when is it damaged? — **A:**
  A real directory under `python/`, never the minor-version link `cpython-3.12-<platform>`, keyed
  by its own name. It is damaged when its binary is missing or fails the stdlib probe. A dangling
  python shim reaches the install through the minor-version link, which uv 0.13.6 points every shim
  at, so the link is followed to the install's key. The review found that a purge which takes every
  file of an idle interpreter and leaves its directories was never repaired: the probe skipped an
  interpreter with no binary, and the dangling-shim branch skipped any name that is a link, so the
  repair ran nothing and recorded the scope repaired. The interpreter arm still runs before the tool
  arm. Amended: R3's *Checked by* (P) and R6's *Checked by* (foreman, 2026-10-29).
- **Q:** (review cycle 2, C2-F2) How is a tool repaired? — **A:** Per damaged tool, every
  distribution in its environment reinstalled at the version its dist-info directory names: `uv pip
  install --python <tools>/<tool>/bin/python --reinstall --no-cache <name>==<version>...`. The review
  found that `uv tool upgrade --all --reinstall --no-cache` moves an unpinned tool to a newer
  release, and moving a version means uninstalling the old one, which needs the `RECORD` a purge
  takes first: the arm exits 1 scope after scope, leaving two dist-info directories, and it also
  upgrades healthy unpinned tools. Measured with uv 0.13.6, no option of `uv tool upgrade` or `uv tool
  install` restores the installed versions and keeps every receipt: `--exclude-newer` writes itself
  into the receipt and does not reach an older release installed after a newer one; `tool upgrade
  <name>==<version>` keeps the receipt but moves an unpinned dependency or `--with` package; `tool
  install -c <pins>` restores the versions but writes the constraints into the receipt. Pinning every
  distribution from its dist-info name removes the reason the GOAL ruled out per-tool repair, so the
  non-goal is reworded rather than dropped. Dependencies are resolved, not skipped: with every
  version pinned the resolver moved nothing on the measured trees, and it restored a dependency
  whose whole dist-info directory was gone. The receipt is never read, so options recorded there (an
  index among them) are not applied, while the user's `uv.toml` and environment are; a distribution
  from a URL, git or path source cannot be restored by version and fails the scope naming the tool
  and the distribution; a tool with no receipt no longer fails the arm. The orphan refusal (R5)
  stays ahead of the arm, and the arm refuses a tool whose `bin/python` does not run. Amended: R4 and
  its *Checked by*, the per-tool non-goal (foreman, 2026-10-29, with the maintainer's autonomy
  decision).
- **Q:** (review cycle 2, C2-F8) Does R1's *Checked by* still say "no measurable difference"? —
  **A:** No. Both reviewers in both cycles measured the unset path's cost: no fork, and bash parsing
  the added code, about half a millisecond per call, which the documentation states. The SHALL is
  what binds, and it holds; the *Checked by* now says what the measurement shows. Amended: R1's
  *Checked by* (foreman, 2026-10-29).
- **Q:** (review cycle 2, C2-F4 and C2-F6) How long may a value be, and what does each surface carry?
  — **A:** A value's record name may be 200 bytes, so a value may be 194, each byte outside `A-Z`,
  `a-z`, `0-9`, `.` and `-` counting as three; a longer value fails the call saying so. It is
  documented wherever the values are: the help, `README.md` and the conf example, and the modulefile
  too. R14 is read per surface: `README.md` carries the whole list, and the help, the conf example and
  the modulefile carry the knob, its values, its scope and the limit, and point to `README.md` for
  the rest. Amended: R10 and R14 (foreman, 2026-10-29).
- **Q:** (review cycle 2, ruling 9) Do the R12 trees exercise what a real purge leaves? — **A:** Not
  as shaped: (P) removed only `json/`, which hid C2-F1, and (T) pinned its only tool, which hid
  C2-F2. A purge removes files by access time and keeps directories and links. So (P) removes every
  file of the interpreter, and (T) adds an unpinned tool installed at an older release, with an
  unpinned `--with` package at an older release, damaged the same way beside the pinned one. The
  summary gains the keys that show the unpinned tool kept its versions and receipt. Local gates cover
  both, and the cluster drives are re-run at the remediated commit. Amended: the *Damaged tree* term
  and R12's *Checked by* (foreman, 2026-10-29).
- **Q:** (review cycle 3, C3-F1) May the repair read `uv-receipt.toml`? — **A:** To refuse, and for
  nothing else. The review found that a tool installed from a local fork keeping upstream's version,
  whose purge took `direct_url.json` with the rest, was reinstalled from the index: the knob-set call
  exited 0 and the tool ran upstream code while its receipt still named the fork. A damaged tool now
  fails the scope, naming the tool and what was found, before any `uv` call for that tool, when its
  receipt records a requirement (the tool or a `--with` package), a constraint or an override from a
  directory, path, editable, git or URL source. The repair never builds a spec from the receipt and
  never writes it, so the receipt stays byte-identical. The `direct_url.json` refusal stays, and a
  tool with no receipt is still repaired. The forms are uv 0.13.6's, measured by real installs of
  each: an entry is an inline table in the `requirements`, `constraints` or `overrides` array of
  `[tool]`, and its source is one of the keys `directory`, `path` (a wheel or an sdist), `editable`,
  `git` and `url`; a registry entry carries only `name`, `specifier`, `extras` and `marker`. The
  index options are not a refusal. uv writes an index configured in `uv.toml`, user or system, or by
  `UV_INDEX`, `UV_INDEX_URL` or `UV_DEFAULT_INDEX` into every receipt's `[tool.options]`, so refusing
  those keys would refuse every damaged tool at a site with a mirror, and the repair runs under that
  same configuration. Two concessions remain: an index or find-links given only on one install's
  command line is not applied again, so a name from that index can resolve from the configured one;
  and with both the receipt and `direct_url.json` gone, the source cannot be known, and the index's
  release is installed. Amended: R4 and its *Checked by* (foreman, 2026-10-29, with the maintainer's
  autonomy decision; revised the same day by the foreman's amended ruling 1, after the measurement).
- **Q:** (review cycle 3, C3-F2) Do two values that differ only in case share a record? — **A:**
  No. The review found that on a filesystem that ignores case, macOS's default, `UVM_REPAIR=Run1`
  and then `UVM_REPAIR=run1` shared one record, since the encoding passed `A-Z` unchanged. Every
  uppercase letter is now written as `_` and two hex digits, so the class a byte passes through
  unchanged is `a-z`, `0-9`, `.` and `-`, and an uppercase letter costs three bytes against the
  200-byte name, which the help, `README.md`, the conf example and the modulefile say where they
  state the limit. Doctor decodes as before. Lustre and GPFS are case-sensitive. Amended: the cycle-2
  answer on a value's length above, whose class loses `A-Z` (foreman, 2026-10-29).
- **Q:** This GOAL carries 13 live criteria, past the soft 8-10 breaker. — **A:** Accepted, all 13
  kept. The seed was shaped big at ten; R12 and R13 are the claim drive and the lock questions
  `lock-simplification` handed here, and R14 is D9's surface list (foreman sign-off, 2026-10-29).

## Related materials

- Seed: [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md), and its *Notes*.
- Decisions record:
  [`spec/purge-resilient-run/research/00-digest.md`](../purge-resilient-run/research/00-digest.md)
  (D3 repair idiom, D6 the pin, D7 doctor as oracle, D9 the surfaces, D10 the knob's shape).
- The lock: [`spec/lock-simplification/GOAL.md`](../lock-simplification/GOAL.md) R5/R6 and its
  `REVIEW.md`; `research/01-lock-wait-contract.md` Q5 for the `uvm clean lock` chain; `evidence/`
  for the summary format R12 follows.
- `bin/uv-manager` § *provisioning lock* (`uvm_acquire_lock`, `uvm_unlock`), `uvm_doctor`, the
  dispatch tail; `.agents/factory/invariants.md` §4-§6. `AGENTS.md` names `uvm_acquire_lock` and the
  dispatch tail high-blast-radius regions.
- `tests/lock-race.sh` (`--launch srun`, `--summary`), the instrument R12 extends or mirrors.
- Related seeds: [`issues/uvm-bootstrap.md`](../../issues/uvm-bootstrap.md) follows this cycle;
  [`issues/test-harness.md`](../../issues/test-harness.md).
