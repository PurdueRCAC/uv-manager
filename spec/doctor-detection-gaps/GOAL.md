# GOAL — `uvm doctor` reports OK on the damage it exists to find

> **Origin spec.** The *what* and *why* — the locked contract `uvm-review` grades against.
> The *how* lives in [`PLAN.md`](PLAN.md) and [`TECH.md`](TECH.md), written by `uvm-plan`.

- **slug:** doctor-detection-gaps
- **kind:** fix
- **appetite:** big

## Problem

`uvm doctor` (`bin/uv-manager:665-751`) is where every other document sends a user whose working
environment stopped importing: `README.md:299` puts it in the site verification block, `README.md:416`
names it the second mitigation for a scratch purge, and the modulefile help text
(`share/modulefiles/uv/main.lua:92`) ends with "run `uv-manager doctor` if something that used to work
stops importing." Four defects, each reproduced against real `uv 0.12.3` and real packages in a
`temp_root.sh` sandbox, mean it answers that question wrongly.

**It is blind exactly when the purge is worst.** The file-level walk at `bin/uv-manager:706` is driven
by the glob `tools/*/lib/*/site-packages/*.dist-info/RECORD`. `RECORD` is read only on uninstall,
making it the coldest file in a distribution and an early casualty of an atime-ordered purge. Gut a
`tqdm` environment and remove `RECORD` along with the files, and doctor prints `OK    no damage
detected` and exits 0. Restore `RECORD` alone and the same tree reports `FAIL  tqdm-4.70.0 is missing
197 of 201 files`. The detector's sight depends on the survival of the file a purge takes first. A
`dist-info` carrying no `RECORD` at all does not match the glob, so a distribution whose manifest is
gone is invisible rather than suspicious.

**Advice sets the exit status.** A tool directory missing `uv-receipt.toml` prints `WARN` at
`bin/uv-manager:688-691` and increments `problems`, so doctor exits 1. Observed on a tree where
`httpie` had lost its receipt: `uvm doctor` exits 1 permanently while `http --version` prints `3.2.4`
and the tool works. Automation keyed to doctor's status — a job prologue, which `README.md:418`
recommends — fails forever over a working tool, and the only route back to exit 0 is to delete it.

**The remedies it prints do not repair, and one is destructive.** `bin/uv-manager:744-749` prints
three commands. `uv tool install <name>` no-ops on a gutted-but-receipted environment, which is the
precise failure the banner above the function describes. `uv tool uninstall && uv tool install` still
yields a broken tree when the cache is damaged, because uv performs no integrity check on its unpacked
`archive-v0` store and only `--no-cache` forces a clean rebuild. And `uv-manager install` with no
argument re-resolves *latest* from the network and repoints `current`: driven under `UVM_PIN=6.6.6`
it left `current -> versions/9.9.9`, silently overriding the site's pin. The block is also six
`printf`s where this file's own SIGPIPE discipline (`bin/uv-manager:622-625`) requires a heredoc, so
`uvm doctor | head` emits `printf: write error: Broken pipe`.

All four are **pre-existing** on `main`. The audience is both a site operator running the verification
block at `README.md:294` and a user inside a batch job at 03:00; the first is misled into signing off
a damaged deployment, the second is told nothing is wrong.

## Outcome / vision

`uvm doctor` detects the damage a purge actually causes rather than the damage that happens to leave
its manifest behind, separates advice from failure in its exit status so automation can key on it, and
prints remedies that repair. It gets roughly four times cheaper doing it, and it says plainly what it
cannot see.

## Acceptance criteria (the contract)

- **R1** — WHEN a `*.dist-info` directory contains no `RECORD`, doctor SHALL report it as damage and
  SHALL set the exit status. *Checked by a sandbox drive: build a tool tree, delete one `RECORD`,
  assert the distribution is named on stdout and the exit status is 1.*
- **R2** — WHEN a tool directory is missing `pyvenv.cfg`, doctor SHALL report it as damage, SHALL set
  the exit status, and SHALL state that no automated repair is safe for that class — a repair
  attempted against it writes into the *base* interpreter's `site-packages`, outside the tree the
  wrapper owns. *Checked by a sandbox drive: delete `pyvenv.cfg` from one tool directory, assert the
  tool is named, the no-safe-repair wording is present, and the exit status is 1.*
- **R3** — The exit status SHALL be set only by findings that mean the tree is broken. A tool
  directory missing `uv-receipt.toml` is advisory, not broken: WHEN it is the only finding, doctor
  SHALL print the advisory on stdout and exit 0. *Checked by a sandbox drive: delete
  `uv-receipt.toml` from an otherwise intact tool directory, assert exit 0 and the advisory line;
  then assert that the same tree with `RECORD` also removed exits 1.* Reclassifying that one finding
  is the whole of this criterion — no other existing finding changes class.
