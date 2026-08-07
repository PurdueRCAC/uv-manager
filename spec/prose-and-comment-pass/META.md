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

## F3 — Step 6 checks a gate for contradiction and blindness, never that it can go red at all
`origin=uvm-plan:step-6 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** the first run of this cycle's census — the command `GOAL.md` supplies as R1's check
  — reported zero hits against a tree with thirteen. The pathspec was a variable holding four paths, and
  zsh does not word-split an unquoted parameter, so `git grep` searched one nonexistent path and exited
  clean. A gate built on that shape would have gone green on an untouched file. I found it only because
  the number disagreed with the GOAL's stated baseline of 13.
- **Skill cause:** Step 6 tells me to read a `verify:` back against the phase checklist for two failure
  modes, contradiction and blindness, and both are about *scope*. Neither catches a gate that cannot
  fail — one whose command silently matches nothing regardless of the tree. The obvious control is to
  run every gate against the pre-pass tree and confirm the ones asserting post-conditions come back
  **red**, but the skill never asks for it. Nothing in Step 6 distinguishes "green because the work is
  done" from "green because the command is inert".
- **Recommended fix:** add to Step 6, after the two-direction read-back: run each `verify:` against the
  current tree before committing the plan. A gate asserting a post-condition the phase has not yet
  delivered must exit non-zero, and one that exits 0 is inert until proven otherwise. Note the specific
  trap that motivated it — an interpolated pathspec collapses under zsh — and require literal paths in
  census-style gates.
- **Confidence:** high · **Effort:** small

## F4 — the high-blast-radius research exception does not distinguish editing a region from editing its comments
`origin=uvm-plan:step-3 severity=low category=instruction status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** Step 3 skips the fan-out for `appetite: small`, then overrides that for any change
  "expected to touch any high-blast-radius region". This cycle is a comment-and-prose pass whose own
  contract (R4) forbids changing an executable statement, yet it edits comment text sitting inside
  `uvm_install`, `uvm_acquire_lock`, `uvm_resolve_root` and `uvm_trampolines`. Read literally the
  exception fires and mandates a full fan-out; read by intent it does not, because none of the contracts
  the exception exists to pin can be broken by a comment.
- **Skill cause:** "touch" is doing two jobs. The exception's stated rationale — "a small edit there
  still needs the exact contracts pinned before design" — is about *behavior*, but the trigger is
  written as file-region adjacency, which text edits satisfy for free.
- **Recommended fix:** make the trigger behavioral: the exception fires when a change can alter what a
  high-blast-radius region *does*. A pass constrained to comments, message strings or documentation
  scales research to appetite instead — though the message text of a region named in `invariants.md` §3
  or §7 is still worth a baseline capture, which is what this cycle did.
- **Confidence:** med · **Effort:** small

## F5 — the subagent fallback is written as availability, but the blocker is often policy
`origin=uvm-plan:step-3 severity=low category=instruction status=open target=.agents/factory/portability.md`
- **What happened:** the fan-out fallback is gated on "**No subagents in your harness?**" and
  `portability.md` frames the same escape hatch as a capability question. Here subagents existed and
  worked; the session instructed me not to spawn them unasked. I took the fallback and did the research
  sequentially, which was plainly the intent, but the condition as written did not cover the case.
- **Skill cause:** the instruction tests for a missing tool when the thing that actually matters is
  whether fanning out is available *and* permitted. A harness with an agent policy, a cost ceiling, or a
  sandbox restriction hits this on every lifecycle skill that fans out, not just this one.
- **Recommended fix:** widen the condition wherever it appears — "if subagents are unavailable **or the
  session disallows them**, do the research yourself, sequentially, writing the same files." The
  deliverable is unchanged either way, which is worth saying so the choice does not read as a scope cut.
- **Confidence:** high · **Effort:** small
