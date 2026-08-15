# 04 — Releasing the lock before every `exec`: the sites, the shape, and the cost

**Conclusion, high confidence (measured): there are four wrapper `exec` sites, not three. All four
leak a held lock, reproduced in a sandbox. Two release points cover them — one before
`exec "${real_uv}" --version` in `uvm_self_update`, one before the `case` at `:944`. The guard costs
2 µs and zero forks when no lock is held, and that property depends on R1's ownership read landing
*after* the empty-`uvm_lock` early-out, not before it.**

Host: macOS 25.5, arm64, APFS, **bash 3.2.57** — the portability floor, so every construct below is
proven at the floor. Drives ran in a copy of the tree outside the working tree
(`cp -R . "$(mktemp -d)/probe"`), under `.agents/factory/bin/temp_root.sh --offline`.

## 1. Four sites, and one that is not a site

`git grep -n 'exec "\${real_' bin/uv-manager` returns exactly four:

```
bin/uv-manager:617:  exec "${real_uv}" --version          # uvm_self_update
bin/uv-manager:947:      exec "${real_uvx}" "$@"          # dispatch tail, uvx mode
bin/uv-manager:949:      exec "${real_uv}" tool run "$@"  # dispatch tail, uvx fallback
bin/uv-manager:953:    exec "${real_uv}" "$@"             # dispatch tail, default
```

The broader `git grep -n 'exec '` adds three comment lines (`:60`, `:454`, `:663`) and `:506`. `:506`
sits between `cat > "${tmp}" <<TRAMPOLINE` (`:498`) and the `TRAMPOLINE` delimiter (`:512`), and is
written `exec "\$t" "\$@"` — escaped, so it is emitted as text into the generated `/bin/sh`
trampoline. It executes in a different process, in a different shell, with none of this script's
state. It is not a wrapper `exec` site and needs no guard. There are no other forms: no `exec env`,
no `exec` used for redirection.

## 2. The gate contradicts the criterion it checks

R4's prose scopes the obligation to "each `exec` in the dispatch tail". `invariants.md` defines the
dispatch tail as "everything below the `# ---- dispatch` banner" — that banner is `:912`, so `:617`
is outside it by 295 lines. R4's own *Checked by* gate nevertheless matches `:617` and asks that
"every site" be covered.

This is a planning defect, and it should be resolved by **widening the criterion, not narrowing the
gate**. Three reasons. R4's first sentence — "No lock SHALL be held across `exec`" — is unqualified,
and it is the sentence that carries the safety property; the second sentence narrows placement, which
was a guess about where the sites are. `:617` demonstrably leaks (§3). And the reviewer will run the
gate verbatim: an implementation covering three of four matches reads as incomplete no matter what
the prose says. The cost of covering `:617` is one line.

Recommend a GOAL clarification recording this, rather than a silent choice in PLAN.

## 3. The leak, measured

`main` holds no lock at any `exec`, so the defect is latent. To make it live, the probe adds the
acquisition `purge-tree-repair` will add by design:

```
uvm_acquire_lock "" 1   # PROBE: stand-in for purge-tree-repair acquiring in the dispatch path
case "${mode}" in
```

Driven with `sh -c` so the shell outlives the wrapper's `exec`:

```
$ .agents/factory/bin/temp_root.sh --offline sh -c \
    'uv --version; ls -d "$UVM_ROOT"/*/.install.lock && cat "$UVM_ROOT"/*/.install.lock/owner'
uv 9.9.9 (fixture)
.../root/arm64/.install.lock
host=Geoffreys-MacBook-Pro-main.local pid=1663 time=1786809979
```

Same result for `uvx demo` (`:947`). Inserting `uvm_unlock` immediately before the `case`:

```
uv 9.9.9 (fixture)   →   lock dir: GONE
uvx-fixture: demo    →   lock dir: GONE
```

`:617` behaves identically. With `uvm_acquire_lock "" 1` inserted between `uvm_install` and the
`exec` inside `uvm_self_update`, `uv self update` left `.install.lock` behind with a live `owner`
file. Baseline — the unmodified script, same drive — leaves no lock, confirming the probe and not the
wrapper is what holds it.

## 4. What the traps already cover

Every non-`exec` exit path releases, verified rather than assumed. With the acquisition placed after
`uvm_export_env`: `uv tool list` and `uv python list` (the `exit "${rc}"` at `:941`) both leave
`lock dir: GONE`, as do `uv self update --dry-run` and the `-h` path (`exit 0` at `:610`/`:604`), and
`die`. The `EXIT` trap is sufficient everywhere except `exec`. R4 is therefore a four-line change to
a discipline that is otherwise complete, not a redesign.

One hazard found while placing that probe: an acquisition before the self-update branch **deadlocks**,
because `uvm_self_update` calls `uvm_install`, which acquires again. The drive sat for the full
`UVM_LOCK_TIMEOUT` and died with the `rmdir` advice — the nesting failure R3 is about, reached from a
new direction. Whoever places `purge-tree-repair`'s acquisition needs this in front of them.

## 5. Shape: two release points

