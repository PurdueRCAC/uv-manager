# PLAN — The provisioning lock can be released by a process that does not hold it

> **Status:** Draft for review · **Last updated:** 2026-08-15
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).
> Every design element traces to a GOAL R-ID.

## 1. Summary

The lock gains an identity and a pulse. `uvm_acquire_lock` records an owner line it can recognize
later, refreshes it from a background process for as long as the holder lives, and refuses a knob
configuration that would let a waiter break a live lock; `uvm_unlock` releases only what that identity
matches. Every `exec` of the real `uv` releases first, which under a heartbeat stops being hygiene and
becomes the only thing preventing an unbreakable lock. The work is confined to the four functions of
the provisioning-lock section plus two one-line release points, and the mechanism stays `mkdir`.

## 2. Design

### The owner record

`uvm_acquire_lock` builds the owner line **before** the `while ! mkdir` loop, from expansions only:

```
host=${HOSTNAME} pid=$$ nonce=${RANDOM}${RANDOM}${RANDOM}
```

Three expansions, no forks. This replaces a line built after the `mkdir` from two command
substitutions (`uname -n`, `date +%s`), which left the lock directory existing with no `owner` file for
3.0 ms; from variables the window measures 0.10 ms. That window is the only interval in which a stale
release can destroy a live lock, so the change is a 29-fold narrowing bought from a rewrite made for
other reasons.

`time=` is **removed**. It duplicated the directory mtime, and the fork it cost is what widened the
window. R5's message states its own elapsed time, so nothing a user reads is lost. The `nonce` is
load-bearing rather than decorative: a spawn loop consumed 694 pids/s on an idle laptop and Linux's
common `pid_max` of 32768 wraps in 47 s against a 600 s stale window, so `host`+`pid` alone can collide
with a live foreign holder on precisely the `uv run`-in-a-loop workload this project cites.

The line is kept in a new global `uvm_lock_owner`, alongside the existing `uvm_lock`.

The `|| true` on the owner write is **removed**. A holder whose write failed cannot later prove
ownership and would leak its own lock for a full stale window. On failure the code `rmdir`s the
directory it just created and dies — safe in that instant and nowhere later, because ownership is
certain the moment `mkdir` returns. This happens **before** `uvm_lock` is set: setting it first and
dying would leave the EXIT trap reading an absent `owner`, declining ownership, and leaking the lock
regardless.

### Release

`uvm_unlock` becomes, in order: early-out on an empty `uvm_lock`; copy the path to a local and clear
`uvm_lock` and `uvm_lock_owner`; reap the refresher; read `owner` with the `read` builtin; compare the
whole line; `rm -f owner` and `rmdir` only on a match, otherwise `note` and leave.

Clearing first is what makes the function idempotent — the EXIT trap runs after the INT handler's
`exit 130`, and with the clear on the success path the declined case would re-read the file and
re-print its note on the way out. It is also what keeps R4's guard free: on a path holding no lock the
function is one `[[ -n ]]` test and no fork.

Every non-match — absent, empty, truncated, unreadable, foreign — leaves the directory. The asymmetry
decides it: a false leave is bounded by the stale breaker, a false delete destroys live mutual
exclusion and is bounded by nothing. The comparison is against the string, never the `read` return
code, because a file with no trailing newline returns 1 with the data assigned. Two spellings are
load-bearing and easy to get wrong: `2>/dev/null` must precede the input redirect or the shell's own
"No such file" reaches the user's stderr, and the variable must be initialized in the same `local`
because a failed read leaves it at its prior value.

`rmdir`'s refusal on a non-empty directory is kept as a second guard. `rm -rf` would halve the outer
window at the cost of throwing that guard away.

### The heartbeat

A new `uvm_lock_heartbeat` is spawned by `uvm_acquire_lock` immediately after the owner write, as
`uvm_lock_heartbeat "${lock}" >/dev/null 2>&1 &`, its pid held in `uvm_lock_beat_pid`. The redirection
is not decoration: a surviving background child holds the caller's pipe open, and `VER=$(uv --version)`
was measured blocking 9 s on one.

