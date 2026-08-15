# META — `uvm doctor` reports OK on the damage it exists to find

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/{slug}/`.
>
> **Silence is the default.** The bar for a finding is one test: *was this the **skill's** fault — not
> mine, not the task's?* A merely hard task, a self-inflicted error, or a one-off code issue that
> belongs in `GOAL.md` or `REVIEW.md` is **not** a finding. The blind `uvm-review` correctness reviewer
> never reads this file; it would leak author intent.

- **slug:** doctor-detection-gaps

## What worked well

- `uvm-feature` Step 4's rule that a deferring non-goal is only a promise if it lands in the named
  file caught a real gap: writing R3c into `issues/test-harness.md` surfaced that two of this cycle's
  criteria resist the obvious test, which would otherwise have been discovered by whoever writes the
  suite.
- `uvm-plan` Step 6's requirement to run every `verify:` against the current tree and confirm it dies
  on the asserted post-condition caught **two** false greens in this cycle — a `sed` fixture mutation
  that silently matched nothing, and a `git grep` anchor that wraps across lines. Both would have
  shipped as green gates. This step earns its cost; do not soften it.
- Writing P3's gate from R4's *Checked by* clause verbatim — the whole command, `uvm doctor | head -1`,
  rather than the block the design happened to be changing — caught a design gap the plan had missed:
  the pipe closes after the *first finding*, so converting only the remediation block left the leak in
  place. A gate scoped to the design would have gone green over it. This is the argument for F4's fix.
- `uvm-review`'s instruction to hand the reviewer the *command* that produces the diff rather than the
  diff itself paid off unexpectedly: the reviewer used the same repo to extract
  `git show main:bin/uv-manager` into `$TMPDIR` and drive both walks against one fixture tree, which is
  the only honest way to grade R5's equality claim. A pre-rendered diff would have made that reach
  awkward enough to skip.
- `uvm-build` Step 1's "prefer reopening the existing phase whose `satisfies` covers the failing
  R-IDs" landed the cycle-1 remediation in one assertion: P3's gate already built the mixed tree the
  finding described, because the gate was written from R4's *Checked by* clause rather than from the
  change. Reopening cost less than a new phase would have, and the retuned gate covers the finding
  permanently instead of once.
- The scoped cycle-2 translation — hand the reviewer a range, a graded surface, and the bare list of
  R-IDs an earlier pass covered, but never the findings — worked as designed. The reviewer re-graded
  exactly R4 and R3, declined R1/R5/R6/R7 with reasons of its own, and still found something new in
  five lines of prose. Scoping did not become a rubber stamp.
- Step 2's ban on reading `04-uv-repair-idioms.md`, paired with an instruction to establish R4's
  sub-claim by execution instead, produced a better result than the reference would have. The cycle-3
  reviewer measured all six assertions in the remediation block against real uv rather than inheriting
  them — including the orphan-accumulation behavior cycle 2 had to correct cycle 1 on. A reviewer
  handed the research file would have graded the prose against a document that was itself wrong.

## Friction findings

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — `appetite: medium` is a legal issue value with no legal GOAL translation
`origin=uvm-feature:step-2 severity=medium category=template status=applied target=.agents/factory/templates/ISSUE.md`
- **What happened:** the seed carried `appetite: medium`, which `templates/ISSUE.md:4` explicitly
  permits (`small | medium | big`), but `templates/GOAL.md:10` and `uvm-feature`'s Argument Parsing
  both admit only `small | big`. No rule anywhere says how a `medium` seed becomes a GOAL appetite, so
  promotion stalled on a question the human had to answer.
- **Skill cause:** the two templates disagree on the vocabulary of the same field across the exact
  handoff `/uvm-feature` performs. This is not a one-off: three of the six queued seeds
  (`doctor-detection-gaps`, `lock-ownership-and-hold-time`, `uvm-bootstrap`) carry `medium`, so every
  one of those promotions hits it, and each is free to translate differently — which makes
  `uvm-review`'s scope check against appetite mean different things on different cycles.
- **Recommended fix:** pick one vocabulary and make both templates say it. Either add `medium` to
  `templates/GOAL.md:10` and to `uvm-feature`'s Argument Parsing with a phase-cap meaning stated in
  `methodology.md` § *Appetite*, or drop it from `templates/ISSUE.md:4` and have `/uvm-feature` Step 2
  round a `medium` seed to `big`, saying so.
- **Confidence:** high · **Effort:** small

## F2 — `kind: fix` and `appetite: big` select opposite research paths
`origin=uvm-plan:step-3 severity=medium category=instruction status=applied target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** Step 3's first bullet skips the fan-out for "`appetite: small` / `kind: fix` /
  `skip research`" and its second runs the full fan-out for "`appetite: big`". This GOAL is `kind: fix`
  **and** `appetite: big`, so it matches both, and the two bullets prescribe opposite work. I resolved
  it by borrowing "when they disagree with the GOAL, the GOAL wins" — but that sentence sits inside the
  *diagnostic fixes* exception and is scoped to whether the root cause is known, which was not the
  question here.
