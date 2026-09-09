---
status: unshaped
kind: fix
appetite: small
lane: public
---

# The owner write is classified by the directory a moment later, not by the errno

> **Superseded on 2026-09-09 by [`lock-simplification`](lock-simplification.md).** This defect rides
> on a robbed winner, and nothing takes a lock by force after that cycle. Confirm at promotion; if the
> fatal path's unqualified `rmdir` survives independently of the robbery, it moves there as an R-ID.

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

`uvm_acquire_lock` wins `mkdir`, writes `owner`, and on failure decides between two very different
causes by testing whether the lock directory is still there:

```sh
if [[ -d "${lock}" ]]; then
  rmdir "${lock}" 2>/dev/null || true
  die "cannot record ownership of the provisioning lock at ${lock}/owner"
fi
```

(`bin/uv-manager:362-365`.) A failed redirect leaves the shell no errno a branch can read, so the
directory's presence is standing in for the errno. The two do not always agree. The write fails at
one instant and the test runs at the next, and in between another rank can win `mkdir` at the same
path — at which point a robbed winner reads as a filesystem fault, takes the fatal branch, and exits
1 with empty stdout. That is the shape `invariants.md` §7 exists to prevent and the one
`lock-acquire-retake` R1 was written to remove.

The branch selection is confirmed by construction. A `mkdir` shim that leaves `owner` as a dangling
symlink makes the write open `ENOENT` while the directory stands:

```sh
.agents/factory/bin/temp_root.sh --offline --arch testarch sh -s <<'EOF'
sh="$UVM_SANDBOX/shim"; mkdir -p "$sh"
cat > "$sh/mkdir" <<'SHIM'
#!/bin/sh
case "${1:-}" in
  *.install.lock) /bin/mkdir "$1" || exit $?; ln -s /nonexistent/target/owner "$1/owner"; exit 0 ;;
esac
exec /bin/mkdir "$@"
SHIM
chmod +x "$sh/mkdir"; PATH="$sh:$PATH"; export PATH
uv --version; echo "rc=$?"
EOF
```

Observed: `rc=1`, empty stdout, `…/owner: No such file or directory` then `cannot record ownership`.

**That construction is outside the case this seed is about.** There the write failed because the
symlink target was missing while the lock directory itself stood; it demonstrates the discriminator's
shape, not a lost race. The in-contract case — directory removed at write time, recreated before the
`-d` test — was **not** reproduced: 5760 ranks of 64-way contention against a planted dead-holder lock
produced zero failures, and branch instrumentation over 1920 of them caught three real robberies, all
three retaken, none routed to the fatal branch. The same harness failed `main` at 1 in 768 with the
documented signature, so the construction does reach the race.

The window is a single builtin test with no forks between the failed redirect and `[[ -d ]]`, which is
why the residual rate is far below the 0.10 ms `mkdir`-to-`owner` window that produces the robbery in
the first place. Small, not closed.

A workable discriminator exists without the `set -euo pipefail` landmine that
`spec/lock-acquire-retake/GOAL.md` § *Non-goals* rejects: `printf … 2>"$errfile" > "${lock}/owner"`
captures the shell's own diagnostic to a file with no subshell, so the errno itself can decide, and
the file is re-emitted on the fatal path to keep the errno reaching stderr. Unverified — it is a
sketch, not a design.

## Why it was deferred

`lock-acquire-retake` cycle 1 review recorded it as **PLAUSIBLE**, not CONFIRMED: the mechanism is
real by reading and by an out-of-contract construction, but the in-contract case survived 5760 ranks
of the regime that produces it. The rubric surfaces PLAUSIBLE findings for triage and does not
auto-loop them, and blocking a cycle on an unreproduced finding in this repository manufactures the
bloat the project is trying to avoid.

**Pre-existing in kind, narrowed in degree.** `main` dies on *every* robbery; the shipped cycle
retakes all but this residue. Nothing here is a regression introduced by that cycle — it is the part
of R1 that the chosen discriminator does not reach.

A second, related defect rides the same branch and is recorded here rather than separately: the
`rmdir "${lock}"` on the fatal path is unqualified by ownership, the removal-by-path shape
`invariants.md` §5 forbids for `uvm_unlock`. In the scenario above the directory belongs to another
rank that has not yet written its `owner` file. It is also pre-existing — `main` runs that `rmdir` on
every write failure, so the shipped code performs strictly fewer — but whatever fixes the classifier
has to decide what that branch does, so the two travel together.

## Outcome / vision

