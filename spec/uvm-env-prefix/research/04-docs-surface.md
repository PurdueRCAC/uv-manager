# Research — the user-facing documentation surface

Topic: `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`, and the
`uvm_help` heredoc. Counts confirmed: README 25, conf 13, modulefile 4, script 19 (of which 5 are
in the help heredoc).

---

## 1. README.md — occurrence map by context

| Line | Context | Note |
|------|---------|------|
| 16 | **Transcript** — abridged `uv-manager status` output | `(from UV_MANAGER_ROOT)` is `${uvm_base_origin}`, set at `bin/uv-manager:86`. Must become `(from UVM_ROOT)` or the README shows output the script no longer produces. |
| 116 | Prose — "Resolves the state root" | |
| 123 | **ASCII tree** — `$UV_MANAGER_ROOT/` is the root node | |
| 245 | **Modulefile excerpt** (lua fence) | Abridged copy of `main.lua:119`; both move together. |
| 258, 259 | Prose — the architecture-neutrality argument | Two occurrences: bare, and `$UV_MANAGER_ROOT/bin`. |
| 290 | Prose — mirror base for pre-warming | `UV_MANAGER_INSTALL_URL`. |
| 302 | **Copy-pasteable command** — `python3 -c '…os.environ["UV_MANAGER_ROOT"]…'` | Breaks if not renamed. Longest line in the file (146 → 142). |
| 316 | Prose — "The state root" | |
| 343 | Prose — the platform key | |
| 370 | Prose — link mode | |
| 406 | Prose — purge mitigation 1 | Pairs with the doctor string at `bin/uv-manager:724`. |
| 466 | Prose — Globus Compute, UEP inheritance | |
| 470 | Prose — pin authority | |
| 478, 479 | **Copy-pasteable `worker_init` block** | `export UV_MANAGER_ROOT=…`, `export UV_MANAGER_PIN=…`. |
| 494 | **Troubleshooting** — quoted error + paraphrase | See §5. |
| 511 | Inline shell — `du -sh $UV_MANAGER_ROOT/*` | |
| 521–526 | **Reference table**, six rows | One per variable. |
| 531 | Prose — where the exported `UV_*` paths live | |

Transcripts and copy-pasteable text that would otherwise drift: **16, 245, 302, 478, 479, 494**.
Everything else is prose or a reference row.

## 2. Design notes — read in full (README:419–449)

**(a) Does it already discuss naming or the `UV_*` namespace?** Not for variables. It contains the
*subcommand* analogue: the dispatch note says `basename $0` "gives wrapper-specific commands a home,
`uv-manager`, without shadowing `uv`'s own namespace, which matters because `uv` keeps adding
subcommands (`auth`, `format`, `check`, `audit` and `upgrade` are all recent)." That is exactly the
argument in the GOAL's Problem section, applied to commands instead of variables. The
`XDG_CONFIG_HOME` note states the boundary — "Storage is the wrapper's business; resolution is not"
— but says nothing about how the boundary is spelled.

