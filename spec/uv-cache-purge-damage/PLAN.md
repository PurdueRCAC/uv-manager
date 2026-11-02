# PLAN — A purge that damages uv's cache is repaired under `UVM_REPAIR`

> **Status:** Draft for the plan gate · **Last updated:** 2026-11-01
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/). Every
> design element traces to a GOAL R-ID. Base: `release/0.8.0` at `8e03774`, wherever this file or
> the skill says `main`.

## 1. Summary

`uvm_detect` gains a walk of the cache's live entries, so doctor reports a damaged script
environment, cached `uvx` environment or unpacked wheel by its path, and the repair's holder sees
the same findings. `uvm_repair_run` gains a last arm, after the interpreter, restore and tool arms
and under the same contract: an environment that still has `pyvenv.cfg` and a running interpreter
is reinstalled in place with every distribution pinned, from `/` and with no cache, which leaves
the entry where it was, a running process importing, and the waiters nothing to rebuild; every other
damaged entry is removed for uv to rebuild from the next call's own script or spec. `tests/repair-race.sh`
gains `U`, `S` and `ukill` on a cache shaped like a user's. Four phases, each gate run green on a
throwaway prototype: detection (P1), the repair (P2), waiters, the local drive and the surfaces
(P3), the cross-node drive (P4).

## 2. Design

### What is removed

- **The concession**, `README.md:673`: "Damage inside uv's cache is not checked or repaired. That
  cache holds the environment of a script with inline dependencies, so `uv run <script>` can still
  fail on a cache the repair never touches." (R8)
- **The early return that ends the walk after the tool arm**, `(( ${#inplace[@]} > 0 )) || return
  0` in `uvm_repair_run`, which would skip any arm appended after it. The tool arm becomes a guarded
  block, unchanged inside.
- **Damaged entries of the cache, by the repair**, the first thing the wrapper removes under
  `UV_CACHE_DIR` other than `uvm clean cache`: a cached environment's link, a script environment
  without `pyvenv.cfg` or interpreter, an unpacked wheel's pointer and link (M2, M3).

### `bin/uv-manager`, function by function

**`uvm_detect_cache`** (new, called last in `uvm_detect`). Sets `uvm_cache_findings`,
`uvm_cache_problems`, `uvm_cache_fix` (entries for the in-place arm) and `uvm_cache_drop`
(entries to remove), each item `KIND:PATH` with `KIND` one of `script`, `link`, `wheel`. Returns
at once when `${uvm_root}/cache` is absent.

- For each `cache/environments-v2/*/` that is a directory and not a link: holding `lib/`, `bin/` or
  `pyvenv.cfg`, it is a script environment; otherwise each child that is a link to a directory is a
  cached environment. The glob skips dot names, which is where a removed script environment waits.
- For each `cache/wheels-v*` bucket, one `find "${bucket}" -type l` lists the wheel links at any
  depth without following them; each that resolves to a directory is an unpacked wheel. Read with a
  here-string, as doctor already reads its lists.
- `uvm_cache_entry KIND PATH` checks one entry, walking through the link: an environment needs
  `pyvenv.cfg`; then each `lib/*/site-packages/*.dist-info` (a wheel: each `*.dist-info` at its root,
  and at least one) needs `RECORD` and `METADATA`, and every path `RECORD` lists, absolute ones
  aside, must exist (`-e` or `-L`). The `RECORD` loop is the tools walk's, with its trailing-line
  guard and quote stripping, except that `../` paths are walked, because a console script is listed
  as `../../../bin/<name>`. The first problem ends the entry's check: one FAIL per entry.
- The FAIL line is `FAIL  cache entry <path> is damaged (<why>, partial purge)`, `<why>` one of
  `it has no pyvenv.cfg`, `<dist> has no RECORD manifest`, `<dist> has no METADATA`, `<dist> is
  missing N of M files`, `it has no dist-info directory`. A wheel, or an environment without
  `pyvenv.cfg`, goes on `uvm_cache_drop`; any other damaged environment on `uvm_cache_fix`.
- Builtins only apart from the `find`, one fork per bucket per walk. Nothing is written: the walk
  reads `RECORD` and tests paths.

