# Harness change log (`uvm-harness`)

The cross-job ledger of every harness self-improvement **decision** — the *act* side of the factory's
self-improvement loop. `/uvm-harness` appends one entry per **applied** and **rejected** decision (and
notable **deferred** ones), and **reads this file before applying**: a proposed fix that reverts a
recent change, or repeats a previously-rejected one, is flagged to the human rather than silently
re-applied. This is the loop's anti-thrash memory.

Findings themselves live in each feature's `spec/{slug}/META.md`; this file is the durable record of
what was *done* about them.

Entry format — one section per decision, newest at the bottom:

```markdown
## {YYYY-MM-DD} — {slug} {F#}: {one-line title}
`decision=applied|rejected|deferred commit={sha|—} target={file}`
- **Rationale:** what was changed and why it generalizes / why rejected (overfit, stale,
  would-weaken-a-gate) / why deferred.
```

Read `origin`, `severity` and `category` from the finding in `META.md`; this ledger records the
*outcome*.

---

<!-- Decisions are appended below this line by /uvm-harness. -->

## 2026-08-07 — bootstrap: factory ported from HyperShell
`decision=applied commit=— target=.agents/`
- **Rationale:** initial import, adapted from the HyperShell factory. Renamed `hs-*` → `uvm-*`; base
  branch `develop` → `main` (this repo has no git-flow split); invariants rewritten for a single bash
  script; `temp_site.sh` replaced by `temp_root.sh` plus an offline installer fixture; `lint.sh`
  added as the static gate in place of a test suite; the FSM scripts converted to PEP 723 so they run
  under `uv run` with no project environment. The `Co-Authored-By` trailer is **kept** here, unlike
  the source repo — this repository's history already records it.

## 2026-08-07 — uvm-env-prefix F1: GOAL criteria that only static inspection can check
`decision=applied commit=132b214 target=.agents/factory/templates/GOAL.md`
- **Rationale:** the sandbox-observability rule admitted one departure, for criteria needing a real
  cluster; a documentation criterion had none and got an invented out-of-band annotation instead.
  Generalizes because `AGENTS.md`'s same-commit rule puts a documentation criterion in most cycles.
  Named the second departure rather than relaxing the rule — both still declare themselves inline.

## 2026-08-07 — uvm-env-prefix F2: `planned` was an unreachable FSM state
`decision=applied commit=fef0ccc target=.agents/skills/uvm-plan/SKILL.md`
- **Rationale:** `uvm-plan` hard-coded `status: in_progress` at plan time, so `TECH.md` claimed
  building had begun for the whole duration of the sign-off gate Step 9 then enforces, and `_fsm.py`'s
  `planned` was dead. Plan writes `planned`; `/uvm-build` Step 5 flips it on the first *completed*
  phase. `in_review` is ordered to win, so a single-phase roadmap does not stop at `in_progress`.
  Touched `templates/TECH.md` in the same commit — it is the copied starting point, so leaving its
  frontmatter at `in_progress` would have silently defeated the change.

## 2026-08-07 — uvm-env-prefix F3 + F5: phase gates unchecked against their own checklists
`decision=applied commit=61574ec target=.agents/skills/uvm-plan/SKILL.md`
- **Rationale:** applied as one commit, by agreement — the two findings are the same check in opposite
  directions (a gate that contradicts a checklist item; a gate blind to one), and splitting them would
  have meant the second commit rewriting the first's sentence. Both were observed in one cycle, which
  is what carried them past the overfit test. Guidance, not a new hard rule: the fix names the two
  failure shapes and the three reconciliations, and leaves the judgment at plan time.

## 2026-08-07 — uvm-env-prefix F4: blindness stated as "do not read", evaded by grep
`decision=applied commit=a242486 target=.agents/skills/uvm-review/SKILL.md`
- **Rationale:** `severity=high` but **strengthens** blind-review integrity rather than loosening it,
  so Safety §3's typed override did not apply. The reviewer obeyed the letter and still pulled
  PLAN/TECH/research/META lines in through two recursive greps. Restated the ban as content reaching
  context and carried the diff rule's `':(exclude)spec/'` precision over to searches; both exclusion
  forms were executed against this repo before being written down. `review-rubric.md` moved in lockstep.

## 2026-08-07 — uvm-env-prefix F6: `verify:` authored in one shell, executed in another
`decision=applied commit=c5f39f4 target=.agents/skills/uvm-build/SKILL.md`
- **Rationale:** Step 4 already refused to trust exit 0 but treated the shell as neutral; a gate tested
  interactively went green where it should have been red, because the agent shell's `grep` is a
  function wrapping `ugrep`. Re-confirmed here before writing: `grep` is a shell function in this
  session and `/usr/bin/grep` under `/bin/sh`. The red-before/green-after half is the load-bearing
  part — a gate never observed failing is not a gate.

## 2026-08-07 — maintainer request: nothing retired a seed after its cycle shipped
`decision=applied commit=7d5ac9f target=.agents/skills/uvm-roadmap/SKILL.md`
- **Rationale:** raised by the maintainer, not by a `META.md` finding — the lifecycle promoted an
  `issues/{slug}.md` into a cycle and then left it in the backlog forever. Built as a third
  operational sibling rather than folded into `/uvm-publish`, which was the first design considered
  and rejected: retirement writes outside `spec/`, so publish would have had to exclude `issues/`
  from its staleness gate, and `/uvm-review` demonstrably grades `issues/` content — the F5 finding
  processed earlier the same day was a gate going green with `issues/test-harness.md` stale. Publish
  detects and reports; `/uvm-roadmap` acts. Keeping the deletion verb out of the one irreversible
  step was the secondary reason. Detection keys off `status: adopted:{slug}` rather than the
  filename, since the two differ (`issues/trampoline-ignores-platform-override.md` →
  `trampoline-platform-override`), and the trigger carries `|| true` because `grep` exits 2 while
  printing matches when the gitignored `.security/` lane is absent. The security lane inverts the
  rule and moves rather than deletes: gitignored means no history to recover from. Lifecycle prose
  moved in lockstep — `templates/ISSUE.md`, `uvm-feature`, `AGENTS.md` and `methodology.md` all
  documented retention as unconditional.

## 2026-08-07 — uvm-env-prefix: the first retirement, and the ROADMAP numbering
`decision=applied commit=5bb08e0 target=ROADMAP.md`
- **Rationale:** exercised the new step by hand on the case already sitting in the tree rather than
  waiting for the next cycle to hit it under time pressure. Dropped the `### N.` numbering in the same
  commit: an audit of what removing one entry breaks found every casualty positional (`cycle 1`,
  `of the three`, `Three are already queued`) and every by-name reference intact, so the numbers were
  manufacturing the only breakage and renumbering-on-every-retirement would have been a standing
  chore. The seed's `Seed:` link in `spec/uvm-env-prefix/GOAL.md` is deliberately left dangling —
  `spec/{slug}/` records what was true when written, and the dangling path is the signpost that makes
  `git log --diff-filter=D` a two-step recovery.
