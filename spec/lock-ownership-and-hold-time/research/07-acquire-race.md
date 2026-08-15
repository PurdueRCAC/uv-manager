# 07 — A lock released during the acquire race is misread as a fatal error

Scope: R8, added to the contract by amendment after P1–P4 had landed. Unlike briefs 01–06 this one was
not produced by the planning fan-out. It originates as `issue-locking.md` in the companion paper
repository, written there from a benchmarking run on Anvil while this cycle was mid-flight, and is
carried here because `spec/{slug}/` is the retained account and the other repository is not this one's
history. The Anvil figures are that file's, quoted unchanged; the local measurements were taken on this
branch at `f5af486`.

## Conclusion

**`uvm_acquire_lock` decides *why* `mkdir` failed by looking at the filesystem again afterwards, and
the inference is unsound. Retry, and let persistence across a bounded number of attempts distinguish
contention from a broken mount.** Confidence: high — reproduced on two operating systems, two
filesystems and two machine classes, and the fix's red state is measured.

## 1. The defect

```bash
while ! mkdir "${lock}" 2>/dev/null; do
  # Distinguish contention from a real failure. If the lock is not there,
  # mkdir failed for some other reason (permissions, quota, ENOSPC) and
  # waiting will never help.
  if [[ ! -d "${lock}" ]]; then
    die "cannot create provisioning lock at ${lock} — check permissions and quota on ${uvm_base}"
  fi
```

`mkdir` fails `EEXIST` because a holder has the lock; the holder releases before the `[[ ! -d ]]` test
runs; the test finds no lock and concludes the `mkdir` must have failed for permissions or quota. A
**released** lock is reported as an unwritable filesystem, and the process dies rather than retrying
the acquisition it was one iteration away from winning.

The window is the interval between `mkdir` returning and the test evaluating. It is short, which is why
this is a contention-rate bug rather than a load bug: it needs a holder whose release lands inside that
interval, and the more waiters cycling per second, the more chances there are for one to. Every path
that removes the lock can supply the release, including the loop's own dead-holder and stale-holder
breaks, which `rmdir` and `continue` straight back into the same race.

The diagnostic makes it worse. The message names permissions and quota, so an operator who hits this
investigates a healthy filesystem. No wording would help, because the code does not know what happened
— it is reporting a guess.

## 2. Anvil, the original evidence

`bench/uvm-bench.sh concurrency`, 64 simultaneous cold starts against an empty `UVM_ROOT` on GPFS
scratch, provisioning uv 0.12.5. Two runs, same day, same filesystem, same binary:

| Host | Class | Cold wall | Successes | Installs |
|---|---|---|---|---|
| `login00` | login | 12.05 s | **64 / 64** | 1 |
| `a706` | compute | 2.71 s | **62 / 64** | 1 |

From `bench/results/a706-x86_64-20260815T160020/concurrency-cold.log`:

```
[7] uv-manager: installing uv (0.12.5) for x86_64
[7] everything's installed!
[23] uv-manager: cannot create provisioning lock at .../x86_64/.install.lock — check permissions and quota on ...
[39] uv-manager: cannot create provisioning lock at .../x86_64/.install.lock — check permissions and quota on ...
```

Ranks 23 and 39 exited non-zero. Nothing was wrong with the filesystem: the other 62 ranks wrote to it
in the same second, `fs.tsv` records the mount writable with working `flock`, and the identical burst
on the login node passed 64/64.

The compute node is where it reproduces because the compute node is **faster**. The same burst
completes in 2.71 s there against 12.05 s on the shared login node, so the same 64 acquisitions pack
into roughly a quarter of the window and the release-during-race event becomes likely instead of merely
possible. The login-node run is not evidence of correctness; it is a slower machine hiding the race.

## 3. Reproduced locally, and at the same rate

macOS 15 / APFS / bash 3.2.57, under `.agents/factory/bin/temp_root.sh --offline`, 64 concurrent
`uv --version` against one shared cold root per burst.

| Measurement | Result |
|---|---|
| Ten bursts on this branch | 9 of 10 bursts lost at least one rank; **25 of 640 ranks (3.9%)** |
| Anvil `a706`, for comparison | 2 of 64 (3.1%) |
| Twenty-burst gate, first run | **33 of 1280 (2.6%)**, `nonzero` also 33 |
| One burst | 1 s wall |

`nonzero` matching `misdiagnosed` exactly is the useful part: every rank that failed in the burst
failed *this* way, so the gate discriminates one defect rather than aggregating several.

A rate this close to Anvil's on entirely different hardware and a different filesystem says the window
is set by the wrapper's own instruction sequence, not by storage latency.

## 4. This cycle does not measurably worsen it

A matched A/B — `main` in a `git worktree` against this branch, same machine, same fixture, interleaved
trials:

| Tree | Ranks lost | Rate |
|---|---|---|
| `main` | 114 / 6400 | 1.78% |
| this branch | 133 / 6720 | 1.98% |

