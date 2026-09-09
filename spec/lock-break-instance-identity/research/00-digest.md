# 00 — Research digest

Consolidated decisions from six briefs, plus the contradictions between them resolved. Read this
first; the briefs carry the evidence.

**Status:** settled. [`07`](07-candidate-remedies.md) measured the candidates against the drive and
§ 5 records its verdict.

---

## 1. What the defect actually is, corrected in three places

The GOAL's account holds, and research sharpened it:

- **The destructive window is the breaker's own two forks, not the winner's acquire gap.** Measured
  compare-at-`:458` → directory removed: **2.97 ms**, against the winner's `mkdir`→`owner` gap of
  **0.27 ms** ([01](01-directory-identity.md) F4). And `rm -f "${lock}/owner"` *re-empties* the
  directory, so a fresh winner that already completed its `owner` write is robbed anyway. The
  invariant's 0.10 ms figure measures only the parent's redirect (0.060 ms measured); the full window
  a fresh winner is exposed in is 0.265 ms ([02](02-ownerless-locks.md) §2). Both numbers are
  method differences rather than disagreements, and `invariants.md` §5 should carry the wider one.
- **The shipped P8 guard buys about a third, not an order of magnitude.** Matched A/B at 3840 ranks
  per cell, replacing `:458` with `if true`: owner-less plant 165 → 214 concurrent entries (2.5σ),
  owner-carrying plant 9 → 14 (not significant at that size) ([04](04-concurrency-drive.md)).
- **Owner-less locks are a production mode of the deployment target, not a legacy tail.** `mkdir` on
  NFSv3 and NFSv4.0 is **documented not to give its winner self-attribution** — RFC 1813 §3.3.8, a
  retransmitted request "can fail with NFS3ERR_EXIST, even though the create was performed
  successfully". Such a rank skips the `robbed` retake (the directory *is* there), writes no `owner`,
  cannot be probed for liveness, and times out on a lock of its own making, leaving a fresh
  owner-less lock behind ([06](06-filesystem-semantics.md) §3). R3's insistence on covering the
  owner-less case is load-bearing, and no remedy may depend on the judged instance having recorded
  anything.

## 2. Contradiction resolved: is an inode token the foundation?

[06](06-filesystem-semantics.md) recommended an inode-based identity token, reasoning from NFS
semantics that it is fail-closed where the `owner` re-read is fail-open.
[01](01-directory-identity.md) measured inode reuse on four filesystems and disqualified it.

**Resolution: 01 wins, and the recommendation is rejected.** 06 reasoned about the right property and
never tested the premise. A fresh directory presented the *judged* inode:

| APFS | tmpfs | ext4 | xfs |
|---|---|---|---|
| 0/200 | 0/999 | **200/200 (100%)** | **37% at k=3** |

ext4 returns the same inode every cycle (`7837`); `dev+ino+birthtime` false-matched 299/300 there,
because the recycled inode is reissued inside the same second and the race is milliseconds wide.
Lustre's backing store is ldiskfs, ext4-derived. **An inode token is sound exactly where this
repository's drive measures it and false exactly where the wrapper runs** — it would pass every gate
this project can build and fail silently on a cluster, which is strictly worse than a documented
vacuity. 06's NFS analysis survives as a reason not to trust *any* read token, not as support for
this one.

Two related candidates die with it:

- **A held-fd identity test** (`exec 9< "${lock}"; [[ /dev/fd/9 -ef "${lock}" ]]`) is correct on
  Linux and broken on macOS, where `/dev/fd/9` reports a different device, so the guard would never
  break a lock there ([01](01-directory-identity.md) F1). That is the platform-conditional silent
  degradation the GOAL already refuses for the `ps -o lstart=` leash.
- **`find -inum … -delete`** is inode-filtered, so no better than the table above allows, and its
  exit status is not portable: GNU rc=1, **BSD rc=0 silently with the directory left standing**
  ([01](01-directory-identity.md) F5, [06](06-filesystem-semantics.md) §4). Unusable as a gate.

**Nothing at any level removes a directory conditional on identity, and this is not a shell
limitation:** `unlinkat(dirfd, name, AT_REMOVEDIR)` resolves the name, so a C implementation carries
the identical TOCTOU.

## 3. Contradiction resolved: does the fix need a fork?

[02](02-ownerless-locks.md) argues a `stat` re-check is *wider than the hole it plugs* — 1.3–2.7 ms
of forks against a 0.265 ms exposure — and offers `[[ dir -ot mark ]]` at 0.0035 ms.
[01](01-directory-identity.md) F4 sharpens the same point: no read token narrows the window at all,
because every token is read *before* the compare, and compare-to-removal is `rm -f` plus `rmdir` in
every design.

