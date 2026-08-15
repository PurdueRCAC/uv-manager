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

---

## Review cycle 2 — changes-requested (2026-08-15)

- **Reviewed commit:** 4208498a33b14aa8181e50ea945d033f1e892310  ·  **Base:** main
- **Mode:** **scoped** to the remediation delta at the human's direction, not a fresh full pass.
  Range `01ffcb6101b0d9bbf0515ae074ac89ca9133971b..HEAD -- . ':(exclude)spec/'`.
- **Graded surface:** one file, `bin/uv-manager`, five added lines and no deletions. The delta is
  user-facing prose inside `uvm_doctor`'s remediation heredoc, and the prose *is* the deliverable, so
  the rubric's file-versus-hunk rule was resolved to **the containing remediation block as a whole** —
  is the added paragraph accurate, does it cohere with its neighbours, does the block still read true
  top-to-bottom. The rest of `bin/uv-manager` was explicitly out of surface.
- **Prior coverage disclosed to the reviewer:** that an earlier pass graded and verified R1–R7, and
  nothing else. Not the findings, not their severities, not the verdict.

### Verification run

- `bash -n bin/uv-manager` → rc 0.
- `.agents/factory/bin/lint.sh` → all checks pass (bash 3.2.57 parse, shellcheck on the script and on
  `.agents/`, symlink integrity, version single-source `0.4.1`).
- Wrapper drives through `temp_root.sh` against fabricated damaged trees.
- Real `uv 0.12.4` under `env -i` with `HOME`, `XDG_CONFIG_HOME`, `UV_TOOL_DIR`, `UV_CACHE_DIR` and
  `UV_TOOL_BIN_DIR` isolated under `$TMPDIR`, small pure-python wheels only. The missing-`pyvenv.cfg`
  repair was **not** executed, by instruction: uv escapes to the base interpreter and writes outside
  any constructible sandbox, which has already left files in this machine's Homebrew Python once.

### The factual claim in the added paragraph — supported, and measured beyond the reference

`04-uv-repair-idioms.md` §4 records only that `uv tool upgrade --all` exits 1 on a receipt-less
directory. It is silent on whether the other tools are repaired, which is precisely what the delta
asserts. Measured across three orderings on real `uv 0.12.4`, damage being a deleted `.py` file:

| Orphan position | Damaged tools | rc | Damaged tools repaired |
|---|---|---|---|
| first (`pycowsay`) | `tqdm` | 1 | yes |
| last (`tqdm`) | `pycowsay` | 1 | yes |
| middle (`pycowsay`) | `cowsay` + `tqdm` | 1 | both |

`Modified <tool> environment` precedes `error: Failed to upgrade … is not installed` in every case, so
uv defers the orphan's error rather than aborting at it, independent of alphabetical position. "Exits
1" and "says that tool is not installed" match verbatim. `uv tool install <name>` — the second branch
of the WARN line the paragraph points at — exits **2** with `Executable already exists`, so only the
"Remove it" branch works and the paragraph's "clear" resolves to the branch that does.

Two limits carried forward: this is `uv 0.12.4` on macOS/arm64 where the reference was 0.12.3, and
like the reference's `--reinstall` observation it is observed behavior, not documented contract. A
future uv that fails fast on the first unreadable receipt would silently falsify the sentence.

**Correction to cycle 1's record.** That cycle's finding was titled "exits 1 **without repairing
anything**" and reproduced against a probe holding a single tool, where "fails wholesale" and
"repairs the rest, then fails" emit the same rc 1. The observation was right and the explanation
attached to it was not. `04-uv-repair-idioms.md` §4 characterized the class from the same single-tool
shape, which is where the reading came from. Anyone reading cycle 1's finding later should take the
table above as the correct account.

### Requirement → evidence matrix (delta-scoped)

