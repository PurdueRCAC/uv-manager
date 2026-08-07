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

## 2026-08-07 — prose-and-comment-pass F1: the ROADMAP edit was named only in the commit recipe
`decision=applied commit=2d5c897 target=.agents/skills/uvm-feature/SKILL.md`
- **Rationale:** Step 7 staged `ROADMAP.md` and Step 4 never mentioned it, so the steps followed
  literally commit an unmodified file, and the convention had to be recovered from `640e2f8` by hand.
  Moved both halves — the adoption marker and the rewritten entry body — into Step 4, with the marker
  shown as an indented example rather than described. Urgency is real: `/uvm-roadmap` now deletes
  retired entries, so the next promotion is the first with no prior example one `git log` away.

## 2026-08-07 — prose-and-comment-pass F2: the criterion-check enumeration went stale in one cycle
`decision=applied commit=d3c64ac target=.agents/factory/templates/GOAL.md`
- **Rationale:** revises `132b214` rather than reverting it. That fix named a second departure from
  sandbox-observability instead of relaxing the rule, and its "declares itself inline" principle is
  kept intact here; only the closed set of two is replaced by the rule it was standing in for. A prose
  criterion — checkable by neither a drive nor a command — was the third case, and the enumeration
  would have needed a fourth revision on the next unanticipated one. `uvm-feature` Step 4 duplicates
  the rule and moved in lockstep.

## 2026-08-07 — prose-and-comment-pass F3: a gate was never checked for being able to fail
`decision=applied commit=87473cc target=.agents/skills/uvm-plan/SKILL.md`
- **Rationale:** extends `61574ec`, whose two read-back directions (contradiction, blindness) are both
  about scope and neither catches an inert gate. Adds the control that plan time was missing: run each
  `verify:` now, and a gate asserting an undelivered post-condition must come back red. The plan-time
  analog of `c5f39f4`'s red-before/green-after at build time. Named the concrete trap — an interpolated
  pathspec collapses under `zsh` — because the abstract rule is what failed to fire.

## 2026-08-07 — prose-and-comment-pass F4: the blast-radius trigger read as adjacency, not behavior
`decision=applied commit=6966001 target=.agents/skills/uvm-plan/SKILL.md`
- **Rationale:** this **narrows a research trigger**, so it went to the human explicitly rather than on
  the finding's say-so; the exception is not an `invariants.md` item or a hard gate, so Safety §3 did
  not bind. Applied the conservative form: it still fires unless the change is *provably* confined to
  comments, message strings or documentation, and message text in a §3 or §7 region keeps a mandatory
  `research/` baseline, since a string those regions print is user-facing behavior. A future run
  proposing to drop that carve-out should treat it as a re-litigation, not a new finding.

## 2026-08-07 — prose-and-comment-pass F5: the fan-out fallback tested availability, not permission
`decision=applied commit=4fe0252 target=.agents/factory/portability.md`
- **Rationale:** subagents existed and worked; the session forbade spawning them unasked, a case the
  condition as written did not cover. Widened at all four sites (`portability.md`, `uvm-plan` twice,
  `uvm-review`) since an agent policy, cost ceiling or sandbox restriction hits every skill that fans
  out. Added that the deliverable is identical either way — without it the fallback reads as a scope
  cut, which is the reason an agent would resist taking it.

## 2026-08-07 — prose-and-comment-pass F6: two skills gave different rules for the commit category
`decision=applied commit=9228a75 target=.agents/skills/uvm-build/SKILL.md`
- **Rationale:** `uvm-build` said `kind`, `uvm-plan` said the shape commit, so a prose cycle had to
  adjudicate `[refactor]` against `[docs]`. `kind` is the lifecycle taxonomy and has no `docs` or
  `harness` member. Took the deferral option over the finding's alternative of a new `TECH.md`
  frontmatter field: the field would have meant touching `_fsm.py`'s `FIELD_ORDER`, `validate` and
  `set_phase.py` to record something already legible in the branch's first commit. `uvm-review` Step 1
  carried the same conflation and moved with it. `uvm-publish` leaves `{category}` undefined rather
  than wrong, so it was left alone — widening to it would have been scope creep past the finding.

