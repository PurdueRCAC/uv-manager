---
slug: example-slug
title: "One-line human title for this feature"
kind: feature
appetite: big
status: in_progress
branch: feature/example-slug
base: main
current_phase: P1
last_updated: "2026-01-01"
phases:
  - id: P1
    name: "First vertical slice (core + small + novel)"
    status: pending
    satisfies: [R1]
    depends_on: []
    parallel: false
    hammerable: false
    hill: uphill
    verify: ".agents/factory/bin/lint.sh"
  - id: P2
    name: "Second slice"
    status: pending
    satisfies: [R2, R3]
    depends_on: [P1]
    parallel: false
    hammerable: true
    hill: uphill
    verify: ".agents/factory/bin/temp_root.sh --offline sh -c 'uv --version && test \"$(readlink \"$UV_MANAGER_ROOT/$(uname -m)/current\")\" = versions/9.9.9'"
review:
  last_reviewed_commit: ""
  verdict: none
  blocked_reason: ""
  cycle: 0
---

# TECH.md — {title}

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/{slug}/TECH.md`); the per-phase checklists below are the
work. `uvm-build` executes the next actionable phase, runs its `verify:` command, updates state via
`uv run .agents/factory/bin/set_phase.py …`, and makes one atomic code-plus-state commit.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs, if `appetite: big`.

## Frontmatter field reference

- `status` (top): `planned | in_progress | blocked | in_review | done`. `done` is stamped by
  `uvm-publish` after confirmation, just before landing — the terminal state of the retained record.
- `appetite`: `small | big` — caps phase count and build-iteration budget (the circuit breaker).
- phase `status`: `pending | in_progress | done | blocked`.
- `satisfies`: GOAL R-IDs this phase delivers. The traceability anchor for `uvm-review`.
- `depends_on`: phase ids that must be `done` first. A phase is actionable only when they are.
- `parallel`: **almost always `false` here.** There is one source file; two phases that both edit
  `bin/uv-manager` are not independent. Reserve `true` for genuinely disjoint work such as
  documentation-only or modulefile-only phases.
- `hammerable`: `false` marks a correctness phase that scope-hammering must never cut. Anything
  touching `invariants.md` §1–§11 is `false`.
- `hill`: `uphill` (still figuring it out) → `crest` (unknowns resolved) → `downhill` (just
  executing). A phase stuck `uphill` across builds is a raised hand — escalate.
- `attempts`: durable failed-verify counter (absent means 0), bumped by
  `set_phase.py --phase P<n> --record-attempt` on every red gate. `next_phase.py` warns at 3. The
  circuit breaker runs on this file, not on session memory.
- `verify`: the exact command that proves the phase. Drive the real script under
  `.agents/factory/bin/temp_root.sh` so it never touches the developer's real state root, and assert
  a **post-condition**, not just exit 0.
- `review.cycle`: completed review passes, auto-incremented by every `set_phase.py --verdict`.
  `REVIEW.md`'s "Cycle {n}" mirrors it and the two-to-three-cycle bound is graded against it.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md) — it is the constitution. Consult
  [`invariants.md`](../../.agents/factory/invariants.md) for the footgun checklist relevant to this
  change.
- One phase per `uvm-build` invocation by default; one atomic commit containing **both** the code and
  the `TECH.md` state change. Subjects follow `[{category}] Build {slug} P<n>: …` with no `WIP:`
  prefix — they are squashed into the single PR-title commit at `uvm-publish`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer (this repository's convention).
- A behavior change updates the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example` and
  `share/modulefiles/uv/main.lua` — whichever it invalidates — **in the same commit**.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager` or `README.md`.

---

## Phase P1 — First vertical slice
**Satisfies:** R1 · **Depends on:** —
**Goal:** <what this slice delivers, end to end and independently verifiable>.

- [ ] <concrete step>
- [ ] <concrete step>
- **Verify:** `.agents/factory/bin/lint.sh` — and name the post-condition asserted.
- **Touches:** `bin/uv-manager`, `README.md`, …

## Phase P2 — Second slice
**Satisfies:** R2, R3 · **Depends on:** P1
**Goal:** <…>.

- [ ] <concrete step>
- **Verify:** `.agents/factory/bin/temp_root.sh --offline …` asserting <post-condition>.
- **Touches:** `bin/uv-manager`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative; the `current_phase`
   pointer is reconciled against them.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[{category}]` commit; stop and
   report.
