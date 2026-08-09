# GOAL — Repair a purged tree in place, at job scale

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** purge-resilient-run
- **kind:** feature
- **appetite:** big

## Problem

A scratch purge is per-file on access time, so it removes a tool environment piecemeal while uv still
records it as installed. The banner above `uvm_doctor` (`bin/uv-manager:644`) states the consequence:
uv "performs no integrity check on an environment it believes is installed; it will exec a half-deleted
venv and produce an ImportError." `uvm_doctor` (`:648`) finds exactly that damage, walking every
`dist-info/RECORD` and stating every file it lists (`:689`). What it does with the answer is print
three commands for a human to run (`:729`). Nobody reads that from a compute node at 03:00, and
automation cannot act on it at all. Nothing else covers the gap: `uvm_ensure_uv` (`:370`) guards only
the uv binary, because `uvm_have` (`:265`) is one `-x` test on `${uvm_current}/uv`, and the
unconditional `mkdir -p` in `uvm_export_env` (`:405`) restores the *shape* of the tree, not its
contents. A user whose job has not run in thirty days gets an ImportError, not a re-provision.

The cost side is the same code path and pulls the other way. Measured in the factory sandbox, warm
tree, 50 invocations, on local SSD: `uv --version` through the wrapper costs 9.6 ms against 3.1 ms for
the real uv invoked directly, and the six-directory `mkdir -p` — with all six directories already
present — is 2.4 ms of that. About a quarter of the wrapper's overhead accomplishes nothing on a warm
tree. The comment at `:402` defends it as "a handful of metadata operations", which is true of one
process; ten thousand ranks starting `uvx` at once issue those six operations ten thousand times
against a single metadata server, in a burst, and local SSD is the optimistic case for a number that
is charged to a parallel filesystem. Any integrity check strong enough to catch a partial purge is far
more expensive than the `mkdir -p` whose cost is already in question — doctor's walk is proportional
to the number of installed files — so "check before running" cannot be bolted onto the exec path as it
stands.

The audience is a user inside a batch job, or the automation that submitted it. Both have already been
charged for the allocation by the time the ImportError appears, and neither is in a position to read
remediation instructions and type them.

## Outcome / vision

A site that opts in gets a wrapper that notices its own tree is damaged, repairs it exactly once
across however many ranks, and proceeds to the command the user actually asked for. Ranks that did not
win the repair wait for it rather than each re-deriving the same conclusion against the same metadata
server. A site that does not opt in gets today's behavior, minus the metadata the wrapper currently
spends on every invocation to no effect: the intact hot path gets cheaper whether or not repair is
enabled.

## Acceptance criteria (the contract)

Unless stated otherwise, each criterion is checked by a sandbox drive under
`.agents/factory/bin/temp_root.sh`, asserting a post-condition — an exit status, a path, a line on
stderr, a `uvm doctor` verdict. Two criteria name a substitute where a drive cannot reach.

- **R1** — WHILE the wrapper's state directories all exist, an invocation SHALL NOT issue the
  six-directory `mkdir -p`; WHEN any of them is missing, it SHALL still be created, under `umask 077`.
  *Checked by* a counting `mkdir` stub placed first on `PATH` inside the sandbox: a warm drive of
  `uv --version` on an intact tree SHALL invoke it zero times; the same drive with one state directory
  removed SHALL invoke it and leave the tree whole again, with mode `700`. *Reported alongside* — the
  seed's own measurement, 50 warm invocations before and after, so the saving is a number in `PLAN.md`
  rather than an assertion.

- **R2** — WHILE `UVM_REPAIR` is unset, the wrapper SHALL run no integrity check and SHALL attempt no
  repair. *Checked by* a drive against a deliberately damaged tree with the variable unset: the
  wrapper SHALL exec as it does on `main`, SHALL create no lock directory, and SHALL write nothing
  additional to stderr.

- **R3** — WHERE `UVM_REPAIR` is set, the wrapper SHALL detect a tool environment or python install
  that a purge has partially removed, and the detection SHALL run in time bounded independently of the
  number of installed files. *Checked by* two sandboxes whose synthetic installed-file counts differ
  by two orders of magnitude, asserting the per-invocation cost on an intact tree does not track the
  count; and by a drive on a damaged tree asserting the damage is found. Any damage class the bounded
  check cannot see SHALL be named in `README.md`, with `uvm doctor` documented as the exhaustive
  authority — a bounded check cannot promise doctor's coverage, and the documentation must not imply
  it does.

