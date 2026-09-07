---
slug: lock-acquire-retake
title: A rank robbed of its fresh lock retakes it
kind: fix
appetite: small
status: in_review
branch: fix/lock-acquire-retake
base: main
current_phase: done
last_updated: '2026-09-06'
phases:
- id: P1
  name: Bounded retake in uvm_acquire_lock, with the invariant text narrowed
  status: done
  satisfies:
  - R1
  - R2
  - R3
  - R5
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: 'set -eu

    bash -n bin/uv-manager

    .agents/factory/bin/lint.sh >/dev/null

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R1DRIVE''

    set -eu

    S="$UVM_SANDBOX/shim"; mkdir -p "$S"

    printf ''%s\n'' ''#!/bin/sh'' ''case "${1:-}" in *.install.lock) /bin/mkdir "$1"
    || exit $?; [ -e "$UVM_SANDBOX/fired" ] || { : > "$UVM_SANDBOX/fired"; /bin/rmdir
    "$1"; }; exit 0;; esac; exec /bin/mkdir "$@"'' > "$S/mkdir"

    chmod +x "$S/mkdir"; PATH="$S:$PATH"; export PATH

    err="$UVM_SANDBOX/err"

    out=$(uv --version 2>"$err") || { echo "FAIL R1: robbed winner exited non-zero
    instead of retaking the lock" >&2; cat "$err" >&2; exit 1; }

    [ "$out" = "uv 9.9.9 (fixture)" ] || { echo "FAIL R5: stdout was [$out], not the
    fixture version alone" >&2; exit 1; }

    if grep -q ''cannot record ownership'' "$err"; then echo "FAIL R1: retake still
    reported the fatal owner-write error" >&2; exit 1; fi

    if grep -qiE ''retak|reacquir'' "$err"; then echo "FAIL R5: the retake announced
    itself on stderr" >&2; exit 1; fi

    R1DRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R2DRIVE''

    set -eu

    S="$UVM_SANDBOX/shim"; mkdir -p "$S"

    printf ''%s\n'' ''#!/bin/sh'' ''case "${1:-}" in *.install.lock) /bin/mkdir "$1"
    || exit $?; [ -e "$UVM_SANDBOX/fired" ] || { : > "$UVM_SANDBOX/fired"; /bin/chmod
    500 "$1"; }; exit 0;; esac; exec /bin/mkdir "$@"'' > "$S/mkdir"

    chmod +x "$S/mkdir"; PATH="$S:$PATH"; export PATH

    err="$UVM_SANDBOX/err"

    if UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 uv --version >/dev/null 2>"$err"; then
    echo "FAIL R2: an EACCES owner write was silently retried into success" >&2; exit
    1; fi

    grep -q ''Permission denied'' "$err" || { echo "FAIL R2: the errno did not reach
    stderr" >&2; cat "$err" >&2; exit 1; }

    grep -q ''cannot record ownership'' "$err" || { echo "FAIL R2: the wrapper''s
    own fatal message is gone" >&2; exit 1; }

    R2DRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R3DRIVE''

    set -eu

    S="$UVM_SANDBOX/shim"; mkdir -p "$S"

    printf ''%s\n'' ''#!/bin/sh'' ''case "${1:-}" in *.install.lock) /bin/mkdir "$1"
    || exit $?; /bin/rmdir "$1"; exit 0;; esac; exec /bin/mkdir "$@"'' > "$S/mkdir"

    chmod +x "$S/mkdir"; PATH="$S:$PATH"; export PATH

    err="$UVM_SANDBOX/err"; s=$(date +%s)

    if UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 uv --version >/dev/null 2>"$err"; then
    echo "FAIL R3: an endlessly robbed rank reported success" >&2; exit 1; fi

    e=$(date +%s); [ $((e-s)) -lt 5 ] || { echo "FAIL R3: repeated robbery consumed
    UVM_LOCK_TIMEOUT ($((e-s))s) instead of a literal bound" >&2; exit 1; }

    R3DRIVE

    git grep -qi retak -- AGENTS.md || { echo "FAIL: AGENTS.md still asserts the owner
    write is fatal without the retake exception" >&2; exit 1; }

    git grep -qi retak -- .agents/factory/invariants.md || { echo "FAIL: invariants.md
    5 still asserts the owner write is fatal without the retake exception" >&2; exit
    1; }

    '
- id: P2
  name: 'Collateral proof: the three counters and the single-download hold are untouched'
  status: done
  satisfies:
  - R4
  - R6
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: 'set -eu

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R4ADRIVE''

    set -eu

    A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$L"

    printf ''host=foreign-node pid=99999 nonce=123\n'' > "$L/owner"

    err="$UVM_SANDBOX/err"; s=$(date +%s)

    if UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 uv --version >/dev/null 2>"$err"; then
    echo "FAIL R4a: a foreign lock did not block the caller" >&2; exit 1; fi

    e=$(date +%s)

    grep -q ''timed out after 5s waiting for provisioning lock'' "$err" || { echo
    "FAIL R4a: the timeout message changed" >&2; cat "$err" >&2; exit 1; }

    grep -q ''host=foreign-node pid=99999'' "$err" || { echo "FAIL R4a: the timeout
    no longer names the holder" >&2; exit 1; }

    [ $((e-s)) -ge 4 ] && [ $((e-s)) -le 8 ] || { echo "FAIL R4a: waited $((e-s))s
    against a 5s timeout" >&2; exit 1; }

    R4ADRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R4BDRIVE''

    set -eu

    A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$L"

    trap ''chmod 755 "$A" 2>/dev/null || true'' EXIT

    printf ''host=foreign-node pid=88888 nonce=987\n'' > "$L/owner"

    sleep 5

    chmod 555 "$A"

    err="$UVM_SANDBOX/err"

    UVM_LOCK_TIMEOUT=3 UVM_LOCK_STALE=4 uv --version >/dev/null 2>"$err" || true

    chmod 755 "$A"

    n=$(grep -c ''breaking stale provisioning lock'' "$err" || true)

    [ "$n" = "1" ] || { echo "FAIL R4b: expected exactly one break note across the
    wait, got $n" >&2; cat "$err" >&2; exit 1; }

    R4BDRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R4CDRIVE''

    set -eu

    S="$UVM_SANDBOX/shim"; mkdir -p "$S"

    printf ''%s\n'' ''#!/bin/sh'' ''case "${1:-}" in *.install.lock) n=0; [ -e "$UVM_SANDBOX/n"
    ] && n=$(cat "$UVM_SANDBOX/n"); echo $((n+1)) > "$UVM_SANDBOX/n"; exit 1;; esac;
    exec /bin/mkdir "$@"'' > "$S/mkdir"

    chmod +x "$S/mkdir"; PATH="$S:$PATH"; export PATH

    err="$UVM_SANDBOX/err"

    if UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 uv --version >/dev/null 2>"$err"; then
    echo "FAIL R4c: an uncreatable lock reported success" >&2; exit 1; fi

    grep -q ''cannot create provisioning lock'' "$err" || { echo "FAIL R4c: the absent-lock
    message changed" >&2; cat "$err" >&2; exit 1; }

    n=$(cat "$UVM_SANDBOX/n")

    [ "$n" = "3" ] || { echo "FAIL R4c: absent bound fired after $n mkdir attempts,
    not 3" >&2; exit 1; }

    R4CDRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''R6DRIVE''

    set -eu

    out=$(uv --version)

    [ "$out" = "uv 9.9.9 (fixture)" ] || { echo "FAIL R6: stdout was [$out]" >&2;
    exit 1; }

    A="$UVM_ROOT/$(uname -m)"; t=$(readlink "$A/current")

    [ "$t" = "versions/9.9.9" ] || { echo "FAIL R6: current points at [$t], not a
    relative versions/ target" >&2; exit 1; }

    [ ! -e "$A/.install.lock" ] || { echo "FAIL R6: a lock was left behind after a
    clean install" >&2; exit 1; }

    R6DRIVE

    n=$(git grep -c flock -- bin/uv-manager | cut -d: -f2)

    [ "$n" = "1" ] || { echo "FAIL R6: flock appears $n times in bin/uv-manager, not
    once as a rationale comment" >&2; exit 1; }

    test -f spec/lock-acquire-retake/research/04-collateral-measurements.md || { echo
    "FAIL: the collateral measurements were not recorded" >&2; exit 1; }'
review:
  last_reviewed_commit: ''
  verdict: none
  blocked_reason: ''
  cycle: 0
---
# TECH.md — A rank robbed of its fresh lock retakes it

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/lock-acquire-retake/TECH.md`); the per-phase checklists
below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus three briefs.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); the footgun checklist is
  [`invariants.md`](../../.agents/factory/invariants.md).
- One phase per `uvm-build` invocation; one atomic commit containing both the code and the `TECH.md`
  state change. Subjects follow `[fix] Build lock-acquire-retake P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids (`R1`, `P2`) in `bin/uv-manager`.

## A note on the two gates that shim `mkdir`

`P1`'s R1 and R3 drives, and `P2`'s R4c drive, intercept `mkdir` with a script first on `PATH`. They
work only while the wrapper's lock acquisition calls `mkdir` as an **external command with the lock
path as its sole argument** (`bin/uv-manager:346`). If that ever becomes a shell builtin or grows a
flag, the shim stops matching, the drive stops constructing the state it exists to construct, and the
failure mode is that the gate **passes**. `GOAL.md` § *Verification limit* declares this; anyone
changing the call shape owes these gates an update.

---

## Phase P1 — Bounded retake in `uvm_acquire_lock`, with the invariant text narrowed
**Satisfies:** R1, R2, R3, R5 · **Depends on:** —
**Goal:** a rank that wins `mkdir` and then finds its lock directory gone retakes the lock and
carries on; one that hits a real filesystem fault still dies with its errno.

- [x] Add `robbed=0` to the existing `local` line at `bin/uv-manager:289`, beside `waited`, `absent`
      and `broke`. Do not declare it inside the loop — that resets it every pass and makes the retake
      unbounded.
- [x] Change `:346` from `while ! mkdir "${lock}" 2>/dev/null; do` to `while :; do`, and make the
      `mkdir` the first statement of the body inside `if mkdir "${lock}" 2>/dev/null; then`. Leave the
      existing wait-loop body at its current indentation and do not edit it — the diff should show
      the body as unchanged context.
- [x] Inside that `if`: attempt the owner write as an `if` condition, `break` on success. On failure,
      `[[ -d "${lock}" ]]` means a fault — `rmdir` and `die` with today's message, unchanged. Absence
      means a lost race — increment `robbed`, `continue` while it is under the literal 3, and `die`
      with a distinct message naming the condition once it reaches it.
- [x] Keep the write's redirection order (`> "${lock}/owner"`, no `2>/dev/null` before it) so the
      shell's diagnostic still carries the errno R2 depends on.
- [x] Delete the post-loop `# Fatal, not best-effort:` comment and its
      `printf … || { rmdir; die; }` block. Carry forward, beside the new write, the two claims that
      still hold: ownership is certain the instant `mkdir` returns, and the write must precede
      `uvm_lock` or the EXIT trap declines ownership and leaks the lock.
- [x] Write the new comments in the repository's voice — the *why*, not the what. Four of them earn
      their place: the directory is the only evidence a failed redirect leaves the shell; absence is a
      lost race and presence is a fault; the bound is a literal that never resets, for the same reason
      `absent`'s is; the diagnostic stays unsuppressed because it carries the errno.
- [x] Narrow `AGENTS.md:154` and `.agents/factory/invariants.md:81` so neither asserts the owner
      write is fatal without qualification. Same commit as the code — a section still asserting the
      reversed decision turns correct code into an auto-CRITICAL finding at review. Nothing else in
      either file changes.
- **Verify:** `bash -n`, `lint.sh`, then three sandbox drives and two `git grep`s. Post-conditions:
  a robbed winner exits **0** with stdout exactly `uv 9.9.9 (fixture)` and no `cannot record
  ownership` and no retake announcement on stderr (R1, R5); an EACCES write exits **non-zero** with
  `Permission denied` *and* `cannot record ownership` on stderr (R2); a rank robbed on every attempt
  exits non-zero in **under 5s** against `UVM_LOCK_TIMEOUT=5`, proving a literal bound rather than
  the timeout (R3); and the word `retak` appears in both invariant files.
  Measured red today: rc 1 with empty stdout on the R1 drive.
- **Inspection-only, not decidable by the gate:** that `robbed` is a *constant* rather than a new
  environment variable (R3's own wording defers this to the reviewer, as it does for `absent`); that
  the narrowed invariant text says the right thing rather than merely containing the word the gate
  greps for; and that the wait-loop body is genuinely unedited rather than merely still passing.
  Read the diff for all three.
- **Touches:** `bin/uv-manager`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P2 — Collateral proof: the counters and the single-download hold
**Satisfies:** R4, R6 · **Depends on:** P1
**Goal:** establish, against the real diff, that `absent`, `waited` and `broke` behave exactly as the
earlier review cycles graded them, and that the ordinary provisioning path is untouched.

This phase exists because every previous remediation to `uvm_acquire_lock` shipped collateral rather
than failing at its target, and `P1`'s gate cannot see collateral. Its drives are **green before the
change as well as after** — R4 and R6 ask for no change, so a green gate here is evidence that `P1`
broke nothing, not evidence that work was done. The one post-condition that is red today is the
measurements record, which is this phase's deliverable.

- [x] Run the four drives in the `verify:` against the built tree.
- [x] Record the measurements in `spec/lock-acquire-retake/research/04-collateral-measurements.md`:
      per drive, the command, the observed rc, and the counted post-condition, set beside the
      pre-change figures in [`research/02-gate-baselines.md`](research/02-gate-baselines.md). Note
      any divergence explicitly rather than only the agreements.
- [x] If any drive is red, the collateral is real: stop, fix it in `bin/uv-manager`, and record what
      moved. Do not adjust the gate to accommodate the code.
- **Verify:** four sandbox drives plus two repository checks. Post-conditions: a fresh foreign lock
  times out with the holder named, within a **4-8s** window against `UVM_LOCK_TIMEOUT=5` (a window,
  not a value — `date` resolution and the loop's own `sleep 1` cost a full second of slop); a denied
  break emits the break note **exactly once** across the whole wait; the absent-lock retry dies after
  **exactly three** `mkdir` attempts with its own message; a clean offline install leaves stdout at
  the fixture version, `current` at the relative target `versions/9.9.9`, and no lock behind;
  `flock` still appears exactly **once** in `bin/uv-manager`; and the measurements file exists.
  Measured red today only on that last clause.
- **Known narrowness of R4b:** the construction denies `rmdir` but not `rm -f` of the owner file, so
  the second iteration finds no owner rather than re-deciding a break and being denied again. It is a
  real regression check on the `[[ -n "${broke}" ]] ||` guard but does not cover the
  both-halves-denied case, which needs `chflags`/`chattr` and is not portable
  ([`research/02`](research/02-gate-baselines.md) § E). Recorded so review does not over-read it.
- **Touches:** `spec/lock-acquire-retake/research/04-collateral-measurements.md`, and
  `bin/uv-manager` only if collateral is found.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `fix/lock-acquire-retake`, `main` reachable.
3. Execute every `[ ]` in the phase, consulting [`PLAN.md`](PLAN.md) and `research/` for detail.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file if reality diverges — regenerate frontmatter with `set_phase.py` and note the
   amendment in the commit body. STOP and escalate only on a `GOAL.md` contradiction.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
