---
slug: prose-and-comment-pass
title: "Prose pass over every comment and user-facing document"
kind: refactor
appetite: small
status: planned
branch: feature/prose-and-comment-pass
base: main
current_phase: P1
last_updated: "2026-08-07"
phases:
  - id: P1
    name: "bin/uv-manager — comments and user-facing message text"
    status: pending
    satisfies: [R1, R2, R4, R5]
    depends_on: []
    parallel: false
    hammerable: false
    hill: uphill
    verify: >-
      bash -n bin/uv-manager
      && .agents/factory/bin/lint.sh
      && git show main:bin/uv-manager | grep -oE '^[a-z_]+\(\)' > "${TMPDIR:-/tmp}/uvm-fns.txt"
      && grep -oE '^[a-z_]+\(\)' bin/uv-manager | diff "${TMPDIR:-/tmp}/uvm-fns.txt" -
      && .agents/factory/bin/temp_root.sh --offline sh -c 'uv --version && readlink "$UVM_ROOT/$(uname -m)/current"' | grep -qx 'versions/9.9.9'
      && test "$(.agents/factory/bin/temp_root.sh sh -c 'unset UVM_ROOT; uvm status' 2>&1 | grep -c '^      \$')" -eq 6
      && .agents/factory/bin/temp_root.sh sh -c 'unset UVM_ROOT; uvm status' 2>&1 | grep -q 'module load uv'
      && .agents/factory/bin/temp_root.sh sh -c 'unset UVM_ROOT; uvm status' 2>&1 | grep -q 'not be your home directory'
      && test "$( (git grep -niwE '(simply|just|essentially|basically|comprehensive|robust|seamless|powerful|elegant|leverage|utilize)' -- bin/uv-manager; git grep -niE '(note that|this ensures|this allows|in order to|worth noting)' -- bin/uv-manager) | wc -l | tr -d ' ')" -eq 4
      && ! grep -q "everything's installed" bin/uv-manager
      && ! grep -q 'what tells you so' bin/uv-manager
  - id: P2
    name: "README.md"
    status: pending
    satisfies: [R1, R6]
    depends_on: [P1]
    parallel: false
    hammerable: false
    hill: uphill
    verify: >-
      .agents/factory/bin/temp_root.sh uvm status | grep -oE '^[a-z][a-zA-Z_ -]*:' | sort -u > "${TMPDIR:-/tmp}/uvm-labels.txt"
      && awk '/^\$ uv-manager status$/,/^```$/' README.md | grep -oE '^[a-z][a-zA-Z_ -]*:' | sort -u | comm -23 - "${TMPDIR:-/tmp}/uvm-labels.txt" > "${TMPDIR:-/tmp}/uvm-missing.txt"
      && test ! -s "${TMPDIR:-/tmp}/uvm-missing.txt"
      && ! git grep -niE '(note that|this ensures|this allows|in order to|worth noting)' -- README.md
      && ! git grep -niwE '(four-line|comprehensive|robust|seamless|powerful|elegant|leverage|utilize)' -- README.md
      && awk '/^\$ uv-manager status$/,/^```$/' README.md | grep -q '^invoked as:'
  - id: P3
    name: "etc/uv-manager.conf.example and share/modulefiles/uv/main.lua"
    status: pending
    satisfies: [R1]
    depends_on: []
    parallel: true
    hammerable: true
    hill: uphill
    verify: >-
      ! git grep -niE '(note that|this ensures|this allows|in order to|worth noting)' -- etc/uv-manager.conf.example share/modulefiles/uv/main.lua
      && ! grep -qE ' --( |$)' etc/uv-manager.conf.example
      && test "$(grep -c '\[\[' share/modulefiles/uv/main.lua)" -eq "$(grep -c '\]\]' share/modulefiles/uv/main.lua)"
      && grep -q 'setenv("UVM_ROOT", root)' share/modulefiles/uv/main.lua
      && ! grep -qE 'setenv\("UV_(CACHE|TOOL|PYTHON)' share/modulefiles/uv/main.lua
      && ! grep -qw 'extremely' share/modulefiles/uv/main.lua
  - id: P4
    name: "Reconciliation — counts, census, PR-body exception list, full drive set"
    status: pending
    satisfies: [R1, R3, R4]
    depends_on: [P1, P2, P3]
    parallel: false
    hammerable: false
    hill: uphill
    verify: >-
      test "$(cat bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua | wc -l | tr -d ' ')" -le 1724
      && test "$( (git grep -niwE '(simply|just|essentially|basically|comprehensive|robust|seamless|powerful|elegant|leverage|utilize)' -- bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua; git grep -niE '(note that|this ensures|this allows|in order to|worth noting)' -- bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua) | wc -l | tr -d ' ')" -eq 7
      && ! git grep -nwE '(R1|R2|R3|R4|R5|R6|P1|P2|P3|P4)' -- bin/uv-manager README.md
      && .agents/factory/bin/lint.sh
      && .agents/factory/bin/temp_root.sh --offline sh -c 'uv --version && readlink "$UVM_ROOT/$(uname -m)/current"' | grep -qx 'versions/9.9.9'
      && .agents/factory/bin/temp_root.sh --offline --arch aarch64 uvm status | grep -qE '^architecture: +aarch64$'
