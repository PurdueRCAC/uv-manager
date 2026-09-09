# 03 — Removal order: what a denied break must not destroy

Topic: R4. Read against R3, which restructures the same eight lines (`bin/uv-manager:440-471`).

## Findings

**The red state is wider than the GOAL describes, and its cost is three things rather than one.**
The GOAL names `<none recorded>` in the timeout message. Measured, a denied `rmdir` after a
successful `rm -f` also destroys the recovery advice and the lock's own staleness:

1. The timeout message reports `<none recorded>` two lines under a break note that named the holder.
2. The advised recovery command **fails**. Run verbatim in that state, `rm -f '<lock>/owner' &&
   rmdir '<lock>'` exits 1 with `rmdir: …/.install.lock: Directory not empty`, and the message never
   mentions the entry that is actually blocking it. The advice was already wrong for this
   construction before `owner` was deleted; deleting `owner` removes the last thing in the directory
   the message can account for.
3. **The lock stops reading as stale.** `uvm_age` falls back to the directory when `${lock}/owner`
   is gone (`:435`), and the successful `rm -f` just bumped that directory's mtime. A second rank
   arriving one second later therefore emits **0 break notes** and times out without attempting a
   break at all. The wrapper converts a breakable stale lock into one no rank will break, for a full
   `UVM_LOCK_STALE` after each arrival. Measured on `main`; the recommended candidate leaves the age
   at 211044504 s and the second rank still announces its break.

**Three distinct constructions reach the red state, not one.** A stray entry, a stray *dot* entry,
and a parent directory at mode 500 (which permits unlinking `owner` inside the lock and refuses
`rmdir` of the lock itself). The shipped R7 gate's `chmod 500` on the *lock* is not one of them —
that denies `rm -f` too, so `owner` survives and R4 is already green there.

**Candidate (c), the restore, is disqualified by measurement, not by taste.** It passes the whole
R4/R7 matrix and then refreshes a dead holder's lock: the restoring write moves `owner`'s mtime from
211044504 s to **2 s**, and the next rank sees no stale lock. Every waiter becomes a heartbeat for a
corpse. Under continuous arrivals the lock is unbreakable until a human clears it. It also sits
inside the spirit of the GOAL's *no compose-and-restore* non-goal: the restore is a write into a lock
this process does not own, which is the act R3 exists to narrow, and it can stamp a judged holder's
line over a retaker's.

## Candidates

| | R4 state (`owner` survives) | R4 message names holder | keeps `rmdir`-refusal guard R3 needs | forks / denied iteration | killed mid-sequence | live holder's heartbeat |
|---|---|---|---|---|---|---|
| **(a′) probe first, then remove** — `-w` on lock *and* parent, plus a builtin glob for entries we did not write | ✅ measured on all 4 denial constructions | ✅ | ✅ untouched | **+0** (all `[[ ]]` and glob) | unchanged from today: owner-less lock | none — declines when a stray exists, so a live holder's `owner` is never unlinked |
| (b) `rmdir` first | ✅ trivially | ✅ | n/a | +0 | n/a | n/a — **and it never breaks any lock**, since `owner` is always inside. Dead. |
| (c) remove, `rmdir`, restore on failure | ✅ measured | ✅ | ✅ | +0 (`printf` builtin) | owner-less lock, restore never runs | **refreshes the lock it declined to break** (measured); can stamp the judged line over a retaker's, making that holder unable to release and its refresher forfeit |
| (d) move `owner` aside *inside* the lock | ✅ | ✅ | — | +1 `mv` | — | — `rmdir` is then always non-empty. Dead. |
| (d′) move `owner` aside *beside* the lock | ✅ | ✅ | ✅ | +1..2 `mv` | owner-less lock **plus** litter in `${uvm_root}` no later run reclaims | same clobber risk as (c) |
| (e) remember the decided line for the message | ✗ | ✅ | ✅ | +0 | — | none |

(a′) and (e) compose, and the recommendation is both. Break-note count is **1** across the whole
wait for every candidate measured, so R7 does not discriminate between them.

## Measured

`/bin/bash` 3.2.57, APFS. Each row: `UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=5 uv --version` under
`temp_root.sh --offline --arch x86_64`. `main` = clean tree; `a′` = out-of-tree copy carrying
`uvm_lock_removable` plus a `last_holder` local.

| construction | `main` | a′ |
|---|---|---|
| stray entry | rc 1, 2 s, 6 stderr lines, 1 note, 1 timeout, **owner GONE**, `<none recorded>` | rc 1, 2 s, 6 lines, 1 note, 1 timeout, **owner present**, holder named |
| stray dot-entry | same, **owner GONE** | **owner present**, holder named |
| parent at 500 | same, **owner GONE** | **owner present**, holder named |
| lock at 500 | owner present, holder named (already green) | unchanged |
| aged, removable (control) | rc 0, `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`, lock removed | unchanged |
| aged, owner-less | rc 0, breaks, provisions | unchanged |
| fresh foreign lock | rc 1 at exactly 2 s, **0** break notes, holder named | unchanged |

