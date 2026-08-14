# Research — the repair lock: reentrancy, early-out, and scale

Scope: R5, R7, and the `uvm_acquire_lock` / `uvm_unlock` high-blast-radius region. Every claim below
was measured by driving a modified copy of the wrapper outside the working tree, under
`.agents/factory/bin/temp_root.sh --offline`. The working tree was not edited.

## Conclusion

**The self-deadlock is real, and it is not the worst of the three defects here. Confidence: high —
all three were reproduced.** A repair that holds `${uvm_root}/.install.lock` and then calls
`uvm_install` waits `UVM_LOCK_TIMEOUT` seconds for a lock held by its own process and then exits 1.
Two further hazards are worse because they fail quietly: the existing early-out predicate lets every
waiter walk away *while the repair is still running*, and a lock held across the dispatch tail's
`exec` is leaked permanently.

The way out is **(c), restructured so repair never nests**: split `uvm_install` into a thin
acquire/re-check/release wrapper and a lock-free `uvm_install_locked` body. Repair takes the lock
once and calls the body. One lock, one acquisition, `uvm_unlock` keeps one meaning, the traps are
untouched. A working prototype of this — plus a predicate-parameterized early-out — passes
`lint.sh`, parses under bash 3.2, and repairs a damaged tree exactly once across 12 concurrent
invocations.

## The deadlock, measured

Probe: a subcommand that acquires the lock and then calls `uvm_install "" 1`.

| Drive | Result |
|---|---|
| Cold tree, `UVM_LOCK_TIMEOUT=3` | `timed out after 3s waiting for provisioning lock`, exit 1, elapsed 3.0s |
| Cold tree, `UVM_LOCK_TIMEOUT=10` | same, elapsed 10.30s |

The wait is linear in the timeout, so the default is a 180-second stall before exit 1. The EXIT trap
does fire and does remove the lock, so the failure is a stall-then-die, not a permanent leak.

Two qualifications that matter for how this defect would present.

**It hides on a warm tree.** `uvm_install`'s fast path (`:308`) returns before acquiring when
`uvm_have` is already true. A repair whose damage is a tool venv — the case that motivates the cycle
— calls `uvm_install "" ""`, hits that fast path, and never nests. The deadlock only fires when
`uvm_install` has real work: uv itself missing, or `force` set. That is R4's first remedy, so it will
reach production; it will not reach a casual test.

**With `UVM_LOCK_TIMEOUT > UVM_LOCK_STALE` it stops deadlocking and starts corrupting.** Driven with
`UVM_LOCK_STALE=2 UVM_LOCK_TIMEOUT=60`, the nested acquire declared its *own* lock stale, `rmdir`'d
it, re-acquired, installed, and exited 0 in 3.35s:

```
uv-manager: breaking stale provisioning lock (3s old): .../.install.lock
uv-manager: installing uv (latest) for arm64
```

Nothing enforces an ordering between the two knobs. The window between the self-break and the
re-`mkdir` admits a second repairer, and `uvm_install`'s unlock at `:364` then releases the lock the
outer repair frame still believes it holds. Mutual exclusion is gone and the exit status is 0.

## Two hazards the topic did not name

**The early-out already breaks R5.** `uvm_have "${want}"` with an empty `want` is one `-x` test on
`${uvm_current}/uv`. On a warm tree with a damaged tool venv that test is *true*, so a waiter returns
1 immediately. Measured with a holder mid-repair: `acquire rc=1 after 0s`. Every rank that did not
win the lock proceeds straight into the half-deleted venv and gets the ImportError the cycle exists to
prevent. Defeating it with `force=1` is not a fix either: the force path skips the early-out
entirely, so the waiter waits the full duration, acquires, and repairs again — N serial repairs
rather than one.

**A lock held across `exec` is leaked forever.** The dispatch tail `exec`s at `:854`; `exec` replaces
the process image and the EXIT trap never runs. Driven directly: `RESULT: LOCK LEAKED PAST exec`.
Nothing reclaims it until `UVM_LOCK_STALE` (600s default) elapses and another process breaks it, and
during those ten minutes every other rank's repair blocks. The repair must release before returning
to the dispatch tail — the trap will not save it.

## The three designs

**(a) A separate `.repair.lock`.** Works, and costs the most. Repair and install locks must always be
taken in one order or two processes deadlock against each other for real; `uvm_unlock` releases only
what the single `uvm_lock` global names, so a second lock needs either a second global with the three
traps at `:187-189` releasing both, or a lock list. Its stale age is a new problem: a real repair
(python install plus several tool environments over an index) plausibly runs past the 600s default,
and the stale-breaker would then break a live repair lock mid-rebuild. It also buys nothing R5 asks
for — the repair lock fences repairers against each other, which the install lock already does.

**(b) A reentrancy guard on `uvm_lock`.** Broken in its naive form, and measured: with the outer frame
holding the lock, one nested `uvm_unlock` leaves `uvm_lock=''` and `lockdir_exists=no`. `uvm_install`
unlocks at `:318`, `:345` and `:364`, so any nesting releases the outer lock early and another process
enters. Making it safe needs a depth counter, which gives `uvm_unlock` two meanings — decrement when
called from `uvm_install`, force-release when called from a trap — on the most concurrency-sensitive
function in the file. The strongest variant is to have `uvm_acquire_lock` report acquisition versus
reentry and let `uvm_install` unlock only if it acquired, but that is (c) with extra state.

