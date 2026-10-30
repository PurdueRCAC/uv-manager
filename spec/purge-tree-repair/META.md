# META — `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`

> **Harness feedback log** for this feature. Written by the lifecycle skills when the **skillset
> itself** costs something; read by `uvm-publish` and applied by `/uvm-harness`. Silence is the
> default. The blind `uvm-review` correctness reviewer never reads this file.

- **slug:** purge-tree-repair

## What worked well

- `uvm-plan` Step 6's "prove the gate can go green on a throwaway copy". Built as a whole-design
  prototype, it caught a double-counting message design, a leaked-assignment gate trap and a
  `$!`-is-a-subshell kill that never fired, all before the plan was committed.

## Friction findings

## F1 — The throwaway-copy recipe acts on the real repository from a worktree
`origin=uvm-plan:6 severity=medium category=instruction status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** Step 6 prescribes `cp -R . "$(mktemp -d)/probe"`. From a git worktree the
  copy's `.git` is a file pointing at the real repository's worktree gitdir, so every git command in
  the copy acts on the real repository. A `git init` in the copy tried to write the main
  repository's `config`, and only the agent sandbox's write fence stopped it. A `git grep` or `git
  status` there would read, and refresh, the real worktree's index.
- **Skill cause:** the recipe assumes `.git` is a directory that `cp -R` duplicates, and every
  lifecycle step here runs in a worktree, where it is not.
- **Recommended fix:** after the copy, `mv "$probe/.git" "$probe/../dotgit"` and `git -C "$probe"
  init -q && git -C "$probe" add -A`. Add a throwaway commit with signing off, on a branch named
  `main`, because `lint.sh`'s skill-injection check runs `git log main`. Then say that the gates'
  `git grep` read the copy's own index.
- **Confidence:** high · **Effort:** small

## F2 — A POSIX `sh` assignment in front of a function call persists, and the gate-trap table lacks it
`origin=uvm-plan:6 severity=low category=template status=open target=.agents/factory/templates/TECH.md`
- **What happened:** a gate helper `ranks N CMD…` was a shell function. `VAR=x ranks …` left
  `UVM_REPAIR` and `SLURM_JOB_ID` set in the gate's shell after the call, as POSIX specifies for
  function calls. The next drive's provisioning call ran with the knob on, recorded an outcome on an
  undamaged tree, and the drive read zero repairs where one was required. It was red against correct
  code. A bare `wait` in a gate that plants a `sleep 60` holder cost 60 s the same way.
- **Skill cause:** the *Gate traps* table is the place a gate author checks shell semantics, and it
  has neither row.
- **Recommended fix:** add two rows.
  - Written as `VAR=x fn …`: the assignment persists after a function call in POSIX `sh`. Write
    instead `fn env VAR=x cmd …`, or a subshell.
  - Written as a bare `wait`: it also waits for a planted holder. Write instead `wait $pids`.
- **Confidence:** high · **Effort:** small

## F3 — `set_phase.py` re-emits every `|` gate as an escaped double-quoted scalar
`origin=uvm-build:P1 severity=medium category=tooling status=open target=.agents/factory/bin/_fsm.py`
- **What happened:** Step 5's first `set_phase.py` call rewrote the whole frontmatter, as
  `lock-simplification` F6 recorded (· seen again). Here it also turned all five literal block
  (`|`) gates into folded double-quoted scalars full of `\n`, `\"` and `\` continuations, the style
  the TECH template reserves for one-liners. The `TECH.md` diff is ~950 lines for three changed
  fields, and proving no gate moved took a PyYAML comparison of every phase against `HEAD`.
- **Skill cause:** the skill forbids hand-editing the YAML and the template mandates `|` for any
  multi-line gate, but `dump_document` uses a bare `yaml.safe_dump`, which never emits block style,
  so the mandated script destroys the mandated form on every cycle.
- **Recommended fix:** give `dump_document` a representer that emits any multi-line string with
  `|` (and flow style for `satisfies`/`depends_on`), and have `set_phase.py` print a parsed
  before/after field diff.
- **Confidence:** high · **Effort:** small

## F4 — Phase gates proven against a whole-design prototype miss per-phase lint
`origin=uvm-build:P2 severity=low category=instruction status=open target=.agents/skills/uvm-plan/SKILL.md`
- **What happened:** P2's checklist asked `uvm_detect` to set `uvm_damaged_pythons`, which only P3's
  interpreter arm reads. Built as written, P2's own gate goes red at `lint.sh` (shellcheck SC2034).
  The flag moved to P3 by a `TECH.md` amendment.
