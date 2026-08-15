# REVIEW — `uvm doctor` reports OK on the damage it exists to find

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 01ffcb6101b0d9bbf0515ae074ac89ca9133971b  ·  **Base:** main  ·  **Date:** 2026-08-15
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md` (escalate on non-convergence)

Mode: full blind pass over the whole spec-excluded diff (`git diff main...HEAD -- . ':(exclude)spec/'`),
five files. `spec/purge-resilient-run/research/04-uv-repair-idioms.md` — a prior, already-landed
cycle's record, named by R4 as the grading reference for the remediation idioms — was supplied to the
reviewer inline so the `spec/` exclusion could stay absolute.

## Verification run

Commands actually executed and their outcomes. This is the spine of the review.

- `bash -n bin/uv-manager` → rc 0.
- `.agents/factory/bin/lint.sh` → rc 0; seven checks, including `bash -n` under bash 3.2.57,
  shellcheck on the script and on `.agents/`, symlink integrity, and the version single-source
  (`0.4.1`).
- `/bin/bash` 3.2.57 driving the rewritten `uvm_doctor` directly, not merely parsing it. The shebang
  is `env bash`, which resolves to bash 5 on this host, so `bash -n` alone never exercises 3.2 at
  runtime. String `+=` accumulation, `$'\n'` and the heredoc all behave identically.
- `temp_root.sh --offline --arch x86_64` drives against synthetic damaged tool trees for each damage
  class: `RECORD` removed, `pyvenv.cfg` removed, `uv-receipt.toml` removed, and the mixed tree
  carrying an advisory alongside a failure.
- R5 equivalence: `git show main:bin/uv-manager` extracted to `$TMPDIR` and driven against the same
  fixture trees, comparing the `FAIL … is missing N of M files` lines.
- R6: a full manifest of every path under `$UVM_ROOT` (mtime, size, mode, sha256) before and after
  `uvm doctor`, plus a counting `mkdir`/`rmdir` stub first on `PATH` — a lock is a `mkdir`, and a
  `mkdir`/`rmdir` pair inside the run is invisible to a before/after tree comparison.
- Injection probe: tool and distribution names containing `$(id)`, backticks, `$`, `"` and `\`.
- SIGPIPE probe: `uvm doctor | head -1` on an 83,653-byte output, with stderr captured separately.

## Requirement → evidence matrix

| R-ID | Implemented by (function/line) | Verified how (command + post-condition) | Status |
|------|--------------------------------|------------------------------------------|--------|
| R1 | walk driven from the `*.dist-info` directory, `uvm_doctor` `bin/uv-manager:739-748` | `RECORD` deleted from `tqdm-4.70.0.dist-info` → `FAIL  tqdm-4.70.0 has no RECORD manifest (partial purge)`, rc 1. Same tree under `git show main:bin/uv-manager` → `OK  no damage detected`, rc 0. At scale: 900 manifest-less dist-infos, `main` says `OK`, the branch names all 900. | ✅ |
| R2 | `bin/uv-manager:718-721` | `pyvenv.cfg` deleted → `FAIL  tool tqdm has no pyvenv.cfg; no automated repair is safe for it`, rc 1. The no-safe-repair wording appears in both the finding and the remediation block. | ✅ |
| R3 | `advisories` counter, `bin/uv-manager:707-711`, `787-799` | Receipt-only damage → `WARN  tool tqdm has no receipt; uv ignores it. Remove it or reinstall by name.` followed by `OK    no damage detected … (1 advisory finding(s) above)`, rc 0, stderr 0 bytes (checked with `2>/dev/null` and `2>&1 >/dev/null` separately). The same tree with `RECORD` also removed → WARN still printed, rc 1. The diff confirms only the receipt branch changed counters. | ✅ |
| R4 | `bin/uv-manager:801-821` | Idioms match the R4 reference's conclusion exactly, including the `--no-cache` rationale and the python-half egress concession. `git grep -n 'uv-manager install' bin/uv-manager` → one hit at `:602`, inside the `self update --help` heredoc, not the remediation block. `uvm doctor \| head -1` → stderr 0 bytes on the OK, advisory and failure paths. The block's claim that a missing `uv` binary needs no command was driven: `current`/`versions` removed, `UVM_PIN=6.6.6 uv --version` → `uv 6.6.6 (fixture)`, `current -> versions/6.6.6`. | ✅ (see F1 on ordering) |
| R5 | `while IFS=, read -r rel _ \|\| [[ -n "${rel}" ]] … done < "${record}"` | Equivalence over 300 distributions × 30 files with 40 damaged: the sorted `FAIL … is missing N of M files` set is byte-identical between branch and `main` (`diff -u` empty, 40 lines each). An adversarial `RECORD` built to split the two parsers — quoted path containing a comma, CRLF, no trailing newline on the last entry, blank line, comma-less line, backslash, leading `-`, leading space, `$`, `/abs` and `../` entries — yielded exactly `FAIL advA-1.0 is missing 2 of 9 files` from both. The trailing-newline guard is load-bearing: without it `total` is 8, not 9. Performance on the 300-dist tree: 0.201 s versus 1.468 s, 7.3×. | ✅ |
| R6 | `doctor)  uvm_set_paths; uvm_doctor` (`bin/uv-manager:891`) — no lock, no `uvm_ensure_uv` | Before/after manifest of `$UVM_ROOT` → `diff -u` empty. Counting `mkdir`/`rmdir` stub first on `PATH` → zero calls during the run. | ✅ |
| R7 | `README.md:416-424` | Read against the criterion. Both required facts survive: the receipt records the request (`jupyterlab`), not the 91 distributions it resolves to; managed interpreters carry no manifest, so the oracle is `import json, os, ssl`, which survives removal of `email/`, `xml/` and `unittest/`. The passage closes with "A clean report means nothing detectable is wrong, not that the tree is whole," and states the exit-status contract for automation. | ✅ |

