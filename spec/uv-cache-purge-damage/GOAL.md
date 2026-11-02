# GOAL — A purge that damages uv's cache is repaired under `UVM_REPAIR`

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** uv-cache-purge-damage
- **kind:** feature
- **appetite:** big · phase cap 4 (clarification M5)

## Problem

The wrapper points `UV_CACHE_DIR` at `${uvm_root}/cache`, inside the tree a scratch purge reaches,
and three kinds of entry there are what `uv run <script>` and `uvx <spec>` execute or build from.
Measured with uv 0.13.6 during shaping:

- **A script environment** (`uv run --no-project s.py`, PEP 723) is a real directory,
  `cache/environments-v2/<script>-<hash>/`, that uv re-syncs in place on every run.
- **An ephemeral `uvx` environment** is a directory `cache/archive-v0/<id>/` with its own
  `pyvenv.cfg` and `bin/`, reached through a relative link
  `cache/environments-v2/<interpreter-hash>/<resolution-hash>`. The deployed `uv/0.7.0` module
  shows the same layout on a production cluster (seed, 2026-11-01).
- **An unpacked wheel** is `cache/archive-v0/<id>/`, reached through
  `cache/wheels-v7/<index>/<name>/<version>-<tag>`. Every environment is built by copying from these.

`uvm_detect` walks `tools/` and `python/` only (`bin/uv-manager:935-1086`), so `uvm doctor` and the
repair see none of this. `README.md:540` concedes it. `srun uvx <tool>` is the route § *Repairing
inside a job*, *Reach*, recommends, and for a tool that is not installed it gets the scope check
and no repair. Who it hurts is the user inside a batch job that `purge-tree-repair` serves.

**Pre-existing** on `main`. Below is what shaping measured.

**The failure, constructed (R1).** The drive ran with real uv 0.13.6 (macOS arm64,
`UV_LINK_MODE=copy`, `UV_PYTHON_PREFERENCE=only-managed`, a managed cpython 3.12.16) under
`.agents/factory/bin/temp_root.sh`, with the wrapper at `648496d`. The subjects were:

- two script environments: `tqdm==4.67.1`, and `rich==13.9.4` with three dependencies;
- three ephemeral `uvx` environments: `tqdm==4.67.1`, `flake8==7.1.1` with three dependencies, and
  `ruff==0.8.4`, whose executable is a binary in `bin/`;
- the unpacked `tqdm` wheel.

Each shape was applied to a fresh copy of a healthy cache. The next call was then run twice:
`uv run --no-project <script>`, or `uvx <spec> --version`. *Fail* means it fails on both calls.
*Heals* means uv rebuilt the entry or the removed files came back. *Latent* means rc 0 with the
damage still there. *Wrong* means rc 0 by doing something it should not.

| Shape | Script environment | Ephemeral `uvx` environment |
|---|---|---|
| 30% of files at random (2 seeds) | fail 3 of 4: rc 1 `ImportError`, or rc 2, uv's own `failed to open file`; heals 1 | fail 2 of 4; heals 2 |
| the newest 30% by mtime | fail, rc 2 (uv) | fail (flake8); latent (tqdm) |
| one `.py` module | fail, rc 1 (tqdm); latent (an unimported pygments lexer) | fail, rc 1 |
| a dist-info's files, directory kept (a purge's shape) | fail, rc 2 (uv) | fail, rc 1, with nothing on stderr (tqdm) or a `TypeError` (flake8) |
| a dist-info directory whole | heals: `uv run` re-syncs | fail, rc 1, nothing on stderr |
| `RECORD` only (ruff) | — | fail, rc 1, nothing on stderr |
| the executable in `bin/` (ruff) | — | fail, rc 2 (uv) |
| `pyvenv.cfg` | **wrong**: rc 0, and uv installs the script's dependencies into the managed interpreter's own `site-packages` | fail, rc 1 (flake8) |
| the `bin/python` link | heals | heals |
| every file, directories kept | heals | heals |
| the entry removed, moved aside, or its link removed | heals | heals |

Unpacked wheel, shaped and then built from:

