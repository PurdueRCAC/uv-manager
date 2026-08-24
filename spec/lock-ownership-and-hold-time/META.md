# META — The provisioning lock can be released by a process that does not hold it

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

- **slug:** lock-ownership-and-hold-time

## What worked well

- The `medium` → `big` rounding rule landed in `fe45b9b` fired on the first promotion after it was
  written, and turned the question that stalled the previous cycle's shaping into a one-line
  Clarification. Nothing had to be asked.
- Step 4's rule that a deferring non-goal is only a promise if it lands in the named file fired
  **twice** here, and both obligations were real: `issues/test-harness.md` gained R3d and
  `issues/purge-tree-repair.md` gained R11. The predicate generalization in particular existed
  nowhere but this seed's Notes, so without the rule it would have died with the seed at
  `/uvm-roadmap`.
- Step 6's instruction to read each `verify:` back against its phase's own checklist caught a **blind**
  clause before it shipped: P3's stray-refresher check was written as `jobs -p`, which reports nothing
  whether or not a refresher leaked, because the refresher is a grandchild of the drive shell. The gate
  would have gone green on the one failure mode the phase can introduce. Testing it rather than reading
  it is what exposed that, which is Step 6's other instruction earning its place.
- `run_verify.py --phase` made re-running three predecessor gates a one-liner, so checking whether a
  new constraint had invalidated an earlier phase's gate cost nothing once the thought occurred. The
  thought is what was missing, not the tool — see F9.
- Recording a *statistical* gate's red state as a number rather than a message paid off at P7: the
  observed 44/1280 could be checked against the brief's 33/1280 and its 2–4% band, which is what
  distinguishes "the predicted defect" from "a different one that also fails the assertion".
- Step 2's "read the region of `bin/uv-manager` the phase will touch before editing it" is what caught
  P6 having two break sites where `PLAN.md` describes one — the second was added by P3, three phases
  after the plan was written. Following the checklist literally would have shipped R7 half-done.

## Friction findings

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — a `shaped` seed can still carry decisions it deliberately left to promotion
`origin=uvm-feature:step-4 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-feature/SKILL.md`
- **What happened:** the seed's `status:` was `shaped`, and Step 4's `shaped` branch says the shaping
  conversation "already happened with a human. Do **not** re-litigate it… adopt it largely as
  written." But the seed's own text carried two decisions it had explicitly parked for this step —
  R4's "whether this is a guard or a documented constraint on the dispatch tail is a promotion
  decision", and a Note saying the early-out predicate generalization "may belong to the repair cycle
  instead". I asked the human about both, which was right, but it is a departure from the letter of
  the branch I was following.
- **Skill cause:** the `shaped` branch is written as if `shaped` meant *fully settled*. It does not,
  and cannot: `/uvm-feature` is what writes these seeds, and deferring a decision to promotion is a
  legitimate thing for a shaping pass to do when the answer depends on what the adopting cycle turns
  out to be. An agent following "do not re-litigate, adopt as written" literally would have guessed
  both, and the R4 guess in particular is a scope difference — a guard in the dispatch tail versus a
  comment. Nothing in the branch tells the reader that a parked decision is not re-litigation.
- **Recommended fix:** one sentence in the `shaped` bullet: a `shaped` seed may still name decisions
  it parked for promotion, and those are this step's to settle with the human — re-litigation is
  reopening what the seed *settled*, not answering what it deliberately left open. Optionally, give
  the phrasing a home in `templates/ISSUE.md` so parked decisions are marked rather than buried in
  prose, which is how both of these were written.
- **Confidence:** high · **Effort:** small

## F2 — a GOAL's *Checked by* clauses are written but never executed
`origin=uvm-plan:step-3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-feature/SKILL.md`
- **What happened:** two of this GOAL's six *Checked by* clauses were not executable as written. R6's
  `git grep -c flock bin/uv-manager` "returning 0" can never pass — `:172` names `flock` in the comment
  recording why the discipline is `mkdir`, so it returns `bin/uv-manager:1` and exits 0. R4's clause
  matched four `exec` sites while R4's prose named three, so the criterion and its own gate disagreed.
  Both were found in research and both needed a human decision to repair the contract.
- **Skill cause:** `/uvm-plan` Step 6 is emphatic that every `verify:` must be run before the plan is
  committed, and that a gate exiting 0 against an undelivered post-condition is inert. Nothing applies
  that discipline to the *GOAL's* clauses, which is where these commands are first written and where
  they are cheapest to test. The asymmetry is the defect: `/uvm-feature` writes commands and
  `/uvm-plan` is the first step required to run any. Had the fan-out not happened to include a
  verification-recipes topic, R6's clause would have been transcribed into a `verify:` that is
  permanently red, walking `--record-attempt` toward the circuit breaker at 3 while the code was
  correct — the exact failure Step 6 exists to prevent, arriving from upstream where Step 6 cannot see
  it.
