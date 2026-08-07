# REVIEW — Prose pass over every comment and user-facing document

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) plus the `AGENTS.md` invariants **only** — it does not see
> `PLAN.md` or `TECH.md`, which would invite grading-its-own-homework. Every finding cites an
> **executed** command, not an assertion. This repository has no test suite; this pass is the
> coverage.

- **Reviewed commit:** 7b0c0d9c2a4792ffc5f935089d2c5c2e2fb82c14  ·  **Base:** `main`  ·  **Date:** 2026-08-07
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3 — mirrors `review.cycle` in `TECH.md`

This file is cumulative and the cycles run oldest-first. The current verdict is the one in the last
`## Review cycle` section, not the one above.

Contract-drift check: `git log --oneline main..HEAD -- spec/prose-and-comment-pass/GOAL.md` returns
only the shaping commit `692adf1`. The contract did not move mid-build.

## Verification run

Commands actually executed and their outcomes. This is the spine of the review. The blind reviewer
built a detached `git worktree` of `main` outside the repository and drove *its* `temp_root.sh`, so
every HEAD-versus-`main` comparison below is two real drives, not a reading. The worktree was removed
and pruned before hand-back.

- `bash -n bin/uv-manager` → clean under bash 3.2.57 (macOS), the portability floor.
- `.agents/factory/bin/lint.sh` → all five checks pass, including symlink integrity and the
  single-sourced version (`0.3.0`).
- **Semantic diff of the executable text** — `bin/uv-manager` on `main` versus HEAD with full-line
  comments and blanks stripped → exactly one differing line, `bin/uv-manager:319`, whose executable
  half is byte-identical (`-*)         ;;`); only the trailing comment was removed. Function-name
  inventory: identical. Variable-assignment inventory: identical. `git diff --summary`: empty (no
  mode change, no symlink converted to a regular file).
- `.agents/factory/bin/temp_root.sh uvm status` → stdout and stderr byte-identical to the `main`
  drive, rc 0 both.
- `.agents/factory/bin/temp_root.sh --offline uv --version` → `uv 9.9.9 (fixture)`;
  `readlink current` → `versions/9.9.9`; a full `find` of the state tree matches the `main` drive
  except for the `.incoming.XXXXXXXX` mktemp suffix.
- `.agents/factory/bin/temp_root.sh --offline --arch aarch64 uvm status` → identical to the `main`
  drive, all paths under `<root>/aarch64/`.
- **No-root failure block** — `UVM_ROOT` and all six scratch candidates unset → stderr byte-identical
  to `main`, rc 1 both. Driven again with `CLUSTER_SCRATCH` pointing at a nonexistent path and
  `SCRATCH` at a `chmod 500` directory: `(not a directory)`, `(not writable)` and `(unset)` reasons
  all still present, identically on both sides.
- **Broad surface**, HEAD versus `main`, normalized only for the sandbox path and repo root:
  `help`, `--version`, unknown subcommand, `self update --dry-run`, `self update -h`, `self update`,
  `versions`, `doctor`, `trampolines`, `clean` with and without `--yes`, and `status` under `UVM_PIN`
  → zero-byte diff across all of them.
- `sh -n` and `bash -n` on `etc/uv-manager.conf.example`, `luac -p` on
  `share/modulefiles/uv/main.lua` → pass. The only non-ASCII codepoint in the four files is the em
  dash; no emoji, no exclamation marks. `git grep -nE '\b(R[0-9]|P[0-9])\b'` over the four files →
  empty, so no feature-scoped spec id leaked into the script or the README.

**Methodology note for anyone re-running the R1 census.** The shell here is `zsh`, which does not
word-split unquoted variables. `F="a b c d"; git grep -n pat -- $F` passes a single four-word
pathspec, matches nothing, and reports clean — the same false-green failure mode `GOAL.md` warns
about for `\b`. Spell the four paths out.

## Requirement → evidence matrix

