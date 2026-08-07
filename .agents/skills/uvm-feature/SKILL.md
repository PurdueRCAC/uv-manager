---
name: uvm-feature
description: >-
  Start a new uv-manager feature/fix/refactor from a clean main branch. Safety-checks the tree,
  derives a {slug}, creates feature/{slug} or fix/{slug}, ingests an inline prompt, an untracked
  GOAL.md, or an issues/{slug}.md deferral, and refines it into spec/{slug}/GOAL.md — appetite,
  non-goals, EARS acceptance criteria with stable R-IDs, resolved clarifications. Shaping only: no
  deep research, no big code reads. First step of the spec-driven software factory (see
  .agents/factory/methodology.md).
disable-model-invocation: true
argument-hint: "<inline feature description> | spec/<slug>/GOAL.md | issues/<slug>.md [fix|refactor] [appetite small|big]"
allowed-tools: Read, Write, Edit, Grep, Glob, AskUserQuestion, Bash(git status *), Bash(git branch *), Bash(git switch *), Bash(git rev-parse *), Bash(git fetch *), Bash(git add *), Bash(git commit *), Bash(git log *), Bash(git ls-files *), Bash(head *)
---

# uvm-feature — shape the goal

## When to Use

Invoke `/uvm-feature` on a clean `main` to begin a new unit of work. It produces exactly one artifact
— a refined `spec/{slug}/GOAL.md` on a fresh branch — and stops for your sign-off before the expensive
`/uvm-plan` step. This is **shaping** in the Shape Up sense: make the goal coherent, bounded and
unambiguous, but leave design freedom for the plan. Do **not** research or read a lot of code here.

Reference, loaded only if needed: [`methodology.md`](../../factory/methodology.md),
[`ears.md`](../../factory/ears.md), and the template
[`templates/GOAL.md`](../../factory/templates/GOAL.md).

**Harness portability.** These skills run on any harness, not only Claude Code — see
[`portability.md`](../../factory/portability.md). Here the Claude-specific affordances degrade
gracefully: if the *Current state* block below is not auto-injected, run those commands yourself in
Step 1; if `AskUserQuestion` is unavailable, ask in plain text and STOP. Everything else is portable
shell.

## User Instructions

Additional instructions provided with the invocation: $ARGUMENTS

## Current state (injected at load)

- Branch: !`git branch --show-current`
- Tree: !`git status --porcelain | head -n 20`
- Untracked GOAL.md files: !`git ls-files --others --exclude-standard 'spec/**/GOAL.md'`
- Open issues: !`git ls-files 'issues/*.md'`

## Argument Parsing

Parse `$ARGUMENTS` case-insensitively. If self-contradictory, STOP and ask.

- A path matching `spec/<slug>/GOAL.md` → **adopt that file** as the seed; `{slug}` comes from the
  path. This is the "I hand-wrote a GOAL.md" flow.
- A path matching `issues/<slug>.md` (or `.security/issues/<slug>.md`) → **promote that issue**.
  `{slug}` is the file stem; its frontmatter supplies `kind` and `appetite` unless the invocation
  overrides them. A bare `{slug}` naming an existing `issues/{slug}.md` resolves the same way. See
  "Promoting an issue" in Step 4.
- `fix` / `bug` / `refactor` → set `kind`; otherwise infer from the wording, defaulting to `feature`.
- `appetite small` / `appetite big` → set appetite; else default `small` for `kind: fix`, `big` for
  `feature`/`refactor`.
- Everything else → the inline feature description (the seed prompt).
- No arguments **and** no untracked `spec/*/GOAL.md` present → STOP and ask for a description or a
  GOAL.md path.

## Safety Principles

- **On `main`, otherwise-clean tree.** If the injected branch is not `main`, STOP — do not auto-switch
  or stash. The tree must be clean **except** the untracked `spec/{slug}/GOAL.md` you are adopting
  when a path was given; any *other* modified or untracked file → STOP.
- **Never overwrite a tracked GOAL.** If `spec/{slug}/` already exists **in git**, or the target branch
  already exists, STOP and report a collision. Adopting an *untracked* hand-written
  `spec/{slug}/GOAL.md` at an explicit path is the intended flow, not a collision.
- **Branch mapping:** `kind: fix` → `fix/{slug}`; `kind: feature|refactor` → `feature/{slug}`.
- **Never guess.** On any ambiguity in scope or requirements, emit a literal
  `[NEEDS CLARIFICATION: …]` marker in GOAL.md and ask the human. Record answers in the Clarifications
  section. Do not invent behavior.
