# GOAL — Trampolines resolve the platform key the wrapper actually uses

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** trampoline-ignores-platform-override
- **kind:** fix
- **appetite:** small

## Problem

`UVM_PLATFORM` is the documented way for a site to split its state tree more finely than `uname -m`
does — glibc skew between login and compute images, musl, x86-64 microarchitecture levels.
`etc/uv-manager.conf.example:80` gives a worked example, `README.md:537` lists it, and the help
heredoc at `bin/uv-manager:767` advertises it. The wrapper honors it: `uvm_init` resolves
`${UVM_PLATFORM:-$(uname -m)}` (`bin/uv-manager:145`). The trampoline it generates does not — the
`/bin/sh` body hardcodes `a=$(uname -m)` (`bin/uv-manager:478`).

At any site that takes the documented advice, the two disagree on every invocation. `uv tool install
ruff` puts the executable under the override key; the trampoline on `PATH` looks under `uname -m`,
finds nothing, and exits 127 with the "not installed for architecture" message naming an architecture
the operator never configured — for a tool that is installed and one directory away. The union-of-names
scan makes this deterministic rather than intermittent: `uvm_trampolines` walks
`"${uvm_base}"/*/bin/shims` and so generates a trampoline for a name the generated body can then never
resolve. The result is that **every** tool a user installs is broken, and the diagnostic points away
from the cause.

The audience is a site operator standing up `uv-manager` for the first time, following the
configuration example as written. They get a wrapper whose own documentation is a trap. Purdue's
deployments use the default `uname -m`, where the two expressions agree and nothing is wrong, so this
has never been observed in production — it was found in the factory sandbox while validating
`temp_root.sh --arch` against the real script. **Pre-existing**: present since the trampoline
mechanism was introduced.

## Outcome / vision

A site sets `UVM_PLATFORM` and everything works. Tools installed under that key are found by the
trampolines on `PATH`; when one genuinely is not installed for the executing node, the message names
the key the trampoline actually searched. The neutral trampoline directory keeps the property it
exists for: one `PATH` entry, evaluated on the login node, still correct on a compute node of a
different architecture.

## Acceptance criteria (the contract)

Unless stated otherwise, each criterion is checked by a sandbox drive under
`.agents/factory/bin/temp_root.sh`, which exports `UVM_PLATFORM` when given `--arch`.

- **R1** — WHILE `UVM_PLATFORM` is set in the invoking environment, WHEN a generated trampoline is
  invoked for a tool installed under that platform key, the trampoline SHALL exec that executable and
  propagate its exit status. *Checked by* the seed's own reproduction: under
  `temp_root.sh --offline --arch x86_64-glibc2.28`, plant an executable shim at
  `$UVM_ROOT/x86_64-glibc2.28/bin/shims/ruff`, run `uvm trampolines`, then invoke
  `$UVM_ROOT/bin/ruff`. It SHALL produce the shim's output and exit 0. On `main` this exits 127.

- **R2** — IF a trampoline cannot resolve its target under the platform key in effect, THEN it SHALL
  exit 127 and name **that key** on stderr — not `uname -m`, when the two differ. *Checked by* the
  same sandbox with the shim removed from the override tree: stderr SHALL name
  `x86_64-glibc2.28`. On `main` it names the host's `uname -m`.

- **R3** — WHERE `UVM_PLATFORM` is unset, trampoline resolution SHALL be unchanged. *Checked by* a
  drive with no `--arch`: a planted shim under `$(uname -m)` SHALL still be found, and the
  not-installed message SHALL still name `$(uname -m)`.

- **R4** — A single trampoline SHALL remain correct across nodes whose platform keys differ within one
  `UVM_ROOT`: no architecture-bearing value is written into the generated body, and the key is
  resolved at exec time from the environment of the process invoking it. *Checked by* one `--keep`
  sandbox holding shims under two keys, invoking the same trampoline under two `--arch` values and
  asserting each execs its own tree's shim; **and** by `grep` over a generated trampoline asserting
  neither key appears as a literal.

