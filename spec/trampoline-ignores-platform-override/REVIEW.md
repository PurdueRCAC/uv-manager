# REVIEW — Trampolines resolve the platform key the wrapper actually uses

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 713d10a809899c38eec464a5533df175b461f760  ·  **Base:** `main`  ·  **Date:** 2026-08-08
- **Verdict:** approved
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md` (escalate on non-convergence)

Blind correctness pass by a fresh `general-purpose` subagent given `GOAL.md`, `invariants.md`,
`review-rubric.md` and the diff under `':(exclude)spec/'`. The orchestrator re-ran the central drive
independently before accepting the verdict.

## Verification run

Commands actually executed and their outcomes. This is the spine of the review.

- `bash -n bin/uv-manager` → rc 0, under bash 3.2.57 (the macOS floor, §10).
- `.agents/factory/bin/lint.sh` → rc 0; all five checks pass, version single-source reads `0.3.0`.
- `temp_root.sh --offline uv --version` → `uv 9.9.9 (fixture)`, rc 0; `readlink current` →
  `versions/9.9.9`. Identical on a `main` baseline tree.
- `temp_root.sh --offline --arch aarch64 uvm status` → output identical to `main`'s modulo sandbox
  paths.
- `temp_root.sh --arch x86_64-glibc2.28 …` with shims planted under both the override key and
  `$(uname -m)`, trampolines generated, then the same file invoked three ways:
  - `UVM_PLATFORM=x86_64-glibc2.28` → `OVERRIDE-TREE`, rc **42** (the shim's own status, propagated).
  - `env -u UVM_PLATFORM` → `NATIVE-TREE`.
  - `UVM_PLATFORM=ppc64le` → rc 127, stderr `uv-manager: 'ruff' is not installed for architecture
    'ppc64le'.`, stdout empty.
  - `grep` over the generated body: neither `x86_64-glibc2.28` nor `arm64` appears; `head -1` is
    `#!/bin/sh`; `uvm_tramp_marker` present once.
- Baseline on `main` (`git show main:bin/uv-manager` staged into a throwaway tree): the same R1 drive
  → rc 127 naming the host's `arm64`. The defect reproduces before and not after.
- Generated body executed under `/bin/sh`, `dash` and `ksh`; `shellcheck --shell=sh` clean on the
  changed line.
- Adversarial drives beyond the contract, all green: `UVM_PLATFORM` containing a space and a glob
  character (assignment RHS is not split or globbed in POSIX sh, so both sides resolve the same
  literal tree); `UVM_PLATFORM=""` (falls back on both sides); §9 unmarked-user-script protection;
  removal sweep; `uvm trampolines` idempotence; `uvm install` + `uvm doctor` under an override key.

## Requirement → evidence matrix

| R-ID | Implemented by (function/line) | Verified how (command + post-condition) | Status |
|------|--------------------------------|------------------------------------------|--------|
| R1 | `bin/uv-manager:486` (heredoc in `uvm_trampolines`) | Sandbox drive above: `OVERRIDE-TREE`, rc 42 — target exec'd and its exit status propagated. `main` baseline: rc 127. | ✅ |
| R2 | `bin/uv-manager:486`, message at `:491` | `UVM_PLATFORM=ppc64le` → rc 127, stderr names `ppc64le`; host `uname -m` is `arm64`, so the two genuinely differ. stdout empty (§7). | ✅ |
| R3 | the `:-` default | `env -u UVM_PLATFORM` → `NATIVE-TREE`; decoy-only tree → rc 127 naming `arm64`. | ✅ |
| R4 | `bin/uv-manager:486` | Same `UVM_ROOT` holding two key trees, one generated trampoline, invoked under each key → each exec'd its own tree's shim. `grep` finds no key literal in the body. | ✅ |
| R5 | banners at `bin/uv-manager:139-147` and `:434-441`; expressions at `:151` and `:486` | Reviewer grade. Expression byte-identical at both sites (`${UVM_PLATFORM:-$(uname -m)}`). Both comments are declarative, state the coupling, and the `uvm_init` one names the concrete failure — "every trampoline exits 127 naming a key the wrapper never used". No filler, no spec ids, no restatement of the adjacent line. | ✅ |
| R6 | — | `lint.sh` rc 0; the three named drives reach identical post-conditions on `HEAD` and on a `main` baseline (same exit status, same `current` target, same version string). Body still `#!/bin/sh`, still runs under `dash`. | ✅ |

Unmapped changes (possible scope creep): none that concern the verdict. Two hunks were examined and
cleared:

- `etc/uv-manager.conf.example:81-84` — the new caution to compute `UVM_PLATFORM` on the executing
  node. No R-ID of its own, but a direct consequence of the fix: the variable now steers trampolines
  as well as the wrapper, so a login-node literal inherited through `sbatch --export=ALL` is newly
  worse. This is what the same-commit rule exists for.
- `ROADMAP.md:37-49` and `issues/trampoline-ignores-platform-override.md:2` — lifecycle bookkeeping
  prescribed by `uvm-feature`. The ROADMAP entry grew from four lines to eight; it is the record of a
  deliberate reordering against the sequencing the file itself states, which earns the space.

The `README.md` and `share/modulefiles/uv/main.lua` edits (`uname -m` → "the platform key") are
same-commit accuracy repairs. All are true of the fixed code and were false-by-omission before.

Requirements taken on trust (cannot be observed from the sandbox): none. R5 is graded rather than
executed, which `GOAL.md` states up front — no command decides whether a comment earns its place.

## Findings

None. No CONFIRMED findings, no PLAUSIBLE findings.

Four candidates were raised and dropped under the refutation protocol:

- **Unquoted assignment divergence.** `uvm_init` writes `arch="${UVM_PLATFORM:-$(uname -m)}"`
  (quoted); the generated body writes `a=${UVM_PLATFORM:-$(uname -m)}` (unquoted). Dissolved: an
  assignment RHS undergoes neither word-splitting nor globbing in POSIX sh. Driven end-to-end with a
  space and with a glob character in the value, through both sites, under `sh`, `dash` and `ksh` —
  same tree resolved every time.
- **Stale trampolines after upgrade.** A site upgrading from `main` keeps `a=$(uname -m)` bodies until
  the next resync. Dropped: not a regression — those sites are already at 127 — and the trampoline's
  own stderr advice (`uv tool install <package>`) is itself a `uv tool` command, which triggers the
  resync. Self-healing.
- **No `setenv("UVM_PLATFORM", …)` caution in the modulefile.** Dropped as gold-plating: §1 already
  covers exported architecture-bearing values generically, and the branch added the caution to
  `etc/uv-manager.conf.example`, which is where an operator sets the variable.
- **`README.md:121`** still says the wrapper "Appends the architecture (`uname -m`)" without the
  override. Dropped: pre-existing, outside every diff hunk, equally imprecise before the change, and
  `README.md:347` covers the override. Grading it here would manufacture a gap on a non-prose branch.

## Human-gate triggers

None triggered. The gate fires on a **CONFIRMED finding** in a high-blast-radius region or against
§1/§2/§6; there are no findings. The diff does sit squarely in `uvm_trampolines` and against §1, so a
finding in a later cycle would trigger it.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run — `/uvm-review` was invoked without the `completeness` argument.
