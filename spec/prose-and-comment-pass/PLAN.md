# PLAN — Prose pass over every comment and user-facing document

> **Status:** Draft for review · **Last updated:** 2026-08-07
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).

## 1. Summary

An audit, not a rewrite. Reading all 1724 in-scope lines produced roughly twenty edits: six of the
thirteen census hits removed, two comments deleted for restating the code they sit above, three
factual or grammatical defects corrected, and one file's punctuation made self-consistent. The other
seven census hits are the load-bearing "not just X" construction and stay, listed with reasons in the
PR body as R1 requires. Four phases, one per file group plus a reconciliation gate, ordered so the
script — where the comment density and the blast radius both concentrate — goes first.

The pass is bounded by R4: no executable statement changes. That makes every gate here either
behavioral (drive the script, compare the post-condition) or textual over comment and message text
only.

## 2. Design

Line numbers below are as of `692adf1` and will shift as edits land; the anchor is the surrounding
text, not the number.

### Census hits removed (six)

| Where | Now | Change |
|-------|-----|--------|
| `bin/uv-manager:25` | "…no separate code path. Note that the dispatch keys on the name…" | Delete "Note that"; the sentence is already declarative without it. |
| `bin/uv-manager:301` | `# Fast path: what was asked for is already on disk. Just repoint.` | Replace the second sentence with the reason the fast path exists — it takes no lock and touches no network. |
| `bin/uv-manager:512` | "…is not more careful, it is just more surface to drift out of date…" | Drop "just" and use the em-dash form already in `AGENTS.md` and `invariants.md`, so the three copies of this sentence agree. |
| `README.md:346` | "Note that `uname -m` reports `arm64` on macOS…" | Delete "Note that". |
| `README.md:466` | "…using `uv` to just-in-time provision a matching environment…" | "…using `uv` to provision a matching environment on demand…" — "just-in-time provision" reads as a verbed noun phrase. |
| `etc/uv-manager.conf.example:130` | "uv waits this long for its own flock-based locks. Note that if your scratch filesystem has flock disabled…" | Delete "Note that". |

### Census hits retained (seven) — the R1 exception list

All seven are `just` meaning *merely* or *equally*, where deletion changes the claim. These go in the
PR body verbatim:

| Where | Text | Why it stays |
|-------|------|--------------|
| `bin/uv-manager:136` | "should override it and keep it just as cheap" | "just as cheap" = *equally cheap*. |
| `bin/uv-manager:178` | "Release on signals too, not just on a normal return." | *not only*. |
| `bin/uv-manager:391` | "would change resolution behaviour, not just storage location" | *not merely*. |
| `bin/uv-manager:599` | "bash's printf builtin reports EPIPE…; `cat` just dies on SIGPIPE" | *merely dies*, which is the whole contrast. |
| `README.md:267` | "would change dependency resolution, not just storage" | *not merely*. |
| `README.md:394` | "Partial loss happens in practice, not just in principle." | *not merely*. |
| `share/modulefiles/uv/main.lua:144` | "would change dependency resolution, not just storage location" | *not merely*. |

### Factual and grammatical defects (three)

These matter more than the vocabulary. Each is a place where a careful reader who checks the claim
finds it wrong, which is the exact failure the GOAL is about.

- **`README.md:448` — "Each is a four-line `sh` script".** A trampoline generated in the sandbox is
  thirteen lines ([`research/01-baseline-output.md`](research/01-baseline-output.md) §E). Replace the
  count with "short"; a number that has to be maintained against a heredoc will drift again.
- **`bin/uv-manager:783`–`784` — "because they are what tells you so".** Plural subject, singular
  verb, and a vague referent. `AGENTS.md` and `invariants.md` both already carry the clear form:
  "because they are what tell you how to configure it."
- **`bin/uv-manager:333`–`334` — `four lines of "everything's installed!"`.** `AGENTS.md` bans
  exclamation marks in source, and the flippancy is out of voice for a comment that documents a real
  provisioning hazard. "four lines of installer chatter" says the same thing.

