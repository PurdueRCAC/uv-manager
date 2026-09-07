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

### A rank robbed of its fresh lock dies instead of retaking it
**Seed:** [`issues/lock-acquire-retake.md`](issues/lock-acquire-retake.md) · `fix` · appetite small ·
**adopted** as [`spec/lock-acquire-retake/`](spec/lock-acquire-retake/GOAL.md)

In flight. Shipped in 0.6.0 as a known defect by recorded maintainer override: the owner write became
fatal — correctly — but a rank whose fresh lock directory is deleted by a losing stale-breaker hits
the same `die` and exits 1 with empty stdout, where the pre-0.6.0 wrapper continued. Matched A/B: zero
robbed winners before, 4 of 1280 after against a planted abandoned lock, 0 of 2304 on the ordinary
cold-start path.

Shaping settled six criteria and two open questions. Appetite stays **small** — it governs research
depth, not care, and the shape is already settled with a deterministic red gate in hand; the
collateral risk that sank the last three remediations to this function is answered instead by making
counter-preservation a graded criterion (R4) rather than plan-level detail. A successful retake is
**silent** (R5), matching the existing absent-lock retry, accepting knowingly that a site then gets no
signal the underlying race is firing. Whether the retake shares the `absent` counter is left to
`/uvm-plan`; R3 constrains only the observable bound and the timeout accounting.

Not merged with `lock-break-instance-identity`: closing the race would make this cycle's gate
unreachable. The committed regression test is deferred to `test-harness` R3e, landed there at
shaping.

### The break still deletes locks it did not judge, and nothing here can measure it yet
**Seed:** [`issues/lock-break-instance-identity.md`](issues/lock-break-instance-identity.md) · `fix` ·
appetite big — **R3 split out to `lock-acquire-retake`, taken first**

What `lock-ownership-and-hold-time` narrowed but did not close. A forfeiture decided from an `owner`
line read a second ago is acted on against a path, and a path is not an instance, so a losing breaker
deletes a lock a third process just won. The shipped guard re-reads `owner` before acting; that
narrows the owner-present case and is vacuous for a lock that had none. The exclusive rename is the
obvious fix and is wrong twice over: `mv -T` does not exist at the portability floor, so `mv` nests
instead of failing, and `rmdir` refusing a non-empty directory turned out to be the thing protecting
established locks.

Its R3 — the robbed winner's death — left for `lock-acquire-retake` above, needing none of the
measurement debt the rest of this seed blocks on.

R1 and R2 stay behind measurement — 320 ranks gave 5 robbed winners against 2, which is noise — so
the harness comes first and the fix follows it. Carries the lock's unmeasured performance claims and
its taken-on-trust safety properties. Sequenced above `purge-tree-repair`, which is what makes long
holds real and this defect common.

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

Sequenced below `lock-break-instance-identity` and for the same reason — a residual rate this low is
not observable from a single-process construction, so `test-harness` R3d comes first or promotion
grades the mechanism by reading. The two also interact: closing that seed's R2 removes the robbery
this rides on and makes the residue unreachable, so whichever lands first changes the case for the
other. Carries the fatal path's unqualified `rmdir` as a second defect on the same branch, pre-existing
and strictly rarer than on `main`, because whatever fixes the classifier has to decide what that
branch does.

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
gone. What remains above it are the two lock cycles — `lock-acquire-retake` and
`lock-break-instance-identity` — whose residual this cycle is what makes common.

### Three small code gaps behind inaccurate invariants
**Seed:** [`issues/invariant-audit-gaps.md`](issues/invariant-audit-gaps.md) · `fix` · appetite small

Fallout from auditing `invariants.md` against the code during `lock-ownership-and-hold-time` planning.
`uvm_global_takes_value` misses `--cache-dir` and `--python-preference`, both of which `uv 0.12.4`
accepts before a subcommand with a separate value — measured, and `--cache-dir` is the only way left to
redirect a cache the wrapper otherwise exports. The trampoline overwrite guard tests `-x`, so an
unmarked 0644 file somebody wrote is silently replaced. The rename in `uvm_install` is unguarded and
leaves a `.incoming.` directory nothing collects. Small and independent; the corresponding text
repairs are harness work and land separately. Sequenced after `purge-tree-repair` because R3 may fold
into it.

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
now carries four regression cases that shipped cycles owe it: R3a from the `UVM_PLATFORM` trampoline
fix, R3b from the state-directory guard, R3c from `uvm doctor`'s detection contract, and R3d for the
lock's ownership and hold-time contract. Sequenced below the operational gaps above only because
those are live; nothing about its value has changed.

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
