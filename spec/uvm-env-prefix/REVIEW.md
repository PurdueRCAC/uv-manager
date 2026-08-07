# REVIEW — Rename the `UV_MANAGER_*` environment prefix to `UVM_*`

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 6fc41245bc6f23e0039827051e7de75c17a68e22  ·  **Base:** `main`  ·  **Date:** 2026-08-07
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3

The contract did not move during the build: `git log --oneline main..HEAD -- spec/uvm-env-prefix/GOAL.md`
returns only the original shaping commit `640e2f8`.

## Verification run

The blind reviewer executed 29 commands; the orchestrator independently re-ran the four contract
observables and both gates. Selected spine, with the post-condition asserted in each case.

- `bash -n bin/uv-manager` → rc 0 under bash 3.2.57 (macOS), the portability floor.
- `.agents/factory/bin/lint.sh` → rc 0. `shellcheck` clean on the wrapper and on `.agents/` scripts;
  `bin/{uv,uvx,uvm}` still git mode `120000`; version single-source reads `0.2.0`.
- `temp_root.sh uvm status` → `state root: <sandbox>/root  (from UVM_ROOT)`.
- `temp_root.sh uvm help | sed -n '/^Environment:/,/^$/p'` → exactly six lines, all `^  UVM_`;
  `grep -c UV_MANAGER_` on the output → 0.
- `UVM_PIN=1.2.3 temp_root.sh uvm status` → `pin: <none — tracks latest>`. The inherited knob did not
  reach the drive; this is the widened scrub, not a rename.
- Full scrub sweep — all six knobs plus `UV_CACHE_DIR` and `SCRATCH` injected outside the sandbox →
  only `UVM_ROOT=<sandbox>/root` and `UVM_SANDBOX=<sandbox>` survive inside it.
- `temp_root.sh sh -c 'UV_MANAGER_ROOT=$UVM_ROOT; export UV_MANAGER_ROOT; unset UVM_ROOT; uvm status'`
  → rc 1, stderr `cannot determine where to keep per-user uv state.`, all six scratch candidates
  listed `(unset)`, both recovery fixes printed. The legacy name is inert.
- `temp_root.sh sh -c 'UV_MANAGER_PIN=1.2.3 UV_MANAGER_PLATFORM=ppc64le uvm status'` →
  `architecture: arm64`, `pin: <none>`. The `UVM_*` counterparts do drive it:
  `architecture: ppc64le`, `arch root: …/root/ppc64le`, `pin: 1.2.3`.
- `temp_root.sh --offline sh -c 'uv --version; readlink "$UVM_ROOT/$(uname -m)/current"'` →
  `uv 9.9.9 (fixture)`; `current -> versions/9.9.9` (relative target, per §4). The fixture's
  `UV_INSTALL_DIR` / `CARGO_DIST_FORCE_INSTALL_DIR` scrub assertion (§6) passed on every offline drive.
- `temp_root.sh --offline --arch x86_64-glibc2.28 …` → provisioned under `root/x86_64-glibc2.28`,
  `current -> versions/9.9.9`, `architecture: x86_64-glibc2.28`.
- Lock, timeout path: pre-created `.install.lock`, `UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=99999` → rc 1,
  `timed out after 2s waiting for provisioning lock`, plus the exact `rmdir '…'` recovery line (§5).
- Lock, stale path: `UVM_LOCK_TIMEOUT=30 UVM_LOCK_STALE=0` → `breaking stale provisioning lock (1s
  old)`, then installs, rc 0.
- `temp_root.sh sh -c 'UVM_INSTALL_URL=file:///nonexistent-mirror uv --version'` → rc 1,
  `curl: (37) Couldn't open file /nonexistent-mirror/install.sh`. The URL knob is honored.
