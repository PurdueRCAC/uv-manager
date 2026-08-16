---
status: unshaped
kind: fix
appetite: small
lane: public
---

# Three small code gaps behind inaccurate invariants

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

An audit of `.agents/factory/invariants.md` against `bin/uv-manager`, run during
`lock-ownership-and-hold-time` planning, found three bullets asserting things the code does not do.
The **text** repairs are harness work (`spec/lock-ownership-and-hold-time/META.md` F5–F7, for
`/uvm-harness`). Behind two of them, and beside a third, sit small **code** gaps that change wrapper
behavior and therefore need a cycle with a deviation table. Each was measured, not read.

**Argument inspection misses two value-taking global options.** `invariants.md` §11 and
`AGENTS.md` assert that `uvm_global_takes_value`'s five entries are the complete set of `uv` global
options taking a separate value, and that "everything else that looks like one is a per-command
option". Measured against `uv 0.12.4`: `uv --cache-dir DIR tool dir` succeeds, and
`uv --python-preference only-managed tool dir` succeeds, while `uv --python 3.12 tool dir` fails with
`unexpected argument`. So both are accepted *before* the subcommand and both take a value. An option
missing from the list is bare-shifted, `uvm_cmd` latches onto its value, and `self update`, `tool` and
`python` all go unrecognized — no trampoline resync, no self-update interception. `--cache-dir` is the
likeliest to be hit in practice: `uvm_set_paths` exports `UV_CACHE_DIR` unconditionally, so the flag
is the only remaining way to redirect the cache. The banner above `uvm_global_takes_value`
(`bin/uv-manager:767-772`) names `--cache-dir` as an example of the category it is a counterexample
to.

**The trampoline overwrite guard tests `-x`.** `invariants.md` §9 and `AGENTS.md` say a file that is
non-empty, executable and unmarked is left alone, and that "only marked files are ever overwritten or
removed". Removal is genuinely marker-only. Overwriting is not: the guard in `uvm_trampolines`
(`bin/uv-manager:725-729`) is a three-way conjunction, so an unmarked file failing `-s` **or** `-x` is
written over. A planted
0644, non-empty user file named for a tool in the union was replaced by the generated trampoline with
no note. `-s` alone already satisfies the "repair a truncated trampoline" requirement the bullet above
it states, so `-x` is buying nothing and costing somebody's file.

**The rename in `uvm_install` is unguarded.** `invariants.md` §6 says "on any failure, remove the
staging directory, release the lock, and die with the pre-warm instructions". Two of the three failure
paths do. The `mv "${tmp}" "${dest}"` in `uvm_install` (`bin/uv-manager:595`) is guarded by nothing:
it dies under
`set -e` with a bare `mv: ... Permission denied` and leaves `versions/.incoming.XXXXXXXX` behind,
which nothing collects.

## Why it was deferred

All three are **pre-existing on `main`** and unrelated to the provisioning lock. The cycle that found
them was mid-flight on a high-blast-radius region with an accepted six-criterion contract, and two of
the three change dispatch-tail behavior. Landing them in that diff would have mixed unrelated risk
into a change already forcing a human sign-off gate, and editing `invariants.md` inside a graded diff
reads as revising the standard being graded against.

## Outcome / vision

The three bullets and the code agree, in whichever direction is right for each: the parser knows the
options `uv` actually accepts before a subcommand, the trampoline writer destroys nothing a user
wrote, and no failure path leaves uncollected litter in `versions/`.

## Sketch of the acceptance criteria

- **R1** — `uvm_global_takes_value` SHALL cover `--cache-dir` and `--python-preference`, and its
  banner, `AGENTS.md` and `invariants.md` §11 SHALL stop asserting that no pre-subcommand option
  outside the five takes a value.
- **R2** — WHEN a file in the trampoline directory is non-empty and lacks `uvm_tramp_marker`, the
  wrapper SHALL leave it alone whatever its mode, and say so.
- **R3** — IF the rename into `versions/<ver>` fails, THEN the wrapper SHALL remove the staging
  directory and die with a message naming the cause.

R3 may instead belong in `issues/purge-tree-repair.md`, which already inventories tree damage; whoever
promotes this should decide rather than land it twice.

## Notes

- Related: `spec/lock-ownership-and-hold-time/META.md` F4–F7 (the text repairs and the standing rule),
  `issues/purge-tree-repair.md` (R3's alternative home).
- Found by: an adversarially-verified audit of `invariants.md` §1–§12 against the code, run during
  `lock-ownership-and-hold-time` planning. Four sections, ~126 claims checked, seven findings filed,
  three refuted. The §5 finding it also produced was taken into that cycle as R7.
- `/uvm-feature` may well split this into three; the criteria share an origin and a verification
  substrate, not a mechanism.
