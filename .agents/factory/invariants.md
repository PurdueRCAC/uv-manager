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
`uvm_init` · `uvm_trampolines` · `uvm_export_env` · `uvm_set_paths` · the dispatch tail
(everything below the `# ---- dispatch` banner)

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

- A pin is **authoritative**: `UVM_PIN` selects which version `current` points at, not merely
  what to download when nothing is present.
- `uvm_have WANT` is the single spelling of "is this request already satisfied?" — used by the caller,
  by the lock's early-out, and inside `uvm_install`. Keep it single.
- `uvm_point_current` swaps atomically and writes a **relative** target (`versions/<ver>`) so the tree
  stays relocatable. `mv -T` is GNU-only and has a documented non-atomic fallback.
- The installed version is read back from the binary (`uv --version`, field 2), never assumed from the
  requested string — that is also how a wrong-architecture download is detected.

## 5. Provisioning lock

- The lock is an atomic **`mkdir`**, not `flock`. `flock` is what `uv` itself needs and is not enabled
  on every parallel filesystem; `mkdir` is atomic on Lustre, GPFS and NFS and needs no helper binary.
- Released on `EXIT`, `INT` **and** `TERM`, and only while it is still **ours**. A `RETURN` trap alone
  leaks the lock when the holder is killed, and a leaked lock blocks every later invocation for that
  user until someone removes it by hand.
- **Ownership, not path.** `uvm_acquire_lock` writes a `host`/`pid`/nonce line into the lock
  directory's `owner` file; `uvm_unlock` removes the directory only while that file still holds the
  line this process wrote. Absent, empty, truncated, unreadable and foreign all mean leave it — a
  false leave is reclaimed by the stale breaker, a false delete destroys live mutual exclusion, which
  is exactly what a holder broken as stale does when release matches on the path alone. The owner
  write is fatal (a holder that cannot prove ownership leaks its own lock for a full stale window)
  and the line is built from shell expansions with no forks, which narrows the `mkdir`-to-`owner`
  window from 3.0 ms to a measured 0.265 ms end to end. The narrower figure once recorded here timed
  the parent's redirect alone and omitted the interval between `mkdir(2)` returning in the forked
  child and the parent regaining control, which is the larger half. The one exception is a directory
  already gone when the write runs:
  that winner was robbed by a losing stale-breaker rather than refused by the filesystem, and it
  retakes the lock under a literal bound that never resets instead of dying with empty stdout. A
  directory still standing is a genuine fault and stays fatal — a failed redirect leaves the shell
  no errno a branch can read, so the directory's presence is the only evidence separating the two.
- **No lock survives an `exec`.** `exec` replaces the process image, so the EXIT trap never runs;
  every `exec` of the real `uv` releases first. Nothing acquires the lock that late in the dispatch
  path today, which is what makes the guard cheap — on a path holding none it is one builtin test and
  no fork. A new `exec` site owes the same call. Under the heartbeat this stops being hygiene: `exec`
  preserves the pid, so a leaked lock's refresher keeps passing its `kill -0 "$$"` leash and nothing
  can ever break the lock.
- **Distinguish contention from failure by persistence, not by a second look.** A `mkdir` that failed
  `EEXIST` and a holder that released before the `[[ ! -d ]]` test are indistinguishable afterwards,
  so one absence is evidence of nothing: it reported a released lock as an unwritable filesystem for
  2–4% of ranks in 64-way cold bursts, on GPFS and on APFS. The waiter retries, and reports the
  permissions/quota/ENOSPC fault — with the same message — only once a literal bound of attempts has
  each found the lock gone. The bound is a constant in the script, never an environment variable, and
  the count never resets: a monotonic count is what stops an alternation of absent-retry and
  successful break from evading the timeout accounting.
- The early-out inside the wait loop must test **the version this call was asked for**. Testing "is
  some uv present" silently hands a pinned caller whatever another process was installing, which is
  the one guarantee a pin exists to provide.
- **Age is measured from the heartbeat, not from acquisition.** `uvm_acquire_lock` spawns a detached
  refresher that rewrites `${lock}/owner` with byte-identical content every `UVM_LOCK_STALE/10`
  seconds; `uvm_unlock` reaps it with `kill` **then** `wait`.