- **R3 A/B at the exec boundary.** The installed `uv` was replaced with an `env` dumper and the HEAD
  script compared against `main`'s driven with `UV_MANAGER_ROOT`: `PATH` and all five `UV_*` exports
  byte-identical. The `status` A/B differs on exactly two lines — the `invoked as:` path and
  `(from UV_MANAGER_ROOT)` → `(from UVM_ROOT)`.
- `temp_root.sh sh -c 'unset UVM_ROOT; uvm --version; uvm help'` → rc 0. Deferred `uvm_init` intact (§3).
- `PATH` idempotence under nesting (`uv` → `uvm status` → `uv`) → shim entries stay at 2 across one
  level, nested and re-entrant (§8).
- BSD-sed portability of the widened scrub pattern: the `\{0,1\}` interval form returns `UVM_PIN` and
  `UV_CACHE_DIR` and correctly excludes `UVX_Q` / `UVMM_Q`; the `UVM\?_` form the comment rejects
  returns **empty output** on BSD sed. The comment's claim is factually correct and load-bearing.
- The `verify:` string now seeded by `.agents/factory/templates/TECH.md`, run verbatim → rc 0,
  `readlink current` = `versions/9.9.9`. The template no longer seeds a broken command.
- The repro block in `issues/trampoline-ignores-platform-override.md`, run verbatim with the renamed
  variables → reproduces as documented: rc 127, `'ruff' is not installed for architecture 'arm64'`.

## Requirement → evidence matrix

