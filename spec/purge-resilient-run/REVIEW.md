# REVIEW — Stop paying for the state-directory `mkdir` on every invocation

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 6531a2dcca0dd6ace78d3dc6c8337b63f3c9ab23  ·  **Base:** `main`  ·  **Date:** 2026-08-14
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md`

**Variant: `debate`.** Two independent fresh reviewers, one instructed to argue *ship*, one *block*,
each blind to `PLAN.md`, `TECH.md`, `research/` and `META.md` and each given the diff under
`':(exclude)spec/'`. Chosen because the diff edits `uvm_export_env`, a high-blast-radius region.

**Circularity note.** This diff edits two of the review's own grading standards — `AGENTS.md:109` and
`.agents/factory/invariants.md` §8. Both reviewers were told not to treat the HEAD text of §8 as ground
truth blessing the code, and to grade that edit against `AGENTS.md` instead. Both did, independently,
and both concluded §8 is a faithful statement of what the code now does rather than an invariant bent
to match a defect: its four normative clauses (six-way `[[ -d ]]` guard; guard outside the `umask 077`
subshell; a missing directory still created under `umask 077`; modes not repaired) were each verified
against observed behavior. The one inaccuracy inside it is F1 below.

## Verification run

Commands actually executed and their outcomes. This is the spine of the review.

- `bash -n bin/uv-manager` → clean under `/bin/bash` **3.2.57(1)-release**, the portability floor. Not
  merely parsed: every behavioral drive below ran under 3.2.57, the only bash on the machine.
- `.agents/factory/bin/lint.sh` → all checks pass (`bash -n`, shellcheck on the script and on
  `.agents/`, symlink integrity, version single-source `0.4.0`, 29 skill state injections).
- **`main` comparison probe.** `git show main:bin/uv-manager` staged outside the working tree with
  `uv`/`uvx`/`uvm` symlinks, so every case below was driven twice — HEAD and `main` — and compared.
  No tracked file was edited by either reviewer.
- **Counting `mkdir` stub** first on `PATH` inside `temp_root.sh --offline` (appends its argv to a log,
  then `exec`s the real `mkdir`). Warm `uv --version` on an intact tree → **HEAD 0 execs, `main` 1**
  (`GOAL.md` predicts exactly 1 on `main`). `uvx foo` likewise 0 vs 1. Re-drive after repair → back
  to 0.
- `temp_root.sh uvm status`, `temp_root.sh --offline uv --version`,
  `temp_root.sh --offline --arch aarch64 uvm status` → captured and normalized for both sides; `diff`
  shows only the probe's own artifacts (invocation path, `mktemp` suffix, `/private` prefix). Same
  `rc=0`, same `current -> versions/9.9.9`, same `uv 9.9.9 (fixture)`, same 17-line status body.
- **State configurations driven, HEAD vs `main`, all reaching parity:** fresh tree; each of the six
  directories removed individually; all six removed at once; a directory left at `0755`; the mixed case
  where a `0755` directory coexists with a missing one so the `mkdir -p` actually runs; a state path
  replaced by a regular file; a dangling symlink at a state path; a symlink-to-directory at a state
  path; an arch subtree stripped to `current` + `versions/9.9.9/uv`; a second architecture added to an
  existing root (`UVM_PLATFORM=x86_64` then `aarch64`).
- **Concurrency:** 40 concurrent invocations against a tree with all six directories removed →
  `nonzero_exits=0/40`, `stderr_bytes=0`, all six present at `700`. Identical on `main`. The guard
  introduces a check-then-act window; it does not produce a failure.
- **Re-entrancy (§8 `PATH` idempotence):** three levels of nested wrapper invocation →
  `uvroot_path_entries=3` at every level on both branches. HEAD 0 `mkdir` execs vs `main` 3.
- **`uvm_set_paths` purity (§8):** `uvm status` and `uvm doctor` on a fresh root → 0 `mkdir` execs,
  `$UVM_ROOT` empty, on both branches.
- **Non-`exec` path (§2):** `uv tool list`, `uv python list`, `uvx ruff`, `uvm doctor`,
  `uv self update --dry-run` → identical `rc` and identical stdout/stderr on both. Warm `mkdir` execs
  drop 2→1; the survivor is `uvm_trampolines`' own pre-existing `mkdir -p "${uvm_neutral_bin}"`
  (`bin/uv-manager:469`), untouched by this diff.
- **The headline figures, re-measured against the real `uv 0.12.4`** staged in a sandbox: direct
  `4.78 ms`; wrapper on `main` `11.7–13.2 ms`; wrapper on HEAD `9.93 ms`. Overhead above the exec'd
  binary — `main` ≈ **6.9 ms**, HEAD ≈ **5.15 ms**, saving ≈ **1.8 ms**. The guard's own cost, 10 000
  iterations under bash 3.2, is **8.7 µs**. Every number the diff states reproduces, within the
  precision it claims.

Both reviewers confirmed `git status --porcelain` empty on hand-back. All instrumentation lived outside
the working tree and was removed with `del`. No bare `bin/uvm install`; no network egress.

## Requirement → evidence matrix

| R-ID | Implemented by (function/line) | Verified how (command + post-condition) | Status |
|------|--------------------------------|------------------------------------------|--------|
| R1 | `uvm_export_env`, `bin/uv-manager:417-425` | Counting `mkdir` stub on `PATH` in `temp_root.sh --offline`. Warm intact tree → **0** execs (`main`: 1). `rmdir` of one state directory → **1** exec, directory recreated at `stat` mode **700**. Verified for each of the six individually, including `$UVM_ROOT/bin` and `bin/shims`. | ✅ |
| R2 | same hunk | All four contract cases driven HEAD vs `main`: (a) fresh tree → all six `drwx------` on both; (b) `chmod 0755` → **not** re-moded on either, and in the mixed case `tools=755 python=700` on both; (c) regular file at a state path → `rc=1` and byte-identical `mkdir: …: File exists` on both; (d) arch subtree deleted but `current`/`versions` kept → `rc=0`, `uv 9.9.9 (fixture)`, all six back at `700`, `current -> versions/9.9.9`, on both. Five further configurations beyond the contract also reach parity. | ✅ |
| R3 | `bin/uv-manager:402-416`, `README.md:462-467`, `.agents/factory/invariants.md:122-128` | `git grep -q "rather than behind a sentinel" -- bin/uv-manager README.md .agents/factory/invariants.md` → **exit 1**, paths written literally (not interpolated — the `zsh` pathspec trap). Replacement prose present at all three sites and graded by both reviewers against `AGENTS.md` § *Prose and comments*: declarative, states measurements rather than adjectives, records the rejected alternative (guard inside the subshell), no filler, no marketing adjectives, no spec ids, no emoji. Passes on voice; one factual inaccuracy → **F1**. | ✅ |
| R4 | `AGENTS.md:109`, `README.md:141` | `git grep -q "roughly 7 ms" -- AGENTS.md README.md` → **exit 1**; both now read "roughly 5 ms", and the new figure is corroborated by measurement against real `uv` (5.15 ms). The normative clause is "wherever it is stated", and one live statement survives outside the checked scope → **F2**. | ⚠️ partial |
| R5 | — | `lint.sh` passes. `bin/uv-manager` diff is **one hunk**, wholly inside `uvm_export_env` between `uvm_set_paths` and the `PATH` prepends. The three named drives reach identical exit status, `current` target and version string against `main`; `uvm doctor`, `uvm trampolines`, `uv tool list` and `uvm install` were compared too. | ✅ |
| Clarification — guard **outside** the subshell | `bin/uv-manager:417` encloses `:420` | Structural read confirmed by both reviewers; corroborated by the 1.8 ms delta, which is the fork *plus* the exec, against a guard costing 8.7 µs. The exec-counting gate cannot see this, so it was checked by inspection and by timing. | ✅ |

Unmapped changes (possible scope creep): all documentation and bookkeeping, none touching the wrapper.
`issues/purge-tree-repair.md` (new) is named explicitly in `GOAL.md`'s non-goals as the destination for
the deferred half. `issues/doctor-detection-gaps.md` and `issues/lock-ownership-and-hold-time.md` (new)
map to no R-ID but are mandated by `AGENTS.md` § *Where a deferral goes*; both reviewers independently
weighed the public-vs-`.security/` lane question and both concluded public is correct — the lock guards
a per-user tree created under `umask 077`, the trigger knobs are the victim's own environment, and no
privilege boundary is crossed. `ROADMAP.md`'s rewrite is required for an adopted seed; every
`issues/*.md` has exactly one entry and every `**Seed:**` link resolves. `issues/purge-resilient-run.md`
frontmatter moves `unshaped` → `adopted:purge-resilient-run`. The nine lines added to
`issues/uvm-bootstrap.md:67-75` are a maintainer note dated 2026-08-09, predating this cycle's
narrowing; both reviewers named it the least clearly sanctioned change in the diff, and it is also the
file carrying F2.

Requirements taken on trust (cannot be observed from the sandbox): **none**. The one property no drive
can reach is the cluster-scale metadata-server claim — every measurement here is macOS on APFS — but no
R-ID asserts a cluster figure, and `GOAL.md` already declares it unmeasured. Nothing was silently
downgraded to trust.

## Findings

Severity: **CRITICAL** (any `invariants.md` §1–§11 violation is auto-CRITICAL) · **HIGH** ·
**MEDIUM** · **LOW**. Verdict: **CONFIRMED** (reproduced) versus **PLAUSIBLE** (suspected, needs human
triage). Only CONFIRMED findings auto-loop to `uvm-build`.

Neither reviewer found a behavioral divergence from `main` in any configuration. Both findings below are
inaccurate numbers in prose the diff introduced.

### [LOW/CONFIRMED] The `25 mkdir(2)` figure is stated as a per-invocation constant, but it scales with the depth of `UVM_ROOT`

- **Where:** `.agents/factory/invariants.md:123`, `README.md:463-464`, `bin/uv-manager:403-404`
  (`uvm_export_env`)
- **Failure scenario:** GNU `mkdir -p` issues one `mkdir(2)` per path component per operand. For a root
  of `c` components the six operands cost `6c+13`, and `6c+13 = 25` only at `c = 2`. A deployment root
  such as `/scratch/negishi/lentner/.uv` gives 37, not 25. A site operator — or the next agent reading
  `invariants.md` §8, which is a gate document — sizes the removed cost against a constant that is true
  only for the bench path. The number this cycle exists to correct is replaced by another number with a
  hidden dependency.
- **Evidence:** `dtruss` is unavailable under SIP, so the count was established by depth-scaling rather
  than by syscall trace. GNU `gmkdir -p` over the same six operands, 1200 iterations: root depth 2 →
  1.6272 / 1.6023 ms per call; root depth 41 → 1.7505 / 1.8416 ms per call. Δ ≈ 0.19 ms across 39 extra
  components × 6 operands = 234 extra calls → **0.81 µs per call**. An independent depth-2 vs depth-11
  pair gave Δ ≈ 0.04 ms over 54 extra calls → **0.79 µs per call**. Cost is linear in root depth,
  therefore the call count is too.
- **Aggravating detail:** `bin/uv-manager:403` and `README.md:463` at least qualify the claim with
  "under GNU coreutils"; `invariants.md:123` drops even that, stating "twenty-five `EEXIST`-failing
  `mkdir(2)` calls per invocation" unqualified, in the file `/uvm-review` grades against.
- **Touches invariant / requirement:** R3 (the replacement prose), `AGENTS.md` § *Prose and comments*
  ("If a property matters, state the measurement").
- **Caveat on strength:** the depth-dependence is reproduced; the specific "37 for a realistic root" is
  a model prediction from coreutils' `mkancesdirs` behavior, not a measured count. The remedy is to
  drop the constant or qualify it, not to substitute a different one.

### [LOW/CONFIRMED] A stale `7 ms` survives in `issues/uvm-bootstrap.md`, a file this diff edits and that will not be retired

- **Where:** `issues/uvm-bootstrap.md:86`
- **Failure scenario:** R4 requires the overhead figure corrected "**wherever it is stated**", but its
  gate is scoped to `AGENTS.md README.md` and so cannot see this. The line reads "interposing another
  shell costs a fork against a 7 ms budget and has to preserve those semantics." When `uvm-bootstrap` is
  promoted, its shaping pass sizes a fork against a budget 40% larger than the one that now exists.
- **Evidence:** `/bin/sh -c "git grep -n '7 ms' -- . ':(exclude)spec/'"` → three hits:
  `issues/purge-resilient-run.md:43,106` and `issues/uvm-bootstrap.md:86`.
  `/bin/sh -c '! git grep -q "roughly 7 ms" -- AGENTS.md README.md'` → PASS. The two hits in
  `issues/purge-resilient-run.md` are exempt in substance: that seed is
  `status: adopted:purge-resilient-run` and `/uvm-roadmap` deletes it when this cycle lands.
  `issues/uvm-bootstrap.md` is `status: unshaped` and stays. The file is not untouched prose either —
  this diff adds nine lines at `:67-75`, sixty lines above the stale figure.
- **Touches invariant / requirement:** R4.
- **Both reviewers found this independently**, from opposite stances.

## Human-gate triggers

**Triggered, and cleared by the maintainer on 2026-08-14.** F1 cites `bin/uv-manager:403-404`, inside
`uvm_export_env`, so the region-based trigger fires on a literal reading. The maintainer signed off on
the grounds that F1 is an inaccurate number in a *comment*: the executable code in that region
reproduced byte-identical behavior against `main` across every configuration driven above, including
the concurrency and re-entrancy cases, and no reviewer produced a behavioral divergence. The
`debate` variant was run precisely because this region was touched.

No §1 (architecture partitioning), §2 (`exec` semantics) or §6 (installer environment) invariant is
implicated.

## Debate reconciliation

The two reviewers agreed on the whole substance. Both returned zero CRITICAL, HIGH and MEDIUM findings;
both independently confirmed F2; both independently rejected the `.security/`-lane objection against
`issues/lock-ownership-and-hold-time.md`; both independently verified the guard sits outside the
subshell, that the six tested operands are exactly the six created, and that bash 3.2.57 both parses and
executes the new conditional. The *ship* reviewer refuted 19 candidates, the *block* reviewer 13, with
substantial overlap. The single divergence is F1: the *block* reviewer tested the `25` figure for
depth-dependence and confirmed it; the *ship* reviewer examined the adjacent "under GNU coreutils"
qualifier, judged it immaterial, and never tested depth. That is a coverage difference, not a
disagreement — nothing the *ship* reviewer ran contradicts F1.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run this cycle.

---

# Review cycle 2 — approved (2026-08-14)

- **Reviewed commit:** 6782b0383d301473964f05eb908d5f6dafe50759  ·  **Base:** `main`
- **Verdict:** approved
- **Cycle:** 2 of ≤3

**Mode: scoped, by the maintainer's instruction** — "limited scope to the minor docs/comment changes
(no code changes)". The graded surface is the cycle-2 remediation delta,
`git diff 6531a2d..HEAD -- . ':(exclude)spec/'`: four files, +16/−14, `bin/uv-manager` comment-only.
The guard itself was graded in cycle 1 by two independent reviewers across ~15 state configurations
and was not re-litigated. One fresh blind reviewer, given `GOAL.md`, `invariants.md` and the rubric
inline, with `spec/` excluded from the diff, from the log (hashes only, subjects withheld) and from
every repository-wide search.

Because prose is this pass's deliverable, the rubric's hunk-scoping inverted: R3 and R4 were graded at
file and repository scope, not only over the moved lines.

## Verification run

- `bash -n bin/uv-manager` and `.agents/factory/bin/lint.sh` → clean (bash 3.2.57, shellcheck, symlink
  integrity, version single-source `0.4.0`).
- **The factual claim the remediation turns on was traced, not modelled.** Cycle 1's F1 could only
  establish depth-dependence by timing, because `dtruss` is unavailable under SIP. This pass ran GNU
  coreutils 9.1 under `strace` in a container: `mkdir -p` over the wrapper's real six operands issues
  one `EEXIST`-failing `mkdirat(2)` per path component of every operand, with no cross-operand
  memoization. Root depth 2 → **25** calls, all `EEXIST`; root depth 5 → **43**. Closed form `6·D+13`;
  the retracted "twenty-five" was a depth-2 artifact and the replacement is the correct
  generalization. Traced outside the repository.
- **No site restates a depth-dependent count as a constant:**
  `git grep -n -i -E 'twenty-five|\b25 (mkdir|EEXIST)' -- . ':(exclude)spec/'` → no hits. The three
  rewritten sites are arithmetically consistent with each other and with `ROADMAP.md:28`.
  `README.md`'s surviving "roughly a quarter of the wrapper's own overhead" back-solves to ≈6.7 ms
  pre-guard, consistent with the 7→5 ms correction.
- **R5 as a comment-only proof:** the two revisions of `bin/uv-manager` compared with comments and
  blank lines stripped are **identical** — the delta changes no executable line. The three named drives
  (`temp_root.sh uvm status`, `--offline uv --version`, `--offline --arch aarch64 uvm status`) reach
  `rc=0`, `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`, `architecture: aarch64`, with installer
  chatter on stderr and the fixture's `UV_INSTALL_DIR` / `CARGO_DIST_FORCE_INSTALL_DIR` scrub assertion
  passing.
- **Prose graded against `AGENTS.md` § *Prose and comments*:** no filler, hedging or marketing
  adjectives, no "This ensures/allows", no emoji, no restatement of adjacent code, and
  `git grep -n -E '\b(R[0-9]|P[0-9]|F[0-9])\b' -- bin/uv-manager README.md` → no hits. Two overlong
  README lines were weighed and dropped as house practice, not a violation. **No §12 finding.**
- **Same-commit rule (§12):** `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua` and the
  `uvm_help` heredoc carry no `mkdir` or timing claim; none is invalidated.
- Both named gates re-run by the orchestrator: `git grep -q "rather than behind a sentinel" -- bin/uv-manager README.md .agents/factory/invariants.md`
  → exit 1, and `git grep -q "roughly 7 ms" -- AGENTS.md README.md` → exit 1, paths written literally.
- `git status --porcelain` empty on hand-back; all instrumentation lived under `/tmp`.

## Requirement → evidence matrix

| R-ID | Status | Evidence |
|------|--------|----------|
| R1, R2 | out of scope | Guard behavior graded in cycle 1; the delta changes no executable line, proven by the comment-stripped comparison above. |
| R3 | ✅ | Named gate exit 1 (exit 0 at `main`, so the gate is live). All three sites rewritten and graded on voice; cycle 1's F1 inaccuracy is corrected and independently re-verified by syscall trace. |
| R4 | ✅ | Named gate exit 1. Repository-wide sweep for `N ms` variants: `AGENTS.md:109` and `README.md:141` read "roughly 5 ms"; `issues/uvm-bootstrap.md:86` now "5 ms budget", closing cycle 1's F2. Remaining hits are the seed below. |
| R5 | ✅ | `lint.sh` passes; no executable line changed; three drives reach the cycle-1 post-conditions. |

Unmapped changes: none. Taken on trust: none.

## Findings

### [LOW/PLAUSIBLE] The adopted seed still carries the retracted claim and the old figure, and only `/uvm-roadmap` removes it

- **Where:** `issues/purge-resilient-run.md:43`, `:106` (and the present-tense unconditional-`mkdir`
  claims at `:29`, `:44`, `:74`, `:110`), linked from `ROADMAP.md:21`.
- **Failure scenario:** a reader following the roadmap index lands on a cost analysis describing code
  that no longer exists. R4's quantifier is "wherever it is stated", and this delta demonstrably treats
  `issues/` as in scope, since it corrected `issues/uvm-bootstrap.md`.
- **Evidence:** `/bin/sh -c "git grep -n '7 ms' -- . ':(exclude)spec/'"` → one hit,
  `issues/purge-resilient-run.md:106`. Frontmatter reads `status: adopted:purge-resilient-run`.
- **Why PLAUSIBLE and not CONFIRMED.** This is not a defect in what ships; it is a dependency on a
  lifecycle step. `AGENTS.md` § *Where a deferral goes* has `/uvm-roadmap` **delete** an adopted seed
  and its `ROADMAP.md` entry once the cycle lands, with `spec/{slug}/` as the retained account and git
  history holding the file. Correcting figures in a file scheduled for deletion is churn, and the
  `:38-41` measurement table is a record of a measurement that happened and should not be rewritten.
  The cycle-2 gate excludes the file by literal pathspec rather than pretending it is absent. Both
  cycle-1 reviewers reached this exemption independently, and so did this cycle's reviewer, unprompted
  and blind to theirs. **It becomes a real defect only if the seed is not retired at merge** — so the
  action is to run `/uvm-roadmap`, not to edit the file.

No other findings. No CONFIRMED findings at any severity.

## Human-gate triggers

**None.** No CONFIRMED finding, and the only change inside a high-blast-radius region
(`uvm_export_env`) is a comment on a hunk proven to leave every executable line untouched. Cycle 1's
gate was triggered and cleared by the maintainer; nothing re-triggers it. No §1, §2 or §6 invariant is
implicated.

## Optional completeness sub-pass

Not run.
