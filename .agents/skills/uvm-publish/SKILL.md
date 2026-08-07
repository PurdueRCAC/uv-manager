---
name: uvm-publish
description: >-
  Land an approved uv-manager feature branch on main. Default: push the branch and open a squash PR
  with a rich, artifact-linked body (Summary/Goal/Design/Research/Phases/Verification). Alternative
  (local): squash-merge into main locally and delete the branch. Confirms before any irreversible or
  outward step. Final step of the software factory.
disable-model-invocation: true
argument-hint: "[pr (default) | local] [merge]"
allowed-tools: Read, Grep, Glob, AskUserQuestion, Bash(uv run *), Bash(.agents/factory/bin/*), Bash(git status *), Bash(git branch *), Bash(git log *), Bash(git diff *), Bash(git rev-parse *), Bash(git fetch *), Bash(git pull *), Bash(git push *), Bash(git switch *), Bash(git merge *), Bash(git add *), Bash(git commit *), Bash(gh pr *), Bash(gh repo *), Bash(head *)
---

# uvm-publish — ship the branch to main

## When to Use

Invoke `/uvm-publish` once `/uvm-review` has approved the branch (`TECH.md`
`review.verdict: approved`). This is the **one irreversible step** — remote pushes and PRs cannot be
checkpointed — so it always confirms with you before acting. The default is a PR to `main`; `local`
does a local squash-merge.

**Harness portability.** Runs on any harness — see [`portability.md`](../../factory/portability.md).
Run the *Current state* commands yourself if not auto-injected; ask in plain text and STOP if
`AskUserQuestion` is unavailable. `gh` and `git` are portable shell.

## User Instructions

Additional instructions provided with the invocation: $ARGUMENTS

## Current state (injected at load)

- Branch: !`git branch --show-current`
- Verdict / kind / slug: resolved in **Step 1** from `spec/{slug}/TECH.md` (a load-time injection cannot strip the branch prefix to form `{slug}`).
- Commits vs main: !`git log --oneline main..HEAD 2>/dev/null | head -n 30`
- Default remote branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "(gh unavailable)"`

## Argument Parsing

- `local` / `no fuss` → squash-merge into `main` locally, delete the branch, no remote PR.
- `pr` (default) → push the branch and open a PR to `main`.
- `merge` → after opening the PR, also `gh pr merge --squash`. Only with explicit confirmation.

## Safety Principles

- **Base is `main`.** There is no `develop` in this repository.
- **Require a *current* approved review.** If `TECH.md` `review.verdict` is not `approved`, STOP and
  report; proceed only on explicit human override. Approval is pinned to
  `review.last_reviewed_commit`: any later commit touching anything **outside `spec/`** invalidates it
  (the review's own artifact commit and meta-notes do not). The Step 1 staleness gate checks this
  mechanically.
- **Confirm before irreversible or outward actions.** Always confirm the mode, PR title and body with
  the human before `git push`, `gh pr create`, or a local merge.
- **Squash, always.** The PR title becomes the squash commit subject on `main`, so the **PR title is
  `[category] Imperative summary`** (category = `TECH.md` `kind`) — **never Conventional Commits**
  (`feat:`/`fix:`). The GitHub repository currently also permits merge and rebase; do not use them.
- **Link, do not quote.** The PR body references artifacts via SHA-pinned blob permalinks, not pasted
  copies.
- Keep the `Co-Authored-By` trailer on commits. PR **bodies** end with the Claude Code generation
  line.

## Procedure

### Step 0 — status (when requested)
Report the verdict, commits vs `main`, and whether a PR already exists (`gh pr status`). Stop.

### Step 1 — Pre-flight
1. On a feature/fix branch, clean tree. Resolve `{slug}` from the branch, then read `kind`, the review
   `verdict`, and `review.last_reviewed_commit` from `spec/{slug}/TECH.md`. STOP if the verdict is not
   `approved`, unless the human overrides.
2. **Staleness gate:** `git diff --stat {last_reviewed_commit}..HEAD -- . ':(exclude)spec/'` must be
   empty. Non-empty means code changed after the approved review — STOP and send back to
   `/uvm-review`. Proceed only on an explicit human override, recorded in the PR body.
3. **Final gate.** Run `.agents/factory/bin/lint.sh` once more on the head commit. It is seconds, and
   it is the last chance to catch a broken script before a squash lands on `main`. Red → STOP.
4. `git fetch origin`. Confirm `main` is reachable and note if the branch is behind it; squash-merge
   tolerates drift, but flag a large one.

### Step 2 — Compose the PR title and body
- **Title:** `[{kind}] {imperative summary}`, synthesized from `GOAL.md` — not a copy of it.
- **Body** (sectioned; link artifacts as
  `https://github.com/PurdueRCAC/uv-manager/blob/{head_sha}/spec/{slug}/<file>`, using the current
  `git rev-parse HEAD`):
  - **Summary** — a high-level description of the whole change. Say what was **removed** as well as
    added.
  - **Goal** → link `GOAL.md`.
  - **Design** → link `PLAN.md`.
  - **Research** → links to `research/*.md`, if present.
  - **Phases completed** → rendered from the `TECH.md` FSM (id · name · satisfies).
  - **Verification** → the gates and sandbox drives actually run, with the post-conditions observed,
    taken from `REVIEW.md`. Name anything taken on trust because it needs a real cluster.
  - **User-facing surface** → confirm the same-commit rule was honored: `uvm_help`, `README.md`,
    `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`, as applicable. Say "none affected"
    when that is true.
  - **Harness feedback** — surface the self-improvement loop *only when substantial*, per the rule
    below; omit the section entirely otherwise.
  - Issue: `Closes #NN` when there is one. Because this PR targets the default branch, GitHub will
    close it on merge.
  - Trailing line: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

**Harness-feedback surfacing rule.** Before finalizing the body, read this feature's harness notes:
```
uv run .agents/factory/bin/meta_status.py spec/{slug}/META.md --status open
```
Add a terse, factual, **toolchain-only** "Harness feedback" section when there is something
substantial: `counts.open > 0` (list each open finding as `F# · {severity} · {title}`), **or**
`spec/{slug}/META.md` has a non-empty "What worked well" section — read the file directly for that,
since the parser only enumerates `F#` findings. Keep it short and process-focused; it is reviewed
alongside the code, so it must not editorialize about the feature. If there are no open findings and
nothing worked-well of note, or the file is absent (`exists: false`), **omit the section**.
`uvm-publish` never *writes* `META.md` findings; it is the loop's surfacer, and `/uvm-harness` is
where fixes get applied.

### Step 3 — Confirm with the human
Present the mode (PR or local), the title, and the body via `AskUserQuestion`. Do not proceed without
a choice.

Once confirmed, stamp the FSM terminal so the retained record does not read `in_review` forever:
```
uv run .agents/factory/bin/set_phase.py spec/{slug}/TECH.md --top-status done --touch
git add spec/{slug}/TECH.md && git commit -m "[{category}] Mark {slug} roadmap done"
```
A spec-only commit; the Step 1 staleness gate ignores it by design.

### Step 4a — PR (default)
```
git push -u origin {branch}
gh pr create --base main --head {branch} --title "{title}" --body-file <(...)
```
Report the PR URL. If `merge` was requested and confirmed, squash with an **explicit** subject and
body so none of the intermediate branch commit subjects leak into the `main` commit — a bare
`gh pr merge --squash` concatenates every branch commit message into the squash body:
```
gh pr merge {N} --squash --subject "{title}" --body "{one-line summary, or empty}" --delete-branch
```

### Step 4b — local (`local`)
```
git switch main && git pull --ff-only
git merge --squash {branch}
git commit -m "{title}"     # keep the Co-Authored-By trailer
git branch -D {branch}
```
Do **not** push `main` unless the human explicitly asks.

### Step 5 — Report
The PR URL or local merge result, the squash subject that landed, the retained `spec/{slug}/`
artifacts, and whether a release is warranted (`/uvm-release`) — a user-visible behavior change
usually is, since sites deploy by `git clone` of a tag or branch.

## Notes

- `spec/{slug}/` is **retained** on merge: the immutable dated design record. The PR body may label
  PLAN and research as historical.
- This skill does not bump the version or tag. That is `/uvm-release`.
- Sites deploy this repository by cloning it, so what lands on `main` is what a site can pick up.
  `git clone` and `rsync -a` preserve the `bin/` symlinks; a `cp -r` without `-a` does not. That is
  the operator's problem, but it is worth remembering before recommending a deployment step in a PR
  body.
