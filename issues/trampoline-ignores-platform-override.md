---
status: adopted:trampoline-ignores-platform-override
kind: fix
appetite: small
lane: public
---

# Trampolines ignore UVM_PLATFORM, so every tool breaks at a site that sets it

## Problem

The wrapper resolves its platform key as `${UVM_PLATFORM:-$(uname -m)}` (`bin/uv-manager:145`),
but the generated trampoline hardcodes `a=$(uname -m)` (`bin/uv-manager:478`). The two disagree
whenever a site uses the override.

`UVM_PLATFORM` is the documented escape hatch for exactly the cases where `uname -m` is too
coarse — glibc skew between login and compute images, musl, `x86-64-v2/v3/v4` levels — and
`etc/uv-manager.conf.example:80` gives a worked example of setting it. At any such site,
`uv tool install ruff` lands the executable in `$UVM_ROOT/<override-key>/bin/shims/ruff`, while
the trampoline on `PATH` looks for `$UVM_ROOT/$(uname -m)/bin/shims/ruff`. That path does not
exist, so **every trampoline fails with exit 127** and the "not installed for architecture" message,
naming the wrong architecture, for a tool that is in fact installed.

Reproduced in the factory sandbox:

```console
$ .agents/factory/bin/temp_root.sh --offline --keep --arch x86_64-glibc2.28 sh -c '
      uv --version >/dev/null
      mkdir -p "$UVM_ROOT/x86_64-glibc2.28/bin/shims"
      printf "#!/bin/sh\necho hello\n" > "$UVM_ROOT/x86_64-glibc2.28/bin/shims/ruff"
      chmod +x "$UVM_ROOT/x86_64-glibc2.28/bin/shims/ruff"
      uvm trampolines
      "$UVM_ROOT/bin/ruff"'
uv-manager: trampolines synced in .../root/bin
uv-manager: 'ruff' is not installed for architecture 'arm64'.
uv-manager: it exists for another architecture; install it here with
uv-manager:     uv tool install <package>
```

Exit 127. The tool is installed; the trampoline is looking in the wrong place.

The same disagreement makes `uvm_trampolines`' union-of-names scan
(`for d in "${uvm_base}"/*/bin/shims`) generate a trampoline for a name it can then never resolve, so
the failure is guaranteed rather than intermittent.

## Why it was deferred

Found while building the factory's sandbox (`temp_root.sh --arch`), not during a change to the
wrapper. Fixing it is product work with a real design question, and it belongs in a cycle of its own:
the trampoline is a `/bin/sh` script generated once and executed later, so it cannot read the
generating process's `arch` variable — the override has to be **baked into the generated body** at
sync time, or read back from the environment at exec time, and those two answers behave differently
when a user's `UVM_PLATFORM` differs from the one in effect when the trampolines were written.
That is a shaping conversation, not a one-line patch.

**Pre-existing** on `main` — present since the trampoline mechanism was introduced, not introduced by
the harness port.

Its practical severity depends on adoption: Purdue's own deployments use the default `uname -m`, where
the two expressions agree and nothing is wrong. It bites the first site that follows the documented
advice in `etc/uv-manager.conf.example`.

## Outcome / vision

A site that sets `UVM_PLATFORM` gets trampolines that resolve to the same tree the wrapper
writes to, and the "not installed for this architecture" message names the key actually in use.

## Sketch of the acceptance criteria

- **R1** — WHILE `UVM_PLATFORM` is set, WHEN a generated trampoline is invoked, it SHALL exec
  the executable under that platform key, not under `uname -m`.
- **R2** — WHEN a trampoline cannot find its target, it SHALL name the platform key it actually
  searched.
- **R3** — The trampoline SHALL remain a `/bin/sh` script that resolves its target at exec time, so a
  single `PATH` entry stays correct across node architectures (`invariants.md` §1, §9).

## Notes

- Related: `invariants.md` §1 (architecture partitioning) and §9 (trampolines).
- Decide whether a trampoline should honor `UVM_PLATFORM` from the *invoking* environment or
  the *generating* one. Honoring the invoker preserves the "one PATH entry, correct everywhere"
  property; baking it in does not, and would break the heterogeneous case the trampolines exist for.
- Found by: the harness port, while validating `temp_root.sh --arch` against the real script.
