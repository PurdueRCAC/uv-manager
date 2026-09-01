# GOAL — A rank robbed of its fresh lock dies instead of retaking it

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** lock-acquire-retake
- **kind:** fix
- **appetite:** small

## Problem

`uvm_acquire_lock` wins `mkdir`, then records ownership with a write that is fatal on failure
(`bin/uv-manager:462-465`). The fatality is correct and deliberate — a holder that cannot prove
ownership leaks its own lock for a full stale window, which is why `invariants.md` §5 and `AGENTS.md`
both assert it. But the redirect has two failure modes and the code treats them alike. A genuine
filesystem fault deserves the `die`. **Losing a race does not, and gets one.**

The losing path: rank `W` wins `mkdir` and owns the directory; a losing stale-breaker, still executing
a break it decided a moment earlier, removes the `owner` file and `rmdir`s the directory out from
under `W`; `W`'s redirect opens `ENOENT` and `W` dies having done nothing wrong. The user sees exit 1
with **empty stdout**, preceded by a raw shell diagnostic naming an internal script line:

```
bin/uv: line 461: /…/.install.lock/owner: No such file or directory
uv-manager: cannot record ownership of the provisioning lock at /…/.install.lock/owner
```

On a wrapper that sits under unattended provisioning, `VER=$(uv --version)` comes back empty — the
shape `invariants.md` §7 exists to prevent — and both paths the message names are gone by the time
anyone reads the job log.

**This is authored, not inherited, and that is what puts it in scope.** Before 0.6.0 the same write
was `> "${lock}/owner" 2>/dev/null || true`: a robbed winner continued and installed. Matched A/B on
an identical construction put **the pre-0.6.0 wrapper at zero robbed winners** against the shipped
code's **4 of 1280** (dead-holder plant) and **3 of 1280** (owner-less plant). On the ordinary
cold-start path with no lock planted: **0 of 2304**.

Confirmed as F9 by review cycle 3 of `lock-ownership-and-hold-time`, deferred there by explicit
maintainer override rather than by the review rubric's exception, and **released in 0.6.0**. It is
live on `main` and on a tagged release that sites can clone.

The race that robs `W` is a separate, pre-existing defect and is **not** this cycle's to fix.

## Outcome / vision

A rank that loses the acquire race retakes the lock and carries on, invisibly. A rank that hits a
real filesystem fault still dies, still carrying the errno that names it. The three counters that
bound the surrounding wait loop behave exactly as they do today.

## Acceptance criteria (the contract)

- **R1** — WHEN the wrapper has won `mkdir` and its `owner` write then fails because the lock
  directory is no longer there, the wrapper SHALL reacquire the lock and continue, rather than exit.
  *Checked by a sandbox drive that constructs the state directly: a `mkdir` shim first on `PATH`
  inside `temp_root.sh --offline` creates the lock directory and removes it once, so the wrapper's
  own write opens `ENOENT`. Assert rc 0 and non-empty stdout. Red today at rc 1 with empty stdout —
  the gate and its measured red state are recorded in
  [`issues/lock-acquire-retake.md`](../../issues/lock-acquire-retake.md).*
- **R2** — IF the `owner` write fails for any reason other than the directory having been removed,
  THEN the wrapper SHALL still exit non-zero and SHALL still report the underlying error.
  *Checked by the companion drive: `chmod 500` the lock directory instead of removing it, so the
  write fails `EACCES`. Assert non-zero exit and that the errno reaches stderr. Green today and
  green after — this is the criterion that stops R1 turning a real fault into a silent retry.*
- **R3** — The retake SHALL be bounded by a constant in the script, not by a new environment
  variable, and SHALL NOT reset, bypass or otherwise extend the existing timeout accounting. A rank
  robbed repeatedly SHALL still exit within `UVM_LOCK_TIMEOUT`.
  *Checked by a sandbox drive whose shim removes the directory on every attempt rather than once:
  assert non-zero exit inside `UVM_LOCK_TIMEOUT`, and that the wrapper does not spin past it. The
  "constant, not a variable" half is graded by the reviewer reading the diff, as it is for the
  existing absent-lock retry.*
- **R4** — The behavior of the three counters already governing the wait loop — `absent`, `waited`
  and `broke` — SHALL be unchanged. *Checked by three sandbox drives, one per counter, reproducing
  the post-conditions earlier review cycles graded them against: a fresh foreign lock times out at
  exactly `UVM_LOCK_TIMEOUT` with rc 1; a denied break emits exactly one break note across the whole
  wait; and the absent-lock retry still reports a real permissions fault after its literal bound of
  three. This criterion exists because every previous remediation to this function shipped collateral
  rather than failing at its target, and the R1 gate cannot see collateral.*
- **R5** — A successful retake SHALL be silent on stdout and stderr. *Checked by the R1 drive:
  stdout carries the fixture version and nothing else, and stderr carries no new line attributable
  to the retake. Provisioning already writes installer output to stderr, so the assertion is that the
  retake adds nothing, not that stderr is empty.*