Unmapped changes (possible scope creep): none in `bin/uv-manager`. Three non-code edits are lifecycle
bookkeeping the GOAL or the factory rules require — `issues/test-harness.md` gains **R3c**, which the
GOAL's *No committed regression test* non-goal explicitly obliges this commit to land, plus an
open-question paragraph noting that R5's `git show main` comparison goes vacuous once this lands so a
future suite must pin a fixture verdict; `issues/doctor-detection-gaps.md` moves to
`status: adopted:doctor-detection-gaps`; the `ROADMAP.md` entry is rewritten to "In flight". The
ROADMAP header still reads `appetite medium` while its body explains the GOAL resolved it to `big` —
self-consistent, not a defect.

Requirements taken on trust (cannot be observed from the sandbox): none. All seven were driven.

## Findings

Severity: **CRITICAL** (any `invariants.md` §1–§11 violation is auto-CRITICAL) · **HIGH** ·
**MEDIUM** · **LOW**. Verdict: **CONFIRMED** (reproduced) versus **PLAUSIBLE** (suspected, needs human
triage). Only CONFIRMED findings auto-loop to `uvm-build`.

### [LOW/CONFIRMED] The first printed remedy exits 1 without repairing when the tree also carries a receipt-less advisory
- **Where:** `bin/uv-manager:806` (`uvm_doctor`, remediation heredoc)
- **Failure scenario:** a purge takes `uv-receipt.toml` from one tool and `RECORD` from another — the
  ordinary mixed outcome, not an edge case. Doctor prints `WARN  tool tqdm has no receipt…`, then
  `FAIL  httpie-3.2.4 has no RECORD manifest`, then a remediation block whose first line is
  `uv tool upgrade --all --reinstall --no-cache`. A reader works top-down, runs it, and gets
  `error: Failed to upgrade tqdm … is not installed`, rc 1. The advisory line carries its own remedy
  ("Remove it or reinstall by name"), but the block never says to clear the orphan first, and the
  block is where a user looks for the repair.
- **Evidence:** doctor on the mixed tree under `temp_root.sh --offline --arch x86_64` printed the
  WARN, the FAIL and the block in that order. The printed idiom was then driven against a
  receipt-less directory with real `uv 0.12.4` under `env -i` with `UV_TOOL_DIR`, `UV_CACHE_DIR`,
  `UV_TOOL_BIN_DIR` and `XDG_CONFIG_HOME` isolated under `$TMPDIR`, `UV_OFFLINE=1`, no network, the
  developer's state root untouched: `error: Failed to upgrade orphan / Caused by: 'orphan' is not
  installed; run 'uv tool install orphan' to install`, rc 1.
- **Touches invariant / requirement:** R4. The named idioms are correct — this is the ordering of the
  block, not the choice of commands. Independently corroborated by
  `spec/purge-resilient-run/research/04-uv-repair-idioms.md` § 4, which records the same rc 1 for
  `uv tool upgrade --all` against a receipt-less directory.

Two observations the reviewer deliberately did not raise, recorded here so a later cycle does not
rediscover them as new: a `RECORD` whose first field is a quoted path containing a comma still yields
a false `missing`, which is pre-existing on `main`, preserved on purpose to satisfy R5's equivalence,
and documented in the adjacent comment; and an unreadable `RECORD` makes doctor print a shell
`Permission denied` to stderr and report `OK`, which is exactly what `main`'s `awk` does, and reaching
that state requires a `chmod` a purge does not perform.

## Human-gate triggers

Not triggered. The only CONFIRMED finding sits in `uvm_doctor`, which is not a high-blast-radius
region, and touches no architecture-partitioning, `exec`-semantics or installer-environment invariant
(§1, §2, §6). No CONFIRMED finding violates `invariants.md` §1–§11.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run this cycle.