- **Skill cause:** the two bullets are written as if `kind` and `appetite` could not conflict. They
  routinely can, and will again: `issues/lock-ownership-and-hold-time.md` is the next queued cycle and
  is also a `fix` whose appetite exceeds `small`.
- **Recommended fix:** make the first bullet's condition conjunctive (`appetite: small` **and** not
  overridden), or state a precedence line — appetite governs research depth, `kind` does not — and
  keep `kind: fix` only as a *default* for appetite rather than an independent trigger.
- **Confidence:** high · **Effort:** small

## F3 — the gate-hazard list omits the prose anchor that wraps across lines
`origin=uvm-plan:step-6 severity=low category=missing-guidance status=applied target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** the R7 gate asserted a `README.md` sentence was gone via
  `git grep -q 'found by walking each distribution'`. That phrase wraps across two lines in the file
  and `git grep` is line-based, so the gate reported the post-condition met while the sentence was
  still there — green, and inert. Caught only because Step 6 requires proving the gate red first.
- **Skill cause:** Step 6 enumerates gate hazards specifically so authors do not rediscover them, and
  names the `zsh` word-splitting case in detail. A multi-line-wrapping prose anchor is the same class —
  a gate that searches something the file does not literally contain — and is more likely in this
  repository than the documented one, because `README.md` and `AGENTS.md` are hard-wrapped at 100
  columns and documentation sweeps are a recurring phase type here.
- **Recommended fix:** add one sentence to Step 6's hazard paragraph: an anchor for a documentation
  gate must be a substring of a single line, and hard-wrapped prose usually is not — verify the anchor
  matches before relying on its absence.
- **Confidence:** high · **Effort:** small

## F4 — a gate may cover half a criterion and still read as full coverage · seen again
`origin=uvm-build:P1 severity=medium category=missing-guidance status=applied target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** R5's *Checked by* clause names two checks — the finding set must equal the one
  `git show main:bin/uv-manager` produces on the same tree, and the walk must be measurably faster.
  The authored P1 gate asserted neither. It asserted one case the rewrite could regress — a `RECORD`
  with no trailing newline — which is worth having but is not the equality claim, and it went green
  with that claim unverified. I built the comparison by hand and retuned the gate to encode the three
  verdicts `main` produces on the awkward shapes.
- **Skill cause:** `uvm-plan` Step 6 requires a gate be proven red before the fix, which certifies
  that the gate *works*, not that it covers what the criterion says it checks. Nothing asks the
  author to reconcile the gate against the R-ID's own *Checked by* clause, or — where a check cannot
  be mechanized — to say in the phase body who grades the remainder. P4's body does exactly that
  delegation voluntarily, so the practice already exists in this cycle and is simply not a rule.
  Red-first also mis-tests a gate that mixes classes: an assertion protecting *preserved* behavior
  must be **green** before the fix, and calling the whole gate "red before" hides that half.
- **Recommended fix:** in Step 6, require each phase to account for every R-ID it `satisfies` — the
  gate encodes the criterion's *Checked by* clause, or the phase body names the reviewer as grader
  for the part it cannot. Add the corollary that a gate mixing new-behavior and regression
  assertions is proven by running both halves against the pre-fix tree and confirming the split.
- **Recurrence (P2):** the same shape, with a sharper edge. P2's gate pairs the `pyvenv.cfg`
  assertion with R6's read-only manifest, and a *preservation* assertion is green on both sides of
  the fix — so `uvm-build` Step 4's "red before, green after" cannot certify it at all, and following
  that rule literally would have let a vacuous manifest diff pass as proof. An empty `find`, a
  mistyped path, and a correct read-only run are the same green. I proved it by writing a file into
  the tree mid-run and watching it go red. The rule to add alongside the split: **an assertion that
  must be green before the fix is certified by tampering, not by red-first** — make the condition it
  guards against actually happen once, and watch the gate catch it. `research/01` §4 records this
  lesson for fixtures ("assert that a fixture mutation actually applied"); it belongs in the skill,
  where it applies to every preservation criterion, not just this cycle's.
