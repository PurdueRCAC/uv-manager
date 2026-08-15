---
status: unshaped
kind: feature
appetite: medium
lane: public
---

# A curl-installable bootstrap for sites and automation with no module

## Problem

Every documented route to the wrapper assumes a site administrator deployed it first. `README.md`
§ *For administrators: deployment* describes a central prefix, and `share/modulefiles/uv/main.lua`
puts that prefix on `PATH` — hard-failing with `LmodError` when it is absent, on purpose. Purdue's
clusters have this. An individual user at another site does not, and neither does automation that
cannot presume Lmod exists: a Globus Compute endpoint, a systemd user unit, `sbatch --export=NONE`.

For those readers the wrapper's own diagnosis is circular. The state-root failure message
(`bin/uv-manager:115-120`) tells them to run `module load uv` or export `UVM_ROOT`, and both presume
the script is already on disk. Nothing in the repository says how it gets there.

The constraint that makes this delicate is already written down, in the script header
(`bin/uv-manager:9-12`): do **not** install at `~/.local/bin/uv`, because that is the standalone uv
installer's default `UV_INSTALL_DIR` and landing there would silently overwrite a real `uv` the user
already has. The same paragraph requires the deployment be "opt-in (module load / explicit PATH
addition), never default `PATH`". A `curl | sh` installer that appends to `.bashrc` contradicts that
in writing; one that puts nothing on `PATH` is useless to the person who ran it. Resolving that
tension is the substance of this cycle, not an implementation detail of it.

An up-to-date check has a source of truth to work from: the version is single-sourced at
`bin/uv-manager:21` and `uvm --version` prints it (`:795`).

## Why it was deferred

Filed as new work during the roadmap sweep, not deferred out of a pass. It is a missing distribution
channel rather than a defect, so nothing on `main` is wrong today — the wrapper is unreachable to
anyone the site did not deploy it for.

## Outcome / vision

One `curl … | sh` leaves an individual user, or an unattended endpoint, with a working `uv`, `uvx` and
`uvm` resolving to scratch on the correct architecture — without touching home quota beyond a few KB
of shell, without overwriting anything, and without a site administrator. Running it a second time is
safe, cheap, and does not go to the network.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — WHEN `uvm.sh` runs and no uv-manager is present, it SHALL install one, and SHALL NOT write
  to any path the standalone uv installer claims by default (`bin/uv-manager:9`).
- **R2** — WHEN a uv-manager is already present, `uvm.sh` SHALL exec it rather than reinstall it.
- **R3** — The staleness check SHALL NOT require network egress on every invocation.
- **R4** — `uvm.sh` SHALL be `/bin/sh`, SHALL require nothing beyond `curl` or `wget`, and SHALL be
  short enough to be read in full by the operator deciding whether to pipe it to a shell.
- **R5** — Re-running `uvm.sh` against an installed, current wrapper SHALL change nothing on disk.
- **R6** — WHEN no state root can be resolved, `uvm.sh` SHALL surface the wrapper's own diagnosis and
  SHALL NOT invent a location — in particular it SHALL NOT fall back to `/tmp`.

## Notes

Open questions for shaping, each with a real trade-off:

- **Where it installs, and whether it touches `PATH` at all.** This is the direct collision with
  `bin/uv-manager:9-12`. Printing an `export PATH=…` line for the user to paste honors "opt-in" and
  costs a step; editing a shell profile removes the step and breaks the rule.
- **A variable naming the install location — `UVM_INSTALL` or similar — read by the hosted `uvm.sh`**
  for where it stashes the local copy of the wrapper for the next exec. The location becomes something
  an operator or an automation harness states rather than something `uvm.sh` picks, which is most of
  what makes the collision above dangerous: nobody is surprised by a path they named. Two questions
  come with it. How does it relate to `UVM_ROOT` — the same scratch tree keeps everything in one place
  and costs no second decision, but then a purge that removes the wrapper removes the thing that would
  have repaired the tree, which is exactly the failure `issues/purge-tree-repair.md` is about. And
  what is the default when it is unset, given `~/.local/bin/uv` is forbidden. — the maintainer,
  2026-08-09.
- **The `curl | sh` posture.** The project already fetches uv this way (`uvm_fetch`, `:249`, and the
  piped `sh` at `:341`), so the precedent is uv's own. Decide whether a tag pin, a published checksum,
  and a documented download-inspect-run path are required rather than optional, given this is
  potentially load-bearing infrastructure for a computing center.
- **What "up to date" means, and how often it is checked.** A version check per invocation adds a
  network round trip to the hot path and an egress requirement to every compute node — which the
  wrapper deliberately confines to provisioning. A time-gated stamp, or an explicit-only check, keeps
  that property.
- **Whether "a wrapper around the wrapper" is really a process in the exec path.** The dispatch tail
  `exec`s so that signals, exit codes and process accounting are the real uv's; interposing another
  shell costs a fork against a 5 ms budget and has to preserve those semantics.
- **Where it is served from.** The repository is `PurdueRCAC/uv-manager`. A raw-content URL pins to a
  branch and changes under users; a release asset pins to a tag and needs the release process to
  publish it. `/uvm-release` would grow a step either way.
- Related: [`issues/purge-tree-repair.md`](purge-tree-repair.md). The two are one story for
  automation — the Anvil MEP endpoint may need to bootstrap the wrapper *and* face a tree purged since
  the user's last run, thirty days earlier, in the same invocation.
- **Same-commit rule.** A new top-level script is user-facing surface, so `README.md` and the
  `uvm_help` heredoc move with it, and the modulefile's relationship to it needs stating: a site with
  the module should not end up with two wrappers disagreeing about `UVM_ROOT`.
- Found by: the maintainer, filed during the roadmap sweep of 2026-08-09.