| R-ID | Disposition | Evidence |
|------|-------------|----------|
| R4 | **Re-graded from scratch** — the delta is remediation text, so this is the only criterion it can move | `uv tool upgrade --all --reinstall --no-cache` against a damaged `tqdm` with receipts intact: rc 0, deleted `tqdm/std.py` restored (57344 bytes) — verified directly rather than taken from the reference. `git grep -n 'uv-manager install' -- bin/uv-manager` → one hit at `:602`, in help text far above `uvm_doctor`; none in the block. `uvm doctor 2>err \| head -1` → stderr empty, `grep -c "write error" err` → 0, rc 1. The five added lines contain no `$` or backtick, so the unquoted heredoc renders them literally. |
| R3 | Re-verified — the delta's whole subject is the advisory class | Sole receipt-less finding → `WARN` on stdout, `OK … (1 advisory finding(s) above)`, rc 0. The block does not print in that case, so the new paragraph only ever surfaces when something else is already broken. |
| R2 | Not moved; coherence checked | No deletions, `bin/uv-manager:719` untouched. Confirmed the rendered block still carries the no-safe-repair wording immediately after the insertion and that the new paragraph does not contradict it. |
| R1, R5 | Left to cycle 1 | The `RECORD` walk (`:738-767`) has no changed line; prose inside a heredoc cannot alter detection or fork count. |
| R6 | Left to cycle 1 | The delta adds no filesystem operation. |
| R7 | Left to cycle 1 | `README.md` is not in the delta; the diff touches one file. |

### Findings

#### [MEDIUM/CONFIRMED] Clearing the orphan the block recommends creates a new failure the block never mentions
- **Where:** `bin/uv-manager:817-818` (`uvm_doctor`, remediation heredoc)
- **Failure scenario:** a tree carries a gutted distribution (`FAIL`) and a receipt-less tool
  (`WARN`); doctor exits 1 and prints the block. The user runs the first command, gets rc 1, reads the
  new paragraph, removes the orphan directory, and reruns — rc 0. They then rerun doctor to confirm
  and get a **new** `FAIL  dangling executable`, which they created by following the instructions.
  `uv-receipt.toml` is the only record of a tool's entrypoints, so once it is gone nothing can clean
  the shim automatically — `uv tool uninstall` reports `Removed dangling environment` with rc 0 and
  leaves the shim standing. No route out of the advisory is shim-clean, and the block names none.
- **Evidence:** wrapper sandbox, orphan `pycowsay` plus gutted `tqdm` — before: `WARN tool pycowsay
  has no receipt…` + `FAIL tqdm-4.66.0 is missing 1 of 3 files`, `2 problem(s)`, rc 1. After removing
  `$A/tools/pycowsay`: `FAIL dangling executable: …/arm64/bin/shims/pycowsay` + the tqdm line,
  `3 problem(s)`, rc 1. The tidy route measured separately on real `uv 0.12.4`: `uv tool uninstall
  pycowsay` → `Removed dangling environment for 'pycowsay'`, rc 0, directory gone, shim still present.
  Mechanism confirmed in the code by the orchestrator: `uvm_set_paths` sets
  `UV_TOOL_BIN_DIR="${uvm_root}/bin/shims"` (`:389`), which is exactly the directory the dangling-shim
  walk scans (`:688`).
- **Touches invariant / requirement:** R4 — "the remediation text SHALL name only idioms that repair a
  damaged tree." The idioms named do repair; the added advice sends the user down a path that leaves
  the tree reporting a failure it did not report before.
- **Disclosed refutation, from the reviewer:** read strictly, "the status" means *the first command's*
  exit status, and under that reading the sentence is true — rc 1 → 0 after clearing the orphan was
  measured. The finding is that the other reading is the one available to someone looking at doctor's
  output, and that the shim consequence is disclosed nowhere. Doctor is not wrong to report the
  dangling shim; the tree really is broken.

Three candidates were raised and dropped: the added lines' width (84 chars, inside the block's
existing 79–86 range, and a style nit either way); the paragraph order placing the reassuring caveat
before the `pyvenv.cfg` danger caveat (judgment call, the adjacent warning is unambiguous); and an
apparent contradiction between "It repairs every other tool" and the following paragraph's "Neither
command repairs a tool whose pyvenv.cfg is gone" (ordinary general-statement-then-exception prose).

### Human-gate triggers

