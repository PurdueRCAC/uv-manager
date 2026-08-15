# Review rubric — `uvm-review`

The operating manual for the adversarial QA pass. The correctness reviewer runs in an **isolated
context** (a fresh subagent) and grades the branch diff against `GOAL.md` plus the `AGENTS.md`
invariants **only** — it is denied `PLAN.md` and `TECH.md`, because showing the author's own rationale
produces grading-its-own-homework and plan-sycophancy. Verification is by **executed command**, never
by assertion.

This repository has no test suite. That raises the bar for this pass rather than lowering it: the
executed-evidence requirement is not a formality, it is the only coverage the change will get before
it reaches a cluster.

## What the reviewer sees

- ✅ `GOAL.md` — the locked contract (R-IDs)
- ✅ the branch diff **excluding `spec/`** (`git diff <base>...HEAD -- . ':(exclude)spec/'` — the spec
  artifacts are committed on the branch, so an unfiltered diff would hand the reviewer PLAN/TECH,
  research, and any prior cycle's REVIEW.md) and the full runnable repo. The commit log carries the
  same pathspec, and on a second cycle its **subjects** are dropped as well — they name the prior
  verdict and the finding ids that were remediated
- ✅ [`invariants.md`](invariants.md) and `AGENTS.md`
- ❌ **NOT** `PLAN.md`, `TECH.md`, `research/`, or `META.md` (`META.md` is the harness
  self-improvement log and leaks author intent, same as PLAN/TECH). The ban is on the content reaching
  context, not on opening the file: exclude `spec/` from every repository-wide search too —
  `git grep -n … -- . ':(exclude)spec/'`, `rg --glob '!spec/**' …` — since a sweep returns their
  matching lines without opening anything
- A **separate, later** completeness sub-pass *may* read `TECH.md` to ask "was every planned phase
  shipped? did scope balloon?" — kept isolated so the plan never contaminates the correctness verdict.

## Scope — flag ONLY

1. **Correctness bugs** — wrong behavior, a crash, a corrupted or misplaced state tree.
2. **GOAL-requirement gaps** — an R-ID with no implementing change, or implemented incorrectly.
3. **`AGENTS.md` invariant violations** — auto-CRITICAL (see below).
4. **Scope creep** — changes that map to no R-ID. Report; do not necessarily block.

**Do not** report style nits, speculative hardening, or "you could also…" gold-plating. A gap-hunting
reviewer manufactures gaps, and manufactured gaps drive exactly the bloat this project is trying to
avoid. Silence on a clean diff is a valid and valuable result.

One exception: prose that violates the `AGENTS.md` § *Prose and comments* rules **in a diff hunk** is
in scope as a §12 finding. A comment that restates the code, or a README sentence padded with
marketing adjectives, costs a reader's confidence in infrastructure that has to be trusted to be
adopted. Flag it; do not rewrite the surrounding text that the diff did not touch.

The hunk scoping inverts when the prose *is* the deliverable. On a documentation or prose-pass branch,
or against a `GOAL.md` criterion that is a whole-file census, the graded surface is the file: the work
is defined as the set of lines the pass chose not to change, and grading only what moved cannot see an
omission. Everywhere else the hunk still bounds it — a reviewer sweeping untouched prose on a feature
branch manufactures gaps.

## Reviewer conduct (the subagent)

- **Leave the tree clean.** Make no edits to tracked files. If you must instrument to reproduce a
  finding, revert it before returning — `git status --porcelain` must be empty when you hand back.
- **Drive the script in a sandbox**, always: `.agents/factory/bin/temp_root.sh [--offline] [--arch K]
  …`. Never against the developer's real `UVM_ROOT`, and never a bare `bin/uvm install`, which
  can download hundreds of megabytes into real storage.
- The **Verdict & loop** section below is the *orchestrator's* job, executed after you return. Do not
  write `REVIEW.md`, call `ReportFindings`, or run `set_phase.py` yourself. Your deliverable is the
  structured findings list and the requirement→evidence matrix you were asked for.

## Refutation protocol (mandatory)

For every candidate finding, **try to disprove it first**:

1. Reproduce it — run the exact command, construct the exact state, that triggers it.
2. Reproduced with observed wrong behavior → **CONFIRMED**.
3. Plausible by reading but not reproduced → **PLAUSIBLE** (human triage; does not auto-loop).
4. Dissolves under scrutiny → drop it silently.

Default to dropping when uncertain. A single-model reviewer has self-preference bias even in a fresh
context, so lean on executed evidence, not opinion.

**What counts as evidence here.** A diff of the sandbox state tree before and after; a `readlink` on
`current`; a captured stderr line; an exit code from a deliberately broken input; a second invocation
proving idempotence; two concurrent invocations proving the lock. "I read the code and it looks
wrong" is a PLAUSIBLE at best.

## Verification traps in this repository

Standing knowledge, safe for a blind reviewer: a false green in a gate command is not author intent
and reveals nothing about the plan. A trap found during a review that is not feature-specific belongs
here, added by `/uvm-harness` — never in `REVIEW.md`, which the next cycle's reviewer is correctly
forbidden to open, so a technique recorded there is rediscovered or walked into again.

- **An interpolated pathspec collapses under `zsh`.** `git grep -n PATTERN -- $PATHS`, where `$PATHS`
  holds several paths, searches one nonexistent path and exits clean: `zsh` does not word-split an
  unquoted parameter. A census built that way reports zero hits against a tree full of them. Write the
  paths literally, and check the count against whatever baseline `GOAL.md` states.
- **`grep` may not be `grep`.** In an interactive agent shell it can be a function wrapping something
  else; under `/bin/sh` it is `/usr/bin/grep`. Run anything load-bearing through `/bin/sh -c` before
  believing its exit status.

## Severity

| Severity | Meaning |
|---|---|
| **CRITICAL** | Loss or misplacement of user state, a wrong-architecture or wrong-version execution, a leaked lock, or **any** `invariants.md` §1–§11 violation. (A §12 project-conventions violation is **HIGH**.) |
| **HIGH** | A GOAL R-ID unmet or wrong; a real bug on a common path; a §12 violation. |
| **MEDIUM** | A bug on an edge path; a partial or fragile requirement. |
| **LOW** | Minor correctness risk; a documented behavior the diff quietly changed without saying so. |

## Verdict & loop (orchestrator only)

- Emit findings via `ReportFindings` (most severe first) **and** write `REVIEW.md`.
- **CONFIRMED** findings → set `TECH.md` `status: blocked` and `review.verdict: changes-requested`
  (via `set_phase.py`), then loop back to `uvm-build`.
- **PLAUSIBLE** findings → surface to the human for triage; do not auto-loop.
- Clean pass → `review.verdict: approved`; proceed to `uvm-publish`.
- Cycle 2+ **appends** a dated `## Review cycle {n}` section to `REVIEW.md` — never overwrite an
  earlier cycle; the file is the cumulative record.
- **Bounded loop:** at most two or three review↔build cycles, graded against the durable
  `review.cycle` counter in `TECH.md` (auto-incremented by every `set_phase.py --verdict`). On
  non-convergence, STOP and escalate — self-correction does not reliably converge.

## Mandatory human sign-off gate

Regardless of auto-loop, a human must approve before `uvm-publish` whenever a CONFIRMED finding
touches:

- a high-blast-radius region: `uvm_acquire_lock`, `uvm_unlock`, `uvm_install`, `uvm_point_current`,
  `uvm_resolve_root`, `uvm_init`, `uvm_trampolines`, `uvm_export_env`, `uvm_set_paths`, or the
  dispatch tail; **or**
- an architecture-partitioning, `exec`-semantics, or installer-environment invariant (§1, §2, §6).

A triggered gate is cleared by the human, never by the agent's own reading of the finding. The
sign-off may be given inline and the run continues from there, but the clearance is recorded in
`REVIEW.md` under *Human-gate triggers*: which finding fired it, who cleared it, the date, and the
grounds. Nothing downstream reconstructs that — `uvm-publish` gates on the review verdict and the
staleness check, and never asks whether a gate fired.

## Optional debate variant (high-risk diffs)

For a diff touching a high-blast-radius region, run **two** independent fresh reviewers — one
instructed to argue "ship", one to argue "block" — and reconcile. Independent instances beat
single-model introspection. Reserve it for genuinely high-risk changes; it costs twice as much.
