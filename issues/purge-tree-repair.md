---
status: shaped
kind: feature
appetite: big
lane: public
---

# `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`

## Problem

A scratch purge is per-file on access time, so it removes a tool environment piecemeal while uv still
records it as installed. uv performs no integrity check on an environment it believes is present; it
execs a half-deleted venv and the user gets an `ImportError`. `uvm_doctor` finds this and prints
commands for a human (`bin/uv-manager:806-831`). Nobody reads that from a compute node at 03:00, and
automation cannot act on it.

The requirement, in the maintainer's words: put `uv run ...` in a script that launches an application
and have it just work, rehydrating whatever the purge removed, with `UVM_REPAIR=1` as the approval to
do the expensive part. It runs where it runs — inside the job, on the node doing the work — not as a
step outside job submission.

That last clause is load-bearing and was settled the hard way. A bring-up subcommand was proposed
during planning and rejected: `uvm repair` in a login-node prologue repairs `$UVM_ROOT/x86_64/` while
the job runs against `$UVM_ROOT/aarch64/`, which is the founding failure of this project re-entered
through the front door. A knob on the dispatch is **architecture-correct by construction**, because it
fires inside `uv`/`uvx` after `uvm_init` has resolved the platform key on the executing node.

## Why it was deferred

Not deferred out of a pass in the usual sense: this is the repair half of
`spec/purge-resilient-run/`, which narrowed to its hot-path half after research established three
defects in that cycle's own acceptance criteria. **Pre-existing** on `main` — the gap has been there
since `uvm_doctor` was written to report rather than repair.

The evidence is large and lives in `spec/purge-resilient-run/research/`; `00-digest.md` is the
decisions record and should be read before promoting this.

## Outcome / vision

A job whose tree has not been touched since before the purge window sets `UVM_REPAIR`, calls
`uv run`, and proceeds. One process repairs; the rest wait and then run. Nothing is spent when the
knob is unset, and nothing is spent on the second and later invocations within the same job.

## Sketch of the acceptance criteria

- **R1** — WHILE `UVM_REPAIR` is unset, the wrapper SHALL run no check, take no lock, and behave
  exactly as it does today.
- **R2** — WHERE `UVM_REPAIR` is set and a verification receipt for the current scope exists, the
  invocation SHALL proceed with no filesystem work beyond one existence test.
- **R3** — WHERE `UVM_REPAIR` is set and no receipt exists, the wrapper SHALL detect damage, repair
  what it can, write a receipt, and then run the user's command.
- **R4** — Tool environments SHALL be repaired with `uv tool upgrade --all --reinstall --no-cache`,
  and SHALL NOT be repaired by reconstructing a spec from `uv-receipt.toml`.
- **R5** — IF a tool directory is missing `pyvenv.cfg`, THEN the wrapper SHALL refuse to repair that
  tool and SHALL say why, rather than running a whole-tree repair over it.
- **R6** — Managed pythons SHALL be repaired only when managed pythons are installed and damage is
  detected in one, never unconditionally.
- **R7** — WHEN several processes find the same damage, exactly one SHALL repair; the others SHALL
  wait and then re-test, and SHALL NOT each repair.
- **R8** — WHEN a repair completes, the user's command SHALL run and the exit status SHALL be that
  command's own. All repair output SHALL go to stderr.
- **R9** — IF the repair cannot proceed or cannot finish, THEN the wrapper SHALL report the cause on
  stderr and exit non-zero rather than exec into an environment it knows is damaged.
- **R10** — The knob's accepted values SHALL be explicit and documented; `UVM_REPAIR=0` SHALL NOT
  enable repair.

## Notes

Findings from the `purge-resilient-run` research that a promotion must not rediscover.

- **Detection has a floor no budget removes.** Two of the three damage classes leave no manifest. A
  distribution deleted entirely leaves nothing to compare against — `uv-receipt.toml` records only the
  top-level request, not the 91 distributions `jupyterlab` resolves to. Managed interpreters carry no
  manifest at all. So an expensive check is *not* a sound check, which is the argument that killed the
  earlier framing of this work: the GOAL must state what is detected and concede the rest, at whatever
  cost point is chosen. Do not write a criterion promising detection of "a partially purged tool
  environment" without qualification.
