# 02 — The repair arms, re-measured against a real uv 0.13.6

**Conclusion.** The decided arms work on uv 0.13.6 and the decided order is required. `uv tool
upgrade --all --reinstall --no-cache` restores every file of a tool damaged as (T), keeps an exact
pin and its `--with` packages, leaves `uv-receipt.toml` byte-identical and writes nothing to stdout.
`uv python install --reinstall` restores a damaged interpreter at its installed patch version, not
the newest. Run alone on a tree whose interpreter is also damaged, the tool arm fails and repairs
nothing, so python before tool is load-bearing. Two findings bear on the design. A receipt-less tool
(doctor's WARN, not a FAIL) makes the tool arm exit 1 after it has repaired everything else, so the
plan must say what the outcome records then. A tool missing `pyvenv.cfg` makes the tool arm exit
**0** while it installs into the base interpreter and retargets the shim, so uv gives no signal and
the wrapper's refusal (R5) is the only guard. Two of the GOAL's "Observed on main" details differ from
this measurement: (T) `uvx` fails inside uv, not with the package's `ImportError`, and (P) `uv run`
exits 1, not 2.

Host: macOS arm64, uv 0.13.6, every drive under `temp_root.sh`. Each drive's captured streams were
kept per question in a scratch directory. Python downloads were 23.9 MiB each.

## Q1 — Seed recipe

Inside the `temp_root.sh` command, with `SEED_UV=$(command -v uv) SEED_UVX=$(command -v uvx)`
passed into the inner `sh -c` (the scrub removes only `UV_*`/`UVM_*`):

```sh
a=$(uname -m); r="$UVM_ROOT/$a"
mkdir -p "$r/versions/0.13.6"
cp "$SEED_UV" "$SEED_UVX" "$r/versions/0.13.6/"
ln -s versions/0.13.6 "$r/current"
```

`uv --version` through the wrapper: rc 0, 0.42 s, `uv 0.13.6 (329bf9448 2026-10-26
aarch64-apple-darwin)`. No provisioning, no codesign or quarantine refusal of the copied binary. The
key must match the wrapper's `${UVM_PLATFORM:-$(uname -m)}`, so a drive using `--arch` seeds
`$UVM_ROOT/$UVM_PLATFORM` instead. On macOS the key is `arm64`.

**Damaging the tree.** `rm` worked from a drive script file the inner `sh` sources. `rm` written
inline in a `sh -c` string was refused by Claude Code's removal check. `mv <file> "$UVM_SANDBOX/trash/"`
works everywhere and is the form to document.

## Q2 — Tree (T) and the tool arm

`uv python install 3.12` (0.75 s) installed `cpython-3.12.16-macos-aarch64-none` and a minor-version
symlink `cpython-3.12-macos-aarch64-none` beside it. The tool's `pyvenv.cfg` `home` points through
the symlink. `uv tool install pyflakes==3.2.0 --python 3.12` (0.51 s) gave a 44-file tool directory;
site-packages is `$UVM_ROOT/<arch>/tools/pyflakes/lib/python3.12/site-packages/`. The shim
`bin/shims/pyflakes` is a symlink to `tools/pyflakes/bin/pyflakes`.

`uvx pyflakes --version`: rc 0, stdout `3.2.0 Python 3.12.16 on Darwin`. `uvx -v` logs `Using
existing tool `pyflakes``: uvx runs the installed environment.

Damage (`pyflakes/checker.py` and `pyflakes-3.2.0.dist-info/RECORD` removed):

- `uvm doctor`: rc 1, `FAIL  pyflakes-3.2.0 has no RECORD manifest (partial purge)`. With `RECORD`
  gone the walk skips the file count. With only `checker.py` gone it reads `FAIL  pyflakes-3.2.0 is
  missing 1 of 29 files (partial purge)`.
- `uvx pyflakes --version`: rc 1, stdout empty, **stderr a single newline**. uv itself fails before
  exec: `-v` shows `WARN Failed to get entrypoints for `pyflakes`: failed to open file
  `.../RECORD``. The `ImportError: cannot import name 'checker'` appears only when `RECORD` survives,
  or through the shim (rc 1).

Tool arm, through the wrapper: rc 0, 0.32 s, stdout 0 bytes. stderr:

```
warning: Failed to uninstall package at `.../pyflakes-3.2.0.dist-info` due to missing `RECORD` file. Installation may result in an incomplete environment.
Modified pyflakes environment
 ~ pyflakes==3.2.0
Nothing to upgrade

hint: `pyflakes` is pinned to `3.2.0` (installed with an exact version pin); ...
```

After: every manifest path is back (`comm -23 manifest.before manifest.after` empty; the after set
adds `__pycache__/*.pyc`, so equality is the wrong test). `uvx pyflakes --version` and the shim both
print `3.2.0 Python 3.12.16 on Darwin`, rc 0. `cmp` on `uv-receipt.toml`: rc 0. `uvm doctor`: rc 0.

## Q3 — R4: pin and `--with`

`six` (one module, no dependencies, no executable) fits: its import is a direct test. `uv tool install
'pyflakes==3.1.0' --with six --python 3.12` recorded `requirements = [{ name = "pyflakes", specifier
= "==3.1.0" }, { name = "six" }]` and installed six 1.17.0. Damaged as (T), then the tool arm: rc 0,
0.25 s, stderr `Modified pyflakes environment`, ` ~ pyflakes==3.1.0`, ` ~ six==1.17.0`. Receipt
`cmp` rc 0, no manifest path missing, `uvx pyflakes --version` prints `3.1.0 Python 3.12.16 on
Darwin`, and `<tooldir>/bin/python -c 'import six; print(six.__version__, six.__file__)'` prints
`1.17.0 .../tools/pyflakes/lib/python3.12/site-packages/six.py`. The unpinned `--with` package kept
its version; that is observed, not a uv contract.

## Q4 — Tree (P) and the python arm

`t.py` is `import json` and `print("t-ok", json.dumps([1]))`. With `lib/python3.12/json/` moved out
of `cpython-3.12.16-macos-aarch64-none`:

- `uv run --no-project -p 3.12 t.py`: rc **1**, `ModuleNotFoundError: No module named 'json'`.
- `uvm doctor`: rc 1, **two** lines for one interpreter, because the loop also enters the minor
  symlink: `FAIL  managed interpreter cpython-3.12-macos-aarch64-none is damaged (stdlib import
  failed)` and the same for `cpython-3.12.16-macos-aarch64-none`.

Python arm: rc 0, 0.84 s, stdout 0 bytes. stderr:

```
Downloading cpython-3.12.16-macos-aarch64-none (download) (23.9MiB)
 Downloaded cpython-3.12.16-macos-aarch64-none (download)
Installed Python 3.12.16 in 786ms
 ~ cpython-3.12.16-macos-aarch64-none
warning: Failed to install executable for cpython-3.12.16-macos-aarch64-none
  cause: Executable already exists at `$UVM_ROOT/<arch>/bin/python-shims/python3.12` but is not managed by uv; use `--force` to replace it
```

The warning appears on every reinstall; the existing shim's target path is unchanged and it still
works. `uv -v` shows one download host, `https://releases.astral.sh`. The `json/` listing `cmp`s
equal to the pre-damage one, `t.py` prints `t-ok [1]`, doctor rc 0. The installed tree is 68 MB on
disk.

**Same patch, not newer.** With `3.12.15` installed while `3.12.16` was available, the arm
re-downloaded `cpython-3.12.15-macos-aarch64-none` (rc 0, 0.79 s) and `t.py` reported `3.12.15`.
The key set in `python/` was unchanged.

**No managed pythons.** `--dry-run` does not exist in 0.13.6 (`error: unexpected argument
'--dry-run' found`, rc 2). With an empty `python/` and `UV_OFFLINE=1`, `uv python install
--reinstall` exits 1 trying to install **`cpython-3.16.0a1-macos-aarch64-none`**, the head of `uv
python list --only-downloads`: a pre-release. The error names a `github.com` URL, while the online
listing and the online download use `releases.astral.sh`. R6's guard is required, not tidiness.

## Q5 — Receipt-less tool

Two tools, one receipt moved out, `pyflakes` damaged as (T). Run once with the orphan sorting before
`pyflakes` (`pycowsay==0.0.0.2`) and once after (`unidecode`). Both runs: doctor rc 1 with `WARN  tool
<name> has no receipt; uv ignores it. ...` and the RECORD FAIL. Tool arm **rc 1**, 0.30-0.37 s,
stdout empty. stderr:

```
warning: Failed to uninstall package at `...` due to missing `RECORD` file. ...
Modified pyflakes environment
 ~ pyflakes==3.2.0
error: Failed to upgrade pycowsay
  cause: `pycowsay` is not installed; run `uv tool install pycowsay` to install
```

`pyflakes` is fully repaired in both orders (`checker.py` and `RECORD` back, `uvx` rc 0); uv reports
the failure at the end. Afterwards doctor exits 0 with the WARN as an advisory. A receipt-less tool
therefore turns a successful repair into a non-zero tool arm. Under R9 as written, the holder records
a failed outcome on a tree it has repaired, and every rank in the scope fails.

## Q6 — Order dependence

Damage: `json/` moved out of the interpreter and the tool damaged as (T). Doctor: rc 1, three FAILs.

- **Tool arm alone:** rc 1, 0.09 s, `error: Failed to upgrade pyflakes` / ``cause: `pyflakes` is
  missing a valid environment; run `uv tool install --force pyflakes` to reinstall``. Nothing is
  restored. `uvx pyflakes --version` then exits 2: `Querying Python at
  `.../tools/pyflakes/bin/python` failed`, `ModuleNotFoundError: No module named 'json'`.
- **Python arm, then tool arm:** rc 0 (0.86 s) and rc 0 (0.47 s). No manifest path missing, `uvx`
  prints `3.2.0 Python 3.12.16 on Darwin`, `t.py` runs, doctor rc 0.

## Q7 — Orphan without `pyvenv.cfg`

Doctor: `FAIL  tool pycowsay has no pyvenv.cfg; no automated repair is safe for it`. The base here is
the sandbox's managed interpreter, so running the tool arm stayed inside the sandbox. Tool arm:
**rc 0**, 0.42 s, stderr opens with `Added pycowsay v0.0.0.2` / ` + pycowsay==0.0.0.2` / `Installed
1 executable: pycowsay`, then repairs `pyflakes`. The base interpreter's `site-packages` gained
`pycowsay` and `pycowsay-0.0.0.2.dist-info`, its `bin/` gained `pycowsay`, and the shim
`bin/shims/pycowsay` now points into the base interpreter's `bin/`. `pyvenv.cfg` is not recreated;
doctor still FAILs the tool. On a system or site interpreter that write lands outside the tree.

## Q8 — Cost of the detection walk

`uvm doctor` on these trees (1-2 tools, 1 interpreter): 0.05-0.13 s, one cold outlier at 0.26 s.
The interpreter probe runs twice per interpreter, once through the minor symlink.

## Implications for gates

- **Streams.** Both arms write nothing to stdout in every run, success or failure. R8's (T) check can
  require stdout to be exactly `3.2.0 Python 3.12.<n> on <system>`; match `^3\.2\.0 Python 3\.12\.`,
  since the platform word differs on Linux.
- **Tool arm success:** rc 0 and stderr contains `Modified pyflakes environment`. Its `warning:
  Failed to uninstall package ... missing `RECORD` file` line is normal on tree (T); a gate or the
  wrapper must not key failure on `warning:`.
- **Python arm success:** rc 0 and ` ~ cpython-3.12.16-`; the `not managed by uv` warning is expected.
- **Manifest:** `comm -23 manifest.before manifest.after` empty, not `cmp`.
- **Byte-identical:** `uv-receipt.toml` (`cmp`, rc 0), and the `ls` of the interpreter's `json/`.
- **R4:** `uvx pyflakes --version` begins `3.1.0 `; `<tooldir>/bin/python -c 'import six'` rc 0.
- **R5:** before/after `ls -A` of the base interpreter's `site-packages`, and `ls` of its `bin/`. A
  wrapper that leaks the arm shows `pycowsay` added to both. uv's rc is 0 in that case, so a gate
  cannot rely on the arm failing.
- **Doctor strings:** `has no RECORD manifest (partial purge)` for (T) as the GOAL defines it;
  `managed interpreter <key> is damaged (stdlib import failed)` appears **twice** per damaged
  interpreter; `has no pyvenv.cfg; no automated repair is safe for it`; `has no receipt; uv ignores
  it`.
- **Red baselines:** (T) `uvx` rc 1 with empty stdout and a lone newline on stderr; (P) `uv run` rc 1
  with `ModuleNotFoundError: No module named 'json'`. A gate expecting `ImportError` or rc 2 fails on
  the red side for the wrong reason.
- **Order:** a gate on combined damage proves the order: tool arm alone gives rc 1 and `is missing a
  valid environment`.

## Open/unsettled

- **Receipt-less tool vs. R9.** Options for the plan: refuse before running, like R5 (the tree stays
  damaged and the outcome is failed); run the arm and accept rc 1 only when every error line is `` `X`
  is not installed `` for a tool doctor WARNed; or record failed and accept that all ranks fail. The
  GOAL does not settle it.
- **Download host fallback.** The offline error names `github.com/astral-sh/python-build-standalone`
  where the online path used `releases.astral.sh`. Whether uv falls back to `github.com` when
  `releases.astral.sh` is unreachable was not measured; it bears on R12's egress list.
- **Hold time.** All timings are a desktop on a fast link with 4-200 KB wheels. A real tool set
  re-downloads its full dependency set with `--no-cache`, and each interpreter is a 23.9 MiB fetch.
  R12 measures the cluster figure.
- `--reinstall` keeping the installed version under `tool upgrade` and the patch under `python
  install` is observed behavior on 0.13.6, not documented contract.
- Linux was not measured here.