**Resolution: the remedy must be fork-free, and 02's specific form is fail-open as written.**
Verified on bash 3.2.57:

```
[[ MISSING -ot existing ]]  →  TRUE
```

Bash documents `-ot` as true when file1 does not exist and file2 does, so a bare
`[[ "${lock}" -ot "${mark}" ]]` **passes precisely when the lock is already gone**. The usable form
is `[[ -d "${lock}" && "${lock}" -ot "${mark}" ]]`. This correction is the reason the mechanism was
sent back for measurement rather than adopted from the brief.

## 4. Settled: R4's remedy, and it is a prerequisite rather than a companion

[03](03-removal-order.md) measured that a denied break destroys **three** things, not the one the
GOAL names:

1. the timeout message reports `<none recorded>` under a break note that named the holder;
2. the recovery command the message prints **fails** — `rmdir: Directory not empty`, rc 1 — so
   `invariants.md` §5's "a recovery command that works" is already false in this state;
3. **the lock stops reading as stale.** `rm -f` bumps the lock directory's mtime, `uvm_age` falls
   back to the directory once `owner` is gone, and the next rank one second later emits **zero**
   break notes and times out without attempting a break. A breakable stale lock becomes one nothing
   will break, refreshed on every arrival.

**The obvious remedy is disqualified by measurement.** Candidate (c) — remove, `rmdir`, restore on
failure — passes the whole R4/R7 matrix and then refreshes a dead holder's lock: the restoring write
moved `owner`'s mtime from 211044504 s to **2 s**. Every waiter becomes a heartbeat for a corpse, and
the lock is unbreakable until a human clears it. It would have looked correct in review.

**Recommended: (a′) + (e)** — a fork-free removability predicate (`[[ -w ]]` on the lock *and* its
parent, plus a glob rejecting entries we did not write) gating both removals, and the decided holder
line kept in a local so the message never reads a file the break may have deleted. Measured green on
all three red constructions and on the negative control. Accepted cost: the predicate is a
precondition, not a proof — an ACL, an immutable flag, or an entry appearing after the test still
leaves the lock owner-less, exactly as today, and (e) still names the holder.

**Ordering, and this is the finding that fixes the phase order:** `main` manufactures owner-less locks
itself through this very path, so **R4 is a prerequisite for any policy that declines to break an
owner-less lock, not a co-requirement** ([02](02-ownerless-locks.md) finding 2). R4 lands first.

**One implementation hazard the briefs did not flag.** Verified here: `"$lock"/*` sees `mark` but not
`.hidden` until `shopt -s dotglob`, and the stray *dot*-entry is one of 03's three red constructions.
`shopt` is global state in a script that globs elsewhere (`uvm_trampolines`), so C3's predicate must
save and restore it or use another technique.

## 5. Provisional: the mechanism for R3

The design space is closed to three shapes, and the choice between them is what
[07](07-candidate-remedies.md) is measuring.

- **C1 — fork-free freshness re-check.** Require the instance still present *and* still as old as the
  forfeiture decision judged it, immediately before the removals. Vacuous-proof: it does not care
  whether `owner` exists, which is the whole defect. Does **not** close the 2.97 ms
  compare-to-removal window; it removes the unbounded class of instances the vacuous test admits.
- **C2 — an authored mark that pins the instance.** A directory has no identity a shell can *read*;
  it can be given one the shell *writes*. `set -C; : > "${lock}/mark"` is 96 µs and zero forks, fails
  ENOENT when the instance is gone — inverting the vacuous case, since an absent instance now fails
  the *create* instead of passing the compare — and pins the directory: with one file inside, 32
  concurrent rival `rmdir`s succeeded **0/32** ([01](01-directory-identity.md) F6). `set -C` makes it
  `O_EXCL`, verified here, so it also makes breakers mutually exclusive. **Its cost is a new wedge:**
  a breaker killed between the pin and the cleanup leaves an entry no trap sweeps, `rmdir` then
  refuses forever, and the lock is unbreakable by anyone. It owes a sweep rule.
- **C3 — 03's (a′)+(e).** § 4 above. Needed for R4 regardless of which of C1/C2 lands, and it
  interacts with C2, whose mark must not read as a foreign entry to the predicate.

