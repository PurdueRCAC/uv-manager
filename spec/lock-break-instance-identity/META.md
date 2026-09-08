# META — A losing breaker deletes the lock a third rank just won

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

- **slug:** lock-break-instance-identity

## What worked well

- `uvm-feature` Step 4's rule that a deferral naming another file is only a promise in that file is
  what produced three real seed edits here instead of three sentences in *Non-goals*. This promotion
  deferred four of the seed's six sketch criteria, and every one of them would have been deleted with
  the seed by `/uvm-roadmap`. The rule paid for itself in one run.

## Friction findings

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — Step 4's roadmap-rewrite rule covers the promoted seed and not the siblings a promotion edits
`origin=uvm-feature:4 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 4 specifies the adoption marker and says to "rewrite the entry body to the
  scope shaping settled" for *this* seed's `ROADMAP.md` entry. Landing the deferral obligations
  changed three sibling seeds — `invariant-audit-gaps` gained a fourth criterion, `test-harness`
  gained two, and `lock-owner-write-errno`'s sequencing premise was answered — and each has its own
  `ROADMAP.md` entry that went stale the moment the seed changed. `invariant-audit-gaps`'s entry
  heading read "Three small code gaps" against a seed now carrying four. Step 7 acknowledges sibling
  seeds exist (`git add issues/{other-slug}.md`) but nothing says their entries move too, so a run
  following the letter of Step 4 leaves the index false in exactly the places it just edited.
- **Skill cause:** The rule is written for the one-seed case. `ROADMAP.md`'s own contract is one entry
  per issue, so any edit to a seed's criteria or sequencing invalidates its entry — the promoted seed
  is not special, it is merely the one the skill was thinking about.
- **Recommended fix:** Extend Step 4's roadmap paragraph: any seed this promotion writes into gets its
  entry rewritten in the same commit, on the same terms, and Step 7's `git add issues/{other-slug}.md`
  line gains `ROADMAP.md` as its companion.
- **Confidence:** high · **Effort:** small

## F2 — Step 5's gate-rehearsal rule contradicts itself for a fix cycle
`origin=uvm-feature:5 severity=medium category=instruction status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 5 says to run every literal *Checked by* command against the current tree,
  then rules that "a clause that cannot pass, or that passes before the work is done, is not a
  criterion". For a `kind: fix` cycle both halves are backwards. Three of this contract's six gates
  **cannot** pass now — that is what makes them red states, and Step 4 two paragraphs earlier requires
  a fix's criteria be phrased as the broken→fixed behavior that produces exactly such a gate. One gate
  **must** pass now, because it pins unchanged behavior; `spec/lock-acquire-retake/GOAL.md` R6 is the
  same shape and shipped, annotated "green today and green after". I ran the commands and then had to
  decide the rule did not mean what it said.
- **Skill cause:** The sentence was written for a feature's forward-looking gates and applied to every
  criterion. Read literally by a run less willing to overrule it, it deletes the red states a fix cycle
  exists to establish, or the collateral gates that catch a remediation shipping damage instead of a
  repair — which is the failure `lock-acquire-retake` R4 was added to prevent.
- **Recommended fix:** Split the rule by what the criterion is for. A gate is defective when it passes
  *and* claims to show a defect, or fails *and* claims to pin existing behavior. State that a fix
  cycle's gates are expected red now and its unchanged-behavior gates green now, and require the
  observed status be written into the criterion either way, as this GOAL does.
- **Confidence:** high · **Effort:** small
