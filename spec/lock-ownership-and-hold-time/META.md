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
- Step 6's instruction to read each `verify:` back against its phase's own checklist caught a **blind**
  clause before it shipped: P3's stray-refresher check was written as `jobs -p`, which reports nothing
  whether or not a refresher leaked, because the refresher is a grandchild of the drive shell. The gate
  would have gone green on the one failure mode the phase can introduce. Testing it rather than reading
  it is what exposed that, which is Step 6's other instruction earning its place.

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

## F2 — a GOAL's *Checked by* clauses are written but never executed
`origin=uvm-plan:step-3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-feature/SKILL.md`
- **What happened:** two of this GOAL's six *Checked by* clauses were not executable as written. R6's
  `git grep -c flock bin/uv-manager` "returning 0" can never pass — `:172` names `flock` in the comment
  recording why the discipline is `mkdir`, so it returns `bin/uv-manager:1` and exits 0. R4's clause
  matched four `exec` sites while R4's prose named three, so the criterion and its own gate disagreed.
  Both were found in research and both needed a human decision to repair the contract.
- **Skill cause:** `/uvm-plan` Step 6 is emphatic that every `verify:` must be run before the plan is
  committed, and that a gate exiting 0 against an undelivered post-condition is inert. Nothing applies
  that discipline to the *GOAL's* clauses, which is where these commands are first written and where
  they are cheapest to test. The asymmetry is the defect: `/uvm-feature` writes commands and
  `/uvm-plan` is the first step required to run any. Had the fan-out not happened to include a
  verification-recipes topic, R6's clause would have been transcribed into a `verify:` that is
  permanently red, walking `--record-attempt` toward the circuit breaker at 3 while the code was
  correct — the exact failure Step 6 exists to prevent, arriving from upstream where Step 6 cannot see
  it.
- **Recommended fix:** a step in `/uvm-feature` before the shape commit: run every *Checked by* clause
  that is a literal command against the current tree and record what it returned. A clause that cannot
  pass, or that passes before the work is done, is not a criterion. This is Step 6's "red is necessary,
  not sufficient" applied one stage earlier, and it costs seconds.
- **Confidence:** high · **Effort:** small

## F3 — the `verify:` field reference documents the style that cannot express a real gate
`origin=uvm-plan:step-6 severity=low category=template status=open target=.agents/factory/templates/TECH.md`
- **What happened:** the field reference explains double-quoted scalar style at length — which
  characters are YAML escapes, how a `\n` splits the command where no shell sees it — and mentions a
  block scalar only as a trailing alternative. Every gate in this cycle is a multi-line heredoc drive
  under `temp_root.sh`, which double-quoted style cannot express at all. The previous cycle shows the
  cost: `spec/doctor-detection-gaps/TECH.md`'s gates round-tripped into folded single-quoted scalars
  whose shell lines are separated by blank lines to survive re-emission, and they are close to
  unreadable.
- **Skill cause:** the guidance optimizes for the single-line case and treats the multi-line case as
  the exception, when for this project — where a gate is a sandbox drive asserting a post-condition —
  multi-line is the norm. The warning it does give is real, but it is advice for a style that should
  rarely be chosen.
- **Recommended fix:** make the literal block scalar (`|`) the documented default for any `verify:`
  longer than one command, and keep the double-quoted escaping warning scoped to the one-liner case.
  Worth noting that `|` round-trips through `next_phase.py`'s PyYAML cleanly, heredocs included.
- **Confidence:** high · **Effort:** small
