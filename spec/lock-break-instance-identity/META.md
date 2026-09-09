# META — A losing breaker deletes the lock a third rank just won

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

- **slug:** lock-break-instance-identity

## What worked well

- `uvm-plan` Step 6's insistence that every `verify:` be **run** before the plan is committed earned
  its keep twice in one cycle: `git grep -c`'s filename prefix and a planted `pid=1` that `kill -0`
  reads as dead both made a gate red while the code was correct. Reading them would have caught
  neither.
- `uvm-feature` Step 4's rule that a deferral naming another file is only a promise in that file is
  what produced three real seed edits here instead of three sentences in *Non-goals*. This promotion
  deferred four of the seed's six sketch criteria, and every one of them would have been deleted with
  the seed by `/uvm-roadmap`. The rule paid for itself in one run.

## Friction findings

<!-- Real findings are appended below this line by the lifecycle skills. -->

## F1 — Step 4's roadmap-rewrite rule covers the promoted seed and not the siblings a promotion edits
`origin=uvm-feature:4 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 4 specifies the adoption marker and says to "rewrite the entry body to the
  scope shaping settled" for *this* seed's `ROADMAP.md` entry. Landing the deferral obligations
  changed three sibling seeds — `invariant-audit-gaps` gained a fourth criterion, `test-harness`
  gained two, and `lock-owner-write-errno`'s sequencing premise was answered — and each has its own
  `ROADMAP.md` entry that went stale the moment the seed changed. `invariant-audit-gaps`'s entry
  heading read "Three small code gaps" against a seed now carrying four. Step 7 acknowledges sibling
  seeds exist (`git add issues/{other-slug}.md`) but nothing says their entries move too, so a run
  following the letter of Step 4 leaves the index false in exactly the places it just edited.
- **Skill cause:** The rule is written for the one-seed case. `ROADMAP.md`'s own contract is one entry
  per issue, so any edit to a seed's criteria or sequencing invalidates its entry — the promoted seed
  is not special, it is merely the one the skill was thinking about.
- **Recommended fix:** Extend Step 4's roadmap paragraph: any seed this promotion writes into gets its
  entry rewritten in the same commit, on the same terms, and Step 7's `git add issues/{other-slug}.md`
  line gains `ROADMAP.md` as its companion.
- **Confidence:** high · **Effort:** small

## F2 — Step 5's gate-rehearsal rule contradicts itself for a fix cycle
`origin=uvm-feature:5 severity=medium category=instruction status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 5 says to run every literal *Checked by* command against the current tree,
  then rules that "a clause that cannot pass, or that passes before the work is done, is not a
  criterion". For a `kind: fix` cycle both halves are backwards. Three of this contract's six gates
  **cannot** pass now — that is what makes them red states, and Step 4 two paragraphs earlier requires
  a fix's criteria be phrased as the broken→fixed behavior that produces exactly such a gate. One gate
  **must** pass now, because it pins unchanged behavior; `spec/lock-acquire-retake/GOAL.md` R6 is the
  same shape and shipped, annotated "green today and green after". I ran the commands and then had to
  decide the rule did not mean what it said.
- **Skill cause:** The sentence was written for a feature's forward-looking gates and applied to every
  criterion. Read literally by a run less willing to overrule it, it deletes the red states a fix cycle
  exists to establish, or the collateral gates that catch a remediation shipping damage instead of a
  repair — which is the failure `lock-acquire-retake` R4 was added to prevent.
- **Recommended fix:** Split the rule by what the criterion is for. A gate is defective when it passes
  *and* claims to show a defect, or fails *and* claims to pin existing behavior. State that a fix
  cycle's gates are expected red now and its unchanged-behavior gates green now, and require the
  observed status be written into the criterion either way, as this GOAL does.
- **Confidence:** high · **Effort:** small

