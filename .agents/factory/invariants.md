# Invariant gate & footgun checklist

A curated, explicitly-enumerated subset of the load-bearing invariants in [`AGENTS.md`](../../AGENTS.md),
maintained **in lockstep with it** (`AGENTS.md` is ground truth — if this drifts, fix it). Two
consumers:

- **`uvm-plan` (gate):** before research *and* after PLAN/TECH is drafted, walk the sections a change
  touches and confirm the design honors each. Record any bend in PLAN's deviation-justification table.
- **`uvm-review` (footgun list):** a violation of any invariant here is **auto-CRITICAL** (a §12
  project-conventions violation is HIGH, not auto-CRITICAL) and, when it touches a high-blast-radius
  region, forces a human sign-off gate.

**Check a bullet against the code before grading against it.** Before raising an auto-CRITICAL for a
§1–§11 violation, confirm the invariant holds on `main` in the neighbourhood being graded. A claim that
does not is a finding against *this file*, recorded in `META.md`, not against the diff. A bullet added
or edited here names the function it constrains and is checked against that function, never against
`AGENTS.md`'s prose — every inaccuracy found so far came from compressing that prose one hop further
from the code.

Only invoke the sections relevant to the change. Do not manufacture findings against untouched code.

## High-blast-radius regions (any CONFIRMED finding here → mandatory human gate)

`uvm_acquire_lock` · `uvm_unlock` · `uvm_install` · `uvm_point_current` · `uvm_resolve_root` ·
`uvm_init` · `uvm_trampolines` · `uvm_export_env` · `uvm_set_paths` · `uvm_repair` ·
`uvm_repair_cache` (the one arm that removes, under `UV_CACHE_DIR`) · `uvm_tool_entry` (an `exec` site that runs the repair; with it `uvm_restore`, whose request reading
stays at three token classes) · the dispatch tail (everything below the `# ---- dispatch` banner)

---

## 1. Architecture partitioning — highest blast radius

- The platform key is resolved **at exec time, on the executing node** (`uvm_init`), never earlier.
- `UVM_ROOT` is architecture-**neutral**. The wrapper appends `<arch>`; nothing outside the
  wrapper may export an architecture-bearing path.
- The paths a modulefile may put on `PATH` are the deployment `bin/`, `$UVM_DATA/bin` (the record
  trampolines) and `$UVM_ROOT/bin` after it (this root's trampolines, from its shims: the managed
  interpreters and any tool without a record). All three are neutral by construction. `UV_CACHE_DIR`, `UV_TOOL_BIN_DIR` and the rest are
  **not** — they are set by the wrapper, on the node.
- Failure mode when violated: `Exec format error` inside a job, after the allocation is charged. It is
  silent at load time and does not reproduce on the login node.
- `uname -m` reports `arm64` on macOS and `aarch64` on Linux. A sandbox drive on a Mac uses a
  different key than the cluster; do not hardcode either.

## 2. Process semantics

- The wrapper **`exec`s** the real `uv`. Exit codes, signals and process accounting must be the real
  binary's — an `srun uv run …` has to forward `SIGTERM` at walltime.
- Exactly two commands do not `exec`, because they change what needs a trampoline: `uv tool` and
  `uv python`. They run to completion under `set +e`, capture `rc`, resync trampolines, and
  `exit "${rc}"`. Do not let a trampoline resync failure overwrite the real exit code.
- `uv self update` is intercepted (an unmanaged install has no receipt, so the binary's own
  self-update is disabled). `--dry-run` and `-h/--help` must answer without touching the network.
  The one exception is `UVM_REPAIR`: with it on, the repair runs first on every invocation through
  `uv` or `uvx`, help and dry-run included, as the knob's own contract says, because it sits on the
  dispatch ahead of every subcommand. A scope with an outcome already recorded costs one `stat`
  and no network.

## 3. State root resolution

- Precedence: `UVM_ROOT`, else the first of `CLUSTER_SCRATCH`, `RCAC_SCRATCH`, `SCRATCH`,
  `PSCRATCH`, `WORK`, `PROJECT` naming an **existing, writable directory**, with `/.uv` appended.
- **There is no `/tmp` fallback**, and adding one is not an improvement. Node-local storage means a
  cold cache and a re-download per node per job, an egress requirement everywhere, and environments
  that disappear at job end.
- When nothing resolves, print **every candidate tried and why each failed**, plus the two fixes
  (`module load uv`, or an explicit export), then exit non-zero.
- `uvm_init` is deferred, not run at load: `help` and `--version` must work on an unconfigured node,
  because they are what tell you how to configure it.

## 4. Version selection & pinning

- A pin is **authoritative** over which version a call selects, and over `current` while no
  concurrent call on the same root selects a different version. `UVM_PIN` selects which version
  `current` points at, not merely what to download when nothing is present. `current` is one link
  per root and a pin is per process, so concurrent calls pinned to different versions race for
  `current` and the last swap wins: an earlier call can exec a later call's version at status 0.
  Calls sharing one pin, as the ranks of an `srun` job do, agree on `current` whichever swap lands
  last.
- `uvm_have WANT` is the single spelling of "is this request already satisfied?", and only
  `uvm_install` asks it: on its fast path, in the re-check before installing, in the selection step,
  and as the predicate it hands the lock. The lock does not spell the question; it runs whatever
  predicate its caller names (§5), which for provisioning is `uvm_have`. Keep it single.
