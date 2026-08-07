---
status: unshaped
kind: feature
appetite: big
lane: public
---

# A real test harness: measure the surface, catch regressions

## Problem

There is no test suite. Every change so far has been verified ad hoc, and the factory's `verify:`
gates currently stand in for coverage — which is process compensating for the absence of tests, not a
substitute for them. Two consequences: a regression in a path nobody thought to re-drive ships
silently, and there is no measurement of how much of the wrapper's behavior is exercised at all.

The two things that looked hard for a bash script — mocking the network and mocking the filesystem —
turn out not to be, and the groundwork already exists in `.agents/factory/bin/`:

- **Filesystem.** The wrapper's entire state tree hangs off one variable. `temp_root.sh` points it at
  a temp directory, scrubs every inherited `UV_*`, `UVM_*` and scratch variable, and removes it on
  exit. No mocking layer is needed; the design already has the seam.
- **Network.** `uvm_fetch` uses `curl`, and `curl` speaks `file://`. Pointing `UVM_INSTALL_URL`
  at a local directory drives the *whole* provisioning path — lock, fetch, install, version detection,
  atomic rename, `current` swap — with no egress. `.agents/factory/fixtures/uv-install/install.sh` is
  that fixture, and it already asserts the installer-environment scrub (`invariants.md` §6) on every
  run.
- **Architecture.** `UVM_PLATFORM` lets one sandbox hold several architectures, so the
  heterogeneous-cluster behavior the project exists for is reachable on a laptop. This is how the
  trampoline defect in `issues/trampoline-ignores-platform-override.md` was found.

What is missing is a runner, a corpus of cases, and a coverage measurement.

## Why it was deferred

The sandbox and the fixture were built as part of the harness port because the factory could not
function without them. Turning them into a test suite is a separate, larger piece of work with real
design choices, and it deserves its own cycle.

## Outcome / vision

`make test` — or one script — runs a suite in a few seconds, covers every subcommand and every
documented failure path, is runnable in CI on Linux and macOS, and reports which parts of the wrapper
were never executed.

## Sketch of the acceptance criteria

- **R1** — The suite SHALL run with no network access and no writes outside a temp directory.
- **R2** — The suite SHALL cover every `uv-manager` subcommand, both dispatch modes (`uv`, `uvx`), the
  `self update` interception, and the `tool`/`python` non-exec path.
- **R3** — The suite SHALL cover the documented failure paths: no state root resolvable, no egress,
  a wrong-architecture binary, a stale lock, a lock timeout, and a partially purged tree.
- **R4** — The suite SHALL assert post-conditions on the state tree, not merely exit status.
- **R5** — The suite SHALL run on bash 3.2 and on bash 5, and SHALL run in CI on both Linux and macOS.
- **R6** — The suite SHALL report a coverage measurement over `bin/uv-manager`.

## Notes

Open questions for shaping, each with a real trade-off:

- **Runner.** `bats-core` is the standard choice and is readable, but it is a dependency a cluster
  operator may not have. A plain-`sh` runner has no dependency and no ecosystem. Note that `bats` can
  be vendored as a git submodule, and that `uvx` can supply tools without a system install — the same
  trick `lint.sh` uses for `shellcheck`.
- **Coverage.** `kcov` measures bash coverage but is Linux-only and awkward to install; `bashcov`
  needs Ruby. A cheaper approximation is a `DEBUG` trap logging executed line numbers, which needs no
  dependency and is good enough to answer "which functions were never entered".
- **Concurrency.** The provisioning lock is the highest-risk region and the hardest to test. Two
  background invocations racing on one sandbox root is the minimum; asserting that exactly one
  installs, and that the other waits rather than proceeding, is the point.
- **Signal handling.** The `INT`/`TERM` lock release matters and is testable: start a provisioning
  run against a fixture installer that sleeps, kill it, assert the lock directory is gone.
- **Relationship to the factory.** The suite should become the `verify:` command that phases use, and
  `lint.sh` should probably grow a `--with-tests` mode or be joined by a sibling. Decide whether the
  suite lives under `.agents/factory/` (harness) or at `tests/` (product). It is product.
- Found by: the maintainer, ahead of the third post-harness cycle.