The body loops: sleep `lock_beat`, exit if `kill -0 "$$"` fails, re-read `owner` and exit unless it
still matches `uvm_lock_owner`, then rewrite it with byte-identical content. The re-read is the guard
against the failure this fix could otherwise create — if the lock were broken and retaken at the same
path, stamping our identity over the new holder's `owner` would make R1 stop *that* holder from
releasing its own lock. `lock_beat` is derived beside the existing knobs as
`$(( lock_stale / 10 ))`, floored at 1: it scales with a site's own configuration and adds no
environment variable, which the GOAL forbids.

Content is byte-identical every beat — freshness lives entirely in the mtime, so a holder can never
become foreign to itself.

`uvm_age` changes what it stats: `uvm_age "${lock}/owner" || uvm_age "${lock}"`. A directory's mtime
tracks its entry list, not writes to files inside it, so left on the directory the heartbeat is
invisible. The fallback preserves today's behavior for a lock with no `owner` file — an older wrapper's,
or one caught inside the 0.10 ms window.

The waiter consults liveness before age: reading `owner`, a holder on this host whose pid is gone loses
the lock at once, one that answers keeps it however long the work takes, and anything else falls
through to the mtime test. That probe is what covers `kill -0`'s residual pid-reuse gap; the leash is
what covers cross-node waiters, who cannot probe. Both fail together only if a holder is killed and its
pid reissued inside one beat.

Refreshing at progress points was rejected as structurally dead: the hold is one blocking pipeline with
two sub-millisecond statements after it.

### Knob ordering

A guard at the top of `uvm_acquire_lock` tests numeric form, forces base 10, then tests ordering, and
dies naming both variables and the seconds it judged. The numeric test is not optional. With
`UVM_LOCK_STALE=abc`, `set -u` kills
the arithmetic at `:225` but **bash 3.2 exits 0**, because the EXIT trap's status overrides the error
status — so `VER=$(uv --version)` returns empty and true on the portability floor. The same guard
catches `' '`, `0` and `-1`, each of which makes every lock instantly stale; a space was driven end to
end breaking a live foreign lock and provisioning over it.

Base 10 is not optional either, and it has to come after the form test. Bash reads a leading zero as
octal: `UVM_LOCK_STALE=0600` is 384 s, and `0800` is not a number at all. Left raw, the guard judges
seconds the operator never wrote — a legal `TIMEOUT=500 STALE=0600` is refused, and the refusal prints
`UVM_LOCK_TIMEOUT=500  UVM_LOCK_STALE=0600` under a headline saying the first must be less than the
second. `^[0-9]+$` also admits `08`, `09` and `0800`, on which the guard's own `(( ))` prints
`value too great for base`, returns false non-fatally, and **accepts**. The order is forced the other
way too: `$(( 10#${x} ))` on an empty or all-space value is silently `0` on bash 3.2 and an error on
5.2, and a `0` stale makes every lock instantly stale. Normalization assigns back to the existing
globals rather than to locals, so `:225`, `:233` and the timeout message all mean the same seconds. A
site running `0600` moves from an effective 384 s to 600 s — toward the documented default, away from
breaking live locks.

Refusing a leading zero outright was prototyped and rejected: it lints clean and its message is
actionable, but it hard-fails cold provisioning over a formatting choice with one plain reading.
Doing both is redundant, because rejection makes `10#` unreachable.

Placement is inside the function that consumes the knobs so that `uvm help` and `uvm --version` still
answer with a broken configuration. That is the whole point of deferring `uvm_init`, transposed one
variable over.

### The timeout has to actually bound

`UVM_LOCK_TIMEOUT` is documented in `uvm_help`, `README.md` and the conf example as how long a call
blocks, and there is a reachable state where it bounds nothing. When a lock is past `UVM_LOCK_STALE`
but cannot be removed — an entry the wrapper did not write, a read-only remount, a full filesystem —
the `continue` at `:229` skips both `waited=$(( waited + 1 ))` at `:232` and `sleep 1` at `:238`.
Measured on the current tree: 825 stderr lines, still spinning 8 s after a 2 s timeout, killed by the
harness.

The repair retries immediately only when the directory is actually gone, and otherwise falls through
to the accounting and the sleep:

```
      [[ -d "${lock}" ]] || continue
      broke=denied
```

