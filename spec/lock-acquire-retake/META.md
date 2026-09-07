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

## F2 — two Step 3 rules both claim authority over the fan-out, with no stated precedence
`origin=uvm-plan:step-3 severity=medium category=instruction status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** Step 3's *high blast radius* exception mandates the full fan-out "regardless of
  appetite" for any change to `uvm_acquire_lock`. This GOAL's Clarifications resolve the opposite in
  as many words: appetite stays `small` and the collateral risk is "answered by R4 being a graded
  criterion rather than by a research fan-out". Both are binding and neither yields. Resolved by
  running a deliberately narrow three-topic fan-out, which served the work, but the choice was mine
  rather than the skill's.
- **Skill cause:** the *diagnostic* exception ends with an explicit tie-break — "when they disagree
  with the GOAL, the GOAL wins" — and the high-blast-radius exception, written immediately after it,
  has none. The omission reads as deliberate on one reading and as an oversight on the other.
- **Recommended fix:** give the high-blast-radius exception its own tie-break sentence. It should
  *not* simply defer to the GOAL — the exception exists precisely because a human may under-scope an
  edit in this region. Stating that a GOAL may narrow the fan-out's breadth but not eliminate it
  would have named what this cycle actually did.
- **Confidence:** high · **Effort:** small

## F3 — "a gate that exits 0 today is inert" has no case for a collateral criterion
`origin=uvm-plan:step-6 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** Step 6 requires every `verify:` to be run against the current tree and treats
  exit 0 there as evidence the gate is inert. R4 and R6 here are *collateral* criteria — they demand
  that behavior not change, so their drives are green before and after by construction. Following the
  rule literally would have meant discarding or contorting four correct regression gates. `P2` keeps
  them and carries a red post-condition of its own (the measurements record) so the phase still has
  one, but the skill gave no guidance for that shape.
- **Skill cause:** the rule is written for gates that assert something the phase will deliver, and a
  regression gate asserts something the phase must not destroy. Both are legitimate `verify:`
  content; only the first is described.
- **Recommended fix:** name the second shape and say what it owes — a regression gate may be green
  today, but the phase carrying it must also assert at least one post-condition that is red today, so
  the phase as a whole is still falsifiable.
- **Confidence:** high · **Effort:** small

**What worked well:** the rule that a non-goal deferring work by naming another file is only real in
that file. Following it turned up that `issues/test-harness.md` R3d does not cover this cycle's
defect — its stated premise is that every defect in this area needs two processes racing, which this
cycle's single-process gate is the counterexample to. Without that step the non-goal would have
pointed at an obligation that did not exist.

**What worked well:** Step 6's instruction to copy the repository outside the working tree and
prove a gate can go green. Applied to the whole design rather than one gate, it turned the plan's
central question — whether `[[ -d ]]` can tell a lost race from a filesystem fault — from an argument
into six measurements before a line of the real diff was written.