- **Recurrence (P3, review cycle 2) — third sighting, and the one that shipped.** R4 governs "the
  remediation text", and P3's own design put remedy text in **two** places: the block, and the
  advisory line, which carries its own remedy because a tree with no failures prints no block. The
  gate asserted the block's idioms hard — no `uv-manager install`, `--no-cache` present — and asserted
  of the advisory line only that it contained the word `receipt`. So R4's standard was enforced on one
  of the two surfaces the phase created, and the unenforced one shipped through cycle 1 naming two
  idioms that both fail: `uv tool install <name>` exits 2 on the surviving shim, and removing the
  directory strands that shim into a fresh `FAIL`. The cycle-1 remediation then *pointed a second
  reader at* that line, which is how a half-covered gate turns into a defect that compounds. The
  generalization the fix needs: when a phase satisfies a criterion in more than one location, the gate
  must name each location, and text that a later edit cites becomes part of that edit's surface.
- **Confidence:** high · **Effort:** small

## F5 — "a red gate is a STOP" does not distinguish iterating from failing
`origin=uvm-build:P3 severity=medium category=instruction status=applied target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** P3's gate went red on its first run, for a real reason — the plan converted only
  the remediation block to a heredoc, and R4's check covers the whole command. Step 4 says, without
  qualification, "Red → STOP; do not mark done or advance state," and record an attempt against the
  durable circuit breaker. Read literally that ends the invocation on the first red of a phase I was
  still implementing. I diagnosed the gap, widened the change, went green, and did not record an
  attempt — a deliberate departure from the letter of the step, taken because the alternative
  misreports what happened.
- **Skill cause:** the step conflates two states with the same name. A gate that is red because the
  implementation is not finished yet is the normal inner loop; a gate that is red after the phase is
  believed complete is evidence the phase is mis-shaped. Only the second is what `attempts` is
  counting — the breaker trips at about 3, so recording every mid-implementation red would trip it on
  a phase converging exactly as intended, and the signal `/uvm-plan` is meant to receive from a
  tripped breaker becomes noise. Nothing in the step tells the builder which state it is in.
- **Recommended fix:** scope the STOP to a gate still red when the builder has no further correction
  to make, and say that reds resolved inside the same invocation are recorded in the phase body as
  amendments rather than on the attempts counter. One sentence, next to the circuit-breaker bullet.
- **Confidence:** high · **Effort:** small

## F6 — the blind-reviewer exclusion is `spec/`, but a GOAL may cite a prior cycle's record as ground truth
`origin=uvm-review:step-2 severity=medium category=instruction status=open target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** R4 names `spec/purge-resilient-run/research/04-uv-repair-idioms.md` as the
  reference the reviewer grades the remediation idioms against. Step 2 tells the reviewer to keep
  `research/` out of context and to exclude `spec/` from every repository-wide search. Following both
  is impossible, so I inlined 138 lines of a prior cycle's research into the reviewer prompt by hand.
- **Skill cause:** Step 2 and the rubric write `spec/` as if it were coextensive with *this* cycle's
  artifacts. It is not — retained records from every landed cycle live there, and `methodology.md`
  keeps them deliberately so later work can cite them. A GOAL pointing at one is correct behavior, not
  an author overreaching. Nothing in the skill says what to do, and the two obvious resolutions differ
  in kind: narrowing the exclusion to `spec/{slug}/` would let the reviewer read a sibling cycle's
  PLAN, while inlining costs the orchestrator a manual step and scales with the file.
- **Recommended fix:** state the rule as `spec/{slug}/` for PLAN/TECH/research/META plus `spec/*/REVIEW.md`,
  and let other cycles' `GOAL.md` and `research/` through — a landed cycle's record carries no intent
  about *this* diff. Add one line to Step 2's curated-input list: when `GOAL.md` names a file under
  `spec/` as a grading reference, name it to the reviewer as readable rather than inlining it.
- **Confidence:** high · **Effort:** small