The owner write is classified by why it failed, not by what the directory looks like afterwards. A
lost race retakes, a genuine fault dies carrying its errno, and neither answer depends on what another
rank did in the gap between two statements. The fatal branch removes only a directory this process can
show it owns.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — WHEN the `owner` write fails, the wrapper SHALL decide between retake and fatal from the
  errno the write reported, not from the lock directory's presence at a later instant.
- **R2** — IF the write failed for a reason other than the lock directory being absent, THEN the
  wrapper SHALL still exit non-zero with the errno on stderr. (Carried forward unchanged from
  `lock-acquire-retake` R2 — this is what stops the change turning a real fault into a silent retry.)
- **R3** — The fatal path SHALL NOT remove a lock directory this process cannot show it created.
- **R4** — The `absent`, `waited`, `broke` and `robbed` counters SHALL be unchanged. Every previous
  remediation to this function shipped collateral rather than failing at its target.
- **R5** — The diagnostic capture SHALL NOT abort the shell under `set -euo pipefail`.
  `spec/lock-acquire-retake/GOAL.md` § *Non-goals* records the measured failure of the obvious
  `err=$( { … } 2>&1 )` form: it aborts before any `die`, loses `cannot record ownership` entirely,
  and exits a bare 1.

## Notes

- **Prose that moves with the fix.** `AGENTS.md:157` and `.agents/factory/invariants.md:83-87` both
  assert that a directory still standing means the write itself was refused. That is true of every
  case measured so far and the code matches it, so it is correct today — but a cycle that narrows the
  discriminator to the errno overturns it, and `AGENTS.md` § *Same-commit rule* makes both edits part
  of that diff.
- **Verification limit.** The shim construction depends on `mkdir` remaining an external command
  invoked with the lock path as its sole argument (`bin/uv-manager:347`). A change to a builtin or a
  different call shape makes the gate stop constructing the state it exists to construct, and the
  failure mode is that it passes. Same caveat `spec/lock-acquire-retake/GOAL.md` § *Verification
  limit* declares.
- **The residual was measured and is rarer than PLAUSIBLE suggested, not commoner.**
  `lock-break-instance-identity` planning built a concurrency drive and instrumented every removal
  site on `main`. Over **7680 planted ranks** the fatal branch at `:363` was entered **once**, and
  its `rmdir` **failed** — it destroyed nothing. All 48 robbery events in that run came from the
  break block at `:459-460`. An earlier brief in the same cycle reported the destructive form twice
  in 1280 ranks; the per-site instrumentation **corrects that**, and the correction is recorded in
  [`spec/lock-break-instance-identity/research/07-candidate-remedies.md`](../spec/lock-break-instance-identity/research/07-candidate-remedies.md)
  finding 2. The reach is the square of a 0.27 ms window — our `mkdir` must succeed, our `owner`
  write must fail ENOENT, *and* a third rank must re-`mkdir` inside that window — and then `rmdir`
  still refuses as soon as that rank writes its own `owner`.
- **That lowers the priority and does not make the branch correct.** `[[ -d "${lock}" ]]` is still a
  path test standing in for an errno. The honest reading of R3 is sharper than this file's wording:
  removing only what this process can show it owns means removing **nothing**, because a rank on this
  path never recorded ownership. Whoever promotes this should settle that before sizing a gate — a
  defect reachable once in 7680 ranks is not measurable from a burst, so the mechanism is graded by
  reading whatever the harness can do. The drive itself lands at `tests/lock-race.sh` and its
  `--plant owner` construction is reusable verbatim.
- Related: [`issues/lock-break-instance-identity.md`](lock-break-instance-identity.md) — its R2 is the
  race that *creates* the robbery. Closing that would make this residue unreachable, so whichever
  lands first changes the case for the other. **It went first**, adopted 2026-09-08 as
  [`spec/lock-break-instance-identity/`](../spec/lock-break-instance-identity/GOAL.md), where the
  same requirement is R3. So the question to settle before promoting this is whether the robbery is
  still reachable at all; if that cycle lands, this may be a terminal record rather than a cycle, and
  the fatal path's unqualified `rmdir` — the second defect on the same branch — is then the only
  live half. [`issues/test-harness.md`](test-harness.md) R3e owns the
  regression test for the retake this builds on.
- Found by: `lock-acquire-retake` review cycle 1 (`debate` variant), F1 and F2 —
  [`spec/lock-acquire-retake/REVIEW.md`](../spec/lock-acquire-retake/REVIEW.md).