- **Every success return from `uvm_install` has selected the requested version** (except under the
  non-atomic `mv` fallback, below). The fast path, the lock's early-out, the re-check under the lock
  and a fresh install all fall through to one selection step before the release; none returns
  early. That is the only place the script selects: `uvm_ensure_uv`, `uvm install` and
  `uv self update` all go through `uvm_install`. A pinned call
  that cannot select its pin, because the installer delivered another version, dies naming the pin
  and leaves the other version on disk unselected. It never runs another version at status 0.
  Selection precedes the release because an unpinned waiter's predicate asks only whether `current/uv`
  exists, so a holder that released before selecting would let the next waiter install again.
- `uvm_point_current` swaps atomically and writes a **relative** target (`versions/<ver>`) so the tree
  stays relocatable. The rename must not follow the existing link: a plain `mv tmp current` moves `tmp`
  inside the version directory `current` names. GNU `mv` takes `-T` and BSD `mv` takes `-h`, each a
  single rename(2), so concurrent swaps leave `current` at whichever ran last and never missing. An
  `mv` with neither gets a documented non-atomic fallback, `rm` then `mv`. Between the two steps a
  concurrent reader can find `current` missing, and a concurrent swap landing there makes this
  call's `mv` follow the new link: its `.current.<pid>` link nests inside that version directory and
  this call's swap never lands. When that swap selected a different version, `current` never names
  the version this call selected, and the call execs the other version at status 0.
- The installed version is read back from the binary (`uv --version`, field 2), never assumed from the
  requested string — that is also how a wrong-architecture download is detected.

## 5. Locks

- The lock is an atomic **`mkdir`**, not `flock`. `flock` is what `uv` itself needs and is not enabled
  on every parallel filesystem; `mkdir` is atomic on Lustre, GPFS and NFS and needs no helper binary.
- **Two locks, never both held.** `.install.lock` guards provisioning (`versions/`, `current`) and
  `.repair.lock` guards the purge repair (`tools/`, `python/`), side by side in `${uvm_root}`. No
  call holds both: `uvm_ensure_uv` returns from `uvm_install`, which releases, before `uvm_repair`
  acquires, so the one `uvm_lock` global names everything a process holds. A repair waiter is
  `fail` mode: at `UVM_LOCK_TIMEOUT` it dies naming the repair lock and its owner line and never
  proceeds. Every bullet below applies to both locks unless it names one.
- Released on `EXIT`, `INT` **and** `TERM` through `uvm_unlock`, which acts only on `uvm_lock`; a
  `RETURN` trap alone leaks the lock when the holder is killed. A process holds a lock exactly while
  `uvm_lock` names it, and removes only a lock it holds. `uvm_unlock` clears `uvm_lock` before it
  removes anything, because in the opposite order a signal landing after the `rmdir` would make the
  trap remove the lock the next caller took in the meantime. The cost is that bash handles a trapped
  signal only after the foreground command returns, so a signal while the lock is being created,
  before `uvm_lock` names it, or being removed, after `uvm_lock` is cleared, can leave the lock
  standing, empty or still carrying its owner line. No call removes it on its own: `uvm doctor`
  reports it and a human removes it with `uvm clean lock`. Until then a provisioning call whose
  request is not yet satisfied waits until it is or until `UVM_LOCK_TIMEOUT` passes, a forced
  `uvm install` waits even on a warm tree, and a repair call with no outcome for its scope fails at
  the timeout. That is the accepted failure mode.
- **Only the creator removes the lock.** `uvm_unlock` acts only on `uvm_lock`, which nothing but this
  process's own winning `mkdir` in `uvm_acquire_lock` sets, so releasing by path removes the
  directory this process made. No call removes or takes another call's lock, whatever its age or its
  owner line records, and the wrapper never asks whether a holder is alive: over a shared filesystem
  that question has no reliable answer. The one exception is a human, by hand or through
  `uvm clean lock`. Clearing a lock whose holder is still running lets a second call provision
  beside it, and the holder's later release then removes whatever lock the next call took, so the
  wording that points a human at the lock says the holder may still be running.
- **The owner write is fatal and leaves nothing behind.** `uvm_acquire_lock` sets `uvm_lock` as soon
  as the winning `mkdir` returns, *before* writing `host=<uname -n> pid=<pid>` into
  `${lock}/owner`. A failed write dies with `cannot record ownership …`, and the EXIT trap's release
  removes any entry the write left (a quota or a full filesystem after the file was created) and then
  the directory. The redirect is never suppressed, because the shell's own diagnostic is the only
  place the errno appears. The owner line is read by a human and by nothing in the wrapper's
  decisions; the host is `uname -n`, never the inherited `HOSTNAME`, so the line names the node the
  holder actually ran on.
- **No lock survives an `exec`.** `exec` replaces the process image, so the EXIT trap never runs;
  every `exec` of the real `uv` releases first. `uvm_repair` takes the repair lock that late in the
  dispatch path and releases it before it returns, so the pre-exec `uvm_unlock` is a guard, not the
  release; on a path holding none it is one builtin test and no fork. A new `exec` site owes the
  same call.
