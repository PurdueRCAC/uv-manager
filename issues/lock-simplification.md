---
status: shaped
kind: fix
appetite: big
lane: public
---

# Stop breaking the lock, and split provisioning from repair

> **Candidate, not a contract.** Promotion through `/uvm-feature` is where the R-IDs below get
> negotiated. The decision recorded in § *The decision* is **not** open at promotion; it was taken by
> the maintainer on 2026-09-09 with the evidence in this file, and § *Rejected — do not re-propose*
> is the list a plan owes a rebuttal rather than a design.

## Problem

The provisioning lock has been the subject of three consecutive cycles, and each one closed a race by
adding state whose own abandonment became the next cycle's defect.

`lock-ownership-and-hold-time` shipped in 0.6.0: an `owner` file, a heartbeat to keep a live holder's
lock from ageing out, and a release qualified by ownership rather than by path. Its break guard turned
out vacuous for a lock carrying no `owner`. `lock-acquire-retake` shipped in 0.6.1 to give the robbed
winner a bounded retake instead of a death. `lock-break-instance-identity` then added a persistence
count for the owner-less case and a `mark` entry pinning the instance under `O_EXCL`. Its review
confirmed three CRITICALs, and **two of the three were failure classes the remedy introduced** — a
fresh winner condemned by a husk count with no age floor, and an abandoned pin wedging provisioning
permanently for every later rank on every node, recoverable only by a human. That branch was reverted
to `main` and only its measurement instrument was kept.

The cost is visible in the file. `bin/uv-manager` went 955 → 1202 → 1224 lines across those cycles.
The provisioning lock is `:169-680` — **512 lines, 37% of the script** — and `uvm_acquire_lock` alone
is 301. It guards `uvm_install`, which is 67. `AGENTS.md:420` still describes this as "a 850-line
script that a site operator has to be able to read in one sitting."

**The common cause is one question the wrapper cannot answer.** Every deleted line below exists to
decide *the holder might be dead — may I take its lock?* That is failure detection, and no
asynchronous system can distinguish a slow process from a dead one. A network filesystem makes it
strictly worse: client-side attribute caching serves a stale `owner` line, clocks skew between nodes
so an age computed here is not an age computed there, `kill -0` answers for a pid number rather than
for the process that recorded it, and MDS failover can replay a metadata operation. Every defect
across the three cycles traces to an attempt to answer it anyway.

## Why it was deferred

Not deferred — **decided**. The three cycles above are the deferral history, and this file replaces
the two seeds that carried it.

## The decision

**The wrapper never breaks a lock, and never infers whether a holder is alive.** The only concurrency
primitive it relies on is `mkdir` atomicity, which it already takes on trust and which Lustre, GPFS
and NFS provide. Nothing reads a pid, a start time, a heartbeat or an mtime to decide whether another
process is still working.

This is affordable because **the two callers of the lock want opposite things, and neither needs
breaking to get them.**

| | provisioning (`uvm_install`) | repair (`purge-tree-repair` R7) |
|---|---|---|
| concurrent work is | safe — private `mktemp -d`, atomic publish | destructive — `uv tool upgrade` mutates shared trees |
| a waiter past the timeout | proceeds and does the work itself | fails non-zero |
| a stale lock costs | one redundant download per rank | a clear error until a human clears it |
| breaking required | no — proceeding is safe | no — failing is correct |

Provisioning does not need the lock to be correct, only to be *usual*: it exists to spare the site N
concurrent downloads, and when it misbehaves the worst outcome is that the saving is not made. Repair
does need exclusion, and gets it from a lock nobody ever takes by force — because the safe response to
"someone else may be repairing" is to refuse to run, which `purge-tree-repair` R9 already requires.

## Outcome / vision

A site operator reads the provisioning lock in one sitting. A rank that waits too long says so, once,
naming the holder, and then does something safe rather than adjudicating. A crashed holder costs a
redundant download and a line in `uvm doctor`, not a wedged tree and a human walking the nodes.

## Sketch of the acceptance criteria

- **R1** — The wrapper SHALL NOT remove, overwrite or take a lock directory it did not create. There
  SHALL be no stale-breaking path, no age comparison against a lock, and no liveness probe of a
  recorded pid.
- **R2** — WHILE a waiter has waited longer than a notice threshold, it SHALL print exactly one notice
  on stderr naming the holder the `owner` file records and the recovery command, and SHALL NOT repeat
  it for the remainder of the wait.
- **R3** — WHEN a **provisioning** waiter reaches `UVM_LOCK_TIMEOUT`, it SHALL proceed with the
  install itself rather than failing or waiting further, and the result SHALL be a correct tree
  whichever rank publishes first.
- **R4** — `uvm_install`'s publish SHALL be safe against a concurrent publish of the same version.
  The unguarded `mv "${tmp}" "${dest}"` at `bin/uv-manager:794` moves the source *inside* an existing
  destination and exits 0, which nests a live tree inside another; the claim SHALL be made with an
  atomic primitive and the loser SHALL discard its copy. Carried from **R3 of
  `issues/invariant-audit-gaps.md`**, which files the same line as leaving an uncollected `.incoming.`
  directory.
- **R5** — WHEN a **repair** waiter reaches its timeout with the damage still present, it SHALL exit
  non-zero naming the holder, per `purge-tree-repair` R9, and SHALL NOT repair concurrently.
