---
status: unshaped | shaped | adopted:{slug} | declined | accepted-behaviour
kind: feature | fix | refactor
appetite: small | medium | big
lane: public
---

# {Title}

> **Candidate, not a contract.** This file records deferred work in enough detail that a future
> session does not have to re-derive it. It is **not** graded by `uvm-review` and must never be copied
> into `spec/{slug}/GOAL.md` verbatim — `/uvm-feature` promotes it, and that is where appetite,
> non-goals and the R-IDs get negotiated with a human. The `status:` field above is the guard.
>
> Deliberately **not** named `GOAL-{slug}.md`: every other GOAL in the factory is a locked contract,
> so a file carrying that name eventually gets treated as one.
>
> Body sections mirror [`GOAL.md`](../.agents/factory/templates/GOAL.md) so promotion is a
> move-and-fill rather than a rewrite. Links below are written relative to `issues/{slug}.md`, where
> the filled-in copy lives — not to this template.

## Status vocabulary

| `status:` | Means | What `/uvm-feature` does with it |
|---|---|---|
| `unshaped` | A raw deferral. Evidence captured; appetite, non-goals and R-IDs are **not** agreed. | Full shaping conversation before a GOAL exists. |
| `shaped` | Already negotiated with a human — dated clarifications, agreed appetite, non-goals, R-IDs — but **not yet accepted into a cycle**. | Re-confirm scope against current `main`, then adopt largely as written. |
| `adopted:{slug}` | Promoted; `spec/{slug}/` now owns it. | Nothing. The seed and its ROADMAP entry stay while the cycle is in flight, because it may bounce or be abandoned; `/uvm-roadmap` deletes both once the branch lands on `main`. |
| `declined` | Considered and **not** taken on as debt, with the reasoning and what would change the answer. | Nothing — it is not a candidate. |
| `accepted-behaviour` | Reported as a defect, judged **intended**. Exists so it is not re-filed. | Nothing — but read it before "fixing" the behavior. |

The last two are terminal records, not queue entries; `ROADMAP.md` lists them apart from the ordered
cycles so the index stays an index of *work*. A deferral closed **without shipping** becomes one and
keeps its file, because nothing else in the repository records that the question was ever asked. A
deferral that shipped is deleted instead: the code refutes a re-filing on its own, and `spec/{slug}/`
holds the account.

`shaped` is not a shortcut past the human gate. It records that the *shaping* happened, not that the
work was accepted; acceptance is still `/uvm-feature` creating the branch and the GOAL.

`lane: public` lives in `issues/`. Security-sensitive deferrals use `lane: security` and live in
`.security/issues/` — see the deferral table in [`AGENTS.md`](../AGENTS.md).

## Problem

<What is wrong today, for whom, and why it matters. Include the evidence the finder had at hand:
`bin/uv-manager:NNN`, the mechanism, the observed behavior, and the exact command that shows it. This
is the expensive part of a deferral and the part a one-line roadmap seed throws away.>

## Why it was deferred

<Why it was not safe or sensible to fix in the pass that found it: scope, blast radius, a GOAL
non-goal, an appetite boundary, or a dependency on other work. Say plainly whether it is
**pre-existing** on `main` or introduced by that pass — a reviewer will ask.>

## Outcome / vision

<What "good" looks like when this is fixed.>

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion. Prefer EARS phrasing (see
[`ears.md`](../.agents/factory/ears.md)).

- **R1** — WHEN <trigger>, the <component> SHALL <observable response>.

## Notes

- Related: <other `issues/` files, `spec/{slug}/` records, or GitHub issues>
- Found by: <slug + phase, e.g. `lock-hardening` P3 — or an out-of-cycle review>
