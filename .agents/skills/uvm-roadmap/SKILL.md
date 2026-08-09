---
name: uvm-roadmap
description: >-
  Retire the deferrals whose cycles have landed, and keep ROADMAP.md true. Finds every
  issues/{slug}.md carrying status: adopted:{slug}, confirms the cycle actually reached main, and
  deletes the seed with its ROADMAP entry after a human-gated preview. Also repairs the drift a
  shipped cycle leaves behind: dangling cross-references, stale figures in surviving seeds, and
  adoption markers left by abandoned branches. Operational sibling of the lifecycle, run between
  releases (see .agents/factory/methodology.md).
disable-model-invocation: true
argument-hint: "[--dry-run] [slug] [--all] [status]"
allowed-tools: Read, Grep, Glob, Edit, Write, AskUserQuestion, Bash(git status *), Bash(git branch *), Bash(git log *), Bash(git ls-tree *), Bash(git rev-parse *), Bash(git add *), Bash(git commit *), Bash(grep *), Bash(del *), Bash(ls *), Bash(head *)
---

# uvm-roadmap — retire what shipped, keep the index true

## When to Use

Invoke `/uvm-roadmap` between releases, or any time `ROADMAP.md` has stopped describing the work that
is actually left. Its main job is the one step the lifecycle never had: a cycle seeded from an
`issues/{slug}.md` ships, and nothing retires the seed, so the backlog keeps advertising work that is
already on `main`.

This is **maintenance, not a lifecycle step.** It does not touch `bin/uv-manager`, does not read or
write `GOAL/PLAN/TECH/REVIEW`, and never advances an FSM. It edits `ROADMAP.md`, deletes seeds under
`issues/`, and — in the security lane only — moves an entry rather than deleting anything.

Deliberately **not** part of `/uvm-publish`. Retirement writes outside `spec/`, which is the one thing
publish's staleness gate is built to notice; folding it in would mean excluding `issues/` from that
gate, and `/uvm-review` legitimately grades `issues/` content. Publish reports an un-retired seed and
stops there.

Reference: [`methodology.md`](../../factory/methodology.md),
[`templates/ISSUE.md`](../../factory/templates/ISSUE.md) (the `status:` vocabulary), and `AGENTS.md`
§ *Where a deferral goes*.

**Harness portability.** Runs on any harness — see [`portability.md`](../../factory/portability.md).
Run the *Current state* commands yourself if not auto-injected; ask in plain text and STOP if
`AskUserQuestion` is unavailable.

## User Instructions

Additional instructions provided with the invocation: $ARGUMENTS

## Current state (injected at load)

- Branch: !`git branch --show-current`
- Tree: !`git status --porcelain | head -n 20`
- Adopted seeds: !`grep -rl "^status: adopted:" issues .security/issues 2>/dev/null`
- Queued entries: !`grep -c "^### " ROADMAP.md 2>/dev/null`

## Argument Parsing

- No argument → consider every adopted seed whose cycle has landed. The default.
- `<slug>` → restrict to the seed adopted by that cycle.
- `--all` → also sweep the drift checks in Step 5, not just retirement.
- `--dry-run` → run Steps 1–4 and present the preview, then STOP. No edits, no deletions, no commit.
- `status` / `report` → list adopted seeds with landed/in-flight/stale for each; no work.

## Safety Principles

- **Deleting a seed destroys the only copy outside git history.** Preview every retirement and confirm
  with the human before acting. Never delete on inference alone.
- **`del`, not `rm`.** `rm` is blocked in this environment and `del` is reversible trash. The seed is
  tracked, so follow with `git add -A` to stage the deletion; that is why this skill does not need
  `git rm`.
- **Landed means on `main`.** A seed is retired only when `git ls-tree main -- spec/{slug}` is
  non-empty. An `adopted:{slug}` marker proves a cycle *started*, never that it finished — a branch
  that bounced at review or was abandoned still carries the marker, and retiring its seed deletes the
  justification for work nobody did.
- **Never delete anything under `.security/`.** That lane is gitignored, so a deletion there leaves no
  commit and no history: the file is simply gone, and the closed finding is exactly what a later audit
  asks for. Retire it by moving its `.security/ROADMAP.md` entry to that file's terminal records, and
  keep the `.security/issues/` file. Never `git add` a path under `.security/`, and never name one in
  a commit message.
- **A GOAL is negotiated down from a seed.** Anything the cycle cut and still wants must survive
  retirement. Step 3 checks this against `GOAL.md` § *Non-goals*; it is the one failure here that
  loses work rather than leaving litter.
- **Never edit `spec/{slug}/`.** It is a dated record of what was true when written. A retired seed
  leaves a dangling `Seed:` link in `GOAL.md` § *Related materials*, and that link stays: it is the
  signpost that makes `git log --diff-filter=D -- issues/{slug}.md` a two-step recovery instead of
  archaeology. The one exception is `META.md`, the harness feedback log rather than part of the design
  record; Step 7 says when.
- **One commit per retirement**, `[harness]` category, keeping the `Co-Authored-By` trailer. Never
  push.

