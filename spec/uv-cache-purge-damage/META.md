# META — A purge that damages uv's cache is repaired under `UVM_REPAIR`

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/uv-cache-purge-damage/`.
>
> **Silence is the default.** The bar for a finding is one test: *was this the **skill's** fault — not
> mine, not the task's?* A merely hard task, a self-inflicted error, or a one-off code issue that
> belongs in `GOAL.md` or `REVIEW.md` is **not** a finding. The blind `uvm-review` correctness reviewer
> never reads this file; it would leak author intent.

- **slug:** uv-cache-purge-damage

## Friction findings

Zero or more findings, appended below — each a markdown **section**, so appending is a low-corruption
operation and a stdlib parser can read them
(`uv run .agents/factory/bin/meta_status.py spec/uv-cache-purge-damage/META.md`). Skills always write `status=open`;
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

## F1 — A seed whose first criterion is a measurement has nowhere to put shaping-time evidence
`origin=uvm-feature:step4 severity=low category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** The seed's R1 required constructing the failure before any repair criterion was
  shaped. The skill says shaping does no research and produces exactly one artifact, so a 30-row
  damage matrix and its remedies went into `GOAL.md` § *Problem*, which the reviewer then grades
  against.
- **Skill cause:** "Shaping only, no research" and "one artifact" do not say what to do when a
  seed's first criterion is itself a measurement that gates the rest of shaping.
- **Recommended fix:** Name the case in Step 4. Either allow `spec/{slug}/research/00-shaping.md`,
  with § *Problem* citing it, or state that § *Problem* holds such evidence and cap its length.
- **Confidence:** med · **Effort:** small

## F2 — `run_verify.py` leaks its own `VIRTUAL_ENV` into the gate, and `temp_root.sh` keeps it
`origin=uvm-build:P1 severity=high category=tooling status=open target=.agents/factory/bin/temp_root.sh`
- **What happened:** Step 4 says to run a new gate through `uv run .agents/factory/bin/run_verify.py`
  to see it red. `uv run` exports `VIRTUAL_ENV` (and puts that environment's `bin/` on `PATH`) for
  the script's ephemeral environment, a Python other than the gate's 3.12. `temp_root.sh` scrubs
  `UV_*` and `UVM_*` but not `VIRTUAL_ENV`, so uv inside the sandbox built the gate's script
  environment on the developer's interpreter, and `p1.sh` went red at its setup (`no script entry
  to damage`) instead of at its first assertion. The same string under `/bin/sh -c` outside `uv
  run` went red where PLAN §6 says (`R2: module on script: doctor exits 0`), and green after.
- **Skill cause:** the runner the skill mandates for the red check changes the environment the gate
  runs in, and the sandbox does not undo it. A red for the wrong reason satisfies "seen red" while
  proving nothing, the failure the runner exists to prevent.
- **Recommended fix:** unset `VIRTUAL_ENV` (and `CONDA_PREFIX`, `PYTHONHOME`, `PYTHONPATH`) in
  `temp_root.sh`'s scrub, and have `run_verify.py` exec the gate with `VIRTUAL_ENV` removed and its
  own environment's `bin/` dropped from `PATH`. Until then, Step 4 can say to run
  `/bin/sh -c "$(uv run … --print)"`.
- **Confidence:** high · **Effort:** small

## F3 — `temp_root.sh` keeps `SLURM_*`, so a gate inside an allocation keys the scope on the job
`origin=uvm-build:P4 severity=medium category=tooling status=open target=.agents/factory/bin/temp_root.sh`
- **What happened:** the foreman ran the gates inside a Slurm allocation, and P2's healthy-scope
  clause failed: with `SLURM_JOB_ID` set, the repair keys its scope on the job id, not on the
  `UVM_REPAIR` value, so the clause's `.repair/value-h1.ok` was never written.
- **Skill cause:** the sandbox scrubs `UV_*`, `UVM_*` and the scratch variables but not `SLURM_*`,
  and neither the gate notes nor the skill say the gates assume a shell outside an allocation.
- **Recommended fix:** unset `SLURM_*` in `temp_root.sh`'s scrub, or document that the gates run
  outside an allocation.
- **Confidence:** high · **Effort:** small
