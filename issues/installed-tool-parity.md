---
status: unshaped
kind: feature
appetite: big
lane: public
---

# A tool run by its own name gets none of the guarantees `uvx` gets

## Problem

The repair `purge-tree-repair` shipped in 0.7.0 was built around one job script: `srun uvx <tool>`
with `UVM_REPAIR` set, where one call per scope checks and repairs the tree, the rest wait, and every
rank runs. The workflow most users reach for first is different. They run `uv tool install <spec>` on
a login node, and later `srun <tool>` in a job. That second form gets none of the guarantees.

**The trampoline never enters the wrapper.** The generated trampoline (`bin/uv-manager:626-675`)
resolves `$d/$a/bin/shims/$n` and execs it, so no scope check runs. `README.md` § *Repairing inside a
job*, *Reach* (line 553), says so and tells the user to write `uvx <tool>` in the job script instead.
Confirmed against the deployed `uv/0.7.0` module on Gautschi on 2026-11-01.

**Even a call that enters the wrapper can only repair what survives in the tree.** The only record of
what the user asked for is `uv-receipt.toml`, inside `tools/<name>/`, on the filesystem the purge
reaches. Every class the repair concedes follows from that:

- A whole `tools/<name>/` removed: uv no longer counts the tool as installed, doctor reports the
  shim, and the repair leaves it (`README.md` § *What it catches is what doctor catches*).
- A receipt removed: `uv tool upgrade --all` exits 1 and nothing has a spec to rebuild from
  (`spec/purge-resilient-run/research/04-uv-repair-idioms.md` §4).
- A distribution removed with its dist-info directory: no evidence remains (`README.md`, same
  section).
- A git, URL or path source: the tool arm refuses it and fails the scope (`invariants.md`, *The purge
  repair restores what is installed*). `uv tool install git+https://github.com/glentner/progressbar`
  is therefore never repairable on 0.7.0.
- An unpinned request is recorded as `{ name = "tqdm" }`, with no version, and an index given on the
  install's command line alone is not applied again (conceded in `invariants.md`). The receipt's
  `install-path` is absolute, so a relocated `UVM_ROOT` invalidates every receipt (04 §2).

**A purged shim takes its trampoline with it.** Trampoline names come from the per-architecture shims,
and the sync removes any trampoline whose name no shim carries (`bin/uv-manager:677-684`). If the purge
takes the shim itself, the next `uv tool` or `uv python` call deletes the trampoline and the tool
leaves `PATH`. A dangling shim survives the sync, but then the trampoline prints "it exists for
another architecture", which is false after a purge.

**The `uvx` route pays for its guarantee on every call.** Measured on Gautschi, 2026-11-01:
`uvx --from git+https://github.com/glentner/progressbar pb` prints `Updating ... (HEAD)` and fetches
on every call, warm runs included, and fails under `UV_OFFLINE=1`. Pinned to a commit it runs offline,
0.21 s warm against 0.29 s unpinned. Users who follow the README's advice trade a network dependency
per call for the repair.

**Pre-existing** on `main`.

## Why it was deferred

It was not deferred by a pass. The maintainer found it dogfooding the deployed module on Gautschi on
2026-11-01, installing personal CLI tools with `uv tool install` and asking what a job would see after
a purge. `purge-tree-repair` scoped itself to the `uvx` route and conceded the whole-directory class
and the trampoline's reach in its own documentation.

