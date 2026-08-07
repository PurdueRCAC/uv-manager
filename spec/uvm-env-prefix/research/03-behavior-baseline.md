# Research 03 — Observable baseline (pre-rename) and post-rename verify design

Captured 2026-08-07 on macOS (`uname -m` = `arm64`), branch `feature/uvm-env-prefix`, at
`uvm_version=0.2.0`. Everything below was produced by driving the real script through
`.agents/factory/bin/temp_root.sh`; nothing is inferred from reading.

Sandbox paths are of the form `$TMPDIR/uv-manager-sandbox.XXXXXX/root` and change on every drive, so
no verify command may assert one literally. `--arch <key>` is the lever that makes the *tail* of every
path literal and machine-independent.

---

## 1. `uvm status` — verbatim, empty root

`uvm status` **works on a completely unprovisioned root and exits 0.** No verify that only inspects
paths, origin, or the pin needs `--offline`.

```
uv-manager:            0.2.0
invoked as:            uvm  (/Users/geoffrey/.../uv-manager/bin/uvm)
architecture:          arm64
state root:            <sandbox>/root  (from UV_MANAGER_ROOT)
arch root:             <sandbox>/root/arm64
selected version:      <none>
real uv:               <sandbox>/root/arm64/current/uv [MISSING]
real uvx:              <sandbox>/root/arm64/current/uvx [MISSING]
resolved version:      n/a
installed versions:
UV_CACHE_DIR:          <sandbox>/root/arm64/cache
UV_TOOL_DIR:           <sandbox>/root/arm64/tools
UV_TOOL_BIN_DIR:       <sandbox>/root/arm64/bin/shims
UV_PYTHON_INSTALL_DIR: <sandbox>/root/arm64/python
UV_PYTHON_BIN_DIR:     <sandbox>/root/arm64/bin/python-shims
trampoline dir:        <sandbox>/root/bin
XDG_CONFIG_HOME:       <sandbox>/config
pin:                   <none — tracks latest>
```

**Lines naming a variable.** Only the `state root:` line does, and it does so *literally*: the origin
string is the variable name. `uvm_resolve_root` (`bin/uv-manager:83`) sets it in exactly two shapes —

- env-var branch: `uvm_base_origin="UV_MANAGER_ROOT"` — **no `$` sigil** (`:86`);
- scratch-candidate branch: `uvm_base_origin="\$${name}"` — **with a `$` sigil**, e.g. `$SCRATCH` (`:96`).

So post-rename the asserted literal is `(from UVM_ROOT)`, bare. The `UV_CACHE_DIR:` … `UV_PYTHON_BIN_DIR:`
lines name `uv`'s own exported variables and are R3's subject — they must not move.

## 2. `uvm help` — the `Environment:` block, verbatim

Five lines, `^  UV_MANAGER_`, the last carrying two names:

```
Environment:
  UV_MANAGER_ROOT        Base directory for per-user uv state (set by the module)
  UV_MANAGER_PIN         uv version to provision and select
  UV_MANAGER_PLATFORM    Override the architecture key (default: uname -m)
  UV_MANAGER_INSTALL_URL Installer base URL, for sites mirroring Astral
  UV_MANAGER_LOCK_TIMEOUT / UV_MANAGER_LOCK_STALE
                         Provisioning lock wait and staleness, in seconds
```

Note the column alignment: the description column starts at 26. `UVM_INSTALL_URL` is 15 characters
against `UV_MANAGER_INSTALL_URL`'s 22, so the heredoc's padding must be re-flowed, not just renamed.
`uvm help` exits 0 and needs no root (`uvm_init` is deferred).

## 3. No-root failure path — exit code and exact stderr

Exit status **1**. Stderr, verbatim (candidate list rendered with all six unset):

```
uv-manager: cannot determine where to keep per-user uv state.

  UV_MANAGER_ROOT is unset, and none of these named an existing,
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
      export UV_MANAGER_ROOT=/path/to/large/scratch/.uv

  This must be on storage visible from every node that will run uv,
  at the same path, and it must not be your home directory.
```

Two lines here carry a variable name and are R5/R7 surface: `UV_MANAGER_ROOT is unset, …` and the
`export UV_MANAGER_ROOT=…` line.