- **Shaping only.** No research fan-out, no broad code exploration, no implementation. If you feel the
  urge to research, that is `/uvm-plan`'s job.
- **Size circuit-breaker (soft).** If shaping produces more than roughly 8–10 acceptance criteria, or
  several distinct deliverables, the appetite is probably too big — pause and offer the human a pilot
  plus follow-ups split, recording the deferred scope in Non-goals. A prompt, not a hard limit.
- **Bias toward the smallest surface.** This is one 850-line script that a site operator has to read
  in a sitting. A new subcommand, environment variable, or fallback costs more than its
  implementation. Before shaping something additive, check `README.md` § *Design notes* — it is the
  record of what was already considered and rejected. If the GOAL is re-proposing one of those, say so
  and make the human confirm.

## Procedure

### Step 1 — Pre-flight
1. Confirm on `main` with an otherwise-clean tree. The **only** permitted pending change is the
   untracked `spec/{slug}/GOAL.md` being adopted in the path-given flow. Any other dirty or untracked
   file → STOP (commit, stash, or discard first).
2. `git fetch origin || true`; if `main` is behind, note it. Not fatal.

### Step 2 — Resolve slug, kind, appetite
1. If a `spec/<slug>/GOAL.md` path was given, use it. Otherwise derive a concise kebab `{slug}` of
   about five words or fewer from the description; if it is not obviously good, propose it and
   confirm.
2. Resolve `kind` and `appetite` per Argument Parsing.
3. Check collisions: `git rev-parse --verify {branch}` must fail (branch absent), and `spec/{slug}/`
   must not be tracked. STOP on collision.

### Step 3 — Create the branch
`git switch -c {branch} main`, where `{branch}` is `fix/{slug}` or `feature/{slug}`.

### Step 4 — Write / refine `spec/{slug}/GOAL.md`
Start from the template. Fill **Problem** (the raw need — motivate, do not design), **Outcome**,
**Acceptance criteria** as R-IDs (`R1`, `R2`, …) nudged toward EARS, **Non-goals**, **Clarifications**
(with any `[NEEDS CLARIFICATION]` markers resolved), and **Related materials**. Record `slug`, `kind`
and `appetite` in the header.

Every criterion must be observable from a sandbox drive under
`.agents/factory/bin/temp_root.sh` — an exit status, a path, a symlink target, a line on stderr, an
environment variable in the child process. If a criterion genuinely requires a real cluster, say so in
the criterion itself so the reviewer knows it is being taken on trust rather than assuming it was
checked.

If adopting a hand-written GOAL.md, refine it **in place**: preserve the author's intent, and only
disambiguate, structure, and add R-IDs, appetite and non-goals. Do not expand scope.

**For `kind: fix`, phrase criteria as the observable broken→fixed behavior the user sees** — never the
suspected cause or mechanism, which is unverified until `/uvm-plan` root-causes it. A criterion pinned
to a wrong diagnosis has to be reinterpreted mid-lifecycle.

**Promoting an issue.** A deferral recorded earlier arrives pre-shaped — Problem, why it was deferred,
draft R-IDs — and its body mirrors this template, so promotion is a move-and-fill. It is still a
*candidate*: **do not copy it into `GOAL.md` verbatim.** Read its `status:` first.

- **`unshaped`** — nobody has agreed an appetite, non-goals, or a final contract. That negotiation is
  this step's job, and skipping it hands `uvm-review` a contract no human ever accepted. Carry the
  evidence (`bin/uv-manager:NNN`, the mechanism, whether the defect is **pre-existing**) into
  **Problem**, and treat the draft R-IDs as input, not as the contract.
- **`shaped`** — the shaping conversation already happened with a human. Do **not** re-litigate it.
  Re-confirm the scope still holds against current `main`, cite anything that has drifted since it was
  written, surface that for sign-off, and adopt it largely as written. What this step performs is
  *acceptance into a cycle*.
- **`adopted:{other-slug}`** — already promoted. STOP and report the collision.
- **`declined` / `accepted-behaviour`** — terminal records, not candidates. STOP and show the human
  the recorded reasoning before doing anything.

When the GOAL lands, leave the `issues/` file in place and set its `status:` to `adopted:{slug}` so
the `ROADMAP.md` index does not dangle. Commit that edit alongside the GOAL.