- **Skill cause:** `uvm-plan` Step 6 proves every gate green against one prototype of the whole
  design, so a phase is never linted in the state its own commit leaves; a symbol set in one phase
  and read in a later one is invisible there.
- **Recommended fix:** in Step 6, also run each phase's gate (or at least `lint.sh`) against the
  prototype cut back to that phase, or tell the planner to assign a flag to the phase that reads it.
- **Confidence:** high · **Effort:** small

## F5 — `uvm-build` has no stop for a gate that waits on an external run · seen again
`origin=uvm-build:P5 severity=low category=missing-guidance status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** P5 Run A ends on a red gate by design, at the clause guarding the cluster
  evidence. The skill's Step 4 calls a still-red gate a STOP to be recorded with `--record-attempt`,
  and Step 7's subject assumes a completed phase. Only `TECH.md` (the P5 body and *How `uvm-build`
  drives this*) said that this red is not an attempt and that Run A commits with the phase
  `in_progress`.
- **Skill cause:** the Run A/Run B split is a factory pattern used in two cycles now, and the skill
  that executes it does not name it. Seen again: `lock-simplification` META F5 asked for the same
  teaching.
- **Recommended fix:** in Step 4, add the external-wait case: when the only failing clause is a
  guard naming an artefact a person produces, stop without `--record-attempt`, leave the phase
  `in_progress`, and commit as `Build {slug} {id} Run A: …`. Mention it in Step 7's subject rule.
- **Confidence:** high · **Effort:** small

## F6 — Review blindness hides this branch's own evidence (seen again: `lock-simplification` F8)
`origin=uvm-review:2 severity=low category=missing-guidance status=open target=.claude/skills/uvm-review/SKILL.md`
- **What happened:** R12 is graded on `spec/purge-tree-repair/evidence/`, which both blind reviewers may not open. They took its cross-node half on trust, and the orchestrator graded the files and recorded that in REVIEW.md, the second alternative `lock-simplification` F8 recommends.
- **Skill cause:** Step 2's declared-readable exception covers a landed cycle's record, not this branch's evidence, and Step 3 doesn't say who grades it.
- **Recommended fix:** as `lock-simplification` F8. Step 3 should say the orchestrator grades `spec/{slug}/evidence/` against the R-ID that names it and records it in REVIEW.md.
- **Confidence:** high · **Effort:** small

## F7 — The sandboxed drives cannot see user configuration, so a defect that needs it passes every gate
`origin=uvm-review:3 severity=medium category=missing-guidance status=open target=.claude/skills/uvm-plan/SKILL.md`
- **What happened:** `temp_root.sh` scrubs `UV_*` and redirects `XDG_CONFIG_HOME`, and the drives run from a neutral directory. The interpreter repair followed a `.python-version`, the global pin or `UV_PYTHON` (cycle 1 F1), yet every phase gate and the R12 cluster drive passed, because no drive configured a request. Only the block reviewer's adversarial drive found it.
- **Skill cause:** plan's gate guidance does not ask which user configuration (uv's environment variables, config files, pin files, working-directory files) can change a wrapped `uv` subcommand's behavior, so no gate covered it.
- **Recommended fix:** when a phase runs `uv` on the user's behalf, plan names the configuration sources that steer that subcommand and gives at least one gate case per source.
- **Confidence:** med · **Effort:** small

## F8 — Remediation mode does not say what invalidates committed evidence
`origin=uvm-build:P5 severity=medium category=missing-guidance status=open target=.agents/skills/uvm-build/SKILL.md`
- **What happened:** review cycle 1's F1 changed the interpreter arm that R12's cluster evidence
  measured at `4c08e9c`. P5's gate checks only that `evidence/lustre.txt` and `evidence/gpfs.txt`
  exist and read right, so it stayed green after the fix; re-running every gate, as Step 1.3 asks,
  could not show that the evidence no longer described the code. The brief had to prescribe the
  reopen: `git mv` the files to `evidence/cycle0/` so the presence guard goes red, the external
  wait again (F5).
- **Skill cause:** Step 1.3 reopens phases by `satisfies` and re-runs gates, which catches a code
  assertion a fix broke but not a recorded artefact taken at an older commit. Nothing names the
  commit the evidence was taken at, and nothing says a remediation touching the measured path
  retires it.
- **Recommended fix:** in Step 1.3, a remediation that edits code an evidence phase measured reopens
  that phase and moves its evidence to `evidence/cycle<N>/`. Better, the evidence summary carries
  the commit it ran at and the gate compares it with the last commit touching `bin/uv-manager`, so
  stale evidence is red without anyone remembering.
- **Confidence:** high · **Effort:** small
