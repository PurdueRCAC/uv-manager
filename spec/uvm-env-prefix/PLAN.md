# PLAN — Rename the `UV_MANAGER_*` environment prefix to `UVM_*`

> **Status:** Draft for review · **Last updated:** 2026-08-07
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).

## 1. Summary

Rename the six variables the wrapper reads for itself from `UV_MANAGER_*` to `UVM_*`, leaving the five
`UV_*` storage variables it exports for `uv` untouched. Clean break, no shim. 112 occurrences across
18 tracked files, of which all but three files are a mechanical case-sensitive substitution.

Two parts are not mechanical and carry the cycle's whole risk: the sandbox scrub in
`.agents/factory/bin/temp_root.sh`, which is a genuine behavior change rather than a rename, and three
column-aligned or self-referential text blocks that substitution would corrupt. Everything else is
bulk edit plus a sweep.

## 2. Design

### The rename

| Reads today | Reads after | Site |
|---|---|---|
| `UV_MANAGER_ROOT` | `UVM_ROOT` | `uvm_resolve_root` (`bin/uv-manager:84-86`) |
| `UV_MANAGER_PLATFORM` | `UVM_PLATFORM` | `uvm_init` (`:145`) |
| `UV_MANAGER_PIN` | `UVM_PIN` | knobs (`:158`) |
| `UV_MANAGER_LOCK_TIMEOUT` | `UVM_LOCK_TIMEOUT` | knobs (`:159`) |
| `UV_MANAGER_LOCK_STALE` | `UVM_LOCK_STALE` | knobs (`:160`) |
| `UV_MANAGER_INSTALL_URL` | `UVM_INSTALL_URL` | knobs (`:161`) |

`uvm_base_origin` is set to the bare variable name (`:86`), so `status` reports `(from UVM_ROOT)` with
no further change. The scratch-candidate branch (`:96`) writes `$SCRATCH` *with* the sigil and is
untouched — the asymmetry is pre-existing and correct, since one is a name the operator sets and the
other is a name the wrapper found.

Nothing about resolution changes: same precedence, same candidate list, same defaults, same failure
text, same exit code. `uvm_export_env` and `uvm_set_paths` are edited only where they interpolate
`uvm_base`/`uvm_root`, whose *values* are unchanged.

### The sandbox scrub — the one behavior change

`temp_root.sh:69` scrubs on `^\(UV_[A-Za-z0-9_]*\)=`, which does not match `UVM_`. After the rename a
developer with `UVM_PIN` exported would get a drive that silently honors it. Widen to the POSIX
interval `UVM\{0,1\}_`.

`\?` is a GNU extension and must not be used: under BSD sed it matches nothing at all, silently
disabling the entire existing scrub on macOS while every gate stays green. Verified directly; see
[`research/00-digest.md`](research/00-digest.md) §4.

The wider pattern cannot strip `UVM_SANDBOX` or `UVM_FIXTURE_DIR`, which are exported ten and
seventeen lines *after* the loop. Fixture knobs a drive wants to vary go on the inner command —
`temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'` — which works because
provisioning is lazy. That usage note goes in the `temp_root.sh` and fixture headers.

### What is removed

- The `UV_MANAGER_` prefix: 112 occurrences, seven characters shorter each.
- Eight columns of dead gutter in the `uvm_help` Environment block, which is re-flowed from column 26
  to 23 and gains a line by splitting the folded lock pair.
- The conf example's header claim that "the wrapper reads only `UV_MANAGER_*` variables", which was
  already false — it also reads the six scratch candidates and scrubs `UV_INSTALL_DIR`.

### What is added

One three-sentence design note in `README.md` § *Design notes*, recording why the wrapper's own knobs
are `UVM_*` while the exported ones stay `UV_*`. Justified in the deviation table below.

### Hand edits that substitution would corrupt

- `ROADMAP.md` — the entry argues `UV_MANAGER_*` is bad *because* it sits in `uv`'s namespace;
  substituting makes it argue against itself.
