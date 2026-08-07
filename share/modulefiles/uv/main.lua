-- -*- lua -*-
--
-- Lmod modulefile for the uv-manager wrapper.
--
-- Install as, e.g.:
--     /apps/modulefiles/standard/uv/main.lua
-- pointing at a deployment at:
--     /apps/external/uv/main/bin/uv-manager   (with uv, uvx, uvm symlinked)
--
-- DESIGN NOTE — everything this modulefile exports is architecture-NEUTRAL.
--
-- A modulefile is evaluated on whatever node runs `module load`. On a
-- heterogeneous cluster that is usually an x86_64 login node, and Slurm's
-- default `--export=ALL` then copies that environment verbatim onto compute
-- nodes that may be aarch64. Any architecture-specific path exported here
-- would therefore be wrong for a large fraction of jobs, and would fail with
-- an "Exec format error" thousands of lines into a job log.
--
-- So this file exports only paths with no architecture component:
--
--   PATH               <prefix>/bin          the wrapper itself
--   UVM_ROOT           <scratch>/.uv         base of the per-user state tree
--   PATH               <scratch>/.uv/bin     trampolines that re-resolve
--                                            `uname -m` at exec time
--
-- The architecture is appended by the wrapper at exec time, on the executing
-- node. Do not inline $UV_CACHE_DIR, $UV_TOOL_BIN_DIR or any other
-- per-architecture path into this file.

local pkg_name    = "uv"
local pkg_version = myModuleVersion()

-- ---------------------------------------------------------------- site knobs

-- Deployment prefix. Contains bin/uv-manager plus the uv, uvx and uvm links.
local prefix = "/apps/external/uv/" .. pkg_version

-- Where per-user uv state lives. Edit the candidate list to match the
-- variable your site actually exports. The wrapper applies an equivalent
-- cascade of its own when UVM_ROOT is unset, so setting it here is for
-- visibility in `module show uv`, not for correctness.
local scratch = os.getenv("CLUSTER_SCRATCH")
             or os.getenv("RCAC_SCRATCH")
             or os.getenv("SCRATCH")

-- ---------------------------------------------------------------- metadata

local url  = "https://github.com/purduercac/uv-manager"
local desc = [[
uv is an extremely fast Python package and project manager, written in Rust.

This module provides a site wrapper around uv rather than uv itself. The
wrapper installs a private copy of the real uv on first use, and keeps the
binary, the download cache, tool virtual environments and uv-managed Python
interpreters on high-capacity scratch storage instead of your home
directory, partitioned by CPU architecture so that a login node and a
compute node of a different architecture never share incompatible
binaries.

Each user gets their own uv and their own environments. Nothing is shared
between users, and you may upgrade or pin your uv independently of the site.
]]

whatis("Name: " .. pkg_name)
whatis("Version: " .. pkg_version)
whatis("Category: python, package manager, development")
whatis("Keywords: python, pip, packaging, virtualenv, uv, uvx")
whatis("URL: " .. url)
whatis("Description: quota-safe, architecture-aware launcher for the uv Python package manager")

help(desc .. [[

Usage
-----
    uv --help                 the real uv, on this node's architecture
    uvx <tool>                run a tool in an ephemeral environment
    uv-manager status         show where this wrapper is putting things
    uv-manager doctor         check for a purged or damaged environment
    uv-manager help           all wrapper commands
                              ('uvm' is a short alias for 'uv-manager')

First use on a given architecture downloads uv (a few seconds, needs outbound
HTTPS). Compute nodes without egress will fail; run any uv command once on a
node of the same architecture that does have egress to pre-warm.

Storage
-------
Run `uv-manager status` to see the exact locations in use. Scratch
filesystems are periodically purged. A uv installation that goes untouched
past the purge window is reprovisioned on next use, but a tool environment
or managed interpreter that is only partly purged is not detected by uv.
Run `uv-manager doctor` if something that used to work stops importing.

More information: ]] .. url .. "\n")

-- ---------------------------------------------------------------- guards

-- Fail loudly rather than putting a nonexistent directory on PATH.
if mode() == "load" and not isDir(pathJoin(prefix, "bin")) then
    LmodError("uv/" .. pkg_version .. ": deployment not found at " .. prefix ..
              " -- this node may not mount the applications filesystem.\n")
end

-- ---------------------------------------------------------------- environment

-- RCAC convention: every module advertises its install prefix and version.
setenv("RCAC_UV_ROOT", prefix)
setenv("RCAC_UV_VERSION", pkg_version)

-- The wrapper. Architecture-neutral by construction.
prepend_path("PATH", pathJoin(prefix, "bin"))

-- Declare the state root explicitly, so it is visible in `module show uv` and
-- in the user's environment, and so it survives into contexts that never see
-- a login shell. When this is absent the wrapper falls back to its own
-- cascade and, failing that, refuses to run with an actionable message.
if scratch ~= nil then
    local root = pathJoin(scratch, ".uv")
    setenv("UVM_ROOT", root)

    -- Architecture-neutral trampolines for anything `uv tool install` or
    -- `uv python install` puts on PATH. Each one re-resolves `uname -m` when
    -- executed, so this single entry is correct on every node type.
    prepend_path("PATH", pathJoin(root, "bin"))
end

-- Pin the uv version this module provides. Strongly recommended for anything
-- automation depends on; roll it forward by cutting a new module version.
-- setenv("UVM_PIN", "0.12.2")

-- ---------------------------------------------------------------- notes
--
-- Deliberately NOT set here, and why:
--
--   UV_CACHE_DIR, UV_TOOL_DIR, UV_TOOL_BIN_DIR, UV_PYTHON_INSTALL_DIR,
--   UV_PYTHON_BIN_DIR
--       Architecture-specific. Set by the wrapper at exec time. See the
--       design note at the top of this file.
--
--   XDG_CONFIG_HOME
--       This is where a user's own ~/.config/uv/uv.toml lives (indexes,
--       credentials, mirrors) and where the standalone installer writes its
--       receipt. Redirecting it would change dependency resolution, not
--       just storage location.
--
--   family("python")  /  family("python-package-manager")
--       A family declaration would force-unload a user's conda or python
--       module on `module load uv`. uv coexists with those; it manages only
--       its own interpreters unless asked otherwise. Enable this only if
--       your site has a policy reason to serialize them.
--
--   Site defaults for uv itself (index mirrors, link-mode, python-downloads)
--       Prefer uv's own system configuration file, /etc/uv/uv.toml, which
--       MERGES with the user's config rather than replacing it. Setting
--       UV_CONFIG_FILE here would replace the user's config entirely.
--       If you cannot manage /etc on compute images, set the corresponding
--       UV_* variables from the wrapper's site config instead, so they are
--       applied on the executing node.