A bare `die` on `rmdir` failure would be wrong: two waiters can declare the same lock stale, and the
loser's `rmdir` gets `ENOENT` having done nothing wrong. The discriminator is whether the directory
survived, not whether our own `rmdir` returned zero. `broke` — declared on the existing
`local waited=0 age` line — keeps a denied break from re-announcing itself once per second, which at
the default timeout would be 180 identical lines.

### Why the lock is absent, decided by persistence rather than by a second look

`uvm_acquire_lock` infers *why* `mkdir` failed by re-observing the filesystem: `[[ ! -d "${lock}" ]]`
means permissions, quota or ENOSPC, and it dies. A holder releasing between `mkdir` returning
`EEXIST` and the test evaluating turns a released lock into an unwritable mount, and the waiter dies
one iteration short of winning. Any observation after the fact races the same way, so the inference
cannot be repaired — it has to stop being needed.

Retry, and let persistence rather than a single sample distinguish contention from a broken mount
([`07`](research/07-acquire-race.md)). A
counter declared beside `waited`, incremented only on the absent branch, `continue` while under a
literal bound of 3, and today's `die` unchanged at the bound. Reading the errno instead is the
rejected alternative: `mkdir`'s stderr carries it, at the cost of parsing a locale-dependent string.

Three properties are load-bearing and each is a way to get this wrong. The bound is **not** a
refinement — a bare `continue` spins forever on EACCES, EDQUOT or ENOSPC, the ordinary operational
faults, converting a clean sub-second non-zero exit into a hot loop, which is strictly worse than the
R7 defect. The counter is **monotonic**, never reset on the "lock present" branch: with R7's
`[[ -d ]] || continue` in place, an alternation of absent-retry and successful-break would otherwise
never reach the accounting, and "no agent can produce that alternation" is exactly the weaker
guarantee R7 exists because someone accepted once. A monotonic counter bounds total iterations at
`lock_timeout + 3`, each extra one a single `mkdir` syscall, and needs no argument. And the `die`
**stays**: delete it and a genuinely unwritable mount stalls every rank for the full
`UVM_LOCK_TIMEOUT` and then reports the wrong fault.

R7 and R8 are duals evaluated at different points of one iteration and mutually exclusive within it —
`[[ ! -d ]]` after *our failed `mkdir`*, `[[ -d ]]` after *our own `rmdir`* — so they compose rather
than conflict, and they must give one answer to the same question: when may the loop re-enter `mkdir`
without paying the accounting? R7's answer is "only when the directory is actually gone"; R8 applies
that rule one branch earlier under a constant bound. The finished loop states one invariant: every
iteration either removes something or is charged to the timeout, and the number of uncharged
iterations is bounded by a constant.

### Messages

The timeout message names the owner line and gives a recovery command that works. Today's does not:
`rmdir '<lock>'` fails with `Directory not empty` for every successful acquisition, because `owner`
lives inside the directory it tells the user to remove. The replacement:

```
uv-manager: timed out after 180s waiting for provisioning lock: <lock>
    holder, from the lock's owner file: host=node0042 pid=12345 nonce=…
    A pid recorded there is on that host, not this one. If it is gone, remove the lock:
        rm -f '<lock>/owner' && rmdir '<lock>'
```

With no `owner`, line 2 reads `<none recorded>` and line 3 still parses, which is why it is phrased
conditionally. It prescribes no `squeue` or `ssh` — the wrapper does not know which the site has, and
naming the wrong one is worse than naming none. It stays on `die`; see the deviation table.

The stale-break note gains the same owner line. After R1, "whose lock was that" is the first question
following a break.

### Release before `exec`

Two `uvm_unlock` calls: before `exec "${real_uv}" --version` in `uvm_self_update`, and before the
`case "${mode}"` block carrying the other three sites. A
`uvm_exec_real() { uvm_unlock; exec "$@"; }` helper would be more miss-resistant and is rejected —
neither the call nor the body matches R4's own census pattern, so the contract's verification would
report zero sites.

### User-facing surface

`uvm_help`'s two knob lines gain the ordering constraint (`:878` is already 78 columns against an
81-column heredoc, so this needs a continuation line). `etc/uv-manager.conf.example:71-76` gains the
constraint and the NFS floor. `README.md`'s knob table at `:551-552` gains the constraint, and
§ *Troubleshooting* gains the lock's first entry — the `owner` file is currently documented nowhere a
user will look, and a message that points at it owes one. `share/modulefiles/uv/main.lua` needs no
change; it exports only `UVM_ROOT` and `UVM_PIN`.