Three designs were compared.

**One call before the `case` at `:944`.** One line, covers `:947`/`:949`/`:953`. Leaves `:617`
uncovered, so the gate keeps matching a site the guard does not reach.

**One call before each of the four `exec`s.** Locally obvious; four lines, three of them adjacent and
redundant — `:947` and `:949` are the two arms of one `if`, and a release before the enclosing `case`
covers both plus `:953` without repetition. Symmetry for its own sake.

**A helper — `uvm_exec_real() { uvm_unlock; exec "$@"; }`.** Structurally unmissable, and the only
design a future edit cannot forget. Rejected: it defeats R4's own gate. `uvm_exec_real "${real_uv}"
"$@"` does not match `exec "\${real_`, and neither does the helper's `exec "$@"`, so the contract's
verification returns zero matches and stops meaning anything. It also adds a function call on the hot
path and hides the `exec` from a reader scanning the tail — the semantics `invariants.md` §2 makes
load-bearing should stay visible where they happen.

**Recommended: two release points.** `uvm_unlock` immediately before `exec "${real_uv}" --version` in
`uvm_self_update`, and `uvm_unlock` immediately before `case "${mode}" in` at `:944`. Every gate match
then has a release above it within a few lines, checkable by eye against the gate's own output. State
the *why* once at each site — no trap survives `exec`, so the release cannot be delegated to `EXIT` —
and nowhere else.

Miss-resistance for a future edit is honestly ranked helper > per-exec > this; the tie-breaker is that
the gate is the enforcement mechanism the contract names, and a design that blinds it trades a
guarantee for a convention. A new `exec` inside the tool/python block would also be a change to
invariants §2, which review catches independently.

This is behavior-neutral on `main` — nothing holds the lock at `exec` today — so the same-commit rule
is not triggered. No `uvm_help`, `README.md`, `conf.example` or modulefile text describes it.

## 6. Cost, and the constraint on R1

`uvm_unlock` (`:177-182`) opens with `[[ -n "${uvm_lock}" ]] || return 0`. `[[` and `return` are
builtins; the `rm` and `rmdir` are below the early-out. Measured at the portability floor, 100 000
calls with `uvm_lock` empty: **4.793 µs/call**, against **2.749 µs** for a function whose body is `:`.
The guard itself is ~2 µs — 0.04% of the 5 ms budget. With `rm`, `rmdir`, `stat`, `date` and `uname`
shadowed by PATH stubs that log every invocation, five empty-lock calls logged **zero** external
commands.

That property is a constraint on R1, which another pass is designing. **The ownership read must sit
after the empty-`uvm_lock` early-out.** Placed before it, every hot-path invocation pays to read an
`owner` file under a path that is the empty string — a `$(cat …)` costs a fork and a subshell, and
even a builtin `read <` costs a failed `open(2)`, on the path `uv run` takes inside loops. The
early-out must remain the first statement in the function.

A second interaction for R1/R2. The `owner` file records `$$`, and `exec` preserves the pid — the
leaked lock in §3 names pid 1663, which *was* the wrapper and *became* the real `uv`. If R2's
liveness test is a pid probe rather than mtime alone, a lock leaked across `exec` reads as **live**
for the entire duration of the user's command and cannot be broken as stale. R2 makes R4 more
load-bearing, not less: it removes the stale-breaker's ability to clean up after the leak.

## 7. Nothing after the release needs the lock

Trace: `uvm_ensure_uv` (`:926`) either finds the wanted version present or calls `uvm_install`, which
releases on every path it takes — `:318` (re-check under the lock), `:364` (success), and `:345`/`:353`
via `die` and the `EXIT` trap. `uvm_acquire_lock`'s early-out returns 1 without ever setting
`uvm_lock`. Provisioning is therefore complete and unlocked before `uvm_export_env` runs, and
`uvm_export_env` sets variables and at most `mkdir -p`s state directories — it touches nothing the
lock protects.

The lock protects *writes* to `versions/` and the `current` swap. Past `uvm_ensure_uv` the wrapper
only reads: `real_uv` resolves through `current`, whose target is swapped atomically and written
relative, and `versions/<ver>` is never removed by the provisioning path — only `.incoming.*` staging
is. Releasing before `exec` cannot release something still needed.

It does foreclose one design: holding the lock for the lifetime of the exec'd `uv`. That is not a
trade-off, it is arithmetic — `exec` destroys the trap, so a lock held across it is not held, it is
abandoned. `purge-tree-repair` must finish its work before the tail, not around it.

## Not established

Whether a *future* caller could legitimately need mutual exclusion spanning the exec'd `uv` — the
repair cycle's R7 rebuild is assumed to complete before dispatch, which is a reading of a seed, not a
verified design. `mkdir` atomicity on Lustre, GPFS and NFS, per the GOAL's declared verification
limit. The timing figures are one host, warm, single-process; they bound the guard's cost from above
on a laptop and say nothing about contention on a shared metadata server. And the probe proves the
guard closes the leak for an acquisition placed where this pass chose to put it — it cannot prove
coverage of a site that does not exist yet.
