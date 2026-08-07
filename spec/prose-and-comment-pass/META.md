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
- Capturing the pre-pass user-facing output as a committed `research/` artifact turned "did this lose
  information a stuck operator needs?" from a judgment call into a `diff`. For a cycle whose contract
  is *behavior unchanged*, the baseline is cheaper to take at plan time than to reconstruct later, and
  `uvm-build` P1 and P4 both closed against it in seconds. Worth doing whenever an R-ID says "same as
  before".
- `uvm-build` Step 4's instruction to re-run a new gate under `/bin/sh` caught nothing this cycle, but
  it is what makes the green trustworthy: every gate here was authored in zsh and four of them use
  process-substitution-free constructions only because that instruction exists.

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
`origin=uvm-feature:step-4 severity=medium category=missing-guidance status=applied target=.agents/skills/uvm-feature/SKILL.md`
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
`origin=uvm-feature:step-4 severity=low category=template status=applied target=.agents/factory/templates/GOAL.md`
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

## F6 — `uvm-build` derives the commit category from `kind`, which is a different taxonomy
`origin=uvm-build:step-7 severity=low category=instruction status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** Step 7 says "`{category}` is the `TECH.md` `kind`", which here is `refactor`.
  `/uvm-plan` Step 8 says the opposite — "`{category}` is the same category as the shape commit" — which
  is `docs`, and the `TECH.md` conventions block I committed last cycle spells out `[docs]` with its
  reason. Two lifecycle skills give different rules for the same field, so I had to adjudicate rather
  than follow. I used `docs`, consistent with the branch's other two commits.
- **Skill cause:** `kind` and commit category are not the same set. `AGENTS.md` lists the categories as
  `feature, fix, docs, refactor, release, harness` and calls the set open; `kind` is the lifecycle
  taxonomy and has no `docs` or `harness` member. A prose or documentation cycle is exactly the case
  where they diverge, and it is not rare — the same-commit rule pulls documentation into most cycles.
- **Recommended fix:** make `uvm-build` defer to the shape commit's category the way `uvm-plan` does,
  and say that `kind` is a fallback when no prior branch commit exists. Alternatively record the
  category once in `TECH.md` frontmatter at plan time so both skills read one field.
- **Confidence:** high · **Effort:** small

## F7 — the prose exception is scoped to the diff hunk, which is the wrong surface for a prose cycle
`origin=uvm-review:step-2 severity=medium category=instruction status=open target=.agents/factory/review-rubric.md`
- **What happened:** the rubric's one exception to "no style nits" says to flag prose that violates the
  voice rules **in a diff hunk** and to "scope it to the hunk, not to the file". The only finding this
  review produced sits at `bin/uv-manager:597`, a line the diff never touched. Followed literally, the
  rubric suppresses it. It survives only because this cycle's `GOAL.md` makes a whole-file census the
  graded criterion, so I reached it through R1 instead — and had to notice that collision myself rather
  than being told how to resolve it.
- **Skill cause:** the hunk-scoping rule is written for a feature or fix cycle, where the file's
  untouched prose is somebody else's problem and a reviewer sweeping it manufactures gaps. In a prose
  cycle the untouched text *is* the deliverable: the work is defined as the set of lines the pass chose
  not to change, and grading only what moved cannot see an omission. The rubric never says which
  reading wins.
- **Recommended fix:** add a sentence to the exception — when the branch's `kind` is a prose or
  documentation pass, or when a `GOAL.md` criterion is a whole-file census, the graded surface is the
  file, not the hunk; the anti-gap-hunting rule still holds elsewhere.
- **Confidence:** high · **Effort:** small

## F8 — remediation is described as local to one phase, but a fix invalidates downstream gates
`origin=uvm-build:step-1.3 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** F1 was one word in `bin/uv-manager`, which Step 1.3 correctly routed to reopening
  P1 and retuning its gate. But P4 is a reconciliation phase whose gate hardcodes the post-pass census
  total, and the one-word fix moved it from 7 to 6. Nothing in Step 1.3 told me to look; I found it
  only because I had read P4's `verify:` during the review. Had I not, P1 would have gone green, the
  branch would have shipped `status: in_review`, and P4 would have sat `done` with a gate that fails
  on the tree it certifies.
- **Skill cause:** Step 1.3 is written as if a finding maps to exactly one phase — "prefer reopening
  the existing phase whose `satisfies` covers the failing R-IDs" — and never mentions the phases
  downstream of it. `next_phase.py` does not re-run gates, so a stale assertion in a `done` phase is
  invisible to the FSM. This factory's plans routinely end in a reconciliation phase that snapshots
  counts, which is exactly the shape that breaks.
