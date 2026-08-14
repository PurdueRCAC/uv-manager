# GOAL — Stop paying for the state-directory `mkdir` on every invocation

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** purge-resilient-run
- **kind:** feature
- **appetite:** small

> **Narrowed in flight, 2026-08-14.** This cycle began as "repair a purged tree in place, at job
> scale" and carried eight criteria across repair, coordination and cost. Research
> ([`research/00-digest.md`](research/00-digest.md)) established that three of them could not be built
> as written, and the repair half moved to [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md)
> with the evidence. What remains is the half the measurement supports. The slug is historical; the
> research record under `research/` is mostly about the deferred work and is retained because that is
> where its evidence lives.

## Problem

`uvm_export_env` unconditionally issues a six-directory `mkdir -p` inside a `umask 077` subshell
(`bin/uv-manager:405-409`) on every invocation of `uv`, `uvx` and `uvm`. The comment above it
(`:402-404`) defends the cost as "a handful of metadata operations", and `README.md:462` and
`.agents/factory/invariants.md:122` record the same claim as a design decision and as a gate.

Measured, the claim is wrong by an order of magnitude in the direction that matters. The construct is
a fork **and** an exec: `( umask 077; … )` forks, `/bin/mkdir` execs, and resolving six already-existing
paths costs 25 `mkdir(2)` calls that all fail `EEXIST` plus six `stat`s. On a warm intact tree that is
**2.0 ms of a 12.0 ms invocation** — 27% of the wrapper's overhead above the exec'd binary, and two of
the three process creations on the warm path. Six `[[ -d ]]` builtin tests cost 15 µs and no forks.

The audience is a user inside a batch job. `uv run` appears inside loops that call it thousands of
times, and ten thousand ranks starting at once issue those failing `mkdir(2)` calls in a burst against
a single metadata server. Local SSD is the optimistic case; a failing `mkdir` RPC cannot be served
from a parallel filesystem's client attribute cache, where a `stat` often can.

The second half of the original claim is not a cost argument and must survive: the unconditional
`mkdir -p` repairs the *shape* of a tree a purge has partially removed. Any guard has to keep that.

## Outcome / vision

The wrapper stops doing metadata work that accomplishes nothing on a warm tree, and the repository
stops asserting a cost claim its own measurement refutes. A missing state directory is still created,
under `umask 077`, and every other behavior is byte-for-byte what it was.

## Acceptance criteria (the contract)

Each criterion is checked by a sandbox drive under `.agents/factory/bin/temp_root.sh`, except where a
grep is named instead.

- **R1** — WHILE all six state directories exist, an invocation SHALL issue no `mkdir`; WHEN any of
  them is missing, it SHALL be created, under `umask 077`. *Checked by* a counting `mkdir` stub first
  on `PATH` inside the sandbox: a warm drive of `uv --version` SHALL invoke it **zero** times; the same
  drive after `rmdir` of one state directory SHALL invoke it at least once and leave that directory
  present at mode `700`. On `main` the warm count is 1.

- **R2** — Behavior SHALL be unchanged in every case where the guard and the unconditional `mkdir -p`
  could differ. *Checked by* four drives asserting parity with `main`: a fresh tree creates all six at
  `drwx------`; a directory left at mode `0755` is **not** re-moded (the status quo does not `chmod` an
  existing directory, and R1 does not ask it to start); a state path replaced by a regular file
  produces the same `mkdir: … File exists` on stderr and the same non-zero exit under `set -e`; and an
  arch subtree deleted except `current/uv` exits 0 with all six recreated at `700`.

- **R3** — The three places asserting that the `mkdir -p` is unconditional SHALL be corrected in the
  same commit as the code: the comment at `bin/uv-manager:402-404`, the design note at
  `README.md:462-463`, and `.agents/factory/invariants.md` §8. *Checked by*
  `! git grep -q "rather than behind a sentinel" -- bin/uv-manager README.md .agents/factory/invariants.md`.
  Whether the replacement prose earns its place is *graded by a reviewer* against `AGENTS.md`
  § *Prose and comments* — no command decides that.

- **R4** — The documented wrapper overhead SHALL be corrected wherever it is stated, since it falls
  from about 7 ms to about 5 ms. *Checked by* `! git grep -q "roughly 7 ms" -- AGENTS.md README.md`.

- **R5** — Nothing outside the guard SHALL change. *Checked by* `.agents/factory/bin/lint.sh` passing,
  and by `temp_root.sh uvm status`, `temp_root.sh --offline uv --version` and
  `temp_root.sh --offline --arch aarch64 uvm status` reaching the same post-conditions as on `main` —
  same exit status, same `current` target, same version string.