- **The refresher's leash is a pid and a start time, never a pid alone.** `kill -0 "$$"` answers for
  a number the kernel reuses, so a holder killed without running its traps leaves a refresher that
  keeps rewriting `owner` the moment that number is reoccupied. Nothing then recovers the lock: the
  age net cannot fire because the mtime keeps moving, and the waiter's own probe cannot fire because
  it finds the reoccupying process alive. `uvm_acquire_lock` records `uvm_proc_start "$$"` beside the
  host token, above the `mkdir` loop, and the refresher forfeits when the pid's start time no longer
  matches. Both readings must be non-empty to forfeit, so a `ps` that cannot answer degrades to the
  bare probe rather than costing a live holder its lock. A ceiling on the refresher's lifetime is the
  rejected alternative: a hold that outlives it silently loses the protection the heartbeat exists to
  give.
  `uvm_age` stats `${lock}/owner` and falls back to the directory, because a directory's mtime tracks
  its entry list rather than writes to files inside it — left on the directory the heartbeat is
  invisible and a long hold is broken as abandoned. The refresher re-reads `owner` before every
  write: stamping our identity over a new holder's record would stop *that* holder from ever
  releasing, an immortal lock manufactured by the ownership rule above.
- **Liveness is a fast path, never a substitute for age.** A holder on this host whose pid is gone
  loses its lock at once instead of waiting out the stale window. Every other lock is decided by the
  mtime, *including one whose recorded pid answers* — `kill -0` answers for a pid number and not for
  the process that recorded it, and pid space wraps in under a minute on a node spawning `uv run` in
  a loop. Gate the age test behind a negative probe and a lock left by a killed holder is unbreakable
  for the lifetime of whatever inherits its pid, which is a leak only a human clears. What keeps a
  live holder's lock is the heartbeat, which fits ten beats inside the threshold, and not the age
  test failing to run.
- **The host token is `uname -n`.** `HOSTNAME` is whatever bash inherited — a container image sets
  it, `sbatch --export=ALL` carries a login node's copy onto every compute node — and the token
  decides whether a recorded pid may be probed locally. Two nodes presenting one name has a waiter
  probe a pid that lives on the other, find it absent, and break a live lock on its first iteration.
  It resolves once, before the `mkdir`, so the owner line is still assembled from expansions alone.
- **`UVM_LOCK_TIMEOUT` must be less than `UVM_LOCK_STALE`**, and `uvm_acquire_lock` refuses the
  inversion rather than acting on it — a waiter that outlives the threshold breaks the lock it is
  waiting for. The guard tests numeric form *before* the comparison, because on bash 3.2 a
  non-numeric value makes the arithmetic fatal under `set -u` and the EXIT trap's status then
  overrides the error's, so the script exits 0 and `VER=$(uv --version)` comes back empty and true.
  It then forces base 10 onto the same globals every later reader uses: bash reads `0600` as 384, and
  `0800` passes a digits-only test and then errors non-fatally inside the comparison, which
  *accepts*. The guard lives inside the function, never at load time, so `uvm help` and
  `uvm --version` still answer on a misconfigured node.
- Break a lock older than `UVM_LOCK_STALE`; time out after `UVM_LOCK_TIMEOUT` naming the holder the
  `owner` file records and a recovery command that works —
  `rm -f '<lock>/owner' && rmdir '<lock>'`. A bare `rmdir` reports `Directory not empty` for every
  lock whose holder got as far as claiming it, because `owner` is inside the directory it removes.
  The message also says that a recorded pid is on the host recorded beside it: a stalled user who
  probes it locally concludes the holder is gone and deletes a live lock. Every break note carries
  the same owner line, since the file that answers "whose lock was that" is deleted with it.

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
  user to repeat a download that already succeeded. The rename into place is guarded by nothing and
  dies under `set -e`, leaving a `.incoming.` directory behind — code work, seeded in
  `issues/invariant-audit-gaps.md`.

## 7. Output discipline

- **Installer and diagnostic output goes to stderr.** Provisioning is a side effect of whatever the
  user actually asked for; `VER=$(uv --version)` on a cold node must not return installer chatter
  ahead of the answer.
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

- POSIX-ish bash, no GNU assumptions. `mv -T` has a non-atomic fallback; `stat -c` and `stat -f` are
  both attempted; `realpath` and `readlink -f` are not used — `abspath` exists for that reason.
- The script must parse under **bash 3.2** (macOS) as well as the bash 4/5 on cluster images.
  `bash -n bin/uv-manager` on a Mac is a real gate, not a formality.
- `curl` or `wget`, whichever is present; neither is assumed.
- Everything on the hot path stays cheap. `uname -m` runs on every invocation, including inside loops
  calling `uv run` thousands of times. A new subshell, `find`, or second process on that path needs a
  reason.

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
