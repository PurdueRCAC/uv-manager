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

### Repairing a purged tree in place, at job scale
**Seed:** [`issues/purge-resilient-run.md`](issues/purge-resilient-run.md) · `feature` · appetite big ·
**adopted** as [`spec/purge-resilient-run/`](spec/purge-resilient-run/GOAL.md)

`uvm doctor` finds a partially purged tree and then prints instructions for a human, which is no use
to a compute node at 03:00 or to automation. Shaping settled the entry point as an opt-in knob,
`UVM_REPAIR`, on the existing dispatch rather than the `uvm run` subcommand the request arrived as —
automation runs `uvx foo` and will not be rewritten to opt in. When set and damage is found, one
process repairs the tree to `doctor`'s standard under the `mkdir` lock while the rest wait. The same
cycle owns the cost side, because the sentinel that makes the unconditional six-directory `mkdir -p`
conditional is the same marker a bounded integrity check needs; `doctor`'s walk stays the exhaustive
authority, since a bounded check cannot promise its coverage.

### A curl-installable bootstrap
**Seed:** [`issues/uvm-bootstrap.md`](issues/uvm-bootstrap.md) · `feature` · appetite medium

`uvm.sh` at the repository root, installed the way uv installs itself, for the user whose site has no
module and for automation that cannot presume Lmod. Installs when absent, execs when present, and
checks the wrapper is current without putting a network round trip in the hot path. The sharp
constraint is already written at `bin/uv-manager:9-12`: never land on `~/.local/bin/uv`, and stay
opt-in rather than on default `PATH`. Second because it completes the automation story the cycle above
starts.

### A real test harness
**Seed:** [`issues/test-harness.md`](issues/test-harness.md) · `feature` · appetite big

The two hard parts for a shell script — mocking the network and the filesystem — are already solved by
`temp_root.sh` and the `file://` installer fixture. What is missing is a runner, a corpus of cases,
and a coverage measurement. It converts the factory's process guarantees into actual coverage, and it
now also owes R3a, the trampoline regression case the shipped `UVM_PLATFORM` fix left it. Sequenced
below the two cycles above only because those are live operational gaps; nothing about its value has
changed.

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
