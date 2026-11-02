# 03 — The cross-node drive (R6)

`tests/repair-race.sh` gains three scenarios beside `F`, `T`, `P`, `kill`, `I` and `ikill`, all
prototyped and green locally (`--launch local`, `--uv-bin`): `U` ×16, `S` ×16, `ukill` ×8.

## The cache (M1)

`prepare_cache` builds, through the wrapper, ten script environments (`requests`, `click`, `attrs`,
`pyyaml`, `packaging`, `jinja2`, `tabulate`, `python-dateutil`, `toolz`, `more-itertools`, each
pinned, each a one-line script) and ten `uvx` environments (`uvx --from <pkg>==<ver> python -c
pass` for `pycowsay`, `black`, `isort`, `cowsay`, `pyflakes`, `pycodestyle`, `docutils`,
`pygments`, `sqlparse`, `wheel`), then both subjects: the script `s.py` needing `tqdm==4.67.1`,
and `uvx tqdm==4.67.1`. Every package has a wheel for Linux x86_64 and macOS arm64 on CPython
3.12. Locally: 3160 files, 54 live entries (22 environments and 32 wheels), prepared in 16-17 s.

The damage is a purge's shape on the scenario's subject: `tqdm/std.py` and every file of
`tqdm-4.67.1.dist-info`, the directory kept. Preparation fails (exit 4) unless the command then
fails.

## Scenarios

| Scenario | Each rank runs | Checks |
|---|---|---|
| `U` | `uvx tqdm==4.67.1 --version` | every rank 0 with `4.67.1`, one repair, one ok outcome, no lock, doctor clean after, `rebuilt=0` |
| `S` | `uv run --no-project <collect>/s.py` | the same, with `s ok 4.67.1` |
| `ukill` | as `U`; the holder's own rank kills its process group on sight | killed pass: `rc_hist=1:<n-1>,137:1`, every waiter timed out naming the lock, no outcome, the lock left, doctor WARNs it; clean pass after `uvm clean lock --yes`: as `U` |

`ukill`'s clean pass keeps a 180 s timeout, as `ikill`'s does. The killed pass relies on the kill
landing before the in-place reinstall: the holder walks first, 0.2 s locally and longer on Lustre,
and the watcher polls every 0.1 s. `restored=0` in the killed pass is asserted, so a kill that
landed after the repair reads as a drive that did not construct the fault, not as a pass.

## Summary keys added (counts and fixed words only)

| Key | How |
|---|---|
| `walk_s` | wall seconds of `uvm doctor` on the damaged tree before the pass, timed by the managed interpreter to two decimals: the holder's walk plus doctor's interpreter probe (about 0.15 s) |
| `cache_files` | `find cache -type f \| wc -l` |
| `live_entries` | script environments, cached-environment links and wheel links, counted by the drive, not the wrapper |
| `link_mode` | `hardlink` when the subject's `tqdm/__init__.py` shares its inode with the wheel's, `symlink` when it is a link, else `copy-or-clone` (the two cannot be told apart from the tree) |
| `flock` | `coherent`, `node-local` or `absent`, from a two-rank probe on two nodes (`srun --nodes=2 --ntasks=2 --ntasks-per-node=1`): rank 0 holds `flock -x` on a file in the collection directory, rank 1 tries `flock -n -E 75`; 75 means the hold was seen, 0 that it was not, anything else that flock failed. `not-measured` under `--launch local`, `unknown` without the `flock` utility |
| `rebuilt` | archives and `environments-v2` entries present after the pass and absent before it |

Existing keys carry the rest of R6's list: `repairs`, `outcomes`, `rc_hist`, `stdout_hist`,
`locks_left`, `hold_s` (the holder's seconds), `notice_lines`.

## Jobs

Two jobs, 2 nodes × 64 ranks, ≤ 30 min, ≤ 16 GB per node, bodies generic (no account, partition,
path or cluster name): job 1 runs `U` and then `S`, each with its own run directory and summary;
job 2 runs `ukill` with `--timeout 60`. Expected: preparation 2-4 min each on Lustre through the
installer, the race under a minute, the walk a few seconds; job 1 under 12 min, job 2 under 8.
Egress: `astral.sh` and its release host for uv, `releases.astral.sh` and GitHub's object host for
the interpreter, `pypi.org` and `files.pythonhosted.org` for the packages. No `git`.