- **Recommended fix:** add to Step 1.3 — after a remediation edit, re-run the `verify:` of every `done`
  phase that lists the reopened phase in `depends_on`, and reopen any that goes red. A phase whose
  gate asserts a count is a downstream dependency of every phase that can change that count.
- **Confidence:** high · **Effort:** small

## F9 — Step 4 requires running a gate under `/bin/sh`, with no supported way to get the string out
`origin=uvm-build:step-4 severity=low category=tooling status=open target=.agents/factory/bin/`
- **What happened:** Step 4 says to run a retuned gate as `/bin/sh -c '…'` and confirm it is red before
  the fix and green after. The gate lives in `TECH.md` as folded YAML across a dozen wrapped lines, so
  it cannot be copied by hand without reflowing it — and reflowing is where a quoting error enters. I
  wrote a throwaway `uv run --with pyyaml` reader twice, once per phase.
- **Skill cause:** `.agents/factory/bin/` has `next_phase.py`, `set_phase.py` and `meta_status.py` but
  nothing that prints or runs a phase's gate, even though Step 4 makes running it under a plain shell
  mandatory. The first attempt failed on a missing `pyyaml` and left the variable empty; an empty
  string handed to `/bin/sh -c` exits 0, so the "confirm it is red" step can be satisfied by a reader
  that silently produced nothing.
- **Recommended fix:** add `run_verify.py spec/{slug}/TECH.md --phase P<n> [--print]` that extracts the
  gate and execs it under `/bin/sh -c`, erroring if the string is empty. Then Step 4 cites one command
  and the false-green is impossible.
- **Confidence:** high · **Effort:** small

## F10 — the blind reviewer is handed `git log`, whose subjects carry the prior cycle's verdict and findings
`origin=uvm-review:step-2 severity=high category=instruction status=open target=.agents/skills/uvm-review/SKILL.md`
- **What happened:** Step 2 says to give the reviewer `git diff {base}...HEAD -- . ':(exclude)spec/'`
  **plus** `git log --oneline {base}..HEAD`. On a second cycle that log reads
  `[docs] Review {slug}: cycle 1 — changes-requested` and
  `[docs] Build {slug} P1: F1 — drop filler just (R1)`. The cycle-2 reviewer reported unprompted that
  it had learned a prior cycle existed, what its verdict was, which finding id was remediated, and what
  the remediation was. Its findings did not depend on that, but it is the reviewer that noticed, not
  the skill.
- **Skill cause:** the skill is meticulous about the `':(exclude)spec/'` pathspec on the diff, calling
  it "load-bearing, not cosmetic," and then hands the same information back through the log in the very
  next clause. The leak channel is commit *subjects*, which no pathspec on the diff can close.
  `uvm-build` and `uvm-review` are the skills that write those subjects, so the format is the harness's
  own doing.
- **Recommended fix:** in Step 2, change the log command to
  `git log --oneline {base}..HEAD -- . ':(exclude)spec/'` — review-cycle commits touch only `spec/` and
  vanish entirely — and add: on `review.cycle` ≥ 1, drop subjects too (`--format=%h`) or omit the log,
  because build subjects name the remediated finding ids. Anchoring on a prior verdict is the exact
  bias the blind pass exists to remove.
- **Confidence:** high · **Effort:** small

## F11 — a verification technique discovered in cycle 1 has nowhere to live that cycle 2 can read
`origin=uvm-review:step-3 severity=medium category=missing-guidance status=open target=.agents/factory/review-rubric.md`
- **What happened:** cycle 1 found that this repo's R1 census silently reports clean when the four
  paths are passed through a shell variable, because `zsh` does not word-split, and recorded that as a
  methodology note in `REVIEW.md`. `REVIEW.md` is under `spec/`, so the cycle-2 reviewer could not read
  it, walked into the identical false green on its first batched census, and had to rediscover the
  cause. It caught itself; a less careful pass reports `0 hits` and calls R1 satisfied.
- **Skill cause:** the harness has no channel for carrying a *verification technique* across cycles.
  Everything a reviewer learns lands in `REVIEW.md`, which the next blind reviewer is correctly
  forbidden to open. The two properties — durable and blindness-safe — are in tension, and no file is
  designated for their intersection. A false-green in a gate command is not author intent and leaks
  nothing about the plan.
- **Recommended fix:** give `REVIEW.md` a `## Verification notes (blindness-safe)` section and have
  Step 2 paste it, and only it, into the next cycle's reviewer prompt. Alternatively promote such notes
  to `review-rubric.md`, which the reviewer already reads — the `zsh` pathspec trap is not
  feature-specific and belongs there permanently.
- **Confidence:** high · **Effort:** small
