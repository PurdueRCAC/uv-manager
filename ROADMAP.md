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

### `uvm doctor` reports OK on the damage it exists to find
**Seed:** [`issues/doctor-detection-gaps.md`](issues/doctor-detection-gaps.md) · `fix` · appetite medium

Four pre-existing defects, each reproduced with real uv. Doctor is blind when a purge takes
`dist-info/RECORD` — the coldest file in a distribution and an early casualty — so it prints `OK` on a
gutted environment. A `dist-info` with no `RECORD` is not treated as damage. Advisory warnings set the
exit status, so one receipt-less tool makes doctor exit 1 forever on a tree that works. And two of the
three remedies it prints do not repair, while the third re-resolves latest and repoints `current` at a
pinned site. Taken next because doctor is the command every other document points a user at, and
because the repair cycle needs it as a detector.

### The provisioning lock can be released by a process that does not hold it
**Seed:** [`issues/lock-ownership-and-hold-time.md`](issues/lock-ownership-and-hold-time.md) · `fix` ·
appetite medium

`uvm_unlock` matches on path, never on ownership, so once a waiter breaks a lock as stale the original
holder's unlock removes the *new* holder's directory — captured live, mutual exclusion gone. Nothing
enforces `UVM_LOCK_TIMEOUT < UVM_LOCK_STALE`, and the inverted order makes a process break its own
lock and exit 0. Latent on `main`, because every path needs a holder outliving the 600 s stale age,
and a download rarely does. Sequenced here because a rebuild does, so the repair cycle would otherwise
inherit a concurrency bug it did not create.

### `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`
**Seed:** [`issues/purge-tree-repair.md`](issues/purge-tree-repair.md) · `feature` · appetite big

The repair half, re-shaped around what research found. The knob stays: it fires inside `uv`/`uvx`
after the platform key is resolved on the executing node, which makes it architecture-correct by
construction where a bring-up subcommand — proposed and rejected during planning — would repair the
login node's tree and leave the job's untouched. What changed is the contract. Detection has a floor
no budget removes, since a deleted distribution and every managed interpreter leave no manifest, so
the criteria must name what is caught and concede the rest. Cost is handled by a verification receipt
rather than an integrity stamp. Depends on the two fixes above.

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
now carries two regression cases that shipped cycles owe it: R3a from the `UVM_PLATFORM` trampoline
fix, and R3b from the state-directory guard. Sequenced below the operational gaps above only because
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