- **R6** — The caller SHALL name the predicate that decides "already satisfied", so a repairer does
  not early-out on the provisioning question. Carried verbatim from **R11 of
  `issues/purge-tree-repair.md`**, which prototyped `satisfied="${3:-uvm_have}"` — plain indirect
  invocation, since namerefs are bash 4.3 and breach the 3.2 floor.
- **R7** — `uvm_lock_heartbeat`, `uvm_proc_start`, `uvm_age`, `uvm_lock_removable`,
  `uvm_lock_still_forfeit` and the ownership-qualified release SHALL be removed, along with the
  `UVM_LOCK_STALE` knob. Release by path is sound once nothing takes a lock by force, because a
  holder's lock can no longer be replaced beneath it — verify this at promotion rather than assuming
  it.
- **R8** — An abandoned lock SHALL be reported by `uvm doctor` and removable by `uvm clean`. Clearing
  it is a diagnostic action taken by a human or by tooling, never a decision a racing rank makes.
- **R9** — `invariants.md` §5 and `AGENTS.md` § *Invariants* SHALL be rewritten to assert the new
  contract, and SHALL NOT retain a single sentence describing a break. `/uvm-review` grades against
  that file, so a leftover assertion turns the correct code into an auto-CRITICAL finding.

## The instrument changes meaning, and that is work in this cycle

`tests/lock-race.sh` landed with `lock-break-instance-identity` and is the reason this decision could
be taken on evidence. Three of its counters do not survive the design: `stolen_holds` and
`robbed_winners` become structurally unreachable once nothing takes a lock by force, and `break_notes`
is always zero. A gate whose assertions cannot fail is not a gate.

`concurrent_installers` inverts rather than disappearing. Two installers are **permitted** under R3 —
that is the point of proceeding on timeout — so the drive must stop asserting their absence and start
asserting what R4 promises: after a burst in which several ranks published concurrently, the tree is
correct. `current` resolves, `versions/<ver>` holds exactly one distribution with no nested
`.incoming.`, and every rank's stdout carries the version it asked for. Establish the drive's red
state against the unguarded rename at `:794` before the guard lands, which is the technique
`spec/lock-ownership-and-hold-time/REVIEW.md` R8 records.

## Rejected — do not re-propose

Each of these was designed, and each failed on evidence. A plan re-proposing one owes this list a
rebuttal, not a design.

- **The exclusive rename, and the compose-and-restore variant.** `mv -T` does not exist at the
  portability floor, and without it `mv` onto an existing name moves the source inside it and exits 0,
  so two breakers both believe they won. `rmdir` refusing a non-empty directory turned out to be what
  protects an *established* lock, so a rename widens the destructive window from the acquire gap to
  the whole hold. Four of five design lenses returned `rename-is-unsound` independently.
- **Any readable identity for a directory instance.** An inode recycles deterministically on ext4
  (measured 200 of 200 at one path) and a held descriptor compares equal on Linux and unequal on
  macOS — sound where the drives run, false where the wrapper runs.
- **Occupancy by a written entry (`${lock}/mark` under `O_EXCL`).** Shipped and reverted. The entry
  outlives a breaker killed between its pin and its cleanup, no trap sweeps it, and once it records
  another node or a recycled pid nothing removes it: measured as five sequential ranks failing at rc 1
  against a lock that never clears.
- **Persistence as a substitute for age (the husk count).** Shipped and reverted. It has no lower
  bound on the instance's age, so a winner slower than the poll is condemned: measured destroying a
  0-second-old lock that `main` spares, and producing robbed winners on the ordinary cold-start path.
- **A heartbeat, a refresher leash, or `kill -0` staleness.** All are liveness inference, which is the
  thing this decision removes. `invariants.md` already rejects `kill -0` for the refresher's own leash
  on the ground that pid space wraps in under a minute on a node spawning `uv run` in a loop; the same
  objection applies wherever it is used.
- **A `/tmp` fallback for the state root**, unchanged from `README.md` § *Design notes*.

## Notes

- **Supersedes [`issues/lock-break-instance-identity.md`](lock-break-instance-identity.md).** Its
  measurement half shipped; its fix half is declined by this decision. Its retained account is
  [`spec/lock-break-instance-identity/`](../spec/lock-break-instance-identity/GOAL.md), whose
  `REVIEW.md` carries the three CRITICALs that produced this file.
- **Supersedes [`issues/lock-owner-write-errno.md`](lock-owner-write-errno.md).** That seed classifies
  a failed `owner` write by testing whether the lock directory still stands, and exists only because a
  robbed winner is reachable. Nothing takes a lock by force after this cycle, so the robbery it rides
  on is gone. Confirm that at promotion; if the fatal path's unqualified `rmdir` survives independently
  of the robbery, it is the live half and belongs here as an R-ID.
- **Sequenced above [`issues/purge-tree-repair.md`](purge-tree-repair.md)**, which is the first
  non-provisioning caller of the lock and which contributes R5 and R6 above. Landing repair on the
  current lock would put a 1-30 second hold behind machinery whose failure modes are the three cycles
  above.
- **Absorbs R3 of [`issues/invariant-audit-gaps.md`](invariant-audit-gaps.md)** as R4, and makes its
  R4 (the heartbeat's silently degrading leash) moot by deleting the heartbeat. Check both at
  promotion so that seed shrinks rather than drifting.
- `tests/lock-race.sh` and `tests/lock-race-burst.sh` are already committed and are the gate this
  cycle re-points; see § *The instrument changes meaning*.
- Found by: the maintainer, 2026-09-09, from `spec/lock-break-instance-identity/REVIEW.md` cycle 1 and
  the growth measurements in this file.
