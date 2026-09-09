---
status: unshaped
kind: fix
appetite: small
lane: public
---

# A pinned rank that loses the provisioning race runs whatever version it finds

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

`uvm_install` has three paths that satisfy a request, and only two of them select the version. The
fast path at `bin/uv-manager:566` and the re-check under the lock at `:574` both run
`[[ -n "${want}" ]] && uvm_point_current "${want}"`. The lock's early-out at `:570` —
`uvm_acquire_lock "${want}" "${force}" || return 0` — returns success having selected nothing.

The gap it lands in is one line wide. `uvm_acquire_lock`'s early-out at `:399` fires on
`uvm_have "${want}"`, which for a non-empty `want` tests `versions/${want}/uv` **directly**. That
becomes true at the rename at `:618`. `current` is not swapped until `:620`. A pinned waiter whose
early-out samples the tree between those two lines returns 0 with `current` pointing wherever it
pointed before.

**With an empty `want` the defect is unreachable, which is why it has gone unnoticed.** `uvm_have ""`
tests `-x "${real_uv}"` — that is `current/uv` — so it cannot be true unless `current` already
resolves, and then there is nothing for `uvm_point_current` to repair. Measured: 2962 early-outs
across 2816 unpinned ranks, zero wrong trees, zero installer entries. The early-out is harmless on
every path that does not carry a pin.

**With a pin it has two outcomes and the quiet one is worse.** Both measured against an instrumented
copy under `temp_root.sh --offline`, 32 concurrent ranks at `UVM_PIN=6.6.6`, with the
`:618`→`:620` gap widened by a `ln` PATH shim (`sleep 2; exec /bin/ln "$@"`) — no edit to the
wrapper, the technique `spec/lock-acquire-retake/` used for `mkdir`:

- **Cold tree.** 31 of 32 ranks took the early-out with `current` absent and died with
  `uv is still missing after provisioning`, rc 1, empty stdout.
- **Warm tree already selecting 9.9.9.** 31 of 32 ranks took the early-out, `current` still resolved
  to `versions/9.9.9`, and every one of them **executed 9.9.9 having asked for 6.6.6** — rc 0,
  nothing on stderr, no way for the caller to know.

The operator spellings reach it too. Two concurrent `uvm install 6.6.6` on a tree at 9.9.9 printed
`selected uv 9.9.9 (fixture)` and exited 0. `uv self update 6.6.6` calls `uvm_install "${target}" ""`
at `:873` and then `exec`s `--version`, which reports the version it did not select.

The silent case contradicts `.agents/factory/invariants.md` §4: "A pin is **authoritative**:
`UVM_PIN` selects which version `current` points at, not merely what to download when nothing is
present." It is wrong output rather than a failure, which is the harder kind to notice — a site that
pins a version for reproducibility gets a different interpreter under some ranks of a job and a
correct one under others, with nothing in the log to say so.

**A prior review recorded this line as "real, pre-existing and self-correcting". The last of those is
false.** The *tree* self-corrects: the winning rank swaps `current` a millisecond later. The
*invocation* does not — it has already returned, or already `exec`ed.

## Why it was deferred

**Pre-existing on `main`** and unrelated to the provisioning lock's break path. Found while
attributing the two-installer signal for `lock-break-instance-identity` R2, whose contract explicitly
declines to repair this line: that cycle measures the early-out and obliges itself only to record
what it finds. Landing a version-selection change inside a cycle already restructuring
`uvm_acquire_lock` would mix an unrelated correctness change into a diff that already forces a human
sign-off gate.

It also wants a decision this cycle had no appetite to take. The three return paths disagree, and the
tidy repair is not "add the missing line" — `uvm_ensure_uv` at `:628` already performs the same test
one frame up, so the better shape is probably for the early-out to return a status the caller acts
on. That is a small refactor of a high-blast-radius function, not a one-line patch.

## Outcome / vision

A pin is honoured by every path that returns success, or the request fails loudly. No invocation ever
`exec`s a version the caller did not ask for.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion.

- **R1** — WHEN a pinned request is satisfied by another process's concurrent install, the wrapper
  SHALL select the pinned version before returning, or SHALL fail naming the version it could not
  select. It SHALL NOT `exec` a different version at rc 0.
- **R2** — The three paths in `uvm_install` that return success SHALL agree on whether selection has
  happened, and that agreement SHALL be visible in the code rather than reconstructed by a reader.
- **R3** — Behavior with an empty `want` SHALL be unchanged. The early-out is on the ordinary
  cold-start path for every unpinned rank in a job, and 2962 of them were measured harmless.

## Notes

- The construction is reproducible without instrumenting the wrapper: widen `:618`→`:620` with a `ln`
  shim first on `PATH` inside `temp_root.sh --offline`, set `UVM_PIN`, and run 32 ranks against one
  shared root. The stdout histogram is the assertion — 31 ranks printing a version nobody asked for.
- Related: [`spec/lock-break-instance-identity/`](../spec/lock-break-instance-identity/GOAL.md) R2 is
  what measured this, and its § *Non-goals* is the deferral this file discharges;
  [`issues/invariant-audit-gaps.md`](invariant-audit-gaps.md) is the sibling pattern — a code gap
  behind an invariant that reads as satisfied.
- Not a lock defect, despite living one line from one. The lock's early-out is correct: it returns 1
  because another process satisfied the request, which is exactly what it is for. The defect is that
  `uvm_install` treats that return as "done" rather than as "satisfied, still unselected".
- Found by: `lock-break-instance-identity` planning, research topic 05, correcting a finding recorded
  during `lock-ownership-and-hold-time` review cycle 2.
