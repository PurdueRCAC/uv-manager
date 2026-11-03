# 03 — The trampoline and the wrapper's internal entry (R3, R6, R7, N8)

Measured 2026-11-01 on macOS, `/bin/sh` being bash 3.2.57 in POSIX mode. The cluster's `/bin/sh`
is bash or dash; the body uses nothing either lacks (`case`, `[ ]`, `${0##*/}`, `command -v`,
`$( )`, `exec`).

## The body

```sh
#!/bin/sh
# uv-manager-trampoline — generated; edits will be lost.
n=${0##*/}
case ${UVM_REPAIR:-0} in
0)  if [ -n "${UVM_ROOT:-}" ]; then
        a=${UVM_PLATFORM:-$(uname -m)}
        for s in shims python-shims; do
            if [ -x "$UVM_ROOT/$a/bin/$s/$n" ]; then exec "$UVM_ROOT/$a/bin/$s/$n" "$@"; fi
        done
    fi ;;
esac
w=$(command -v uv-manager) || w='<the generating wrapper's directory>/uv-manager'
if [ ! -x "$w" ]; then
    echo "uv-manager: '$n' needs uv-manager on PATH; load the uv module." >&2
    exit 127
fi
exec "$w" _trampoline "$n" "$@"
```

Three paths, as the GOAL's design direction names them:

1. **Knob off, `UVM_ROOT` set, shim executable**: exec the shim. No wrapper, no lock.
2. **Knob on**: exec the wrapper's internal entry with the command's name.
3. **Shim missing or `UVM_ROOT` unset**: exec the internal entry, which resolves the root by the
   wrapper's cascade (N8) and then runs the shim or says why it cannot.

`UVM_ROOT` comes from the modulefile or from the wrapper, which now exports it and `UVM_DATA` to
everything it runs (N8). The root is never baked in: a second cluster sharing `UVM_DATA` has its own.

**The knob's spelling in `sh`.** `case ${UVM_REPAIR:-0} in 0)` treats unset, empty and `0` as off
and everything else as on, `00` and `false` included, as the wrapper's `[[ -n … && … != 0 ]]` does.
Executed with a stand-in `uv-manager` first on `PATH` that leaves a marker:

| `UVM_REPAIR` | entered the wrapper |
|---|---|
| unset, `''`, `0` | no (shim ran) |
| `00`, `false`, `1` | yes |
| unset, `UVM_ROOT` unset | yes |
| unset, shim missing | yes |

That stand-in is also how R6's gate proves "without starting the wrapper": the trampoline looks
`uv-manager` up on `PATH` before its baked path, so a marker-leaving stand-in placed first on
`PATH` would be entered if any path reached it.

**Which wrapper.** `uv-manager` on `PATH` first: it is what the user's `uv` resolves, so the
trampoline's check and a `uv` call's check are the same version's. The baked path, the generating
wrapper's own directory plus `/uv-manager` (deployments keep `uv`, `uvx`, `uvm` beside it, §12),
covers an automation context that invoked the wrapper by absolute path with no module. A path
containing `'` is not baked (it falls through to the message). `command -v` inside `$( )` costs a
subshell, but only on paths 2 and 3.

## Cost (R6)

300 warm calls each, a shim that exits 0, `UVM_PLATFORM` set (so neither body forks `uname`):

| | per call |
|---|---|
| bare shim | 4.0 ms |
| `release/0.8.0`'s trampoline (`d=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)`) | 10.8 ms |
| this body | 7.6 ms |

With `UVM_PLATFORM` unset (one `uname -m` fork in each): 12.8 ms against 9.7 ms. The new body drops
the two command substitutions and the `dirname` exec that located the tree from `$0`, which stops
working under `UVM_DATA` anyway. The P2 gate measures 1200 calls of each inside `temp_root.sh`
(16 s against 11 s on the prototype) and asserts the new total is at most the old plus 1 s.

## The internal entry: `uv-manager _trampoline NAME [ARG...]`

