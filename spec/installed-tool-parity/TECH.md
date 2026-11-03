---
slug: installed-tool-parity
title: An installed tool run by its own name gets the repair uvx gets
kind: feature
appetite: big
status: done
branch: feature/installed-tool-parity
base: release/0.8.0
current_phase: done
last_updated: '2026-11-01'
phases:
- id: P1
  name: 'The durable tree: UVM_DATA and the records a uv tool command writes'
  status: done
  satisfies:
  - R2
  - R9
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/installed-tool-parity/gates/p1.sh
- id: P2
  name: Trampolines under UVM_DATA that enter the wrapper
  status: done
  satisfies:
  - R3
  - R6
  - R7
  - R9
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/installed-tool-parity/gates/p2.sh
- id: P3
  name: 'Restore from the record: the walk, the backfill and doctor'
  status: done
  satisfies:
  - R1
  - R4
  - R8
  - R10
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/installed-tool-parity/gates/p3.sh
- id: P4
  name: Restore by name for a tool with no trace here
  status: done
  satisfies:
  - R5
  depends_on:
  - P3
  parallel: false
  hammerable: true
  hill: uphill
  verify: sh spec/installed-tool-parity/gates/p4.sh
- id: P5
  name: Cross-node drive on Lustre and the surface census
  status: done
  satisfies:
  - R11
  - R12
  depends_on:
  - P4
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/installed-tool-parity/gates/p5.sh
review:
  last_reviewed_commit: 0883c7d
  verdict: approved
  blocked_reason: ''
  cycle: 3
