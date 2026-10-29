# 01 — The wait loop and its caller contract

Research brief for `uvm-plan`, 2026-10-27, against `cf77b37`. Every idiom below was run under
`/bin/bash` 3.2.57, the only bash on the measuring Mac. Bash 5 was **not** available, so every
5.x statement is from the bash changelog, not measured. The draft was spliced into a throwaway copy
of the tree. That copy passes the R1, R2, R3, R7 (stale knob) and R11 drives and
`tests/lock-race.sh --plant control --ranks 32 --bursts 2` (R14: 2 installs for 2 bursts, 0 non-zero,
0 locks left, `progress=ok`).

## Recommendation: the hypothesis holds, with four amendments

`uvm_acquire_lock ON_TIMEOUT PREDICATE [ARG...]`, predicate run as `"$@"` after one `shift`. Return 0
means go and do the work, holding the lock only if `uvm_lock` is non-empty. Return 1 means the
predicate came true while waiting, and nothing is held.

1. **R11 is simpler than the hypothesis.** Set `uvm_lock="${lock}"` the instant `mkdir` wins, *before*
   the owner write, then `printf … > "${lock}/owner" || die "cannot record ownership …"`. Release is
   now by path, so the EXIT trap's `uvm_unlock` removes the entry the failed write left, then the
   directory. No second cleanup path is needed. With the shim from `issues/lock-owner-write-errno.md`
   this gives rc 1, the shell's `…/owner: No such file or directory` line, the `cannot record
   ownership` line, and `LOCK=released`. The die's explicit `exit 1` survives the trap. Bonus: the
   window between `mkdir` and `uvm_lock=` in which a signal leaks the lock shrinks to one assignment.
2. **Guard against a missing predicate with an explicit `die`.** An empty `"$@"` is a *successful*
   no-op (measured: `set --; "$@"` gives rc 0). So `uvm_acquire_lock proceed`, with no predicate,
   early-outs on every contended call, and the bug appears only under contention. Do not use
   `${1:?}` as the guard. Under an EXIT trap, bash 3.2 exits **0** on that expansion error
   (measured: rc 0 with the message on stderr), the same trap-status override the knob guard
   already documents. A form that works: `(( $# >= 2 )) || die "…"` (measured: rc 1).
3. **Reset `holder` before each read.** A failed open never runs `read`, so the variable keeps
   its previous value.
4. **Caller contract on return 1.** Return 1 says the predicate is true. It does not say the
   version is selected. A provisioning caller must still do what its fast path does, which is
   `uvm_point_current` for a pin (R12/R13). The plain `|| return 0` reproduces the pin defect.

`force` leaves the lock: a forced install passes `false`. Two shapes were measured clean on 3.2.
One is `set -- false` / `set -- uvm_have "${want}"`, then `uvm_acquire_lock proceed "$@"`. The other
is a never-empty local array, `local pred=(uvm_have "${want}"); [[ -z "${force}" ]] || pred=(false)`,
which carries the empty arg through as `<uvm_have><>`. An **empty** array is fatal under `set -u` on
3.2 (`ep[@]: unbound variable`), so never let the array go empty.

## Q1: predicates under `set -euo pipefail`

The `"$@"` form ran correctly with `uvm_have ""` (false, then true once `real_uv` existed),
`uvm_have 9.9.9`, `false` and `true`. `shift` followed by `"$@"` does not trip `set -u` when no
arguments are left. **Errexit is suspended inside anything called from `if`, `&&` or `||`, and in
every function that call reaches.** `f() { false; echo inside; }; if f; …` prints `inside` and
returns true. The rule for predicate authors: the function's status must be the deciding test's
status. Chain steps with `|| return 1`, and never rely on `set -e` to stop at a failed step. Keep
the predicate side-effect-free and cheap, because it runs once a second for up to
`UVM_LOCK_TIMEOUT`. It must never touch `uvm_lock`.

## Q2: draft (spliced into the copy, all drives above green)

```bash
uvm_lock=""
uvm_unlock() {
  [[ -n "${uvm_lock}" ]] || return 0
  local lock="${uvm_lock}"
  uvm_lock=""
  rm -f "${lock}/owner" 2>/dev/null || true
  rmdir "${lock}" 2>/dev/null || true
}
trap 'uvm_unlock' EXIT
trap 'uvm_unlock; exit 130' INT
trap 'uvm_unlock; exit 143' TERM

uvm_acquire_lock() {
  local on_timeout="$1"; shift
  local lock="${uvm_root}/.install.lock" waited=0 absent=0 notice=30 holder=""
  local owner="host=$(uname -n) pid=$$"
  [[ "${lock_timeout}" =~ ^[0-9]+$ ]] \
    || die "UVM_LOCK_TIMEOUT must be a whole number of seconds: UVM_LOCK_TIMEOUT=${lock_timeout}"
  lock_timeout=$(( 10#${lock_timeout} ))
  (( notice <= lock_timeout )) || notice="${lock_timeout}"
  (umask 077; mkdir -p "${uvm_root}") \
    || die "cannot create ${uvm_root} — is ${uvm_base} writable?"
  while ! mkdir "${lock}" 2>/dev/null; do
    if [[ ! -d "${lock}" ]]; then
      absent=$(( absent + 1 ))
      (( absent >= 3 )) || continue
      die "cannot create provisioning lock at ${lock} — check permissions and quota on ${uvm_base}"
    fi
    if "$@"; then return 1; fi
    if (( waited == notice || waited >= lock_timeout )); then
      holder=""; read -r holder 2>/dev/null < "${lock}/owner" || true
    fi
    (( waited != notice )) || note "waiting for the provisioning lock at ${lock}
    held by: ${holder:-<none recorded>}
    If no process holds it, clear it with: rm -f '${lock}/owner' && rmdir '${lock}'"
    if (( waited >= lock_timeout )); then
      [[ "${on_timeout}" != proceed ]] || return 0
      die "timed out after ${lock_timeout}s waiting for the provisioning lock at ${lock}
    held by: ${holder:-<none recorded>}"
    fi
    waited=$(( waited + 1 ))
    sleep 1
  done
  uvm_lock="${lock}"
  printf '%s\n' "${owner}" > "${lock}/owner" \
    || die "cannot record ownership of the provisioning lock at ${lock}/owner"
}
```

Add the `(( $# >= 2 ))` guard from amendment 2, which costs one line. `notice = min(30, timeout)`
means every wait that reaches the timeout speaks exactly once first. With R3's `UVM_LOCK_TIMEOUT=3`
the waiter prints one notice naming the holder and then proceeds. In `fail` mode with a timeout of
30 or less, both the notice and the die name the holder. The plan may skip the notice when
`waited >= lock_timeout`. The literal "provisioning" in the messages is wrong for a repair caller,
and the plan should word them neutrally.

**Line counts.** The section is 335 lines on `main` (169–503), 138 of them neither comment nor
blank. In the copy, with comments of today's density, it is 90 lines, 46 of them code. The acquire
function drops from 217 lines to 48, the wait loop from 141 to 24, and the file from 1224 to 979.

**Threshold: 30 s, a literal.** A real uv release tarball (14–17 MB) downloaded in 0.32–0.39 s here.
A normal cold provision therefore sits far below both 10 s and 30 s, so the threshold only separates
"slow" from "wedged". Once it is crossed, every waiter prints exactly once: 127 notices of 3 lines on
a 128-rank job, whichever threshold is chosen. A 10 s threshold crosses on slow egress or slow
extraction onto a parallel filesystem, which are normal events. That puts 381 lines in a job log
and invites a user to clear a live lock, which is the Clarification's residual. 30 s is one-sixth of
the default timeout. Its costs are that the R2 drive needs `UVM_LOCK_TIMEOUT=60` with a release at
33 s (measured: 34 s wall, `lines_naming_holder=1`, rc 0), and that an interactive user sits through
30 s of silence. 10 s is defensible if interactive feedback outweighs log noise.

## Q3: the R5/R6 drive without a repair implementation

The approach is sound **today**. `sed -n '/^# ---- provisioning lock/,/^# ---- fetching/p'` writes
the section to a temp file, and plain `.` sources it. **Do not source a process substitution:**
`source <(printf 'x=sourced\n')` on 3.2 leaves `x` unset, silently. The harness provides `note`,
`die`, `uvm_base`, `uvm_root` and `lock_timeout`, plus `lock_stale` and `uvm_have` on `main`. It
plants a lock with a live `sleep` holder, then calls the lock with a critical section that touches a
marker.

- Against `main`, as `uvm_acquire_lock "" 1`. The force flag stands in for "skip the provisioning
  predicate". A live plant gives rc 1 at the timeout with the owner line, and no marker. A dead-pid
  plant gives a `breaking … abandoned by a dead process` line, the marker, and the plant gone (R1's
  red). `pred-flip` times out, because `main` has no caller predicate (R6 is not constructible there).
- Against the draft, as `uvm_acquire_lock fail repair_done`, with the `uvm_have` stub always true.
  A live plant gives the notice, the die naming the plant, rc 1 at 3.11 s, and no marker. The
  waiter did not early-out on the true provisioning test (R6). A dead-pid plant gives the same, with
  the plant intact. A release mid-wait gives rc 0 and the marker. A predicate flipped mid-wait gives
  rc 1, no marker, and the plant intact.

**What the drive depends on:** the two banners, `lock_timeout` staying outside the section, the
section calling nothing at acquire time beyond `note`, `die` and external commands, and the call
shape `uvm_acquire_lock fail PRED [ARG...]` with 0/1 returns, `uvm_lock` and `uvm_unlock`. A die
exits the harness, so the drive must check for the marker *after* the process exits. To release a
plant, move it aside (`mv`), as the shaping drives do.

## Q4: traps after a provisioning timeout

After a proceed return, `uvm_lock` is empty. Every `uvm_unlock`, the install paths, the
guards in front of `exec` and all three traps then reduce to one builtin test. R3 is the proof that
matters: under release by path, a wrongly set `uvm_lock` would delete the foreign plant, and the
plant **survived**. A waiter killed with TERM exits 143 and leaves the plant byte-identical. A
holder killed with TERM exits 143 and its own lock is gone. INT could not be exercised, because
bash ignores SIGINT in an asynchronously launched non-interactive child, so a signal drive must use
TERM. In the copy, `git grep` for `uvm_lock_owner`, `uvm_lock_beat_pid`, `lock_stale`, `uvm_age`,
`uvm_proc_start`, `uvm_lock_heartbeat` and `kill -0` matches only the `uvm help` text line for
`UVM_LOCK_STALE`, which is R9's surface.

## Q5: the Clarification residual

Nothing in the draft makes the residual worse in kind. It is wider than stated, though, and this
part is derived, not measured. One human clear of a live lock shifts ownership by one **for the
rest of that contention episode**, not for one rank. A clears and B acquires. A's release removes
B's lock, then C acquires. B's release removes C's. The chain runs until a release finds no
successor. For provisioning it dies quickly, because waiters' predicates turn true after the first
publish. For a repair caller, every repairer in the chain overlaps its predecessor.

The draft's R11 path belongs to the same class. If a human clears the lock between this rank's
`mkdir` and its owner write, and another rank wins `mkdir` before the write, the write succeeds into
the rival's directory, and both ranks hold. That needs a human acting in a sub-millisecond window.
The ownership-qualified release would have broken the chain, and R7 removes it by decision. R8's
wording must therefore say plainly that the holder may be alive.

**The next cycle inherits an open question, not decided here:** whether repair (`purge-tree-repair`)
takes this same `.install.lock` or a lock of its own.
- **Shared lock:** repair and provisioning serialize against each other. A provisioning waiter
  past its timeout proceeds during a repair. A provisioning predicate can come true mid-repair and
  exec a tree being mutated. A repair waiter fails behind a slow provision.
- **Own lock:** `uvm_acquire_lock` gains a path or name argument. `uvm doctor` and `uvm clean` (R8)
  must cover two locks. The message wording must name which lock.

This cycle can keep the path internal, with neutral wording, and leave either answer open.

## Q6: bash 3.2 vs 5 hazards

| Idiom | 3.2 (measured) | 5.x (changelog) | In the draft |
|---|---|---|---|
| bare false `(( … ))` or `[[ … ]]` statement | continues | exits under `set -e` (since 4.1) | none bare; every test sits in `if` or `\|\|` |
| `let "n=0"`, or a function returning 1 from `(( 0 ))` | exits | exits | not used |
| function whose last statement is a false `&&` list | returns 1, so the caller exits | same | none: tests are written `… \|\| action` |
| `local v="$(false)"` | rc 0 (masked) | same | only `owner`, where a failed `uname` merely blanks the host |
| `local v; v="$(false)"` | exits | same | — |
| `"${empty[@]}"` under `set -u` | fatal | allowed (since 4.4) | no arrays in the lock |
| `${1:?}` under an EXIT trap | exits **0** | — | use an explicit `die` |
| `10#0800`, `10#000` | 800, 0 | same | kept, after the form test |
| form test `^[0-9]+$` | rejects `' '`, `-1`, `1e3`, empty; accepts `0`, `0800` | same | kept |

The floor is the *permissive* side of the first row. Code that passes on the Mac can die on a
cluster's bash 5, so the row has to be checked by reading the code, not by running it.