- **Recommended fix:** a step in `/uvm-feature` before the shape commit: run every *Checked by* clause
  that is a literal command against the current tree and record what it returned. A clause that cannot
  pass, or that passes before the work is done, is not a criterion. This is Step 6's "red is necessary,
  not sufficient" applied one stage earlier, and it costs seconds.
- **Confidence:** high · **Effort:** small

## F3 — the `verify:` field reference documents the style that cannot express a real gate
`origin=uvm-plan:step-6 severity=low category=template status=open target=.agents/factory/templates/TECH.md`
- **What happened:** the field reference explains double-quoted scalar style at length — which
  characters are YAML escapes, how a `\n` splits the command where no shell sees it — and mentions a
  block scalar only as a trailing alternative. Every gate in this cycle is a multi-line heredoc drive
  under `temp_root.sh`, which double-quoted style cannot express at all. The previous cycle shows the
  cost: `spec/doctor-detection-gaps/TECH.md`'s gates round-tripped into folded single-quoted scalars
  whose shell lines are separated by blank lines to survive re-emission, and they are close to
  unreadable.
- **Skill cause:** the guidance optimizes for the single-line case and treats the multi-line case as
  the exception, when for this project — where a gate is a sandbox drive asserting a post-condition —
  multi-line is the norm. The warning it does give is real, but it is advice for a style that should
  rarely be chosen.
- **Recommended fix:** make the literal block scalar (`|`) the documented default for any `verify:`
  longer than one command, and keep the double-quoted escaping warning scoped to the one-liner case.
  Worth noting that `|` round-trips through `next_phase.py`'s PyYAML cleanly, heredocs included.
- **Confidence:** high · **Effort:** small

## F4 — `invariants.md` was written from `AGENTS.md` prose, not from the functions it constrains
`origin=uvm-plan:step-5 severity=medium category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** an audit of all twelve sections against `bin/uv-manager` — ~126 claims, four
  sections, seven findings filed, three refuted by an adversarial pass — found **four** assertions
  measured false of the code. Three of them (§6, §9, §11, recorded below) are the same failure mode:
  a qualifier dropped or invented while compressing `AGENTS.md` prose into a checklist bullet. The
  fourth (§5) turned out to be a code defect and was taken into this cycle as R7. All four date from
  the file's creation commit `33a91fb`, so this is origin error, not drift.
- **Skill cause:** `invariants.md` is graded against as **auto-CRITICAL**, and nothing in the factory
  ever required its assertions to be checked against the code they constrain. It was derived from
  prose that is itself a summary, one step further from ground truth at each hop. `AGENTS.md` says
  "when something below disagrees with the code, the code is ground truth" — but that rule is written
  for the human reading it, and no step executes it. The consequence is not hypothetical: a reviewer
  following §11 would fail a correct parser, and §6 would have a reviewer demand pre-warm text on a
  path where it is deliberately absent.
- **Recommended fix:** two things. Repair the three bullets (F5–F7). And add a standing rule to this
  file's header, which is a *strengthening* and so needs no typed override: before raising an
  auto-CRITICAL for a §1–§11 violation, confirm the invariant is true of `main` in the neighbourhood
  being graded; a claim that does not hold on `main` is a finding against **this file**, logged in
  `META.md`, not against the diff. A bullet added or edited here names the function it constrains and
  is checked against that function, not against `AGENTS.md`'s prose. Explicitly **not** recommended: a
  recurring audit or a `lint.sh` check — one adversarial sweep found these and the claims are
  semantic, so a schedule would buy ceremony `AGENTS.md` already prices.
- **Confidence:** high · **Effort:** small

## F5 — §6 generalizes one failure path's message to "any failure"
`origin=uvm-plan:step-5 severity=low category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** §6's last bullet reads "On any failure, remove the staging directory, release the
  lock, and die with the pre-warm instructions." Measured: the installer-pipeline guard
  (`bin/uv-manager:341-349`) carries the pre-warm text; the version read-back guard (`:351-355`)
  deliberately does not, because pre-warming would send the user to repeat the same download; and the
  rename at `:361` is guarded by nothing and dies under `set -e` leaving a `.incoming.` directory. So
  both halves of the sentence are false as written. No `AGENTS.md` counterpart, so this is a
  single-file edit.
- **Skill cause:** as F4. The bullet describes the first failure path it encountered and quantifies it
  over all three.
- **Recommended fix:** replace with a bullet that names the per-path advice — no egress gets pre-warm,
  a binary that will not run gets the wrong-architecture message — and states plainly that the rename
  is unguarded. The unguarded rename itself is code work, seeded in `issues/invariant-audit-gaps.md`.
- **Confidence:** high · **Effort:** small

