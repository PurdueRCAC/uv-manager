---
name: uvm-release
description: >-
  Human-gated cutter of uv-manager versions — the operational sibling of uvm-harness that fills the gap
  uvm-publish leaves ("this skill does not bump the version or tag"). Two modes: `release` (a final
  version off main) and `pre-release` (an aN/bN/rcN off main, flagged prerelease on GitHub). Shared
  core: bump the single version source in bin/uv-manager, follow it into README.md, run the gate
  (lint.sh + sandbox drives + version consistency), sign an annotated tag, then — only after an
  explicit human OK before the first irreversible step — push and `gh release create`, and verify the
  published tag clones back with working symlinks. Rehearses the whole thing in an isolated git
  worktree first. Operational, NOT a lifecycle step.
disable-model-invocation: true
argument-hint: "<release|pre-release> <version> [--skip-dry-run] | status"
allowed-tools: Read, Edit, Write, Grep, Glob, AskUserQuestion, Bash(uv run *), Bash(.agents/factory/bin/*), Bash(bash -n *), Bash(git status *), Bash(git branch *), Bash(git rev-parse *), Bash(git log *), Bash(git show *), Bash(git diff *), Bash(git fetch *), Bash(git pull *), Bash(git switch *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git tag *), Bash(git worktree *), Bash(git clone *), Bash(git ls-files *), Bash(git ls-remote *), Bash(gh release *), Bash(gh repo *), Bash(mktemp *), Bash(head *), Bash(tail *), Bash(ls *)
---

# uvm-release — cut a version, human-gated

## When to Use

Invoke `/uvm-release` to bump the version and cut a release — the concern `/uvm-publish` explicitly
leaves out. It is an **operational sibling of `/uvm-harness`, not a lifecycle step**: it touches no
`spec/`, no FSM, no `GOAL/PLAN/TECH/REVIEW`. It moves the version, the tag, and the published release.

This is where **irreversible, outward** publishing happens. A tag can be deleted, but a tag that sites
have already cloned cannot be recalled, and this repository is deployed by `git clone` into
`/apps/external/uv/<version>` at national computing centers. So it always confirms before the first
push, and rehearses everything in an isolated git worktree first.

Reference: [`invariants.md`](../../factory/invariants.md) §12 (version single-sourced; the same-commit
rule; `bin/` symlinks) and the `AGENTS.md` § *Environment & working rules*.

**Harness portability.** Runs on any harness — see [`portability.md`](../../factory/portability.md).
Run the *Current state* commands yourself if not auto-injected; ask in plain text and STOP if
`AskUserQuestion` is unavailable. `git`, `gh` and the worktree rehearsal are portable shell.

## User Instructions

Additional instructions provided with the invocation: $ARGUMENTS

## Current state (injected at load)

- Branch: !`git branch --show-current`
- Tree (must be clean): !`git status --porcelain | head -n 20`
- Version (the only source): !`grep -n '^readonly uvm_version=' bin/uv-manager || true`
- Recent tags: !`git tag -l --sort=-v:refname | head -n 8`
- main tip: !`git log --oneline -3 main 2>/dev/null`
- Default remote branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "(gh unavailable)"`

## Argument Parsing

Parse `$ARGUMENTS` case-insensitively for the mode and flags; the version is case-sensitive. If
self-contradictory or ambiguous, STOP and ask.

- **Mode** (first positional, required): `release` | `pre-release`. Missing → STOP and offer both via
  `AskUserQuestion`.
- **`status`** as the sole token → Step 0 fast path, no work.
- **Version** (second positional, required — **never inferred or auto-bumped**; a published string is
  too consequential to guess). Validate: SemVer-shaped, **no `v` prefix** (it must match the string
  assigned to `uvm_version`), strictly greater than the latest existing tag, and not already a tag.
  **Mode consistency:** `pre-release` REQUIRES a suffix (`X.Y.Za1`, `X.Y.Zrc1`); `release` REQUIRES a
  final version with no suffix. Any mismatch → STOP.
- **Flags:** `--skip-dry-run` opts out of Step 2. It must be explicit, and it is discouraged.
- Anything unrecognized → STOP and ask.

**Tag convention.** There are no tags yet, so the first run establishes it: bare `X.Y.Z`, matching the
`uvm_version` string exactly, so `git tag -l` and `uv-manager --version` read the same. Once tags
exist, follow whatever the existing ones do rather than this paragraph.

## Safety Principles

- **Confirm before anything irreversible.** Steps 1–6 are all reversible in-tree. The single Step 7
  `AskUserQuestion` gate precedes the first push. **No push without an explicit human OK.**
- **Dry-run first (default on).** The bump and the full gate are rehearsed in an isolated
  `git worktree` before a single real ref moves.
- **The gate is non-negotiable.** `.agents/factory/bin/lint.sh`, the sandbox drives, and the
  version-consistency check must all pass. A red gate is a STOP, never an override-to-ship. There is
  no test suite standing behind this; the gate is the whole safety net.
- **Version is single-sourced** at `readonly uvm_version=` in `bin/uv-manager`. Exactly one other place
  quotes it — the sample `uv-manager status` output in `README.md` — and it moves in the same commit.
  Never hardcode it anywhere else. The `uvm_help` heredoc interpolates the variable and needs no edit;
  confirm that is still true rather than assuming it.
- **Signed tags only.** `git tag -s`, verified with `git tag -v` **before** any push.
- **Never force-push, never rewrite `main`.** The bump is an ordinary commit on `main`.
- **Never `rm`.** Use `del`; `git worktree remove` cleans the rehearsal.
- **Operational, not meta.** This skill never recurses and never records a finding unasked. Harness
  friction found here is named in the Step 10 report and recorded only on the human's say-so.
  `/uvm-harness` applies findings; it does not receive them, so it is a consumer, not a destination.
- Use `[release]` subjects on the bump commit. Keep the `Co-Authored-By` trailer.

## Procedure

| mode | base | tag lands on | `gh release` | GitHub "Latest" moves |
|---|---|---|---|---|
| **release** | `main` | the bump commit on `main` | plain | yes |
| **pre-release** | `main` | the bump commit on `main` | `--prerelease` | no |

### Step 0 — status fast path (when requested)
Report the current `uvm_version`, the latest tags, the `main` tip, whether the intended target is
already a tag, and whether a release looks in flight (an unpushed local tag, or a bump commit with no
tag). Stop.

### Step 1 — Parse and pre-flight
Resolve mode and version per Argument Parsing. Require **`main`** and a **clean tree**; otherwise
STOP. `git fetch origin`; confirm `main` matches `origin/main` (diverged → STOP). STOP if the target
version is already a tag, is not greater than the latest, or violates the mode/suffix rule.

### Step 2 — Worktree dry-run (default on; `--skip-dry-run` opts out)
Rehearse the whole thing in isolation before any real ref moves:

1. `dir=$(mktemp -d)` outside the repo, so it never dirties the working tree;
   `git worktree add --detach "$dir/rel" main`.
2. In that worktree, apply Step 4 (the bump) and run the **full gate** from Step 5.
3. `git worktree remove "$dir/rel"`. Any red → STOP and report; **nothing in the real tree moved.**

A few permission prompts may appear for commands run against the temporary worktree path. That is
expected.

### Step 3 — (no branch setup)
Both modes land on `main` directly. There is no release branch: this repository has a single line of
development, and a release is a tagged commit on it.

### Step 4 — Shared core: bump the version
1. Edit the `readonly uvm_version="…"` line in `bin/uv-manager` to the target version. This is the only
   source.
2. Follow it into `README.md` — the sample `uv-manager status` output near the top quotes the version.
   `git grep -n "$old_version"` and confirm you have caught every occurrence; anything found outside
   those two files is either a legitimate example pin (a `UVM_PIN=0.12.2` for *uv's* version,
   which is unrelated) or a violation of the single-source rule worth reporting.
3. Commit `[release] Bump version to X.Y.Z`, staging exactly the files you changed.

### Step 5 — Gate (non-negotiable)
Run all of:

```
.agents/factory/bin/lint.sh
.agents/factory/bin/temp_root.sh --offline uv --version
.agents/factory/bin/temp_root.sh --offline --arch aarch64 uvm status
.agents/factory/bin/temp_root.sh uvm --version        # must print exactly X.Y.Z
.agents/factory/bin/temp_root.sh uvm help             # must render, unconfigured, without a state root
```

Assert the post-conditions, not just exit 0: the offline drive reports the fixture version and leaves
a `current` symlink pointing at `versions/<fixture-version>`; `uvm --version` prints the new version;
`uvm help` works with no state root configured, which is the property that makes an unconfigured node
recoverable. Any failure → STOP.

### Step 6 — Signed tag
```
git tag -s X.Y.Z -m "uv-manager X.Y.Z"
git tag -v X.Y.Z
```
Verify the signature **before anything is pushed**. A signing or verification failure is a STOP.

### Step 7 — PAUSE: confirm before anything irreversible
Everything so far is reversible in-tree. Draft the release notes from `git log <lasttag>..HEAD` — or
from the full history for the first release — grouped by `[category]`, linking `#NN` issues where
present. Then present via `AskUserQuestion`: the mode, the version, where the tag lands, whether
GitHub "Latest" will move, the drafted notes (human-editable), and the exact push and publish
commands. **Nothing is pushed until an explicit OK.**

### Step 8 — Push and publish
```
git push origin main
git push origin X.Y.Z
gh release create X.Y.Z --verify-tag [--prerelease] --title "uv-manager X.Y.Z" --notes-file <file>
```
The tag must reach the remote before `--verify-tag`. Use `--prerelease` in `pre-release` mode only.

### Step 9 — Verify after publish
The deployment check that matters for this project is that a **fresh clone of the tag is deployable**,
because sites install by cloning into `/apps/external/uv/<version>` and the `bin/` symlinks are what
make the four entry points one script:

```
d=$(mktemp -d)
git clone --depth 1 --branch X.Y.Z <repo-url> "$d/uv-manager"
ls -l "$d/uv-manager/bin"                       # uv, uvx, uvm must still be symlinks
"$d/uv-manager/bin/uvm" --version               # must print X.Y.Z
"$d/uv-manager/bin/uvm" help                    # must render with no state root configured
```

Then confirm `gh release view X.Y.Z` shows the intended prerelease flag, and that `main` and the tag
point where you expect. Clean up with `del "$d"`.

### Step 10 — Report
Mode, version, tag SHA and signature status, the release URL, whether "Latest" moved, the results of
the fresh-clone check, and any caveat. Note explicitly whether sites tracking a moving `main` will
pick this up automatically or need to be told to re-clone a tag.

Name any **harness friction** this release exposed — a skill instruction that was wrong or ambiguous,
a command that had to be hand-fixed — and offer to record it. `/uvm-harness` reads only
`spec/*/META.md`, so an unrecorded finding dies with the session. On the human's OK, write it to the
`META.md` of a cycle in this release's commit range (the newest, if several) — create it from
[`templates/META.md`](../../factory/templates/META.md) if absent, else append — with
`origin=uvm-release:<step>` and `status=open`, as its own `[harness]` commit. No cycle in range, or no
OK: report it and stop.

## Examples

- `/uvm-release release 0.3.0` — cut a final version off `main`; "Latest" moves.
- `/uvm-release pre-release 0.3.0rc1` — release candidate; GitHub "Latest" stays where it is.
- `/uvm-release status` — current version, tags, `main` tip, in-flight check; no changes.

## Notes

- **Reference `invariants.md` §12; do not duplicate it.** This skill introduces no new invariant.
- A version bump is only worth cutting when a site would want it. A `[harness]`-only change to
  `.agents/` alters nothing a site deploys and does not need a release.
- The Lmod modulefile derives its prefix from `myModuleVersion()`, so it is version-agnostic and needs
  no edit at release time. A site that deploys per-version module files still has to add one; say so
  in the release notes when the version is meant to be pinned.
