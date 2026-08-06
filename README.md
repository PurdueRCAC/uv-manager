# uv-manager

A transparent wrapper around [`uv`](https://docs.astral.sh/uv/) that makes it behave correctly
on an HPC cluster: no home-directory quota consumption, no architecture mismatches between login
and compute nodes, and no shared state between users.

It is a single bash script. Users type `uv` and `uvx` and get the real thing.

```console
$ module load uv
$ uv --version
uv 0.12.2
$ uv-manager status
uv-manager:            0.2.0
architecture:          x86_64
state root:            /anvil/scratch/x-glentner/.uv  (from UV_MANAGER_ROOT)
arch root:             /anvil/scratch/x-glentner/.uv/x86_64
selected version:      versions/0.12.2
...
```

---

## Contents

- [Why this exists](#why-this-exists)
- [What the wrapper does](#what-the-wrapper-does)
- [For users](#for-users)
- [For administrators: deployment](#for-administrators-deployment)
- [Adapting to your site](#adapting-to-your-site)
- [Scratch purges and what uv does not notice](#scratch-purges-and-what-uv-does-not-notice)
- [Design notes](#design-notes)
- [Automation: Globus Compute endpoints](#automation-globus-compute-endpoints)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)

---

## Why this exists

`uv` suits HPC well: a single static binary, no bootstrap interpreter, fast enough that
provisioning an environment inside a job prologue is reasonable, and a lockfile format that makes
runs reproducible. Users want it, and we want them to have it.

Out of the box, though, `uv` makes three assumptions that a cluster violates.

### 1. It assumes your home directory is a reasonable place to put things

By default `uv` writes to:

| What | Default location |
| --- | --- |
| The `uv` binary (standalone installer) | `~/.local/bin` |
| Download / wheel cache | `$XDG_CACHE_HOME/uv` → `~/.cache/uv` |
| Tool virtual environments (`uv tool install`) | `~/.local/share/uv/tools` |
| Tool executables | `~/.local/bin` |
| Managed Python interpreters (`uv python install`) | `~/.local/share/uv/python` |

All of those are on `/home`. At Purdue that is a 25 GB quota that cannot be raised. A single
uv-managed CPython is about 150 MB unpacked, and a cache holding a few PyTorch and JAX builds runs
to tens of gigabytes. Users fill their home directory and then find out about it when a job dies
overnight on a failed write, or when their shell stops working.

Home is also the wrong filesystem for this work even when it fits. It is provisioned as
medium-performance, snapshotted, non-purged space. Putting the metadata traffic of a hundred ranks
resolving dependency trees onto it is slow, and it degrades the filesystem for everyone else.

### 2. It assumes every node has the same CPU architecture

This is the assumption that costs people jobs. Clusters are increasingly heterogeneous: login
nodes and most partitions are `x86_64`, while newer accelerated partitions are `aarch64`
(Grace-Hopper, GB10, and similar).

A user logs into the login node, runs `uvx vllm` or `uv sync`, gets a working environment, and
submits to an `aarch64` partition. `uv` itself, the managed interpreter, every compiled wheel in
the venv, and every tool executable in `~/.local/bin` are the wrong architecture. The failure is
`Exec format error`, typically thousands of lines into a job log, after the allocation has been
charged.

Nothing in `uv` guards against this, because on a normal machine it cannot happen. Partitioning
per-user state by architecture is the wrapper's main job.

### 3. It assumes an interactive human with a shell profile

`uv`'s installer edits shell startup files. Its tool executables are only useful if a directory
gets added to `PATH`. Neither assumption holds in a batch job, a systemd user service, or a
Globus Compute endpoint spawning workers.

### Why not a shared module?

The obvious alternative is a site-wide `module load uv` backed by one blessed binary and, perhaps,
shared environments in `/apps`. We chose not to:

- **Version alignment belongs to the user.** The point of `uv` is that a project pins its own
  toolchain. A site-blessed version becomes something users work around as soon as it lags what a
  `pyproject.toml` expects. It also conflicts with the Globus Compute case below, where the
  client's versions dictate what has to be provisioned.
- **Shared environments carry ongoing cost.** They need a curation policy, a deprecation policy,
  a permissions model, and someone to own all three. `uv` builds most environments from a
  warm cache in seconds.
- **Shared mutable state causes accidents.** One user's `uv tool install` should not be able to
  affect another's.

So every user gets their own `uv` and their own environments, and the site provides a launcher
that puts them in the right place. That is the whole scope of the project.

---

## What the wrapper does

`bin/uv`, `bin/uvx` and `bin/uv-manager` are the same file. The latter two are symlinks, and the
script picks its mode from `basename $0`, the same way real `uv` does.

On every invocation it:

1. **Resolves the state root.** `$UV_MANAGER_ROOT` if set (normally by the modulefile), otherwise
   a cascade over conventional site variables. It refuses to run if neither yields a writable
   directory. See [Adapting to your site](#adapting-to-your-site).

2. **Appends the architecture** (`uname -m`) and derives the tree:

   ```
   $UV_MANAGER_ROOT/
   ├── bin/                     architecture-neutral trampolines  ← safe on PATH
   └── <arch>/
       ├── versions/<ver>/      uv + uvx, one directory per version
       ├── current -> versions/<ver>
       ├── bin/shims/           tool executables      (UV_TOOL_BIN_DIR)
       ├── bin/python-shims/    managed python links  (UV_PYTHON_BIN_DIR)
       ├── cache/               download + wheel cache (UV_CACHE_DIR)
       ├── tools/               tool virtual environments (UV_TOOL_DIR)
       └── python/              managed interpreters (UV_PYTHON_INSTALL_DIR)
   ```

3. **Provisions `uv` on first use for that architecture**, into a version-keyed directory, with
   `current` swapped atomically. Concurrent invocations serialize on an atomic `mkdir` lock that
   releases itself on signals and breaks itself when abandoned.

4. **Exports the `UV_*` storage variables** and `exec`s the real binary. Because it `exec`s, exit
   codes and signals are the real `uv`'s and the overhead is one `fork` of bash.

5. **Intercepts `uv self update`**, which cannot work for an unmanaged install, turning it into a
   re-provision.

6. **Maintains architecture-neutral trampolines** so executables from `uv tool install` and
   `uv python install` are reachable from a single `PATH` entry on every node type.

`UV_UNMANAGED_INSTALL` is doing several jobs at once here. Reading
[`install.sh`](https://astral.sh/uv/install.sh) confirms it sets `NO_MODIFY_PATH=1` and
`INSTALL_UPDATER=0`, and that `INSTALL_UPDATER=0` gates the receipt write. So:

- No shell startup file is edited.
- No receipt is written to `$XDG_CONFIG_HOME/uv/uv-receipt.json`, so provisioning does not clobber
  the bookkeeping of a user's own personal `uv` in `~/.local/bin`. The two coexist.
- The binary's own `uv self update` is disabled as a side effect, which is why we intercept it.
- The installer verifies an inlined SHA-256 and places binaries with `mv` within the destination
  directory, an atomic rename, so re-provisioning under a running process is safe.

---

## For users

```bash
module load uv

uv init myproject && cd myproject
uv add numpy
uv run python -c 'import numpy; print(numpy.__version__)'

uvx ruff check .        # ephemeral tool, nothing installed
```

Everything is ordinary `uv`. The additions live under `uv-manager`:

| Command | Effect |
| --- | --- |
| `uv-manager status` | Every resolved path and the selected version. Useful in a support ticket. |
| `uv-manager doctor` | Check for a partially purged or damaged tree. See below. |
| `uv-manager versions` | List `uv` versions installed for this architecture. |
| `uv-manager install [VER]` | Provision a version (default: latest). |
| `uv-manager use VER` | Switch to an already-installed version. Instant. |
| `uv-manager refresh` | Force re-provisioning from the network. |
| `uv-manager trampolines` | Regenerate the neutral executable shims. |
| `uv-manager env` | Print shell exports for the current node. |
| `uv-manager clean [cache\|arch\|all] --yes` | Remove part of the tree. |

`uv status` still works as a deprecated alias for `uv-manager status`.

Three things worth putting in your site documentation:

**First use on each architecture downloads `uv`.** It takes a few seconds and needs outbound
HTTPS. If your compute nodes have no egress, users must run any `uv` command once on a node of the
same architecture that does.

**A project's `.venv` is still the user's to manage.** The wrapper relocates uv's own storage. It
does not set `UV_PROJECT_ENVIRONMENT`, so `uv sync` still creates `./.venv`. If the project lives
in `$HOME`, that venv counts against home quota and is architecture-specific:

```bash
export UV_PROJECT_ENVIRONMENT=".venv-$(uname -m)"
```

**Scratch is purged, and `uv` will not notice.** See
[below](#scratch-purges-and-what-uv-does-not-notice). This is the one remaining problem the
wrapper cannot fully solve.

---

## For administrators: deployment

### Layout

```
/apps/external/uv/main/
└── bin/
    ├── uv                  the wrapper
    ├── uvx -> uv           symlink
    └── uv-manager -> uv    symlink
```

```bash
git clone https://github.com/purduercac/uv-manager /apps/external/uv/main
chmod 0755 /apps/external/uv/main/bin/uv
```

The symlinks have to survive deployment. `git clone` and `rsync -a` preserve them; `cp -r` without
`-a` does not, and a `uvx` that is a copy of the script will silently run in `uv` mode.

Do not install this as `~/.local/bin/uv`. That is the standalone installer's default
`UV_INSTALL_DIR`, so the wrapper would overwrite, or be overwritten by, a user's own real `uv`.

### The Lmod module

A complete, commented modulefile is in
[`share/modulefiles/uv/main.lua`](share/modulefiles/uv/main.lua). The essential part:

```lua
local prefix  = "/apps/external/uv/" .. myModuleVersion()
local scratch = os.getenv("CLUSTER_SCRATCH") or os.getenv("RCAC_SCRATCH")
                                             or os.getenv("SCRATCH")

prepend_path("PATH", pathJoin(prefix, "bin"))

if scratch ~= nil then
    local root = pathJoin(scratch, ".uv")
    setenv("UV_MANAGER_ROOT", root)
    prepend_path("PATH", pathJoin(root, "bin"))   -- neutral trampolines
end
```

**Every path this modulefile exports must be architecture-neutral.** Getting this wrong is the
main deployment hazard, so the mechanism is worth stating:

A modulefile is evaluated on whatever node runs `module load`, normally an `x86_64` login node.
Slurm's default `--export=ALL` then copies that environment verbatim onto compute nodes that may
be `aarch64`. Something like `setenv("UV_CACHE_DIR", scratch .. "/.uv/x86_64/cache")` would be
wrong for every `aarch64` job, and would fail silently.

`UV_MANAGER_ROOT` is safe because the architecture is appended by the wrapper at exec time, on the
node that is actually running. So is `$UV_MANAGER_ROOT/bin`, which holds trampolines that
re-resolve `uname -m` when invoked. Do not inline the `UV_*` variables into the modulefile.

Two other deliberate omissions:

- **No `family()`.** Declaring `family("python")` would force-unload a user's `conda` or `python`
  module. `uv` coexists with them.
- **No `XDG_CONFIG_HOME` override.** That is where `~/.config/uv/uv.toml` lives: index URLs,
  credentials, mirrors. Redirecting it would change dependency resolution, not just storage.

### Site defaults for `uv` itself

For index mirrors, `link-mode` or `python-downloads`, prefer `uv`'s own system configuration file,
`/etc/uv/uv.toml`. Per [uv's docs](https://docs.astral.sh/uv/concepts/configuration-files/),
system config merges with the user's rather than replacing it. Do not use `UV_CONFIG_FILE`, which
replaces user config entirely. If you cannot manage `/etc` on compute images, set the
corresponding `UV_*` variables instead; [`etc/uv-manager.conf.example`](etc/uv-manager.conf.example)
lists the ones that matter on a parallel filesystem, with reasons.

### Pre-warming

If compute nodes lack outbound HTTPS, and it is worth verifying rather than assuming, do this once
per architecture at deployment time:

```bash
for host in <x86-login> <aarch64-node>; do
    ssh "$host" 'module load uv && uv --version && uv-manager status'
done
```

For a site with no egress at all, mirror the Astral release assets and set
`UV_MANAGER_INSTALL_URL` to your mirror; the wrapper fetches `<base>/install.sh` or
`<base>/<version>/install.sh`.

### Verification

```bash
module load uv
uv-manager status                    # every path under scratch, none under $HOME
uv-manager doctor
du -sh ~/.cache/uv ~/.local/share/uv 2>/dev/null   # should not exist

# flock works on your scratch filesystem; uv requires it
python3 -c 'import fcntl,os; f=os.open(os.environ["UV_MANAGER_ROOT"]+"/.t",os.O_CREAT|os.O_RDWR); fcntl.flock(f,fcntl.LOCK_EX); print("flock OK")'

# the arch split is real
srun -p <aarch64-partition> --pty bash -lc 'module load uv && uv-manager status'
```

---

## Adapting to your site

Almost everything is one variable.

### The state root

Set `UV_MANAGER_ROOT` from your modulefile. If it is unset the wrapper tries, in order:

```
$CLUSTER_SCRATCH   $RCAC_SCRATCH   $SCRATCH   $PSCRATCH   $WORK   $PROJECT
```

appending `/.uv` to the first that names an existing, writable directory. Adjust the
`uvm_candidates` array near the top of `bin/uv` if your site uses something else:

| Site | Variable |
| --- | --- |
| Purdue RCAC (community) | `$CLUSTER_SCRATCH`, `$RCAC_SCRATCH` |
| Purdue Anvil | `$SCRATCH`, `$PROJECT`/`$WORK` |
| NERSC | `$PSCRATCH`, `$SCRATCH`, `$CFS` |
| TACC | `$SCRATCH`, `$WORK`, `$WORK2` |
| OLCF | `$MEMBERWORK/<proj>`, `$PROJWORK/<proj>` |

There is deliberately no `/tmp` fallback. If nothing resolves, the wrapper prints every candidate
it tried along with why each failed, and exits non-zero. A silent fallback to node-local storage
would mean re-downloading `uv` on every node of every job, a cold cache everywhere, an egress
requirement on every node, and environments that disappear at job end. The contexts where the
variable is most likely to be missing are the automated ones, where nobody is watching.

### The platform key

`uname -m` is the default, and it is the right granularity for the `uv` binary and for uv-managed
CPython builds. It runs on every invocation, including inside loops calling `uv run` thousands of
times, so anything you replace it with should stay cheap. Override with `UV_MANAGER_PLATFORM`.
Sites that may need a finer key: glibc skew between login and compute images, musl-based
partitions, or `x86-64-v2/v3/v4` levels if users build wheels from source across a mixed fleet.

Note that `uname -m` reports `arm64` on macOS and `aarch64` on Linux, so a test deployment on a Mac
produces a different key.

### Filesystem semantics to verify before deploying

**`flock` must work.** `uv` takes `flock`-based exclusive locks on the cache, the managed-Python
directory, the tool directory, and the project environment. On a Lustre mount without `flock`,
`uv` fails outright:

```
Could not acquire lock for `.../python` at `.../python/.lock`: Function not implemented (os error 38)
```

`uv` has no bypass for this today
([astral-sh/uv#13626](https://github.com/astral-sh/uv/issues/13626)), and `UV_LOCK_TIMEOUT` does
not help when `flock` is absent entirely. NFS locking is separately known to be unsound across
client/server boundaries ([#18073](https://github.com/astral-sh/uv/issues/18073)).

The wrapper's own provisioning lock uses `mkdir` instead, which is atomic on Lustre, GPFS and NFS
and needs no `flock`.

**Link mode will fall back to copying.** `uv` defaults to `clone` (reflink), which Lustre, GPFS and
NFS do not support, then tries hardlink, which fails across filesystems. With the cache under
`UV_MANAGER_ROOT` and a project `.venv` on home, users see `Failed to hardlink files; falling back
to full copy` on every install. `UV_LINK_MODE=copy` makes that explicit and silences the warning;
keeping the venv on the same filesystem as the cache actually fixes it.

**Consider `UV_COMPILE_BYTECODE=1` and a real `TMPDIR`.** Without the first, the first import from
every rank of a large job writes `.pyc` concurrently into the same directory, which is a metadata
storm on Lustre. Without the second, building `torch` or `mpi4py` from source in a small tmpfs
`/tmp` fails with an error that does not point at the cause.

---

## Scratch purges and what uv does not notice

Scratch is purged per file on access and modification time: Anvil at 30 days with no warning email,
most Purdue community clusters at 60. The natural question is whether `uv` re-hydrates gracefully
afterwards. It does not, and the failure is quiet. Tested directly against uv 0.12.2:

| What is lost | What happens |
| --- | --- |
| Cache only | Fine. Re-downloads on next use. |
| An entire tool environment | `uvx <tool>` works, since uv rebuilds it. But the executable left in `bin/shims` by `uv tool install` becomes a dangling symlink and is not repaired. |
| A tool's `uv-receipt.toml` only | `uv tool list` warns `Ignoring malformed tool`; `uv tool run` quietly falls back to an ephemeral environment. |
| **Individual files inside an environment** | uv performs no integrity check on an environment it believes is installed. It execs it, and the user gets a Python `ImportError` traceback. |
| **Files inside a managed interpreter** | Same. Deleting `lib/python3.12/json` produced `ModuleNotFoundError: No module named 'json'` from uv's own interpreter probe, and broke the whole managed-Python subsystem. |

Partial loss happens in practice, not just in principle. Because purge is keyed per file on access
time, a hot module's `__init__.py` gets its atime refreshed on every run while `tests/`,
`*.dist-info` and rarely-imported submodules in the same environment go untouched for a month. An
environment used weekly can lose its cold files while the hot ones survive.

How much this matters depends on your mount options, which is worth checking. With `noatime`, atime
never updates, the purge falls back to mtime, and the whole tree ages uniformly, which is the
benign case. With `relatime`, or a GPFS policy engine using atime, partial loss is live.

Mitigations, in order of effectiveness:

1. **Put `UV_MANAGER_ROOT` on non-purged storage.** On Anvil that means `$PROJECT`, which is what
   RCAC's documentation already recommends for long-lived Python environments. Scratch is still
   fine for the cache alone if you want to split them.
2. **`uv-manager doctor`** detects what uv does not: dangling shims, missing receipts, damaged
   managed interpreters, and files missing from inside an environment, found by walking each
   distribution's `RECORD` manifest. Reasonable to run from a job prologue for anything long-lived.
3. **Prefer `uvx` over `uv tool install`.** Ephemeral environments are keyed off the cache and
   rebuild cleanly; installed ones accumulate damage.
4. **Watch inodes.** Anvil scratch allows 1,000,000 files and community scratch 2,000,000. A
   populated `uv` tree is a meaningful fraction of that. Run `uv cache prune` periodically.

---

## Design notes

Rationale for the choices that may look arbitrary.

**Dispatch on `basename $0`.** Real `uv` does the same, so `uvx` needs no separate code path and
stays correct if Astral changes what `uvx` means. It also gives wrapper-specific commands a home,
`uv-manager`, without shadowing `uv`'s own namespace, which matters because `uv` keeps adding
subcommands (`auth`, `format`, `check`, `audit` and `upgrade` are all recent).

**`exec`, not a subprocess.** Signals, exit codes and process accounting stay as they would be
without the wrapper. An `srun uv run ...` has to forward `SIGTERM` correctly at walltime, and a
wrapper that waited on a child would have to reimplement that. The exceptions are `uv tool` and
`uv python`, which change what needs a trampoline and so must run to completion.

**Version-keyed installs with an atomic symlink swap.** Makes a pin authoritative rather than
advisory, makes switching between downloaded versions instant, and makes rollback trivial.

**`mkdir` for the provisioning lock.** Atomic on Lustre, GPFS and NFS, needs no helper binary, and
does not depend on `flock`, which `uv` itself requires but which is not enabled everywhere.

**Architecture-neutral trampolines.** The only way to have one `PATH` entry that is correct on both
node types. Each is a four-line `sh` script that re-resolves `uname -m` at exec time. They are
generated for the union of names across all architectures, so invoking a tool on an architecture
where it is not installed gives a useful message instead of `Exec format error`.

**Not overriding `XDG_CONFIG_HOME`.** Storage is the wrapper's business; resolution is not.

**`mkdir -p` on every invocation** rather than behind a sentinel. It is a handful of metadata
operations, and it repairs a tree that a purge has partially eaten.

---

## Automation: Globus Compute endpoints

The wrapper's second job is backing Purdue's Globus Compute Multi-User Endpoint on Anvil.

Globus Compute has a long-standing alignment problem: the Python minor version and the SDK/Parsl
versions have to match across four hops, from client to MEP to the single-user endpoint the MEP
spawns to the workers. When they do not, failures surface as opaque deserialization errors. Anvil's
MEP handles this by intercepting the client's reported versions and using `uv` to just-in-time
provision a matching environment before the UEP starts, plus a default `worker_init` that
provisions worker environments from a site-level `requirements` parameter.

For that to work the wrapper has to survive an environment it did not choose:

- **A UEP is not spawned from a login shell**, so whatever your site sets in `/etc/profile.d` may
  not be present. Set `UV_MANAGER_ROOT` explicitly in the endpoint configuration rather than
  relying on inheritance. If it is missing, the wrapper now fails loudly with the exact fix instead
  of quietly using node-local `/tmp`.
- **`worker_init` runs on compute nodes**, so egress and pre-warming assumptions apply there.
- **Pin the version.** `UV_MANAGER_PIN` is authoritative: it selects which installed version
  `current` points at, so pinning to an already-downloaded version costs milliseconds.
- **Provision once, then run directly.** Keep `uv run` off the hot path of a many-rank launch. It
  takes a lock on the project environment, and N ranks starting at once either serialize on it or,
  where `flock` is unreliable, race.

```bash
# worker_init
export UV_MANAGER_ROOT="${SCRATCH}/.uv"
export UV_MANAGER_PIN=0.12.2
export PATH="/apps/external/uv/main/bin:$PATH"

export UV_PROJECT_ENVIRONMENT="${SCRATCH}/.venvs/${SLURM_JOB_ID}-$(uname -m)"
uv sync --frozen --quiet
export PATH="${UV_PROJECT_ENVIRONMENT}/bin:$PATH"
```

---

## Troubleshooting

**Start with `uv-manager status`.** It prints every resolved path, where the root came from, and
which version is selected.

**"cannot determine where to keep per-user uv state"** means `UV_MANAGER_ROOT` is unset and no
candidate resolved. The message lists each candidate and why it failed. The usual cause is a batch
or automation context that did not inherit a login shell.

**"install failed — no egress from this node?"** Pre-warm from a node of the same architecture that
has outbound HTTPS.

**A tool prints "is not installed for architecture 'aarch64'".** That is the trampoline working as
intended. Run `uv tool install <package>` on that architecture.

**`ImportError` from something that used to work** is usually a partial purge. Run
`uv-manager doctor`.

**`WARN: The following commands are shadowed by other commands in your PATH: uv uvx`** during
provisioning is cosmetic. The installer notices that the module's `bin/`, which holds the wrapper,
precedes its own install directory. That is the arrangement we want.

**Disk accounting.** `du -sh $UV_MANAGER_ROOT/*` breaks down cost per architecture.

---

## Reference

### Wrapper environment variables

| Variable | Effect |
| --- | --- |
| `UV_MANAGER_ROOT` | Base for per-user state. Architecture-neutral; the wrapper appends `<arch>`. |
| `UV_MANAGER_PIN` | `uv` version to provision and select. |
| `UV_MANAGER_REFRESH` | Non-empty forces re-provisioning from the network. |
| `UV_MANAGER_PLATFORM` | Override the architecture key. Default `uname -m`. |
| `UV_MANAGER_INSTALL_URL` | Installer base URL, for mirrors. Default `https://astral.sh/uv`. |
| `UV_MANAGER_LOCK_TIMEOUT` | Seconds to wait for the provisioning lock. Default 180. |
| `UV_MANAGER_LOCK_STALE` | Seconds after which an untouched lock is broken. Default 600. |

`UV_WRAPPER_PIN` and `UV_WRAPPER_REFRESH` are accepted as deprecated aliases.

### `uv` variables the wrapper sets

`UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR`,
all under `$UV_MANAGER_ROOT/<arch>/`, plus `PATH`.

### `uv` variables the wrapper deliberately leaves alone

`XDG_CONFIG_HOME`, `UV_CONFIG_FILE`, `UV_PROJECT_ENVIRONMENT`, `UV_DEFAULT_INDEX`, `UV_INDEX`,
`UV_PYTHON_PREFERENCE`, `UV_PYTHON_DOWNLOADS`, `UV_LINK_MODE`, `UV_COMPILE_BYTECODE`, `TMPDIR`.

The first two would change dependency resolution. The rest are site or user policy; see
[`etc/uv-manager.conf.example`](etc/uv-manager.conf.example).

### Repository layout

```
bin/uv, bin/uvx, bin/uv-manager   the wrapper (uvx and uv-manager are symlinks)
etc/uv-manager.conf.example       example site settings, heavily commented
share/modulefiles/uv/main.lua     example Lmod modulefile
```

### External references

- [uv environment variables](https://docs.astral.sh/uv/reference/environment/)
- [uv storage locations](https://docs.astral.sh/uv/reference/storage/)
- [uv configuration files](https://docs.astral.sh/uv/concepts/configuration-files/)
- [Astral standalone installer](https://astral.sh/uv/install.sh)
- [Purdue RCAC documentation](https://docs.rcac.purdue.edu/)
- [Globus Compute multi-user endpoints](https://globus-compute.readthedocs.io/)

---

## License

MIT. See [LICENSE](LICENSE).