review:
  last_reviewed_commit: ""
  verdict: none
  blocked_reason: ""
  cycle: 0
---

# TECH.md — Prose pass over every comment and user-facing document

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/prose-and-comment-pass/TECH.md`); the per-phase
checklists below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) and
  [`research/01-baseline-output.md`](research/01-baseline-output.md), the pre-pass output every
  message-text edit is compared against.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); [`invariants.md`](../../.agents/factory/invariants.md) is the
  footgun checklist.
- One phase per `uvm-build` invocation; one atomic commit containing both the edit and the `TECH.md`
  state change. Subjects follow `[docs] Build prose-and-comment-pass P<n>: …` — `docs`, matching the
  shape commit, rather than the GOAL's `kind: refactor`, because nothing executable changes.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- **R4 binds every phase.** No executable statement, function name, variable name or exit code
  changes. Only comment lines, user-facing message text, and documentation.
- Line numbers in `PLAN.md` are as of `692adf1` and shift as edits land. Anchor on the surrounding
  text.

---

## Phase P1 — `bin/uv-manager`: comments and user-facing message text
**Satisfies:** R1, R2, R4, R5 · **Depends on:** —
**Goal:** every comment and every message string in the script reads to the `AGENTS.md` standard, with
no behavior change and no information lost from the operator-facing blocks.

Census hits:

- [ ] `:25` — delete "Note that" from the identity banner.
- [ ] `:301` — replace "Just repoint." with the reason the fast path exists: no lock, no network.
- [ ] `:512` — "is not more careful, it is more surface to drift out of date", em-dash form, matching
      the wording already in `AGENTS.md` and `invariants.md`.
- [ ] Leave the four load-bearing uses of `just` at `:136`, `:178`, `:391`, `:599`. Each means *merely*
      or *equally*; record them for P4's PR-body list.

Factual and grammatical defects:

- [ ] `:333`–`:334` — replace `four lines of "everything's installed!"` with "four lines of installer
      chatter". `AGENTS.md` bans exclamation marks in source.
- [ ] `:783`–`:784` — "because they are what tells you so" → "because they are what tell you how to
      configure it."

Restatements (R2):

- [ ] `:361` — delete "Decide whether provisioning is needed, then do it."; keep the pin paragraph.
- [ ] `:559` — delete `# ignore other flags` from the `-*)` arm.

Message blocks (R5) — audit, do not restructure:

- [ ] Read the four heredocs (`uvm_self_update` help, `uvm_status`, `uvm_clean`, `uvm_help`) and the
      inline `die`/`note` strings against `AGENTS.md` § *Prose and comments*.
- [ ] The `uvm_resolve_root` failure block keeps all six candidates with their per-candidate reason,
      both fixes, and the home-directory constraint. Compare wording against
      [`research/01-baseline-output.md`](research/01-baseline-output.md) §B.
- [ ] Do not convert any `printf` block to a heredoc. That is an executable change and R4 forbids it;
      the digest records that the EPIPE concern behind it does not reproduce.

Read the remaining ~198 comment lines for restatement and length. Most will pass untouched.

- **Verify:** the gate runs `bash -n`, `lint.sh`, a diff of the ordered `^name()` definitions against
  `main`, an `--offline` provision asserting `current -> versions/9.9.9`, and three assertions on the
  no-root failure block (six candidate lines, `module load uv`, the home-directory warning).
- **Inspection-only, not covered by the gate:** R2. There is no grep for a comment that paraphrases
  its own code, and the gate is shaped by the mechanical items above. `/uvm-review` must read the
  comment diff rather than trust the green.
- **Touches:** `bin/uv-manager`.

## Phase P2 — `README.md`
**Satisfies:** R1, R6 · **Depends on:** P1
**Goal:** all 570 lines audited in place, with the one verified factual error corrected and the quoted
sample output true to a live drive.

