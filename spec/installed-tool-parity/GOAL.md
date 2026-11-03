# GOAL — An installed tool run by its own name gets the repair `uvx` gets

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** installed-tool-parity
- **kind:** feature
- **appetite:** big · at most five phases, target 2026-11-06 (Clarification N10). R5 alone is
  `hammerable: true`; every other criterion is a correctness criterion and `hammerable: false`.

## Problem

`purge-tree-repair`, shipped in 0.7.0, made one job script survive a scratch purge: `srun uvx
<tool>` with `UVM_REPAIR` set, where one call per scope checks and repairs the tree, the rest wait,
and every rank runs. That route stays. The workflow most users reach for first is a second one:
`uv tool install <spec>` on a login node, then `srun <tool>` in a job. Who it hurts is the same user
inside a batch job, and that route gets none of the guarantees. It is **pre-existing** on `main`; the
maintainer found it dogfooding the deployed `uv/0.7.0` module on a production cluster on 2026-11-01.

**The trampoline never enters the wrapper.** The generated trampoline (`bin/uv-manager:626-675`)
execs `$d/$a/bin/shims/$n` directly, so no scope check runs. `README.md` § *Repairing inside a job*,
*Reach* (`:552-554`), says so and tells users to write `uvx <tool>` instead.

**Even a call that enters the wrapper can only repair what survives in the tree.** The one record
of what the user asked for is `uv-receipt.toml`, inside `tools/<name>/`, on the filesystem the purge
reaches. Every class the 0.7.0 repair concedes follows from that: a whole tool directory gone; a
receipt gone; a distribution gone with its dist-info directory; a git, URL or path source, which the
tool arm refuses (`.agents/factory/invariants.md` §8); an unpinned request, recorded with no version;
and an absolute `install-path`, which a relocated `UVM_ROOT` invalidates
(`spec/purge-resilient-run/research/04-uv-repair-idioms.md` §2, §4).

**The realistic purge of an idle tool is refused outright.** A purge takes files by access time and
keeps directories and links (`spec/purge-tree-repair/GOAL.md`, review cycle 2, ruling 9). Measured
in shaping with real uv 0.13.6: with every file of an installed `pycodestyle` removed, `UVM_REPAIR=o1
uv --version` fails the scope with "tool pycodestyle has no pyvenv.cfg, so no automated repair is
safe". The same tool reinstalled from a pinned replay came back exactly, with the base interpreter's
`site-packages` unchanged (Clarification Q2).

**A purged shim takes its trampoline with it.** Trampoline names come from the per-architecture
shims, and the sync removes any trampoline no shim names (`bin/uv-manager:677-684`). Re-confirmed at
`648496d`: with the shim removed, the next `uv tool list` deletes the trampoline. Before that sync
the trampoline prints "it exists for another architecture", which is false after a purge.

**The `uvx` route pays for its guarantee on every call.** `uvx --from git+<repo> <cmd>` fetches on
every call, and fails under `UV_OFFLINE=1`, unless pinned to a commit (production cluster,
2026-11-01). That is a trade the `uvx` route's users can make, not a defect; it is one reason the
installed route deserves a contract of its own. Measured in shaping (Clarification Q3): `uvx` on an
installed tool whose whole directory is gone runs an ephemeral environment at the newest release,
exit 0, with no message — the installed version is silently lost.

**Re-confirmed against `release/0.8.0` (`648496d`), 2026-11-01.** The seed's line references hold:
the trampoline heredoc `:626-675`, the sync's removal `:677-684`, the `uv tool` intercept
`:1685-1694`, `README.md:302` ("every path under scratch, none under $HOME") and the *Reach*
paragraph. The script is 1715 lines.

## Outcome / vision

Two job-script routes, both supported, under one repair contract: with `UVM_REPAIR` set, one call
per scope checks and repairs, the rest wait, and every rank runs.

| Route | Where its state lives | Who owns its purge cases |
|---|---|---|
| `srun uvx <spec>` | the ephemeral environment in `${UVM_ROOT}/<arch>/cache` | works on 0.7.0, except cache damage, which [`uv-cache-purge-damage`](../../issues/uv-cache-purge-damage.md) closes |
| `uv tool install <spec>`, then `srun <tool>` | the record and trampoline in `$UVM_DATA`, the payload in `${UVM_ROOT}/<arch>/tools` | this cycle |

Neither route replaces the other, and the documentation presents both. After this cycle `srun
<tool>` for an installed tool carries the guarantees `srun uvx <spec>` does. A tool whose directory,
receipt or shim a purge took comes back from a record the purge cannot reach, and a healthy tool
runs with no network fetch and, with the knob unset, without entering the wrapper.

**The `UVM_DATA` contract.** `UVM_ROOT` names the scratch tree: the payload, large, per-architecture
and rebuildable. `UVM_DATA` names the durable tree: what the user asked for, a few KB per tool,
architecture-neutral and rebuildable from nothing else, plus the trampolines generated from it. The
modulefile sets it beside `UVM_ROOT`, so `module show uv` names both trees; unset, the wrapper uses
`${XDG_DATA_HOME:-$HOME/.local/share}/uvm`. Nothing large and nothing architecture-specific is
written there, so the home-quota promise that motivated the wrapper holds, and where home is
snapshotted the records are backed up as well as purge-proof.

**Design direction carried from the seed** (maintainer-endorsed; the plan owns the mechanism):

- A record is one directory per tool of plain files, never TOML: the `uv tool install` arguments
  as typed with URL userinfo stripped; every distribution pinned from its dist-info name, a VCS or
  URL source from `direct_url.json`; the interpreter; the entrypoints. Written by temp file and
  `mv` when `uv tool install` or `upgrade` exits 0, deleted when `uninstall` does.