### Comments deleted for restating the code (R2)

- **`bin/uv-manager:361` — "Decide whether provisioning is needed, then do it."** That is
  `uvm_ensure_uv`'s name expanded into a sentence. The paragraph below it, on a pin being
  authoritative, is the part that earns its place.
- **`bin/uv-manager:559` — `# ignore other flags` on the `-*)` arm.** The arm is `-*) ;;`.

The remaining ~198 comment lines survive the R2 reading. The script's comments were written to this
standard before the standard existed, which is what keeps this pass small.

### Consistency

`etc/uv-manager.conf.example` uses a real em-dash in its title line and `--` as an em-dash in five
places below it (`:11`, `:56`, `:79`, `:95`, `:147`). Normalize to the em-dash the rest of the
repository uses. `README.md:141` writes "7ms" where `AGENTS.md` writes "7 ms".

### Two edits settled at the planning gate

Both were open judgment calls; both were decided in favour of the correction.

- **`README.md:13`–`19` gains the `invoked as:` line.** The sample drops it from the middle of the
  block while the trailing `...` signals only that the tail was cut. A quoted sample that differs from
  a real drive is the same credibility failure as the "four-line" claim, so it is corrected rather than
  left. Costs one line, which R3's aggregate absorbs.
- **`share/modulefiles/uv/main.lua:50` loses "extremely".** Astral's tagline, but it is user-facing
  text shown in `module help`, and a marketing adjective there is what R1 exists to catch. The sentence
  loses nothing factual.

### What is being removed

Two whole comments, one comment sentence, six filler words, and the padding in four sentences that
are being tightened rather than rewritten. Nothing is added except the three corrected claims, which
replace text of comparable length. Expected net: the script loses six to ten lines, the other three
files change at the word level, and R3's aggregate has room it does not need.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | Six census hits removed (P1–P3); seven retained with the reason table above, which becomes the PR-body list (P4). |
| R2 | Two restatement comments deleted; the remaining comment body read line by line in P1 and graded by inspection at review. |
| R3 | No section is expanded. Aggregate line count asserted `<= 1724` by P4's gate. |
| R4 | No executable statement touched, by construction. Gated behaviorally: `bash -n`, `lint.sh`, a function-definition diff against `main`, and the three GOAL-named drives reaching their baseline post-conditions. |
| R5 | The four heredocs and the inline error and diagnostic strings audited in P1. The `uvm_resolve_root` failure block keeps all six candidates, both fixes and the home-directory warning, asserted by P1's gate and compared by eye against [`research/01-baseline-output.md`](research/01-baseline-output.md) §B. |
| R6 | P2 gates the `README.md` sample block: every field label it quotes must still appear in a live `uvm status` drive. |

## 3. Invariant gate (AGENTS.md constitution check)

Checked before research and again against this drafted design.

- **§1 Architecture partitioning** — touched only as *documented text*: the script's state-root and
  trampoline banners, `README.md`'s modulefile warning, and the modulefile's own design note. No path
  construction, no `setenv`, no `prepend_path` changes. The explanations must stay correct, which is
  why P3's checklist re-reads them against the code rather than only for voice.
- **§3 State root resolution** — R5 is the invariant restated as a requirement. The failure block
  keeps every candidate, both fixes, and the home-directory constraint.
- **§7 Output discipline** — untouched. The `printf`-versus-heredoc question was probed and found not
  to reproduce (digest); converting either block would be an executable change and R4 forbids it.
- **§10 Portability floor** — `bash -n` under macOS bash 3.2 runs in every phase gate. A comment edit
  cannot break parsing, but a mangled heredoc terminator can.
- **§12 Project conventions** — the voice rules are the standard being applied. The version
  single-source is checked by `lint.sh`; no edit goes near `readonly uvm_version`. P4 greps the script
  and README for feature-scoped spec ids.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| — | — | — |