## F6 — §9 drops the qualifiers on the trampoline overwrite guard
`origin=uvm-plan:step-5 severity=medium category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** §9 says "Only marked files are ever overwritten or removed." Removal is
  marker-only; overwriting is not. The guard at `bin/uv-manager:491-496` is a three-way conjunction,
  so an unmarked file failing `-s` **or** `-x` is written over — a planted 0644 non-empty user file was
  replaced with no note. The sentence is duplicated verbatim at `AGENTS.md:170`, so the repair is a
  two-file lockstep edit.
- **Skill cause:** as F4 — the compression dropped "non-empty and executable", which is exactly the
  part that makes the claim false.
- **Recommended fix:** state that removal is marker-only while overwriting is refused only for a file
  that is all three, and say why the `-s` term exists (a trampoline truncated by a purge is 0 bytes
  and unmarked, and the bullet above requires it be repaired). The `-x` term is a genuine safety gap
  against the property `AGENTS.md` states; that is code work, seeded.
- **Confidence:** high · **Effort:** small

## F7 — §11's rationale is disproved by `uv`'s actual CLI
`origin=uvm-plan:step-5 severity=medium category=inaccurate-guidance status=open target=.agents/factory/invariants.md`
- **What happened:** §11 asserts the five entries in `uvm_global_takes_value` are complete and that
  "everything else that looks like one is a per-command option and can only appear after the
  subcommand". Measured against `uv 0.12.4`: `uv --cache-dir DIR tool dir` and
  `uv --python-preference only-managed tool dir` both succeed, so two more options are accepted before
  the subcommand and take a value. The enumeration is right about the five under `uv --help`'s *Global
  options* heading; the reasoning attached to it is wrong, and `bin/uv-manager:533-538` names
  `--cache-dir` as an example of the category it disproves. Duplicated in `AGENTS.md:181-183`.
- **Skill cause:** as F4, with an aggravating factor — this bullet asserts a fact about a *third-party
  CLI* that nobody ran. It also argues against lengthening the list ("not more careful, more surface
  to drift"), which reads as a standing reason not to check.
- **Recommended fix:** restate as the set of options `uv` accepts before the subcommand that take a
  separate value, name the two known-missing entries as a gap, and keep the real point — the list is
  not a `uv` CLI model, it is the set that would otherwise be mis-skipped. The banner in the script
  rides with the code fix, which is seeded.
- **Confidence:** high · **Effort:** small

## F8 — `/uvm-plan`'s invariant gate is not cross-checked against its own phase checklists
`origin=uvm-build:P3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** P3's checklist said to derive `lock_beat=$(( lock_stale / 10 ))` "beside the
  existing knobs" — at load time. Measured on bash 3.2.57, `UVM_LOCK_STALE=abc` makes that arithmetic
  fatal under `set -u`, so at load it kills `uvm help` and `uvm --version`. `PLAN.md` §3 rules that
  out in its own words two sections earlier: "the R3 guard sits inside `uvm_acquire_lock`, so `help`
  and `--version` still answer on an unconfigured or misconfigured node. Load-time placement was
  rejected for exactly this reason." The plan contradicted itself and nothing caught it before build.
- **Skill cause:** `/uvm-plan` writes the § *Invariant gate* and the phase checklists as separate
  passes, and nothing asks whether the checklists actually obey the gate the same document just
  asserted. The gate reads as a compliance statement about the design rather than a constraint the
  roadmap is checked against.
- **Recommended fix:** after drafting the phases, re-read § *Invariant gate* against each checklist
  item and record any item that lands on the wrong side of one. A single "which phase would violate
  this?" pass per gate bullet would have caught it.
- **Confidence:** high · **Effort:** small

## F9 — the "re-run predecessor gates" rule exists only in remediation mode · seen again
`origin=uvm-build:P4 severity=high category=missing-guidance status=open target=.claude/skills/uvm-build/SKILL.md`
- **What happened:** P4's new ordering guard refuses `UVM_LOCK_TIMEOUT >= UVM_LOCK_STALE`. P3's
  already-`done` gate held a lock with `UVM_LOCK_STALE=10` against the default timeout of 180 — a
  pair P4 now refuses — so that gate went red the moment P4 landed. Nothing in the ordinary Steps 3–5
  path says to re-run it; I did so by choice. Had I not, P3 would have shipped with a permanently red
  gate that `next_phase.py` still reports as `done`.
- **Skill cause:** the skill states this hazard exactly, in the words "a `done` phase whose assertion
  the fix invalidated is invisible to the FSM and ships green" — but only inside **Step 1's
  Remediation mode**, reached solely when a review has requested changes. A forward build that adds a
  constraint invalidates predecessor gates by the same mechanism, and Step 4 says nothing about it.
  The hazard is a property of shared state between phases, not of remediation.
- **Recommended fix:** move the rule into Step 4, phrased for both paths — after a phase that adds a
  constraint, a refusal, or anything that narrows legal inputs, re-run the `verify:` of every `done`
  phase and retune (never silently reopen) any gate whose *setup* the constraint made illegal.
  Distinguish the two outcomes: a stale gate setup is retuned and the phase stays `done`; a broken
  assertion reopens the phase.
- **Seen again at P5, in the direction the fix does not cover:** P4's constraint also invalidated the
  *pending* P5 gate, whose stale-break drive was written against the same now-illegal knob pair. The
  recommended fix says "every `done` phase", which would have missed it. A constraint invalidates
  gate setups in both directions — the sweep is over every phase's `verify:`, not the ones behind the
  pointer.