An issue promoted out of `.security/issues/` keeps its evidence in the hidden lane: the public
`GOAL.md` states the **observable hardening outcome** and points at `.security/` for detail. It never
republishes an attack mechanism for a weakness that is still live.

### Step 5 — Coherence self-check
Re-read the GOAL. Is it solved, bounded to the appetite, and free of unresolved markers? Is every
requirement testable and observable? If not, iterate with the human before committing.

### Step 6 — Meta-note (self-improvement loop · silence by default)
Before committing, reflect on the **skillset itself** — not the task, not the code. Write nothing
unless the bar is met.

**The bar (one test):** *was this the skill's fault — not mine, not the task's?* **Qualifies:** you
hand-fixed a command this skill gave (wrong flag or path, unquoted YAML); a genuinely ambiguous
instruction; a `[NEEDS CLARIFICATION]` better guidance could have pre-empted; an allowed-tools/step
mismatch; a gate that passed or failed misleadingly. **Stay silent for:** a merely hard task; your own
error against clear guidance; a one-off content or code issue (that goes in `GOAL.md`, not here); a
vague preference.

If, and only if, the bar is met, record it in `spec/{slug}/META.md` — create it from
[`templates/META.md`](../../factory/templates/META.md) if absent, else append. You may also add a
one-line **What worked well** note when part of this skill materially helped. Caps: **at most three
findings**, terse; if an equivalent finding already exists, append "· seen again" rather than
duplicating; a fix that would weaken a non-negotiable gate (`lint.sh`, the sandbox drive, an
`invariants.md` item) is `severity=high` and must say so. **Records only** — `/uvm-harness` applies
fixes later, human-reviewed. Use the next unused `F#`, always write `status=open`, and append the
finding as a section **outside** any code fence:

```markdown
## F<n> — <one-line title>
`origin=uvm-feature:<step> severity=<high|medium|low> category=<instruction|steering|tooling|template|missing-guidance> status=open target=<best-guess file>`
- **What happened:** <what the skill made you do, or fail to do>.
- **Skill cause:** <why it's the instructions' fault — not yours, not the task's>.
- **Recommended fix:** <the change to the skill/template/script>.
- **Confidence:** <high|med|low> · **Effort:** <small|medium|large>
```

`uvm-feature` is shaping-only, so findings here are usually about ambiguous shaping guidance or the
`GOAL.md` template.

### Step 7 — Commit
```
git add spec/{slug}/GOAL.md          # add spec/{slug}/META.md too if you recorded a meta-note
git add issues/{slug}.md ROADMAP.md  # only when promoting: status -> adopted:{slug}
git commit -m "[{category}] Shape {slug} goal"
```
`{category}` is the `AGENTS.md` commit category matching the work — normally `{kind}` itself
(`fix`|`feature`|`refactor`), or a more specific category such as `docs` when the GOAL is really that
kind of change. Never collapse everything non-`fix` to `feature`. Keep the `Co-Authored-By` trailer.
Do not push.

### Step 8 — Report & hand off
Report the branch, slug, kind, appetite, the R-ID list, and any open clarifications. Tell the human
the sign-off gate: review `spec/{slug}/GOAL.md`, then run **`/uvm-plan`**. Stop.

## Examples

- `/uvm-feature make the trampolines honor UV_MANAGER_PLATFORM` — infer `feature`, derive slug
  `trampoline-platform-override`, create the branch, shape the GOAL.
- `/uvm-feature issues/trampoline-ignores-platform-override.md` — promote the recorded deferral: shape
  its draft R-IDs into a contract, then flip the issue to `status: adopted:{slug}`.
- `/uvm-feature fix the provisioning lock is not released when the node is preempted` — `kind: fix`,
  appetite small, branch `fix/{slug}`.
- `/uvm-feature spec/doctor-record-check/GOAL.md` — adopt the hand-written GOAL and refine in place.

## Notes

- This skill never researches, edits the script, or pushes. That is `/uvm-plan`, `/uvm-build`,
  `/uvm-publish`.
- If a requirement cannot be made unambiguous with the human right now, leave the
  `[NEEDS CLARIFICATION]` marker in place and STOP — an ambiguous GOAL blocks `/uvm-plan`.
- Some `git` mutations may prompt for permission depending on your `settings.local.json`. That is
  expected and safe.
