---
status: unshaped
kind: feature
appetite: big
lane: public
---

# A purge that damages uv's cache breaks `uv run`, and nothing repairs it

## Problem

The wrapper points `UV_CACHE_DIR` at `${uvm_root}/cache`, inside the tree a scratch purge reaches. A
PEP 723 script's environment lives there, under `environments-v2/`: measured during
`purge-tree-repair` shaping with uv 0.13.6, `uv run --no-project s.py` for a script declaring one
dependency built its environment at `${UV_CACHE_DIR}/environments-v2/s-<hash>`. Environments for
`uv run --with` and ephemeral `uvx` runs are kept the same way. uv runs no integrity check on its
unpacked archive store (`archive-v0`), which environments are linked from
(`spec/purge-resilient-run/research/00-digest.md` D3). So a per-file atime purge can leave `uv run
<script>` failing on a cache that `UVM_REPAIR` never touches. Who it hurts is a user inside a batch
job, the same user `purge-tree-repair` serves.

`README.md` § *Scratch purges* records that losing the cache **entirely** is fine, since uv
re-downloads. Partial loss inside an environment or an unpacked archive is the case nobody has
measured.

**Pre-existing** on `main`. Not measured: shaping showed where the environments live, not that a
partially purged one fails. The first job here is to construct that failure.

## Why it was deferred

Conceded by `purge-tree-repair` at its GOAL gate (2026-10-29, the foreman's ruling on its M3). The
repair the obvious design implies is to clear a shared cache under the repair lock, after which
every rank of the job rebuilds its environment at once. uv serializes that with `flock` on the
cache, which is not enabled on every parallel filesystem (`README.md` § *Provision once, then run
directly*). That is a concurrency design of its own, not a fourth arm on a whole-tree repair.

## Outcome / vision

A job whose cache a purge has damaged sets `UVM_REPAIR`, calls `uv run <script>`, and proceeds,
under the same one-repairs-the-rest-wait contract `purge-tree-repair` ships.

## Sketch of the acceptance criteria

- **R1** — A drive SHALL establish whether a partially purged script environment, and a partially
  purged entry in the archive store, make `uv run <script>` fail, and the result SHALL be recorded
  before any repair criterion is shaped.
- **R2** — WHERE `UVM_REPAIR` is set and damage of a class R1 established is detected in the cache,
  the repair SHALL leave `uv run <script>` succeeding, under `purge-tree-repair`'s lock, scope and
  outcome contract.
- **R3** — The ranks that waited SHALL NOT rebuild one environment concurrently on a filesystem
  without working `flock`, or the documentation SHALL say where they do.
- **R4** — `README.md` and `uvm help` SHALL stop listing cache damage as conceded once it is
  repaired, and SHALL keep listing whatever R1 shows is still undetectable.

## Notes

- Related: [`issues/purge-tree-repair.md`](purge-tree-repair.md), whose GOAL concedes this class and
  names this seed.
- Found by: `purge-tree-repair` shaping, 2026-10-29.
