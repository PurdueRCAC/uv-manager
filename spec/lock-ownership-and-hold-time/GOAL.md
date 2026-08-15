# GOAL — The provisioning lock can be released by a process that does not hold it

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** lock-ownership-and-hold-time
- **kind:** fix
- **appetite:** big

## Problem

`uvm_unlock` (`bin/uv-manager:177-182`) removes the lock directory named by the `uvm_lock` global. It
matches on the **path** and never on ownership, and the `EXIT`/`INT`/`TERM` traps at `:187-189`
inherit that. Three defects follow, all pre-existing on `main` and all reproduced in a sandbox.

**One process deletes another's live lock.** Once any holder's lock ages past `UVM_LOCK_STALE`, a
waiter breaks it at `:225-229` and acquires. The original holder is still running and still believes
it holds the lock; its own `uvm_unlock` then removes the *new* holder's directory. Reproduced against
current `main` with an `owner` file naming a live process: `breaking stale provisioning lock (2s
old)`, the breaker then provisioned, and its unlock left `lock dir: GONE` — mutual exclusion gone
while the first holder still ran.

**Nothing enforces `UVM_LOCK_TIMEOUT < UVM_LOCK_STALE`.** Both knobs are documented and independently
settable (`:165-166`, `etc/uv-manager.conf.example:71-76`) with no note that one bounds the other.
Inverted, a waiter declares a live lock stale, breaks it and proceeds, and a single process that
nests an acquisition breaks its own lock and exits 0.

**A lock held across `exec` is leaked until the stale timer fires.** The dispatch tail `exec`s at
`:947-953`; `exec` replaces the process image and the `EXIT` trap never runs. `main` holds no lock at
that point today, so this is latent — but the trap discipline the rest of the file depends on does not
cover it, and the next queued cycle is the one that makes it live.

The stale-breaker is the mechanism behind the first two, and it was sized for a single binary
download. `UVM_LOCK_STALE` defaults to 600 s. The timeout message at `:234-236` tells a waiting user,
verbatim, to `rmdir` the lock — correct for an abandoned lock and destructive for a slow live one.

**A released lock is misread as a broken filesystem.** Added by amendment; found by benchmarking, not
by the original shaping. `uvm_acquire_lock` decides *why* `mkdir` failed by looking at the filesystem
again afterwards, and dies on `[[ ! -d "${lock}" ]]`. The inference is unsound: `mkdir` fails
`EEXIST` because a holder has the lock, the holder releases before the test runs, and the test
concludes the mount is unwritable. The waiter dies one iteration short of an acquisition it would
have won, and the message sends its operator to investigate a healthy filesystem. Every release
supplies the window, including the loop's own break paths, which `rmdir` and `continue` straight back
into it.

