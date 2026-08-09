# META — {Title}

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

- **slug:** {slug}

## What worked well

Brief, optional reinforcement: a part of a skill or the harness that materially helped, so
`/uvm-harness` knows what **not** to change. One line each, naming the skill and step. Skip the
section entirely if nothing stands out.

- <what helped, and in which skill/step>

## Friction findings

Zero or more findings, appended below — each a markdown **section**, so appending is a low-corruption
operation and a stdlib parser can read them
(`uv run .agents/factory/bin/meta_status.py spec/{slug}/META.md`). Skills always write `status=open`;
only `/uvm-harness` flips it. `target` is a best-guess file with **no line number** — re-derive the
exact edit at apply time to avoid staleness — written repo-relative and always spelled `.agents/…`,
never through the `.claude` symlink, so `/uvm-harness --all` sees one file as one file. If an
equivalent finding already exists, append
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
