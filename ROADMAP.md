# Roadmap

The ordered index of future cycles. One entry per `issues/{slug}.md`, newest work at the bottom of
each section. Each **Seed** points at the pre-shaped deferral that holds the evidence; `/uvm-feature`
promotes one into a `spec/{slug}/GOAL.md`, and that promotion is where appetite, non-goals and the
R-IDs get negotiated. An entry here is a candidate, not a commitment.

Unremediated security findings are indexed separately in `.security/ROADMAP.md`, which is gitignored.
See `AGENTS.md` for why.

---

## Queued

### 1. Rename the environment prefix to `UVM_*`
**Seed:** [`issues/uvm-env-prefix.md`](issues/uvm-env-prefix.md) · `refactor` · appetite small ·
**adopted** as [`spec/uvm-env-prefix/`](spec/uvm-env-prefix/GOAL.md)

`UV_MANAGER_*` sits inside `uv`'s own namespace, so a reader cannot tell which names Astral honors and
which the wrapper invented. `UVM_*` is unambiguously ours. Six variables, 61 occurrences across four
files. The compatibility question is settled: clean break, no shim, because nothing is deployed.

### 2. Prose pass over every comment and document
**Seed:** [`issues/prose-and-comment-pass.md`](issues/prose-and-comment-pass.md) · `refactor` ·
appetite small

Apply `AGENTS.md` § *Prose and comments* to the text that already exists. An audit for drift and
length, not a rewrite — the guard is that the total comment and documentation line count must not
grow. Follows the rename, so it is not editing sentences that are about to change.

### 3. A real test harness
**Seed:** [`issues/test-harness.md`](issues/test-harness.md) · `feature` · appetite big

The two hard parts for a shell script — mocking the network and the filesystem — are already solved by
`temp_root.sh` and the `file://` installer fixture. What is missing is a runner, a corpus of cases,
and a coverage measurement. Highest-value cycle of the three: it converts the factory's process
guarantees into actual coverage.

### 4. Trampolines ignore `UV_MANAGER_PLATFORM`
**Seed:** [`issues/trampoline-ignores-platform-override.md`](issues/trampoline-ignores-platform-override.md)
· `fix` · appetite small

A real, reproduced correctness defect: the wrapper honors the platform override, the generated
trampolines do not, so every tool exits 127 at any site that follows the documented advice in
`etc/uv-manager.conf.example`. Pre-existing. Deliberately sequenced **after** the test harness so the
fix lands with a regression test — this is exactly the class of defect that reappears. It also touches
the same line as cycle 1, so doing it after the rename avoids a third edit there.

### 5. An onboarding guide for the factory
**Seed:** [`issues/factory-onboarding-guide.md`](issues/factory-onboarding-guide.md) · `feature` ·
appetite big

A self-contained page for a human meeting agentic engineering for the first time. Deliberately last:
written after the cycles above, it can cite real artifacts from this repository and report honestly
what the factory failed to catch, which is the only version of the document worth showing a sceptical
audience.

## Terminal records

Deferrals that were considered and closed. Listed apart from the ordered cycles so the index above
stays an index of *work*. Read one before re-filing the thing it describes.

*(none yet)*
