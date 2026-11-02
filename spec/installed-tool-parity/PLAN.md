# PLAN — An installed tool run by its own name gets the repair `uvx` gets

> **Status:** Accepted at the plan gate, amended there and at review cycle 1 (A2, 2026-11-01) ·
> **Last updated:** 2026-11-01
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/). Every
> design element traces to a GOAL R-ID. Base: `release/0.8.0` (`648496d`), wherever this file or
> the skill says `main`.

## 1. Summary

The wrapper keeps a record of every tool `uv tool install` puts in the scratch tree, under a second,
durable root, `UVM_DATA` (default `${XDG_DATA_HOME:-$HOME/.local/share}/uvm`). The recorded tools'
trampolines move there too, and every trampoline changes shape (the interpreters' and unrecorded
tools' stay in `$UVM_ROOT/bin`, A2): with the knob off they still exec the shim and nothing else, and with
the knob on, or the shim missing, they enter the wrapper through one internal entry,
`uv-manager _trampoline NAME`, which runs the same scope check a `uv` call runs and then the tool.
Inside that check the walk gains a restore arm: a recorded tool that lost what only its record can
rebuild is replayed with `uv tool install --force -c <pins>`, and its receipt copied back so nothing
is held against `uv tool upgrade`. Five phases, all measured on a throwaway prototype: records (P1),
trampolines and the entry (P2), the restore and the backfill (P3), the on-demand restore by name
(P4, the hammerable R5), and the cross-node drive with the surface census (P5).

## 2. Design

### What is removed

- **0.7.0's trampoline body, in place.** A sync rewrites each marked file in `$UVM_ROOT/bin` that a
  shim names with the new body under the same path, and removes one only when no shim of that root
  names it, 0.7.0's rule (A2). `uvm_neutral_bin` stops naming `${uvm_base}/bin`, which becomes
  `uvm_root_bin`. The modulefile keeps `$UVM_ROOT/bin` on `PATH` after `$UVM_DATA/bin`, permanently.
- **Locating the tree from `$0`.** The 0.7.0 body's `d=$(CDPATH= cd -- "$(dirname -- "$0")/.." &&
  pwd -P)` goes. Two command substitutions and a `dirname` exec leave the hot path (03).
- **The sixth directory in `uvm_export_env`'s guard.** `$UVM_DATA/bin` is created by the sync
  only, so no `uv` or `uvx` call creates anything under `UVM_DATA` (R10).
- **"A tool run by its own name skips the check"** and its advice to write `uvx <tool>` (`README.md`
  *Reach*), the "none under `$HOME`" claims (`README.md:4`, `:302`), and mitigation 4's "Prefer
  `uvx` over `uv tool install`" (R12).
- **0.7.0's refusals for a recorded tool.** A recorded tool without `pyvenv.cfg`, from a git or
  URL source, or with a broken interpreter link is restored instead of failing the scope. An
  unrecorded one is refused exactly as on 0.7.0 (R4).
- **The 0.7.0 message "it exists for another architecture"** where it is false: a recorded tool
  whose shim is missing gets its own message (R6). Without a record the 0.7.0 text stays.
- **`.pyc` writes by doctor's interpreter probe** (D12).

### `bin/uv-manager`, function by function

**`uvm_init`** (high-risk). After the root, resolves the durable tree with builtins only:
`uvm_data` from `UVM_DATA`, else `${XDG_DATA_HOME}/uvm`, else `${HOME}/.local/share/uvm`, and
`uvm_data_origin` (`UVM_DATA`, `$XDG_DATA_HOME`, `$HOME`). With none of the three set, `uvm_data`
is empty and the origin says "nothing: set UVM_DATA"; nothing on the hot path fails for it, and
everything that writes there (records, trampolines) skips. Derives `uvm_records="${uvm_data}/tools"`
and `uvm_neutral_bin="${uvm_data}/bin"` (both empty when `uvm_data` is), and `uvm_root_bin` =
`${uvm_base}/bin`, this root's trampolines (A2). No `stat`, no fork: §10's hot path gains three builtin tests.

**`uvm_export_env`** (high-risk). Exports `UVM_ROOT=${uvm_base}` and, when resolved,
`UVM_DATA=${uvm_data}` (N8; both neutral, §1). Prepends `${uvm_neutral_bin}` instead of
`${uvm_base}/bin`, still idempotently. The `mkdir -p` guard covers five directories, not six. The
exports alone are `uvm_export_trees`, which the knob-off trampoline entry runs, so it creates
nothing (C1-F7).

**Records** (new, beside the trampolines): `uvm_strip_userinfo`, `uvm_record_constraints`,
`uvm_record_write`, `uvm_tool_marks`, `uvm_records_update` (02).

- `uvm_record_write TOOL [ARG...]` stages `request` (ARGs, userinfo stripped; with none, the
  existing record's), `constraints`, `python`, `entrypoints` and the receipt copy under
  `${uvm_records}/.TOOL.<pid>` (`umask 077`), moves the old record aside, renames the stage in,
  removes a stage a rival's rename nested, removes the old record. It returns 0 on every path: a
  record that cannot be written leaves a `note`, never a changed exit status (§2).
- `uvm_tool_marks` prints one line per tool: name, receipt `cksum`, receipt inode (`ls -i`),
  dist-info names. One `cksum` and one `ls` for all receipts.
- `uvm_records_update SUBCMD BEFORE [ARG...]`, after an exit 0: for `install`, one changed tool
  takes the arguments as typed, more than one keep their requests; for `upgrade` every changed tool
  keeps its request with new pins; for `uninstall` a tool gone since BEFORE loses its record.

**`uvm_trampolines [records]`** (high-risk; amended at review cycle 1, A2). Two directories, one
helper, `uvm_trampoline_dir DIR NAMES WRAPPER`: write every name (`umask 077`, the body is 03's),
then remove each marked file no name lists. `$UVM_DATA/bin` takes every record's `entrypoints`.
`$UVM_ROOT/bin` takes every shim name under `${uvm_base}/*/bin/{shims,python-shims}`, 0.7.0's rule,
so a marked 0.7.0 trampoline a shim names is rewritten in place under its own path and a sync on one
root touches no other root's. With `records`, the second directory is skipped (doctor). A directory
that cannot be created or written (`-d` and `-w`) is left as it is. The baked wrapper path is
`$(abspath "$0")`'s directory plus `/uv-manager`. §9 otherwise unchanged.

**`uvm_tool_entry NAME [ARG...]`** (new, an `exec` site; P5's census proposes it for the
high-risk list in `AGENTS.md`). Reached
as `uv-manager _trampoline NAME …` from `uvm_manager_main`, before `uvm_init` like `help`. Knob on:
`uvm_ensure_uv`, `uvm_export_env`, `uvm_repair`, then `uvm_restore_by_name` when the shim is still
missing (P4). Then the shim under `UV_TOOL_BIN_DIR`, else `UV_PYTHON_BIN_DIR`: `uvm_export_env`,
`uvm_unlock`, `exec`. Else `uvm_tool_missing`: exit 127 with the recorded-but-not-present message
and its remedy, or 0.7.0's three lines. The knob-off path calls neither `uvm_ensure_uv` nor
`uvm_export_env` before deciding, so a missing shim takes no lock and creates nothing (R6), and
execs through `uvm_export_trees`, so a present one creates nothing either (C1-F7).

**`uvm_detect`** (high-risk). A new first step, `uvm_detect_records`, walks the records. A recorded
tool with no trace in this tree (no `tools/<name>`, no shim named by its entrypoints, dangling or
not) goes on `uvm_absent_tools` for doctor and is never restored by the walk (R5, N2). A recorded
tool with a trace that lost its directory, `pyvenv.cfg`, interpreter link or an executable is a
FAIL "tool X is damaged (…); its record restores it"; one that lost only its receipt is a WARN
saying the same (it still runs). Both go on `uvm_restore_tools`. The existing passes skip those
tools: no dangling-shim FAIL, no orphan refusal, no missing-receipt WARN, no missing-file FAIL for
a tool the restore owns. The interpreter probe gains `PYTHONDONTWRITEBYTECODE=1` (D12). Nothing
else changes, so an unrecorded tool is reported exactly as on 0.7.0.

**`uvm_restore TOOL`** (new; high-risk note: it reads its own recorded request, and only for the
three token classes the gate accepted under deviation 1, `--force`, `<name>[extras]@latest` and the
local-file options, never as a model of uv's command line). D2's replay from `/` in a subshell, every byte to stderr. Refuses a
local source first (D3), naming the tool and the option or "a local path". On success, copies the
receipt back when every `install-path` names `${UV_TOOL_BIN_DIR}/` (temp name and `mv -f` inside
the tool directory), else writes `.uvm-restored` there. On failure sets `uvm_repair_reason` to "the
restore of tool X from its record failed" and returns 1. It never writes the record (R1).

**`uvm_backfill`** (new). D7. `uvm_record_write` with the rendered request, for each tool with a
receipt, `pyvenv.cfg` and no record. Amended at review cycle 1: a requirement uv renders across two
lines (a VCS URL with a subdirectory) is joined; a `--with` rendered as a name and a URL is recorded
as `name @ URL` (C1-F5); the receipt's `[tool.options]` `index-url` and `extra-index-url`, where
they are one-line strings, join the request (`uvm_receipt_indexes`, C1-F6); a tool whose receipt
counts more git, URL or local requirements than its environment has `direct_url.json` files is
skipped (`uvm_unpinnable`, C1-S1). `uvm_record_constraints` carries `#subdirectory=` (C1-F4), and
the receipt copy is skipped when any URL in it carries userinfo the strip rule would remove, under
any scheme (`uvm_carries_userinfo`, C1-F8).

**`uvm_repair_run`** (high-risk). After the interpreter arm and before the in-place arm: one note,
"restoring the installed tools for <arch> from their records: …", then `uvm_restore` per tool, the
first failure ending the walk with its reason. The in-place loop skips tools being restored, and a
recorded tool it would refuse (no `pyvenv.cfg`, no runnable `bin/python`, a URL, git or path
source, a source in the receipt, no pins) is restored instead. No message names `pip install`,
`python install` or `tool upgrade` (the fixture's counters).

**`uvm_repair`** (high-risk). Unchanged contract. The holder runs `uvm_backfill` (notes to stderr)
before `uvm_repair_run`, so a user who only runs jobs after the upgrade gets records (N7).

**`uvm_restore_by_name NAME`** (new, P4). Finds the record whose `entrypoints` names NAME. Its
failed record is `${uvm_repair_failed%.failed}+tool-<encoded tool>.failed`; `+` never appears in an
encoded scope (`_2B`), so the two never collide. `uvm_acquire_lock repair fail uvm_ondemand_done`,
the predicate being "shim executable or failed record present", with the arrival test before and
the re-check after, as `uvm_repair` does. The holder restores, records a failure (temp name and
`mv`), or, restored with no NAME among its executables, records that. Success writes nothing (N3).
Releases, then execs via the caller or dies with the recorded reason.

**`uvm_doctor`**. Runs `uvm_backfill` (stderr), only where uv's `tools/.lock` already exists (C1-F1),
and `uvm_trampolines records` first, then `uvm_detect`. Amended at review cycle 1: one advisory per
tool with a receipt, `pyvenv.cfg` and no record, naming `uv tool list` as what writes one, or, for a
tool `uvm_unpinnable` refuses, the source to install it again from. Adds advisories: each absent recorded tool ("recorded but not installed for <arch>.
Run it by name with UVM_REPAIR set to restore it here, or uv tool uninstall …"), and each tool with
`.uvm-restored` ("pinned by a restore … `uv tool install --force` with its original arguments
releases it"). The remediation block gains one replay line per restorable tool. The value-outcome
loop skips `+tool-` records. Writes nothing under `UVM_ROOT` (R8).

**`uvm_status`**. Adds `UVM_DATA:  <path>  (from <origin>)`; `trampoline dirs:` names
`$UVM_DATA/bin` and `$UVM_ROOT/bin`.

**`uvm_help`**. `UVM_DATA` in *Environment*: what it holds, a few KB per tool, its default.

**The dispatch tail** (high-risk). Right after `uvm_export_env`, the self-heal (N6 as amended):
`if [[ -n "${uvm_neutral_bin}" && ! -d "${uvm_neutral_bin}" ]]; then uvm_trampolines || true;
fi`. Measured at 5.2 µs per call on bash 3.2 and APFS (200 000 iterations of the test), against
about 9.5 ms of wrapper per call (GOAL Q4); one `stat`, no fork, while the directory exists. The
first call after an upgrade writes the trampolines and rewrites 0.7.0's in place; on a tree with no
installed tool it creates the two directories and no file, so R10's check holds (N11). Concurrent first calls each sync; every write is
a temp file and `mv -f`, so they converge. The `tool`/`python` branch takes `uvm_tool_marks` before `uv
tool install|upgrade|uninstall`, runs uv under `set +e` as now, and on `rc == 0` for `tool` runs
`uvm_records_update` and `uvm_backfill`, each `|| true`; then `uvm_trampolines || true`, then
`exit "${rc}"` (§2: nothing overwrites `rc`). `uvm trampolines` and `uvm install` sync both
directories.

### State tree afterwards

```
$UVM_ROOT/                      scratch: the payload, per architecture, rebuildable
├── bin/                        this root's trampolines, one per shim name (interpreters, tools
│                               without a record), on PATH after $UVM_DATA/bin; 0.7.0's rewritten
└── <arch>/
    ├── tools/<name>/           + .uvm-restored when a restore could not put the receipt back
    ├── bin/shims/, bin/python-shims/, cache/, python/, versions/, current
    └── .repair/                + <scope>+tool-<name>.failed for a failed restore by name
$UVM_DATA/                      durable: what was asked for, a few KB per tool, no architecture
├── bin/<name>                  trampolines, one per recorded executable        (on PATH, first)
└── tools/<name>/
    ├── request                 uv tool install's arguments as typed, userinfo stripped
    ├── constraints             name==version, or name @ <source>, one per distribution
    ├── python                  3.12
    ├── entrypoints             one executable per line
    └── uv-receipt.toml         uv's receipt, byte for byte
```

### The two routes after this cycle

| Route | Knob off | Knob on, scope not checked | Purged |
|---|---|---|---|
| `srun uvx <spec>` | as 0.7.0 | scope check, then uv | restores recorded tools with a trace (Q3's installed forms), repairs the rest as 0.7.0 |
| `srun <tool>` | trampoline execs the shim | trampoline → `_trampoline` → scope check → shim | W/E/R/S/G restored in the walk; no trace: restored by name alone |

### User-facing surface (same-commit rule)

| Surface | Phase | What changes |
|---|---|---|
| `uvm_help` | P1, P2 | `UVM_DATA` line (P1); `trampolines` line names `UVM_DATA/bin` (P2) |
| `README.md` | P1 | line 4's quota sentence and the `:302` status comment say what lives under home; *Reference* row for `UVM_DATA`; the tree diagram in *What the wrapper does* |
| | P2 | *Reach*: both routes under one contract, the trampoline enters the wrapper when the knob is set; *Design notes* "Architecture-neutral trampolines" updated, with why there are two directories (A2); the hot-path figure; the `UVM_DATA` section says what becomes of the 0.7.0 trampolines (they serve from `$UVM_ROOT/bin`, and the first `uv` call rewrites them in place) and to run `uv-manager doctor` once after upgrading. No section titled by a version |
| | P3 | *Repairing inside a job*: the restore, what it covers and concedes (N1's copy-back and its fallback, N5, N9), the refusals that now apply only to unrecorded tools; mitigation 4 reworded; *Design notes* entry: why what the user asked for lives outside the scratch tree |
| | P4 | the restore by name; a tool installed on another architecture or cluster (N5) |
| `etc/uv-manager.conf.example` | P1, P3 | `UVM_DATA` commented with its default; the repair paragraph names the restore |
| `share/modulefiles/uv/main.lua` | P1, P2 | `setenv("UVM_DATA", …)` from `XDG_DATA_HOME` else `HOME` (P1); `$UVM_DATA/bin` prepended after `$UVM_ROOT/bin`'s `prepend_path`, so it lands first, with `$UVM_ROOT/bin` kept for the root's own trampolines (A2); design note; help text saying to run `uv-manager doctor` once after upgrading (P2) |
| `AGENTS.md` § *Invariants* + `invariants.md` | P1, P2, P3 | §8 records under `UVM_DATA` (P1); §1 (with `$UVM_ROOT/bin` kept, A2) and §9's two directories, §8's exports, the five-way guard, the self-heal (P2); §8's restore beside the repair, the doctor probe, the backfill's limits (P3) |
| `AGENTS.md` repository map, `tests/` paragraph, high-risk regions | P5 | scenarios `I` and `ikill`; the census proposes `uvm_tool_entry` for the high-risk list |

### Release note

For the foreman to carry into the 0.8.0 notes (R12, N6 as amended); `README.md` carries the same
facts in its `UVM_DATA` section, and no README section is titled by a version.

> Installed tools now keep a record under `UVM_DATA` (default `~/.local/share/uvm`), and a recorded
> tool's trampoline lives in `$UVM_DATA/bin`. The module puts `$UVM_DATA/bin` first on `PATH` and
> keeps `$UVM_ROOT/bin` after it, where the managed interpreters' trampolines and those of tools
> without a record stay. The first `uv` call under 0.8.0 writes the new trampolines and rewrites
> each 0.7.0 trampoline in `$UVM_ROOT/bin` in place, so a running job keeps finding it. Run
> `uv-manager doctor` once after upgrading: it writes a record for every tool installed under 0.7.0
> and the trampolines for them. A `PATH` entry naming `$UVM_ROOT/bin` by hand gains `$UVM_DATA/bin`
> ahead of it.

### Requirement → design map

| R-ID | Design element(s) | Phase |
|------|-------------------|-------|
| R1 | `uvm_restore`'s replay (D2) with `constraints`; the receipt copy-back (D1); the record never written by a restore; VCS pins as constraints; `UV_PYTHON` from `python` | P3 |
| R2 | `uvm_tool_marks` + `uvm_records_update` in the dispatch tail; `uvm_record_write` staged and renamed; `uvm_strip_userinfo`; nothing on a non-zero exit | P1 |
| R3 | the trampoline's knob-on path; `uvm_tool_entry` → `uvm_repair` → `exec` | P2 |
| R4 | `uvm_detect_records` (W, E, R, S, G with a trace); the restore arm in `uvm_repair_run` under the repair lock and outcome contract; the in-place arm's fallback; unrecorded tools untouched | P3 |
| R5 | `uvm_restore_by_name`, its predicate and failed record; the walk never restores a tool without a trace | P4 (second clause: P3) |
| R6 | the trampoline's knob-off path; `uvm_tool_missing`; the knob-off entry takes no lock | P2 |
| R7 | `uvm_trampolines`: `$UVM_DATA/bin` from records, removal only when no record names one; `$UVM_ROOT/bin` from this root's shims under 0.7.0's rule, 0.7.0's trampolines rewritten in place, no other root touched (A2); the cascade through the entry (N8) | P2 |
| R8 | `uvm_backfill` in doctor (where `tools/.lock` exists), after `uv tool`, in the holder; its limits (`uvm_unpinnable`, `uvm_receipt_indexes`, the `--with` URL form); doctor's advisories; doctor's sync of `$UVM_DATA/bin` alone; D12 | P3 |
| R9 | `uvm_data` in `uvm_init`; status line; modulefile `UVM_DATA`; records and trampolines only, none keyed by architecture (P1). `PATH` order with `$UVM_ROOT/bin` kept after; the self-heal in the dispatch tail (P2) | P1, P2 |
| R10 | `uvx` path unchanged; nothing written under `UVM_DATA` by `uvx` on a tree with no tool; five-way guard | P3 (gate), P2 (guard) |
| R11 | `tests/repair-race.sh` scenarios `I`, `ikill`; two generic jobs | P5 |
| R12 | the surface table above; *Release note* above; census gate | P1-P4 (text), P5 (census) |

## 3. Invariant gate (AGENTS.md constitution check)

Walked against [`invariants.md`](../../.agents/factory/invariants.md) before the drives and again
after the prototype passed every gate.

- **§1 Architecture (changed on purpose).** The `PATH` entries a modulefile may export become the
  deployment `bin/`, `$UVM_DATA/bin` and `$UVM_ROOT/bin` after it, permanently (N6 as amended, A2);
  all three are neutral. Both neutral: `UVM_DATA` names no architecture, and
  nothing under it does (R9's gate greps for both platform keys). The wrapper's new exports,
  `UVM_ROOT=${uvm_base}` and `UVM_DATA`, are neutral. The platform key is still resolved at exec
  time on the executing node, by the trampoline and by `uvm_init`.
- **§2 Process semantics.** Honored. `uvm_tool_entry` `exec`s the shim, so status and signals are
  the tool's. The `tool` intercept still captures `rc` under `set +e`, and the record writes, the
  backfill and the sync are each `|| true` before `exit "${rc}"`.
- **§3 Root resolution.** Honored and relied on: a trampoline with `UVM_ROOT` unset enters the
  wrapper, which runs the unchanged cascade (N8). `help` and `--version` stay ahead of `uvm_init`;
  `_trampoline` sits beside them and calls `uvm_init` itself.
- **§4 Pinning.** Untouched. The restore never calls `uvm_install` and cannot move `current`.
- **§5 Locks.** Contract unchanged. The on-demand restore is one more caller of `uvm_acquire_lock
  repair fail PREDICATE`, with its own predicate, never early-outing on the provisioning question,
  and `uvm_tool_entry` releases before its `exec`. Two locks are still never held together.
- **§6 Installer.** Untouched. The record writer's rival handling copies §6's (discard only one's
  own uniquely named stage).
- **§7 Output.** Honored. Restore, backfill and their notes go to stderr; the tool's stdout is its
  own (R3's gate compares it exactly). New multi-line output is a heredoc through `cat`.
- **§8 Environment (changed on purpose).** The wrapper also exports `UVM_ROOT` and `UVM_DATA` (N8)
  and writes under `UVM_DATA` records and trampolines only (R9). The restore sits beside the
  in-place repair: it replays a record rather than reinstalling in place, keeps resolution the
  user's by its pins, runs from `/`, names its interpreter through `UV_PYTHON`, and is the one
  place the wrapper writes a receipt (a byte copy of uv's own, never built). `uvm_set_paths` stays
  pure. The `mkdir -p` guard becomes five-way. Doctor's probe runs with `PYTHONDONTWRITEBYTECODE=1`.
- **§9 Trampolines (changed on purpose).** Two directories (A2): `$UVM_DATA/bin` from records, not
  removed while a record names them; `$UVM_ROOT/bin` from this root's shims, 0.7.0's rule per root,
  0.7.0's trampolines rewritten in place. Marker, rewrite-never-skip, temp and `mv`, the
  spare rule and the `/bin/sh` body resolving the platform key at exec time carry over.
- **§10 Portability.** Every idiom executed under bash 3.2 and its `sh` (02, 03). The knob-off
  `uv` path gains no fork (three builtin tests in `uvm_init`, two exports, and the self-heal's one
  `[[ -d ]]`, 5.2 µs measured). The knob-off trampoline
  is 3 ms cheaper. `UVM_REPAIR` off still forks nothing in the dispatch tail.
- **§11 Argument inspection.** The parser is unchanged and recognizes only `self update`, `tool`
  and `python`. The record keeps `uvm_rest` as opaque strings. The restore reads its own recorded
  request for a short list of options, which is a bend (deviation 1).
- **§12 Conventions.** Same-commit rule per the surface table; no spec ids in the script or README;
  the version stays `0.7.0` until `/uvm-release`.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| **1.** The restore scans its recorded request for `--force`, `<name>@latest` and the local-file options (`-e`, `--editable`, `--with-editable`, `--with-requirements`, `-c`, `--constraints`, `--overrides`, `-b`, `--build-constraints`), §11's "not a model of uv's CLI" | `--force` twice exits 2 and `@latest` fails against its own pins (measured); N9 requires naming the local option | Replaying the request untouched fails every request typed with `--force` or `@latest`. Parsing the receipt instead is TOML parsing, which N1 and the seed rule out. The list is per-subcommand and fixed, and a miss fails the restore loudly rather than restoring wrong. |
| **2.** `temp_root.sh` (factory harness) redirects `XDG_DATA_HOME` into the sandbox, in a feature phase | Without it every drive's `uv tool install` writes records into the developer's `~/.local/share/uvm`, which the drive rules forbid | Setting `XDG_DATA_HOME` in every gate leaves every reviewer drive leaking. The gate ruled it stays P1's first item. |
| **3.** Doctor's interpreter probe gains `PYTHONDONTWRITEBYTECODE=1`, and the backfill's `uv tool list` `UV_NO_CACHE=1` | R8: doctor writes nothing under `UVM_ROOT`; `release/0.8.0`'s probe already leaves `.pyc` there (measured) | Checking R8 on a tree whose bytecode is already warm hides a write that real doctor runs make. |
| **4.** A `.uvm-restored` file in a restored tool's directory, inside uv's territory | N1's fallback needs doctor to know a tool is pinned by a restore, and the record must stay byte-identical | Comparing the live receipt with the record's copy cannot tell a cross-tree restore from a later `install --force` there. The file lives exactly as long as the restored environment (`--force` drops it, measured). |
| **5.** Gates committed as scripts under `spec/installed-tool-parity/gates/` | P3's drive is ~150 lines of `sh`; inline in YAML it is unreviewable and its line numbers in a failure mean nothing | Inline literal blocks, as the template prefers. Each `verify:` stays one command naming the script, and every script asserts post-conditions. |

## 4. Rabbit holes (resolved)

Research narrowed from a parallel fan-out to four sequential briefs run by the planner (high-risk
exception, narrowed): each needed a seeded real-uv sandbox and the previous brief's answer, and the
shaping run had already measured Q1-Q4. Every claim below was executed.

- **N1 — can a restore leave nothing held?** Yes: copy the record's receipt back when its
  `install-path`s name this tree. Measured in W, E, R, S and on the git tool: `uv tool upgrade`
  behaves as on the unpurged twin. Where they name another tree, the fallback, with doctor's
  advisory and the marker. ([01](research/01-replay-and-receipt.md))
- **The replay's form.** `--force`/`--python` twice exit 2; `@latest` fails against older pins;
  `UV_PYTHON` beats a global pin and loses to the request's `--python`. ([01](research/01-replay-and-receipt.md))
- **URL archives (N9).** Restorable through a `name @ <url>` constraint, even by name. Local
  sources refused. ([01](research/01-replay-and-receipt.md))
- **Credentials (R2).** uv strips them from the receipt; the wrapper strips the request; pypi.org
  accepts `__token__:SECRETMARK`, so R2's check has a host. ([01](research/01-replay-and-receipt.md))
- **Which tools a `uv tool` command touched.** Receipt checksum alone misses a forced identical
  reinstall; adding the inode catches it. ([02](research/02-records-and-backfill.md))
- **Atomic record replacement.** No primitive renames over a non-empty directory; two renames give
  old, none, or new. ([02](research/02-records-and-backfill.md))
- **Backfill source (N7).** `uv tool list`'s renderings, including the two-space VCS form and the
  URL archive that renders no requirement. ([02](research/02-records-and-backfill.md))
- **Trampoline cost and knob semantics in `sh`.** 7.6 ms against 10.8 ms; `case ${UVM_REPAIR:-0}`
  matches the wrapper's test for unset, empty, `0`, `00`, `false`. ([03](research/03-trampoline-and-entry.md))
- **Does doctor already write under `UVM_ROOT`?** Yes, `.pyc` from its probe, and `uv tool list`'s
  interpreter cache. Both suppressed. ([01](research/01-replay-and-receipt.md))
- **`UV_LINK_MODE`.** The sibling's Notes record that the module does not set it. This GOAL does
  not lean on that claim (`git grep -n LINK_MODE spec/installed-tool-parity/GOAL.md`: no match),
  and the restore runs with `UV_NO_CACHE=1`, so no link from the cache enters a restored tool.

## 5. Risks & open questions

**Rulings at the plan gate (foreman, 2026-11-01).** The plan is accepted with these, and deviations
1-5 are accepted.

1. **`temp_root.sh`** stays P1's first item, in P1's commit.
2. **The release note** lives in *Release note* above (§2), for the foreman to carry into the 0.8.0
   notes. No README section is titled by a version; the `UVM_DATA` section carries the durable
   migration facts. R12's check is amended to match.
3. **The upgrade gap is not accepted.** GOAL R7, R9, R12 and N6 are amended: the 0.8.x module keeps
   `$UVM_ROOT/bin` after `$UVM_DATA/bin`, a sync removes a 0.7.0 trampoline only once it is
   replaced (or unnamed), any `uv` call that finds `$UVM_DATA/bin` absent generates it once (5.2 µs
   per call measured), and the documentation says to run `uv-manager doctor` once after upgrading.
   P2 carries all of it, and its gate gains the upgrade-path check.
4. **R10 against N7:** N7 governs; GOAL Clarification N11 says so.
5. **R5 beyond its letter:** accepted.
6. **R7's removal reading:** accepted.

**Rulings at review cycle 1 (foreman, 2026-11-01).** [`REVIEW.md`](REVIEW.md) § *Review cycle 1*,
*Rulings*. Rulings 1 and 9 are contract amendment A2 (GOAL R7, R9, R11, N6, Clarification A2): the
two trampoline directories above and R11's dropped second-filesystem clause. Rulings 2-8 are fixes
under the contract as written: doctor backfills only where `tools/.lock` exists (C1-F1); the VCS
constraint carries `#subdirectory=` (C1-F4); a `--with` direct URL is backfilled as `name @ URL`
(C1-F5); the receipt's one-line `index-url` and `extra-index-url` join a backfilled request, the
rest replaying under the configuration in effect (C1-F6); the knob-off entry creates nothing
(C1-F7); the receipt-copy guard matches userinfo under any scheme (C1-F8); a tool whose source pin
a purge took gets no record (C1-S1), widened from git and URL to the local sources too, since a
version pin would restore those from an index, which N9 forbids. Ruling 10, the cluster `ikill`
clean pass, is held for the diagnostic run.

**Risks:**

- **P3 is the schedule's risk.** It touches `uvm_detect`, `uvm_repair_run`, `uvm_repair`, doctor and
  the dispatch tail, and its gate is a 1-minute real-uv drive over 8 restores and the R8 tree. If it
  slips past Nov 4, the builder tells the foreman before anything is cut: cutting R5 (P4) to a
  follow-up seed is the foreman's decision (N10), not the builder's.
- **Network in the gates.** P1, P3, P4 and P5's local half need `pypi.org`,
  `files.pythonhosted.org`, `github.com`, `codeload.github.com` and `releases.astral.sh`. One
  prototype run of P3 failed once on the git tool's restore and passed on the next run: a red whose
  stderr is uv's network error is the environment, not an attempt.
- **uv's rendering and receipt format drift.** The backfill parses `uv tool list`'s bracket form and
  the copy-back test reads `install-path = "`; both measured on 0.13.6. A future uv that changes
  either makes the backfill skip (no record, 0.7.0 behaviour) or the copy-back fall back to the
  marker. Neither restores wrong.
- **The window with no record.** Between the writer's two renames a reader sees no record and treats
  the tool as unrecorded. A record is rewritten only by a `uv tool` command, which rewrites the
  tool directory itself at the same time.
- **Shared `UVM_DATA` across clusters (N5).** A record written on one cluster restores on another
  only by name; its pins may name a version with no distribution there, which fails the restore
  naming the tool. Documented in P4.
- **Only a cluster can confirm** R11: the restore holder's seconds and the waiters' wait on Lustre
  across 2 nodes, `flock` for uv's own tool lock on that mount, and the group kill under `srun`.
  The local `I` ×16 and `ikill` ×8 pass. Expected hold on Lustre: under a minute (5-22 s locally).
- **`ls -i` and inode reuse.** A filesystem that reuses a freed inode for the new receipt in the same
  instant reads one forced reinstall as unchanged; the record then keeps its old, identical content.
  The backfill covers a missing record.

**Cluster evidence (Run B, 2026-11-01).** [`evidence/lustre.txt`](evidence/lustre.txt), 2 nodes ×
64 ranks on a Lustre scratch, both jobs `exit=0` and `progress=ok`. The drive ran at `a49e6d9`; the
one later commit before this record changed only the trampoline write's failure path and the
self-heal trigger, not the restore path the drive measures.

| Scenario, pass | `UVM_LOCK_TIMEOUT` | `hold_s` | `wait_max_s` | `notice_lines` |
|---|---|---|---|---|
| `I` | 180 | 9 | 11 | 0 |
| `ikill`, killed | 60 | none (holder killed) | 61 | 127 |
| `ikill`, clean | 180 | 12 | 15 | 0 |

Both holds, five tools restored with no cache, sit inside the local 5-22 s and far from the
timeout; the killed pass's 61 s wait is its 60 s timeout, with all 127 waiters naming the lock and
its owner.

## 6. Verification strategy

Every gate is a script in [`gates/`](gates/), run from the repository root under `/bin/sh`, with
`UV_CACHE_DIR` and `UV_TOOL_DIR` exported to scratch for `lint.sh`. Each was run green against a
throwaway prototype of its phase (built cumulatively in a copy outside the working tree), and red
against its predecessor's state on its own first post-condition:

| Gate | Red before its phase | Green on the prototype |
|---|---|---|
| `p1.sh` | HEAD: `FAIL R9: the modulefile does not set UVM_DATA`; past that, `lib.sh` stops on `temp_root.sh` setting no `XDG_DATA_HOME` (P1's own item) | `P1 ok`, 24 s; again green after P2-P4 |
| `p2.sh` | after P1: `FAIL: R7: no trampoline at …/uvm/bin/fx`; HEAD: `P1 has not landed`; against P2 as first planned (no self-heal): `FAIL: self-heal: no trampoline in UVM_DATA/bin after the first uv call` | `P2 ok` after the amendment, 30 s (1200 calls: 16 s old, 11 s new) |
| `p3.sh` | after P2: `FAIL: W: rank 1 exited 127` ("'pycodestyle' is recorded but not installed") | `P3 ok`, about 1 min |
| `p4.sh` | after P3: `FAIL: R5: rank 1 exited 127` ("'pyflakes' is recorded but not installed for architecture 'uvmfake'") | `P4 ok`, about 40 s |
| `p5.sh` | before Run A: `P5 Run A has not landed`; after Run A: only `cluster evidence … not recorded yet` | local half green (F ×16, T ×8, I ×16, ikill ×8, census); evidence half green on the local summaries scaled to 128 ranks and 2 nodes, and red at `clean_restores=1` when that key is broken |

Per R-ID, the post-condition each gate asserts:

- **R1** (`p3.sh`): per shape, the three tools' sorted dist-info listings equal the pre-purge ones,
  `pyvenv.cfg` is 3.12, the receipts are byte-identical (copy-back), no `.uvm-restored`, the git
  commit equal, `diff -r` of the records empty; after a restore, `uv tool upgrade pycodestyle`
  leaves 2.11.1. `p4.sh`: the cross-key restore is reported pinned by a restore. Review cycle 1:
  a git tool from a subdirectory pins `#subdirectory=` and is restored by name from its install's
  record and from a backfilled one (C1-F4).
- **R2** (`p1.sh`): request as typed; constraints; reinstall rewrites; upgrade moves pins and keeps the
  request; VCS pin line; `upgrade --all` matches each environment; a failed install leaves the
  `cksum` listing; `SECRETMARK` absent; uninstall removes the record (`p3.sh`: and the trampoline).
  Review cycle 1: a receipt carrying an ssh URL's password is not copied, and one carrying a
  password-less ssh login is (C1-F8).
- **R3** (`p2.sh`): one repair line, `job-100.ok`, stdout exactly `fx-ran`; second call no line; rc 7;
  failed repair rc ≠ 0 and the shim never ran.
- **R4** (`p3.sh`): 16 ranks by name per shape, 3 through `uvx`: one restore announced, every rank 0
  with its tool's output; a failed restore (`UV_OFFLINE=1`) fails 4 ranks with the reason; an
  unrecorded twin in (E) fails naming `pyvenv.cfg`.
- **R5** (`p4.sh`): key B, 8 ranks, one restore, 8/8 rc 0, key B's listing equals key A's;
  `UVM_REPAIR=2 uv --version` restores nothing; a failed restore fails 4 waiters in under 30 s
  against a 60 s timeout, with a `+tool-pycodestyle.failed` record.
- **R6** (`p2.sh`): knob unset, `''`, `0` never enter a marker-leaving stand-in wrapper; 1200 calls
  cost at most `release/0.8.0`'s + 1 s; (S) with a record rc 127, the name, `UVM_REPAIR`, `uv-manager
  doctor`, no lock, no outcome; without one, 0.7.0's text.
- **R7** (`p2.sh`): the record trampoline outlives its shim through `uvm trampolines` and `uv tool
  list`, and the root's goes with it; a tool with no record has its trampoline in `$UVM_ROOT/bin`
  only; the cascade through `SCRATCH` runs the shim through either trampoline and exports both
  trees; nothing resolvable names `UVM_ROOT`; in `$UVM_ROOT/bin` a sync rewrites a 0.7.0 trampoline
  a shim names, removes one none names, and leaves an unmarked script; an unwritable `$UVM_DATA/bin`
  is left as it is; two roots sharing `UVM_DATA`: syncs, doctor and `uv tool list` on one leave the
  other's interpreter, unrecorded tool and recorded tool running; modulefile, `AGENTS.md`,
  `invariants.md`.
- **R8** (`p3.sh`): `release/0.8.0`-built tree, doctor writes three records and the trampolines,
  `UVM_ROOT` `cksum` listing unchanged, each tool in (W) restored by name; an absent recorded tool
  is a WARN naming `UVM_REPAIR`, rc 0. Review cycle 1: with `tools/.lock` gone, doctor leaves the
  `UVM_ROOT` listing unchanged, writes no record and names the tool and `uv tool list` (C1-F1); a
  `--with` direct URL is backfilled as `name @ URL` and restored (C1-F5); the receipt's indexes join
  a backfilled request, whose restore succeeds under an unreachable `UV_INDEX_URL` (C1-F6); a git
  tool whose `direct_url.json` is gone gets no record, doctor names it, and the knob-set call keeps
  0.7.0's refusal rather than restoring the moved branch head (C1-S1).
- **R9** (`p2.sh`, amended): on a tree `release/0.8.0` built, with the 0.8.x module's `PATH` and no
  `uv` call yet, 8 concurrent ranks run the tool by name through its 0.7.0 trampoline and exit 0;
  a `bash` job script runs the tool, then `uv --version` (the first call, which creates
  `$UVM_DATA/bin` and rewrites the 0.7.0 trampoline in place), then the tool again, and exits 0
  with its output twice; the modulefile prepends `$UVM_DATA/bin` after `$UVM_ROOT/bin`.
- **R9** (`p1.sh`): default chain (`UVM_DATA`, `XDG_DATA_HOME`, `HOME`); two keys, no path names a
  key, only records and trampolines; `du -sk` ≤ 24 per record; status names `UVM_DATA` and its
  origin; `uvm help`; the modulefile. The reviewer reads the modulefile.
- **R10** (`p3.sh`): `SLURM_JOB_ID=200 UVM_REPAIR=1 uvx pycowsay==0.0.0.2` on a tree with no tool:
  rc 0, `job-200.ok`, no file under its `UVM_DATA`. `p5.sh` re-runs `F` and `T` unchanged.
- **R11** (`p5.sh`): the evidence keys of 04, both scenarios, `ranks=128`, `nodes=2`.
- **R12** (`p5.sh`): `UVM_DATA` in all six files; the two dropped phrases absent; `uvm help`;
  "once after upgrading" in `README.md` and the modulefile; no README heading carrying a version;
  `### Release note` in this file naming `$UVM_DATA/bin`; `uvm_tool_entry` named in `AGENTS.md`'s
  high-risk regions. Inspection-only: each hit read against R12's list, the *Design notes* entry,
  the `UVM_DATA` section's migration text.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
