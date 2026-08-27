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
**Seed:** [`issues/lock-acquire-retake.md`](issues/lock-acquire-retake.md) · `fix` · appetite small

Shipped in 0.6.0 as a known defect, by recorded maintainer override. The owner write became fatal —
correctly, since a holder that cannot prove ownership leaks its lock for a full stale window — but a
rank whose fresh lock directory is deleted by a losing stale-breaker hits the same `die` and exits 1
with empty stdout, where the pre-0.6.0 wrapper continued. Matched A/B: zero robbed winners before,
4 of 1280 after against a planted abandoned lock, 0 of 2304 on the ordinary cold-start path. The
remedy is a bounded retake in the style of the existing absent-lock retry, keeping the `die` for a
genuine filesystem fault.

First because it is the only known rank-killer on a tagged release, and `small` because the gate
already exists and needs no concurrency harness: the failure is a deterministic property of one code
path, constructible in one process in about two seconds. Split out of
`lock-break-instance-identity`, whose R1 and R2 remain blocked on measurement that this does not
need.

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
