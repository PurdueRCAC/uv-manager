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

### Prose pass over every comment and document
**Seed:** [`issues/prose-and-comment-pass.md`](issues/prose-and-comment-pass.md) · `refactor` ·
appetite small · **adopted** as [`spec/prose-and-comment-pass/`](spec/prose-and-comment-pass/GOAL.md)

Apply `AGENTS.md` § *Prose and comments* to the text that already exists. An audit for drift and
length, not a rewrite — a census of the banned vocabulary across the in-scope files returns 13 hits.
Scope is settled: all 570 lines of `README.md` are in, `.agents/` is out, and the guard is that the
four files' aggregate 1724 lines must not grow.

### A real test harness
**Seed:** [`issues/test-harness.md`](issues/test-harness.md) · `feature` · appetite big

The two hard parts for a shell script — mocking the network and the filesystem — are already solved by
`temp_root.sh` and the `file://` installer fixture. What is missing is a runner, a corpus of cases,
and a coverage measurement. Highest-value cycle on this list: it converts the factory's process
guarantees into actual coverage.

### Trampolines ignore `UVM_PLATFORM`
**Seed:** [`issues/trampoline-ignores-platform-override.md`](issues/trampoline-ignores-platform-override.md)
· `fix` · appetite small

A real, reproduced correctness defect: the wrapper honors the platform override, the generated
trampolines do not, so every tool exits 127 at any site that follows the documented advice in
`etc/uv-manager.conf.example`. Pre-existing. Deliberately sequenced **after** the test harness so the
fix lands with a regression test — this is exactly the class of defect that reappears. It touches the
same line as the `UVM_*` rename, which has already landed.

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