**Verdict, measured ([07](07-candidate-remedies.md)): the composition is C1 + C2 + C3, and all three
are load-bearing.** 64-rank bursts, `none×12 + owner×40 + control×5`, counters `stolen/robbed/concurrent`:

| wrapper | owner-less | owner | control | progress |
|---|---|---|---|---|
| `main` | 32 / 8 / 32 | 11 / 3 / 11 | 0/0/0 | ok |
| C1 | 13 / 4 / 13 | 8 / 5 / 8 | 0/0/0 | ok |
| C1+C3 | 9 / 0 / 9 | 6 / 4 / 6 | — | ok |
| C2+C3, C1 dropped | 0 / 0 / 0 | 0 / 0 / 0 | 0/0/0 | **FAIL — 1/40 bursts wedged** |
| C1+C2+C3, pin *before* the age test | 0 / 0 / 0 | — | — | **FAIL — 768 timeouts, 12/12 locks left** |
| **C1+C2+C3, pin after** | **0 / 0 / 0** | **0 / 0 / 0** | **0/0/0** | **ok** |

Four things follow, and three of them are counter-intuitive enough to be the reason this was measured
rather than argued:

- **A predicate cannot close this race.** C1 alone narrows (owner-less 4.2% → 1.7%) and no more,
  because the exposure sits *after* the predicate. [01](01-directory-identity.md) F4 predicted this
  and the drive confirmed it. **The pin is necessary, not merely available.**
- **Why the pin closes what a predicate cannot:** it is not evidence, it is an *occupancy*. While our
  mark stands no other rank's `rmdir` succeeds and no `mkdir` can place a new instance at the path, so
  the path cannot change identity between the judgment and the act. A rival arriving in the residual
  window between our `rm -f` and our `rmdir` pins the emptied directory itself, which makes *our*
  `rmdir` fail rather than admitting a fresh winner.
- **Order is the design: age, then pin, then verify, then remove.** Creating an entry bumps the
  directory's mtime, so a pin placed *before* the age comparison makes that comparison unsatisfiable
  forever — measured as a total deadlock.
- **Dropping C1 wedges the lock.** Without the age test the pin can land inside a *live* hold; that
  holder's own `rmdir` is then refused, leaving an empty directory with a fresh mtime that nothing
  reads as stale and no rank can break.

**R3's absolute wording is now supported by an argument, not only by a rate.** The pin makes the
judged instance unable to change identity, so "removes only the instance it judged" is a property of
the mechanism rather than a measured scarcity. What remains taken on trust is NFS: the pin's `O_EXCL`
create depends on NFS exclusive-create semantics this machine cannot exercise, which is a dependency
the shipped code does not currently have. § 8.

