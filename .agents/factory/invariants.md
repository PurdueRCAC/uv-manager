# Invariant gate & footgun checklist

A curated, explicitly-enumerated subset of the load-bearing invariants in [`AGENTS.md`](../../AGENTS.md),
maintained **in lockstep with it** (`AGENTS.md` is ground truth — if this drifts, fix it). Two
consumers:

- **`uvm-plan` (gate):** before research *and* after PLAN/TECH is drafted, walk the sections a change
  touches and confirm the design honors each. Record any bend in PLAN's deviation-justification table.
- **`uvm-review` (footgun list):** a violation of any invariant here is **auto-CRITICAL** (a §12
  project-conventions violation is HIGH, not auto-CRITICAL) and, when it touches a high-blast-radius
  region, forces a human sign-off gate.

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
- Released on `EXIT`, `INT` **and** `TERM`. A `RETURN` trap alone leaks the lock when the holder is
  killed, and a leaked lock blocks every later invocation for that user until someone removes it by
  hand.
- Distinguish contention from failure: if the lock directory is absent after a failed `mkdir`, the
  failure is permissions/quota/ENOSPC and waiting will never help — die with that message.
- The early-out inside the wait loop must test **the version this call was asked for**. Testing "is
  some uv present" silently hands a pinned caller whatever another process was installing, which is
  the one guarantee a pin exists to provide.
- Break a lock older than `UVM_LOCK_STALE`; time out after `UVM_LOCK_TIMEOUT` with the
  exact `rmdir` command to recover.

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
- On any failure, remove the staging directory, release the lock, and die with the pre-warm
  instructions.

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
  happens to share the name. Leave it and say so. Only marked files are ever overwritten or removed.
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

- `uvm_global_takes_value` lists exactly the five `uv` **global** options that take a separate value.
  Everything else that looks like one is a per-command option and can only appear after the
  subcommand, where the parser has already stopped. A longer list is not more careful — it is more
  surface to drift out of date and more arguments to mis-skip.
- `shift 2` is all-or-nothing in bash: with one argument left it shifts nothing and returns non-zero.
  Guard on the count (`(( $# >= 2 ))`) or a trailing value-taking flag spins the loop forever.
- The parser recognizes only `self update`, `tool` and `python`. Everything else passes through
  untouched. Do not grow it into a `uv` CLI model.

## 12. Project conventions (violations are HIGH, not auto-CRITICAL)

- **Version is single-sourced** at `readonly uvm_version=` (`bin/uv-manager:21`). The sample output in
  `README.md` quotes it and moves with it.
- **Same-commit rule.** A behavior change updates whichever of these it invalidates, in the same
  commit: the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example`,
  `share/modulefiles/uv/main.lua`.
- `bin/{uv,uvx,uvm}` are **symlinks** to `bin/uv-manager` (git mode `120000`). Four independent copies
  still dispatch correctly but drift on the next update.
- Adding a name is one symlink plus one pattern in the `case`. Unrecognized names fall through to `uv`
  mode.
- Comments and prose follow the voice rules in `AGENTS.md` § *Prose and comments*: declarative, the
  *why* not the what, no filler or marketing adjectives, no emoji, and **no feature-scoped spec ids**
  (`R1`, `P3`) in the script or the README.
- Verify by driving the script under `.agents/factory/bin/temp_root.sh`, never against the developer's
  real state root. Exit 0 alone is not a pass — assert a concrete post-condition.
