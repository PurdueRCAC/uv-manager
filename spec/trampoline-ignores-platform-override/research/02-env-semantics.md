# 02 — Whose `UVM_PLATFORM`? Exec-time environment semantics

Scope: the GOAL settled that the trampoline honors the **invoking** environment. This brief checks
that the choice is coherent in the invocation paths that actually occur, and names the one behavior it
produces that looks like a bug but is the contract.

## The wrapper never exports it

`UVM_PLATFORM` is **read** at `bin/uv-manager:145` and assigned nowhere. Neither the wrapper nor
`share/modulefiles/uv/main.lua` exports it; `uvm_export_env` sets the five `UV_*` storage variables
and `PATH`, and leaves `UVM_PLATFORM` untouched (invariant §8). The variable reaches both the wrapper
and a trampoline by the same route: the site or user exported it, and it was inherited.

That is what makes the invoker answer self-consistent. Both the wrapper and the trampoline evaluate
the *same expression* against the *same environment* at the *same moment*, so within any one
environment they cannot disagree. No amount of environment manipulation splits them, because there is
no second source of truth to split from.

Confirmed behaviorally: with `--arch x86_64-glibc2.28`, `uvm status` reports `architecture:
x86_64-glibc2.28` and `UVM_PLATFORM` is present in the environment a child process inherits.

## The case that looks like a regression and is not

    $ UVM_PLATFORM=k9 uv tool install ruff     # exported for this command only
    $ ruff                                     # plain shell, variable gone

The tool lands under `k9`; the later trampoline resolves `uname -m`, finds nothing, exits 127 naming
`uname -m`. This is correct. In that second shell the wrapper would resolve `uname -m` too — `uv tool
list` would also show nothing. The environments genuinely differ, and the trampoline reports the key
it searched, which is exactly R2. Post-fix the diagnosis is accurate; today it is actively misleading,
because the message names a key the wrapper was not using either.

There is no coherent alternative here. Baking the generation-time key in would make `ruff` work in the
second shell while `uv tool list` disagreed with it — two subsystems in one state root reporting
different architectures.

## The hazard this fix widens, honestly stated

`etc/uv-manager.conf.example:82` recommends a **computed** value:

    export UVM_PLATFORM="$(uname -m)-glibc$(getconf GNU_LIBC_VERSION | awk '{print $2}')"

Evaluated per-shell on the executing node, that is correct and is the intended usage. But Slurm's
`--export=ALL` copies the *resolved value* from the submitting node, so a batch script that does not
re-source the site profile inherits the login node's key. On a compute node of a different
architecture the wrapper then resolves a key belonging to the other tree — and this is **already true
today**, for `uv`, `uvx` and `uv run`, independent of this cycle. It is a property of `UVM_PLATFORM`
itself and of §1's warning that nothing outside the wrapper may carry an architecture-bearing value.

What changes: today the trampoline ignores the variable and so happens to survive that
mis-propagation, while being unconditionally broken for every correctly configured site. After the fix
it shares the wrapper's exposure. The trade is worth taking — a trampoline that resolves correctly
while `uv` itself is resolving into the wrong tree is not a safe state, it is a state where half the
installation is wrong and nothing says so — but it is a real change in failure mode and belongs in
PLAN §5, not buried.

It also supplies the evidence for a one-sentence caution in the conf example: the value must be
evaluated on the executing node, not inherited as a literal. That is a documentation gap the fix makes
load-bearing.

## Not a new attack surface

A key containing `/` or `..` would path-traverse inside the state tree. `uvm_init` already
concatenates the same unvalidated value into `uvm_root`, so the exposure is identical to today's and
is confined to a variable the user sets in their own environment against their own per-user tree
(`umask 077`). Not a finding, and validating the key is out of scope for this GOAL.