- **R4** — WHEN damage is detected, the wrapper SHALL repair it to the standard `uvm doctor` reports
  clean: uv itself, damaged tool environments, and damaged python installs — the same three remedies
  doctor prints today. *Checked by* a drive that damages each of the three, runs the wrapper with
  `UVM_REPAIR` set, and asserts `uvm doctor` subsequently exits 0. **This is the one criterion the
  `--offline` fixture cannot cover**: rebuilding a tool environment or a python install means a real
  resolution against an index, so the drive needs egress and one small real package. Say so in the
  verification record rather than leaving a reviewer to assume the fixture covered it.

- **R5** — WHEN several processes detect the same damage concurrently, exactly one SHALL perform the
  repair, under the `mkdir` lock discipline already in `uvm_acquire_lock` rather than `flock`; the
  others SHALL wait for it and then re-test the repaired state, and SHALL NOT each attempt a repair of
  their own. The early-out SHALL test the state *this* invocation needs, not merely that some repair
  happened. *Checked by* a drive launching N concurrent invocations against one damaged sandbox tree
  and asserting exactly one repair marker on stderr and N successful commands. Correctness on Lustre,
  GPFS and NFS specifically is *taken on trust from* the existing lock discipline plus a real-cluster
  drive, which the reviewer records as such — a local temp directory does not exercise those
  filesystems.

- **R6** — WHEN a repair completes, the command the user asked for SHALL run, and the wrapper's exit
  status SHALL be that command's own. All repair output SHALL go to stderr. *Checked by* a drive
  asserting `VER=$(uv --version)` on a damaged tree returns only the version string on stdout, with
  repair chatter on stderr, and by a drive whose command exits 3 asserting the wrapper exits 3.

- **R7** — IF a repair cannot proceed — the lock times out, or the repair itself fails — THEN the
  wrapper SHALL report the diagnosis on stderr and exit non-zero, and SHALL NOT exec into an
  environment it has already determined is damaged. *Checked by* a drive with `UVM_LOCK_TIMEOUT=1`
  against a held lock, asserting a non-zero exit and a message naming the damage and the lock.

- **R8** — Behavior outside the repair path SHALL be unchanged, and the new knob SHALL be documented
  wherever the existing knobs are. *Checked by* `.agents/factory/bin/lint.sh` passing; by
  `temp_root.sh uvm status`, `temp_root.sh --offline uv --version` and
  `temp_root.sh --offline --arch aarch64 uvm status` reaching the same post-conditions as on `main`;
  and by `UVM_REPAIR` appearing in the `uvm_help` heredoc, `README.md`, and
  `etc/uv-manager.conf.example` in the same commit as the code, per the `AGENTS.md` same-commit rule.

## Non-goals (no-gos)

- **No `uvm run` subcommand.** The request arrived in that shape, and it is the wrong one: a Globus
  Compute endpoint runs `uvx foo`, and asking automation to opt into `uvm run uvx foo` means the
  resilience reaches only callers who already knew they needed it. A knob on the existing dispatch
  reaches every caller at a site that enables it, and costs no new user-facing verb.
- **Not on by default.** `UVM_REPAIR` is opt-in. Automatic repair in the exec path spends the 7 ms
  budget and changes what `exec` means for every caller at every site, including the ones whose
  storage is not purged. A site that wants it everywhere sets it in the modulefile, which is a decision
  its operator makes and can reverse.
- **No `uvm doctor --repair` flag.** The natural manual counterpart, and a real candidate — but it is
  additive user-facing surface that nothing in this cycle needs, since `UVM_REPAIR=1 uvm status` drives
  the same machinery. Record it as a follow-up if the repair proves useful; do not ship it on
  speculation.
- **No repair of anything the wrapper does not own.** Project virtualenvs are out: `UV_PROJECT_ENVIRONMENT`
  is deliberately left unset, so a project's `.venv` is the user's, not ours. Repair covers the arch
  tree the wrapper created.
