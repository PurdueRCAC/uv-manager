# PLAN — A losing breaker deletes the lock a third rank just won

> **Status:** Draft for review · **Last updated:** 2026-09-08
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).

## 1. Summary

Build the instrument first, then fix the defect it measures. `tests/lock-race.sh` plants a lock,
releases 64 concurrent ranks at it, and counts three things the wrapper already reports on stderr —
no instrumentation of `bin/uv-manager` at all. Then repair `uvm_acquire_lock`'s break path in the
order research established: **stop a denied break destroying evidence** (R4, which turns out to be a
*prerequisite* rather than a companion, because `main` manufactures the owner-less locks the fix has
to survive), then **age, pin, verify, remove** (R3). The pin is the load-bearing part and the
counter-intuitive one: a directory has no identity a shell can read, so the breaker gives it one it
*writes*, and that entry's presence makes the instance unable to change identity between the judgment
and the act.

## 2. Design

Three changes to `bin/uv-manager`, all inside the provisioning-lock section, plus two new files at
`tests/` and the documentation the same-commit rule pulls in.

### 2.1 `uvm_lock_removable` — a new predicate (R4)

A fork-free precondition, called from the break path before either removal:

```bash
uvm_lock_removable() {
  local lock="$1" e
  [[ -d "${lock}" ]] || return 1
  [[ -w "${lock}" && -w "${lock%/*}" ]] || return 1
  for e in "${lock}"/* "${lock}"/.[!.]* "${lock}"/..?*; do
    [[ -e "${e}" || -L "${e}" ]] || continue
    case "${e##*/}" in
      owner|mark) ;;
      *) return 1 ;;
    esac
  done
  return 0
}
```

Explicit dot patterns rather than `shopt -s dotglob`: a bare glob cannot see a stray dot-entry, and
`shopt` is global state in a script that globs in `uvm_trampolines`. The `[[ -e || -L ]] || continue`
guard is load-bearing — with `nullglob` unset a non-matching pattern expands to itself. Unit-tested
across eleven states ([`research/07`](research/07-candidate-remedies.md)); costs no fork.

### 2.2 The break path — age, pin, verify, remove (R3, R4)

The order is the design, and each step exists because a simpler arrangement was measured failing:

1. **Age.** `[[ "${still}" == "${holder}" ]]` plus `uvm_lock_still_forfeit`, which re-verifies
   whichever branch decided the forfeiture. `-d` precedes any `-ot` because bash reports
   `[[ MISSING -ot existing ]]` **true**, so a bare `-ot` passes exactly when the instance is already
   gone. The reference `${mark}` is per-pid (`${uvm_root}/.install.mark.$$`), because a shared one
   another rank bumps forward reopens the hole it closes.

   **Amended during P3, on measurement — see [`TECH.md`](TECH.md) § *Amendments*.** This step as
   drafted tested the *lock directory's* mtime, and that wedged 1 burst in 40: a breaker's own unlink
   of `owner` bumps the directory's mtime, so a husk left by a failed `rmdir` reads as fresh for a
   full `UVM_LOCK_STALE` and no branch names it forfeit before the timeout fires. What shipped reads
   the age off `${lock}/owner` when it exists — only the holder's heartbeat writes that file — and
   judges an owner-less lock on **persistence** instead: owner-less on two consecutive passes a
   second apart is a husk, since a winner records `owner` within a fraction of a millisecond of its
   `mkdir`. A dead holder is re-probed with `kill -0` rather than re-aged, which is what keeps the
   0-second fast path §5 promises.
2. **Sweep an abandoned pin.** On finding a `mark`, read it and probe the pid it records; same host
   and gone means remove it. Reuses the liveness rule the function already applies to `owner`, so it
   adds no bound and recovers immediately rather than a stale window later.
