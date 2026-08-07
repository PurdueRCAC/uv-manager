# GOAL — {Title}

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.
> Keep this at the right altitude: solved and bounded, but not over-specified — leave design freedom
> for the plan. Edit requirements here; do not silently drift them during build.

- **slug:** {slug}
- **kind:** feature | fix | refactor
- **appetite:** small | big  ·  *small caps research and phase count; a one-sentence change may skip
  the lifecycle entirely.*

## Problem

<The raw need, in plain language. What hurts today, for whom, and why it matters. One or two
paragraphs. Motivate the work; do not describe the solution yet. For this project, "for whom" is
usually a site operator or a user inside a batch job — say which, because the two have very different
tolerances for a loud failure.>

## Outcome / vision

<What "good" looks like when this ships. The shared picture we are agreeing on.>

## Acceptance criteria (the contract)

Stable IDs (`R1`, `R2`, …) that survive squash-merge and anchor traceability. Prefer **EARS** phrasing
(see [`ears.md`](../../.agents/factory/ears.md)) — it makes each line directly testable — but plain,
unambiguous prose is acceptable where EARS would be forced.

Each criterion must be observable from a sandbox drive
(`.agents/factory/bin/temp_root.sh …`): an exit status, a path, a symlink target, a line on stderr, an
environment variable in the child process. Two kinds of criterion cannot be, and each declares its
departure where it is written: one that genuinely requires a real cluster says so; one satisfied by
the text of the repository rather than by its behavior — a documentation sweep, a rename's eradication
of the old name — carries its own check inline (`git grep -n …`).

- **R1** — WHEN <trigger>, the <component> SHALL <observable response>.
- **R2** — WHILE <state>, the <component> SHALL <response>.
- **R3** — IF <unwanted condition>, THEN the <component> SHALL <response>.
- **R4** — The <component> SHALL <ubiquitous requirement>.

## Non-goals (no-gos)

Explicit exclusions that keep scope bounded to the appetite. Naming what we are **not** doing matters
as much as what we are — the standing bias in this repository is to delete rather than add, and a
non-goal is how that bias gets recorded.

- <thing deliberately out of scope>

## Clarifications

Questions resolved with the human during shaping. Unresolved ones stay marked
`[NEEDS CLARIFICATION: …]` and **block** `uvm-plan`. Never guess.

- **Q:** <question> — **A:** <answer> (resolved YYYY-MM-DD).

## Related materials

- Issue: <https://github.com/PurdueRCAC/uv-manager/issues/NN>
- Seed: <`issues/{slug}.md`, when this was promoted from a deferral>
- <`README.md` sections, `uv` documentation, upstream Astral issues, prior art>