- **No re-tuning of `UVM_LOCK_TIMEOUT` for ten-thousand-rank scale.** R5 makes the timeout load-bearing
  at a scale it was not sized for, and the honest response is a measurement on a real cluster, not a
  larger number guessed here. R7 makes the timeout's expiry a clear failure rather than a silent one;
  that is this cycle's obligation.
- **No committed regression test.** `issues/test-harness.md` still owns the runner and the layout, and
  inventing a one-off here would pre-empt its decisions. R5 is precisely the concurrency assertion that
  seed names as the hardest thing it must cover — record this cycle's cases there.
- **The bootstrap is a separate cycle.** `uvm.sh`, `UVM_INSTALL`, and where the hosted installer stashes
  the local wrapper belong to `issues/uvm-bootstrap.md`; the maintainer's note about `UVM_INSTALL` was
  recorded there in this commit rather than absorbed here.
- **No change to what the wrapper exports or how it resolves.** `XDG_CONFIG_HOME`, `UV_CONFIG_FILE`,
  `UV_PROJECT_ENVIRONMENT`, the index variables and `TMPDIR` stay untouched.

## Clarifications

- **Q:** Is the entry point a new `uvm run` subcommand, a knob on the existing dispatch, or automatic
  on the `uv`/`uvx` path? — **A:** A knob, `UVM_REPAIR`, off by default. A new subcommand only helps
  callers who adopt it, which excludes the unattended endpoint that motivates the work; automatic
  everywhere spends the hot-path budget and changes `exec` semantics for sites that do not need it
  (resolved 2026-08-09).
- **Q:** How far does the repair go when it fires? — **A:** As far as `uvm doctor` detects: uv itself,
  damaged tool environments, damaged python installs. The seed's motivating failure is an ImportError
  from a half-deleted tool venv, so a repair that stopped at the uv binary would leave the case that
  justified the cycle unfixed. The cost is that a user who typed `uv --version` on a badly purged tree
  may wait for reinstalls they did not ask for — acceptable, because they opted in and the alternative
  is the ImportError (resolved 2026-08-09).
- **Q:** Is the unconditional `mkdir -p` in this cycle or its own? — **A:** In this cycle. It is not
  merely adjacent: whatever sentinel makes the `mkdir` conditional is the same class of cheap on-disk
  marker R3's bounded check needs, and splitting them would have the second cycle rework the first's
  mechanism. R1 keeps the property the current comment claims for it — a missing directory is still
  recreated (resolved 2026-08-09).
- **Q:** Should the knob be named something other than `UVM_REPAIR`? — **A:** `UVM_REPAIR` unless
  `/uvm-plan` finds a collision or a clearer name; it matches the existing `UVM_*` knobs and it is
  documented surface, so the GOAL names it rather than leaving the contract to reference an unnamed
  variable. A rename during planning needs sign-off, not silence (resolved 2026-08-09).
- **Q:** `ROADMAP.md` sequences this cycle first. Does promoting it now override any recorded
  ordering? — **A:** No. It is the head of the queue, and `issues/test-harness.md` is sequenced *below*
  it, so the missing harness is a non-goal here rather than a violated dependency (resolved
  2026-08-09).

## Related materials

- Seed: [`issues/purge-resilient-run.md`](../../issues/purge-resilient-run.md)
- Sibling cycle: [`issues/uvm-bootstrap.md`](../../issues/uvm-bootstrap.md) — one story for automation.
  The Anvil MEP endpoint may need to bootstrap the wrapper *and* face a tree purged since the user's
  last run, in the same invocation.
- Deferred verification: [`issues/test-harness.md`](../../issues/test-harness.md).
- High-risk regions this cycle touches, per `AGENTS.md`: `uvm_export_env` / `uvm_set_paths` (R1),
  `uvm_acquire_lock` / `uvm_unlock` (R5, R7), `uvm_install` / `uvm_point_current` (R4), and the
  dispatch tail (R6).
- The code the criteria name: `uvm_export_env` (`bin/uv-manager:399`), `uvm_doctor` and its
  remediation text (`:644`, `:729`), `uvm_have` (`:265`), `uvm_ensure_uv` (`:370`), the lock timeout
  (`:233`).
