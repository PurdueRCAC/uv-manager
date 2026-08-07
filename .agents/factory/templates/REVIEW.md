# REVIEW — {Title}

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** {sha}  ·  **Base:** {base}  ·  **Date:** {YYYY-MM-DD}
- **Verdict:** approved | changes-requested
- **Cycle:** {n} of ≤3 — mirrors `review.cycle` in `TECH.md` (escalate on non-convergence)

## Verification run

Commands actually executed and their outcomes. This is the spine of the review.

- `bash -n bin/uv-manager` → <result>
- `.agents/factory/bin/lint.sh` → <result>
- `.agents/factory/bin/temp_root.sh --offline uv --version` → <observed behavior>
- `.agents/factory/bin/temp_root.sh --offline --arch aarch64 uvm status` → <observed behavior>
- <further drives: concurrency, failure paths, idempotence, the specific post-conditions asserted>

## Requirement → evidence matrix

Bidirectional traceability. Flag requirements with no implementing change **and** changes that map to
no requirement (scope creep).

| R-ID | Implemented by (function/line) | Verified how (command + post-condition) | Status |
|------|--------------------------------|------------------------------------------|--------|
| R1   | <…>                            | <…>                                      | ✅ / ❌ |

Unmapped changes (possible scope creep): <list or "none">.

Requirements taken on trust (cannot be observed from the sandbox): <list or "none">. Anything here
must already be named in `GOAL.md` or `PLAN.md` §5; a criterion silently downgraded to trust during
review is itself a finding.

## Findings

Severity: **CRITICAL** (any `invariants.md` §1–§11 violation is auto-CRITICAL) · **HIGH** ·
**MEDIUM** · **LOW**. Verdict: **CONFIRMED** (reproduced) versus **PLAUSIBLE** (suspected, needs human
triage). Only CONFIRMED findings auto-loop to `uvm-build`.

### [CRITICAL/CONFIRMED] <one-line defect>
- **Where:** `bin/uv-manager:NNN` (`function_name`)
- **Failure scenario:** <concrete state and inputs → wrong output, wrong exit code, wrong tree>
- **Evidence:** <the command run and what it showed>
- **Touches invariant / requirement:** <§n or R-ID>

## Human-gate triggers

Set if any CONFIRMED finding touches a high-blast-radius region (`uvm_acquire_lock`, `uvm_unlock`,
`uvm_install`, `uvm_point_current`, `uvm_resolve_root`, `uvm_init`, `uvm_trampolines`,
`uvm_export_env`, `uvm_set_paths`, the dispatch tail) or an architecture-partitioning, `exec`-semantics
or installer-environment invariant (§1, §2, §6). These always require human sign-off before
`uvm-publish`, regardless of auto-loop.

- <triggered? which finding?>

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

- Was every planned phase actually shipped? Did scope balloon beyond the appetite? <notes>