**`uvm_detect`**. Calls `uvm_detect_cache` after the interpreter probe and appends its findings
and count, as it does the records'. Nothing else changes.

**`uvm_repair_run`** (high-risk, through `uvm_repair`). The tool arm loses its early return; the
function ends `uvm_repair_cache; return 0`. Its header comment names the fourth arm.

**`uvm_repair_cache`** (new, the last arm). Re-partitions after the interpreter arm has run: an
entry on `uvm_cache_fix` without `pyvenv.cfg` or an executable `bin/python` now, or a cached
environment (`link`) any of whose dist-info directories holds `direct_url.json`, moves to the
removal list. Then one note, `repairing the cache for <arch>: <n> environment(s) in place, <m>
entry(ies) removed`, and:

1. **Removals first**, so a script environment without `pyvenv.cfg` is gone before the arm's first
   uv call (M3).
   - `link`: `rm -f -- <link>`. The archive stays for any process using it and for `uv cache prune`.
   - `script`: `mv -- <dir> <parent>/.<name>.<host>.<pid>.<random>`, built as §9 builds temporary
     names, then `rm -rf` of that. A failed `mv` is the scope's failure; a failed `rm -rf` notes
     `left <aside> behind; uv cache prune removes it` and goes on, since uv no longer sees the entry.
   - `wheel`: `rm -f` of every `<link>.*` but `<link>.lock` (uv's archive pointer is `<link>.http`;
     its flock file stays), then of the link. Removing the link alone was measured to leave the
     damage in use while the walk stops seeing it (research 01, D6).
   - A failure sets `uvm_repair_reason="cannot remove the cache entry <path>: <rm's or mv's
     message>"` and returns.
2. **Reinstalls**, one per environment on the final fix list: `out=$(uvm_record_constraints
   <entry>)`, a failure there setting `the cache environment <entry> holds a distribution whose
   source is not recorded`; then `(cd / && exec "${real_uv}" pip install --python <entry>/bin/python
   --reinstall --no-cache <pins>) >&2`, a failure setting `the cache environment repair failed for
   <entry>`. `uvm_record_constraints` already pins a distribution with `direct_url.json` to its URL,
   VCS commit and subdirectory, and globs the layout cache environments share with tools.

