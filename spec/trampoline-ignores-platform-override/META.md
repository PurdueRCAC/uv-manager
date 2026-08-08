# META — Trampolines resolve the platform key the wrapper actually uses

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

- **slug:** trampoline-ignores-platform-override

## What worked well

- `uvm-feature` Step 4's `status:` triage made the shaping obligation unambiguous: `unshaped` meant the
  seed's draft R-IDs were input rather than contract, so the three open design questions went to the
  human instead of being guessed.

## Friction findings

## F1 — Promotion never reads the seed's ROADMAP entry, where sequencing lives
`origin=uvm-feature:4 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 4 directs you to the `issues/{slug}.md` frontmatter and body, and only
  mentions `ROADMAP.md` later as a file to *edit*. This seed's roadmap entry carried a constraint its
  issue file did not: "Deliberately sequenced **after** the test harness so the fix lands with a
  regression test." That is an ordering decision a human recorded, and promoting this issue overrides
  it. It changed the shaping materially — it became a question to the human, a non-goal, and a
  rewritten roadmap entry. I found it only because Step 4 later requires editing that entry.
- **Skill cause:** The two halves of a deferral hold different information — the issue holds evidence,
  the roadmap entry holds *position and rationale for that position* — and the promotion step reads
  only the first. Nothing instructs the skill to notice that a promotion jumps recorded order, so
  whether the human is told is left to luck.
- **Recommended fix:** In Step 4's "Promoting an issue", add: read the seed's `ROADMAP.md` entry
  alongside the issue. If it records a sequencing dependency and the cycles it names have not landed,
  surface the reordering for sign-off before shaping, and record the decision as a Clarification and a
  Non-goal. `git ls-tree main --name-only spec/` shows what has landed.
- **Confidence:** high · **Effort:** small