3. **Pin.** `set -C` makes the redirect `O_EXCL`:
   `printf '%s\n' "${owner}" 2>/dev/null > "${lock}/mark"`. ENOENT means the instance is already gone;
   EEXIST means another breaker owns this break. Either way, decline. `2>/dev/null` precedes the
   output redirect — the ordering already documented at the `owner` write — because without it the
   EEXIST case emits a raw shell diagnostic once per iteration, measured at ~180 lines at the shipped
   default timeout. The mark carries `${owner}` rather than being empty, because a pin recording no
   identity cannot be swept and wedges the lock exactly as an un-swept one does.
4. **Verify, then remove.** Re-read `owner` and require it still matches, and require
   `uvm_lock_removable`. Then `rm -f "${lock}/owner" "${lock}/mark"` and `rmdir "${lock}"`. On a
   declined verify, `rm -f "${lock}/mark"` alone — the lock is left exactly as it was found, `owner`
   included.

**What the pin buys, and why nothing cheaper does.** Every predicate is evaluated before the removals
and the exposure is the two forks after it — measured at 2.97 ms, about 11x the winner's own 0.27 ms
acquire gap. The pin is not evidence, it is an occupancy: while the mark stands no other rank's
`rmdir` succeeds and no `mkdir` can place a new instance at the path. A rival arriving in the residual
window between our `rm -f` and our `rmdir` pins the emptied directory itself, which makes *our*
`rmdir` fail rather than admitting a fresh winner.

`${mark}` is removed on the wait loop's exits and by the EXIT trap; left behind it accumulates one
file per contending pid in the user's own tree forever.

### 2.3 Messages (R4)

- `last_holder` keeps the last non-empty `owner` line the loop read, so the timeout message never
  depends on a file the break may have removed. Its label moves to the past tense — `holder, as the
  lock's owner file recorded it:`.
- The recovery advice becomes
  `rm -f '<lock>/owner' '<lock>/mark' && rmdir '<lock>'`. The current advice fails
  `Directory not empty` while a mark stands, and *already* fails in the state R4 is about.
- The break note stays where it is and changes from an accomplished act to an attempted one:
  `provisioning lock is forfeit and will be broken (<n>s old)`. Moving it inside the decision would
  cost `lock-ownership-and-hold-time` R7's one-note-per-wait contract, and a note emitted after a
  successful removal cannot report the `owner` line it just deleted, which is the note's whole
  purpose.

### 2.4 `tests/lock-race.sh` and `tests/lock-race-burst.sh` (R1, R2)

Two standalone POSIX `sh` files, no runner — `bats` is a dependency a cluster operator may not have
and this cycle lands one case, so the exit code is the interface. Split in two because a driver
holding the burst body in a heredoc is invisible to `sh -n` and to shellcheck.

```
tests/lock-race.sh [--plant owner|none|control] [--ranks N] [--bursts B]
                   [--deadline S] [--straggler] [--late S] [--quiet] [--keep]
```

Exit **0** clean · **1** the race was observed, stdout names which counter · **2** usage · **3** the
count is untrustworthy, **nothing on stdout** · **4** the wrapper made no progress.

Three counters, all read from per-rank stderr, none needing a change to `bin/uv-manager`:

| counter | observable |
|---|---|
| stolen holds | `uvm_unlock`'s note at `:266`, which fires exactly when a break removed an instance it never judged after ownership was recorded |
| robbed winners | the shell diagnostic from the `owner` write at `:351`, which the redirect deliberately does not suppress |
| concurrent installers | a marker directory the fixture hook holds strictly inside the lock hold |

The fixture needs no edit: `temp_root.sh` copies it into the sandbox per invocation, so the burst
script splices its hook into the sandbox's copy.

**Exit 4 is not decoration.** The drive's first version reported rc 0 for a candidate that declined
every break — 768 timeouts, nothing installed, a lock left standing in all 12 bursts — because all
three race counters were legitimately zero. It asserts progress (≥1 installer entry per burst, no
lock left standing, no non-zero rank) *before* any race verdict.

**Straggler contamination**, the reason the prior cycle's counts were worthless, is closed two ways:
collection state lives outside the sandbox, every writer registers a liveness marker cleared on exit,
and each burst is counted at its own time then recounted at the end so a late write is named rather
than absorbed. Both guards are exercised by `--straggler` and `--late`.

