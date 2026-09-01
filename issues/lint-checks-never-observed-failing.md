---
status: unshaped
kind: fix
appetite: small
lane: public
---

# The static gate's own checks are never required to be observed failing

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.
>
> **Originally a portable harness seed**, written to drop into any repository carrying the `.agents/`
> factory. Localized to this one and confirmed to apply on 2026-08-27 — see *Confirmed here* below.
> The portable `{prefix}`-placeholder form is this file's first committed revision (`3229b64`), which
> is what to copy when porting the factory elsewhere.
>
> **Applied by `/uvm-harness`, not by a lifecycle cycle.** The remedy changes `.agents/`, so this is
> not a `/uvm-feature` candidate despite living in `issues/`.

## Problem

The factory is emphatic that a gate must be watched failing before it is trusted. `uvm-build`
Step 4 requires a new or retuned `verify:` to be run through `run_verify.py` and **confirmed red
before the fix and green after**, on the stated grounds that *a gate never observed failing is not a
gate*. `uvm-harness` Step 6 applies the same rule to the offline fixture's invariant assertions:
a change there "must also be shown to still fire — invoke the fixture directly with the leak present
and confirm it exits 90."

The one thing that rule is **not** applied to is `lint.sh`'s own checks. The `uvm-harness`
Step 6 row for `bin/lint.sh` asks only that `lint.sh` be run — that is, that it still exits 0 on a
clean tree. **A check that can never fail satisfies that requirement perfectly.** Nothing in the
harness ever asks a `lint.sh` check to demonstrate it can go red, so a check that silently matches
nothing is indistinguishable from a check that passes, for as long as it exists.

This matters more for `lint.sh` than for any single `verify:`, because `lint.sh` is the gate the
other gates lean on: it is cited in `verify:` strings, run by `uvm-harness` after every
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

**Confirmed here, 2026-08-27.** The portable form asks each project to check three things before
adopting. Two were run; the third is the cycle's own work and is left for it.

1. **The gap is present.** `uvm-harness` Step 6 (`.agents/skills/uvm-harness/SKILL.md:149-153`)
   requires, for an edit to `bin/lint.sh`: run `lint.sh`, plus a live `temp_root.sh --offline` drive
   — and then applies the must-still-fire rule to *the fixture's invariant assertions only*. It never
   asks a `lint.sh` check to demonstrate it can go red. The asymmetry is exactly as described.
2. **No live instances found by inspection, and the check that matters was not run.** Step 3's two
   named failure modes are absent: `lint.sh` uses no GNU-only escapes, and its single `git ls-files`
   (`:96`) names three specific files rather than taking a census, so the tracked-only blindness
   cannot bite. This agrees with the Notes below. **Step 2 — breaking the tree once per check and
   confirming each goes red — was not run**, and it is the only one of the three that can find a
   check that is unfireable for a reason nobody predicted. Whoever takes this owes it first, as the
   red state for R1.
3. **The shape that is live here is an *absent* census, not a broken one.** None of the six checks
   enumerates — every one targets named files, which is why step 3's two heuristics find nothing. But
   `lint.sh` hardcodes the list of `.agents/` shell scripts **twice**, at `:46-47` for `bash -n` and
   `:74-76` for shellcheck, and it is complete today only because all three files predate it. A
   fourth script added under `.agents/` would go unchecked by both, with `lint.sh` green throughout.
   That is the same silence this seed is about, reached by omission rather than by a census that
   matches nothing, and step 3's heuristics do not look for it.

## Why it was deferred

Harness work: it changes `.agents/`, which only the human-gated `uvm-harness` may apply. It is
also not urgent in any single project — the cost is silent and accrues over time, one unfireable
check at a time — which is exactly why it needs a file rather than a good intention.

## Outcome / vision

Adding or rewriting a `lint.sh` check requires the same evidence as adding a `verify:` gate: the
check is shown red against a deliberately broken tree, and green against a clean one. Ideally the red
case is recorded rather than improvised, so it can be re-run whenever the check is touched again.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion. Prefer EARS phrasing (see
[`ears.md`](../.agents/factory/ears.md)).

- **R1** — WHEN a check is added to or rewritten in `lint.sh`, `uvm-harness` SHALL require that
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

- **R4 already has a working precedent in this repository**, which narrows it rather than blocking
  it: the skill-injection check reports `29 skill state injections all exit 0` — the count is in the
  output, so a sweep that silently found nothing would read as `0` instead of as a pass. R4 is asking
  for what that check already does, applied to the rest.
- **Same family as** the `portability.md` rule that an injected `` !`cmd` `` must exit 0. Both are
  mechanisms whose failure mode is *silence*: nothing looks wrong, and the absence of a signal reads
  as the absence of a problem. R4 is the general antidote — make the quiet path say a number.
- Found by: porting the factory into a new project (`rcac-docs-mcp`), where the checks were rewritten
  from scratch for a Python repository and the rewrite made the gap immediately visible. The two
  concrete bugs were in the **new** checks and are **not** present in this repository's current
  `lint.sh`, whose checks target specific named files rather than performing a census. The gap this
  seed describes is procedural and bites on the next check added or rewritten.
- Related: `uvm-harness` Step 6 (post-apply verification matrix), `uvm-build` Step 4
  (`run_verify.py`, red-before-green), `.agents/factory/bin/temp_root.sh` (the BSD/GNU `sed` note).