Not triggered. The CONFIRMED finding sits in `uvm_doctor`, which is not a high-blast-radius region,
and touches no §1, §2 or §6 invariant. No `invariants.md` §1–§11 violation was found.

---

## Review cycle 3 — approved (2026-08-15)

- **Reviewed commit:** f59a69977cc2680e997400cdc8b02e676e93a893  ·  **Base:** main
- **Mode:** **fresh full pass** over `main...HEAD -- . ':(exclude)spec/'` — the default for a later
  cycle, chosen over scoping to the nine-line remediation delta because this is the last cycle of the
  bounded loop and the two earlier passes graded different surfaces (cycle 1 full, cycle 2 scoped).
  Nothing about the prior cycles reached the reviewer's prompt: no finding ids, no severities, no
  verdict, no statement of which R-IDs an earlier cycle had already graded.
- **Graded surface:** five files, 141 insertions and 38 deletions. `bin/uv-manager` is the whole of
  the code delta and it is confined to `uvm_doctor`; `README.md` is prose; `ROADMAP.md`,
  `issues/doctor-detection-gaps.md` and `issues/test-harness.md` are the deferral record.
- **`debate` variant:** not offered. The diff touches no high-blast-radius region — `uvm_doctor` is
  not one — and no §1, §2 or §6 invariant.

### Blindness caveat for this cycle

The reviewer's log command was given as
`git log --oneline main..HEAD -- . ':(exclude)spec/' --format=%h`. Everything after `--` is a
pathspec, so `--format=%h` was swallowed as a path and `--oneline` printed seven **commit subjects**,
including `Build doctor-detection-gaps P3: F1 — say what the repair does to an orphan (R4)`. A prior
cycle's finding id and the shape of its remediation therefore reached the reviewer's context. It
disclosed this unprompted.

Bounding the damage: no prior verdict text, severity, or spec-file content leaked, and the subject
most at risk of anchoring is the one the reviewer then verified from scratch by executing real `uv
0.12.4` against fabricated orphans — reproducing the cycle-2 correction independently, including that
uv accumulates the orphan error rather than aborting at it. The leak weakened the guarantee; it did
not obviously move the verdict. Recorded as a harness defect in [`META.md`](META.md), not a code
finding. Reproduced by the orchestrator: with the flag placed before `--`, only hashes print.

### Verification run

Reviewer, and independently re-run by the orchestrator on the four headline criteria:

- `bash -n bin/uv-manager` → rc 0 under `/bin/bash` 3.2.57, the only bash on this machine, so every
  drive below is a bash 3.2 drive.
- `.agents/factory/bin/lint.sh` → all 7 checks pass.
- Wrapper drives through `temp_root.sh --offline` against fabricated damaged trees, including an
  eight-case pathological `RECORD` fixture: no trailing newline, CRLF, a quoted embedded comma, and
  paths containing `$`, `*`, a space and a backslash.
- Real `uv 0.12.4` under an isolated `env -i` playground for the claims the wrapper sandbox cannot
  settle — whether each remedy the block names actually repairs.
- A 331-path manifest of `$UVM_ROOT` (path, type, mtime, mode, size, sha256, symlink target) taken
  before and after a failing `uvm doctor`.

### Requirement → evidence matrix

