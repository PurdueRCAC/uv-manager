# META — The provisioning lock can be released by a process that does not hold it

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/{slug}/`.
>
> **Silence is the default.** The bar for a finding is one test: *was this the **skill's** fault — not
> mine, not the task's?* A merely hard task, a self-inflicted error, or a one-off code issue that
> belongs in `GOAL.md` or `REVIEW.md` is **not** a finding. The blind `uvm-review` correctness reviewer
> never reads this file; it would leak author intent.

- **slug:** lock-ownership-and-hold-time

## What worked well

- The `medium` → `big` rounding rule landed in `fe45b9b` fired on the first promotion after it was
  written, and turned the question that stalled the previous cycle's shaping into a one-line
  Clarification. Nothing had to be asked.
- Step 4's rule that a deferring non-goal is only a promise if it lands in the named file fired
  **twice** here, and both obligations were real: `issues/test-harness.md` gained R3d and
  `issues/purge-tree-repair.md` gained R11. The predicate generalization in particular existed
  nowhere but this seed's Notes, so without the rule it would have died with the seed at
  `/uvm-roadmap`.

## Friction findings

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — a `shaped` seed can still carry decisions it deliberately left to promotion
`origin=uvm-feature:step-4 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-feature/SKILL.md`
- **What happened:** the seed's `status:` was `shaped`, and Step 4's `shaped` branch says the shaping
  conversation "already happened with a human. Do **not** re-litigate it… adopt it largely as
  written." But the seed's own text carried two decisions it had explicitly parked for this step —
  R4's "whether this is a guard or a documented constraint on the dispatch tail is a promotion
  decision", and a Note saying the early-out predicate generalization "may belong to the repair cycle
  instead". I asked the human about both, which was right, but it is a departure from the letter of
  the branch I was following.
- **Skill cause:** the `shaped` branch is written as if `shaped` meant *fully settled*. It does not,
  and cannot: `/uvm-feature` is what writes these seeds, and deferring a decision to promotion is a
  legitimate thing for a shaping pass to do when the answer depends on what the adopting cycle turns
  out to be. An agent following "do not re-litigate, adopt as written" literally would have guessed
  both, and the R4 guess in particular is a scope difference — a guard in the dispatch tail versus a
  comment. Nothing in the branch tells the reader that a parked decision is not re-litigation.
- **Recommended fix:** one sentence in the `shaped` bullet: a `shaped` seed may still name decisions
  it parked for promotion, and those are this step's to settle with the human — re-litigation is
  reopening what the seed *settled*, not answering what it deliberately left open. Optionally, give
  the phrasing a home in `templates/ISSUE.md` so parked decisions are marked rather than buried in
  prose, which is how both of these were written.
- **Confidence:** high · **Effort:** small
