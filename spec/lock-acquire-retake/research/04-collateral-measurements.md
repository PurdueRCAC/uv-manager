# Research 04 — collateral measurements, after the retake landed

The point of this record is R4 and R6: the retake was allowed to change one thing, and this is the
evidence it changed nothing else. Measured against the tree at `P1`
(`[fix] Build lock-acquire-retake P1`), on GNU bash 3.2.57 / `arm64-apple-darwin25`, every drive
through `.agents/factory/bin/temp_root.sh --offline`. Pre-change figures are from
[`02-gate-baselines.md`](02-gate-baselines.md), taken against `e3538d3`.

## Results

| Drive | Post-condition | Pre-change | Post-change | Verdict |
|-------|----------------|-----------|-------------|---------|
| R4a — fresh foreign lock | rc | 1 | 1 | unchanged |
| | elapsed vs `UVM_LOCK_TIMEOUT=5` | ~6s | 6s | unchanged |
| | `timed out after 5s` lines | 1 | 1 | unchanged |
| | holder named from `owner` | yes | 1 match | unchanged |
| | break notes emitted | 0 | 0 | unchanged |
| R4b — denied break | rc | 1 | 1 | unchanged |
| | `breaking stale provisioning lock` lines | 1 | **1** | unchanged |
| | timeout lines | 1 | 1 | unchanged |
| R4c — absent-lock retry | rc | 1 | 1 | unchanged |
| | `mkdir` attempts before the die | 3 | **3** | unchanged |
| | `cannot create provisioning lock` | present | 1 match | unchanged |
| R6 — ordinary hold | rc | 0 | 0 | unchanged |
| | stdout | `uv 9.9.9 (fixture)` | `uv 9.9.9 (fixture)` | unchanged |
| | `current` target | `versions/9.9.9` | `versions/9.9.9` | unchanged |
| | lock left behind | none | none | unchanged |
| | `flock` matches in the script | 1 | 1 | unchanged |

No divergence. `absent`, `waited` and `broke` behave exactly as the earlier review cycles graded
them, and the single-download hold is intact.

## Divergences in the *drives*, not in the behavior

- **R4b's elapsed time is 3s here against 9s in `02`.** The knobs differ, not the wrapper: `02` drove
  it at `UVM_LOCK_TIMEOUT=8`, this gate at `3`, because the committed gate ages the lock with
  `UVM_LOCK_STALE=4` and a `sleep 5` rather than with `touch -t` and BSD-only `date` arithmetic. The
  counted post-condition — exactly one break note across the whole wait — is what R4b asserts, and it
  is identical.
- **R4a's 6s against a 5s timeout** is the `date +%s` resolution plus the loop's own `sleep 1`
  granularity, the same slop `02` recorded. The gate asserts a 4-8s window for this reason rather
  than a value.

## Gate amendment made during this phase

The R4b drive `chmod 555`s the sandbox's architecture directory to deny the break's `rmdir`, then
restores it. An abort between those two points leaves a directory `temp_root.sh` cannot remove, and
the sandbox survives the run — reproduced accidentally while taking these measurements with an
ad-hoc script, which cost a manual `chmod -R` and a `del` to clear. The committed gate could not
abort there as written, but the hazard is one edit away and its cost is litter a later run cannot
clean, so the drive now arms `trap 'chmod 755 "$A" 2>/dev/null || true' EXIT` before it drops the
permissions. The explicit restore stays; the trap covers the failure paths, including the drive's
own `exit 1`.

## What this record does not establish

- **The R4b sub-path is narrower than the criterion reads.** The construction denies `rmdir` but not
  the `rm -f` of the owner file, so the second iteration finds no owner and a fresh directory mtime
  rather than re-deciding a break and being denied again. "Exactly one" is therefore a real
  regression check on the `[[ -n "${broke}" ]] ||` guard but does not cover the both-halves-denied
  case, which needs `chflags`/`chattr` and is not portable
  ([`02`](02-gate-baselines.md) § E). Unchanged from the plan; restated so review does not over-read
  the green.
- **No drive races two processes.** Every state here is constructed single-process, which is what
  makes these deterministic. The race that robs a winner is still
  `issues/lock-break-instance-identity.md` R2, and still blocked on the concurrency harness.
- **`mkdir` atomicity on Lustre, GPFS and NFS** is untested and unchanged; R6 pins the discipline
  rather than revisiting it.
