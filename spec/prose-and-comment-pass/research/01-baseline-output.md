# Baseline — user-facing output before the pass

Captured from `main`-equivalent working tree at plan time, commit `692adf1`,
by driving the real script under `.agents/factory/bin/temp_root.sh`. Sandbox paths are normalized to
`$SANDBOX` and the repository path to `$REPO`; everything else is verbatim.

This is the comparison text for R4, R5 and R6. The pass may reword these blocks, so a byte-exact
diff is the wrong gate — the question a reviewer asks against this file is whether any *information*
a stuck operator needs has gone missing.

## A — `uvm status` (no uv provisioned)

```
uv-manager:            0.3.0
invoked as:            uvm  ($REPO/bin/uvm)
architecture:          arm64
state root:            $SANDBOX/root  (from UVM_ROOT)
arch root:             $SANDBOX/root/arm64
selected version:      <none>
real uv:               $SANDBOX/root/arm64/current/uv [MISSING]
real uvx:              $SANDBOX/root/arm64/current/uvx [MISSING]
resolved version:      n/a
installed versions:    
UV_CACHE_DIR:          $SANDBOX/root/arm64/cache
UV_TOOL_DIR:           $SANDBOX/root/arm64/tools
UV_TOOL_BIN_DIR:       $SANDBOX/root/arm64/bin/shims
UV_PYTHON_INSTALL_DIR: $SANDBOX/root/arm64/python
UV_PYTHON_BIN_DIR:     $SANDBOX/root/arm64/bin/python-shims
trampoline dir:        $SANDBOX/root/bin
XDG_CONFIG_HOME:       $SANDBOX/config
pin:                   <none — tracks latest>
```

## B — no state root resolves (R5), stderr, exit 1

```
uv-manager: cannot determine where to keep per-user uv state.

  UVM_ROOT is unset, and none of these named an existing,
  writable directory:

      $CLUSTER_SCRATCH  (unset)
      $RCAC_SCRATCH     (unset)
      $SCRATCH          (unset)
      $PSCRATCH         (unset)
      $WORK             (unset)
      $PROJECT          (unset)

  Fix by loading the site module:
      module load uv

  or by setting it explicitly — for automation and batch contexts
  that do not inherit a login shell, do this in the job script or
  endpoint configuration:
      export UVM_ROOT=/path/to/large/scratch/.uv

  This must be on storage visible from every node that will run uv,
  at the same path, and it must not be your home directory.
```

## C — `uvm help`

```
uv-manager 0.3.0 — site launcher for uv on multi-architecture clusters

Usage: uv-manager <command> [args]

  status              Show every resolved path and the selected uv version
  doctor              Check for a partially purged / damaged tree
  versions            List uv versions installed for this architecture
  install [VERSION]   Select VERSION, downloading it if absent.
                      With no VERSION, re-resolve latest from the network.
  trampolines         Regenerate architecture-neutral executable shims
  clean [WHAT] --yes  Remove cache (default), arch tree, or all
  help                This message

Environment:
  UVM_ROOT            Base directory for per-user uv state (set by the module)
  UVM_PIN             uv version to provision and select
  UVM_PLATFORM        Override the architecture key (default: uname -m)
  UVM_INSTALL_URL     Installer base URL, for sites mirroring Astral
  UVM_LOCK_TIMEOUT    Seconds to wait for the provisioning lock (default: 180)
  UVM_LOCK_STALE      Seconds before an untouched lock is broken (default: 600)

'uvm' is a short alias for 'uv-manager'. The same script is also installed as
'uv' and 'uvx', which pass through to the real uv for this node's architecture.
```

## D — `uv self update --help`, intercepted

```
Usage: uv self update [TARGET_VERSION]

Intercepted by uv-manager. Re-provisions this user's uv for arm64 under
$SANDBOX/root/arm64 instead of attempting an in-place self-update, which cannot work
for an unmanaged install.

Options:
  --dry-run    Report what would happen and exit
  -h, --help   Show this message

See also: uv-manager install [VERSION], uv-manager versions
```

## E — generated trampoline body

Thirteen lines, which is what makes the `README.md` claim of a "four-line `sh` script" wrong.

```sh
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
```

## F — provisioning, offline fixture

```
uv-manager: installing uv (latest) for arm64
fixture: installed uv 9.9.9 into $SANDBOX/root/arm64/versions/.incoming.Ym0oALCu
uv 9.9.9 (fixture)
current -> versions/9.9.9
```