| R-ID | Implemented by | Verified how (command + post-condition) | Status |
|------|----------------|------------------------------------------|--------|
| R1 | Six edits across the four files | Both census commands, HEAD and `main`, four explicit paths. `main`: 10 + 3 = **13**, matching the GOAL baseline exactly. HEAD: **7 + 0**. All three `note that` hits gone; six of the seven survivors are the contrastive "not just X" or the comparative idiom "just as cheap". One survivor is in filler position — see F1. | ⚠️ partial |
| R2 | Two comment removals, five rewrites in `bin/uv-manager` | `grep -cE '^[[:space:]]*#'` → 200 → **198** comment lines; trailing comments 15 → 14. The removals are `# Decide whether provisioning is needed, then do it.` and `# ignore other flags`, both pure restatements of the adjacent line. The five rewrites all move from what to why. The new `# Fast path: already on disk, so no lock and no network.` was checked against the code: the early return at `bin/uv-manager:302-305` precedes both `uvm_acquire_lock` (`:307`) and `uvm_fetch` (`:337`), so the claim is true. No surviving comment paraphrases its statement. | ✅ |
| R3 | Aggregate budget | `cat bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua \| wc -l` → **1723** on HEAD versus **1724** on `main` (via `git show main:<path>`). Net −1. Per file: script 848→846, README 570→**571**, conf 148→148, modulefile 158→158. The aggregate reading settled in the GOAL's third clarification is what makes this pass; per-file it would fail on the README. | ✅ |
| R4 | Nothing executable touched | Semantic diff, function inventory, variable inventory, and the six sandbox drive comparisons above — all identical to `main`. `lint.sh` passes. The dispatch tail below `# ---- dispatch` (`bin/uv-manager:803`) is untouched, so `exec` semantics, the `tool`/`python` non-exec path and `rc` propagation are unchanged by construction. | ✅ |
| R5 | No message text changed | **Zero** bytes of quoted user-facing message text or heredoc content differ from `main` — established by the semantic diff and confirmed by the byte-identical stderr across every drive, including the no-root block with all six candidate names and every failure reason. The R1 census independently confirms no banned vocabulary survives inside any quoted string or heredoc: all seven survivors are `#`/`--` comments or README prose. | ✅ (see trust note) |
| R6 | `README.md:15` | `temp_root.sh uvm status` against the sample block at `README.md:13-19`. The `main` sample was **stale** — it omitted the `invoked as:` field that live `uvm status` has emitted all along. HEAD adds it in the correct position with column padding matching the live drive character for character; field order matches the drive exactly. | ✅ |

**Requirements taken on trust.** R5's "SHALL be audited to the same standard" half is a statement
about a process, not an observable post-condition, and no sandbox can see it. Its consequential half
— "SHALL lose no information a stuck operator needs" — is verified above by byte-identical output
across the whole message surface, which is the stronger evidence: no information could be lost
because no message changed. Nothing else was downgraded to trust during this review.

**Unmapped changes (scope creep).** Six, all benign; none blocks.

1. `ROADMAP.md` and `issues/prose-and-comment-pass.md` — the seed is marked
   `status: adopted:prose-and-comment-pass` and the roadmap entry gains an `**adopted** as spec/…`
   pointer with its body rewritten to record the settled scope. The GOAL's last non-goal says those
   files' *prose is not audited*; this is lifecycle bookkeeping from the shaping commit, not an
   audit, and it matches the `/uvm-roadmap` contract in `AGENTS.md`. Outside R3's four-file count.
2. `README.md:449`, "four-line `sh` script" → "short `sh` script". Maps to no R-ID — no banned word
   is involved — but it corrects a factual error: the trampoline heredoc body at
   `bin/uv-manager:472-484` is thirteen lines, not four. `AGENTS.md` would prefer the measurement
   over the vague "short", but "short" is at least true where "four-line" was false.
3. `README.md:141`, `7ms` → `7 ms`, now matching `AGENTS.md` verbatim.
4. `README.md:467` drops "just-in-time" from the Globus Compute paragraph. This was a census hit
   (`-w just` matches across the hyphen), but "just-in-time provisioning" is a term of art rather
   than filler, so this is the one edit that reads as satisfying the grep rather than the standard.
   The replacement keeps the timing ("before the UEP starts"), so no information is lost.
5. `share/modulefiles/uv/main.lua:50`, "extremely fast" → "fast". The line is Astral's own one-line
   description of uv, shown to users by `module help uv`. No R-ID requires the change — "extremely"
   is not in the banned vocabulary — and trimming an upstream product description under our house
   style is a judgment call rather than a defect either way.
6. `etc/uv-manager.conf.example`, `--` → `—` at six sites. Normalizes against the file's own
   pre-existing em dashes at `:1` and `:45`, which `main` was inconsistent with; `grep -n ' -- '`
   over the file now returns nothing, and it still passes `bash -n` and `sh -n`. Recorded because it
   sits in slight tension with the GOAL's stated outcome — the em dash is itself a recognizable
   generated-text tell — but the repository's established voice uses em dashes throughout, so
   internal consistency is the better reading. Human triage, not a defect.

## Findings

### [MEDIUM/CONFIRMED] F1 — `just` survives in filler position, against R1

- **Where:** `bin/uv-manager:597` (the banner comment above `uvm_status`)
- **Failure scenario:** R1 requires that the banned vocabulary not appear *in filler position* in the
  four in-scope files. The pass removed three of the ten `just`-class hits and all three `note that`
  hits, but left `` bash's printf builtin reports EPIPE as "write error: Broken pipe"; `cat` just
  dies on SIGPIPE. `` This one fails the deletion test that separates the other six survivors from
  filler: strike `just` and the sentence loses nothing. Contrast the contrastive "not just X"
  survivors, where striking it breaks the sentence. An operator reads the same fact twice in this
  file, once padded and once not — which is precisely the provenance tell the GOAL's *Problem*
  section is about.
