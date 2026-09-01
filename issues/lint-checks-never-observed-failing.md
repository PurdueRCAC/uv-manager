---
status: unshaped
kind: fix
appetite: small
lane: public
---

# The static gate's own checks are never required to be observed failing

> **Portable harness seed.** This file describes a gap in the factory itself, not in any one
> project's code, and is written to be dropped into any repository carrying the `.agents/`
> software factory. Each project should **confirm it applies here before adopting it** — the
> confirmation procedure is in *Problem* below and takes about five minutes. Where this file says
> `lint.sh`, read "whatever this project's static gate is called"; where it says `{prefix}-harness`,
> read this project's harness skill.

## Problem

The factory is emphatic that a gate must be watched failing before it is trusted. `{prefix}-build`
Step 4 requires a new or retuned `verify:` to be run through `run_verify.py` and **confirmed red
before the fix and green after**, on the stated grounds that *a gate never observed failing is not a
gate*. `{prefix}-harness` Step 6 applies the same rule to the offline fixture's invariant assertions:
a change there "must also be shown to still fire — invoke the fixture directly with the leak present
and confirm it exits 90."

The one thing that rule is **not** applied to is `lint.sh`'s own checks. The `{prefix}-harness`
Step 6 row for `bin/lint.sh` asks only that `lint.sh` be run — that is, that it still exits 0 on a
clean tree. **A check that can never fail satisfies that requirement perfectly.** Nothing in the
harness ever asks a `lint.sh` check to demonstrate it can go red, so a check that silently matches
nothing is indistinguishable from a check that passes, for as long as it exists.

This matters more for `lint.sh` than for any single `verify:`, because `lint.sh` is the gate the
other gates lean on: it is cited in `verify:` strings, run by `{prefix}-harness` after every
`.agents/` edit, and in projects with no test suite it is the only standing static signal.

**Evidence (from a fresh port of this harness to a Python project).** Nine `lint.sh` checks were
written and all nine reported green. Run against a deliberately broken tree, **two of the nine could
never have fired**:

- A convention census iterated `git ls-files`, which lists only **tracked** files. A source file
  created and not yet staged was invisible to it — and before the commit is precisely when the gate
  earns its keep. Fix: `git ls-files --cached --others --exclude-standard`, and `git grep --untracked`.
- A pattern used `\b` for word boundaries. `\b` is a GNU extension; git's POSIX `-E` engine matches
  nothing with it. The check reported clean against a file literally containing the string it was
  written to forbid. Fix: spell the boundary out, `(^|[^A-Za-z0-9_])…([^A-Za-z0-9_]|$)`.

Both passed the "run `lint.sh`, it is green" bar unchanged. Both were found only by breaking the tree
on purpose and re-running.

**This project already knows the second failure mode in one place and has not generalized it.**
`.agents/factory/bin/temp_root.sh` carries a comment explaining that `\?` is a GNU extension "BSD sed
matches nothing with it, which would disable the whole scrub on macOS while every gate stayed green."
That is the identical mechanism, reasoned about once, at one call site, as prose — with nothing
stopping the next author from reintroducing it three lines away.

**Confirm before adopting.** This is a procedural gap, so it is present by default; the question is
only whether it has bitten yet. In this repository:

1. Read the `{prefix}-harness` Step 6 row for `bin/lint.sh`. If it says only "run `lint.sh`", the gap
   is present.
2. For each check in `lint.sh`, construct the smallest tree edit that *should* make it fail, apply it,
   and run `lint.sh`. Revert. Any check that stays green is a live instance, not a hypothetical.
3. Pay particular attention to checks that (a) enumerate files through `git ls-files` or `git grep`
   without `--others`/`--untracked`, (b) use `\b`, `\?`, `\+`, `\d`, or `\s` in a `git grep -E`,
   `grep` or `sed` pattern, or (c) assert the **absence** of something — an absence check reports
   success both when the tree is clean and when the check is broken.

## Why it was deferred

Harness work: it changes `.agents/`, which only the human-gated `{prefix}-harness` may apply. It is
also not urgent in any single project — the cost is silent and accrues over time, one unfireable
check at a time — which is exactly why it needs a file rather than a good intention.

## Outcome / vision

Adding or rewriting a `lint.sh` check requires the same evidence as adding a `verify:` gate: the
check is shown red against a deliberately broken tree, and green against a clean one. Ideally the red
case is recorded rather than improvised, so it can be re-run whenever the check is touched again.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion. Prefer EARS phrasing (see
[`ears.md`](../.agents/factory/ears.md)).

- **R1** — WHEN a check is added to or rewritten in `lint.sh`, `{prefix}-harness` SHALL require that
  check to be demonstrated failing against a deliberately broken tree before the change is committed,
  matching the requirement that already exists for the fixture's invariant assertions.
- **R2** — WHERE a `lint.sh` check enumerates files, it SHALL include untracked-but-not-ignored files
  (`git ls-files --cached --others --exclude-standard`, `git grep --untracked`), because a gate that
  only sees the index cannot speak to the working tree it is being run on.
- **R3** — WHERE a check's pattern is handed to `git grep -E`, POSIX `grep`, or `sed`, it SHALL avoid
  GNU-only escapes (`\b`, `\?`, `\+`, `\d`, `\s`); the portability note now scattered in
  `temp_root.sh` SHALL move somewhere every author of a pattern will read.
- **R4** — WHEN `lint.sh` runs, it SHALL report the number of items each census-style check actually
  examined, so a check that silently matched nothing is visible as a zero rather than as a pass.

A candidate for the shaping conversation, deliberately **not** assumed here: a `lint.sh --self-test`
mode that applies each recorded breakage to a scratch copy of the tree and asserts the corresponding
check fires. It makes R1 mechanical instead of procedural, at the cost of a fixture per check —
worth it where `lint.sh` substitutes for a test suite, probably not where it supplements one.

## Notes

- **Same family as** the `portability.md` rule that an injected `` !`cmd` `` must exit 0. Both are
  mechanisms whose failure mode is *silence*: nothing looks wrong, and the absence of a signal reads
  as the absence of a problem. R4 is the general antidote — make the quiet path say a number.
- Found by: porting the factory into a new project (`rcac-docs-mcp`), where the checks were rewritten
  from scratch for a Python repository and the rewrite made the gap immediately visible. The two
  concrete bugs were in the **new** checks and are **not** present in this repository's current
  `lint.sh`, whose checks target specific named files rather than performing a census. The gap this
  seed describes is procedural and bites on the next check added or rewritten.
- Related: `{prefix}-harness` Step 6 (post-apply verification matrix), `{prefix}-build` Step 4
  (`run_verify.py`, red-before-green), `.agents/factory/bin/temp_root.sh` (the BSD/GNU `sed` note).