## F7 — the rubric grades four severities and then routes on one bit · seen again
`origin=uvm-review:step-4 severity=medium category=instruction status=open target=.agents/factory/review-rubric.md`
- **What happened:** the pass returned exactly one finding, LOW and CONFIRMED — the ordering of a
  printed remediation block, not a defect in what it names. § *Verdict & loop* says "**CONFIRMED**
  findings → `status: blocked` … loop back to `uvm-build`" with no reference to severity, so a LOW
  finding blocks the branch on the same terms a CRITICAL one does and consumes one of at most three
  cycles. I followed the letter and set `changes-requested`, then had to tell the human separately
  that the finding is LOW and accepting it is reasonable — which is the triage the routing rule
  removed.
- **Skill cause:** the rubric defines a four-level severity table immediately above a routing rule that
  ignores it, in the same file. PLAUSIBLE findings already have a human-triage path; CONFIRMED-but-LOW
  has none, and the alternative disposition this repository already uses — defer it to
  `issues/{slug}.md` with a `ROADMAP.md` entry — is documented in `AGENTS.md` and unreachable from
  Step 4.
- **Recommended fix:** in § *Verdict & loop*, route on CONFIRMED **at MEDIUM or above**; a CONFIRMED
  LOW is surfaced to the human alongside the PLAUSIBLE set, with deferral to `issues/{slug}.md` named
  as a disposition. Keep the auto-block unconditional for any §1–§11 violation regardless of the
  severity assigned.
- **Recurrence (cycle 3), inverted.** Two CONFIRMED LOW findings came back and I approved anyway,
  because blocking on them is indefensible: one is *contract-mandated* — R5 requires verdict parity
  with `main`, so the `RECORD` comma-splitting the reviewer confirmed cannot be corrected inside this
  cycle without failing the criterion — and the other is a length judgment on prose that asserts
  nothing false. Following the letter would have spent the last cycle of a bounded loop on work the
  GOAL forbids. The rule has now been departed from in both directions from the same defect, which is
  the argument for fixing it rather than exercising judgment each time. The fix should also name the
  case the first sighting did not: a CONFIRMED finding against **pre-existing behavior the criteria
  require preserving** is not a finding against the diff at all, and belongs in `issues/{slug}.md` by
  construction.
- **Confidence:** high · **Effort:** small

## F8 — the refutation protocol certifies that the bad thing happened, never that the fixture can explain it
`origin=uvm-build:P3 severity=medium category=missing-guidance status=open target=.agents/factory/review-rubric.md`
- **What happened:** cycle 1's finding read "exits 1 **without repairing anything**", CONFIRMED
  against a probe holding one tool. Remediating it meant writing that claim into user-facing prose, so
  I measured it first with two tools — and `uv tool upgrade --all --reinstall --no-cache` restored the
  damaged file and *then* exited 1 on the orphan. The observation (rc 1) was right; the explanation
  attached to it was not, and it is the explanation the fix has to encode. Had I trusted the finding,
  doctor would now talk users out of a command that repairs their tree.
- **Skill cause:** § *Refutation protocol* turns on whether the wrong behavior **reproduced**, and
  § *What counts as evidence* lists observations — an exit code, a captured stderr line, a `readlink`.
  Neither asks whether the constructed state can *distinguish* the stated cause from its alternatives.
  With one tool in the tree, "fails wholesale" and "repairs the rest, then fails" emit the same rc 1,
  so the fixture could not have refuted the wrong one. This is not reviewer sloppiness and not
  one-off: `spec/purge-resilient-run/research/04-uv-repair-idioms.md` §4 characterized the same class
  the same way, from the same single-tool shape, and the finding inherited it.
- **Recommended fix:** add a step 1b to the protocol — before writing the finding, state the competing
  explanation for the same observation and say what in the fixture rules it out; if nothing does,
  either widen the fixture or downgrade the *explanation* to PLAUSIBLE while keeping the observation
  CONFIRMED. A finding whose severity or remedy turns on the mechanism needs a fixture with at least
  two of whatever the mechanism ranges over.
- **Confidence:** high · **Effort:** small