- **Confidence:** high · **Effort:** small

## F10 — `uvm-release`'s tag-convention paragraph cancelled itself after the first release
`origin=harness-audit:release-skill severity=medium category=instruction status=open target=.agents/skills/uvm-release/SKILL.md`
- **What happened:** the *Tag convention* paragraph in Argument Parsing opens "There are no tags yet,
  so the first run establishes it" and closes "Once tags exist, follow whatever the existing ones do
  rather than this paragraph." `git tag -l` returns `0.3.0 0.4.0 0.4.1 0.5.0`. The condition failed
  1h46m after the paragraph was written in `33a91fb`, and four tagged releases have shipped since.
  It is not merely inert: it points a `pre-release` run at four suffix-free tags, against the STOP a
  few lines above it that says `pre-release` REQUIRES a suffix.
- **Skill cause:** the paragraph was authored with a self-cancelling precondition and no mechanism
  fires when that precondition expires. The live rules it duplicates already sit in the *Version*
  bullet — no `v` prefix, matching `uvm_version`, strictly greater than the latest tag, not already a
  tag — so nothing is lost by removing it.
- **Recommended fix:** delete the paragraph. Graft its one non-duplicated clause, the rationale "so
  `git tag -l` and `uv-manager --version` read the same", into the *Version* bullet. Net −3 lines.
- **Confidence:** high · **Effort:** small

## F11 — three scope claims in the factory's own docs are now false
`origin=harness-audit:scope-claims severity=medium category=instruction status=open target=.agents/factory/methodology.md`
- **What happened:** commit `bced44f` gave the operational siblings somewhere to put a finding, and
  three sentences describing what those siblings touch were left asserting the old scope. All three
  are false against the current files: `methodology.md` — "None touches `spec/`, the FSM, or product
  requirements", while `/uvm-roadmap` and `/uvm-release` both now write `spec/{slug}/META.md`;
  `.agents/skills/uvm-release/SKILL.md` — "it touches no `spec/`", four lines above its own Step 10,
  which says to write to a cycle's `META.md`, and inside `bced44f`'s own diff;
  `.agents/skills/uvm-harness/SKILL.md` — "`uvm-harness` is the **only** skill that writes to
  `.agents/`", while `/uvm-roadmap`'s triage table says "Repair." for `.agents/` hits and `7342ff3`
  did exactly that to two `SKILL.md` files.
- **Skill cause:** the fix was applied by addition in two files, and nothing asked which existing
  sentences the addition falsified — including one in the same diff. This is the mechanism behind
  F4's family of inaccurate assertions, recurring in the factory's own prose rather than in
  `invariants.md`.
- **Recommended fix:** repair all three, naming `META.md` as the exception for `/uvm-roadmap` and
  `/uvm-release` only, and naming both `/uvm-roadmap` and `/uvm-build` as `.agents/` writers besides
  `/uvm-harness`. Beware the obvious rewrite of the `methodology.md` sentence: a blanket "all three
  may append to `spec/{slug}/META.md`" licenses the meta-on-meta recursion that document forbids.
- **Confidence:** high · **Effort:** small

## F12 — `/uvm-harness` has never said no, and no step asks it to
`origin=harness-audit:ratchet severity=medium category=missing-guidance status=open target=.agents/skills/uvm-harness/SKILL.md`
- **What happened:** measured across all 89 commits on `main`: **zero** net-negative `.agents/`
  commits, no file under `.agents/` has ever shrunk, and excluding the append-only ledger the totals
  are **4287 lines added against 151 deleted**. The ledger records **53 applied, 1 deferred, 0
  rejected** in 54 entries. Safety §6's anti-thrash memory has a branch for a fix that "repeats a
  previously-rejected one" that has never been written to. A 98% apply rate is not a filter.
- **Skill cause:** no step in the skill ever asks what should come *out*. Step 3 offers `reject` as an
  option a human may pick, but nothing obliges the run to look for one, and Step 4 previews only the
  edits that were already chosen. Note that Safety §4's "Prefer adding an **example** or a clarifying
  sentence over a new hard rule" is *not* the cause — it prefers soft additions over hard rules, not
  additions over deletions. The gap is an absence, not a wrong instruction.
- **Recommended fix:** require every run to record either a rejection or a deletion candidate, and to
  state plainly when it found neither. This **tightens** a guardrail rather than loosening one, so
  Safety §3's "a finding that argues to loosen a guardrail is itself a warning sign" does not apply —
  but the edit touches the applier's own safety principles, so it deserves the human's eye either way.
- **Confidence:** high · **Effort:** medium

## F13 — `harness-log.md` entries run 3x the format the file itself specifies
`origin=harness-audit:ledger-format severity=high category=instruction status=open target=.agents/factory/harness-log.md`
- **What happened:** the file's own header specifies one section per decision — header line, metadata
  line, one `**Rationale:**` bullet. Measured over its 54 entries: **mean 10.1 lines, median 9, max
  18**, roughly 3x the documented shape. Step 7 of `/uvm-harness` likewise asks for "a one-line
  rationale". The file is now 559 lines / ~11.4k tokens, 1.99x `AGENTS.md`, the largest file in
  `.agents/`, and Step 2 reads it **end to end** on every run — 49% of that invocation's payload.
  Growth is ~110–143 lines per cycle.
