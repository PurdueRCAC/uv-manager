---
slug: trampoline-ignores-platform-override
title: Trampolines resolve the platform key the wrapper actually uses
kind: fix
appetite: small
status: in_progress
branch: fix/trampoline-ignores-platform-override
base: main
current_phase: P2
last_updated: '2026-08-08'
phases:
- id: P1
  name: Trampolines honor UVM_PLATFORM, with the coupling recorded and the docs that
    go stale
  status: done
  satisfies:
  - R1
  - R2
  - R3
  - R4
  - R5
  - R6
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: .agents/factory/bin/lint.sh && .agents/factory/bin/temp_root.sh --arch x86_64-glibc2.28
    sh -c 'set -e; K=x86_64-glibc2.28; N=$(uname -m); mkdir -p "$UVM_ROOT/$K/bin/shims"
    "$UVM_ROOT/$N/bin/shims"; for p in "$K OVERRIDE" "$N NATIVE"; do set -- $p; f="$UVM_ROOT/$1/bin/shims/ruff";
    echo "#!/bin/sh" > "$f"; echo "echo $2" >> "$f"; chmod +x "$f"; done; uvm trampolines
    >/dev/null 2>&1; T="$UVM_ROOT/bin/ruff"; [ "$("$T")" = OVERRIDE ]; [ "$(UVM_PLATFORM=$N
    "$T")" = NATIVE ]; [ "$(env -u UVM_PLATFORM "$T")" = NATIVE ]; UVM_PLATFORM=ppc64le
    "$T" 2>&1 | grep -q "architecture .ppc64le."; ! grep -q "$K" "$T"; ! grep -q "$N"
    "$T"' && /bin/sh -c '! grep -qE "re-resolves? .uname -m.|.uname -m. (at exec time|when
    invoked)" README.md share/modulefiles/uv/main.lua bin/uv-manager'
- id: P2
  name: 'Discretionary: the per-node caution and the troubleshooting entry'
  status: pending
  satisfies: []
  depends_on:
  - P1
  parallel: false
  hammerable: true
  hill: downhill
  verify: .agents/factory/bin/lint.sh && /bin/sh -c 'grep -A6 "^# Override the architecture
    key" etc/uv-manager.conf.example | grep -q "executing node"'
review:
  last_reviewed_commit: ''
  verdict: none
  blocked_reason: ''
  cycle: 0
---
# TECH.md — Trampolines resolve the platform key the wrapper actually uses

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/trampoline-ignores-platform-override/TECH.md`); the
per-phase checklists below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs `01`–`04`.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); [`invariants.md`](../../.agents/factory/invariants.md) is the
  footgun checklist. §1 and §9 are the ones this cycle lives in.
- One phase per `uvm-build` invocation; one atomic commit containing both the code and the `TECH.md`
  state change. Subjects follow `[fix] Build trampoline-ignores-platform-override P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids (`R1`, `P2`) in `bin/uv-manager` or `README.md`.
- **`PLAN.md` §5 corrects `GOAL.md` Q3.** Shaping recorded that no documentation line goes stale;
  five do. Build against the plan.

---

## Phase P1 — Trampolines honor `UVM_PLATFORM`
**Satisfies:** R1, R2, R3, R4, R5, R6 · **Depends on:** —
**Goal:** the generated trampoline resolves the same platform key `uvm_init` does, the coupling is
legible at both sites, and every sentence the change invalidates moves with it. This is the whole
contract; P2 adds nothing the GOAL requires.

- [x] `bin/uv-manager:476` — `a=\$(uname -m)` becomes `a=\${UVM_PLATFORM:-\$(uname -m)}`. Both
      backslashes are required: the heredoc delimiter is unquoted, and they are what defer evaluation
      to the trampoline's runtime instead of the generator's. `:-` and not `-`, matching
      `uvm_init:145`, so an exported-but-empty value falls back to `uname -m` at both sites.
- [x] Nothing else in `uvm_trampolines` changes — not the union scan, the `uvm_tramp_marker` ownership
      test, the temp-write-and-`mv`, or the orphan sweep.
- [x] Coupling comment at the platform-key banner (`bin/uv-manager:130`–`142`) and at the trampoline
      banner (`:425`–`435`): these two expressions resolve the same key and must move together;
      when they disagree the tool is installed in one tree and looked for in another, and every
      trampoline exits 127 naming a key the wrapper never used. Declarative, the *why* not the what,
      no restatement of the line below.
- [x] Retire the five stale trampoline descriptions — say *platform key* where the text says
      `uname -m`: `bin/uv-manager:431`, `README.md:261`, `README.md:455`,
      `share/modulefiles/uv/main.lua:24`, `:122`. `README.md:345` § *The platform key* already owns
      the term. Leave every site listed as correct in [`research/04`](research/04-doc-surface.md)
      alone — in particular the `uvm_help` heredoc and the `README.md` variable table, which describe
      the variable rather than the trampoline.
- **Verify:** `lint.sh`, then a `--arch x86_64-glibc2.28` drive asserting: the trampoline prints
  `OVERRIDE` (R1); prints `NATIVE` under the host key and under `env -u UVM_PLATFORM` (R3, and the
  two-keys-one-root half of R4); stderr names `ppc64le` when the key resolves nowhere (R2); and
  **neither key appears literally in the generated file** (R4). Then the three-file census for the
  documentation sweep. Confirmed red against the current tree, and green against a throwaway copy
  carrying only the one-line change.
- **Inspection-only, not covered by the gate:** **R5's comment quality.** The gate proves the two
  expressions match; no command decides whether a comment earns its place under `AGENTS.md`
  § *Prose and comments*. `/uvm-review` must read both sites rather than read the green.
- **Touches:** `bin/uv-manager`, `README.md`, `share/modulefiles/uv/main.lua`.

## Phase P2 — Discretionary: the per-node caution and the troubleshooting entry
**Satisfies:** — (no R-ID; `hammerable: true`) · **Depends on:** P1
**Goal:** close the documentation gap the fix creates. Neither item is in the contract, and the human
may strike this phase whole without touching the fix.

- [ ] `etc/uv-manager.conf.example`, the `UVM_PLATFORM` block: one sentence that the value must be
      evaluated on the **executing node**. The file recommends a computed value and says only that it
      must be cheap; inherited as a literal through `sbatch --export=ALL` it now sends the whole
      system — wrapper and trampolines both — into another node's tree. Rationale in
      [`research/02`](research/02-env-semantics.md); this is an addition to a file the standing bias
      says should shrink, so keep it to one sentence.
- [ ] `README.md:515` troubleshooting — decide by reading whether *"is not installed for architecture
      'aarch64'"* needs qualifying now that the quoted key can be a site override rather than a
      `uname -m` value, and that "run it on that architecture" is thin advice for an operator whose
      key encodes a glibc version. Defensible either way. **Changing nothing is an acceptable
      outcome**; record the decision in the commit body.
- **Verify:** `lint.sh`, plus the conf-example caution asserted **within the `UVM_PLATFORM` block**
  (`grep -A6` from the anchor line). The scoping is load-bearing: `"executing node"` already appears
  at `etc/uv-manager.conf.example:12`, so an unscoped census is a false green. Confirmed red against
  the current tree.
- **Inspection-only, not covered by the gate:** the `README.md:515` decision. Its correct outcome may
  be an empty diff, which no gate can distinguish from the work not being done.
- **Touches:** `etc/uv-manager.conf.example`, possibly `README.md`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative; the `current_phase`
   pointer is reconciled against them.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