- The `uvm_help` heredoc and `share/modulefiles/uv/main.lua`'s comment block — column-aligned.
- Any bulk edit is driven off `git grep -l`, never a glob: `sed -i`/`perl -pi` replace the path rather
  than the inode, so a glob reaching `CLAUDE.md` or `.claude` would convert those symlinks into
  regular files, and `lint.sh` checks only `bin/{uv,uvx,uvm}`.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | The six reads in `uvm_resolve_root`, `uvm_init` and the knobs block. |
| R2 | Falls out of the clean break: no legacy branch exists, so `UV_MANAGER_ROOT` alone leaves `uvm_resolve_root` to the scratch cascade and then the existing non-zero failure. |
| R3 | `uvm_export_env` / `uvm_set_paths` unchanged except for interpolated values; the five exported names are not touched. |
| R4 | `uvm_base_origin="UVM_ROOT"` (`:86`); the re-flowed `uvm_help` Environment block. |
| R5 | `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua` and the help heredoc, split across P1 (help) and P2 (the other three). |
| R6 | The widened scrub pattern in `temp_root.sh`, plus its own six exports renamed. |
| R7 | The bulk substitution over the remaining 12 files, the three hand edits, and the closing sweep. |

## 3. Invariant gate (AGENTS.md constitution check)

Walked before research and again against this design.

- **§1 architecture partitioning** — `UVM_ROOT` stays architecture-neutral; the arch component is still
  appended in `uvm_init` at exec time. The modulefile exports only the renamed neutral root and the
  neutral trampoline `PATH`. Nothing architecture-bearing moves.
- **§3 state root resolution** — precedence, the six candidates, the no-`/tmp` rule, the full
  candidate-list failure message and the deferral of `uvm_init` are all unchanged. Only the name in
  the first branch and in the printed advice moves.
- **§4 pinning** — `UVM_PIN` remains authoritative; `uvm_have` is untouched.
- **§5 provisioning lock** — `mkdir`, the three traps, the version-specific early-out and the stale
  break are untouched; only the two timeout knob names move.
- **§6 installer environment** — `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` are Astral's names
  and are *not* renamed; the `env -u` scrub is unaffected. Confirmed against the live `install.sh`
  that neither is `UVM_`-prefixed.
- **§8 environment set / not set** — the five exported names and the three `PATH` prepends are
  explicitly out of scope (R3). The rename sharpens this invariant rather than bending it: after it,
  the prefix itself tells a reader which side of the storage/resolution boundary a name is on.
- **§10 portability floor** — the reason the scrub uses `\{0,1\}` and not `\?`. No new process on the
  hot path; a rename is free.
- **§12 conventions** — same-commit rule discharged by P1+P2; no spec ids in the script or README; the
  version is not touched.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| Adds three sentences to README § *Design notes* | After the rename the Reference table shows `UVM_ROOT` and `UV_CACHE_DIR` a few lines apart. Unexplained, that reads as an oversight — the opposite of the rename's purpose — and invites a later contributor to "fix" it by renaming the five exported names, which would be a real regression. | Saying nothing was the default given the delete-not-add bias, and is rejected because the mixed prefixes are the *point* of the change and the section exists precisely to record decisions like this one. |
| Widens the sandbox scrub beyond a pure rename | Renaming alone silently regresses drive isolation (R6). | An enumerated unset of the six new names was rejected per §11's principle: it sits alongside the `UV_*` loop rather than replacing it, and silently misses the seventh knob somebody adds later. |

## 4. Rabbit holes (resolved)

- **Is the stated motivation real, or is `UV_MANAGER_*` fine?** Real, and understated.
  `UV_LOCK_TIMEOUT` already exists upstream (uv 0.9.4, *"time in seconds uv waits for a file lock"*,
  default 300) beside the wrapper's own `UV_MANAGER_LOCK_TIMEOUT` (`mkdir` lock, default 180). Two
  file-lock timeouts in one namespace, already shipped
  ([`05`](research/05-namespace-safety.md), re-verified against `env_vars.rs`).