- **Skill cause:** the format is stated once, in the file being appended to, and no step checks a new
  entry against it. Nothing in the loop measures the payload it is adding to.
- **Recommended fix:** hold new entries to the documented three-line shape, and reformat the existing
  54 in one pass (≈378 lines, ~40% off the `/uvm-harness` payload). Forward growth drops from ~10 to
  ~3 lines per entry.
- **GATE FLAG — this finding must not be read as licensing pruning.** Do **not** delete, age out or
  sample entries, and do **not** relax Step 2's end-to-end read. Safety §6 is deliberately
  asymmetric: "reverts a **recent** change" carries a recency qualifier and "repeats a
  **previously-rejected** one" does not, so rejection history has no horizon. Compress the entries;
  keep all 54. Doing otherwise weakens a non-negotiable gate and needs a typed human override, which
  this finding does not supply. Marked `high` for that reason, not because the format itself is
  urgent.
- **Confidence:** high · **Effort:** medium

## F14 — `invariants.md` §5 states an unsound inference as doctrine
`origin=harness-audit:invariant-premise severity=high category=instruction status=open target=.agents/factory/invariants.md`
- **What happened:** §5's contention bullet reads "if the lock directory is absent after a failed
  `mkdir`, the failure is permissions/quota/ENOSPC and waiting will never help — die with that
  message." A holder releasing between `mkdir` returning `EEXIST` and the test evaluating makes a
  released lock indistinguishable from an unwritable mount, so the premise is false. Measured on
  Anvil compute node `a706`: 62 of 64 concurrent cold starts, two ranks killed by this inference on a
  healthy GPFS mount. Reproduced on this branch at 25 of 640 ranks. The bullet is the only place the
  premise is written down — `AGENTS.md` never states it, `README.md` never mentions it.
- **Skill cause:** this is F4's family with the sharpest instance yet. §5 was written from the
  script's own comment, which asserts the inference confidently, rather than from reasoning about
  what the code can actually observe. A checklist bullet that repeats a comment inherits the
  comment's error and then grades code against it: any §1–§11 violation is auto-CRITICAL, so the
  correct code would have been the finding.
- **Recommended fix:** the imperative "distinguish contention from failure" survives; replace its
  evidence — persistence across a bounded number of attempts, not a single observation. The code
  repair is R8/P7 in this cycle and the bullet is overturned in that commit, per `AGENTS.md`'s
  same-commit rule. Recorded here because the finding is about the checklist being derived from
  prose rather than from the function, which outlives this cycle's fix.
- **Confidence:** high · **Effort:** small

## F15 — no skill owns a mid-cycle GOAL amendment, on its second use
`origin=harness-audit:amendment-route severity=medium category=missing-guidance status=open target=.agents/factory/methodology.md`
- **What happened:** a benchmarking run found a fourth defect in the function this cycle rewrites,
  after four phases had landed. Folding it in meant adding R8 to a locked `GOAL.md`, a Clarification,
  a `PLAN.md` design section, requirement-map and deviation rows, an invariant-gate note, and a
  seventh phase. No skill covers that: `/uvm-feature` STOPs when not on `main`, `/uvm-build` only says
  to STOP and escalate, and `/uvm-review` is not running. It was done as a maintainer hand-commit,
  the same way `5fc4196` added R7.
- **Skill cause:** the lifecycle assumes the contract is settled before `/uvm-build` starts. It is a
  reasonable default and it has now failed twice on the same cycle. `harness-log.md`'s F3 already
  records this as `decision=deferred`, "real and unfixed" — this is that finding recurring, which is
  the signal `/uvm-harness` acts on, and neither of `5fc4196`'s four findings named it.
- **Recommended fix:** give the amendment a documented route — most cheaply a mode of `/uvm-feature`
  that accepts running on a `feature/`|`fix/` branch when the slug matches, requires an
  `AskUserQuestion`, and writes the whole artifact set in one commit with a stated subject shape. Two
  guardrails worth encoding from this instance: the amendment must state which soft circuit-breakers
  it crosses, and an amendment that *overturns* an invariant rather than adding one needs the
  `AGENTS.md` "never in the diff alone" human, which is the amendment commit itself.
- **Confidence:** high · **Effort:** medium

## F16 — a gate whose drive dies at the wrapper reports nothing at all
`origin=uvm-build:P5 severity=medium category=missing-guidance status=open target=.agents/factory/templates/TECH.md`
- **What happened:** P5's stale-break drive ran `UVM_LOCK_STALE=1 UVM_LOCK_TIMEOUT=10 uv --version`
  under `set -e` with the wrapper's stderr redirected into the sandbox for a later `grep`. P4 had made
  that pair illegal, so the call died on the refusal, `set -e` aborted the drive before any assertion,
  and `run_verify.py` exited 1 having printed **nothing** — no `FAIL:` line, no wrapper message, no
  clue which of four drives failed. The refusal was sitting in `$UVM_SANDBOX/brk`, unread and deleted
  with the sandbox.
