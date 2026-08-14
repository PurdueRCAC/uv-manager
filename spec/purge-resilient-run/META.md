# META — Repair a purged tree in place, at job scale

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/{slug}/`.

- **slug:** purge-resilient-run

## What worked well

- `uvm-feature:4`'s instruction to read the seed's `ROADMAP.md` entry alongside the issue paid off
  immediately: the entry is where "Taken first because both halves are live operational gaps" lives,
  which is what confirmed this promotion jumped no recorded ordering and turned the missing test
  harness into a clean non-goal rather than a violated dependency.
- `uvm-plan:3`'s research fan-out, and specifically the instruction to prefer driving the script over
  reading it, is what made this cycle's outcome possible. Three conclusions that would have shipped
  broken — a stamp file that leaves a purged tree unrepaired, a repair lock that produces two
  concurrent repairers on shipped defaults, and an acceptance oracle satisfiable with zero repair
  code — were each caught by running the thing, not by inspection. The adversarial pass over the
  briefs earned its cost: it overturned load-bearing claims in three of the six.
- `uvm-plan:6`'s rule to run every `verify:` against the current tree *and read the failure output*
  caught a gate of mine that was red for its own reasons: it asserted a `current` symlink target after
  `uvm status`, which is read-only and provisions nothing, so no arch tree existed to read. Left in, it
  would have stayed red through the whole build while the code was correct. The rule works; the
  half of it that earns its keep is "confirm it died on the asserted post-condition", not "confirm it
  is red".

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — Free text alongside an issue path is routed as scope, with no rule for the case where it is about a different seed

`origin=uvm-feature:argument-parsing severity=medium category=instruction status=open target=.agents/skills/uvm-feature/SKILL.md`

- **What happened:** the invocation was `issues/purge-resilient-run.md` plus a sentence about a
  `UVM_INSTALL` variable that the hosted `uvm.sh` would read. Argument Parsing resolves the path to a
  promotion and then says "Everything else → the inline feature description (the seed prompt)."
  Followed literally, that folds the sentence into the purge cycle's scope. It does not belong there:
  `uvm.sh` is `issues/uvm-bootstrap.md`, the *next* roadmap entry, and absorbing it would have merged
  two `appetite: big`/`medium` cycles behind a contract no human agreed to. I caught it only because
  the remark named `uvm.sh`, which I happened to recognize from the other seed.
- **Skill cause:** the parsing rules treat the path and the free text as independent, and the "seed
  prompt" fallback is written for the *no-path* flow. When a path is given, the skill never says what
  accompanying prose means — a scope addition, a shaping hint, an appetite override, or a note that
  belongs on a different file entirely — so the only stated rule is the one that produces the wrong
  answer. Nothing directs the skill to check the remark against the *other* open issues, even though
  Step 1's injected state already lists them.
- **Recommended fix:** in Argument Parsing, add a clause for path-plus-prose: the prose is shaping
  input for the named seed, **not** an automatic scope extension, and before using it check it against
  the other entries in the injected "Open issues" list. Where it belongs to a different seed, record it
  in that seed's `## Notes` (with attribution and date) and commit it alongside the GOAL, listing the
  separation as a non-goal. Where it is genuinely ambiguous which cycle owns it, ask — merging two
  seeds is an appetite decision, not a parsing one.
- **Confidence:** high · **Effort:** small

## F2 — The same-commit list omits the two files that record the invariants, so revising one ships a self-contradicting repository

`origin=uvm-plan:2 severity=high category=missing-guidance status=open target=AGENTS.md`

