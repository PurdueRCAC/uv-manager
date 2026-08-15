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
- `uvm-plan` Step 6's requirement to run every `verify:` against the current tree and confirm it dies
  on the asserted post-condition caught **two** false greens in this cycle — a `sed` fixture mutation
  that silently matched nothing, and a `git grep` anchor that wraps across lines. Both would have
  shipped as green gates. This step earns its cost; do not soften it.

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

## F2 — `kind: fix` and `appetite: big` select opposite research paths
`origin=uvm-plan:step-3 severity=medium category=instruction status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** Step 3's first bullet skips the fan-out for "`appetite: small` / `kind: fix` /
  `skip research`" and its second runs the full fan-out for "`appetite: big`". This GOAL is `kind: fix`
  **and** `appetite: big`, so it matches both, and the two bullets prescribe opposite work. I resolved
  it by borrowing "when they disagree with the GOAL, the GOAL wins" — but that sentence sits inside the
  *diagnostic fixes* exception and is scoped to whether the root cause is known, which was not the
  question here.
- **Skill cause:** the two bullets are written as if `kind` and `appetite` could not conflict. They
  routinely can, and will again: `issues/lock-ownership-and-hold-time.md` is the next queued cycle and
  is also a `fix` whose appetite exceeds `small`.
- **Recommended fix:** make the first bullet's condition conjunctive (`appetite: small` **and** not
  overridden), or state a precedence line — appetite governs research depth, `kind` does not — and
  keep `kind: fix` only as a *default* for appetite rather than an independent trigger.
- **Confidence:** high · **Effort:** small

## F3 — the gate-hazard list omits the prose anchor that wraps across lines
`origin=uvm-plan:step-6 severity=low category=missing-guidance status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** the R7 gate asserted a `README.md` sentence was gone via
  `git grep -q 'found by walking each distribution'`. That phrase wraps across two lines in the file
  and `git grep` is line-based, so the gate reported the post-condition met while the sentence was
  still there — green, and inert. Caught only because Step 6 requires proving the gate red first.
- **Skill cause:** Step 6 enumerates gate hazards specifically so authors do not rediscover them, and
  names the `zsh` word-splitting case in detail. A multi-line-wrapping prose anchor is the same class —
  a gate that searches something the file does not literally contain — and is more likely in this
  repository than the documented one, because `README.md` and `AGENTS.md` are hard-wrapped at 100
  columns and documentation sweeps are a recurring phase type here.
- **Recommended fix:** add one sentence to Step 6's hazard paragraph: an anchor for a documentation
  gate must be a substring of a single line, and hard-wrapped prose usually is not — verify the anchor
  matches before relying on its absence.
- **Confidence:** high · **Effort:** small

## F4 — a gate may cover half a criterion and still read as full coverage
`origin=uvm-build:P1 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** R5's *Checked by* clause names two checks — the finding set must equal the one
  `git show main:bin/uv-manager` produces on the same tree, and the walk must be measurably faster.
  The authored P1 gate asserted neither. It asserted one case the rewrite could regress — a `RECORD`
  with no trailing newline — which is worth having but is not the equality claim, and it went green
  with that claim unverified. I built the comparison by hand and retuned the gate to encode the three
  verdicts `main` produces on the awkward shapes.
- **Skill cause:** `uvm-plan` Step 6 requires a gate be proven red before the fix, which certifies
  that the gate *works*, not that it covers what the criterion says it checks. Nothing asks the
  author to reconcile the gate against the R-ID's own *Checked by* clause, or — where a check cannot
  be mechanized — to say in the phase body who grades the remainder. P4's body does exactly that
  delegation voluntarily, so the practice already exists in this cycle and is simply not a rule.
  Red-first also mis-tests a gate that mixes classes: an assertion protecting *preserved* behavior
  must be **green** before the fix, and calling the whole gate "red before" hides that half.
- **Recommended fix:** in Step 6, require each phase to account for every R-ID it `satisfies` — the
  gate encodes the criterion's *Checked by* clause, or the phase body names the reviewer as grader
  for the part it cannot. Add the corollary that a gate mixing new-behavior and regression
  assertions is proven by running both halves against the pre-fix tree and confirming the split.
- **Confidence:** high · **Effort:** small
