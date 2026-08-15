# 02 — The hold-time heartbeat: placement and mechanism

Scope: R2, and its interaction with R1 and R6. Every claim marked *measured* was produced by driving a
modified copy of the wrapper outside the working tree under `.agents/factory/bin/temp_root.sh
--offline`, on bash 3.2.57 / APFS, with a `UVM_FIXTURE_SLEEP` knob added to the offline fixture so the
hold can be stretched. The working tree was not edited.

## Recommendation

**(d), in its narrow form: the heartbeat is owned by the lock, and the waiter's break decision consults
liveness before age.** `uvm_acquire_lock` spawns a refresher immediately after writing `owner` and
`uvm_unlock` reaps it; the refresher rewrites `${lock}/owner` with byte-identical content every
`lock_stale / 10` seconds and exits when `kill -0 "$$"` fails. The waiter, before testing age, reads
`owner`: a holder on this host whose pid is gone loses the lock at once, and one that answers keeps it
however long the work takes. Cross-node waiters fall back to the mtime, which is what the heartbeat
exists to keep fresh.

Measured, with `UVM_LOCK_STALE=20` against a 45-second holder: the waiter printed no `breaking stale
provisioning lock`, the holder finished, released its own lock, and left `current -> versions/9.9.9`.
The same drive against pristine `main` is the red state — `breaking stale provisioning lock (3s old)`,
both processes installing, and `lock after: GONE`.

## (c) is not viable, and the reason is structural

The lock is held from `:313` to `:364`. Between those lines the only statements that could carry a
refresh are `uvm_installed_version` at `:351` and `uvm_point_current` at `:363`, both after the fetch
and both sub-millisecond. The hold is one blocking foreground pipeline with nothing inside it. A
refresh at progress points refreshes only after the slow part is already over, which is precisely when
it no longer matters. Rejected.

Inverting the pipeline — background the install, refresh from the main shell — does work: measured,
`pipefail` propagates correctly through `wait "$!"` in bash 3.2, for a bare backgrounded pipeline
(rc=7) and for a subshell wrapping one (rc=7), so R6's failure detection survives. It is rejected on
placement, not mechanism. It welds the heartbeat to `uvm_install`'s pipeline, and `purge-tree-repair`
R7 — the reason this cycle exists — holds the lock across a rebuild that is not that pipeline. A
heartbeat scoped to the lock covers every holder, present and future, with no second implementation.

## The mtime has to move to a file, not the directory

A directory's mtime changes when its entry list changes, not when a file inside it is written. That is
the specification, so it holds on Lustre, GPFS and NFS as well as locally; measured on APFS, `owner`
advanced 1786810222 → 1786810231 across five samples while the lock directory stayed pinned at
1786810220 the whole time. **`uvm_age` must stat `${lock}/owner`.** Left on the directory it reads the
acquisition time forever and the heartbeat is invisible.

The fallback when `owner` is absent — an older wrapper's lock, or the 0.104 ms window between the
`mkdir` at `:208` and the `owner` write at `:242` — is to stat the directory, exactly as today:
`uvm_age "${lock}/owner" || uvm_age "${lock}"`. Measured: a lock directory with no `owner` and
`UVM_LOCK_STALE=1` is still broken as stale, so behavior for locks the heartbeat never touched is
unchanged.

## Mechanics

**A builtin redirect, not `touch`.** `printf '%s\n' "${uvm_owner}" > "${lock}/owner"` costs 0.080 ms
per beat including the guard read, and forks nothing. `touch` would fork and would have to target the
directory, which does not work.

**Order `2>/dev/null` before the input redirect.** `read -r line < "${f}" 2>/dev/null` leaks the
shell's `No such file or directory` to the user's stderr, because redirections are processed left to
right and the failing one is opened first. Measured; it appeared three times in one drive.
`read -r line 2>/dev/null < "${f}"` is silent.

**Detach the refresher's stdout.** A surviving background child holds the write end of the caller's
pipe open, so `VER=$(uv --version)` blocks until it exits — measured at 9 s against an 8 s child, 0 s
with `>/dev/null 2>&1` on the subshell. The normal path reaps the refresher before the `exec`, so this
is latent rather than live, but it is one token and it forecloses the §7 failure the invariant names by
name.

**`wait` after `kill`, not `kill` alone.** Without it bash prints `Terminated: 15` and the entire
subshell body to stderr — measured, isolated to stderr — and the refresher can recreate `owner`
between the `rm -f` and the `rmdir`, leaving a non-empty directory that `rmdir` refuses. `kill` then
`wait` returns in 16.6 ms even with the child blocked inside `sleep 30`, once per provisioning
invocation. The orphaned `sleep(1)` grandchild outlives it and writes nothing.

**Traps are not inherited.** An async subshell resets traps to default, measured: the EXIT trap ran
once, in the parent. The refresher cannot release its parent's lock by exiting. `trap - EXIT INT TERM`
inside it is belt and braces, not a fix.

