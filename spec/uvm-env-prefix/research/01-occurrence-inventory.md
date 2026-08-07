# Research 01 — Occurrence inventory for the `UV_MANAGER_*` → `UVM_*` rename

Working tree at `feature/uvm-env-prefix`. Counts are literal `UV_MANAGER` matches, case-sensitive.

**138 occurrences in 21 files.** 23 are excluded as historical (`spec/**`, `issues/uvm-env-prefix.md`);
**115 must change** across 18 files.

## Per-file totals and classification

| File | n | Class | Notes |
|---|---:|---|---|
| `README.md` | 25 | user-doc | table, sample `status`, modulefile excerpt, sbatch/Globus examples |
| `bin/uv-manager` | 20 | mixed | 8 functional, 4 user-doc (help heredoc), 4 user-doc (printf'd messages), 3 source comment, 1 string literal |
| `etc/uv-manager.conf.example` | 13 | user-doc | 11 `#export` lines, 2 prose |
| `issues/trampoline-ignores-platform-override.md` | 13 | **live-seed** | includes a runnable repro block |
| `issues/uvm-env-prefix.md` | 11 | **historical** | do not touch |
| `spec/uvm-env-prefix/GOAL.md` | 11 | **historical** | do not touch |
| `.agents/factory/bin/temp_root.sh` | 11 | mixed | 7 functional, 4 comment |
| `AGENTS.md` | 7 | factory-doc | edit via `AGENTS.md`; `CLAUDE.md` is a symlink |
| `.agents/factory/invariants.md` | 7 | factory-doc | §-numbered normative list |
| `share/modulefiles/uv/main.lua` | 4 | mixed | 1 functional `setenv`, 1 commented `setenv`, 2 comment |
| `.agents/factory/methodology.md` | 3 | factory-doc | |
| `.agents/factory/ears.md` | 2 | factory-doc | R2/R3 EARS examples |
| `ROADMAP.md` | 2 | live-seed | **needs judgment, not sed** — see below |
| `issues/test-harness.md` | 2 | **live-seed** | |
| `.agents/factory/templates/TECH.md` | 1 | factory-doc | **`verify:` example — seeds a broken command** |
| `.agents/factory/review-rubric.md` | 1 | factory-doc | |
| `.agents/factory/fixtures/uv-install/install.sh` | 1 | factory-doc | comment only, not executed |
| `.agents/skills/uvm-{feature,release,review}/SKILL.md` | 1 each | factory-doc | |
| `spec/uvm-env-prefix/META.md` | 1 | **historical** | title line |

Per-variable across the whole tree: `ROOT` 65, `PLATFORM` 21, bare `UV_MANAGER_*` 14,
`INSTALL_URL` 13, `PIN` 12, `LOCK_STALE` 7, `LOCK_TIMEOUT` 6.

## Functional occurrences (the ones that break execution)

| Location | Occurrence | Replacement |
|---|---|---|
| `bin/uv-manager:84` | `if [[ -n "${UV_MANAGER_ROOT:-}" ]]; then` | `${UVM_ROOT:-}` |
| `bin/uv-manager:85` | `uvm_base="${UV_MANAGER_ROOT}"` | `"${UVM_ROOT}"` |
| `bin/uv-manager:86` | `uvm_base_origin="UV_MANAGER_ROOT"` | `"UVM_ROOT"` — this is the string `status` prints (R4) |
| `bin/uv-manager:145` | `arch="${UV_MANAGER_PLATFORM:-$(uname -m)}"` | `${UVM_PLATFORM:-…}` |
| `bin/uv-manager:158-161` | `pin=`, `lock_timeout=`, `lock_stale=`, `install_base_url=` | `UVM_PIN`, `UVM_LOCK_TIMEOUT`, `UVM_LOCK_STALE`, `UVM_INSTALL_URL` |
| `temp_root.sh:78,80,81` | assign / `export` / `mkdir -p` of `UV_MANAGER_ROOT` | `UVM_ROOT` |
| `temp_root.sh:88,89` | `UV_MANAGER_INSTALL_URL="file://…"` + `export` | `UVM_INSTALL_URL` |
| `temp_root.sh:92` | `{ UV_MANAGER_PLATFORM="$arch"; export …; }` | `UVM_PLATFORM` |
| `main.lua:119` | `setenv("UV_MANAGER_ROOT", root)` | `setenv("UVM_ROOT", root)` |
| `main.lua:129` | commented `-- setenv("UV_MANAGER_PIN", "0.12.2")` | `UVM_PIN` |
| `TECH.md:29` | `verify:` string containing `$UV_MANAGER_ROOT/$(uname -m)/current` | `$UVM_ROOT/…` |
| `README.md:302` | `os.environ["UV_MANAGER_ROOT"]` in the flock diagnostic one-liner | `"UVM_ROOT"` |
| `issues/trampoline-…:29-33` | repro block writing under `$UV_MANAGER_ROOT/x86_64-glibc2.28/…` | `$UVM_ROOT/…` |

## Trap checks — results

**Case variants: none.** Every case-insensitive `uv[_ ]manager` match in the tree is the uppercase
literal `UV_MANAGER`. Zero occurrences of `uv_manager`, `Uv_Manager`, or any mixed case. A
case-insensitive replace of `UV_MANAGER_` would therefore be *correct*, but do not run one: the tree
also holds **183 lowercase `uvm_` identifiers** in `bin/uv-manager` (function and variable names) and
**165 `uv-manager` program-name strings**. Neither contains `UV_MANAGER`, so a case-*sensitive*
`s/UV_MANAGER_/UVM_/g` cannot touch them. Use `-s`, not `-i`.

**`UV_MANAGER` without a trailing underscore: none.** All 138 matches are followed by `_`. The 14
"bare prefix" hits are `UV_MANAGER_` followed by `*`, whitespace or end-of-token — prose referring to
the family, e.g. `` `UV_MANAGER_*` variables ``. `s/UV_MANAGER_/UVM_/g` renders these `UVM_*`, which
reads correctly in every case except `ROADMAP.md:19` (below).

**Word boundaries are clean.** The only characters preceding a match are space, `` ` ``, `"`, `{`, `$`,
or line-start. No longer identifier embeds the prefix.

**Heredoc quoting: no hazard.** `uvm_help` uses `cat <<EOF` (unquoted, so `${uvm_version}` interpolates).
The six names at lines 767-771 appear as bare text with no `$`, so they neither expand today nor after
the rename. *But the block is column-aligned at 26* and `UV_MANAGER_INSTALL_URL` (22 ch) is what sets
that width. After the rename the longest is `UVM_INSTALL_URL` (15 ch); a plain sed leaves 8 columns of
dead gutter. Re-align by hand. Same for line 771, which pairs
`UV_MANAGER_LOCK_TIMEOUT / UV_MANAGER_LOCK_STALE` on one line with a continuation description.

**`verify:` / code-fence seeds.** One: `.agents/factory/templates/TECH.md:29`. It is the template every
future `TECH.md` copies, so leaving it stale seeds a `$UV_MANAGER_ROOT` (empty → `/$(uname -m)/current`)
into unrelated cycles. `README.md:302` and `issues/trampoline-…:29-33` are the other two runnable
blocks.

**`.gitignore` / `.security/`.** `.security/` **does not exist**. `.gitignore` covers `.security/`,
`.local/`, `.agents/settings.local.json`, `.agents/worktrees/`, `__pycache__/`, `*.pyc`, `.DS_Store`.
The only ignored path present is `.agents/factory/bin/__pycache__/`, which contains no match. **No
untracked or ignored file contains `UV_MANAGER`.** No `.local/`, no worktrees.

**Symlinks.** `.claude → .agents`, `CLAUDE.md → AGENTS.md`, `bin/{uv,uvm,uvx} → uv-manager`. None of
the 18 target files is a symlink, but `sed -i` / `perl -pi` **replace the path**, so a glob that
reaches `CLAUDE.md` or `.claude/**` would convert a symlink into a regular file. Drive the transform
off `git grep -l`, which never lists symlink duplicates (confirmed: the per-file totals sum to exactly
138 with no double-counting). `lint.sh` only validates the `bin/` symlinks, not these two — a broken
`CLAUDE.md` would pass lint.

## `UVM_` namespace: current occupants, no collisions

| Name | Where | Status |
|---|---|---|
| `UVM_SANDBOX` | `temp_root.sh:79-80` | keep (non-goal) |
| `UVM_FIXTURE_DIR` | `temp_root.sh:86-89` | keep |
| `UVM_FIXTURE_VERSION` / `_EXIT` / `_BROKEN` | `fixtures/uv-install/install.sh` | keep; **passed in by a drive** |
| `UVM_ROOT` / `PIN` / `PLATFORM` / `INSTALL_URL` / `LOCK_TIMEOUT` / `LOCK_STALE` | only `spec/uvm-env-prefix/GOAL.md`, `issues/uvm-env-prefix.md` | prose about this cycle; both files are excluded, so **no file being transformed already contains a target name** — no duplicate definitions, no collisions |

## Recommended mechanical transform

```sh
cd /Users/geoffrey/Software/github.com/purduercac/uv-manager
perl -pi -e 's/UV_MANAGER_/UVM_/g' \
  $(git grep -l 'UV_MANAGER_' -- . ':!spec/' ':!issues/uvm-env-prefix.md')
```

`perl -pi` rather than `sed -i`: BSD and GNU `sed` disagree on whether `-i` takes an argument, and this
repo is developed on macOS and deployed on Linux. Dry-run verified: applying this to those 18 files
leaves **zero** residual `UV_MANAGER` in them.

**Excluded (must retain the old names):** `spec/uvm-env-prefix/GOAL.md` (11), `spec/uvm-env-prefix/META.md`
(1), `issues/uvm-env-prefix.md` (11) — including its occurrence-count table at lines 27-32, whose
numbers (36/7/5/5/4/4 = 61) are the four-shipping-file count as of when it was written.

**Verify:** `git grep -n UV_MANAGER_` must return only those three paths (23 lines).

## Manual work the sed cannot do

1. **`ROADMAP.md:19` becomes false.** The sentence reads "`UV_MANAGER_*` sits inside `uv`'s own
   namespace… `UVM_*` is unambiguously ours." Substituting yields "`UVM_*` sits inside `uv`'s own
   namespace… `UVM_*` is unambiguously ours." Rewrite to past tense, or drop the entry — item 1 is
   marked **adopted** into this spec, so `/uvm-publish` will likely close it. `ROADMAP.md:39`
   (heading for item 4, the trampoline defect) is a plain `UV_MANAGER_PLATFORM` → `UVM_PLATFORM`.
   The line-20 claim "61 occurrences across four files" is already stale (currently 62).
2. **`temp_root.sh` scrub (R6) is a behavior change, not a rename.** Line 68 scrubs
   `^UV_[A-Za-z0-9_]*=`, which does **not** match `UVM_` — after the rename a developer's exported
   `UVM_PIN` reaches every drive. A blanket `UVM_*` scrub would also strip `UVM_FIXTURE_VERSION`/
   `_EXIT`/`_BROKEN`, which drives deliberately pass in. Unset the six by name, before line 78.
3. **Help heredoc re-alignment** (`bin/uv-manager:767-771`).
4. **`etc/uv-manager.conf.example:8`** — "The wrapper reads only `UV_MANAGER_*` variables" becomes
   "only `UVM_*` variables", which is now the actual point of the file; verify the surrounding
   paragraph still reads as intended.
5. **`.agents/factory/invariants.md`** is kept in lockstep with `AGENTS.md`; both change, and both
   must still agree after the edit.