- Trampolines for recorded tools live in `$UVM_DATA/bin`, generated from the records. Those for
  interpreters and unrecorded tools, generated from surviving shims, stay in each root's
  `$UVM_ROOT/bin`, which the modulefile keeps on `PATH` after `$UVM_DATA/bin` (N6 and A2, amended).
- A trampoline has three paths: knob unset and shim executable, exec the shim and nothing else;
  knob set, exec the wrapper's one internal entry with the tool's name, which runs the scope check
  a `uvx` call runs and then execs the shim; shim missing, enter the wrapper, which restores under
  the knob and otherwise says what to run.
- Restore replays the record: `uv tool install --force --no-cache -c <pins> <argv>`, from `/` in a
  subshell like the existing arms.
- The existing walk and `uv-manager doctor` read the records; doctor backfills records for tools
  that have none.

### Terms

- **Record:** what the wrapper keeps under `$UVM_DATA` for one installed tool.
- **Trace:** a tool has a trace in an architecture's tree when its directory under `tools/` or a
  shim naming it under `bin/shims/` exists there, dangling or not.
- **Restore:** reinstalling a tool from its record. **Repair** stays the 0.7.0 in-place arm.
- **Purge shapes** of an installed tool, used by R1, R4 and R11:
  - **(W)** its whole directory removed, its shim left dangling;
  - **(E)** every file of its directory removed, directories and links kept, which takes
    `pyvenv.cfg` and the receipt;
  - **(R)** its `uv-receipt.toml` alone removed;
  - **(S)** its shim alone removed;
  - **(G)** a tool installed from `git+https://…` with no revision, in shape (E).
- **Tool pair:** the trees R1 and R4 are driven on: a tool pinned with a pinned `--with` package,
  and beside it a tool installed unpinned at an older release with an unpinned `--with` package at
  an older release, newer releases of both existing (the shape that hid C2-F2 in
  `purge-tree-repair`).
- **Fixture drive / real-uv drive / tree (F):** as defined in `spec/purge-tree-repair/GOAL.md`. A
  real-uv drive seeds `versions/<ver>` and `current` from a local uv 0.13.6, as
  `tests/repair-race.sh --uv-bin` does, and sets `XDG_DATA_HOME` inside the sandbox.

## Acceptance criteria (the contract)

Every **Observed** status was recorded on 2026-11-01 at `release/0.8.0` (`648496d`), which carries
`main`'s code unchanged.

- **R1** — WHEN a tool is restored from its record, its environment SHALL hold exactly the
  distributions, at exactly the versions, it held when the record was last written: a VCS
  distribution at the recorded commit, on an interpreter of the recorded minor version
  (Clarification N4). The restore SHALL leave the record byte-identical. A restore SHALL NOT leave
  a tool held against `uv tool upgrade` that was not held before the purge; where the plan's drive
  shows no mechanism can keep that, the documentation SHALL state the hold and name `uv tool install
  --force <argv>` as its remedy, and `uv-manager doctor` SHALL report the tool as pinned by a
  restore (Clarification N1).
  *Checked by real-uv drives on the tool pair and on (G), each in shapes (W), (E), (R) and (S):
  the sorted dist-info listing before the purge equals the listing after the restore,
  `direct_url.json`'s `commit_id` is unchanged, `pyvenv.cfg`'s `version_info` keeps its major and
  minor, every record file compares equal (`cmp`), and the tool runs. Then, for the unpinned tool
  of the pair, `uv tool upgrade <tool>` after the restore moves it to the newest release, as it does
  on an unpurged twin. **Observed: not constructible** — no record exists. The replay idiom alone
  measured green in shaping (Clarification Q1), and its receipt then held the tool: `uv tool
  upgrade` printed "Nothing to upgrade" (N1).*
- **R2** — WHEN `uv tool install` or `uv tool upgrade` exits 0 through the wrapper, the wrapper SHALL
  write or rewrite the record of each tool it installed or upgraded, so that no reader sees one half
  written; WHEN `uv tool uninstall` exits 0, it SHALL delete that tool's record. On a non-zero exit
  nothing under `$UVM_DATA` SHALL change. No file under `$UVM_DATA` SHALL contain a credential given
  in a URL's userinfo, whether in the tool's spec, an index or find-links URL, or a VCS URL.
  *Checked by real-uv drives: an install writes a record; an upgrade of an unpinned tool at an
  older release moves the record's pins with the environment; `upgrade --all` rewrites each
  record; an uninstall removes the record and the trampoline. An install of a name no index has
  leaves `find "$UVM_DATA" -type f -exec cksum {} +` unchanged. An install whose index URL carries
  the userinfo `__token__:SECRETMARK` (the plan names a host that accepts it) leaves `grep -r
  SECRETMARK "$UVM_DATA"` with no match. **Observed: red** — nothing is written outside `UVM_ROOT`;
  `$XDG_DATA_HOME` does not exist after an install.*
- **R3** — WHERE `UVM_REPAIR` is set, WHEN an installed tool is run by its own name, the call SHALL
  run the scope check a `uv` or `uvx` call in the same scope runs, under the same lock, outcome and
  failure contract (`purge-tree-repair` R2, R7, R9, R10), before the tool executes, and then run the
  tool, whose stdout and exit status SHALL be its own. All repair output SHALL go to stderr.
  *Checked by fixture drives on tree (F) with a shim `fx` planted beside it and the trampolines
  synced: `SLURM_JOB_ID=100 UVM_REPAIR=1 fx` prints one repair line on stderr, records the `job-100`
  scope repaired, and prints exactly the shim's stdout; a second call prints no repair line; a shim
  exiting 7 gives rc 7; with the repair made to fail, rc is non-zero and the shim does not run.
  **Observed: red** — rc 0, stdout `fx-ran`, 0 repair lines, no `.repair/` directory. The control,
  `uvx fx` in the same scope: 1 repair line and `job-100.ok`.*
