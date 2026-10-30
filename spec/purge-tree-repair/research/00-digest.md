# 00 — Digest

Four briefs and one prototype. Briefs 02 and 04 were fanned out. Briefs 01 and 03 were written
alongside a prototype of the whole design, built in a throwaway copy outside the working tree. Every
phase gate in `TECH.md` was run against that prototype, green, and against this branch's HEAD, red.
The fan-out was full rather than narrowed, because the change edits `uvm_acquire_lock`, `uvm_doctor`
and the dispatch tail. Two of those are high-blast-radius regions.

## Decisions

**D1 — The lock takes its name.** `uvm_acquire_lock LOCK ON_TIMEOUT PREDICATE [ARG...]`, with LOCK
`install` or `repair`, derives the path and the message words from one table. Provisioning's messages
are unchanged, and the single existing call site gains one word ([01](01-lock-api.md)).

**D2 — Outcomes are two names per scope in `${uvm_root}/.repair/`.** `<key>.ok` is empty, and
`<key>.failed` holds the reason, written to a temporary name and renamed. A call tests `.ok` first,
so the repaired path costs one `stat`. The waiter's predicate is either name existing. A per-root
directory makes a heterogeneous job across two architectures check each tree once
([04](04-outcome-scope-surface.md) Q2).

**D3 — The scope key is built by builtins and spelled for every bash.**

- Inside Slurm the key is `job-${SLURM_CLUSTER_NAME:+…-}${SLURM_ARRAY_JOB_ID:-${SLURM_JOB_ID}}`,
  else `value-${UVM_REPAIR}`. Keying an array task on its array is the foreman's ruling at the plan
  gate (PLAN §5).
- Every byte outside an explicitly listed `[A-Za-z0-9._-]` becomes `_`. A range class is
  locale-dependent before bash 5.0, so the class lists its characters.
- A key over 200 bytes dies naming the knob.
- The cluster name stops two clusters on one filesystem from reading each other's job ids. It comes
  from the same scheduler, and it is the job id's namespace (04 Q1, Q2).

**D4 — Detection is `uvm_doctor`'s walk, extracted.** `uvm_detect` sets doctor's findings and
counts, plus three flags for the repair: tool damage, interpreter damage, and orphan names.
`uvm_doctor` becomes `uvm_detect` plus its lock, outcome and staging advisories. Its output on a tree
without the new state is unchanged.

**D5 — The arms are uv's whole-tree commands, interpreters first** (02 Q2-Q6, decision record D3).

- `uv python install --reinstall` runs only when an interpreter is damaged and a managed install
  exists. With none installed it would install a pre-release.
- `uv tool upgrade --all --reinstall --no-cache` runs on tool damage.
- Run alone on a tree whose interpreter is also damaged, the tool arm exits 1 and repairs nothing.
- Both arms write nothing to stdout. The wrapper still sends their stdout to stderr.
- No message of the wrapper's names either command, because the gates count those lines.

**D6 — An orphan without `pyvenv.cfg` refuses the repair before any arm runs.** Against such a
tool, uv's tool arm exits **0** while it writes into the base interpreter and retargets the shim
(02 Q7). The refusal is the only guard, and the gate compares listings of the base interpreter.

**D7 — A receipt-less tool fails the tool arm, and the outcome records that.**

- uv exits 1 after repairing every other tool (02 Q5). Taken literally, R9 records a failed outcome,
  and its reason names the receipt-less tool.
- The alternative accepts rc 1 when every uv error is "not installed" for a tool doctor WARNed. That
  parses uv's stderr. It is rejected as fragile; the foreman accepted the plan as written (PLAN §5, ruling 3).

**D8 — No re-detect after the arms.** A repaired outcome is recorded when the commands succeed. The
GOAL's fixture drives depend on it: tree (F)'s damage survives the stub repair. An outcome never
claims the tree is intact.

**D9 — Outcomes are bounded by the purge, not by pruning.**

- Brief 04 recommends a holder-side `find -mtime +30`. Rejected for this cycle. It reads every
  outcome's inode once per scope, so a 10k-task array over a 43k-entry store costs about 4×10⁸
  metadata operations a week, on the metadata server, at the scale it targets.
- On purged storage, the only kind where the knob does work, an outcome is only ever `stat`ed. It
  ages from creation and goes with the window.
- On storage that is not purged, the documentation says to leave the knob unset.
- `uvm clean outcomes` is the manual bound, and its dry run counts what is there.
- Accepted by the foreman (PLAN §5, ruling 4).

**D10 — The human path.**

- `uvm doctor` WARNs a standing repair lock with its owner line.
- It WARNs each failed outcome recorded under a value, with its reason and `uvm clean outcomes
  --yes`.
- It counts failed outcomes recorded under Slurm jobs, which end with their jobs, in one line,
  without reading them.
- `uvm clean lock` removes both locks, and its dry run prints each owner line.
- `uvm clean outcomes` removes `${uvm_root}/.repair/`.

**D11 — The R12 drive is a sibling, `tests/repair-race.sh`** ([03](03-cluster-drive.md)).

- Scenarios: F offline, T and P with real uv, and kill (P with the holder killed on sight, then
  doctor, `uvm clean lock --yes` and a clean pass).
- Real uv comes from `--uv-bin` locally, or the pinned installer on a cluster.

## Found, and not this cycle's to fix

- **Cross-scope serialization** (04 defect 2). Distinct scopes queue on one repair lock, and each
  walks: N scopes starting together on a healthy tree serialize N walks, and any scope past
  `UVM_LOCK_TIMEOUT / w` fails. R7 covers one scope.
  - Ruled at the plan gate: arrays become one scope.
  - Separately submitted jobs are seeded as `issues/repair-scope-queueing.md`.
- Doctor's interpreter loop also enters uv's minor-version symlink (`cpython-3.12-<platform>`), so a
  damaged interpreter is reported, and probed, twice (02 Q4). It is pre-existing and harmless to the
  repair, which only needs the flag. A seed for `/uvm-roadmap`.
- The GOAL's observed-on-main (T) and (P) details differ from brief 02's measurement.
  - (T): `uvx` fails inside uv with a lone newline on stderr, not with the package's `ImportError`.
  - (P): `uv run` exits 1, not 2.
  - No gate keys on either detail.

## Corrections to inputs

- The seed's "1-30 s" hold is a desktop figure (02: tool arm 0.3 s, python arm 0.8 s per
  interpreter, 23.9 MiB). The cluster figure is R12's to record.
- `pgrep` is denied in the agent sandbox ("Cannot get process list"). The kill drives therefore kill
  the wrapper's pid alone.