**Sizing is arithmetic, from `lock-ownership-and-hold-time/PLAN.md:392-397`** — validated rather than
assumed (predicted `P_burst` 0.175 against measured 0.175 on the owner plant), then applied with the
**measured** `P_burst` because stolen holds cluster within a burst and the independence assumption is
optimistic. `control×5 + none×12 + owner×40` at 64 ranks: 103 s, false green 3.5e-4 and 1.2e-11.

### 2.5 Documentation the same-commit rule pulls in

- `.agents/factory/invariants.md` §5 and `AGENTS.md` § *Invariants*: the pin and its sweep are new
  mechanism; the break note and recovery command change wording; and the `mkdir`-to-`owner` window is
  0.265 ms measured end to end, not the 0.10 ms both files quote, which measures only the redirect.
- `README.md:527-533` quotes the recovery command and describes what is inside the lock. Both move.
- `.agents/factory/bin/lint.sh`: both `tests/` files join the `sh -n` loop at `:46` **and** the
  shellcheck list at `:73`. The list is hardcoded in two places, so a file added to one and not the
  other is silently unchecked with the gate green.
- `AGENTS.md` § *Repository map* gains a `tests/` row, and § *Verification* stops opening "There is no
  test suite yet" — it becomes one drive, not a suite.
- `uvm_help`, `etc/uv-manager.conf.example` and the modulefile are **not** touched: no knob is added
  or changed, and neither quotes any of these strings.

### 2.6 What is removed

Little, and that is worth stating plainly rather than glossing. The vacuous identity test at `:458` is
subsumed rather than deleted — it stays as the first term of the composite condition, because it is
still the right answer for the owner-present case. What goes is the *unqualified* pair of removals and
the timeout message's dependence on a file the break may have deleted. The net is roughly +30 lines in
the highest-blast-radius function in the script, and § 5 records that as the cycle's main risk.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | § 2.4 — the two `tests/` files; liveness markers plus end-of-run recount; measured burst sizing; exit 3 and exit 4 |
| R2 | § 2.4 — three separate counters; per-burst attribution from the break note at `:446`; entries reported and never asserted |
| R3 | § 2.2 — age, sweep, pin, verify, remove, in that order |
| R4 | § 2.1 `uvm_lock_removable`; § 2.3 `last_holder`, the past-tense label and the corrected recovery command |
| R5 | No change to `absent`, `waited`, `broke` or `robbed`; the retake at `:366-378` untouched; `lock-acquire-retake`'s shim-built gates re-run in P4 |
| R6 | No change to the acquire discipline; `mkdir` unchanged; the offline drive and the `flock` census re-run in P4 |

## 3. Invariant gate (AGENTS.md constitution check)

Walked before research and again against this design.

- **§5 provisioning lock** — the discipline stays `mkdir`; release stays ownership-qualified on
  `EXIT`/`INT`/`TERM`; the early-out still tests the version asked for; the heartbeat, the host token
  and the `UVM_LOCK_TIMEOUT < UVM_LOCK_STALE` guard are untouched. The pin is **new mechanism inside
  §5** and the section is edited in the same commit, as is `AGENTS.md`'s copy. Contention is still
  told from failure by persistence: the pin's EEXIST and ENOENT both fall through to the existing
  timeout accounting, and neither resets a counter.
- **§5, the literal-bound rule** — the sweep introduces no environment variable and no new bound. It
  reuses the pid-liveness rule already applied to `owner`.
- **§7 output discipline** — every new message is stderr. The pin's `2>/dev/null` exists precisely so
  a declined break adds nothing to a user's stream; measured at ~180 suppressed lines.
- **§10 portability floor** — every new test is a bash builtin: `[[ -d ]]`, `[[ -w ]]`, `[[ -ot ]]`,
  `case`, pathname expansion, and one `printf` redirect. `set -C` and `-ot` were verified on bash
  3.2.57. The removals stay `rm -f` and `rmdir`; no GNU flags, no `stat` added to the break path.