`invariants.md` §5 and `AGENTS.md` § *Invariants* are revised in the same commits as the code that
invalidates them: the stale-break bullet (age is now heartbeat-relative), the recovery-command bullet,
and a new assertion that `UVM_LOCK_TIMEOUT` must be less than `UVM_LOCK_STALE`.

### What is removed

`time=` and both command substitutions from the owner write; the `|| true` that made a failed write
silent; the bare `rmdir` advice. The change is otherwise additive — roughly 45 lines into an 850-line
script, against a "prefer deleting to adding" rule. The justification is that four of the six criteria
are defects reproduced in a sandbox in a region `AGENTS.md` lists as high-blast-radius, and three of
them cannot be fixed by deletion.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | `uvm_lock_owner` global; owner line from expansions only; fatal owner write with pre-`uvm_lock` `rmdir`; `uvm_unlock` rewritten to clear-then-compare-then-remove, leaving every non-match in place |
| R2 | `uvm_lock_heartbeat` spawned at acquire and reaped at unlock; `lock_beat = lock_stale / 10` floored at 1; `uvm_age` stats `${lock}/owner` with a directory fallback; waiter liveness probe ahead of the age test |
| R3 | Numeric-form test, base-10 normalization onto the existing globals, then the ordering guard, at the top of `uvm_acquire_lock`; `die` naming both variables and the seconds judged; `uvm_help`, conf example, `README.md` knob table |
| R4 | `uvm_unlock` before `exec "${real_uv}" --version` in `uvm_self_update` and before the `case "${mode}"` block; the empty-`uvm_lock` early-out keeps it fork-free |
| R5 | Timeout message carrying the owner line, the cross-host caveat and `rm -f … && rmdir …`; same owner line on the stale-break note; `README.md` § *Troubleshooting* entry |
| R6 | No `flock`; `mkdir` loop, atomic-rename install path and `current` swap untouched; the warm fast path at `:308` still returns before any lock, so no refresher is spawned |
| R7 | `[[ -d "${lock}" ]] || continue` after the break attempt, so a denied removal falls through to the accounting and the sleep; a `broke` local suppressing the repeated announcement |
| R8 | A monotonic `absent` counter beside `waited`, incremented only when `mkdir` fails with the lock gone; `continue` under a literal bound of 3, today's `die` at it; the bound never resets, so total iterations stay under `lock_timeout + 3` |

## 3. Invariant gate (AGENTS.md constitution check)

Checked against [`invariants.md`](../../.agents/factory/invariants.md) before research and again
against this design.

- **§2 Process semantics** — the four `exec`s remain `exec`s; releasing before them changes nothing the
  real `uv` observes. The `tool`/`python` non-exec path still runs to completion, captures `rc`,
  resyncs and exits `rc`; its release continues to come from the EXIT trap, verified by drive.
- **§3 State root resolution** — the R3 guard sits inside `uvm_acquire_lock`, so `help` and `--version`
  still answer on an unconfigured or misconfigured node. Load-time placement was rejected for exactly
  this reason.
- **§4 Version selection & pinning** — the early-out predicate is untouched and still tests the version
  this call was asked for. The waiter's liveness probe is consulted only on the break decision, never
  on the early-out, so a pinned caller cannot be handed another process's install.
- **§5 Provisioning lock** — `mkdir` stays, and no helper binary is introduced. Release still happens on
  EXIT, INT and TERM, now qualified by ownership. Two bullets are revised in the same commit as the code
  that invalidates them: the stale-break bullet, because age is now measured from the heartbeat, and the
  recovery-command bullet, because the command it promises has never worked. A third is added for the
  knob ordering. R7 needs no new text: §5 already asserts the wrapper times out after
  `UVM_LOCK_TIMEOUT`, and R7 is what makes that assertion true when a break is denied.
  **R8 overturns one.** §5's contention bullet states the false premise as doctrine — "if the lock
  directory is absent after a failed `mkdir`, the failure is permissions/quota/ENOSPC and waiting
  will never help — die with that message." Anvil disproves it. The bullet's imperative survives;
  only its evidence changes, from one observation to persistence across bounded attempts. This is the
  only place the premise is written down: `AGENTS.md` never states it and `README.md` never mentions
  it. Because it is an overturn rather than an addition, `AGENTS.md`'s same-commit rule puts it in
  P7's diff *and* in front of a human, "never in the diff alone" — which is what the amendment this
  section belongs to is for.
