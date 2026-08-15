---
slug: lock-ownership-and-hold-time
title: "The provisioning lock can be released by a process that does not hold it"
kind: fix
appetite: big
status: planned
branch: fix/lock-ownership-and-hold-time
base: main
current_phase: P1
last_updated: "2026-08-15"
phases:
  - id: P1
    name: "Give the lock an identity, and release only what matches it"
    status: pending
    satisfies: [R1]
    depends_on: []
    parallel: false
    hammerable: false
    hill: uphill
    verify: |
      set -eu
      bash -n bin/uv-manager
      .agents/factory/bin/lint.sh >/dev/null
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; export UVM_TEST_LOCK="$L"
      printf '%s\n' 'printf "host=elsewhere pid=999999 nonce=0\n" > "$UVM_TEST_LOCK/owner"' >> "$UVM_FIXTURE_DIR/install.sh"
      uv --version >/dev/null
      if [ ! -d "$L" ]; then echo "FAIL: release removed a lock this process does not own" >&2; exit 1; fi
      if [ ! -f "$L/owner" ]; then echo "FAIL: foreign owner file removed" >&2; exit 1; fi
      if ! grep -q 'pid=999999' "$L/owner"; then echo "FAIL: foreign owner overwritten" >&2; exit 1; fi
      DRIVE
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      uv --version >/dev/null
      L="$UVM_ROOT/$(uname -m)/.install.lock"
      if [ -d "$L" ]; then echo "FAIL: own lock not released" >&2; exit 1; fi
      DRIVE
  - id: P2
    name: "Release before every exec of the real uv"
    status: pending
    satisfies: [R4]
    depends_on: [P1]
    parallel: false
    hammerable: false
    hill: uphill
    verify: |
      set -eu
      bash -n bin/uv-manager
      n=$(git grep -n 'exec "\${real_' bin/uv-manager | wc -l | tr -d ' ')
      if [ "$n" != 4 ]; then echo "FAIL: exec census is $n, expected 4" >&2; exit 1; fi
      .agents/factory/bin/lint.sh >/dev/null
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      uv --version >/dev/null 2>&1
      for probe in "--version" "self update"; do
        PS4='+ ' bash -x "$(command -v uv)" $probe >/dev/null 2>"$UVM_SANDBOX/t" || true
        u=$(grep -n '^++* uvm_unlock$' "$UVM_SANDBOX/t" | tail -1 | cut -d: -f1 || true)
        p=$(grep -n '^++* export PATH$' "$UVM_SANDBOX/t" | tail -1 | cut -d: -f1 || true)
        e=$(grep -n '^++* exec ' "$UVM_SANDBOX/t" | tail -1 | cut -d: -f1 || true)
        if [ -z "$u" ] || [ -z "$e" ] || [ "$u" -lt "$p" ] || [ "$u" -gt "$e" ]; then
          echo "FAIL: no release between uvm_export_env and exec on 'uv $probe' (unlock=$u path=$p exec=$e)" >&2
          exit 1
        fi
      done
      DRIVE
  - id: P3
    name: "Keep a live holder's lock alive for as long as the holder is"
    status: pending
    satisfies: [R2]
    depends_on: [P2]
    parallel: false
    hammerable: false
    hill: uphill
    verify: |
      set -eu
      bash -n bin/uv-manager
      .agents/factory/bin/lint.sh >/dev/null
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"
      printf '%s\n' 'if [ -n "${UVM_FIXTURE_SLOW:-}" ]; then sleep "$UVM_FIXTURE_SLOW"; fi' >> "$UVM_FIXTURE_DIR/install.sh"
      ( UVM_FIXTURE_SLOW=8 uv --version >/dev/null 2>"$UVM_SANDBOX/holder.err" ) & holder=$!
      sleep 1
      first=$(sed -n 's/.*\(pid=[0-9][0-9]*\).*/\1/p' "$L/owner" 2>/dev/null || true)
      sleep 4
      set +e
      UVM_LOCK_STALE=3 UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>"$UVM_SANDBOX/waiter.err"
      set -e
      now=$(sed -n 's/.*\(pid=[0-9][0-9]*\).*/\1/p' "$L/owner" 2>/dev/null || true)
      if grep -q 'breaking stale provisioning lock' "$UVM_SANDBOX/waiter.err"; then
        echo "FAIL: a live holder's lock was broken as stale" >&2; exit 1
      fi
      if [ -z "$first" ] || [ "$first" != "$now" ]; then
        echo "FAIL: lock was $first, now ${now:-gone}" >&2; exit 1
      fi
      wait "$holder"
      DRIVE
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"
      printf '%s\n' 'if [ -n "${UVM_FIXTURE_SLOW:-}" ]; then sleep "$UVM_FIXTURE_SLOW"; fi' >> "$UVM_FIXTURE_DIR/install.sh"
      ( UVM_LOCK_STALE=10 UVM_FIXTURE_SLOW=20 uv --version >/dev/null 2>&1 ) & holder=$!
      sleep 2
      p=$(sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' "$L/owner" 2>/dev/null || true)
      if [ -z "$p" ]; then echo "FAIL: no holder pid recorded" >&2; exit 1; fi
      kill -9 "$p" 2>/dev/null || true
      sleep 1; m1=$(stat -f %m "$L/owner" 2>/dev/null || stat -c %Y "$L/owner" 2>/dev/null || true)
      sleep 3; m2=$(stat -f %m "$L/owner" 2>/dev/null || stat -c %Y "$L/owner" 2>/dev/null || true)
      wait "$holder" 2>/dev/null || true
      if [ "$m1" != "$m2" ]; then
        echo "FAIL: something refreshed the lock after its holder was killed ($m1 -> $m2)" >&2; exit 1
      fi
      DRIVE
  - id: P4
    name: "Refuse a knob configuration that lets a waiter break a live lock"
    status: pending
    satisfies: [R3]
    depends_on: [P3]
    parallel: false
    hammerable: false
    hill: uphill
    verify: |
      set -eu
      bash -n bin/uv-manager
      .agents/factory/bin/lint.sh >/dev/null
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$A"; mkdir "$L"
      printf 'host=%s pid=%s nonce=0\n' "$(uname -n)" "$$" > "$L/owner"
      sleep 3
      set +e
      UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uv --version >/dev/null 2>"$UVM_SANDBOX/err"; rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then echo "FAIL: inverted knobs accepted (rc=0)" >&2; exit 1; fi
      if ! grep -q UVM_LOCK_TIMEOUT "$UVM_SANDBOX/err" || ! grep -q UVM_LOCK_STALE "$UVM_SANDBOX/err"; then
        echo "FAIL: refusal does not name both variables" >&2; exit 1
      fi
      if [ ! -d "$L" ]; then echo "FAIL: the live lock was destroyed" >&2; exit 1; fi
      set +e
      UVM_LOCK_STALE=abc uv --version >/dev/null 2>&1; rcn=$?
      set -e
      if [ "$rcn" -eq 0 ]; then echo "FAIL: non-numeric UVM_LOCK_STALE accepted (rc=0)" >&2; exit 1; fi
      UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uvm --version >/dev/null
      UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uvm help >/dev/null
      DRIVE
      if ! grep -q 'UVM_LOCK_TIMEOUT' etc/uv-manager.conf.example; then echo "FAIL: conf example silent" >&2; exit 1; fi
      for f in README.md etc/uv-manager.conf.example bin/uv-manager; do
        if ! grep -q 'less than' "$f"; then echo "FAIL: $f does not state the ordering constraint" >&2; exit 1; fi
      done
  - id: P5
    name: "Tell a stalled user how to tell an abandoned lock from a live one"
    status: pending
    satisfies: [R5, R6]
    depends_on: [P4]
    parallel: false
    hammerable: false
    hill: uphill
    verify: |
      set -eu
      bash -n bin/uv-manager
      .agents/factory/bin/lint.sh >/dev/null
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$A"; mkdir "$L"
      printf 'host=node0042 pid=12345 nonce=0\n' > "$L/owner"
      set +e
      UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=600 uv --version >/dev/null 2>"$UVM_SANDBOX/err"; rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then echo "FAIL: waiter did not time out" >&2; exit 1; fi
      for tok in owner host pid; do
        if ! grep -qw "$tok" "$UVM_SANDBOX/err"; then
          echo "FAIL: timeout message never mentions '$tok'" >&2; exit 1
        fi
      done
      if ! grep -q "rm -f .*owner.* && rmdir" "$UVM_SANDBOX/err"; then
        echo "FAIL: recovery command still advises a bare rmdir that cannot succeed" >&2; exit 1
      fi
      DRIVE
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$A"; mkdir "$L"
      printf 'host=node0042 pid=12345 nonce=0\n' > "$L/owner"
      sleep 2
      UVM_LOCK_STALE=1 UVM_LOCK_TIMEOUT=10 uv --version >/dev/null 2>"$UVM_SANDBOX/brk"
      if ! grep -q 'breaking' "$UVM_SANDBOX/brk"; then echo "FAIL: no break occurred" >&2; exit 1; fi
      if ! grep -q 'pid=12345' "$UVM_SANDBOX/brk"; then
        echo "FAIL: stale-break note does not name the owner it deleted" >&2; exit 1
      fi
      DRIVE
      if ! grep -q 'install\.lock' README.md; then
        echo "FAIL: README documents no lock troubleshooting entry" >&2; exit 1
      fi
      .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
      set -e
      out=$(uv --version)
      if [ "$out" != "uv 9.9.9 (fixture)" ]; then echo "FAIL: stdout was '$out'" >&2; exit 1; fi
      A="$UVM_ROOT/$(uname -m)"
      if [ "$(readlink "$A/current")" != versions/9.9.9 ]; then echo "FAIL: current target moved" >&2; exit 1; fi
      DRIVE
      if git grep -n flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#'; then
        echo "FAIL: flock invoked outside a comment" >&2; exit 1
      fi
review:
  last_reviewed_commit: ""
  verdict: none
  blocked_reason: ""
  cycle: 0
---

# TECH.md — The provisioning lock can be released by a process that does not hold it

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/lock-ownership-and-hold-time/TECH.md`); the per-phase
checklists below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus six briefs.

## Ordering, and why it is not negotiable

**P2 (R4) lands before P3 (R2).** `exec` preserves the pid, so the heartbeat's `kill -0 "$$"` leash
still passes after the wrapper has been replaced by the real `uv`. Shipping the heartbeat first would
turn today's bounded 600-second leak into a lock nothing can ever break. This is the digest's headline
finding and the reason the GOAL was amended to cover all four `exec` sites.

Every phase is `hammerable: false`: all five touch `invariants.md` §5 or §2, both in the
high-blast-radius list. Every phase is `parallel: false`; there is one source file.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and invariants come from [`AGENTS.md`](../../AGENTS.md);
  [`invariants.md`](../../.agents/factory/invariants.md) is the footgun checklist.
- One phase per `uvm-build` invocation; one atomic commit with both the code and the `TECH.md` state
  change. Subjects: `[fix] Build lock-ownership-and-hold-time P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids in `bin/uv-manager` or `README.md`.
- Gates run under bash 3.2.57 here, which is the portability floor, not an approximation of it.

---

## Phase P1 — Give the lock an identity, and release only what matches it
**Satisfies:** R1 · **Depends on:** —
**Goal:** a release removes the lock only when the `owner` file still names this process; every other
outcome leaves the directory standing.

- [ ] Build the owner line before the `while ! mkdir` loop, from expansions only:
      `host=${HOSTNAME} pid=$$ nonce=${RANDOM}${RANDOM}${RANDOM}`. Remove `time=` and both command
      substitutions — they are what widen the `mkdir`-to-owner-write window from 0.10 ms to 3.0 ms.
- [ ] Add the `uvm_lock_owner` global beside `uvm_lock`.
- [ ] Make the owner write fatal: on failure, `rmdir` the lock and `die` **before** `uvm_lock` is set.
      Setting it first and dying leaves the EXIT trap reading an absent `owner`, declining ownership,
      and leaking the lock anyway.
- [ ] Rewrite `uvm_unlock`: early-out on empty `uvm_lock`; copy the path to a local and clear both
      globals; read `owner` with `read`, `2>/dev/null` **before** the input redirect, variable
      initialized in the same `local`; compare the whole line; `rm -f owner` and `rmdir` on a match,
      otherwise `note` and leave. Never branch on `read`'s return code.
- [ ] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: release on EXIT/INT/TERM is now
      qualified by ownership.
- **Verify:** the R1 drive — a foreign `owner` written from inside the installer leaves both the lock
  directory and that `owner` file intact, and an ordinary drive still leaves no lock behind. Red today
  at `FAIL: release removed a lock this process does not own`.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P2 — Release before every exec of the real uv
**Satisfies:** R4 · **Depends on:** P1
**Goal:** no path reaches an `exec` holding the lock, and the hot path pays one builtin test for it.

- [ ] `uvm_unlock` before `exec "${real_uv}" --version` in `uvm_self_update`.
- [ ] `uvm_unlock` before the `case "${mode}"` block covering the other three sites.
- [ ] Do **not** introduce `uvm_exec_real`. It is more miss-resistant and it makes R4's own census
      pattern match nothing, so the contract's verification would report zero sites.
- **Verify:** the census returns 4, and xtrace ordering puts `uvm_unlock` between `uvm_export_env` and
  `exec` on both `uv --version` and `uv self update`. Red today at
  `FAIL: no release between uvm_export_env and exec on 'uv --version'`.
- **Inspection-only for the reviewer:** "the release must be a builtin test that forks nothing when no
  lock is held" — the GOAL assigns this to a human, and no command decides it. Confirm the ownership
  read sits *after* the empty-`uvm_lock` early-out; before it, every hot-path call pays a failed
  `open(2)`. "Every site covered" is likewise a reading of the four-line census, not a proximity grep.
- **Touches:** `bin/uv-manager`.

## Phase P3 — Keep a live holder's lock alive for as long as the holder is
**Satisfies:** R2 · **Depends on:** P2
**Goal:** a hold longer than `UVM_LOCK_STALE` is never broken, and nothing outlives the drive.

- [ ] Derive `lock_beat=$(( lock_stale / 10 ))`, floored at 1, beside the existing knobs. No new
      environment variable — the GOAL forbids one.
- [ ] Add `uvm_lock_heartbeat`: sleep `lock_beat`; exit when `kill -0 "$$"` fails; re-read `owner` and
      exit unless it still matches `uvm_lock_owner`; rewrite it with byte-identical content. The
      re-read is what stops a refresher stamping our identity over a new holder's `owner` after a
      break — which R1 would then turn into an immortal lock.
- [ ] Spawn it after the owner write as `… >/dev/null 2>&1 &`, recording the pid. The redirection is
      load-bearing: a surviving child holds the caller's pipe open and `VER=$(uv --version)` was
      measured blocking 9 s on one.
- [ ] Reap in `uvm_unlock` — `kill` then `wait`, before reading `owner`. Without the `wait`, bash
      prints `Terminated: 15` and the subshell body to stderr, and the refresher can recreate `owner`
      between the `rm -f` and the `rmdir`.
- [ ] Change `uvm_age` to `uvm_age "${lock}/owner" || uvm_age "${lock}"`. A directory's mtime tracks
      its entry list, not writes to files inside it, so on the directory the heartbeat is invisible.
- [ ] Add the waiter's liveness probe ahead of the age test: same host with a dead pid loses the lock
      at once, same host with a live pid keeps it, anything else falls through to the mtime.
- [ ] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: the stale age is now measured from the
      heartbeat, not from acquisition.
- **Verify:** an 8-second hold against `UVM_LOCK_STALE=3` produces no `breaking stale provisioning
  lock` on the waiter's stderr and leaves `owner` naming the original pid; and a plain drive leaves no
  background job behind. The gate keeps `set +e` around the waiter and does **not** assert `rc=0` —
  after the fix the waiter dies of an ordinary timeout. Red today at
  `FAIL: a live holder's lock was broken as stale`.
- **Note on the second drive:** the orphan clause — SIGKILL the holder, assert `owner`'s mtime freezes
  — is **green today by construction**, because nothing refreshes anything yet. It is a regression
  guard against the failure this phase can introduce, not a post-condition it delivers, and the gate's
  red comes from the first drive. `jobs -p` was tried here and is blind: the refresher is a grandchild
  of the drive shell, so it reports nothing whether or not one leaked.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P4 — Refuse a knob configuration that lets a waiter break a live lock
**Satisfies:** R3 · **Depends on:** P3
**Goal:** `UVM_LOCK_TIMEOUT >= UVM_LOCK_STALE` is refused before any lock is touched, and `help` still
answers.

- [ ] Guard at the top of `uvm_acquire_lock`: numeric form first, then ordering, then `die` naming both
      variables and their values. Placement is inside the consuming function so `uvm help` and
      `uvm --version` still answer with a broken configuration.
- [ ] The numeric test is not optional and is a recorded deviation: with `UVM_LOCK_STALE=abc`, `set -u`
      kills the arithmetic at `:225` but bash 3.2 **exits 0**, so `VER=$(uv --version)` returns empty
      and true. It also catches `' '`, `0` and `-1`, each of which makes every lock instantly stale.
- [ ] Same-commit surface: the `uvm_help` knob lines (`:878` is already 78 columns against an 81-column
      heredoc, so this needs a continuation line), `etc/uv-manager.conf.example:71-76`, and
      `README.md`'s knob table at `:551-552`. Document the NFS floor — `UVM_LOCK_STALE` below roughly
      120 s is unsafe for cross-node waiters. `share/modulefiles/uv/main.lua` needs no change.
- [ ] Add the ordering constraint to `invariants.md` §5 and `AGENTS.md` § *Invariants*.
- **Verify:** inverted knobs exit non-zero, name both variables, and leave a pre-existing live lock
  present; a non-numeric value is refused; `uvm --version` and `uvm help` still answer; and all three
  user-facing files state the constraint. Red today at `FAIL: inverted knobs accepted (rc=0)`.
- **Touches:** `bin/uv-manager`, `etc/uv-manager.conf.example`, `README.md`,
  `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P5 — Tell a stalled user how to tell an abandoned lock from a live one
**Satisfies:** R5, R6 · **Depends on:** P4
**Goal:** the timeout message names the holder and gives a recovery command that works.

- [ ] Rewrite the timeout message: the owner line inline, the caveat that a recorded pid is on that
      host and not this one, and `rm -f '<lock>/owner' && rmdir '<lock>'`. With no `owner`, print
      `<none recorded>` and keep line 3 phrased conditionally so it still parses.
- [ ] Fix the recovery command, which has **never** worked — `rmdir '<lock>'` fails with
      `Directory not empty` for every successful acquisition, because `owner` lives inside the
      directory. `invariants.md` §5's "the exact `rmdir` command to recover" is currently unsatisfied
      by the code; this is what makes it true.
- [ ] Keep the message on `die` rather than a `cat` heredoc. Recorded deviation, argued from
      measurement: one `printf` behind a departed reader emits one diagnostic line, the same count BSD
      `cat` produces, and only when the caller ignores SIGPIPE.
- [ ] Give the stale-break note the same owner line. After R1, "whose lock was that" is the first
      question following a break.
- [ ] Add `README.md` § *Troubleshooting*'s first lock entry, naming
      `$UVM_ROOT/<arch>/.install.lock`, its `owner` file and the two-step removal. The `owner` file is
      currently documented nowhere a user will look, and a message that points at it owes one.
- [ ] Update `invariants.md` §5 and `AGENTS.md` § *Invariants* for the recovery-command wording.
- **Verify:** a drive to timeout whose stderr matches `owner`, `host` and `pid` as whole words and
  carries the two-step recovery; a stale break naming the owner it deleted; `README.md` mentioning
  `install.lock`; plus the full R6 regression — `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`, and
  no `flock` outside a comment. Red today at `FAIL: timeout message never mentions 'owner'`.
- **Touches:** `bin/uv-manager`, `README.md`, `.agents/factory/invariants.md`, `AGENTS.md`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note the
   amendment in the commit body. STOP and escalate only on a `GOAL.md` contradiction.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