## 4. Rabbit holes (resolved)

- **Does the census baseline hold, and is the GOAL's `-w` warning real?** Yes to both, and the trap is
  worse than documented: the first census run here returned zero hits because zsh does not word-split
  an unquoted variable, so a four-path pathspec collapsed into one nonexistent path and git reported
  clean. Every gate spells the four paths out ([`00-digest.md`](research/00-digest.md)).
- **Is the "four-line `sh` script" claim true?** No — thirteen lines, generated and counted in the
  sandbox ([`01-baseline-output.md`](research/01-baseline-output.md) §E).
- **Do the `printf` blocks leak `write error: Broken pipe`?** Not reproducible, with default signal
  disposition or with SIGPIPE ignored in the parent. No `issues/` seed filed.
- **What is the exact baseline text R4/R5/R6 compare against?** Captured verbatim before any edit, in
  [`01-baseline-output.md`](research/01-baseline-output.md).

## 5. Risks & open questions

- **R3's only additive edit is the `invoked as:` line.** Everything else in the pass removes or
  replaces text. If the script's comment edits come in lighter than the six-to-ten lines estimated
  above, the aggregate still has 1724 − 1 = 1723 lines of headroom, so the guard is not tight. Worth
  knowing rather than discovering at P4.
- **R2 cannot be gated.** There is no grep for a restatement. P1's gate is blind to it by
  construction, so the phase body marks it inspection-only and `/uvm-review` must read the comment
  diff rather than trust the green.
- **The function-definition diff catches renames, not rewrites.** It would not notice a changed
  comparison operator inside a function whose name is unchanged. The drives are what cover that, and
  they exercise provisioning, both architectures, the status path and the no-root failure path — but
  not `uvm_doctor`'s damage detection, `uvm_clean`, or lock contention. A reviewer reading the diff
  for "is this only comments and strings" remains the real guard.
- **Nothing here needs a real cluster.** The pass changes no behavior, so the usual "only confirmable
  on the cluster" caveat does not apply. The one cluster-adjacent claim being edited is `README.md`'s
  modulefile warning, and it is being read for accuracy, not changed.

## 6. Verification strategy

Three layers, in every phase gate: `bash -n bin/uv-manager` (bash 3.2 on macOS is a real gate),
`.agents/factory/bin/lint.sh` (adds shellcheck, symlink integrity and the version single-source), and
a drive under `.agents/factory/bin/temp_root.sh`.

Post-conditions asserted, by R-ID:

- **R1** — the script's own census drops from 7 to 4 (P1); no phrase-census hit survives in
  `README.md` (P2) or in the two example files (P3); the four-path total is exactly 7 (P4), down
  from 13.
- **R2** — inspection only, stated as such in P1 and P2 so review reads it.
- **R3** — `cat` of the four files is `<= 1724` lines (P4).
- **R4** — the ordered list of `^name()` definitions is identical to `main`'s (P1); `--offline`
  provisioning still lands `current -> versions/9.9.9` (P1, P4); `--offline --arch aarch64 uvm status`
  still reports `architecture: aarch64` (P4).
- **R5** — the no-root failure block still names 6 candidates and still carries `module load uv`,
  `export UVM_ROOT=` and the home-directory warning (P1). Wording compared by eye against
  [`research/01-baseline-output.md`](research/01-baseline-output.md) §B.
- **R6** — every field label quoted in `README.md`'s sample block is a subset of the labels a live
  `uvm status` emits, and the block now carries `invoked as:` (P2).

**Every gate was run against the pre-pass tree and confirmed red.** That is the control that matters:
a gate asserting a post-condition the phase has not delivered must fail, or it cannot distinguish "the
work is done" from "the command is inert". The first draft of P1's gate was green pre-pass — it
asserted only non-regression — and gained the census and defect-specific clauses for exactly this
reason. A red gate during build now means the edit is wrong, not the gate.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