- **Distinguish contention from failure by persistence, not by a second look.** A `mkdir` that failed
  `EEXIST` and a holder that released before the `[[ ! -d ]]` test are indistinguishable afterwards,
  so one absence is evidence of nothing: it reported a released lock as an unwritable filesystem for
  2–4% of ranks in 64-way cold bursts, on GPFS and on APFS. The waiter retries, and reports the
  permissions/quota/ENOSPC fault — with the same message — only once a literal bound of attempts has
  each found the lock gone. The bound is a constant in the script, never an environment variable, and
  the count never resets, which holds the iterations absent-retry can add to the wait to that bound
  however the loop alternates.
- **The caller names the predicate.** `uvm_acquire_lock LOCK ON_TIMEOUT PREDICATE [ARG...]` runs the
  predicate as `"$@"` once a second while waiting and returns 1, holding nothing, when it comes true.
  LOCK, `install` or `repair`, names the lock, `${uvm_root}/.LOCK.lock`, and the words its messages
  use, so provisioning's text is unchanged; an unknown name dies.
  Provisioning (`uvm_install`) passes `uvm_have "${want}"`, or `false` when forced, so its early-out
  tests **the version this call was asked for** — testing "is some uv present" silently hands a pinned
  caller whatever another process was installing. Any other caller passes its own test and never
  early-outs on the provisioning question. There are three callers: provisioning, the scope's
  repair (`uvm_repair_recorded`: an outcome recorded for the scope), and the restore by name
  (`uvm_restore_by_name`, predicate `uvm_ondemand_done`: the shim the call runs is executable, or a
  failed record `<scope>+tool-<tool>.failed` is present). The restore by name runs only with the
  knob set, after `uvm_repair` has returned, and only when that shim is still missing; it tests its
  predicate on arrival, while waiting and once the lock is won, as `uvm_repair` does. Success
  records nothing, because the shim is the evidence and the path is entered only when it is
  missing; a failure is written under a temporary name and renamed, so its waiters fail at once with
  the reason rather than at `UVM_LOCK_TIMEOUT`. A missing predicate dies on an explicit `(( $# >= 3 ))`:
  an empty `"$@"` is a successful no-op, and `${1:?}` exits 0 under the EXIT trap on bash 3.2. A
  predicate runs with errexit suspended, so its status must be the deciding test's, and it never
  touches `uvm_lock`.
- **One notice, then proceed or fail.** At `min(30, UVM_LOCK_TIMEOUT)` seconds a waiter prints one
  notice on stderr: the lock path, the owner line (`<none recorded>` when there is none), that the
  holder may still be running, and `rm -f '<lock>/owner' && rmdir '<lock>'`. The removal is two steps
  because a bare `rmdir` reports `Directory not empty` while `owner` is inside, and it is the absolute
  path rather than a `uvm` command because a reader on another node, architecture or `UVM_ROOT` would
  clear a different lock and be told it succeeded. The 30 is a literal, not a knob. At
  `UVM_LOCK_TIMEOUT`, `proceed` returns 0 holding nothing and the caller does the work without the
  lock; any other mode dies naming the lock and its owner line and runs nothing. No message says or
  implies whether the holder is alive.
- **Doctor reports both locks and judges nothing.** Each standing lock, provisioning or repair, is
  one `uvm doctor` WARN naming which lock, the path, the owner line (`<none recorded>` when there is
  none), that the holder may still be running, and `uvm clean lock --yes`. It is never a FAIL: every
  rank sees a lock while any rank provisions or repairs, and a job prologue keyed on doctor's exit
  status would fail beside a healthy holder. `uvm clean lock` removes both lock directories and
  nothing else. Its dry run prints each standing lock's owner line and says that clearing a live
  holder's lock lets another call provision or repair beside it and the holder's release then
  removes that call's lock; only `--yes` removes them.
- **Doctor reports a failed repair outcome and never reads one under a job.** A failed outcome
  recorded under a value is a WARN with its reason and `uvm clean outcomes --yes`, since it stands
  until the value changes; a failed restore by name under a value, a name carrying `+tool-`, is a
  WARN of its own naming the tool. Failed outcomes under Slurm jobs, both kinds, are counted on one WARN by name and
  never opened: each ended with its job, and a read would refresh its atime and keep it alive
  through the purge that is meant to take it. Repaired outcomes are not reported. `uvm clean
  outcomes` removes `.repair/` whole; its dry run counts the records by name, never opening one.
- **`UVM_LOCK_TIMEOUT` is form-tested, then forced to base 10, inside `uvm_acquire_lock`.** Form
  first: on bash 3.2 a non-numeric value makes the arithmetic fatal under `set -u` and the EXIT trap's
  status then overrides the error's, so the script exits 0 and `VER=$(uv --version)` comes back empty
  and true. Then base 10 onto the same global the messages read: bash reads `0600` as 384, and `0800`
  is not a number at all. The guard lives inside the function, never at load time, so `uvm help` and
  `uvm --version` still answer on a misconfigured node.

## 6. Installer environment

- **Scrub `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR`** (`env -u`) before piping `install.sh`
  to `sh`. `install.sh` checks them *before* `UV_UNMANAGED_INSTALL` and they win; if either is
  exported, `uv` lands elsewhere, the expected binary never appears, and every later invocation
  re-runs the installer and fails.
- Mirror-related variables are **left alone** — they redirect where the tarball comes from, which is
  legitimate site policy.
