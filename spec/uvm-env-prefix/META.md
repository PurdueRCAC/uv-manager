# META — Rename the `UV_MANAGER_*` environment prefix to `UVM_*`

> **Harness feedback log** for this feature — the producer artifact of the factory's self-improvement
> loop. Written by the lifecycle skills (`uvm-feature` / `uvm-plan` / `uvm-build` / `uvm-review`) when
> the **skillset itself** costs something; read by `uvm-publish` (surfaced in the PR) and applied by
> `/uvm-harness`. This file is **orthogonal** to the `GOAL → PLAN → TECH → REVIEW` spine — it is about
> the *toolchain*, not the feature — and is retained on merge like the rest of `spec/{slug}/`.

- **slug:** uvm-env-prefix

## What worked well

- `uvm-feature` Step 4's `status: unshaped` branch. The seed had drafted an `R5` reading
  `<compatibility behavior, once the human has chosen>`, and the instruction to treat draft R-IDs as
  input rather than contract is what turned that placeholder into the single blocking question instead
  of a guess.

## Friction findings

## F1 — GOAL template has no escape hatch for a criterion that is not drive-verifiable
`origin=uvm-feature:step-4 severity=low category=template status=open target=.agents/factory/templates/GOAL.md`
- **What happened:** the template requires every criterion to be observable from a `temp_root.sh`
  drive, and offers exactly one exception — "if one genuinely requires a real cluster, say so in the
  criterion." A rename cycle's documentation criteria (R5, R7 here) are verifiable by `git grep` and by
  nothing else; neither the rule nor its exception covers them, so I invented an out-of-band annotation
  line under the criteria list.
- **Skill cause:** the template generalizes from behavioral cycles. Documentation sweeps are a standing
  category of work in this repository — the same-commit rule in `AGENTS.md` guarantees most cycles
  carry one — so the omission is in the guidance, not in the task.
- **Recommended fix:** extend the template's exception sentence to name the second case: a criterion
  verified by static inspection states its check inline (`git grep -n …`), the way a cluster-only
  criterion states its dependence. Costs one sentence and removes the invented convention.
- **Confidence:** high · **Effort:** small
