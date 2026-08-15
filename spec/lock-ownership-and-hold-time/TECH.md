---
slug: lock-ownership-and-hold-time
title: The provisioning lock can be released by a process that does not hold it
kind: fix
appetite: big
status: in_progress
branch: fix/lock-ownership-and-hold-time
base: main
current_phase: P5
last_updated: '2026-08-15'
phases:
- id: P1
  name: Give the lock an identity, and release only what matches it
  status: done
  satisfies:
  - R1
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: 'set -eu

    bash -n bin/uv-manager

    .agents/factory/bin/lint.sh >/dev/null

    .agents/factory/bin/temp_root.sh --offline sh -s <<''DRIVE''

    set -e

    A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; export UVM_TEST_LOCK="$L"

    printf ''%s\n'' ''printf "host=elsewhere pid=999999 nonce=0\n" > "$UVM_TEST_LOCK/owner"''
    >> "$UVM_FIXTURE_DIR/install.sh"

    uv --version >/dev/null

    if [ ! -d "$L" ]; then echo "FAIL: release removed a lock this process does not
    own" >&2; exit 1; fi

    if [ ! -f "$L/owner" ]; then echo "FAIL: foreign owner file removed" >&2; exit
    1; fi

    if ! grep -q ''pid=999999'' "$L/owner"; then echo "FAIL: foreign owner overwritten"
    >&2; exit 1; fi

    DRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''DRIVE''

    set -e

    uv --version >/dev/null

    L="$UVM_ROOT/$(uname -m)/.install.lock"

    if [ -d "$L" ]; then echo "FAIL: own lock not released" >&2; exit 1; fi

    DRIVE

    '
