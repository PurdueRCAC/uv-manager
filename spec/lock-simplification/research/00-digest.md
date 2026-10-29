# 00 — Digest: decisions the briefs settle

Five read-only briefs were fanned out for `appetite: big` on a high-blast-radius change
(`uvm_acquire_lock`, `uvm_unlock`, `uvm_install`, `uvm_point_current`). The fan-out was not narrowed.
Every measurement was taken on macOS with `/bin/bash` 3.2.57 and BSD `mv`. Statements about GNU
coreutils, busybox and bash 5 come from source or changelogs, and the briefs say "read, not run"
beside them.

| # | Brief | Settles |
|---|-------|---------|
| 01 | [wait contract](01-lock-wait-contract.md) | The shape of `uvm_acquire_lock` and `uvm_unlock`, the predicate API, the notice threshold, R11, and the R5/R6 harness |
| 02 | [publish](02-publish.md) | The guarded publish for R4 and R10, and the shim gates |
| 03 | [selection](03-selection.md) | The single selection step for R12 and R13, the `current` swap, the failure construction, and the hot-path cost |
| 04 | [instrument](04-instrument.md) | The re-pointed `tests/lock-race.sh` (R15), its red/green gate, and the Slurm mode for R4 (c) |
| 05 | [surface](05-surface.md) | `uvm doctor` and `uvm clean lock` (R8), and the R9/R7 census and gate |

## Decisions

1. **Lock API.** The signature is `uvm_acquire_lock ON_TIMEOUT PREDICATE [ARG...]`, with
   `ON_TIMEOUT` ∈ {`proceed`, `fail`}. The predicate runs as `"$@"`.
   - It returns 0 to tell the caller to do the work. The lock is held iff `uvm_lock` is set.
   - It returns 1 when the predicate came true while waiting. Nothing is held then.
   - A missing predicate is refused with `(( $# >= 2 )) || die`. Do not use `${1:?}`: under the
     EXIT trap, bash 3.2 exits 0 on it (01).
   - A forced install passes `false`, so `force` leaves the lock.
2. **Release is by path, and `uvm_lock` is set the moment `mkdir` wins**, before the owner write.
   R11 then needs no second cleanup path: the EXIT trap removes the entry and then the directory (01).
3. **One notice, at `min(30, UVM_LOCK_TIMEOUT)` seconds.** The 30 is a literal, not a knob. Every
   wait that reaches its timeout speaks exactly once before acting. The notice prints the path form
   `rm -f '<lock>/owner' && rmdir '<lock>'`, not `uvm clean lock`. Under a different architecture
   or `UVM_ROOT`, `uvm clean lock --yes` reported success and left the real lock standing (05).
4. **The absent-retry bound of 3 stays.** It guards a measured race (2–4% of ranks) that the
   decision does not touch. The robbed retake goes: nothing robs a winner any more.
5. **Publish: detect, don't prevent.** Keep `mv "${tmp}" "${dest}"` byte for byte, because the
   shims key on it, and capture its stderr. Then (02):
   - If the source landed nested at `${dest}/${tmp##*/}`, a rival won: remove the nested copy.
   - If `mv` failed and `${dest}/uv` is executable, a rival won: discard `${tmp}`.
   - Otherwise clean up and die naming the publish, with `mv`'s errno line.

   This is not the rejected exclusive rename: publish needs no exclusion, and either copy is
   correct.
6. **`uvm_point_current` gains `mv -h`** between `mv -T` and the `rm`+`mv` tail.
   - Without it, the sandbox (BSD) loses `current` and nests `.current.<pid>` inside
     `versions/<ver>` once many ranks select concurrently. That breaks R4, R12 and R15 on macOS
     (02, 03, 04, measured independently).
   - With it: zero misses in 9,600 swaps and 1,408 ranks.
   - `ln -sfn` is worse (03).
7. **Selection converges.** Every success path in `uvm_install` reaches one selection step, *before*
   `uvm_unlock`.
   - A pinned call whose installer delivered another version dies naming the pin.
   - `uvm_ensure_uv` collapses into `uvm_install`. It adds no fork (03).
8. **R12 failure construction: "the 6.6.6 installer delivers 9.9.9"** (`UVM_FIXTURE_VERSION`
   unset). A missing `6.6.6/install.sh` is green on `main` too, so it cannot grade (03).
9. **Doctor reports a standing lock as WARN, never FAIL**, with the owner line verbatim.
   `uvm clean lock` is one case arm. Its dry run prints the owner line and the live-holder warning
   in place of `du` (05).
10. **Instrument plants.** `control` and `held`. A `held` plant is owned by the live burst shell.
    `owner` and `none` go away.
    - Progress (exit 4) means: installer entries ≥ bursts, plant intact and byte-identical, and at
      least one concurrent burst under `held`.
    - Correctness (exit 1) means: the tree keys (`nested_staging`, `nested_current`,
      `stray_staging`, `dist_ok`, `current_ok`), wrong stdout, and non-zero ranks.
    - A release barrier in the spliced fixture hook raises the red rate against the unguarded
      publish to about 0.7 per burst (04).
11. **The Slurm drive is a mode of `tests/lock-race.sh`** (`--launch srun`, `--pin`, `--summary`,
    `LOCKRACE_SHARED`), not a new script. That keeps the GOAL's non-goal ("no committed suite beyond
    `tests/lock-race.sh`") and `lint.sh`'s explicit file list intact, and reuses `temp_root.sh`
    (04).
12. **R9's pattern under-matches.** A single-token supplement
    (`stale|kill -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher`)
    is gated at zero on `AGENTS.md`, `invariants.md` and the config example, and printed for README.
    The GOAL's `uvm help | grep -c` form exits 1 on a correct tree, so the gate uses `if … grep -n`
    (05).

## Contradictions resolved

- The selection brief (03) and the instrument brief (04) both found that the `current`-swap defect
  sits *outside* the region the GOAL names. They are the same finding. The swap fix lands with the
  publish guard (P2), because R15's tree assertion needs it on macOS, and before selection
  convergence (P3), because convergence alone made R12 *worse*.
- Brief 01 offered skipping the notice when the timeout arrives first. Rejected: `min(30, timeout)`
  keeps "every long wait speaks once" true at every timeout.
