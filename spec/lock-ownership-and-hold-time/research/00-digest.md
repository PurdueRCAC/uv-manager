# 00 — Digest

Six briefs, fanned out breadth-first over R1-R6, plus a seventh added later. Everything below is
settled unless it says otherwise; where two briefs disagreed, the resolution and its reason are
recorded here rather than left for the build to discover.

R7 and R8 postdate the fan-out. R7 came from an audit of `invariants.md` against the code and is
argued in `PLAN.md` rather than in a brief. R8 came from a benchmarking run on Anvil after P1-P4 had
landed, and brief [07](07-acquire-race.md) carries its evidence — it is the one brief here that is not
this cycle's own research.

| Brief | Question | Verdict |
|---|---|---|
| [01](01-ownership-identity.md) | What makes a release provably ours | Owner line in a global, compared verbatim with the `read` builtin |
| [02](02-heartbeat-placement.md) | Where the heartbeat lives | Owned by the lock: refresher spawned at acquire, reaped at unlock |
| [03](03-knob-ordering-guard.md) | Where the ordering check goes | Top of `uvm_acquire_lock`, numeric form first |
| [04](04-exec-release-guard.md) | Which `exec` sites, and how | Four sites, two release points |
| [05](05-timeout-message.md) | What the timeout message says | Owner line inline, and a recovery command that works |
| [06](06-verification-recipes.md) | How each criterion is driven | One red recipe per R-ID, `sh -s` heredocs under `temp_root.sh` |
| [07](07-acquire-race.md) | Why a released lock reads as a broken mount | The `[[ ! -d ]]` inference is unsound; retry under a monotonic bound |

## The headline: R2 makes R4 load-bearing

Neither brief saw this alone. `exec` preserves the pid, so the refresher's `kill -0 "$$"` leash still
passes after the wrapper has been replaced by the real `uv`; an orphaned refresher then beats for the
whole length of the user's command and the lock it refreshes can never age out. The waiter's liveness
probe does not save it either — the recorded pid is alive, because it is now `uv`. Today's leak is
bounded at `UVM_LOCK_STALE`; with a heartbeat and no release-before-`exec` it is unbounded.

`uvm_unlock` reaps the refresher, and R4 calls `uvm_unlock` before every `exec`, so the guard is the
whole defense. **R4 lands before R2**, and the GOAL was amended to cover all four `exec` sites rather
than the three below the dispatch banner. A ceiling on the refresher's lifetime was considered and
rejected: it reintroduces the bound R2 exists to remove.

## Contradictions resolved

**The `owner` line's content (01 vs 02 vs 05).** 01 wants both command substitutions dropped from the
write — that is what narrows the `mkdir`-to-owner-write window from 3.0 ms to 0.10 ms, a 29-fold
narrowing of the only interval in which a stale release can destroy a live lock. But `time=` needs a
`date +%s` fork, and 05's draft message prints it. **Drop `time=`.** The line becomes
`host=${HOSTNAME} pid=$$ nonce=${RANDOM}${RANDOM}${RANDOM}` — three expansions, no forks. R5's
*Checked by* asks for the `owner` file, the host and the pid; the message already states its own
elapsed time, so nothing is lost. The nonce is not decoration: a single spawn loop consumed 694 pids/s
on an idle laptop, and Linux's common `pid_max` of 32768 wraps in 47 s against a 600 s stale window, so
`host`+`pid` can collide with a live foreign holder on exactly the `uv run`-in-a-loop workload this
project cites.

**Where the age is read (02 vs the existing code).** A directory's mtime tracks its entry list, not
writes to files inside it — POSIX, and measured on APFS with `owner` advancing across five beats while
the directory stayed pinned. `uvm_age` must stat `${lock}/owner`, falling back to the directory when
`owner` is absent, or the heartbeat is invisible and locks predating this change stop aging correctly.

**Making the `owner` write fatal (01, unresolved there).** 01 flags the `|| true` at `:243` as a
self-inflicted leak: a holder whose write failed cannot later prove ownership. Making it fatal is right
but not in the obvious way — setting `uvm_lock`, failing the write and calling `die` leaves the EXIT
trap reading an absent `owner`, declining ownership under R1, and leaking the lock regardless. The
write must `rmdir` the directory it just created and die **before** `uvm_lock` is set. That is safe
exactly there, and nowhere later: in the instant after `mkdir` returns, ownership is certain.

