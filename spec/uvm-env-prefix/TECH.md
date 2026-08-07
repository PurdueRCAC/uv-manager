---
slug: uvm-env-prefix
title: Rename the UV_MANAGER_* environment prefix to UVM_*
kind: refactor
appetite: small
status: in_review
branch: feature/uvm-env-prefix
base: main
current_phase: done
last_updated: '2026-08-07'
phases:
- id: P1
  name: Close the sandbox scrub gap before anything depends on it
  status: done
  satisfies:
  - R6
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: UVM_PIN=1.2.3 UV_CACHE_DIR=/nope .agents/factory/bin/temp_root.sh sh -c
    'env | grep -c ^UVM_PIN; env | grep -c ^UV_CACHE_DIR; env | grep -c ^UVM_SANDBOX'
    | paste -sd, - | grep -qx 0,0,1 && .agents/factory/bin/temp_root.sh --offline
    sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version' | grep -qF 'uv 6.6.6 (fixture)'
    && .agents/factory/bin/lint.sh >/dev/null
- id: P2
  name: Rename the six knobs in the wrapper and the sandbox that drives it
  status: done
  satisfies:
  - R1
  - R2
  - R3
  - R4
  - R5
  - R6
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: '.agents/factory/bin/lint.sh >/dev/null && .agents/factory/bin/temp_root.sh
    uvm status | grep -qF ''(from UVM_ROOT)'' && .agents/factory/bin/temp_root.sh
    uvm help | grep -c ''^  UVM_'' | grep -qx 6 && .agents/factory/bin/temp_root.sh
    sh -c ''UVM_PIN=1.2.3 uvm status'' | grep -qE ''^pin: +1[.]2[.]3$'' && UVM_PIN=9.9.9
    .agents/factory/bin/temp_root.sh uvm status | grep -qE ''^pin: +<none'' && .agents/factory/bin/temp_root.sh
    --arch testarch uvm status | grep -c ''^UV_.*/testarch/'' | grep -qx 5 && .agents/factory/bin/temp_root.sh
    sh -c ''UV_MANAGER_ROOT=$UVM_ROOT; export UV_MANAGER_ROOT; unset UVM_ROOT; uvm
    status >/dev/null 2>err; test $? -ne 0 && grep -q keep.per-user err'''
- id: P3
  name: 'Site-facing artifacts: README, conf example, modulefile'
  status: done
  satisfies:
  - R5
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: '! git grep -q UV_MANAGER_ -- README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua
    && grep -qF ''(from UVM_ROOT)'' README.md && grep -q ''setenv(.UVM_ROOT.'' share/modulefiles/uv/main.lua
    && .agents/factory/bin/temp_root.sh uvm status | grep -qE ''^state root:.*from
    UVM_ROOT'''
- id: P4
  name: Factory documents, live seeds, and the closing sweep
  status: done
  satisfies:
  - R7
  depends_on:
  - P1
  - P2
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: '! git grep -q UV_MANAGER_ -- . '':!spec/'' '':!issues/uvm-env-prefix.md''
    && git ls-files -s CLAUDE.md .claude bin/uv bin/uvx bin/uvm | grep -c ^120000
    | grep -qx 5 && .agents/factory/bin/lint.sh >/dev/null'
review:
  last_reviewed_commit: ''
  verdict: none
  blocked_reason: ''
  cycle: 0
---
# TECH.md — Rename the `UV_MANAGER_*` environment prefix to `UVM_*`

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/uvm-env-prefix/TECH.md`); the per-phase checklists below
are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs 01–05.

## Why the phases are ordered this way

`temp_root.sh` exports `UV_MANAGER_ROOT` itself, so renaming the wrapper without it breaks every
sandbox drive and nothing can be verified. The scrub widening, by contrast, is inert today — nothing
reads `UVM_*` yet — and is independently provable now. So the one genuine behavior change goes first,
alone, where its gate is unambiguous; then the rename lands with a working sandbox underneath it.

**No phase is `hammerable`.** A partially applied rename is worse than none: it leaves an operator
reading documentation that names variables the script no longer honors. There is no fat to cut here,
only an inconsistent tree.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); the footgun checklist is
  [`invariants.md`](../../.agents/factory/invariants.md).
- One phase per `uvm-build` invocation; one atomic commit with both the change and the `TECH.md` state
  update. Subjects follow `[refactor] Build uvm-env-prefix P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- **Never bulk-edit through a glob.** `sed -i` and `perl -pi` replace the path, not the inode, so a
  glob reaching `CLAUDE.md` or `.claude` turns those symlinks into regular files and `lint.sh` — which
  checks only `bin/{uv,uvx,uvm}` — still passes. Drive every bulk edit off `git grep -l`.