The fix needs state outside `UVM_ROOT`, which contradicts a claim the README makes in two places
(line 4, and line 302's `uv-manager status` comment "every path under scratch, none under $HOME").
That is a design change for a human to accept, not a defect to patch.

## Outcome / vision

After `uv tool install <spec>` on a login node, `srun <tool>` in a job with `UVM_REPAIR` set carries
the guarantees `srun uvx <spec>` does: one repair per scope, the rest wait, every rank runs. It goes
further than `uvx` on one count. A tool whose whole directory, receipt or shim the purge took comes
back from a record the purge cannot reach, and runs with no network fetch when healthy.

The principle: scratch holds the payload, which is large, per-architecture and rebuildable. Home holds
what the user asked for, which is a few KB, architecture-neutral, and rebuildable from nothing else.
Today both live on scratch, and the receipt dies with the payload it describes.

Direction agreed with the maintainer in conversation on 2026-11-01. Appetite, non-goals and R-IDs are
not negotiated; that happens at promotion.

## Recommended design

These are the maintainer-endorsed choices to carry into shaping, not a contract.

**Records live in `${XDG_DATA_HOME:-$HOME/.local/share}/uvm/`.** Not `.../share/uv`: that is uv's own
default tool directory, and the README's verification step expects it absent (line 300). No new knob
at first, since each costs more than its implementation; `UVM_DATA` is the name if a site needs one.
Home on Gautschi and Gilbreth is ZFS with snapshots, so there the records are backed up as well as
purge-proof.

**One directory per tool, plain files, no TOML.** The wrapper reads files with `mapfile` and never
parses TOML (04 §2), so a record is `tools/<name>/` holding:

- `argv`: the arguments after `uv tool install`, one per line, as typed, with URL userinfo stripped.
- `constraints.txt`: every distribution in the tool's environment pinned, read from the dist-info
  directory names the repair already walks, with VCS and URL sources taken from `direct_url.json`
  (PEP 610), which carries the resolved `commit_id`.
- `python`: the interpreter version from the environment's `pyvenv.cfg`.
- `entrypoints`: one name per line.

The wrapper writes a record by temp file and `mv` when `uv tool install` or `uv tool upgrade` exits 0,
and deletes it when `uv tool uninstall` does. The intercept already exists: `uv tool` runs to
completion and then syncs the trampolines (`bin/uv-manager:1687`).

**Trampolines move to `${XDG_DATA_HOME}/uvm/bin` and are generated from the records.** The modulefile
prepends that directory in place of `$UVM_ROOT/bin`. A purge can no longer remove a trampoline, and a
sync no longer deletes one because its shim went. The trampoline finds the tree from `$UVM_ROOT` at
exec time, since it no longer sits inside it the way `$0/..` assumes today. During migration the
generator takes the union of records and surviving shims.

**The trampoline has three paths.** With `UVM_REPAIR` unset and the shim executable, it execs the shim
and nothing else, as on 0.7.0. With `UVM_REPAIR` set, it execs the wrapper's internal entry with the
tool name; the wrapper runs the scope check a `uvx` call runs and then execs the shim. Parity holds by
construction because it is the same code path, and the cost is one wrapper invocation, about 12 ms
(`spec/purge-resilient-run/PLAN.md`), which the `uvx` route already pays. When the shim is missing or
not executable, the trampoline enters the wrapper either way: with the knob set, the wrapper restores
that tool from its record under the repair lock and execs it; without it, it prints the restore
command and points at `uv-manager doctor`, in place of the "another architecture" text when a record
exists.

**Restore is a replay of the record.** `uv tool install --force --no-cache -c constraints.txt <argv>`,
run from `/` in a subshell like the existing arms. `--force` gets past an orphaned shim, which
otherwise exits 2, and `--no-cache` because the cache sits on the purged filesystem and uv does not
check its unpacked archives (04 §1). The pins come from the record, so the invariant that a repair
changes no resolution holds, and git-sourced tools become repairable.

**The existing walk and doctor read the records.** The classes the walk fails on today (receipt gone,
directory gone, git or URL source) become restorable, and a distribution removed with its dist-info
has ground truth in `constraints.txt`. Doctor reports recorded-but-absent tools as repairable,
backfills records for installed tools that have none (every 0.7.0 install), pinned to what is
installed now, and regenerates missing trampolines.

## Proposed non-goals

- A purged trampoline as a failure class. It is moot once trampolines live in home, and doctor
  regenerates them from the records.
- Damage inside uv's cache, which is [`uv-cache-purge-damage`](uv-cache-purge-damage.md).
- A hand-edited manifest. The records belong to the wrapper; a user changes them through `uv tool`.
- Export and import of a tool set across clusters or sites, and any `uv-manager tool` subcommand
  family beyond the one internal entry the trampoline needs.
- Recording credentials. A replay authenticates through `uv.toml`, netrc or the environment, as the
  original install did.
- `uv run`, PEP 723 scripts and project `.venv` directories.

## Open questions for shaping

- Does `uv tool install -c` accept a direct-URL constraint for a VCS source, or must the replay
  rewrite the spec in `argv` to `@<commit_id>`? R1 answers it before anything else is firmed up.
- Which Python does a replay ask for: the request (`3.14`) or the recorded patch release? The first
  accepts patch drift after a purge; the second can fail where that patch is no longer offered.
- Outside a job the scope is the knob's literal value. A restore on a miss is driven by evidence, the
  missing shim, so it may need no scope record at all; the waiter's predicate would be "the shim is
  executable again". Decide, and decide how it composes with the predicate change
  [`repair-scope-queueing`](repair-scope-queueing.md) proposes.
- Where home is shared across clusters, a tool installed on one appears on `PATH` on the others and is
  restored lazily on first use there. That may be the feature or the surprise; it needs a ruling and
  possibly a gate.
- A tool called thousands of times in a job pays the wrapper on every call under the knob. Can the
  trampoline test the scope's repaired record in `sh` without duplicating `uvm_repair_encode` in a
  second language, as the platform key already is? Measure against the hot-path budget
  [`test-harness`](test-harness.md) carries as R7.

## Sketch of the acceptance criteria

- **R1** — A drive against real uv SHALL establish that replaying a record reproduces the tool's
  frozen set exactly, for an index source, a pinned `--with` and a git source, and SHALL record which
  form the VCS pin takes, before any other criterion is firmed up.
- **R2** — WHEN `uv tool install`, `uv tool upgrade` or `uv tool uninstall` exits 0 through the
  wrapper, the wrapper SHALL write, rewrite or delete that tool's record atomically, and SHALL change
  nothing under the records directory on a non-zero exit.
- **R3** — A record SHALL contain no credential: a drive installing from an index URL that carries a
  token SHALL find the token in no file under the records directory.
- **R4** — WHERE `UVM_REPAIR` is set, WHEN a tool installed with `uv tool install` is run by its own
  name, the call SHALL run the scope check a `uvx` call runs before the tool executes, and a
  multi-node `srun` of that tool SHALL repair once and run on every rank.
- **R5** — WHERE `UVM_REPAIR` is set, WHEN a recorded tool's directory, receipt or shim is missing, the
  next call by its name SHALL restore it from its record under the repair lock and then run it, with
  concurrent callers waiting rather than restoring, for git-sourced tools as for index-sourced ones.
- **R6** — WHILE `UVM_REPAIR` is unset, a healthy tool run by its own name SHALL exec its shim without
  entering the wrapper.
- **R7** — Trampolines SHALL be generated from the records and SHALL NOT be removed because a shim is
  missing. `uv-manager doctor` SHALL report a recorded-but-absent tool as repairable, backfill a record
  for an installed tool that has none, and regenerate a missing trampoline, while staying read-only on
  the scratch tree.
- **R8** — `README.md`, `uvm help` and the modulefile documentation SHALL state what the wrapper keeps
  in home and its size per tool, SHALL drop the advice to call `uvx <tool>` in a job script, and a
  *Design notes* entry SHALL record why what the user asked for lives in home.

## Notes

- Related: [`spec/purge-tree-repair/`](../spec/purge-tree-repair/GOAL.md), landed, whose repair this
  extends to the second workflow; [`repair-scope-queueing`](repair-scope-queueing.md), which amends the
  same waiter predicate; [`uv-cache-purge-damage`](uv-cache-purge-damage.md), the class left out here;
  [`test-harness`](test-harness.md), whose R7 budget the knob-set trampoline path spends against;
  [`uvm-bootstrap`](uvm-bootstrap.md), since moving trampolines to home changes what a bootstrap puts
  on `PATH`.
- Found by: the maintainer, dogfooding the deployed `uv/0.7.0` module on Gautschi, 2026-11-01.
