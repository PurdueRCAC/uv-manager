# PLAN — Stop paying for the state-directory `mkdir` on every invocation

> **Status:** Draft for review · **Last updated:** 2026-08-14
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).

## 1. Summary

Put a six-way `[[ -d ]]` guard in front of the unconditional `mkdir -p` in `uvm_export_env`, outside
the `umask 077` subshell, and correct the four documents that assert the decision it reverses. Nothing
is added — no variable, no function, no branch of behavior. Two of the three process creations on the
warm path disappear and the wrapper's overhead above the exec'd binary falls from about 7 ms to about
5 ms. This is what remains of a much larger cycle after research moved the repair half to
[`issues/purge-tree-repair.md`](../../issues/purge-tree-repair.md); the appetite is now small and the
design is one hunk.

## 2. Design

`uvm_export_env` (`bin/uv-manager:399-422`) currently runs, on every invocation of `uv`, `uvx` and
`uvm`:

```bash
  (
    umask 077
    mkdir -p "${UV_CACHE_DIR}" … "${uvm_neutral_bin}"
  )
```

That is a fork for the subshell, an exec of `/bin/mkdir`, and — measured with an `LD_PRELOAD`
counter — 25 `mkdir(2)` calls that all fail `EEXIST` plus six `stat`s to resolve six existing paths.
The replacement wraps it in a builtin test and leaves the subshell byte-identical:

```bash
  if [[ ! -d "${UV_CACHE_DIR}" || ! -d "${UV_TOOL_DIR}" || ! -d "${UV_TOOL_BIN_DIR}" \
     || ! -d "${UV_PYTHON_INSTALL_DIR}" || ! -d "${UV_PYTHON_BIN_DIR}" \
     || ! -d "${uvm_neutral_bin}" ]]; then
    ( umask 077; mkdir -p … )
  fi
```

Three properties of that shape are load-bearing rather than stylistic.

**The guard is outside the subshell.** Inside, the fork survives and roughly a third of the saving
goes with it — and the phase gate, which counts `mkdir` execs, cannot tell the two apart. This is why
`GOAL.md` R1 states the placement rather than leaving it to the diff.

**The fall-through target is unmodified.** The parity case where a state path has been replaced by a
regular file depends on `mkdir` still being the thing that reports it (`mkdir: … File exists`, non-zero
under `set -e`). Replacing the block with per-directory `mkdir` calls, or with a `[[ -e ]]` test and a
hand-written error, changes that message and that exit status.

**No mode repair.** `mkdir -p` does not `chmod` an existing directory, verified directly and through
the wrapper: a `cache` left at `0755` survives an invocation on `main` unchanged. The property today is
"directories we create are 0700", not "our directories are 0700", and the guard preserves exactly
that. Adding a mode check would be new behavior nothing asked for, and it would cost a `stat` fork per
directory — `stat(1)` is 1.89 ms, more than the whole saving.

`uvm_set_paths` stays pure and untouched. `uvm_export_env` is also reached from `uvm trampolines` and
`uvm install`; one guard covers all three callers with no special-casing.

### What is removed

The unconditional fork and exec on the warm path, and the cost claim that defended it in four places.
Nothing is added to the script's surface: no new knob, no new subcommand, no new fallback. Net line
count is roughly flat — a five-line `if` against a three-line comment deleted.

### Documentation

| File | Change |
|---|---|
| `bin/uv-manager:402-404` | The comment inverts: the guard's warrant is the measurement, and the surviving half of the old claim (a missing directory is still created, under `umask 077`) is stated. |
| `README.md:462-463` | The design note becomes the record of a rejection reversed by measurement, not a deletion. Design notes are where this project keeps what it turned down and why. |
| `.agents/factory/invariants.md:122-123` | §8's last bullet rewritten. Not optional: this file is what `uvm-review` grades against. |
| `AGENTS.md:109`, `README.md:141` | "roughly 7 ms" becomes the new figure. |

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | The `[[ -d ]]` guard in `uvm_export_env`, outside the subshell; the unmodified subshell as its fall-through. |
| R2 | The fall-through target being byte-identical, and the deliberate absence of any mode check. |
| R3 | The comment rewrite, the `README.md` design note, and `invariants.md` §8. |
| R4 | `AGENTS.md:109` and `README.md:141`. |
| R5 | No other edit; `lint.sh` and the three baseline drives. |

