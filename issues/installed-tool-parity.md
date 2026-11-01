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
rank runs. That route stays supported. The workflow most users reach for first is a second one: they
run `uv tool install <spec>` on a login node, and later `srun <tool>` in a job. That second route gets
none of the guarantees.

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
0.21 s warm against 0.29 s unpinned. That is a trade the `uvx` route's users can make by pinning, not
a defect in it; it is one reason the installed route is worth a contract of its own.

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

Two job-script routes, both supported, with one repair contract: with `UVM_REPAIR` set, one call per
scope checks and repairs, the rest wait, and every rank runs.

| Route | Where its state lives | Who owns its purge cases |
|---|---|---|
| `srun uvx <spec>` | the ephemeral environment in `${UVM_ROOT}/<arch>/cache` | works on 0.7.0, except cache damage, which [`uv-cache-purge-damage`](uv-cache-purge-damage.md) closes |
| `uv tool install <spec>`, then `srun <tool>` | the record and trampoline in `$UVM_DATA`, the payload in `${UVM_ROOT}/<arch>/tools` | this cycle |

Neither route replaces the other, and the documentation presents both. After this cycle, `srun <tool>`
for an installed tool carries the guarantees `srun uvx <spec>` does. A tool whose whole directory,
receipt or shim the purge took comes back from a record the purge cannot reach, and a healthy tool
runs with no network fetch.

**The `UVM_DATA` contract.** `UVM_ROOT` names the scratch tree: the payload, which is large,
per-architecture and rebuildable. `UVM_DATA` names the durable tree: what the user asked for, which is
a few KB per tool, architecture-neutral, and rebuildable from nothing else, plus the trampolines
generated from it. Nothing large and nothing architecture-specific is written under `UVM_DATA`, so the
home-quota promise that motivated the wrapper holds. Today both kinds of state live on scratch, and
the receipt dies with the payload it describes.

Direction agreed with the maintainer in conversation on 2026-11-01. Appetite, non-goals and R-IDs are
not negotiated; that happens at promotion.

## Recommended design

These are the maintainer-endorsed choices to carry into shaping, not a contract.

**`UVM_DATA` is the durable root, set beside `UVM_ROOT`.** The modulefile sets it the way it sets
`UVM_ROOT`, so an operator reads the storage boundary in one place, and `module show uv` names both
trees. Where it is unset, which is the automation case the `UVM_ROOT` cascade exists for, the wrapper
defaults it to `${XDG_DATA_HOME:-$HOME/.local/share}/uvm`. Not `.../share/uv`: that is uv's own
default tool directory, and the README's verification step expects it absent (line 300). It is a
`UVM_*` name for the reason the README's design notes give: it is the wrapper's knob, not uv's. The
repository's bias against new knobs is answered by what this one carries, a second storage tree that
has to be visible where `UVM_ROOT` is. Home on Gautschi and Gilbreth is ZFS with snapshots, so there
the records are backed up as well as purge-proof.

The layout:

```
$UVM_DATA/                     durable, architecture-neutral, a few KB per tool
  bin/<entrypoint>             trampolines, generated from tools/
  tools/<name>/                one record per installed tool
$UVM_ROOT/<arch>/              scratch, rebuildable (unchanged)
  tools/  bin/shims/  python/  cache/  versions/
```

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

**Trampolines move to `$UVM_DATA/bin` and are generated from the records.** The modulefile prepends
that directory in place of `$UVM_ROOT/bin`. A purge can no longer remove a trampoline, and a
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

**`srun uvx <spec>` keeps its 0.7.0 behaviour.** This cycle changes nothing on the `uvx` path for a
tool that is not installed; that route's open case is cache damage, owned by
[`uv-cache-purge-damage`](uv-cache-purge-damage.md). Where `uvx <tool>` resolves to an installed
tool's environment, which uv documents it does unless a version is requested or `--isolated` is
passed, the scope check that call runs reads the same records, so the record-based restore covers it
too.

**The existing walk and doctor read the records.** The classes the walk fails on today (receipt gone,
directory gone, git or URL source) become restorable, and a distribution removed with its dist-info
has ground truth in `constraints.txt`. Doctor reports recorded-but-absent tools as repairable,
backfills records for installed tools that have none (every 0.7.0 install), pinned to what is
installed now, and regenerates missing trampolines.

## Proposed non-goals

- A purged trampoline as a failure class. It is moot once trampolines live in `UVM_DATA`, and doctor
  regenerates them from the records.
- Damage inside uv's cache, which is the `uvx` route's half of the contract and belongs to
  [`uv-cache-purge-damage`](uv-cache-purge-damage.md). Together the two cycles complete it.
- Any change to how `srun uvx <spec>` behaves for a tool that is not installed.
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
- Which forms of `uvx` resolve to an installed tool's environment: a bare name, `--from <spec>` naming
  the installed source, a git source whose package and command names differ. R1 records it, since it
  decides how far the restore reaches on the `uvx` route.
- Where `UVM_DATA` is shared across clusters, as a home directory can be, a tool installed on one
  appears on `PATH` on the others and is restored lazily on first use there. That may be the feature
  or the surprise; it needs a ruling and possibly a gate.
- A tool called thousands of times in a job pays the wrapper on every call under the knob. Can the
  trampoline test the scope's repaired record in `sh` without duplicating `uvm_repair_encode` in a
  second language, as the platform key already is? Measure against the hot-path budget
  [`test-harness`](test-harness.md) carries as R7.

## Sketch of the acceptance criteria

- **R1** — A drive against real uv SHALL establish that replaying a record reproduces the tool's
  frozen set exactly, for an index source, a pinned `--with` and a git source, and SHALL record which
  form the VCS pin takes and which `uvx` forms resolve to an installed tool, before any other
  criterion is firmed up.
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
- **R8** — `README.md`, `uvm help` and the modulefile documentation SHALL present `srun uvx <spec>` and
  `srun <tool>` as supported job-script routes under one repair contract, SHALL state what the
  wrapper keeps under `UVM_DATA` and its size per tool, SHALL drop only the statement that a tool run
  by its own name skips the check, and a *Design notes* entry SHALL record why what the user asked for
  lives outside the scratch tree.
- **R9** — The modulefile SHALL set `UVM_DATA` and put `$UVM_DATA/bin` on `PATH`. WHERE `UVM_DATA` is
  unset, the wrapper SHALL use `${XDG_DATA_HOME:-$HOME/.local/share}/uvm`. The wrapper SHALL write
  under `UVM_DATA` only records and trampolines, none of them architecture-specific.
- **R10** — `srun uvx <spec>` for a tool that is not installed SHALL behave as on 0.7.0: the same
  scope check, the same exit statuses, and no record written.

## Notes

- Related: [`spec/purge-tree-repair/`](../spec/purge-tree-repair/GOAL.md), landed, whose repair this
  extends to the second workflow; [`repair-scope-queueing`](repair-scope-queueing.md), which amends the
  same waiter predicate; [`uv-cache-purge-damage`](uv-cache-purge-damage.md), which completes the
  `uvx` route's half of the same contract; [`test-harness`](test-harness.md), whose R7 budget the
  knob-set trampoline path spends against; [`uvm-bootstrap`](uvm-bootstrap.md), since moving
  trampolines to `UVM_DATA` changes what a bootstrap puts on `PATH`.
- Found by: the maintainer, dogfooding the deployed `uv/0.7.0` module on Gautschi, 2026-11-01.
