---
status: unshaped
kind: fix
appetite: small
lane: public
---

# Two small code gaps behind inaccurate invariants

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

> **Shrunk on 2026-10-27 from four gaps to two.** R3 (the unguarded rename) was absorbed into
> [`lock-simplification`](../spec/lock-simplification/GOAL.md) as its R4 and R10, and R4 (the
> heartbeat's leash) is moot because that cycle, which has shipped, deleted the heartbeat. Their
> numbers are left vacant below rather than closed up, since `ROADMAP.md` and other seeds cite R1–R4
> by number.

## Problem

An audit of `.agents/factory/invariants.md` against `bin/uv-manager`, run during
`lock-ownership-and-hold-time` planning, found bullets asserting things the code does not do. A
fourth arrived the same way, from `lock-break-instance-identity` shaping.
The **text** repairs are harness work (`spec/lock-ownership-and-hold-time/META.md` F5–F7, for
`/uvm-harness`). Behind two of them, and beside a third, sit small **code** gaps that change wrapper
behavior and therefore need a cycle with a deviation table. Each was measured, not read.

**Argument inspection misses two value-taking global options.** The banner above
`uvm_global_takes_value` asserts that its five entries are the complete set of `uv` global options
taking a separate value, and that "everything else that looks like one … is a per-command option".
`invariants.md` §11 and `AGENTS.md` asserted the same until 2026-09-07, when the harness text repair
corrected both to say the list is not complete. Measured against `uv 0.12.4`:
`uv --cache-dir DIR tool dir` succeeds, and `uv --python-preference only-managed tool dir` succeeds,
while `uv --python 3.12 tool dir` fails with `unexpected argument`. So both are accepted *before* the subcommand and
both take a value. An option missing from the list is bare-shifted, `uvm_cmd` latches onto its
value, and `self update`, `tool` and `python` all go unrecognized — no trampoline resync, no
self-update interception. `--cache-dir` is the likeliest to be hit in practice: `uvm_set_paths`
exports `UV_CACHE_DIR` unconditionally, so the flag is the only remaining way to redirect the cache.
The banner (`bin/uv-manager:676-681`) names `--cache-dir` as an example of the category it is a
counterexample to.

**The trampoline overwrite guard tests `-x`.** `invariants.md` §9 and `AGENTS.md` say a file that is
non-empty, executable and unmarked is left alone. Until 2026-09-07 both also said "only marked files
are ever overwritten or removed"; the harness text repair narrowed that to removal, and both now
name the `-x` term as a gap this seed carries. Removal is genuinely marker-only. Overwriting is not:
the guard in `uvm_trampolines` (`bin/uv-manager:634-638`) is a three-way conjunction, so an unmarked
file failing `-s` **or** `-x` is written over. A planted 0644, non-empty user file named for a tool
in the union was replaced by the generated trampoline with no note. `-s` alone already satisfies the
"repair a truncated trampoline" requirement the bullet above it states, so `-x` is buying nothing
and costing somebody's file.

The two further gaps this file used to carry — the unguarded rename in `uvm_install`, and the
heartbeat's leash silently degrading to bare `kill -0` — left with `lock-simplification` (banner
above). That GOAL's R4 and R10 carry the rename's evidence, measured red on `main` on 2026-10-27.

## Why it was deferred

Both remaining findings are **pre-existing on `main`** and unrelated to the provisioning
lock. The cycle that found
them was mid-flight on a high-blast-radius region with an accepted six-criterion contract, and both
change dispatch-tail behavior. Landing them in that diff would have mixed unrelated risk
into a change already forcing a human sign-off gate, and editing `invariants.md` inside a graded diff
reads as revising the standard being graded against.

## Outcome / vision

The bullets and the code agree, in whichever direction is right for each: the parser knows the
options `uv` actually accepts before a subcommand, and the trampoline writer destroys nothing a user
wrote.

## Sketch of the acceptance criteria

- **R1** — `uvm_global_takes_value` SHALL cover `--cache-dir` and `--python-preference`, and its
  banner, `AGENTS.md` and `invariants.md` §11 SHALL stop asserting that no pre-subcommand option
  outside the five takes a value.
- **R2** — WHEN a file in the trampoline directory is non-empty and lacks `uvm_tramp_marker`, the
  wrapper SHALL leave it alone whatever its mode, and say so.
- **R3** — *Moved out* on 2026-10-27 to
  [`lock-simplification`](../spec/lock-simplification/GOAL.md), where it is R10 and, for the
  concurrent-publish half, R4.
- **R4** — *Moot*: [`lock-simplification`](../spec/lock-simplification/GOAL.md) R7 deleted the
  heartbeat and its leash, so there is no degradation left to make visible.

## Notes

- Related: `spec/lock-ownership-and-hold-time/META.md` F4–F7 (the text repairs and the standing rule),
  [`spec/lock-simplification/GOAL.md`](../spec/lock-simplification/GOAL.md) (where R3 went, and what
  made R4 moot).
- Found by: an adversarially-verified audit of `invariants.md` §1–§12 against the code, run during
  `lock-ownership-and-hold-time` planning. Four sections, ~126 claims checked, seven findings filed,
  three refuted. The §5 finding it also produced was taken into that cycle as R7.
- `/uvm-feature` may well split this up; the two criteria share an origin and a verification
  substrate, not a mechanism.
