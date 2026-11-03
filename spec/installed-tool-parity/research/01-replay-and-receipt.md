# 01 — The replay, and the receipt it leaves (N1, N4, N9, @latest)

Measured 2026-11-01 with uv 0.13.6 (macOS arm64) under `.agents/factory/bin/temp_root.sh`, a real uv
seeded into `versions/`, `UV_PYTHON_PREFERENCE=only-managed`, a managed cpython 3.12.16. Drives:
[`drives/receipt-copy-back.sh`](drives/receipt-copy-back.sh) (N1),
[`drives/replay-matrix.sh`](drives/replay-matrix.sh) (sections C-K) and the shaping run's
[`drives/shaping-*.sh`](drives/). The replay below is the restore's exact form: the real uv called
directly, the wrapper's five storage variables exported, from `/`.

```sh
(cd / && UV_PYTHON=<minor> UV_NO_CACHE=1 exec "$real_uv" tool install --force -c <record>/constraints <request...>)
```

## N1 — the hold, and the copy-back that removes it

Subject: `pycodestyle==2.11.1 --with six==1.16.0`, then `pycodestyle --with six` without `--force`,
so the receipt names no version and the environment stays at 2.11.1 / 1.16.0 while 2.15.0 / 1.17.0
exist. The unpurged twin's `uv tool upgrade pycodestyle` moves it to 2.15.0 / 1.17.0.

| Shape | Replay | Dist-info listing | Receipt after replay | Copy-back, then `uv tool upgrade` |
|---|---|---|---|---|
| (W) directory gone | rc 0 | identical | `constraints = [==2.11.1, ==1.16.0]` | moves to 2.15.0 / 1.17.0, as the twin |
| (E) every file gone | rc 0 | identical | same | same |
| (R) receipt gone | rc 0 | identical | same | same |
| (S) shim gone | rc 0, shim back | identical | same | same |
| (W), no copy-back | rc 0 | identical | same | **held**: hint "`pycodestyle` is pinned to `2.11.1` (installed with an exact version pin)" |

After the copy-back the tool runs (`2.11.1`), `uv tool list` lists `pycodestyle v2.11.1`, and the
receipt is byte-identical to the one saved before the purge. `uv tool upgrade` then rewrites nothing
in it (the requirement is unpinned) and moves the environment.

The git tool: `git+https://github.com/glentner/progressbar`, shape (E), replayed with the constraint
`progressbar @ git+https://github.com/glentner/progressbar@837e34e…`. Listing identical,
`commit_id` unchanged (uv adds `requested_revision` to `direct_url.json`). uv's replayed receipt
carries `constraints = [… progressbar git = "…?rev=837e34e…"]`, which holds the tool. With the copy
back, `uv tool upgrade progressbar` prints what the unpurged twin's does ("Nothing to upgrade", the
default branch being at that commit).

**When the copy-back is safe.** The receipt records an absolute `install-path` per entrypoint:
`install-path = "<UVM_ROOT>/<arch>/bin/shims/pycodestyle"`. uv uses those paths to manage the
entrypoints, so a receipt naming another architecture's or another root's shim directory must not
go back. The test is fixed-string, never a parse: count the lines containing `install-path = "` and
those containing `install-path = "${UV_TOOL_BIN_DIR}/`; copy back only when both are equal and
non-zero. A path TOML had to escape fails the second count, which is the safe direction. Measured
equal (1 of 1) in all four shapes.

**When it is not.** On another platform key (R5) or a relocated `UVM_ROOT`, the copy names another
tree, so uv's pinned receipt stays. The fallback the Clarification names applies there: the
documentation states the hold, names `uv tool install --force <request>` as the remedy, and doctor
reports the tool as pinned by a restore. The marker is a file `.uvm-restored` in the tool's own
directory, written by the restore; `uv tool install --force` recreates the directory and drops it
(measured, [`drives/list-renderings.sh`](drives/list-renderings.sh)), and uv ignores it in `uv
tool list` and `uv tool upgrade` (uv itself keeps `.gitignore` and `CACHEDIR.TAG` there).