## Procedure

### Step 0 — status / dry-run (when requested)
`status`: classify each adopted seed and report; no work. `--dry-run`: Steps 1–4, present the preview,
STOP.

### Step 1 — Pre-flight
Clean tree; non-empty → STOP. Confirm you are on `main`; this skill does not run on a feature branch,
because a seed retired on a branch that never merges takes the backlog entry with it.

### Step 2 — Find the adopted seeds and classify each
```
grep -rl "^status: adopted:" issues .security/issues 2>/dev/null || true
```
Plain `grep`, not `git grep`: `.security/` is gitignored, and `git grep` searches tracked files only,
so it would skip that lane while appearing to work. The `|| true` is load-bearing — with `.security/`
absent `grep` exits 2 while still printing its matches, so anything branching on the exit status reads
"no adopted seeds" off a list of them. Match on the frontmatter, never on the filename —
the seed's filename and the cycle slug are different strings (`issues/trampoline-ignores-platform-override.md`
promotes to slug `trampoline-platform-override`), so a filename guess deletes nothing, or deletes the
wrong thing.

Read the `{slug}` out of each `status: adopted:{slug}` value and classify:

| `git ls-tree main -- spec/{slug}` | Meaning | Action |
|---|---|---|
| non-empty | the cycle landed | retire (Steps 3–4) |
| empty, branch exists | in flight | leave alone |
| empty, no branch | abandoned; the marker is stale | offer to reset `status:` to `shaped` or `unshaped`, never delete |

The stale case matters because `/uvm-feature` STOPs on `adopted:{other-slug}` as a collision. Left
alone, an abandoned cycle permanently bricks its own seed: it can never be promoted and its ROADMAP
entry can never be worked.

### Step 3 — Check the seed shipped whole
Read `spec/{slug}/GOAL.md` § *Non-goals* against the seed's problem statement and its sketch of the
acceptance criteria. Non-goals are the written record of what the promotion negotiated away.

Anything cut and still wanted does not die with the seed. Either rewrite the seed down to the
remainder and reset `status:` to `unshaped`, re-wording its ROADMAP entry to match, or file a fresh
seed for it. Only a seed with no live remainder is deleted.

### Step 4 — Preview, confirm, retire
Present per seed: the file to delete, the ROADMAP entry to remove, any remainder being preserved, and
the cross-references Step 5 will repair. Confirm with `AskUserQuestion`.

Then, for each confirmed public-lane seed:
```
del issues/{seed}.md
```
Remove its `### ` block from `ROADMAP.md`. Security-lane seeds are moved, not deleted, per the safety
rule above.

### Step 5 — Repair what the removal broke
Entries carry no numbers, so removing one renumbers nothing. What still breaks is prose:

- A cross-reference to the retired cycle by name (`Follows the rename`, `the same line as …`). The
  dependency is discharged, so say so rather than deleting the sentence — a reader needs to know the
  ordering constraint existed and cleared.
- A count (`Highest-value cycle of the three`, `Three are already queued`) that the retirement makes
  wrong, in `ROADMAP.md` and inside surviving seeds.
- With `--all`: figures a shipped cycle invalidated in seeds it never edited — a line count, an
  occurrence table, a file inventory. A stale baseline in a seed whose own acceptance criterion is a
  line-count guard is the one number in it that has to be right.

Do not rewrite a `Found by:` line. Those ordinals are provenance, not queue position.

### Step 6 — Commit
```
git add -A
git commit -m "[harness] Retire the {slug} seed and its roadmap entry"
```
One commit per retirement; fold Step 5's repairs into the commit that caused them. Keep the
`Co-Authored-By` trailer. Do not push.

### Step 7 — Report
Seeds retired, seeds left in flight, stale markers found and what was done about them, remainders
preserved, and cross-references repaired. Name anything you chose not to touch.

Name any **harness friction** this sweep exposed and offer to record it, on the same rule
`/uvm-release` Step 10 carries: `/uvm-harness` reads only `spec/*/META.md`, so on the human's OK it
goes to the retired cycle's `spec/{slug}/META.md` with `origin=uvm-roadmap:<step>` and `status=open`,
as its own `[harness]` commit.

## Examples

- `/uvm-roadmap` — retire every landed seed, one commit each.
- `/uvm-roadmap --dry-run` — preview the whole sweep; change nothing.
- `/uvm-roadmap uvm-env-prefix` — retire just that cycle's seed.
- `/uvm-roadmap status` — classify every adopted seed; no work.

## Notes

- `/uvm-publish` detects an un-retired seed and names it in its final report. It does not act: this
  skill is where deletion lives, so publish keeps neither an `Edit` tool nor a deletion verb.
- A seed that shipped leaves no terminal record. `ROADMAP.md` § *Terminal records* is for deferrals
  closed **without** shipping, where nothing else in the repository shows the question was asked. For
  shipped work the refutation is free: someone re-filing it greps the code and finds it already done.
- This skill never touches `bin/uv-manager`, never advances an FSM, and never tags a release.