- Case-sensitive substitution only. There are no case variants, and 183 lowercase `uvm_` identifiers
  plus 165 `uv-manager` program-name strings that a case-insensitive pass would endanger.

---

## Phase P1 — Close the sandbox scrub gap
**Satisfies:** R6 · **Depends on:** —
**Goal:** `.agents/factory/bin/temp_root.sh` scrubs inherited `UVM_*` variables as well as `UV_*`, so
that when P2 makes the wrapper read them they cannot leak into a drive. Inert today, provable today.

- [x] Widen the pattern at `temp_root.sh:69` from `UV_` to `UVM\{0,1\}_`. **Use the POSIX interval, not
      `\?`** — `\?` is a GNU extension that matches *nothing* under BSD sed, which would silently
      disable the whole scrub on macOS while every gate stayed green.
- [x] Update the comment at `:66-68`: it describes scope ("every `UV_*` variable"), so it moves with
      the pattern. Record why the interval is spelled that way.
- [x] Add a line to the `temp_root.sh` header and the fixture header noting that fixture knobs go on
      the *inner* command — `temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'` —
      because the sandbox is hermetic by design. Provisioning is lazy, so this works.
- [x] Confirm `UVM_SANDBOX` (`:79`) and `UVM_FIXTURE_DIR` (`:86`) are still exported after the loop and
      therefore unaffected.
- **Verify:** the drive asserts three counts at once, `0,0,1` — an inherited `UVM_PIN` is gone, an
  inherited `UV_CACHE_DIR` is gone, and `UVM_SANDBOX` survives — then that an inner-command
  `UVM_FIXTURE_VERSION` still reaches the fixture (`uv 6.6.6 (fixture)`), proving the scrub did not
  overshoot. Fails on today's tree, which is what makes it a gate.
- **Touches:** `.agents/factory/bin/temp_root.sh`, `.agents/factory/fixtures/uv-install/install.sh`.

## Phase P2 — Rename the six knobs
**Satisfies:** R1, R2, R3, R4, R5 (help), R6 (drive-through) · **Depends on:** P1
**Goal:** the wrapper reads `UVM_*` and the sandbox drives it through those names. After this phase
the software is correct; everything remaining is text.

- [x] `bin/uv-manager`: rename the six reads — `uvm_resolve_root` (`:84-86`), `uvm_init` (`:145`), the
      knobs block (`:158-161`) — plus every mention in comments, the no-root failure message
      (`:103`, `:120`) and the doctor hint (`:724`).
- [x] Re-flow the `uvm_help` Environment block. `UVM_` is seven characters shorter, so a plain
      substitution leaves eight columns of dead gutter. Move descriptions to column 23 to match the
      commands block above, and split the folded `LOCK_TIMEOUT / LOCK_STALE` pair now that the names
      fit. Draft in [`research/04-docs-surface.md`](research/04-docs-surface.md).
- [x] `temp_root.sh`: rename its own three exports — `UV_MANAGER_ROOT` (`:78,80,81`),
      `UV_MANAGER_INSTALL_URL` (`:88-89`), `UV_MANAGER_PLATFORM` (`:92`) — and the `--offline`/`--arch`
      usage text.
- [x] Leave `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` alone in `uvm_fetch`/`uvm_install`.
      They are Astral's names (invariant §6); the fixture's assertion on them must keep passing.
- [x] Confirm the five exported storage variables and the three `PATH` prepends are untouched.
- **Verify:** `lint.sh`, then `status` reports `(from UVM_ROOT)`; `help` shows exactly six `^  UVM_`
  lines; `UVM_PIN` set **inside** the drive reaches the `pin:` line while `UVM_PIN` set **outside** it
  does not; `--arch testarch` puts all five `UV_*` storage paths under the arch directory; and with
  only the legacy `UV_MANAGER_ROOT` set the wrapper exits non-zero with `keep per-user` on stderr.
  The inside/outside `UVM_PIN` pair is the sharp assertion — either drive alone proves nothing.
