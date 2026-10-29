# Roadmap

The ordered index of future cycles, in the order they should be taken. One entry per
`issues/{slug}.md`; each **Seed** points at the pre-shaped deferral that holds the evidence.
`/uvm-feature` promotes one into a `spec/{slug}/GOAL.md`, and that promotion is where appetite,
non-goals and the R-IDs get negotiated. An entry here is a candidate, not a commitment. When the cycle
lands on `main`, `/uvm-roadmap` retires the seed and removes its entry.

Entries carry no numbers, and a cross-reference names the slug rather than a position. Retiring an
entry shifts everything below it, and an ordinal reference survives that shift still grammatical and
now pointing at the wrong cycle.

Unremediated security findings are indexed separately in `.security/ROADMAP.md`, which is gitignored.
See `AGENTS.md` for why.

---

## Queued

### Stop breaking the lock, and split provisioning from repair
**Seed:** [`issues/lock-simplification.md`](issues/lock-simplification.md) · `fix` · appetite big ·
**adopted** as [`spec/lock-simplification/`](spec/lock-simplification/GOAL.md)

In flight. The decision taken on 2026-09-09 after `lock-break-instance-identity`'s review stands: the
wrapper never breaks a lock and never infers whether a holder is alive. Shaping on 2026-10-27 settled
fifteen criteria. A provisioning waiter past `UVM_LOCK_TIMEOUT` installs for itself and a repair
waiter fails, with one notice naming the holder when a wait runs long. Publishing becomes safe against
a concurrent publish of the same version, which today nests one tree inside another at rc 0, and a
failed publish cleans up after itself. `uvm doctor` reports a standing lock and `uvm clean` removes
it without the tree. The heartbeat, lock ageing, every break path, the ownership-qualified release
and `UVM_LOCK_STALE` go, and `tests/lock-race.sh` is re-pointed at a correct-tree assertion.

Two neighbours folded in. The pinned early-out defect below was adopted whole, since this cycle
rewrites the early-out it lives in. The owner-write fatal path was confirmed to survive the robbery
in one form, a lock left standing that nothing would reclaim, and is R11. It also absorbs R3 of
`invariant-audit-gaps` and makes that seed's R4 moot, and takes `purge-tree-repair` R11 as its R6.
Sequenced first: it unblocks `purge-tree-repair`.

### `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`
**Seed:** [`issues/purge-tree-repair.md`](issues/purge-tree-repair.md) · `feature` · appetite big

The repair half, re-shaped around what research found. The knob stays: it fires inside `uv`/`uvx`
after the platform key is resolved on the executing node, which makes it architecture-correct by
construction where a bring-up subcommand — proposed and rejected during planning — would repair the
login node's tree and leave the job's untouched. What changed is the contract. Detection has a floor
no budget removes, since a deleted distribution and every managed interpreter leave no manifest, so
the criteria must name what is caught and concede the rest. Cost is handled by a verification receipt
rather than an integrity stamp. The detector it reads shipped in 0.5.0, and the lock's ownership and
hold-time fix landed with it, so the concurrency bug this cycle would otherwise have inherited is
gone. What remains above it is `lock-simplification`, which replaced both lock cycles that used to sit
here. This cycle is the reason that one exists: R7's "exactly one repairs, the rest wait and re-test"
is the first non-provisioning hold, at 1-30 seconds rather than a download, and it contributes R5 and
R6 there. Its own R11 moves into that cycle as R6.

### A pinned call can run another call's pin, when two pins race for `current`
**Seed:** [`issues/pin-holds-against-concurrent-pins.md`](issues/pin-holds-against-concurrent-pins.md) ·
`fix` · appetite small

`current` is one link per root and a pin is per process, so two calls on one root pinned to different
versions each select their own and the later swap wins. Every run of `uv` goes through `current`, so
the earlier call then runs the other pin's version at rc 0 with nothing on stderr. Measured in
`lock-simplification` review cycle 3: 13 and 19 of 320 ranks in alternating-pin bursts, on the atomic
`mv -h` path, against 0 of 320 with one pin throughout. Ranks sharing one pin, as an `srun` job's do,
are unaffected, which is why it is not urgent. Pre-existing, documented in `invariants.md` §4 and
`README.md`, and deferred by the maintainer when that cycle shipped. The direction to shape, not yet
decided, is for a pinned call to exec its own `versions/<pin>/uv` rather than going through `current`.

### Two small code gaps behind inaccurate invariants
**Seed:** [`issues/invariant-audit-gaps.md`](issues/invariant-audit-gaps.md) · `fix` · appetite small

Fallout from auditing `invariants.md` against the code during `lock-ownership-and-hold-time` planning.
`uvm_global_takes_value` misses `--cache-dir` and `--python-preference`, both of which `uv 0.12.4`
accepts before a subcommand with a separate value — measured, and `--cache-dir` is the only way left to
redirect a cache the wrapper otherwise exports. The trampoline overwrite guard tests `-x`, so an
unmarked 0644 file somebody wrote is silently replaced. Small and independent; the corresponding text
repairs are harness work and land separately.