- **R4** — WHERE `UVM_REPAIR` is set, WHEN a recorded tool is in shape (W), (E), (R), (S) or (G),
  the next knob-set call in a scope with no outcome, by the tool's name or through `uv` or `uvx`,
  SHALL restore it from its record while holding the repair lock, then run its command. Concurrent
  callers SHALL wait and SHALL NOT restore, and a failed restore SHALL fail them promptly with its
  reason, as `purge-tree-repair` R7 and R9 require. A tool with no record SHALL be treated exactly
  as on 0.7.0.
  *Checked by real-uv drives, one per shape, 16 local ranks each calling the tool by name: exactly
  one rank announces a restore, 16/16 exit 0 with the tool's output, and R1's equalities hold. One
  run per shape goes through `uvx <tool>` instead. A twin of the pair with no record, in shape (E),
  fails the scope naming `pyvenv.cfg` as today. With the restore made to fail (the plan names how,
  for example an unreachable index), every rank exits non-zero carrying the reason. **Observed:
  red** — shape (E): the scope fails, "tool pycodestyle has no pyvenv.cfg, so no automated repair
  is safe"; replayed by hand from a record, the same tool came back exactly.*
- **R5** — WHERE `UVM_REPAIR` is set, WHEN a recorded tool with no trace in the executing
  architecture's tree is run by its own name, the call SHALL restore that tool alone from its
  record under the repair lock and run it, with concurrent callers waiting. A knob-set call SHALL
  NOT restore a recorded tool that has no trace in the tree unless that tool is the one being run
  by name (Clarifications N2, N3). **Hammerable:** the first criterion to move to a follow-up seed
  if the five-phase cap binds (N10); the second clause, that the walk restores no tool without a
  trace, stays either way.
  *Checked by a real-uv drive on two platform keys (`temp_root.sh --arch`): a tool installed under
  key A, then on key B `UVM_REPAIR=1 <tool>` from 8 ranks: one restore, 8/8 exit 0 with the tool's
  output. On key B, `UVM_REPAIR=2 uv --version` with a second recorded tool absent there prints no
  restore line. **Observed: red** — on key B the trampoline exits 127, "it exists for another
  architecture".*
- **R6** — WHILE `UVM_REPAIR` is unset, empty or `0`, a tool whose shim is executable SHALL be run by
  its own name without starting the wrapper. A tool whose shim is missing or not executable SHALL
  exit 127 without restoring anything or taking a lock, naming the tool; where a record exists the
  message SHALL say the tool is recorded but not present for this architecture and name the remedy
  (the knob, or `uv-manager doctor`); without one it keeps the 0.7.0 text.
  *Checked by fixture drives: with a planted shim and the wrapper the trampoline would enter
  replaced by one that leaves a marker (the plan names how), a knob-unset call runs the shim and no
  marker appears. 300 warm calls of trampoline-to-shim against `release/0.8.0`'s trampoline, as
  `lock-simplification`'s review measured, show the unset path's cost unchanged within noise. In
  shape (S) with a record, rc 127, the tool named, the remedy printed, no lock and no outcome.
  **Observed: green for the first clause** (the 0.7.0 trampoline execs the shim; 13-14 ms against
  4.4 ms for the bare shim on the shaping host), **red for the second** — shape (S) prints "it
  exists for another architecture", rc 127, which is false after a purge.*