- [ ] `:448` — "Each is a four-line `sh` script" is wrong; a generated trampoline is thirteen lines
      ([`research/01-baseline-output.md`](research/01-baseline-output.md) §E). Use "short" rather than
      a number that will drift against the heredoc again.
- [ ] `:346` — delete "Note that".
- [ ] `:466` — "using `uv` to just-in-time provision" → "using `uv` to provision a matching environment
      on demand".
- [ ] `:141` — "7ms" → "7 ms", matching `AGENTS.md`.
- [ ] `:280` — unwrap the mid-sentence aside in "If compute nodes lack outbound HTTPS, and it is worth
      verifying rather than assuming, do this once…".
- [ ] `:13`–`:19` — add the `invoked as:` line the sample drops from the middle of the block, between
      `uv-manager:` and `architecture:`. Settled at the planning gate; see `PLAN.md` §2. Use a
      deployment path, not a sandbox one: `uvm  (/apps/external/uv/main/bin/uvm)`.
- [ ] Leave the two load-bearing uses of `just` at `:267` and `:394`; record them for P4.
- [ ] Read the remaining sections, including *Design notes*, for restatement and length. No new
      sections, no reordering, no table-to-prose conversion.

- **Verify:** every field label quoted in the sample block must appear in a live `uvm status` drive
  (subset test, so the abridgement stays legal); no phrase-census hits remain in `README.md`; the
  "four-line" claim is gone.
- **Touches:** `README.md`.

## Phase P3 — `etc/uv-manager.conf.example` and `share/modulefiles/uv/main.lua`
**Satisfies:** R1 · **Depends on:** —
**Goal:** the two site-facing example files read to the same standard, and their explanations of
architecture neutrality still match what the script does.

- [ ] `conf.example:130` — delete "Note that".
- [ ] `conf.example:37` — "Purdue Anvil. Note RCAC's own guidance points…" → drop the "Note".
- [ ] `conf.example` — normalize the five ASCII ` -- ` dashes (`:11`, `:56`, `:79`, `:95`, `:147`) to
      the em-dash the file's own title line and the rest of the repository use.
- [ ] `main.lua:50` — "uv is an extremely fast Python package and project manager" → drop "extremely".
      Settled at the planning gate; see `PLAN.md` §2.
- [ ] `main.lua:144` — leave "not just storage location"; record it for P4.
- [ ] Re-read `main.lua:10`–`:28` and `:131`–`:158` against the script: the design note and the
      "deliberately NOT set" list must still name what `uvm_set_paths` actually exports.

- **Verify:** no phrase-census hits in either file; no ASCII ` -- ` dash left in the conf example;
  `main.lua`'s `[[`/`]]` long-bracket strings stay balanced (a mangled `]]` breaks every user's
  `module load`); `UVM_ROOT` is still the only state variable the modulefile sets and no
  architecture-bearing `UV_*` path has appeared in it.
- **Note:** `luac -p share/modulefiles/uv/main.lua` is a stronger check and is worth running by hand
  if `lua` is on your PATH. It is not in the gate, because it is not present on every machine and a
  gate that fails for environmental reasons teaches people to ignore gates.
- **Touches:** `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`.

## Phase P4 — Reconciliation
**Satisfies:** R1, R3, R4 · **Depends on:** P1, P2, P3
**Goal:** the contract-level numbers hold, and the surviving census hits are written down where R1
requires them.

- [ ] Re-run both census commands over the four spelled-out paths. Expect exactly 7 hits. Spell the
      paths out: a shell that does not word-split an unquoted variable turns the pathspec into one
      nonexistent path and git reports clean.
- [ ] Write the seven survivors, each with its reason, into `spec/prose-and-comment-pass/META.md` or a
      scratch note that `/uvm-publish` lifts into the PR body. R1 requires the list to reach the PR.
- [ ] Confirm the aggregate line count has not increased above 1724.
- [ ] Drive the full GOAL R4 set and compare against
      [`research/01-baseline-output.md`](research/01-baseline-output.md): `uvm status`,
      `--offline uv --version`, `--offline --arch aarch64 uvm status`, plus the no-root failure block.
- [ ] Confirm no feature-scoped spec id leaked into the script or the README.

- **Verify:** aggregate `<= 1724`; census total exactly 7; no spec ids; `lint.sh`; `--offline`
  provisioning lands `current -> versions/9.9.9`; `--offline --arch aarch64 uvm status` still reports
  `architecture: aarch64`.
- **Inspection-only, not covered by the gate:** whether the PR-body exception list was actually
  written, and whether the surviving hits are the seven `PLAN.md` predicted rather than seven
  different ones.
- **Touches:** `spec/prose-and-comment-pass/`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[docs]` commit; stop and report.
