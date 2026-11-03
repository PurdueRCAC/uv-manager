# AGENTS.md

Guidance for coding agents (Claude Code and others) working in this repository. `CLAUDE.md` is a
symlink to this file — edit `AGENTS.md`, never a separate copy. (`.claude` is likewise a symlink to
`.agents`, so Claude Code finds the factory skills and settings through it.)

This is the operating manual: the architecture, the load-bearing invariants, and the process rules an
agent needs to make correct changes here without rediscovering them. When something below disagrees
with the code, **the code is ground truth — fix this file.**

---

## Project

`uv-manager` is a transparent wrapper around [`uv`](https://docs.astral.sh/uv/) that makes it behave
correctly on an HPC cluster: no home-directory quota consumption, no architecture mismatch between
login and compute nodes, no state shared between users. Users type `uv` and `uvx` and get the real
thing.

It is **one bash script**, `bin/uv-manager`, plus three symlinks to it. Sites deploy it centrally
(`/apps/external/uv/main/bin/`) and expose it through an Lmod module. `README.md` is the design
rationale and the user/administrator documentation; it is written for a site operator, not for us.

Deployed centrally, this is potentially load-bearing infrastructure for a computing center: it sits
under every user's `uv`, and under automation that provisions environments without a human watching. A
defect here does not produce a stack trace on a laptop — it produces `Exec format error` thousands of
lines into a job log, after the allocation has been charged. Correctness is not negotiable against
convenience.

## Environment & working rules

- **`del`, not `rm`** — `rm` is blocked in this environment. Use `del <path>` (reversible trash;
  directories need no flags).
- **Commit only when explicitly asked.** When you do, branch off **`main`**; there is no `develop`.
  Lifecycle work goes on `feature/{slug}` or `fix/{slug}` and lands on `main` by squash.
- **Squash merges.** Commit subjects are `[category] Imperative summary`. Categories in use:
  `feature`, `fix`, `docs`, `refactor`, `release`, and `harness` (the `.agents/` factory). The set is
  not closed — coin a lowercase category when one genuinely fits.
- **Commit messages are short.** Subject at most 72 characters. A body is optional and earns its place
  the way a comment does: it records a decision, a rejected alternative, or a consequence the diff does
  not show. It never narrates the diff or lists the files touched. Two or three lines is a normal body;
  past about fifteen, the commit should have been two commits. The *Prose and comments* rules below
  apply here too.
- **Keep the `Co-Authored-By: Claude Opus 5` trailer** on commits. This repo records it; that is a
  deliberate difference from other projects you may have seen. PR bodies end with the Claude Code
  generation line.
- **Version is single-sourced** at `readonly uvm_version=` (`bin/uv-manager:21`). Two places quote it
  and must move with it: the sample output in `README.md` and any pinned example. Never hardcode a
  version anywhere else.
- **Same-commit rule.** A change to wrapper behavior updates, in the *same commit*, whichever of these
  it invalidates: the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example`, and
  `share/modulefiles/uv/main.lua`. The script's own help text and the README are the only user-facing
  documentation; drift there is a defect, not a chore. A change that **overturns an invariant** asserted
  below adds two more: § *Invariants* and `.agents/factory/invariants.md`. `/uvm-review` grades against
  that file, so a section left asserting the decision a change reversed turns correct code into an
  auto-CRITICAL finding. Overturning one is a design decision, not bookkeeping — it belongs in the
  plan's deviation table and in front of a human, never in the diff alone.

## Commands

There is no build system and no package manager. Everything is a shell command.

```bash
bash -n bin/uv-manager                       # syntax check (fastest gate)
.agents/factory/bin/lint.sh                  # bash -n + shellcheck + symlink integrity

.agents/factory/bin/temp_root.sh uvm status  # drive the wrapper in a throwaway state root
.agents/factory/bin/temp_root.sh --offline uv --version         # provision from a local fixture
.agents/factory/bin/temp_root.sh --offline --arch aarch64 uvm status
```

`shellcheck` is obtained through `uvx --from shellcheck-py shellcheck` — no system install, and the
tool this project wraps supplies its own linter. `lint.sh` does this for you.

**Never drive the wrapper without `temp_root.sh`.** A bare `bin/uvm install` writes into the
developer's real `UVM_ROOT` (or resolves one from `$SCRATCH`) and can download hundreds of
megabytes. `temp_root.sh` scrubs every inherited `UV_*`, `UVM_*` and scratch variable, points the
root at a temp directory, and removes it on exit.

## Repository map

| Path | Responsibility |
|------|----------------|
| `bin/uv-manager` | **The script.** Everything below lives here. |
| `bin/{uv,uvx,uvm}` | Symlinks to it. Mode is chosen by `basename $0`, not by symlink-ness. |
| `etc/uv-manager.conf.example` | Site settings, heavily commented. Every variable in it is real. |
| `share/modulefiles/uv/main.lua` | Example Lmod modulefile. Exports only architecture-neutral paths. |
| `README.md` | Design rationale + user and administrator documentation. |
| `tests/` | Executable drives: the provisioning-lock race, and the purge-repair race across nodes, for interpreters, tools, installed-tool restores and uv's cache. |
| `.agents/` | The spec-driven software factory (skills, methodology, templates, scripts). |
| `spec/{slug}/` | Committed, dated per-feature design records. Retained on merge. |
| `issues/{slug}.md`, `ROADMAP.md` | Deferred code work and its ordered index. |

Inside `bin/uv-manager`, the sections are banner-commented in execution order: identity dispatch,
diagnostics, state root, platform key, knobs, locks, fetching, install, storage layout,
trampolines, argument inspection, `self update` interception, subcommands, purge repair, dispatch.

## Execution model

```
argv[0] ──► mode (uv | uvx | manager)
              │
   manager ───┴──► uvm_manager_main          help/--version answer before uvm_init
              │    └─ _trampoline NAME ─► uvm_tool_entry: a trampoline's way in; knob on, the
              │                           scope check, then the restore by name if the shim is
              │                           still missing (locked), then exec the shim; else the
              │                           shim or 127
              │
   uv/uvx ────┴──► uvm_init                  resolve root, append arch, derive paths
                   uvm_parse_command         find the first positional argument
                   uvm_ensure_uv             provision if needed (locked)
                   uvm_export_env            export UV_*, UVM_ROOT, UVM_DATA + prepend PATH
                   (self-heal)               no marker in $UVM_ROOT/bin: sync the trampolines
                                             once per root
                   uvm_repair                only with UVM_REPAIR on: once per scope (locked)
                   ├─ self update ──► intercepted, re-provisions, execs uv --version
                   ├─ tool | python ─► run to completion, resync trampolines, exit rc
                   └─ everything else ─► exec the real uv
```

The wrapper adds roughly 5 ms. That budget is real: `uv run` appears inside loops that call it
thousands of times. Anything added to the hot path (a subshell, a `find`, a second `uname`) has to
justify itself.

## Invariants (read before editing `bin/uv-manager`)

The curated, enumerated form of this list is
[`.agents/factory/invariants.md`](.agents/factory/invariants.md), kept **in lockstep with this file**
— if the two drift, this file wins. Summarized here:

**Architecture is resolved at exec time, on the executing node.** `UVM_ROOT` is
architecture-*neutral*; the wrapper appends `<arch>`. A modulefile is evaluated on an `x86_64` login
node and copied verbatim to `aarch64` compute nodes by `sbatch --export=ALL`, so no
architecture-bearing path may ever be exported from outside the wrapper. This is the whole reason the
project exists; violating it fails silently and expensively. The paths a modulefile may put on `PATH`
are the deployment `bin/`, `$UVM_DATA/bin` (the record trampolines) and `$UVM_ROOT/bin` after it (this
root's trampolines, from its shims). All three are neutral.

**`exec`, not a subprocess.** Signals, exit codes and process accounting must be the real `uv`'s. The
two exceptions — `uv tool` and `uv python` — change what needs a trampoline and so must run to
completion, capture `rc`, resync, and exit `rc`.

**No `/tmp` fallback for the state root.** Deliberate. Node-local storage would mean a cold cache and
a re-download on every node of every job, an egress requirement everywhere, and environments that
vanish at job end. When nothing resolves, the wrapper prints every candidate it tried and why each
failed, then exits non-zero.

**A pin is authoritative** over which version a call selects, and over `current` while no concurrent
call on the same root selects a different version. `UVM_PIN` selects which version `current` points
at — not merely which version to download when nothing is present. `current` is one link per root
and a pin is per process, so concurrent calls pinned to different versions race for `current` and
the last swap wins: an earlier call can exec a later call's version at status 0. Calls sharing one
pin, as the ranks of an `srun` job do, agree on `current` whichever swap lands last.

**The locks are `mkdir`.** Atomic on Lustre, GPFS and NFS; needs no helper binary; does not depend
on `flock`, which `uv` itself requires but which is not enabled on every parallel filesystem. There
are two, side by side in the per-architecture root: `.install.lock` for provisioning and
`.repair.lock` for the purge repair. They guard disjoint parts of the tree, and no call holds both,
because `uvm_ensure_uv` has released before the repair begins; one `uvm_lock` global therefore
names everything a process holds. A repair waiter fails at `UVM_LOCK_TIMEOUT`, so behind a shared
lock it would fail on an unrelated slow download. Each lock releases on `EXIT`, `INT` and `TERM`, not only on return, through `uvm_unlock`, which acts only
on `uvm_lock`: a process holds a lock exactly while `uvm_lock` names it, and removes only a lock it
holds. `uvm_unlock` clears `uvm_lock` before removing anything, because in the opposite order a
signal landing after the `rmdir` would make the trap remove the lock the next caller took in the
meantime. The cost is that bash handles a trapped signal only after the foreground command returns,
so a signal while the lock is being created, before `uvm_lock` names it, or being removed, after
`uvm_lock` is cleared, can leave the lock standing, empty or still carrying its owner line. No call
removes it on its own: `uvm doctor` reports it and a human removes it with `uvm clean lock`. Until
then a provisioning call whose request is not yet satisfied waits until it is or until
`UVM_LOCK_TIMEOUT` passes, a forced `uvm install` waits even on a warm tree, and a repair call with
no outcome recorded for its scope fails at the timeout. That is the accepted failure mode. The caller names the predicate a waiter runs once a second to ask whether its work is
already done, and provisioning's predicate tests **the version this call was asked for** — testing
"is some uv present" hands a pinned caller whatever another process happened to be installing.
There are three callers. Besides provisioning and the scope's repair, `uvm_restore_by_name` takes
the repair lock to restore the one tool a knob-set call runs by name when its shim is still missing
after the check; its predicate is that shim executable or a failed record for the scope and the
tool (`<scope>+tool-<tool>.failed`) present, tested on arrival, while waiting and once the lock is
won. Success writes nothing, since the shim is the evidence; a failure is recorded so that its
waiters fail with the reason rather than at the timeout.

**Only the creator removes the lock.** `uvm_unlock` releases by path, and that is sound because
nothing but this process's own winning `mkdir` sets `uvm_lock`: no call removes or takes another
call's lock, whatever its age or its owner line records, and the wrapper never asks whether a holder
is alive, a question a shared filesystem cannot answer reliably. The one exception is a human, by
hand or through `uvm clean lock`, which removes both lock directories and nothing else; clearing a
lock whose holder is still running lets a second call provision or repair beside it, which is why
every message that points at a lock says its holder may still be running. `uvm doctor` reports each
standing lock, provisioning or repair, with its owner line, as a WARN and never a FAIL, and reports
every staging copy left under `versions/` the same way; it removes neither. It also WARNs each
failed repair outcome recorded under a value, and each failed restore by name under a value, with
its reason and `uvm clean outcomes --yes`, and counts those under Slurm jobs, both kinds, on one
line without opening them, since a read would refresh a
record's atime and keep it alive through the purge. `uvm_lock`
is set as soon as the winning `mkdir` returns, *before* the `host=<uname -n> pid=<pid>` line is
written to `owner`, so a failed write — fatal, with `cannot record ownership` and the errno the
shell's own diagnostic names — is cleaned up by the EXIT trap's release, entry and directory both.
The owner line is for a human; nothing in the wrapper decides anything from it.

**No lock survives an `exec`.** `exec` replaces the process image and the EXIT trap never runs, so
every `exec` of the real `uv` releases first — the three in the dispatch tail and the one in
`uvm_self_update`. The repair takes its lock that late in the dispatch path and releases it before
it returns, so the pre-exec release is a guard that keeps a leak impossible if that changes; on a
path holding no lock it costs one builtin test and no fork. A new `exec` site owes the same call.

**Contention is told from failure by persistence, not by a second look.** A `mkdir` that failed
`EEXIST` and a holder that released before the `[[ ! -d ]]` test look identical afterwards, so one
absence is evidence of nothing — it reported a released lock as an unwritable filesystem for 2–4% of
ranks in 64-way cold bursts, on GPFS and on APFS alike. The waiter retries, and names the
permissions, quota or ENOSPC fault only once a literal bound of attempts has each found the lock
gone. The bound is a constant in the script and never an environment variable, and the count never
resets, which holds the iterations it can add to the wait to that bound however the loop alternates.

**`UVM_LOCK_TIMEOUT` is form-tested, then forced to base 10, inside `uvm_acquire_lock`.** On bash
3.2 a non-numeric value makes the arithmetic fatal under `set -u`, and the EXIT trap's status
overrides the error's, so the script exits 0 and `VER=$(uv --version)` returns empty and true; bash
also reads `0600` as 384, and `0800` is not a number at all. The guard sits inside the function,
never at load, so `uvm help` and `uvm --version` still answer on a node whose configuration is
broken.

**A waiter speaks once, then proceeds or fails.** At `min(30, UVM_LOCK_TIMEOUT)` seconds it prints
one notice naming the lock, the `owner` line it records, that the holder may still be running, and
`rm -f '<lock>/owner' && rmdir '<lock>'` — two steps, because a bare `rmdir` reports `Directory not
empty` while `owner` is inside, and an absolute path rather than a `uvm` command, because a reader on
another node, architecture or `UVM_ROOT` would otherwise clear a different lock and be told it
succeeded. At `UVM_LOCK_TIMEOUT` a provisioning waiter (`proceed`) returns holding nothing and
installs for itself; any other caller, the repair waiter among them, dies naming the lock and its
owner line, and runs nothing. The words are the lock's own: a repair caller's messages say "repair
lock" and "repairing", never "provisioning".

**`current` is swapped atomically, and its target is relative** (`versions/<ver>`), so the tree stays
relocatable. With GNU (`-T`) or BSD/macOS (`-h`) `mv`, a concurrent reader never observes a missing
or half-written `current`; an `mv` with neither takes a non-atomic fallback that can leave `current`
briefly missing. Under it, a concurrent swap can turn a call's rename into a `.current.<pid>` link
nested inside the version directory that swap selected, so the call's own swap never lands. When
that swap selected a different version, `current` never names the version the call selected and the
call execs the other version at status 0.

**Scrub `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` before running the installer.**
`install.sh` checks them *before* `UV_UNMANAGED_INSTALL` and they take precedence; if a user has
either exported, `uv` lands elsewhere, the expected binary never appears, and every later invocation
re-runs the installer and fails. Mirror-related variables are left alone — they only redirect where
the tarball comes from, which is legitimate site policy.

**stdout belongs to the user's command.** Provisioning is a side effect of whatever was actually
asked for. `VER=$(uv --version)` on a cold node must not come back with installer chatter ahead of the
answer, so installer output goes to stderr and multi-line wrapper output uses a heredoc (`cat` dies
quietly on `SIGPIPE`; bash's `printf` builtin reports `write error: Broken pipe`).

**`UVM_REPAIR` off forks nothing.** Unset, empty or `0` is a single `[[ ]]` in the dispatch tail,
with no fork and no filesystem access; what the unset path does cost is bash parsing the added code,
about 0.6 ms per call. On, a call whose scope already has an outcome costs one `stat` for a repaired
one, and one read for a failed one's reason. The scope is the Slurm job, else the knob's value. A
repaired record in an array task, which `SLURM_ARRAY_TASK_ID` marks, is keyed on
`job-[<SLURM_CLUSTER_NAME>-]<SLURM_ARRAY_JOB_ID>`, so the array shares it; every other record, a
failed one in an array included, on `job-[<SLURM_CLUSTER_NAME>-]<SLURM_JOB_ID>`, so the next task
of an array tries again. The name is built by builtins: every byte outside a class that lists
its characters rather than ranging them, `a-z 0-9 . -`, is written as `_` and two hex digits, so no
two scopes share a name, on a filesystem that ignores case too. The holder records the outcome under `.repair/` before it releases, a failed one under a
temporary name renamed into place, so a waiter that sees the lock go also sees a whole outcome. The
walk is `uvm_detect`, the same one `uvm_doctor` runs, and only the call that won the lock runs it;
it flags only damage the repair can act on. The interpreter arm names each damaged install by its
key, an install whose binary is gone included. The tool arm runs once per damaged tool, `uv pip
install --python <tool>/bin/python --reinstall --no-cache` with every distribution pinned at the
version its dist-info directory name records, so it never writes a receipt, keeps every version,
pinned or not, and touches no healthy tool; it refuses a tool without `pyvenv.cfg`, one whose
`bin/python` does not run, one holding a distribution whose `direct_url.json` records a URL, git or
path source, and one whose receipt records a requirement, constraint or override from such a
source, the only use it makes of the receipt (`uvm_tool_receipt`). Its index options are not a
refusal: uv writes a configured index into every receipt, and the repair runs under the same
configuration. The cache arm, `uvm_repair_cache`, runs last, after the interpreters it builds on:
each damaged cache environment that still has `pyvenv.cfg` and a running `bin/python` gets the tool
arm's reinstall for its damaged distributions only, the complete set the walk found
(`uvm_cache_fixd`): `--python <entry>/bin/python --reinstall-package <name>… --no-cache`, pinned by
`uvm_record_constraints` over those dist-info directories (versions, `direct_url.json` sources), so
every other distribution keeps its files byte for byte. Every other damaged live
entry is removed for uv to rebuild (`uvm_cache_remove`), all before the arm's first `uv` call that
could reach the base interpreter (only `uvm_cache_index_check`'s fetch comes earlier, for an
environment that is still a virtualenv, into a target of its own): a
cached environment's link, never the archive behind it, also when any distribution in it is not
shown to come from the configured index (`uvm_cache_unpinnable link`, over every distribution: a
dist-info without `RECORD`, a `direct_url.json` kept, or one or a `uv_cache.json` listed in a
`RECORD`, or a `uv_cache.json` on disk, with no `direct_url.json` beside it); a script environment, renamed aside to
`.<name>.<host>.<pid>.<random>` and then removed, a removal that cannot finish noted and passed; an
unpacked wheel's pointer files `<link>.<ext>` but `<link>.lock`, then the link, a wheel whose link
was gone included, which the walk reached through its pointer (`uvm_cache_pointee`). A script
environment with a damaged distribution whose `RECORD` lists a `direct_url.json` that is gone, or
that keeps or lists a `uv_cache.json` with no `direct_url.json`, fails the scope rather than be
pinned by version (`uvm_cache_unpinnable script`, over the damaged distributions only). Every
other damaged distribution either kind would pin by version, its `RECORD` kept or not, is pinned
only once `uvm_cache_index_check` shows the configured index serves the same release: the versions
fetched in one `--no-deps --no-cache` call per environment from `/` into a dot-named target in
`environments-v2`, removed on every path, then compared by the environment's interpreter under
`-I -S`, wheels only: a distribution whose dist-info directory, in the environment or in the
target, holds `uv_build.json` was built by uv from an sdist (measured with uv 0.13.6: written for
every sdist build, the target's included, never for a wheel), and passes once fetched, since a
build is not reproducible (numpy writes its build interpreter's path into a `.py`), so a fork
served as an sdist is conceded. A wheel is compared on source files only (`*.py` and `*.pyi`
outside the dist-info directory and `bin/`, so a fork differing only in an extension or metadata
is conceded): a surviving `RECORD`'s sha256 entries against the release's `RECORD` for the same
paths, or else each source file the environment still holds hashed; a release with none in common
passes. A mismatch or a release the index does not serve fails a script environment's scope
naming the distribution and `uv-manager clean cache --yes`; a fetch that failed fails it naming
the distribution and the fetch, with no remedy. The fetch runs with `NO_COLOR=1` and
`FORCE_COLOR` and `CLICOLOR_FORCE` unset, and is a failed fetch only on a positive marker: exit 2,
`Failed to fetch`, "not found in the cache" or a network-disabled hint, or a hint naming
`401 Unauthorized` or `403 Forbidden`; every other non-zero exit, an `exclude-newer` hint
included, is a release the index does not serve. Either removes a cached environment's link. Each
reinstalled environment
is walked again (`uvm_cache_clean`). A cached environment whose reinstall fails, or that is still
damaged on the second walk, loses its link after the reinstalls; a script environment in either
state fails the scope.
A failed rename or removal fails the scope naming the entry. Every arm
runs from `/` in a subshell, so the user's and the system's `uv.toml` and the `UV_*` variables apply
and the working directory's `pyproject.toml` and `uv.toml` do not. Every arm names its targets, so a
repair never applies the job's Python request. The repair never calls
`uvm_install`, so it cannot move `current`, and every byte it writes, uv's included, goes to stderr.
No message on the `uv` and `uvx` path names `pip install` or `python install`: the offline fixture
echoes its command line and the drives count those lines as repairs. Doctor's remediation block
names both, and runs only under `uv-manager`.

**The restore sits beside the repair, between the interpreter arm and the tool arm.**
`uvm_detect_records` runs first in `uvm_detect`: a recorded tool with a trace in this tree (its
directory, or a shim its record names, dangling or not) that lost its directory, `pyvenv.cfg`,
interpreter link, an executable or its receipt goes on `uvm_restore_tools`, and the walk's other
passes skip it, so no 0.7.0 refusal reaches a recorded tool; a recorded tool with no trace is never
restored by the walk, only listed for doctor. A damaged recorded tool the tool arm would refuse
(`uvm_tool_refusal`) joins the restore. `uvm_restore` replays the record: `uv tool install --force
-c <record>/constraints <request>`, from `/` in a subshell, `UV_PYTHON` the recorded minor (so a
request's own `--python` wins), `UV_NO_CACHE=1`, every byte to stderr. Resolution stays the user's:
the pins are constraints, `uv.toml` and the `UV_*` variables apply. It reads its recorded request
for three token classes only, `--force` (dropped), `<name>[extras]@latest` (`@latest` dropped) and
the local-file options (refused, as is a `@ file:` constraint), and never models `uv`'s command
line. It is the one place the wrapper writes a receipt, and what it writes is uv's own: the record's
byte copy goes back over the replay's pinned receipt when every `install-path` in it names this
`UV_TOOL_BIN_DIR`, else a `.uvm-restored` file marks the tool pinned by a restore. It never writes
the record. The tool arm stays the first choice for every other damaged tool, recorded or not,
because it keeps the receipt byte for byte. `uvm_backfill` writes a record only for an installed
tool with a receipt, `pyvenv.cfg` and no record, from one `uv tool list` run from `/` with
`UV_NO_CACHE=1`, and never rewrites one; the repair's holder, doctor, and the `uv tool` intercept on
`rc == 0` call it, `|| true`. It skips a tool whose receipt records a git, URL or local source whose
`direct_url.json` is gone (`uvm_unpinnable`): a record pinned by version alone would restore a branch
head or an index's release, so that tool keeps the tool arm's refusal and doctor names it. Doctor
writes nothing under `UVM_ROOT`: its interpreter probe runs with `PYTHONDONTWRITEBYTECODE=1`, it
backfills only where uv's `tools/.lock` already exists (the list creates it, and a purge takes it),
reporting each tool with no record otherwise, and its trampoline sync is `uvm_trampolines records`,
`$UVM_DATA/bin` alone.

**Storage is ours; resolution is not.** The wrapper sets `UV_CACHE_DIR`, `UV_TOOL_DIR`,
`UV_TOOL_BIN_DIR`, `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR` and `PATH`, and exports `UVM_ROOT`
(the resolved root, the cascade's included) and `UVM_DATA` to everything it runs, so a trampoline
finds the shims and a child that re-enters the wrapper resolves the same trees; both are neutral. It deliberately leaves
`XDG_CONFIG_HOME`, `UV_CONFIG_FILE`, `UV_PROJECT_ENVIRONMENT`, index variables, `UV_LINK_MODE`,
`UV_COMPILE_BYTECODE` and `TMPDIR` alone. The first two would change dependency resolution; the rest
are site or user policy.

**The durable tree holds records and trampolines and nothing else.** `UVM_DATA` (default
`${XDG_DATA_HOME:-$HOME/.local/share}/uvm`, resolved in `uvm_init` with builtins, empty when none of
the three is set) is the one place the wrapper writes outside `UVM_ROOT`. After a `uv tool install`,
`upgrade` or `uninstall` that exits 0, it writes, rewrites or deletes the record of each tool the
command changed under `$UVM_DATA/tools/<name>/`: plain files, URL userinfo stripped, staged under a
name of its own and renamed in, so no reader sees half a record. A non-zero exit changes nothing
there, a record that cannot be written leaves a note and never a changed `rc`, and nothing under
`UVM_DATA` names an architecture. `uvm_export_env`'s `mkdir -p` guard covers the five per-architecture
directories and neither trampoline directory, which only a trampoline sync creates. The upgrade's
self-heal is per root: a `uv` or `uvx` call that finds no `$UVM_ROOT/bin/.uv-manager-synced`
(`uvm_heal_marker`) creates it and syncs both directories, and only that call and a sync of
`$UVM_ROOT/bin` write that marker, so doctor, which never writes under `UVM_ROOT`, can neither set
nor clear it, and another root sharing `UVM_DATA` cannot stand in for this one. An unwritable
`UVM_DATA` costs that one attempt. A marker that cannot be created, in a `$UVM_ROOT/bin` that cannot
be created or written or under an inode quota, skips the sync rather than run one on every call; a
sync that fails to write `$UVM_ROOT/bin` removes the marker, so the next call tries again. While the
marker exists the test is one `stat` and no fork. A record and its `$UVM_DATA/bin` trampolines are one step wherever a record is
written: the intercept and `uvm install` sync both directories, doctor and the restore by name sync
`$UVM_DATA/bin`, and the repair's holder syncs it once per scope, after its backfill. The knob-off
trampoline entry runs `uvm_export_trees`, the exports without the guard, so it creates nothing.

**Trampolines live in two neutral directories, each with its own rule.** `$UVM_DATA/bin` holds one
for every executable a record names, so a purge that takes a shim leaves its trampoline; one is
removed only when no record names it. `$UVM_ROOT/bin` holds one for every shim name in this root,
under any architecture, dangling or not: the managed interpreters and any tool without a record. One
is removed there when no shim of this root names it, as 0.7.0 did, and a sync never touches another
root's, so roots sharing `UVM_DATA` cannot remove each other's. A marked 0.7.0 trampoline a shim names
is rewritten in place under its own path, never removed, so a shell that hashed it keeps running
the tool. A temporary name carries the host, the pid and a `$RANDOM`, since writers on two nodes
can share a pid. Invoking a tool on an architecture where it is not installed reports that instead of
`Exec format error`. A directory that cannot be created or written (`-d` and `-w`, since `mkdir -p`
succeeds on a read-only one) is left as it is, nothing written or removed. A write that fails inside
a writable one (a block quota, a full filesystem) removes its temporary file and stops that
directory's sync, so an empty file never replaces a working trampoline, and the directory does not
count as synced. With `UVM_REPAIR` off,
`UVM_ROOT` set and the shim executable, the `/bin/sh` body execs the shim and starts no wrapper;
otherwise it execs `uv-manager _trampoline NAME` (`uvm_tool_entry`), which runs the scope check a `uv`
call runs, resolves the root by the cascade, restores the recorded tool by name when the knob is set
and its shim is still missing (`uvm_restore_by_name`, §5), and execs the shim after releasing, or
exits 127 naming the tool. The root is never baked into a body. Every sync (the `uv tool` and `uv
python` intercept, `uvm trampolines`, `uvm install`, the self-heal) writes both directories but
doctor's, the restore by name's and the repair holder's, which write `$UVM_DATA/bin` alone;
`uvm trampolines` names only the directories it wrote. Only files carrying `uvm_tramp_marker` are ever
removed. Overwriting is narrower: a file is spared only when it
is unmarked, non-empty and executable — somebody's own script, left alone with a note — so an unmarked
file that is empty or non-executable is replaced. That the guard turns on `-x` at all is a gap rather
than a decision; `issues/invariant-audit-gaps.md` carries it. `PATH` prepending is
idempotent because the exported `PATH` is inherited by everything `uv` spawns.

**Per-user, never shared.** State directories are created under `umask 077`.

**Portability floor.** POSIX-ish bash with no GNU assumptions: the `current` swap tries `mv -T` (GNU),
then `mv -h` (BSD), then a non-atomic fallback; `stat -c` and `stat -f` are both tried;
`realpath`/`readlink -f` are not used (`abspath` exists for that reason). The script parses under
bash 3.2 (macOS) as well as the bash 4/5 found on cluster images. Generated trampolines are `/bin/sh`,
not bash.

**The global-option list in `uvm_global_takes_value` is deliberately short.** It exists only to find
the first positional argument so `self update`, `tool` and `python` can be recognized — not to model
`uv`'s CLI. The list is not complete: `uv 0.12.4` also accepts `--cache-dir` and `--python-preference`
before the subcommand with a separate value, and both are missing, which
`issues/invariant-audit-gaps.md` carries. Length is still not the goal — every entry is more surface to
drift out of date — but the entries that are there have to be right, and a short list is not evidence
that anything option-shaped must follow the subcommand.

## High-risk regions

One file, so blast radius is measured in functions. A confirmed defect in any of these forces a human
sign-off gate at review:

| Region | Why |
|--------|-----|
| `uvm_acquire_lock` / `uvm_unlock` | Concurrency across nodes. A wrong early-out hands a pinned caller the wrong version; a release that removes a lock this process did not create admits a second holder; until a human clears a leaked lock, a provisioning call whose request is not yet satisfied waits until it is or until the timeout passes. |
| `uvm_install` / `uvm_point_current` | Atomicity of the version swap under concurrent readers; installer environment scrubbing. |
| `uvm_resolve_root` / `uvm_init` | Silent misplacement of a user's entire state tree. Deferred on purpose so `help` and `--version` still work when unconfigured. |
| `uvm_trampolines` | Writes into two directories on the user's `PATH`. Overwriting an unmarked file is destroying somebody's script; removing a file a running shell has hashed fails its next call. |
| `uvm_export_env` / `uvm_set_paths` | Everything `uv` spawns inherits this environment. Nesting must stay idempotent. |
| the dispatch tail | `exec` semantics, the `tool`/`python` non-exec path, `rc` propagation. |
| `uvm_repair` / `uvm_detect` | Runs before every exec while `UVM_REPAIR` is on, on every rank of a job. An arrival test that misses repairs on every call; an outcome recorded after the release sends a waiter into a second repair; a byte on stdout lands in the user's command's output. |
| `uvm_repair_cache` | The only arm that removes anything, and it removes under `UV_CACHE_DIR`: a cached environment's link, a script environment, a wheel's pointer files and link. A glob one character too wide takes another wheel's files; a removal on the wrong side of the `pyvenv.cfg` test lets uv install a script's dependencies into the managed interpreter; a reinstall pinned by version where the source was a URL, git, a path or a find-links directory swaps the code a job runs. |
| `uvm_tool_entry` / `uvm_restore` | An `exec` site that runs the repair: every installed tool run by its own name with `UVM_REPAIR` on enters it, on every rank. An exec before `uvm_unlock` leaves the repair lock held for every waiter; a byte on stdout lands in the tool's output. `uvm_restore` reads its recorded request for three token classes only, `--force`, `<name>@latest` and the options naming a local file, and passes the rest to uv as recorded; a fourth class starts a model of uv's command line. |

## Verification

There is no test suite yet — building one is planned work, tracked in `ROADMAP.md`. A change is
proven by driving the real script in a sandbox, and the factory's `verify:` commands are written that
way.

`tests/` holds the drives that outgrew a `verify:` line. There are two, and each is there because its
subject cannot be measured any other way. `tests/lock-race.sh` releases bursts of concurrent ranks
at the provisioning lock and checks the tree and the answers they leave. Under `--plant held` a live
holder never releases, so every rank waits out the timeout and then installs and publishes beside the
others; a barrier spliced into the sandbox's fixture copy releases them to publish together. Under
`--plant control` nothing is planted, and one installer per burst, never two at once, is asserted.
After each burst, `versions/<ver>` must hold exactly one distribution with nothing nested inside it,
no staging copy may survive beside it, `current` must resolve, and every rank must exit 0 printing
the version it asked for; each defect has its own counter. It asserts that the wrapper made progress
*before* any of that — an installer ran in every burst, no lock other than an intact plant was left
standing, and under `held` at least one burst ran two installers at once — because a burst that never
raced leaves a clean tree that proves nothing. Burst sizes are derived from a measured per-burst rate
rather than chosen, and the arithmetic is in the file. It needs no instrumentation of
`bin/uv-manager`. With `--launch srun` the same bursts run from every node of a Slurm allocation
against one tree on the parallel filesystem that `LOCKRACE_SHARED` names, and `--summary` writes a
result made only of counts and version numbers, so a cluster run can be committed as evidence.
`tests/repair-race.sh` releases ranks once with `UVM_REPAIR=1` at a tree it has damaged, checks that
exactly one repairs it under the repair lock while the rest wait and then run, and under `--scenario
kill` kills that holder to check the waiters' timeout, `uvm doctor`, `uvm clean lock --yes` and a
clean pass, with the same `--launch srun` and counts-only `--summary`. Scenarios `I` and `ikill` do
the same for five installed tools, one per purge shape, each rank running its tool by its own name
through its trampoline, and count one restore from the records and the tools' equality with what
was installed. Scenarios `U`, `S` and `ukill` damage uv's cache, a cached `uvx` environment or a
script environment among twenty others, run `uvx <spec>` or `uv run <script>` on every rank, kill
the holder under `ukill`, and count the cache entries the pass rebuilt, or rewrote in place after
the repair, which must be none, beside the walk's seconds, the cache's file, live-entry and `RECORD`
line counts (`--large-cache` adds a data-science stack) and its link mode, and, under `--launch
srun`, whether a `flock` taken on one node holds on another.

`.agents/factory/bin/temp_root.sh` is the substrate. It scrubs the inherited environment (every
`UV_*` and `UVM_*` variable, and every scratch candidate `uvm_resolve_root` consults), points
`UVM_ROOT` at a temp directory, puts the working tree's `bin/` first on `PATH`, runs from inside the
sandbox, and removes it on any exit path.

Two mocking techniques make this cover the paths that would otherwise need a cluster:

- **The network.** `uvm_fetch` uses `curl`/`wget`, and `curl` speaks `file://`. Pointing
  `UVM_INSTALL_URL` at a local directory exercises the entire provisioning path — lock, fetch,
  install, version detection, atomic rename, `current` swap — with no egress. `temp_root.sh --offline`
  wires this to `.agents/factory/fixtures/uv-install/`. The fixture also **asserts** that
  `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` were scrubbed, so that invariant is checked on
  every offline drive.
- **The architecture.** `UVM_PLATFORM` overrides the platform key, so one temp root can hold
  several architectures and the heterogeneous-cluster behavior is testable on one machine.
  `temp_root.sh --arch <key>`.

**Exit 0 is necessary but not sufficient.** Assert a concrete post-condition — a path that exists, a
symlink target, a version string, a specific message on stderr. A drive that "completed" but left the
wrong `current` target is a failure.

## Prose and comments

The project's documentation and comments have a voice. Keep it. Overly verbose prose — the padding,
hedging and marketing adjectives that generated text tends toward — is a tic that costs a reader's
confidence in code that is otherwise correct, and this is infrastructure that has to be taken
seriously to be adopted. Match the existing voice.

**Write:**

- Declarative statements. `# Reserved id, exempt from gating.` — not `# This function will check...`.
- The **why**, not the what. The code says what it does. A comment earns its place by explaining a
  constraint, a failure mode, or a rejected alternative.
- Concrete failure modes. "the failure is `Exec format error`, thousands of lines into a job log,
  after the allocation has been charged" beats "this could cause problems."
- Whole sentences with terminal punctuation, in the banner-comment style already in the file.

**Do not write:**

- Filler and hedging: "simply", "just", "note that", "it's worth noting", "essentially", "basically".
- Marketing adjectives: "comprehensive", "robust", "seamless", "powerful", "elegant", "leverage",
  "utilize". If a property matters, state the measurement.
- "This ensures that…", "This allows us to…", "In order to…" — usually a sentence that has not
  decided what it is claiming.
- Restatements of the adjacent line. A comment that paraphrases the code is worse than none.
- Emoji, decorative Unicode, or exclamation marks in source or in `README.md`.
- Bulleted lists where two sentences would do. Tables are for reference material; prose is for
  reasoning.
- Symmetry for its own sake — three parallel bullets where only two facts exist.

**Never embed feature-scoped spec ids** (`R1`, `P3`) in the script or the README. They restart per
feature, live in `spec/{slug}/`, and collide across branches. Requirement provenance lives in the
commit, the PR, and the retained `spec/{slug}/` record. Referencing stable things is fine: real
function names, real variable names, documented behavior of `uv`.

## Working on this codebase as an agent

- **Use the factory for non-trivial work.** A feature, fix or refactor flows through the `.agents/`
  lifecycle: **`/uvm-feature`** (shape `GOAL.md`, or promote an `issues/{slug}.md`) →
  **`/uvm-plan`** (research + `PLAN.md`/`TECH.md`) → **`/uvm-build`** (execute phases) →
  **`/uvm-review`** (blind, externally-verified QA) → **`/uvm-publish`** (squash PR to `main`), each
  on a branch with artifacts committed under `spec/{slug}/`.
  [`.agents/factory/methodology.md`](.agents/factory/methodology.md) is the *why*;
  [`.agents/factory/invariants.md`](.agents/factory/invariants.md) is the curated footgun checklist
  derived from this file. **Ceremony scales to appetite** — a one-sentence change skips the lifecycle
  entirely.
- Three operational siblings sit outside the lifecycle: **`/uvm-harness`** applies the factory's own
  self-improvement findings back to `.agents/`, **`/uvm-roadmap`** retires the seeds whose cycles have
  landed and keeps `ROADMAP.md` true, and **`/uvm-release`** cuts a tagged version.
- **Where a deferral goes.** A pass that decides *not* to fix something still records it, and the
  destination is not a matter of taste:

  | File | Holds | Written by |
  |------|-------|------------|
  | `spec/{slug}/META.md` | **Harness/skill feedback only** — "was this the *factory's* fault". Never code follow-ups. | the lifecycle skills |
  | `issues/{slug}.md` | **Deferred code work**, pre-shaped from `templates/ISSUE.md` | whoever defers it |
  | `ROADMAP.md` | the **ordered index** — one entry per issue, `**Seed:**` pointing at the file | whoever defers it |
  | `.security/issues/{slug}.md` + `.security/ROADMAP.md` | the same two, for **unremediated security findings** — gitignored, never published | whoever defers it |
  | `spec/{slug}/` | work **actually in flight** | the lifecycle skills |

  An `issues/{slug}.md` is a *candidate, not a contract*. `/uvm-feature` promotes it into a `GOAL.md`,
  and that promotion is where appetite, non-goals and the R-IDs get negotiated with a human. Never
  copy one into a `GOAL.md` verbatim.

  **A deferral is retired, not kept forever.** When the cycle that adopted a seed lands on `main`,
  `/uvm-roadmap` deletes the seed and removes its `ROADMAP.md` entry: `spec/{slug}/` is the retained
  account and git history holds the file. The security lane inverts this — nothing under `.security/`
  is ever deleted, because it is gitignored and a deletion there leaves no history to recover from, so
  a remediated finding moves to that roadmap's terminal records instead.

  **The security lane is not optional.** A deferral describing an unremediated weakness — a live
  exploitable mechanism or enough evidence to reconstruct one — goes in `.security/`, which is
  gitignored. A public roadmap of live vulnerabilities is an attacker's work plan. The *fixes* land as
  ordinary public commits when they ship; only the standing inventory stays private. When in doubt
  which lane, use `.security/` and ask.
- **Verify by driving the script.** Not by reading it, and not only by `bash -n`. The concurrency, the
  filesystem semantics and the environment handling are where the defects are, and all three are
  reachable from `temp_root.sh`.
- **Prefer deleting to adding.** This is a 850-line script that a site operator has to be able to read
  in one sitting. A new subcommand, a new environment variable, a new fallback each cost more than
  their implementation. The `README.md` "Design notes" section is the record of what was rejected and
  why — read it before proposing something it already turned down.
- **This file is the map, and it drifts.** For a deep change, re-verify the specific invariant against
  the script before relying on it, and update this file when the code moves.