| R-ID | Implemented by | Verified how (command + post-condition) | Status |
|------|----------------|------------------------------------------|--------|
| R1 | `uvm_resolve_root:84-86`, `uvm_init:145`, knobs `:158-161` | All six knobs driven individually: `UVM_ROOT` → `(from UVM_ROOT)`; `UVM_PIN`/`UVM_PLATFORM` → `pin: 1.2.3`, `architecture: ppc64le`; `UVM_INSTALL_URL` → curl 37 against the override; `UVM_LOCK_TIMEOUT` → `timed out after 2s`; `UVM_LOCK_STALE` → `breaking stale provisioning lock (1s old)`. Defaults unchanged (180 / 600 / `https://astral.sh/uv`). | ✅ |
| R2 | Absence of any legacy branch — `grep -c UV_MANAGER bin/uv-manager` → 0 | The GOAL's literal observable reproduces: rc 1 with `cannot determine where to keep per-user uv state` rather than resolving the directory. `UV_MANAGER_PIN` / `UV_MANAGER_PLATFORM` likewise inert. No shim, no warning. | ✅ |
| R3 | `uvm_set_paths` / `uvm_export_env`, untouched by the diff | A/B against `main` at both the `status` surface and the exec boundary: five `UV_*` exports and three `PATH` prepends byte-identical given the same root. | ✅ |
| R4 | `uvm_base_origin` `:86`; `uvm_help` heredoc `:765-770` | `status` → `(from UVM_ROOT)`; `help` Environment block → six `^  UVM_` lines, zero `UV_MANAGER_`. | ✅ |
| R5 | commits `08e157e` (heredoc) + `3859dc8` (README, conf, modulefile) | `git grep -n UV_MANAGER_` over the four surfaces → clean. Split across P2/P3, but both squash onto `main` as one commit, so the same-commit rule holds at the merge unit. | ✅ |
| R6 | `temp_root.sh` scrub + its own three exports | `UVM_PIN=1.2.3 temp_root.sh uvm status` → no pin (the GOAL's literal observable). The scope decision the GOAL flagged is honored: blanket `UVM_*` scrub with fixture knobs moved to the inner command — `temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'` → `uv 6.6.6 (fixture)`, documented at `temp_root.sh:34-36` and `fixtures/uv-install/install.sh:23-24`. | ✅ |
| R7 | commit `6fc4124` | `git grep -n UV_MANAGER_ -- . ':(exclude)spec/' ':(exclude)issues/uvm-env-prefix.md'` → no output. Only the two permitted historical records retain the old prefix. | ✅ |

**Unmapped changes (possible scope creep).** Three, none of them defects:

1. `bin/uv-manager:769-770` — the folded `LOCK_TIMEOUT / LOCK_STALE` help pair became two lines that
   now also state their defaults. Accurate against `:159-160` and consistent with the README table;
   the shorter names made room for it.
2. `README.md:428-435` — a new "Design notes" entry arguing the namespace split. Beyond R5's "carry
   the new names", but `AGENTS.md` designates that section as the record of rejected alternatives.
3. `etc/uv-manager.conf.example:8-12` — the header claim was rewritten rather than renamed, because
   the old text ("the wrapper reads only `UV_MANAGER_*` variables") was false. The replacement checks
   out: `uvm_set_paths` unconditionally exports all five storage variables and the conf sets none.

**Requirements taken on trust:** none. All seven were verified — R1–R4 and R6 by sandbox drive,
R5 and R7 by `git grep`, which is the check `GOAL.md` itself names for them.

## Findings

### [LOW/CONFIRMED] A live seed still describes the pre-branch, narrower sandbox scrub
- **Where:** `issues/test-harness.md:21`
- **Failure scenario:** the sentence reads "`temp_root.sh` points it at a temp directory, scrubs every
  inherited `UV_*` and scratch candidate, and removes it on exit." P1 widened that scrub to cover
  `UVM_*` as well. When `/uvm-feature` promotes this seed into a `GOAL.md`, the harness is designed on
  the belief that a developer's exported `UVM_PIN` reaches a test — so the resulting design either
  duplicates the scrub or writes a case that silently depends on the developer's environment.
- **Evidence:**
  ```
  $ grep -n 'scrub' issues/test-harness.md
  21:  a temp directory, scrubs every inherited `UV_*` and scratch candidate, and removes it on exit. No
  $ grep -n 'scrubs every inherited' AGENTS.md
  73:megabytes. `temp_root.sh` scrubs every inherited `UV_*`, `UVM_*` and scratch variable, points the
  ```
  `AGENTS.md:73` and `:204` were both updated for the widened scrub, and this same seed had its other
  two `UV_MANAGER_*` references updated in commit `6fc4124` — so the file was in hand when the
  sentence was left stale.
- **Touches invariant / requirement:** `invariants.md` §12 (same-commit documentation rule, applied to
  a live seed), and the GOAL's own non-goal clause: *"Live seeds that describe future work … are
  updated, because a stale seed misleads the cycle that promotes it."*

No other findings. The reviewer attempted and failed to break: the widened `sed` interval on BSD sed
(the rejected alternative genuinely fails silently there); scrub overshoot into `UVM_SANDBOX` /
`UVM_FIXTURE_*`; any drift in the exported `UV_*` storage variables; and every §1–§11 invariant
reachable from the sandbox — deferred init, the atomic relative `current` target, lock
timeout/stale/recovery text, the installer-environment scrub assertion, the trampoline union and
unmarked-file behavior, and `PATH` idempotence.

Not raised as findings: several rewrapped Markdown paragraphs now sit 7–12 columns short of their
neighbors because the shorter name was substituted without reflowing. Pure style, no line grew, and
the modulefile's column-aligned comment block *was* correctly re-padded.

## Human-gate triggers

**None.** The single CONFIRMED finding is in a seed file — it touches no high-blast-radius region and
no §1, §2 or §6 invariant. No human sign-off is required before the remediation cycle.

## Blindness note

The correctness reviewer disclosed that two recursive `grep -rn` sweeps returned matching *lines* from
`spec/uvm-env-prefix/{PLAN,TECH,META,research/*}.md` despite an exclusion filter that did not fire. It
opened no file under `spec/`, and every drive it ran derives from observables written into `GOAL.md`
itself — R2 and R6 spell theirs out literally. The leak is recorded rather than dismissed: it is a
partial erosion of the blindness this pass depends on, and the orchestrator's independent re-run of
all four contract observables is what the verdict rests on. Logged as a harness finding in
[`META.md`](META.md) F4.

## Optional completeness sub-pass (separate reviewer; may see TECH.md)

Not run — `/uvm-review` was invoked without the `completeness` argument.

---

## Review cycle 2 — approved (2026-08-07)

- **Reviewed commit:** d916d9438621a9358a7af0d23e75e6eb94b645ae  ·  **Base:** `main`
- **Mode:** *scoped remediation verification*, at the human's instruction — not a fresh blind pass.
  The cycle-1 correctness pass is not re-run, and its verdict on the code carries forward. What
  justifies that is the delta: `git diff --stat 6fc4124..HEAD` is one prose sentence in
  `issues/test-harness.md` plus the three `spec/` artifacts. No file under `bin/`, `etc/`, `share/`
  or `.agents/` changed, so nothing cycle 1 executed could have come out differently.

### The cycle-1 finding

**[LOW/CONFIRMED] A live seed still describes the pre-branch, narrower sandbox scrub** —
`issues/test-harness.md:21`. **Resolved.**

The sentence now reads the same scope as its normative sibling, so the two cannot disagree:

```
$ git grep -n 'scrubs every inherited' -- . ':!spec/'
AGENTS.md:73:megabytes. `temp_root.sh` scrubs every inherited `UV_*`, `UVM_*` and scratch variable, points the
issues/test-harness.md:21:  a temp directory, scrubs every inherited `UV_*`, `UVM_*` and scratch variable, and removes it on
```

The reflow is sound — line 21 is 98 columns against a file maximum of 104, and no line grew past its
neighbors.

### The retuned gate

The finding's real cause was that P4's gate searched only for the old prefix, so a checklist item
about *scope* was invisible to it. The commit retuned the gate. A gate never observed failing is not
a gate, so it was driven both ways, in a detached worktree at the pre-remediation commit, under
`/bin/sh` with `/usr/bin/grep` — the interactive shell here wraps `grep` in a function over `ugrep`,
which is `META.md` F6 and would have made an interactive result untrustworthy:

| Gate | at `6fc4124` (pre-fix) | at `d916d94` (HEAD) |
|------|------------------------|---------------------|
| cycle-1 form (`! git grep -q UV_MANAGER_ …`) | rc 0 — **blind to the defect** | rc 0 |
| retuned form (adds the two scrub-scope clauses) | **rc 1 — catches it** | rc 0 |

The `-ge 2` clause is what stops the check passing by matching nothing; both matching lines are shown
above.

### Gates and contract observables, re-run at HEAD

- `bash -n bin/uv-manager` → rc 0 under GNU bash 3.2.57 (arm64-apple-darwin25), the portability floor.
- `.agents/factory/bin/lint.sh` → rc 0.
- P4 `verify:` verbatim from the frontmatter → rc 0; also rc 0 re-run under `/bin/sh`.
- All five tracked symlinks (`CLAUDE.md`, `.claude`, `bin/{uv,uvx,uvm}`) still git mode `120000` — the
  guard against a bulk edit replacing a symlink with a regular file.
- **R6:** `UVM_PIN=1.2.3 temp_root.sh uvm status` → `pin: <none — tracks latest>`; the inherited knob
  did not reach the drive. `temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'` →
  `uv 6.6.6 (fixture)`; the scrub did not overshoot.
- **R7:** `git grep -n UV_MANAGER_ -- . ':(exclude)spec/' ':(exclude)issues/uvm-env-prefix.md'` → no
  output. The three historical records still carry the old prefix deliberately (11, 11 and 4
  occurrences), which is what the GOAL asks for.

### Verdict

**Approved.** No CONFIRMED findings outstanding, no PLAUSIBLE findings raised, no human-gate trigger —
the remediation touches one sentence in a seed file and one `verify:` string, neither a
high-blast-radius region nor a §1/§2/§6 invariant. All seven R-IDs remain verified; none is taken on
trust. Next step is `/uvm-publish`.
