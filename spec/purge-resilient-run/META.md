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