- **R6** — Behavior under the existing single-download hold SHALL be unchanged, and the discipline
  SHALL remain `mkdir`. *Checked by `temp_root.sh --offline uv --version` still reporting the fixture
  version and leaving `current -> versions/<fixture>`, no lock left behind, plus
  `git grep -n flock bin/uv-manager` matching nothing outside the rationale comment.*

## Non-goals (no-gos)

- **The race itself is not fixed here.** The retake makes the robbed winner recover; it does not stop
  the robbery. That is [`issues/lock-break-instance-identity.md`](../../issues/lock-break-instance-identity.md)
  R2, which stays blocked on the concurrency harness that seed's R1 describes. A cycle that closed the
  race would make R1 here unreachable, so the two must not be merged.
- **No suppression of the shell's own diagnostic on the fatal path.** Keeping the raw
  `No such file or directory` off stderr during a *successful* retake is desirable, but the obvious
  implementation is measured-unsafe: `err=$( { printf … > "${lock}/owner"; } 2>&1 )` under this
  script's `set -euo pipefail` aborts the shell before any `die` runs, losing
  `cannot record ownership` entirely and exiting a bare 1 — strictly worse than today. R5 requires
  only that a *successful* retake add nothing; the fatal path keeps the diagnostic that carries the
  errno, which R2 depends on.
- **No new environment variable and no new subcommand.** R3 pins the bound to a constant.
- **No committed regression test.** [`issues/test-harness.md`](../../issues/test-harness.md) owns the
  runner. The obligation is landed there in this same commit as **R3e**, and it is not a restatement
  of R3d: R3d is scoped to defects that need two processes racing on one tree, and this cycle's gate
  is the counterexample — a single-process, deterministic construction of the same class of defect.
- **No change to the lock's location, name, or the fatality of the owner write in general.**
  `invariants.md` §5 keeps "the owner write is fatal"; this cycle narrows *when* by one measured
  case, and R2 is what holds the rest of it.

## Clarifications

- **Q:** Appetite — the seed says `small`, but the remedy restructures the acquire loop in the
  repository's highest-blast-radius function. — **A:** `small` stands. Appetite governs research
  depth, not care: the shape is settled (a bounded retake in the style of the existing `absent`
  counter three lines above), the red gate exists and is deterministic, and the collateral risk is
  answered by R4 being a graded criterion rather than by a research fan-out (resolved 2026-08-27).
- **Q:** Should a successful retake announce itself, as breaks and timeouts do? — **A:** No; R5 makes
  silence a requirement. The existing absent-lock retry is already silent, and a note would fire
  precisely when many ranks contend, putting one line per robbed rank into a job log. The cost is
  accepted knowingly: a site gets no signal that the underlying race is firing, and
  `lock-break-instance-identity` R2 stays invisible until its harness measures it (resolved
  2026-08-27).
- **Q:** Does the retake share the existing `absent` counter or get its own? — **A:** Left to
  `/uvm-plan`. R3 constrains the observable outcome — a literal bound, and no extension of the
  timeout accounting — which is what matters; `invariants.md` §5 already warns that a count which
  resets lets an alternation evade the accounting, and that warning applies to whichever shape the
  plan picks (resolved 2026-08-27).
- **Q:** Cycle 3 recorded a twenty-line ceiling on the diff to `uvm_acquire_lock` as the signal to
  stop and reconsider. Is that a criterion? — **A:** No. A line count is a brittle thing to grade and
  it is a proxy for what R4 measures directly. It stays as guidance for `/uvm-plan` and as a prompt
  to escalate rather than push through (resolved 2026-08-27).

## Related materials

- Seed: [`issues/lock-acquire-retake.md`](../../issues/lock-acquire-retake.md) — carries the working
  `mkdir` PATH shim, its `EACCES` companion, the `set -euo pipefail` landmine, and the collateral
  gates. `ROADMAP.md` entry, sequenced **first**, ahead of `lock-break-instance-identity`.
- Origin: [`spec/lock-ownership-and-hold-time/REVIEW.md`](../lock-ownership-and-hold-time/REVIEW.md)
  — cycle 3's **F9**, its `### Correction to cycle 2`, and the human-gate clearance recording the
  override that shipped it.
- `bin/uv-manager` § *provisioning lock*: the owner write at `:462-465`, the absent-lock retry at
  `:356-360` that R3 is modelled on, and the break block at `:407-437` whose race causes this.
- `AGENTS.md` names `uvm_acquire_lock` a high-blast-radius region: a confirmed finding here forces a
  human sign-off gate at review.

## Verification limit, declared up front

The R1 gate depends on `mkdir` remaining an external command invoked with the lock path as its sole
argument (`bin/uv-manager:346`), because that is what the `PATH` shim intercepts. A future change to a
builtin or a different call shape would make the gate silently stop constructing the state it exists
to construct — the failure mode being that it passes. Whoever lands it owes a comment saying so beside
the gate.

`mkdir` atomicity on Lustre, GPFS and NFS is unchanged by this cycle and remains taken on trust, as
declared by `lock-ownership-and-hold-time`. R6 pins the discipline rather than revisiting it.