- **Touches:** `bin/uv-manager`, `.agents/factory/bin/temp_root.sh`.

## Phase P3 — Site-facing artifacts
**Satisfies:** R5 · **Depends on:** P2
**Goal:** everything a site operator reads names the variables the script actually honors.

- [x] `README.md` (25 occurrences). Five passages are transcripts or copy-pasteable commands and must
      match real output: the sample `status` block, the modulefile excerpt, the `flock` probe
      one-liner, the `worker_init` example, and the troubleshooting paraphrase of the no-root message.
      Leave the quoted versions 0.2.0 and 0.12.2 alone — no bump this cycle.
- [x] Add the three-sentence design note to README § *Design notes* recording why the wrapper's own
      knobs are `UVM_*` while the five exported ones stay `UV_*`. Draft in
      [`research/04-docs-surface.md`](research/04-docs-surface.md); justification in PLAN's deviation
      table. Keep it to three sentences.
- [x] `etc/uv-manager.conf.example` (13). Rewrite the header sentence rather than substituting it — it
      already claims something false, that the wrapper reads *only* `UV_MANAGER_*` variables.
- [x] `share/modulefiles/uv/main.lua` (4), including the design-note comment block and the
      commented-out `setenv("UV_MANAGER_PIN", …)` example. The comment block is column-aligned: pad to
      the existing 19-wide field rather than retightening. Confirm nothing architecture-bearing moves.
- [x] Refill paragraphs that now wrap raggedly. Every affected line only shrinks, so nothing overflows.
- **Verify:** none of the three files contains `UV_MANAGER_`; README carries the literal
  `(from UVM_ROOT)`; the modulefile sets `UVM_ROOT`; and a live `status` drive prints the same origin
  line the README claims it does.
- **Touches:** `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`.

## Phase P4 — Factory documents and the sweep
**Satisfies:** R7 · **Depends on:** P1, P2, P3
**Goal:** no `UV_MANAGER_` remains anywhere outside the three historical records, and the repository's
symlinks survived the bulk editing.

- [x] Normative factory documents: `AGENTS.md` (7), `.agents/factory/invariants.md` (6),
      `methodology.md` (3), `ears.md` (2), `review-rubric.md` (1), and the three `SKILL.md` files (1
      each). `AGENTS.md:73` and `:203` describe the scrub's *scope*, not just its names, so they change
      with P1's behavior rather than by substitution.
- [x] `.agents/factory/templates/TECH.md:29` — a `verify:` example. Left stale it seeds a broken
      command into every future TECH.md.
- [x] Live seeds: `issues/trampoline-ignores-platform-override.md` (13, including a runnable repro at
      `:29-33`) and `issues/test-harness.md` (2). Both describe future work; a stale seed misleads the
      cycle that promotes it.
- [x] `ROADMAP.md` — **hand-edit, do not substitute.** Entry 1 argues that `UV_MANAGER_*` is wrong
      *because* it sits in `uv`'s namespace; substituting turns it into an argument against itself.
- [x] Leave the three historical records untouched: `issues/uvm-env-prefix.md` and
      `spec/uvm-env-prefix/{GOAL,META}.md`. They describe what was true when written.
- **Verify:** `git grep UV_MANAGER_` outside `spec/` and `issues/uvm-env-prefix.md` returns nothing;
  all five tracked symlinks (`CLAUDE.md`, `.claude`, `bin/{uv,uvx,uvm}`) are still mode `120000`;
  `lint.sh` green. The symlink count is the guard `lint.sh` does not provide.
- **Touches:** `AGENTS.md`, `.agents/factory/**`, `.agents/skills/**`, `issues/*.md`, `ROADMAP.md`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `feature/uvm-env-prefix`, `main` reachable.
3. Execute every `[ ]`, consulting [`PLAN.md`](PLAN.md) and [`research/`](research/) for detail.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file if reality diverges — regenerate frontmatter with `set_phase.py` and note it in the
   commit body. STOP only on a `GOAL.md` contradiction.
6. Mark done, advance, `--touch`, one `[refactor]` commit, stop and report.
