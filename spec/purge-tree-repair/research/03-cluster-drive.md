# 03 — The R12 drive: `tests/repair-race.sh`

**Conclusion.** The drive is a sibling of `tests/lock-race.sh` and does not extend it. The two share
`--launch srun`, the shared-root variable, the `nowrapper` guard and the summary discipline. They
share nothing else: lock-race bursts fixture installs, and this drive prepares one real tree, damages
it, and releases ranks once per pass. A prototype in a throwaway copy ran every scenario locally at
8 and 64 ranks with a real uv 0.13.6, and the fixture scenario offline.

## Shape

`tests/repair-race.sh --scenario F|T|P|kill [--ranks N] [--timeout S] [--launch local|srun]
[--summary FILE] [--uv-bin PATH] [--uv-version VER]`, one POSIX `sh` file with three roles:

- **driver**: parses options, then runs itself inside `temp_root.sh` (`--offline` for F only) as
  the `job` role, and turns what that role leaves in a collection directory outside the sandbox into
  the summary.
- **job**: prepares and damages the tree, launches the ranks (`srun … --export=ALL` re-executing the
  script as the `rank` role, or local background calls), and records outcomes, locks, restoration and
  the uv version.
- **rank**: one wrapper call with `UVM_REPAIR=1` and `UVM_LOCK_TIMEOUT`. It writes stdout, stderr,
  rc, elapsed seconds, and `node bash wrapper|other`.

## Scenarios and damage

| Scenario | Prepared | Damage | Each rank runs | Expected stdout |
|---|---|---|---|---|
| F | fixture uv | tree (F): a planted tool whose `RECORD` names an absent file; the stub repair sleeps 3 s | `uv --version` | `uv 9.9.9 (fixture)` |
| T | real uv, managed cpython 3.12, `pyflakes==3.2.0 --python 3.12` | `pyflakes/checker.py` and the dist-info `RECORD` moved out | `uvx pyflakes --version` | first word `3.2.0` |
| P | real uv, managed cpython 3.12 | the interpreter's `lib/python3.12/json/` moved out | `uv run --no-project -p 3.12 t.py` | `t-ok [1]` |
| kill | as P | as P | as P; the holder is killed, then a clean pass | waiters fail, clean pass `t-ok [1]` |

The drive sets `UV_PYTHON_PREFERENCE=only-managed` in the job role, which is user policy rather than
the wrapper's, so the interpreter and the tool's venv both live in the sandbox. Tool and interpreter
versions are pinned through the uv version, which embeds its interpreter download list: uv 0.13.6
resolves `3.12` to the same patch everywhere. The (P) interpreter is the non-symlink
`python/cpython-3.12.*` directory, because uv also installs a minor-version symlink beside it (brief
02). Damage is a `mv` into the run's trash directory: `rm` written inline in an `sh -c` drive is
refused by the agent harness, and a move works on every host.

**Real uv.** `--uv-bin PATH` copies a local binary and its `uvx` into `versions/<ver>` and points
`current` at it. That is the path for a host whose installer cannot run, such as this agent sandbox,
where `install.sh`'s `mktemp -d` is denied. Without it, the job pins `UVM_PIN=--uv-version` (default
0.13.6) and the wrapper provisions through the real installer. That is the cluster path, and it
exercises provisioning on the compute filesystem too.

## The KILL fault

Each rank starts its wrapper call directly in the background, so `$!` is the wrapper's own pid: the
pid its owner line records. Started through a backgrounded compound command, `$!` named a subshell
and the kill never matched, which was measured. In the kill scenario each rank polls
`.repair.lock/owner` every 0.1 s while its call runs. The one rank that reads `host=$(uname -n)
pid=$!` kills it with `KILL` at once. No cross-node signalling is needed, because the holder's own
rank is on the holder's node. The kill takes the wrapper alone, as a node fault would. Its repair
child, if one has started, runs on unrecorded; the sandbox's process listing is denied (`pgrep`
fails), and under `srun` the step's end reaps it. A tool repair finished in 0.3 s locally and outran a
kill delayed by 1 s, so the scenario damages the interpreter (a 23.9 MiB download) and kills on
sight.

After the pass, the job runs `uvm doctor` (one `WARN  repair lock standing` expected), then `uvm
clean lock --yes`, then a clean pass with the same scope. That pass must repair once and exit 0
everywhere.

## Summary keys

Counts, whole seconds, versions and fixed words only: `scenario launch ranks timeout uv wall rc_hist
stdout_hist uv_resolved nodes bash repairs repair_lines hold_s wait_max_s wait_p50_s notice_lines
timeout_named_lock killed outcomes outcome_kind locks_left restored launch_failures progress`. The
kill scenario adds `doctor_warn_repair_lock` and the clean pass's keys prefixed `clean_`. The job body
appends `exit=`. `hold_s` is the repairing rank's elapsed time and `wait_*` are the others'. Both are
measured by the rank with `date +%s`, because `%N` is GNU-only.

## Local measurements (prototype, macOS, bash 3.2, uv 0.13.6)

- F ×16 offline: `repairs=1 rc_hist=0:16 stdout_hist=9.9.9:16 outcomes=1 locks_left=0`, 3 s.
- T ×64: `repairs=1 rc_hist=0:64 stdout_hist=3.2.0:64 hold_s=1`. P ×64: `repairs=1 rc_hist=0:64
  hold_s=2`.
- kill ×64, timeout 20: `rc_hist=1:63,137:1 killed=1 timeout_named_lock=63 outcomes=0
  doctor_warn_repair_lock=1`, clean pass `clean_repairs=1 clean_rc_hist=0:64`.
  `notice_lines=63`: the notice fires at `min(30, timeout)`.
- `--launch srun` without `REPAIRRACE_SHARED`: exit 2. The `srun` path itself is unexercised
  locally, and its first run is the cluster's.

## Egress the cluster run needs

`astral.sh` and the binary host its installer names for uv itself, `pypi.org` and
`files.pythonhosted.org` for the tool, and `releases.astral.sh` for the interpreter. uv 0.13.6's
offline error names a `github.com` URL for the same interpreter (brief 02), so `github.com` may be a
fallback. All of them, `objects.githubusercontent.com` included, were probed and are present from
compute nodes on both target clusters (PLAN §5, ruling 6). A missing host shows as `progress` other
than `ok` with exit 4, or as a failed outcome in the summary: R9's failure, not a gap in the claim.