## The replay's form

- **`--force` twice is fatal**: `uv tool install --force … --force` exits 2 (clap rejects a
  repeated flag). The replay drops `--force` from the recorded request and adds its own.
- **`--python` twice is fatal** too (rc 2). The replay passes the recorded minor as `UV_PYTHON`
  rather than `-p`, so a request that carries its own `--python` wins over it, as N4 rules (a flag
  beats its environment variable; measured: `UV_PYTHON=3.12` beside `--python 3.12`, rc 0).
- **`--no-cache` beside `UV_NO_CACHE=1`** is accepted (rc 0), so the request's own flag can stay.
- **`-c` twice** is accepted, but the request's own `-c` names a local file and is refused (N9).
- **`UV_PYTHON` beats a global pin.** With `$XDG_CONFIG_HOME/uv/.python-version` at 3.11 and
  downloads off, the replay with `UV_PYTHON=3.12` built on 3.12.16; without it, uv tried 3.11 and
  failed. So no `.python-version`, global pin or user `UV_PYTHON` steers the replay (§8's rule).
- **`<name>@latest` fails against older pins**: "Because you require pycodestyle==2.11.1 and
  pycodestyle==2.15.0 … unsatisfiable". uv resolves `@latest` to a concrete version first, and
  records the request in the receipt as plain `{ name = "pycodestyle" }`. The replay rewrites a
  request element `<name>[extras]@latest` to `<name>[extras]`: replayed so, it came back at the
  pinned 2.11.1 (rc 0). The record keeps `@latest` as typed.

## Sources (N9)

- **Index**: restored exactly in every shape (above, and shaping Q1).
- **VCS**: constraint `name @ git+<url>@<commit>`, as above.
- **URL archive**: `uv tool install <wheel URL>`; `direct_url.json` is
  `{"url":"…/pycowsay-0.0.0.2-py3-none-any.whl","archive_info":{}}`. Replay with the constraint
  `pycowsay @ <url>` and the request as typed: rc 0, listing identical. Replayed with the request
  `pycowsay` by name and the same constraint: rc 0, and `direct_url.json` names the URL, so the
  constraint pins the source. **URL archives are restorable**, as N9 allows.
- **Local** (`./lp`, `-e ./lp`): `direct_url.json` carries a `file://` URL (`dir_info` for a
  directory). The record keeps it; the restore refuses it (a constraint `@ file:`), and refuses a
  request naming `-e`/`--editable`, `--with-editable`, `--with-requirements`, `-c`/`--constraints`,
  `--overrides` or `-b`/`--build-constraints`, naming the tool and the option.

## Credentials (R2)

`uv tool install --index-url https://__token__:SECRETMARK@pypi.org/simple pyflakes==3.2.0`: rc 0,
pypi.org accepts the userinfo. The receipt records `index-url = "https://pypi.org/simple"`; with
`--index`, `index = [{ url = "https://pypi.org/simple", …, authenticate = "always" }]`. `grep -r
SECRETMARK` over the tool directory finds nothing: **uv strips userinfo from the receipt** itself,
so the receipt copy carries none. The record's request is stripped by the wrapper (02). R2's check
uses this host and this marker.

## Pre-existing writes found on the way

`uv-manager doctor` on `release/0.8.0` writes under `UVM_ROOT`: its interpreter probe (`import
json, os, ssl`) leaves `__pycache__/*.pyc` in the managed interpreter. R8 forbids any write there,
so the probe runs with `PYTHONDONTWRITEBYTECODE=1`. `uv tool list`, which the backfill calls,
writes `cache/interpreter-v4/…msgpack`; the backfill runs it with `UV_NO_CACHE=1`. With both, a
`find "$UVM_ROOT" -type f -exec cksum {} +` listing is identical across doctor (P3 gate).
