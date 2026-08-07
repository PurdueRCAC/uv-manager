# Harness portability — running the factory outside Claude Code

The `uvm-*` skills are plain markdown plus portable shell (`git`, `uv run`, the
`.agents/factory/bin` scripts) and are meant to run on **any** agent harness — Claude Code, Warp,
OpenCode, and open-weight models. A handful of affordances are Claude-Code-specific; each has a
graceful fallback so the skill still works, at worst with one manual step. This table is the
compatibility contract — keep it current when a skill gains a new affordance, and every skill links
here.

## Affordance → fallback

| Claude-Code affordance | What it does | Fallback on another harness |
|---|---|---|
| **Frontmatter** (`name`, `description`, `argument-hint`, `allowed-tools`, `disable-model-invocation`) | Skill discovery and least-privilege tool gating | **Harmlessly ignored** — it is YAML, not procedure. The skill **body** is the operating manual. Grant whatever tools your harness needs by its own mechanism; the committed `.agents/settings.json` is the safe baseline of what the skills actually run. |
| **`` !`cmd` `` injection** under "Current state (injected at load)" | Runs shell at load and pastes the output into context | **Run those commands yourself** as the first action. The listed commands *are* the state — if you see literal `` !`…` `` text, execute it and read the output. |
| **`$ARGUMENTS`** | The invocation's arguments | Use your harness's argument mechanism, or read them from the user's message. |
| **`AskUserQuestion`** | Structured multiple-choice to the human | **Ask in plain text and STOP** for the answer. Never guess to dodge the question. |
| **`Agent` subagent fan-out** (`uvm-plan` research, `uvm-review` reviewer) | Parallel read-only workers | **Do the work sequentially yourself**, producing the same artifacts (`research/NN-*.md`; the review). For `uvm-review` this weakens *blindness* — compensate by starting a clean context and grading strictly on executed evidence, per the rubric. |
| **`ReportFindings`** (`uvm-review`) | Renders findings in the host UI | **Additive, not load-bearing** — `REVIEW.md` is the durable record. Skip the call; still write `REVIEW.md`. |
| **`Skill` / `/uvm-*` launch** | How a skill starts | Launch by your harness's mechanism; the handoffs ("then run `/uvm-plan`") are advisory prose. |

> **Scope the allowlists honestly.** The frontmatter `allowed-tools` and the committed
> `.agents/settings.json` are accident protection, not a security boundary — `Bash(uv run *)` alone
> admits arbitrary Python. They exist to stop fat-fingered mutations, which is why `git checkout` (a
> silent working-tree discard) is deliberately absent, not to confine a determined adversary.

## Already portable — no action

`git`, `gh`, the FSM scripts, `temp_root.sh`, `lint.sh`, file read/edit/grep/glob, and every artifact
under `spec/{slug}/` and `.agents/`. All lifecycle state lives in **files** (`TECH.md` frontmatter,
`META.md`), re-read fresh each invocation. Scripts are invoked by repo-relative path, not through a
Claude-specific variable.

## The Python scripts and `uv`

`next_phase.py`, `set_phase.py` and `meta_status.py` carry **PEP 723 inline metadata**, so
`uv run .agents/factory/bin/next_phase.py …` resolves their one dependency (PyYAML) into a cached
ephemeral environment. There is no `pyproject.toml`, no virtualenv to create, and nothing to install
first. `meta_status.py` is stdlib-only by design — the `META.md` finding format is deliberately not
YAML so that appending to it cannot corrupt it and reading it needs no dependency.

Without `uv`, run them with any Python 3.11+ that has PyYAML available; the only `uv`-specific part is
dependency resolution. On a machine with neither, `meta_status.py` still works under bare `python3`.

## Smaller and open-weight models

The skills deliberately assume less skill than their author, so a weaker model **fails safe** by
following the guardrails rather than guessing: STOP-and-ask on ambiguity, `[NEEDS CLARIFICATION]`
markers, the invariant gate, blind evidence-based review, and silence-by-default meta-notes all
degrade gracefully. When adapting a skill for another harness, keep instructions imperative and
checkable, and preserve every STOP condition — they are the safety net. Friction you hit doing so is
itself a meta-note for `/uvm-harness` to fix.