## F9 — REVIEW.md is append-only with no way to retract a finding a later cycle disproved
`origin=uvm-review:step-3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** cycle 2 measured the behavior cycle 1's finding asserted and found the assertion
  too strong — the observation held, the mechanism attached to it did not. Step 3 says a later cycle
  "**never overwrites**" and appends, which is right for an audit trail, but it says nothing about a
  *superseded* claim. Cycle 1's finding still stands in the file as written, in a section a reader has
  no reason to distrust. I invented a "Correction to cycle 1's record" subsection inside cycle 2 to
  keep the file honest; nothing in the skill or the template asked for it or says where it goes.
- **Skill cause:** the file's two jobs collide and the skill only names one. As an audit trail it must
  not be rewritten; as the durable account of what is true about this change it is read downstream —
  `uvm-publish` surfaces it in the PR, and a human triaging a PLAUSIBLE finding months later reads it
  cold. Append-only without a retraction convention means the record's most prominent claims are the
  oldest ones, and a wrong finding that was already acted on propagates as fact.
- **Recommended fix:** add one line to Step 3 and a stanza to `templates/REVIEW.md`: when a cycle
  disproves or narrows an earlier cycle's finding, it appends a **`### Correction to cycle {n}`** note
  in its own section stating what was claimed, what was measured, and which account supersedes. Never
  edit the earlier section — the correction is the mechanism, not a rewrite.
- **Confidence:** high · **Effort:** small

## F10 — the flag that blinds the reviewer's log is given as a fragment, and the obvious placement no-ops
`origin=uvm-review:step-2 severity=high category=instruction status=applied target=.agents/skills/uvm-review/SKILL.md`
- **What happened:** Step 2 writes the log command out in full as
  `git log --oneline {base}..HEAD -- . ':(exclude)spec/'`, then a clause later says "on
  `review.cycle` ≥ 1 drop the subjects too (`--format=%h`)". I composed the two as written, appending
  the flag to the printed command — and everything after `--` is a pathspec, so `--format=%h` was
  consumed as a path, `--oneline` survived, and seven commit subjects reached the reviewer. One of
  them named a prior cycle's finding id and the shape of its remediation. The reviewer disclosed it
  unprompted; nothing in the skill would otherwise have caught it.
- **Skill cause:** the safe form is stated as a *modification to a command printed elsewhere*, and the
  only correct composition requires knowing to move the flag ahead of the `--`. This is the guard on
  blind-review integrity, the pass's central guarantee, and it fails **silently and green** — the log
  prints, the pathspec still filters, nothing errors. Every cycle ≥ 1 walks into it; the two earlier
  cycles here were scoped passes whose log was omitted, so this is the first invocation that could.
- **Recommended fix:** print the cycle-≥-1 command literally and completely in Step 2 —
  `git log {base}..HEAD --format=%h -- . ':(exclude)spec/'` — rather than naming a flag to add, and
  say why the placement matters; this is the same class as the interpolated-pathspec trap the rubric's
  § *Verification traps* already documents. Simpler still: on a later cycle, omit the log. Nothing in
  the returned matrix used it.
- **Confidence:** high · **Effort:** small

## F11 — the drift sweep is gated on `--all`, including in the file the retirement is already editing
`origin=uvm-roadmap:step-5 severity=medium category=instruction status=open target=.claude/skills/uvm-roadmap/SKILL.md`
- **What happened:** retiring this seed meant repairing two dangling links in
  `issues/purge-tree-repair.md`. A hundred lines above them the same file said `uvm_doctor` "prints
  three commands for a human (`bin/uv-manager:729-731`)" — a count this cycle changed to two, at a
  line range that no longer exists. Step 5's triage table sent me into the file; its `--all` bullet
  put that sentence out of scope. I corrected it anyway, departing from the letter of the step,
  because leaving it was indefensible once the file was open.
- **Skill cause:** the `--all` bullet scopes the drift sweep by *which seed* holds the stale figure —
  "in seeds it never edited" — when the discriminator that matters is whether the sweep is already
  opening the file. A false figure standing beside a freshly repaired link is worse than one in a file
  nobody touched: the repair is a signal the file was reviewed, so a later reader trusts the rest of
  it. Nor is this a one-off. Every retirement repairs the seeds that depended on the shipped cycle,
  and those are precisely the seeds most likely to quote its behavior — `purge-tree-repair.md` quotes
  doctor's output four times because doctor is its detector.
- **Recommended fix:** split the bullet in two. In the default sweep, any file Step 5 edits is read
  whole for claims the shipped cycle falsified — a count, a line citation, a quoted output. Keep
  `--all` for the repository-wide version, over seeds the retirement does not otherwise touch.
- **Confidence:** high · **Effort:** small
