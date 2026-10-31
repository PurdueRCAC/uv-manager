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
uv-manager:            0.6.1
invoked as:            uv-manager  (/apps/external/uv/main/bin/uv-manager)
architecture:          x86_64
state root:            /anvil/scratch/x-lentner/.uv  (from UVM_ROOT)
arch root:             /anvil/scratch/x-lentner/.uv/x86_64
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

`bin/uv-manager` is the script. `bin/uv`, `bin/uvx` and `bin/uvm` are symlinks to it, and it
picks its mode from `basename $0`, the same way real `uv` does.

On every invocation it:

1. **Resolves the state root.** `$UVM_ROOT` if set (normally by the modulefile), otherwise a
   cascade over conventional site variables. It refuses to run if neither yields a writable
   directory. See [Adapting to your site](#adapting-to-your-site).

2. **Appends the architecture** (`uname -m`) and derives the tree:

   ```
   $UVM_ROOT/
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
   is released on signals too. A call that has waited `UVM_LOCK_TIMEOUT` for it installs for
   itself rather than failing; when several publish the same version at once, one copy is kept
   and the others are discarded.

4. **Exports the `UV_*` storage variables** and `exec`s the real binary. With `UVM_REPAIR` set it
   first repairs what a scratch purge removed (see [below](#repairing-inside-a-job)). Because it
   `exec`s, exit codes and signals are the real `uv`'s. The wrapper adds roughly 5 ms per invocation on top of
   `uv` itself, which matters only if you are calling it tens of thousands of times.

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
| `uv-manager install [VER]` | Select a version, downloading it if absent. With no version, re-resolve latest from the network. |
| `uv-manager trampolines` | Regenerate the neutral executable shims. |
| `uv-manager clean [cache\|lock\|outcomes\|arch\|all] --yes` | Remove part of the tree. `lock` removes the provisioning lock and the repair lock and leaves the installed versions alone. `outcomes` removes the recorded repair outcomes, so each scope checks again. Without `--yes`, each prints what it would remove. |

`uvm` is a short alias for `uv-manager`, so `uvm status` and `uvm doctor` work too.

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
wrapper cannot fully solve. Inside a Slurm job, `UVM_REPAIR=1` on the `uv` or `uvx` call repairs
what it can detect before the command runs.

---

## For administrators: deployment

### Layout

```
/apps/external/uv/main/
└── bin/
    ├── uv-manager          the script
    ├── uv  -> uv-manager
    ├── uvx -> uv-manager
    └── uvm -> uv-manager   short alias for uv-manager
```

```bash
git clone https://github.com/purduercac/uv-manager /apps/external/uv/main
```

Use `git clone` or `rsync -a` so the symlinks stay symlinks. `cp -r` is not portable here: GNU
coreutils preserves them, macOS and the BSDs dereference them into four independent copies, which
still dispatch correctly (mode comes from the invoked name, not from whether it is a symlink) but
will drift apart on the next update. `cp -R` and `cp -a` preserve them on both.

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
    setenv("UVM_ROOT", root)
    prepend_path("PATH", pathJoin(root, "bin"))   -- neutral trampolines
end
```

**Every path this modulefile exports must be architecture-neutral.** Getting this wrong is the
main deployment hazard, so the mechanism is worth stating:

A modulefile is evaluated on whatever node runs `module load`, normally an `x86_64` login node.
Slurm's default `--export=ALL` then copies that environment verbatim onto compute nodes that may
be `aarch64`. Something like `setenv("UV_CACHE_DIR", scratch .. "/.uv/x86_64/cache")` would be
wrong for every `aarch64` job, and would fail silently.

`UVM_ROOT` is safe because the architecture is appended by the wrapper at exec time, on the node
that is actually running. So is `$UVM_ROOT/bin`, which holds trampolines that re-resolve the
platform key when invoked. Do not inline the `UV_*` variables into the modulefile.

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

If compute nodes lack outbound HTTPS — worth verifying rather than assuming — do this once per
architecture at deployment time:

```bash
for host in <x86-login> <aarch64-node>; do
    ssh "$host" 'module load uv && uv --version && uv-manager status'
done
```

For a site with no egress at all, mirror the Astral release assets and set `UVM_INSTALL_URL` to
your mirror; the wrapper fetches `<base>/install.sh` or `<base>/<version>/install.sh`.

### Verification

```bash
module load uv
uv-manager status                    # every path under scratch, none under $HOME
uv-manager doctor
du -sh ~/.cache/uv ~/.local/share/uv 2>/dev/null   # should not exist

# flock works on your scratch filesystem; uv requires it
python3 -c 'import fcntl,os; f=os.open(os.environ["UVM_ROOT"]+"/.t",os.O_CREAT|os.O_RDWR); fcntl.flock(f,fcntl.LOCK_EX); print("flock OK")'

# the arch split is real
srun -p <aarch64-partition> --pty bash -lc 'module load uv && uv-manager status'
```

---

## Adapting to your site

Almost everything is one variable.

### The state root

Set `UVM_ROOT` from your modulefile, from `/etc/profile.d`, or from a user's own shell profile.

If `UVM_ROOT` is unset, the wrapper tries, in order:

```
$CLUSTER_SCRATCH   $RCAC_SCRATCH   $SCRATCH   $PSCRATCH   $WORK   $PROJECT
```

appending `/.uv` to the first that names an existing, writable directory. Adjust the
`uvm_candidates` array near the top of `bin/uv-manager` if your site uses something else:

| Site | Variable |
| --- | --- |
| Purdue RCAC (community) | `$CLUSTER_SCRATCH`, `$RCAC_SCRATCH` |
| Purdue Anvil | `$SCRATCH`, `$PROJECT`/`$WORK` |
| NERSC | `$PSCRATCH`, `$SCRATCH`, `$CFS` |
| TACC | `$SCRATCH`, `$WORK`, `$WORK2` |
| OLCF | `$MEMBERWORK/<proj>`, `$PROJWORK/<proj>` |

Adjusting the array patches the deployed script, and that patch cannot coexist with an update:
`git pull` aborts, `rsync -a` overwrites it silently. Somebody re-applies the edit after every
update, or every user drops back to the stock cascade. Setting `UVM_ROOT` has no such cost.

There is deliberately no `/tmp` fallback. If nothing resolves, the wrapper prints every candidate
it tried along with why each failed, and exits non-zero. A silent fallback to node-local storage
would mean re-downloading `uv` on every node of every job, a cold cache everywhere, an egress
requirement on every node, and environments that disappear at job end. The contexts where the
variable is most likely to be missing are the automated ones, where nobody is watching.

### The platform key

`uname -m` is the default, and it is the right granularity for the `uv` binary and for uv-managed
CPython builds. It runs on every invocation, including inside loops calling `uv run` thousands of
times, so anything you replace it with should stay cheap. Override with `UVM_PLATFORM`. Sites that
may need a finer key: glibc skew between login and compute images, musl-based partitions, or
`x86-64-v2/v3/v4` levels if users build wheels from source across a mixed fleet.

`uname -m` reports `arm64` on macOS and `aarch64` on Linux, so a test deployment on a Mac produces a
different key.

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

The wrapper's own locks, one for provisioning and one for the purge repair, use `mkdir` instead,
which is atomic on Lustre, GPFS and NFS and needs no `flock`.

**Link mode will fall back to copying.** `uv` defaults to `clone` (reflink), which Lustre, GPFS and
NFS do not support, then tries hardlink, which fails across filesystems. With the cache under
`UVM_ROOT` and a project `.venv` on home, users see `Failed to hardlink files; falling back to
full copy` on every install. `UV_LINK_MODE=copy` makes that explicit and silences the warning;
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

1. **Put `UVM_ROOT` on non-purged storage.** On Anvil that means `$PROJECT`, which is what
   RCAC's documentation already recommends for long-lived Python environments. Scratch is still
   fine for the cache alone if you want to split them.
2. **`uv-manager doctor`** looks at every installed distribution and reports the damage uv ignores:
   dangling shims, a tool directory that lost its `pyvenv.cfg` or its receipt, a damaged managed
   interpreter, a distribution whose `RECORD` manifest is gone, and files a surviving manifest lists
   that are no longer on disk. As advisories, it also reports a provisioning or repair lock left
   standing, with the owner line it records, any staging copy an interrupted install left under
   `versions/`, and a repair that failed (see [Repairing inside a job](#repairing-inside-a-job)).
   Each of those lines names what to remove and says the process that left it may still be running,
   because nothing on disk can tell. Failures set the exit status and advisories do not, so a job
   prologue can key on it. Its floor is whatever nothing on disk records. A distribution removed
   entirely leaves no evidence, because `uv-receipt.toml` names the request — `jupyterlab` — not
   the 91 distributions uv resolved it to; a managed interpreter carries no manifest at all, so the
   check there is whether `import json, os, ssl` still succeeds, which it does with `email/`, `xml/` and
   `unittest/` gone. A clean report means nothing detectable is wrong, not that the tree is whole.
3. **`UVM_REPAIR` in the job script.** Set on a `uv` or `uvx` call, it runs doctor's check and
   repairs what it finds before the command runs. See [Repairing inside a
   job](#repairing-inside-a-job).
4. **Prefer `uvx` over `uv tool install`.** Ephemeral environments are keyed off the cache and
   rebuild cleanly; installed ones accumulate damage.
5. **Watch inodes.** Anvil scratch allows 1,000,000 files and community scratch 2,000,000. A
   populated `uv` tree is a meaningful fraction of that. Run `uv cache prune` periodically.

### Repairing inside a job

```bash
#SBATCH --nodes=2
export UVM_REPAIR=1
srun uv run --no-project analyse.py
```

With `UVM_REPAIR` set, a `uv` or `uvx` call checks the tree before it runs the command, on the node
that runs it, so it checks the tree of that node's architecture. Unset, empty and `0` mean off. Any
other value means on, `00` and `false` included. Off forks nothing and touches no file; what it
costs is bash parsing the added code, about 0.6 ms per call.

**One check per scope.** Inside a Slurm job the scope is the job: every step of an allocation shares
`SLURM_JOB_ID`, so the first call checks and every later call in every step costs one `stat`. That
holds across nodes: an `srun` over many nodes is one job, so one rank on one node repairs and
the ranks on every node wait for it, then run. An array shares what a successful check records:
it is keyed on `SLURM_ARRAY_JOB_ID`, so one task's check covers every task. A failed check is the
task's own, keyed on its `SLURM_JOB_ID`, so the next task checks again rather than inheriting a
failure that may have been transient. The shared record
outlives a purge that lands partway through an array: tasks that start after it trust the earlier
check and do not see the new damage. `SLURM_CLUSTER_NAME` qualifies the id, because two clusters
sharing a filesystem issue the same job ids. Outside a job the scope is the value itself, so give a
per-run value, such as `UVM_REPAIR="$(date +%s)-$$"`. A constant value reuses one record across
purges: the record is only ever tested, never read, so its access time is its creation time, and a
purge can take older tool files while the record survives. That reads as clean on a damaged tree.
Values are compared exactly: `run/1`, `run 1`, `run_1` and `run:1` are four scopes, and `Run1` and
`run1` are two, on a filesystem that ignores case too. A value may be 194 bytes long, each byte
outside `a-z`, `0-9`, `.` and `-` counting as three, an uppercase letter among them, because the
record's name spells those bytes out; a longer value fails the call before any check, saying so.
A Slurm array task is one with `SLURM_ARRAY_TASK_ID` set.

**What happens.** One call in the scope takes the repair lock, `$UVM_ROOT/<arch>/.repair.lock`, and
runs the check `uv-manager doctor` runs. When a managed interpreter is damaged, a binary gone or its
standard library failing to import, it reinstalls that interpreter, named by its directory under
`python/`, at the patch version it already had. When a tool environment is damaged it then
reinstalls, into that environment alone, every distribution it holds at the version its
`<name>-<version>.dist-info` directory names, with `uv pip install --reinstall --no-cache`. A purge
takes files and leaves directories, so those names survive the manifests inside them. The tool keeps
its version, pinned or not, its `--with` packages, its dependencies' versions, the interpreter it
runs on and its `uv-receipt.toml` byte for byte, and a tool that is not damaged is not touched. A
dependency whose whole dist-info directory is gone is resolved again within what the tool's own
requirements allow. The repair runs under the user's `uv.toml` and environment, so a configured
index or mirror is in effect for it. It runs from `/`, so a project's `pyproject.toml` or `uv.toml`
in the job's working directory or above it does not reach it, and the command itself still runs
where it was started. The receipt is read only to refuse a tool whose source an index
cannot stand in for, below, and is never written. A repair restores what is installed and never
applies the job's Python request: a `.python-version` in the working directory or above it, uv's
global pin and `UV_PYTHON` all leave it unchanged. Interpreters go first because every tool runs on
one, and the tool repair fails on an interpreter that cannot import its standard library. The call records the outcome under
`$UVM_ROOT/<arch>/.repair/` and releases the lock. The other calls wait on the lock, see the
outcome, and act on it. No call repairs when nothing is damaged. The uv version in use and `current`
stay as they were. All repair output goes to stderr, and the exit status is the command's own.

**A failure stops the scope.** When the repair fails, the call records the reason, and that call and
every other call in the scope exit non-zero with it and run nothing. Nobody retries within the
scope: inside a job the record ends with the job, or with the task in an array; under a value it
stands until the value changes.
`uv-manager doctor` reports each failed record under a value with its reason, and counts those under
jobs without reading them, since a read would refresh a record's access time and keep it from the
purge. `uv-manager clean outcomes --yes` removes them all. A holder that dies records nothing, so its
waiters fail at `UVM_LOCK_TIMEOUT` naming the repair lock and its owner line; `uv-manager doctor`
reports the lock, and `uv-manager clean lock --yes` removes it.

**Three tool states fail the scope by design.** Each needs a human, and then a new job or a new
value.

- A tool directory that has lost its `pyvenv.cfg` is no longer a virtualenv, and a reinstall aimed
  at it would install into the base interpreter, outside the tree, and still exit 0. The repair
  refuses before it changes anything, and the reason names the tool. Remove
  `$UVM_ROOT/<arch>/tools/<tool>` and install the tool again, naming the version you want.
- A damaged tool whose `bin/python` still does not run once the interpreters are repaired has lost
  the interpreter it was built on. The reason names the tool; remove its directory and install it
  again.
- A tool that holds a distribution from somewhere other than an index has no version the repair
  can restore by name, and a reinstall by version would replace a fork with upstream, or a local
  package with a public one of the same name. The repair refuses before anything of that tool is
  reinstalled, and the reason names the tool and what it found: a distribution whose
  `direct_url.json` records a URL, git or path source, or a `uv-receipt.toml` that records a
  requirement (the tool or a `--with` package), a constraint or an override from a directory, path,
  editable, git or URL source. Install the tool again from its source.

Two cases are conceded. An index or find-links given only on one install's command line, as
`uv tool install --index <url>`, is recorded in the receipt but not applied again: the repair uses
the index `uv.toml` and the environment configure, so a name from that other index can resolve
from this one. And a tool whose purge took both records, its receipt and the `direct_url.json` of
the distribution from another source, has a source that cannot be known, so the repair installs
the release of that version from the configured index, `pypi.org` by default. A tool with no `uv-receipt.toml` is otherwise repaired like any other, since the repair
needs nothing from it; `uv-manager doctor` still reports the missing receipt, which uv needs to count
the tool as installed.

**What it catches is what doctor catches.** A distribution removed entirely, its dist-info directory
included, leaves no evidence; it comes back only as a dependency some other distribution in the
tool requires. A managed interpreter is checked only by whether its binary is there and `import
json, os, ssl` succeeds, so damage elsewhere in its standard library goes unseen. A purge that takes
every file of an interpreter leaves its directories and links, so the shim uv points through the
minor-version link, `python/cpython-3.12-<platform>`, still leads to the install, and the install is
repaired. A shim whose whole tool or interpreter directory is gone is reported by doctor but not
repaired, since uv no longer counts that tool or interpreter as installed; remove the shim, and
install the tool or interpreter again if you still need it. Damage inside uv's cache is not checked or repaired. That
cache holds the environment of a script with inline dependencies, so `uv run <script>` can still
fail on a cache the repair never touches. A project's `.venv` lives outside the tree and is the
user's.

**Network.** The tool repair downloads every distribution of each damaged tool again, from
`pypi.org` and `files.pythonhosted.org` or the index configured in `uv.toml` or the environment.
With the cache bypassed, uv stages that download in its temporary directory under `TMPDIR`, which
needs room for the whole of the tool's environment; a `TMPDIR` that is not writable or is full
fails the scope with uv's reason. The interpreter reinstall downloads from `releases.astral.sh`, or
the mirror the user configured. Where compute nodes have no egress, the repair fails as above.

**Reach.** The check runs on every call through `uv` or `uvx`, whatever the subcommand. It does not
run when a tool is invoked by its own name, because the trampoline execs the tool directly and never
enters the wrapper; use `uvx <tool>` in the job script. `uvx <script>.py` is not a uv form: uv
refuses it and points at `uv run`, and with the knob set the wrapper would repair before uv refuses.

**Many jobs at once.** Jobs submitted separately are separate scopes, and each one checks the tree
once, holding the repair lock while it does. When many start together on one tree they check in
turn. If one check takes `w` seconds, the job in place `k` of that line waits about `(k - 1) × w`
seconds, and a job whose wait passes `UVM_LOCK_TIMEOUT` fails there, naming the repair lock, having
run and changed nothing. So about `UVM_LOCK_TIMEOUT / w + 1` jobs that start within one check of
each other get through. At the default 180 s and a check of 1.5 s that is about 120 jobs; at a
5 s timeout, three or four. A job that fails this way can be resubmitted, and checks again. An array shares
its successful check and does not queue this way once one task has made it. On NFS, a call that wins the
lock can miss an outcome another node just recorded, which costs one redundant check.

**Leave it unset on storage that is not purged.** Each scope leaves one empty file under
`.repair/`. On purged storage the purge removes them with everything else; elsewhere nothing does.
`uv-manager clean outcomes` counts them, and with `--yes` removes them; that costs each scope one
more check, never a false clean.

---

## Design notes

Rationale for the choices that may look arbitrary.

**Dispatch on `basename $0`.** Real `uv` does the same, so `uvx` needs no separate code path and
stays correct if Astral changes what `uvx` means. It also gives wrapper-specific commands a home,
`uv-manager`, without shadowing `uv`'s own namespace, which matters because `uv` keeps adding
subcommands (`auth`, `format`, `check`, `audit` and `upgrade` are all recent). Adding a name is
one symlink plus one pattern in the `case`; unrecognised names fall through to `uv` mode.

**`UVM_*` for the wrapper's own knobs.** `uv` reads dozens of `UV_*` variables and adds more with
each release, so a name inside that namespace leaves an operator no way to tell what Astral honors
from what this wrapper invented, and a future Astral name landing on one of ours would collide
silently — unrecognised `UV_*` variables are deliberately passed through untouched. The five
storage variables the wrapper exports keep their `UV_*` names: those are `uv`'s by right. The two
prefixes are the storage/resolution boundary made visible in the place an operator reads first, the
modulefile.

**`exec`, not a subprocess.** Signals, exit codes and process accounting stay as they would be
without the wrapper. An `srun uv run ...` has to forward `SIGTERM` correctly at walltime, and a
wrapper that waited on a child would have to reimplement that. The exceptions are `uv tool` and
`uv python`, which change what needs a trampoline and so must run to completion.

**Version-keyed installs with an atomic symlink swap.** Makes a pin authoritative rather than
advisory, makes switching between downloaded versions instant, and makes rollback trivial.

**`mkdir` for the locks.** Atomic on Lustre, GPFS and NFS, needs no helper binary, and does not
depend on `flock`, which `uv` itself requires but which is not enabled everywhere.

**Only the call that created the lock removes it.** Earlier designs let a waiter conclude that the
holder had died and take its lock: by an age threshold, by a holder refreshing its lock on a timer,
by a probe of a recorded pid. Each asked a question a shared filesystem cannot answer reliably.
Attribute caches serve an old owner line, clocks differ between nodes, and a pid names a number on
one host rather than a process. Each fix also added state whose own leftovers became the next
defect. A waiter past `UVM_LOCK_TIMEOUT` now does something safe instead: a provisioning call
installs for itself, and when two copies of a version are published at once, one is kept and the
other discarded; a repair call fails, since two repairs at once are not safe. A
holder killed mid-install costs each call that has to provision one timeout, and leaves a line in
`uv-manager doctor` until a human clears it with `uv-manager clean lock`.

**Repair is a knob on the call, not a subcommand.** A `uv-manager repair` step in a login-node
prologue repairs the login node's architecture while the job runs on another. A knob read inside
`uv` and `uvx` fires after the platform key is resolved on the node that runs the command, so it
repairs the right tree by construction, and it needs no step outside the job script.

**The scope is the job id.** Inside a job, a record says that a check ran in this job, and it ends
with the job, so a purge that removes it costs one more check and never a false clean. A constant
value outside a job has no such end, which is why the documentation asks for a per-run value there.

**The repair has a lock of its own.** Provisioning writes `versions/` and `current`; the repair
rewrites `tools/` and `python/`. Sharing one lock would make a repair waiter fail because of an
unrelated slow download, and let a provisioning waiter past its timeout exec mid-repair. No call
holds both: provisioning releases before the repair begins.

**Architecture-neutral trampolines.** The only way to have one `PATH` entry that is correct on both
node types. Each is a short `sh` script that re-resolves the platform key at exec time. They are
generated for the union of names across all architectures, so invoking a tool on an architecture
where it is not installed gives a useful message instead of `Exec format error`.

**Not overriding `XDG_CONFIG_HOME`.** Storage is the wrapper's business; resolution is not.

**`mkdir -p` behind a guard.** Running it unconditionally came first, defended as a handful of
metadata operations. Measured, it is a fork, an exec, and — under GNU coreutils — one `EEXIST`-failing
`mkdir(2)` per path component of every operand, to resolve six directories that already exist: roughly
a quarter of the wrapper's own overhead, and more the deeper the scratch path, paid by every rank of
every job. Six shell builtin tests replace it. A missing directory is still created, under
`umask 077`, which is what the unconditional call was really protecting.

---

## Automation: Globus Compute endpoints

The wrapper's second job is backing Purdue's Globus Compute Multi-User Endpoint on Anvil.

Globus Compute has a long-standing alignment problem: the Python minor version and the SDK/Parsl
versions have to match across four hops, from client to MEP to the single-user endpoint the MEP
spawns to the workers. When they do not, failures surface as opaque deserialization errors. Anvil's
MEP handles this by intercepting the client's reported versions and using `uv` to provision a
matching environment before the UEP starts, plus a default `worker_init` that provisions worker
environments from a site-level `requirements` parameter.

For that to work the wrapper has to survive an environment it did not choose:

- **A UEP is not spawned from a login shell**, so whatever your site sets in `/etc/profile.d` may
  not be present. Set `UVM_ROOT` explicitly in the endpoint configuration rather than relying on
  inheritance. If it is missing, the wrapper fails with the exact fix rather than falling back to
  node-local storage.
- **`worker_init` runs on compute nodes**, so egress and pre-warming assumptions apply there.
- **Pin the version.** `UVM_PIN` is authoritative: it selects which installed version
  `current` points at, so pinning to an already-downloaded version costs milliseconds. Calls
  running at once on the same architecture's tree with different pins race for `current`, and the
  last one wins; calls sharing one pin agree.
- **Provision once, then run directly.** Keep `uv run` off the hot path of a many-rank launch. It
  takes a lock on the project environment, and N ranks starting at once either serialize on it or,
  where `flock` is unreliable, race. `UVM_REPAIR` does not change that: once its scope has an
  outcome it adds one `stat` per call, and the project lock is uv's.

```bash
# worker_init
export UVM_ROOT="${SCRATCH}/.uv"
export UVM_PIN=0.12.2
export PATH="/apps/external/uv/main/bin:$PATH"

export UV_PROJECT_ENVIRONMENT="${SCRATCH}/.venvs/${SLURM_JOB_ID}-$(uname -m)"
uv sync --frozen --quiet
export PATH="${UV_PROJECT_ENVIRONMENT}/bin:$PATH"
```

---

## Troubleshooting

**Start with `uv-manager status`.** It prints every resolved path, where the root came from, and
which version is selected.

**"cannot determine where to keep per-user uv state"** means `UVM_ROOT` is unset and no candidate
resolved. The message lists each candidate and why it failed. The usual cause is a batch or
automation context that did not inherit a login shell.

**"install failed — no egress from this node?"** Pre-warm from a node of the same architecture that
has outbound HTTPS.

**"waiting for the provisioning lock"** means another process holds the lock on the same
architecture's tree, usually because it is provisioning it. The lock is the directory
`$UVM_ROOT/<arch>/.install.lock`, and the `owner` file inside it records the host and pid of the
process that took it; the notice prints that line once, at 30 seconds or at `UVM_LOCK_TIMEOUT` if
that is sooner. A waiter never removes a lock it did not create, whatever its age. At
`UVM_LOCK_TIMEOUT` it downloads and installs for itself and carries on, so until someone removes a
lock left by a holder that was killed, a provisioning call whose request is not yet satisfied waits
until it is or until the timeout passes. The holder may still be running: a recorded pid belongs to
the host recorded beside it, so probing it from the node
you are on proves nothing. Once nothing is provisioning that tree, remove the lock with the command
the notice prints, `rm -f '<lock>/owner' && rmdir '<lock>'`; `rmdir` on its own reports
`Directory not empty`. On a node of the same architecture with the same `UVM_ROOT`,
`uv-manager doctor` reports the lock with its owner line and `uv-manager clean lock --yes` removes
it; from anywhere else, use the path. Removing a lock whose holder is still running lets a second
call provision beside it, and the holder's own release then removes that call's lock, so wait until
nothing is provisioning the tree.

**"waiting for the repair lock"** means another call with `UVM_REPAIR` set is checking or
repairing the same architecture's tree for the same scope, or for another one. The lock is the
directory `$UVM_ROOT/<arch>/.repair.lock`, with the same `owner` line, notice and removal as the
provisioning lock above. The difference is the timeout: a repair waiter never proceeds without the
lock, so at `UVM_LOCK_TIMEOUT` it fails with "timed out … waiting for the repair lock", names the
owner line, and runs nothing. A holder that was killed leaves the lock and no outcome, so every
call with `UVM_REPAIR` set and no outcome for its scope fails this way until a human removes the
lock. Once nothing is repairing that
tree, `uv-manager doctor` reports the lock and `uv-manager clean lock --yes` removes it; the next
call in the scope then checks and repairs.

**"the repair for … failed"** means a call in this scope already tried the repair and recorded why
it failed, so this call runs nothing and says the same. The reason follows the colon: a repair
command that failed, often for want of egress, which uv's own output in the failing call's log
shows; a tool with no `pyvenv.cfg`; a tool whose interpreter is gone; or a distribution installed
from a URL, git or path source. Fix what it names. Inside a job, the
next job, or the array's next task, checks again. Under a value, the record stands until the value
changes: `uv-manager doctor` prints it as `repair failed for UVM_REPAIR=<value>`, and
`uvm clean outcomes --yes` removes it.

**A tool prints "is not installed for architecture 'aarch64'".** That is the trampoline working as
intended. The quoted name is the platform key, which a site may have overridden; install the tool
from a node that resolves to it.

**`ImportError` from something that used to work** is usually a partial purge. Run
`uv-manager doctor`, or, inside a job, set `UVM_REPAIR=1` on the call to repair before it runs.

**`WARN: The following commands are shadowed by other commands in your PATH: uv uvx`** during
provisioning is cosmetic. The installer notices that the module's `bin/`, which holds the wrapper,
precedes its own install directory. That is the arrangement we want.

**Disk accounting.** `du -sh $UVM_ROOT/*` gives the cost of each architecture.

---

## Reference

### Wrapper environment variables

| Variable | Effect |
| --- | --- |
| `UVM_ROOT` | Base for per-user state. Architecture-neutral; the wrapper appends `<arch>`. |
| `UVM_PIN` | `uv` version to provision and select. |
| `UVM_PLATFORM` | Override the architecture key. Default `uname -m`. |
| `UVM_INSTALL_URL` | Installer base URL, for mirrors. Default `https://astral.sh/uv`. |
| `UVM_LOCK_TIMEOUT` | Seconds to wait for a lock. Past it, provisioning installs without the lock and a repair fails. Default 180. |
| `UVM_REPAIR` | Repair what a purge removed before running the command, once per Slurm job, else once per value. Off when unset, empty or `0`; any other value is on. A value may be 194 bytes, each byte outside `a-z 0-9 . -`, an uppercase letter included, counting as three. See [Repairing inside a job](#repairing-inside-a-job). |

`UVM_LOCK_TIMEOUT` is whole seconds, read as decimal. No call removes a lock it did not create, so
there is no threshold after which a lock counts as abandoned.

### `uv` variables the wrapper sets

`UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_PYTHON_INSTALL_DIR`, `UV_PYTHON_BIN_DIR`,
all under `$UVM_ROOT/<arch>/`, plus `PATH`.

### `uv` variables the wrapper deliberately leaves alone

`XDG_CONFIG_HOME`, `UV_CONFIG_FILE`, `UV_PROJECT_ENVIRONMENT`, `UV_DEFAULT_INDEX`, `UV_INDEX`,
`UV_PYTHON_PREFERENCE`, `UV_PYTHON_DOWNLOADS`, `UV_LINK_MODE`, `UV_COMPILE_BYTECODE`, `TMPDIR`.

The first two would change dependency resolution. The rest are site or user policy; see
[`etc/uv-manager.conf.example`](etc/uv-manager.conf.example).

### Repository layout

```
bin/uv-manager                    the script
bin/{uv,uvx,uvm}                  symlinks to it; mode is chosen by basename
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
