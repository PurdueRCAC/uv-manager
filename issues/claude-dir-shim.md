---
status: unshaped
kind: refactor
appetite: small
lane: public
---

# `.claude` is a symlink, so no agent can create a worktree

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

`.claude` is a committed symlink to `.agents` (git mode `120000`, confirmed by
`git ls-files -s .claude`), which is how Claude Code finds the factory's skills and settings without
a second copy of them. That arrangement is deliberate and `AGENTS.md:3-5` documents it.

It also makes worktree isolation unavailable to every agent working here. Claude Code puts a
requested worktree under `.claude/worktrees/<name>` and refuses to traverse a symlinked `.claude` at
all:

```
Cannot create worktree: /…/uv-manager/.claude is a symlink. A repository-committed
symlink at .claude, .claude/worktrees, or .claude/worktrees/<name> could redirect
worktree creation outside the repository. Remove the symlink and retry.
```

The refusal is sound — a committed symlink at any of those three paths could redirect writes outside
the repository, and the tool cannot tell this one from a hostile one. The consequence is that an
agent asking for `isolation: 'worktree'` **dies** rather than degrading, which is how this was found.

Someone already anticipated the destination: `.gitignore` carries `.agents/worktrees/`, the path a
worktree would land on *through* the symlink. Nothing ever reaches it.

**What is actually lost is small, which is why this is a seed and not a fix.** Worktree isolation
matters when several agents mutate files in parallel, and this repository is one bash script with
`parallel: false` on every phase for exactly that reason. The workaround — copy the tree to `/tmp`
and work there — is what two probes did successfully during the `lock-ownership-and-hold-time`
disposition. The cost is a hard failure instead of a graceful one, and having to remember to tell
each agent not to ask.

## Why it was deferred

Found out of cycle, during a disposition workflow for `lock-ownership-and-hold-time` — one of four
probe agents requested worktree isolation and died on this. It has no bearing on the lock work, and
folding a repository-layout change into a `fix` branch already twenty-three commits deep and carrying
an overridden human-sign-off gate would have been scope creep of the plainest kind.

It also touches `AGENTS.md`'s own description of the layout and `.gitignore`, so it wants its own
`harness`-category commit where a reader can see the whole move at once.

Pre-existing on `main`: yes. `.claude` has been a symlink since the factory landed.

## Outcome / vision

`.agents/` stays canonical and tool-neutral. `.claude/` becomes a real directory holding nothing but
symlinks back into it, plus whatever Claude-Code-specific runtime state the tool wants to write —
which is the honest shape for a per-tool compatibility shim, and better matches the stated intent
("Guidance for coding agents (Claude Code and others)") than aliasing the entire directory does.

```
.agents/            factory/  skills/  settings.json        # canonical
.claude/            factory -> ../.agents/factory
                    skills  -> ../.agents/skills
                    settings.json -> ../.agents/settings.json
                    worktrees/                              # real, gitignored
```

An agent that asks for worktree isolation gets one. Nothing else about how the factory is found
changes.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — WHEN an agent requests worktree isolation in this repository, the harness SHALL create the
  worktree rather than refuse it.
- **R2** — `.agents/` SHALL remain the canonical location of the factory, and every top-level entry
  in it SHALL be reachable through `.claude/` at the path Claude Code expects. Skills, settings and
  the factory scripts SHALL load exactly as they do today.
- **R3** — IF `.agents/` gains a top-level entry with no `.claude/` counterpart, THEN
  `.agents/factory/bin/lint.sh` SHALL fail naming it. This is the whole cost of the change: one
  symlink becomes three, and three drift where one cannot. Note the existing check at
  `.agents/factory/bin/lint.sh:90-108` covers `bin/{uv,uvx,uvm}` only — this is a **new** check
  modeled on that loop, not an extension of it.
- **R4** — Claude Code runtime state SHALL be gitignored at its new paths (`.claude/worktrees/`,
  `.claude/settings.local.json`), and the stale `.agents/worktrees/` entry removed.
- **R5** — `AGENTS.md:3-5` SHALL describe the layout that exists, in the same commit.

**Verify before committing to the design:** that Claude Code resolves a *symlinked* `.claude/skills`.
It resolves a symlinked `.claude` today — that is how these skills load — but one level deeper is an
assumption, and the whole shape depends on it. Cheap to test: make the change on a scratch branch and
check the skill list.

## Notes

- **Rejected: invert it** — make `.claude/` real and canonical with `.agents` the symlink. It fixes
  worktrees just as well and needs no drift check, but it privileges one tool in a repository whose
  operating manual is explicitly addressed to "Claude Code and others", and `AGENTS.md`/`agents.md`
  is the convention with reach beyond one vendor.
- **Rejected: do nothing.** Defensible — `/tmp` copies work, and this repository rarely needs
  parallel file-mutating agents. Rejected because the failure mode is a dead agent rather than a
  degraded one, and because the fix is roughly fifteen minutes.
- Small enough that it can ride along with any adjacent `harness` commit rather than taking a cycle
  of its own; the `/uvm-harness` sibling is the natural owner if one is running anyway.
- Related: [`issues/factory-onboarding-guide.md`](factory-onboarding-guide.md) — the other factory
  item in this index, and the precedent for harness work living in `issues/` rather than a `META.md`,
  which is scoped to skill-instruction defects.
- Found by: an out-of-cycle disposition workflow during `lock-ownership-and-hold-time`, 2026-08-26.
