# META — lock-acquire-retake

Harness self-improvement notes for this cycle. Records only; `/uvm-harness` applies fixes.

## Friction findings

## F1 — the fix-criteria rule is absolute but its rationale is conditional
`origin=uvm-feature:step-4 severity=low category=instruction status=open target=.claude/skills/uvm-feature/SKILL.md`
- **What happened:** Step 4 says for `kind: fix`, phrase criteria as observable broken→fixed behavior
  "never the suspected cause or mechanism, which is unverified until `/uvm-plan` root-causes it."
  This cycle was promoted from a *completed* review that had already root-caused the defect with a
  matched A/B and shipped it in a release, so the mechanism is contract-grade evidence rather than a
  suspicion. R1 names it anyway, because a criterion phrased purely as "a rank sometimes dies" cannot
  be turned into the deterministic gate the seed already carries — the gate *is* the mechanism.
- **Skill cause:** the prohibition is written absolutely while the reason given for it holds only
  when the cause is unverified. Promotion from a landed review cycle is the standing case where it
  does not, and the skill has a whole `shaped`/`unshaped` vocabulary for exactly that provenance
  without connecting it to this rule.
- **Recommended fix:** qualify it — mechanism stays out of a criterion *while it is a hypothesis*,
  and may be named once a landed cycle's `REVIEW.md` has measured it, which is also what makes a
  red gate constructible.
- **Confidence:** med · **Effort:** small

**What worked well:** the rule that a non-goal deferring work by naming another file is only real in
that file. Following it turned up that `issues/test-harness.md` R3d does not cover this cycle's
defect — its stated premise is that every defect in this area needs two processes racing, which this
cycle's single-process gate is the counterexample to. Without that step the non-goal would have
pointed at an obligation that did not exist.