- **R4** — The remediation text SHALL name only idioms that repair a damaged tree, SHALL NOT recommend
  `uv-manager install`, and SHALL be emitted through a heredoc. *Checked by a sandbox drive asserting
  `uvm doctor | head -1` writes nothing matching `write error` to stderr, plus
  `git grep -n 'uv-manager install' bin/uv-manager` showing no occurrence inside the remediation
  block. The claim that each named idiom repairs is graded by the reviewer against
  `spec/purge-resilient-run/research/04-uv-repair-idioms.md`.*
- **R5** — The `RECORD` walk SHALL reach the same verdict without forking per file. *Checked by a
  sandbox drive over a fixture tree with known damage: the set of `FAIL … is missing N of M files`
  lines SHALL be identical to those produced by `git show main:bin/uv-manager` against the same tree,
  and the walk SHALL be measurably faster on that tree.*
- **R6** — Detection SHALL remain read-only. `uvm doctor` SHALL take no lock and SHALL leave the state
  tree byte-identical. *Checked by a sandbox drive comparing a manifest of paths, mtimes and content
  hashes taken before and after. Access times are the deliberate exception — reading a manifest
  updates them.*
- **R7** — `README.md` SHALL state what doctor cannot detect, rather than implying the check is
  exhaustive. *Checked by the reviewer against `README.md:416-418`, which today enumerates four
  detected classes and names the `RECORD` walk as the mechanism, reading as a complete list. Two
  facts have to survive the edit: a distribution deleted entirely leaves no ground truth, because
  `uv-receipt.toml` records only the top-level request (`jupyterlab`), not the 91 distributions it
  resolves to; and managed interpreters carry no manifest, so doctor's oracle there is
  `import json, os, ssl`, which survives the removal of `email/`, `xml/` and `unittest/`.*

The same-commit rule applies: R1–R4 and R7 change user-visible behavior, so the `uvm_help` heredoc,
`README.md` and `share/modulefiles/uv/main.lua` move in the same commit as the code.

## Non-goals (no-gos)

- **No repair.** Doctor detects and reports; it does not rebuild anything.
  [`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md) owns rehydration, and its R5
  already carries the `pyvenv.cfg` refusal that R2 here only reports.
- **No committed regression test.** [`issues/test-harness.md`](../../issues/test-harness.md) owns the
  runner; the obligation is landed there as its R3c in this same commit, not left as a sentence here.
- **No fix to the provisioning lock.** R6 asserts doctor takes no lock; it does not touch
  `uvm_unlock`. [`issues/lock-ownership-and-hold-time.md`](../../issues/lock-ownership-and-hold-time.md)
  owns that.
- **No new subcommand, no new environment variable, no new flag.** The fix is to what `doctor`
  already does.
- **Not lifting the detection floor.** A deleted distribution and every managed interpreter leave no
  manifest, and no budget in this cycle changes that. R7 documents the floor instead of chasing it.
- **No change to `uvm status`,** and no new output format or machine-readable mode for doctor.

## Clarifications

- **Q:** The seed and `ROADMAP.md` record `appetite: medium`, but the GOAL template's vocabulary is
  `small | big` and all four landed GOALs used `small`. Which applies? — **A:** `big`. Seven criteria
  spanning detection, an exit-status contract change, a remediation rewrite, a performance rewrite of
  the walk, and a documentation sweep exceed any `small` cycle so far, and `big` is a value
  `/uvm-plan` already interprets (resolved 2026-08-14).
- **Q:** R5 is performance, not correctness owed. Does it belong in this cycle? — **A:** Yes. R1
  rewrites the same loop to probe for a missing `RECORD`, so deferring R5 means touching that loop
  twice, and `README.md:418` proposes doctor for job prologues where 1.33 s per check is real
  (resolved 2026-08-14).
- **Q:** The seed's line citations are stale — does its evidence still hold on current `main`? —
  **A:** Yes; only the line numbers moved, by about 17, after `ac8f803` and `62d0739`. Every defect
  reproduces as described. This GOAL cites current `main` (`uvm_doctor` at 665-751, the `RECORD` glob
  at 706, the receipt `WARN` at 688-691, the remediation block at 744-749) (resolved 2026-08-14).
- **Note for `/uvm-plan`, not a question.** The current walk *reads* every `RECORD`, and `read(2)`
  updates atime where `[[ -e ]]` does not. Running doctor therefore keeps `RECORD` warm and the module
  files cold — preserving doctor's sight on trees that are checked often and least likely to be
  damaged, and absent on the thirty-day-idle tree that motivates the work. That warming is an
  accident of the implementation, not a design to preserve; R1 is what makes the verdict independent
  of it.

## Related materials

- Seed: [`issues/doctor-detection-gaps.md`](../../issues/doctor-detection-gaps.md) · `ROADMAP.md`
  entry, first in the queue and sequenced **before** `purge-tree-repair`.
- `spec/purge-resilient-run/research/02-bounded-integrity-check.md` — where the four defects were
  found; `04-uv-repair-idioms.md` — which repair idioms actually work; `00-digest.md` — the
  adversarial pass that narrowed that cycle to the hot-path guard and left detection untouched.
- `README.md` § *Verification* (:294), § *Scratch purge* mitigations (:411-422), the doctor row at
  :180; `share/modulefiles/uv/main.lua:78,92`.
