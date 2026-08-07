# Research digest — `uvm-env-prefix`

Consolidated decisions from briefs 01–05. Where the briefs disagreed, this file carries the single
resolution and the reason; the briefs are kept as evidence, not as instructions.

## 1. The premise is stronger than the GOAL states

`UV_LOCK_TIMEOUT` already exists upstream, added in uv 0.9.4:
*"The time in seconds uv waits for a file lock to become available. Defaults to 300s (5 min)."*
The wrapper carries `UV_MANAGER_LOCK_TIMEOUT` for its own `mkdir` provisioning lock, default 180.
Two file-lock timeouts, two owners, two defaults, one namespace — verified directly against
`crates/uv-static/src/env_vars.rs`, not the docs page ([`05`](05-namespace-safety.md)).

The collision the GOAL treats as a future hazard has, in the sense that matters to a confused
operator, already happened. `uv` exposes 150 public `UV_*` names, 68 of them with three or more
segments, and `UV_MANAGED_PYTHON` shares the first nine characters of `UV_MANAGER_`. Lead the PLAN
with this rather than with the hypothetical.

Negative results, all verified: `uv` reads no `UVM_*` name; the standalone `install.sh` reads none;
SystemVerilog UVM's only real environment variable is `UVM_HOME` (the rest are `+plusargs`), and none
of the six proposed names intersects anything. `UVM_*` is a safe namespace.

## 2. Scope: 112 occurrences, 18 files

`git grep` counts 135 total; 23 are in the three historical records the GOAL excludes
(`issues/uvm-env-prefix.md`, `spec/uvm-env-prefix/{GOAL,META}.md`). No case variants exist — every hit
is the uppercase literal, and neither the 183 lowercase `uvm_` function names nor the 165 `uv-manager`
program-name strings contain `UV_MANAGER`, so a case-sensitive substitution is provably safe
([`01`](01-occurrence-inventory.md)).

Two files resist mechanical substitution and must be hand-edited:

- **`ROADMAP.md`** — the entry reads "`UV_MANAGER_*` sits inside `uv`'s own namespace … `UVM_*` is
  unambiguously ours." Substitution makes it self-contradictory.
- **`bin/uv-manager`'s help heredoc** and **`share/modulefiles/uv/main.lua`'s comment block** are
  column-aligned. `UVM_` is seven characters shorter than `UV_MANAGER_`, so substitution leaves dead
  gutter.

**Symlink hazard.** `sed -i` and `perl -pi` replace the path, not the inode. A glob reaching
`CLAUDE.md` (→ `AGENTS.md`) or `.claude` (→ `.agents`) converts a symlink into a regular file, and
`lint.sh` checks only `bin/{uv,uvx,uvm}` — it would pass. Drive any bulk edit off `git grep -l`, which
lists `AGENTS.md` alone, and assert all five symlinks survive.

## 3. R6 — resolved against two of three briefs

The briefs split: [`01`](01-occurrence-inventory.md) and [`03`](03-behavior-baseline.md) recommended
unsetting the six new names explicitly, to protect `UVM_FIXTURE_*` variables passed into a drive from
outside; [`02`](02-sandbox-scrub.md) recommended widening the existing pattern.

**Widening wins.** Three findings decide it:

1. Nothing passes a `UVM_FIXTURE_*` from outside today. All eleven references in the tree are
   definitional or prose — not the TECH template's `verify:`, not `set_phase.py`, not the release
   skill's drives. An allowlist would protect a caller that does not exist.
2. Provisioning is lazy: nothing installs until the first `uv` call *inside* the sandbox. So the
   fixture knobs work when set on the inner command, verified —
   `temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'` prints `uv 6.6.6 (fixture)`.
3. Invariant §11's principle applies directly: a longer list is not more careful, it is more surface
   to drift. An enumerated unset silently misses the seventh knob somebody adds later, and it would
   sit *alongside* the `UV_*` loop rather than replacing it.

The deeper reason is that the scrub's contract is hermeticity. A drive that depends on a variable
*surviving* the scrub is working against the tool's purpose; parameterize the command, not the
sandbox.

**Consequence:** brief 03's proposed R6 guard
(`UVM_FIXTURE_VERSION=7.7.7 temp_root.sh --offline uv --version`) is wrong under this design and must
be rewritten to the inner-command form. Keep it as a guard — it proves the scrub did not overshoot.

