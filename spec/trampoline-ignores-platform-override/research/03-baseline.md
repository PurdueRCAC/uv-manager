# 03 — Pre-change baseline and the verification surface

Scope: capture what the script does **today**, on this branch, so every gate has a red-to-green
reference and invariant §7's "message text is user-facing behavior" is recorded before it changes.
Host `uname -m` is `arm64`; the cluster equivalent would be `aarch64` (§1).

## Baseline A — the defect (GOAL R1, R2)

    .agents/factory/bin/temp_root.sh --offline --arch x86_64-glibc2.28 sh -c '
      uv --version >/dev/null 2>&1
      mkdir -p "$UVM_ROOT/x86_64-glibc2.28/bin/shims"
      printf "#!/bin/sh\necho RUFF-OK\n" > "$UVM_ROOT/x86_64-glibc2.28/bin/shims/ruff"
      chmod +x "$UVM_ROOT/x86_64-glibc2.28/bin/shims/ruff"
      uvm trampolines
      "$UVM_ROOT/bin/ruff"'

Output today:

    uv-manager: trampolines synced in .../root/bin
    uv-manager: 'ruff' is not installed for architecture 'arm64'.
    uv-manager: it exists for another architecture; install it here with
    uv-manager:     uv tool install <package>

Exit **127**. The shim is executable at `.../root/x86_64-glibc2.28/bin/shims/ruff`. The message names
`arm64`, a key nothing in this sandbox uses. Reproduces the seed exactly.

Post-fix this must print `RUFF-OK` and exit 0 (R1); with the shim absent it must exit 127 naming
`x86_64-glibc2.28` (R2).

## Baseline B — the control that must not regress (R3)

Same drive with no `--arch`, shim planted under `$(uname -m)`: prints `RUFF-OK-NATIVE`, exit **0**.
Already correct, and the fix must leave it so. This is the case every existing deployment runs,
including Purdue's, which is why the seed's severity is adoption-dependent.

## Baseline C — the generated body

    #!/bin/sh
    # uv-manager-trampoline — generated; edits will be lost.
    n=${0##*/}
    d=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
    a=$(uname -m)
    for s in shims python-shims; do
        t="$d/$a/bin/$s/$n"
        if [ -x "$t" ]; then exec "$t" "$@"; fi
    done
    echo "uv-manager: '$n' is not installed for architecture '$a'." >&2
    echo "uv-manager: it exists for another architecture; install it here with" >&2
    echo "uv-manager:     uv tool install <package>" >&2
    exit 127

One line changes. Note the body contains no literal key today, and must still contain none after the
fix — that is R4's grep, and it is the assertion that distinguishes this design from the rejected
bake-it-in alternative.

## Verification surface discovered

Three facts that shape the `verify:` commands:

1. **No provisioning needed.** `uvm trampolines` exits 0 against a state root with no `uv` installed
   (brief `01`). Gates drop `--offline` and stop depending on the installer fixture.
2. **`uvm status` prints `architecture: <key>`**, a direct read of the wrapper's resolved key. Cheap
   assertion that the wrapper side is unchanged.
3. **`--keep` prints the sandbox path to stderr**, so a heterogeneous drive that needs two `--arch`
   invocations against one root cannot use two `temp_root.sh` calls — each makes a fresh sandbox. The
   R4 drive must instead run a single `temp_root.sh` invocation and vary `UVM_PLATFORM` *inside* it
   with an environment prefix, which is also closer to what a real two-node job does.

## Gate-authoring traps carried forward

`.agents/factory/review-rubric.md` § *Verification traps* records two, and **both** bite the gates
this cycle needs:

- *An interpolated pathspec collapses under `zsh`* — a gate that builds its paths from a variable can
  search one nonexistent path and report clean. Every `verify:` here writes its paths literally.
- *`grep` may not be `grep`* — in an interactive agent shell it can be a function; under `/bin/sh` it
  is `/usr/bin/grep`. R4's gate is a grep asserting the **absence** of a literal key in the generated
  body, which is precisely the shape whose false green is invisible. Every load-bearing grep in
  `TECH.md` runs inside a `temp_root.sh … sh -c '…'` drive, so it executes under `/bin/sh`.

Each gate was run against the current tree to confirm it exits **non-zero** before the fix exists.