**Rejected outright, with reasons, so a later cycle does not re-propose them:** the exclusive rename
family (the GOAL's non-goal, and `mv a b` was re-measured nesting rather than failing); any
compose-and-restore variant (§ 4, candidate (c), measured); `rm -rf` on the lock, which discards the
`rmdir`-refusal that is load-bearing per `invariants.md` §5; and a nonce-named child directory
([06](06-filesystem-semantics.md) §4), which keeps `mkdir` and kills the vacuous case but inherits
the same NFSv3 non-idempotency on the inner `mkdir` and the same negative-dentry exposure, for a
second acquisition-path `mkdir`/`rmdir` pair.

## 6. Settled: the drive, and what its gates may assert

[04](04-concurrency-drive.md) built it and measured the red state (64-rank bursts, APFS, HEAD
`634caaa`):

| plant | ranks | concurrent installers | per-rank *p* | stolen | robbed | red bursts |
|---|---|---|---|---|---|---|
| control | 512 | **0** | 0 | 0 | 0 | 0/8 |
| owner | 7680 | **23** | 0.30% | 23 | 11 | 21/120 |
| owner-less | 6272 | **254** | 4.05% | 254 | 42 | 86/98 |

Cycle 3's 9-of-29 and 41-of-61 reproduce at matched size (3-of-23 and 47-of-67). Four decisions the
gates inherit:

- **No instrumentation of `bin/uv-manager` is needed, for either counter.** A stolen hold is
  `uvm_unlock`'s own note at `:266`, which fires exactly when a break removed an instance it never
  judged after ownership was recorded; a robbery inside the acquire window is the shell diagnostic
  from `:351`, which the redirect deliberately does not suppress. Both grepped from per-rank stderr,
  and both zero across 512 control ranks. This answers [05](05-installer-attribution.md) §4's open
  question in the negative — a counter in the script is not required.
- **Assert simultaneity, never entry count.** Three break-free paths give extra *serialized* entries
  — `force`, the `absent` retry, and a spurious re-download when `current` is absent or dangling with
  `versions/` populated. Asserting `entries == bursts` would flap on a state the drive itself creates
  by killing a rank.
- **Attribute per burst, never per rank.** 23 of 32 concurrent entries under the owner plant came
  from ranks that never broke anything, because a rank wins `mkdir` on a lock somebody *else* broke.
- **The tracked fixture needs no edit.** `temp_root.sh` copies it into the sandbox per invocation, so
  the burst script splices its hook into the sandbox's copy.

Straggler contamination — the reason the prior cycle's counts were untrustworthy — is solved and
proven in both directions: collection state outside the sandbox, liveness markers cleared on exit,
each burst counted at its own time and recounted at the end. `--straggler` → rc 3 with zero bytes on
stdout; `--late 3` → rc 3, `concurrent 0 -> 2`.

**Sizing** uses the arithmetic from `lock-ownership-and-hold-time/PLAN.md:392-397`, validated rather
than assumed: predicted `P_burst` 0.175 against measured 0.175 on the owner plant. The formula
*over*-estimates the owner-less plant (0.930 predicted, 0.878 measured) because stolen holds cluster
within a burst, so sizing uses the **measured** `P_burst`. Recommended gate
`control×5 + none×12 + owner×40` at 64 ranks: **103 s**, false green 3.5e-4 and 1.2e-11.

## 7. What this means for the contract

- **R1, R2 — deliverable as written**, at `tests/lock-race.sh` plus `tests/lock-race-burst.sh`, two
  standalone POSIX `sh` files, no runner. Both owe entry to `lint.sh:46` and `:73`.
- **R3 — deliverable as written.** The gate the GOAL specifies is achievable and measured green, and
  the pin gives the absolute wording a mechanism rather than a rate (§ 5). The cost to disclose at
  sign-off is not a residual race but a new dependency: `O_EXCL` create semantics on NFS, which no
  drive here can exercise.
- **R4 — deliverable, and it sequences first.** § 4.
- **R5, R6 — unchanged**, and `lock-acquire-retake`'s shim-constructed gates stay reachable because
  they construct their state in one process rather than through a real race.
- **Two findings outside the contract, both recorded**: the `:570` early-out is a §4 pin-authority
  violation rather than a second-installer cause, now
  [`issues/pin-early-out-selects-nothing.md`](../../../issues/pin-early-out-selects-nothing.md); and
  the fatal branch at `:363` was measured **once in 7680 planted ranks with its `rmdir` failing**, so
  [`issues/lock-owner-write-errno.md`](../../../issues/lock-owner-write-errno.md) is rarer than its
  PLAUSIBLE grade implied rather than commoner. [05](05-installer-attribution.md) §5 reported the
  destructive form twice in 1280 ranks; [07](07-candidate-remedies.md) finding 2 corrects it by
  per-site instrumentation, and the seed now records the correction.

## 8. Taken on trust, and what would discharge it

From [06](06-filesystem-semantics.md) §5, narrowed to what this cycle depends on:

| Property | Status | Discharged by |
|---|---|---|
| `mkdir` mutual exclusion on Lustre/GPFS/NFS | documented for POSIX, entailed by both vendors' compliance claims, asserted by neither | a concurrent-`mkdir` drive on each |
| `mkdir` self-attribution | **documented FALSE** on NFSv3/v4.0, TRUE on v4.1+ sessions | settled; the fix must not depend on it |
| `rmdir` refuses a non-empty directory | measured on APFS, ext4, tmpfs, xfs; POSIX `[ENOTEMPTY]` | — |
| a re-read reflects another client's write | **documented violable**: close-to-open "does not protect against races during concurrent file access" | a two-client NFS drive |
| a fresh winner's `owner` is visible to a breaker in the window | **assumed FALSE on NFS**: `lookupcache=all` caches negative dentries until the parent's attributes expire, so the 0.265 ms window becomes `acdirmin`/`acdirmax`-bounded — **up to 60 s at defaults** | a two-client NFSv3 drive, or `lookupcache=pos` at the site |
| `[[ -d "${lock}" ]]` and the `absent` counter observe the server's truth | assumed; same exposure | same drive |
| a rate measured on APFS transfers to a parallel filesystem | **false, and stated as such in the GOAL** | a real allocation |
| errno discrimination from a failed removal | **unavailable**: all seven `rmdir` failures rc=1, wording unspecified by POSIX and translated under glibc | — (settled; observe, do not interrogate) |