## F3 — Nothing requires a research brief's recommended shell idiom to be tested before it is adopted
`origin=uvm-plan:3 severity=high category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** A brief recommended the fix's central guard as `[[ "${lock}" -ot "${mark}" ]]`.
  Bash documents `-ot` as true when file1 does not exist and file2 does, so that expression passes
  **exactly when the lock is already gone** — fail-open in the one state the guard exists to catch.
  A second brief then reproduced the same form. Nothing in Step 3 or Step 4 asks for a recommended
  idiom to be run; I caught it only by testing it on my own initiative, and the corrected form
  (`[[ -d "${lock}" && … ]]`) had to be pushed back into the research round.
- **Skill cause:** Step 6 requires every `verify:` be executed before the plan is committed, which
  catches a dead *gate*. There is no equivalent for the *design* a brief recommends, even though
  Step 3 explicitly invites briefs to drive the script and they arrive carrying source. So the one
  artefact the plan copies verbatim into the highest-risk function is the one artefact no step
  requires anybody to run.
- **Recommended fix:** Add to Step 4: any shell idiom a brief recommends and the design adopts is
  executed against the portability floor first, and PLAN records what it returned. One line, and it
  is the same discipline Step 6 already applies to gates.
- **Confidence:** high · **Effort:** small

## F4 — Step 6's red-gate rule has no category for a gate blocked on an earlier phase
`origin=uvm-plan:6 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** Step 6 sorts a red gate into two kinds — red on the asserted post-condition
  (good) or red for its own reasons (bad). Two of four phases here gate on a deliverable an earlier
  phase produces, so at plan time they died on `tests/lock-race.sh: No such file or directory`, which
  is neither. I had to decide the rule did not cover it and invent an idiom — a `test -x … || { echo
  "FAIL: P1 has not landed"; }` guard — so the failure reads as a dependency rather than a broken
  gate.
- **Skill cause:** The rule is written for a single phase in isolation, but the same step tells you to
  author phases as ordered vertical slices with `depends_on`, which makes a gate depending on an
  earlier phase's output the normal case rather than an exception.
- **Recommended fix:** Name the third category in Step 6: a gate whose first unmet clause is an
  artefact from a phase in its own `depends_on` is legitimately red, and should say so in one guarded
  line rather than dying on a raw shell error.
- **Confidence:** high · **Effort:** small

## F5 — The gate-authoring trap list omits `git grep -c`, which the same step recommends using
`origin=uvm-plan:6 severity=low category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** `n=$(git grep -c flock -- bin/uv-manager); [ "$n" = 1 ]` is always false:
  `git grep -c` prints `bin/uv-manager:1`, not `1`. The gate was red while the code was correct, and
  would have walked `--record-attempt` toward the circuit breaker in a phase whose job is to prove
  nothing changed.
- **Skill cause:** Step 6 keeps a good, specific list of gate traps — `! cmd` under `set -e`, an
  interpolated pathspec under `zsh`, a prose anchor spanning a wrapped line — and `git grep` is the
  substitute it recommends by name for a documentation sweep. Its `-c` output shape belongs on that
  list; `grep -c` on a path prints the bare count and is the right spelling for a census.
- **Confidence:** high · **Effort:** small

## F6 — Step 4's "red before the fix" check is unavailable exactly when the skill tells you to retune a gate
`origin=uvm-build:P1 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** Step 4 says a new or retuned `verify:` must be confirmed "red before the fix and
  green after". I retuned P1's gate mid-phase — Step 1 prescribes `set_phase.py --verify` for exactly
  this — but by then the deliverable existed, so the pre-fix state the check wants was gone and the
  new assertion block had never been observed failing. I had to invent a substitute: feed the block a
  `--plant none` run and show it rejects on three of its five keys.
- **Skill cause:** The instruction assumes a gate is authored before the code it grades. The same
  skill prescribes retuning a gate through `set_phase.py --verify` in remediation mode and mid-phase,
  both of which happen *after* code exists, so the check is structurally unavailable in the flow the
  skill itself directs you into. Nothing offers the substitute.
- **Recommended fix:** Say what to do when the pre-fix state is gone: construct an input the new
  assertion must reject and show it rejecting, which is the same evidence in the only form still
  available. One sentence beside the existing red-before-green-after rule.
- **Confidence:** high · **Effort:** small

## F7 — `run_verify.py`'s trace escapes the gate's newlines, so a mangled gate and an intact one look alike
`origin=uvm-build:P1 severity=low category=tooling status=open target=.agents/factory/bin/run_verify.py`
- **What happened:** The trace prints `+ /bin/sh -c 'set -eu\n.agents/factory/bin/lint.sh …'` with
  literal `\n` between every statement. That is precisely the shape of a gate whose newlines were
  lost in reflowing — the failure `run_verify.py` exists to prevent — so I had to reason from the
  gate's *behavior* to establish that the string it executed was intact.
- **Skill cause:** Step 4 mandates this tool on the grounds that hand-copying a wrapped gate is where
  a quoting error enters, then the tool renders its own input in a form indistinguishable from that
  error. A reader who trusts the trace concludes the opposite of the truth.
- **Recommended fix:** Print the gate as a real multi-line block before the `+` line, or escape
  nothing and let it wrap. Either makes a genuinely collapsed gate visibly different.
- **Confidence:** high · **Effort:** small
