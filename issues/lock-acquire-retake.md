---
status: adopted:lock-acquire-retake
kind: fix
appetite: small
lane: public
---

# A rank robbed of its fresh lock dies instead of retaking it

> **Candidate, not a contract.** Deferred work recorded so a future session does not re-derive it.
> Not graded by `uvm-review`; never copy into a `GOAL.md` verbatim.

## Problem

`uvm_acquire_lock` wins `mkdir`, then records ownership:

```sh
printf '%s\n' "${owner}" > "${lock}/owner" || {
  rmdir "${lock}" 2>/dev/null || true
  die "cannot record ownership of the provisioning lock at ${lock}/owner"
}
```

The write is fatal by design — a holder that cannot prove ownership leaks its own lock for a full
stale window, which is why `invariants.md` §5 and `AGENTS.md` both say so. But the redirect has two
quite different failure modes and the code treats them alike. A genuine filesystem fault deserves
the `die`. **A lost race does not**, and it gets one:

- rank `W` wins `mkdir`, so it owns the directory;
- a losing stale-breaker, still executing a break it decided a moment earlier, `rm -f`s the `owner`
  file and `rmdir`s the directory out from under `W` (the residual tracked in
  [`lock-break-instance-identity.md`](lock-break-instance-identity.md));
- `W`'s redirect opens `ENOENT`, and `W` dies having done nothing wrong.

The user sees exit 1 with **empty stdout**, preceded by a raw shell diagnostic naming an internal
script line:

```
bin/uv: line 461: /…/.install.lock/owner: No such file or directory
uv-manager: cannot record ownership of the provisioning lock at /…/.install.lock/owner
```

On a wrapper that sits under unattended provisioning, `VER=$(uv --version)` comes back empty — the
shape `invariants.md` §7 exists to prevent — and the two paths the message names no longer exist by
the time an operator reads the job log.

**This is authored, not inherited.** On `main` before 0.6.0 the same write was
`> "${lock}/owner" 2>/dev/null || true`: a robbed winner continued and installed. Matched A/B on an
identical construction put **`main` at zero robbed winners** against the shipped code's **4 of 1280**
(dead-holder plant) and **3 of 1280** (owner-less plant). On the ordinary cold-start path with no
lock planted: **0 of 2304**.

## Why it was deferred

Review cycle 3 of `lock-ownership-and-hold-time` confirmed it as F9 and the maintainer deferred it by
**explicit override**, cleared 2026-08-26, rather than by the review rubric's deferral exception —
that exception is conjunctive and this fails its first condition, the death being authored by the
diff under review. The grounds are in `spec/lock-ownership-and-hold-time/REVIEW.md`
§ *Human-gate triggers*, and the reasoning was not that the defect is acceptable:

- the remedy is a **restructure** of the acquire loop, not the local edit cycle 2 had supposed, and
  the review loop bound was exhausted, so it would have shipped unreviewed;
- every remediation to `uvm_acquire_lock` on that cycle produced **collateral** rather than a failure
  of its target, so this function wants a review behind it more than it wants to be rushed;
- shipping 0.6.0 was measurably safer than withholding it — the release fixes a defect costing 21 of
  1280 ranks on ordinary contention, against this one's 0 of 2304 on the same path.

Released in 0.6.0 and live on `main`.

## Outcome / vision

A rank that loses the acquire race retakes the lock and carries on. A rank that hits a real
filesystem fault still dies, still with its errno. Nothing else about the acquire loop moves.

## Sketch of the acceptance criteria

Draft R-IDs, to be firmed up at promotion. Carried over from
[`lock-break-instance-identity.md`](lock-break-instance-identity.md), where this was that seed's R3
before it was split out; its numbering there is left with a gap so existing citations still resolve.

- **R1** — WHEN the wrapper's own `owner` write fails because the directory it created has been
  removed, the wrapper SHALL retake the lock rather than die, bounded by a constant in the style of
  the existing absent-lock retry, and SHALL still report a genuine filesystem fault with its errno.
- **R2** — The retake SHALL NOT reset or bypass the timeout accounting. A rank robbed repeatedly
  SHALL still exit at `UVM_LOCK_TIMEOUT`, and the existing `absent`, `waited` and `broke` counters
  SHALL keep the exact behavior reviewers graded them for.
