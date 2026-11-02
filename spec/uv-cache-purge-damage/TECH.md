---
slug: uv-cache-purge-damage
title: A purge that damages uv's cache is repaired under UVM_REPAIR
kind: feature
appetite: big
status: done
branch: feature/uv-cache-purge-damage
base: release/0.8.0
current_phase: done
last_updated: '2026-11-02'
phases:
- id: P1
  name: 'Detection: doctor walks the cache''s live entries'
  status: done
  satisfies:
  - R1
  - R2
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/uv-cache-purge-damage/gates/p1.sh
- id: P2
  name: 'The repair: in place where it can be, removed where it cannot'
  status: done
  satisfies:
  - R3
  - R4
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/uv-cache-purge-damage/gates/p2.sh
- id: P3
  name: Waiters, the local race drive and the surfaces
  status: done
  satisfies:
  - R5
  - R7
  - R8
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: sh spec/uv-cache-purge-damage/gates/p3.sh
- id: P4
  name: Cross-node drive on Lustre
  status: done
  satisfies:
  - R1
  - R6
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: downhill
  verify: sh spec/uv-cache-purge-damage/gates/p4.sh
review:
  last_reviewed_commit: e61e360
  verdict: changes-requested
  blocked_reason: ''
  cycle: 5
---
# TECH.md — A purge that damages uv's cache is repaired under `UVM_REPAIR`

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/uv-cache-purge-damage/TECH.md`); the per-phase
checklists below are the work. `uvm-build` executes the next actionable phase, runs its `verify:`
command, updates state via `uv run .agents/factory/bin/set_phase.py …`, and makes one atomic
code-plus-state commit.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md). R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md). Base is `release/0.8.0` (`8e03774`), wherever a
  skill says `main`.
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs 01-03, and the
  throwaway prototype every gate went green on, [`research/drives/prototype.diff`](research/drives/prototype.diff).
  The prototype is evidence that the design builds, not code to paste: its comments are not this
  repository's voice and the review has not seen it.

## Frontmatter field reference

See [`templates/TECH.md`](../../.agents/factory/templates/TECH.md). Every phase is `parallel:
false` (one source file) and `hammerable: false`: M5 caps the cycle at these four, and each carries
a criterion the GOAL does not let move to a follow-up.

## Gate notes (read before retuning any gate)

Each `verify:` runs one script in [`gates/`](gates/) from the repository root under `/bin/sh`. The
scripts share [`gates/lib.sh`](gates/lib.sh): `run`, `fail`, `seed`, `script`, `subjects` (the
two script and three `uvx` environments and their wheels, kept as `$golden`), `restore`, `senv`,
`xlink`, `wlink`, `real`, `files`, `nth`, `purge`, `distinfo`, `base_sp`, `treelist`, `knob`,
`call`, `expect`. Every gate was run green on a throwaway prototype and red against its
predecessor's state (PLAN §6). A retune keeps these:

- **`lint.sh` needs scratch caches**: export `UV_CACHE_DIR` and `UV_TOOL_DIR` to a scratch directory
  before any gate.
- **Real uv comes from `command -v uv`** outside `temp_root.sh`, passed in as `SEED_UV` and copied
  into `versions/<ver>/` by `seed` (`tests/repair-race.sh --uv-bin` for the race drives). This is a
  harness step, never product code; the cluster drive provisions through the installer. A gate
  refuses a `uv` that is this checkout's own `bin/uv`.
- **The gates need network**: `pypi.org`, `files.pythonhosted.org` and `releases.astral.sh`. A red
  whose stderr is uv's own network error is the environment, not the code: do not
  `--record-attempt` it; re-run.
- **The damage is a purge's shape**: files and links unlinked, directories kept (`purge` reads paths
  on stdin). No `rm` inside a drive; a removed link goes to `$trash` with `mv`.
- **No `VAR=x` in front of a shell function**: POSIX `sh` keeps the assignment. `knob` sets
  `UVM_REPAIR` in a subshell around the call, and `UV_OFFLINE` and `UV_LINK_MODE` are exported in a
  subshell or for the rest of the drive.
- **No bare `wait`**; wait on the named pids. A background process started inside `$(…)` is not this
  shell's child, so the R4 sleepers start in the drive's own shell and read `$!`.
- **Messages the gates count.** The cache arm's one note starts `repairing the cache for`, which
  `tests/repair-race.sh` counts under `uv-manager: repairing the ` and P2 under `uv-manager:
  repairing the cache`. The removal failure says `cannot remove the cache entry <path>`, the
  reinstall failure `the cache environment repair failed for <path>`, the leftover aside `uv cache
  prune removes it`, and doctor's FAIL `FAIL  cache entry <path> is damaged (`. No message on the
  `uv`, `uvx` or trampoline path names `pip install`, `python install` or `tool upgrade`.
- **The R7 timing** compares each side's fastest of three alternating 400-call rounds against
  `8e03774`, within 1 s. A red there on a loaded machine is re-run once before it counts.
- **`ukill` asserts `restored=0` in its killed pass.** A kill that lands after the reinstall leaves
  the clean pass nothing to repair; that is a fault not constructed, not a defect.
- **Sort under `LC_ALL=C`** wherever a listing is compared.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md). Consult [`invariants.md`](../../.agents/factory/invariants.md)
  §2, §5, §7, §8, §10, §11 and §12 for this change.
- One phase per `uvm-build` invocation; one atomic commit with **both** the code and the `TECH.md`
  state change. Subjects follow `[feature] Build uv-cache-purge-damage P<n>: …`.
- Keep the `Co-Authored-By` trailer.
- A behavior change updates the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example` and
  `share/modulefiles/uv/main.lua` (whichever it invalidates) **in the same commit**. PLAN §2's
  surface table says which phase owes which line.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager` or `README.md`.
- Empty arrays expand as `${a[@]+"${a[@]}"}` (bash 3.2 under `set -u`).

---

## Phase P1 — Detection: doctor walks the cache's live entries
**Satisfies:** R1, R2 · **Depends on:** —
**Goal:** `uvm doctor` reports every damaged live entry of the cache by its path, reports nothing
on a healthy cache, never walks an archive no link reaches, and writes nothing.

- [x] `uvm_cache_entry KIND PATH` and `uvm_detect_cache`, as PLAN §2 specifies: script
  environments and cached-environment links by glob, wheel links by one `find -type l` per
  `wheels-v*` bucket, walked through the link; `pyvenv.cfg`, `RECORD`, `METADATA` and every
  `RECORD` path, `../` paths included and absolute ones skipped; one FAIL per entry; the fix and
  drop lists for P2.
- [x] `uvm_detect` calls it last and adds its findings and count; the header comment above
  `uvm_damaged_python` names the two new lists.
- [x] Same commit: `README.md` mitigation 2 says doctor checks the cache's live entries (script
  environments, cached `uvx` environments, the unpacked wheels they were built from) by the files
  each `RECORD` lists; the concession at `README.md:673` says doctor reports cache damage and the
  repair does not yet touch it.
- [x] R1: no code. The baseline is `research/drives/shaping-matrix.out` and `shaping-supp.out`,
  re-run at `8e03774`; the gate damages exactly R1's failing shapes.
- *Amended at review cycle 1's remediation, 2026-11-02, by ruling 4 and the foreman's GOAL
  clarification (R2 and the non-goal read "no link or pointer"):*
  - [x] `uvm_detect_cache` lists each bucket's links and its `*.http` and `*.rev` files in one
    `find`. A pointer is read only when its link is gone or dangling, by `uvm_cache_pointee`:
    builtins, split at NUL bytes, under `LC_ALL=C`, the 16 characters from `[A-Za-z0-9_-]` after
    the byte `0xb0` (measured in both kinds with uv 0.13.6). The archive it names is walked as a
    wheel entry, named by its link's path, only when it exists. A pointer that cannot be read or
    parsed, or that names a missing archive, is passed over without a word. The repair removes the
    pointers and never the archive. Measured: uv builds new environments through an orphan `.http`
    and an orphan `.rev`, copying the damage.
  - [x] Gate clauses. The pointer-only wheel gives a FAIL naming its link (red on `fb2b686`:
    doctor exits 0), and the same FAIL under every bash on the host. A garbage pointer, one naming
    a missing archive and an unreadable one give rc 0, no FAIL and nothing on stderr; the
    unreadable one is red with the read unguarded. A healthy cache's `bash -x` trace never enters
    `uvm_cache_pointee`, red with the pointer read before the link test; a positive control shows
    the trace does name it when a pointer is read. Only bash 3.2 was on the build host, so the
    parity clause compared one version there; it compares every version a host carries.
  - [x] README: the pointer-only wheel moves from what goes unseen to what is checked.
- *Amended at review cycle 1's remediation, 2026-11-02, by the foreman's ruling 5b (C1-F4):*
  - [x] The cluster figure crossed M1's 30 s line. On a Lustre scratch, 2 nodes × 64 ranks,
    `--large-cache`, at `312b6f7`: `record_lines=40185`, `cache_files=41043`, `live_entries=153`,
    `link_mode=hardlink`, `flock=coherent`; `walk_s` 51.66 (U), 94.74 (S), 108.01 (ukill), with
    `hold_s` 22 and 42 and the clean pass's 29, `wait_max_s` 25, 54 and 40, every run green with
    `rebuilt=0`. The cause was one `[[ -e || -L ]]` per `RECORD` line, a metadata round trip each.
  - [x] The walk is not narrowed. `uvm_cache_entry` now queues an entry, and `uvm_cache_check`
    tests each entry's `pyvenv.cfg` and each dist-info's `RECORD` and `METADATA` in the shell as
    before, then runs one `find -H` over every entry with a dist-info to compare (names only, no
    per-file predicate) and one `awk` pass over that listing and every `RECORD`. The awk reads a
    `RECORD` as the shell did (the field before the first comma, empty skipped, one quote off each
    end, absolute skipped), resolves `.` and `..` by name, and prints each path the listing lacks;
    the shell tests only those with `-e`/`-L`, so a path through a linked directory or outside the
    entry counts as it did, and a dangling link counts as present. The finding text, the first
    problem per entry and its order, the pointer path, wheels at their root, `uvm_cache_unpinnable`
    and `uvm_cache_clean` are unchanged. Where awk fails, every path is tested as before
    (`uvm_cache_record_paths`).
  - [x] P1's and P2's gates pass unchanged. P1 gains a clause: a console script purged through
    `../`, a file two directories down, a `RECORD` path that is a dangling link (no FAIL) and then
    removed, and a quoted `RECORD` path present (no FAIL) and purged. Each gave the same FAIL text
    at `312b6f7` and here (`flake8-7.1.1.dist-info is missing 1 of 42 files`, `tqdm-4.67.1.dist-info
    is missing 1 of 43 files`); the clause is red with the listing keyed by basename, at
    `console`.
  - [x] Local, `U` ×16 `--large-cache`: `walk_s=1.93` at `312b6f7`, `walk_s=0.75` here, then 0.72
    for `U`, 0.73 for `S` and 0.72 for `ukill` on the final tree, each exit 0 with `rebuilt=0`.
    Whether the check is narrowed waits for the cluster re-run: held back unless it is still past
    30 s.
- *Amended at review cycle 3's remediation, 2026-11-02, by the foreman's ruling 1 (C3-F1):*
  - [x] `uvm_cache_check` read each damaged dist-info's counts back with `rest="${gaps#*"${nl}${di}${tab}"}"`,
    a shortest-prefix strip of a buffer that grows with the damage, once per damaged dist-info.
    The counts now go into two indexed arrays, `gapm` and `gapt`, at the dist-info's index in
    `dis`: the awk pass and its fallback print the `T` lines in `dis` order, so one cursor that
    only moves forward finds each index, and the second pass reads the walked dist-info
    directories in the same order with a second counter. No string is searched per dist-info;
    bash 3.2 has no associative arrays, and its indexed arrays are lists walked from the head
    (measured: 16,000 sequential accesses 0.5 s, so negligible at any cache this walk sees). The
    awk program, the fallback and the FAIL text are unchanged. E9's tree (231 dist-info
    directories, 30% purged at random, seed 1): doctor's output at `52f5bf1` and here
    byte-identical, with awk and with awk failing (the fallback), 21 FAIL lines each.
  - [x] Timings on this workstation, E9 (N=20, 231 dist-info directories): doctor 17 s at
    `52f5bf1` (the review measured 47 s on a busier host), 1 s here (`date +%s` resolution); the
    fallback 18 s and 1 s. E9 with N=40 under the knob (451 dist-info directories, 4 calls of an
    unrelated script): at `52f5bf1` doctor 121 s, ranks 2-4 fail at 183 s on the 180 s lock
    timeout and the holder is still running at 200 s; here doctor 1 s, the holder repairs all 41
    environments (each through the index check below) and exits 0 at 39 s, and ranks 2-4 exit 0
    at 40 s.
  - [x] Gate clause (P1, last): E9's tree built from the gate's own script environment, 21
    environments and 231 dist-info directories, purged at random with seed 1; doctor must name
    all 21, and the fastest of three damaged runs must be within 4× + 0.5 s of the fastest of
    three healthy runs on the same tree. Red at `52f5bf1` (healthy 0.326 s, damaged 18.063 s),
    green here (0.329 s and 0.449 s; the full gate 0.305 s and 0.424 s).
  - [x] README *Many jobs at once*: the 30%-random-purge figure beside the one-entry figure.
- **Verify:** `sh spec/uv-cache-purge-damage/gates/p1.sh` — healthy rc 0 with no FAIL; 23 shapes
  each rc 1 with `FAIL  cache entry <path> `; the tree's listing unchanged by doctor and nothing
  newer than a marker; a console script through `../`, a file two levels down, a dangling and a
  removed link, and a quoted path, each with the per-path walk's text; a wheel reached only
  through its `.http` pointer named, alike under every
  bash at hand; a garbage, a dangling and an unreadable pointer passed over silently; no pointer
  read on a healthy cache; an unreached archive, every file gone, not named and rc 0; 231
  dist-info directories, 30% purged at random, named within 4× + 0.5 s of the healthy walk.
- **Touches:** `bin/uv-manager`, `README.md`.

## Phase P2 — The repair: in place where it can be, removed where it cannot
**Satisfies:** R3, R4 · **Depends on:** P1
**Goal:** a knob-set call repairs every damaged live entry under the repair lock's contract: in
place for an environment with `pyvenv.cfg` and a running interpreter, removal otherwise, every
failure failing the scope with a reason naming the entry, and a running process unaffected.

- [x] `uvm_repair_run`: the tool arm's `(( ${#inplace[@]} > 0 )) || return 0` becomes a guarded
  block, unchanged inside; the function ends `uvm_repair_cache; return 0`; its header names the
  fourth arm.
- [x] `uvm_repair_cache`, as PLAN §2 specifies: re-partition after the interpreter arm (no
  `pyvenv.cfg`, no executable `bin/python`, or a cached environment with `direct_url.json` → removal);
  one note; removals first (link `rm -f`; script environment renamed aside by §9's temporary-name
  rule, then `rm -rf`, a failed `rm` noted and passed; wheel every pointer file `<link>.<ext>` but
  `.lock`, then the link once they are gone); then one reinstall per environment, pins from
  `uvm_record_constraints`, `(cd / && exec … pip install --python <entry>/bin/python --reinstall
  --no-cache …) >&2`. Each failure sets `uvm_repair_reason` naming the entry and returns.
- [x] `uvm_doctor`: with cache damage, `uv-manager clean cache --yes` in the command block and the
  paragraph PLAN §2 gives.
- [x] Same commit: `uvm_help`'s `UVM_REPAIR` names uv's cache; `README.md` *Repairing inside a job*
  (*What happens*: the cache arm last, in place versus removed; the concession at `:673` replaced by
  what is repaired; *Network*: the reinstall's downloads); `etc/uv-manager.conf.example`'s repair
  paragraph and the modulefile's `UVM_REPAIR` help name uv's cache, `uv run <script>` and `uvx
  <spec>`; `AGENTS.md` § *Invariants* and `invariants.md` §8 gain the cache arm (PLAN §2's table).
- *Amended at build, 2026-11-01:* a wheel's pointers are the plain files `<link>.<ext>` with a
  dotless `<ext>`, not every `<link>.*`. A compressed platform tag holds dots, so another wheel's
  link `<link>.<tag>` and its `.http` and `.lock` share the prefix, and the plan's glob would remove
  them (driven with the filter: a healthy sibling at `<link>.manylinux_x` keeps its link, pointer
  and lock while the damaged wheel goes, and a new script then builds from the sibling). The
  pointers go in one `rm` and the link in a second, only after the first succeeds, so a pointer that
  cannot be removed (an immutable `.http`, driven) leaves the link for the walk to see again rather
  than a link gone beside a pointer uv still follows. A removal's reason carries `rm`'s or `mv`'s
  first line only, as the outcome record is read by its first line. A script environment that is
  gone by the time of its rename counts as removed rather than failing the scope (driven with an
  `mv` that loses the race).
- *Amended at P3's build, 2026-11-02, by the foreman's rulings on P2's open questions:*
  (1) a cached environment whose surviving `RECORD` lists a `direct_url.json` that is gone goes on
  the drop list in the walk (`uvm_cache_sourceless`, read across every dist-info, not only the first
  damaged one), so the repair never pins a URL, git or path distribution by version from the
  index; a script environment in that state, which M2 does not let the repair remove, fails the
  scope with `the cache environment <path> holds a distribution whose source is not recorded`
  (builder's extension; kept by the foreman's ruling of 2026-11-02, see P4). Gate clause: a local wheel named
  `tqdm-4.67.1` built in the gate, its `uvx` environment's `tqdm/std.py` and `direct_url.json`
  purged; red on P2's code (`AttributeError: … no attribute 'MARK'`, PyPI's tqdm pinned in),
  green after (prints `local`, one entry removed, doctor clean). (2) After the reinstalls each
  reinstalled entry is walked again (`uvm_cache_clean`); one still damaged sets `the cache
  environment <path> is still damaged after its repair`. Gate clause: a stand-in `uv` whose `pip
  install` exits 0 and does nothing; red without the re-walk (no reason, `.ok` recorded), green
  after (`.failed`, the reason naming the entry). (3) and (4) are README text, carried by P3.
- *Amended at review cycle 1's remediation, 2026-11-02, by the foreman's rulings 1-3 (REVIEW.md):*
  - [x] Ruling 1. `uvm_cache_sourceless` becomes `uvm_cache_unpinnable KIND ENV`. A cached
    environment goes on the drop list in the walk when any dist-info has no `RECORD`, keeps a
    `direct_url.json`, or has a `RECORD` listing a `direct_url.json` or a `uv_cache.json` with no
    `direct_url.json` beside it. Measured with uv 0.13.6: uv writes `uv_cache.json` for a
    distribution from a local file or a find-links directory, and for none from PyPI, its wheel or
    its sdist (an sdist build writes `uv_build.json`). Nothing in an environment names an index
    given only on the command line; ruling 3's fallback covers that case. Gate clauses: the local
    wheel's `uvx` environment with every file of its dist-info purged, which prints `local` and
    removes one entry (red on `fb2b686`: `AttributeError: … no attribute 'MARK'`, PyPI's tqdm
    pinned in); and R3's shape loop, where `distinfo` and `record` on a cached environment now
    assert the link reaches a new archive, the old one kept and one archive added, in place of
    "restored in place". The ruling moved those shapes to the drop class, so the assertion is
    replaced by the ruling's post-condition, not loosened (red on `fb2b686` at `distinfo on uvx`).
  - [x] Ruling 2. A script environment whose dist-info lost its `RECORD` is still pinned by
    version. The script half of the same test refuses one whose `RECORD` lists a `uv_cache.json`
    with no `direct_url.json` (builder's extension: a find-links directory's fork at a version the
    index also has would otherwise be swapped silently, C1-F1's harm). The re-walk's "drop the
    entry if anything still disagrees" is built for cached environments only: a script environment
    still damaged fails the scope as before, since M2 does not let the repair remove a live script
    environment. Open for the foreman. README: the class, the re-sync among the R5 exceptions, and
    the parity claim with the tool arm removed.
  - [x] Ruling 3. `uvm_cache_remove` holds the removals. A cached environment whose reinstall fails,
    or that the second walk finds still damaged, loses its link after the reinstalls. A script
    environment in either state fails the scope, and the README names the class with its two
    remedies. Gate clauses, each red on `fb2b686` and green here: a find-links environment with a
    module purged lets an unrelated call in the scope run, then its own call (`fl1`); an offline
    reinstall of a cached environment loses its link and the call runs (`xo1`); a stand-in `uv`
    whose `pip install` does nothing removes a cached environment's link (`npx1`); a script
    environment from the find-links directory fails the scope naming the entry and is kept
    (`fs1`; red on the message: `fb2b686` fails it as a failed reinstall).
  - [x] Ruling 4 was escalated: walking an archive that only a pointer reaches contradicted R2's
    "SHALL NOT walk an `archive-v0` entry that no link reaches". The foreman approved it as a GOAL
    clarification on 2026-11-02, and it is built under P1 below; the repair half is P2's gate
    clause `pt1`.
- *Amended at review cycle 2's remediation, 2026-11-02, by the foreman's rulings 1-4 and 6
  (REVIEW.md, C2-F1 and C2-F2):*
  - [x] Ruling 3 first, since rulings 1 and 2 test only what it collects. `uvm_cache_check` keeps
    walking an entry past its first damaged dist-info directory and passes every damaged one to
    `uvm_cache_found`, which keeps them beside the entry on `uvm_cache_fixd`; the FAIL text is the
    first problem in glob order, as before. The reinstall names each damaged distribution with
    `--reinstall-package` and pins only those (`uvm_record_constraints ENV DI…`); the other
    distributions are not passed at all, not even as constraints. Measured with uv 0.13.6 before
    building: in the rich environment with `rich/console.py` and `mdurl/_parse.py` purged, `pip
    install --reinstall-package rich --reinstall-package mdurl --no-cache rich==13.9.4 mdurl==0.1.2`
    resolved 4 packages, reinstalled 2, and left markdown-it-py's and pygments' 495 files with the
    same inode, mtime, size and sha256; with tqdm damaged beside a find-links `mylib` PyPI does not
    have, mylib was never resolved and stayed byte-identical; a dist-info without `RECORD`, without
    any file, or without `METADATA` is reinstalled the same way (uv warns of the missing `RECORD`).
    So uv expresses "reinstall these, keep the rest" and nothing is escalated. Cached environments
    keep their drop logic over every distribution.
  - [x] Ruling 1. `uvm_cache_unpinnable KIND DI` tests one dist-info directory. A script
    environment's damaged distribution with no `direct_url.json` and a `uv_cache.json` on disk is
    unpinnable whether or not a `RECORD` survives to list it; only the damaged distributions are
    tested, so an undamaged find-links distribution no longer fails the scope (`d14`). The reason
    keeps its prefix and adds the distribution and the remedy: `… holds a distribution whose source
    is not recorded (mdurl 0.1.2); clear the cache with uv-manager clean cache --yes`.
  - [x] Ruling 2. A damaged distribution with no `RECORD`, no `direct_url.json` and no
    `uv_cache.json` goes through `uvm_cache_index_check` before any removal or reinstall: `pip
    install -q --python <env>/bin/python --target <tmp> --no-deps --no-cache name==version` from
    `/`, the target the dot name a script environment is renamed aside to, beside it in
    `environments-v2` (the walk and uv skip it; `uv cache prune` removed such a directory,
    measured), removed after on every path. Then `<env>/bin/python -I -S` compares the sha256 the
    target's `RECORD` gives each file under site-packages with that file in the environment where
    it is still present, skipping `bin/` (a script carries its interpreter's path: measured, the
    target's `RECORD` lists `bin/tqdm`) and paths outside. A mismatch (exit 3), a failed fetch or
    a target without one dist-info `RECORD` fails the scope naming the distribution, with the
    remedy. Python is the hasher because `RECORD` holds urlsafe base64 and `shasum`/`sha256sum`
    print hex; the environment's interpreter is the one the reinstall already trusts. Zero files
    in common passes, as ruling 2 states: a dependency never imported loses every file under an
    access-time purge while `pyvenv.cfg`, read on every run, survives, so failing that case would
    fail ordinary scopes; README lists it with the fork that stays unseen. Cost, measured on this
    workstation, medians of three: `tqdm` 0.22 s fetch and 0.06 s compare, the repair 0.79 s
    against 0.56 s with `RECORD` kept; `scipy` 1.14.1 (1,389 files) 0.93 s and 0.16 s, the repair
    4.47 s against 3.11 s. One fetch in nine stalled about 19 s on the network. A healthy scope
    and the unset path run none of it.
  - [x] Ruling 4, the same-commit surfaces. README: the `uv.toml` remedy is gone, from the
    find-links paragraph and from the command-line index case; `uv-manager clean cache --yes` is
    named with its cost; the re-sync claim is narrowed to URL, git and path sources the script
    names, a find-links directory or another index not synced back; ruling 2's check is described
    with the fork it cannot see and its cost; the reinstall touches only damaged distributions,
    and *Network* says so. Doctor's cache paragraph and `etc/uv-manager.conf.example` say the
    same; the help text and the modulefile say nothing these change. `AGENTS.md` § *Invariants*
    and `invariants.md` §8 carry the narrowed reinstall, the on-disk mark and the index check.
  - [x] Ruling 6, gate clauses, each red at `75bcbab` with the clause's own text and green here
    (run one per subshell against `75bcbab`'s script): `c2_scope` (d14: a script declaring a
    find-links `uvmgate` loses `tqdm/std.py`; an unrelated `uvx ruff` and its own call run, and
    uvmgate is byte-identical; red: `an undamaged find-links distribution failed an unrelated
    call's scope: rc 1`); `c2_uvtoml` (d15: the find-links directory in `uv.toml`; a PyPI module
    purged is repaired, uvmgate's module purged fails naming `uvmgate 0.1` and the remedy; red: `a
    uv.toml find-links environment with a PyPI module purged: rc 1`); `c2_fork A` and `c2_fork B`
    (d16: a fork of mdurl 0.1.2 by find-links and no-index, every file of its dist-info or its
    `RECORD` alone purged; no call runs PyPI's mdurl, the scope fails naming `mdurl 0.1.2` and the
    remedy, the fork's file and no temporary target are left; red: `PyPI's mdurl ran in place of
    the fork`, each shape); `c2_sibling` (rich and mdurl damaged in one environment, both restored,
    markdown-it-py's and pygments' files the same inode, size and cksum; red: `an undamaged
    distribution was rewritten by the repair`). No existing clause changed: the script shapes
    `distinfo` and `record`, and R4's `distinfo` sleepers, now pass through the index check and
    stay green, and `lscript`, `fls`, `off1` and `np1` keep their messages, the reason's prefix
    being unchanged.
- *Amended at review cycle 3's remediation, 2026-11-02, by the foreman's rulings 2-4 (C3-F2,
  C3-F3, C3-F4):*
  - [x] Ruling 2. Every damaged distribution the arm would pin by version, one with no
    `direct_url.json` that `uvm_cache_unpinnable` does not refuse, goes through
    `uvm_cache_index_check`, its `RECORD` kept or not; before, only one without `RECORD` did, so
    six 1.16.0 from an HTTP index the script names, its `six.py` purged and its `RECORD` kept,
    was reinstalled from PyPI (E3). The check takes `ENV DI…`: one `uv pip install -q --python
    <env>/bin/python --target <tmp> --no-deps --no-cache name==ver …` per environment, from `/`
    under the reinstall's configuration, the target a dot name in `environments-v2` (for a cached
    environment too, so it is never beside the link inside its hash directory), removed on every
    path. `uvm_cache_hash_py` then matches each `DI` to the fetched dist-info by normalized name and
    version. Where `RECORD` survives, its sha256 entries are compared with the release's `RECORD`
    for the same paths, reading no file of the environment; where it is gone, each release file
    still present is hashed, as before. Both pass over the dist-info's own `RECORD`, `INSTALLER`,
    `REQUESTED`, `direct_url.json` and `uv_cache.json`, and `../`- and `bin/`-rooted paths. On a
    failure it prints the failing `DI`, so the reason names that distribution; a failed fetch names
    every distribution of the batch (plural "holds distributions …" when more than one). The
    reason keeps its shape: `… holds a distribution whose source is not recorded (six 1.16.0),
    whose files differ from the configured index's release; clear the cache with uv-manager clean
    cache --yes`. A cached environment follows its existing semantics, an unpinnable distribution
    dropping the link: a failed check moves the entry to the drop list, noted after the repair line
    as `<link> is not shown to come from the configured index; its link is removed for uv to
    rebuild`. Checks run in the first loop, before any removal or reinstall, as the refusals do.
  - [x] Cost, this workstation, a knob-set call on the damage path, three runs each at `52f5bf1`
    and here: `tqdm` alone, `tqdm/std.py` purged, 0.40-0.50 s against 0.64-0.68 s (+0.2 s); E9's
    environment, one module of each of its 11 distributions purged, 1.15-1.17 s against
    1.49-1.62 s (+0.4 s for the batch). Well inside the 10 s escalation line.
  - [x] Ruling 3, README: the class (a distribution from an index the script names, over HTTP,
    when the configured index lacks that build or serves another, a `+hpc` local version or a
    rebuild), that under the knob it fails every call in the scope until `uv-manager clean cache
    --yes`, and that the loud failure is chosen over a swap. The sentence that another index the
    script names "is not synced back" now says such a distribution is refused rather than
    reinstalled; the command-line-index concession beside the tool arm's says the check now
    decides it. Driven (E2, case B): the `+hpc` environment fails an unrelated call's scope at the
    check, `… (six 1.16.0+hpc), which the configured index does not serve; clear the cache …`.
  - [x] Ruling 4, prose only: `invariants.md` §8, `AGENTS.md`, the README and the arm's banner
    comment say the removals precede the arm's first `uv` call that could reach the base
    interpreter, the index check's fetch, for an environment still a virtualenv, coming earlier.
    `etc/uv-manager.conf.example` says the check covers every pin by version.
  - [x] Gate clause `c3_index` (E3): a gate-built six 1.16.0 (`ORIGIN = "index-fork"`) served by
    `python -m http.server` from the managed interpreter, a script naming it in
    `[[tool.uv.index]]`; `six.py` purged, `RECORD` kept. Two knob-set calls and a knob-off call:
    none prints `six pypi`, the scope fails naming `six 1.16.0` and the remedy, `six.py` is still
    absent and `RECORD` byte-identical, no temporary target left. Then a cached environment from
    the same index given with `--index` on `uv run --with`, `six.py` purged: rc 0, prints
    `six index-fork`, the link removal noted. Red at `52f5bf1` on each half, run alone
    (`PyPI's six ran in place of the index's`; `the cached environment from the index its call
    names: rc 0, printed [six pypi]`), green here.
  - [x] Existing clauses changed, each because the check now runs before every in-place
    reinstall: `off1` (offline) fails at the fetch, so it asserts `… holds a distribution whose
    source is not recorded (tqdm 4.67.1), which the configured index does not serve` in place of
    `the cache environment repair failed for`; `xo1` (offline, cached) loses its link at the check,
    so it asserts the new note in place of `the reinstall of … failed`; `np1`/`npx1`'s stand-in
    `uv` passes a `pip install` carrying `--target` to uv, so the fetch is real and only the
    reinstall does nothing (a setup retune; their assertions are unchanged). Every other clause
    passes unchanged, the R3 shape loop's module, metadata and third shapes now through the
    check.
- *Amended at review cycle 4's remediation, 2026-11-02, by the maintainer's ruling (C4-F1, C4-F2):*
  - [x] Ruling 1. `uvm_cache_hash_py` compares source files only, for every distribution checked:
    `*.py` and `*.pyi` paths outside the dist-info directory and `bin/` (and `../`), from a
    surviving `RECORD` against the release's `RECORD`, or hashed where `RECORD` is gone. The
    install-file skip list goes with it, since the dist-info directory is no longer compared at
    all. A path on one side only is passed over, as before, so a release with no source file in
    common passes once the fetch succeeded. Measured at `3a9ac04` with the reviewer's drives:
    markupsafe 2.0.1 fails on `_speedups.cpython-312-darwin.so`, docopt 0.6.2 built under
    `UV_EXCLUDE_NEWER=2024-06-01T00:00:00Z` on `METADATA`; both repair in place here. The cached
    twin (d4: `uvx --from tqdm --with markupsafe==2.0.1`) lost its link at `3a9ac04` and is now
    reinstalled in place. `c3_index` and `c2_fork` differ in a `.py` file already (`six.py`,
    `mdurl/__init__.py`), so neither fork changed, and both stay green.
  - [x] Ruling 2. uv 0.13.6, measured with `--target --no-deps --no-cache -q`: a version the
    index lacks exits 1, `error: No solution found when resolving dependencies` / `cause: Because
    there is no version of tqdm==99.0.0 …`; a project it lacks (a 404) exits 1, `… Because X was
    not found in the package registry …`; a refused connection exits 2, `error: Failed to fetch:
    http://127.0.0.1:9/simple/tqdm/` with `cause: … Connection refused (os error 61)`; a 500 exits
    2, `Failed to fetch` with the status; a 401 or 403 exits 1 with the "not found in the package
    registry" text and a `hint:` naming the status; `UV_OFFLINE=1` exits 1, `… tqdm was not found
    in the cache …` with a `hint:` that the network was disabled; a wheel file that 404s exits 1,
    `Failed to download`. The exit status alone does not separate them, so
    `uvm_cache_index_check` keeps uv's stderr (fd swap, then passed on to stderr whole) and reads
    a version the index lacks only from exit 1 with "there is no version of" or "was not found in
    the package registry" and no `hint:`; anything else, a later uv's new wording included, is a
    failed fetch, `uvm_cache_index_why` left empty. The script arm's reason for it: `the cache
    environment <p> is damaged, and uv-manager could not fetch <dist> <ver> from the configured
    index to check its source (the index may be unreachable); the scope is not repaired`, no
    remedy. A cached environment loses its link in every case, as before. Driven: unreachable,
    a version PyPI lacks (`tqdm 4.67.99`, keeps `which the configured index does not serve` and
    the remedy) and a 403 (the fetch-failure reason), stdout empty in each.
  - [x] Ruling 3. README (source-only comparison, the conceded fork, the fetch-failure reason
    quoted, why uv's words are read), `etc/uv-manager.conf.example`, `AGENTS.md` § *Invariants* and
    `invariants.md` §8. The help text and the modulefile say nothing this changes.
  - [x] Ruling 4, gate clauses, each red at `3a9ac04` and green here (run alone against each
    tree's script, with P2's setup): `c4_sdist` (markupsafe 2.0.1 from its sdist, the C extension
    asserted built, `markupsafe/_native.py` purged, `RECORD` kept; red: `C4-F1: ms 2.0.1 built from
    its sdist, markupsafe/_native.py purged: rc 1`), skipped with a message where `cc --version`
    fails; `c4_docopt` (docopt 0.6.2 built under the older `UV_EXCLUDE_NEWER`, `docopt.py` purged;
    red: `C4-F1: dp 0.6.2 … rc 1`); `c4_fetch` (`UV_INDEX_URL=http://127.0.0.1:9/simple
    UV_HTTP_RETRIES=0`; the fetch-failure reason naming tqdm 4.67.1, no `clean cache`, `.failed`
    and no `.ok`, no target left; red: `C4-F2: an unreachable index prescribed clean cache`).
  - [x] Existing clause changed: `off1` (`UV_OFFLINE=1`) is a failed fetch under ruling 2, so it
    asserts the fetch-failure reason and no `clean cache` in place of `which the configured index
    does not serve` (red at `3a9ac04`: `R3: call 1 does not name the failed entry`). Every other
    clause passes unchanged.
- *Amended at review cycle 5's remediation, 2026-11-02, by the maintainer's ruling (C5-F1, C5-F2,
  C5-F3):*
  - [x] Measured first, uv 0.13.6. `uv_build.json` (content `{}`, listed in `RECORD`) is written
    into the dist-info directory of every distribution uv builds from source: docopt 0.6.2 (sdist
    only) in a venv, a `uv run` script environment and a `uvx --with` cached environment; tqdm
    4.66.4 under `--no-binary`; numpy 2.1.3 under `no-binary`; a local source tree (beside
    `direct_url.json` and `uv_cache.json`, so never reaching the check). It is written for no wheel
    install: tqdm, six, rich and its three dependencies from PyPI in a venv, six in a script and a
    cached environment, tqdm into a `--target`, and the tqdm fork from an HTTP index whose dist-info
    `fork_and_split.sh` lists. The fetch of a source-only release, `pip install -q --target
    <tmp> --no-deps --no-cache docopt==0.6.2`, builds it (`Building docopt==0.6.2` / `Built`
    without `-q`), exits 0 with empty stderr under `-q`, and its target's dist-info holds
    `uv_build.json`. So the mark is reliable, and nothing is escalated.
  - [x] Ruling 1. `uvm_cache_hash_py`, once the release is found in the target, passes a `DI`
    over without comparing when `DI` or the release's dist-info holds `uv_build.json`: the fetch
    having succeeded is the check. Wheels keep the source-only comparison unchanged. The file is
    tested on disk only, not as a `RECORD` listing, as the ruling states; a listing would widen the
    concession to a purge that took the file. Driven: numpy 2.1.3 under `no-binary`
    (`numpy_sdist.sh`) exits 1 at `e61e360` on `numpy/__config__.py`, and here repairs in place,
    rc 0, the second call silent, no target left: 35 s to build, 110 s for the knob-set call (the
    fetch builds it once more, the reinstall a third time).
  - [x] Ruling 2. The fetch runs as `unset FORCE_COLOR CLICOLOR_FORCE && export NO_COLOR=1` in
    its own subshell. Measured with `FORCE_COLOR=1` and no scrub, every class prints escape codes
    inside `hint:` and `cause:`; with the scrub none does. A failure is a failed fetch,
    `uvm_cache_index_why` empty, when uv exits 2, or a line of stderr holds `Failed to fetch` or
    `not found in the cache`, or a `hint:` line holds `network` … `disabled`, `401 Unauthorized`
    or `403 Forbidden` (the status phrases, not the bare numbers, which a timestamp or a version
    in an `exclude-newer` hint can hold). Every other non-zero exit is `which the configured index
    does not serve` with the remedy. Driven through the repair (`classes.sh`, every call under
    `FORCE_COLOR=1 CLICOLOR_FORCE=1`, no escape code in uv's stderr): a version the index lacks,
    a version behind an `exclude-newer` hint and a project the index lacks (404) name `clean
    cache`; 401, 403, 500, a refused connection and `UV_OFFLINE=1` give the fetch-failure reason
    with none. The review's `split.sh`: B (exclude-newer) now names `clean cache`, D1 and D2 (401,
    without and with `FORCE_COLOR=1`) both give the fetch-failure reason. `fork_and_split.sh`: the
    fork from the script's index is still refused with `RECORD` kept and gone, no temporary
    target left. Known consequence, per the ruling: an sdist whose build fails in the fetch (no
    compiler) exits 1 and reads as a release the index does not serve; the README says so.
  - [x] Ruling 3. README (wheels only, the `uv_build.json` mark, the conceded sdist fork and its
    mirror, a wheel fork where the configured index serves that version only as an sdist, which
    the ruling's "either" implies; the markers listed; the sdist's extra build in the cost),
    `etc/uv-manager.conf.example`, `AGENTS.md` § *Invariants* and `invariants.md` §8. The banner
    comments of `uvm_repair_cache`, `uvm_cache_index_check` and `uvm_cache_hash_py` say the same.
    The help text, doctor and the modulefile say nothing this changes.
  - [x] Ruling 4, gate clauses, each red at `e61e360` and green here, run alone with P2's setup
    against each tree's script. `c5_numpy` (numpy 2.1.3 under `no-binary` in `uv.toml`, asserted
    built from its sdist with a `builds-v0/` path in `numpy/__config__.py`, `numpy/_pytesttester.py`
    purged, `RECORD` kept; through `c4_built`, which takes the finding's tag; red: `C5-F1: nu 2.1.3
    built from its sdist, numpy/_pytesttester.py purged: rc 1`), skipped with a message where `cc
    --version` fails. numpy is chosen over a lighter package because it is the finding's own case
    and the clause costs about 105 s here (79 s red), affordable beside P2's other clauses; a
    gate-built sdist with an in-tree backend writing `sys.executable` would show the same mechanism
    without a compiler, and is the fallback if the cost or the build's portability turns. `c5_excl`
    (`UV_EXCLUDE_NEWER=2024-06-01T00:00:00Z` on the tqdm 4.67.1 script; uv's hint asserted present;
    red: `C5-F2: a version exclude-newer filters out does not name clean cache`). `c5_401` (an index
    answering 401 served by the managed interpreter, `FORCE_COLOR=1`; red: `C5-F3: a 401 under
    FORCE_COLOR=1 prescribed clean cache`).
  - [x] No existing clause changed. `c2_fork` (refused before the fetch), `c3_index` (a wheel fork,
    compared), `c4_sdist` and `c4_docopt` (now passed by the mark, not by the comparison),
    `c4_fetch` (exit 2) and `off1` (offline wording) pass as written.
- **Verify:** `sh spec/uv-cache-purge-damage/gates/p2.sh` — R3's post-conditions over 21
  shape-and-entry pairs, the working directory's `uv.toml`, doctor first and its remedy line, 8
  concurrent first calls, the offline failure across 4 calls, three read-only removals, the
  leftover aside, a script environment whose source is not recorded, a cached environment from a
  local wheel without its `RECORD`, a find-links environment, a failed or empty reinstall of a cached
  environment, a find-links script environment, a wheel reached only through its pointer, an
  undamaged find-links distribution beside a damaged one, the find-links directory in `uv.toml`, a
  find-links fork of a PyPI version without its dist-info files or its `RECORD`, the undamaged
  distributions byte-identical after a repair, hardlink mode, six from an HTTP index the script
  names and its cached twin, markupsafe 2.0.1 and docopt 0.6.2 built from their sdists repaired in
  place, an unreachable index failing with its own reason, numpy 2.1.3 built from its sdist
  repaired in place, a version behind an `exclude-newer` hint naming `clean cache`, a 401 under
  `FORCE_COLOR=1` failing as a fetch; R4's three sleepers per shape (PLAN §6). R3's dead-holder clause
  is carried by P3's `ukill`, since the lock code does not change here. Inspection-only: the
  documentation items above, and which entries the repair moves or removes (R4's reviewer clause).
- **Touches:** `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`,
  `share/modulefiles/uv/main.lua`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P3 — Waiters, the local race drive and the surfaces
**Satisfies:** R5, R7, R8 · **Depends on:** P2
**Goal:** sixteen ranks against a damaged cache rebuild nothing the repair restored; the other
arms and the unset path are as on `8e03774`; every surface says what is repaired and what is not.

- [x] `tests/repair-race.sh`: scenarios `U`, `S`, `ukill` as [research 03](research/03-cluster-drive.md)
  specifies (`prepare_cache`, the damage, `entries` before and after each pass, the keys `walk_s`,
  `cache_files`, `live_entries`, `link_mode`, `rebuilt`, the checks, `ukill`'s clean timeout of
  180 s and its `restored=0` read). `F`, `T`, `P`, `kill`, `I`, `ikill` unchanged. The header
  documents the three scenarios and every new key. The flock probe is P4's.
- [x] `README.md`: the purge-table row `| **Files inside uv's cache** | … |`; *What it catches*:
  the unseen classes (an environment's dist-info directory removed whole, packages a pyvenv-less run
  already put into a managed interpreter, `UV_LINK_MODE=symlink`, wheels built from source
  distributions); the manual remedy `uv-manager clean cache --yes` and that `uv cache clean
  <package>` or `uv cache prune` alone leaves the failure; the classes the repair removes, that the
  next call on each node rebuilds each concurrently where `flock` is node-local, and that uv fails
  outright where `flock` is absent; *Many jobs at once* with the walk's local cost per `RECORD`
  line.
- [x] `AGENTS.md`'s `tests/` paragraph: the cache scenarios, one sentence naming `U`, `S`, `ukill`.
- [x] Census: propose `uvm_repair_cache` for `AGENTS.md`'s high-risk regions (the arm that removes
  under `UV_CACHE_DIR`), `invariants.md`'s list moving with it. The foreman decides at review.
- [x] `README.md`: one sentence that the cache layout the walk reads (the links under
  `environments-v2` and `wheels-v*`, and the `.http` pointer beside a wheel's link) was verified
  against uv 0.13.x. Foreman's plan-gate condition, 2026-11-01.
- [x] R8 sweep: read each of the four surfaces against R8's list and fix what P1 and P2 left.
- *Amended at build, 2026-11-02:* the `flock` key is in every `U`, `S` and `ukill` summary now,
  `not-measured`, or `unknown` without the utility; the two-node probe stays P4's. The drive itself
  reports `ukill`'s killed pass with `restored` other than 0 as a fault not constructed (exit 4),
  not only the gate. The census was made, not only proposed: `uvm_repair_cache` has a row in
  `AGENTS.md`'s high-risk regions and an entry in `invariants.md`'s list, for the foreman to keep or
  revert at review. The README also carries the foreman's ruling (3), the window during an in-place
  reinstall, and ruling (1)'s user-facing half: the link removed for a lost `direct_url.json`, the
  script environment's refusal, and the conceded case where `RECORD` went too. The sweep also
  renamed the purge table's `Cache only` row to `The whole cache`, qualified mitigation 1's cache on
  scratch with `UVM_REPAIR`, and widened the modulefile's partial-purge sentence to uv's cache.
- *Amended at review cycle 1's remediation, 2026-11-02:*
  - [x] Reopened by ruling 1: `U`'s damage took the subject's `RECORD`, a shape the repair now
    removes, so `U` read `rebuilt=1` after P2's fix. `U` and `ukill` now keep `RECORD` and take
    `tqdm/std.py` and every other file of the dist-info directory, the in-place class R5 grades;
    `S` keeps its shape, since a script environment is reinstalled in place either way. The check
    `rebuilt=0` is unchanged.
  - [x] Ruling 6 (C1-F5). `rebuilt` adds the environments present before the pass that hold a
    dist-info file newer than the repair's outcome record (`resynced`), to the resolution of the
    filesystem's timestamps. Constructed, since no scenario re-syncs on its own: `S` ×4 with a
    `touch` of the subject's `INSTALLER` one second after the pass, on copies of the drive. Red on
    `fb2b686`'s drive (`rebuilt=0`, exit 0), green here (`rebuilt=1`, exit 1). The gate's `U`, `S`
    and `ukill` `rebuilt=0` reads the stronger key; no committed clause constructs the re-sync.
- *Amended at review cycle 2's remediation, 2026-11-02, by the foreman's ruling 5 (C2-F3):*
  - [x] `tests/repair-race.sh`'s help for `--large-cache` and for `record_lines` describes the
    listing walk, one `find` over the live entries and every `RECORD` line compared with that
    listing, in place of a path tested per line. Help text only; no scenario, check or key moves.
- **Verify:** `sh spec/uv-cache-purge-damage/gates/p3.sh` — `U` ×16, `S` ×16, `ukill` ×8 exit 0 with
  `rebuilt=0` (`clean_rebuilt` for `ukill`), the keys well formed, `live_entries` ≥ 22, no `/` in a
  summary, `ukill`'s killed pass `restored=0`; `F` ×16, `T` ×8, `P` ×8, `kill` ×8 exit 0; the unset
  path within 1 s of `8e03774`'s; the R8 census. Inspection-only: R5's README sentence, each
  surface against R8's list, and that the walk sits behind the knob and the lock (R7).
- **Touches:** `tests/repair-race.sh`, `README.md`, `AGENTS.md`, any surface the sweep corrects.

## Phase P4 — Cross-node drive on Lustre
**Satisfies:** R1 (the site's link mode), R6 · **Depends on:** P3
**Goal:** R6's evidence from `tests/repair-race.sh` `U`, `S` and `ukill` at 2 nodes × 64 ranks
on a Lustre scratch, with the site's link mode R1 asks for, and the README's walk figure from it.
**This phase has an external wait, so it is two runs.**

**Run A — build, check locally, hand back:**
- [x] `tests/repair-race.sh`: the flock probe as [research 03](research/03-cluster-drive.md)
  specifies: a `REPAIRRACE_ROLE=flock` branch beside `rank`, run once per job under `--launch srun`
  with `srun --nodes=2 --ntasks=2 --ntasks-per-node=1`, recorded as `flock=coherent|node-local|absent`,
  `not-measured` under a local launch, `unknown` without the utility. The header documents it.
- [x] `AGENTS.md`'s `tests/` paragraph: the probe, half a sentence.
- [x] Run the gate. It is expected red **only** at `cluster evidence … not recorded yet`, and every
  check above that line must pass. **This red is the external wait, not a failed attempt: do not
  `--record-attempt` for it.** Commit Run A as `[feature] Build uv-cache-purge-damage P4: Run A — …`,
  the phase left `in_progress`, and stop.
- [x] Hand back to the foreman: the commit, the local `U`, `S` and `ukill` summaries, and the two job
  bodies below.
  - The bodies are generic. Their `#SBATCH` lines size the job only; the foreman adds account,
    partition and QoS, which are never committed.
  - Both fit the approved test-job class: at most 30 min wall and 16 GB per node.
  - The foreman stages this commit's tree on a filesystem every node mounts (at least `bin/` with
    its symlinks, `tests/`, `.agents/factory/bin/temp_root.sh` and `.agents/factory/fixtures/`),
    checks the staged blobs against `git ls-tree -r`, then passes `REPAIRRACE_REPO` and, per job,
    its own empty `REPAIRRACE_RUN_DIR` on Lustre.
  - Both jobs may be queued together.

  **Job 1, scenarios U then S:**
  ```bash
  #!/bin/bash
  #SBATCH --job-name=repair-race-cache
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
  for s in U S; do
      d="$REPAIRRACE_RUN_DIR/$s"
      REPAIRRACE_SHARED="$d/shared"
      export REPAIRRACE_SHARED
      mkdir -p "$REPAIRRACE_SHARED" && cd "$d" || exit 1
      "$REPAIRRACE_REPO/tests/repair-race.sh" --launch srun --ranks "$n" --scenario "$s" \
          --large-cache --summary "$d/summary.txt"
      echo "exit=$?" >> "$d/summary.txt"
  done
  ```

  **Job 2, scenario ukill:**
  ```bash
  #!/bin/bash
  #SBATCH --job-name=repair-race-ukill
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
  "$REPAIRRACE_REPO/tests/repair-race.sh" --launch srun --ranks "$n" --scenario ukill --timeout 60 \
      --large-cache --summary "$REPAIRRACE_RUN_DIR/summary.txt"
  echo "exit=$?" >> "$REPAIRRACE_RUN_DIR/summary.txt"
  ```
  - **Expected runtime:** job 1 under 20 min, job 2 under 12. Each drive prepares for 4-7 min (uv
    through the installer, cpython 3.12, twenty-two environments and their wheels, then the large
    cache's two environments, about 38,000 `RECORD` lines and 38,000 files more), and races
    in under a minute. The walk runs on the large cache three times per scenario (the timed
    doctor, the holder, the `restored` doctor) and five under `ukill`; locally it took 1.8 s, and
    at a metadata round trip of up to 1 ms per line it is under a minute each on Lustre. Job 2's
    killed pass runs out its 60 s timeout, then doctor, `uvm clean lock --yes` and a clean pass of
    one repair. A walk past about 170 s would time the U and S waiters out at their 180 s and
    fail the run; that is M1's finding, not an infrastructure fault.
  - **Memory:** 64 ranks per node, each the bash wrapper, then `uvx` or `uv run` and a Python 3.12:
    2-4 GB per node, inside 16 GB.
  - **Egress** from compute nodes: `astral.sh` and its release host for uv, `releases.astral.sh`
    and GitHub's object host for the interpreter, `pypi.org` and `files.pythonhosted.org`. No
    `git`.
  - **Evidence:** the three summaries in order, unedited: `cat <job1>/U/summary.txt
    <job1>/S/summary.txt <job2>/summary.txt > spec/uv-cache-purge-damage/evidence/lustre.txt`.
    Each summary is the drive's key=value block, `scenario=` first, then `exit=` appended by the
    job; `record_lines` follows `live_entries`.
  - **The foreman pushes the branch and submits both jobs.**

- *Amended at Run A, 2026-11-02, by the foreman's rulings on P3's open questions:* (1) a script
  environment that lost a `direct_url.json` its `RECORD` lists keeps failing the scope with its
  reason. P2's gate gains the clause: a script whose dependency is the local wheel by `file://`, its
  environment's `tqdm/std.py` and `direct_url.json` purged; green on this code (rc non-zero, the
  reason naming the entry, `.failed` and no `.ok`, the entry kept), red with the refusal disabled
  (`a script environment that lost direct_url.json let the call run`). (2) Accepted. (3)
  `uvm_repair_cache` stays in `AGENTS.md`'s high-risk regions. (4) Accepted.
- *Amended at Run A, 2026-11-02:* the probe's words, as built. Under `--launch srun`, `absent`
  covers a node without the `flock` utility as well as a filesystem that refuses `flock`, since
  either rank's status other than 0 or 75 reads that way and the probe never fails the drive (the
  foreman's condition for the job environment). A step that fails, or ranks that report one node
  or none, leave `not-measured`, which the evidence half rejects, rather than a word the probe did
  not see. Rank 0 creates `left` before it releases, and a try that finds it counts for nothing,
  so a hold that ran out its 30 s bound cannot read as `node-local`. Driven ad hoc under a
  stand-in `srun`, `flock` and `uname` on one host: `coherent`, `node-local` (a lock file per
  rank), `absent` (a `flock` that fails, and none on `PATH`) and `not-measured` (both ranks on one
  node), each with `U` exit 0. The job bodies gain a job name, and nothing else. Rehearsed as
  committed, with `--uv-bin` added as every local drive seeds uv, under the stand-in `srun` at 128
  ranks: job 1 in 29 s, job 2 in 80 s, and the gate's evidence half green
  on their three summaries, red at `clean_repairs=2`.

- *Amended at review cycle 1's remediation, 2026-11-02, by the foreman's rulings 5 and 7:*
  - [x] Ruling 5 (C1-F4). `tests/repair-race.sh --large-cache`, under `U`, `S` and `ukill` only,
    adds before the subjects a script environment of pandas 2.2.3, scipy 1.14.1, scikit-learn 1.5.2
    and matplotlib 3.9.2 and a `uvx` environment of jupyterlab 4.2.5, the review's own stack. The
    summary gains `record_lines`, the lines of the live entries' `RECORD` files before the damage,
    beside `walk_s`. Locally, `U` ×16: `record_lines=40191`, `walk_s=1.81`, `cache_files=41053`,
    `live_entries=154`, `prep_s=13`; `S` ×16 `walk_s=1.80`, `prep_s=54`; `ukill` ×8
    `walk_s=1.82`, `prep_s=33`; each exit 0 with `rebuilt=0`. The gate's local `U` ×16 runs
    `--large-cache` and asserts `record_lines` ≥ 10,000 (red without the option at
    `record_lines=2713`); the evidence half asserts the same of each cluster summary. Both job
    bodies pass `--large-cache`, and nothing else in them changes.
  - [x] Ruling 5's bucket clause: not built. Nothing in the cache's layout records which
    `wheels-v*` bucket a uv version reads, so a bucket the pinned uv no longer uses cannot be
    shown from the layout; every `wheels-v*` bucket is still walked. Whether to narrow the check
    waits for the cluster figure.
  - [x] Ruling 7 (C1-F6) is Run B's: the README's figure from R6's `walk_s` and `record_lines`.

**Run B — read the evidence, close the phase:**
- [x] Copy the evidence to `spec/uv-cache-purge-damage/evidence/lustre.txt`, unedited. If it
  contains anything identifying, stop and ask the foreman. Do not scrub by hand.
- [x] Run the gate. A scenario can fail for an infrastructure reason (egress lost, `REPAIRRACE_SHARED`
  not shared, `srun` refused, `progress` not ok). Record that in the commit body and escalate to the
  foreman; do not close the phase on it.
- [x] Record in `PLAN.md` §5, under a paragraph starting `**Cluster evidence`, the measured
  `walk_s`, `cache_files`, `live_entries`, `hold_s`, `wait_max_s`, `link_mode` and `flock` for each
  scenario. A `walk_s` past 30 s is a review finding (M1), not a reason for a knob.
- [x] `README.md` *Many jobs at once*: the walk seconds the evidence records beside its file,
  entry and `RECORD`-line counts (R8, ruling 7).
- [x] Re-run P1-P3's gates. Mark the phase `done` with `--top-status in_review` and commit as
  `[feature] Build uv-cache-purge-damage P4: Run B — …`.
- *Run B, 2026-11-02:* the evidence at `729080d`, the foreman's two jobs on a Lustre scratch, 2
  nodes × 64 ranks, `--large-cache`, copied unedited (sha256 `25f57b18…5c16`, 128 lines, checked
  after the copy). `walk_s` 3.45 (U), 4.71 (S), 2.59 (ukill) against 51.66, 94.74 and 108.01 at
  `312b6f7`: ruling 5b's listing walk is under M1's line, so the check is not narrowed. Every
  scenario `progress=ok`, `exit=0`, `rebuilt=0` (`clean_rebuilt=0` under `ukill`), `flock=coherent`,
  `link_mode=hardlink`. The gate is green. PLAN §5 records the figures and its release note is
  rewritten for the drop classes and the listing; the README's *Many jobs at once* carries the
  figure (ruling 7). P1-P4 and the installed-tool-parity gates re-run green.
- *Amended at review cycle 2's remediation, 2026-11-02, by the foreman's ruling 7:*
  - [x] S is re-run on a Lustre scratch after this change, by the foreman, job 1's body with `S`
    alone. S's damage, every file of the subject's tqdm dist-info, now reaches
    `uvm_cache_index_check` in the holder: tqdm 4.67.1 is fetched under the lock before the
    reinstall, which names tqdm alone. `U` and `ukill` keep `RECORD` and never reach the check, so
    their summaries stand; each environment holds tqdm alone, so naming it changes nothing they
    measure. Locally, `S` ×16 `--large-cache` on this change: exit 0, one repair, `rebuilt=0`,
    `walk_s=0.89`, `hold_s=2`. `evidence/lustre.txt` is left as Run B copied it until the re-run's S
    summary replaces S's block; the gate's evidence half stays green on it meanwhile. The phase is
    in progress at that external wait.
  - *Re-run, 2026-11-02:* the foreman re-ran `U`, `S` and `ukill` at `e25d773`, `U` and `ukill`
    too, since the reinstall now names only the damaged distributions on every in-place repair, not
    on S's path alone. The evidence is replaced by the three new summaries, copied unedited (sha256
    `f23b8cb5…457c`, 128 lines, checked after the copy). Same cache as Run B; `walk_s` 1.93 (U),
    1.85 (S), 2.72 (ukill); `hold_s` 6 and 3, `wait_max_s` 7 and 4; ukill's clean pass `hold_s` 3,
    `wait_max_s` 4; every scenario `progress=ok`, `exit=0`, `rebuilt=0` (`clean_rebuilt=0`),
    `flock=coherent`, `link_mode=hardlink`. S's hold fell from 24 s to 3 s with the narrowed
    reinstall. PLAN §5 records `e25d773` as the run of record, `312b6f7` and `729080d` as history;
    its release note and the README's *Many jobs at once* give 1.9-2.7 s. P1-P4 re-run green.
- *Amended at review cycle 3's remediation, 2026-11-02, by the foreman's ruling 5:*
  - [x] U, S and ukill are re-run on a Lustre scratch at the final commit, by the foreman, the two
    job bodies above unchanged. The walk changed (C3-F1), and every in-place repair now fetches the
    damaged distributions' releases under the lock before its reinstall (C3-F2): `U`'s and
    `ukill`'s tqdm, which keeps its `RECORD`, now reaches the check, as `S`'s did already, so all
    three summaries are stale. Locally at 16 ranks `--large-cache`: `U` `walk_s=2.64 hold_s=4
    wait_max_s=5`, `S` `walk_s=2.34 hold_s=3 wait_max_s=4`, `ukill` `walk_s=2.37`, killed pass
    `restored=0`, clean pass one repair; each exit 0, `rebuilt=0` (`clean_rebuilt=0`). Those
    `walk_s` figures came on a loaded host: `U` ×4 alternated with `52f5bf1` gave 0.79 and 0.77 here
    against 0.81 and 0.70 there, and doctor on the same large cache alternated eight times is
    0.63-0.74 s on both. `evidence/lustre.txt` is left as it is until the re-run replaces it; the
    gate's evidence half stays green on it meanwhile. The phase is in progress at that external
    wait.
- *Amended at review cycle 4's remediation, 2026-11-02, by the maintainer's ruling 4:*
  - [x] U, S and ukill are re-run on a Lustre scratch at the final commit, by the foreman, the two
    job bodies above unchanged; the item above is that same re-run, now at the commit carrying the
    source-only check. Every in-place repair still fetches under the lock, and the comparison now
    hashes fewer paths, so the cycle-3 local figures stand as the expectation. Locally at 16 ranks
    `--large-cache` on this change: `U` `walk_s=0.68 hold_s=1 wait_max_s=2`, `S` `walk_s=0.67
    hold_s=1 wait_max_s=2`, `ukill` `walk_s=0.68`, killed pass `restored=0`, clean pass one repair;
    each exit 0, `rebuilt=0` (`clean_rebuilt=0`). `evidence/lustre.txt` is untouched; the gate's
    evidence half stays green on it.
- *Run B at the final commit, 2026-11-02, by the foreman:*
  - [x] U, S and ukill ran at `fc7184f`, the commit carrying review cycle 5's wheels-only check, on a
    second Lustre scratch (the first was out of service), 2 nodes × 64 ranks, bash 4.4, the job
    bodies above unchanged. U: `walk_s=2.90 hold_s=3 wait_max_s=5`. S: `walk_s=4.37 hold_s=4
    wait_max_s=4`. ukill: `walk_s=2.52`, 127 waiters named the lock, clean pass `hold_s=3`. Each
    `rc_hist=0:128` (clean pass for ukill), one repair, `rebuilt=0`. `evidence/lustre.txt` replaced
    unedited, sha256 `1e01ad60…`. PLAN §5 records `fc7184f` as the run of record, with `e25d773`,
    `3a9ac04` and `e61e360` as history; the README and the release note give 2.5-4.4 s. P1 and P2
    are green under bash 4.4 on that cluster too. No further review cycle runs (the maintainer's
    ruling at cycle 5): the maintainer's review of the 0.8.0 PR is the final gate.
- **Verify:** `sh spec/uv-cache-purge-damage/gates/p4.sh`. Local half: `--launch srun` without
  `REPAIRRACE_SHARED` exits 2; `U` ×16 on the large cache with every new key, `record_lines` ≥
  10,000 and `flock` unmeasured. Evidence half:
  `U`, `S` and `ukill` present, each `launch=srun`, `ranks=128`, `nodes=2`, `progress=ok`, `exit=0`,
  `walk_s` a number, `live_entries` ≥ 22, `record_lines` ≥ 10,000, `link_mode` and `flock` fixed
  words; `U` and `S` every rank
  0 with the expected output, one repair, one ok outcome, no lock, restored, `rebuilt=0`; `ukill`
  `rc_hist=1:127,137:1`, 127 timeouts naming the lock, no outcome, the lock left, doctor's WARN, a
  clean pass of one repair with `clean_rebuilt=0`; no `/` in the evidence; `PLAN.md` records it.
  Inspection-only: *Many jobs at once* against the evidence's `walk_s`.
- **Touches:** `tests/repair-race.sh`, `AGENTS.md`, `spec/uv-cache-purge-damage/evidence/` and
  `PLAN.md` §5 (Run B), `README.md` (Run B).

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative; the `current_phase`
   pointer is reconciled against them.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[feature]` commit; stop and
   report.
