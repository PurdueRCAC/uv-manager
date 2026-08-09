---
name: uvm-review
description: >-
  Adversarial QA of a completed uv-manager feature branch. Delegates the correctness pass to a FRESH
  reviewer subagent that sees only GOAL.md, the branch diff, the AGENTS.md invariant checklist and the
  runnable repo — NOT PLAN.md/TECH.md, which avoids grading-its-own-homework. The reviewer refutes each
  finding and cites executed commands run in a sandbox; CONFIRMED findings loop back to /uvm-build; a
  high-blast-radius region forces a human gate. Fourth step of the software factory (see
  .agents/factory/review-rubric.md).
disable-model-invocation: true
argument-hint: "[debate] [completeness] [status]"
allowed-tools: Read, Grep, Glob, Write, Agent, ReportFindings, AskUserQuestion, Bash(git status *), Bash(git branch *), Bash(git log *), Bash(git diff *), Bash(git rev-parse *), Bash(git add *), Bash(git commit *), Bash(uv run *), Bash(.agents/factory/bin/*), Bash(tail *)
---

# uvm-review — adversarial QA (clean context)

## When to Use

Invoke `/uvm-review` when a branch's `TECH.md` is fully built (`status: in_review`). **Best run in a
fresh session**, but the real guarantee comes from delegating scrutiny to freshly spawned subagents
with curated inputs, so bias is removed even if this session is not clean. The reviewer grades the
diff against the **locked `GOAL.md`** and the **`AGENTS.md` invariants**, by **executed command**, not
opinion.

This project has no test suite. That raises the bar for this pass rather than lowering it: the
executed-evidence requirement is the only coverage the change gets before it reaches a cluster.

Operating manual: [`review-rubric.md`](../../factory/review-rubric.md) and
[`invariants.md`](../../factory/invariants.md). Read both before delegating.

**Harness portability.** Runs on any harness — see [`portability.md`](../../factory/portability.md).
Fallbacks: run the *Current state* commands yourself if not auto-injected; ask in plain text and STOP
if `AskUserQuestion` is unavailable; **if subagents are unavailable or the session disallows them,
perform the correctness pass yourself in a clean context** (you lose delegated blindness — compensate with executed evidence, per
the rubric); skip `ReportFindings` (`REVIEW.md` is the durable record).

## User Instructions

Additional instructions provided with the invocation: $ARGUMENTS

## Current state (injected at load)

- Branch: !`git branch --show-current`
- Base: `main` (confirm from `base:` in TECH.md during Step 1).
- Diffstat vs main: !`git diff --stat main...HEAD 2>/dev/null | tail -n 20`

## Argument Parsing

- `status` → report the current `review` verdict from `TECH.md` and any existing `REVIEW.md`; no work.
- `debate` → run the two-independent-reviewer variant, for high-blast-radius diffs.
- `completeness` → also run the *separate* completeness sub-pass, which may see `TECH.md`.

## Safety Principles

- **Blindness is the point.** The correctness reviewer is given `GOAL.md`, the diff, the runnable repo,
  `invariants.md` and `review-rubric.md`, and is **explicitly told that `PLAN.md`, `TECH.md`,
  `research/` and `META.md` must not reach its context by any route** (`META.md` leaks author intent
  and harness notes, same reason as PLAN/TECH). Opening them is the obvious route; a repository-wide
  `grep -rn` or `rg` sweep is the one that actually fires, because a reviewer inventorying a renamed
  symbol reaches for exactly that and gets the matching lines back without opening a file.
  Only this skill reads `TECH.md`, and only for the `base`/`slug`/`kind` metadata; it must
  not pass PLAN/TECH *content* into the reviewer prompt. **The diff must be blind too:** those
  artifacts are committed on the branch, so a plain `git diff {base}...HEAD` hands the reviewer
  PLAN/TECH/research and any prior cycle's REVIEW.md as added hunks. The `':(exclude)spec/'` pathspec
  below is load-bearing, not cosmetic.
- **External verification is the spine.** Every finding must cite an executed command. No
  assertion-only findings.
- **Every drive is sandboxed.** `.agents/factory/bin/temp_root.sh [--offline] [--arch KEY] …`. The
  reviewer must never run a bare `bin/uvm install` or otherwise touch the developer's real
  `UVM_ROOT`, cache or managed interpreters.
- **Refute before reporting.** Try to disprove each candidate; classify `CONFIRMED` (reproduced) versus
  `PLAUSIBLE` (needs human triage). Default to dropping when uncertain.
- **Scope is narrow:** correctness bugs, GOAL R-ID gaps, invariant violations (auto-CRITICAL), and
  scope creep. **No style nits, no speculative hardening** — a gap-hunting reviewer manufactures gaps.
  The one exception is prose: a diff hunk that violates `AGENTS.md` § *Prose and comments* is in scope
  as a §12 finding. Padding and marketing adjectives cost a reader's confidence in infrastructure that
  has to be trusted to be adopted. Scope it to the hunk, not to the file — unless the prose is the
  deliverable, on a documentation branch or against a whole-file-census criterion, where the file is
  the graded surface. The rubric carries the full rule.
- **Read-only session.** This skill makes no source edits. It writes `REVIEW.md` and updates the
  `TECH.md` `review` block via `set_phase.py`.
- **Mandatory human gate** when any CONFIRMED finding touches a high-blast-radius region
  (`uvm_acquire_lock`, `uvm_unlock`, `uvm_install`, `uvm_point_current`, `uvm_resolve_root`,
  `uvm_init`, `uvm_trampolines`, `uvm_export_env`, `uvm_set_paths`, the dispatch tail) or an
  architecture-partitioning, `exec`-semantics or installer-environment invariant (§1, §2, §6).
- **Bounded loop:** at most two or three review↔build cycles; escalate on non-convergence.

## Procedure

### Step 1 — Pre-flight
Confirm a feature/fix branch; resolve `{slug}` from the branch; confirm `base` (defaults to `main`);
read `kind` from `TECH.md`. The commit `{category}` is the category of the branch's shape commit
(`git log --oneline {base}..HEAD`, oldest entry), not `kind` — the two taxonomies differ. Capture the
head SHA (`git rev-parse HEAD`). If
`TECH.md` `status` is not `in_review`/`done`, note it — the build may be incomplete — and ask whether
to proceed.

**Contract-drift check:** `git log --oneline {base}..HEAD -- spec/{slug}/GOAL.md`. Anything beyond the
original shaping commit means the locked contract moved mid-build. Surface those commits and confirm
before grading: post-shape clarifications happen legitimately, but a silently drifted requirement
would make this review grade the wrong contract.

**Debate check:** if the diff touches a high-blast-radius region or an §1/§2/§6 invariant — the
condition [`review-rubric.md`](../../factory/review-rubric.md) § *Optional debate variant* names —
recommend the `debate` variant and let the human choose. It costs twice as much, so it is their call
and not an automatic escalation; what is not acceptable is the option never being offered on the
highest-risk diff in the repository. Skip this when `debate` was already requested.

### Step 2 — Delegate the correctness pass (fresh subagent)
Launch a fresh `general-purpose` reviewer via `Agent`. Give it, inline, **only**:

- the full text of `spec/{slug}/GOAL.md` — the contract, the R-IDs;
- the command to produce the diff: `git diff {base}...HEAD -- . ':(exclude)spec/'`, plus
  `git log --oneline {base}..HEAD -- . ':(exclude)spec/'`. Never a bare `git diff {base}...HEAD`,
  which leaks the committed spec artifacts into the reviewer's context — and the same pathspec belongs
  on the log, a channel the diff's cannot close: review-cycle commits touch only `spec/` and vanish
  under it, but a build subject reads `[fix] Build {slug} P1: F1 — …` and names a prior cycle's
  finding along with its remediation. On `review.cycle` ≥ 1 drop the subjects too (`--format=%h`), or
  omit the log. Anchoring on a prior verdict is the exact bias this pass exists to remove;
- the full text of `invariants.md` and `review-rubric.md`;
- the instruction: work in the runnable repo; follow the refutation protocol; **run** the relevant
  gates — `bash -n bin/uv-manager`, `.agents/factory/bin/lint.sh`, and behavioral drives through
  `.agents/factory/bin/temp_root.sh [--offline] [--arch KEY]`, never the developer's real state root;
  and **keep `PLAN.md`, `TECH.md`, `research/` and `META.md` out of context entirely** — do not open
  them, and exclude `spec/` from every repository-wide search:
  `git grep -n … -- . ':(exclude)spec/'`, `rg --glob '!spec/**' …`. `GOAL.md` is supplied inline
  above, so excluding the whole directory costs the reviewer nothing;
- the conduct rule: **no edits to tracked files** (revert any instrumentation before returning;
  `git status --porcelain` must be clean on hand-back), and the rubric's "Verdict & loop" section is
  the orchestrator's job — the reviewer must not write `REVIEW.md`, call `ReportFindings`, or run
  `set_phase.py`;
- required return: a structured findings list (severity, CONFIRMED/PLAUSIBLE, `file:line`, failure
  scenario, the executed evidence with the observed post-condition) plus a requirement→evidence matrix
  (every R-ID: implemented? verified how? or explicitly taken on trust) and any unmapped changes.

`debate`: launch **two** independent reviewers — one instructed to argue "ship", one "block" — and
reconcile their findings.

### Step 3 — Collect, sanity-check, and report
Read the reviewer's returned findings. Confirm the reviewer left the tree clean
(`git status --porcelain` empty; if not, inspect and revert its leftovers before anything else). Do a
light second-pass sanity check, dropping anything not backed by cited evidence. Then:

1. **Cycle 1:** write `spec/{slug}/REVIEW.md` from the template — verification run,
   requirement→evidence matrix, findings most-severe-first, human-gate triggers. **Cycle 2+
   (`review.cycle` ≥ 1): never overwrite.** Append a dated
   `## Review cycle {n} — {verdict} ({YYYY-MM-DD})` section; the file is the cumulative record. A
   later cycle defaults to a fresh blind pass over the full spec-excluded diff; the human may instead
   scope it to verifying the remediation of named findings — record which mode was used.
2. Call `ReportFindings` with the verified findings, most severe first (empty array if clean), with
   `verdict` = CONFIRMED/PLAUSIBLE per finding.

### Step 4 — Set verdict + route
- **Clean (no CONFIRMED):**
  `uv run .agents/factory/bin/set_phase.py spec/{slug}/TECH.md --verdict approved --reviewed-commit
  {sha} --touch` → recommend `/uvm-publish`.
- **CONFIRMED findings:**
  `uv run .agents/factory/bin/set_phase.py spec/{slug}/TECH.md --top-status blocked --verdict
  changes-requested --reviewed-commit {sha} --blocked-reason "<short>" --touch` → recommend
  `/uvm-build` to fix the named R-IDs and invariants. If any CONFIRMED finding hit a high-blast-radius
  region or a §1/§2/§6 invariant, **STOP and require explicit human sign-off** before any further step.
- **PLAUSIBLE only:** surface to the human for triage; do not auto-block.

Every `--verdict` call auto-increments the durable `review.cycle` counter in `TECH.md`. Do not manage
it by hand; it is the source of truth for the three-cycle bound and for REVIEW.md's "Cycle {n}".

**Meta-note (orchestrator only · silence by default).** Reflect on the **review skillset itself** — not
the diff, not the code. *You, the orchestrator,* may record a finding; the blind reviewer never does,
and content or correctness issues belong in `REVIEW.md`. You may also add a one-line **What worked
well** note. The bar for a finding is the one test: *was this the skill's fault — not mine, not the
task's?* (an ambiguous rubric step, a curated-input or allowed-tools mismatch, guidance that made the
delegation misfire). If met, record it in `spec/{slug}/META.md` — create from
[`templates/META.md`](../../factory/templates/META.md) if absent, else append. At most three terse
findings, next unused `F#`, always `status=open`, "· seen again" instead of duplicating; a fix that
would weaken a non-negotiable gate (blind-review integrity, the executed-evidence spine, the human
gate, an `invariants.md` item) is `severity=high` and must say so. **Records only:**

```markdown
## F<n> — <one-line title>
`origin=uvm-review:<step> severity=<high|medium|low> category=<instruction|steering|tooling|template|missing-guidance> status=open target=<best-guess file>`
- **What happened:** <what the skill made you do, or fail to do>.
- **Skill cause:** <why it's the instructions' fault — not yours, not the task's>.
- **Recommended fix:** <the change to the skill/template/script>.
- **Confidence:** <high|med|low> · **Effort:** <small|medium|large>
```

Then **commit the review artifacts** so the tree stays clean for the loop:
```
git add spec/{slug}/REVIEW.md spec/{slug}/TECH.md   # + spec/{slug}/META.md if you recorded a meta-note
git commit -m "[{category}] Review {slug}: cycle {n} — {verdict}"
```
Keep the `Co-Authored-By` trailer. Do not push.

### Step 5 — Optional completeness sub-pass (`completeness`)
Launch a **separate** fresh subagent that *may* read `TECH.md` and ask: was every planned phase
actually shipped? did scope balloon beyond the appetite? Keep it isolated from the correctness pass so
the plan never contaminates the correctness verdict. Append its notes to `REVIEW.md`.

### Final report
Verdict, CONFIRMED/PLAUSIBLE counts, human-gate status, R-ID coverage (including anything taken on
trust), and the recommended next step — `/uvm-build` to remediate, or `/uvm-publish` when approved.
Note the review cycle count; if it is the second or third cycle without convergence, escalate.

## Examples

- `/uvm-review` — blind correctness pass; write `REVIEW.md`; set verdict; route.
- `/uvm-review debate` — two independent reviewers for a diff touching the provisioning path.
- `/uvm-review completeness` — correctness pass plus the separate did-we-ship-everything sub-pass.
- `/uvm-review status` — show the current verdict and existing findings; no work.

## Notes

- The blind reviewer sees `GOAL.md`, not `PLAN.md`/`TECH.md`: `GOAL.md` is *what and why*, legitimate
  ground truth; the plan is the author's *how*, and grading it invites plan-sycophancy.
- Single-model review in a fresh context removes anchoring bias but not family-level self-preference —
  hence the executed-evidence spine and the human gate. This is risk reduction, not proof.
- A requirement the sandbox genuinely cannot observe is not a pass. Record it in REVIEW.md's
  "taken on trust" list, and check it was already declared in `GOAL.md` or `PLAN.md` §5. A criterion
  silently downgraded to trust during review is itself a finding.