- **§7 Output discipline** — installer output still goes to stderr, stdout still carries only the user's
  answer, verified by the degenerate-owner drives returning `uv 9.9.9 (fixture)` alone. The heartbeat's
  `>/dev/null 2>&1` forecloses a child holding the caller's pipe open. The `die`-versus-heredoc question
  is a recorded deviation.
- **§10 Portability floor** — no namerefs, no `$BASHPID`, no `read -t` timeout convention: all three are
  bash 4+, and the design uses `$$`, plain `read`, and `kill -0`, which are 3.2. The warm hot path is
  unchanged and spawns no refresher.
- **§12 Project conventions** — the same-commit surface is enumerated above; no spec ids appear in the
  script or README; version is untouched.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| R3's guard also refuses **non-numeric** knob values and **normalizes to base 10**, neither of which R3 originally asked for | A bare ordering comparison inherits the bash 3.2 fatality where `UVM_LOCK_STALE=abc` aborts at `:225` and the script still **exits 0**. The form test is also what makes `10#` safe: `$(( 10# ))` on an empty or all-space value is `0` on bash 3.2 and an error on 5.2. Without both, the guard does not deliver R3's stated behavior — it refuses legal pairs and accepts `0800` | Comparing only the ordering: silently keeps a worse failure than the one R3 removes. A `case` on `"${t}:${s}"` was prototyped and is wrong — `18:0` slips through and dies with an arithmetic syntax error. Normalizing without a form test first: `0800` passes `^[0-9]+$`, so the check must precede arithmetic that cannot evaluate it. Rejecting leading zeros instead of normalizing: hard-fails cold provisioning over a formatting choice with one plain reading |
| A **background process** exists during provisioning, on a script whose §10 budget guards forks | The hold is one blocking pipeline; nothing else can refresh an mtime during it, and R2 requires the lock to survive it | Refresh at progress points is structurally dead — two sub-millisecond statements, both after the fetch. Inverting the pipeline works mechanically but welds the heartbeat to `uvm_install`, and `purge-tree-repair` holds the lock across a rebuild that is not that pipeline |
| `uvm_age` grows a **fallback** (`owner` then the directory) rather than one path | A directory's mtime does not move when a file inside it is rewritten, so the heartbeat is only visible on the file; the directory branch is what keeps locks with no `owner` aging as they do today | Stat only `owner`: an older wrapper's lock, or one caught in the 0.10 ms acquire window, would never age out. Stat only the directory: the heartbeat is invisible and R2 fails |
| The owner write becomes **fatal**, adding a failure path | Under R1 a holder that cannot prove ownership leaks its own lock for a full stale window; the failure is silent today | Keeping `|| true`: trades a rare loud failure for a rare silent leak in a region where a leak blocks the user until manual repair |
| R8 **overturns** `invariants.md` §5's contention bullet rather than adding to it, and is admitted to a locked GOAL at 4/6 done | The bullet asserts an inference Anvil measured false at 3.1% of ranks; leaving it means correct code is graded against a premise the hardware disproves. Deferring the code does not protect the cycle either — `review-rubric.md`'s deferral exception needs a `GOAL.md` criterion that repair would fail, and none exists, so a blind reviewer who reproduces it blocks | Deferring to a seed: buys a `changes-requested` loop and a second human sign-off gate on `uvm_acquire_lock` for nothing, and leaves `purge-tree-repair` R7's "wait and then re-test" unsatisfiable against a loop whose waiters die at 2–4%. Reading the errno instead of retrying: locale-dependent string parsing. A bare `continue` without a bound: spins forever on EACCES/EDQUOT/ENOSPC, strictly worse than the R7 defect it sits beside |
| The timeout message stays on `die`'s single `printf` rather than a **`cat` heredoc**, against §7's letter | Measured: one `printf` behind a departed reader emits one diagnostic line, the same count BSD `cat` produces, and only when the caller ignores SIGPIPE. §7's hazard is N writes, which is why `uvm_status` and `uvm_doctor` needed `cat` | A heredoc costs a fork and an exec, breaks `die`'s single spelling of the prefix plus `exit 1`, and buys zero lines of noise on a message that is the process's last output |