**Job control emits nothing.** Non-interactive bash 3.2 runs with `$-` = `ehuB` — no `m` — so `&`
prints no `[1] 12345` and no `Done`.

## R1 cannot be undermined by the heartbeat

The refresher writes the *same bytes* every beat: host, pid, and the **acquisition** time, not the
current time. Measured across five beats, `owner` read `host=… pid=12339 time=1786810220` unchanged
while its mtime advanced. Identity is therefore fixed at acquire and freshness lives entirely in the
mtime, so a holder can never become foreign to itself, and R5's message can still say how long the
lock has been held.

One real hazard remains and needs a guard. If the lock is broken and retaken at the same path, a
refresher writing by path would stamp its own identity over the *new* holder's `owner`, and R1 would
then stop that holder from releasing its own lock — an immortal lock produced by the ownership fix
itself. The refresher must re-read and compare before writing. Measured: with a foreign record in
place the guard declines and the record survives.

## The orphan, and what actually closes it

A plain background refresher outlives a SIGKILLed holder. Measured in the real script: the holder was
killed at t, `owner`'s mtime kept advancing at t+3, t+5, t+7 and would have done so forever. With
`kill -0 "$$"` in the loop the mtime freezes at the instant of the kill. `$$` inside a subshell is the
holder's pid in bash 3.2, and `kill` is a builtin.

A pipe leash would be stronger, and it is **not available at the portability floor**: bash 3.2 returns
rc=1 from `read -t` for *both* timeout and EOF, so a leashed refresher cannot tell "one second passed"
from "my parent died". Measured — the leash fired at t+1 with the holder still alive. The `>128`
timeout convention is bash 4.0 and later.

`kill -0` leaves pid reuse. That is why the waiter's liveness probe earns its place: it is checked
*before* age, so even an immortal refresher does not protect a lock whose recorded pid is gone.
Measured against a deliberately unleashed build — the refresher was still beating and the waiter still
reported `breaking provisioning lock abandoned by a dead process` and proceeded. Same-host contention
is fully covered by the probe; the leash is what protects cross-node waiters, who cannot probe. Both
halves fail together only if the holder is killed *and* its pid is reissued within one beat, which
requires cycling the whole pid space in that window.

The probe also converts self-nesting from a possible self-break into a loud timeout: measured with
`owner` naming the waiter's own pid, the waiter timed out and the lock survived.

## Interval, and NFS

`lock_beat=$(( lock_stale / 10 ))`, floored at 1, derived beside `lock_stale` at `:166`. No new
environment variable, which the GOAL's non-goals forbid; it scales with a site's own configuration;
and it makes R2's gate drivable in tens of seconds rather than minutes.

The worst age a remote waiter can observe is one beat plus the NFS attribute-cache lag. The Linux NFS
client's `acregmax` default is 60 s for regular files, so at the 600 s default the worst case is
60 + 60 = 120 s against a 600 s threshold — a 5× margin. Lustre and GPFS return coherent attributes
under their lock managers and do not contribute a term. This is reasoned from documented defaults, not
measured. The consequence worth writing down is a floor: `UVM_LOCK_STALE` below roughly 120 s is
unsafe for cross-node waiters on NFS, and that was already true before the heartbeat.

## Cost

Nothing on the warm hot path: `uvm_install`'s fast path at `:308` returns before `uvm_acquire_lock`, so
no refresher is spawned. Measured — no refresher process after a warm drive, 10 ms per warm
invocation. Per provisioning invocation the true count is one fork for the subshell, one `sleep` fork
per beat, and 16.6 ms of `wait` at release. A ten-minute repair at the default interval is 21 forks.
`lint.sh` passes on the prototype: bash 3.2 parse, shellcheck, symlinks.

## One defect in the contract

R6's gate is written as `git grep -c flock bin/uv-manager` returning 0. It returns **1** on pristine
`main` — `:172` names `flock` in the banner comment explaining why the discipline is `mkdir`. The gate
as written fails before any change is made. It should assert that no `flock` is *invoked*, not that the
word is absent.

## Not established

The cross-node case, entirely. One host cannot produce a waiter that is unable to probe a holder's pid,
so the branch the heartbeat exists to serve is exercised here only by forcing `unknown`. The NFS
attribute-cache term is reasoned from `nfs(5)` defaults; the Lustre and GPFS coherence claims are
reasoned from their lock managers. None of the three was measured, and the GOAL already declares
parallel-filesystem semantics out of reach.

The `rm -f` / `rmdir` race the `wait` closes did not reproduce in the probe — `rmdir` succeeded. Its
absence in a handful of attempts is not evidence it cannot happen, and the `wait` is cheap enough that
proving it was not worth the drives.

Pid reuse was not exercised. Whether a real cluster login node cycles `pid_max` inside one beat is a
site fact, and the escape hatch if one ever does — a hard ceiling on the refresher's lifetime, after
which the lock resumes aging — is left unrecommended because it reintroduces the bound R2 removes.