- **Skill cause:** the gate conventions require every assertion to print a `FAIL:` line naming the
  post-condition, which makes a *failed assertion* self-describing. Nothing covers the drive command
  itself: the idiom the templates and every gate in this cycle use — redirect the wrapper's stderr to
  a file, assert against it afterwards — makes the wrapper's own diagnostic invisible on the one path
  where the drive never reaches the assertion. Silence is then indistinguishable from a harness bug.
- **Recommended fix:** state the rule where gates are authored — a drive command whose failure aborts
  the drive is guarded (`if ! cmd …; then echo "FAIL: <what it was doing>" >&2; cat "$stderr_file"
  >&2; exit 1; fi`), never left bare under `set -e`. It costs three lines per drive and it is the
  difference between "the knobs became illegal" and an exit code.
- **Confidence:** high · **Effort:** small

## F17 — the cycle-1 commit log leaks the plan's phase decomposition
`origin=uvm-review:Step 2 severity=high category=instruction target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** Step 2 hands the reviewer `git log --oneline {base}..HEAD -- . ':(exclude)spec/'`
  and only drops the **subjects** on `review.cycle` >= 1, where they would name a prior verdict. On
  cycle 1 this branch's subjects read `[fix] Build lock-ownership-and-hold-time P1: release only what
  we own`, `… P2: release before every exec`, `… P5: name the lock's holder` — the phase ids, the
  phase order and each phase's thesis. That is `PLAN.md` content, arriving through the one channel the
  `spec/` pathspec cannot filter. I noticed and omitted the log, which the step permits in a trailing
  clause, but nothing directed me to.
- **Skill cause:** the step models the log's leak as *prior-cycle findings* and therefore times the
  mitigation to the cycle counter. The leak is not cycle-scoped: `/uvm-build`'s own commit convention
  embeds `P{n}: {phase thesis}` in every build subject, so a first-cycle log discloses the plan's
  decomposition on every branch the factory produces. The permission to omit is buried as "Omitting
  the log is equally correct" after 90 words about the cycle >= 1 form, which reads as a stylistic
  aside rather than the default.
- **Recommended fix:** invert it — `git log {base}..HEAD --format=%h -- . ':(exclude)spec/'` (or no log
  at all) is the default at every cycle, and `--oneline` is the exception, justified only where the
  subjects are known not to carry phase or finding ids. One sentence replaces the current three.
- **Confidence:** high · **Effort:** small

## F18 — red-before/green-after cannot tell a gate that measures the wrong mechanism
`origin=uvm-build:Step 4 severity=high category=missing-guidance target=.claude/skills/uvm-build/SKILL.md`
- **What happened:** P3's drive 1 asserts that a live holder's lock is not broken as stale. It set
  `UVM_LOCK_STALE=3` on the waiter and left the holder at the default 600, and the beat is
  `lock_stale / 10` of each process's *own* value — so the holder refreshed every 60 s against a 3 s
  threshold. The heartbeat the drive exists to prove was never what made it pass; the pid probe was,
  by suppressing the age test entirely. The gate was honestly red before P3 (nothing refreshed
  anything) and honestly green after, satisfying Step 4's protocol in full, while never once
  exercising its own subject. It only surfaced because review cycle 1's fix removed the probe's veto
  and the drive went red — a year later, on a cluster, it would have surfaced as a leaked lock.
- **Skill cause:** Step 4 grades a gate by its *transition* — "confirm it is red before the fix and
  green after" — and nothing asks **why** it was red or **which** mechanism turned it green. A gate
  measuring a correlated mechanism passes that test perfectly. The trap is specific and recurring in
  this repo: a drive that spawns two wrapper processes which must agree on a knob, where setting it
  on one is invisible until something changes the other's behavior.
- **Recommended fix:** add one clause to Step 4 — after a gate goes green, name the line of the
  implementation that made it green, and if the drive spawns more than one wrapper process, state
  which knobs they must share. Where the two disagree, the gate is measuring something else. Cheap:
  one sentence of reasoning per gate, no extra drive.
- **Confidence:** high · **Effort:** small

**What worked well:** reopening the phase whose `satisfies` covered the failing behavior, rather than
appending a remediation phase, put the fix and its regression drives in the file next to the reasoning
that produced the defect — where the next reader meets them together.

## F19 — the debate variant assumes the two reviewers overlap, and says nothing about disjoint results
`origin=uvm-review:step-3 severity=medium category=missing-guidance status=open target=.agents/factory/review-rubric.md`
- **What happened:** cycle 2's two reviewers returned two CONFIRMED defects in one function and
  neither found the other's. The rubric's instruction is to "reconcile" their findings, which
  presumes the sets overlap and the work is arbitrating severity or disposition — what cycle 1 did,
  where both stances reached the same F1. With disjoint sets there is nothing to arbitrate, and the
  orchestrator is left to decide unaided what disjointness *means*. It means coverage is incomplete:
  two passes over a 273-line function found two defects with no intersection, which is evidence a
  third exists, and that inference belongs in the record rather than in whether the orchestrator
  happens to draw it.