## 3. Invariant gate (AGENTS.md constitution check)

Checked against [`invariants.md`](../../.agents/factory/invariants.md) before research and again
against this design.

- **§8 — environment the wrapper sets.** The five `UV_*` variables, the `PATH` prepends and their
  idempotence are untouched; `uvm_set_paths` stays pure. The last bullet of §8 is the one this design
  revises, recorded below.
- **§10 — portability floor.** `[[ -d ]]`, `||` and `!` inside `[[ ]]`, and line continuations inside
  `[[ ]]` are bash 2.02 constructs. Verified: parses and runs under `/bin/bash` 3.2.57, `shellcheck`
  clean. No GNU assumption; no new external command.
- **§12 — project conventions.** Same-commit rule observed across all four documents; prose follows
  `AGENTS.md` § *Prose and comments*; no feature-scoped spec ids in the script or `README.md`.
- **§1 — architecture partitioning.** Untouched. The guard tests paths already derived by
  `uvm_set_paths` from the key `uvm_init` resolved on this node; nothing new is exported.
- **§2, §5, §7 — process semantics, the lock, output discipline.** Untouched. `uvm_export_env` runs
  before the dispatch tail and takes no lock; the guard prints nothing.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| §8's last bullet ("`mkdir -p` runs unconditionally rather than behind a sentinel: a handful of metadata operations") is rewritten. | The bullet is a cost claim, and the cost is 2.0 ms of a 12.0 ms invocation — 27% of the wrapper's overhead and two of three warm-path forks. The behavior it protects (a purged tree's shape is restored) is preserved by R1's second clause and asserted by the gate. | Leaving it would make the correct implementation an **auto-CRITICAL §8 violation** in `uvm-review`, inside a high-blast-radius region, forcing a human sign-off gate on correct code. Keeping the code unchanged instead was rejected on the measurement. |

Note for the record: `invariants.md:122-123` has no counterpart in `AGENTS.md`, so it is a derived
bullet that already drifted from the file the lockstep rule says wins. The same-commit rule names four
user-facing files and neither invariant document; that gap is [`META.md`](META.md) F2.

## 4. Rabbit holes (resolved)

- **Is a stamp file needed, and is it the same mechanism the deferred integrity check wants?** No, on
  both counts. Six `[[ -d ]]` tests cost 15 µs against a stamp's 3 µs — 12 µs, one part in nine hundred
  of an invocation — and the stamp fails R1's repair clause outright: with `bin/shims` removed the
  stamp variant issues zero `mkdir` calls and leaves the tree broken
  ([`01`](research/01-hot-path-cost.md), and D2 in [`00-digest.md`](research/00-digest.md), where the
  fingerprint variant is killed too).
- **How large is the saving, really?** Four independent measurements disagreed on absolutes and agreed
  on the shape. The reproducible statement is ~2.0 ms of ~12.0 ms; a final probe measured 9.69 → 7.83
  ms. The GOAL's original "about a quarter of the wrapper's overhead" is correct on the
  overhead-above-exec denominator (26.6%); an early brief's "not a quarter, restate it" was a
  denominator error ([`00-digest.md`](research/00-digest.md) D1).
- **What does `mkdir -p` actually cost in syscalls?** Not "≈40 stats". 25 `mkdir(2)` calls all failing
  `EEXIST` plus 6 stats, against the guard's 6 stats. The correction runs in the guard's favour on a
  parallel filesystem, where a failing `mkdir` RPC cannot be served from a client attribute cache and a
  `stat` often can.
- **Does the unconditional call protect the directories from an atime purge?** No. `mkdir -p` and
  `[[ -d ]]` both leave atime unchanged; only reading a directory bumps it. Removing it costs no purge
  protection.
- **Which documents assert the decision?** Eight places across six files were enumerated for the
  original scope; four survive into this one ([`06`](research/06-surface-and-docs.md)). `AGENTS.md`
  does **not** assert the unconditional `mkdir`, contrary to an earlier reading.

## 5. Risks & open questions

- **The cluster figure is unmeasured, and cannot be measured here.** Every number is macOS on APFS with
  a warm dentry cache. macOS exec is expensive, which inflates the fork saving; Lustre and GPFS
  metadata is far more expensive than APFS, which inflates the syscall saving. The two errors run in
  opposite directions and neither is sizable from this machine. The claim that transfers is the 25-to-6
  syscall reduction, not the millisecond figure. Do not let the new prose state a cluster number.
- **The gate cannot see the guard's placement.** It counts `mkdir` execs, and a guard written inside
  the subshell produces the same count while keeping the fork. `TECH.md` P1 carries this as an
  inspection item so `/uvm-review` reads it rather than trusting the gate.
- **The gate cannot see prose quality.** R3's replacement text is graded by a reviewer against
  `AGENTS.md` § *Prose and comments*; no command decides whether a comment earns its place.
- **A `!`-prefixed assertion is invisible to `set -e`.** Found while authoring these gates: `set -e; ! true`
  neither aborts nor fails the script, so a `! git grep -q …` assertion inside a gate is inert. Both
  gates use explicit `if … then exit 1; fi`. Any later gate in this repository should too.

## 6. Verification strategy

Three layers, all exercised while authoring and all confirmed red on the current tree.

**`bash -n` and `lint.sh`** — the portability floor. `/bin/bash` on this machine is 3.2.57, so the
parse gate is real rather than a formality. Both pass on `main` and on a patched probe copy, so they
are regression guards, not the discriminator.

**The counting `mkdir` stub** — R1 and R2's discriminator, and the only way to observe a call that has
no other effect. A stub first on `PATH` inside the sandbox logs and delegates; the wrapper reaches it
from inside the `umask` subshell, and the wrapper's own three `PATH` prepends land ahead of it without
shadowing `mkdir`. Post-conditions asserted in one drive: warm intact tree issues **0** (today: 1); a
directory left at `0755` is still `0755` afterwards; a removed directory is recreated at mode `700`; a
state path replaced by a regular file still exits non-zero. On `main` the drive prints
`warm=1 kept0755=755 restored=1 mode=700 file-rc=1` and exits 1 — red on exactly one clause, with the
three parity clauses already holding. Applied to a probe copy outside the working tree, the same drive
prints `warm=0` and exits 0.

**Scoped greps** — R3 and R4. Pathspecs are written literally, because the research briefs under
`spec/` quote the old text verbatim and an unscoped grep would stay red forever. `bin/uv-manager:402`
wraps mid-phrase, so `handful of metadata` never matches there; `rather than behind a sentinel` matches
all three targets on one line each.

**The baseline drives** — R5, asserting post-conditions rather than exit 0. `uv --version` under
`--offline`, and again under `--offline --arch aarch64`, each asserting the version string and the
`current` symlink target `versions/9.9.9` under its own architecture key — one sandbox holding two
keys is how the heterogeneous-cluster split stays reachable on one machine. Plus `uvm status`, and a
second `--arch aarch64` drive asserting `status` reports the override key.

One correction worth recording, because it is the failure `/uvm-plan` warns about in its own words. The
first draft of this gate asserted a `current` symlink target after `uvm status` under `--arch aarch64`.
`uvm status` is read-only — it calls `uvm_set_paths` and never `uvm_export_env` or `uvm_ensure_uv` — so
no arch tree and no `current` exist at that point, and the gate failed for its own reasons rather than
on the asserted post-condition. Left in, it would have been red through the whole build while the code
was correct, walking `--record-attempt` toward the circuit breaker. The provisioning arm now uses
`uv --version`, which does provision.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