- **R7** — A trampoline for each entrypoint a record names SHALL live in `$UVM_DATA/bin`, and a
  sync SHALL remove one there only when no record names it, so it SHALL NOT be removed because a
  shim is missing. A trampoline for each shim name in a root's tree, under any architecture, SHALL
  live in that root's `$UVM_ROOT/bin`: the managed interpreters and any tool without a record among
  them. A sync SHALL remove one there only when no shim of that root names it, as 0.7.0 does, and a
  sync on one root SHALL NOT write or remove a trampoline under another root. A marked 0.7.0
  trampoline in `$UVM_ROOT/bin` that a shim names SHALL be rewritten in place with the new body,
  never removed, so that a path a running shell has hashed keeps working; an unmarked file there
  SHALL NOT be touched. A trampoline SHALL find the tree wherever the wrapper would, `UVM_ROOT` unset
  in its environment included, or fail naming `UVM_ROOT`. `.agents/factory/invariants.md` §9 carries
  over: the marker, rewrite-never-skip, temp file and `mv`, a `/bin/sh` body resolving the platform
  key at exec time (Clarifications N6 as amended, N8, A2).
  *Checked by fixture drives: with a record and a shim planted, removing the shim and running `uvm
  trampolines` and then `uv tool list` leaves `$UVM_DATA/bin/fx`. With `UVM_ROOT` removed from the
  environment and the sandbox's tree reachable through a cascade candidate (`SCRATCH`), the
  trampoline runs the shim. With a marked 0.7.0 trampoline a shim names, a marked one no shim names
  and an unmarked executable script planted in `$UVM_ROOT/bin`, a sync rewrites the first in place,
  removes the second and leaves the third. With one `UVM_DATA` shared by roots A and B, B holding a
  managed interpreter's shim, an unrecorded tool's and a recorded tool's, a sync, `uv-manager
  doctor` and `uv tool list` on A leave all three running on B. **Observed: red** — with the shim
  removed, the sync deletes `$UVM_ROOT/bin/fx`. Amended at review cycle 1 (A2): at `7aecf40` the
  sync on A leaves B's interpreter and unrecorded tool exiting 127 (C1-F3).*
- **R8** — `uv-manager doctor` SHALL write a record for each installed tool that has none and still
  has its receipt, pinned to what is installed now, such that R1's restore of that record brings
  the tool back with its `--with` packages and its source; SHALL report a recorded tool with no
  trace in this architecture's tree as an advisory naming its remedy, not as a failure; SHALL
  regenerate missing trampolines; and SHALL write nothing under `UVM_ROOT`. A tool with neither
  record nor receipt is reported and not backfilled. The same backfill SHALL run after a `uv tool`
  command through the wrapper and in the knob-set walk's holder, each only where a record is
  missing and never rewriting one (Clarification N7).
  *Checked by a real-uv drive on a tree built by the `release/0.8.0` wrapper (the tool pair and a
  git tool), then switched to the branch's: `uvm doctor` writes three records; then each tool, in
  shape (W), is restored through the knob and R1's equalities hold. A `find "$UVM_ROOT" -type f
  -exec cksum {} +` listing is identical before and after doctor. **Observed: red** — doctor writes
  no record; there is no `UVM_DATA`.*
- **R9** — The modulefile SHALL set `UVM_DATA` and put `$UVM_DATA/bin` on `PATH` ahead of
  `$UVM_ROOT/bin`, which stays on `PATH` after it permanently, holding that root's trampolines
  (R7), so a 0.7.0 trampoline still on scratch serves at 0.7.0 behaviour until a sync rewrites it.
  WHEN a `uv` or `uvx` call finds `$UVM_DATA/bin` absent, the wrapper SHALL sync the trampolines
  once; while it exists the test costs one `stat`. WHERE `UVM_DATA` is unset, the wrapper SHALL use
  `${XDG_DATA_HOME:-$HOME/.local/share}/uvm`. The wrapper SHALL write under `UVM_DATA` only records
  and trampolines, none named for an architecture, and `uv-manager status` SHALL name `UVM_DATA` and
  where it came from. No new environment variable beyond `UVM_DATA`.
  *Checked by drives: with `UVM_DATA` unset and `XDG_DATA_HOME` in the sandbox, records land under
  `$XDG_DATA_HOME/uvm`; with both unset and `HOME` in the sandbox, under `$HOME/.local/share/uvm`.
  After installs on two platform keys, `find "$UVM_DATA"` lists only records and trampolines, no
  path containing either key, and `du -sk` per tool record of a few KB (the plan states the
  figure). `uvm status` names `UVM_DATA`. The modulefile by `git grep -n UVM_DATA
  share/modulefiles/uv/main.lua`, read by the reviewer. **Observed: red** — no `UVM_DATA` exists;
  `uvm status | grep -ci data` prints 0.* *Amended at the plan gate (N6): on a tree built by
  `release/0.8.0` with a tool installed, with the 0.8.x modulefile's `PATH` and no `uv` call yet,
  ranks running the tool by name all exit 0; the first `uv` call then generates `$UVM_DATA/bin` and
  removes the 0.7.0 trampoline it replaced; the modulefile's `PATH` order is checked by the line
  order of its two `prepend_path` calls and read by the reviewer; the stat's cost is measured and
  stated in `PLAN.md`. **Observed: green for the ranks** (the 0.7.0 trampoline serves), **red for
  the generation** (nothing writes `$UVM_DATA`).* *Amended at review cycle 1 (A2): the first `uv`
  call creates `$UVM_DATA/bin` and rewrites the 0.7.0 trampoline in place rather than removing it,
  and a `bash` job script that runs the tool, then `uv --version`, then the tool again, with the
  0.8.x `PATH` and no `uv` call before it, exits 0 with the tool's output twice. **Observed at
  `7aecf40`: red** — the second call exits 127, because the first `uv` call removed the path bash
  had hashed (C1-F2).*
- **R10** — `srun uvx <spec>` for a tool that is not installed, and every `uv` command other than `uv
  tool`, SHALL behave as on 0.7.0: the same scope check, the same exit statuses, and nothing written
  under `$UVM_DATA` for a tool that is not installed (Clarification N11).
  *Checked by a real-uv drive: `SLURM_JOB_ID=200 UVM_REPAIR=1 uvx pycowsay` on a tree with no
  installed tool gives rc 0 and one repaired outcome for the scope, and a `find "$UVM_DATA" -type f
  -exec cksum {} +` listing is the same before and after. **Observed: green**, vacuously for the
  `UVM_DATA` clause, since nothing writes it; the scope half as the fixture control in R3 shows.
  Expected green after. Collateral.*
- **R11** — WHEN a job launches 128 ranks across 2 nodes with `UVM_REPAIR=1`, each running an
  installed tool by its own name, against a tree on a parallel filesystem whose recorded tools are
  in shapes (W), (E), (R), (S) and (G), exactly one rank SHALL restore while holding the repair lock,
  every rank SHALL exit 0 with its tool's expected output, R1's equalities SHALL hold, and no lock
  SHALL be left. WHEN the restoring rank is killed, every waiter SHALL exit non-zero at
  `UVM_LOCK_TIMEOUT` naming the repair lock and its owner line with no outcome recorded, and after
  `uvm clean lock --yes` a clean pass SHALL restore once with every rank exiting 0.
  *Checked by a Slurm drive extending `tests/repair-race.sh` with an installed-tool scenario and its
  kill variant (the plan's choice of shape), `--launch srun`, 2 nodes × 64 ranks on Lustre, every
  file of the run, `$UVM_DATA` included, under the run directory (A2). Its summary holds counts only,
  committed as evidence the way `purge-tree-repair`'s was: restores=1, `rc_hist`, `stdout_hist`,
  nodes, locks left, the holder's seconds, the waiters' wait, notice lines, frozen sets identical,
  the git commit kept, records identical; the kill pass and the clean pass as in `purge-tree-repair`
  R12. It needs `git` on compute nodes and egress to `pypi.org`, `files.pythonhosted.org` and
  `github.com`; the target cluster's compute nodes have `git` and egress to GitHub, PyPI and
  `astral.sh` (foreman, 2026-11-01). The foreman submits the jobs; the orchestrator grades the evidence and the
  reviewers take it on trust. **Observed: not constructible**; the local reds of R3 and R4 stand
  for it.*
- **R12** — Read per surface, as `purge-tree-repair` R14 was: `README.md`, the `uvm_help` heredoc,
  `etc/uv-manager.conf.example` and `share/modulefiles/uv/main.lua` SHALL present `srun uvx <spec>`
  and `srun <tool>` as supported job-script routes under one repair contract, SHALL say what the
  wrapper keeps under `UVM_DATA`, its default and its size per tool, and SHALL drop only the
  statement that a tool run by its own name skips the check. `README.md` SHALL also: reword the two
  places that promise nothing under home (line 4's quota sentence and the `uv-manager status`
  comment at `:302`) to say what does live there; reword mitigation 4 ("Prefer `uvx` over `uv tool
  install`"); state what a restore covers and concedes (N1, N5, N9); carry a reference-table row for
  `UVM_DATA`; and add a *Design notes* entry recording why what the user asked for lives outside the
  scratch tree; its section on `UVM_DATA` SHALL say what becomes of the 0.7.0 trampolines and to run
  `uv-manager doctor` once after upgrading, and no section of it SHALL be titled by a version. The
  release note, kept in `PLAN.md` under *Release note* for the foreman to carry into the 0.8.0
  notes, SHALL say that the 0.7.0 trampolines in `$UVM_ROOT/bin` are rewritten in place and that
  a `PATH` entry naming that directory by hand gains `$UVM_DATA/bin` ahead of it (N6, A2). `AGENTS.md` and `.agents/factory/invariants.md` SHALL move in lockstep on §1 (the
  paths a modulefile may put on `PATH`), §8 (what the wrapper sets and writes, and the restore
  beside the repair) and §9 (trampolines).
  *Checked by `git grep -c UVM_DATA -- bin/uv-manager README.md etc/uv-manager.conf.example
  share/modulefiles/uv/main.lua AGENTS.md .agents/factory/invariants.md` naming all six files; by
  `git grep -n -e 'none under \$HOME' -e 'use .uvx <tool>. in the job script' -- README.md`
  returning no match; by `temp_root.sh uvm help | grep -c UVM_DATA` printing at least 1; each hit
  read by the reviewer against this list. Amended at the plan gate: by `git grep -n -i 'once after
  upgrading'` matching `README.md` and `share/modulefiles/uv/main.lua`; by `git grep -n -E '^#+ .*[0-9]+\.[0-9]+\.[0-9]+' -- README.md` returning no match; by a `### Release note` heading
  in `PLAN.md` whose text names `$UVM_DATA/bin`. **Observed: red** — `UVM_DATA` has 0 hits (`git
  grep` rc 1), the help census prints 0, and both phrases match (`README.md:302`, `:554`).*