- **The cost problem is real and the receipt is the proposed answer.** Doctor-grade detection is 2.8 s
  on a realistic tree (jupyterlab, ruff, pre-commit, httpie, snakemake, two managed pythons), 0.37 s
  once the walk is fork-free. Neither is payable per invocation in a many-rank launch, and
  `README.md:503` already tells operators to keep `uv run` off that path. R2's receipt records "a
  check ran in this scope", not "the tree is intact" — a purge that eats the receipt causes a
  redundant re-check, never a false clean. Scoping it by letting the knob carry the value
  (`export UVM_REPAIR="$SLURM_JOB_ID"`) keeps scheduler names out of the wrapper and leaves the scope
  with the operator. This was contested during research by an agent arguing any skip-sentinel is the
  dead stamp from `00-digest.md` D2; the distinction is that D2's stamp asserted integrity and failed
  unsafely. Settle it at promotion.
- **`uv tool upgrade --all --reinstall --no-cache` is the only tool idiom that works, and it is unsafe
  without R5.** `uv tool install <name>` no-ops on a gutted-but-receipted environment;
  `uninstall && install` still leaves damage when the cache is corrupt, because uv integrity-checks
  nothing in `archive-v0`; `uv tool install --reinstall tqdm` against a tool pinned at `==4.66.0`
  upgraded it to 4.70.0 and rewrote the receipt, destroying the pin permanently. `upgrade --reinstall`
  reads the receipt itself and preserved both the pin and the `--with` packages. But with a tool's
  `pyvenv.cfg` missing, that command exits 0 having written the package into the **base** interpreter's
  `site-packages` — reproduced inside the wrapper's own tree, contaminating the managed interpreter
  every future tool venv is seeded from. `--all` has no `--exclude`, so one such tool poisons the
  repair of every other.
- **The python arm is the expensive, fragile half.** `uv python install --reinstall` on an intact tree
  costs 2.1 s and re-fetches 48 MiB from `github.com`; with no managed pythons installed it downloads
  a CPython release candidate. On an egress-less compute node it converts a locally repairable tool
  venv into a hard network failure. It also emits `warning: Failed to install executable ... not
  managed by uv` for every shim on every run, so no "stderr is quiet" post-condition survives it.
- **Never call `uvm_install ""`.** A prototype did, and with `UVM_PIN=0.4.0` on a tree already at
  0.4.0 whose only damage was a tool environment, it repointed `current` to latest — overriding the
  pin for every other rank in the job, including ranks already past `uvm_ensure_uv` and about to exec
  `${uvm_current}/uv`. Invariant §4. Repair must go through `uvm_ensure_uv`, or pass the pin.
- **Reach limit that must be documented.** A purged tool invoked by its own name never enters the
  wrapper: the trampoline (`:481-495`) execs `$d/$a/bin/shims/$n` directly. `UVM_REPAIR` reaches `uv`,
  `uvx` and `uvm` and nothing else, so a user typing `ruff` on a purged tree still gets the
  `ImportError`. The knob serves the stated requirement, which is about `uv run`; it does not make the
  whole tree self-healing, and the README should not imply it does.
- **`uvm doctor`'s exit status became usable as an acceptance oracle in 0.5.0.** It used to return 0
  on a gutted environment whose `RECORD` the purge also took, so a criterion written against it was
  satisfiable with zero implementation, and 1 forever on a tree with a receipt-less but working tool.
  Both are fixed: a `dist-info` with no manifest is now damage, and failures set the status where
  advice does not. The floor below still bites, though — a distribution deleted entirely leaves
  nothing to detect — so a criterion written only against the status concedes that class silently.
  Pair it with a `RECORD`-independent post-condition: a captured manifest re-materialised, and the
  tool's console script actually running.
- **Sequencing.** The detector half is discharged; it shipped in 0.5.0. What remains is
  [`issues/lock-ownership-and-hold-time.md`](lock-ownership-and-hold-time.md), whose defects become
  live the moment anything holds the lock for a rebuild rather than a download. Promoting this first
  means absorbing it.
- Related: [`issues/uvm-bootstrap.md`](uvm-bootstrap.md) and
  [`issues/test-harness.md`](test-harness.md); R7 is the concurrency assertion that seed names as the
  hardest thing it must cover.
- Found by: the maintainer, filed during the roadmap sweep of 2026-08-09; re-shaped from
  `spec/purge-resilient-run/` research on 2026-08-14.
