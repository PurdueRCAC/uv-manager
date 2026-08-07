# PLAN — {Title}

> **Status:** Draft for review · **Last updated:** {YYYY-MM-DD}
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/) when
> `appetite: big`. Every design element traces to a GOAL R-ID.

## 1. Summary

<Two to four sentences: the approach in a nutshell and why it fits the appetite.>

## 2. Design

<The technical design at the right altitude. For this project that means: which functions in
`bin/uv-manager` change and how, what the state tree looks like afterwards, which environment
variables are read or exported, what the failure paths print and exit with, and what the user-facing
surface (`uvm_help`, `README.md`, the conf example, the modulefile) has to say. Be specific enough to
build from, not so specific it duplicates the diff.

State explicitly what is being *removed*. A change that only adds is worth a second look.>

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1   | <function / behavior / documented text> |
| R2   | <…> |

## 3. Invariant gate (AGENTS.md constitution check)

Checked against [`invariants.md`](../../.agents/factory/invariants.md) **before** research and
**again** after this design was drafted. List every load-bearing invariant this change touches and
confirm compliance.

- <§n invariant> — <how this design honors it>.

### Deviation justifications

Any place this design bends an invariant or adds complexity, with the simpler alternative and why it
was rejected. Empty is the goal.

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| —         | —         | — |

## 4. Rabbit holes (resolved)

Unknowns that could have blown the appetite, and how research settled them. Link the relevant
`research/NN-*.md`. This is where risk was bought down before committing to phases.

Typical shapes here: a filesystem semantic that has to be verified rather than assumed (`flock`,
atomic rename, reflink), an `uv` behavior that has to be read out of Astral's source or tested, a
`bash` portability question between 3.2 and 5, or a cluster behavior that cannot be reproduced in the
sandbox and needs a stated assumption.

- <unknown> → <resolution> ([`research/NN-topic.md`](research/NN-topic.md)).

## 5. Risks & open questions

- <residual risk, its mitigation, or a question that needs a human before or during build>.
- <anything that can only be verified on a real cluster, named explicitly so it is not mistaken for
  something the review covered>.

## 6. Verification strategy

How we will *prove* this works. This seeds each phase's `verify:` command in `TECH.md`.

Start from the three layers in [`methodology.md`](../../.agents/factory/methodology.md): `bash -n`,
`.agents/factory/bin/lint.sh`, and a sandbox drive under `.agents/factory/bin/temp_root.sh`
(`--offline` for anything touching provisioning, `--arch` for anything touching the architecture
split). For each R-ID, name the **post-condition** the drive asserts — not just the command. A
`verify:` that only checks exit 0 is not a gate.

---

*Backing research (if present): [`research/00-digest.md`](research/00-digest.md).*
