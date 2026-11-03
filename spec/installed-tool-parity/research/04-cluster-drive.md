# 04 — The cross-node drive (R11)

`tests/repair-race.sh` gains two scenarios. Everything else in it stays: the roles (driver, job,
rank), `--launch srun` with `REPAIRRACE_SHARED`, `--uv-bin`, the `nowrapper` guard, the group kill,
the counts-only summary. `F`, `T`, `P` and `kill` are unchanged and stay in the gate as regressions
(the sibling `uv-cache-purge-damage` R7 names `T`).

## Scenario `I`

Preparation, in the sandbox, real uv (`--uv-bin` locally; the pinned installer on the cluster):

- `UVM_DATA="$UVM_SANDBOX/data"` and `$UVM_DATA/bin` first on `PATH`, as the module puts them.
  The records live under the run directory, beside the tree under test.
- `uv python install 3.12`, then five tools through the wrapper, so each has a record:

| Tool | Installed as | Shape | Rank runs | Expected stdout |
|---|---|---|---|---|
| pyflakes | `pyflakes==3.2.0 --with tomli==2.0.1` | (W) directory moved out | `pyflakes --version` | `3.2.0 Python 3.12.…` |
| pycodestyle | `==2.11.1 --with six==1.16.0`, then unpinned `--with six` | (E) every file removed | `pycodestyle --version` | `2.11.1` |
| pygments | `pygments==2.18.0` | (R) receipt moved out | `pygmentize -V` | `Pygments version 2.18.0, …` |
| wheel | `wheel==0.45.1` | (S) shim moved out | `wheel version` | `wheel 0.45.1` |
| progressbar | `git+https://github.com/glentner/progressbar`, no revision | (G) every file removed | `pb --version` | `pb v1.2.1` |

- Before the damage it keeps each tool's dist-info listing, receipt, the git commit and a copy of
  the records. After it, `pyflakes` and `wheel` must fail by name, or the scenario was not built.
- Rank `i` runs tool `i mod 5` by its own name, and must resolve it to `$UVM_DATA/bin/<name>`.

The git source is a small public repository with no revision, as shape (G) defines it. Its commit
is the record's pin, and `commit_kept` compares before against after, so the drive does not depend
on the default branch standing still.

## Scenario `ikill`

As `I`, and the rank whose wrapper holds the repair lock kills its process group on sight (the
`kill` machinery: the trampoline `exec`s the wrapper, so `$!` is the owner line's pid). Then
`uvm doctor`, `uvm clean lock --yes`, and a clean pass in the same scope.

## Summary keys

Counts, whole seconds, versions and fixed words only. Beside the existing keys:

| Key | Meaning |
|---|---|
| `restores`, `restore_lines` | ranks announcing `uv-manager: restoring the ` (in place of `repairs`) |
| `timeout_named_owner` | ranks whose timeout line carries `held by: host=` |
| `frozen_identical` | tools (of 5) whose sorted dist-info listing equals the pre-purge one |
| `manifests_kept` | tools whose every dist-info directory has its `RECORD` (shape E keeps the directories, so the listing alone is blind to it) |
| `minor_kept` | tools whose `pyvenv.cfg` names 3.12 |
| `records_identical` | tools whose record compares equal (`diff -r`) |
| `receipts_kept` | tools whose receipt is byte-identical to the pre-purge one (N1 copy-back) |
| `commit_kept` | 1 when the git tool's `commit_id` is unchanged |
| `unpinned_upgrade` | `moved` when `uv tool upgrade pycodestyle` after the restore leaves 2.11.1, as the unpurged twin does (scenario `I` only) |

## Local results on the prototype (macOS, bash 3.2, uv 0.13.6, `--uv-bin`)

- `I` ×16: `rc_hist=0:16 stdout_hist=expected:16 restores=1 hold_s=5..22 outcomes=1 locks_left=0
  frozen_identical=5 manifests_kept=5 minor_kept=5 records_identical=5 receipts_kept=5
  commit_kept=1 unpinned_upgrade=moved`. The 22 s hold was a cold first run; 5 s warm.
- `ikill` ×8: `rc_hist=1:7,137:1 killed=1 kill_took=group timeout_named_lock=7
  timeout_named_owner=7 notice_lines=7 outcomes=0 locks_left=1 doctor_warn_repair_lock=1`, then
  `clean_restores=1 clean_rc_hist=0:8 clean_locks_left=0` and every equality at 5, about 35 s.
- Fed to the P5 gate's evidence half, scaled to 128 ranks and 2 nodes, the summaries pass; with
  `clean_restores=0` the gate fails at that key.

## The jobs

Two jobs, as `purge-tree-repair` split its evidence: `I` in one, `ikill` in the other, so either can
be re-run alone and both can queue together. Each: 2 nodes × 64 ranks, 30 min, 16 GB per node.

- **Runtime.** Preparation provisions uv through the installer, installs cpython 3.12 (24 MiB) and
  the five tools, about a minute. One hold restores five tools with `--no-cache`, building the git
  tool from source: 5-22 s locally, so allow a minute on Lustre. `ikill` adds the killed pass, whose
  waiters run out a 60 s timeout, then doctor and the clean pass. Each job is under 6 min; the
  30 min limit leaves a margin of 5×.
- **Memory.** 64 ranks per node, each a `sh` trampoline that becomes the bash wrapper, then a
  Python 3.12 running a `--version`: 30-60 MB each, 2-4 GB per node, inside 16 GB.
- **Egress** from compute nodes: `astral.sh` and `releases.astral.sh` (uv and the interpreter),
  `pypi.org`, `files.pythonhosted.org`, `github.com` (the git tool, and `objects.githubusercontent.com`
  for interpreter downloads). `git` on compute nodes (the foreman confirmed both).

The job bodies are in `TECH.md` § P5. They carry no account, partition, path or cluster name; the
foreman adds those at submission and never commits them.
