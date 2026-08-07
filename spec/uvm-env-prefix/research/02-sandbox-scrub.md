# R6 — the sandbox scrub

Research for `uvm-env-prefix`. All claims below were driven, not read.

## 1. Ordering in `temp_root.sh`

The scrub sits at lines 69–72, and **every export the sandbox depends on happens after it**:

| Line | Action |
|------|--------|
| 59 | `mktemp -d` the sandbox |
| **69–71** | **scrub loop** — `s/^\(UV_[A-Za-z0-9_]*\)=.*/\1/p`, then `unset` |
| 72 | `unset CLUSTER_SCRATCH RCAC_SCRATCH SCRATCH PSCRATCH WORK PROJECT` |
| 77–81 | set + export `XDG_CONFIG_HOME`, `UV_MANAGER_ROOT`, **`UVM_SANDBOX`** |
| 86–89 | `--offline`: set + export **`UVM_FIXTURE_DIR`**, `UV_MANAGER_INSTALL_URL` |
| 92 | `--arch`: set + export `UV_MANAGER_PLATFORM` |
| 95 | prepend `$repo/bin` to `PATH` |
| 101 | run the command |

**A blanket `UVM_*` scrub placed where the current loop sits breaks nothing that `temp_root.sh` itself
sets.** `UVM_SANDBOX` and `UVM_FIXTURE_DIR` are assigned ten and seventeen lines later. The same is
true of the three post-rename knobs (`UVM_ROOT`, `UVM_INSTALL_URL`, `UVM_PLATFORM`) — all set after.

The only thing a blanket scrub can cost is a `UVM_FIXTURE_*` passed in **from outside** by a caller.

## 2. How the fixture knobs reach the stub

`.agents/factory/fixtures/uv-install/install.sh` uses an **unquoted** `<<STUB` heredoc, so expansion
splits two ways:

- `UVM_FIXTURE_VERSION` — read at **install.sh run time** (line 36, `version="${UVM_FIXTURE_VERSION:-9.9.9}"`),
  and `$version` is interpolated into the stub as a literal. Needs to be in the environment when the
  wrapper's `uvm_install` executes the fetched installer.
- `UVM_FIXTURE_BROKEN`, `UVM_FIXTURE_EXIT` — written escaped (`\${UVM_FIXTURE_EXIT:-0}`), so they land
  in the stub **verbatim** and are evaluated at **stub run time**, i.e. every later `uv`/`uvx` call.

That distinction changes *when* a knob is consulted, but **not** whether the scrub can strip it: the
scrub runs once, before the command, so it removes a variable for the whole drive — install time and
stub time alike.

What actually matters is a different property, and it is decisive: **provisioning is lazy.** Nothing
is installed until the first `uv`/`uvx` call *inside* the sandbox. So all three knobs can be set on
the inner command, after the scrub. Driven and confirmed:

```
$ temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'
uv 6.6.6 (fixture)
$ temp_root.sh --offline sh -c 'uv --version >/dev/null; UVM_FIXTURE_EXIT=7 uv --version; echo rc=$?'
uv 9.9.9 (fixture)
rc=7
$ temp_root.sh --offline sh -c 'uv --version >/dev/null; UVM_FIXTURE_BROKEN=1 uv --version; echo rc=$?'
rc=126
```

**The fixture knobs never need to cross the scrub boundary.** The tension the GOAL flags is real but
costless.

## 3. Who passes a `UVM_FIXTURE_*` today

`git grep UVM_FIXTURE` returns eleven hits: five in `temp_root.sh`/`install.sh` (definitions and the
header comment), and six in prose — `issues/uvm-env-prefix.md:79`, `GOAL.md:62,87–88`. **No drive
anywhere in the repo passes a `UVM_FIXTURE_*` from outside.** Not the TECH template's `verify:`
example, not `set_phase.py`'s sample, not `REVIEW.md`, not `uvm-release/SKILL.md`'s release drives,
not `AGENTS.md`. The allowlist in design (c) would be protecting a caller that does not exist.

## 4. The gap, proven today (pre-rename)

Setting a pin in each namespace and reading `uvm status`:

| Drive | `pin:` line |
|-------|-------------|
| `UV_MANAGER_PIN=1.2.3 temp_root.sh uvm status` | `<none — tracks latest>` |
| `UVM_PIN=1.2.3 temp_root.sh uvm status` | `<none — tracks latest>` |

Both read `<none>`, but for different reasons — the second only because today's wrapper reads
`UV_MANAGER_PIN`, not `UVM_PIN`. So `status` alone does not yet distinguish. Inspecting the drive's
environment directly does:

```
$ UVM_PIN=1.2.3 UVM_INSTALL_URL=file:///nope UV_MANAGER_PIN=9.9.9 UV_CACHE_DIR=/real/cache \
  SCRATCH=/real/scratch  temp_root.sh sh -c 'env | grep -E "^(UVM?_|SCRATCH)" | sort'
UV_MANAGER_ROOT=…/root
UVM_INSTALL_URL=file:///nope        ← leaked
UVM_PIN=1.2.3                       ← leaked
UVM_SANDBOX=…
```