- **Is `UVM_*` itself safe?** Yes. `uv` reads no `UVM_*` name, nor does `install.sh`. SystemVerilog
  UVM's only genuine environment variable is `UVM_HOME`; its verbosity and testname knobs are
  simulator plusargs, not environment ([`05`](research/05-namespace-safety.md)).
- **Can the scrub be widened without breaking the fixture?** Yes, and at no cost — the fixture exports
  happen after the loop, provisioning is lazy so inner-command knobs work, and nothing in the tree
  passes a `UVM_FIXTURE_*` from outside today ([`02`](research/02-sandbox-scrub.md)).
- **What exactly does the tree contain?** 135 occurrences, 112 to change, 18 files, no case variants,
  no `UV_MANAGER` without a trailing underscore, no pre-existing collision in the target namespace
  ([`01`](research/01-occurrence-inventory.md)).
- **What literals can a verify assert?** Captured from live drives, including the incantation that
  reaches the no-root failure path from inside the sandbox
  ([`03`](research/03-behavior-baseline.md)).

## 5. Risks & open questions

- **Nothing here needs a real cluster.** Every criterion is reachable from `temp_root.sh`, including
  the architecture split via `--arch`. This is unusually clean for this repository and is worth saying
  plainly so the reviewer does not assume something was taken on trust.
- **The bulk substitution is the likeliest source of a defect**, not the design. Mitigated by driving
  it off `git grep -l`, by the symlink post-condition, and by the closing sweep.
- **A pinned offline install reports the fixture's default 9.9.9** unless `UVM_FIXTURE_VERSION` is set
  to match the pin, which would make a pin verify silently test the wrong thing. Noted so the phase
  that writes one does not fall into it.
- **Pre-existing, not fixed here:** `uv tool install uvm` installs PyPI's Unity Version Manager, whose
  console script is named `uvm`. `uvm_set_paths` prepends `UV_TOOL_BIN_DIR` last, so it lands ahead of
  the module's `bin/` and shadows manager mode. Dormant tool, loud failure, unaffected by this cycle.
  Belongs in `issues/` if anyone wants it addressed.
- **`ROADMAP.md`'s entry 1 becomes a record of completed work** rather than a candidate. It is
  hand-edited in P3; `/uvm-publish` may want to move it to Terminal records, which is that skill's
  call, not this plan's.

## 6. Verification strategy

Three layers, per `methodology.md`: `bash -n` and `shellcheck` through `.agents/factory/bin/lint.sh`,
then real drives under `.agents/factory/bin/temp_root.sh`. `uvm status` works on an empty root and
exits 0, so most drives need no `--offline`.

Post-conditions asserted, by R-ID:

| R | Post-condition | Drive |
|---|---|---|
| R1 | `pin:` line reads the pinned value when `UVM_PIN` is set **inside** the drive | `temp_root.sh sh -c 'UVM_PIN=1.2.3 uvm status'` |
| R2 | exit non-zero **and** stderr carries `keep per-user`, with only the legacy name set | `temp_root.sh sh -c 'UV_MANAGER_ROOT=$UVM_ROOT; export …; unset UVM_ROOT; uvm status'` |
| R3 | exactly five `^UV_` status lines, all under the arch directory | `temp_root.sh --arch testarch uvm status` |
| R4 | `status` prints `(from UVM_ROOT)`; `help` shows six `^  UVM_` lines and no `UV_MANAGER_` | `temp_root.sh uvm status` / `uvm help` |
| R6 | `UVM_PIN` set **outside** does not reach the drive (`pin:` reads `<none`), and the scrub has not overshot — an inner-command `UVM_FIXTURE_VERSION` still reaches the fixture | `UVM_PIN=… temp_root.sh uvm status`; `temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'` |
| R5, R7 | `git grep -n UV_MANAGER_` outside the three historical records returns nothing, and all five repository symlinks are still mode `120000` | static |

The R1/R6 pair is the sharp one: the same variable must be honored when set inside the sandbox and
ignored when set outside it. One drive alone proves neither.
