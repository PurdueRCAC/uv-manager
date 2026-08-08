# 00 — Digest

Consolidated decisions from briefs `01`–`04`. The fan-out ran despite `appetite: small` because
`uvm_trampolines` is a high-blast-radius region and this change alters what it generates. Subagents
were unavailable in this session, so the briefs were produced sequentially by the planning agent
itself, per the skill's documented fallback.

## Decisions

1. **One line changes in the script.** `bin/uv-manager:476` becomes
   `a=\${UVM_PLATFORM:-\$(uname -m)}`, which the unquoted heredoc emits as
   `${UVM_PLATFORM:-$(uname -m)}` — verified against bash 3.2.57, parsed clean by `dash -n` and
   `/bin/sh -n`, and driven correctly through seven runtime cases including empty-string and
   whitespace keys (`01`).
2. **`:-`, not `-`.** `uvm_init` uses `:-`; an exported-but-empty `UVM_PLATFORM` must fall back to
   `uname -m` at both sites or the divergence returns in a case nobody tests (`01`).
3. **No new process, and one fewer fork when the override is set.** Invariant §10's hot-path rule is
   satisfied without argument (`01`).
4. **The invoker's environment is the only self-consistent answer.** The wrapper never exports
   `UVM_PLATFORM`; both sites read the same variable from the same inherited environment, so within
   any one environment they cannot disagree (`02`).
5. **Five documentation sites go stale**, contradicting `GOAL.md` Q3. All five say a trampoline
   re-resolves `uname -m`; all five become "the platform key" (`04`). The same-commit rule applies.
6. **Gates need no provisioning.** `uvm trampolines` exits 0 on a state root with no `uv`, so no
   `verify:` in this cycle uses `--offline` (`01`, `03`).
7. **Load-bearing greps run under `/bin/sh`.** R4's gate asserts the *absence* of a literal key, the
   exact shape whose false green the rubric warns about twice (`03`).

## Contradiction resolved

`GOAL.md` § *Clarifications* Q3 ("no line becomes stale") versus brief `04` (five stale sites).
**Brief `04` wins** — it enumerated the sites, Q3 reasoned about a different set of sentences (the
`UVM_PLATFORM` variable descriptions, which are indeed fine). This is not a GOAL contradiction
requiring escalation: Q3 explicitly delegated the confirmation to this step, and the R-IDs are
unaffected. Recorded in PLAN §5 so `/uvm-review` sees the correction rather than grading the fix
against the wrong assumption.

## Carried into PLAN §5 as risk, not resolved here

The fix widens exposure to a **mis-propagated** `UVM_PLATFORM`. Today trampolines ignore the variable
and so survive a stale value inherited through `sbatch --export=ALL`; afterwards they share the
wrapper's existing exposure to it. The trade is right — a trampoline resolving correctly while `uv`
itself resolves into the wrong tree is not a safe state — but the failure mode genuinely changes, and
it motivates a one-sentence caution in the conf example that the value must be evaluated on the
executing node (`02`, `04`). That sentence is an addition to a file the standing bias says should
shrink, so it is flagged for the human rather than folded in.
