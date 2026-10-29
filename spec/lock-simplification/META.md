# META — Stop breaking the lock, and split provisioning from repair

- **slug:** lock-simplification

## What worked well

- `uvm-review` *debate* on the lock/install/select diff: the two stances agreed on every R-ID, and the block stance alone found the prose defects (F1, F2 in REVIEW.md) by building states the ship stance's reading had passed.

- `uvm-feature` Step 4, *Promoting an issue* (`shaped`): "re-confirm the scope still holds against current `main`" caught that the seed's line numbers, sizes and two function names came from a reverted branch, before a plan inherited them.

- `uvm-plan` Step 6, *prove the gate can go green* on a throwaway copy: it caught a self-red in the R12 gate (an `ln`-shim check applied to the unsatisfiable burst, where no `ln` is ever called) before `/uvm-build` would have spent attempts on it.

- `uvm-build` Step 3, *re-measure a rate at the researched size*: 40 bursts against P1's wrapper showed the barrier's red rate collapsing to zero after about 16 bursts in every run, which the brief's 20-burst sample could not show. The cause (the barrier globbing a growing directory) was fixed before the gate depended on it.

## Friction findings

## F1 — Step 5 runs every literal *Checked by* command, but allowed-tools cannot run `tests/`
`origin=uvm-feature:5 severity=low category=tooling status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** Step 5 requires running every literal *Checked by* command against the current tree. This GOAL's collateral criterion (R14) is `tests/lock-race.sh --plant control …`. The skill's `allowed-tools` grants `Bash(.agents/factory/bin/*)`, which covers every `temp_root.sh` drive, and `git grep`, but not `tests/*`, so on a harness that enforces the frontmatter that Step 5 command cannot run as written.
- **Skill cause:** Step 5 was added (one stage earlier than `/uvm-plan` Step 6) without widening `allowed-tools` to match. The repository already has a committed drive under `tests/`, and AGENTS.md names it as the gate for lock changes.
- **Recommended fix:** Add `Bash(tests/*)` to `allowed-tools`, or say in Step 5 which commands may be left for `/uvm-plan` Step 6 and how to record that they were.
- **Confidence:** high · **Effort:** small

## F2 — No seed status records "superseded by an adopted cycle"
`origin=uvm-feature:4 severity=low category=missing-guidance status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** The seed being promoted superseded two others. One already read `adopted:` from an earlier cycle; the other (`issues/lock-owner-write-errno.md`) is `unshaped` with a prose banner saying it is superseded. The skill's status vocabulary (`unshaped`, `shaped`, `adopted:`, `declined`, `accepted-behaviour`) has no value for it, so it stays `unshaped`, and a later `/uvm-feature` on it would treat a dead seed as a live candidate. The foreman had to give hand instructions for what to edit.
- **Skill cause:** *Promoting an issue* covers a seed this GOAL promotes and a seed it writes into, but not a seed it supersedes, although `ROADMAP.md` already carries **superseded** markers that `/uvm-roadmap` relies on.
- **Recommended fix:** Add a third case to Step 4: a seed the promoted one supersedes gets a `superseded:{slug}` status (or the existing `declined` with a pointer), its ROADMAP Seed line gets the **superseded** marker pointing at `spec/{slug}/`, and `/uvm-roadmap` retires it with the cycle. Add `superseded:` to the STOP list beside `declined`.
- **Confidence:** med · **Effort:** small

## F3 — Silent on whether a promoted seed's R-IDs keep their numbers
`origin=uvm-feature:4 severity=low category=instruction status=open target=.agents/skills/uvm-feature/SKILL.md`
- **What happened:** `ROADMAP.md` and two sibling seeds cite this seed's draft R-IDs by number ("absorbs R3 … as R4", "contributes R5 and R6", "R11 moves … as R6"). Folding in a second seed and a newly confirmed criterion forced a choice between renumbering, which would falsify those citations, and keeping R1–R9 and appending. The GOAL kept them, but that was a judgement the skill could have made.
- **Skill cause:** The skill says "stable R-IDs" and "do not copy verbatim", and for `shaped` seeds "adopt largely as written", but never says whether stability starts at the GOAL or at the seed. The repository already treats seed numbers as stable (`lock-break-instance-identity` R3 left vacant rather than closed up) without the skill saying so.
- **Recommended fix:** One sentence in *Promoting an issue*: a `shaped` seed's R-IDs keep their numbers in the GOAL when anything outside the seed cites them, additions are appended, and a removed number is left vacant, not reused.
- **Confidence:** med · **Effort:** small

## F4 — Gate traps table offers `grep -c` as the fix without its exit status
`origin=uvm-plan:6 severity=low category=template status=open target=.agents/factory/templates/TECH.md`
- **What happened:** The table's row for `git grep -c` recommends `grep -c P path`, "which prints the bare count". At zero matches `grep -c` prints `0` and exits 1. The GOAL's R9 *Checked by* (`uvm help | grep -c UVM_LOCK_STALE`) has exactly that shape, and it reads red on a correct tree under any gate keyed on status. The plan had to replace it with `if … | grep -n P; then FAIL; fi`.
- **Skill cause:** The template's own recommended replacement carries an unlisted trap, and `/uvm-feature` copies its *Checked by* idioms from that table.
- **Recommended fix:** Amend the row: `grep -c` prints the bare count but exits 1 at zero. Use it only inside `n=$(… ) || true` or a comparison; to assert absence, write `if … grep -n P; then FAIL; fi`.
- **Confidence:** high · **Effort:** small

## F5 — No shape for a phase whose evidence arrives from outside the build
`origin=uvm-plan:6 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** R4 (c) needs a Slurm drive that only the foreman can submit, so P5's gate is red until a human returns evidence. The FSM has no waiting state. `/uvm-build` would treat the red as a failed attempt and walk `--record-attempt` toward the circuit breaker at 3 while the code is correct. The plan carries the foreman's rule ("an external wait splits a phase into two runs") by hand: Run A builds and hands back, Run B reads the evidence, and Run A's red is explicitly not an attempt.
- **Skill cause:** Step 6 sorts reds into four kinds and covers a red "on an artefact a phase in its own `depends_on` has yet to produce". It has no category for an artefact a *person* produces, and neither does `/uvm-build`'s attempt rule.
- **Recommended fix:** Add the Run A/Run B split to Step 6 and to `templates/TECH.md`. The gate guards the external artefact with a message naming it, and the phase body says that red is not an attempt. Teach `/uvm-build` to stop without `--record-attempt` when the only failing clause is that guard.
- **Confidence:** med · **Effort:** small

## F6 — The first `set_phase.py` call re-serializes the whole frontmatter
`origin=uvm-build:P1 severity=low category=tooling status=open target=.agents/factory/bin/set_phase.py`
- **What happened:** Step 5's `set_phase.py --phase P1 --phase-status done --current P2 --top-status in_progress` changed three fields and rewrote all ~390 frontmatter lines: flow lists became block lists, list items lost their indent, double quotes became single, and the blank line after the closing `---` went. The commit's `TECH.md` diff is ~800 lines, and a reviewer cannot see the state change in it. Proving that no `verify:` string moved took a throwaway PyYAML comparison of every phase against `HEAD`.
- **Skill cause:** `/uvm-plan` writes the frontmatter in the template's hand style, and the skill says to regenerate it with a script whose emitter does not keep that style. So the first build commit of every cycle carries this reflow.
- **Recommended fix:** Make `set_phase.py` emit the template's style (flow lists for `satisfies`/`depends_on`, the indented `- id:` list, `|` for `verify`), or have `/uvm-plan` normalize through `set_phase.py --touch` before its own commit so the reflow lands with the plan. Either way, have it print a parsed before/after field diff.
- **Confidence:** high · **Effort:** small

## F7 — A gate that reads `HEAD` cannot go green before the commit Step 7 makes
`origin=uvm-build:P2 severity=low category=missing-guidance status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** P2's gate builds its red-state copy with `git archive HEAD` and overlays P1's wrapper, so it runs the *committed* `tests/lock-race.sh`. Before the phase commit that is the old instrument, which refuses `--plant held` with exit 2, so the gate cannot pass on the working tree however correct it is. Step 4 says verify, then Step 7 commits code and state atomically. The build had to commit the code with the state unchanged, run the gate on that commit, then fold the state in with `git commit --amend`.
- **Skill cause:** `/uvm-plan` Step 6 proves a gate red and green on throwaway copies, where the instrument is already in place, and says nothing about a gate whose input comes from git history rather than the working tree. `/uvm-build` assumes every gate reads the working tree.
- **Recommended fix:** In `/uvm-plan` Step 6, require a gate that archives the tree to archive the working tree (`w=$(git stash create); git archive "${w:-HEAD}"`, which leaves the stash stack alone), and keep history reads to the commit it looks up by subject. Failing that, have `/uvm-build` Step 7 name the commit-then-amend order for such a gate.
- **Confidence:** high · **Effort:** small

## F8 — Review blindness hides evidence the plan routes to the reviewer
`origin=uvm-review:2 severity=low category=missing-guidance status=open target=.agents/skills/uvm-review/SKILL.md`
- **What happened:** TECH's P5 *Inspection-only* list says "the reviewer reads both evidence files for anything identifying", and GOAL R4 (c) is graded on `spec/{slug}/evidence/`. Step 2's blindness rule keeps the reviewer out of `spec/` except a cited landed-cycle record, so both reviewers took R4 (c) on trust, and the orchestrator had to read the evidence itself.
- **Skill cause:** the declared-readable exception covers "a landed cycle's retained record", not this branch's own evidence. Evidence files carry measurements, not author intent, so the blindness rationale does not apply to them.
- **Recommended fix:** extend the Step 2 exception to `spec/{slug}/evidence/` when a GOAL R-ID or an inspection item names it. Alternatively, say in Step 3 that the orchestrator grades those files and records it in REVIEW.md. This does not weaken blindness: PLAN, TECH, research and META stay out.
- **Confidence:** med · **Effort:** small