## 4. Rabbit holes (resolved)

- **Where a heartbeat can even run, when the whole hold is one blocking pipeline** → a background
  refresher owned by the lock, leashed by `kill -0 "$$"`, reaped with `kill` *then* `wait`
  ([`02`](research/02-heartbeat-placement.md)).
- **Whether an mtime refresh is visible at all** → not on the directory; `uvm_age` must stat
  `${lock}/owner`. POSIX, and measured on APFS ([`02`](research/02-heartbeat-placement.md),
  [`06`](research/06-verification-recipes.md)).
- **Whether `host`+`pid` is a sufficient identity** → no; 694 pids/s measured, `pid_max` wraps in 47 s
  against a 600 s window. A `$RANDOM` nonce closes it for no fork
  ([`01`](research/01-ownership-identity.md)).
- **Whether reading the owner file is affordable on the EXIT-trap path** → `read` builtin at 34 µs
  versus `$(cat)` at 1686 µs, a third of the 5 ms budget ([`01`](research/01-ownership-identity.md)).
- **Whether an orphaned refresher can outlive its holder** → yes, measured beating past a SIGKILL;
  `kill -0 "$$"` freezes it. A pipe leash is unavailable at the 3.2 floor, where `read -t` cannot
  distinguish timeout from EOF ([`02`](research/02-heartbeat-placement.md)).
- **Whether the knob guard can live at load time** → no; it would break `help` and `--version`, the two
  commands that document the knobs ([`03`](research/03-knob-ordering-guard.md),
  [`06`](research/06-verification-recipes.md)).
- **Whether bash 3.2 reports the arithmetic failure at all** → it does not; the EXIT trap's status
  overrides it and the script exits 0 ([`03`](research/03-knob-ordering-guard.md)).
- **Whether the message should move to a heredoc** → no, by measurement rather than by §7's letter
  ([`05`](research/05-timeout-message.md)).
- **How a drive holds a lock long enough to test staleness** → append a sleep to the fixture copy inside
  the sandbox; the fixture is copied per invocation, so nothing tracked is touched
  ([`06`](research/06-verification-recipes.md)).
- **Whether the "why did `mkdir` fail" inference can be made correct** → no. Any observation after the
  fact races the same way; the lock's absence at *t+1* says nothing about why `mkdir` failed at *t*.
  Reading the errno works and costs a locale-dependent string parse; retrying under a bound costs
  neither ([`07`](research/07-acquire-race.md)).

## 5. Risks & open questions

- **Cross-node behavior is unverified, entirely.** One host cannot produce a waiter unable to probe a
  holder's pid, so the branch the heartbeat exists to serve is exercised here only by forcing it. This
  is the cycle's largest residual risk and the GOAL declares it up front.
- **The NFS attribute-cache margin is reasoned, not measured.** Worst observed age is one beat plus
  `acregmax`: 60 + 60 s against the 600 s default, a 5× margin. It implies a floor worth documenting —
  `UVM_LOCK_STALE` below roughly 120 s is unsafe for cross-node waiters on NFS, and was so before this
  change. Lustre and GPFS coherence is reasoned from their lock managers.
- **`mkdir` atomicity on Lustre, GPFS and NFS remains taken on trust**, as R6 pins rather than revisits.
- **A signal inside the 0.10 ms acquire window still leaks a lock.** `mkdir` has returned and `uvm_lock`
  is not yet set, so the trap cannot see it. The window is 30× narrower than today's and the stale
  breaker reclaims it; closing it entirely needs the trap to read a variable set before the `mkdir`,
  which would make the trap capable of deleting a lock this process failed to take.
- **Sleep-based gate timings were reliable here but have not run on a loaded shared machine.** A
  `verify:` retried under load may need wider margins.
- **R8's gate is statistical, and its floor is assumed rather than measured.** Twenty bursts is sized
  against a pessimistic 0.5% per-rank rate; the observed rate is 2.6–3.9% on two machine classes. A
  machine slow enough to push the true rate below that floor would weaken the gate the way Anvil's
  login node did — that is the failure mode to watch, not a flaky red
  ([`07`](research/07-acquire-race.md)).