All of it to stderr. No message names `pip install`, `python install` or `tool upgrade` (the
fixture's counters).

**`uvm_doctor`**. When `uvm_cache_problems > 0`, the command block gains `    uv-manager clean
cache --yes` and a paragraph: the clean command removes the whole cache, which uv rebuilds as it
needs it; `uv cache clean <package>` leaves the environments built from a damaged wheel, and `uv
cache prune` the wheel they rebuild from, so neither alone clears it; a knob-set call repairs it in
place. Doctor still writes nothing under `UVM_ROOT`: the walk only reads.

**`uvm_help`**. `UVM_REPAIR`'s text names uv's cache: the environments `uv run <script>` and `uvx
<spec>` run from, and the wheels they are built from.

**Unchanged:** the dispatch tail, `uvm_repair` (its lock, outcome and failure contract), the
interpreter, restore and tool arms (R7), `uvm_tool_entry`, `uvm_restore_by_name`, the trampolines,
`uvm_set_paths`, `uvm_export_env`. An installed tool run by its own name with the knob set reaches
the same `uvm_repair`, so its scope check covers the cache too.

### State tree afterwards

```
$UVM_ROOT/<arch>/cache/
├── environments-v2/
│   ├── <script>-<hash>/            reinstalled in place, or gone and rebuilt by the next uv run
│   ├── .<script>-<hash>.<host>.<pid>.<random>/   only if rm -rf failed; uv cache prune removes it
│   └── <interp-hash>/<res-hash>    link reinstalled through in place, or removed
├── wheels-v7/<source>/…/<name>/<ver>-<tag>[.http|.msgpack|.lock]   damaged: all but .lock removed
└── archive-v0/<id>/                 never removed by the repair; unreached ones are prune's
```

### User-facing surface (same-commit rule)

| Surface | Phase | What changes |
|---|---|---|
| `README.md` | P1 | mitigation 2: doctor checks the cache's live entries, by what it reads; the concession at `:673` says doctor reports cache damage (the repair follows in P2) |
| | P2 | *Repairing inside a job*, *What happens*: the cache arm last, what is reinstalled in place and what is removed; the concession goes, replaced by what is repaired; *Network*: the reinstall downloads each damaged environment's distributions |
| | P3 | the purge table's row `**Files inside uv's cache**`; *What it catches*: what the walk leaves unseen (an environment's dist-info directory removed whole, packages a pyvenv-less run already put into a managed interpreter, `UV_LINK_MODE=symlink`, and, beyond R8's list, wheels uv built from source distributions, which are not live entries); the manual remedy, `uv-manager clean cache --yes`, and that `uv cache clean <package>` or `uv cache prune` alone leaves the failure; the classes the repair removes and that the next call on each node rebuilds each concurrently where `flock` is node-local and uv fails outright where `flock` is absent (R5); *Many jobs at once* with the local walk cost per `RECORD` line |
| | P4 Run B | *Many jobs at once*: the walk seconds R6 recorded on Lustre, beside its file and entry counts |
| `uvm_help` | P2 | `UVM_REPAIR` names uv's cache |
| `etc/uv-manager.conf.example` | P2 | the repair paragraph names uv's cache, `uv run <script>` and `uvx <spec>` |
| `share/modulefiles/uv/main.lua` | P2 | the `UVM_REPAIR` help names uv's cache, `uv run <script>` and `uvx <spec>` |
| `AGENTS.md` § *Invariants* + `invariants.md` | P2 | §8: the cache arm sits last, reinstalls in place what has `pyvenv.cfg` and an interpreter and removes the rest, from `/`, `--no-cache`, pins from the dist-info names and `direct_url.json`; doctor's walk of the cache reads only |
| `AGENTS.md` `tests/` paragraph | P3, P4 | the cache scenarios (P3); the flock probe (P4) |

### Requirement → design map

| R-ID | Design element(s) | Phase |
|------|-------------------|-------|
| R1 | the shaping drives re-run at `8e03774` as the baseline ([research 01](research/01-cache-walk.md)); the failing shapes are exactly the set P1 and P2's gates damage; R6's `link_mode` key | P1 (baseline), P4 (link mode) |
| R2 | `uvm_detect_cache` and `uvm_cache_entry` in `uvm_detect`; the FAIL line; links walked, unreached archives never; reads only | P1 |
| R3 | `uvm_repair_cache` after the other arms under `uvm_repair`'s unchanged lock, scope and outcome contract; pins from `uvm_record_constraints`; `--no-cache`; from `/`; removals before reinstalls; a pyvenv-less script environment removed before any uv call; reasons naming the entry | P2 |
| R4 | in-place reinstall rewrites files under a running process's paths; removal only of a link (the archive kept), or of a script environment that no process can use safely (M2) | P2 |
| R5 | in place leaves nothing to rebuild (`rebuilt=0` at 16 ranks); the removal classes and their per-node rebuild in `README.md` | P3 |
| R6 | `U`, `S`, `ukill`; the realistic cache; keys `walk_s`, `cache_files`, `live_entries`, `link_mode`, `flock`, `rebuilt`; two generic jobs | P3 (scenarios), P4 (flock probe, jobs, evidence) |
| R7 | the walk only inside `uvm_detect`, which only doctor and the lock holder run; the other arms untouched; `F`, `T`, `P`, `kill` re-run; the unset path timed against `8e03774` | P3 (gate) |
| R8 | the surface table above | P1-P3 (text), P3 (census), P4 Run B (walk figure) |

## 3. Invariant gate (AGENTS.md constitution check)

Walked against [`invariants.md`](../../.agents/factory/invariants.md) before research and again
after every gate went green on the prototype.

- **§1 Architecture.** Untouched. The cache is already `${UVM_ROOT}/<arch>/cache`, set on the node.
- **§2 Process semantics.** Honored. The repair runs before the `exec` as now; uv's exit status and
  signals are still the command's.
- **§3, §4, §6.** Untouched: the arm never calls `uvm_install` and cannot move `current`.
- **§5 Locks.** Contract unchanged and no new caller of `uvm_acquire_lock`. The arm runs inside the
  holder's `uvm_repair_run`; a killed holder leaves its lock exactly as now (`ukill`). Two locks are
  never held together: `uvm_install` has released before `uvm_repair` acquires.
- **§7 Output.** Findings, notes and uv's own output go to stderr; P2's gate compares stdout
  exactly.
- **§8 Environment.** Honored and extended (same commit as P2's code). The repair restores what is
  installed and changes no resolution: every distribution is pinned to its dist-info version or its
  recorded source, from `/` in a subshell, under the user's `uv.toml` and `UV_*`, with `--no-cache`;
  `--python` names the environment's own interpreter and is used only where `pyvenv.cfg` is present,
  so nothing installs into a managed interpreter's `site-packages`. Doctor writes nothing under
  `UVM_ROOT`: the walk reads `RECORD` and tests paths, and P1's gate lists the tree before and after.
  `uvm_set_paths` stays pure. No variable is added.
- **§9 Trampolines.** Untouched. The aside name follows §9's temporary-name rule.
- **§10 Portability.** Every idiom ran under bash 3.2 (`bash -n` and the drives on macOS). Knob off
  forks nothing and touches no file: the walk is reachable only from doctor and from
  `uvm_repair_run`, which runs after the outcome test and after the lock is won. The `find` is one
  fork per bucket inside that walk, off the hot path. Empty arrays use `${a[@]+"${a[@]}"}`.
- **§11 Argument inspection.** Untouched. The pins come from the entry on disk, never from the
  user's command, so the wrapper never finds the script or spec (the GOAL's non-goal).
- **§12 Conventions.** Same-commit rule per the surface table; no spec ids in the script or README;
  the version stays where `/uvm-release` leaves it.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| **1.** The repair removes entries under `UV_CACHE_DIR` (a link, a script environment, a wheel's pointer files), where every other arm only reinstalls | M2 and M3: a pyvenv-less environment cannot be reinstalled safely, and an entry uv rebuilds from the next call's own spec needs no human | Refusing such an entry, as the tool arm refuses a pyvenv-less tool, fails every call in the scope over state uv rebuilds unaided (M3's asymmetry). Reinstalling every environment in place cannot reach one without `pyvenv.cfg` or `bin/python`. |
| **2.** The wheel removal reads uv's cache bookkeeping: it removes the `<link>.*` siblings, of which uv 0.13.6 follows `.http` | Removing only the link was measured to keep the damaged archive in use and hide it from the walk, a false clean | Removing the archive directory is a tree removal that can fail halfway, and would break a running process in a `UV_LINK_MODE=symlink` environment. Naming `.http` alone breaks silently on a uv that renames its pointer; the sibling glob does not. |
| **3.** The walk forks `find` once per `wheels-v*` bucket | A wheel's link sits 3, 4 or 5 levels down by source | Globs at fixed depths either miss a source or descend through the pypi links into every archive. The fork is off the hot path, once per scope. |
| **4.** Gates committed as scripts under `spec/uv-cache-purge-damage/gates/`, as the previous cycle did (its deviation 5) | P2's drive is about 160 lines of `sh` | Inline YAML literal blocks of that length are unreviewable, and a failing line number in one means nothing. |

## 4. Rabbit holes (resolved)

The fan-out was narrowed to three sequential briefs run by the planner (high-risk exception,
narrowed): each needed a seeded real-uv sandbox and the previous answer, and shaping had measured R1.

- **What is a live entry, and how deep are wheels?** Script directories, interpreter-hash
  directories of links, wheel links at depth 3-5. ([01](research/01-cache-walk.md))
- **Does `RECORD` list `bin/` executables?** Yes, as `../../../bin/<name>`; the walk follows `..`.
  ([01](research/01-cache-walk.md))
- **Which name does uv follow to an unpacked wheel?** The `.http` pointer. The design's first draft
  removed the link and would have been a false clean. ([01](research/01-cache-walk.md))
- **Does `uv cache prune` collect what the repair leaves?** Dot-named `environments-v2` entries and
  unreached archives, yes. ([01](research/01-cache-walk.md))
- **Does the in-place reinstall restore every R1 failing shape, keep the listing and rebuild
  nothing?** Yes, script and `uvx` environments, ruff's binary and `RECORD` included, under default
  and hardlink link modes. ([02](research/02-repair.md))
- **R4?** Three running processes per shape import after the repair. ([02](research/02-repair.md))
- **R5 at 16 ranks?** `rebuilt=0` for `U` and `S`. ([02](research/02-repair.md))
- **Walk cost?** 55 µs per `RECORD` line on APFS; a metadata round trip each on Lustre.
  ([01](research/01-cache-walk.md))
- **`flock` across nodes, as a fixed word (M4)?** A two-rank probe with `flock -n -E 75`.
  ([03](research/03-cluster-drive.md))

## 5. Risks & open questions

**Drift since shaping** (GOAL citations against `8e03774`):

- `uvm_detect` is now `bin/uv-manager:1612-1777`, not `:935-1086`, and `uvm_detect_records`
  (`:1570`) runs first in it; the cache walk goes last, beside it, as the brief asked.
- The concession is `README.md:673`, not `:540` (R8's grep still finds exactly one hit).
- `UV_LINK_MODE` is at `etc/uv-manager.conf.example:177`, not `:156`, still commented.
- `uvm_repair_run` now runs interpreters, restore, in-place tools; the tool arm's early return is
  removed (§2) so the cache arm can follow.
- Doctor now backfills only where `tools/.lock` exists and writes nothing under `UVM_ROOT`; the
  walk keeps that.
- An installed tool run by its own name reaches `uvm_repair` through `uvm_tool_entry`, so that route
  repairs the cache too. Nothing in the GOAL forbids it; the README's *Reach* says so.
- `tests/repair-race.sh` has `I` and `ikill`; `U`, `S` and `ukill` sit beside them.
- R7's "as on `release/0.8.0`" now means `8e03774`. Its `F` and `T` observations were re-run by
  P3's gate on the prototype: both green.

**Open questions for the foreman's gate:**

1. **Cached environments from a URL, git or a path are removed, not reinstalled.** A `uvx` or `uv
   run --with` environment holding a distribution with `direct_url.json` loses its link and is
   rebuilt by the next call from its own spec, which keeps a `--with-editable` editable. It is a
   removal class under M2 ("a uvx environment's link") and R5's README covers it. A script
   environment with such a distribution is reinstalled in place with its source pinned.
2. **Wheels uv built from a source distribution** (`sdists-v*`) are outside the GOAL's definition of
   a live entry, so neither walked nor repaired, though a purge can damage one and an environment
   built from it inherits the damage. The plan lists them in the README beside R8's three unseen
   classes. Widening the walk is a follow-up seed if wanted.
3. **R6's `walk_s` is doctor's wall time on the damaged tree**, the holder's walk plus doctor's
   interpreter probe (about 0.15 s), measured before the pass rather than inside the holder, which
   prints no timing. `link_mode` cannot tell `copy` from `clone`, so it reports `copy-or-clone`.
4. **R2 beyond its letter:** an unpacked wheel with no dist-info directory at all is a FAIL. A
   healthy wheel always has one.
5. **The unset path's timing** is gated as the fastest of three alternating 400-call rounds against
   `8e03774`, within 1 s. On the prototype both sides took 6 s.

None of these departs from the GOAL in substance; no criterion was found unbuildable.

**Risks:**

- **P2 is the schedule's risk and the review's.** It touches `uvm_repair_run`, a high-blast-radius
  region, adds the first removals any arm makes, and every review of the last two cycles found
  defects in states the gates had not driven. The gate drives each failure state listed in
  [research 02](research/02-repair.md); a reviewer will look for more (a rename across a quota, a
  wheel shared by two damaged environments, a concurrent `uv cache prune` from another job).
- **M1 on the cluster.** The R6 cache walks in an estimated 0.5-1.5 s on Lustre. A user's cache of
  large stacks can pass 30 s; if R6's figure does, that is a review finding, and M1's narrowing
  (dist-info and `pyvenv.cfg` tests only) is a P2 change within the cycle, not a fifth phase.
- **uv's cache layout is uv's.** The bucket names (`environments-v2`, `wheels-v*`) and the pointer
  beside the link were read from uv 0.13.6. A uv that renames a bucket makes the walk see less,
  never repair wrong; one that moves the pointer elsewhere than `<link>.*` makes the wheel removal a
  false clean, which P2's wheel shapes catch at the pinned uv.
- **A `ukill` kill that lands after the reinstall** makes the clean pass find nothing. The killed
  pass asserts `restored=0`, so that reads as a fault not constructed. Locally the walk alone gave
  0.2 s of margin against a 0.1 s poll; on Lustre it is longer.
- **Network in the gates.** P1-P4's local halves need `pypi.org`, `files.pythonhosted.org` and
  `releases.astral.sh`. A red whose stderr is uv's network error is the environment, not an attempt.
- **Only a cluster can confirm** R6: the walk's seconds on Lustre, `flock`'s coherence across nodes,
  the group kill under `srun`, and that no rank on either node rebuilds what the holder restored.

**Cluster evidence** ([`evidence/lustre.txt`](evidence/lustre.txt), at `fc7184f`, the run of
record): a second Lustre scratch, 2 nodes × 64 ranks, `tests/repair-race.sh --large-cache`,
uv 0.13.6, bash 4.4. Each scenario's cache held `cache_files=41073`, `live_entries=153` and
`record_lines=40215`, with `link_mode=hardlink` and `flock=coherent`. The first cluster was out of
service for the final runs, so the run of record moved to a second Lustre scratch.

| Scenario | `walk_s` | `hold_s` | `wait_max_s` | Outcome |
|---|---|---|---|---|
| U | 2.90 | 3 | 5 | `rc_hist=0:128`, one repair, `rebuilt=0`, no lock left |
| S | 4.37 | 4 | 4 | `rc_hist=0:128`, one repair, `rebuilt=0`, no lock left |
| ukill | 2.52 | killed; clean pass 3 | 61; clean pass 4 | 127 waiters named the lock at 61 s, `locks_left=1`, doctor's WARN; clean pass `rc_hist=0:128`, one repair, `clean_rebuilt=0` |

Earlier runs of the same drive, kept as history:

- `312b6f7`, the walk testing every path a `RECORD` lists: `walk_s` 51.66, 94.74 and 108.01, past
  M1's 30 s.
- `729080d`, ruling 5b's listing walk: `walk_s` 2.6-4.7 s, under M1's line, so the check is not
  narrowed.
- `e25d773`, review cycle 2's remediation, on the first Lustre scratch with bash 5.1: `walk_s` 1.93,
  1.85 and 2.72; S's hold fell from 24 s to 3 s once only damaged distributions were reinstalled.
- `3a9ac04`, review cycle 3's remediation, on the first Lustre scratch: `walk_s` 1.94, 1.87 and
  2.01, holds 3, 3 and a clean-pass 6 s.
- `e61e360`, review cycle 4's remediation, on the second Lustre scratch with bash 4.4: `walk_s`
  2.73, 2.78 and 2.65, holds 3, 3 and a clean-pass 11 s.

## 6. Verification strategy

Every gate is a script in [`gates/`](gates/), run from the repository root under `/bin/sh`, sharing
[`gates/lib.sh`](gates/lib.sh), with `UV_CACHE_DIR` and `UV_TOOL_DIR` exported to scratch for
`lint.sh` and a real uv first on `PATH`. Each ran green on a throwaway prototype of its phase, built
cumulatively in a copy outside the working tree, and red against its predecessor's state on its
own first post-condition:

| Gate | Red before its phase | Green on the prototype |
|---|---|---|
| `p1.sh` | HEAD: `FAIL: R2: module on script: doctor exits 0` | `P1 ok`, 37 s |
| `p2.sh` | after P1: `FAIL: R3: module on script: rc 1`; HEAD: `P1 has not landed` | `P2 ok`, 70 s |
| `p3.sh` | after P2: `repair-race U x16` (usage: no scenario `U`) | drive half green (`U`, `S`, `ukill`, `F`, `T`, `P`, `kill`, 2 min 25 s); timing and census green once stand-in text was in each surface |
| `p4.sh` | before Run A: `P4 Run A has not landed`; after Run A: only `cluster evidence … not recorded yet` | local half green; evidence half green on the local summaries scaled to 128 ranks and 2 nodes, red at `clean_repairs=2` when that key is broken |

Per R-ID, the post-condition each gate asserts:

- **R1** (P1, P2): the shapes damaged are R1's *fail* and *wrong* rows; the baseline's outputs are
  in `research/drives/shaping-*.out`. `p4.sh`: `link_mode` is a fixed word in each cluster summary.
- **R2** (`p1.sh`): healthy cache rc 0, no FAIL; for each of 23 shape-and-entry pairs (script and
  `uvx` environments: module, dist-info files, `RECORD`, `METADATA`, every third file,
  `pyvenv.cfg`; flake8: module, dist-info files, `pyvenv.cfg`; ruff: `bin/ruff`, `RECORD`; the
  wheel: module, dist-info files, `RECORD`, `METADATA`, every third file, every file) doctor rc 1
  and `FAIL  cache entry <path> ` naming the entry; on a damaged tree, the listing of `UVM_ROOT`
  (type, size, path) identical after doctor and nothing newer than a marker; an archive whose link
  is gone, every file removed, gives rc 0 and is not named.
- **R3** (`p2.sh`): a healthy scope runs no cache repair and records ok; for 21 shape-and-entry
  pairs, the knob-set call exits 0 with its exact output and one repair line, the managed
  interpreter's `site-packages` listing is unchanged, the dist-info listing equals the one before,
  in-place shapes keep the entry and add no archive or link, a second call prints no repair line,
  and doctor reports nothing; a damaged wheel's new script runs; a `uv.toml` in the working
  directory is not applied; doctor first, then one repair, and doctor names `uv-manager clean cache
  --yes`; 8 concurrent first calls, one repair, all 0; `UV_OFFLINE=1` fails 4 concurrent calls naming
  the entry, with a failed record; read-only parents fail a `uvx` link, a wheel and a pyvenv-less
  script environment naming the entry, leaving it, and the base `site-packages` unchanged; an
  aside `rm -rf` cannot finish runs the call and notes it; under `UV_LINK_MODE=hardlink` (inodes
  checked) the repair leaves doctor clean.
- **R4** (`p2.sh`): for module and dist-info-files shapes, three sleeping processes (script
  environment, `uvx` link path, `uvx` archive path) import `tqdm.contrib.logging` after the repair.
- **R5** (`p3.sh`): `U` ×16, `S` ×16, `ukill` ×8 with `rebuilt=0` (the clean pass's for `ukill`).
  Inspection-only: the README's removal classes and their per-node rebuild sentence, since no
  fixed string can tell that paragraph from the README's other uses of "node-local".
- **R6** (`p3.sh`, `p4.sh`): the keys in every local summary, `live_entries` ≥ 22, no `/` in a
  summary; on the evidence, all three scenarios with `ranks=128`, `nodes=2`, `exit=0`,
  `progress=ok`, every count above, `flock` one of three words.
- **R7** (`p3.sh`): `F` ×16, `T` ×8, `P` ×8, `kill` ×8 exit 0; the unset path within 1 s of
  `8e03774`'s. Inspection-only: the walk sits behind the knob and the lock.
- **R8** (`p3.sh`): the concession's grep returns nothing; `uv's cache` in `README.md`, the conf
  example, the modulefile and `uvm help`; the purge-table row `| **Files inside uv's cache** |`;
  `UV_LINK_MODE=symlink`, `uv cache clean <package>` and `uv-manager clean cache` in the README;
  `ukill` in `AGENTS.md`. Inspection-only: each surface against R8's list, the unseen classes, and
  (Run B) *Many jobs at once* against the evidence's `walk_s`.

### Release note

For the foreman to carry into the 0.8.0 notes, if wanted:

> `UVM_REPAIR` and `uv-manager doctor` now also check uv's cache: the environments `uv run
> <script>` and `uvx <spec>` run from, and the wheels they are built from, against the files each
> `RECORD` lists. A damaged script environment is reinstalled in place, with the exceptions the
> README names; a damaged cached `uvx` or `uv run --with` environment whose sources cannot all be
> shown to come from the configured index loses its link and is rebuilt by the next call, as is a
> damaged wheel. The check costs one listing of the cache's live entries per scope: 2.5-4.4 s on a
> Lustre scratch for a cache of 40,000 `RECORD` lines.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