- `UV_UNMANAGED_INSTALL` is doing several jobs: no shell-startup edit, no receipt (so a user's own
  `~/.local/bin/uv` bookkeeping is not clobbered), and — as a side effect — the disabled self-update
  that §2 intercepts.
- Install into a `mktemp -d` staging directory inside `versions/`, then **rename** into place. A
  rename within the same directory is atomic; a partial tree at a version path is not recoverable.
- Every failure removes the staging directory and releases the lock, but the advice is per path and
  the paths differ. A dead installer pipeline gets the pre-warm instructions; a version read-back that
  will not run gets the wrong-architecture message and deliberately no pre-warm, which would send the
  user to repeat a download that already succeeded.
- **Publishing tolerates a rival.** A call that proceeded past the lock timeout publishes beside
  whoever else did, and both copies are the same version, so either may win. No directory rename at
  the portability floor refuses an existing target — `mv` onto a directory moves the source inside it
  and exits 0, on GNU, BSD and busybox alike, and `mv -n` reports a skip as success — so the race is
  detected afterwards, not prevented. The call stays `mv "${tmp}" "${dest}"` with its stderr captured.
  A destination already present means discard the staging copy. A failed `mv` with `${dest}/uv`
  executable means a rival landed between `mv`'s look and the rename: discard and carry on. A failed
  `mv` with no rival removes the staging copy, releases the lock and dies `cannot publish uv <ver>
  into <dest>: <mv's message>`. A successful `mv` that left `${dest}/${tmp##*/}` nested a rival's tree
  around ours: remove that one entry. The loser only ever removes its own uniquely named `mktemp`
  directory, never the rival's tree. A loser killed between the nest and its removal leaves a hidden
  complete copy inside `versions/<ver>`, which every reader skips; no primitive at the floor avoids
  that residue. `uvm doctor` reports it, and any `versions/.incoming.*`, as a WARN naming the path
  and saying an install may still be using it. Nothing removes a staging copy but its own call and a
  human.

## 7. Output discipline

- **Installer and diagnostic output goes to stderr.** Provisioning is a side effect of whatever the
  user actually asked for; `VER=$(uv --version)` on a cold node must not return installer chatter
  ahead of the answer. The purge repair is the same: its findings, its notes and the stdout of uv's
  repair command all go to stderr, and the user's command keeps its own stdout and exit status.
- Multi-line wrapper output uses a **heredoc through `cat`**, not a series of `printf`s: `cat` dies
  quietly on `SIGPIPE`, while bash's `printf` builtin reports `write error: Broken pipe`. This is why
  `uvm_status | head` behaves like an ordinary Unix filter.

## 8. Environment the wrapper sets — and does not

- Sets, all under `$UVM_ROOT/<arch>/`: `UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`,
  `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR`, plus three `PATH` prepends (the two shim directories
  and `$UVM_DATA/bin`, the last only when `UVM_DATA` resolved).
- Exports `UVM_ROOT=${uvm_base}`, the root whether it came from the environment or the cascade, and
  `UVM_DATA` when it resolved, to everything it runs. A trampoline finds the shims through
  `UVM_ROOT`, and a child that re-enters the wrapper resolves the same trees. Both are neutral (§1).
- **Deliberately does not set:** `XDG_CONFIG_HOME`, `UV_CONFIG_FILE`, `UV_PROJECT_ENVIRONMENT`,
  `UV_DEFAULT_INDEX`, `UV_INDEX`, `UV_PYTHON_PREFERENCE`, `UV_PYTHON_DOWNLOADS`, `UV_LINK_MODE`,
  `UV_COMPILE_BYTECODE`, `TMPDIR`. The first two would change dependency **resolution**, not just
  storage; the rest are site or user policy. Storage is the wrapper's business; resolution is not.
- **The purge repair restores what is installed and changes no resolution.** The interpreter arm
  names each damaged install by its key under `python/`; the tool arm runs per damaged tool, `uv pip
  install --python <tool>/bin/python --reinstall --no-cache` with every distribution pinned at the
  version its dist-info directory name records. Both arms name their targets, so no `.python-version`,
  global pin or `UV_PYTHON` steers them. The tool arm never writes `uv-receipt.toml` and builds no
  spec from it: a tool keeps its pin, its `--with` packages and its receipt byte for byte, and a
  healthy tool is never touched. It reads the receipt to refuse and for nothing else: a tool whose
  receipt records a requirement, constraint or override from a directory, path, editable, git or
  URL source fails the scope before any `uv` call for it, as one whose `direct_url.json` records
  such a source does, since a version from an index would replace what was installed. The
  receipt's index options are not a refusal: uv writes the index `uv.toml` or a `UV_INDEX` variable
  configures into every receipt, `uv.toml` and the `UV_*` variables apply to the reinstall, which
  keeps resolution the user's, as above, and an index given on one install's command line alone is
  not applied again (conceded). Both arms run from `/` in a subshell: uv reads project configuration
  (`[tool.uv]`, `[tool.uv.pip]`, `uv.toml`) from the working directory and its parents, where a
  `target` would send the reinstall into the job's project and an `exclude-newer` would hide the
  installed versions. `--no-config` is not the fix; it drops the user's and the system's `uv.toml`
  too.
