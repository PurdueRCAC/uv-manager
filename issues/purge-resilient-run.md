---
status: adopted:purge-resilient-run
kind: feature
appetite: big
lane: public
---

# A run entry point that survives a purge, at job scale

## Problem

Two gaps that share a cause and pull against each other.

**Damage the wrapper detects but never repairs.** A scratch purge is per-file on access time, so a
tool environment is removed piecemeal while uv still believes it is installed. The banner above
`uvm_doctor` (`bin/uv-manager:644`) states the consequence: uv "performs no integrity check on an
environment it believes is installed; it will exec a half-deleted venv and produce an ImportError."
`uvm_doctor` (`:648`) finds exactly that damage, by walking every `dist-info/RECORD` and stating every
file it lists (`:689`). What it does with the answer is print instructions for a human (`:729`):

```
uv-manager install
uv tool uninstall <name> && uv tool install <name>
uv python uninstall <ver> && uv python install <ver>
```

Nobody reads that from a compute node at 03:00, and automation cannot act on it at all. Nothing else
covers the gap: `uvm_ensure_uv` (`:370`) guards only the uv binary, since `uvm_have` (`:265`) is one
`-x` test on `${uvm_current}/uv`; and the unconditional `mkdir -p` in `uvm_export_env` (`:405`)
restores the *shape* of the tree, not its contents. A user who comes back after thirty days gets an
ImportError, not a re-provision.

**The hot path already costs more than it looks, and it is paid per rank.** Measured in the factory
sandbox, warm tree, 50 invocations, on local SSD:

| | per call |
|---|---|
| `uv --version` through the wrapper | 9.6 ms |
| the same real `uv` invoked directly | 3.1 ms |
| the six-directory `mkdir -p` in `uvm_export_env`, all six already present | 2.4 ms |
| a bare subshell fork, for subtraction | 0.8 ms |

The wrapper's ~6.5 ms of overhead is therefore about a quarter metadata work that accomplishes nothing
on a warm tree. The comment at `:402` defends it as "a handful of metadata operations", which is true
of one process. Ten thousand ranks starting `uvx` at once issue those six directory operations ten
thousand times against a single metadata server, in a burst, and local SSD is the optimistic case for
a number that is charged to a parallel filesystem.

The two gaps constrain each other. Any integrity check strong enough to catch a partial purge is far
more expensive than the `mkdir -p` whose cost is already in question — doctor's RECORD walk is
proportional to the number of installed files — so "check before running" cannot be bolted onto the
exec path as it stands.

**`uvx` is not straightforwardly immune, and establishing where it is belongs in the cycle.** `uvx`
execs `uv tool run` (`:845`), which prefers an already-installed tool over building an ephemeral
environment; where that installed tool is the half-purged one, `uvx` inherits the failure rather than
routing around it. Such resilience as it has comes from rebuilding out of `UV_CACHE_DIR`, which is on
the same purged filesystem, and it pays full per-rank resolution to get it.

## Why it was deferred

Not deferred out of a pass — filed as new work during the roadmap sweep. **Pre-existing** on `main`:
the gap has been there since `uvm_doctor` was written to report rather than repair.

It is recorded rather than shaped because it carries at least four unresolved design questions, and it
touches three of the high-risk regions named in `AGENTS.md` — `uvm_export_env`, the dispatch tail, and
whatever coordinates a repair, which will be the provisioning lock.

## Outcome / vision

A job that has not run since before the purge window starts, notices its environment is damaged,
repairs it exactly once across however many ranks, and proceeds. Ranks that did not win the repair
wait for it rather than each re-deriving the same conclusion against the same metadata server. On an
intact tree the check costs less than the metadata the wrapper spends unconditionally today.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — WHILE the selected environment is intact, the entry point SHALL issue no more filesystem
  metadata operations per invocation than the current hot path.
- **R2** — WHEN the environment is damaged, exactly one process SHALL perform the repair; the others
  SHALL wait for it and then proceed, and SHALL NOT each independently attempt one.
- **R3** — WHEN a repair completes, the command the user asked for SHALL run, and the exit status SHALL
  be that command's own.
- **R4** — The integrity check on the hot path SHALL be bounded, and SHALL NOT be proportional to the
  number of installed files.
- **R5** — WHILE no damage exists, the entry point SHALL NOT require network egress.
- **R6** — The repair SHALL be correct under concurrent execution across nodes on Lustre, GPFS and NFS,
  using the `mkdir` discipline already in `uvm_acquire_lock` rather than `flock`.

## Notes

Open questions for shaping, each with a real trade-off:

- **Whether this is a new subcommand at all.** `AGENTS.md` carries a standing bias against adding one,
  and the entry point could equally be a knob on the existing dispatch. `uvm run` is the shape the
  request came in as, not a settled answer.
- **What the cheap check is.** A stamp file whose mtime is compared against the tree costs one `stat`
  but can be stale; a real check catches the partial purge but is doctor's cost. A middle option is to
  verify only what the invocation is about to use.
- **What the losing ranks do.** Wait on the lock, or proceed optimistically and fail. Waiting is
  correct and is what `uvm_acquire_lock` already implements; it also serializes ten thousand ranks
  behind one repair, so the timeout at `:233` becomes load-bearing at a scale it was not sized for.
- **Whether `uv` and `uvx` get any of this, or only the new entry point.** Automatic repair in the exec
  path spends the 7 ms budget and changes `exec` semantics for every caller.
- **Hard installations versus per-rank ephemeral resolution.** Preferring `uv tool install` for
  distributed jobs is the point of the request: one resolved environment the ranks share, rather than
  ten thousand independent assessments of the same tree.
- **Whether the unconditional `mkdir -p` is separable.** It may be a cheap win on its own, and it may
  be the thing a stamp file replaces. Decide whether it is in this cycle or its own.
- Related: [`issues/uvm-bootstrap.md`](uvm-bootstrap.md) — the Anvil MEP / Globus Compute case wants
  both, since the endpoint may need to bootstrap the wrapper *and* face a purged tree in the same run.
- Related: [`issues/test-harness.md`](test-harness.md). R2 and R6 are concurrency assertions, which
  that seed already names as the highest-risk and hardest thing to test.
- Found by: the maintainer, filed during the roadmap sweep of 2026-08-09.
