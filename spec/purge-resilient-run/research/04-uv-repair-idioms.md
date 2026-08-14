# 04 — What actually repairs a damaged tool environment or managed python

**Conclusion, high confidence: `uv tool upgrade --all --reinstall --no-cache` for tools, and
`uv python install --reinstall` (no target) for managed pythons.** Both are whole-tree commands, so
the wrapper never enumerates anything and never reconstructs a version spec — which is what makes
them safe. The three remedies `uvm_doctor` prints today are wrong on two counts, and one of them is
wrong in exactly the scenario doctor exists to describe.

Two findings change R4's shape. First, the tool half **can** be verified with zero egress; the GOAL's
concession is too pessimistic there. The python half cannot: uv never stores the interpreter tarball
in `UV_CACHE_DIR`, so every python repair is a fresh 23.8 MiB fetch from `github.com`. Second, a
purged `pyvenv.cfg` turns any in-place tool repair into a write against the *base* interpreter's
`site-packages` — outside anything the wrapper owns.

Host: macOS 26.5.2, arm64, real `uv 0.12.3`, isolated `UV_*` roots under `/tmp`, never the
developer's state root. Test tools: `pycowsay==0.0.0.2` (4 KB pure-python wheel) and `tqdm`.

## 1. Doctor's printed idiom is wrong

`uv tool install <name>` on a gutted-but-receipted environment prints ``` `pycowsay==0.0.0.2` is
already installed ```, exits 0, and repairs nothing. That is the GOAL's motivating failure, confirmed
directly. So the repair must force.

Worse, doctor's `uv tool uninstall <name> && uv tool install <name>` **also** fails once the cache is
damaged. `UV_CACHE_DIR` sits on the same purged filesystem as the venv, and uv performs no integrity
check on its unpacked `archive-v0` store. Removing one file from the cached archive and then running
the full uninstall/install cycle produced `Installed 1 package`, exit 0, and an environment still
missing that file. `--reinstall` alone (which implies `--refresh`) fails the same way: `--refresh`
invalidates index metadata, not the unpacked archive.

| Repair, against a corrupt `archive-v0` | rc | tool runs after |
|---|---|---|
| `uv tool install <spec>` | 0 | no |
| `uv tool uninstall && uv tool install <spec>` | 0 | **no** |
| `uv tool install --reinstall <spec>` | 0 | **no** |
| `uv tool install --reinstall --no-cache <spec>` | 0 | yes |
| `uv cache clean <name>` then `--reinstall` | 0 | yes |
| `uv tool upgrade --reinstall --no-cache <name>` | 0 | yes |

`--no-cache` is the load-bearing flag, not an optimization. Its cost is one re-download per repair
and a temp unpack under `TMPDIR`, which the wrapper deliberately does not set.

## 2. The version trap, measured

`uv-receipt.toml` records the **request**, not the resolution:

```toml
[tool]
requirements = [{ name = "tqdm", specifier = "==4.66.0" }, { name = "pycowsay", specifier = "==0.0.0.2" }]
python = "3.12"
entrypoints = [{ name = "tqdm", install-path = "/abs/path/bin/shims/tqdm", from = "tqdm" }]
```

Three traps live in that file. `requirements` does not distinguish the tool from its `--with`
packages — the tool is the *directory* name, everything else is a `--with`. An unpinned tool records
`{ name = "tqdm" }` with no specifier, so the installed version is unrecoverable from the receipt
once the `dist-info` is purged. And `install-path` is absolute, so the receipt does not survive a
relocated `UVM_ROOT`.

Reconstructing an install command from that file is therefore a live defect, and the failure is
silent. `uv tool install --reinstall tqdm` against a tool installed as `tqdm==4.66.0` **upgraded it
to 4.70.0 and rewrote the receipt**, destroying the user's pin permanently — not for the run, for
good. `uv tool list --show-version-specifiers` then reports no pin at all.

`uv tool upgrade --reinstall` does not do this. Despite the verb, `--reinstall` suppresses the
upgrade: on an unpinned `tqdm==4.66.1` with a cold index (`--no-cache`, so no stale resolution) it
reported `~ tqdm==4.66.1` / `Nothing to upgrade` and left the version alone. On the pinned tool it
preserved both `==4.66.0` and `--with pycowsay==0.0.0.2`, receipt byte-identical. It reads the receipt
itself, so the wrapper never parses TOML and never has a spec to get wrong.

`--all` extends this to the whole tree: two damaged tools repaired in **421 ms**, rc 0.