- **The cache arm sits last and is the only arm that removes.** `uvm_repair_cache` runs after the
  tool arm, on what `uvm_detect_cache` found. A damaged cache environment that still has
  `pyvenv.cfg` and an executable `bin/python` (tested after the interpreter arm) has its damaged
  distributions reinstalled in place as the tool arm does, and only those: the walk collects every
  damaged dist-info directory of each entry (`uvm_cache_fixd`) while its FAIL text stays the first
  problem, and the reinstall runs from `/` in a subshell, with `--python <entry>/bin/python
  --reinstall-package <name>… --no-cache` and the pins `uvm_record_constraints` reads from those
  dist-info names and `direct_url.json`, so every other distribution keeps its files byte for byte;
  `--python` is passed only where `pyvenv.cfg` is present, so nothing installs into a managed
  interpreter's `site-packages`. Everything else is removed, every removal before the arm's first
  `uv` call that could reach the base interpreter (only `uvm_cache_index_check`'s fetch comes
  earlier, for an environment that still has `pyvenv.cfg` and a running `bin/python`, into a target
  of its own): a cached environment's link (also one holding any distribution not shown to come from
  the configured index, which its spec rebuilds: a dist-info without `RECORD`, a `direct_url.json`
  kept, or one or a `uv_cache.json` listed in a surviving `RECORD`, or a `uv_cache.json` on disk,
  with no `direct_url.json`, `uvm_cache_unpinnable link`), never the archive, which a running
  process may be using; a
  script environment, renamed aside under §9's temporary-name rule and then removed, a removal that
  cannot finish noted and passed, since the walk and uv skip dot names; an unpacked wheel's pointer
  files `<link>.<ext>` but `<link>.lock` (uv follows `<link>.http`, not the link; a dotted `<ext>`
  is another wheel's), then the link. A script environment with a damaged distribution whose
  `RECORD` lists a `direct_url.json` that is gone, or that keeps or lists a `uv_cache.json` with no
  `direct_url.json` (a local file or find-links directory), is never pinned by version: it fails
  the scope naming the distribution and `uv-manager clean cache --yes` (`uvm_cache_unpinnable
  script`). Every other damaged distribution either kind would pin by version, its `RECORD` kept
  or not, is pinned only after `uvm_cache_index_check` fetches those versions in one
  `--no-deps --no-cache` call per environment from `/` into a dot-named target in `environments-v2`, removed
  on every path, and finds them equal, by the environment's interpreter under `-I -S`: a surviving
  `RECORD`'s sha256 entries against the release's `RECORD` for the same paths, or else each file
  the environment still holds hashed, source files only: `*.py` and `*.pyi` outside the dist-info
  directory and `bin/`. Only wheels are compared: a distribution whose dist-info directory, in the
  environment or in the fetched target, holds `uv_build.json` was built by uv from an sdist and
  passes once the fetch succeeded, since a build is not reproducible (extensions and metadata
  differ, and a backend can write its build interpreter's path into a `.py`, as numpy's does); a
  fork served as an sdist is conceded. A wheel's extensions and metadata are not compared either,
  so a fork differing only there is conceded, and a release with no source file in common passes.
  A mismatch or a release the index does not serve fails a script environment's scope the same
  way. A fetch that failed fails it with its own reason, naming the distribution and the fetch and
  no `clean cache`. The fetch runs with colour off (`NO_COLOR=1`, `FORCE_COLOR` and
  `CLICOLOR_FORCE` unset), and is a failed fetch only on a positive marker: exit 2,
  `Failed to fetch`, "not found in the cache" or a network-disabled hint, or a hint naming
  `401 Unauthorized` or `403 Forbidden`. Every other non-zero exit, a version behind an
  `exclude-newer` hint included, is a release the index does not serve, so a later uv's new
  wording for a failed fetch names `clean cache`. Each removes a
  cached environment's link. It runs only on the repair's path, never in doctor or a healthy
  scope. After
  the reinstalls each reinstalled entry is walked again (`uvm_cache_clean`), so a reinstall that
  exits 0 and restores nothing never records ok. A cached environment whose reinstall fails, or
  that is still damaged on that walk, loses its link after the reinstalls, the one removal that
  follows a `uv` call; a script environment in either state fails the scope. A failed rename or
  removal sets `uvm_repair_reason` naming the entry. Doctor's walk of the cache lists the live entries with one `find -H` (names only, no
  per-file predicate, no `-L`, no `-printf`), compares every `RECORD` path against the listing in
  one `awk` pass that resolves `.` and `..` by name, and tests with `-e`/`-L` only the paths the
  listing lacks, so a dangling link counts as present; it reads `RECORD` files and writes
  nothing. A wheel whose link is gone or dangling is walked through its pointer, `<link>.http` or
  `<link>.rev` (`uvm_cache_pointee`: the 16 characters after the byte `0xb0`, by builtins under
  `LC_ALL=C`), only when the archive it names exists; a pointer that cannot be read or parsed is
  passed over without a word, and a pointer beside a live link is never read. An archive is never
  removed.