- **R3** — Behavior under the existing single-download hold SHALL be unchanged, and the discipline
  SHALL remain `mkdir`.

## The gate already exists, and it is cheap

This is what makes the cycle `small`: the failure is a deterministic property of one code path given
one filesystem state — `mkdir` returned 0 and `${lock}` is absent at the owner write. The wrapper
cannot tell a constructed instance from a raced one, because its only evidence is `$?` from `mkdir`
and the result of the redirect. So a candidate is graded pass/fail rather than against noise, and
none of the concurrency-harness debt blocking `lock-break-instance-identity` R1/R2 applies here.

Driven red against `b3f7491` and green against a scratch patch, about two seconds per drive:

```sh
shim=$(mktemp -d)
cat > "$shim/mkdir" <<'EOF'
#!/bin/sh
if [ $# -eq 1 ]; then case "$1" in *.install.lock)
  /bin/mkdir "$1" || exit $?
  [ -e "${UVM_SANDBOX}/fired" ] || { : > "${UVM_SANDBOX}/fired"; /bin/rmdir "$1"; }
  exit 0 ;; esac; fi
exec /bin/mkdir "$@"
EOF
chmod +x "$shim/mkdir"
# Drive `uv --version` with "$shim" first on PATH inside temp_root.sh --offline,
# asserting rc 0 and non-empty stdout. Red before the fix: rc 1, stdout empty.
```

It is coupled to `mkdir` remaining an external command taking the lock path as its sole argument
(`bin/uv-manager:346` at 0.6.0), which belongs in a comment beside the gate. Its **companion**
`chmod 500`s the lock directory instead of removing it, and asserts the write stays fatal with its
errno intact — that is what stops a fix here turning a genuine filesystem fault into a silent retry,
and it is half the gate rather than an extra.

## Two things measured that a fix will otherwise walk into

**The stderr cleanup is a trap.** The obvious way to keep the shell's own diagnostic off stderr on a
successful retake — `err=$( { printf '%s\n' "${owner}" > "${lock}/owner"; } 2>&1 )` — is unsafe under
this script's `set -euo pipefail` (`bin/uv-manager:19`). A failing command substitution aborts the
shell before any `die` runs, so the fatal path loses `cannot record ownership` altogether and exits a
bare 1, which is worse than today. Guard it explicitly with `|| { … }`, or leave the stray line
alone: on a successful retake stdout is already clean, and the cold-provisioning path writes installer
output to stderr regardless. Not required by R1 either way.

**Collateral is the real risk, and the gate above does not cover it.** The remedy wraps an outer
retry around a loop body carrying three counters that reviewers graded separately for exact behavior.
Whoever takes this owes gates pinning all three unchanged: rc 1 at exactly `UVM_LOCK_TIMEOUT` against
a fresh foreign lock, exactly one break note across a denied break, and `absent`'s literal bound of
three intact. Cycle 3 recorded a twenty-line ceiling on the diff to `uvm_acquire_lock` as the signal
to stop and reconsider rather than push through.

## Notes

- `uvm_acquire_lock` is a named high-blast-radius region in `AGENTS.md`, so a confirmed finding here
  forces a human sign-off gate at review.
- Fixing this does **not** close the race that causes it. The retake makes the robbed winner recover
  instead of dying; the robbery still happens, and belongs to
  [`lock-break-instance-identity.md`](lock-break-instance-identity.md) R2, which stays blocked on the
  concurrency harness that seed's R1 describes.
- Related: [`issues/test-harness.md`](test-harness.md) R3d already owns the lock's ownership and
  hold-time contract as a regression case; this gate discharges part of it *without* two processes,
  which is a stronger claim than that seed currently makes.
- The retained account of what shipped and why:
  [`spec/lock-ownership-and-hold-time/`](../spec/lock-ownership-and-hold-time/REVIEW.md) — cycle 3's
  F9 and its `### Correction to cycle 2`.
- Found by: `uvm-review` cycle 3 of `lock-ownership-and-hold-time` (debate variant; the block-stance
  reviewer isolated it with the matched A/B), 2026-08-26.
