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
`uvm_init` · `uvm_trampolines` · `uvm_export_env` · `uvm_set_paths` · `uvm_repair` · the dispatch
tail (everything below the `# ---- dispatch` banner)

---

## 1. Architecture partitioning — highest blast radius

- The platform key is resolved **at exec time, on the executing node** (`uvm_init`), never earlier.
- `UVM_ROOT` is architecture-**neutral**. The wrapper appends `<arch>`; nothing outside the
  wrapper may export an architecture-bearing path.
- The two paths a modulefile may put on `PATH` are the deployment `bin/` and `$UVM_ROOT/bin`
  (trampolines). Both are neutral by construction. `UV_CACHE_DIR`, `UV_TOOL_BIN_DIR` and the rest are
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
  early-outs on the provisioning question. A missing predicate dies on an explicit `(( $# >= 3 ))`:
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
  until the value changes. Failed outcomes under Slurm jobs are counted on one WARN by name and
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
  `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR`, plus three `PATH` prepends.
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
- `uvm_set_paths` is **pure** — it sets variables and touches no filesystem — so read-only subcommands
  (`status`, `doctor`) can call it without provisioning anything.
- `PATH` prepending is **idempotent**. The exported `PATH` is inherited by everything `uv` spawns, and
  anything that re-enters the wrapper would otherwise add the same three entries at every nesting
  level.
- `mkdir -p` runs behind a six-way `[[ -d ]]` guard, and the guard sits **outside** the `umask 077`
  subshell. Unconditionally it cost a fork, an exec and — under GNU coreutils — one `EEXIST`-failing
  `mkdir(2)` per path component of every operand, to resolve six directories that already existed; the
  count therefore grows with the depth of `UVM_ROOT`. Moved inside the subshell, the guard keeps the
  fork and loses a third of the saving. A missing directory is still created, under
  `umask 077` — that is the behavior the unconditional call was protecting and it has to survive any
  further change here. Modes are **not** repaired: `mkdir -p` never chmods an existing directory, so
  the property is "directories we create are 0700", not "our directories are 0700".

## 9. Trampolines

- Generated for the **union of names across all architectures**, so invoking a tool on an architecture
  where it is not installed reports that instead of failing with `Exec format error`.
- Every trampoline we own is **rewritten**, never skipped on mere existence — one truncated by a purge
  or written by an older version has to be repaired.
- A file that is non-empty, executable and **lacks `uvm_tramp_marker`** is somebody's own script that
  happens to share the name. Leave it and say so. Removal is marker-only; overwriting is not. A file
  is spared only when it is unmarked **and** non-empty **and** executable, so an unmarked file that is
  empty or non-executable is written over. The `-s` term is deliberate — a trampoline truncated by a
  purge is 0 bytes and unmarked, and the bullet above requires it be repaired. The `-x` term is a real
  gap against the property `AGENTS.md` states, seeded in `issues/invariant-audit-gaps.md`.
- Written to a temp name and `mv -f`'d into place, so a concurrent exec never sees a partial script.
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
