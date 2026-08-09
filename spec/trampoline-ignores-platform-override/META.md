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
- `uvm-plan` Step 3's **high-blast-radius exception** earned itself here. `appetite: small` and
  `kind: fix` both said "skip the fan-out" for what is a one-line change; the exception overrode them
  because `uvm_trampolines` is on the list. The research is what found the five stale documentation
  sites that refute `GOAL.md` Q3, and a lean plan would have shipped against a wrong assumption.
- `uvm-plan` Step 3's sequential fallback for an unavailable fan-out is stated plainly enough to follow
  without improvisation, and the deliverable really is the same four briefs.

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

## F2 — Gates are red-tested but never green-tested, and the safe way to green is undocumented
`origin=uvm-plan:6 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** Step 6 requires running every `verify:` against the current tree and confirming
  it exits non-zero, which catches an *inert* gate. It says nothing about confirming the gate turns
  green once the change exists, which is the other half — a gate can be red because the command is
  broken (a typo, a missing flag, a tool absent), and that gate stays red through the build, burning
  the `--record-attempt` counter toward the circuit breaker at 3 while the code is actually correct.
  I proved green by copying the repo to `/tmp`, applying the one-line change to the copy, and running
  the gate against the copy's `temp_root.sh`. Devising that took real thought, because Step 6 sits
  under a Safety Principle reading "Never build. No edits to `bin/uv-manager`."
- **Skill cause:** The instructions specify one direction of the test and leave the complementary one
  unstated, while a prominently-placed prohibition makes the obvious way to perform it look
  forbidden. Nothing tells the planner that a throwaway copy outside the working tree is the
  sanctioned route, so each run either re-derives it or skips the check.
- **Recommended fix:** Extend Step 6: after confirming red, confirm green by applying the change to a
  scratch copy of the repository (`cp -R . /tmp/<slug>-probe`) and running the gate there. Add a
  clause to the "Never build" principle noting that a throwaway copy outside the working tree is not
  a build and is the intended way to prove a gate is not merely red.
- **Confidence:** high · **Effort:** small

## F3 — Nothing warns that `verify:` strings are YAML scalars, where `\n` is not a shell escape
`origin=uvm-plan:6 severity=medium category=template status=open target=.agents/factory/templates/TECH.md`
- **What happened:** My first draft of P1's gate built its fixture with
  `printf "#!/bin/sh\necho OVERRIDE\n"`. In a YAML **double-quoted** scalar — the style the `TECH.md`
  template demonstrates, because deferring `$` expansion into `sh -c '…'` requires it — `\n` is a YAML
  escape and becomes a real newline, splitting the command before the parser or the shell ever
  complains. I restructured the whole gate to contain no backslash except the `\"` escapes. The
  template's example happens to have no `\n` in it, so the trap is invisible to anyone copying it.
- **Skill cause:** Template and skill both treat `verify:` as "a shell command" when it is a shell
  command *inside a YAML scalar*, with a second escaping layer whose rules differ. The `verify` field
  reference in the template covers post-conditions and sandboxing and says nothing about quoting
  style. A corrupted gate here fails in a way that reads as a broken phase, not a broken plan.
- **Recommended fix:** Add a line to the template's `verify` field reference: the value is a YAML
  scalar, so in double-quoted style `\n`, `\t` and `\\` are YAML escapes, not shell ones — keep the
  command free of backslashes apart from `\"`, or use a block scalar. This also belongs in
  `.agents/factory/review-rubric.md` § *Verification traps*, alongside the `zsh` pathspec and
  `grep`-is-not-`grep` entries, since it is the same class of silent false result.
- **Confidence:** high · **Effort:** small

## F4 — Nothing tells the orchestrator when to escalate to `debate`
`origin=uvm-review:step2 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** the diffstat put the change inside `uvm_trampolines` and against §1 — the two
  things `review-rubric.md` § *Optional debate variant* names as the trigger for two independent
  reviewers — but `SKILL.md` § *Argument Parsing* makes `debate` purely opt-in. The two documents
  point different ways and the skill states no rule, so the escalation decision fell to the
  orchestrator's judgement with nothing to ground it.
- **Skill cause:** the rubric describes when debate is warranted; the skill never tells the
  orchestrator to detect that condition. A user typing `/uvm-review` on the highest-risk diff in the
  repository gets the same single pass as one on a typo fix, and never learns the option existed.
- **Recommended fix:** in Step 1, after resolving the diff, check whether it touches a
  high-blast-radius region or §1/§2/§6; if so, surface the recommendation and let the human choose.
  Not automatic — the rubric is right that it costs twice as much, and that is the human's call — but
  the choice should be offered rather than silently skipped.
- **Confidence:** high · **Effort:** small
