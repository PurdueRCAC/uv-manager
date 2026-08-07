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
  documentation; drift there is a defect, not a chore.

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
| `.agents/` | The spec-driven software factory (skills, methodology, templates, scripts). |
| `spec/{slug}/` | Committed, dated per-feature design records. Retained on merge. |
| `issues/{slug}.md`, `ROADMAP.md` | Deferred code work and its ordered index. |

Inside `bin/uv-manager`, the sections are banner-commented in execution order: identity dispatch,
diagnostics, state root, platform key, knobs, provisioning lock, fetching, install, storage layout,
trampolines, argument inspection, `self update` interception, subcommands, dispatch.

## Execution model

```
argv[0] ──► mode (uv | uvx | manager)
              │
   manager ───┴──► uvm_manager_main          help/--version answer before uvm_init
              │
   uv/uvx ────┴──► uvm_init                  resolve root, append arch, derive paths
                   uvm_parse_command         find the first positional argument
                   uvm_ensure_uv             provision if needed (locked)
                   uvm_export_env            export UV_* + prepend PATH
                   ├─ self update ──► intercepted, re-provisions, execs uv --version
                   ├─ tool | python ─► run to completion, resync trampolines, exit rc
                   └─ everything else ─► exec the real uv
```

The wrapper adds roughly 7 ms. That budget is real: `uv run` appears inside loops that call it
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
project exists; violating it fails silently and expensively.

**`exec`, not a subprocess.** Signals, exit codes and process accounting must be the real `uv`'s. The
two exceptions — `uv tool` and `uv python` — change what needs a trampoline and so must run to
completion, capture `rc`, resync, and exit `rc`.

**No `/tmp` fallback for the state root.** Deliberate. Node-local storage would mean a cold cache and
a re-download on every node of every job, an egress requirement everywhere, and environments that
vanish at job end. When nothing resolves, the wrapper prints every candidate it tried and why each
failed, then exits non-zero.

**A pin is authoritative.** `UVM_PIN` selects which version `current` points at — not merely
which version to download when nothing is present.

**The provisioning lock is `mkdir`.** Atomic on Lustre, GPFS and NFS; needs no helper binary; does not
depend on `flock`, which `uv` itself requires but which is not enabled on every parallel filesystem.
It must release on `EXIT`, `INT` and `TERM` (a leaked lock blocks that user until someone removes it
by hand), break itself when abandoned past `UVM_LOCK_STALE`, and its early-out must test **the
version this call was asked for** — testing "is some uv present" hands a pinned caller whatever
another process happened to be installing.

**`current` is swapped atomically, and its target is relative** (`versions/<ver>`), so the tree stays
relocatable and a concurrent reader never observes a missing or half-written `current`.

**Scrub `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` before running the installer.**
`install.sh` checks them *before* `UV_UNMANAGED_INSTALL` and they take precedence; if a user has
either exported, `uv` lands elsewhere, the expected binary never appears, and every later invocation
re-runs the installer and fails. Mirror-related variables are left alone — they only redirect where
the tarball comes from, which is legitimate site policy.

**stdout belongs to the user's command.** Provisioning is a side effect of whatever was actually
asked for. `VER=$(uv --version)` on a cold node must not come back with installer chatter ahead of the
answer, so installer output goes to stderr and multi-line wrapper output uses a heredoc (`cat` dies
quietly on `SIGPIPE`; bash's `printf` builtin reports `write error: Broken pipe`).

**Storage is ours; resolution is not.** The wrapper sets `UV_CACHE_DIR`, `UV_TOOL_DIR`,
`UV_TOOL_BIN_DIR`, `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR` and `PATH`. It deliberately leaves
`XDG_CONFIG_HOME`, `UV_CONFIG_FILE`, `UV_PROJECT_ENVIRONMENT`, index variables, `UV_LINK_MODE`,
`UV_COMPILE_BYTECODE` and `TMPDIR` alone. The first two would change dependency resolution; the rest
are site or user policy.

**Trampolines are generated over the union of names across all architectures**, so invoking a tool on
an architecture where it is not installed reports that instead of `Exec format error`. Only files
carrying `uvm_tramp_marker` are ever overwritten or removed; an unmarked, non-empty, executable file
of the same name is somebody's own script and is left alone, with a note. `PATH` prepending is
idempotent because the exported `PATH` is inherited by everything `uv` spawns.

**Per-user, never shared.** State directories are created under `umask 077`.

**Portability floor.** POSIX-ish bash with no GNU assumptions: `mv -T` has a non-atomic fallback,
`stat -c` and `stat -f` are both tried, `realpath`/`readlink -f` are not used (`abspath` exists for
that reason). The script parses under bash 3.2 (macOS) as well as the bash 4/5 found on cluster
images. Generated trampolines are `/bin/sh`, not bash.

**The global-option list in `uvm_global_takes_value` is deliberately short.** It exists only to find
the first positional argument so `self update`, `tool` and `python` can be recognized. `uv`'s global
options that take a separate value are those five; everything else that looks like one is a
per-command option and can only appear after the subcommand, where the parser has already stopped.
A longer list is not more careful — it is more surface to drift out of date.

## High-risk regions

One file, so blast radius is measured in functions. A confirmed defect in any of these forces a human
sign-off gate at review:

| Region | Why |
|--------|-----|
| `uvm_acquire_lock` / `uvm_unlock` | Concurrency across nodes. A wrong early-out hands a pinned caller the wrong version; a leaked lock blocks the user until manual repair. |
| `uvm_install` / `uvm_point_current` | Atomicity of the version swap under concurrent readers; installer environment scrubbing. |
| `uvm_resolve_root` / `uvm_init` | Silent misplacement of a user's entire state tree. Deferred on purpose so `help` and `--version` still work when unconfigured. |
| `uvm_trampolines` | Writes into a directory on the user's `PATH`. Overwriting an unmarked file is destroying somebody's script. |
| `uvm_export_env` / `uvm_set_paths` | Everything `uv` spawns inherits this environment. Nesting must stay idempotent. |
| the dispatch tail | `exec` semantics, the `tool`/`python` non-exec path, `rc` propagation. |

## Verification

There is no test suite yet — building one is planned work, tracked in `ROADMAP.md`. Until then, a
change is proven by driving the real script in a sandbox, and the factory's `verify:` commands are
written that way.

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
- Two operational siblings sit outside the lifecycle: **`/uvm-harness`** applies the factory's own
  self-improvement findings back to `.agents/`, and **`/uvm-release`** cuts a tagged version.
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
