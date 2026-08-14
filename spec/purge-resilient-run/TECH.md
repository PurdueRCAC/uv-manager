---
slug: purge-resilient-run
title: Stop paying for the state-directory mkdir on every invocation
kind: feature
appetite: small
status: done
branch: feature/purge-resilient-run
base: main
current_phase: done
last_updated: '2026-08-14'
phases:
- id: P1
  name: Guard the state-directory mkdir, and invert the comment defending it
  status: done
  satisfies:
  - R1
  - R2
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nif git grep -q \"rather than behind a sentinel\" -- bin/uv-manager;\
    \ then\n  echo \"FAIL: bin/uv-manager still asserts the unconditional mkdir\"\
    \ >&2; exit 1\nfi\n.agents/factory/bin/lint.sh >/dev/null\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -c '\nset -eu\nR=$(command -v mkdir); L=\"$UVM_SANDBOX/log\"; export\
    \ R L\nd=\"$UVM_SANDBOX/stub\"; \"$R\" -p \"$d\"\ncat > \"$d/mkdir\" <<\"EOS\"\
    \n#!/bin/sh\necho x >> \"$L\"\nexec \"$R\" \"$@\"\nEOS\nchmod 0755 \"$d/mkdir\"\
    ; PATH=\"$d:$PATH\"; export PATH\na=$(uname -m)\nuv --version >/dev/null 2>&1\n\
    : > \"$L\"; uv --version >/dev/null\nwarm=$(wc -l < \"$L\" | tr -d \" \")\nchmod\
    \ 0755 \"$UVM_ROOT/$a/cache\"; uv --version >/dev/null\nkeep=$(stat -c %a \"$UVM_ROOT/$a/cache\"\
    \ 2>/dev/null || stat -f %Lp \"$UVM_ROOT/$a/cache\")\nchmod 0700 \"$UVM_ROOT/$a/cache\"\
    \nrmdir \"$UVM_ROOT/$a/tools\"\n: > \"$L\"; uv --version >/dev/null\nback=$(wc\
    \ -l < \"$L\" | tr -d \" \")\nmode=$(stat -c %a \"$UVM_ROOT/$a/tools\" 2>/dev/null\
    \ || stat -f %Lp \"$UVM_ROOT/$a/tools\")\nrmdir \"$UVM_ROOT/$a/tools\"; : > \"\
    $UVM_ROOT/$a/tools\"\nset +e; uv --version >/dev/null 2>&1; frc=$?; set -e\necho\
    \ \"warm=$warm kept0755=$keep restored=$back mode=$mode file-rc=$frc\"\ntest \"\
    $warm\" -eq 0 && test \"$keep\" = 755 && test \"$back\" -ge 1 && test \"$mode\"\
    \ = 700 && test \"$frc\" -ne 0'\n"
- id: P2
  name: Correct the four documents that assert the reversed decision
  status: done
  satisfies:
  - R3
  - R4
  - R5
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nif git grep -q \"rather than behind a sentinel\" -- README.md\
    \ .agents/factory/invariants.md; then\n  echo \"FAIL: design note or invariant\
    \ still asserts the unconditional mkdir\" >&2; exit 1\nfi\nif git grep -q \"twenty-five\"\
    \ -- README.md .agents/factory/invariants.md; then\n  echo \"FAIL: depth-dependent\
    \ mkdir(2) count restated as a constant\" >&2; exit 1\nfi\nif git grep -q \"25\
    \ mkdir(2)\" -- bin/uv-manager; then\n  echo \"FAIL: depth-dependent mkdir(2)\
    \ count restated as a constant\" >&2; exit 1\nfi\nif git grep -q \"7 ms\" -- .\
    \ ':(exclude)spec/' ':(exclude)issues/purge-resilient-run.md'; then\n  echo \"\
    FAIL: stale wrapper-overhead figure outside the retired seed\" >&2; exit 1\nfi\n\
    .agents/factory/bin/lint.sh >/dev/null\n.agents/factory/bin/temp_root.sh uvm status\
    \ >/dev/null\n.agents/factory/bin/temp_root.sh --offline sh -c 'test \"$(uv --version)\"\
    \ = \"uv 9.9.9 (fixture)\" && test \"$(readlink \"$UVM_ROOT/$(uname -m)/current\"\
    )\" = versions/9.9.9'\n.agents/factory/bin/temp_root.sh --offline --arch aarch64\
    \ sh -c 'test \"$(uv --version)\" = \"uv 9.9.9 (fixture)\" && test \"$(readlink\
    \ \"$UVM_ROOT/aarch64/current\")\" = versions/9.9.9'\n.agents/factory/bin/temp_root.sh\
    \ --offline --arch aarch64 sh -c 'uvm status | grep -q \"^architecture:      \
    \    aarch64\"'"
review:
  last_reviewed_commit: 6782b0383d301473964f05eb908d5f6dafe50759
  verdict: approved
  blocked_reason: ''
  cycle: 2
