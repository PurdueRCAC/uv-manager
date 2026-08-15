# 00 — Digest

Three briefs, no contradictions between them. The decisions the plan takes from them:

1. **R5's "forking per file" is loose — the forks are per *distribution*, six of them.** The per-file
   loop is already builtin-only. Removing the `dirname`/`awk`/`basename` processes measures **6.5×**
   (0.52 s → 0.08 s over 100 distributions and 4112 files), better than the seed's estimated 4×.
   [`01`](01-fork-free-record-walk.md)
2. **R1 and R5 collapse into one glob.** Globbing `*.dist-info` rather than `*.dist-info/RECORD`
   detects the missing manifest and drives the walk from the same loop, where the naive reading of R1
   adds a second glob costing ~19.6 ms per 800 distributions. [`01`](01-fork-free-record-walk.md)
3. **One guard decides whether the rewrite is correct: `|| [[ -n "${rel}" ]]`.** Without it, a `RECORD`
   whose last line has no trailing newline loses that entry and the walk goes *silent* on a damaged
   distribution. `awk` has no such behavior, so this is a regression the rewrite can introduce and
   nothing else catches. The phase gate must include such a fixture.
   [`01`](01-fork-free-record-walk.md)
4. **Byte-identical means preserving `awk`'s CSV bug.** Both implementations mis-split a quoted path
   containing a comma, identically. Fixing that is not R5. [`01`](01-fork-free-record-walk.md)
5. **Every gate in this cycle is offline and needs no real uv.** Doctor reads the filesystem only, so a
   fabricated tool tree plus the `--offline` fixture's stub binary drives every branch.
   [`02`](02-doctor-baseline.md)
6. **R6 is preservation, not repair — doctor is already read-only.** No lock, no writes, verified by a
   path+hash manifest before and after. The gate guards against a regression the new probes could
   introduce. [`02`](02-doctor-baseline.md)
7. **The classification rule is one sentence: `FAIL` sets the exit status, `WARN` does not.** Exactly
   one existing finding moves, and it is already spelled `WARN`. No new output vocabulary.
   [`03`](03-remediation-and-exit-status.md)
8. **`uv-manager install` is deleted from the remedies, not replaced.** An ordinary `uv` call
   re-provisions and honors `UVM_PIN` — measured. Three commands become two.
   [`03`](03-remediation-and-exit-status.md)

## Contradiction resolved

Brief `01` measures 6.5× where the seed and `GOAL.md` § *Outcome* say "roughly four times cheaper".
Both are right about their own tree; the ratio is tree-shaped, being dominated by the ratio of
distributions to files. **Recommendation: the phase gate asserts verdict equality and does not assert
a speed threshold**, and the GOAL's "roughly four times" stands as the shaped expectation rather than
being restated as a number the code must hit. R5's own text asks only that the walk be "measurably
faster", which is the right standard.

## Carried forward as assumptions, not findings

- Every measurement is warm local APFS on one host. On Lustre with a cold MDS the filesystem term
  dominates and the relative win compresses; the fork saving remains. Not measurable off-cluster,
  consistent with the caveat in `spec/purge-resilient-run/research/02-bounded-integrity-check.md`.
- `--reinstall` suppressing the upgrade in `uv tool upgrade` is observed behavior on `uv 0.12.3`, not
  documented contract. It should be re-checked when the pinned uv moves. Inherited from research `04`
  §6.