- **§12 conventions** — same-commit surfaces in § 2.5; no feature-scoped spec ids in the script,
  `README.md` or `tests/`.
- **§2, §4, §6, §8, §9, §11** — untouched. The dispatch tail, pin authority, the installer scrub, the
  exported environment, trampolines and argument inspection are all outside this diff.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| A second file (`mark`) inside the lock directory, in a repository whose bias is to delete rather than add | It is the only mechanism measured to close the race. A predicate cannot: the exposure is *after* the predicate, and C1 alone moved the owner-less plant only 4.2% → 1.7% | An inode token — measured **100% false-match on ext4**, sound only on APFS where the drive runs ([`research/01`](research/01-directory-identity.md) F3). A held-fd `-ef` test — correct on Linux, broken on macOS. `find -inum -delete` — **BSD returns rc 0 silently** with the directory standing. Rename — the GOAL's non-goal, re-measured nesting. Compose-and-restore — measured refreshing a dead lock into permanence |
| A sweep rule for an abandoned pin | Without it a breaker killed between pin and cleanup wedges the lock for everyone, `rmdir` refusing forever | Leaving it unswept was measured: permanent wedge. An empty `: >` mark cannot be swept at all, so identity in the mark is not optional |
| `${uvm_root}/.install.mark.$$`, a per-pid file outside the lock | The `-ot` comparison needs a reference whose mtime is *now*, and a shared one another rank bumps forward reopens the hole | **Measured in P3 and rejected on soundness.** Re-running `uvm_age` re-tests `age > lock_stale`, which the dead-holder branch never established, so it would gate the 0-second fast path behind the full stale window |
| +~30 lines in `uvm_acquire_lock` | Three of the four steps were each measured necessary, and the fourth is the ordering between them | Every smaller composition was measured: C1 alone narrows only; C1+C3 leaves 9/768 and 6/2560; C2+C3 without C1 wedges 1/40 bursts; pin-before-age deadlocks completely |

## 4. Rabbit holes (resolved)

- *Can a shell read a directory's identity?* No, and the tokens that exist are worse than absent —
  sound on APFS, 100% false on ext4, 37% periodic on xfs, and Lustre's backing store is ext4-derived
  ([`01`](research/01-directory-identity.md)).
- *Is the owner-less lock a legacy tail?* No: `mkdir` on NFSv3/v4.0 is **documented not to tell its
  winner it won** (RFC 1813 §3.3.8), so the transport manufactures owner-less locks with no live
  holder ([`06`](research/06-filesystem-semantics.md)).
- *Is refusing to break an owner-less lock the fix?* No — measured as a permanent outage, rc 1 and
  empty stdout per rank per call, and `main` manufactures such locks itself through the R4 path. That
  is why **R4 sequences before R3** ([`02`](research/02-ownerless-locks.md)).
- *Is the obvious R4 fix safe?* No. Remove-`rmdir`-restore passes the whole R4/R7 matrix and then
  refreshes a dead holder's `owner` mtime from 211044504 s to 2 s, making every waiter a heartbeat for
  a corpse ([`03`](research/03-removal-order.md)).
- *Can this be measured at all?* Yes, and the prior cycle's contamination is closed
  ([`04`](research/04-concurrency-drive.md)).
- *Is the owner plant's signal even ours to fix?* Yes. The coordinator's hypothesis that the fatal
  branch at `:363` owned it was **refuted** — entered once in 7680 ranks with its `rmdir` failing —
  and the break block owns all 48 events ([`07`](research/07-candidate-remedies.md)). Had that gone
  the other way, an owner-plant gate could not have gone green from this diff.
- *Which composition is smallest?* Measured, six wrappers ([`07`](research/07-candidate-remedies.md)).

## 5. Risks & open questions

- **The pin adds an NFS dependency the shipped code does not have.** `O_EXCL` create semantics on NFS
  cannot be exercised here. This is the cycle's sharpest new exposure and it should be weighed at
  sign-off, not discovered at review. NFSv3 `EXCLUSIVE` create carries a verifier and is the one
  create mode RFC 1813 gives exactly-once semantics to — better placed than the `mkdir` it guards,
  which is documented *not* to — but that is a documented inference, not a measurement.
