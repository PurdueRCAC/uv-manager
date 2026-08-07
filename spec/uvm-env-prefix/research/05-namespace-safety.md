# Namespace safety: is `UVM_*` a defensible prefix?

Research date 2026-08-07. Sources verified against `uv` source at `main` (fetched
`crates/uv-static/src/env_vars.rs`, 68495 bytes) and the live installer (`https://astral.sh/uv/install.sh`,
71225 bytes), not only against documentation. Claims below are marked **verified** (I read the artifact) or
**inferred** (secondary sources only).

## 1. The size and shape of `UV_*`

**Verified.** `uv` declares **150 public `UV_*` environment variables**, plus 17 internal/test/documentation
placeholders (`UV_INTERNAL__*`, `UV_TEST_*`, the `UV_INDEX_MY_INDEX_*` doc examples) for 167 distinct names in
the source. The count independently matches the 150 listed at
<https://docs.astral.sh/uv/reference/environment/>.

Multi-word `UV_<NOUN>_<NOUN>[_<NOUN>]` naming is not merely precedented, it is the dominant form: **68 of the
150** have three or more segments. Real examples, verbatim from `env_vars.rs`: `UV_INSTALLER_GITHUB_BASE_URL`,
`UV_PYTHON_DOWNLOADS_JSON_URL`, `UV_COMPILE_BYTECODE_TIMEOUT`, `UV_INSECURE_NO_ZIP_VALIDATION`,
`UV_CONCURRENT_CACHE_READS`, `UV_UPLOAD_HTTP_TIMEOUT`. Nothing about the shape `UV_MANAGER_ROOT` marks it as
foreign to Astral's own conventions — which is exactly the problem.

**No current `UV_*` name is `UV_MANAGER_*`.** But two findings sharpen the premise beyond "a hypothetical
future collision":

- **`UV_MANAGED_PYTHON`** (added in uv 0.6.8) and **`UV_NO_MANAGED_PYTHON`** exist. `UV_MANAGED_*` vs
  `UV_MANAGER_*` differ by one character in the sixth segment position. Two prefixes that close, one Astral's
  and one ours, in the same namespace, is a reader trap.
