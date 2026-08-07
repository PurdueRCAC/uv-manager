# META — Rename the `UV_MANAGER_*` environment prefix to `UVM_*`

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/{slug}/`.

- **slug:** uvm-env-prefix

## What worked well

- `uvm-feature` Step 4's `status: unshaped` branch. The seed had drafted an `R5` reading
  `<compatibility behavior, once the human has chosen>`, and the instruction to treat draft R-IDs as
  input rather than contract is what turned that placeholder into the single blocking question instead
  of a guess.
- `uvm-plan` Step 3's **high-blast-radius exception**, which overrode `appetite: small` and forced the
  research fan-out. It changed the outcome: a lean plan would have shipped a `UVM\?_` scrub patch that
  silently disables the whole sandbox scrub on macOS, and would have missed that `UV_LOCK_TIMEOUT`
  already exists upstream — the cycle's strongest justification. The exception earned its cost here.

## Friction findings

## F1 — GOAL template has no escape hatch for a criterion that is not drive-verifiable
`origin=uvm-feature:step-4 severity=low category=template status=applied target=.agents/factory/templates/GOAL.md`
- **What happened:** the template requires every criterion to be observable from a `temp_root.sh`
  drive, and offers exactly one exception — "if one genuinely requires a real cluster, say so in the
  criterion." A rename cycle's documentation criteria (R5, R7 here) are verifiable by `git grep` and by
  nothing else; neither the rule nor its exception covers them, so I invented an out-of-band annotation
  line under the criteria list.
- **Skill cause:** the template generalizes from behavioral cycles. Documentation sweeps are a standing
  category of work in this repository — the same-commit rule in `AGENTS.md` guarantees most cycles
  carry one — so the omission is in the guidance, not in the task.
- **Recommended fix:** extend the template's exception sentence to name the second case: a criterion
  verified by static inspection states its check inline (`git grep -n …`), the way a cluster-only
  criterion states its dependence. Costs one sentence and removes the invented convention.
- **Confidence:** high · **Effort:** small

## F2 — `uvm-plan` stamps `status: in_progress` before the sign-off gate it then enforces
`origin=uvm-plan:step-6 severity=low category=instruction status=applied target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** Step 6 says "Set top `status: in_progress`", so `TECH.md` claims building has
  begun at the moment the plan is written — while Step 9 stops and requires a human to review
  `PLAN.md` and `TECH.md` before `/uvm-build` runs. The FSM and the process disagree for the whole
  duration of the sign-off gate.
- **Skill cause:** `_fsm.py:48` accepts `planned` as a top status and nothing in the factory ever
  writes it. The value is unreachable because this instruction hard-codes the next one, so the
  enum's most accurate state for this moment is dead.
- **Recommended fix:** Step 6 sets `status: planned`; `/uvm-build` flips it to `in_progress` on its
  first phase, alongside the phase-status change it already makes.
- **Confidence:** high · **Effort:** small