## Non-goals (no-gos)

- **A purged trampoline as a failure class.** Moot for a recorded tool, whose trampoline lives under
  `UVM_DATA`; doctor regenerates any that go missing (R8). A trampoline in `$UVM_ROOT/bin`, for an
  interpreter or an unrecorded tool, is as purgeable as on 0.7.0 and comes back with the next sync
  of that root (A2).
- **Damage inside uv's cache.** The `uvx` route's half of the contract, owned by
  [`uv-cache-purge-damage`](../../issues/uv-cache-purge-damage.md), whose R1-R4 already carry it.
  A restore here runs with `--no-cache` and never reads the cache.
- **Any change to `srun uvx <spec>` for a tool that is not installed** (R10).
- **Records for managed interpreters.** No `uv python install` replay; interpreter trampolines stay
  in `$UVM_ROOT/bin`, generated from surviving shims (A2), and a damaged interpreter is still the
  0.7.0 interpreter arm's.
- **Local sources.** A tool installed from a path, a directory or an editable source, or with an
  option naming a local file (`--with-requirements`, `-c`, `--overrides`), is recorded but not
  restored: the restore refuses it naming the tool and the reason, as 0.7.0's arm refuses a path
  source (Clarification N9).
- **A hand-edited record.** Records belong to the wrapper; a user changes them through `uv tool`.
- **Export and import of a tool set across sites, and any `uv-manager tool` subcommand family**
  beyond the one internal entry the trampoline needs.
- **Recording credentials.** A replay authenticates as the original install did, through `uv.toml`,
  netrc or the environment; one whose only credential was in a URL fails as a failed restore.
- **`uv run`, PEP 723 scripts and project `.venv` directories.**
- **A shell fast path for a recorded outcome in the trampoline.** Measured in shaping
  (Clarification Q4), a knob-set call by name costs about what the `uvx` route already costs, so
  duplicating the scope derivation in `sh`, beside the platform key, does not earn its upkeep.
- **Any change to the lock contract, the scope derivation or the whole-tree waiter's predicate.**
  [`repair-scope-queueing`](../../issues/repair-scope-queueing.md) owns that predicate; Clarification
  N3 records why the two compose.
- **No committed suite beyond the R11 drive.** The other *Checked by* drives are this cycle's gates.

