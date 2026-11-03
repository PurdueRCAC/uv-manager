# 00 — Digest: installed-tool-parity

Four briefs, all run by the planner in sequence rather than fanned out. The GOAL's shaping run had
already measured the replay idiom (Q1-Q4), and what remained were measurements that each needed a
seeded real-uv sandbox and the previous result: the copy-back depended on the replay form, the
record format on the copy-back, the gates on the prototype. PLAN §4 records the narrowing. Every
claim below was executed, with uv 0.13.6 on macOS arm64 under `temp_root.sh`, bash 3.2.57 and its
POSIX `sh`. The drives are in [`drives/`](drives/).

| # | Brief | Decides |
|---|---|---|
| 01 | [Replay and receipt](01-replay-and-receipt.md) | N1's mechanism, the replay's exact form, which sources restore, credentials |
| 02 | [Records and backfill](02-records-and-backfill.md) | The record's files, how a `uv tool` command finds what it changed, atomic writing, the backfill's source |
| 03 | [Trampoline and entry](03-trampoline-and-entry.md) | The `sh` body, its cost, the internal entry, generation and migration |
| 04 | [Cluster drive](04-cluster-drive.md) | `tests/repair-race.sh` scenarios `I` and `ikill`, their keys, the jobs |

## Decisions

- **D1 · N1 holds by copying the receipt back.** After a replay with `-c`, uv's receipt carries the
  pins and holds the tool. Copying the record's verbatim receipt over it, when every `install-path`
  in the copy names this tree's `UV_TOOL_BIN_DIR`, leaves the tool exactly as its unpurged twin:
  `uv tool upgrade` moved the unpinned pair tool 2.11.1 → 2.15.0 in all of W, E, R and S, and the
  git tool upgrades as its twin does. Where the copy names another tree (another platform key, a
  relocated root), uv's pinned receipt stays, a `.uvm-restored` marker goes in the tool directory,
  doctor reports the hold, and the documentation names `uv tool install --force <request>`. (01)
- **D2 · The replay.** `(cd / && UV_PYTHON=<minor> UV_NO_CACHE=1 exec "$real_uv" tool install
  --force -c <record>/constraints <request…>) >&2`, with `--force` dropped from the request (a
  repeated flag exits 2) and `<name>[extras]@latest` rewritten to `<name>[extras]` (`@latest`
  conflicts with older pins). `UV_PYTHON` rather than `-p`, so a request's own `--python` wins
  (N4) and no pin file steers it. (01)
- **D3 · Sources.** Index, VCS and URL archives restore (a `name @ <url>` constraint pins a URL
  archive even when the request names the package). Local sources are recorded and refused, named
  by the request's option or by a `@ file:` constraint. (01)
- **D4 · Credentials.** uv strips userinfo from its receipt; the wrapper strips it from the request
  and from `direct_url.json` URLs, keeping a password-less ssh login. (01, 02)
- **D5 · The record** is `request`, `constraints`, `python`, `entrypoints` and `uv-receipt.toml`
  under `$UVM_DATA/tools/<name>/`, about 0.3 KB of content and 20 KB by `du -sk`. Staged whole and
  renamed into place with the old one moved aside first, so a reader sees the old, none, or the new.
  (02)
- **D6 · What a `uv tool` command changed** is a before/after signature per tool: receipt checksum,
  receipt inode, dist-info names. The inode catches a forced reinstall that changes no byte. (02)
- **D7 · The backfill** renders the request from one `uv tool list --show-version-specifiers
  --show-with --show-extras` call (`UV_NO_CACHE=1`, from `/`), only when some tool lacks a record.
  It runs in doctor, after a `uv tool` command that exits 0, and in the walk's holder. (02)
- **D8 · The trampoline** execs the shim when the knob is off and `UVM_ROOT` names a tree with it,
  and otherwise execs `uv-manager _trampoline <name>` (the `uv-manager` on `PATH`, else the
  generating wrapper's). It costs 7.6 ms against `release/0.8.0`'s 10.8 ms. (03)
- **D9 · The internal entry** `uvm_tool_entry` runs the scope check under the knob, then the
  on-demand restore when the shim is still missing, then execs the shim after `uvm_unlock`; with
  no shim it exits 127, naming the command and, for a recorded one, the remedy. (03)
- **D10 · The walk** restores, from its record, a recorded tool with a trace that lost its
  directory, `pyvenv.cfg`, interpreter link, receipt or an executable, and any recorded tool the
  in-place arm would refuse. A tool the in-place arm can repair keeps the 0.7.0 arm, so its
  receipt stays byte-identical (N1's first direction). A recorded tool with no trace is never
  restored by the walk; doctor lists it. (02, 03)
- **D11 · On demand (R5)** a knob-set call by name whose shim is still missing restores that tool
  alone under the repair lock. Success writes nothing; failure writes `<scope>+tool-<name>.failed`
  with the reason, and the waiters' predicate (`shim executable or failed record`) fails them with
  it, measured within seconds against a 60 s timeout. (03)
- **D12 · Doctor writes nothing under `UVM_ROOT`.** Its interpreter probe runs with
  `PYTHONDONTWRITEBYTECODE=1` (on `release/0.8.0` it leaves `.pyc` files) and the backfill's `uv
  tool list` with `UV_NO_CACHE=1`; the trampoline sync it runs skips the 0.7.0 migration. (01)
- **D13 · Drives get a sandboxed `XDG_DATA_HOME`.** `temp_root.sh` redirects it as it does
  `XDG_CONFIG_HOME`; otherwise every drive's `uv tool install` writes records into the developer's
  own `~/.local/share/uvm`. P1's first item.
- **D14 · Gates are scripts** in `spec/installed-tool-parity/gates/`, each run green on a
  throwaway prototype and red against its predecessor's state (PLAN §6).

## Contradictions resolved

- The shaping run's replay of an unpinned tool used `uv tool install --force pycodestyle --with
  six` to build the "unpinned at an older release" state in one drive. `--force` rebuilds and
  moves it to the newest release (measured), so that drive's N1 rows said nothing.
  `tests/repair-race.sh`'s `T` builds the state without `--force`, and so do the gates.
- `README.md` § *Scratch purges* calls a missing receipt advisory (the tool runs). With a record it
  is still advisory to doctor, and the walk restores it (R4 names shape R): doctor keeps the WARN,
  and the restore arm acts on it.