- **A pin orphaned by a process on another node still wedges the lock.** Measured: rc 1, no stderr
  leaks, and the timeout message names `mark` in its recovery command. Bounded by the same manual
  recovery that a foreign `owner` already needs, and no worse than today's foreign-`owner` case — but
  it is a second way to reach it.
- **+30 lines in the highest-blast-radius function.** `AGENTS.md` says a site operator has to read
  this script in one sitting, and every previous remediation here shipped collateral rather than
  failing at its target. R5 is a graded criterion for exactly that reason, and P4 re-runs the gates of
  two prior cycles rather than trusting this one's.
- **C1b is unmeasured and would simplify the diff.** If re-running `uvm_age` is equivalent, the
  reference file, its cleanup and its litter class all disappear for one fork on the provisioning
  path. P3 measures it before choosing; the plan does not pre-commit to the more complex form.
- **Everything is APFS on one machine.** A rate measured here is not a rate on Lustre or GPFS, and the
  burst sizing derives from that rate. The GOAL declares this; it stays true.
- **Only a real cluster can confirm:** `mkdir` mutual exclusion on Lustre/GPFS/NFS; that a re-read
  reflects another client's write (close-to-open explicitly "does not protect against races during
  concurrent file access"); that a fresh winner's `owner` is visible to a breaker inside the window,
  which on NFS defaults may be **up to 60 s** rather than 0.265 ms because `lookupcache=all` caches
  negative dentries until the parent's attributes expire; and the pin's exclusive-create behavior.
- **A live breaker's pin was never observed being swept** — the pid probe cannot fire on a live local
  pid by construction, and no drive built a breaker surviving a full wait iteration.
- **The recommended composition has not been run at the full false-green budget.** 40 owner bursts
  gives 3.5e-4; the 70-burst run is P4's.

## 6. Verification strategy

Three layers, per `methodology.md`: `bash -n bin/uv-manager`, `.agents/factory/bin/lint.sh`, and
drives under `.agents/factory/bin/temp_root.sh --offline`. `temp_root.sh` runs `"$@"` directly and
does not redirect stdin, so gates use `sh -s` with a quoted heredoc.

Post-conditions per requirement:

- **R1** — the drive exists and lints; `--plant control` exits 0; both plants exit **1** against
  today's wrapper, which is the red state; `--straggler` and `--late` each exit **3** with zero bytes
  on stdout. Burst sizing is graded by a reviewer against the numbers written into the drive.
- **R2** — the control run reports `stolen=0 robbed=0 concurrent=0` with `break_notes=0`, and a
  planted run attributes its concurrency to `via_break` rather than `no_break_in_burst`. The three
  counters appear as three separate lines.
- **R3** — `control×5 + none×12 + owner×40` at 64 ranks all exit 0, with `progress=ok`. Red today at
  32/8/32 and 11/3/11.
- **R4** — three constructions (stray entry, stray dot-entry, parent at mode 500), each aged past
  `UVM_LOCK_STALE`: `owner` still present after the break note, the timeout message naming the holder
  rather than `<none recorded>`, exactly one break note and one timeout per wait, and a second rank
  one second later still announcing its break — the staleness half, which `main` destroys by bumping
  the directory mtime. Plus the `chmod 500`-on-the-lock negative control, which is already green.
- **R5** — `lock-acquire-retake`'s R1/R2/R3 shim-built drives still pass, and its R4 counter gates:
  a fresh foreign lock timing out at exactly `UVM_LOCK_TIMEOUT`; exactly one break note across a
  denied wait; the absent-lock retry still naming a real permissions fault after its bound of three.
- **R6** — `temp_root.sh --offline uv --version` prints `uv 9.9.9 (fixture)` and leaves
  `current -> versions/9.9.9` with no lock behind; `git grep -n flock bin/uv-manager` matches only the
  rationale comment at `:172`.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
