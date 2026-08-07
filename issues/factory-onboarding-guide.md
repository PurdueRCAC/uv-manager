---
status: unshaped
kind: feature
appetite: big
lane: public
---

# An onboarding guide for the factory

## Problem

The factory is now documented for an agent: `AGENTS.md` is the constitution, `methodology.md` explains
the lifecycle, and each skill carries its own operating procedure. None of that is written for a
**human meeting agentic engineering for the first time** — a research software engineer evaluating
whether any of this is credible, or an institutional reader deciding whether to fund it.

The HyperShell factory this was ported from carries such a document
(`.agents/factory/getting-started.html`, about 58 KB): a self-contained page introducing agents,
harnesses, Shape Up, and the factory from first principles. It was deliberately not ported, because it
is a substantial standalone artifact rather than an adaptation of an existing file, and writing it
against a harness that had not yet been exercised would have documented intentions instead of
practice.

## Why it was deferred

Two reasons, and the second is the important one.

It is large and independent — it explains a methodology, not this repository, so almost none of it is
a mechanical adaptation of the source.

More importantly, it should be written **after** the harness has been driven through real cycles.
Three are already queued (`uvm-env-prefix`, `prose-and-comment-pass`, `test-harness`). A guide written
now would describe the design; a guide written after those would describe what actually happened,
including where the factory got in the way. The second document is worth far more than the first to a
reader deciding whether any of this is credible, and the difference is entirely in whether it can cite
evidence.

## Outcome / vision

A single self-contained page a sceptical reader can open cold and come away understanding what the
factory is, why each guardrail exists, and what it actually produced here — with real artifacts from
this repository as the evidence.

## Sketch of the acceptance criteria

- **R1** — The guide SHALL be self-contained and readable with no prior knowledge of agentic
  engineering.
- **R2** — The guide SHALL explain each non-negotiable gate in terms of the failure it prevents, not
  in terms of process.
- **R3** — The guide SHALL cite real artifacts from this repository — committed `spec/{slug}/` records,
  real `REVIEW.md` findings, real `META.md` entries — rather than invented examples.
- **R4** — The guide SHALL state honestly what the factory did *not* catch, including any defect that
  reached `main` and was found later.
- **R5** — `/uvm-harness` Step 6 SHALL check this guide for staleness when the factory's shape changes.

## Notes

- Source to adapt: `.agents/factory/getting-started.html` in the HyperShell repository. Its structure
  is worth keeping; its examples are all HyperShell's and none of them transfer.
- R4 is the criterion that makes the document credible to the intended audience. A guide that reports
  only successes reads as marketing, which is the exact failure mode being defended against.
- `/uvm-harness` Step 6 currently has no staleness check for an onboarding page, because there is no
  page. Add it in the same cycle (R5).
- Found by: the harness port, as a deliberate scope reduction.