- **Existing environments.** They run in every shape, because they hold copies.
- **One module removed.** A new environment built from the wheel copies the damage, and uv exits 0
  while it does. The script then fails with `ModuleNotFoundError`, and so does a new `uvx --with`
  environment.
- **Its dist-info files, every file, or 30% at random removed.** Every later build that needs the
  wheel fails with rc 2 (uv, `failed to open file .../archive-v0/<id>/...`).
- **The directory removed.** uv heals: it downloads the wheel again.

Shapes in `simple-v*`, `interpreter-v*` and the wheels' `.http` and `.msgpack` files all heal.

The remedies a user would reach for:

- **`uv cache clean tqdm`** removes the unpacked wheel and leaves both environments, so both calls
  still fail.
- **`uv cache prune`** removed both environments and left the damaged wheel, which is still
  linked. The environments rebuild from it, and both calls still fail.

Neither is a remedy alone.

**What a process running from an entry sees.** A process was started from an environment, then
imported a module it had not yet imported:

- after its directory was **moved aside**, the import failed with `ModuleNotFoundError: No module
  named 'tqdm'`, for the script environment and for the `uvx` environment's `archive-v0` directory;
- after **only the `uvx` environment's link was removed**, it succeeded, with the archive left in
  place, and the next `uvx` call built a new one;
- after an **in-place reinstall** (`uv pip install --python <env>/bin/python --reinstall --no-cache
  tqdm==4.67.1`, run from `/`) landed while it slept, it succeeded.

That reinstall is the tool arm's idiom. It restored the module, random and dist-info shapes in both
kinds of environment. It cannot reach an environment whose `bin/python` is gone.

**Ruled out as a repair, pre-building.** Pre-building the call's own entry is possible in uv:

- `uv sync --script s.py` rebuilds a script environment;
- `uvx --from tqdm==4.67.1 python -c pass` rebuilt the same `environments-v2` key.

Either one needs the wrapper to find the script or the spec in the user's arguments. Invariant §11
rules that out.

**Against `648496d` with the knob set:**

- `UVM_REPAIR=g1 uv run --no-project s.py`, with `tqdm/std.py` removed from the script
  environment, exits 1, runs no repair, and records the scope *repaired*
  (`.repair/value-g1.ok`). A purge-damaged cache therefore reads as clean for the rest of the
  scope.
- `uvx tqdm==4.67.1 --version` exits 1 the same way.
- `uvm doctor` exits 0, printing `OK no damage detected`.
- With the script environment's `pyvenv.cfg` removed, the knob-set call exits 0 and leaves `tqdm`
  in the managed interpreter's `site-packages`.

**Seed text this corrects.** Three statements in the seed do not hold as written:

- The seed's note on moving a damaged entry aside expected a process with the entry open to keep
  its files. It keeps the files it has open, but a later import resolves by path and fails, as
  measured above.
- The seed says the module sets `UV_LINK_MODE=copy`. The shipped modulefile does not set it, and
  `etc/uv-manager.conf.example:156` carries it commented. Under copy, clone and hardlink alike, an
  environment's files are its own paths, so the damage-to-wheel results above hold. A user's
  `UV_LINK_MODE=symlink` is not covered (non-goal).
- `uv cache clean <pkg>` is not the manual remedy: see above. Clearing the whole cache is.

## Outcome / vision

A job whose cache a purge has damaged sets `UVM_REPAIR=1`, calls `uv run <script>` or `uvx
<spec>`, and proceeds. One call per scope checks the tree, now including the cache's live entries,
and repairs what it finds under the repair lock. The others wait and then run, and none of them
rebuilds what the repair restored. A process already running from a repaired entry keeps running.
That is `purge-tree-repair`'s contract, extended to the `uvx` route's own state. It is half of a
two-route contract:

| Route | Its state | Its purge cases |
|---|---|---|
| `srun uvx <spec>`, `srun uv run <script>` | the ephemeral or script environment and the wheels in `${UVM_ROOT}/<arch>/cache` | this cycle |
| `uv tool install`, then `srun <tool>` | records in `$UVM_DATA`, the payload in `${UVM_ROOT}/<arch>/tools` | [`installed-tool-parity`](../../issues/installed-tool-parity.md) |