- **Evidence:**

  ```
  $ git grep -niwE '(simply|just|essentially|basically|comprehensive|robust|seamless|powerful|elegant|leverage|utilize)' \
      -- bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua
  README.md:268:  ... not just storage.                          <- contrastive
  README.md:395:  ... not just in principle. ...                 <- contrastive
  bin/uv-manager:136: ... keep it just as cheap.                 <- comparative idiom
  bin/uv-manager:178: ... not just on a normal return. ...       <- contrastive
  bin/uv-manager:389: ... not just storage location. ...         <- contrastive
  bin/uv-manager:597: ... "write error: Broken pipe"; `cat` just <- FILLER
  share/modulefiles/uv/main.lua:144: --  just storage location.  <- contrastive

  $ sed -n '736,737p' bin/uv-manager
      # Heredoc rather than printfs, for the same reason as uvm_status: `cat`
      # dies quietly on SIGPIPE where bash's printf reports EPIPE.
  ```

  The project's own preferred phrasing exists 140 lines away, and `AGENTS.md` § *Output discipline*
  uses it too: "`cat` dies quietly on `SIGPIPE`". That sibling is the evidence this survivor is
  filler rather than load-bearing. The fix is one word.
- **Touches:** R1; `invariants.md` §12 (prose voice). Not a high-blast-radius region.

**Outstanding publish-time obligation, not a finding.** R1's second clause — "Every surviving hit
SHALL be listed in the PR body with the reason it stays" — cannot be satisfied from the branch. The
seven survivors above, with the right-hand classification column, are the list `/uvm-publish` must
carry, minus whichever F1 removes.

## Human-gate triggers

None. F1 sits in a banner comment above `uvm_status`, which is not a high-blast-radius region, and
it touches no §1 (architecture partitioning), §2 (`exec` semantics) or §6 (installer environment)
invariant. No human sign-off gate is required before the next step.

---

## Review cycle 2 — approved (2026-08-07)

- **Reviewed commit:** 7c85613723e109274969535bfd5ae6ed2a339a0b  ·  **Base:** `main`
- **Verdict:** approved  ·  **Cycle:** 2 of ≤3
- **Mode:** fresh blind pass over the full spec-excluded diff, the default for a later cycle — not a
  narrow re-check of cycle 1's F1. The reviewer was a new subagent given `GOAL.md`, `invariants.md`,
  `review-rubric.md` and the runnable repo, and was not told a prior cycle existed.

Contract-drift check: `git log --oneline main..HEAD -- spec/prose-and-comment-pass/GOAL.md` still
returns only the shaping commit `692adf1`. The contract did not move between cycles.

### Verification run

Independent of cycle 1, and again built on a detached `git worktree` of `main` under `$TMPDIR` so
every HEAD-versus-`main` claim is two real drives. The worktree was removed and pruned before
hand-back; `git worktree list` shows only the repository.

- `bash -n bin/uv-manager` → clean. `.agents/factory/bin/lint.sh` → exit 0, five of five checks,
  under bash 3.2.57.
- Every changed line in `bin/uv-manager` classified: 22 of 23 are comment lines. The one code line is
  `-*)         ;;`, where `sed -n l` on both refs shows the executable prefix byte-identical and only
  the trailing comment removed. `git diff main...HEAD --check` clean.
- `temp_root.sh uvm status`, `temp_root.sh --offline uv --version`, and
  `temp_root.sh --offline --arch aarch64 uvm status` → rc 0 on both refs, output identical modulo the
  repo path and the `mktemp` suffix. Deeper post-condition drive on both: `uv 9.9.9 (fixture)`,
  `current -> versions/9.9.9`, binary present, `lock left: none`.
- The offline fixture's own assertion that `UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` were
  scrubbed (§6) passed on every offline drive.
- No-root failure block, `env -i` with all six scratch candidates unset → rc 1, empty stdout, stderr
  byte-identical to `main`, every candidate named with its reason.
- All four heredocs driven on both refs — `uvm help`, `uvm clean` without `--yes`,
  `uv self update --help`, `uv self update --dry-run` → rc 0, stdout identical in every case.
- Trampoline generation drive plus `wc -l` → **13 lines**, which is the executed evidence that
  `main`'s "four-line `sh` script" was factually wrong and the branch's "short" corrects it.
