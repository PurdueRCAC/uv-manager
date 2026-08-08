# 01 — The generated body: heredoc escaping, POSIX support, hot path

Scope: can the trampoline carry `${UVM_PLATFORM:-$(uname -m)}`, written from an unquoted bash
heredoc, and still be a portable `/bin/sh` script. Read-only; probes were run outside the working
tree.

## The escaping works, verified rather than reasoned

`uvm_trampolines` writes through `cat > "${tmp}" <<TRAMPOLINE` — an **unquoted** delimiter, so the
body undergoes parameter expansion and command substitution as bash writes it. Everything the
generated script needs at *its* runtime is escaped with a backslash. The existing line is
`a=\$(uname -m)`; the replacement is:

```
a=\${UVM_PLATFORM:-\$(uname -m)}
```

Reproducing the generator's exact heredoc form against bash 3.2.57 (the system bash, and the
portability floor) emits:

```sh
a=${UVM_PLATFORM:-$(uname -m)}
```

Both `\$` sequences survive: the first produces the literal `$` opening the parameter expansion, the
second the literal `$(` of the fallback substitution. The `:-` and the braces are ordinary literal
text to bash here and need no escaping. No `eval`, no nested quoting, no second interpolation layer.

## POSIX conformance

`${VAR:-word}` where *word* is a command substitution is POSIX shell, not a bashism. Confirmed three
ways on the generated file:

- `/bin/sh -n` — clean (macOS `/bin/sh` is bash 3.2 in POSIX mode).
- `dash -n` — clean. `dash` is the strictest POSIX shell to hand and the closest stand-in for the
  `/bin/sh` on a Debian/Ubuntu compute image.
- Executed under `dash` with `UVM_PLATFORM=zz`: resolves `zz`, prints the not-installed message.

## Runtime matrix

The candidate body was driven against a mock tree holding shims under two override keys and under the
host's native key.

| Case | `UVM_PLATFORM` | Result | Exit |
|------|----------------|--------|------|
| Override, shim present | `x86_64-glibc2.28` | execs that tree's shim | 0 |
| Different override, same tramp | `aarch64-glibc2.34` | execs that tree's shim | 0 |
| Unset | — | execs native `arm64` shim | 0 |
| Set but empty | `""` | falls back to `uname -m` | 0 |
| Override, no shim | `ppc64le` | message names `ppc64le` | 127 |
| Key containing a space | `two words` | message names `two words`, no word-split | 127 |
| Args and exit code | `x86_64-glibc2.28` | argv forwarded, `exit 42` propagated | 42 |

The empty-string case matters: `uvm_init:145` also uses `:-`, not `-`, so an exported-but-empty
`UVM_PLATFORM` falls back to `uname -m` at **both** sites. Using `-` in the trampoline would
reintroduce the divergence this cycle exists to remove, in a case nobody would think to test.

The space case works because `$a` is used only inside the already-quoted `t="$d/$a/bin/$s/$n"`.

## Hot path

No new process. When the override is set the expansion resolves without forking at all, so the
trampoline is strictly **cheaper** than today; when it is unset the `uname` fork is the same one that
runs now. Invariant §10's "everything on the hot path stays cheap" is satisfied without an argument.

## Every `uname` site in the repository

Surveyed to be sure this is the only divergence, not one instance of a pattern:

| Site | Verdict |
|------|---------|
| `bin/uv-manager:145` `uvm_init` | The reference expression. Unchanged. |
| `bin/uv-manager:476` trampoline heredoc | **The defect.** |
| `bin/uv-manager:236` `uname -n` | Lock metadata, hostname not architecture. Unrelated. |
| `bin/uv-manager:132`, `:431` comments | Prose describing resolution — see `04`. |
| `main.lua:24`, `:122` | Prose describing the trampoline — see `04`. |
| `etc/uv-manager.conf.example:82`, `:144` | Worked examples of user-set values. Correct as written. |

One code site diverges. There is no second instance.

## Bonus finding: trampolines need no provisioning

`uvm trampolines` on a state root with no `uv` installed exits 0 and generates from whatever shim
directories exist. Dispatch is `trampolines) uvm_export_env; uvm_trampolines`, and `uvm_set_paths` is
pure (invariant §8). So verification drives for this cycle do **not** need `--offline` and do not
provision anything — they plant a shim directory and run. That makes every gate fast and removes the
installer fixture from the failure surface of a gate that is not about provisioning.