---
# TECH.md — Stop paying for the state-directory `mkdir` on every invocation

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/purge-resilient-run/TECH.md`); the per-phase checklists
below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); [`invariants.md`](../../.agents/factory/invariants.md) is the footgun
  checklist. **This cycle edits `invariants.md` itself** — see P2.
- One phase per `uvm-build` invocation; one atomic commit containing both the change and the
  `TECH.md` state update. Subjects follow `[{category}] Build purge-resilient-run P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager` or `README.md`.
- **Gate-authoring rule learned in this cycle:** never write an assertion as `! cmd`. Under `set -e` a
  `!`-prefixed command neither aborts nor fails the script, so the assertion is inert. Use
  `if cmd; then echo FAIL >&2; exit 1; fi`. Both gates above do.

---

## Phase P1 — Guard the state-directory `mkdir`, and invert the comment defending it
**Satisfies:** R1, R2 · **Depends on:** —
**Goal:** the warm path stops forking and exec'ing `/bin/mkdir`, while every case in which the
unconditional call did something useful still does it.

- [x] In `uvm_export_env` (`bin/uv-manager:399-422`), wrap the existing `( umask 077; mkdir -p … )` in
      a six-way `[[ -d ]]` test. **The `if` goes outside the subshell.** Inside, the fork survives and
      about a third of the saving with it — and the gate below counts `mkdir` execs, so it cannot tell
      the two apart.
- [x] Leave the subshell's **commands** unchanged (reindented by two, which nesting forces). The parity
      case where a state path has been replaced by a regular file depends on `mkdir` still being what
      reports it, under `set -e`.
- [x] Add no mode check. `mkdir -p` does not `chmod` an existing directory today; R2 pins that.
- [x] Rewrite the comment at `:402-404`: the measurement is the warrant, and the surviving half of the
      old claim — a missing directory is still created, under `umask 077` — is stated. Do not reuse the
      phrase "rather than behind a sentinel"; the gate greps for it.
- **Verify:** the gate above. Post-conditions asserted in one drive: warm intact tree issues **0**
  `mkdir` executions (`main`: 1); a directory left at `0755` is still `0755` after an invocation; a
  removed directory is recreated at mode `700`; a state path replaced by a regular file still exits
  non-zero. On `main` this prints `warm=1 kept0755=755 restored=1 mode=700 file-rc=1` and exits 1 —
  red on exactly one clause. Proven green on a patched probe copy outside the working tree, under
  `/bin/bash` 3.2.57.
- **Inspection-only, because the gate is blind to it:** that the `if` is outside the subshell, and that
  the replacement comment earns its place under `AGENTS.md` § *Prose and comments*. `/uvm-review` must
  read both rather than trust the green.
- **Touches:** `bin/uv-manager`.

## Phase P2 — Correct the four documents that assert the reversed decision
**Satisfies:** R3, R4, R5 · **Depends on:** P1
**Goal:** no file in the repository still claims the `mkdir -p` is unconditional or that the wrapper
costs 7 ms.

- [x] `README.md:462-463` — the design note becomes the record of a rejection **reversed by
      measurement**, not a deletion. This section is where the project keeps what it turned down and
      why; removing the entry would lose that.
- [x] `.agents/factory/invariants.md:122-123` — rewrite §8's last bullet. Not optional: this file is
      what `/uvm-review` grades against, so leaving it would make the correct implementation an
      auto-CRITICAL §8 violation inside a high-blast-radius region.
- [x] `AGENTS.md:109` and `README.md:141` — replace "roughly 7 ms". State the wrapper's overhead above
      the exec'd binary as about 5 ms.
- [x] State no cluster number anywhere. Every measurement is macOS on APFS; the figure that transfers
      is the syscall reduction — one `EEXIST`-failing `mkdir(2)` per path component of every operand,
      down to six builtin tests — not the milliseconds. See `PLAN.md` §5.
- [x] Leave `ROADMAP.md` alone — already updated when the cycle was narrowed. **Amended in cycle 2:**
      `issues/` is no longer exempt; see the F2 item below.

**Cycle-2 remediation (review findings F1, F2).**

- [x] **F1** — the replacement prose stated "25 `mkdir(2)` calls" as a per-invocation constant, but GNU
      `mkdir -p` issues one per path component per operand, so the count is `6c+13` for a root of `c`
      components and 25 holds only at `c = 2`. Corrected at all three sites to the per-component rate,
      which also says the thing that transfers to a cluster: a deep scratch path costs more, not less.
      `.agents/factory/invariants.md` had additionally dropped the "under GNU coreutils" qualifier the
      other two sites carry; restored.
- [x] **F2** — R4 says "wherever it is stated", but the gate was scoped to `AGENTS.md README.md` and so
      could not see `issues/uvm-bootstrap.md:86`, a seed that `/uvm-roadmap` will **not** retire on
      merge. Corrected to 5 ms. The two hits in `issues/purge-resilient-run.md` are left: that seed is
      `adopted:` and is deleted when this cycle lands, and the retuned gate excludes it by literal
      pathspec rather than pretending it does not exist.
- **Verify:** the gate above, retuned in cycle 2 from two greps to four. The new clauses are the
  ones the findings prove were missing: no constant call-count in the script, the README or the
  invariant, and **no `7 ms` anywhere outside `spec/` and the retired seed** — the repository-wide form
  R4's "wherever it is stated" always meant. Proven red before the fix on clause 2 (the first unmet
  clause, not an incidental later one) and green after, both through `run_verify.py` so the string
  executed is the one the YAML stores, under `/bin/sh`.
- **Inspection-only:** whether the rewritten design note and invariant bullet read like the rest of the
  file. No command decides that.
- **Touches:** `README.md`, `.agents/factory/invariants.md`, `AGENTS.md`, and — from cycle 2 —
  `bin/uv-manager` (comment only) and `issues/uvm-bootstrap.md`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]`, consulting `PLAN.md` and `research/`.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file if reality diverges; STOP only on a `GOAL.md` contradiction.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one commit; stop and report.
