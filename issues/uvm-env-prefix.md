---
status: adopted:uvm-env-prefix
kind: refactor
appetite: small
lane: public
---

# Rename the UV_MANAGER_* environment prefix to UVM_*

## Problem

The wrapper's six configuration variables all begin with `UV_MANAGER_`. That prefix sits inside `uv`'s
own namespace: `uv` reads dozens of `UV_*` variables (`UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_LINK_MODE`,
`UV_PYTHON_DOWNLOADS`, and a growing list), and a reader scanning a modulefile or a job script cannot
tell from the name whether `UV_MANAGER_ROOT` is something Astral honors or something this wrapper
invented. Astral is free to add a `UV_MANAGER_*` name at any time, and the wrapper deliberately passes
unrecognized `UV_*` variables through untouched, so the collision would be silent.

`UVM_*` is unambiguous: it is the wrapper's namespace and nothing else's. It matches the `uvm` command
alias already shipped, and it keeps the boundary the whole project is organized around — *storage is
ours, resolution is uv's* — visible in the variable names themselves.

Current surface, from `git grep`:

| Variable | Occurrences |
|---|---|
| `UV_MANAGER_ROOT` | 36 |
| `UV_MANAGER_PIN` | 7 |
| `UV_MANAGER_PLATFORM` | 5 |
| `UV_MANAGER_INSTALL_URL` | 5 |
| `UV_MANAGER_LOCK_TIMEOUT` | 4 |
| `UV_MANAGER_LOCK_STALE` | 4 |

Spread across `README.md` (25), `bin/uv-manager` (19), `etc/uv-manager.conf.example` (13) and
`share/modulefiles/uv/main.lua` (4).

## Why it was deferred

Recorded during the harness port, before any cycle had started. It is not a defect and nothing is
broken; it is a naming decision that has to be made deliberately because it is user-visible.

The real question is **compatibility**, and it is a shaping question, not an implementation one. Any
site that has already deployed 0.2.0 has `UV_MANAGER_ROOT` written into a modulefile, a Globus Compute
endpoint configuration, and possibly job scripts. Three defensible answers:

1. **Clean break.** Rename, bump the minor version, say so in the release notes. Simplest code, and
   honest at this stage of adoption.
2. **Accept both, prefer `UVM_*`.** A short compatibility shim per variable. Costs a few lines on the
   hot path and permanent explanation in the README.
3. **Accept both, and warn once on the old name.** As above, plus a deprecation path with a removal
   version.

Which one is right depends on how widely 0.2.0 is actually deployed today, which is a fact the
maintainer has and this file does not.

## Outcome / vision

Every variable the wrapper itself reads is spelled `UVM_*`, and no reader has to wonder whether a name
belongs to `uv` or to the wrapper. The `UV_*` variables the wrapper *exports for uv* — `UV_CACHE_DIR`,
`UV_TOOL_DIR`, and the rest — are unaffected: those genuinely are uv's, and renaming them would be
wrong.

## Sketch of the acceptance criteria

- **R1** — The wrapper SHALL read `UVM_ROOT`, `UVM_PIN`, `UVM_PLATFORM`, `UVM_INSTALL_URL`,
  `UVM_LOCK_TIMEOUT` and `UVM_LOCK_STALE`.
- **R2** — The wrapper SHALL continue to export the `UV_*` storage variables unchanged; only the
  variables it *reads for itself* are renamed.
- **R3** — WHEN `uv-manager status` is run, it SHALL report the new names and the origin of the
  resolved root.
- **R4** — `README.md`, `etc/uv-manager.conf.example` and `share/modulefiles/uv/main.lua` SHALL use the
  new names throughout, in the same commit (`invariants.md` §12).
- **R5** — <compatibility behavior, once the human has chosen among the three options above>.

## Notes

- The factory's own `temp_root.sh` scrubs variables by the `UV_*` pattern; it needs the same rename in
  the same cycle or the sandbox stops isolating the wrapper's own knobs.
- `UVM_FIXTURE_*` in the installer fixture is already in the target namespace and is unaffected.
- Found by: the maintainer, ahead of the first post-harness cycle.
