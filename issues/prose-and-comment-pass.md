---
status: unshaped
kind: refactor
appetite: small
lane: public
---

# Prose pass over every comment and document

## Problem

This is potentially load-bearing infrastructure for a computing center, and infrastructure has to be
taken seriously before it is adopted. Overly verbose prose works against that. The padding, hedging and
marketing adjectives that generated text tends toward are a recognizable tic, and a reader who notices
it stops evaluating the code and starts evaluating where it came from — which is a bad trade for a
script that is otherwise correct.

The voice rules are now written down in `AGENTS.md` § *Prose and comments* — declarative statements,
the *why* rather than the what, concrete failure modes, no filler, no marketing adjectives, no emoji,
no restatements of the adjacent line. What has not happened is a pass applying them to the text that
already exists: 848 lines of `bin/uv-manager` comments, 563 lines of `README.md`, the
`etc/uv-manager.conf.example` commentary, and the modulefile's design notes.

The existing prose is largely good — it was written to that standard before the standard was written
down. The pass is therefore an audit for drift and for length, not a rewrite.

## Why it was deferred

Recorded during the harness port. Doing it before the voice rules existed would have been arguing from
taste; doing it before the `UVM_*` rename would mean editing sentences that are about to change
anyway. It should follow `uvm-env-prefix`.

## Outcome / vision

Every comment and document in the repository reads as though one careful engineer wrote it, and
nothing in it triggers the "this was generated" reflex. Shorter than it is now.

## Sketch of the acceptance criteria

- **R1** — No comment in `bin/uv-manager` SHALL restate what the adjacent line does; each SHALL state
  an invariant, a constraint, or a rejected alternative.
- **R2** — The banned vocabulary in `AGENTS.md` § *Prose and comments* SHALL NOT appear in
  `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`, or `share/modulefiles/uv/main.lua`.
- **R3** — WHEN the pass is complete, the total comment and documentation line count SHALL NOT have
  increased.
- **R4** — Behavior SHALL be unchanged: `git diff` SHALL touch only comments, strings shown to users,
  and documentation, and `.agents/factory/bin/lint.sh` plus the standard sandbox drives SHALL pass
  unchanged.

## Notes

- R3 is the honest guard against a "polish" pass that adds words. If a section genuinely needs more
  explanation, another has to lose it.
- Worth deciding during shaping whether `README.md` is in scope in full, or only the sections a reader
  hits first. It is 563 lines and its later sections are reference material, where density is a
  feature.
- The `uvm_help` heredoc and the wrapper's error messages are user-facing strings, not comments. They
  are in scope and are the highest-value target: the "cannot determine where to keep per-user uv state"
  block is the first thing a stuck operator reads.
- Found by: the maintainer, ahead of the second post-harness cycle.