- **Skill cause:** § *Optional debate variant* is two sentences and defines the technique by its
  input (two opposing stances) rather than by how to read its output. The stance assignment is itself
  what drives divergence — a reviewer told to argue ship searches for reasons to dissolve, one told
  to argue block searches for states to construct, and they walk different paths through the code —
  so disjoint results are a predictable mode of the variant, not a surprise it can leave unhandled.
- **Recommended fix:** add a sentence to § *Optional debate variant*: overlap between the two
  reviewers is a confidence signal about the findings; disjointness is a coverage signal about the
  pass. Record which of the two occurred in `REVIEW.md`'s reconciliation note, and treat a fully
  disjoint result as grounds to say so explicitly rather than to present the union as complete.
- **Confidence:** high · **Effort:** small

## F20 — Step 2 says to inline a file that is inside the graded diff
`origin=uvm-review:step-2 severity=medium category=instruction status=open target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** Step 2's curated-input list says to give the reviewer "the full text of
  `invariants.md` and `review-rubric.md`". But `invariants.md` is routinely *part of the diff being
  graded* — it was on this branch, revised in six of the seven phases — and the rubric says so
  itself: "an edit to this file sits inside the graded diff, so it revises the standard and is judged
  on its merits". Pasting a copy into the prompt hands the reviewer a second, orchestrator-mediated
  version of a file whose current contents are the thing under review, and it doubles a long prompt
  across two reviewers. I pointed at both paths instead, noting they are outside `spec/` so no
  blindness is at stake, and told the reviewers `invariants.md` is itself in the diff.
- **Skill cause:** the inline rule exists to bound what reaches a blind context, and it is correct
  for `GOAL.md`, which lives under `spec/`. It was extended to two files that do not, where it buys
  nothing and costs accuracy. Nothing in Step 2 distinguishes "inline because the reviewer must not
  browse for it" from "inline because it is long".
- **Recommended fix:** in Step 2, replace the two files in the inline list with an instruction to
  read them at their paths, stating that both sit outside `spec/` and that `invariants.md` is
  frequently inside the graded diff, so the working-tree copy is the one to grade. `GOAL.md` stays
  inline for the reason it always was.
- **Confidence:** high · **Effort:** small

**What worked well (cycle 2):** offering the scoped-versus-full choice as an explicit question, with
the reason a scoped pass was the weaker option on this diff, meant the graded surface was a decision
on the record instead of a default nobody examined.

## F21 — the remediation re-run rule follows `depends_on`, which is not what a shared-file edit invalidates
`origin=uvm-build:step-1 severity=medium category=instruction status=open target=.claude/skills/uvm-build/SKILL.md`
- **What happened:** Step 1.3 says to re-run "the `verify:` of every `done` phase that lists the
  reopened phase in `depends_on`". Reopening P3 makes that P4 alone — P5 lists P4, P6 lists P5, and
  P1 and P2 list nothing. Yet the F6 fix edits `uvm_acquire_lock` and the heartbeat, which P1, P2,
  P4, P5, P6 and P7 all assert against. I re-ran all six because this cycle's own P3 notes recorded
  doing so after the last remediation, not because the skill asked. Following the letter would have
  re-run one gate of six and left five `done` phases graded against code that had moved — the exact
  "invisible to the FSM and ships green" failure the rule was written to prevent.
- **Skill cause:** `depends_on` encodes *build order*, not *assertion overlap*. In a repository whose
  entire subject is one script, ordering and blast radius come apart immediately: every phase here
  edits the same function, so the dependency graph says almost nothing about which gates a fix can
  invalidate. The rule picked the field that was available rather than the one that answers the
  question.
- **Recommended fix:** restate the rule by surface rather than by edge — after a remediation edit,
  re-run every `done` phase whose gate exercises a function the edit touched, and say that in a
  single-file project that is normally all of them. Keep `depends_on` as the ordering constraint it
  is. One sentence, and it costs a few minutes of gates against a class of defect that ships silently.
- **Confidence:** high · **Effort:** small

## F22 — nothing makes a new primitive meet the portability floor before it is designed
`origin=uvm-build:step-2 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-build/SKILL.md`
- **What happened:** P8's design turned on `rename(2)` being atomic and exclusive. That is true of
  the syscall and irrelevant to this script, which can only call `mv`, and `mv -T` does not exist at
  the portability floor. `AGENTS.md` § *Portability floor* and `invariants.md` §10 both say so, and
  `uvm_point_current` carries a documented non-atomic `mv -T` fallback eleven lines from code I had
  read that session. I proposed the design to the maintainer, got approval, and only then put it in
  front of a five-lens fan-out that spent an hour re-deriving what those three places already said.
- **Skill cause:** Step 2 says to read the region the phase will touch, including its banner comment,
  which I did. It says nothing about the region a phase's *new mechanism* depends on. A break that
  introduces `mv` is not an edit to `uvm_point_current`, so nothing pointed there, and the invariant
  gate in `invariants.md` is framed for `/uvm-plan` rather than for a design decided mid-build — the
  case that arises whenever a review reopens a phase and the remedy is not the one the plan foresaw.
- **Recommended fix:** add a clause to Step 3: when a phase introduces a shell primitive the script
  does not already use, check it against `invariants.md` §10 and grep the file for an existing use
  before designing around it. One grep. It would have cost a minute and saved the fan-out, the
  approval, and the reversal.
- **Confidence:** high · **Effort:** small

## F23 — a mid-build design fork has no route to a human that is not a finished plan
`origin=uvm-build:step-3 severity=low category=missing-guidance status=open target=.claude/skills/uvm-build/SKILL.md`
- **What happened:** P8's checklist had to carry two candidate designs and the sentence "the design
  is not settled and is a human's call", because the skill's only escalation is "STOP and escalate on
  a `GOAL.md` contradiction". This was not a contradiction — it was a fork inside the appetite where
  the two branches had materially different blast radius. I invented the format, and the record is
  worse for it: `TECH.md` briefly held unchecked boxes describing work nobody had agreed to.
- **Skill cause:** Step 3 models divergence as either an amendment the agent makes freely or a
  contract violation that stops the cycle. The middle case — a design decision that is the
  maintainer's but does not touch the GOAL — has no home, so it lands wherever the agent puts it.
- **Recommended fix:** name the middle case in Step 3 and give it one shape: state the options and
  their blast radius, ask, and record the answer as a dated line in the phase body the way `GOAL.md`
  records a clarification. Then a reversal has somewhere to attach.
- **Confidence:** med · **Effort:** small

**What worked well (P8):** the census-not-drive decision. Once the guard's window was too small to
open on demand, pinning the count of lock removals in the file was a real assertion rather than a
drive that would have passed by luck — and the first version of that census failed immediately by
counting two legitimate removals, which is the gate catching the gate.

## F24 — nothing says what a later cycle does when it undercuts an earlier cycle's *deferral*
`origin=uvm-review:step-3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** cycle 3's matched A/B showed that half of cycle 2's F7 — the robbed winner's
  death — does not predate the diff, which is the premise the maintainer's 2026-08-16 deferral of F7
  rested on. The skill's only correction machinery is `### Correction to cycle {n}`, scoped to "a
  finding a later cycle overturned". A *disposition* is not a finding, and a deferral cleared by a
  human is not the agent's to reopen silently. I invented the handling: split the new half out under
  its own id, correct the characterization inside cycle 3's section, and put the disposition question
  to the human rather than answering it.
