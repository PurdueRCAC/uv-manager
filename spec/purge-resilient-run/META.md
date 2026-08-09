# META — Repair a purged tree in place, at job scale

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/{slug}/`.

- **slug:** purge-resilient-run

## What worked well

- `uvm-feature:4`'s instruction to read the seed's `ROADMAP.md` entry alongside the issue paid off
  immediately: the entry is where "Taken first because both halves are live operational gaps" lives,
  which is what confirmed this promotion jumped no recorded ordering and turned the missing test
  harness into a clean non-goal rather than a violated dependency.

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — Free text alongside an issue path is routed as scope, with no rule for the case where it is about a different seed

`origin=uvm-feature:argument-parsing severity=medium category=instruction status=open target=.agents/skills/uvm-feature/SKILL.md`

- **What happened:** the invocation was `issues/purge-resilient-run.md` plus a sentence about a
  `UVM_INSTALL` variable that the hosted `uvm.sh` would read. Argument Parsing resolves the path to a
  promotion and then says "Everything else → the inline feature description (the seed prompt)."
  Followed literally, that folds the sentence into the purge cycle's scope. It does not belong there:
  `uvm.sh` is `issues/uvm-bootstrap.md`, the *next* roadmap entry, and absorbing it would have merged
  two `appetite: big`/`medium` cycles behind a contract no human agreed to. I caught it only because
  the remark named `uvm.sh`, which I happened to recognize from the other seed.
- **Skill cause:** the parsing rules treat the path and the free text as independent, and the "seed
  prompt" fallback is written for the *no-path* flow. When a path is given, the skill never says what
  accompanying prose means — a scope addition, a shaping hint, an appetite override, or a note that
  belongs on a different file entirely — so the only stated rule is the one that produces the wrong
  answer. Nothing directs the skill to check the remark against the *other* open issues, even though
  Step 1's injected state already lists them.
- **Recommended fix:** in Argument Parsing, add a clause for path-plus-prose: the prose is shaping
  input for the named seed, **not** an automatic scope extension, and before using it check it against
  the other entries in the injected "Open issues" list. Where it belongs to a different seed, record it
  in that seed's `## Notes` (with attribution and date) and commit it alongside the GOAL, listing the
  separation as a non-goal. Where it is genuinely ambiguous which cycle owns it, ask — merging two
  seeds is an appetite decision, not a parsing one.
- **Confidence:** high · **Effort:** small
