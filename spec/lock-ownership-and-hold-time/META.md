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

## F4 — `invariants.md` was written from `AGENTS.md` prose, not from the functions it constrains
`origin=uvm-plan:step-5 severity=medium category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** an audit of all twelve sections against `bin/uv-manager` — ~126 claims, four
  sections, seven findings filed, three refuted by an adversarial pass — found **four** assertions
  measured false of the code. Three of them (§6, §9, §11, recorded below) are the same failure mode:
  a qualifier dropped or invented while compressing `AGENTS.md` prose into a checklist bullet. The
  fourth (§5) turned out to be a code defect and was taken into this cycle as R7. All four date from
  the file's creation commit `33a91fb`, so this is origin error, not drift.
- **Skill cause:** `invariants.md` is graded against as **auto-CRITICAL**, and nothing in the factory
  ever required its assertions to be checked against the code they constrain. It was derived from
  prose that is itself a summary, one step further from ground truth at each hop. `AGENTS.md` says
  "when something below disagrees with the code, the code is ground truth" — but that rule is written
  for the human reading it, and no step executes it. The consequence is not hypothetical: a reviewer
  following §11 would fail a correct parser, and §6 would have a reviewer demand pre-warm text on a
  path where it is deliberately absent.
- **Recommended fix:** two things. Repair the three bullets (F5–F7). And add a standing rule to this
  file's header, which is a *strengthening* and so needs no typed override: before raising an
  auto-CRITICAL for a §1–§11 violation, confirm the invariant is true of `main` in the neighbourhood
  being graded; a claim that does not hold on `main` is a finding against **this file**, logged in
  `META.md`, not against the diff. A bullet added or edited here names the function it constrains and
  is checked against that function, not against `AGENTS.md`'s prose. Explicitly **not** recommended: a
  recurring audit or a `lint.sh` check — one adversarial sweep found these and the claims are
  semantic, so a schedule would buy ceremony `AGENTS.md` already prices.
- **Confidence:** high · **Effort:** small

## F5 — §6 generalizes one failure path's message to "any failure"
`origin=uvm-plan:step-5 severity=low category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** §6's last bullet reads "On any failure, remove the staging directory, release the
  lock, and die with the pre-warm instructions." Measured: the installer-pipeline guard
  (`bin/uv-manager:341-349`) carries the pre-warm text; the version read-back guard (`:351-355`)
  deliberately does not, because pre-warming would send the user to repeat the same download; and the
  rename at `:361` is guarded by nothing and dies under `set -e` leaving a `.incoming.` directory. So
  both halves of the sentence are false as written. No `AGENTS.md` counterpart, so this is a
  single-file edit.
- **Skill cause:** as F4. The bullet describes the first failure path it encountered and quantifies it
  over all three.
- **Recommended fix:** replace with a bullet that names the per-path advice — no egress gets pre-warm,
  a binary that will not run gets the wrong-architecture message — and states plainly that the rename
  is unguarded. The unguarded rename itself is code work, seeded in `issues/invariant-audit-gaps.md`.
- **Confidence:** high · **Effort:** small

## F6 — §9 drops the qualifiers on the trampoline overwrite guard
`origin=uvm-plan:step-5 severity=medium category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** §9 says "Only marked files are ever overwritten or removed." Removal is
  marker-only; overwriting is not. The guard at `bin/uv-manager:491-496` is a three-way conjunction,
  so an unmarked file failing `-s` **or** `-x` is written over — a planted 0644 non-empty user file was
  replaced with no note. The sentence is duplicated verbatim at `AGENTS.md:170`, so the repair is a
  two-file lockstep edit.
- **Skill cause:** as F4 — the compression dropped "non-empty and executable", which is exactly the
  part that makes the claim false.
- **Recommended fix:** state that removal is marker-only while overwriting is refused only for a file
  that is all three, and say why the `-s` term exists (a trampoline truncated by a purge is 0 bytes
  and unmarked, and the bullet above requires it be repaired). The `-x` term is a genuine safety gap
  against the property `AGENTS.md` states; that is code work, seeded.
- **Confidence:** high · **Effort:** small

## F7 — §11's rationale is disproved by `uv`'s actual CLI
`origin=uvm-plan:step-5 severity=medium category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** §11 asserts the five entries in `uvm_global_takes_value` are complete and that
  "everything else that looks like one is a per-command option and can only appear after the
  subcommand". Measured against `uv 0.12.4`: `uv --cache-dir DIR tool dir` and
  `uv --python-preference only-managed tool dir` both succeed, so two more options are accepted before
  the subcommand and take a value. The enumeration is right about the five under `uv --help`'s *Global
  options* heading; the reasoning attached to it is wrong, and `bin/uv-manager:533-538` names
  `--cache-dir` as an example of the category it disproves. Duplicated in `AGENTS.md:181-183`.
- **Skill cause:** as F4, with an aggravating factor — this bullet asserts a fact about a *third-party
  CLI* that nobody ran. It also argues against lengthening the list ("not more careful, more surface
  to drift"), which reads as a standing reason not to check.
- **Recommended fix:** restate as the set of options `uv` accepts before the subcommand that take a
  separate value, name the two known-missing entries as a gap, and keep the real point — the list is
  not a `uv` CLI model, it is the set that would otherwise be mis-skipped. The banner in the script
  rides with the code fix, which is seeded.
- **Confidence:** high · **Effort:** small

## F8 — `/uvm-plan`'s invariant gate is not cross-checked against its own phase checklists
`origin=uvm-build:P3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** P3's checklist said to derive `lock_beat=$(( lock_stale / 10 ))` "beside the
  existing knobs" — at load time. Measured on bash 3.2.57, `UVM_LOCK_STALE=abc` makes that arithmetic
  fatal under `set -u`, so at load it kills `uvm help` and `uvm --version`. `PLAN.md` §3 rules that
  out in its own words two sections earlier: "the R3 guard sits inside `uvm_acquire_lock`, so `help`
  and `--version` still answer on an unconfigured or misconfigured node. Load-time placement was
  rejected for exactly this reason." The plan contradicted itself and nothing caught it before build.
- **Skill cause:** `/uvm-plan` writes the § *Invariant gate* and the phase checklists as separate
  passes, and nothing asks whether the checklists actually obey the gate the same document just
  asserted. The gate reads as a compliance statement about the design rather than a constraint the
  roadmap is checked against.
- **Recommended fix:** after drafting the phases, re-read § *Invariant gate* against each checklist
  item and record any item that lands on the wrong side of one. A single "which phase would violate
  this?" pass per gate bullet would have caught it.
- **Confidence:** high · **Effort:** small
