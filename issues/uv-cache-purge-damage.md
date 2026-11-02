---
status: adopted:uv-cache-purge-damage
kind: feature
appetite: big
lane: public
---

# A purge that damages uv's cache breaks `uv run` and `uvx`, and nothing repairs it

## Problem

The wrapper points `UV_CACHE_DIR` at `${uvm_root}/cache`, inside the tree a scratch purge reaches. A
PEP 723 script's environment lives there, under `environments-v2/`: measured during
`purge-tree-repair` shaping with uv 0.13.6, `uv run --no-project s.py` for a script declaring one
dependency built its environment at `${UV_CACHE_DIR}/environments-v2/s-<hash>`. An ephemeral `uvx`
environment lives in the archive store itself: on a production cluster on 2026-11-01, under the deployed
`uv/0.7.0` module, every tool run that day with `uvx` and never installed (`pb` from a git source,
`tqdm`, `httpie` among them) had its environment at `${UV_CACHE_DIR}/archive-v0/<hash>/`, with its
own `pyvenv.cfg` and `bin/`, while `tools/` was empty. uv runs no integrity check on that store
(`spec/purge-resilient-run/research/00-digest.md` D3). So a per-file atime purge can leave `uv run
<script>` or `uvx <tool>` failing on a cache that `UVM_REPAIR` never touches.

The second of those is a supported job-script route, and the one `README.md` § *Repairing inside a
job* recommends today. Its *Reach* paragraph tells a job script to call `uvx <tool>` rather than the
tool's own name, so that the scope check runs. For a tool not installed with `uv tool install`, `uvx`
runs it from the cache, and the check walks `tools/` and `python/` only, so `srun uvx <tool>` gets the
check and not the repair.
An installed tool is out of reach of cache damage: the module sets `UV_LINK_MODE=copy`, so
`tools/<name>/` holds its own copies of every file, and the tool arm reinstalls with `--no-cache`.

Who it hurts is a user inside a batch job, the same user `purge-tree-repair` serves, and in
particular the one who took the `srun uvx <tool>` route.

`README.md` § *Scratch purges* records that losing the cache **entirely** is fine, since uv
re-downloads. Partial loss inside an environment or an unpacked archive is the case nobody has
measured.

**Pre-existing** on `main`. Not measured: shaping and the 2026-11-01 listing showed where the
environments live, not that a partially purged one fails. The first job here is to construct that
failure, for a script environment and for an ephemeral `uvx` one.

## Why it was deferred

Conceded by `purge-tree-repair` at its GOAL gate (2026-10-29, the foreman's ruling on its M3). The
repair the obvious design implies is to clear a shared cache under the repair lock, after which
every rank of the job rebuilds its environment at once. uv serializes that with `flock` on the
cache, which is not enabled on every parallel filesystem (`README.md` § *Provision once, then run
directly*). That is a concurrency design of its own, not a fourth arm on a whole-tree repair.

## Outcome / vision

A job whose cache a purge has damaged sets `UVM_REPAIR`, calls `uv run <script>` or `uvx <tool>`,
and proceeds, under the same one-repairs-the-rest-wait contract `purge-tree-repair` ships. This is
the `uvx` route's half of a two-route contract: `srun uvx <spec>` and, after
[`installed-tool-parity`](installed-tool-parity.md), `uv tool install` then `srun <tool>` both carry
it, and neither replaces the other. Until this cycle lands, the documentation says plainly that
`srun uvx <tool>` is repaired only for an installed tool, and that `uv cache clean` is the manual
remedy.

## Sketch of the acceptance criteria

- **R1** — A drive SHALL establish whether a partially purged script environment, a partially
  purged ephemeral `uvx` environment, and a partially purged unpacked archive make `uv run <script>`
  or `uvx <tool>` fail, and the result SHALL be recorded before any repair criterion is shaped.
- **R2** — WHERE `UVM_REPAIR` is set and damage of a class R1 established is detected in the cache,
  the repair SHALL leave `uv run <script>` and `uvx <tool>` succeeding, under `purge-tree-repair`'s
  lock, scope and outcome contract, and SHALL NOT remove an entry another process may be executing
  from without stating how that process is protected.
- **R3** — The ranks that waited SHALL NOT rebuild one environment concurrently on a filesystem
  without working `flock`, or the documentation SHALL say where they do.
- **R4** — `README.md` and `uvm help` SHALL stop listing cache damage as conceded once it is
  repaired, and SHALL keep listing whatever R1 shows is still undetectable.

## Notes

- Related: [`spec/purge-tree-repair/`](../spec/purge-tree-repair/GOAL.md), landed, whose GOAL concedes
  this class and names this seed; [`installed-tool-parity`](installed-tool-parity.md), which gives the
  installed route the same contract from durable records under `UVM_DATA`. An installed tool is out
  of this class's reach either way; this cycle is what completes the `uvx` route.
- A direction to measure, not a decision: under the repair lock, `mv` a damaged entry aside rather
  than delete it. A rename within one filesystem is atomic, a process with the entry open keeps its
  files, and the next call misses and rebuilds with one rank holding the lock. It still leaves R3.
- Found by: `purge-tree-repair` shaping, 2026-10-29. Widened to `uvx` on 2026-11-01, from the
  maintainer dogfooding the deployed module on a production cluster.