- **R5** — The platform-key expression in the generated trampoline SHALL be identical to the one in
  `uvm_init`, and both sites SHALL carry a comment recording that they must move together and the
  failure that follows when they do not. *Graded by a reviewer* against the two sites in
  `bin/uv-manager` and `AGENTS.md` § *Prose and comments* — there is no command that decides whether a
  comment earns its place.

- **R6** — Behavior outside trampoline resolution SHALL be unchanged, and the trampoline SHALL remain
  a `/bin/sh` script. *Checked by* `.agents/factory/bin/lint.sh` passing, and by
  `temp_root.sh uvm status`, `temp_root.sh --offline uv --version` and
  `temp_root.sh --offline --arch aarch64 uvm status` reaching the same post-conditions they reach on
  `main` — same exit status, same `current` target, same version string.

## Non-goals (no-gos)

- **No committed regression test.** `ROADMAP.md` sequences this cycle after `issues/test-harness.md`
  precisely so the fix could land with one, and that harness has not been built. Shipping the fix now
  is a deliberate reordering: the defect is live, the verification above is a drive that reproduces it
  exactly, and inventing a one-off test script here would pre-empt the harness cycle's decisions about
  runner and layout. This defect is a case that harness must cover — record it there, do not build a
  runner here.
- **No single-sourcing of the platform-key expression.** Bash and the generated `/bin/sh` share no
  code, so removing the duplication means interpolating a quoted string into the heredoc — indirection
  an operator reading the generated file has to unpick, to prevent a two-line divergence. R5's comment
  is the guard this appetite buys; a structural one is a test.
- **No fallback search.** The trampoline resolves one key. Trying the override and then `uname -m`
  would paper over a misconfigured site and hide it from the operator who could fix it.
- **No change to how `uvm_init` resolves the key**, to the set of variables the wrapper exports, or to
  the union-of-names scan. The wrapper's behavior is correct; the generated body is what disagrees
  with it.
- **No new configuration.** No knob to select trampoline resolution behavior.

## Clarifications

- **Q:** Should the trampoline honor `UVM_PLATFORM` from the environment that *invokes* it, or from
  the environment that *generated* it? — **A:** The invoker's, resolving the same
  `${UVM_PLATFORM:-$(uname -m)}` expression `uvm_init` uses. Baking the generating key in makes the
  trampoline architecture-bearing and breaks the heterogeneous case trampolines exist for: a body
  written on an `x86_64` login node would send an `aarch64` compute node to the wrong tree
  (resolved 2026-08-07, and constrained by `invariants.md` §1 and §9).
- **Q:** `ROADMAP.md` defers this cycle until after the test harness. Should the promotion wait? —
  **A:** No. Ship the fix now, verified by the drives above, and record the deferred regression test
  as a non-goal and as a case the harness cycle must cover (resolved 2026-08-07).
- **Q:** Does the same-commit rule require a documentation change? — **A:** No line becomes stale.
  `README.md:349` and `:537`, `etc/uv-manager.conf.example:80` and the help heredoc all describe
  `UVM_PLATFORM` as the architecture-key override, which is what the fixed wrapper does; today they
  describe behavior the script does not deliver. `/uvm-plan` SHALL confirm this rather than assume it
  (resolved 2026-08-07).

## Related materials

- Seed: [`issues/trampoline-ignores-platform-override.md`](../../issues/trampoline-ignores-platform-override.md)
- `.agents/factory/invariants.md` §1 (architecture partitioning — highest blast radius) and §9
  (trampolines). `uvm_trampolines` is a high-risk region in `AGENTS.md`: it writes into a directory on
  the user's `PATH`.
- The two disagreeing sites: `bin/uv-manager:145` (`uvm_init`) and `bin/uv-manager:478` (the
  trampoline heredoc).
- The documentation that makes this reachable: `etc/uv-manager.conf.example:80`, `README.md:349`.