---
# TECH.md — An installed tool run by its own name gets the repair `uvx` gets

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/installed-tool-parity/TECH.md`); the per-phase
checklists below are the work. `uvm-build` executes the next actionable phase, runs its `verify:`
command, updates state via `uv run .agents/factory/bin/set_phase.py …`, and makes one atomic
code-plus-state commit.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md). R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md). Base is `release/0.8.0`, wherever a skill says `main`.
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs 01-04.

## Frontmatter field reference

See [`templates/TECH.md`](../../.agents/factory/templates/TECH.md). Every phase is `parallel: false`
(one source file). Every phase but P4 is `hammerable: false`; P4 carries R5 alone, the one criterion
N10 lets move to a follow-up seed. If P4 is hammered, R5's second clause (the walk restores no tool
without a trace) stays, because P3's gate asserts it.

## Gate notes (read before retuning any gate)

Each `verify:` runs one script in [`gates/`](gates/) from the repository root under `/bin/sh`. The
scripts share [`gates/lib.sh`](gates/lib.sh): `run`, `fail`, `seed KEY` (a real uv under a platform
key), `frozen TOOL [KEY]`, `envpins TOOL [KEY]`, `datalist`. Every gate was run green against a
throwaway prototype and red against its predecessor's state (PLAN §6). A retune keeps these:

- **`lint.sh` needs scratch caches**: export `UV_CACHE_DIR` and `UV_TOOL_DIR` to a scratch directory
  before any gate.
- **Real uv comes from `command -v uv`** outside `temp_root.sh`, passed in as `SEED_UV` (the scrub
  removes only `UV_*` and `UVM_*`) and copied into `versions/<ver>/` by `seed`. This is a harness
  step, never product code. A gate refuses a `uv` that is this checkout's own `bin/uv`.
- **The real-uv gates need network**: P1, P3, P4 and P5's local half reach `pypi.org`,
  `files.pythonhosted.org`, `github.com`, `codeload.github.com` and `releases.astral.sh` (P2 is
  offline). A red whose stderr is uv's own network error, a restore of `progressbar` failing to
  fetch included, is the environment, not the code: do not `--record-attempt` it; re-run.
- **`XDG_DATA_HOME` comes from `temp_root.sh`** (P1's first item). `lib.sh` stops with
  `XDG_DATA_HOME: temp_root.sh sets XDG_DATA_HOME` until it does.
- **No `VAR=x` in front of a shell function.** POSIX `sh` keeps the assignment. Gates use `env` on
  commands and a subshell, `(UVM_ROOT=…; seed …)`, around functions.
- **No `rm` inside a drive**; damage is `mv` into `$trash` or `find … -type f -delete` (the purge's
  own shape, which keeps directories and links). Each drive works in its own fresh roots.
- **No bare `wait`**; wait on the named pids.
- **The unpinned tool is built without `--force`.** `uv tool install --force pycodestyle --with six`
  rebuilds at the newest release; the state the gates need is the pinned install followed by the
  unpinned one, as `tests/repair-race.sh`'s `T` builds it.
- **No message on the `uv`, `uvx` or trampoline path names `pip install`, `python install` or
  `tool upgrade`**: the offline fixture echoes those lines and P2 counts them as repairs. The
  restore's note says "restoring the installed tool(s) … from their records".
- **Sort under `LC_ALL=C`** wherever a listing is compared.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md). Consult [`invariants.md`](../../.agents/factory/invariants.md)
  §1, §2, §3, §5, §7, §8, §9, §10, §11 for this change.
- One phase per `uvm-build` invocation; one atomic commit with **both** the code and the `TECH.md`
  state change. Subjects follow `[feature] Build installed-tool-parity P<n>: …`.
- Keep the `Co-Authored-By` trailer.
- A behavior change updates the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example` and
  `share/modulefiles/uv/main.lua` (whichever it invalidates) **in the same commit**. PLAN §2's
  *User-facing surface* table says which phase owns which sentence. A phase that lands a §1, §8 or
  §9 change updates `AGENTS.md` § *Invariants* and `.agents/factory/invariants.md` in that commit.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager` or `README.md`.
- **No step and no subagent uses any cluster tool**, meaning any tool of a cluster MCP server.
  The only approved remote class is the foreman's test jobs, which the foreman submits. Put this
  line in any sub-brief a phase writes.
- The repository is public: no cluster names or specifics, no local paths, in any file or commit.

---

## Phase P1 — The durable tree: `UVM_DATA` and the records a `uv tool` command writes
**Satisfies:** R2, R9 · **Depends on:** —
**Goal:** every `uv tool install`, `upgrade` and `uninstall` that exits 0 through the wrapper writes,
rewrites or deletes a plain-file record under `UVM_DATA`, credentials stripped, staged and renamed;
`UVM_DATA` resolves from `UVM_DATA`, `XDG_DATA_HOME`, `HOME`, and `uvm status` names it.

- [x] `.agents/factory/bin/temp_root.sh`: set and export `XDG_DATA_HOME="$sandbox/data"` beside
  `XDG_CONFIG_HOME`, with a comment saying why (PLAN deviation 2; the gate ruled it lands here, in
  P1's commit).
- [x] `uvm_init`: `uvm_data`, `uvm_data_origin`, `uvm_records` (PLAN §2). Builtins only; empty when
  nothing resolves, and nothing on the hot path fails for it.
- [x] Records: `uvm_strip_userinfo`, `uvm_record_constraints`, `uvm_record_write`, `uvm_tool_marks`,
  `uvm_records_update` (PLAN §2, research 02). `uvm_record_write` returns 0 on every path.
- [x] Dispatch tail, `tool`/`python` branch: `uvm_tool_marks` before `uv tool
  install|upgrade|uninstall`; `uvm_records_update … || true` on `rc == 0` for `tool`; `exit "${rc}"`
  unchanged.
- [x] `uvm_status`: the `UVM_DATA:` line with its origin. `uvm_help`: `UVM_DATA` under *Environment*.
- [x] `share/modulefiles/uv/main.lua`: `setenv("UVM_DATA", …)` from `XDG_DATA_HOME`, else `HOME`,
  plus `/.local/share`, plus `/uvm`, with a comment; its design note lists `UVM_DATA` as neutral.
  (`PATH` changes in P2.)
- [x] `README.md`: line 4's quota sentence and the `:302` status comment say what lives under home;
  the *Reference* table's `UVM_DATA` row; the state-tree diagram shows `$UVM_DATA/tools/`.
- [x] `etc/uv-manager.conf.example`: `UVM_DATA`, commented, with its default and what it holds.
- [x] `AGENTS.md` § *Invariants* and `invariants.md` §8: the wrapper writes records under
  `UVM_DATA` and nothing else there yet.
- **Review cycle 1 (2026-11-01), reopened for C1-F8** ([`REVIEW.md`](REVIEW.md), ruling 7):
  - [x] `uvm_carries_userinfo`: the receipt copy is skipped when any URL in it carries userinfo
    under any scheme, except the password-less ssh login `uvm_strip_userinfo` keeps.
  - [x] `p1.sh`: a receipt planted with an ssh URL's password is not copied by a backfill; one with
    a password-less ssh login is. Red at `8504ac4`.
- **Review cycle 2 (2026-11-01), reopened for C2-P1** ([`REVIEW.md`](REVIEW.md), ruling 6):
  - [x] A record's stage, and the name an uninstall moves a record aside to, carry the host, the
    pid and a `$RANDOM`, as a trampoline's temporary name does (P2): holders on two nodes can
    share a pid in a shared `UVM_DATA`. No fork. `p1.sh` is unchanged and green.
- **Verify:** `sh spec/installed-tool-parity/gates/p1.sh` (real uv, network). Asserts R2's request,
  constraints, python, entrypoints and receipt copy; reinstall, upgrade, `upgrade --all`; the VCS
  pin; a failed install leaves the `cksum` listing; no `SECRETMARK`; uninstall deletes; R9's default
  chain, two keys, no key in a path, only records (or trampolines), `du -sk` ≤ 24, status, help,
  the modulefile. The README and conf text are inspection-only at review.
- **Touches:** `bin/uv-manager`, `.agents/factory/bin/temp_root.sh`, `README.md`,
  `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`, `AGENTS.md`,
  `.agents/factory/invariants.md`.

## Phase P2 — Trampolines under `UVM_DATA` that enter the wrapper
**Satisfies:** R3, R6, R7, R9 (the migration path, as amended) · **Depends on:** P1
**Goal:** the recorded tools' trampolines live in `$UVM_DATA/bin`, and each root's shim-derived ones
in its `$UVM_ROOT/bin` (GOAL A2); knob off they exec the shim and nothing else, knob on they run the
scope check through `uv-manager _trampoline`; a missing shim exits 127 saying why. An existing
user's tools keep running across the upgrade: the module keeps `$UVM_ROOT/bin` after
`$UVM_DATA/bin`, and the first `uv` call writes the record trampolines and rewrites each 0.7.0
trampoline in place (GOAL N6 and A2, amended).

- [x] `uvm_init`: `uvm_neutral_bin="${uvm_data}/bin"` (empty with `uvm_data`), `uvm_legacy_bin`.
- [x] `uvm_export_env`: export `UVM_ROOT=${uvm_base}` and `UVM_DATA`; prepend `${uvm_neutral_bin}`
  when set; the guard covers five directories. Comment why each export is neutral.
- [x] `uvm_trampolines [migrate]`: research 03's body; names from shims and records; removal only
  when neither names; `migrate`, after generating, removes a marked file in `${uvm_legacy_bin}` only
  when its replacement in `$UVM_DATA/bin` carries the marker or nothing names it, and nothing else;
  the baked wrapper path; `umask 077`. Update the banner comment and the platform-key banner (the
  expression is still written twice).
- [x] `uvm_tool_entry`, `uvm_tool_missing`; `_trampoline` in `uvm_manager_main` beside `help`,
  before `uvm_init`. The knob-on path runs `uvm_ensure_uv`, `uvm_export_env`, `uvm_repair`; every
  exec releases first.
- [x] Callers: the `tool`/`python` intercept, `uvm trampolines` and `uvm install` pass `migrate`.
- [x] The self-heal in the dispatch tail, right after `uvm_export_env`: `uvm_trampolines migrate`
  once when `${uvm_neutral_bin}` is set and absent (PLAN §2; one `[[ -d ]]`, 5.2 µs measured). A
  comment says why it is there and what it costs.
- [x] `share/modulefiles/uv/main.lua`: keep `prepend_path("PATH", pathJoin(root, "bin"))` and add
  the `$UVM_DATA/bin` prepend after it, outside the `scratch` guard, so `$UVM_DATA/bin` is first;
  the design note says `$UVM_ROOT/bin` is the 0.8.x migration path a later release removes; the
  help text says to run `uv-manager doctor` once after upgrading.
- [x] `README.md`: *Reach* (both routes, one contract; the trampoline enters the wrapper with the
  knob set; drop "use `uvx <tool>` in the job script"); *What the wrapper does* item 6 and the
  tree; *Design notes* "Architecture-neutral trampolines"; the `UVM_DATA` section's migration
  facts (0.7.0 trampolines served from `$UVM_ROOT/bin` until replaced, the first `uv` call
  generates the new ones, run `uv-manager doctor` once after upgrading, a hand-made `PATH` entry
  moves); the troubleshooting entry for "is not installed for architecture". No section titled by a
  version. The release-note text stays in `PLAN.md` § *Release note*.
- [x] `uvm_help`: the `trampolines` line names `UVM_DATA/bin`.
- [x] `AGENTS.md` § *Invariants* and `invariants.md`: §1 (the `PATH` entries, `$UVM_ROOT/bin` after
  `$UVM_DATA/bin` through 0.8.x), §8 (the exports, the five-way guard, the self-heal's one stat),
  §9 (`$UVM_DATA/bin`, generated from records and shims, removal rule, the migration rule).
- **Review cycle 1 (2026-11-01), reopened for A2** ([`REVIEW.md`](REVIEW.md), rulings 1, 6 and 9;
  C1-F2, C1-F3, C1-F7, C1-S2). The items above that name `migrate`, retirement, or shims as a
  source for `$UVM_DATA/bin` are superseded by these:
  - [x] `uvm_trampolines [records]` over `uvm_trampoline_dir DIR NAMES WRAPPER`: `$UVM_DATA/bin` from
    the records alone, a marked file removed only when no record names it; `$UVM_ROOT/bin`
    (`uvm_root_bin`, was `uvm_legacy_bin`) from this root's shims under 0.7.0's rule, so a 0.7.0
    trampoline a shim names is rewritten in place and no other root is touched; `records` skips
    the second directory. The guard tests `-d` and `-w`, and a directory that fails it is left as
    it is. The `migrate` argument and the retirement go.
  - [x] `uvm_export_trees`: `uvm_export_env`'s exports without its `mkdir -p` guard;
    `uvm_tool_entry` execs through it, so the knob-off entry creates nothing (C1-F7).
  - [x] Callers: the `uv tool`/`uv python` intercept, `uvm trampolines`, `uvm install` and the
    self-heal sync both directories; doctor passes `records`. `uvm status` names both directories;
    `uvm help`'s `trampolines` line names both.
  - [x] Surfaces in lockstep: `README.md` (the tree, the `UVM_DATA` section's 0.7.0 account, item 6,
    the modulefile excerpt and its note, *Design notes* on why there are two directories, the
    reference row), the modulefile's header, comments and help, the conf example, `AGENTS.md` and
    `invariants.md` §1, §8 and §9. `PLAN.md`'s *Release note* is amended with GOAL A2.
  - [x] `p2.sh`, retuned to A2 and extended: a tool with no record has its trampoline in
    `$UVM_ROOT/bin` only; the 0.7.0 trampoline is rewritten in place and a `bash` job script that
    ran it before the first `uv` call runs it after (C1-F2); in `$UVM_ROOT/bin` a sync rewrites a
    0.7.0 trampoline a shim names, removes one none names, leaves an unmarked script; the knob-off
    entry through the cascade creates no missing directory (C1-F7); an unwritable `$UVM_DATA/bin`
    is left as it is while the root's still syncs (C1-S2); two roots sharing `UVM_DATA` keep each
    other's interpreter, unrecorded tool and recorded tool running through a sync, doctor and `uv
    tool list` (C1-F3). Red at `8504ac4`.
- **Review cycle 2 (2026-11-01), reopened** ([`REVIEW.md`](REVIEW.md), rulings 2, 5 and 6; C2-F2,
  C2-F4, C2-F6, C2-P1):
  - [x] The self-heal's trigger is per root: `$UVM_ROOT/bin/.uv-manager-synced`
    (`uvm_heal_marker`), written by `uvm_trampolines` after a sync of `$UVM_ROOT/bin` and by
    nothing else, so doctor (`records`) neither sets nor clears it and another root sharing
    `UVM_DATA` cannot stand in for it. The dispatch tail syncs when it is missing and the root's
    directory is writable or creatable; an unwritable `UVM_DATA` costs one attempt; the hot path
    is one `[[ -e ]]` (C2-F2, C2-F4).
  - [x] `uvm_trampoline_dir` adds each directory it wrote to `uvm_synced`, and `uvm trampolines`
    reports only those and names any it left (`uvm_trampolines_report`, C2-F6).
  - [x] A trampoline's temporary name is `.<name>.<host>.<pid>.<random>`. The ruling named
    `$HOSTNAME`; the wrapper already records that bash keeps an inherited `HOSTNAME` (a login
    node's, under `sbatch --export=ALL`), which on every compute node of a job is the same, so
    `$RANDOM` goes in beside it. Neither forks (C2-P1).
  - [x] Surfaces: `README.md` item 2's upgrade account and *Design notes*; `AGENTS.md`;
    `invariants.md` §8 and §9; the modulefile's comment on `$UVM_ROOT/bin`.
  - [x] `p2.sh`: doctor first, and another root sharing `UVM_DATA` first, each leave this root's
    0.7.0 trampoline for its first `uv` call to rewrite, and a knob-set call by name records the
    scope; an unwritable `UVM_DATA` leaves the root's trampoline untouched by a second call; the
    marker is written; `uvm trampolines` beside an unwritable `$UVM_DATA/bin` does not report it
    synced and names it; the temporary name carries the host. Red at `1a0d680`.
- **Verify:** `sh spec/installed-tool-parity/gates/p2.sh` (offline). Asserts R3 (one repair line,
  `job-100.ok`, exact stdout, a second call silent, rc 7 kept, a failed repair runs nothing), R6
  (unset, `''`, `0` never enter a stand-in wrapper; 1200 calls no slower than `release/0.8.0`'s
  trampoline + 1 s; (S) with a record: 127, the name, `UVM_REPAIR`, `uv-manager doctor`, no lock,
  no outcome; without: 0.7.0's text), R7 (record outlives shim through a sync and `uv tool list`;
  the cascade through `SCRATCH`; the failure names `UVM_ROOT`; migration), R9's upgrade path (a
  `release/0.8.0` tree, the 0.8.x `PATH`, no `uv` call: 8 ranks by name all exit 0; the first `uv`
  call generates `$UVM_DATA/bin/<tool>` and removes the 0.7.0 one; the tool runs through the new
  one), the modulefile's prepend order, `AGENTS.md` and `invariants.md` naming `UVM_DATA/bin`, the
  *Reach* sentence gone.
- **Touches:** `bin/uv-manager`, `README.md`, `share/modulefiles/uv/main.lua`, `AGENTS.md`,
  `.agents/factory/invariants.md`, and `etc/uv-manager.conf.example` (its `UVM_DATA` paragraph now
  says the trampolines live in its `bin/`; same-commit rule).

## Phase P3 — Restore from the record: the walk, the backfill and doctor
**Satisfies:** R1, R4, R8, R10 · **Depends on:** P2
**Goal:** a knob-set call by name or through `uv`/`uvx`, in a scope with no outcome, restores every
recorded tool with a trace in shapes W, E, R, S, G from its record under the repair lock, leaves
nothing held, and runs; doctor backfills records and writes nothing under `UVM_ROOT`.

- [x] `uvm_recorded`, `uvm_restoring`, `uvm_detect_records`; `uvm_detect` calls it first and its
  passes skip tools being restored; the interpreter probe gets `PYTHONDONTWRITEBYTECODE=1`.
- [x] `uvm_restore` (research 01 D1-D3): the local-source refusal, the request rewrite (`--force`,
  `@latest`), `UV_PYTHON` and `UV_NO_CACHE=1`, from `/` in a subshell to stderr, the copy-back test,
  the `.uvm-restored` marker, the failure reason. Never writes the record.
- [x] `uvm_backfill` (research 02): `uv tool list` from `/` with `UV_NO_CACHE=1`, only when a record is
  missing; never rewrites one.
- [x] `uvm_repair_run`: the restore arm after the interpreter arm, one note; the in-place arm skips
  restored tools and restores a recorded tool it would refuse. `uvm_repair`: the holder backfills
  before the walk. Comments say why the in-place arm stays first choice (the receipt stays
  byte-identical).
- [x] Dispatch tail: `uvm_backfill || true` after `uvm_records_update` on `rc == 0` for `tool`.
- [x] `uvm_doctor`: backfill and a sync without `migrate` first; the absent-tool and pinned-by-restore
  advisories; a replay line per restorable tool in the remediation block; the value-outcome loop
  skips `+tool-` names (P4 writes them; harmless before).
- [x] `README.md` *Repairing inside a job*: the restore (what a record restores, shapes, the copy-back
  and its fallback, `uv tool install --force <request>` as the remedy for a hold, sources: index,
  VCS, URL archive restored, local refused, N5's shared `UVM_DATA`); *Three tool states fail the
  scope by design* now says "a tool with no record"; mitigation 4 reworded; *What it catches*;
  *Design notes*: why what the user asked for lives outside the scratch tree (R12).
- [x] `etc/uv-manager.conf.example` and the modulefile's help: the knob restores installed tools too.
- [x] `AGENTS.md` § *Invariants* and `invariants.md` §8: the restore beside the repair (replays a
  record, keeps resolution by pins, the one receipt written is uv's own copied back), doctor's
  probe writes no bytecode, doctor writes nothing under `UVM_ROOT`.
- **Amended in the build (2026-11-01).** Three departures from PLAN §2, none touching GOAL:
  doctor's remediation block names a knob-set call (`UVM_REPAIR="restore-$(date +%s)" uv
  --version`) under one comment line per restorable tool, not a hand-typed replay, because a
  replay typed through the wrapper records its `-c <file>` as the request, which the restore then
  refuses as a local-file option, and leaves the receipt pinned; the absent-tool advisory names
  `uv tool uninstall` "where it is installed", since on a key without the tool it exits non-zero
  and drops nothing; and the in-place arm's four refusals moved into `uvm_tool_refusal`, which the
  restore arm reads to take over a recorded tool the in-place arm would refuse, so one predicate
  serves both arms and one note announces every restore. The request scan is its own helper,
  `uvm_restore_request`, shared by the restore and doctor. The backfill runs after every `uv
  tool` command that exits 0 (N7's "every `uv tool` command"), not only the three that write
  records.
- **Review cycle 1 (2026-11-01), reopened** ([`REVIEW.md`](REVIEW.md), rulings 2-5 and 8; C1-F1,
  C1-F4, C1-F5, C1-F6, C1-S1):
  - [x] Doctor runs `uvm_backfill` only where `${UV_TOOL_DIR}/.lock` exists, and reports each tool
    with a receipt, `pyvenv.cfg` and no record as an advisory: `uv tool list` writes its record, or,
    for a tool `uvm_unpinnable` refuses, install it again from its source (C1-F1, C1-S1).
  - [x] `uvm_record_constraints` carries `"subdirectory"` from `direct_url.json` as
    `#subdirectory=` on a VCS or URL constraint (C1-F4).
  - [x] `uvm_backfill`: joins a `uv tool list` line whose bracket is still open to the next (uv
    renders a VCS requirement with a subdirectory across two lines); records a `--with` rendered as
    a name and a URL as `name @ URL` (C1-F5); adds the receipt's `[tool.options]` `index-url` and
    `extra-index-url`, where they are one-line strings, through `uvm_receipt_indexes` (C1-F6);
    skips a tool `uvm_unpinnable` refuses, one whose receipt counts more git, URL or local
    requirements (`uvm_tool_receipt`'s new `uvm_receipt_sources`) than its environment has
    `direct_url.json` files (C1-S1).
  - [x] `README.md`: doctor's lock-file case, what a backfilled record carries and replays under the
    current configuration (ruling 5), the unpinnable tool, and a troubleshooting entry for doctor's
    "has no record"; `AGENTS.md` and `invariants.md` §8 likewise.
  - [x] `p3.sh`: the subdirectory tool, restored by name from its install's record and from a
    backfilled one; a backfilled `--with` direct URL; a backfilled index restored under an
    unreachable `UV_INDEX_URL`; doctor with `tools/.lock` gone leaves `UVM_ROOT` unchanged and names
    the tool; an unpinnable git tool gets no record, doctor names it, and the knob-set call keeps
    0.7.0's refusal. Red at `8504ac4`.
  - **Built (2026-11-01).** Two details the rulings left open. `uv tool list` renders a VCS
    requirement with a subdirectory with a newline before its closing bracket, so before this the
    backfill recorded such a tool by name alone; the join fixes that beside C1-F4. Ruling 8 names
    git and URL sources; `uvm_unpinnable` also refuses a local source whose `direct_url.json` is
    gone, since a version pin would restore it from an index, which N9 forbids.
- **Review cycle 2 (2026-11-01), reopened** ([`REVIEW.md`](REVIEW.md), rulings 1, 3, 4 and 7; C2-F1,
  C2-F3, C2-F5, cycle 1's ruling 10):
  - [x] A record and its `$UVM_DATA/bin` trampolines are one step wherever a record is written.
    The intercept and doctor already synced after their backfill; the repair's holder now runs
    `uvm_trampolines records` right after its backfill, once per scope whether or not it wrote,
    and the restore by name runs it after its restore (C2-F1).
  - [x] `uvm_unpinnable` checks per requirement: `uvm_tool_receipt` keeps each source
    requirement's name (`uvm_receipt_reqs`, `uvm_receipt_reqs_from`), and each must have a
    `direct_url.json` in its own dist-info directory, names compared case aside with `-` and `.`
    as `_` under `nocasematch`, restored after. An entry with no name refuses (C2-F3).
  - [x] `uvm_receipt_indexes` carries a one-line `index = [ … ]` as `--index URL`, or
    `--default-index URL` for `default = true`, when every table holds only `url`, `name`,
    `default` and uv's defaults for `explicit`, `format` and `authenticate`, the array whole or not
    at all; and `index-strategy` as `--index-strategy` (C2-F5).
  - [x] `README.md`: the backfill carries the index tables and strategy and checks each source
    requirement's own `direct_url.json`; the measured per-tool restore cost on a parallel
    filesystem and the advice to raise `UVM_LOCK_TIMEOUT` for a job that runs many recorded tools,
    in the restore paragraph and the repair lock's troubleshooting entry (ruling 7); the conf
    example's `UVM_LOCK_TIMEOUT` paragraph likewise; `AGENTS.md` and `invariants.md` §8.
  - [x] `p3.sh`: a jobs-only user on a `release/0.8.0` tree gets the record and its trampoline
    from the walk's holder, and after a purge takes the tool and its 0.7.0 trampoline the tool runs
    by name; a backfilled request carries `--default-index`, `--index` and `--index-strategy`, and
    restores under an unreachable `UV_DEFAULT_INDEX`; a git tool whose own `direct_url.json` is gone
    gets no record though its git dependency kept one. Red at `1a0d680`, each clause shown by a
    variant with the earlier new clauses removed.
- **Verify:** `sh spec/installed-tool-parity/gates/p3.sh` (real uv, network, about 1 min). Asserts,
  per shape W, E, R, S over the pinned tool, the unpinned tool and the git tool (shape G is the git
  tool in E): 16 ranks by name and 3 through `uvx`, one restore, every rank 0 with its output, and
  R1's equalities (listing, minor, receipt copied back, no marker, commit, `diff -r` of records);
  `uv tool upgrade` moves the restored unpinned tool; `UV_OFFLINE=1` fails 4 ranks with the reason;
  an unrecorded twin in (E) fails naming `pyvenv.cfg`; a `--with-requirements` tool is refused by
  name; uninstall removes record and trampoline; R10's `uvx`; R8 on a `release/0.8.0`-built tree.
  The README prose is inspection-only.
- **Touches:** `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`,
  `share/modulefiles/uv/main.lua`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P4 — Restore by name for a tool with no trace here
**Satisfies:** R5 · **Depends on:** P3 · **Hammerable** (N10). The cut is the foreman's: if P3
slips past Nov 4, the builder reports it before cutting anything.
**Goal:** a knob-set call by name whose shim is still missing after the scope check restores that
tool alone under the repair lock; waiters wait; a failure fails them promptly with its reason.

- [x] `uvm_ondemand_done`, `uvm_restore_by_name` (PLAN §2): the record by entrypoint; the failed
  record `<scope>+tool-<encoded>.failed` (temp name and `mv`), its length bound; the lock with the
  arrival test, the predicate and the re-check; no record on success; "restored and provides no
  <name>" as a failure. `uvm_tool_entry` calls it under the knob when the shim is missing.
- [x] Doctor: failed `+tool-` records under a value get their own WARN line with the reason; under a
  job they are counted with the others and never opened (§5's doctor bullet).
- [x] `README.md`: the restore by name; a tool installed on another architecture or cluster sharing
  `UVM_DATA` (N5), and why it comes back pinned there, with `uv tool install --force <request>` as
  the remedy and doctor's line. `uvm_help`'s `UVM_REPAIR` text if it names what the knob restores.
- [x] `AGENTS.md` and `invariants.md` §5: the third caller of the repair lock and its predicate.
- **Built (2026-11-01).** No departure from PLAN §2. Details the plan left open: the failed
  record's name is bounded at 240 bytes, room for the temporary name's `.<pid>` under NAME_MAX;
  `uvm_repair` leaves its scope phrase in `uvm_repair_scope`, so a waiter's message names the
  scope ("cannot run <name> for Slurm job N: <reason>"); doctor's job count takes `+tool-`
  records with the rest, since its glob already matched them; doctor's "pinned by a restore"
  advisory landed in P3 and is what the cross-key restore reaches. The conf example and the
  modulefile's help already say the knob restores installed tools and claim nothing this changes,
  so they are untouched; `AGENTS.md`'s execution-model diagram names the restore by name.
- **Verify:** `sh spec/installed-tool-parity/gates/p4.sh` (real uv, network). Asserts key B: 8 ranks
  by name, one restore, 8/8 rc 0, listing equal to key A's, pycodestyle not restored; `UVM_REPAIR=2
  uv --version` restores nothing; doctor reports pyflakes pinned by a restore and pycodestyle absent;
  `UV_OFFLINE=1` fails 4 waiters with the reason in under 30 s against a 60 s timeout, with the
  `+tool-pycodestyle.failed` record.
- **Touches:** `bin/uv-manager`, `README.md`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P5 — Cross-node drive on Lustre and the surface census
**Satisfies:** R11, R12 · **Depends on:** P4
**Goal:** R11's evidence from `tests/repair-race.sh` scenarios `I` and `ikill` at 2 nodes × 64
ranks, and R12's census across every surface.
**This phase has an external wait, so it is two runs.**

**Run A — build, check locally, hand back:**
- [x] `tests/repair-race.sh`: scenarios `I` and `ikill` as research 04 specifies (preparation through
  the wrapper, `UVM_DATA` and its `bin` on `PATH` in the job role, the five shapes, ranks by name
  resolving to their trampolines, the summary keys, the checks). `F`, `T`, `P`, `kill` unchanged.
  The header documents both scenarios and every new key.
- [x] `AGENTS.md`'s `tests/` paragraph: the installed-tool scenarios, one sentence.
- [x] Census: propose `uvm_tool_entry` for `AGENTS.md`'s high-risk regions (an `exec` site that runs
  the repair), with `uvm_restore`'s note that it reads its recorded request for only three token
  classes (`--force`, `@latest`, the local-file options); `invariants.md`'s list moves with it.
- [x] R12 sweep: read every surface against R12's list and fix what P1-P4 left.
- [x] Run the gate. It is expected red **only** at `cluster evidence … not recorded yet`, and every
  check above that line must pass. **This red is the external wait, not a failed attempt: do not
  `--record-attempt` for it.** Commit Run A as `[feature] Build installed-tool-parity P5: Run A — …`,
  the phase left `in_progress`, and stop.
- [x] Hand back to the foreman: the commit, the local `I` and `ikill` summaries, and the two job
  bodies below.
  - The bodies are generic. Their `#SBATCH` lines size the job only; the foreman adds account,
    partition and QoS, which are never committed.
  - Both fit the approved test-job class: at most 30 min wall and 16 GB per node.
  - The foreman stages this commit's tree on a filesystem every node mounts (at least `bin/` with
    its symlinks, `tests/`, `.agents/factory/bin/temp_root.sh` and `.agents/factory/fixtures/`),
    checks the staged blobs against `git ls-tree -r`, then passes `REPAIRRACE_REPO` and, per job,
    its own empty `REPAIRRACE_RUN_DIR` on Lustre. The drive's `UVM_ROOT` and `UVM_DATA` both land
    under that run directory.
  - Both jobs may be queued together.

  **Job 1, scenario I:**
  ```bash
  #!/bin/bash
  #SBATCH --nodes=2
  #SBATCH --ntasks=128
  #SBATCH --ntasks-per-node=64
  #SBATCH --mem=16G
  #SBATCH --time=00:30:00
  # REPAIRRACE_REPO     the staged tree of the commit under test, on a filesystem every node mounts
  # REPAIRRACE_RUN_DIR  an empty directory on the filesystem under test; the job writes only beneath it
  set -u
  : "${REPAIRRACE_REPO:?set REPAIRRACE_REPO to the staged tree}"
  : "${REPAIRRACE_RUN_DIR:?set REPAIRRACE_RUN_DIR to a directory on the filesystem under test}"
  n="${SLURM_NTASKS:?run inside a Slurm allocation}"
  REPAIRRACE_SHARED="$REPAIRRACE_RUN_DIR/shared"
  export REPAIRRACE_SHARED
  mkdir -p "$REPAIRRACE_SHARED" && cd "$REPAIRRACE_RUN_DIR" || exit 1
  "$REPAIRRACE_REPO/tests/repair-race.sh" --launch srun --ranks "$n" --scenario I \
      --summary "$REPAIRRACE_RUN_DIR/summary.txt"
  echo "exit=$?" >> "$REPAIRRACE_RUN_DIR/summary.txt"
  ```

  **Job 2, scenario ikill:**
  ```bash
  #!/bin/bash
  #SBATCH --nodes=2
  #SBATCH --ntasks=128
  #SBATCH --ntasks-per-node=64
  #SBATCH --mem=16G
  #SBATCH --time=00:30:00
  # REPAIRRACE_REPO     the staged tree of the commit under test, on a filesystem every node mounts
  # REPAIRRACE_RUN_DIR  an empty directory on the filesystem under test; the job writes only beneath it
  set -u
  : "${REPAIRRACE_REPO:?set REPAIRRACE_REPO to the staged tree}"
  : "${REPAIRRACE_RUN_DIR:?set REPAIRRACE_RUN_DIR to a directory on the filesystem under test}"
  n="${SLURM_NTASKS:?run inside a Slurm allocation}"
  REPAIRRACE_SHARED="$REPAIRRACE_RUN_DIR/shared"
  export REPAIRRACE_SHARED
  mkdir -p "$REPAIRRACE_SHARED" && cd "$REPAIRRACE_RUN_DIR" || exit 1
  "$REPAIRRACE_REPO/tests/repair-race.sh" --launch srun --ranks "$n" --scenario ikill --timeout 60 \
      --summary "$REPAIRRACE_RUN_DIR/summary.txt"
  echo "exit=$?" >> "$REPAIRRACE_RUN_DIR/summary.txt"
  ```
  - **Expected runtime:** each job under 6 min. Preparation is about a minute (uv through the
    installer, cpython 3.12, five tools, one from git). Job 1's hold restores five tools with
    `--no-cache` while 127 ranks wait: 5-22 s locally, allow a minute. Job 2's killed pass runs out
    the 60 s timeout, then doctor, `uvm clean lock --yes` and a clean pass of one restore.
  - **Memory:** 64 ranks per node, each a `sh` trampoline become the bash wrapper, then a Python 3.12
    `--version`: 2-4 GB per node, inside 16 GB.
  - **Egress and `git`** from compute nodes: `astral.sh`, `releases.astral.sh`, `pypi.org`,
    `files.pythonhosted.org`, `github.com` (and its object host for interpreter downloads). The
    foreman confirmed both for the target cluster.
  - **Evidence:** job 1's `summary.txt` followed by job 2's, unedited:
    `cat <job1>/summary.txt <job2>/summary.txt > spec/installed-tool-parity/evidence/lustre.txt`.
  - **The foreman pushes the branch and submits both jobs.**

- **Built, Run A (2026-11-01).** One departure from research 04, none from GOAL: under `ikill` the
  clean pass keeps the wrapper's default `UVM_LOCK_TIMEOUT` of 180 s (`clean_timeout=180` in the
  summary), and `--timeout` governs the killed pass alone. With one timeout for both passes, as
  `kill` has, a gate run's clean holder took 24 s to restore the five tools with no cache, past
  the 20 s default, and all 7 waiters timed out on a restore that succeeded; research 04 had
  measured that hold at 5-22 s. The clean pass's subject is one restore and every rank exiting 0,
  not the timeout. `kill` is unchanged. Doctor, from P4's notes: the line counting failed outcomes
  under Slurm jobs now counts failed repairs and failed restores by name separately, by name alone
  so nothing is opened; the `+tool-` line under a value says that every command the tool provides
  fails, and that `uvm clean outcomes --yes` removes every outcome. R12 sweep: the README's two
  route sentences, the `uvm_help` `UVM_REPAIR` text and the modulefile's help now present a tool
  run by its own name beside `uv`/`uvx` under one contract, and the modulefile's help says what
  `UVM_DATA` keeps, its default and its size; `AGENTS.md` and `invariants.md` §9 name the restore by
  name between the scope check and the 127. Left for review, as outside R12's letter: the README's
  "leave it unset on storage that is not purged" (also in the conf example) beside the restore by
  name across architectures, the git host missing from the conf and modulefile network lists, and
  the status sample lacking its `UVM_DATA:` line.

- **Review cycle 1 (2026-11-01).** GOAL R11 drops its second-filesystem clause (A2, ruling 9); the
  job bodies above already keep `UVM_DATA` under the run directory, so they are unchanged. Ruling
  10, the `ikill` clean pass that held the lock past the timeout on the cluster, is held until the
  diagnostic run reports: the drive's clean pass and the restore stay as they are.
- **Review cycle 2 (2026-11-01).** Ruling 7 closes cycle 1's ruling 10: the diagnostic rerun was
  green, and the 209 s hold is read as variance in a five-tool uncached restore. The drive keeps its
  clean timeout; the README states the per-tool restore cost and when to raise `UVM_LOCK_TIMEOUT`
  (P3).

**Run B — read the evidence, close the phase:**
- [x] Copy the evidence to `spec/installed-tool-parity/evidence/lustre.txt`, unedited: job 1's
  summary, then job 2's. If it contains anything identifying, stop and ask the foreman. Do not scrub
  by hand.
- [x] Run the gate. A scenario can fail for an infrastructure reason (egress lost since the probe,
  `REPAIRRACE_SHARED` not shared, `srun` refused, `progress` not ok). Record that in the commit body
  and escalate to the foreman; do not close the phase on it.
- [x] Record in `PLAN.md` §5 the measured `hold_s`, `wait_max_s` and `notice_lines` for both
  scenarios. A hold near `UVM_LOCK_TIMEOUT` is a finding, not a reason for a knob.
- [x] Re-run P1-P4's gates. Mark the phase `done` with `--top-status in_review` and commit as
  `[feature] Build installed-tool-parity P5: Run B — …`.
- **Built, Run B (2026-11-01).** The two job summaries, hash-checked against the foreman's
  downloads, are `evidence/lustre.txt` unedited; nothing identifying was in them. The drive ran at
  `a49e6d9`. Review cycle 3's two fixes landed after it and touch only the trampoline write's
  failure path and the self-heal trigger, so the foreman accepts that evidence for R11. Measured
  holds and waits are in `PLAN.md` §5.
- **Verify:** `sh spec/installed-tool-parity/gates/p5.sh`. Local half: `--launch srun` without
  `REPAIRRACE_SHARED` exits 2; `F` ×16 and `T` ×8 unchanged; `I` ×16 and `ikill` ×8 with every key
  of research 04; no `/` or host name in a summary; the R12 census (`UVM_DATA` in all six files, the
  two dropped phrases absent, `uvm help`). Evidence half: both scenarios, `exit=0` and
  `progress=ok` twice, `ranks=128` and `nodes=2`, restores and outcomes, every equality at 5 in both
  passes, the commit kept, `unpinned_upgrade=moved`, the kill keys at 127, `clean_restores=1`.
  The census also asserts "once after upgrading" in `README.md` and the modulefile, no README
  heading carrying a version, `PLAN.md`'s `### Release note` naming `$UVM_DATA/bin`, and
  `uvm_tool_entry` in `AGENTS.md`. R12's per-surface reading, the *Design notes* entry and the
  `UVM_DATA` section's migration text are inspection-only.
- **Touches:** `tests/repair-race.sh`, `AGENTS.md`, `spec/installed-tool-parity/evidence/` (Run B),
  `PLAN.md` §5 (Run B), any surface the R12 sweep corrects.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative; the `current_phase`
   pointer is reconciled against them.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[feature]` commit; stop and report.