- **What happened:** R1 reverses a decision asserted as an invariant in
  `.agents/factory/invariants.md:122-123` ("`mkdir -p` runs unconditionally rather than behind a
  sentinel"). The same-commit rule in `AGENTS.md`, and the four-file list recited by `uvm-plan`,
  `uvm-build` and `uvm-publish`, names the help heredoc, `README.md`, the conf example and the
  modulefile. None names `AGENTS.md` or `invariants.md`. A cycle that follows the skills faithfully
  therefore lands correct code that its own invariant file declares a violation of — and because
  `invariants.md` is what `uvm-review` grades against, the result is an **auto-CRITICAL §8 finding on
  correct code**, inside a high-blast-radius region (`uvm_export_env`), which forces a mandatory human
  sign-off gate. I found it only by fanning a research agent at the documentation surface; nothing in
  the procedure would have surfaced it.
- **Skill cause:** the same-commit rule enumerates user-facing surfaces and stops there, treating the
  invariant record as a thing that describes the code rather than a thing that gates it. `AGENTS.md`
  states that `invariants.md` is maintained in lockstep with it and that `AGENTS.md` wins, but no step
  in any skill ever checks the lockstep, and the gate that consumes it is not on the list of things a
  behavior change invalidates. Related drift found the same way: `invariants.md:122-123` has **no**
  counterpart in `AGENTS.md` at all, so it is a derived claim that already drifted in the direction
  the lockstep rule says loses.
- **Recommended fix:** extend the same-commit rule in `AGENTS.md` — and the recitation in the three
  skills — to: "a change that revises a load-bearing invariant updates `AGENTS.md` § *Invariants* and
  `.agents/factory/invariants.md` in the same commit." Add a line to `uvm-plan` Step 5 (invariant gate
  #2) making the deviation table's output explicit: a bend that is accepted becomes an edit to both
  files, not just a table row. Marked `severity=high` because it silently mis-fires a non-negotiable
  gate rather than merely omitting documentation.
- **Confidence:** high · **Effort:** small

## F3 — A GOAL found unbuildable at plan time has no route back to shaping

`origin=uvm-plan:5 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`

- **What happened:** research established that three of this GOAL's eight criteria cannot be built as
  written — R4's acceptance oracle is satisfiable with zero implementation, R3 promises detection no
  bounded check delivers, and R3 and R4 contradict each other on managed pythons. The human chose to
  narrow the cycle. `uvm-plan` may not edit `GOAL.md`, and `uvm-feature` refuses to run anywhere but
  `main` on a clean tree, so there is no defined transition: the branch holds committed research and a
  contract that must change, and every documented next step is closed. Step 1 already contemplates
  "STOP and send the human back to `/uvm-feature`" for unresolved clarification markers, which has the
  same dead end.
- **Skill cause:** the lifecycle is written as a one-way pipeline. Discovering that the contract is
  wrong is a *success* of the research step — buying down risk before code is the stated purpose — but
  it is the one outcome with no procedure. The absence bites hardest exactly when research worked.
- **Recommended fix:** give `uvm-plan` a "bounce to shaping" step: commit `research/` and the digest,
  leave `PLAN.md` and `TECH.md` unwritten, and state the two ways back — re-shape `GOAL.md` in place
  on the branch, or park the branch and re-promote from `main`. Correspondingly, let `uvm-feature`
  accept an existing feature branch whose only committed artifacts are `GOAL.md`, `META.md` and
  `research/`, treating it as a re-shape rather than a collision.
- **Confidence:** high · **Effort:** medium

## F4 — Gate-authoring guidance misses the `!` prefix, which silently disables an assertion under `set -e`

`origin=uvm-plan:6 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`

- **What happened:** I wrote a phase gate whose documentation assertion was `! git grep -q "..." -- bin/uv-manager`,
  inside a `set -eu` script. POSIX exempts a `!`-prefixed pipeline from `set -e`, so a failing
  assertion neither aborts the script nor affects its status: `sh -c 'set -e; ! true; echo REACHED'`
  prints `REACHED` and **exits 0**. The gate appeared red only because a later drive failed. Had the
  code landed and the comment not, that gate would have gone green with the phase item unmet. I found
  it by noticing the drive output printed at all, which it should not have if the earlier assertion had
  aborted — not by running the gate, which is what the step instructs.
- **Skill cause:** Step 6 is thorough about gates that are *inert because the post-condition already
  holds* and about YAML mangling, and it gives one worked example (a pathspec interpolated from a
  variable, word-split away under `zsh`). It says nothing about assertions that are inert because of
  shell semantics, and its prescribed check — run the gate, confirm it is red — cannot detect this
  class, because a multi-clause gate is red for whatever clause does work. The failure is strictly
  worse than the one the step does cover: an inert `!` assertion goes green when the work is skipped.
- **Recommended fix:** add to Step 6, beside the literal-pathspec rule: never write a gate assertion as
  `! cmd`; use `if cmd; then echo "FAIL: …" >&2; exit 1; fi`, which also names the failure. Extend the
  "read the failure output" instruction to "confirm the gate failed on the *first* unmet clause" —
  output appearing from a later clause means an earlier assertion did not abort. Worth a line in
  `templates/TECH.md` too, where the `verify:` field reference lives.
- **Confidence:** high · **Effort:** small

## F5 — The injected "Current state" diffstat is silently truncated, and it dropped the two files carrying two R-IDs

`origin=uvm-review:state-injection severity=medium category=tooling status=open target=.agents/skills/uvm-review/SKILL.md`

- **What happened:** the diffstat injected at skill load listed 19 file rows but its own summary line
  read `21 files changed`. The two missing rows were `.agents/factory/invariants.md` and `AGENTS.md` —
  the alphabetically first two, so the truncation took the head, not the tail. Those are exactly the
  files R3 and R4 require to have been corrected. An orchestrator who curated the reviewer's inputs from
  the injected state would have handed over a diff description asserting that neither file moved, and a
  reviewer told the diff touches `README.md` and `bin/uv-manager` would grade R3 as two-thirds met and
  R4 as unmet. I caught it only because the circularity of grading against a possibly-edited
  `invariants.md` made me re-run the diffstat by hand.
- **Skill cause:** the injection emits a diffstat with no ellipsis marker and no statement that it may
  be elided, so it reads as complete. Nothing in Step 1 tells the orchestrator to re-derive the file
  list, and Step 2 builds the reviewer's prompt from whatever the orchestrator believes the diff
  contains. The failure is silent and points the wrong way — toward manufactured findings against
  correct work.
- **Recommended fix:** inject `git diff --name-only {base}...HEAD -- . ':(exclude)spec/'` alongside (or
  instead of) the stat, since the file list is what the pass actually needs and it cannot be truncated
  into looking complete. Failing that, add a line to Step 1: re-derive the changed-file list before
  curating the reviewer prompt, and reconcile it against the injected summary's count.
- **Confidence:** high · **Effort:** small

## F6 — The mandatory human gate keys on the *location* of a finding, not on whether it is behavioral

`origin=uvm-review:step-4 severity=high category=instruction status=open target=.agents/factory/review-rubric.md`

- **What happened:** the only two CONFIRMED findings this cycle are inaccurate numbers in prose. One of
  them cites `bin/uv-manager:403-404` because that is where the comment lives — inside `uvm_export_env`,
  a high-blast-radius region. Both Step 4 and the rubric's gate section are written purely in terms of
  what a finding *touches*, so a wrong figure in a comment fires the same mandatory
  stop-and-get-sign-off as a leaked lock would. I had to interrupt the human to clear a gate on a
  comment, in a cycle where two independent reviewers drove ~15 state configurations, a 40-way
  concurrency race and 3-level re-entrancy without producing one behavioral divergence.
- **Skill cause:** the gate's trigger is a region list and an invariant-section list, with no severity
  or nature qualifier. That is deliberate and mostly right — the point is that a human sees anything
  landing in the provisioning path — but the rubric also routes prose violations into scope as §12
  findings, which are by construction located wherever the prose is. The two rules compose into a gate
  that fires on typos. Nothing distinguishes "this finding is about code in the region" from "this
  finding is about a comment that happens to sit in the region".
- **Recommended fix:** qualify the trigger — a CONFIRMED finding fires the gate when it concerns the
  *behavior* of a high-blast-radius region, or any §1/§2/§6 invariant at any severity. A finding whose
  entire content is prose or documentation accuracy is reported at its severity and does not fire it.
  **Marked `severity=high` because this narrows a non-negotiable gate**, so it must not be applied
  without a human deciding it: the failure mode of getting it wrong is a behavioral defect in the
  provisioning path shipping without sign-off, which is strictly worse than the interruption it saves.
  The safe half can land alone — record in Step 4 that the gate may be cleared inline with the reasoning
  written into `REVIEW.md`, which is what happened here.
- **Confidence:** med · **Effort:** small

## F7 — Nothing checks a gate's pathspec against the quantifier of the requirement it gates

`origin=uvm-build:P2 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`

- **What happened:** R4 reads "SHALL be corrected **wherever it is stated**" and its gate was
  `! git grep -q "roughly 7 ms" -- AGENTS.md README.md`. Two literal paths against an unbounded
  quantifier. The gate went green while a live `7 ms` sat in `issues/uvm-bootstrap.md:86`, a seed that
  is *not* deleted on merge — and the same build edited that very file nine lines' worth, so it was not
  even out of sight. Both review reviewers found it independently; no gate could have. The
  cycle-2 retune is the repository-wide form with two literal exclusions, which is what the criterion
  meant from the start.
- **Skill cause:** `uvm-plan` Step 6's gate-authoring guidance is entirely about gates that are *inert*
  — the `!`-prefix trap (F4), the `zsh` pathspec collapse, post-conditions that already hold. All three
  are failures of the assertion. This is a failure of the assertion's *scope*: the command works
  perfectly and proves a strictly smaller claim than the criterion makes. Narrowing is the natural
  thing to write, too, because the author knows which files they touched, and a repository-wide grep
  trips over `spec/` quoting the old text — so the path of least resistance is to enumerate, and
  nothing pushes back.
- **Recommended fix:** add a clause to Step 6: when a criterion is universally quantified ("wherever",
  "every", "no file", "anywhere"), the gate must be quantified the same way — repository-wide with
  **explicit exclusions**, never an enumeration of the files the author happened to edit. Each
  exclusion is a claim needing a reason in the phase body (here: `spec/` quotes the old text verbatim;
  `issues/purge-resilient-run.md` is deleted by `/uvm-roadmap` on merge). A useful tell for the
  authoring pass: if the gate names fewer paths than the criterion's prose does, one of the two is
  wrong.
- **Confidence:** high · **Effort:** small

## F8 — The blind-review boundary is drawn at `spec/`, but `issues/` and `ROADMAP.md` restate the research on the same branch

`origin=uvm-review:step-2 severity=medium category=missing-guidance status=open target=.agents/factory/review-rubric.md`

- **What happened:** the cycle-2 reviewer disclosed, unprompted, that author rationale reached it
  through the legitimately-scoped diff. `issues/purge-tree-repair.md` and
  `issues/doctor-detection-gaps.md` cite `spec/purge-resilient-run/research/*` by filename and digest
  id and restate their verdicts; `ROADMAP.md:24-31` states that "the oracle passed with zero
  implementation" — a research conclusion. The `':(exclude)spec/'` pathspec is load-bearing and was
  applied to the diff, the log and every sweep, and it still let the plan's reasoning through, because
  a deferral cycle is *required* by `AGENTS.md` to write that reasoning into public files outside
  `spec/`.
- **Skill cause:** the rule is written as a directory exclusion — "keep `PLAN.md`, `TECH.md`,
  `research/` and `META.md` out of context" — which encodes the assumption that author intent lives
  only under `spec/`. On any cycle that defers work, it does not: the seed and the roadmap entry are
  where the deferral's evidence is recorded, by design. The two rules compose into a boundary that
  reads airtight and is not. Nothing tells the orchestrator to look at what the diff's *own* new files
  say before believing the pass is blind.
- **Recommended fix:** state the limit honestly in the rubric's "What the reviewer sees" — the
  exclusion bounds the artifacts, not the rationale, and a diff that adds `issues/*.md` or rewrites
  `ROADMAP.md` carries plan reasoning the reviewer will read. Add a line to Step 2: when the diff adds
  or rewrites seeds, say so in the reviewer's prompt and instruct it to treat their conclusions as
  claims to verify, not as findings already adjudicated. Excluding `issues/` outright is the wrong
  fix — the seeds are part of the graded delta.
- **Confidence:** high · **Effort:** small

## F9 — Scoping a later cycle to "named findings" contradicts the rule that drops the prior cycle's finding ids

`origin=uvm-review:step-3 severity=medium category=instruction status=open target=.agents/skills/uvm-review/SKILL.md`

- **What happened:** the maintainer scoped this cycle to the docs/comment delta. Step 3 sanctions that
  — "the human may instead scope it to verifying the remediation of named findings" — while Step 2
  requires dropping the log subjects on `review.cycle` ≥ 1 precisely because a subject like
  `Build {slug} P1: F1 — …` names a prior finding, and "anchoring on a prior verdict is the exact bias
  this pass exists to remove". Naming the findings to the reviewer is the thing Step 2 forbids. I
  resolved it by hand: describe the *surface* (four files, prose only) and state that the code was
  graded elsewhere, never which findings or what verdict. That worked — the reviewer re-derived the
  cycle-1 exemption independently — but the skill does not say to do it.
- **Skill cause:** the two steps were written against different concerns and never reconciled. Step 3
  is about the human's authority to bound cost; Step 2 is about anchoring. Neither says how to convey
  a scope without conveying the verdict that produced it, so the natural reading of Step 3 — paste the
  findings in — silently defeats Step 2 on exactly the cycle where anchoring is most likely.
- **Recommended fix:** in Step 3's scoped-cycle clause, add the translation rule: a scoped cycle is
  communicated to the reviewer as a *diff range and a graded surface*, never as finding ids, severities
  or a prior verdict. Note the corollary the rubric already half-states — when the scope is prose, the
  hunk-scoping inverts and the reviewer grades at file and repository scope, which has to be said
  explicitly or a prose-scoped pass grades only the moved lines and cannot see an omission.
- **Confidence:** high · **Effort:** small