**Defeating `temp_root.sh`'s own export.** Both of these work and both were driven:

- `.agents/factory/bin/temp_root.sh env -u UV_MANAGER_ROOT uvm status` → rc 1, full message.
- `.agents/factory/bin/temp_root.sh sh -c 'unset UV_MANAGER_ROOT; uvm status'` → rc 1, full message.

`temp_root.sh` already unsets all six scratch candidates, so nothing else needs suppressing.
**Prefer the `sh -c` form for R2**, because R2 must not merely unset the new name — it must *set the
legacy name to a real directory* and show it is ignored, and `sh -c` has the sandbox root in hand.
Driven today in mirror image (`UVM_ROOT` set to the sandbox root, `UV_MANAGER_ROOT` unset): rc 1 and
the same message, confirming a wrong-namespace name naming a perfectly good directory still fails.

## 4. Pin and platform, today

| Drive | Observable |
|---|---|
| `UV_MANAGER_PIN=1.2.3` inside the drive | `pin:                   1.2.3` |
| unset | `pin:                   <none — tracks latest>` (em dash, U+2014) |
| `--arch aarch64` | `architecture:          aarch64`; `arch root: <sandbox>/root/aarch64` |
| `UV_MANAGER_PLATFORM=ppc64le` inside the drive | `architecture: ppc64le`; arch root ends `/ppc64le` |

The platform key is unvalidated — `--arch testarch` is accepted and used verbatim, which is what makes
the R3 assertion below machine-independent.

`UV_MANAGER_PIN=1.2.3` set *outside* `temp_root.sh` reports no pin (the scrub catches it).
`UVM_PIN=1.2.3` set outside **reaches the drive today** — verified directly:

```
UVM_PIN=1.2.3 UVM_FIXTURE_VERSION=7.7.7 temp_root.sh sh -c 'echo "[${UVM_PIN:-}] [${UVM_FIXTURE_VERSION:-}]"'
  → [1.2.3] [7.7.7]
```

This is R6's whole point. The scrub regex `^\(UV_[A-Za-z0-9_]*\)=` requires a literal `_` as the third
character, so `UVM_PIN=` never matches. It passes today only because `UVM_PIN` is unread; post-rename
it becomes a live leak. The same drive shows `UVM_FIXTURE_VERSION` passing through — a blanket `UVM_*`
scrub would break the fixture knobs the GOAL flags, so the scrub must enumerate the six wrapper knobs.

## 5. Offline provisioning

`.agents/factory/bin/temp_root.sh --offline uv --version` → exit 0.

- stdout, alone: `uv 9.9.9 (fixture)` — nothing else. Installer chatter is on stderr (invariant §7).
- `readlink <root>/<arch>/current` → **`versions/9.9.9`** (relative, per the relocatability invariant).
- `uvm status` then reports `selected version: versions/9.9.9`, `resolved version: uv 9.9.9 (fixture)`,
  `installed versions:    9.9.9`.

A pinned offline install also drives cleanly, and is the strongest single R1 assertion available.
Copy `install.sh` to `$UVM_FIXTURE_DIR/<ver>/install.sh` (the wrapper fetches
`${install_base_url}/${want}/install.sh`, `bin/uv-manager:317`) and export `UVM_FIXTURE_VERSION` to
match, otherwise the stub reports 9.9.9 and `current` lands on `versions/9.9.9` — a trap worth knowing.
With both set: `current` → `versions/1.2.3`.

Lock knobs are observable too, both driven:

- `LOCK_TIMEOUT=1` with `.install.lock` pre-created → rc 1,
  `uv-manager: timed out after 1s waiting for provisioning lock: …`
- `LOCK_STALE=0` with `.install.lock` pre-created → `uv-manager: breaking stale provisioning lock (1s old): …`
  then a normal install, rc 0.

## 6. Proposed `verify:` commands (post-rename)

