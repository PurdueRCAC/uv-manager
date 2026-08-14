---
status: shaped
kind: fix
appetite: medium
lane: public
---

# The provisioning lock can be released by a process that does not hold it

## Problem

`uvm_unlock` (`bin/uv-manager:177-182`) removes the lock named by the `uvm_lock` global. It matches on
the **path**, never on ownership, and the EXIT/INT/TERM traps at `:187-189` inherit that. Three
defects follow, all reproduced in a repo copy driven under `temp_root.sh --offline` during the
`purge-resilient-run` research cycle.

**One process deletes another's live lock.** Once any holder's lock ages past `UVM_LOCK_STALE`, a
waiter breaks it at `:225-229` and acquires. The original holder is still running, still believes it
holds the lock, and its own `uvm_unlock` then removes the *new* holder's directory. Captured with a
watcher sampling the `owner` file each second:

```
W: t=4  dir owner=pid=21034      (A holding)
W: t=5  dir owner=pid=21586      (C broke A's lock and took it)
A: AFTER-UNLOCK pid=21034 lockdir=gone   <-- A removed C's owner file and C's lock
W: t=9  nodir owner=none         (C still working, mutual exclusion gone)
```

**Nothing enforces `UVM_LOCK_TIMEOUT < UVM_LOCK_STALE`.** With the order inverted, a process waiting
on a lock declares that lock stale, breaks it, re-acquires and proceeds — and a single process that
nests an acquisition breaks its *own* lock and exits 0. Driven at `UVM_LOCK_STALE=2
UVM_LOCK_TIMEOUT=60`: `breaking stale provisioning lock (3s old)`, install proceeds, exit 0. Both
knobs are documented and independently settable (`:165-166`, `etc/uv-manager.conf.example:71-76`),
with no note that one bounds the other.

**A lock held across `exec` is leaked until the stale timer fires.** The dispatch tail `exec`s at
`:854`; `exec` replaces the process image and the EXIT trap never runs. `main` never holds a lock at
that point, so this is latent rather than live — but it is a standing trap for any future code that
acquires later in the dispatch path, and the trap discipline the file relies on does not cover it.

The stale-breaker is the mechanism behind the first two, and it was sized for a single binary
download. `UVM_LOCK_STALE` defaults to 600 s; the message at `:234-236` tells a waiting user, verbatim,
to `rmdir` the lock — advice that is correct for an abandoned lock and destructive for a slow live one.

## Why it was deferred

**Pre-existing** on `main` and, today, hard to reach: every one needs a holder whose work outlives
`UVM_LOCK_STALE`, and a uv download rarely takes ten minutes. Found while designing the repair
coordination for `purge-resilient-run`
(`spec/purge-resilient-run/research/03-lock-reentrancy-and-concurrency.md`, corrected by the
adversarial pass in `00-digest.md` D4–D5), which narrowed to the hot-path guard and left the lock
untouched.

They stop being latent the moment anything holds the lock for the duration of a rebuild rather than a
download, which is exactly what [`issues/purge-tree-repair.md`](purge-tree-repair.md) needs. Fixing
them first keeps that cycle from inheriting a concurrency bug it did not create.

## Outcome / vision

The lock is held only by the process that acquired it, its age reflects whether the holder is alive
rather than when it started, and a long legitimate hold is never mistaken for an abandoned one.

## Sketch of the acceptance criteria

- **R1** — `uvm_unlock` SHALL remove the lock only when the `owner` file names this process; otherwise
  it SHALL leave it and clear `uvm_lock`.
- **R2** — WHILE a holder is alive, its lock SHALL NOT be breakable as stale, however long the work
  takes. A heartbeat refreshing the lock's mtime as the holder makes progress is the shape research
  recommends and the maintainer selected.
- **R3** — IF `UVM_LOCK_TIMEOUT` is not less than `UVM_LOCK_STALE`, THEN the wrapper SHALL say so and
  refuse the inverted configuration rather than silently breaking live locks.
- **R4** — No lock SHALL be held across `exec`. Whether this is a guard or a documented constraint on
  the dispatch tail is a promotion decision.
- **R5** — The timeout message SHALL NOT advise `rmdir` without saying how to tell an abandoned lock
  from a live one.
- **R6** — Behavior under the existing single-download hold SHALL be unchanged, and the discipline
  SHALL remain `mkdir`, never `flock`.

## Notes

- `uvm_acquire_lock` / `uvm_unlock` is a named high-blast-radius region in `AGENTS.md`, so a confirmed
  finding here forces a human sign-off gate at review. Treat R1 and R2 as `hammerable: false`.
- Related, and worth deciding at promotion: `uvm_acquire_lock`'s early-out calls `uvm_have "${want}"`,
  a version predicate. Research prototyped an optional third parameter naming the predicate
  (`satisfied="${3:-uvm_have}"`, plain indirect invocation — namerefs are bash 4.3 and breach the 3.2
  floor), which leaves every existing call site unchanged and keeps `uvm_have` the single spelling of
  the version question. That generalization is only needed once something other than provisioning
  takes the lock, so it may belong to the repair cycle instead.
- Verification is the hard part and the honest limit: `mkdir` atomicity on Lustre, GPFS and NFS cannot
  be exercised by a `mktemp -d` on APFS. The ownership and inversion defects reproduce anywhere; the
  filesystem semantics are taken on trust from the existing discipline.
- Found by: the `purge-resilient-run` research fan-out, 2026-08-12.