**Reap before read (02 vs 01's release ordering).** `uvm_unlock` must `kill` and then `wait` the
refresher before touching `owner`, or the refresher recreates the file between the `rm -f` and the
`rmdir` and leaves a directory `rmdir` refuses. Without the `wait`, bash also prints `Terminated: 15`
and the subshell body to stderr. Release order: early-out on empty `uvm_lock` → save the path to a
local → clear `uvm_lock` → reap → read `owner` → compare → `rm -f owner` → `rmdir`.

## Settled design

**Ownership (R1).** Record the owner line in `uvm_lock_owner` at acquire; at release compare the whole
line, and treat every non-match — absent, empty, truncated, unreadable, foreign — as "not ours, leave
it". The asymmetry is not close: a false leave is bounded by the stale breaker, a false delete destroys
live mutual exclusion and is bounded by nothing. `rmdir`'s refusal on a non-empty directory is a real
second guard and is kept; `rm -rf` would halve the outer window and throw that guard away.

**Heartbeat (R2).** `uvm_acquire_lock` spawns the refresher immediately after the owner write, with
`>/dev/null 2>&1 &` — a surviving child otherwise holds the caller's pipe open and `VER=$(uv --version)`
blocks on it, measured at 9 s. The refresher rewrites `owner` with byte-identical content every
`lock_stale / 10` seconds, floored at 1, and exits when `kill -0 "$$"` fails. It re-reads and compares
before writing: if the lock was broken and retaken at the same path, stamping our identity over the new
holder's `owner` would make R1 stop that holder releasing its own lock — an immortal lock produced by
the ownership fix itself. The waiter consults liveness before age: same host with a dead pid loses the
lock at once, same host with a live pid keeps it however long the work takes, anything else falls back
to the mtime. Refresh at progress points was rejected as structurally dead — the hold is one blocking
pipeline with two sub-millisecond statements after it.

**Knob ordering (R3).** Guard at the top of `uvm_acquire_lock`. Load-time placement at `:164-167` runs
before the help/`--version` short-circuit and would kill the two commands that document the knobs'
defaults — invariants §3 transposed one variable over. `uvm_init` placement would refuse `uvm doctor`,
the subcommand whose job is reporting what is wrong. The check must test numeric form before comparing:
with `UVM_LOCK_STALE=abc`, `set -u` kills the arithmetic at `:225` but **bash 3.2 still exits 0**,
because the EXIT trap's status overrides the error status, so `VER=$(uv --version)` returns empty and
true on the portability floor. `' '`, `0` and `-1` make every lock instantly stale — driven end to end,
a space broke a live foreign lock and provisioned over it.

**Release before `exec` (R4).** Two points: before `exec "${real_uv}" --version` in `uvm_self_update`,
and before the `case "${mode}"` block that carries the other three. The
`uvm_exec_real() { uvm_unlock; exec "$@"; }` helper is the most miss-resistant shape and is rejected —
neither the call nor the helper body matches R4's census pattern, so the contract's own verification
would report zero sites.

**Message (R5).** The advised `rmdir '<lock>'` **has never worked**: the `owner` file is inside the
directory, so it fails with `Directory not empty` for exactly the abandoned-lock case it is written
for. invariants §5's "the exact `rmdir` command to recover" is therefore unsatisfied by current code.
The replacement names the owner line, states that a recorded pid is on that host and not this one, and
gives `rm -f '<lock>/owner' && rmdir '<lock>'`. It stays on `die`: measured, one `printf` behind a
departed reader emits one diagnostic line, the same count BSD `cat` produces, and only when the
invoking process ignores SIGPIPE. §7 protects against N writes, which is why `uvm_status` and
`uvm_doctor` needed `cat`; `die` is one write. The stale-break note gains the same owner line — after
R1, "whose lock was that" is the first question following a break.

## Verification

`temp_root.sh [--offline] [--arch KEY] [--keep] COMMAND` runs `"$@"` directly and does not redirect
stdin, so `sh -s` with a quoted heredoc works and removes the escaping that makes earlier cycles'
`verify:` blocks unreadable. One sandbox per invocation, deleted on exit, so holder and waiter must be
started inside a single drive and assertions must live there too. The fixture is copied into the
sandbox, so appending a `UVM_FIXTURE_SLOW` sleep to `$UVM_FIXTURE_DIR/install.sh` stretches the hold
without touching anything tracked — the lever for every timing recipe. All five change gates are red
against `653b770`; R6 is green and must stay green.

R8's gate is the exception to the one-drive shape: it is statistical, not deterministic. Twenty bursts
of 64 concurrent ranks, because a single burst is red with probability `1 - 0.995^64 = 0.27` at a
pessimistic 0.5% per-rank floor, so twenty leave a false green at `0.73^20 ≈ 1.6e-3`. Measured red at
33 of 1280 and 24.5 s. Its second drive — an unwritable architecture directory still naming the fault,
non-zero, in under five seconds — is green today and green after, and exists so nobody satisfies the
first by deleting the `die`.

Two clauses no command can decide, marked inspection-only for the reviewer: R4's fork-free-release cost
claim, which the GOAL already assigns to a human, and "every `exec` site covered", which is a reading
of the four-line census rather than a proximity grep.

## Not established

Cross-node behavior, entirely — one host cannot produce a waiter unable to probe a holder's pid, so the
branch the heartbeat exists to serve is exercised only by forcing the `unknown` path. The NFS
attribute-cache term is reasoned from `nfs(5)` defaults: worst observed age is one beat plus
`acregmax`, 60 + 60 s against a 600 s threshold. That implies a floor worth documenting —
`UVM_LOCK_STALE` below roughly 120 s is unsafe for cross-node waiters on NFS, and was already so before
the heartbeat. Lustre and GPFS attribute coherence is reasoned from their lock managers. `mkdir`
atomicity on all three is taken on trust, as the GOAL declares up front. Fork costs are macOS figures;
the ratios transfer, the absolute milliseconds do not.

One item deliberately left out of scope: `uvm_age` reads `0600` as octal 384 s at `:225` today. Any
guard must read it the same way, or the two disagree. That is a separate `issues/` candidate, not this
cycle's.