A 0.20 pp delta at **0.83σ**, with `main`'s own per-trial spread (1.17%–2.30%) wider than the gap.

This is recorded because it is the one place the R7 admission precedent does not reach. `5fc4196`
justified grafting R7 onto a locked GOAL on two grounds, and the second is explicit in its body: "This
cycle worsens it, so it is not deferrable." That clause is false here. R8 was admitted on a different
argument — that deferring does not protect the cycle, because `review-rubric.md`'s single deferral
exception also requires a `GOAL.md` criterion that repair would fail, and none exists. Structurally the
cycle does add re-entry paths into the racy guard: P3 took the in-loop `rmdir`-then-`continue` paths
from one to two, and P6 adds a third. That is a reachability argument, not a measured one, and it is
kept distinct from the numbers above.

## 5. Why deciding by a second look cannot be repaired

Any observation after the fact races the same way — the lock's absence at time *t+1* says nothing about
why `mkdir` failed at time *t*. Two ways out:

- **Read the errno.** `mkdir`'s stderr carries it. Rejected: parsing a locale-dependent string.
- **Stop needing it.** Retry, and let persistence rather than a single sample distinguish contention
  from a broken mount. Cheaper, and no locale exposure.

Three properties of the second are load-bearing, each a distinct way to get it wrong:

**The bound is not a refinement — it is the fix.** A bare `continue` spins forever on EACCES, EDQUOT or
ENOSPC, which are the ordinary operational faults, never increments `waited`, never sleeps, and turns
today's clean sub-second non-zero exit into a hot loop. That is strictly worse than the R7 defect nine
lines below it.

**The counter must be monotonic**, never reset on the lock-present branch. With R7's
`[[ -d "${lock}" ]] || continue` in place, an alternation of absent-retry and successful-break would
otherwise never reach the accounting. Producing that alternation requires an agent recreating a
stale-on-arrival lock every iteration, which after P1's owner line — live pid, fresh mtime — nobody can
do; but "not producible" is exactly the weaker guarantee R7 exists because someone accepted once. A
monotonic counter bounds total iterations at `lock_timeout + 3`, each extra one a single `mkdir`
syscall, and needs no argument.

**The `die` stays.** Delete it and a genuinely unwritable mount stalls every rank for the full
`UVM_LOCK_TIMEOUT` and then reports the wrong fault. Measured on this branch: an unwritable
architecture directory returns rc=1 in 0 s with the message intact. That is a control the gate keeps
green, not a behavior to trade away.

## 6. R7 and R8 compose; neither subsumes the other

The two predicates are duals evaluated at different points of one iteration and mutually exclusive
within it: `[[ ! -d "${lock}" ]]` after *our failed `mkdir`*, `[[ -d "${lock}" ]]` after *our own
`rmdir`*. R7 without R8 leaves the fatal misdiagnosis intact; R8 without R7 leaves the denied-break
spin unbounded. Their textual overlap is one line — the `local waited=0 age holder pid` declaration
both extend — which is a sequential edit if P6 lands first and a conflict if it does not.

Semantically they answer one question: when may the loop re-enter `mkdir` without paying the
accounting? R7's answer is "only when the directory is actually gone"; R8 applies that rule one branch
earlier under a constant bound. The finished loop states a single invariant — **every iteration either
removes something or is charged to the timeout, and the number of uncharged iterations is bounded by a
constant.**

## 7. The invariant this overturns

`.agents/factory/invariants.md` §5 states the unsound inference as doctrine: "if the lock directory is
absent after a failed `mkdir`, the failure is permissions/quota/ENOSPC and waiting will never help —
die with that message." Anvil disproves it. This is the only place the premise is written down —
`AGENTS.md` never states it and `README.md` never mentions it — so the same-commit obligation is one
bullet in one file. The imperative survives; only its evidence changes.

Because it is an overturn rather than an addition, `AGENTS.md` requires the edit in the diff *and* in
front of a human, "never in the diff alone". That is what the R8 amendment commit is.

## Not established

- **GPFS and Lustre semantics**, as everywhere in this cycle. The Anvil run is one filesystem on one
  cluster; APFS agreement on the rate is suggestive, not a proof that the window behaves identically
  under a distributed metadata server.
- **The true per-rank rate at scale.** Every figure here is 64-rank bursts. Whether the rate rises with
  rank count, and how it interacts with a slow first install, is unmeasured.
- **Whether three is the right bound.** It is chosen as "clearly more than a race, clearly less than a
  broken mount", not derived. Nothing measured says a persistent fault ever clears on the second look;
  if one does, the bound is where that would surface.
- **The original file's citations.** `issue-locking.md` pairs `bin/uv-manager:312-318` with
  `uvm_version="0.4.1"`; at 0.4.1 and on `main` the guard is `:213`, and `:317` is this branch. The
  drift is in the line numbers only — the quoted code and the message are byte-identical across all
  three. The code is ground truth.
