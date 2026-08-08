# PLAN — Trampolines resolve the platform key the wrapper actually uses

> **Status:** Draft for review · **Last updated:** 2026-08-07
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).

## 1. Summary

One line of `bin/uv-manager` changes: the generated trampoline's `a=$(uname -m)` becomes
`a=${UVM_PLATFORM:-$(uname -m)}`, the same expression `uvm_init` already evaluates. Both sides then
resolve the same variable from the same inherited environment at exec time, so they cannot disagree.
The rest of the cycle is the cost of that line — a comment at each site recording that the two must
move together, and five documentation sentences that describe the trampoline as resolving `uname -m`
and stop being true.

## 2. Design

### The change

`bin/uv-manager:476`, inside the `TRAMPOLINE` heredoc:

```diff
-a=\$(uname -m)
+a=\${UVM_PLATFORM:-\$(uname -m)}
```

The heredoc delimiter is unquoted, so the backslashes are what defer evaluation to the generated
script's runtime rather than the generator's. Verified against bash 3.2.57: the emitted line is
exactly `a=${UVM_PLATFORM:-$(uname -m)}` ([`research/01`](research/01-generated-body.md)).

Nothing else in `uvm_trampolines` moves. The union-of-names scan, the `uvm_tramp_marker` ownership
test, the temp-file-and-`mv` write, and the orphan sweep are untouched. `uvm_init` is untouched — the
wrapper side was always right.

`:-` and not `-` is load-bearing. `uvm_init` uses `:-`, so an exported-but-empty `UVM_PLATFORM` falls
back to `uname -m`; a trampoline using `-` would treat the empty string as the key and reintroduce the
divergence in the one case nobody would think to test.

### The message

`$a` is already interpolated into the not-installed message, so it names the override key with no
further change. That is the whole of R2.

### The coupling comments

Two sites, in the repository's declarative voice, stating the constraint and the failure — not
paraphrasing the line. At the `uvm_init` platform-key banner (`bin/uv-manager:130`–`142`) and at the
trampoline banner (`:425`–`435`). Substance: these two expressions resolve the same key and must move
together; when they disagree the tool is installed in one tree and looked for in another, and every
trampoline exits 127 naming a key the wrapper never used.

### Documentation

Five sentences say a trampoline re-resolves **`uname -m`**; after the fix it re-resolves the *platform
key*, of which `uname -m` is the default. `README.md:261`, `README.md:455`,
`share/modulefiles/uv/main.lua:24`, `:122`, and `bin/uv-manager:431`. README already owns the term —
§ *The platform key* at `README.md:345` defines it — so this borrows established vocabulary rather
than coining any. Full audit and the sites that correctly stay unchanged:
[`research/04`](research/04-doc-surface.md).

The `uvm_help` heredoc needs nothing: `UVM_PLATFORM Override the architecture key (default: uname -m)`
describes the variable, which is unchanged.

### What is removed

Nothing. This is a net-additive change of roughly six comment lines against an 850-line script that
should shrink, and that is worth stating plainly rather than leaving for a reviewer to notice. Three
of the five documentation edits get shorter, which pays part of it back. The additive part is the
coupling comment, bought deliberately in place of the structural guard — see the deviation table.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | `a=${UVM_PLATFORM:-$(uname -m)}` in the generated body; `$a` indexes the same tree `uvm_init` writes to. |
| R2 | The existing `'$n' is not installed for architecture '$a'` message, now carrying the resolved key. |
| R3 | `:-` fallback: unset or empty resolves `uname -m`, unchanged from today. |
| R4 | The expression is written escaped, so it is evaluated by the trampoline, not by the generator; no `${arch}` is interpolated into the body. Asserted by grepping the generated file for both keys. |
| R5 | The two coupling comments, plus the identical expression at both sites. |
| R6 | `uvm_trampolines`' surrounding logic and `uvm_init` untouched; body stays `/bin/sh`; `lint.sh` and the three standing drives. |

## 3. Invariant gate (AGENTS.md constitution check)

Walked before research and again against this design.

- **§1 Architecture partitioning** — strengthened, not bent. The key is now resolved at exec time on
  the executing node at *both* sites instead of one. No architecture-bearing value is written into the
  generated body; the gate greps for both keys to prove it. The neutral directory stays neutral.
- **§2 Process semantics** — the body still `exec`s its target. Argument forwarding and exit-code
  propagation were driven directly (`exit 42` observed through the trampoline).
- **§7 Output discipline** — the not-found block is three `echo … >&2` lines, unchanged in shape and
  still on stderr.
- **§9 Trampolines** — body remains `/bin/sh` and re-resolves at exec time, which is what this cycle
  restores in the case where the two definitions of "the architecture" differ. Union scan, marker
  ownership, temp-write-and-rename and the orphan sweep are all untouched.
- **§10 Portability floor** — `${VAR:-$(cmd)}` is POSIX, confirmed by `dash -n` and by execution under
  `dash`; the generator parses under bash 3.2.57. Hot path: no new process, and one fewer fork when
  the override is set.
- **§12 Project conventions** — the same-commit rule is discharged inside the phase that changes
  behavior; comments follow the voice rules; no spec ids in the script or README.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| Six net-new comment lines in a script the standing bias says should shrink | R5 makes the coupling legible; the two expressions live 330 lines apart in different languages, and the next reader has no way to know they are one decision | Single-sourcing the expression was rejected in shaping: bash and the generated `/bin/sh` share no code, so it means interpolating a quoted string into the heredoc — indirection an operator reading the generated file has to unpick, to prevent a two-line divergence |
