# GOAL — Prose pass over every comment and user-facing document

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** prose-and-comment-pass
- **kind:** refactor
- **appetite:** small

## Problem

Deployed centrally, this script sits under every user's `uv` and under automation nobody is watching.
An operator evaluating it for that position reads the prose before they read the logic, and prose is
where provenance shows. Padding, hedging and marketing adjectives are a recognizable tic; a reader who
notices one stops evaluating the code and starts evaluating where it came from. For a script that is
otherwise correct, that is a bad trade.

`AGENTS.md` § *Prose and comments* now writes the standard down — declarative statements, the *why*
rather than the what, concrete failure modes, no filler, no restatements of the adjacent line. The
standard was written after most of the text it governs, and nothing has yet audited that text against
it. The surface is 1724 lines: 848 in `bin/uv-manager` (200 of them comments, plus four heredoc blocks
at `bin/uv-manager:566`, `:605`, `:740`, `:752` and the inline error messages), 570 in `README.md`, 148
in `etc/uv-manager.conf.example`, 158 in `share/modulefiles/uv/main.lua`.

The prose is largely good — it was written to this standard before the standard existed. A census of
the banned vocabulary across those four files returns 13 hits. That number sets the shape of the work:
this is an audit for drift and for length, not a rewrite, and a pass that produces a large diff has
misunderstood itself.

## Outcome / vision

Every comment and user-facing document in the repository reads as though one careful engineer wrote
it, and nothing in it triggers the "this was generated" reflex. Shorter than it is now. The script
still does exactly what it did before.

## Acceptance criteria (the contract)

- **R1** — The filler and marketing vocabulary banned by `AGENTS.md` § *Prose and comments* SHALL NOT
  appear in filler position in `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`, or
  `share/modulefiles/uv/main.lua`. *Checked by the text of the repository,* with `F` standing for those
  four paths:

  ```
  git grep -niwE '(simply|just|essentially|basically|comprehensive|robust|seamless|powerful|elegant|leverage|utilize)' -- F
  git grep -niE  '(note that|this ensures|this allows|in order to|worth noting)' -- F
  ```

  Use `-w`, not `\b`: git's regex engine does not implement `\b`, and the pattern that contains it
  matches nothing and reports clean. The baseline is 13 hits, 10 from the first command and 3 from the
  second. A word used load-bearingly is not a violation — most of the ten are the construction "not
  just X" — so the criterion is not "zero hits". Every surviving hit SHALL be listed in the PR body
  with the reason it stays.

- **R2** — No comment in `bin/uv-manager` SHALL paraphrase the statement it sits above. Each SHALL
  state an invariant, a constraint, a failure mode, or a rejected alternative. *This criterion is
  graded by reading, not by a command* — there is no grep for a restatement. The post-pass file carries
  roughly 200 comment lines, which a reviewer can read in one sitting, and the diff makes the removals
  explicit.

- **R3** — The aggregate line count of the four in-scope files SHALL NOT increase. It is 1724 before
  the pass. *Checked by:*
  `cat bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua | wc -l`.
  Individual files may grow if others shrink to pay for it.

- **R4** — Behavior SHALL be unchanged. `.agents/factory/bin/lint.sh` SHALL pass, and
  `temp_root.sh uvm status`, `temp_root.sh --offline uv --version` and
  `temp_root.sh --offline --arch aarch64 uvm status` SHALL each reach the same post-conditions they
  reach on `main` — same exit status, same `current` target, same version string. The diff SHALL touch
  only comment lines, user-facing message text, and documentation: no executable statement, function
  name, variable name, or exit code changes.

- **R5** — The wrapper's user-facing message blocks — the four heredocs and the inline error and
  diagnostic strings — SHALL be audited to the same standard as the comments, and SHALL lose no
  information a stuck operator needs. Specifically, WHEN no state root resolves, the failure block
  SHALL still name every candidate the wrapper tried and why each one failed. *Observable from a
  sandbox drive* with `UVM_ROOT` and every scratch candidate unset: the message on stderr is compared
  against the same drive on `main`.

- **R6** — IF the pass changes the text or field layout of `uvm status` output, THEN the sample output
  quoted at `README.md:12`–`18` SHALL be updated in the same commit, per the same-commit rule in
  `AGENTS.md`. *Checked by:* diffing that block against a real `temp_root.sh uvm status` drive.

## Non-goals (no-gos)

- **`.agents/` is out of scope** — `AGENTS.md`, `.agents/factory/*.md`, the skills, and the templates.
  A further 1013 lines, agent-facing rather than user-facing, and written most recently and under
  these rules. Excluding it is what keeps the appetite small.
- **No prose linter.** Committing a script or CI check that enforces the vocabulary is additive
  tooling, and the standing bias here is to delete rather than add. If the pass finds the manual audit
  painful enough to want one, that is a seed for `issues/`, not part of this cycle.
- **No information architecture changes to `README.md`.** No new sections, no reordering, no splitting
  the file. Auditing the text in place is the work; deciding the document should be shaped differently
  is a different cycle.
- **No new documentation.** This pass does not fill gaps it discovers. A missing explanation is a
  finding to record, not to write — R3 would have to be paid for out of text that is already earning
  its place.
- **No conversion between tables and prose in either direction.** `AGENTS.md` says tables are for
  reference material and prose is for reasoning; re-adjudicating existing choices against that line is
  scope this appetite cannot hold.
- **`spec/`, `issues/` and `ROADMAP.md` prose is not audited.** They are working records, not
  published documentation.

## Clarifications

- **Q:** How much of `README.md` is in scope, given that its later sections are reference material
  where density is a feature? — **A:** All 570 lines. The census found only four banned-vocabulary hits
  in the whole file, so the reference sections are cheap to audit and will mostly pass untouched;
  skipping them means the next reader has to re-ask the question (resolved 2026-08-07).
- **Q:** Is the agent-facing documentation in scope? The seed's *Outcome* says "every comment and
  document in the repository," but its criteria sketch names only the four user-facing files. —
  **A:** Out of scope, recorded as a non-goal above. The seed's criteria sketch wins over its Outcome
  sentence (resolved 2026-08-07).
- **Q:** Is R3's line-count guard per-file or aggregate? — **A:** Aggregate, following the seed's own
  reasoning that a section which genuinely needs more explanation is paid for by another losing it
  (resolved 2026-08-07).

## Related materials

- Seed: [`issues/prose-and-comment-pass.md`](../../issues/prose-and-comment-pass.md)
- The standard being applied: `AGENTS.md` § *Prose and comments*
- The same-commit rule that R6 enforces: `AGENTS.md` § *Environment & working rules*
- `README.md` § *Design notes* — the record of what has already been rejected, and itself in scope