## Clarifications

Resolved in shaping, from real-uv drives with uv 0.13.6 under `temp_root.sh` (macOS, arm64):

- **Q1 — Does `uv tool install -c` accept a direct-URL constraint for a VCS source, or must the
  replay rewrite `argv` to `@<commit_id>`?** — **A:** The constraint works. With `argv` the bare
  `git+https://github.com/glentner/progressbar` and the constraint line `progressbar @
  git+https://github.com/glentner/progressbar@<commit_id>`, the restored set was identical and
  `direct_url.json` named the same commit. Rewriting `argv` also works but changes the recorded
  request to `?rev=<commit>`, so the record keeps `argv` as typed and carries the pin as a
  constraint. The other forms held too: an unpinned tool and `--with` package at older releases
  came back at those releases, not the newest; a pinned tool with a pinned `--with` came back
  exactly; shapes (R) and (W) replayed exactly with `--force`. In shape (S) a replay without
  `--force` prints "already installed", exits 0 and leaves the shim missing, so `--force` is
  load-bearing there. `UV_CONSTRAINT` is honored as `-c` is (shaping, 2026-11-01).
- **Q2 — Is the realistic purge of an idle tool restorable without the base-interpreter escape
  `purge-tree-repair` R5 guards against?** — **A:** Yes, from a record. In shape (E),
  `pyvenv.cfg` and the receipt gone, `uv tool install --force --no-cache -c <pins> <argv>` rebuilt
  the environment exactly, `pyvenv.cfg` included, and the base interpreter's `site-packages`
  listing was unchanged. So a record turns 0.7.0's refusal into a restore; with no record the
  refusal stands (R4) (shaping, 2026-11-01).