| One added sentence to `etc/uv-manager.conf.example` (phase P2) | The fix makes `UVM_PLATFORM` load-bearing for the whole system, and the file recommends a computed value without saying it must be computed on the executing node; §1's failure mode is `Exec format error` in a charged allocation | Saying nothing was the status quo, and was defensible while trampolines ignored the variable. It stops being defensible once they obey it. Isolated in its own phase so it can be struck without touching the fix |

No §1–§11 conflict. Nothing escalated.

## 4. Rabbit holes (resolved)

- **Does the heredoc escaping survive?** Yes — `a=\${UVM_PLATFORM:-\$(uname -m)}` emits correctly under
  bash 3.2.57, no nested quoting or `eval`
  ([`research/01`](research/01-generated-body.md)).
- **Is `${VAR:-$(cmd)}` safe in a real `/bin/sh`?** Yes — `dash -n` clean and executed correctly under
  `dash`; seven runtime cases pass including empty-string and whitespace keys (`01`).
- **Whose environment wins, and is that coherent?** The invoker's, and it is the only self-consistent
  answer: the wrapper never exports `UVM_PLATFORM`, so both sides read one inherited variable
  ([`research/02`](research/02-env-semantics.md)).
- **Is this one defect or an instance of a pattern?** One. Every `uname` site in the repository was
  surveyed; exactly one code site diverges (`01`).
- **Do the gates need provisioning?** No — `uvm trampolines` exits 0 against a state root with no `uv`
  installed, so no `verify:` uses `--offline` and the installer fixture leaves the failure surface
  (`01`, [`research/03`](research/03-baseline.md)).

## 5. Risks & open questions

- **`GOAL.md` Q3 is wrong, and this plan corrects it.** Shaping recorded "no line becomes stale" and
  delegated confirmation here. Five sites do go stale — the ones describing the *trampoline*, not the
  ones describing the *variable*, which is the set Q3 reasoned about. No R-ID changes and this is not a
  GOAL contradiction, but `/uvm-review` should grade against this correction rather than the
  clarification ([`research/04`](research/04-doc-surface.md)).
- **The fix widens exposure to a mis-propagated `UVM_PLATFORM`.** A value computed on a login node and
  inherited through `sbatch --export=ALL` without re-evaluation already sends the *wrapper* into
  another node's tree. Today trampolines ignore the variable and accidentally survive that; afterwards
  they share the exposure. The trade is right — a trampoline resolving correctly while `uv` itself
  resolves into the wrong tree is not a safe state — but the failure mode genuinely changes. This is
  what motivates the P2 conf-example sentence ([`research/02`](research/02-env-semantics.md)).
- **Taken on trust: no real heterogeneous cluster.** The sandbox proves the trampoline honors
  `UVM_PLATFORM`, using `UVM_PLATFORM` — the same mechanism under test. It cannot prove behavior on
  genuinely different-architecture hardware. The mitigating fact is that the default path is
  untouched: with the variable unset the generated line is behaviorally identical to today's, so a
  site not using the override cannot be affected by this change. R3 is the drive that pins that.
- **R5 is graded by reading.** No command decides whether a comment earns its place. If the reviewer
  judges the coupling comments to be restatement, they fail §12's voice rules and the fix still ships
  correct — a prose finding, not a correctness one.

## 6. Verification strategy

Three layers, per `methodology.md`. Every gate below was run against the current tree and **exits
non-zero**, and the behavioral gate was additionally proven to exit 0 against a throwaway copy of the
repository carrying only the one-line change — so neither gate is inert.

| R-ID | Post-condition asserted |
|------|-------------------------|
| R1 | Under `--arch x86_64-glibc2.28`, with a shim planted in that tree, `$UVM_ROOT/bin/ruff` prints `OVERRIDE` and exits 0. Today it prints the not-installed message and exits 127. |
| R2 | With `UVM_PLATFORM=ppc64le`, stderr matches `architecture 'ppc64le'`. Today it matches the host's `uname -m`. |
| R3 | With `UVM_PLATFORM` unset via `env -u`, the trampoline prints `NATIVE` — the shim under `$(uname -m)`. Already true; must stay true. |
| R4 | One trampoline, one state root, shims under two keys: it prints `OVERRIDE` under one `UVM_PLATFORM` and `NATIVE` under the other. Neither key appears literally in the generated file (`! grep -q`). |
| R5 | Reviewer reads the two comment sites against `AGENTS.md` § *Prose and comments*. Inspection-only, stated in the phase so the gate's green is not mistaken for covering it. |
| R6 | `.agents/factory/bin/lint.sh` passes (includes `bash -n` and shellcheck); `temp_root.sh uvm status`, `--offline uv --version` and `--offline --arch aarch64 uvm status` reach their `main` post-conditions. All four confirmed against the patched copy. |
| §12 | Census over the three files finds none of the five stale trampoline descriptions. The pattern deliberately matches the two **line-wrapped** sites (`README.md:261`, `main.lua:24`), which a naive `re-resolves.*uname` census reports clean. |

Both rubric traps apply and are handled: paths are written literally rather than interpolated from a
variable, and every load-bearing `grep` runs under `/bin/sh` — R4's is an *absence* assertion, the
exact shape whose false green is invisible ([`research/03`](research/03-baseline.md)).

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
