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

### The break still deletes locks it did not judge, and nothing here can measure it yet
**Seed:** [`issues/lock-break-instance-identity.md`](issues/lock-break-instance-identity.md) · `fix` ·
appetite big · **adopted** as [`spec/lock-break-instance-identity/`](spec/lock-break-instance-identity/GOAL.md)

What `lock-ownership-and-hold-time` narrowed but did not close. A forfeiture decided from an `owner`
line read a second ago is acted on against a path, and a path is not an instance, so a losing breaker
deletes a lock a third process just won. The shipped guard re-reads `owner` before acting; that
narrows the owner-present case and is vacuous for a lock that had none. The exclusive rename is the
obvious fix and is wrong twice over: `mv -T` does not exist at the portability floor, so `mv` nests
instead of failing, and `rmdir` refusing a non-empty directory turned out to be the thing protecting
established locks. Do not re-propose it without reading the seed.

**In flight.** Shaping settled the one question the seed left open: the measurement and the fix are
one cycle, not two. The drive lands at `tests/` — where `test-harness` had already decided the suite
belongs — scoped to a lock race and explicitly not the runner, sized by the arithmetic
`lock-ownership-and-hold-time` established and never applied, with separate assertions for a robbed
lock and for two installers so a red gate can name what it caught. The seed's R4 and R6 came along;
its R5 went to `invariant-audit-gaps` and its performance debt to `test-harness`, since this file's
entry and its seed are both deleted when the cycle lands.

Sequenced above `purge-tree-repair`, which is what makes long holds real and this defect common.

### The owner write is classified by the directory a moment later, not by the errno
**Seed:** [`issues/lock-owner-write-errno.md`](issues/lock-owner-write-errno.md) · `fix` ·
appetite small — **blocked on measurement**

What `lock-acquire-retake` narrowed but did not close. The retake decides between a lost race and a
filesystem fault by testing whether the lock directory is still standing, because a failed redirect
leaves the shell no errno a branch can read. The write fails at one instant and the test runs at the
next, so a rank that wins `mkdir` at that path in between turns a robbed winner back into a fatal
fault. Recorded PLAUSIBLE by that cycle's review, not CONFIRMED: the mechanism is real by reading and
by an out-of-contract construction, but 5760 ranks of 64-way contention found none of it, with
instrumentation catching three real robberies and three retakes. The same harness failed `main` at 1
in 768, so the construction reaches the race.

Sequenced below `lock-break-instance-identity`, which went first and is now in flight — so the drive
this seed needs arrives with that cycle rather than with `test-harness`, and the question to settle
before promoting is whether the robbery this rides on is still reachable once that cycle lands. If it
is not, this becomes a terminal record and the second defect on the same branch is the only live half:
the fatal path's unqualified `rmdir`, pre-existing and strictly rarer than on `main`, which whatever
fixes the classifier has to decide what to do about.

### A pinned rank that loses the provisioning race runs whatever version it finds
**Seed:** [`issues/pin-early-out-selects-nothing.md`](issues/pin-early-out-selects-nothing.md) ·
`fix` · appetite small

`uvm_install` has three paths that return success and only two of them select the version. The lock's
early-out at `bin/uv-manager:570` returns 0 without the `uvm_point_current` that `:566` and `:574`
both perform, and the window it samples is the one line between the rename at `:618` and the swap at
`:620`. Unreachable without a pin, because `uvm_have ""` tests `current/uv` and so can only be true
when nothing needs repairing — 2962 unpinned early-outs measured harmless. With a pin, 31 of 32
concurrent ranks asking for 6.6.6 on a warm tree executed 9.9.9 at rc 0 with nothing on stderr, which
contradicts §4's "a pin is authoritative" and is wrong output rather than a failure. A prior review
recorded this line as self-correcting; the tree self-corrects, the invocation does not.

Sequenced here because it is independent of the lock cycles above it despite living one line from
one — the lock's early-out is correct, and the defect is that `uvm_install` reads "another process
satisfied this" as "done" rather than "satisfied, still unselected". The repair is probably a status
the caller acts on rather than a fourth copy of the same two lines, which is why it is not a
one-liner.

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
gone. What remains above it are the two lock cycles — `lock-break-instance-identity` and
`lock-owner-write-errno` — whose residual this cycle is what makes common.

### Four small code gaps behind inaccurate invariants
**Seed:** [`issues/invariant-audit-gaps.md`](issues/invariant-audit-gaps.md) · `fix` · appetite small

Fallout from auditing `invariants.md` against the code during `lock-ownership-and-hold-time` planning.
`uvm_global_takes_value` misses `--cache-dir` and `--python-preference`, both of which `uv 0.12.4`
accepts before a subcommand with a separate value — measured, and `--cache-dir` is the only way left to
redirect a cache the wrapper otherwise exports. The trampoline overwrite guard tests `-x`, so an
unmarked 0644 file somebody wrote is silently replaced. The rename in `uvm_install` is unguarded and
leaves a `.incoming.` directory nothing collects. A fourth arrived from `lock-break-instance-identity`
shaping: the heartbeat's leash silently becomes bare `kill -0` wherever `ps -o lstart=` cannot answer,
which is the immortal-lock defect returning, and nothing — invariant or wrapper — concedes it. Small
and independent; the corresponding text repairs are harness work and land separately. Sequenced after
`purge-tree-repair` because R3 may fold into it. R4 is the loosest of the four and the only one that
may want a new output surface.

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