- **Q3 — Which `uvx` forms resolve to an installed tool's environment?** — **A:** Measured by
  whether a new environment appeared in the cache. Installed: `uvx <name>` where the command is
  the tool's name; `--from <name>`; `--from <name>==<installed>`; `<name>@<installed>`; `--from
  git+<url>@<installed commit>`; `--from <package> <command>` for a git tool. Not installed:
  `<name>@latest`; `--isolated`; `--from git+<url>` with no revision, which builds a new
  environment even at the installed commit; and `uvx <command>` for a git tool whose command differs
  from its package (`uvx pb`), which looks for a package named after the command and fails. uv
  finds the installed tool by the command's name (`tools/<command>` in `-v`). With the tool's
  whole directory gone, `uvx <name>` exits 0 on an ephemeral environment at the newest release.
  So the restore reaches the `uvx` route for the installed forms, through the scope check's walk
  (R4) (shaping, 2026-11-01).
- **Q4 — What does a knob-set trampoline cost against the hot path?** — **A:** On the shaping host,
  300 warm calls each: real `uv --version` 6.7 ms; through the wrapper 15.7-16.4 ms, about 9.5 ms
  of wrapper; with the knob set and the scope recorded 16.1-16.9 ms, about 0.5 ms more; a `sh`
  shim that exits 4.4 ms, and the same through today's trampoline 13.2-14.3 ms, about 9 ms of
  trampoline. A real tool (`pyflakes --version`, 40 calls): shim 36-42 ms, trampoline 48 ms, `uvx`
  57-59 ms. A knob-set call by name is trampoline plus wrapper plus shim, about 18 ms over the
  shim, which is what the `uvx` route pays today. The 12 ms the seed cites is
  `spec/purge-resilient-run/PLAN.md`'s whole invocation on another host. The knob-unset path is
  unchanged (R6) (shaping, 2026-11-01).

Rulings at the GOAL gate are the foreman's, as the maintainer's delegated judge for this effort.

- **N1 — Q:** A replay, by `-c` or `UV_CONSTRAINT`, writes every pin into the receipt's
  `constraints`, and a later `uv tool upgrade <tool>` then prints "Nothing to upgrade … pinned" for
  a tool installed unpinned, a git tool following its default branch included (measured in
  shaping). May a restore leave a tool held that way? — **A:** No. A restore must not leave a tool
  held against upgrade that was not held before the purge; R1 carries it and checks `uv tool
  upgrade` after a restore of the pair's unpinned tool. The mechanism is the plan's. The direction
  to test first: keep the in-place 0.7.0 repair wherever the environment still runs, so its
  receipt stays byte-identical; keep a verbatim copy of `uv-receipt.toml` in the record as opaque
  bytes, which the wrapper copies and never parses, so the seed's "no TOML" (no TOML parsing) holds;
  after a successful replay, put that copy back as the receipt when the paths it records still name
  this tree, and otherwise keep uv's pinned receipt and have doctor report the tool as pinned by a
  restore. If the plan's drive shows the copy-back breaks uv, the fallback is to document the hold
  and name `uv tool install --force <argv>` as the remedy. The plan also measures how a recorded
  `<name>@latest` replays against its pins. Amended: R1 and its *Checked by* (foreman ruling,
  2026-11-01).
- **N2 — Q:** Does the knob-set walk restore every recorded tool, or only those with a trace? —
  **A:** Only those with a trace in the executing architecture's tree. Every purge shape leaves
  one, a dangling shim at least, so the walk still restores every class the seed names. A recorded
  tool with no trace was installed for another architecture, on another cluster sharing
  `UVM_DATA`, or removed by hand; restoring all of those in every job's walk would install every
  tool on every node type and cluster, each download under the lock. Those come back on demand, by
  name (R5) (foreman ruling, 2026-11-01).
- **N3 — Q:** What does a caller waiting on an on-demand restore wait for, and how does it compose
  with `repair-scope-queueing`? — **A:** Success is the evidence, the shim executable again, and no
  repaired outcome is written for it; failure is a failed record keyed by the scope and the tool,
  carrying the reason, so waiters fail promptly as `purge-tree-repair` M4 requires. Success needs
  no record because a trampoline enters this path only when the shim is missing, so a stale record
  cannot read clean; a shim-only predicate cannot carry a failure's reason, so waiters would sit out
  `UVM_LOCK_TIMEOUT`. `repair-scope-queueing` proposes accepting a repaired outcome newer than the
  waiter's arrival from any scope; this path writes no repaired outcome, so that change cannot
  satisfy it, and nothing is owed to that seed (foreman ruling, 2026-11-01).
- **N4 — Q:** Which interpreter does a replay ask for? — **A:** The recorded minor (`-p 3.12`),
  unless `argv` carries its own `--python`, which then wins; patch drift after a purge is accepted.
  `pyvenv.cfg` records the patch (`3.12.16`) and the receipt records `python = "3.12"` only when the
  install asked for one; with no request a replay takes uv's default interpreter, which on a cluster
  can be a module's system interpreter of another minor. Wheels are keyed by minor, and every
  distribution stays pinned (foreman ruling, 2026-11-01).
- **N5 — Q:** What happens where `UVM_DATA` is shared by clusters, as a home directory can be? —
  **A:** The feature, gated by the knob and a call by name. A tool installed on one cluster appears
  on `PATH` on the others; there it is restored only by name with the knob set (R5, N2), and
  without the knob the trampoline says it is recorded but not present (R6). Doctor reports it as an
  advisory, so a prologue keyed on doctor's exit status does not fail (R8). Pins recorded on one
  platform are constraints elsewhere: they add no package, and a pinned version with no
  distribution for the other platform fails the restore naming the tool. The same holds across
  architectures on one cluster. Documented (R12) (foreman ruling, 2026-11-01).
- **N6 — Q:** What becomes of the 0.7.0 trampolines in `$UVM_ROOT/bin`? — **A:** The first 0.8.0
  sync removes the ones carrying the marker, as the sync already removes its own, and the release
  note tells anyone who put `$UVM_ROOT/bin` on `PATH` by hand to use `$UVM_DATA/bin`. A stale
  `PATH` entry then fails loudly, command not found, rather than running a trampoline that skips
  the check. Amended: R7, R12 (foreman ruling, 2026-11-01).
  **Amended at the plan gate (foreman ruling, 2026-11-01):** "command not found" for an installed
  tool on the first job after a site upgrades the module is not acceptable. Through 0.8.x the
  modulefile puts `$UVM_DATA/bin` first on `PATH` and keeps `$UVM_ROOT/bin` after it, a documented
  migration path a later release removes; a 0.7.0 trampoline still on scratch serves at 0.7.0
  behaviour until a sync generates its replacement. A sync removes a marked 0.7.0 trampoline only
  once its replacement exists in `$UVM_DATA/bin`, or once no record or shim names it. Any `uv` or
  `uvx` call that finds `$UVM_DATA/bin` absent generates the trampolines once (one `stat` on the hot
  path while it exists, measured in `PLAN.md`). The documentation says plainly to run `uv-manager
  doctor` once after upgrading. Amended: R7, R9, R12.
  **Amended at review cycle 1 (A2, foreman ruling, 2026-11-01):** `$UVM_ROOT/bin` stays on `PATH`
  behind `$UVM_DATA/bin` permanently, not as a migration path, and a marked 0.7.0 trampoline there
  that a shim names is rewritten in place, never removed. Clarification A2 says why. Amended: R7,
  R9, R12.
- **N7 — Q:** Where does backfill run for 0.7.0 installs? — **A:** In doctor, after every `uv tool`
  command (which already syncs trampolines, so a first `uv tool list` under 0.8.0 migrates every
  tool), and in the knob-set walk's holder, each only where a record is missing, never rewriting
  one; without the third, a user who only runs jobs after the upgrade has no records. The request
  comes from uv's own record of it, the receipt's requirements or `uv tool list
  --show-version-specifiers --show-with --show-extras` (measured to print `[required: ==2.11.1]
  [with: six==1.16.0]` and `[required: git+https://…]`); the plan picks. Amended: R8 (foreman
  ruling, 2026-11-01).
- **N8 — Q:** How does a trampoline find the tree with `UVM_ROOT` unset? — **A:** The wrapper
  exports `UVM_ROOT` and `UVM_DATA` to what it runs, and a trampoline that finds `UVM_ROOT` unset
  enters the wrapper, which runs the cascade, rather than holding a third copy of the cascade in
  `sh`. Today's trampoline uses its own location, `$0/..`, which stops working under `UVM_DATA`, and
  children of the wrapper see no `UVM_ROOT` when the root came from the cascade. Baking a root in at
  generation is wrong on a second cluster sharing `UVM_DATA`. This is a deliberate change to §8,
  named in *Invariants changed on purpose* below (foreman ruling, 2026-11-01).
- **N9 — Q:** Which sources are restorable? — **A:** Index and VCS sources, as measured; a URL
  archive too if the plan's drive shows `<name> @ <url>` constrains it as it does a VCS source,
  else refused naming it. Local sources stay a human's job (non-goal): their source sits outside
  anything the wrapper keeps, and the replay runs from `/` (foreman ruling, 2026-11-01).
- **N10 — Q:** Appetite, phase cap and the circuit-breaker? — **A:** Big, at most five phases,
  targeting `release/0.8.0` by 2026-11-06 so that `uv-cache-purge-damage` can follow by about
  2026-11-10. Twelve criteria, past the soft 8-10 breaker, accepted: the seed's ten, with its R4's
  cross-node half split out as R11 (as `purge-tree-repair` did with R12) and its R5 split into the
  trace and on-demand halves (R4, R5). R5 is `hammerable: true`, the first to move to a follow-up
  seed if the cap binds; every other criterion is a correctness criterion and `hammerable: false`
  (foreman ruling, 2026-11-01).