**Who this hurts.** Today, almost nobody: every path needs a holder whose work outlives 600 s, and a
uv download rarely does. Measured on current `main`, the default ordering (`TIMEOUT` 180 <
`STALE` 600) means a waiter dies at 180 s before the breaker can fire, so the ownership defect is
unreachable without a site raising `UVM_LOCK_TIMEOUT`. That is precisely what a site must do once
anything holds the lock for a rebuild instead of a download, which is what
[`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md) R7 requires. The audience for this
fix is therefore the *next* cycle and the site that configures it — the failure is two processes
running `uv tool upgrade --reinstall` against one tree, with no lock left between them.

**R8's audience is different, and it is everybody.** That assessment holds for R1–R7 and is left on
record as written. It does not survive R8: the acquire race needs no holder outliving
`UVM_LOCK_STALE`, no raised timeout and no ten-minute download — only ordinary contention on a fast
node, which is the normal case for a many-rank launch on the hardware this wrapper exists for.
Measured on Anvil compute node `a706`, 64 concurrent cold starts on GPFS scratch: 62 of 64. The login
node returned 64 of 64 because it is four times slower, so that figure is a slower machine hiding the
race, not evidence of correctness. Reproduced on this branch under `temp_root.sh --offline`: 25 of
640 ranks over ten bursts, a 3.9% rank loss against Anvil's 3.1%. Reachable today, on `main`, at
shipped defaults.

## Outcome / vision

The lock is held only by the process that acquired it, its age reflects whether the holder is alive
rather than when it started, and a long legitimate hold is never mistaken for an abandoned one. The
repair cycle inherits a lock it can hold for the length of a rebuild.

## Acceptance criteria (the contract)

- **R1** — WHEN `uvm_unlock` runs and the lock's `owner` file does not name this process, the wrapper
  SHALL leave the lock directory in place and clear `uvm_lock`. *Checked by a sandbox drive: acquire,
  overwrite `owner` with a foreign host/pid, trigger the release path, and assert the directory and
  its `owner` file both survive; then the ordinary case, where the owner matches and the directory is
  removed.*
- **R2** — WHILE a holder is alive, its lock SHALL NOT be breakable as stale, however long the work
  takes. *A heartbeat refreshing the lock's mtime as the holder makes progress is the shape research
  recommends and the maintainer selected; the mechanism is settled, the placement is `/uvm-plan`'s.
  Checked by a sandbox drive with `UVM_LOCK_STALE` set below the hold duration: a second process
  waiting on a live holder SHALL NOT print `breaking stale provisioning lock`, and the holder's lock
  SHALL still be its own when the work finishes.*
- **R3** — IF `UVM_LOCK_TIMEOUT` is not less than `UVM_LOCK_STALE`, THEN the wrapper SHALL report the
  inverted configuration and refuse it, rather than silently breaking live locks. Both knobs SHALL be
  read as the decimal seconds the operator wrote, and the refusal SHALL print the seconds it judged.
  *Checked by a sandbox drive with the knobs inverted: non-zero exit, a message naming both variables,
  and a pre-existing live lock still present afterwards; plus three spellings — `TIMEOUT=0600
  STALE=500` refused, `TIMEOUT=500 STALE=0600` accepted, and `STALE=0800` on a contended lock
  producing no `value too great for base` on stderr. The pre-fix behavior is already reproduced —
  `breaking stale provisioning lock (2s old)` followed by the lock's deletion, and `0600` measured as
  384 s — so the gate has a known red state.*
- **R4** — No lock SHALL be held across `exec`. The wrapper SHALL release before each `exec` of the
  real `uv` — the three in the dispatch tail and the one in `uvm_self_update`. *Checked by a sandbox
  drive asserting the release runs on a path that reaches `exec`, and by
  `git grep -n 'exec "\${real_' bin/uv-manager` showing every site covered; the census returns four
  matches today. The claim that this costs the hot path nothing measurable is graded by the reviewer
  against the implementation — the release must be a builtin test that forks nothing when no lock is
  held — because a 5 ms budget is below what a timing drive can resolve on a shared machine.*
- **R5** — The timeout message SHALL NOT advise `rmdir` without also saying how to tell an abandoned
  lock from a live one. *Checked by a sandbox drive to timeout, asserting the message names the
  discriminator — the `owner` file and the host and pid it records.*
- **R6** — Behavior under the existing single-download hold SHALL be unchanged, and the discipline
  SHALL remain `mkdir`. *Checked by `.agents/factory/bin/temp_root.sh --offline uv --version` still
  reporting the fixture version and leaving `current -> versions/<fixture>`, plus a census showing no
  `flock` is invoked — `git grep -n flock bin/uv-manager` matching nothing outside a comment, which
  retains the rationale comment at `:172` that records why the discipline is `mkdir`.*
- **R7** — A stale lock the wrapper cannot remove SHALL NOT defeat `UVM_LOCK_TIMEOUT`. WHEN a break
  attempt leaves the lock directory in place, the waiter SHALL fall through to the timeout accounting
  rather than retrying at once, and SHALL NOT re-announce the break on each iteration. *Checked by a
  sandbox drive against a lock directory holding an entry the wrapper did not write, aged past
  `UVM_LOCK_STALE`: the call exits non-zero within `UVM_LOCK_TIMEOUT` and its stderr carries the
  timeout message. Red today — measured 825 stderr lines and still spinning 8 s after a 2 s timeout,
  killed by the harness.*

- **R8** — A failed `mkdir` of the lock directory SHALL NOT be reported as a permissions or quota
  fault on the evidence of a single observation. WHEN the lock is absent after `mkdir` fails, the
  waiter SHALL retry; it SHALL report the filesystem fault only after a bounded number of attempts
  have each found it absent. The bound SHALL be a constant in the script, not a new environment
  variable, and the retries SHALL NOT reset or bypass the timeout accounting. *Checked by two sandbox
  drives: twenty cold bursts of 64 concurrent ranks against one shared root, asserting no rank
  carries `check permissions and quota` and every rank exits 0 — red today, measured at 25 of 640
  ranks (3.9%) on this branch against 2 of 64 (3.1%) on Anvil compute; and an unwritable
  architecture directory, asserting a real fault is still named, still non-zero, and still reported
  in under five seconds rather than after `UVM_LOCK_TIMEOUT` — green today and green after.*

## Non-goals (no-gos)

- **No `flock`.** The `mkdir` discipline is an invariant: atomic on Lustre, GPFS and NFS, no helper
  binary, and `flock` is not enabled on every parallel filesystem. R6 pins it.
- **No repair, and no second caller of the lock.** This cycle fixes the lock; it does not give
  anything new a reason to take it. [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md)
  owns that.
- **No generalization of `uvm_acquire_lock`'s early-out predicate.** Research prototyped an optional
  third parameter naming the predicate instead of the hardcoded `uvm_have`, so that a non-provisioning
  caller can express its own "already satisfied" test. It is only needed once something other than
  provisioning takes the lock, so it is landed as **R11 in
  [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md)** in this same commit rather than
  left as a sentence here.
- **No committed regression test.** [`issues/test-harness.md`](../../issues/test-harness.md) owns the
  runner; the obligation is landed there as its **R3d** in this same commit. Concurrency is the case
  that seed already names as the hardest thing it must cover, and this cycle is verified by sandbox
  drives alone until it exists.
- **No new subcommand and no new environment variable.** `UVM_LOCK_TIMEOUT` and `UVM_LOCK_STALE`
  already exist; R3 constrains how they may be combined and adds nothing.
- **No change to the lock's location or name.** `${uvm_root}/.install.lock` stays where it is, so a
  tree half-migrated between wrapper versions cannot end up with two locks.

## Clarifications

- **Q:** The seed and `ROADMAP.md` record `appetite: medium`, which is no longer a value the
  lifecycle interprets. — **A:** `big`, by the rounding rule now stated in `/uvm-feature`'s Argument
  Parsing: rounding up costs a research fan-out, rounding down fails `uvm-review`'s scope check
  against a contract a human already accepted (resolved 2026-08-15).
- **Q:** R4 left "a guard or a documented constraint on the dispatch tail" as a promotion decision. —
  **A:** A guard. `uvm_unlock` early-returns on an empty `uvm_lock`, so the cost on the hot path is a
  builtin test and no fork, and `purge-tree-repair` acquires later in the dispatch path by design —
  the guard makes the next cycle safe by construction rather than by remembering (resolved
  2026-08-15).
- **Q:** Does the predicate generalization belong here or to the repair cycle? — **A:** The repair
  cycle, which is the first caller that needs it. Landed there as R11 rather than named only here
  (resolved 2026-08-15).
- **Q:** The seed's line citations were written before the `doctor-detection-gaps` cycle. Do they
  still hold? — **A:** All but one. `:165-166`, `:177-182`, `:187-189`, `:225-229` and `:234-236` are
  unmoved; the `exec` tail cited as `:854` is now `:947-953`, a line-number move only. Every defect
  reproduces as described (resolved 2026-08-15).
- **Q:** R4 said "in the dispatch tail", but its own census matches `exec "${real_uv}" --version` in
  `uvm_self_update` — 295 lines above the dispatch banner, and measured to leak identically. — **A:**
  Cover all four sites; R4 now says so. The gate was right and the prose was narrow. Under R2 an
  uncovered site is no longer a bounded leak: `exec` preserves the pid, so the heartbeat's `kill -0
  "$$"` leash still passes after the wrapper has become the real `uv`, and the orphaned refresher keeps
  the lock unbreakable for the length of the user's command (resolved 2026-08-15).
- **Q:** R6's `git grep -c flock bin/uv-manager` returning 0 cannot pass — `:172` names `flock` in the
  comment recording why the discipline is `mkdir`, so the census returns `bin/uv-manager:1`. — **A:**
  Restated as "no `flock` invoked", matching nothing outside a comment. Found independently by two
  briefs and confirmed at the terminal. The literal form was worse than useless:
  `test "$(git grep -c …)" = 0` is never true even on a clean file, because `git grep -c` emits the
  filename prefix (resolved 2026-08-15).
- **Q:** Should a maximum refresher lifetime back up R4's guard, so an orphaned heartbeat cannot hold a
  lock forever? — **A:** No. `uvm_unlock` reaps the refresher and R4 calls it before every `exec`. A
  ceiling adds a counter and a documented number, and a hold that outlives it silently loses the
  protection R2 exists to give — reintroducing the bound this cycle removes (resolved 2026-08-15).
- **Q:** Bash reads `UVM_LOCK_STALE=0600` as octal 384. Does R3 compare what the operator wrote or
  what bash computes? — **A:** What the operator wrote. The guard forces base 10 before comparing and
  prints the seconds it judged. Left raw, a legal `TIMEOUT=500 STALE=0600` is *refused* with a message
  whose own two numbers satisfy the rule it cites, and `^[0-9]+$` admits `0800`, on which the guard's
  own arithmetic errors non-fatally, compares false, and **accepts**. Both driven. This is a hole in
  the guard this cycle ships, not an inherited defect, which is what puts it in scope (resolved
  2026-08-15).
- **Q:** The `continue` in the stale-break block skips both the timeout counter and the `sleep`, so a
  lock that cannot be removed spins unbounded. Is that this cycle's or a seed's? — **A:** This cycle,
  as R7. It sits in the function four phases already rewrite, and P3 and P5 each make the spin hotter
  and noisier — deferring means shipping a hold-time fix that degrades the one bound the knob
  documents. Reachability needs a cold tree, a lock past `UVM_LOCK_STALE`, and removal persistently
  denied: a read-only remount, a full filesystem, or a stray entry in the lock directory. Found by an
  audit of `invariants.md` against the code, not by the original shaping (resolved 2026-08-15).
- **Q:** Should this be promoted before `purge-tree-repair`, to get repair benchmarks sooner? —
  **A:** No; the recorded sequencing stands. The blocking subset is narrower than the whole cycle —
  R1 and R3 are what R7 of the repair cycle strictly needs — but the maintainer chose to take the
  cycle whole and in order rather than split it (resolved 2026-08-15).
- **Q:** A benchmarking run found a fourth defect in `uvm_acquire_lock` — a released lock misread as
  a broken filesystem — after four phases had already landed. Does it join this cycle or become a
  seed? — **A:** This cycle, as R8. The R7 precedent does not strictly reach: R7 was admitted on two
  grounds and the second, "this cycle worsens it", is measurably false here — a matched A/B against
  `main` gave 1.78% versus 1.98% of ranks lost, 0.83σ, with `main`'s own spread wider than the gap.
  What decides it instead is that deferring does not protect the cycle. `review-rubric.md`'s single
  deferral exception requires both that the finding predate the diff *and* that a `GOAL.md` criterion
  would be failed by repairing it; R6 pins the `mkdir` discipline and the single-download hold, and a
  bounded retry disturbs neither, so the second condition fails and a blind reviewer who reproduces a
  3.9% rank loss in a high-blast-radius region blocks the cycle regardless. Deferral buys a
  `changes-requested` loop and a second human sign-off gate on `uvm_acquire_lock` in exchange for
  nothing. Two soft circuit-breakers are crossed knowingly: seven phases against `/uvm-plan`'s six,
  and eight criteria reaching `/uvm-feature`'s 8–10 band (resolved 2026-08-15).

## Related materials

- Seed: [`issues/lock-ownership-and-hold-time.md`](../../issues/lock-ownership-and-hold-time.md) ·
  `ROADMAP.md` entry, sequenced **before** `purge-tree-repair`.
- R8's origin: `issue-locking.md` in the companion paper repository, shaped there while this cycle
  was mid-flight and adopted here by amendment rather than transplanted to `issues/`. Its evidence is
  `bench/uvm-bench.sh concurrency` against Anvil `a706` and `login00`, run 20260815T160020. Its
  citations pair this branch's line numbers with `uvm_version="0.4.1"`, where the guard is `:213`;
  the code is ground truth. The paper's Section V concurrency figure depends on this landing and the
  burst being re-run.
- `spec/purge-resilient-run/research/03-lock-reentrancy-and-concurrency.md` — where the defects were
  found; `00-digest.md` D4–D5 — the adversarial pass that corrected it and narrowed that cycle to the
  hot-path guard.
- `bin/uv-manager` § *provisioning lock* (`:160-245`), the dispatch tail (`:940-955`),
  `etc/uv-manager.conf.example:71-76`, and the `uvm_help` heredoc's knob descriptions (`:878-879`).
- `AGENTS.md` names `uvm_acquire_lock` / `uvm_unlock` a high-blast-radius region: a confirmed finding
  here forces a human sign-off gate at review, and R1 and R2 are `hammerable: false`.

## Verification limit, declared up front

`mkdir` atomicity on Lustre, GPFS and NFS cannot be exercised by a `mktemp -d` on APFS. The ownership
defect, the inverted-knob defect and the `exec` leak all reproduce locally and are graded by drive;
the parallel-filesystem semantics are **taken on trust** from the existing discipline, which R6 pins
rather than revisits.