Dispatched in `uvm_manager_main` beside `help`, before `uvm_init`, to `uvm_tool_entry`:

- `uvm_init`, `uvm_set_paths` (pure).
- **Knob on:** `uvm_ensure_uv`, `uvm_export_env`, `uvm_repair` (the same scope check, lock,
  outcome and failure contract a `uv` call runs; R3), then, with the shim still missing, the
  on-demand restore by name (R5, P4).
- The shim, under `UV_TOOL_BIN_DIR` then `UV_PYTHON_BIN_DIR`: `uvm_export_env`, `uvm_unlock`,
  `exec`. A new exec site, so it releases first (§5); exit status and signals are the tool's (§2).
- No shim: exit 127, naming the command. With a record naming it as an entrypoint: "'fx' is
  recorded but not installed for architecture 'arm64'. With UVM_REPAIR set, running it restores it
  here; uv-manager doctor says more." Without one, 0.7.0's three lines, unchanged. The knob-off
  path reaches this without `uvm_ensure_uv` or `uvm_export_env`, so it takes no lock and creates
  nothing (R6).

Fixture-measured on the prototype (P2 gate): `SLURM_JOB_ID=100 UVM_REPAIR=1 fx` beside tree (F)
prints one repair line on stderr, records `job-100.ok`, prints exactly `fx-ran`; the second call
prints no repair line; `FX_RC=7` gives rc 7; with the fixture's repair failing, rc 1, the shim
never ran, and stderr names "the repair for Slurm job 101".

## Generation (R7, N6)

- Names: every shim name under `${uvm_base}/*/bin/{shims,python-shims}`, dangling or not, and
  every line of every record's `entrypoints`. A record keeps its trampolines past a purge of the
  shims. A marked trampoline is removed only when neither names it.
- Directory: `$UVM_DATA/bin`, created under `umask 077` by the sync and by nothing on the hot path
  (`uvm_export_env`'s guard drops from six directories to five).
- §9 carries over unchanged: the marker, rewrite-never-skip, temp file and `mv -f`, the
  unmarked-non-empty-executable spare rule, `/bin/sh`, the platform key at exec time.
- **Migration (N6):** a sync called with `migrate` removes every file in `${uvm_base}/bin` that
  carries the marker and nothing else. The `uv tool` and `uv python` intercept, `uvm trampolines`
  and `uvm install` pass it; doctor does not, since R8 forbids it writing under `UVM_ROOT`.
  Prototype: a marked 0.7.0 trampoline is removed and an unmarked executable script beside it stays.
- With `UVM_ROOT` unset and the tree reachable through `SCRATCH`, the trampoline enters the
  wrapper, which resolves `$SCRATCH/.uv`, exports both trees and execs the shim, which sees
  `UVM_ROOT=$SCRATCH/.uv` and `UVM_DATA` in its environment. With nothing resolvable, the cascade's
  message names `UVM_ROOT`.

## The upgrade gap

`$UVM_DATA/bin` is empty until the first sync after the upgrade: any `uv tool` or `uv python`
command, `uvm trampolines`, or `uvm doctor`. A user whose first act under 0.8.0 is `srun <tool>`
gets "command not found". Closing it on the hot path means a `[[ -d ]]` test in every call and a
write under `UVM_DATA` from commands R10 says write nothing there. PLAN §5 carries it as an open
question; the plan's default is the release note and the README's upgrade step.

**Amended at the plan gate (2026-11-01).** The gap is closed, not documented: the 0.8.x module keeps
`$UVM_ROOT/bin` after `$UVM_DATA/bin`, so a 0.7.0 trampoline serves until replaced; a sync removes
it only once its replacement exists; and any `uv` call that finds `$UVM_DATA/bin` absent generates
it once. The test is one `[[ -d ]]`: 5.2 µs per call on bash 3.2 and APFS, over 200 000 iterations.
P2's gate drives it on a tree `release/0.8.0` built, with no `uv` call before the ranks.