Neither route replaces the other. An installed tool is out of this class's reach: its environment
holds its own files, and the tool arm reinstalls with `--no-cache`.

## Acceptance criteria (the contract)

Drives run under `.agents/factory/bin/temp_root.sh` with a real uv seeded into `versions/`, as
`tests/repair-race.sh --uv-bin` does. **Damaged cache** means one of the shapes the R1 table marks
*fail* or *wrong*, applied to a script environment, an ephemeral `uvx` environment, or an unpacked
wheel that a new environment is then built from. A **live entry** is one that a link under
`environments-v2/` or `wheels-v*/` reaches, or a script environment directory. Every *Observed*
status below was recorded on 2026-11-01 at `648496d` (`release/0.8.0`).

- **R1** — A drive against real uv SHALL establish which purge shapes make the next `uv run
  <script>` or `uvx <spec>` fail, heal, or run wrong. It covers a script environment, an ephemeral
  `uvx` environment, and an unpacked wheel that environments are built from. The results SHALL be
  recorded before any repair criterion is shaped.
  *Checked by the shaping drive in **Problem**, re-run by the plan as the baseline for R2–R5 at the
  uv version then pinned. R6's cluster summary records the site's link mode. **Observed: green**,
  recorded above.*
- **R2** — `uv-manager doctor` SHALL report a FAIL naming the entry for each damaged live entry:
  - an environment with a file missing that a surviving `RECORD` lists, an executable under `bin/`
    included;
  - an environment with a dist-info directory that has lost its `RECORD` or `METADATA`;
  - an environment that has lost its `pyvenv.cfg`;
  - an unpacked wheel with a file missing that its `RECORD` lists, or whose `RECORD` or `METADATA`
    is gone.

  It SHALL report no FAIL on a healthy cache. It SHALL stay read-only. It SHALL NOT walk an
  `archive-v0` entry that no link or pointer (`.http`/`.rev`) reaches.
  *Checked by a real-uv drive: each R1 failing shape gives `uvm doctor` rc 1 and a FAIL line naming
  the entry; the healthy cache gives rc 0. **Observed: red** — with `tqdm/std.py` removed from both
  environments, `uvm doctor` exits 0, `OK no damage detected`.*
- **R3** — WHERE `UVM_REPAIR` is set and the scope has no outcome, WHEN the check detects a damaged
  live entry, the call SHALL repair it. The repair runs under `purge-tree-repair`'s lock, scope and
  outcome contract: one call repairs, the rest wait, the outcome is recorded before release, a
  failure fails every call in the scope with its reason, and a dead holder's waiters fail at
  `UVM_LOCK_TIMEOUT` naming the repair lock. After it, `uv run <script>` and `uvx <spec>` SHALL
  exit 0 with the command's own output.

  A repaired environment SHALL hold the same distributions at the same versions as before. The
  repair SHALL NOT build from a damaged unpacked wheel. It SHALL install nothing into a managed
  interpreter's own `site-packages`. It SHALL run from `/`, as the existing arms do. A scope with no
  damage SHALL run no cache repair.
  *Checked by real-uv drives on every R1 failing shape, knob set:*
  - *rc 0 and the expected output;*
  - *each restored environment's dist-info listing identical to before;*
  - *the managed interpreter's `site-packages` listing identical to before;*
  - *a new script needing the damaged wheel runs after the repair;*
  - *a second call in the scope prints no repair line.*

  ***Observed: red*** *— with `tqdm/std.py` removed:*
  - *`UVM_REPAIR=g1 uv run --no-project s.py` exits 1, prints zero repair lines, and records
    `.repair/value-g1.ok`;*
  - *`UVM_REPAIR=g2 uvx tqdm==4.67.1 --version` exits 1.*

  *With `pyvenv.cfg` removed, the knob-set call exits 0 and leaves `tqdm` in the managed
  interpreter's `site-packages`.*
- **R4** — IF a process is executing from an environment the repair touches, THEN a module present
  in that environment before the repair SHALL import in that process after it.
  *Checked by a real-uv drive, for a script environment and an ephemeral `uvx` environment each
  damaged as R1:*
  - *start the environment's `bin/python` sleeping;*
  - *run the knob-set repair;*
  - *import a module present throughout that the process has not yet imported. It exits 0.*

  *The reviewer reads which entries the repair moves or removes. **Observed: vacuously green** — no
  repair runs. At shaping, moving the entry aside failed this import and an in-place reinstall
  passed it (**Problem**).*