- **`uvm_age` read `0600` as octal 384 s** at `:225`. Folded into R3's guard rather than seeded: the
  guard forces base 10 on the same globals `:225` and `:233` read, so all three sites and the timeout
  message mean the seconds the operator wrote. No `issues/` seed is owed.
- **Three `invariants.md` bullets were measured false of the code** during an audit prompted by §5's
  broken recovery command — §6 over-generalizes one guard's message to "any failure", §9 drops the
  qualifiers on the trampoline overwrite guard, and §11 asserts something about `uv`'s CLI that
  `uv --cache-dir … tool dir` disproves. Two are duplicated verbatim in `AGENTS.md`. The text repairs
  are `META.md` F4–F7 for `/uvm-harness` after merge; the two small code gaps behind them are seeded in
  [`issues/invariant-audit-gaps.md`](../../issues/invariant-audit-gaps.md). Deliberately outside this
  cycle's diff: they are unrelated to the lock, and editing the checklist inside the graded diff reads
  as revising the standard being graded against.

## 6. Verification strategy

Three layers, per `methodology.md`: `bash -n bin/uv-manager`, `.agents/factory/bin/lint.sh` (which adds
shellcheck and symlink integrity), and a drive under `.agents/factory/bin/temp_root.sh --offline`.

`temp_root.sh` runs `"$@"` directly and does not redirect stdin, so gates use `sh -s` with a quoted
heredoc rather than the `sh -c` escaping earlier cycles used. One sandbox per invocation means a holder
and a waiter must both start inside a single drive, and assertions must live there too. The fixture is
copied into the sandbox, so a `UVM_FIXTURE_SLOW` sleep appended to `$UVM_FIXTURE_DIR/install.sh`
stretches the hold without touching anything tracked.

Post-conditions asserted, per requirement:

- **R1** — a foreign `owner` written from inside the installer survives the holder's release, and so
  does the lock directory; and an ordinary drive still leaves no lock behind.
- **R2** — with a hold longer than `UVM_LOCK_STALE`, the waiter's stderr contains no
  `breaking stale provisioning lock` and the `owner` file still names the original holder's pid. The
  waiter exits non-zero on an ordinary timeout after the fix, so the gate must not assert `rc=0`.
- **R3** — inverted knobs exit non-zero, print both variable names and the seconds judged, and leave a
  pre-existing live lock present; `TIMEOUT=0600 STALE=500` refused and `TIMEOUT=500 STALE=0600`
  accepted; `STALE=0800` reaching no arithmetic; `uvm help` and `uvm --version` still answering.
- **R4** — xtrace ordering shows `uvm_unlock` between `uvm_export_env` and `exec`, on both the dispatch
  tail and the `uv self update` path; plus the four-line census.
- **R5** — a drive to timeout whose stderr matches `owner`, `host` and `pid` as whole words.
- **R6** — `uv --version` still prints `uv 9.9.9 (fixture)` and `current` still points at
  `versions/9.9.9`; no `flock` outside a comment.
- **R7** — against a lock directory holding an entry the wrapper did not write, aged past
  `UVM_LOCK_STALE`, the call exits within `UVM_LOCK_TIMEOUT` and its stderr carries the timeout
  message rather than a repeated break announcement.
- **R8** — twenty cold bursts of 64 concurrent ranks against one shared root leave no rank carrying
  `check permissions and quota` and no rank exiting non-zero; and an unwritable architecture
  directory still produces that message, non-zero, in under five seconds. The burst count is
  arithmetic rather than taste: at a pessimistic 0.5% per-rank floor a single burst is red with
  probability `1 - 0.995^64 = 0.27`, so twenty bursts leave a false green at `0.73^20 ≈ 1.6e-3`; at
  the measured 3.9% it is far below that. One burst costs 1 s here, so the gate costs about 25 s. Do
  not economize below twenty — a shorter gate green on a slow machine is exactly how Anvil's login
  node reported 64 of 64.

All six change gates are red against `653b770`; R6 is green and must stay green. Two clauses are
**inspection-only** and are called out in `TECH.md` for the reviewer rather than trusted to a gate:
R4's fork-free-release cost claim, which the GOAL already assigns to a human, and "every `exec` site
covered", which is a reading of the census rather than something a proximity grep can decide.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