## 3. Enumeration is not needed, and would not be cheap

`uv tool list` costs 7.7 ms per call against 6.4 ms for `uv --version` on the same host — about 1.3 ms
of work behind a whole extra uv process. Adding one to the wrapper's ~11 ms invocation roughly doubles
it, which puts it firmly behind R3's sentinel and not on the hot path. It does work against a damaged
tree, and warns `Ignoring malformed tool <name>` for a receipt-less directory.

`uv python list --only-installed` is worse and wrong for this purpose: 225 ms, and it reports system
interpreters (`/usr/bin/python3`, Homebrew) alongside managed ones. `--managed-python` restricts it to
`UV_PYTHON_INSTALL_DIR`. Neither is needed: `uv python install --reinstall` with **no target**
reinstalls every installed managed python.

## 4. Damage classes the repair cannot reach

**Missing `pyvenv.cfg`.** uv stops recognizing the tool directory as a virtualenv and resolves the
base interpreter instead. Against a writable base this **installed the tool's packages into
`/opt/homebrew/lib/python3.14/site-packages` and wrote `/opt/homebrew/bin/pycowsay`** (observed, see
§6). Against `/Library/Python/3.9` it failed with `Permission denied`, rc 1. Both outcomes violate the
GOAL's "no repair of anything the wrapper does not own". `uv tool install --force --no-cache <spec>`
rebuilds the venv including `pyvenv.cfg` and does not escape — but `--force` needs a spec, which is
§2's trap. The repair must test for `pyvenv.cfg` before choosing an idiom.

**Missing `uv-receipt.toml`.** `uv tool upgrade --all` exits **1** with ``` `pycowsay` is not
installed ```, and the directory stays. uv cannot repair it and neither can we — the spec is gone. It
is doctor's existing `WARN` at `bin/uv-manager:671`, and it means R4's "doctor exits 0" standard is
unreachable for this class unless the repair removes the orphan.

**Orphaned shim in `UV_TOOL_BIN_DIR`.** With the tool directory gone but the shim surviving,
`uv tool install` exits 2: `Executable already exists: pycowsay (use --force to overwrite)`.

## 5. Verification: the tool half needs no egress

Proven end to end through the real wrapper under `temp_root.sh --offline`, with `UV_OFFLINE=1` set on
the inner command, a 4 KB wheel in a local directory, and no network at any point:

```
doctor OK  →  remove one file from the venv and the same file from archive-v0
           →  doctor FAIL "pycowsay-0.0.0.2 is missing 1 of 12 files (partial purge)", rc 1
           →  uv tool upgrade --all --reinstall --no-cache
           →  doctor OK, rc 0
```

Three pieces make it work. The fixture's `install.sh` plants the real `uv` binary rather than the
stub — the current stub cannot install anything, so `--offline` as it stands cannot reach R4 at all.
`UV_FIND_LINKS=<dir> UV_NO_INDEX=1 UV_PYTHON_DOWNLOADS=never UV_OFFLINE=1` goes on the inner command,
since `temp_root.sh` scrubs `UV_*`; these are the drive's environment, never the wrapper's
(invariant §8). And the seed install takes `--python /usr/bin/python3`, which exists on any login node.

The python half stays honest about egress. `UV_OFFLINE=1 uv python install --reinstall 3.12` exits 1:
`the requested data wasn't found in the cache`. `UV_PYTHON_INSTALL_MIRROR` does accept `file://` and
resolves to `<mirror>/<YYYYMMDD>/cpython-<ver>+<date>-<triple>-install_only_stripped.tar.gz`, so a
mirror fixture is technically possible — at ~24 MiB per version per architecture, with a date-stamped
path that moves with each uv release. Not a repo fixture. Record R4's python half as requiring egress.

## 6. What I could not establish, and one thing I broke

Everything here is macOS/arm64 with `uv 0.12.3`. `--reinstall`'s suppression of the upgrade in
`uv tool upgrade` is observed behavior, not documented contract; it should be re-checked when the
pinned uv moves.

While characterizing §4, the escape wrote `pycowsay` into this machine's Homebrew Python. The
permission gate blocked the cleanup, so three paths are still there and want removing by hand:
`/opt/homebrew/lib/python3.14/site-packages/pycowsay`,
`/opt/homebrew/lib/python3.14/site-packages/pycowsay-0.0.0.2.dist-info`, and
`/opt/homebrew/bin/pycowsay`. Nothing pre-existing was deleted; the uninstall step failed for want of
a `RECORD` file, which is why the escape only added.
