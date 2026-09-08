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
  trampoline defect fixed in [`spec/trampoline-ignores-platform-override/`](../spec/trampoline-ignores-platform-override/GOAL.md)
  was found.

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
- **R3a** — The suite SHALL cover a generated trampoline resolving its target WHILE `UVM_PLATFORM` is
  set, asserting it execs under the override rather than under `uname -m`. This case is owed: the
  trampoline cycle shipped its fix without a regression test on the written condition that the harness
  cover it.
- **R3b** — The suite SHALL cover the state-directory guard in `uvm_export_env` with a counting
  `mkdir` stub first on `PATH`: a warm invocation against an intact tree SHALL invoke it zero times,
  and the same invocation after one state directory is removed SHALL invoke it and leave that
  directory at mode `700`. Owed on the same terms as R3a.
- **R3c** — The suite SHALL cover `uvm doctor`'s detection contract on a damaged tree: a `*.dist-info`
  whose `RECORD` has been removed reported as damage with exit 1; a tool directory missing
  `pyvenv.cfg` reported with the no-safe-repair wording; a tree whose only finding is a receipt-less
  tool directory exiting 0; and `uvm doctor | head -1` writing nothing matching `write error` to
  stderr. Owed on the same terms as R3a and R3b.
- **R3d** — The suite SHALL cover the lock's ownership and hold-time contract: a release attempted
  against a lock whose `owner` names another process SHALL leave that lock standing; a live holder
  SHALL NOT be breakable as stale however long it holds; an inverted
  `UVM_LOCK_TIMEOUT`/`UVM_LOCK_STALE` SHALL be refused; and no lock SHALL survive an `exec`. Owed on
  the same terms as R3a through R3c, and the sharpest of the four — R3 above already names a stale
  lock and a lock timeout, but those are single-process cases, and every defect here needs two
  processes racing on one tree.
- **R3e** — The suite SHALL cover the acquire-time retake: a wrapper that has won `mkdir` and whose
  `owner` write then fails because the directory was removed underneath it SHALL reacquire and exit
  0, while the same write failing `EACCES` SHALL still exit non-zero carrying its errno. Owed by
  `lock-acquire-retake`, whose `GOAL.md` § *Non-goals* defers the committed test here. Unlike R3d
  this needs **one** process: the state is constructible with a `mkdir` shim first on `PATH` inside
  `temp_root.sh --offline`, which makes it the cheapest of the five and a reasonable one to land
  first. It is also the counterexample to R3d's premise that every defect in this area needs two
  processes racing on one tree — the *reachability* of this one does, its *handling* does not, and
  the handling is what a regression test pins.
- **R3f** — The suite SHALL cover the break path's instance identity: a break decided against a lock
  instance that no longer exists SHALL leave whatever occupies that path standing, including when the
  judged instance recorded no `owner` file, and a break that is then denied SHALL leave the `owner`
  file it found. `lock-break-instance-identity` lands the concurrency drive this case needs at
  `tests/`, so unlike R3a through R3e this one arrives with its apparatus already committed — what is
  owed here is folding it into the runner rather than writing it.
- **R4** — The suite SHALL assert post-conditions on the state tree, not merely exit status.
- **R5** — The suite SHALL run on bash 3.2 and on bash 5, and SHALL run in CI on both Linux and macOS.
- **R6** — The suite SHALL report a coverage measurement over `bin/uv-manager`.
- **R7** — The suite SHALL settle the provisioning lock's performance claims with numbers rather than
  arguments: the wrapper's ~5 ms hot-path budget, which no timing drive on a shared machine currently
  resolves and which `spec/lock-ownership-and-hold-time/GOAL.md` R4 delegates to a reviewer reading
  the implementation; the one `ps` fork `uvm_proc_start` adds per heartbeat beat; and the one `sleep`
  each acquisition orphans for up to a beat, because `uvm_unlock` kills the refresher subshell and not
  the `sleep` it is blocked in. A location-controlled A/B measured ~0.6 ms of drift between the
  pre-0.6.0 wrapper and the branch, ~0.2 ms of it parse cost from the file growing 37,184 → 49,376
  bytes, mostly comments — a real number nobody can currently act on. The fork counts are reachable
  with the counting-stub trick R3b uses; the `pids.max` interaction that makes the orphan matter is
  **not** reachable here, and this criterion concedes it rather than pretending otherwise. Owed by
  [`spec/lock-break-instance-identity/GOAL.md`](../spec/lock-break-instance-identity/GOAL.md)
  § *Non-goals*, which declines it on the grounds that a timing A/B is a different instrument from a
  race detector.

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
  suite lives under `.agents/factory/` (harness) or at `tests/` (product). It is product — and
  `lock-break-instance-identity` acts on that answer ahead of this cycle, landing the first drive at
  `tests/`. So `tests/` and one case in it exist before this cycle starts, and the runner has a
  first inhabitant to be shaped around instead of a blank directory.
- **R3a is inherited debt, not a new idea.** `spec/trampoline-ignores-platform-override/GOAL.md`
  § *Non-goals* made "no committed regression test" conditional on this suite covering the case. That
  condition was written down in one place — the roadmap entry the shipped fix then retired — so it is
  restated here, where the cycle that owes it will read it.
- **R3b arrived the same way**, from `spec/purge-resilient-run/GOAL.md` § *Non-goals*, and was again
  recorded only where the retirement would have taken it. Two cycles have now discharged "no committed
  regression test" by naming this seed; a third should assume the obligation is not written down until
  it is written down here. What the stub cannot see is worth knowing before writing the case: it
  counts `mkdir` executions, so it is blind to whether the guard sits outside the `umask 077`
  subshell. A guard moved inside keeps the fork and about a third of the saving, and the count is
  unchanged. That placement needs an assertion of its own — timing, or a structural check.
- **R3c is the third such debt**, from `spec/doctor-detection-gaps/GOAL.md` § *Non-goals*. Two of its
  criteria resist the obvious test and the shape matters more than the case list. Its R5 asserts the
  rewritten `RECORD` walk reaches the verdict `git show main:bin/uv-manager` reaches, which is a
  moving reference: once the fix lands on `main` that comparison is vacuous, so the suite must pin a
  fixture tree with an expected verdict rather than diff against a branch. Its R6 asserts doctor takes
  no lock, and a before/after manifest of paths, mtimes and hashes cannot see a lock directory created
  and removed inside the run — that needs a counting stub on `PATH`, the R3b trick, not a tree
  comparison.
- Found by: the maintainer, ahead of the third post-harness cycle.
