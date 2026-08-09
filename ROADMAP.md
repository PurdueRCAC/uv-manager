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

### A real test harness
**Seed:** [`issues/test-harness.md`](issues/test-harness.md) · `feature` · appetite big

The two hard parts for a shell script — mocking the network and the filesystem — are already solved by
`temp_root.sh` and the `file://` installer fixture. What is missing is a runner, a corpus of cases,
and a coverage measurement. Highest-value cycle on this list: it converts the factory's process
guarantees into actual coverage.

### Trampolines ignore `UVM_PLATFORM`
**Seed:** [`issues/trampoline-ignores-platform-override.md`](issues/trampoline-ignores-platform-override.md)
· `fix` · appetite small · **adopted** as
[`spec/trampoline-ignores-platform-override/`](spec/trampoline-ignores-platform-override/GOAL.md)

A real, reproduced correctness defect: the wrapper honors the platform override, the generated
trampolines do not, so every tool exits 127 at any site that follows the documented advice in
`etc/uv-manager.conf.example`. Pre-existing. Shaping settled the open design question — the trampoline
resolves the invoker's `${UVM_PLATFORM:-$(uname -m)}` at exec time, the same expression `uvm_init`
uses, because baking in the generating key would break the heterogeneous case trampolines exist for.
Taken **ahead** of the test harness rather than after it, against the sequencing recorded here: the
defect is live, and the drives that reproduce it stand in for the regression test until a runner
exists. The harness cycle must cover this case.

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