- id: P2
  name: Release before every exec of the real uv
  status: done
  satisfies:
  - R4
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\nn=$(git grep -n 'exec \"\\${real_' bin/uv-manager\
    \ | wc -l | tr -d ' ')\nif [ \"$n\" != 4 ]; then echo \"FAIL: exec census is $n,\
    \ expected 4\" >&2; exit 1; fi\n.agents/factory/bin/lint.sh >/dev/null\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nuv --version >/dev/null 2>&1\nfor probe in\
    \ \"--version\" \"self update\"; do\n  PS4='+ ' bash -x \"$(command -v uv)\" $probe\
    \ >/dev/null 2>\"$UVM_SANDBOX/t\" || true\n  u=$(grep -n '^++* uvm_unlock$' \"\
    $UVM_SANDBOX/t\" | tail -1 | cut -d: -f1 || true)\n  p=$(grep -n '^++* export\
    \ PATH$' \"$UVM_SANDBOX/t\" | tail -1 | cut -d: -f1 || true)\n  e=$(grep -n '^++*\
    \ exec ' \"$UVM_SANDBOX/t\" | tail -1 | cut -d: -f1 || true)\n  if [ -z \"$u\"\
    \ ] || [ -z \"$e\" ] || [ \"$u\" -lt \"$p\" ] || [ \"$u\" -gt \"$e\" ]; then\n\
    \    echo \"FAIL: no release between uvm_export_env and exec on 'uv $probe' (unlock=$u\
    \ path=$p exec=$e)\" >&2\n    exit 1\n  fi\ndone\nDRIVE\n"
- id: P3
  name: Keep a live holder's lock alive for as long as the holder is
  status: done
  satisfies:
  - R2
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"\nprintf '%s\\n' 'if [ -n \"${UVM_FIXTURE_SLOW:-}\"\
    \ ]; then sleep \"$UVM_FIXTURE_SLOW\"; fi' >> \"$UVM_FIXTURE_DIR/install.sh\"\n\
    ( UVM_FIXTURE_SLOW=8 uv --version >/dev/null 2>\"$UVM_SANDBOX/holder.err\" ) &\
    \ holder=$!\nsleep 1\nfirst=$(sed -n 's/.*\\(pid=[0-9][0-9]*\\).*/\\1/p' \"$L/owner\"\
    \ 2>/dev/null || true)\nsleep 4\nset +e\nUVM_LOCK_STALE=3 UVM_LOCK_TIMEOUT=2 uv\
    \ --version >/dev/null 2>\"$UVM_SANDBOX/waiter.err\"\nset -e\nnow=$(sed -n 's/.*\\\
    (pid=[0-9][0-9]*\\).*/\\1/p' \"$L/owner\" 2>/dev/null || true)\nif grep -q 'breaking\
    \ stale provisioning lock' \"$UVM_SANDBOX/waiter.err\"; then\n  echo \"FAIL: a\
    \ live holder's lock was broken as stale\" >&2; exit 1\nfi\nif [ -z \"$first\"\
    \ ] || [ \"$first\" != \"$now\" ]; then\n  echo \"FAIL: lock was $first, now ${now:-gone}\"\
    \ >&2; exit 1\nfi\nwait \"$holder\"\nDRIVE\n.agents/factory/bin/temp_root.sh --offline\
    \ sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\
    \nprintf '%s\\n' 'if [ -n \"${UVM_FIXTURE_SLOW:-}\" ]; then sleep \"$UVM_FIXTURE_SLOW\"\
    ; fi' >> \"$UVM_FIXTURE_DIR/install.sh\"\n( UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=10\
    \ UVM_FIXTURE_SLOW=20 uv --version >/dev/null 2>&1 ) & holder=$!\nsleep 2\np=$(sed\
    \ -n 's/.*pid=\\([0-9][0-9]*\\).*/\\1/p' \"$L/owner\" 2>/dev/null || true)\nif\
    \ [ -z \"$p\" ]; then echo \"FAIL: no holder pid recorded\" >&2; exit 1; fi\n\
    kill -9 \"$p\" 2>/dev/null || true\nsleep 1; m1=$(stat -f %m \"$L/owner\" 2>/dev/null\
    \ || stat -c %Y \"$L/owner\" 2>/dev/null || true)\nsleep 3; m2=$(stat -f %m \"\
    $L/owner\" 2>/dev/null || stat -c %Y \"$L/owner\" 2>/dev/null || true)\nwait \"\
    $holder\" 2>/dev/null || true\nif [ \"$m1\" != \"$m2\" ]; then\n  echo \"FAIL:\
    \ something refreshed the lock after its holder was killed ($m1 -> $m2)\" >&2;\
    \ exit 1\nfi\nDRIVE"
- id: P4
  name: Refuse a knob configuration that lets a waiter break a live lock
  status: done
  satisfies:
  - R3
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=%s\
    \ pid=%s nonce=0\\n' \"$(uname -n)\" \"$$\" > \"$L/owner\"\nsleep 3\nset +e\n\
    UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"\
    ; rc=$?\nset -e\nif [ \"$rc\" -eq 0 ]; then echo \"FAIL: inverted knobs accepted\
    \ (rc=0)\" >&2; exit 1; fi\nif ! grep -q UVM_LOCK_TIMEOUT \"$UVM_SANDBOX/err\"\
    \ || ! grep -q UVM_LOCK_STALE \"$UVM_SANDBOX/err\"; then\n  echo \"FAIL: refusal\
    \ does not name both variables\" >&2; exit 1\nfi\nif [ ! -d \"$L\" ]; then echo\
    \ \"FAIL: the live lock was destroyed\" >&2; exit 1; fi\nset +e\nUVM_LOCK_STALE=abc\
    \ uv --version >/dev/null 2>&1; rcn=$?\nset -e\nif [ \"$rcn\" -eq 0 ]; then echo\
    \ \"FAIL: non-numeric UVM_LOCK_STALE accepted (rc=0)\" >&2; exit 1; fi\nUVM_LOCK_TIMEOUT=10\
    \ UVM_LOCK_STALE=2 uvm --version >/dev/null\nUVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2\
    \ uvm help >/dev/null\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s\
    \ <<'DRIVE'\nset +e\nUVM_LOCK_TIMEOUT=0600 UVM_LOCK_STALE=500 uv --version >/dev/null\
    \ 2>\"$UVM_SANDBOX/oct\"; rc=$?\nset -e\nif [ \"$rc\" -eq 0 ]; then\n  echo \"\
    FAIL: 0600 vs 500 accepted -- the guard judged 384, not 600\" >&2; exit 1\nfi\n\
    if ! grep -q 'UVM_LOCK_TIMEOUT=600' \"$UVM_SANDBOX/oct\"; then\n  echo \"FAIL:\
    \ the refusal prints the raw string, not the seconds it judged\" >&2; exit 1\n\
    fi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\n\
    out=$(UVM_LOCK_TIMEOUT=500 UVM_LOCK_STALE=0600 uv --version 2>\"$UVM_SANDBOX/oct2\"\
    )\nif [ \"$out\" != \"uv 9.9.9 (fixture)\" ]; then\n  echo \"FAIL: a legal pair\
    \ spelled 500/0600 was refused: $(cat \"$UVM_SANDBOX/oct2\")\" >&2; exit 1\nfi\n\
    DRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"\
    $UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\"; mkdir \"$L\"\
    \nprintf 'host=%s pid=%s nonce=0\\n' \"$(uname -n)\" \"$$\" > \"$L/owner\"\nset\
    \ +e\nUVM_LOCK_TIMEOUT=3 UVM_LOCK_STALE=0800 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"\
    \nset -e\nif grep -q 'value too great for base' \"$UVM_SANDBOX/err\"; then\n \
    \ echo \"FAIL: the form check passed a value the arithmetic cannot evaluate\"\
    \ >&2; exit 1\nfi\nDRIVE\nif ! grep -q 'UVM_LOCK_TIMEOUT' etc/uv-manager.conf.example;\
    \ then echo \"FAIL: conf example silent\" >&2; exit 1; fi\nfor f in README.md\
    \ etc/uv-manager.conf.example bin/uv-manager; do\n  if ! grep -q 'less than' \"\
    $f\"; then echo \"FAIL: $f does not state the ordering constraint\" >&2; exit\
    \ 1; fi\ndone\n"
- id: P5
  name: Tell a stalled user how to tell an abandoned lock from a live one
  status: pending
  satisfies:
  - R5
  depends_on:
  - P4
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=node0042\
    \ pid=12345 nonce=0\\n' > \"$L/owner\"\nset +e\nUVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=600\
    \ uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"; rc=$?\nset -e\nif [ \"$rc\"\
    \ -eq 0 ]; then echo \"FAIL: waiter did not time out\" >&2; exit 1; fi\nfor tok\
    \ in owner host pid; do\n  if ! grep -qw \"$tok\" \"$UVM_SANDBOX/err\"; then\n\
    \    echo \"FAIL: timeout message never mentions '$tok'\" >&2; exit 1\n  fi\n\
    done\nif ! grep -q \"rm -f .*owner.* && rmdir\" \"$UVM_SANDBOX/err\"; then\n \
    \ echo \"FAIL: recovery command still advises a bare rmdir that cannot succeed\"\
    \ >&2; exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\n\
    set -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\";\
    \ mkdir \"$L\"\nprintf 'host=node0042 pid=12345 nonce=0\\n' > \"$L/owner\"\nsleep\
    \ 2\nUVM_LOCK_STALE=1 UVM_LOCK_TIMEOUT=10 uv --version >/dev/null 2>\"$UVM_SANDBOX/brk\"\
    \nif ! grep -q 'breaking' \"$UVM_SANDBOX/brk\"; then echo \"FAIL: no break occurred\"\
    \ >&2; exit 1; fi\nif ! grep -q 'pid=12345' \"$UVM_SANDBOX/brk\"; then\n  echo\
    \ \"FAIL: stale-break note does not name the owner it deleted\" >&2; exit 1\n\
    fi\nDRIVE\nif ! grep -q 'install\\.lock' README.md; then\n  echo \"FAIL: README\
    \ documents no lock troubleshooting entry\" >&2; exit 1\nfi\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nout=$(uv --version)\nif [ \"$out\" != \"\
    uv 9.9.9 (fixture)\" ]; then echo \"FAIL: stdout was '$out'\" >&2; exit 1; fi\n\
    A=\"$UVM_ROOT/$(uname -m)\"\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9\
    \ ]; then echo \"FAIL: current target moved\" >&2; exit 1; fi\nDRIVE\nif git grep\
    \ -n flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#';\
    \ then\n  echo \"FAIL: flock invoked outside a comment\" >&2; exit 1\nfi\n"
- id: P6
  name: Make UVM_LOCK_TIMEOUT bound a waiter it cannot break free of
  status: pending
  satisfies:
  - R7
  - R6
  depends_on:
  - P5
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"\nmkdir -p \"$L/stuck\"\nsleep 2\nUVM_LOCK_TIMEOUT=2\
    \ UVM_LOCK_STALE=1 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\" &\np=$!\nsleep\
    \ 6\nif kill -0 \"$p\" 2>/dev/null; then\n  kill -9 \"$p\" 2>/dev/null || true\n\
    \  echo \"FAIL: still spinning 6s after a 2s timeout ($(wc -l < \"$UVM_SANDBOX/err\"\
    \ | tr -d ' ') lines)\" >&2\n  exit 1\nfi\nif ! grep -q 'timed out after' \"$UVM_SANDBOX/err\"\
    ; then\n  echo \"FAIL: the waiter exited without the timeout message\" >&2; exit\
    \ 1\nfi\nif [ \"$(grep -c 'breaking' \"$UVM_SANDBOX/err\" || true)\" -gt 1 ];\
    \ then\n  echo \"FAIL: the denied break re-announced itself every iteration\"\
    \ >&2; exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\n\
    set -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\";\
    \ mkdir \"$L\"\nprintf 'host=node0042 pid=12345 nonce=0\\n' > \"$L/owner\"\nsleep\
    \ 2\nUVM_LOCK_STALE=1 UVM_LOCK_TIMEOUT=10 uv --version >/dev/null 2>\"$UVM_SANDBOX/brk\"\
    \nif ! grep -q 'breaking' \"$UVM_SANDBOX/brk\"; then\n  echo \"FAIL: an ordinary\
    \ stale break no longer works\" >&2; exit 1\nfi\nA=\"$UVM_ROOT/$(uname -m)\"\n\
    if [ \"$(readlink \"$A/current\")\" != versions/9.9.9 ]; then echo \"FAIL: break\
    \ did not provision\" >&2; exit 1; fi\nDRIVE\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nout=$(uv --version)\nif [ \"$out\" != \"\
    uv 9.9.9 (fixture)\" ]; then echo \"FAIL: stdout was '$out'\" >&2; exit 1; fi\n\
    A=\"$UVM_ROOT/$(uname -m)\"\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9\
    \ ]; then echo \"FAIL: current target moved\" >&2; exit 1; fi\nDRIVE\nif git grep\
    \ -n flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#';\
    \ then\n  echo \"FAIL: flock invoked outside a comment\" >&2; exit 1\nfi\n"
review:
  last_reviewed_commit: ''
  verdict: none
  blocked_reason: ''
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

- [x] Build the owner line before the `while ! mkdir` loop, from expansions only:
      `host=${HOSTNAME} pid=$$ nonce=${RANDOM}${RANDOM}${RANDOM}`. Remove `time=` and both command
      substitutions — they are what widen the `mkdir`-to-owner-write window from 0.10 ms to 3.0 ms.
- [x] Add the `uvm_lock_owner` global beside `uvm_lock`.
- [x] Make the owner write fatal: on failure, `rmdir` the lock and `die` **before** `uvm_lock` is set.
      Setting it first and dying leaves the EXIT trap reading an absent `owner`, declining ownership,
      and leaking the lock anyway. The shell's own redirect diagnostic is left unsuppressed — it
      carries the errno, and `die`'s line does not.
- [x] Rewrite `uvm_unlock`: early-out on empty `uvm_lock`; copy the path to a local and clear both
      globals; read `owner` with `read`, `2>/dev/null` **before** the input redirect, variable
      initialized in the same `local`; compare the whole line; `rm -f owner` and `rmdir` on a match,
      otherwise `note` and leave. Never branch on `read`'s return code.
- [x] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: release on EXIT/INT/TERM is now
      qualified by ownership.
- **Verify:** the R1 drive — a foreign `owner` written from inside the installer leaves both the lock
  directory and that `owner` file intact, and an ordinary drive still leaves no lock behind. Red today
  at `FAIL: release removed a lock this process does not own`.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P2 — Release before every exec of the real uv
**Satisfies:** R4 · **Depends on:** P1
**Goal:** no path reaches an `exec` holding the lock, and the hot path pays one builtin test for it.

- [x] `uvm_unlock` before `exec "${real_uv}" --version` in `uvm_self_update`.
- [x] `uvm_unlock` before the `case "${mode}"` block covering the other three sites.
- [x] Do **not** introduce `uvm_exec_real`. It is more miss-resistant and it makes R4's own census
      pattern match nothing, so the contract's verification would report zero sites.
- [x] **Amended:** add the release-before-`exec` rule to `invariants.md` §5 and `AGENTS.md`
      § *Invariants*. `PLAN.md` enumerated three invariant revisions and this was not among them,
      because R4 overturns nothing. The amendment is argued from the same asymmetry the cycle runs
      on: `uvm_exec_real` was rejected for making the census blind, so the census plus a comment at
      each site is all that stops a fifth `exec` from being added without a release — and under P3's
      heartbeat that omission is no longer a bounded leak but a lock nothing can break. The next
      cycle is the one that acquires the lock late in the dispatch path.
- **Verify:** the census returns 4, and xtrace ordering puts `uvm_unlock` between `uvm_export_env` and
  `exec` on both `uv --version` and `uv self update`. Red today at
  `FAIL: no release between uvm_export_env and exec on 'uv --version'`.
- **Observed:** cold drive traced `export PATH` (153) → `uvm_unlock` (157) → `exec` (161), with the
  guard costing three trace lines and no fork; `uv tool list` still releases from the EXIT trap after
  its `exit 0`.
- **Inspection-only for the reviewer:** "the release must be a builtin test that forks nothing when no
  lock is held" — the GOAL assigns this to a human, and no command decides it. Confirm the ownership
  read sits *after* the empty-`uvm_lock` early-out; before it, every hot-path call pays a failed
  `open(2)`. "Every site covered" is likewise a reading of the four-line census, not a proximity grep.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P3 — Keep a live holder's lock alive for as long as the holder is
**Satisfies:** R2 · **Depends on:** P2
**Goal:** a hold longer than `UVM_LOCK_STALE` is never broken, and nothing outlives the drive.

- [x] Derive `lock_beat=$(( lock_stale / 10 ))`, floored at 1. No new environment variable — the GOAL
      forbids one. **Amended:** derived inside `uvm_acquire_lock`, not beside the knobs as planned.
      Measured on bash 3.2.57: `UVM_LOCK_STALE=abc` makes that arithmetic fatal under `set -u`
      (`abc: unbound variable`), so at load time it would kill `uvm help` and `uvm --version` — the
      two commands that document these knobs, and the reason `PLAN.md` §3 puts R3's guard inside the
      function rather than at load. Load-time derivation would also read `0600` as 38 rather than 60,
      because P4 normalizes `lock_stale` inside the function, after load. Keeping the arithmetic in
      `uvm_acquire_lock` confines it to where `(( age > lock_stale ))` already lives, so P3 adds no
      new failure surface.
- [x] Add `uvm_lock_heartbeat`: sleep `lock_beat`; exit when `kill -0 "$$"` fails; re-read `owner` and
      exit unless it still matches `uvm_lock_owner`; rewrite it with byte-identical content. The
      re-read is what stops a refresher stamping our identity over a new holder's `owner` after a
      break — which R1 would then turn into an immortal lock. Also `trap - EXIT INT TERM` in the
      subshell: research measured async subshells resetting traps anyway, but a refresher whose EXIT
      trap did fire would find its inherited `uvm_lock`/`uvm_lock_owner` matching and delete the live
      lock it exists to protect.
- [x] Spawn it after the owner write as `… >/dev/null 2>&1 &`, recording the pid. The redirection is
      load-bearing: a surviving child holds the caller's pipe open and `VER=$(uv --version)` was
      measured blocking 9 s on one.
- [x] Reap in `uvm_unlock` — `kill` then `wait`, before reading `owner`. Without the `wait`, bash
      prints `Terminated: 15` and the subshell body to stderr, and the refresher can recreate `owner`
      between the `rm -f` and the `rmdir`.
- [x] Change `uvm_age` to `uvm_age "${lock}/owner" || uvm_age "${lock}"`. A directory's mtime tracks
      its entry list, not writes to files inside it, so on the directory the heartbeat is invisible.
- [x] Add the waiter's liveness probe ahead of the age test: same host with a dead pid loses the lock
      at once, same host with a live pid keeps it, anything else falls through to the mtime. A pid
      that is not all digits is treated as unprobeable rather than dead — `kill -0` would fail on it
      and manufacture a break with no evidence behind it.
- [x] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: the stale age is now measured from the
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
- **Observed beyond the gate:** with `UVM_LOCK_STALE=20` against a 9 s hold, `owner`'s mtime advanced
  1786823336 → 1786823342 while the lock directory stayed pinned at 1786823336 — the measurement that
  makes the `uvm_age` change necessary rather than defensive. `VER=$(uv --version)` on a cold tree
  returned in 0 s with no `uv-manager` process left running, and stderr carried no `Terminated`. An
  owner-less lock still ages out through the directory fallback; a live pid past `UVM_LOCK_STALE` is
  never broken; a dead pid on this host is broken at once inside a 600 s window.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P4 — Refuse a knob configuration that lets a waiter break a live lock
**Satisfies:** R3 · **Depends on:** P3
**Goal:** `UVM_LOCK_TIMEOUT >= UVM_LOCK_STALE` is refused before any lock is touched, and `help` still
answers.

- [x] Guard at the top of `uvm_acquire_lock`: numeric form first, then ordering, then `die` naming both
      variables and their values. Placement is inside the consuming function so `uvm help` and
      `uvm --version` still answer with a broken configuration.
- [x] The numeric test is not optional and is a recorded deviation: with `UVM_LOCK_STALE=abc`, `set -u`
      kills the arithmetic at `:225` but bash 3.2 **exits 0**, so `VER=$(uv --version)` returns empty
      and true. It also catches `' '`, `0` and `-1`, each of which makes every lock instantly stale.
- [x] Force base 10 after the form test and before the comparison, assigning back to the **existing
      globals**: `lock_timeout=$(( 10#${lock_timeout} ))`, same for `lock_stale`. Not `local` — `:225`,
      `:233` and the timeout message must read the same seconds. `0600` is 384 to bash and `0800` is
      not a number at all, so a guard on the raw strings judges seconds the operator never wrote and
      prints a refusal its own two numbers satisfy.
- [x] Keep the form test **ahead** of the normalization: `$(( 10#${x} ))` on an empty or all-space
      value is silently `0` on bash 3.2 and an error on 5.2, and a `0` stale makes every lock
      instantly stale.
- [x] No extra user-facing surface for the normalization — a padded value now means what it looks
      like. `etc/uv-manager.conf.example` gains "whole seconds, decimal"; `uvm_help` and `README.md`
      still only gain the ordering constraint.
- [x] Same-commit surface: the `uvm_help` knob lines (`:878` is already 78 columns against an 81-column
      heredoc, so this needs a continuation line), `etc/uv-manager.conf.example:71-76`, and
      `README.md`'s knob table at `:551-552`. Document the NFS floor — `UVM_LOCK_STALE` below roughly
      120 s is unsafe for cross-node waiters. `share/modulefiles/uv/main.lua` needs no change.
- [x] Add the ordering constraint to `invariants.md` §5 and `AGENTS.md` § *Invariants*.
- **Verify:** inverted knobs exit non-zero, name both variables, and leave a pre-existing live lock
  present; a non-numeric value is refused; `uvm --version` and `uvm help` still answer; and all three
  user-facing files state the constraint; plus `TIMEOUT=0600 STALE=500` refused with the refusal
  printing `600`, `TIMEOUT=500 STALE=0600` accepted, and `STALE=0800` reaching no arithmetic. Red
  today at `FAIL: inverted knobs accepted (rc=0)`. The `500/0600` drive is green today and red against
  a guard that omits the normalization — it is the row that discriminates the correct guard from the
  one the first draft of this plan specified.
- **Red state moved, and the reason matters.** The gate went red at `FAIL: refusal does not name both
  variables`, not at the predicted `FAIL: inverted knobs accepted (rc=0)`. P3 landed first, and its
  liveness probe already keeps a lock whose recorded pid is alive on this host, so the inverted-knob
  drive now times out non-zero instead of breaking the lock. The remaining harm R3 names — a waiter
  breaking a *cross-node* live holder, which no probe can rescue — is unreachable from one machine,
  so the assertion that still discriminates is the refusal itself.
- **Observed beyond the gate:** `' '`, `0`, `-1`, `abc`, `12x`, `18:0` and `0x10` each refused with a
  pre-placed foreign lock and its `owner` file surviving intact; `0600/500` refused printing
  `UVM_LOCK_TIMEOUT=600` — the seconds judged, not the string written; `500/0600` and the defaults
  both accepted through to `current -> versions/9.9.9`; `uvm help` answering 0 under inverted knobs
  and carrying the new constraint line.
- **P3's gate was retuned in this phase, and P3 stays `done`.** Its second drive held the lock with
  `UVM_LOCK_STALE=10` against the default `UVM_LOCK_TIMEOUT=180` — a pair this phase now refuses, so
  the holder never acquired and the gate failed at `FAIL: no holder pid recorded`. The drive was
  written before the ordering constraint existed; the knobs became illegal, not the assertion. Fixed
  to `UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=10` through `set_phase.py --verify`, re-run green. P1 and P2
  were re-run and needed nothing — both use the defaults.
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

## Phase P6 — Make `UVM_LOCK_TIMEOUT` bound a waiter it cannot break free of
**Satisfies:** R7, R6 · **Depends on:** P5
**Goal:** a stale lock that cannot be removed produces a timeout, not an unbounded spin.

- [ ] Retry the `mkdir` immediately only when the directory is actually gone. After the break attempt,
      `[[ -d "${lock}" ]] || continue`; otherwise fall through to the accounting and the sleep.
- [ ] A bare `die` on `rmdir` failure is **wrong**: two waiters can declare the same lock stale, and
      the loser's `rmdir` gets `ENOENT` having done nothing wrong. The discriminator is whether the
      directory survived, not whether our own `rmdir` returned zero.
- [ ] Add `broke` to the existing `local waited=0 age` line and use it to suppress re-announcing a
      denied break. At the default timeout that would otherwise be 180 identical lines.
- [ ] No user-facing surface change and no `invariants.md` edit: §5 already asserts the wrapper times
      out after `UVM_LOCK_TIMEOUT`. This phase is what makes that assertion true.
- **Verify:** against a lock directory holding an entry the wrapper did not write, aged past
  `UVM_LOCK_STALE`, the call exits within the timeout carrying the timeout message and announces the
  break at most once; an ordinary stale break still works and still provisions; plus the full R6
  regression, so the last phase ends on the cold-provisioning check. Red today at
  `FAIL: still spinning 6s after a 2s timeout` — measured 825 lines before the harness killed it.
- **Touches:** `bin/uv-manager`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note the
   amendment in the commit body. STOP and escalate only on a `GOAL.md` contradiction.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