- **Skill cause:** Step 3 and the rubric's *Verdict & loop* both treat a deferral as terminal once
  taken. Neither says whether re-blocking a component of a deferred finding is in bounds or is
  re-litigating a cleared human decision, so the agent picks — and picking "in bounds" on a cycle-3
  verdict is what decides whether the branch ships.
- **Recommended fix:** add one rule to *Verdict & loop*: a later cycle that measures the deferral
  exception's own conditions false for part of a deferred finding reports that part under a new id,
  records the correction against the disposition rather than the finding, and routes the
  keep-or-reopen decision to the human as a gate item. Never re-defer it on the agent's own reading.
- **Confidence:** high · **Effort:** small

## F25 — the loop bound is ambiguous at exactly the cycle where it binds
`origin=uvm-review:step-4 severity=medium category=missing-guidance status=open target=.agents/factory/review-rubric.md`
- **What happened:** this is cycle 3 with a `changes-requested` verdict. "At most two or three
  review↔build cycles; escalate on non-convergence" does not say whether the escalation is owed
  *now*, whether a fourth build may proceed unreviewed, or whether a fourth review is the
  non-convergence it forbids. I wrote "a fourth pass is outside the bound" into `REVIEW.md` as my
  reading, not as the skill's instruction.
- **Skill cause:** "two or three" is a range with no tiebreak and no statement of what escalation
  produces — the bound is stated as a count without a terminal state, so the one cycle where it
  actually constrains anything is the one it does not describe.
- **Recommended fix:** make it concrete: cycle 3 is the last that may set `changes-requested`; a
  verdict that would be cycle 4's stops and hands the maintainer the standing findings, the
  remediation delta, and an explicit ship/abandon/rescope choice. Say what escalation is, not only
  that it happens.
- **Confidence:** high · **Effort:** small

**What worked well (cycle 3):** the debate variant earned its cost for the first time in this cycle.
Both reviewers independently built a simultaneity detector — a marker held at the tail of the
fixture's `install.sh` — which is the first time this record counts concurrent installer entries
instead of inferring them from install totals, and it is the seed's own R1 obligation discharged by
review rather than by a committed harness. Cycle 2's two passes shared no finding; cycle 3's shared
three, and disagreed only on disposition, which is the signal the variant exists to produce.
