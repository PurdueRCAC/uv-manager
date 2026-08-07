---
name: uvm-plan
description: >-
  Turn a shaped spec/{slug}/GOAL.md into a design and a phased roadmap. Runs an invariant gate against
  AGENTS.md, fans out read-only research subagents (scaled to appetite; codebase- and uv-docs-first),
  synthesizes spec/{slug}/PLAN.md, re-checks invariants, and generates spec/{slug}/TECH.md — the phased
  YAML FSM driven by /uvm-build. Second step of the software-factory lifecycle (see
  .agents/factory/methodology.md).
disable-model-invocation: true
argument-hint: "[appetite small|big] [skip research] [status]"
allowed-tools: Read, Write, Edit, Grep, Glob, Agent, AskUserQuestion, WebSearch, WebFetch, Bash(git status *), Bash(git branch *), Bash(git rev-parse *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(uv run *), Bash(.agents/factory/bin/*), Bash(bash -n *), Bash(ls *), Bash(head *)
---

# uvm-plan — research → PLAN → TECH

## When to Use

Invoke `/uvm-plan` after `/uvm-feature` has landed a quality `GOAL.md` on a feature/fix branch. It
produces the design (`PLAN.md`), optional backing `research/`, and the phased FSM (`TECH.md`), then
stops for your sign-off before `/uvm-build` touches code. Depth scales to the GOAL's `appetite`.

Reference: [`methodology.md`](../../factory/methodology.md),
[`invariants.md`](../../factory/invariants.md) (the gate), and the templates
[`PLAN.md`](../../factory/templates/PLAN.md) / [`TECH.md`](../../factory/templates/TECH.md).

**Harness portability.** Runs on any harness — see [`portability.md`](../../factory/portability.md).
Fallbacks: if the *Current state* block is not auto-injected, run those commands yourself in Step 1;
ask in plain text and STOP if `AskUserQuestion` is unavailable; and **if subagents are unavailable, do
the research fan-out sequentially yourself** (Step 3 gives the fallback).

## User Instructions

Additional instructions provided with the invocation: $ARGUMENTS

## Current state (injected at load)

- Branch: !`git branch --show-current`
- Tree: !`git status --porcelain | head -n 20`
- Spec artifacts: !`ls -1 spec/*/ 2>/dev/null | head -n 40`

## Argument Parsing

- `skip research` / `no research` → collapse to a lean plan (no fan-out) regardless of appetite.
- `appetite small|big` → override the GOAL's appetite for this planning run.
- `status` / `report` → summarize what artifacts already exist for this slug and what is missing; no
  work.

## Safety Principles

- **On a feature/fix branch, never `main`.** Derive `{slug}` = branch minus its `feature/`|`fix/`
  prefix. STOP if on the base branch or the tree is dirty.
- **`GOAL.md` must exist, be committed, and carry no unresolved `[NEEDS CLARIFICATION]` markers.** If
  markers remain, STOP and send the human back to `/uvm-feature`.
- **Research is strictly read-only.** Bias it to three sources in this order: the script itself,
  `README.md` § *Design notes* (the record of rejected alternatives), and `uv`'s own documentation or
  source. Reach for the web only for genuinely external unknowns — Astral's installer behavior, an
  open `astral-sh/uv` issue, a filesystem semantic.
- **Never build.** No edits to `bin/uv-manager`. That is `/uvm-build`.
- **The invariant gate is mandatory**, at both checkpoints. Any bend gets recorded in PLAN's deviation
  table, never applied silently.

## Procedure

### Step 1 — Pre-flight & load
1. Confirm feature/fix branch and clean tree; resolve `{slug}`.
2. Read `spec/{slug}/GOAL.md` (appetite, R-IDs, non-goals) and
   [`invariants.md`](../../factory/invariants.md).

### Step 2 — Invariant gate #1 (pre-research sanity)
Given the GOAL's intent, list the invariant sections (§1–§12) this change will touch and confirm the
intent is even sane against them. A change to provisioning must respect the version-authoritative pin
and the lock's early-out; a change to anything a modulefile touches must respect architecture
neutrality. If the GOAL is fundamentally at odds with an invariant, STOP and escalate.

### Step 3 — Research fan-out (appetite-scaled)

- **`appetite: small` / `kind: fix` / `skip research`:** skip the fan-out. Do at most a couple of
  targeted reads yourself, and proceed to Step 4 with a lean plan; `research/` may be omitted.

  **Exception — diagnostic fixes.** When the GOAL's root cause is *unknown*, or it explicitly requests
  diagnosis, run the full fan-out regardless of `kind`/`appetite`. For such a fix the investigation
  *is* the deliverable, and skipping it yields a guess. `kind` and `appetite` are proxies for "is the
  root cause known?"; when they disagree with the GOAL, the GOAL wins.

  **Exception — high blast radius.** Run the full fan-out whenever the change is expected to touch any
  high-blast-radius region on `invariants.md`'s list (`uvm_acquire_lock`, `uvm_install`,
  `uvm_point_current`, `uvm_resolve_root`, `uvm_trampolines`, `uvm_export_env`, the dispatch tail),
  regardless of appetite. A "small" edit there still needs the exact contracts pinned before design.

  An explicit `skip research` argument stays a human override and still skips.

- **`appetite: big`:** identify the *rabbit holes* — the unknowns that could blow the appetite. In this
  project they are usually one of: a filesystem semantic that must be verified rather than assumed
  (atomic rename, `flock`, reflink, `stat` flavors); an `uv` or `install.sh` behavior that has to be
  read out of Astral's source or driven in the sandbox; a `bash` portability question between 3.2 and
  5; or a cluster behavior that cannot be reproduced locally and needs a stated assumption.

  Launch **read-only research subagents in parallel** (`Agent`), one per topic, breadth-first:
  - Each gets the topic, GOAL context, explicit scope boundaries, and the instruction to produce a
    brief of roughly one to two thousand tokens and **write it to
    `spec/{slug}/research/NN-topic.md`** — use `general-purpose` so it can write, and number `01`,
    `02`, … with distinct paths so there are no write conflicts.
  - A research agent **may** drive the script read-only through
    `.agents/factory/bin/temp_root.sh`; that is the cheapest way to answer "what does it actually do".
    It must not edit tracked files.
  - Scale count to appetite. Log what you fan out.
  - **Consume each agent's returned summary; never read its transcript sidecar** — it floods context.
    **No subagents in your harness?** Do the research yourself, sequentially, writing the same files.
- Read the returned briefs and synthesize **`spec/{slug}/research/00-digest.md`** — the consolidated
  decisions, resolving any cross-brief contradiction with a single recommendation each.

### Step 4 — Write `PLAN.md`
From the template: **Summary**; **Design** at the right altitude, naming the functions in
`bin/uv-manager` that change and what the state tree looks like afterwards; the **requirement → design
map** with every R-ID covered; **rabbit holes resolved** (link the briefs); **risks and open
questions**, including anything only a real cluster can confirm; and the **verification strategy**
that seeds each phase's `verify:` command.

State explicitly what is being **removed**. A change that only adds is worth a second look in this
repository.

### Step 5 — Invariant gate #2 (post-design)
Re-walk the touched invariant sections against the *drafted design*. Fill PLAN's deviation
justification table for anything that bends an invariant or adds complexity, naming the simpler
alternative and why it was rejected. Empty is the goal. STOP and escalate on an unavoidable conflict
with a §1–§11 invariant.

### Step 6 — Generate `TECH.md` (the FSM)
Copy the template. Author phases as **vertical slices, not horizontal layers** — each independently
verifiable end to end, ordered core-and-novel first.

**Size circuit-breaker (soft):** if the roadmap needs more than about six phases for a single 850-line
script, the scope is probably too big — pause and reconsider with the human before committing a
mega-plan.

For each phase set `id`, `name`, `satisfies` (R-IDs), `depends_on`, `parallel` (**almost always
`false`** — there is one source file, so two phases editing it are not independent; reserve `true` for
documentation-only or modulefile-only phases), `hammerable` (**false** for anything touching
`invariants.md` §1–§11), `hill: uphill`, and a real `verify:` command.

A `verify:` must name a **post-condition**, not merely exit 0. Build it from the three layers:
`bash -n`, `.agents/factory/bin/lint.sh`, and a drive under `.agents/factory/bin/temp_root.sh`
(`--offline` for anything touching provisioning, `--arch` for anything touching the architecture
split). Any change to the user-facing surface gets a phase item for the same-commit rule —
`uvm_help`, `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`.

Set top `status: planned`, `current_phase` to the first phase, and `last_updated` to today. The plan is
written but not signed off; `/uvm-build` flips the top status to `in_progress` when it completes the
first phase. Then **validate**: `uv run .agents/factory/bin/next_phase.py spec/{slug}/TECH.md` must
exit 0 and report the first phase.

### Step 7 — Meta-note (self-improvement loop · silence by default)
Before committing, reflect on the **skillset itself** — not the task, not the code. Write nothing
unless the bar is met.

**The bar (one test):** *was this the skill's fault — not mine, not the task's?* **Qualifies:** you
hand-fixed a command this skill gave (wrong flag or path, unquoted `verify:` YAML); a genuinely
ambiguous instruction; a `[NEEDS CLARIFICATION]` better guidance could have pre-empted; an
allowed-tools/step mismatch; a gate that passed or failed misleadingly. **Stay silent for:** a merely
hard task; your own error against clear guidance; a one-off content or code issue (that goes in
`PLAN.md`/`GOAL.md`); a vague preference.

If, and only if, the bar is met, record it in `spec/{slug}/META.md` — create from
[`templates/META.md`](../../factory/templates/META.md) if absent, else append. You may also add a
one-line **What worked well** note. Caps: at most three findings, terse; append "· seen again" rather
than duplicating an equivalent finding; a fix that would weaken a non-negotiable gate (the invariant
gate, the `verify:` design, an `invariants.md` item) is `severity=high` and must say so. **Records
only.** Use the next unused `F#`, always `status=open`, appended **outside** any code fence:

```markdown
## F<n> — <one-line title>
`origin=uvm-plan:<step> severity=<high|medium|low> category=<instruction|steering|tooling|template|missing-guidance> status=open target=<best-guess file>`
- **What happened:** <what the skill made you do, or fail to do>.
- **Skill cause:** <why it's the instructions' fault — not yours, not the task's>.
- **Recommended fix:** <the change to the skill/template/script>.
- **Confidence:** <high|med|low> · **Effort:** <small|medium|large>
```

Likely sources here: the research fan-out mechanics (Step 3), the invariant-gate steps, or `TECH.md`
YAML authoring.

### Step 8 — Commit
```
git add -A spec/{slug}      # PLAN.md + TECH.md, plus research/ and META.md when present
git commit -m "[{category}] Plan {slug}: design + phased roadmap"
```
`{category}` is the same category as the shape commit. Keep the `Co-Authored-By` trailer. Do not push.

### Step 9 — Report & hand off
Report the design summary, the phase list (id · name · satisfies · verify), any deviations recorded,
and open risks — especially anything that can only be confirmed on a real cluster. Sign-off gate: the
human reviews `PLAN.md` and `TECH.md`, then `/uvm-build` executes phase one. Stop.

## Examples

- `/uvm-plan` — full appetite-scaled run for the current branch's slug.
- `/uvm-plan skip research` — lean plan for a small change, no fan-out.
- `/uvm-plan status` — list existing GOAL/research/PLAN/TECH for this slug and what is missing.

## Notes

- Keep `research/` lean. Reviewers and future readers pay a tax for sprawl; keep only what informs the
  design.
- `TECH.md` is the resume ground truth for `/uvm-build`. If `next_phase.py` reports it invalid, fix it
  before committing.
- A research brief that concludes "we cannot test this locally" is a useful brief. Record the
  assumption in PLAN §5 rather than inventing a verification that does not verify anything.