Second-rank drive against the same root after a denied break: `main` 0 break notes with `owner`
mtime bumped to now; a′ 1 break note with the age preserved. Recovery command in the red state: rc
1, `Directory not empty`.

`uvm_lock_removable` unit-tested on bash 3.2 — removable for an empty dir and for owner-only;
declined for a stray file, a stray dot-file, a subdirectory, a dangling symlink, lock at 500, parent
at 500; removable again once restored. `shellcheck -s bash` clean. `temp_root.sh --offline uv
--version` on the patched copy: `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`, no lock left.

## Reasoned

- (a′) costs no fork by construction: `[[ -w ]]`, `[[ -e ]]`, `[[ == ]]` and pathname expansion are
  all builtins. The loop already spends a `mkdir`, two `stat`s, a `date` and a `sleep` per iteration,
  so even a fork would not have been decisive — but zero removes the argument.
- (a′) is a **precondition, not a proof.** It cannot see an entry created between the test and the
  `rmdir`, an immutable flag (`chflags uchg`, `chattr +i`), an ACL the mode bits do not express, or a
  sticky parent owned by someone else. `access(2)` also answers for the real uid, which is the right
  answer here. In every one of those the residue is today's residue, no worse, and (e) still names
  the holder — which is why (e) is not optional decoration.
- **Placement.** The probe belongs *after* R3's identity test and before the two removals, as a
  second condition on the same `if`. It consumes none of R3's evidence and R3 consumes none of its.
  Whatever R3 lands for the owner-less case, `uvm_lock_removable` stays a pure predicate on the
  filesystem.
- **Wording.** With (e) the residual case prints a line from a file that no longer exists under the
  label `holder, from the lock's owner file:`. Past tense — "as the lock's owner file recorded it" —
  covers both cases. Neither string is quoted in `README.md`, `uvm_help`, the conf example or the
  modulefile, so the same-commit obligation is `invariants.md` §5's last bullet only.
- The lock's own `uvm_unlock` (`:259-264`) has the identical two-step and the identical exposure. Out
  of scope for R4, which names `:481`; worth a line in whatever seed the cycle leaves behind.

## Recommendation

**(a′) + (e).** Gate both removals behind a fork-free removability predicate — `[[ -w "${lock%/*}"
&& -w "${lock}" ]]` and a glob rejecting any entry other than `owner` — and keep the decided holder
line in a local so the timeout message never depends on a file the break may have removed.

The cost accepted: **R4's state clause becomes best-effort behind a predicate that cannot be
complete.** A denial the predicate cannot foresee still leaves the lock owner-less, exactly as today.
That is the right cost, because the alternative that closes the state clause unconditionally is (c),
and (c) buys it by refreshing a dead lock into permanence — trading a lost diagnostic line for an
outage only a human clears. A predicate that is right about every constructible denial and honest
about the rest, with the message made independent of the file, keeps the user-visible promise in
R4's rationale unconditional while adding no new failure mode and no fork.

## Verbatim red-state construction (for a `verify:` gate)

```sh
# Under: .agents/factory/bin/temp_root.sh --offline --arch x86_64 sh <this file> <construction>
lock="${UVM_ROOT}/${UVM_PLATFORM}/.install.lock"
mkdir -p "${lock}"
printf 'host=elsewhere pid=987654 nonce=111222333\n' > "${lock}/owner"

case "$1" in
  stray)     : > "${lock}/stray-entry" ;;         # rmdir refused: Directory not empty
  dotstray)  : > "${lock}/.hidden-stray" ;;       # same, invisible to a bare glob
  parent500) : ;;                                 # chmod below: rm -f allowed, rmdir refused
esac
touch -t 202001010000 "${lock}/owner" "${lock}"   # aged past UVM_LOCK_STALE
[ "$1" = parent500 ] && chmod 500 "${UVM_ROOT}/${UVM_PLATFORM}"

UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=5 uv --version >/dev/null 2>err; echo "rc=$?"
chmod 700 "${UVM_ROOT}/${UVM_PLATFORM}"           # so the sandbox teardown can proceed

# Assertions. Red on main for all three constructions; green after.
test -f "${lock}/owner"                           || echo 'FAIL: owner destroyed by a denied break'
grep -q '<none recorded>' err                     && echo 'FAIL: timeout message lost the holder'
test "$(grep -c 'breaking ' err)" = 1             || echo 'FAIL: break note count (R7)'
test "$(grep -c 'timed out after' err)" = 1       || echo 'FAIL: no timeout message'
```

`chmod 500` on the *lock* directory is the shipped R7 construction and is **not** an R4 red state —
it denies `rm -f` too, so `owner` survives. Use it as the negative control.