- **N11 — Q:** R10 says no `uv` command other than `uv tool` writes under `UVM_DATA`, and N7 puts
  the backfill in the knob-set walk's holder. Which governs? — **A:** N7. A knob-set walk may
  backfill records for tools that are already installed; R10's "nothing written under `$UVM_DATA`"
  applies to tools that are not installed. The one-time trampoline generation N6 adds writes no
  file on a tree with no installed tool, so R10's check holds as written (foreman ruling at the
  plan gate, 2026-11-01).
- **Q:** Where does R11 run? — **A:** On Lustre, 2 nodes × 64 ranks. Compute nodes there have `git`
  and egress to GitHub, PyPI and `astral.sh` (foreman ruling, 2026-11-01).
- **A2 — Amended at review cycle 1, 2026-11-01, foreman ruling.** Review cycle 1 found two defects
  in the trampoline contract as R7, R9 and N6 stood, not in the build. Retiring a 0.7.0 trampoline
  broke a running job: a `bash` script that ran the tool, then `uv`, then the tool again, exited 127
  on the second call, because the first `uv` call removed the path bash had hashed (C1-F2). And
  `$UVM_DATA/bin` held trampolines derived from one root's shims while every root sharing
  `UVM_DATA` synced it: a sync on root A, from doctor or `uv tool list`, removed root B's managed
  interpreters and unrecorded tools, which then exited 127 on B (C1-F3), the case N5 accepts as a
  feature. 0.7.0 did neither. **A:** Each trampoline directory keeps to the one source of names it
  can see whole. `$UVM_DATA/bin` holds the trampolines generated from the records, shared by every
  root that shares `UVM_DATA`, and loses one only when no record names it, which in practice means
  a `uv tool uninstall`. `$UVM_ROOT/bin` stays on `PATH` behind it permanently and holds this
  root's shim-derived trampolines, the managed interpreters and any tool without a record among
  them, under the new body and 0.7.0's removal rule, per root; a sync on one root never touches
  another root's. A marked 0.7.0 trampoline a shim names is rewritten in place, so a hashed path
  keeps working. Doctor writes nothing under `UVM_ROOT` (R8), so its sync is `$UVM_DATA/bin`'s
  alone, and R8's "regenerate missing trampolines" means the record trampolines; the next sync of
  a root writes its own. A directory a sync cannot write is left as it is, which the guard now
  tests with `-w` (C1-S2). With ruling 9, R11 drops "`$UVM_DATA` on a second filesystem where the
  cluster offers one": the site's test envelope keeps every file of a test run on scratch, and
  nothing in `UVM_DATA`'s behaviour depends on which filesystem holds it (C1-F9). Amended: R7, R9,
  R11, R12's release-note sentence, N6, two non-goals and *Invariants changed on purpose* §1 and §9.

### Invariants changed on purpose

For `/uvm-plan`'s invariant gate and `uvm-review`'s footgun list, these bends are decided here and
are not findings:

- **§1:** the paths a modulefile may put on `PATH` become the deployment `bin/`, `$UVM_DATA/bin`,
  and `$UVM_ROOT/bin` after it, permanently, for each root's own trampolines (R7, R9, N6 as
  amended, A2).
- **§8:** the wrapper also exports `UVM_ROOT` and `UVM_DATA` to what it runs (N8), and writes under
  `UVM_DATA` records and trampolines only (R9). The restore sits beside the repair: it replays a
  record rather than reinstalling in place, and keeps resolution the user's by its pins (R1, N1).
- **§9:** trampolines live in two directories. `$UVM_DATA/bin` holds those generated from the
  records, and they are not removed because a shim is missing. `$UVM_ROOT/bin` holds each root's
  shim-derived ones under 0.7.0's removal rule, per root, and a 0.7.0 trampoline a shim names is
  rewritten in place (R7, A2).

## Related materials

- Seed: [`issues/installed-tool-parity.md`](../../issues/installed-tool-parity.md).
- The landed repair: [`spec/purge-tree-repair/GOAL.md`](../purge-tree-repair/GOAL.md) and
  `REVIEW.md` (lock, scope, outcome contract; the R12 evidence format); `tests/repair-race.sh`, the
  instrument R11 extends.
- [`spec/purge-resilient-run/research/04-uv-repair-idioms.md`](../purge-resilient-run/research/04-uv-repair-idioms.md)
  and `00-digest.md` (D3, the receipt's traps).
- `bin/uv-manager`: `uvm_trampolines`, `uvm_detect`, `uvm_tool_pins`, `uvm_repair_run`,
  `uvm_repair`, the `uv tool` intercept in the dispatch tail. All but the helpers are
  high-blast-radius regions.
- `.agents/factory/invariants.md` §1, §2, §8, §9, §10; `README.md` § *Repairing inside a job*, §
  *Design notes*, § *Verification*; `share/modulefiles/uv/main.lua`.
- Related seeds: [`uv-cache-purge-damage`](../../issues/uv-cache-purge-damage.md), which completes
  the `uvx` route; [`repair-scope-queueing`](../../issues/repair-scope-queueing.md) (N3);
  [`test-harness`](../../issues/test-harness.md), whose R7 hot-path budget Q4 informs;
  [`uvm-bootstrap`](../../issues/uvm-bootstrap.md), since `$UVM_DATA/bin` changes what a bootstrap
  puts on `PATH`.