Each was dry-run today in mirror image (old names swapped for new) and **passed**. All avoid `"` and
`\`, so they embed in a double-quoted YAML scalar without escaping.

**R1** — the six new names are read. Two lines; the first covers ROOT/PLATFORM/INSTALL_URL/PIN, the
second LOCK_STALE.

```
.agents/factory/bin/temp_root.sh --offline --arch testarch sh -c 'mkdir -p $UVM_FIXTURE_DIR/1.2.3; cp $UVM_FIXTURE_DIR/install.sh $UVM_FIXTURE_DIR/1.2.3/install.sh; UVM_FIXTURE_VERSION=1.2.3 UVM_PIN=1.2.3 uv --version >/dev/null 2>&1; readlink $UVM_ROOT/testarch/current' | grep -qx versions/1.2.3
```
```
.agents/factory/bin/temp_root.sh --offline sh -c 'mkdir -p $UVM_ROOT/$(uname -m)/.install.lock; UVM_LOCK_STALE=0 UVM_LOCK_TIMEOUT=5 uv --version' 2>&1 | grep -q breaking.stale.provisioning.lock
```
For LOCK_TIMEOUT specifically (costs ~2 s):
```
.agents/factory/bin/temp_root.sh --offline sh -c 'mkdir -p $UVM_ROOT/$(uname -m)/.install.lock; UVM_LOCK_TIMEOUT=1 uv --version' 2>&1 | grep -q timed.out.after.1s
```

**R2** — a legacy name has no effect.
```
.agents/factory/bin/temp_root.sh sh -c 'UV_MANAGER_ROOT=$UVM_ROOT; export UV_MANAGER_ROOT; unset UVM_ROOT; uvm status 2>e; test $? -eq 1 || exit 1; grep -q keep.per-user e'
```
Asserts both the exit code and the message. `e` lands in the sandbox cwd and dies with it.

**R3** — the five exported storage paths are unchanged.
```
.agents/factory/bin/temp_root.sh --arch testarch uvm status | grep '^UV_' | sed 's|.*/testarch/|/testarch/|' | paste -sd, - | grep -qx '/testarch/cache,/testarch/tools,/testarch/bin/shims,/testarch/python,/testarch/bin/python-shims'
```
Exactly five `^UV_` lines exist in `status`; the fixed `--arch` makes the tails literal and the `sed`
strips the random sandbox prefix. Asserts order, count and every path.

**R4** — origin and help.
```
.agents/factory/bin/temp_root.sh uvm status | grep '^state root:' | grep -qF '(from UVM_ROOT)'
```
```
.agents/factory/bin/temp_root.sh sh -c 'uvm help > h; grep -q UV_MANAGER_ h && exit 1; for n in ROOT PIN PLATFORM INSTALL_URL LOCK_TIMEOUT LOCK_STALE; do grep -q UVM_$n h || exit 1; done; echo OK' | grep -qx OK
```
The second is both halves of R4's help clause in one drive: no legacy name survives, all six new names
appear.

**R6** — an inherited wrapper knob does not reach a drive, and a fixture knob still does.
```
UVM_PIN=1.2.3 .agents/factory/bin/temp_root.sh uvm status | grep '^pin:' | grep -qF '<none'
```
```
UVM_FIXTURE_VERSION=7.7.7 .agents/factory/bin/temp_root.sh --offline uv --version 2>/dev/null | grep -qF 'uv 7.7.7 (fixture)'
```
The second is the guard against over-scrubbing; without it a wildcard `UVM_*` scrub passes R6 and
silently breaks every fixture-parameterized drive.

### Quoting notes

- None of the above contains `"` or `\`, so each drops into `verify: "…"` unchanged.
- `grep -q keep.per-user`, `grep -q timed.out.after.1s`, `grep -q breaking.stale.provisioning.lock`
  use `.` for the literal spaces deliberately — it removes the last reason to quote a pattern.
- `grep -qF '<none'` matches the em dash line without embedding U+2014 in a verify command. Do **not**
  try to match `<none — tracks latest>` literally.
- The only mildly awkward one is R1's first command: it is long, and the `$UVM_FIXTURE_DIR` /
  `$UVM_ROOT` expansions must stay inside the drive's single quotes so they resolve to the sandbox and
  not to the developer's environment. Splitting it into a `sh -c` with a leading `set -e` would be
  worse to embed, not better.
- `paste -sd, -` in R3 is BSD- and GNU-compatible as written.