- Exclamation and non-ASCII census over the four files → zero prose `!`; the only non-ASCII codepoint
  is the em dash. `git grep -nwE '(R[0-9]|P[0-9]|F[0-9])'` over the four → empty, no spec id leaked.

Orchestrator spot-check, run outside the subagent: `git status --porcelain` empty, no leftover
worktree, R1 census 6 + 0, aggregate 1723 against `main`'s 1724, and the cycle-1 F1 site at
`bin/uv-manager:597` now reads ``  `cat` dies quietly on SIGPIPE. ``

The cycle-1 methodology note stands and cost this reviewer a false green too: its first batched R1
census used a shell variable for the pathspec, which `zsh` does not word-split, and returned zero
hits on both refs. Spell the four paths out literally.

### Requirement → evidence matrix

| R-ID | Verified how (command + post-condition) | Status |
|------|------------------------------------------|--------|
| R1 | Both census commands, four explicit paths, HEAD and `main`. `main`: 10 + 3 = **13**, reproducing the GOAL baseline. HEAD: **6 + 0**. Cycle 1's F1 survivor is gone; the four removals are `bin/uv-manager:301`, `:512`, `:599` and `README.md:466`. All six survivors are the contrastive "not just X" or the comparative "just as cheap" — none is strikeable without loss. | ✅ |
| R2 | Graded by reading all 846 lines, as the criterion specifies. Two restatements removed (`# Decide whether provisioning is needed, then do it.`, `# ignore other flags`). The reviewer hunted the surviving comments for paraphrase and reported none: `# Re-check under the lock.` names double-checked locking, `# Nothing resolved. …` states the §3 invariant, and the inline `# atomic rename within versions/` and `# a prior run may have died holding this name` are why, not what. | ✅ |
| R3 | `cat <four> \| wc -l` → **1723** HEAD, **1724** `main`. Script 848→846 pays for README 570→571. Met, but by one line: the GOAL's *vision* of "shorter than it is now" is satisfied nominally rather than substantially. | ✅ |
| R4 | Line-by-line classification of the diff, plus lint and the six sandbox drive comparisons above. No function name, variable name, exit code or heredoc body changed. | ✅ |
| R5 | Zero bytes of user-facing message text differ from `main` — confirmed by identical stdout across all four heredoc drives and byte-identical stderr on the no-root block with all six candidates and their reasons. The one exclamation mark in the four files went with `"everything's installed!"` at `:334`. | ✅ (see trust note) |
| R6 | Sample at `README.md:14-20` diffed against a real drive: label-plus-pad width 23 on both, two-space separator, field order matching `uvm_status`'s heredoc. `git log -S'invoked as' -- bin/uv-manager` shows the field arrived in `f902ebf` with no README update, so the branch is repairing a pre-existing same-commit-rule violation rather than creating churn. | ✅ |

**Requirements taken on trust.** Unchanged from cycle 1: R5's "SHALL be audited" half is a claim about
process, not an observable post-condition. Its consequential half is verified by identical output
across the whole message surface. Nothing else was downgraded to trust.

### Findings

**None.** Six candidates were raised and all six died under an executed check — including a challenge
to the new `# Fast path: already on disk, so no lock and no network.` comment (refuted: the early
return at `:302-305` precedes `uvm_acquire_lock` at `:307` and `uvm_fetch` at `:335`, and the offline
drive left no lock), and a challenge to whether `-*)  ;;` is an executable-line change under R4
(refuted by byte comparison).

Two unmapped changes carry forward from cycle 1 as human triage, neither blocking: the modulefile's
"extremely fast" → "fast" at `share/modulefiles/uv/main.lua:50`, which trims Astral's own verbatim
tagline under our house style, and the six `--` → `—` conversions in
`etc/uv-manager.conf.example`, which normalize against em dashes the file already carried at `:1` and
`:45`. This cycle adds one cosmetic observation, explicitly not a finding: the shortened lines at
`etc/uv-manager.conf.example:37` and `:130` were not rewrapped, so they sit at 60 and 67 characters in
a file that otherwise wraps at 74–78.

**Outstanding publish-time obligation, carried from cycle 1 and now shorter by one.** R1's second
clause requires every surviving hit to be listed in the PR body with the reason it stays. The list
`/uvm-publish` must carry:

```
README.md:268                      ... not just storage.              contrastive
README.md:395                      ... not just in principle. ...     contrastive
bin/uv-manager:136                 ... keep it just as cheap.         comparative idiom
bin/uv-manager:178                 ... not just on a normal return.   contrastive
bin/uv-manager:389                 ... not just storage location.     contrastive
share/modulefiles/uv/main.lua:144  ... just storage location.         contrastive
```

### Human-gate triggers

None. There are no CONFIRMED findings, so no high-blast-radius region and no §1, §2 or §6 invariant is
implicated. Approved for `/uvm-publish`.