- **The restore sits beside the repair and replays a record.** The arms run interpreters, then the
  restore, then the in-place tool arm, then the cache arm; each that fails sets
  `uvm_repair_reason` and returns.
  `uvm_detect_records` lists a recorded tool with a trace here that lost its directory,
  `pyvenv.cfg`, interpreter link, an executable or its receipt, and `uvm_detect`'s other passes skip
  it; a damaged recorded tool the tool arm would refuse (`uvm_tool_refusal`) joins it. A recorded
  tool with no trace is never restored by the walk. `uvm_restore` runs `uv tool install --force -c
  <record>/constraints <request>` from `/` in a subshell, with `UV_PYTHON` the recorded minor (a
  request's own `--python` wins) and `UV_NO_CACHE=1`, everything to stderr. Resolution stays the
  user's: the pins are constraints, and `uv.toml` and the `UV_*` variables apply. The restore is
  the one place the wrapper writes a receipt, and it writes uv's own: the record's byte copy goes
  back over the replay's pinned receipt only when every `install-path` line names this
  `UV_TOOL_BIN_DIR` (a fixed-string count, never a parse), else `.uvm-restored` marks the tool
  pinned by a restore for doctor. It never writes the record. The in-place arm stays first choice
  for every other damaged tool, recorded or not, because it keeps the receipt byte for byte.
- **Doctor writes under `UVM_DATA` and nothing under `UVM_ROOT`.** It backfills records
  (`uvm_backfill`: only a tool with a receipt, `pyvenv.cfg` and no record, from `uv tool list` run
  from `/` with `UV_NO_CACHE=1`, never a rewrite) only where uv's `tools/.lock` already exists,
  since the list creates that file and a purge takes it, and otherwise reports each tool with no
  record and `uv tool list` as what writes one. It syncs `$UVM_DATA/bin` alone (`uvm_trampolines
  records`), and its interpreter probe runs with `PYTHONDONTWRITEBYTECODE=1`. The repair's holder
  and the `uv tool` intercept on `rc == 0` run the same backfill, `|| true`.
- **A record and its trampolines are one step.** Wherever a record is written its `$UVM_DATA/bin`
  trampolines are written with it: the intercept syncs both directories after its backfill, doctor
  syncs `$UVM_DATA/bin` after its own, and the repair's holder syncs `$UVM_DATA/bin` once per scope
  right after its backfill, whether or not that wrote anything. The restore by name syncs it after
  its restore.
- **A backfilled record pins what a 0.7.0 receipt can say.** The request is `uv tool list`'s
  rendering (a requirement it ends in a newline joined to its line; a `--with` it renders as a name
  and a URL recorded as `name @ URL`), plus the receipt's `[tool.options]` lines uv writes on one
  line: `index-url`, `extra-index-url`, `index` (each inline table as `--index URL`, or
  `--default-index URL` for `default = true`, carried only when it holds nothing but `url`, `name`,
  `default` and uv's defaults for `explicit`, `format` and `authenticate`, and an array only whole)
  and `index-strategy`, the only receipt lines read; anything else replays under the configuration
  in effect. A tool gets no record (`uvm_unpinnable`) when a requirement its receipt records from a
  git, URL or local source, the tool or a `--with` package, has no `direct_url.json` in its own
  dist-info directory, matched by name (case aside, `-` and `.` as `_`, under `nocasematch` restored
  after); a transitive dependency's cannot stand in for it. Pinned by version alone, its restore
  would fetch a branch head or an index's release. It keeps the in-place arm's refusal, and doctor names it. A VCS or URL constraint carries
  the `subdirectory` its `direct_url.json` records.
- **The durable tree.** `UVM_DATA` resolves in `uvm_init` from `UVM_DATA`, else
  `${XDG_DATA_HOME}/uvm`, else `${HOME}/.local/share/uvm`, by builtin tests only; with none of the
  three set it is empty and every writer there skips, and no call fails for it. The wrapper writes
  under it records and trampolines (§9) and nothing else: after a `uv tool install|upgrade|uninstall` that exits 0,
  `uvm_records_update` writes, rewrites or deletes `$UVM_DATA/tools/<name>/` (`request`,
  `constraints`, `python`, `entrypoints`, `uv-receipt.toml`) for each tool whose `uvm_tool_marks`
  line the command changed. A non-zero exit writes nothing there. A record is staged as
  `.<name>.<host>.<pid>.<random>`, the old one moved aside, the stage renamed in, so a reader sees the old record,
  none, or the new one. URL userinfo is stripped from the request and from every source URL; a
  password-less ssh login is kept. The receipt is copied only when no URL in it, under any scheme,
  carries userinfo that rule would strip (`uvm_carries_userinfo`). Every writer returns 0 and the dispatch tail calls it `|| true`:
  a record never changes `rc` (§2). No path under `UVM_DATA` names an architecture.
- `uvm_set_paths` is **pure** — it sets variables and touches no filesystem — so read-only subcommands
  (`status`, `doctor`) can call it without provisioning anything.
- `PATH` prepending is **idempotent**. The exported `PATH` is inherited by everything `uv` spawns, and
  anything that re-enters the wrapper would otherwise add the same three entries at every nesting
  level.
- `mkdir -p` runs behind a five-way `[[ -d ]]` guard over the per-architecture directories, and the
  guard sits **outside** the `umask 077` subshell. Neither trampoline directory is among them: only a
  trampoline sync creates those. The dispatch tail's self-heal, right after `uvm_export_env`, runs
  `uvm_trampolines` when this root has no `$UVM_ROOT/bin/.uv-manager-synced` (`uvm_heal_marker`), so
  the first `uv` or `uvx` call after an upgrade syncs the trampolines once per root; while the marker
  exists it is one `[[ -e ]]`, one `stat` and no fork. The call creates the marker (and, on a tree
  without one, `$UVM_ROOT/bin` under `umask 077`) **before** it syncs, and only it and a sync of
  `$UVM_ROOT/bin` write the marker, so doctor (which never writes under `UVM_ROOT`) and another root
  sharing `UVM_DATA` can neither set it nor stand in for it, and an unwritable `UVM_DATA` costs the
  one attempt. A marker that cannot be created — a `$UVM_ROOT/bin` that cannot be created or
  written, or an inode quota — skips the sync rather than retry it on every call. A sync that fails
  to write `$UVM_ROOT/bin` removes the marker, so the next call tries again, one attempt per call
  while it fails. A call killed mid-sync leaves its marker; the old trampolines it did not reach
  still run their tools until the next `uv tool` command or `uvm trampolines`. On a tree with no
  installed tool it creates the two directories and the marker. `uvm_export_trees` is the exports without the guard, for the knob-off trampoline entry, which
  creates nothing. Unconditionally it cost a fork, an exec and — under GNU coreutils — one `EEXIST`-failing
  `mkdir(2)` per path component of every operand, to resolve six directories that already existed; the
  count therefore grows with the depth of `UVM_ROOT`. Moved inside the subshell, the guard keeps the
  fork and loses a third of the saving. A missing directory is still created, under
  `umask 077` — that is the behavior the unconditional call was protecting and it has to survive any
  further change here. Modes are **not** repaired: `mkdir -p` never chmods an existing directory, so
  the property is "directories we create are 0700", not "our directories are 0700".

## 9. Trampolines

- They live in **two directories, each under its own rule** (`uvm_trampoline_dir DIR NAMES`):
  - **`$UVM_DATA/bin`**: one for every line of every record's `entrypoints`. A marked one is removed
    only when no record names it, so a record keeps its trampoline past a purge of the shim. Roots
    sharing `UVM_DATA` share the records, so each root's sync writes the same set.
  - **`$UVM_ROOT/bin`**: one for every shim name under this root's `*/bin/{shims,python-shims}`,
    dangling or not: the managed interpreters and any tool without a record. A marked one is removed
    when no shim of this root names it, 0.7.0's rule. A sync never touches another root's.
  - Each is created under `umask 077` by the sync, `$UVM_ROOT/bin` also by the self-heal ahead of
    its sync (§8), and by nothing on the hot path. One that cannot be created or written (`-d` and
    `-w`: `mkdir -p` succeeds on a read-only directory) is left as it is, nothing written and
    nothing removed.
  - A write, `chmod` or rename that fails inside a writable directory (a block quota, a full
    filesystem) removes its temporary file and stops that directory's sync: the trampoline it was
    replacing stays, nothing is removed, and the directory is not added to `uvm_synced`. An empty
    file renamed into place would exit 0 and run nothing.
- The body has three paths. `UVM_REPAIR` off (`case ${UVM_REPAIR:-0} in 0)`: unset, empty, `0`),
  `UVM_ROOT` set and the shim executable: `exec` the shim, no wrapper, no lock. Otherwise: `exec
  uv-manager _trampoline NAME`, the `uv-manager` on `PATH` first, else the generating wrapper's own
  directory baked in (not baked when the path holds a `'`). The root is never baked in.
- `uvm_tool_entry` (`_trampoline`, dispatched beside `help` before `uvm_init`): knob on, it runs
  `uvm_ensure_uv`, `uvm_export_env` and `uvm_repair`, the same scope check, lock, outcome and failure
  contract a `uv` call runs; then the shim under `UV_TOOL_BIN_DIR`, else `UV_PYTHON_BIN_DIR`, after
  `uvm_export_trees` and `uvm_unlock` (an exec site, §2, §5). Knob on and the shim still missing after
  `uvm_repair`: `uvm_restore_by_name` first (§5). No shim: exit 127 naming the tool, and,
  with a record naming it, that it is recorded but not installed here and the remedy; without one,
  0.7.0's text. The knob-off path provisions nothing, takes no lock and creates nothing.
- **0.7.0's trampolines are rewritten in place.** A marked file in `$UVM_ROOT/bin` that a shim names
  gets the new body under the same path, by temp file and rename, and is never removed for being
  old: a job script's shell that ran the tool before the first sync has hashed that path, and its
  next call must find a file there. Every sync (the `uv tool`/`uv python` intercept, `uvm
  trampolines`, `uvm install`, the self-heal) writes both directories; doctor's, the repair
  holder's and the restore by name's write `$UVM_DATA/bin` alone, the first because the other is
  under `UVM_ROOT`. `uvm trampolines` reports only the directories the sync wrote
  (`uvm_synced`), and names one it left.
- Generated for the **union of names across all architectures** in each directory, so invoking a
  tool on an architecture where it is not installed reports that instead of failing with `Exec format
  error`.
- Every trampoline we own is **rewritten**, never skipped on mere existence — one truncated by a purge
  or written by an older version has to be repaired.
- A file that is non-empty, executable and **lacks `uvm_tramp_marker`** is somebody's own script that
  happens to share the name. Leave it and say so. Removal is marker-only; overwriting is not. A file
  is spared only when it is unmarked **and** non-empty **and** executable, so an unmarked file that is
  empty or non-executable is written over. The `-s` term is deliberate — a trampoline truncated by a
  purge is 0 bytes and unmarked, and the bullet above requires it be repaired. The `-x` term is a real
  gap against the property `AGENTS.md` states, seeded in `issues/invariant-audit-gaps.md`.
- Written to a temp name and `mv -f`'d into place, so a concurrent exec never sees a partial script.
  The temp name is `.<name>.<host>.<pid>.<random>`: writers on two nodes of a shared filesystem can
  share a pid, and `HOSTNAME` can be inherited from a login node, so `$RANDOM` goes in too; none of
  the three forks.
- The trampoline body is `/bin/sh`, not bash, and re-resolves the architecture at exec time.

## 10. Portability floor

- POSIX-ish bash, no GNU assumptions. `mv -T` (GNU) is tried, then `mv -h` (BSD), then a non-atomic
  fallback; `stat -c` and `stat -f` are both attempted; `realpath` and `readlink -f` are not used — `abspath` exists for that reason.
- The script must parse under **bash 3.2** (macOS) as well as the bash 4/5 on cluster images.
  `bash -n bin/uv-manager` on a Mac is a real gate, not a formality.
- `curl` or `wget`, whichever is present; neither is assumed.
- Everything on the hot path stays cheap. `uname -m` runs on every invocation, including inside loops
  calling `uv run` thousands of times. A new subshell, `find`, or second process on that path needs a
  reason.
- **`UVM_REPAIR` off forks nothing**: `[[ -n "${UVM_REPAIR:-}" && "${UVM_REPAIR}" != 0 ]]` in the
  dispatch tail, no fork and no filesystem access. What the unset path does cost is bash parsing the
  added code, about 0.6 ms per call. On, with an outcome already recorded for the scope, it is one
  `stat` (`[[ -e ]]`) before the exec. The outcome test precedes `uvm_detect`, and `uvm_detect` runs
  only after the repair lock is won. The record name is built by builtins (`printf -v` among them),
  escapes every byte outside its class (`a-z 0-9 . -`, so every uppercase letter too) as `_` and two
  hex digits so that no two scopes share a name, on a case-insensitive filesystem as well, and walks
  bytes under `LC_ALL=C`, restoring the caller's locale. Its class lists its characters: a
  range follows the locale's collation before bash 5.0.

## 11. Argument inspection

- `uvm_global_takes_value` lists `uv` **global** options that take a separate value, as `uv --help`
  groups them. It exists only to skip values while finding the first positional argument; it is not a
  model of `uv`'s CLI. It is also not complete: `uv 0.12.4` accepts `--cache-dir` and
  `--python-preference` before the subcommand with a separate value and neither is listed, seeded in
  `issues/invariant-audit-gaps.md`. Length is still not the goal — every entry is more surface to
  drift and more arguments to mis-skip — but do not read the list's shortness as proof that anything
  option-shaped must follow the subcommand.
- `shift 2` is all-or-nothing in bash: with one argument left it shifts nothing and returns non-zero.
  Guard on the count (`(( $# >= 2 ))`) or a trailing value-taking flag spins the loop forever.
- The parser recognizes only `self update`, `tool` and `python`. Everything else passes through
  untouched. Do not grow it into a `uv` CLI model.
- One bend, on purpose: `uvm_restore_request` reads a tool's own recorded request for three token
  classes and no others, `--force` (dropped, since the replay adds its own and uv refuses a repeated
  flag), `<name>[extras]@latest` (`@latest` dropped, since it conflicts with the pins) and the
  local-file options `-e`, `--editable`, `--with-editable`, `--with-requirements`, `-c`,
  `--constraints`, `--overrides`, `-b`, `--build-constraints` (refused). Every other token passes
  through as recorded. A miss fails the restore loudly; it never restores wrong.

## 12. Project conventions (violations are HIGH, not auto-CRITICAL)

- **Version is single-sourced** at `readonly uvm_version=` (`bin/uv-manager:21`). The sample output in
  `README.md` quotes it and moves with it.
- **Same-commit rule.** A behavior change updates whichever of these it invalidates, in the same
  commit: the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example`,
  `share/modulefiles/uv/main.lua`, and — when the change overturns an invariant asserted above — this
  file together with `AGENTS.md` § *Invariants*. A §1–§11 section still asserting the reversed decision
  makes correct code an auto-CRITICAL violation. An edit to this file sits inside the graded diff, so
  it revises the standard and is judged on its merits, never read as license.
- `bin/{uv,uvx,uvm}` are **symlinks** to `bin/uv-manager` (git mode `120000`). Four independent copies
  still dispatch correctly but drift on the next update.
- Adding a name is one symlink plus one pattern in the `case`. Unrecognized names fall through to `uv`
  mode.
- Comments and prose follow the voice rules in `AGENTS.md` § *Prose and comments*: declarative, the
  *why* not the what, no filler or marketing adjectives, no emoji, and **no feature-scoped spec ids**
  (`R1`, `P3`) in the script or the README.
- Verify by driving the script under `.agents/factory/bin/temp_root.sh`, never against the developer's
  real state root. Exit 0 alone is not a pass — assert a concrete post-condition.
