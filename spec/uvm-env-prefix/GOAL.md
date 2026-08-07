# GOAL — Rename the `UV_MANAGER_*` environment prefix to `UVM_*`

- **slug:** uvm-env-prefix
- **kind:** refactor
- **appetite:** small

## Problem

The wrapper's six configuration variables all begin with `UV_MANAGER_`, which sits inside `uv`'s own
namespace. `uv` reads dozens of `UV_*` variables and adds more with each release, so a site operator
reading a modulefile or a job script cannot tell from the name whether `UV_MANAGER_ROOT` is something
Astral honors or something this wrapper invented. The wrapper deliberately passes unrecognized `UV_*`
variables through untouched, so if Astral ever ships a `UV_MANAGER_*` name the collision is silent.

The audience is the site operator writing the modulefile. The whole project is organized around one
boundary — storage is ours, resolution is `uv`'s — and that boundary is currently invisible in the
variable names, which is exactly where an operator looks first.

## Outcome / vision

Every variable the wrapper reads for itself is spelled `UVM_*`, matching the `uvm` command alias
already shipped. The `UV_*` variables the wrapper *exports for uv* are untouched: those genuinely are
`uv`'s, and renaming them would be wrong. Nothing else about the wrapper's behavior changes.

Nothing is deployed at 0.2.0, so this is a clean break with no compatibility shim — see Clarifications.

## Acceptance criteria (the contract)

- **R1** — The wrapper SHALL read its configuration from `UVM_ROOT`, `UVM_PIN`, `UVM_PLATFORM`,
  `UVM_INSTALL_URL`, `UVM_LOCK_TIMEOUT` and `UVM_LOCK_STALE`, with the same meanings and defaults the
  `UV_MANAGER_*` names have today.
- **R2** — IF a `UV_MANAGER_*` name is set and its `UVM_*` counterpart is not, THEN the wrapper SHALL
  behave exactly as if nothing were set. Observable: in a sandbox with no scratch candidate present,
  `UV_MANAGER_ROOT=/some/dir uvm status` exits non-zero with the existing "cannot determine where to
  keep per-user uv state" message rather than resolving that directory.
- **R3** — The wrapper SHALL continue to export `UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`,
  `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR` and its `PATH` prepends unchanged. Observable: the five
  paths `uvm status` prints are identical before and after, given the same root.
- **R4** — WHEN `uv-manager status` resolves its root from the environment, the origin it reports
  SHALL read `UVM_ROOT`; WHEN `uv-manager help` is run, its Environment block SHALL list the six new
  names and no `UV_MANAGER_*` name.
- **R5** — `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua` and the
  `uvm_help` heredoc SHALL carry the new names, in the same commit as the script change.
- **R6** — `.agents/factory/bin/temp_root.sh` SHALL drive the wrapper through the new names, and a
  `UVM_*` wrapper knob inherited from the developer's environment SHALL NOT reach a drive. Observable:
  `UVM_PIN=1.2.3 .agents/factory/bin/temp_root.sh uvm status` reports no pin. The current scrub matches
  `^UV_[A-Za-z0-9_]*=`, which does not match `UVM_`, so this is a behavior change and not a rename.
- **R7** — No `UV_MANAGER_` occurrence SHALL remain in the working tree outside the historical records
  named in Non-goals. Verified by `git grep -n UV_MANAGER_`. This covers the factory's normative
  documents (`AGENTS.md`, `.agents/factory/invariants.md`, `methodology.md`, `ears.md`,
  `review-rubric.md`, the skills) and the `verify:` example in
  `.agents/factory/templates/TECH.md`, which would otherwise seed a broken command into every future
  TECH.md.

R5 and R7 are grep-verifiable rather than drive-verifiable; R4's help output is drivable.

## Non-goals (no-gos)

- **No compatibility surface of any kind** — no dual-name fallback, no deprecation warning, no
  detection of a legacy name. Nothing is deployed, and hedging against a non-issue is its own defect.
- **The exported `UV_*` storage variables are not renamed.** They are `uv`'s namespace by right.
- **`UVM_SANDBOX` and `UVM_FIXTURE_*` are unchanged.** They already sit in the target namespace.
- **No version bump and no tag.** Release cadence belongs to `/uvm-release`.
- **No change to resolution behavior** — the scratch cascade, its candidate list, defaults, precedence
  and error text are the same; only the names move.
- **The trampoline platform-override defect is not fixed here** even though this cycle edits the same
  line. It is `issues/trampoline-ignores-platform-override.md`, sequenced after the test harness so it
  lands with a regression test.
- **Historical records keep the old names**: `issues/uvm-env-prefix.md` (this cycle's own seed) and
  anything under `spec/`. They describe what was true when written; rewriting them falsifies the
  record. Live seeds that describe future work — `issues/trampoline-ignores-platform-override.md`,
  `issues/test-harness.md` — are updated, because a stale seed misleads the cycle that promotes it.

## Clarifications

- **Q:** Sites already running 0.2.0 may have `UV_MANAGER_ROOT` in a modulefile or a Globus Compute
  endpoint configuration. Clean break, dual-name shim, or deprecation warning? — **A:** Clean break,
  with no warning. Nobody is using it yet, so a compatibility path would be a code smell hedging
  against a non-issue (resolved 2026-08-07).

## Related materials

- Seed: [`issues/uvm-env-prefix.md`](../../issues/uvm-env-prefix.md)
- `README.md` — the environment-variable reference table, the sample `status` output, the modulefile
  excerpt, and the `sbatch` example all quote the names.
- `.agents/factory/invariants.md` — the same-commit rule and the storage/resolution boundary.
- Note for `/uvm-plan`: `temp_root.sh` sets `UVM_SANDBOX` and `UVM_FIXTURE_DIR` itself and the fixture
  reads `UVM_FIXTURE_VERSION`, `UVM_FIXTURE_EXIT` and `UVM_FIXTURE_BROKEN`. A blanket `UVM_*` scrub
  would also strip a fixture variable a drive is deliberately passing in, so R6 needs a decision about
  scope rather than a wildcard.