| R-ID | Disposition | Evidence |
|------|-------------|----------|
| R1 | **Met** | `:744-753`. Delete one `RECORD` → `FAIL  tqdm-4.70.0 has no RECORD manifest (partial purge)` on stdout, rc 1. Also reached when `RECORD` is a *directory*. A present-but-unreadable `RECORD` prints `Permission denied` to stderr and the walk continues — the same shape `main` had with `awk: can't open file`. |
| R2 | **Met**, and the safety claim executed rather than trusted | `:723-726`. Remove `pyvenv.cfg` → `FAIL  tool httpie has no pyvenv.cfg; no automated repair is safe for it`, rc 1. Against real uv 0.12.4: with `pyvenv.cfg` deleted, `uv tool upgrade --all --reinstall --no-cache` exits **0 with no warning** and the base interpreter's `site-packages` gains `tqdm/` and `tqdm-4.70.0.dist-info/`. The repair writes outside the tree exactly as the finding says. |
| R3 | **Met** | `:711-716, 792-804`. Receipt-less tool as the only finding → the `WARN` line, then `OK    no damage detected under … (1 advisory finding(s) above)`, **rc 0**. Same tree with `RECORD` also removed → rc 1. Confirmed the receipt case is the only reclassification: `main`'s `uvm_doctor` emitted exactly one `WARN`. |
| R4 | **Met**, every named idiom verified by execution | `:806-831`. `uvm doctor 2>err \| head -1` on a failing tree → **stderr 0 bytes**. `git grep -n 'uv-manager install' bin/uv-manager` → one hit at `:602`, in the `self update` help, none in the block. Against real uv: `--reinstall` alone left a gutted `std.py` absent and `--no-cache` restored it; `uv python install --reinstall` with no target hit both installed managed versions; an offline `--reinstall` failed with `the requested data wasn't found in the cache`, so "needs network access" holds; `uv tool upgrade --all` reported `is not installed` for **every** orphan, not just the first, so "it repairs every other tool before it gets there" holds independent of alphabetical position; the WARN's `--force` is necessary — plain `uv tool install` exits 2 with `Executable already exists` *and deletes the directory*. Sandbox drive with `UVM_PIN=6.6.6` and `versions/`, `current` removed: doctor rc 1, next `uv --version` reprovisioned and left `current -> versions/6.6.6`, so "honors UVM_PIN" holds. |
| R5 | **Met** | `:743-772`. Fixture of 40 synthetic tools × 60 files plus 2 hand-built tools: the `FAIL … is missing N of M files` line set is **byte-identical** to `git show main:bin/uv-manager` against the same tree, 15 lines each, `diff` empty. On the pathological fixture the only difference is the new no-`RECORD` line R1 owes. Forks counted with `awk`/`basename`/`dirname` stubs on `PATH`: **198 → 42**, and the residual 42 are one `basename` per tool in the unrelated tools loop, outside the walk. Wall clock, alternating order, 3 runs: 349/336/368 ms → 128/121/132 ms, ~2.7×. |
| R6 | **Met** | Tree byte-identical across a failing run over 331 paths. A counting `mkdir`/`touch` stub first on `PATH` recorded **0 invocations**, and `find $UVM_ROOT -name .install.lock` returned nothing, so no lock was taken even transiently. |
| R7 | **Met** | `README.md:416-424`. Both load-bearing facts executed, not read: a real `uv-receipt.toml` holds `requirements = [{ name = "tqdm" }]` — the request, not the resolved set; and on a managed CPython 3.11.9 with `email/`, `xml/` and `unittest/` deleted, `import json, os, ssl` exits 0 while `import email` raises `ModuleNotFoundError`. Placing that gutted interpreter under `$UVM_ROOT/<arch>/python/` made `uvm doctor` print `OK`, rc 0 — the floor the README documents is the floor that exists. |

Nothing was taken on trust. R4's last sentence defers the repairs-or-not question to
`spec/purge-resilient-run/research/04-uv-repair-idioms.md`, which the reviewer is forbidden to open;
it was instructed to establish the sub-claim by execution instead, and did, for all six assertions in
the block.

### Findings

No CONFIRMED finding blocks. Three observations, recorded and surfaced rather than looped back.

#### [LOW/CONFIRMED · not a defect of this change] A quoted `RECORD` path containing a comma yields a false `FAIL`
- **Where:** `bin/uv-manager:761`
- **Failure scenario:** `IFS=, read -r rel _` splits on the first comma, so the RECORD line
  `"c/a,b.py",sha256=x,1` yields `c/a`, which does not exist, and an intact distribution is reported
  as `missing 1 of 1 files`.
- **Evidence:** fixture with `$SP/c/a,b.py` present and that RECORD line — the new script and
  `git show main:bin/uv-manager` both print `FAIL  c-1.0 is missing 1 of 1 files (partial purge)`.