- **R5** — WHEN calls in a scope wait on a cache repair, no waiter SHALL rebuild an environment or
  unpack a wheel that the repair restored. WHERE the repair removes an entry instead of restoring
  it, `README.md` SHALL name that class. It SHALL say that the next call on each node rebuilds such
  an entry concurrently where `flock` is node-local, and that uv fails outright where `flock` is
  absent.
  *Checked by a real-uv drive of 16 ranks: the `archive-v0` entries and `environments-v2` links
  created after the holder's release number 0 for the classes the repair restores. Then the
  reviewer reads `README.md` for the classes it removes. R6 records the count across nodes.
  **Observed: not constructible** — no repair.*
- **R6** — WHEN a job runs 128 ranks under `srun` on 2 nodes, `UVM_REPAIR=1`, against a damaged
  cache on a parallel filesystem:
  - in scenario (U), the damage is an ephemeral `uvx` environment and each rank runs `uvx <spec>`;
  - in scenario (S), it is a script environment and each rank runs `uv run <script>`.

  In each, exactly one rank SHALL repair, every rank SHALL exit 0 with the expected output, and no
  lock SHALL be left.

  A kill scenario SHALL record purge-tree-repair's R9 (c) outcome on a damaged cache:
  - every waiter exits non-zero at the timeout, naming the repair lock;
  - `uvm doctor` WARNs the lock;
  - a clean pass after `uvm clean lock --yes` repairs once.

  *Checked by `tests/repair-race.sh`, extended with the scenarios (names are the plan's) and run by
  the foreman on Lustre across 2 nodes × 64 ranks; GPFS on 1 node × 64 is optional (M4). Taken on
  trust.*

  *The drive's cache is realistic, not only the subjects under test (M1). Before the damage it
  holds at least 20 other live entries: script and `uvx` environments over a mix of packages.*

  *The summary holds counts only:*
  - *repairs, outcomes, `rc_hist`, `stdout_hist`, locks left;*
  - *the holder's repair seconds, and the detection walk's seconds beside the cache's file count
    and its number of live entries;*
  - *the entries waiters rebuilt (R5), notice lines, and the link mode.*

  ***Observed: not constructible.***
- **R7** — WHILE `UVM_REPAIR` is unset, the call SHALL walk no part of the cache and write
  nothing, as on `release/0.8.0`. The interpreter and tool arms SHALL behave as they do there.
  *Checked by `tests/repair-race.sh --scenario F --ranks 16`, and `--scenario T --ranks 8 --uv-bin
  <uv>`, both exit 0, `progress=ok`, with P and kill as the plan's phase gate. Then by the hot-path
  measurement `purge-tree-repair`'s R1 names. The reviewer reads that the cache walk sits behind
  the knob and the lock. **Observed: green** — F: `repairs=1`, `outcome_kind=ok`, `locks_left=0`;
  T: `unpinned_version=2.11.1`, `second_dist_info=0`, `receipts_kept=2`. Expected green after.*
- **R8** — The surfaces `AGENTS.md` § *Same-commit rule* names SHALL stop listing cache damage as
  conceded. Those are the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example` and
  `share/modulefiles/uv/main.lua`. Each SHALL say that `uv run <script>` and `uvx <spec>` are
  repaired for it under the knob. `README.md` SHALL add partial cache loss to its purge table. It
  SHALL keep listing what R2 leaves unseen:
  - an environment's dist-info directory removed whole;
  - packages a pyvenv-less run already put into a managed interpreter;
  - `UV_LINK_MODE=symlink`.

  It SHALL name clearing the whole cache as the manual remedy, and say that `uv cache clean <pkg>`
  or `uv cache prune` alone leaves the failure in place. It SHALL bring *Many jobs at once* up to
  date with the walk time R6 records.
  *Checked by `git grep -n "Damage inside uv's cache is not checked" README.md` returning nothing,
  then the reviewer reading each surface against this list. **Observed: red** — one hit,
  `README.md:540`.*

## Non-goals (no-gos)

- **Installed tools.** `tools/` and the route `uv tool install` then `srun <tool>` belong to
  [`installed-tool-parity`](../../issues/installed-tool-parity.md), which builds first.
- **A uv command-line model.** The repair does not find the script in `uv run` or the spec in `uvx`
  to pre-build the call's own entry. Invariant §11 rules that out, though uv could do it (Problem).
- **`archive-v0` entries no link or pointer reaches.** `uv cache prune` collects them. They are neither walked
  nor repaired.
- **Contamination already in a managed interpreter.** Packages an earlier pyvenv-less run put
  there are not detected or removed. The python arm's probe passes them, and R8 documents them.
- **`UV_LINK_MODE=symlink`**, where an environment's files are links into the wheel. It is not
  measured, and R8 documents it.
- **Project `.venv` directories.** They live outside the tree.
- **The interpreter and tool arms.** They are unchanged (R7).
- **Separately submitted jobs queueing on the walk.** That stays as `purge-tree-repair` left it. R6
  records the longer walk, and R8 updates the README's arithmetic.
- **Anything `purge-tree-repair` ruled out.** No new environment variable, no subcommand, no change
  to the lock contract, and no offline repair mode.

## Clarifications

Rulings at the GOAL gate are the foreman's, as the maintainer's delegated judge.

- **Q:** Does this cycle have a problem to solve? — **A:** Yes. R1 constructed failures in
  all three kinds of entry, and one silently wrong run. uv heals only the shapes that take an
  environment's interpreter link, all of its files, or the entry itself (shaping, 2026-11-01).
- **Q:** Which cycle goes first? — **A:** This cycle plans and builds only after
  `installed-tool-parity` has landed on `release/0.8.0`. That cycle rewrites the trampoline, the
  `uv tool` intercept and parts of the repair dispatch. This branch starts from `release/0.8.0` at
  `648496d` (foreman ruling, 2026-11-01).
- **Q:** Does the check walk the whole cache, or only the entry this call will use? — **A:** The
  live entries of the whole cache, once per scope, as `purge-tree-repair` walks the whole tree.
  Finding the call's own entry needs uv's hashing or a command-line model, and §11 rules that out
  (shaping reading, 2026-11-01).
- **Q:** Does moving a damaged entry aside protect a running process? — **A:** No. Measured: a later
  import resolves by path and fails. R4 states the protection as behaviour and leaves the mechanism
  to the plan. Removing only the link of a `uvx` environment, and an in-place reinstall, passed it
  (shaping, 2026-11-01).
- **Q:** Is the repair's mechanism settled here? — **A:** No; it is the plan's. R3–R5 bind it. Shaping
  measured that the tool arm's per-environment reinstall restores both kinds of environment in place,
  which satisfies R4 and R5 by construction, and that it cannot reach an environment without
  `bin/python` or `pyvenv.cfg`.
- **Q:** Does pre-building the call's own entry belong in this cycle? — **A:** No. It needs the
  wrapper to find the script or spec in the user's arguments, which invariant §11 rules out. It is
  a non-goal (foreman ruling, 2026-11-01).
- **M1 — Q:** Does the detection walk carry a time budget? — **A:** No threshold. The walk stats
  every file a live entry's `RECORD` lists, one metadata round trip each on Lustre, and a cache is
  larger than `tools/`. R6 records the walk's seconds beside the cache's file count, and the README
  states the figure, as `purge-tree-repair` ruled for hold time. A walk past about 30 s on the
  cluster cache is a review finding. The plan may then narrow the check to the dist-info and
  `pyvenv.cfg` tests, which catch R1's dist-info and `pyvenv.cfg` shapes but not a lone module or a
  lone executable. So that the timing means something, R6's cache holds at least 20 other live
  entries, script and `uvx` environments over a mix of packages. Amended: R6's *Checked by*
  (foreman ruling, 2026-11-01).
- **M2 — Q:** Must every R1 shape be restored in place, or may the repair remove an entry? —
  **A:** Either, under R4 and R5 as written. An in-place restore leaves waiters nothing to rebuild.
  The repair may remove only an entry that no process can be using safely: an environment without
  `pyvenv.cfg` or `bin/python`, a `uvx` environment's link, or an unpacked wheel. R5's documentation
  covers each class it removes (foreman ruling, 2026-11-01).
- **M3 — Q:** What does the repair do with a cache environment that lost `pyvenv.cfg`? — **A:** It
  never reinstalls one in place, since uv would use the base interpreter in its place and install
  there. It removes the link of a `uvx` environment. It removes or recreates a script environment
  before any uv call that could reach the base interpreter. This is deliberately the opposite of
  the tool arm, which refuses a tool without `pyvenv.cfg` and fails the scope (`purge-tree-repair`
  R5). The asymmetry is not an inconsistency. A tool directory holds state the user created, a
  receipt and a chosen version, that a rebuild could lose. A cache entry holds nothing uv cannot
  rebuild from the script or spec the next call names (foreman ruling, 2026-11-01).
- **M4 — Q:** On which filesystems does R6 run? — **A:** Lustre across 2 nodes × 64 ranks is
  required. GPFS on 1 node × 64 is optional, at the foreman's discretion. The summary records whether
  the mount's `flock` is coherent across nodes or node-local, as a fixed word (foreman ruling,
  2026-11-01).
- **M5 — Q:** What are the appetite's bounds? — **A:** `big`, at most 4 phases:
  1. detection in doctor (R2);
  2. the repair and its protections (R3, R4);
  3. waiters, the local race drive and the documentation (R5, R8);
  4. the extended cluster drive (R6).

  At most 3 review cycles. The target is landing on `release/0.8.0` by about 2026-11-10. If phase
  2 cannot meet R4 in place for script environments, removal under M2 is the fallback, not a fifth
  phase (foreman ruling, 2026-11-01).
- **C1-F3 — Q:** Is a wheel whose link the purge took, while its pointer stayed, a live entry? —
  **A:** Yes. uv reaches the archive through the pointer file beside the link, `<link>.http` for an
  index's wheel and `<link>.rev` for a URL's, a path's or a find-links directory's, and builds new
  environments from it, damage included (review cycle 1, C1-F3). Measured with uv 0.13.6: the
  pointer is msgpack, and the archive's id is the 16 characters from `[A-Za-z0-9_-]` that follow
  the byte `0xb0` in both kinds. The walk reads a pointer only when its link is gone or dangling,
  and walks the archive it names only when that archive exists. The repair removes the pointer
  files and never an archive, and doctor stays read-only. Amended: R2 and the non-goal read "no
  link or pointer" (foreman ruling, 2026-11-02).

## Notes

- The claim in `installed-tool-parity`'s seed and GOAL that "the module sets `UV_LINK_MODE=copy`"
  is false. The shipped modulefile does not set it, and `etc/uv-manager.conf.example:156` carries
  it commented (**Problem**, measured 2026-11-01).

## Related materials

- Seed: [`issues/uv-cache-purge-damage.md`](../../issues/uv-cache-purge-damage.md).
- The contract reused: [`spec/purge-tree-repair/GOAL.md`](../purge-tree-repair/GOAL.md) R2, R7,
  R9, R10, R12, R13 and its `REVIEW.md`, including the ruling that the arms run from `/` (C4-F1).
- [`spec/purge-resilient-run/research/00-digest.md`](../purge-resilient-run/research/00-digest.md)
  D3 and [`04-uv-repair-idioms.md`](../purge-resilient-run/research/04-uv-repair-idioms.md) §1, §4.
  Those are the earlier measurements of a damaged `archive-v0` and of the escape through a missing
  `pyvenv.cfg`.
- Code: `uvm_detect`, `uvm_repair_run` and `uvm_repair` in `bin/uv-manager`, and the dispatch tail.
- Instruments: `tests/repair-race.sh` and `.agents/factory/invariants.md` §5, §7, §8, §10 and §11.
- Sibling seeds: [`installed-tool-parity`](../../issues/installed-tool-parity.md) and
  [`repair-scope-queueing`](../../issues/repair-scope-queueing.md).
- `README.md` § *Scratch purges and what uv does not notice* and § *Repairing inside a job*.