- **`UV_LOCK_TIMEOUT`** exists, added in **uv 0.9.4**, documented as *"The time in seconds uv waits for a file
  lock to become available. Defaults to 300s (5 min)."* The wrapper has `UV_MANAGER_LOCK_TIMEOUT` for its own
  `mkdir` provisioning lock. Two lock timeouts, same namespace, different owners, different locks, different
  defaults (300 vs the wrapper's 180). **This collision is not hypothetical — it has already happened.** Astral
  shipped a name that semantically overlaps a wrapper name after the wrapper chose it.

Rate of change: names are still being added continuously through the current series
(`attr_added_in` annotations run to `0.9.26`, with additions in every minor series from 0.0 to 0.12). The
premise that Astral could one day ship a colliding `UV_MANAGER_*` name is **well-founded, and understated** —
the adjacent-namespace collision has already occurred once with `UV_LOCK_TIMEOUT`.

## 2. Does `uv` read anything `UVM_*`?

**Verified: no.** `grep -c 'UVM_' env_vars.rs` returns **0**. Not one `UVM_`-prefixed string exists anywhere in
`uv`'s environment-variable registry, and the docs page shows none. There is also no `UV_*` variable whose
semantics a `UVM_` prefix could be confused with — `UVM_` is not a truncation, abbreviation, or plausible
misreading of any of the 150.

## 3. The standalone installer

**Verified** by reading the fetched `install.sh`. The wrapper-relevant variables are all `UV_*` or `CARGO_*`;
**none is `UVM_`-prefixed**, and `grep -c 'UVM_' install.sh` returns **0**. The rename cannot affect installer
behavior.

The precedence order the wrapper depends on is confirmed at `install.sh:1236-1245`:

```sh
if [ -n "${UV_INSTALL_DIR:-}" ]; then
    _force_install_dir="$UV_INSTALL_DIR"
elif [ -n "${CARGO_DIST_FORCE_INSTALL_DIR:-}" ]; then
    _force_install_dir="$CARGO_DIST_FORCE_INSTALL_DIR"
elif [ -n "$UNMANAGED_INSTALL" ]; then          # UNMANAGED_INSTALL="${UV_UNMANAGED_INSTALL:-}" at line 61
    _force_install_dir="$UNMANAGED_INSTALL"
fi
```

`UV_INSTALL_DIR` and `CARGO_DIST_FORCE_INSTALL_DIR` are checked **before** `UV_UNMANAGED_INSTALL` and win. The
invariant in `AGENTS.md` and the scrubbing at `bin/uv-manager:336` are correct as written and unaffected by
the rename.

## 4. SystemVerilog UVM: real risk or non-issue?

The question is whether UVM uses `UVM_*` **environment variables** or `+UVM_*` **plusargs**. The distinction
is decisive, and the answer is mostly the latter.

- **`UVM_HOME` is a genuine environment variable** — the one real instance. It points at the simulator's UVM
  library, e.g. `export UVM_HOME=/tools/Metrics/dsim/.../uvm-1.2`. Confirmed by OpenHW Group's `core-v-verif`
  makefile documentation ("Point your shell environment variable `UVM_HOME` to your simulator's UVM library")
  and by ChipVerify's installation guide.
- **`UVM_VERBOSITY`, `UVM_MAX_QUIT_COUNT`, `UVM_TESTNAME` are simulator plusargs, not environment variables** —
  they are passed as `+UVM_VERBOSITY=UVM_DEBUG` on the simulator command line. `core-v-verif` documents them
  explicitly as run-time plusargs, distinct from the shell variables it lists (`CV_SIMULATOR`, `CV_CORE`,
  `IMPERAS_HOME`, …). They never enter the process environment as `UVM_*`.
- **`uvm_root` is a SystemVerilog class**, the top-level UVM component, not an environment variable. A search
  for `UVM_ROOT` as a shell variable returns only the class.
- **Inferred, lower confidence:** secondary sources mention site-local conventions `UVM_LIB_DIR`, `UVM_INCLUDE`,
  `UVMC_HOME`, `UVM_LIB` in UVM-Connect flows. These are per-site Makefile conventions, not standardized by
  Accellera, and I could not confirm them in a primary source.

**Verdict: effectively a non-issue.** The proposed six names — `UVM_ROOT`, `UVM_PIN`, `UVM_PLATFORM`,
`UVM_INSTALL_URL`, `UVM_LOCK_TIMEOUT`, `UVM_LOCK_STALE` — intersect **nothing** in the EDA namespace.
`UVM_HOME` is the only real EDA environment variable and is not among them, nor would the wrapper ever want
that name. The residual concern is aesthetic (an EDA user on a shared cluster seeing `UVM_ROOT` may briefly
mis-file it) rather than functional. Worth one sentence in `README.md`; not worth changing the prefix.

**NVIDIA UVM is not a collision either.** `nvidia-uvm.ko` exposes `UVM_*` symbols as C constants
(`UVM_CHUNK_SIZE_MAX`) inside the kernel module; the driver's tunables use the `NVreg_*` prefix. No
environment variables. Verified insofar as no `UVM_*` env var appears in NVIDIA's documentation.

## 5. `uvm` as a command name

**Verified: no Debian package ships a `bin/uvm`.** An exact-filename contents search of Debian stable across
all architectures and sections returns no results. Nothing in the base distributions claims the name.

Two out-of-distribution tools do:

- **Unity Version Manager (Python)**, PyPI `uvm` 1.0.2, last released 2021-04-28. **I confirmed from the wheel
  metadata that it declares `[console_scripts] uvm=uvm.main:app`** — installing it produces an executable
  literally named `uvm`.
- **Unity Version Manager (Rust)**, `Larusso/unity-version-manager`, distributed via `brew tap wooga/tools`.
  Not packaged for Linux distributions.

**One concrete, wrapper-specific consequence worth putting in the plan's risk section.** `uvm_set_paths`
prepends `UV_TOOL_BIN_DIR` **last**, so it sits **first** on `PATH`, ahead of the module's `bin/`
(`bin/uv-manager:414-417`). A user who runs `uv tool install uvm` gets the Unity Version Manager's `uvm`
executable in `UV_TOOL_BIN_DIR`, plus a generated trampoline of the same name in the neutral bin dir — both
ahead of the module directory. From that point the user's `uvm` is Unity's, and the wrapper's manager mode is
shadowed. The `uvm_tramp_marker` guard does not help: it protects unmarked files *inside* the trampoline
directory, not the module's `bin/` from being shadowed by an earlier `PATH` entry.

This risk **exists today** — the repo already ships the `uvm` alias, and the rename neither creates nor worsens
it. Likelihood is low (a dormant 2021 Unity tool on an HPC cluster), and the failure is loud and
self-inflicted rather than silent. Informational, not blocking.

## 6. Verdict

`UVM_*` is a safe and defensible namespace. It is **empty in `uv`** (zero `UVM_` strings across 167 registered
variables and the installer), empty in the installer's `CARGO_*` surface, and does not intersect the EDA
world's one real environment variable, `UVM_HOME`. The stated motivation is **well-founded and, if anything,
understated**: the argument is usually framed as a hypothetical future collision, but Astral has already
shipped `UV_LOCK_TIMEOUT` alongside the wrapper's `UV_MANAGER_LOCK_TIMEOUT` — two file-lock timeouts with
different owners and different defaults in one namespace — and `UV_MANAGED_PYTHON` sits one character from the
`UV_MANAGER_` prefix. With 150 names, 68 of them three-plus segments, and additions in every minor series
through 0.12, the namespace is actively growing into the wrapper's chosen territory. The strongest argument for
the rename is not the hypothetical: it is that the collision already happened once and nobody noticed. The one
item for the risk section is the `uv tool install uvm` PATH-shadowing path in §5, which is pre-existing and
informational.

## Sources

- `uv` env-var registry (fetched and read): <https://raw.githubusercontent.com/astral-sh/uv/main/crates/uv-static/src/env_vars.rs>
- `uv` env-var reference: <https://docs.astral.sh/uv/reference/environment/>
- `uv` standalone installer (fetched and read): <https://astral.sh/uv/install.sh>
- OpenHW `core-v-verif` makefile env vars: <https://github.com/openhwgroup/core-v-verif/blob/master/mk/README.md>
- UVM installation / `UVM_HOME`: <https://chipverify.com/uvm/uvm-installation>
- `uvm_root` is a class: <https://verificationacademy.com/verification-methodology-reference/uvm/docs_1.2/html/files/base/uvm_root-svh.html>
- Debian contents search for `bin/uvm`: <https://packages.debian.org/search?searchon=contents&keywords=bin%2Fuvm&mode=exactfilename&suite=stable&arch=any>
- PyPI `uvm` (Unity Version Manager): <https://pypi.org/project/uvm/> and <https://github.com/educup/uvm>
- Unity Version Manager (Rust): <https://github.com/Larusso/unity-version-manager>
- NVIDIA `nvidia-uvm.ko`: <https://deepwiki.com/NVIDIA/open-gpu-kernel-modules/3.4-nvidia-uvm.ko-unified-virtual-memory>
