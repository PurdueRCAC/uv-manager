# 04 — Same-commit documentation audit

`GOAL.md` § *Clarifications* Q3 answered "no line becomes stale" and instructed `/uvm-plan` to confirm
rather than assume. **The audit refutes it.** The answer was right about the `UVM_PLATFORM`
descriptions and wrong about the trampoline descriptions, which are a separate set of sentences nobody
enumerated during shaping.

## Stale after the fix — must move in the same commit (§12)

Five sites state that a trampoline re-resolves **`uname -m`**. After the fix it re-resolves the
platform key, of which `uname -m` is only the default.

| Site | Current text |
|------|--------------|
| `bin/uv-manager:431` | "trampolines that re-resolve `uname -m` at exec time" |
| `share/modulefiles/uv/main.lua:24` | "trampolines that re-resolve / `uname -m` at exec time" |
| `share/modulefiles/uv/main.lua:122` | "Each one re-resolves `uname -m` when executed" |
| `README.md:260` | "trampolines that re-resolve / `uname -m` when invoked" |
| `README.md:455` | "Each is a short `sh` script that re-resolves `uname -m` at exec time." |

The fix is the same in all five: say **platform key** where the text says `uname -m`. README already
owns that vocabulary — § *The platform key* at `README.md:345` is the section that defines it — so
this aligns the trampoline prose with terminology the document already established rather than
inventing any. Three of the five get shorter.

`main.lua` is documentation-only here: no `setenv` changes, only the two comments. That makes it the
one genuinely parallel-safe phase in this cycle.

## Accurate as written — no change

| Site | Why it survives |
|------|-----------------|
| `bin/uv-manager:767` help heredoc | "Override the architecture key (default: `uname -m`)" — describes the variable, which is unchanged. |
| `README.md:537` variable table | Same sentence, same reason. |
| `README.md:345`–`352` § The platform key | Describes `uvm_init`'s resolution. Untouched by this cycle. |
| `etc/uv-manager.conf.example:78`–`82` | The override's purpose and the worked example stay correct. |
| `bin/uv-manager:132` banner | Describes `uvm_init`, not the trampoline. |
| `README.md:125`, `:147`, `:183`, `:247` | Say "architecture-neutral trampolines" without naming a mechanism. |

## Borderline — inspection, not a mechanical edit

`README.md:515`, troubleshooting:

> **A tool prints "is not installed for architecture 'aarch64'".** That is the trampoline working as
> intended. Run `uv tool install <package>` on that architecture.

Still true, and `aarch64` is still a valid instance of the message. But post-fix the quoted key can be
a site's override rather than a `uname -m` value, and the advice "run it on that architecture" is
incomplete for an operator whose key encodes a glibc version rather than a machine type. A short
qualification is defensible; leaving it is also defensible. Flagged for the build phase to decide by
reading, not by grep — no census detects it.

## The gap the fix creates

`etc/uv-manager.conf.example:82` recommends a computed value. Per brief `02`, that value must be
evaluated **on the executing node**; inherited as a literal through `sbatch --export=ALL` it sends
both the wrapper and — newly — the trampolines into another node's tree. The file currently says
"Keep it cheap to compute" and nothing about *when* it is computed. One sentence closes it.

This is an addition to a file the standing bias says should shrink, so it is called out for the human
rather than folded in silently. The argument for it: the fix converts `UVM_PLATFORM` from a variable
that half the system ignored into one the whole system obeys, and §1's failure mode is `Exec format
error` thousands of lines into a charged allocation.