- **Why it does not block:** identical on `main`, where the `awk -F,` split the same way, and **R5
  requires verdict parity with `main`** — correcting it here would violate the criterion. The code
  comment at `:757-760` states the trade-off outright. Recorded because a real wheel can carry a comma
  in a data-file path and doctor will call it damaged; that is a candidate for its own seed, not work
  this cycle contracted for.

#### [LOW/CONFIRMED · author judgment] The remediation block prints tool-class advice for classes that were not reported
- **Where:** `bin/uv-manager:806-831`
- **Failure scenario:** the block is unconditional, so a tree whose only problem is a gutted
  distribution gets 25 lines, 12 of which discuss a receipt-less orphan (`:820-823`) and a
  `pyvenv.cfg`-less tool (`:825-829`) that doctor did not report. The old block was 8 lines.
- **Evidence:** orchestrator drive, single finding `FAIL  tqdm-4.70.0 has no RECORD manifest` — the
  full 25-line block printed, both conditional paragraphs included.
- **Why it does not block:** both paragraphs are conditionally *phrased* ("a tool reported above as
  having no receipt", "a tool whose pyvenv.cfg is gone"), so nothing false is asserted, and the block
  never prints on the advisory-only tree, where doctor exits 0 silently but for the WARN. Against
  `AGENTS.md` § *Prose and comments* it is not padding either — each paragraph carries a distinct
  load-bearing fact, and the `pyvenv.cfg` one is a safety caveat that is cheapest to read when it is
  not needed. Whether 25 lines is the right price is the author's call, not a correctness defect.

#### [LOW/informational] Two of the three same-commit surfaces `GOAL.md` names did not move
`GOAL.md`'s closing line says the `uvm_help` heredoc, `README.md` and
`share/modulefiles/uv/main.lua` move with the code; only `README.md` did. Both others were checked
and assert nothing this change invalidates: `bin/uv-manager:865` reads
`doctor  Check for a partially purged / damaged tree`, and `main.lua:78,92` mention neither exit
status, nor receipts, nor the `RECORD` mechanism. `etc/uv-manager.conf.example` has no doctor
reference at all. `AGENTS.md`'s rule is "whichever of these it *invalidates*", so the diff is
compliant and the GOAL's unconditional phrasing is what overstates.

### Scope

No creep. Every hunk maps to an R-ID or to a non-goal the GOAL required landing in this commit:
`issues/test-harness.md` R3c is the *No committed regression test* obligation, and the `ROADMAP.md`
rewrite plus `status: adopted:doctor-detection-gaps` are lifecycle bookkeeping. No new subcommand,
environment variable, flag, output format, or `uvm status` change; no repair code; `uvm_unlock`
untouched.

### Invariants checked and intact

`invariants.md` §7 (output discipline — the last `printf` in `uvm_doctor` is gone and stderr is empty
through `head -1`), §8 (0 external `mkdir`s during doctor; `uvm_set_paths` still touches no
filesystem), §10 (parses *and runs* under bash 3.2.57 — `+=` on a string, `$'\n'`, `${var##*/}`,
`${di%/*}`, and the `read … || [[ -n "${rel}" ]]` guard, which was checked for a spin and terminates
in 2 iterations on a 2-line file with no trailing newline), §12 (version single-source `0.4.1`
untouched, symlinks intact, no feature-scoped spec ids in the script or the README). Heredoc
injection was probed directly: a dist-info named `h$X-1.0.dist-info` rendered literally as
`FAIL  h$X-1.0 …`, and paths containing `$HOME`, `star*` and spaces were matched with no expansion,
splitting or globbing — the comment at `:790-791` is accurate. §1, §2, §5, §6, §9 and §11 are not
touched by the diff.

### Human-gate triggers

Not triggered. No CONFIRMED finding blocks, none touches a high-blast-radius region — the entire code
delta is inside `uvm_doctor`, which is not one — and none touches a §1, §2 or §6 invariant.

### Convergence

Three cycles, the ceiling of the bounded loop, and this one converged: cycle 2's MEDIUM was
remediated by `f59a699` and a fresh full pass over the whole diff raised no blocker. The tree was
clean on hand-back (`git status --porcelain` empty).
