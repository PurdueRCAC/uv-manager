# META — An installed tool run by its own name gets the repair `uvx` gets

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/installed-tool-parity/`.
>
> **Silence is the default.** The bar for a finding is one test: *was this the **skill's** fault — not
> mine, not the task's?* A merely hard task, a self-inflicted error, or a one-off code issue that
> belongs in `GOAL.md` or `REVIEW.md` is **not** a finding. The blind `uvm-review` correctness reviewer
> never reads this file; it would leak author intent.

- **slug:** installed-tool-parity

## Friction findings

Zero or more findings, appended below — each a markdown **section**, so appending is a low-corruption
operation and a stdlib parser can read them
(`uv run .agents/factory/bin/meta_status.py spec/installed-tool-parity/META.md`). Skills always write `status=open`;
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

## F1 — `/uvm-feature` has no notion of a release integration branch
`origin=uvm-feature:1 severity=low category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** this release integrates its cycles on `release/0.8.0`, `main` plus one harness
  commit. Step 1 STOPs off `main`, Step 3 branches from `main`, and the landed-cycle checks read
  `main`; the foreman had to issue a base-branch ruling naming which of the three to reread.
- **Skill cause:** the skill assumes every cycle starts from `main`, and has no input for the branch
  a release integrates on, though `AGENTS.md` lands work on `main` by squash and a release batches it.
- **Recommended fix:** accept an optional base (`base release/X.Y.Z`), check cleanliness and branch
  from it, keep the landed checks on `main`, and record the base in the GOAL header.
- **Confidence:** med · **Effort:** small

## F2 — an `unshaped` seed whose contract waits on a measurement has no route through shaping
`origin=uvm-feature:4 severity=low category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** the seed made its R1 a real-uv measurement "before any other criterion is
  firmed up", while the skill says shaping does no research. A cheap drive, run on the foreman's
  instruction, settled the VCS pin form and the `uvx` forms and found that a replay pins the
  receipt against `uv tool upgrade`, which changed three recommendations in the GOAL.
- **Skill cause:** "Shaping only" has no exception for a bounded measurement that decides the
  contract itself, so without an instruction from outside the skill the GOAL would have carried
  those as open questions into `/uvm-plan`.
- **Recommended fix:** allow one bounded `temp_root.sh` drive in Step 4 when a seed names a
  measurement as its gating criterion, with the results recorded as Clarifications and the command
  in the GOAL, and keep the no-fan-out rule for everything else.
- **Confidence:** med · **Effort:** small

## F3 — Step 6's `cp -R .` probe shares the worktree's git index
`origin=uvm-plan:6 severity=medium category=instruction status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** the plan runs in a linked worktree under `.agents/worktrees/`, whose `.git` is
  a file pointing at the shared git directory. `cp -R . "$(mktemp -d)/probe"` copies that file, so
  every `git grep` and `git show` a gate runs inside the probe reads the real worktree's index, and
  a `git add` there would write it. The probe was built instead with `git archive HEAD | tar -x`,
  `git init` and a local `release/0.8.0` branch for the gates that read it.
- **Skill cause:** Step 6 prescribes the copy command verbatim and the factory runs cycles in
  worktrees, but the step does not say that a copied `.git` file is still the original repository.
- **Recommended fix:** prescribe `git archive HEAD | tar -x -C "$probe"` plus `git init` and a
  commit in the probe (and any base branch a gate reads), or say to delete the copied `.git` first.
- **Confidence:** high · **Effort:** small

## F4 — no guidance for a gate too long for a YAML scalar
`origin=uvm-plan:6 severity=low category=template target=.agents/factory/templates/TECH.md status=open`
- **What happened:** P3's gate is a real-uv drive of about 150 lines (four shapes, ranks, the R8
  tree). The template says anything longer than one command is a literal block scalar; inline, the
  drive would be unreadable in review and its failure line numbers meaningless. The plan committed
  the gates as scripts under `spec/installed-tool-parity/gates/` with one-line `verify:` values and
  recorded that as a deviation.
- **Skill cause:** the template covers one-liners and multi-line blocks and has no rule for when a
  gate becomes a file, or where such a file lives.
- **Recommended fix:** allow `verify: "sh spec/{slug}/gates/pN.sh"` past a stated size, with shared
  helpers in a sourced `lib.sh`, and keep the post-condition rule unchanged.
- **Confidence:** med · **Effort:** small

## F5 — `/uvm-build` has no state for a phase waiting on an external run
`origin=uvm-build:4 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** P5's gate is red by design until a cluster job's summary is committed. Step 4
  says a gate that stays red is a STOP with `--record-attempt`, and Step 5 advances only on green;
  the skill says nothing of a phase split around a wait. The exception (commit Run A with the phase
  `in_progress`, do not record an attempt for the evidence line, hand back the job bodies) lived
  only in this cycle's TECH § P5 and in the foreman's brief.
- **Skill cause:** the skill's red/green model has no third outcome for a gate whose remaining red
  is an external input, though the factory runs cross-node drives every cycle that touches locks.
- **Recommended fix:** a Step 4 paragraph: a phase whose TECH body declares an external wait is
  built in two runs; Run A must show every check above the named evidence line green, commits with
  the phase `in_progress` and no attempt recorded, and hands back; Run B copies the evidence
  unedited and closes. Name the evidence line the gate must stop at, so any other red still counts.
- **Confidence:** high · **Effort:** small