**(c) Split the install body. Recommended.** `uvm_install` keeps the fast path, the acquire, the
re-check and the unlock; a new `uvm_install_locked WANT` holds the fetch, version read-back, rename
and `uvm_point_current`, and assumes the lock is held. Repair acquires once and calls the body. Two
incidental simplifications fall out: the explicit `uvm_unlock` before each `die` inside the body is
redundant, because `die` exits and the EXIT trap releases — verified by removing both and driving a
failed install (`released by trap alone`). The alternative reading of (c), "decide, release, then
repair", is wrong: it opens a window in which every rank concludes damage, releases, and repairs
concurrently.

Prototype result, 12 concurrent `uvm repair` invocations against one damaged sandbox tree:

```
  1 REPAIRING
  1 re-check under lock is clean
 10 another process repaired it
  0 nonzero exits
```

`lint.sh` passes on the modified copy (bash 3.2 parse, shellcheck, symlinks), and
`temp_root.sh --offline uv --version` and `--arch aarch64 uvm status` reach their usual
post-conditions.

## The three questions

**Generalizing the early-out without breaking §4.** Give `uvm_acquire_lock` an optional third
parameter naming the satisfaction predicate, defaulting to `uvm_have`:
`local want="$1" force="$2" satisfied="${3:-uvm_have}"`, and call `"${satisfied}" "${want}"` in the
loop. Every existing call site is unchanged, `uvm_have` stays the single spelling of the *version*
question, and the lock stops hardcoding which question is being asked. Plain indirect invocation, not
a nameref — namerefs are bash 4.3 and would breach the 3.2 floor. Verified to parse under 3.2 and to
pass shellcheck. The repair's predicate must be the conjunction of everything *this* invocation
needs, evaluated as one: a predicate that goes true after the first of three remedies releases the
waiters into a tree that is still half repaired.

**Return-value semantics.** Keep them. `rc=0` means acquired, `rc=1` means the predicate is now
satisfied — for repair, "someone else repaired what I need, proceed". A waiter never has to
distinguish rc=1 from a timeout, because the timeout does not return: `die` exits 1 from inside
`uvm_acquire_lock`, which is R7's non-zero exit. R7 also wants the damage named, and that needs no
new parameter — have the repair `note` the damage *before* acquiring. Measured, the waiter's stderr
then reads `repair: damage detected under <root>` followed by `timed out after 1s waiting for
provisioning lock: <path>`, exit 1. After acquiring, re-check under the lock before repairing,
mirroring `:316`, or the winner of a tight race repairs twice.

**Traps.** Under (c) nothing changes: one lock, one `uvm_lock`, the three traps at `:187-189` already
cover EXIT, INT and TERM. Under (a) they must release both locks or a SIGTERM at walltime leaks the
repair lock with no stale-breaker behind it. Under (b) the trap must force a full release rather than
a decrement. In all three, the `exec` leak above is the binding constraint, and no trap addresses it.

## Scale

A waiting rank costs, per poll iteration, one `mkdir` returning EEXIST, one `stat` fork inside
`uvm_age` (two on macOS, where `stat -c` fails before `stat -f` succeeds), one `date` fork, one
`sleep` fork, and one `[[ -x ]]` for the early-out. Counted with stub binaries over a 5-iteration
wait: 6 `mkdir`, 10 `stat`, 6 `date`, 4 `sleep`. Call it three metadata operations and three process
spawns per rank per second. Ten thousand ranks waiting on one repair is 30,000 metadata operations
per second against a single metadata server, sustained for the whole repair — the same burst class
the GOAL already flags for the six-directory `mkdir -p`, but held for minutes instead of milliseconds.
It is worth naming in `PLAN.md` even though the fix is out of scope.

`waited` counts failed `mkdir` attempts, not seconds. Locally 10 iterations took 10.30s; on a loaded
MDS each iteration costs more than its `sleep 1`, so `timed out after 180s` is a lower bound on the
wall clock, and the message overstates its own precision. The drain after a repair completes is fast,
because a waiter that early-outs never acquires anything — the risk is not the drain, it is a repair
that runs longer than 180 seconds, which a python install plus several tool environments over a cold
cache plausibly does. Every waiter then dies at 180s having burned 180s of allocation each. R7 makes
that a clean failure, which is this cycle's obligation; the GOAL correctly defers the number.

## Not established

The repair's actual duration. R4's rebuild needs a real index and the `--offline` fixture cannot
reach one, so the prototype substitutes a `sleep`. Whether a real repair fits inside 180s is the one
number that decides whether the scale paragraph above is a footnote or the headline, and it can only
be measured on a cluster.

Lustre, GPFS and NFS semantics. A local temp directory does not exercise them. `mkdir` atomicity is
taken on trust from the existing discipline, per R5's own wording. The `exec` leak, however, is
filesystem-independent and reproduces anywhere.
