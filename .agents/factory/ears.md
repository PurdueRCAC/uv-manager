# EARS — Easy Approach to Requirements Syntax

A lightweight controlled-natural-language convention for acceptance criteria that are **testable and
low-ambiguity**. Used by `uvm-feature` to shape `GOAL.md` criteria (R-IDs).

**Nudge, do not hard-enforce.** EARS reduces ambiguity; it does not eliminate it, and forcing it onto
genuinely exploratory requirements stilts them. Prefer EARS where it clarifies; fall back to plain,
unambiguous prose where it would be contrived. Every criterion still gets a stable R-ID.

## Generic template

> **While** \<optional precondition/state>, **when** \<optional trigger>, the \<component> **shall**
> \<observable response>.

Keep `<component>` a real part of this project — `uv-manager status`, the provisioning lock, the
trampoline generator, `uvm_resolve_root`, the modulefile — and keep `<response>` **observable**: an
exit status, a path that exists, a symlink target, a line on stderr, an environment variable in the
child process. `uvm-review` has to check it by driving the script under
`.agents/factory/bin/temp_root.sh`, so a criterion it cannot observe is a criterion it cannot grade.

## The six patterns

| Pattern | Keyword | Form |
|---|---|---|
| **Ubiquitous** | *(none)* | The \<component> shall \<response>. |
| **State-driven** | `While` | While \<state>, the \<component> shall \<response>. |
| **Event-driven** | `When` | When \<trigger>, the \<component> shall \<response>. |
| **Optional-feature** | `Where` | Where \<feature is included>, the \<component> shall \<response>. |
| **Unwanted-behavior** | `If … Then` | If \<unwanted condition>, then the \<component> shall \<response>. |
| **Complex** | combo | While \<state>, when \<trigger>, the \<component> shall \<response>. |

## Examples in this project's terms

- **R1 (event):** *When* `uv tool install` completes, the wrapper *shall* regenerate the neutral
  trampoline directory and exit with the underlying `uv` exit code.
- **R2 (unwanted):** *If* neither `UV_MANAGER_ROOT` nor any scratch candidate names a writable
  directory, *then* the wrapper *shall* print each candidate with the reason it was rejected and exit
  non-zero, without writing anything.
- **R3 (state):** *While* `UV_MANAGER_PIN` names an installed version, the wrapper *shall* point
  `current` at that version without contacting the network.
- **R4 (ubiquitous):** The wrapper *shall* leave `XDG_CONFIG_HOME` unmodified in the environment of
  the process it execs.

## Anti-patterns

- Untestable adjectives — "fast", "robust", "safe". Replace with an observable threshold or a named
  post-condition.
- Several requirements on one line. Split so each has its own R-ID and its own pass/fail.
- Specifying the *how*. Implementation belongs in `PLAN.md`.
- Encoding a **suspected cause** in a *fix's* criterion ("the fix must not use the stale lock path").
  The root cause is unverified until `/uvm-plan` diagnoses it; state the observable broken→fixed
  behavior instead.
- A criterion that can only be observed on a real cluster. If it genuinely cannot be reduced to a
  sandbox drive, say so explicitly in the criterion and in `PLAN.md`'s verification strategy, so the
  reviewer knows it is being taken on trust rather than silently assuming it was checked.