`UV_MANAGER_PIN`, `UV_CACHE_DIR` and `SCRATCH` are gone — the `UV_*` scrub works. `UVM_PIN` and
`UVM_INSTALL_URL` survive. **After R1 lands, that leak becomes a pin and a mirror URL silently
honored by every drive.** The gap is real and the isolation loss is total for the six knobs.

## 5. Design

**Recommended: (a), widened pattern — but as `UVM\{0,1\}_`, not `UVM\?_`.**

```sh
for name in $(env | sed -n 's/^\(UVM\{0,1\}_[A-Za-z0-9_]*\)=.*/\1/p'); do
```

**Portability finding that decides the spelling.** `\?` is a GNU BRE extension. BSD sed on macOS
matches nothing with it — the repo's stated bash-3.2/macOS floor is a real development platform here:

```
$ printf 'UVM_PIN=1\nUV_CACHE_DIR=2\n' | sed -n 's/^\(UVM\?_[A-Za-z0-9_]*\)=.*/\1/p'
              (empty — silently scrubs nothing, the worst possible failure for an isolation guard)
$ printf 'UVM_PIN=1\nUV_CACHE_DIR=2\n' | sed -n 's/^\(UVM\{0,1\}_[A-Za-z0-9_]*\)=.*/\1/p'
UVM_PIN
UV_CACHE_DIR
```

`\{0,1\}` is POSIX BRE and works on both. A `UVM\?_` patch would lint clean, drive green, and protect
nothing on the maintainer's own laptop.

Rejected:

- **(b) explicit `unset` of the six names.** The `UV_*` loop must stay regardless — `uv` reads dozens
  of `UV_*` and the wrapper exports five of them. So (b) is the loop *plus* six hardcoded names: more
  surface, and a seventh knob added later silently escapes the sandbox. Against the delete-not-add bias.
- **(c) blanket `UVM_*` + `UVM_FIXTURE_*` allowlist.** Protects a caller that does not exist (§3), and
  §2 shows the knobs work from inside the drive anyway. An allowlist is a standing exception a reader
  has to hold in their head.
- **(d) rename the fixture variables to a third namespace.** Churns a file the GOAL explicitly puts
  out of scope, invents a third prefix in a cycle whose whole point is collapsing to one, and solves a
  problem §2 shows is not there.

Isolation: (a) is strictly stronger than today and subsumes it. Readability: one character class,
comment unchanged in shape. Existing drives: none broken (§3, and §6 below). Portability: POSIX BRE,
`sh -n` and `shellcheck --shell=sh` clean.

**Also required in the same edit** — the comment at lines 66–68 says "every `UV_*` variable", the
header at lines 5/17/21/30 quotes `UV_MANAGER_*`, and `AGENTS.md:73` and `AGENTS.md:203` both say
"every `UV_*`". R7 covers the names; the *scope* wording ("every `UV_*` and `UVM_*` variable") is R6's.

## 6. Exact replacement block

```sh
# Scrub every UV_* and UVM_* variable and every scratch candidate uvm_resolve_root
# consults. Without this, a developer with UV_CACHE_DIR, UVM_PIN or $SCRATCH exported
# gets a drive that silently reads real storage or honors a pin, and a green verify
# that proves nothing. UVM\{0,1\}_ rather than UVM\?_: \? is a GNU extension and BSD
# sed matches nothing with it, which would scrub nothing on macOS and say so silently.
# The sandbox's own UVM_SANDBOX and UVM_FIXTURE_DIR are set below, after this runs;
# a drive that needs a fixture knob sets it on the inner command, since nothing is
# provisioned until the first uv call inside the sandbox.
for name in $(env | sed -n 's/^\(UVM\{0,1\}_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$name"
done
unset CLUSTER_SCRATCH RCAC_SCRATCH SCRATCH PSCRATCH WORK PROJECT 2>/dev/null || true
```

## 7. Proof drive (post-condition, not exit 0)

Post-rename, the GOAL's own observable becomes decisive because the wrapper reads `UVM_PIN`:

```sh
UVM_PIN=1.2.3 .agents/factory/bin/temp_root.sh uvm status \
  | grep -q 'pin: *<none' && echo PASS || echo FAIL
```

Confirms the leak is closed *and* R1 is wired. Pair it with a drive that shows isolation did not
overshoot — the offline path must still provision, and a fixture knob set inside must still land:

```sh
.agents/factory/bin/temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version' \
  | grep -qx 'uv 6.6.6 (fixture)' && echo PASS || echo FAIL
```

Both were run against a patched copy of `temp_root.sh` (isolated tree, working-tree file untouched)
and both pass; `--offline --arch aarch64-test uvm status` still reports the overridden arch root, and
`UVM_FIXTURE_VERSION=6.6.6` from *outside* is correctly ignored (drive reports the 9.9.9 default).
