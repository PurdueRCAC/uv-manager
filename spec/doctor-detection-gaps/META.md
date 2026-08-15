# META — `uvm doctor` reports OK on the damage it exists to find

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

- **slug:** doctor-detection-gaps

## What worked well

- `uvm-feature` Step 4's rule that a deferring non-goal is only a promise if it lands in the named
  file caught a real gap: writing R3c into `issues/test-harness.md` surfaced that two of this cycle's
  criteria resist the obvious test, which would otherwise have been discovered by whoever writes the
  suite.

## Friction findings

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — `appetite: medium` is a legal issue value with no legal GOAL translation
`origin=uvm-feature:step-2 severity=medium category=template status=open target=.agents/factory/templates/GOAL.md`
- **What happened:** the seed carried `appetite: medium`, which `templates/ISSUE.md:4` explicitly
  permits (`small | medium | big`), but `templates/GOAL.md:10` and `uvm-feature`'s Argument Parsing
  both admit only `small | big`. No rule anywhere says how a `medium` seed becomes a GOAL appetite, so
  promotion stalled on a question the human had to answer.
- **Skill cause:** the two templates disagree on the vocabulary of the same field across the exact
  handoff `/uvm-feature` performs. This is not a one-off: three of the six queued seeds
  (`doctor-detection-gaps`, `lock-ownership-and-hold-time`, `uvm-bootstrap`) carry `medium`, so every
  one of those promotions hits it, and each is free to translate differently — which makes
  `uvm-review`'s scope check against appetite mean different things on different cycles.
- **Recommended fix:** pick one vocabulary and make both templates say it. Either add `medium` to
  `templates/GOAL.md:10` and to `uvm-feature`'s Argument Parsing with a phase-cap meaning stated in
  `methodology.md` § *Appetite*, or drop it from `templates/ISSUE.md:4` and have `/uvm-feature` Step 2
  round a `medium` seed to `big`, saying so.
- **Confidence:** high · **Effort:** small