## F3 — a phase's `verify:` contradicted a checklist item in the same phase
`origin=uvm-build:P3 severity=low category=missing-guidance status=applied target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** P3's gate is `! git grep -q UV_MANAGER_ -- README.md …`, and P3's own checklist
  says to add a design note whose approved draft (`research/04-docs-surface.md` §2) argues its point
  by naming `UV_MANAGER_*` literally. Executing the checklist turned the gate red. Resolved by
  rewording the note, since the contract outranks the draft, but the conflict was written into the
  plan and only surfaced at the gate.
- **Skill cause:** an eradication gate (`! git grep OLD`) is in standing tension with any prose the
  same cycle adds that has to *discuss* the old name — a rename's rationale usually does. Nothing in
  `uvm-plan` asks whether a phase's `verify:` can survive that phase's own checklist, and nothing
  asks whether a drafted passage would trip a gate written elsewhere in the same file.
- **Recommended fix:** in `uvm-plan`'s roadmap step, add one check — read each phase's `verify:`
  against its own checklist items and against any text the phase quotes from `research/`, and
  reconcile before writing. Cheapest at plan time; at build time it costs a red gate and a rewrite.
- **Confidence:** high · **Effort:** small

## F4 — the blindness rule covers reading files but not searching them
`origin=uvm-review:step-2 severity=high category=instruction status=applied target=.agents/skills/uvm-review/SKILL.md`
- **What happened:** the reviewer honored "do not read `PLAN.md`, `TECH.md`, `research/`, or
  `META.md`" and never opened one, but two recursive `grep -rn` sweeps returned matching *lines* from
  all four into its context. It disclosed this itself. The pass's blindness was partially eroded by an
  action the instructions did not cover.
- **Skill cause:** Step 2 spends a paragraph on the one leak it anticipated — the `':(exclude)spec/'`
  pathspec on the diff, flagged as "load-bearing, not cosmetic" — and then states the artifact ban in
  terms of *reading*. `grep -rn`, `rg`, and a `Glob`/`Explore` sweep all surface the same content
  without opening a file, and a reviewer inventorying occurrences of a renamed symbol will reach for
  exactly those. The gap is between the diff rule, which is precise about pathspecs, and the artifact
  rule, which is not.
- **Recommended fix:** state the ban in terms of *content reaching context*, not reading, and give the
  reviewer the exclusion to append to every repository-wide search
  (`-- . ':(exclude)spec/'` for `git grep`, `--glob '!spec/**'` for `rg`). One clause in the Step 2
  bullet and one line in `review-rubric.md` § *What the reviewer sees*.
- **Severity note:** `high` because the fix protects blind-review integrity, a non-negotiable gate —
  the pass has no other defense against plan-sycophancy.
- **Confidence:** high · **Effort:** small

## F5 — nothing checks that a phase's `verify:` can observe every item on its checklist
`origin=uvm-build:P4 severity=medium category=missing-guidance status=applied target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** P4's gate was `! git grep -q UV_MANAGER_ …`, which tests the *substitution* half
  of the phase. Two of its checklist items were about scope descriptions — `AGENTS.md:73`/`:203`, and
  the live seeds — which change with P1's behavior rather than by substitution. The gate could not
  observe them, went green with `issues/test-harness.md:21` still describing the old, narrower scrub,
  and `/uvm-review` caught it a cycle later.
- **Skill cause:** `uvm-plan` requires a `verify:` per phase and requires it to assert a post-condition,
  but never asks whether the gate's post-condition *covers the checklist*. A phase whose items are
  heterogeneous — some mechanical, some judgment — gets a gate shaped by the mechanical ones, because
  those are the ones that are easy to express as a command. This is the complement of F3: F3 is a gate
  that contradicts a checklist item, F5 is a gate that is blind to one.
- **Recommended fix:** in `uvm-plan`'s roadmap step, walk each checklist item against the phase's
  `verify:` and mark any the gate cannot observe. Either extend the gate or state in the phase body
  that the item is inspection-only, so `/uvm-review` knows to read it rather than trust the gate.
- **Confidence:** high · **Effort:** small

## F6 — `verify:` strings are authored in the agent's shell and executed in another
`origin=uvm-build:P4 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** while retuning P4's gate I tested a candidate clause interactively and it reported
  green on a tree where it should have been red. The agent shell's `grep` is a function wrapping
  `ugrep`; the clause behaved correctly under `/bin/sh` with `/usr/bin/grep`. Had I trusted the
  interactive result I would have committed a gate that passes unconditionally — the same class of
  defect the cycle-1 finding already was.
- **Skill cause:** Step 4 is emphatic that exit 0 is not a pass and the post-condition is the gate, but
  it treats the *shell* as neutral. A `verify:` string is authored in the agent's interactive
  environment and later executed by `next_phase.py` consumers, `lint.sh` and CI under plain `sh`, where
  aliases, shell functions and GNU-vs-BSD utility differences all diverge. `AGENTS.md` already treats
  that divergence as load-bearing for the wrapper (the `\?`-versus-`\{0,1\}` trap in P1 is the same
  bug); the build skill does not extend it to the gates.
- **Recommended fix:** one line in Step 4 — run a new or retuned `verify:` as `/bin/sh -c '…'`, and
  confirm it is **red before the fix and green after**. A gate never observed failing is not a gate.
- **Confidence:** high · **Effort:** small
