---
status: unshaped
kind: fix
appetite: small
lane: public
---

# A pinned call can run another call's pin, when two pins race for `current`

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

`current` is one link per root, and a pin is per process. Two calls on one root that are pinned to
*different* versions each select their own, through `uvm_install`'s one selection step, and the
later swap wins. Every run of `uv` then goes through `current`: `real_uv` is `${uvm_current}/uv`
(`bin/uv-manager:154-156`), the dispatch tail execs it (`:1707-1713`), `uv self update` execs it
(`:782`), and the `tool`/`python` path runs it without exec (`:1689`). So the earlier call, having
selected its pin correctly, runs the later call's version at rc 0 with nothing on stderr.

Measured by `lock-simplification` review cycle 3 (finding C3-F1), under
`.agents/factory/bin/temp_root.sh --offline`:

- **Shimmed.** Call A, pinned 6.6.6, paused after its rename; call B, pinned 9.9.9, ran to
  completion; A then printed `uv 9.9.9 (fixture)` at rc 0.
- **No shims.** 8-rank bursts alternating the two pins, 40 bursts, run twice: **13 of 320** and
  **19 of 320** ranks printed the other pin's version at rc 0. No rank failed and no link nested.
  This is on the atomic `mv -h` path, so it is not the non-atomic fallback's hazard.
- **Same-pin control.** The same bursts with one pin throughout: **0 of 320** wrong.

**Ranks sharing one pin are unaffected**, which is the case that matters most. Every rank of an
`srun` job inherits the same `UVM_PIN`, the ranks agree on `current` whichever swap lands last, and
that case is what `lock-simplification` R12 graded green. The exposure is two differently pinned
workloads sharing one architecture's tree at once, such as two jobs from one user, or a job and an
interactive shell.

The behaviour is documented rather than hidden. `.agents/factory/invariants.md` §4 says a pin is
authoritative over which version a call *selects*, and over `current` only while no concurrent call
on the same root selects a different version. `README.md` § *Automation: Globus Compute endpoints*
says differently pinned calls race for `current` and the last one wins. What the documentation
concedes is still a call running a version it did not ask for, at rc 0.

## Why it was deferred

**Pre-existing on `main`** before `lock-simplification`, and outside its range: that cycle fixed a
pinned call losing a *provisioning* race (its R12), not a race between two pins. Review cycle 3 was
the last the bounded loop allowed, and it found this as an inexactness in the prose qualifying "a
pin is authoritative", not as a defect in the diff. The maintainer was offered a rescope that would
have taken the code change into that cycle, and chose to ship with the wording corrected and this
recorded as deferred (`spec/lock-simplification/REVIEW.md` § *Maintainer override*, 2026-10-28).

## Outcome / vision

A pinned call runs the version it pinned, whatever any concurrent call on the same root selects.
`current` remains the shared default for unpinned calls and for anything that runs it directly.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — WHEN a pinned call has selected its pin, the wrapper SHALL run the pinned version,
  whatever version a concurrent call on the same root has since pointed `current` at.
- **R2** — Behaviour SHALL be unchanged for calls sharing one pin and for unpinned calls: one
  installer per burst on a cold tree, and `current` naming the selected version afterwards.
- **R3** — The hot path SHALL NOT grow a fork or a filesystem test for an unpinned call.

## Notes

- **A direction, not a decision.** The obvious shape is for a pinned call to exec its own
  `versions/<pin>/uv` (and `uvx`) rather than going through `current`, which takes the race out of
  the call without touching the shared link. Questions it raises for shaping: whether a pinned call
  should still swap `current` at all, or leave that to unpinned ones; whether the `tool`/`python`
  path, which runs `uv` without exec and then regenerates trampolines, follows the pin too; and how
  this sits with §4's rule that `uvm_install` is the only place the script selects.
- The construction needs no shims. Under `temp_root.sh --offline`, write a 6.6.6 fixture at
  `$UVM_FIXTURE_DIR/6.6.6/install.sh`, start concurrent ranks on one root alternating
  `UVM_PIN=6.6.6 UVM_FIXTURE_VERSION=6.6.6` with `UVM_PIN=9.9.9`, and histogram each rank's stdout
  against its own pin. The same-pin run is the control.
- Related: [`spec/lock-simplification/`](../spec/lock-simplification/GOAL.md). Its `REVIEW.md`
  cycle 3 carries the drives (D3, D4, D4c), and its R12 is the same-pin case this file leaves alone.
- Found by: `lock-simplification` review cycle 3, C3-F1; recorded as deferred by the maintainer's
  override at landing, and filed by `/uvm-roadmap` when that cycle's seeds retired.
