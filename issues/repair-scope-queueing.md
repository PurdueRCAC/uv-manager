---
status: unshaped
kind: feature
appetite: small
lane: public
---

# Separately submitted jobs queue to check one tree under the repair lock

> **Candidate, not a contract.** `/uvm-feature` promotes it; appetite, non-goals and R-IDs are
> negotiated there.

## Problem

With `UVM_REPAIR` set, the first call in each scope takes the repair lock and walks the tree
(`uvm doctor`'s detection) before it records an outcome. A waiter's predicate tests only its own
scope's outcome. So N scopes that arrive together on one tree walk it one after another, and the
k-th waits about k walks. Any scope past `UVM_LOCK_TIMEOUT / w` in the queue fails at the timeout
on a tree that may be healthy, where w is the walk time:

- about 0.1 s on small trees;
- 0.4-2.8 s on a realistic tree (`spec/purge-resilient-run/research/00-digest.md`);
- the 90th job at w = 2 s and the default 180 s.

`purge-tree-repair` removed the commonest case: array tasks share one scope, keyed on
`SLURM_ARRAY_JOB_ID`. What remains is jobs submitted separately, each with its own `SLURM_JOB_ID`,
that start together on one tree. Examples are a workflow manager submitting many single jobs, or a
dependency release starting a batch at once.

Found in `purge-tree-repair` planning: `spec/purge-tree-repair/research/04-outcome-scope-surface.md`
defect 2, and `PLAN.md` §5, ruling 2.

## Why it was deferred

The fix the planning brief named is to let a waiter accept a repaired outcome written after its own
arrival, from any scope. That amends the waiter predicate that `purge-tree-repair`'s GOAL settled:
one existence test for the waiter's own scope. A change of that kind needs its own shaping. It is
**introduced** by `purge-tree-repair`; `main` has no repair to queue on.

## Outcome / vision

Many jobs arriving together on one tree cost one walk between them, not one each. No arrival ever
reads clean on a tree no check has seen since the arrival began.

## Sketch of the acceptance criteria

- **R1** — WHEN N scopes with no outcome arrive together on one tree, at most one SHALL walk it, and
  the others SHALL proceed on a repaired outcome recorded after they arrived.
- **R2** — A scope SHALL NOT proceed on an outcome recorded before it arrived. That is the
  false-clean case the job scope exists to prevent.

## Notes

- Candidate mechanisms:
  - The waiter records its arrival, and its predicate also accepts any `.ok` newer than that (`-nt`
    is a bash builtin).
  - A per-root "last check" record that the holder rewrites.
  - Either must hold on Lustre and GPFS, where mtime is coherent, and must state NFS attribute
    caching.
- R12 of `purge-tree-repair` covers one job with many ranks, and is unaffected.
- Related: `spec/purge-tree-repair/`, `issues/test-harness.md`.