## Non-goals (no-gos)

- **No repair, no `UVM_REPAIR`, no integrity check.** All of it moved to
  [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md), which is shaped and carries the
  research. This cycle adds no knob, no subcommand and no new user-facing surface at all.
- **No stamp or sentinel file.** Measured against six `[[ -d ]]` tests it saves 12 µs — one part in
  nine hundred of an invocation — and it fails R1's second clause by construction: a stamp records
  that the layout was correct once, and a purge that removes a directory does not remove the stamp.
  The drive with `bin/shims` removed leaves the tree broken.
- **No mode repair.** `mkdir -p` does not `chmod` an existing directory, so the property today is
  "directories we create are 0700", never "our directories are 0700". R2 pins the existing behavior
  rather than improving it; changing it is a separate decision.
- **No changes to `uvm_doctor`, to the lock, or to `uvm_set_paths`' purity.** The first two have their
  own seeds ([`doctor-detection-gaps`](../../issues/doctor-detection-gaps.md),
  [`lock-ownership-and-hold-time`](../../issues/lock-ownership-and-hold-time.md)).
- **No further hot-path work.** After the guard, the warm path execs `uname -m` and nothing else the
  wrapper controls. The largest remaining item is the `#!/usr/bin/env bash` shebang's extra exec at
  ~1.05 ms, which cannot be traded away because bash is not at a fixed path across cluster images.
- **No committed regression test.** [`issues/test-harness.md`](../../issues/test-harness.md) still owns
  the runner; R1's counting-stub drive is a case that harness must cover.

## Clarifications

- **Q:** The GOAL previously recorded, resolved, that R1's sentinel and R3's marker were one mechanism.
  Does that hold? — **A:** No, and it is **vacated** rather than amended: both halves are gone. The
  layout question has a free, authoritative, self-healing test in `[[ -d ]]`, and the contents question
  moved to another cycle. Measurement showed the stamp buys 12 µs and breaks the repair clause
  (resolved 2026-08-14, on `research/01-hot-path-cost.md` and the adversarial re-measurement in
  `research/00-digest.md`).
- **Q:** Where must the guard sit? — **A:** **Outside** `( umask 077; … )`. A guard inside keeps the
  fork and gives away roughly a third of the saving, and R1's exec-counting gate cannot tell the
  difference — so the placement is part of the contract, not an implementation detail
  (resolved 2026-08-14).
- **Q:** Does the same-commit rule reach `AGENTS.md` and `.agents/factory/invariants.md`? — **A:** It
  must here. `invariants.md` is what `uvm-review` grades against, so leaving §8 asserting the old
  decision would make the correct implementation an auto-CRITICAL violation inside a high-blast-radius
  region. The rule as written names only four user-facing files; that gap is recorded as a harness
  finding in [`META.md`](META.md) F2 (resolved 2026-08-14).
- **Q:** Does `AGENTS.md` assert the unconditional `mkdir`, as an earlier pass claimed? — **A:** No.
  `git grep` finds no such claim there; `invariants.md:122` is a derived bullet with no counterpart,
  which is pre-existing lockstep drift in the direction the rule says loses. `AGENTS.md`'s obligation
  here is only the stale 7 ms figure at `:109` (resolved 2026-08-14).
- **Q:** Do the GOAL's original figures (9.6 / 3.1 / 2.4 ms) stand? — **A:** Not as absolutes; they
  varied with fixture and method across four independent measurements. The reproducible statement is
  ~2.0 ms saved, wrapper overhead above the exec'd binary falling from ~7 ms to ~5 ms, and two of three
  warm-path process creations removed. All macOS on APFS; the cluster figure is unmeasured and the two
  sources of error run in opposite directions (resolved 2026-08-14).

## Related materials

- Seed: [`issues/purge-resilient-run.md`](../../issues/purge-resilient-run.md)
- Deferred out of this cycle: [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md),
  [`issues/doctor-detection-gaps.md`](../../issues/doctor-detection-gaps.md),
  [`issues/lock-ownership-and-hold-time.md`](../../issues/lock-ownership-and-hold-time.md)
- Backing research: [`research/00-digest.md`](research/00-digest.md), and
  [`research/01-hot-path-cost.md`](research/01-hot-path-cost.md) and
  [`research/06-surface-and-docs.md`](research/06-surface-and-docs.md) for this cycle specifically.
- `.agents/factory/invariants.md` §8 (the bullet this cycle rewrites) and §10 (the portability floor —
  the guard must parse and run under bash 3.2). `uvm_export_env` / `uvm_set_paths` is a high-risk
  region in `AGENTS.md`.
