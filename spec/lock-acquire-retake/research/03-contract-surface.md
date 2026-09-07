# Research 03 — contract surface for the acquire-loop restructure

## Decisions (load-bearing facts)

- `uvm_acquire_lock` has exactly one caller: `bin/uv-manager:548`. Its 0/1 return is fully absorbed by
  `|| return 0` there — no other code branches on it, and `uvm_install` itself never returns non-zero
  (it only returns 0 or `die`s). The restructure must preserve exactly two exits: `return 0` with the
  lock held and globals set, `return 1` with nothing held and nothing set.
- Three globals cross the function boundary on success: `uvm_lock`, `uvm_lock_owner`,
  `uvm_lock_beat_pid` (set at `:466-467,478`). Two readers exist: `uvm_unlock` (`:234-268`), and the
  detached heartbeat subshell (`:193-227`), which reads `uvm_lock_owner` by inherited value at fork
  time, not by argument — it is never passed explicitly.
- The EXIT/INT/TERM traps (`:273-275`) call `uvm_unlock` unconditionally; `uvm_unlock`'s own guard
  (`[[ -n "${uvm_lock}" ]] || return 0`, `:235`) is what makes this safe before `uvm_lock` is set. A
  kill between a winning `mkdir` and the `uvm_lock=` assignment leaks the just-created directory today
  (the fatal-`die` path already partially covers this with its own `rmdir` at `:463`, but a bare
  signal skips that too). The restructure does not change this guard or close this window — it
  makes the window recur once per bounded retry instead of once per call, which is an accepted,
  unavoidable consequence of adding a retry inside the same acquire, not a new defect class.
- `waited`, `absent`, `broke` are initialized exactly once, at the `local` line (`:289`), and are never
  reset anywhere else in the function (confirmed: `grep -n` for each assignment form returns only the
  four lines below). A new retry counter declared the same way survives the restructured loop for the
  same reason. The footgun to avoid: re-declaring it with `local` *inside* the loop body would reset it
  every iteration and silently defeat R3.
- Every other loop-scoped local (`holder`, `pid`, `reason`, `still`) has no initializer at `:289` but is
  explicitly reset to `""` as the first thing done with it on every iteration, before any read. No
  unbound-variable read exists today under `set -u`, and none of these four is a candidate for the new
  counter's storage — the new counter belongs beside `waited`/`absent`, not beside these.
- The same-commit rule pulls in exactly two files beyond `bin/uv-manager` itself: `AGENTS.md:154` and
  `.agents/factory/invariants.md:81`. Neither `uvm_help`, `README.md`, `etc/uv-manager.conf.example`,
  nor `share/modulefiles/uv/main.lua` asserts owner-write fatality anywhere, so none of the four needs
  editing. Both anchor phrases below are confirmed unique (count 1) and single-line via `git grep`.

## Part 1 — call graph and return contract

**Caller.** `bin/uv-manager:548`, inside `uvm_install`:

```
uvm_acquire_lock "${want}" "${force}" || return 0  # another process got there first
```

`uvm_acquire_lock` returning 1 means the early-out at `:366-368` fired: while this rank was waiting,
another process installed `want` and `force` was not set. `uvm_install` treats that identically to
"nothing to do" and returns 0 immediately, without ever having acquired the lock and without calling
`uvm_unlock` (harmless if it did — `uvm_unlock` no-ops on an empty `uvm_lock`). Returning 0 means the
lock is held and `uvm_install` proceeds to re-check under lock (`:551`), download, and eventually call
`uvm_unlock` itself on every exit path (`:553,580,588,599`). `uvm_install` is called from three sites —
`uvm_ensure_uv:609`, `uvm_self_update:851`, and the manager `install` subcommand (`:1146`) — none of
which inspect its return value; under `set -euo pipefail` that is safe only because `uvm_install` never
returns non-zero itself (it either returns 0 or calls `die`, which exits the script). The restructure
must not introduce a third return value or a path where `uvm_install`'s caller could see non-zero.

**Globals set on success** (`:466-478`): `uvm_lock="${lock}"`, `uvm_lock_owner="${owner}"`,
`uvm_lock_beat_pid=$!`. Readers:
- `uvm_unlock` (`:234-268`) reads all three, by design ("release only what this process still owns").
- `uvm_lock_heartbeat` (`:193-227`) reads `uvm_lock_owner` at `:225-226` — as an inherited global in
  the forked subshell, not a parameter. This is the only reader of `uvm_lock_owner` besides `uvm_unlock`.
