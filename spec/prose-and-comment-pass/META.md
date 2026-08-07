# META — Prose pass over every comment and user-facing document

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

- **slug:** prose-and-comment-pass

## What worked well

- `uvm-feature` Step 4's split of `status: unshaped` from `status: shaped` was the right cut. The seed
  carried an internal contradiction — its *Outcome* said "every document in the repository," its
  criteria sketch named four files — and the instruction to treat draft R-IDs as input rather than as
  the contract is what surfaced that as a question for the human instead of a silent guess.

## Friction findings

Zero or more findings, appended below — each a markdown **section**, so appending is a low-corruption
operation and a stdlib parser can read them
(`uv run .agents/factory/bin/meta_status.py spec/{slug}/META.md`). Skills always write `status=open`;
only `/uvm-harness` flips it. `target` is a best-guess file with **no line number** — re-derive the
exact edit at apply time to avoid staleness. If an equivalent finding already exists, append
"· seen again" to its title instead of duplicating: recurrence is signal, not bloat.

Field enums — `severity`: `high` (a safety, gate, or correctness gap) `| medium | low`; `category`:
`instruction | steering | tooling | template | missing-guidance`; `status`: `open` (written by skills)
`| applied | rejected | deferred` (written by `/uvm-harness`).

Schema — copy one block per finding, appending it **after** this fence. The fence is illustrative and
is skipped by the parser:

```markdown
## F1 — <one-line title of the skillset problem>
`origin=<skill>:<step> severity=<high|medium|low> category=<instruction|steering|tooling|template|missing-guidance> status=open target=<best-guess file>`
- **What happened:** <what the skill made you do, or fail to do>.
- **Skill cause:** <why this is the instructions' fault — not yours, not the task's>.
- **Recommended fix:** <the concrete change to the skill, template, or script>.
- **Confidence:** <high|med|low> · **Effort:** <small|medium|large>
```

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — Step 7 stages a `ROADMAP.md` edit that Step 4 never asks for
`origin=uvm-feature:step-4 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 4 specifies the promotion edit precisely for one file — "leave the `issues/`
  file in place and set its `status:` to `adopted:{slug}`" — and says nothing about `ROADMAP.md`. Step 7
  then stages `ROADMAP.md` in the same `git add`. Following the two steps literally commits an
  unmodified file. I recovered the real convention (append
  `· **adopted** as [spec/{slug}/](…)` to the **Seed:** line, and rewrite the entry body to reflect
  what shaping settled) only by reading the prior cycle's shaping commit, `640e2f8`.
- **Skill cause:** the instruction is in the wrong step. Step 7 is the mechanical commit recipe and
  carries the only mention of the file; the step that describes the promotion never names it. A skill
  should not depend on git archaeology to recover a convention it stages a file for — and the next
  cycle to promote a seed is the first one where no prior example is a single `git log` away, since
  `/uvm-roadmap` deletes retired entries.
- **Recommended fix:** move the `ROADMAP.md` edit into Step 4 beside the `issues/` status flip, stating
  both halves: the `**adopted** as` marker on the **Seed:** line, and that the entry body is updated to
  the scope shaping actually settled rather than left describing open questions.
- **Confidence:** high · **Effort:** small

## F2 — the GOAL template's non-drive-verifiable exceptions are a closed set of two, and prose quality is a third
`origin=uvm-feature:step-4 severity=low category=template status=open target=.agents/factory/templates/GOAL.md`
- **What happened:** the template names exactly two criteria that need not be observable from a
  `temp_root.sh` drive — one requiring a real cluster, and one "satisfied by the text of the repository"
  that "carries its own check inline (`git grep -n …`)". This cycle's R2 ("no comment paraphrases the
  statement it sits above") is satisfied by the text of the repository but admits no command at all; no
  grep detects a restatement. I wrote it as a declared departure from a rule the template states as
  closed, which is the same invented-convention move that `spec/uvm-env-prefix/META.md` F1 reported.
- **Skill cause:** F1's applied fix enumerated the cases known at the time instead of stating the
  underlying rule, so the enumeration went stale on the very next cycle. Prose and comment quality is
  not an exotic category here — `AGENTS.md` § *Prose and comments* makes it a standing concern, and the
  same-commit rule pulls documentation into most cycles.
- **Recommended fix:** replace the enumeration with the rule it was standing in for: every criterion
  declares how it is checked, and a criterion not checkable by a drive or a command says who grades it
  and against what. That covers cluster-only, `git grep`, and reviewer-judgment cases without needing a
  fourth revision the next time an unanticipated one appears.
- **Confidence:** med · **Effort:** small