## 4. The BSD sed trap

Brief 02 flagged that `\?` is a GNU extension. Confirmed independently, and it is worse than reported:
on BSD sed the pattern `s/^\(UVM\?_[A-Za-z0-9_]*\)=.*/\1/p` matches **nothing** — it does not merely
miss `UVM_`, it silently disables the entire existing `UV_*` scrub on the maintainer's own machine,
while `sh -n`, `shellcheck` and every drive stay green.

Use the POSIX interval:

```sh
# Scrub every UV_* and UVM_* variable, and every scratch candidate uvm_resolve_root
# consults. Without this, a developer with UV_CACHE_DIR, UVM_PIN or $SCRATCH exported
# gets a drive that silently reads real storage or honors a real knob, and a green
# verify that proves nothing. The interval is POSIX; \? is a GNU extension that
# matches nothing under BSD sed and would disable this loop on macOS.
for name in $(env | sed -n 's/^\(UVM\{0,1\}_[A-Za-z0-9_]*\)=.*/\1/p'); do
```

`UVM_SANDBOX` (L79) and `UVM_FIXTURE_DIR` (L86) are exported *after* the loop at L69, so the wider
pattern cannot strip them. A nested drive correctly gets its own.

## 5. Observable baseline

Captured from live drives ([`03`](03-behavior-baseline.md)); these are the literals to assert against.

| Surface | Today | After |
|---|---|---|
| `status` origin | `state root: … (from UV_MANAGER_ROOT)` — bare name, no `$` | `(from UVM_ROOT)` |
| scratch-candidate origin | `(from $SCRATCH)` — *with* `$` | unchanged |
| `help` | five lines matching `^  UV_MANAGER_`, descriptions at column 26 | six lines `^  UVM_`, column 23 |
| no-root failure | exit 1; stderr carries `keep per-user` and two variable mentions | same text, new names |
| `pin:` unset | `pin:` + `<none — tracks latest>` (em dash) | unchanged |
| offline install | stdout exactly `uv 9.9.9 (fixture)`; `current` → `versions/9.9.9` | unchanged |

`uvm status` works on an empty root and exits 0, so most verifies need no `--offline`.

To reach the no-root path, defeat the sandbox's own export from inside the drive:
`temp_root.sh sh -c 'UV_MANAGER_ROOT=$UVM_ROOT; export UV_MANAGER_ROOT; unset UVM_ROOT; uvm status'`.
That is also exactly the R2 test — the legacy name set, the new one absent.

**Trap:** a pinned offline install whose fixture is not also given a matching `UVM_FIXTURE_VERSION`
reports 9.9.9 and lands `current` on `versions/9.9.9`, so the verify silently tests the wrong thing.

## 6. Documentation

Add a three-sentence design note to `README.md` § *Design notes* ([`04`](04-docs-surface.md)). The
section already carries the subcommand form of the same argument, the Reference table will show
`UVM_ROOT` and `UV_CACHE_DIR` a few lines apart, and without a note the mixed prefixes read as an
oversight — the opposite of the rename's point. It also guards against a later contributor "fixing"
the inconsistency by renaming the five exported names, which would be a real regression.

`etc/uv-manager.conf.example`'s header sentence — "The wrapper reads only `UV_MANAGER_*` variables" —
is already loose (the wrapper also reads the scratch candidates and scrubs `UV_INSTALL_DIR`) and gets
rewritten rather than substituted.

Five README passages are transcripts of real output or copy-pasteable commands and must match the
script after the change: the sample `status` block, the modulefile excerpt, the `flock` probe
one-liner, the `worker_init` example, and the troubleshooting paraphrase of the no-root message. The
versions quoted in README (0.2.0, 0.12.2) stay — no bump this cycle.

## 7. Carried into the PLAN as risk

`uv tool install uvm` installs PyPI's Unity Version Manager, whose wheel declares a console script
named `uvm`. Because `uvm_set_paths` prepends `UV_TOOL_BIN_DIR` last, it lands ahead of the module's
`bin/` and shadows the wrapper's manager mode. Pre-existing, dormant tool, loud failure; the rename
neither creates nor worsens it ([`05`](05-namespace-safety.md)). Record it, do not fix it here.