It carried four gaps until 2026-10-27. The unguarded rename in `uvm_install` (R3) went to
`lock-simplification`, and the heartbeat's silently degrading leash (R4) is moot there because that
cycle deletes the heartbeat.

### `.claude` is a symlink, so no agent can create a worktree
**Seed:** [`issues/claude-dir-shim.md`](issues/claude-dir-shim.md) · `refactor` · appetite small

`.claude` is a committed symlink to `.agents`, and Claude Code refuses to create a worktree under a
symlinked `.claude` — a committed symlink there could redirect writes outside the repository, and it
cannot tell this one from a hostile one. An agent asking for worktree isolation dies rather than
degrading. The fix is to make `.claude/` a real directory of symlinks back into `.agents/`, which
keeps `.agents/` canonical and turns `.claude/` into the per-tool shim it actually is. The cost is
that one symlink becomes three and three can drift, so it owes a new `lint.sh` check; the existing
one covers `bin/{uv,uvx,uvm}` only. Sequenced here because it is cheap and it unblocks worktree
isolation for every cycle below it, but nothing is blocked on it — copying the tree to `/tmp` works
and is what the probes that found this did.

### The static gate's own checks are never required to be observed failing
**Seed:** [`issues/lint-checks-never-observed-failing.md`](issues/lint-checks-never-observed-failing.md) ·
`fix` · appetite small · **applied by `/uvm-harness`**, not by a lifecycle cycle

The factory requires a `verify:` gate to be watched going red before it is trusted, and applies the
same rule to the offline fixture's invariant assertions. It does not apply it to `lint.sh`'s own
checks, which are asked only to be run — a bar a check that can never fire clears perfectly. That
matters because `lint.sh` is the gate the other gates lean on, and in a repository with no test suite
it is the only standing static signal.

Confirmed present here on 2026-08-27: `uvm-harness` Step 6 asks only that `lint.sh` be run. No live
instances — no check enumerates, and none uses a GNU-only escape — but the `.agents/` script list is
hardcoded in two places, so a fourth script would be silently unchecked with the gate green. The one
confirmation step not yet run is the one that matters: break the tree once per check and watch each
go red. That is the cycle's own first task and its red state.

Originally a portable seed from porting the factory into `rcac-docs-mcp`, where two of nine rewritten
checks turned out unfireable. The `{prefix}`-placeholder form is preserved at `3229b64`.

### A curl-installable bootstrap
**Seed:** [`issues/uvm-bootstrap.md`](issues/uvm-bootstrap.md) · `feature` · appetite medium

`uvm.sh` at the repository root, installed the way uv installs itself, for the user whose site has no
module and for automation that cannot presume Lmod. Installs when absent, execs when present, and
checks the wrapper is current without putting a network round trip in the hot path. The sharp
constraint is already written at `bin/uv-manager:9-12`: never land on `~/.local/bin/uv`, and stay
opt-in rather than on default `PATH`. Follows `purge-tree-repair` because it completes the automation
story that cycle starts.

### A real test harness
**Seed:** [`issues/test-harness.md`](issues/test-harness.md) · `feature` · appetite big

The two hard parts for a shell script — mocking the network and the filesystem — are already solved by
`temp_root.sh` and the `file://` installer fixture. What is missing is a runner, a corpus of cases,
and a coverage measurement. It converts the factory's process guarantees into actual coverage, and it
now carries six regression cases that shipped or in-flight cycles owe it: R3a from the `UVM_PLATFORM`
trampoline fix, R3b from the state-directory guard, R3c from `uvm doctor`'s detection contract, R3d
for the lock's ownership and hold-time contract, R3e for the acquire-time retake, and R3f for the
break path's instance identity. It also inherits the provisioning lock's unmeasured performance
claims as R7. `tests/` and its first drive arrive ahead of this cycle, from
`lock-break-instance-identity`, so the runner has an inhabitant to be shaped around rather than a
blank directory. Sequenced below the operational gaps above only because those are live; nothing
about its value has changed.

### An onboarding guide for the factory
**Seed:** [`issues/factory-onboarding-guide.md`](issues/factory-onboarding-guide.md) · `feature` ·
appetite big

A self-contained page for a human meeting agentic engineering for the first time. Deliberately last:
written after the cycles above, it can cite real artifacts from this repository and report honestly
what the factory failed to catch, which is the only version of the document worth showing a sceptical
audience.

## Terminal records

Deferrals considered and closed **without** shipping — `declined` and `accepted-behaviour`. Listed
apart from the ordered cycles so the index above stays an index of *work*. Read one before re-filing
the thing it describes. Work that shipped leaves no entry here: the code refutes a re-filing on its
own, and `spec/{slug}/` holds the account.

*(none yet)*