**(b) Recommendation: yes, add one note — three sentences.** Two reasons that outweigh the
delete-first bias. First, the README will now show `UVM_ROOT` and exported `UV_CACHE_DIR` within a
few lines of each other (Reference §"Wrapper environment variables" vs §"`uv` variables the wrapper
sets"); without a note, the mixed prefixes read as an oversight rather than a boundary, which is the
opposite of the rename's stated purpose. Second, the note is a guard: it tells the next contributor
why the five exported names are *not* to be made consistent with the wrapper's own. The dispatch
note already carries half the argument, so this is completing a record rather than opening a new
one — and placing it immediately after the dispatch note keeps the two namespace arguments together.

Draft, to insert after the `basename $0` note (README:427):

> **`UVM_*` for the wrapper's own knobs.** `uv` reads dozens of `UV_*` variables and adds more with
> each release, so a name inside that namespace leaves an operator no way to tell what Astral honors
> from what this wrapper invented, and an eventual `UV_MANAGER_*` from Astral would collide silently
> — unrecognised `UV_*` variables are deliberately passed through untouched. The five storage
> variables the wrapper exports keep their `UV_*` names: those are `uv`'s by right. The two prefixes
> are the storage/resolution boundary made visible in the place an operator reads first, the
> modulefile.

Voice check: declarative, no filler, no marketing adjectives, "unrecognised" matches the spelling
already used at README:427.

## 3. `etc/uv-manager.conf.example`

**Header sentence (lines 8–10).** Current text is already loose — the wrapper also reads the six
scratch candidates, and it reads `UV_INSTALL_DIR` / `CARGO_DIST_FORCE_INSTALL_DIR` in order to
scrub them. Post-rename the interesting failure is different: a reader who sees `UVM_*` above and
`UV_*` below needs to know that five `UV_*` names are set by the wrapper unconditionally
(`uvm_set_paths`, `bin/uv-manager`) and that setting them in this file has no effect. Draft
replacement, same three-line shape, wrapping at the file's 78 columns:

```
# Everything the wrapper reads for itself is spelled UVM_*. The UV_* names
# below are uv's own configuration, included because these are the settings
# that actually matter on a parallel filesystem and are easy to overlook.
# Five more -- the storage locations -- are exported by the wrapper on the
# executing node and override anything set for them here.
```

**Alignment.** None of the `#export` lines are column-aligned; each is a standalone assignment, so
the 4-character shortening costs nothing. Lines 33, 38, 41, 44, 47, 58, 62, 70, 74, 80 are pure
renames. Line 80 (`UVM_PLATFORM`, 93 → 89 chars) stays over the file's prose width, as it already is.

**Reflow needed** in three paragraphs where the name appears mid-prose: 8–10 (replaced above),
17–19, and 97–102 (line 99, "With the cache under UV_MANAGER_ROOT and a project's .venv on home").

## 4. `share/modulefiles/uv/main.lua`

Four occurrences.

- **Line 22** — inside the DESIGN NOTE's exported-paths table:
  ```
  --   PATH               <prefix>/bin          the wrapper itself
  --   UV_MANAGER_ROOT    <scratch>/.uv         base of the per-user state tree
  ```
  Three aligned columns; the value column starts at 24 and the continuation line 24 hangs under
  column 3. Recommend the **minimal** edit: keep the name field 19 wide, pad `UVM_ROOT` with 11
  spaces. Line length is unchanged at 77, the diff is one line, and lines 21/23/24 are untouched.
  Re-tightening the whole block to the new 8-character maximum would redraw four lines for no gain.
- **Line 40** — prose comment, "the wrapper applies an equivalent cascade of its own when
  UV_MANAGER_ROOT is unset". Reflow lines 38–41.
- **Line 119** — `setenv("UV_MANAGER_ROOT", root)`, the live export.
- **Line 129** — commented-out example `-- setenv("UV_MANAGER_PIN", "0.12.2")`. Standalone, no
  alignment.

**Nothing architecture-bearing is affected.** The file exports `RCAC_UV_ROOT`, `RCAC_UV_VERSION`,
two `PATH` prepends and the state root; only the last is renamed, and it is the architecture-neutral
one by construction. The "Deliberately NOT set here" block (135–136) names the five per-architecture
`UV_*` storage variables, which keep their names under R3, and line 158's advice to set "the
corresponding `UV_*` variables from the wrapper's site config" stays correct.

## 5. Cross-check — output quoted verbatim

- **README:16** — the only true transcript. `(from UV_MANAGER_ROOT)` → `(from UVM_ROOT)`. Origin
  string lives at `bin/uv-manager:86`. Column alignment is unaffected: the origin sits at the end of
  the value, not in the label column.
- **README:494** — the quoted phrase "cannot determine where to keep per-user uv state" contains no
  variable name and does **not** change (`bin/uv-manager:102`). The clause after it — "means
  `UV_MANAGER_ROOT` is unset" — paraphrases the error body at `bin/uv-manager:103` and `:120`, so
  both sides move in the same commit. The candidate-listing `printf '      $%-16s …'` format
  (lines 108–112) is unrelated to the rename and needs no width change.
- **Versions.** README quotes `uv 0.12.2` (line 12) and `uv-manager: 0.2.0` (line 14, from
  `readonly uvm_version` at `bin/uv-manager:21`). No version bump this cycle, so both stand.
  `0.12.2` also appears at README:479, conf:58 and main.lua:129 as pinned examples — unaffected.
- **Not quoted output, but paired strings:** README:406 "Put `UV_MANAGER_ROOT` on non-purged
  storage" ↔ the doctor line at `bin/uv-manager:724`, "Consider pointing UV_MANAGER_ROOT at
  non-purged storage instead."
- No README passage quotes `uv-manager help`, so the reflowed Environment block below has no
  documentation mirror to keep in step.

## 6. The `uvm_help` Environment block

Current rendered output (verified by driving `temp_root.sh uvm help`): the **commands** block puts
descriptions at column 23; the **Environment** block puts them at column 26, and the longest line is
81 characters. The `UV_MANAGER_LOCK_TIMEOUT / UV_MANAGER_LOCK_STALE` pair is folded onto two lines
only because the joined names are 47 characters wide.

With the shorter names the pair fits as two ordinary entries, and both blocks can share column 23.
Exact replacement for `bin/uv-manager:766–772` (widths verified: max line 79, all descriptions at
column 23):

```
Environment:
  UVM_ROOT            Base directory for per-user uv state (set by the module)
  UVM_PIN             uv version to provision and select
  UVM_PLATFORM        Override the architecture key (default: uname -m)
  UVM_INSTALL_URL     Installer base URL, for sites mirroring Astral
  UVM_LOCK_TIMEOUT    Seconds to wait for the provisioning lock (default: 180)
  UVM_LOCK_STALE      Seconds before an untouched lock is broken (default: 600)
```

Name field is 20 characters after a 2-space indent. The two lock descriptions are new text; they
mirror the wording already in the README reference table (rows 525–526), so they introduce no claim
the docs do not already make. A more conservative alternative keeps the folded pair:

```
  UVM_LOCK_TIMEOUT / UVM_LOCK_STALE
                      Provisioning lock wait and staleness, in seconds
```

This is a smaller diff but leaves one entry out of alignment with the other five for no reason once
the names are short. Recommend the split.

## 7. Formatting hazards, collected

1. **README tree diagram (123–133).** The `├──` children are indented relative to the fence, not to
   the `$UV_MANAGER_ROOT/` label, so shortening the root node needs no redraw. The inline comment
   column inside the tree (`(UV_TOOL_BIN_DIR)` and friends) is aligned among the child lines only
   and is untouched — those variables keep their names.
2. **README reference table (519–526).** Markdown pipe table with a `| --- | --- |` separator; no
   fixed widths, so shrinking column 1 by 4 characters is free.
3. **README prose wrap is ~98 columns.** Every occurrence in prose shortens its line by 4; the
   paragraphs at 116–118, 258–260, 289–291, 315–316, 342–345, 369–372, 405–408, 465–471, 493–496 and
   530–531 will look ragged unless refilled. No line grows, so nothing overflows.
4. **README:302** is a 146-character one-liner inside a fence — leave it long, just rename.
5. **`main.lua:22`** is the only column-aligned block in the tree; pad rather than redraw (§4).
6. **`uvm_help`** is the only place where the rename lets alignment *improve* (§6).
7. **conf example** has no aligned columns; only paragraph refill at 8–10, 17–19 and 97–102.