## 2026-08-07 — prose-and-comment-pass F7: the prose exception was scoped to the diff hunk
`decision=applied commit=5dd4c7d target=.agents/factory/review-rubric.md`
- **Rationale:** hunk scoping is right for a feature cycle, where untouched prose is somebody else's
  problem and a sweeping reviewer manufactures gaps. It inverts when the prose *is* the deliverable:
  the work is defined as the lines the pass chose not to change, so grading only what moved cannot see
  an omission. The rubric now says which reading wins and keeps the anti-gap-hunting rule everywhere
  else; the `uvm-review` Safety Principles summary points at it.

## 2026-08-07 — prose-and-comment-pass F8: remediation was written as local to one phase
`decision=applied commit=1a83475 target=.agents/skills/uvm-build/SKILL.md`
- **Rationale:** a near miss, not a hypothetical — a one-word fix moved a census total from 7 to 6 and
  a `done` reconciliation phase's gate still hardcoded 7. `next_phase.py` never re-runs a gate, so a
  stale assertion in a `done` phase is invisible to the FSM and the branch ships green over a gate that
  fails on the tree it certifies. Scoped the re-run to `done` phases whose `depends_on` names the
  reopened one, rather than all of them: this factory's plans routinely end in a count-snapshotting
  phase, which is exactly the shape that breaks.

## 2026-08-07 — prose-and-comment-pass F9: the mandatory /bin/sh drive had no supported command
`decision=applied commit=2895fc1 target=.agents/factory/bin/run_verify.py`
- **Rationale:** makes `c5f39f4` executable rather than changing it. Step 4 required the drive and left
  the gate locked in folded YAML, so it was hand-reflowed twice via throwaway readers — and reflowing
  is where a quoting error enters. The empty-string guard is the load-bearing part: `/bin/sh -c ''`
  exits 0, so the first attempt's missing `pyyaml` produced an empty string that *satisfied* "confirm
  it is red". Chose a fourth script over documenting a one-liner because the false green is what needed
  to become impossible, not inconvenient. It `exec`s rather than spawning, so the gate's own status
  reaches the caller — verified at 1, 42 and 0, and the empty gate at 2.

## 2026-08-07 — prose-and-comment-pass F10: commit subjects leaked past the diff's pathspec
`decision=applied commit=b5a9826 target=.agents/skills/uvm-review/SKILL.md`
- **Rationale:** extends `a242486`, which closed the diff channel and handed the same information back
  through the log in the next clause. `severity=high`, but like its predecessor it **strengthens**
  blind-review integrity, so Safety §3's typed override did not apply. Two halves, because one pathspec
  is not enough: review-cycle commits touch only `spec/` and vanish under it, but build subjects name
  the remediated finding id, so cycle ≥ 1 drops subjects entirely. Verified by constructing a spec-only
  review commit and watching it disappear from the filtered log.

## 2026-08-07 — prose-and-comment-pass F11: a verification technique had nowhere blindness-safe to live
`decision=applied commit=65fa2c6 target=.agents/factory/review-rubric.md`
- **Rationale:** took the rubric option and **rejected the finding's alternative** of a
  blindness-safe `REVIEW.md` section paste-forwarded by Step 2. That design makes every cycle judge
  what is safe to carry across the blindness boundary, and the judgment is the risk; the rubric already
  reaches every reviewer and carries no author intent. A future run proposing the `REVIEW.md` channel
  should read this first. Added the `grep`-is-not-`grep` trap next to the `zsh` one — same class, and
  both were reproduced live while applying this run, the `zsh` one by a detection loop written for this
  very ledger entry.

## 2026-08-07 — prose-and-comment-pass: the run's own commit-subject format does not fit
`decision=applied commit=2d5c897 target=.agents/skills/uvm-harness/SKILL.md`
- **Rationale:** noted, not fixed. `uvm-harness` Step 5 prescribes
  `[harness] {summary} ({slug} F#)`, which spends 38 characters on overhead for a slug this long and
  cannot fit `AGENTS.md`'s 72-character subject limit. Two subjects were amended after the fact this
  run. Followed the repository's actual precedent instead — `61574ec`, `fef0ccc` and every prior
  harness commit omit the suffix and let this ledger carry the finding linkage. Left as an observation
  because `uvm-harness` never writes `META.md` findings (Safety §5) and a self-edit mid-run is the
  meta-on-meta the same rule forbids.