- Nothing else in the script reads any of the three (confirmed by exhaustive grep — no hits outside
  `uvm_acquire_lock` itself, `uvm_unlock`, and `uvm_lock_heartbeat`).

**Trap window.** `uvm_unlock`'s guard is `[[ -n "${uvm_lock}" ]] || return 0` (`:235`). `uvm_lock` is
declared empty at load (`:175`) and is set only at `:466`, after the owner-write block (`:462-465`)
completes. So: a kill landing anywhere from the moment `mkdir` returns 0 (loop test false, `:346`)
through `:465` finds `uvm_lock` still empty, and the trap-invoked `uvm_unlock` does nothing — the
directory (and, depending on exact timing, a partially or fully written `owner` file) is left for the
stale-break path to reclaim later. The fatal-write branch already does its own best-effort `rmdir`
(`:463`) for the case where the write itself fails, but a raw external signal bypasses that entirely.
This is a pre-existing, accepted gap (the comment at `:400` calls it "one caught inside the acquire
window"), not something this cycle introduces. The restructure changes its *frequency*, not its
*mechanism*: moving `mkdir` into the loop body means this same window can be re-entered on every
bounded retry attempt (a rank robbed twice re-opens the window twice), whereas today it opens at most
once per call. The guard logic itself (`uvm_lock` as the single signal of "is there anything to
clean up") is untouched and remains correct under the retry.

**`uvm_unlock` call sites** (six explicit calls, plus the three trap invocations at `:273-275`):

| Line | Context | On provisioning path? |
|---|---|---|
| 553 | `uvm_install`, re-check-under-lock finds want already satisfied | yes |
| 580 | `uvm_install`, installer piped to `sh` failed, before `die` | yes |
| 588 | `uvm_install`, wrong-architecture / version-detection failure, before `die` | yes |
| 599 | `uvm_install`, end of successful install, before implicit return | yes |
| 856 | `uvm_self_update`, guard before `exec "${real_uv}" --version` | no — dispatch-tail guard, "no lock survives an exec" |
| 1189 | main dispatch tail, guard before the three `exec` branches | no — same guard, general case |

**Exit paths out of `uvm_acquire_lock`** (six `die`, two `return`):

| Line | Exit | Condition |
|---|---|---|
| 324 | `die` | `lock_timeout`/`lock_stale` not both digit-strings |
| 336 | `die` | `lock_timeout >= lock_stale` |
| 344 | `die` | cannot `mkdir -p "${uvm_root}"` |
| 359 | `die` | lock directory absent on 3rd consecutive probe (persistent absence) |
| 367 | `return 1` | early-out — `want` already satisfied elsewhere, `force` unset |
| 447 | `die` | `waited > lock_timeout` |
| 464 | `die` | owner write failed — **this is the site the plan narrows** |
| 479 | `return 0` | success, lock held, globals set |

## Part 2 — local variable lifetimes

Declaration, `:289`:

```
local waited=0 age holder pid broke="" reason absent=0 host started still
```

`waited=0`, `broke=""`, `absent=0` are initialized only here. Every other assignment to them is a
mutation, never a re-init:

```
357:      absent=$(( absent + 1 ))
437:      broke=denied
440:    waited=$(( waited + 1 ))
```

No line anywhere in the function sets `absent=0`, `waited=0`, or `broke=""` a second time — confirmed
by grepping the whole file for each assignment form; the only hits are the four lines above. They are
plain function-local shell variables (not loop-scoped), so they persist across every iteration of the
existing `while` loop, which is exactly what R3/R4 require and exactly what a new retry counter needs:
declare it at `:289` alongside `absent`/`waited`, initialize to 0 there, increment inside the loop, and
never touch it with `local` again inside the loop body — a second `local ctr=0` inside the loop would
silently reset it every pass and defeat the bound.

Locals declared with no initializer: `age`, `holder`, `pid`, `reason`, `host`, `started`, `still`.
`host` (`:297`) and `started` (`:302`) are assigned once, unconditionally, before the loop, and never
read before that assignment — no risk. `holder`, `pid`, `reason`, `still` are all first *written*
(explicitly reset to `""`) as the first act of the code path that uses them, every iteration, before
any read:

- `holder=""` at `:373`, read starting `:374`.
- `pid=""` at `:375`, read starting `:376`.
- `reason=""` at `:387`, read starting `:388` (same `if` chain that sets it).
- `still=""` at `:423`, read at `:424`, only reachable inside `[[ -n "${reason}" ]]` (`:407`).

`age` is never independently initialized; its only assignment is inside the condition that reads it
(`:402-403`, `age="$(...)" || age="$(...)"` immediately followed by `(( age > lock_stale ))` in the same
compound test), so the read is always preceded by the assignment in the same expression. None of the
seven is at risk of an unbound-variable error under `set -u` today. None of them is a candidate
storage location for the new counter — a counter needs monotonic persistence across iterations, which
is the `waited`/`absent`/`broke` pattern, not the reset-every-iteration pattern these four use.

## Part 3 — same-commit doc surface

**`uvm_help` heredoc** (`bin/uv-manager:1098-1125`). Says nothing about the owner file or its
fatality. The only lock-related lines are:

```
1118  UVM_LOCK_TIMEOUT    Seconds to wait for the provisioning lock (default: 180)
1119  UVM_LOCK_STALE      Seconds before an untouched lock is broken (default: 600)
1120                      The timeout must be less than the stale threshold.
```

No edit needed.

**`README.md`.** Checked the four named regions plus a repo-wide search for "owner"/"fatal" near lock
prose:
- `:136-138` — "Concurrent invocations serialize on an atomic `mkdir` lock that releases itself on
  signals and breaks itself when abandoned." No fatality claim.
- `:372-373` — "The wrapper's own provisioning lock uses `mkdir` instead, which is atomic on Lustre,
  GPFS and NFS and needs no `flock`." No fatality claim.
- `:458-459` — "**`mkdir` for the provisioning lock.** Atomic on Lustre, GPFS and NFS, needs no helper
  binary, and does not depend on `flock`..." No fatality claim.
- `:526-534` — describes the `owner` file's contents and the manual-removal recovery command, but
  never describes what happens when *writing* it fails. No sentence to narrow.

No edit needed anywhere in `README.md`.

**`etc/uv-manager.conf.example`** and **`share/modulefiles/uv/main.lua`** — confirmed via
`grep -in "owner\|fatal"` (conf.example) and `grep -in "lock"` (main.lua): zero matches in both. Neither
file mentions the lock's ownership mechanism at all; only `conf.example` documents the timeout/stale
env vars, unaffected by this change. No edit needed in either.

**`AGENTS.md` § Invariants**, exact sentence, single line, `AGENTS.md:154`:

```
delete is bounded by nothing. The owner write is fatal, because a holder that cannot prove ownership
```

(continues onto `:155`: "leaks its own lock for a full stale window.") The clause "The owner write is
fatal" sits wholly on line 154 in this file.

**`.agents/factory/invariants.md` §5**, exact sentence, `.agents/factory/invariants.md:81`:

```
  write is fatal (a holder that cannot prove ownership leaks its own lock for a full stale window)
```

Here the sentence is hard-wrapped: "The" ends line 80 (`...release matches on the path alone. The`)
and "owner write is fatal (...)" continues on line 81. A grep anchor spanning both files must therefore
avoid the word "The" glued to "owner write is fatal".

**Anchors, verified by running `git grep` just now:**

- `AGENTS.md`: anchor `The owner write is fatal` — `git grep -c "The owner write is fatal" -- AGENTS.md`
  → `AGENTS.md:1`. Fits on one line there (`:154`), unique.
- `.agents/factory/invariants.md`: anchor `write is fatal (a holder that cannot prove ownership` —
  `git grep -c "write is fatal (a holder that cannot prove ownership" -- .agents/factory/invariants.md`
  → `.agents/factory/invariants.md:1`. Fits on one line there (`:81`), unique. (The `AGENTS.md` anchor
  does *not* work against this file — the phrase is split across two lines here — which is why a
  narrower, invariants.md-specific anchor is needed.)

Both counts are exactly 1, as expected pre-change. A gate written against these anchors should assert
the phrase is *absent* (or narrowed to a qualified form) post-change in both files, since a plan that
narrows "when" the write is fatal must edit both sentences to say so, or the reviewer's diff check for
an overturned invariant will find a section still asserting the pre-narrowing absolute.
