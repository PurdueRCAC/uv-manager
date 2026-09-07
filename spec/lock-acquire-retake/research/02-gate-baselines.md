# Research 02 — gate baselines against the unmodified tree

Measured against `e3538d3` (`bash --version`: GNU bash 3.2.57(1)-release, `arm64-apple-darwin25`),
working tree clean, no edits made to `bin/uv-manager` or any other tracked file. Every drive ran
through `.agents/factory/bin/temp_root.sh --offline`, or a manual replica of its environment scrub
for the two drives (E, F... actually D and E) that need a lock directory pre-planted before the first
`uv` invocation — `temp_root.sh` provisions nothing until that call, so a lock has to exist before it
runs. `uvm_root` resolves to `.../root/arm64` on this machine; all paths below are sandbox-relative.

## A — R1, the robbed winner

```sh
shim=$(mktemp -d)
cat > "$shim/mkdir" <<'EOF'
#!/bin/sh
if [ $# -eq 1 ]; then case "$1" in *.install.lock)
  /bin/mkdir "$1" || exit $?
  [ -e "${UVM_SANDBOX}/fired" ] || { : > "${UVM_SANDBOX}/fired"; /bin/rmdir "$1"; }
  exit 0 ;; esac; fi
exec /bin/mkdir "$@"
EOF
chmod +x "$shim/mkdir"
.agents/factory/bin/temp_root.sh --offline sh -c "PATH=\"$shim:\$PATH\" uv --version"
```

**Measured:** rc `1`. stdout: 0 bytes. stderr:

```
/Users/geoffrey/Software/github.com/purduercac/uv-manager/bin/uv: line 462: /…/.install.lock/owner: No such file or directory
uv-manager: cannot record ownership of the provisioning lock at /…/.install.lock/owner
```

The shim fires exactly once, `mkdir "${lock}"` wins, the sentinel `rmdir` removes the directory
before the owner write, and the write opens `ENOENT` at `bin/uv-manager:462`. Reached cleanly: the
shim directory sat ahead of the working tree's own `bin/` (which `temp_root.sh` also prepends, but
after the caller's `PATH` per its `PATH="$repo/bin:$PATH"` — the caller's shim dir, placed first in
the inner `sh -c` invocation, wins). `mkdir "${lock}"` is invoked with the lock path as its sole
argument (`$# -eq 1` matched), confirming the seed's premise about the call shape still holds at this
commit.

**Verdict: RED today**, exactly as the seed predicted — rc 1, empty stdout, the raw shell diagnostic
plus `cannot record ownership`. After the fix this drive should assert rc 0 and non-empty stdout
(the fixture version).

## B — R2, the genuine fault

```sh
shim=$(mktemp -d)
cat > "$shim/mkdir" <<'EOF'
#!/bin/sh
if [ $# -eq 1 ]; then case "$1" in *.install.lock)
  /bin/mkdir "$1" || exit $?
  [ -e "${UVM_SANDBOX}/fired" ] || { : > "${UVM_SANDBOX}/fired"; /bin/chmod 500 "$1"; }
  exit 0 ;; esac; fi
exec /bin/mkdir "$@"
EOF
chmod +x "$shim/mkdir"
.agents/factory/bin/temp_root.sh --offline sh -c \
  "UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 PATH=\"$shim:\$PATH\" uv --version"
```

**Measured:** rc `1`, elapsed 0s (wall-clock, second resolution). stdout: 0 bytes. stderr:

```
/…/bin/uv: line 462: /…/.install.lock/owner: Permission denied
uv-manager: cannot record ownership of the provisioning lock at /…/.install.lock/owner
```

The wrapper dies promptly — it does not fall into the wait loop and does not consume any of the 5s
`UVM_LOCK_TIMEOUT`. `EACCES` reaches stderr verbatim as "Permission denied", distinguishable from A's
"No such file or directory" by errno text alone; this is the discriminator any fix has to preserve.

**Verdict: GREEN today**, and must stay green — this is the criterion a naive fix (retry on any
non-zero write status) would break by turning an EACCES into a silent retry loop.

## C — R3, repeated robbery

```sh
shim=$(mktemp -d)
cat > "$shim/mkdir" <<'EOF'
#!/bin/sh
if [ $# -eq 1 ]; then case "$1" in *.install.lock)
  /bin/mkdir "$1" || exit $?
  /bin/rmdir "$1"
  exit 0 ;; esac; fi
exec /bin/mkdir "$@"
EOF
chmod +x "$shim/mkdir"
.agents/factory/bin/temp_root.sh --offline sh -c \
  "UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 PATH=\"$shim:\$PATH\" uv --version"
```

**Measured:** rc `1`, elapsed 0s. stdout: 0 bytes. stderr identical in shape to A (`No such file or
directory` / `cannot record ownership`).

**This is the important negative result for R3.** Under the current, unmodified code there is no
observable difference between "robbed once" (drive A) and "robbed on every call" (drive C): the
`while ! mkdir` loop only re-enters on a failed `mkdir`. Here `mkdir` *succeeds* on its only call —
the shim always returns 0 after removing the directory — so the loop body is never re-entered at
all; the owner write is attempted exactly once and dies exactly as in A. There is currently no retry
around the owner write for the robbery-every-time construction to exercise repeatedly, because there
is no retry around the owner write, period. The "repeated robbery" and "single robbery" gates are
indistinguishable today by construction, not by coincidence — they will only diverge once the fix
adds the bounded retake loop that R3 is meant to bound. Timing this drive against `UVM_LOCK_TIMEOUT`
is consequently not meaningful yet: it dies in the same iteration it would die in for A, well under
any timeout.

**Verdict: RED today** (same failure as A), **but the drive does not yet exercise "repeated" as
distinct from "once"** — that distinction only exists after the fix introduces something to repeat.
Whoever builds the post-fix gate for R3 should confirm the shim still removes the directory on every
attempt of the *new* retake loop, not just verify it dies before ever looping.

## D — R4a, fresh foreign lock times out

Pre-planted by hand (equivalent to `temp_root.sh`'s scrub-and-export, replicated manually because the
lock must exist before the first `uv` invocation, and `temp_root.sh` provisions nothing before
that):

```sh
mkdir -p "$UVM_ROOT/arm64/.install.lock"
printf 'host=foreign-node pid=99999 nonce=123456789\n' > "$UVM_ROOT/arm64/.install.lock/owner"
UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 uv --version
```

**Measured:** rc `1`, elapsed ~6s wall-clock (`date +%s` resolution; the loop's `waited` counter
increments before the bound check and each iteration sleeps 1s, so 5 sleeps land the boundary at ~6s
measured, consistent with "about 5s"). stderr:

```
uv-manager: timed out after 5s waiting for provisioning lock: /…/.install.lock
    holder, from the lock's owner file: host=foreign-node pid=99999 nonce=123456789
    A pid recorded there is on that host, not this one. If it is gone, remove the lock:
        rm -f '/…/.install.lock/owner' && rmdir '/…/.install.lock'
```

The foreign host token means the liveness probe (`pid` extraction gated on `holder%% * == host=…`)
never fires, so this exercises the age-only path. The owner file's real mtime (just created) keeps
age well under `UVM_LOCK_STALE=60`, so no break is attempted — this is a pure `waited` accounting
drive.

**Verdict: GREEN today** against the R4 want (unchanged `waited` behavior). This is a collateral
gate, not a red-today gate: R4 does not ask this to change, it asks the fix not to touch it.

## E — R4b, a denied break emits exactly one break note

Construction: lock directory with a foreign-host `owner` file backdated past `UVM_LOCK_STALE`, with
the *grandparent* directory (`uvm_root`, i.e. `.../root/arm64`) made non-writable so the final
`rmdir` of `.install.lock` is denied. `.install.lock` itself stays writable, so `rm -f
"${lock}/owner"` succeeds — only the directory removal is blocked, which is enough to set
`broke=denied` without ever fully clearing the lock:

```sh
mkdir -p "$UVM_ROOT/arm64/.install.lock"
printf 'host=foreign-node pid=88888 nonce=987654321\n' > "$UVM_ROOT/arm64/.install.lock/owner"
touch -t "$(date -v-120S +%Y%m%d%H%M.%S)" "$UVM_ROOT/arm64/.install.lock/owner"
chmod 555 "$UVM_ROOT/arm64"
UVM_LOCK_TIMEOUT=8 UVM_LOCK_STALE=60 uv --version
chmod 755 "$UVM_ROOT/arm64"   # restore before cleanup
```

**Measured:** rc `1`, elapsed 9s. stderr:

```
uv-manager: breaking stale provisioning lock (120s old): /…/.install.lock
    its owner file recorded: host=foreign-node pid=88888 nonce=987654321
uv-manager: timed out after 8s waiting for provisioning lock: /…/.install.lock
    holder, from the lock's owner file: <none recorded>
    …
```

`grep -c "breaking stale provisioning lock"` on stderr: **1**. Confirmed exactly once across the
whole 8s wait, as R4b wants. Note on mechanism, since the final timeout message shows `<none
recorded>` rather than repeating the foreign holder line: the `rm -f "${lock}/owner"` half of the
break succeeds on the first iteration (only `rmdir` is denied, by the grandparent's permissions), so
by the second iteration `holder` reads back empty from the now-missing `owner` file, and the
directory's own mtime (fresh — file removal just touched it) is far short of `lock_stale`, so `reason`
never becomes non-empty again. The "exactly one" result here is real but constructed through a subtly
different path than "rmdir denied, owner file untouched" — a construction where *both* `rm -f` and
`rmdir` are denied (e.g. `.install.lock` itself non-writable, or an immutable `owner` file) was not
attempted; it would be a stronger version of this drive and is worth trying when the post-fix gate is
built, to confirm the "announced once" guard (`[[ -n "${broke}" ]] ||`) is what is actually being
exercised rather than the age-resets-after-removal side effect.

**Verdict: GREEN today**, with the caveat above about which sub-path was measured.

## F — R4c, the absent-lock retry's literal bound of three

```sh
shim=$(mktemp -d)
cat > "$shim/mkdir" <<'EOF'
#!/bin/sh
if [ $# -eq 1 ]; then case "$1" in *.install.lock)
  n=0; [ -e "${UVM_SANDBOX}/mkdir_calls" ] && n=$(cat "${UVM_SANDBOX}/mkdir_calls")
  echo $((n+1)) > "${UVM_SANDBOX}/mkdir_calls"
  exit 1 ;; esac; fi
exec /bin/mkdir "$@"
EOF
chmod +x "$shim/mkdir"
.agents/factory/bin/temp_root.sh --offline --keep sh -c \
  "UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 PATH=\"$shim:\$PATH\" uv --version"
```

**Measured:** rc `1`, elapsed 0.37s (no `sleep` reached — `absent < 3` takes the `continue` branch,
which skips the loop's trailing `sleep 1`). stderr:

```
uv-manager: cannot create provisioning lock at /…/.install.lock — check permissions and quota on /…/root
```

`$UVM_SANDBOX/mkdir_calls` (the shim's own call counter) reads **3** after the run. Confirms the
`absent` counter's literal bound fires the `die` on exactly the third failed `mkdir` where the
directory is also absent afterward, with no wall-clock cost (this path never sleeps).

**Verdict: GREEN today.**

## G — R6, the ordinary offline path is unaffected

```sh
.agents/factory/bin/temp_root.sh --offline --keep sh -c \
  'uv --version; find "$UVM_ROOT" -maxdepth 4; find "$UVM_ROOT" -name ".install.lock"'
git grep -n flock bin/uv-manager
```

**Measured:** rc `0`. stdout: `uv 9.9.9 (fixture)`, nothing else. `find … -name .install.lock`
returned nothing — no lock left behind. `readlink "$UVM_ROOT/arm64/current"` → `versions/9.9.9`, a
relative target as required. `git grep -n flock bin/uv-manager` matches exactly one line:

```
bin/uv-manager:172:# not depend on flock — which uv itself requires but which is not enabled on
```

— the rationale comment for choosing `mkdir` as the locking discipline, and nothing else in the
file mentions `flock`.

**Verdict: GREEN today.** This is the "did we break the common case" gate; it has no red state to
speak of, only a baseline to not regress.

## Gate reliability notes

- **A, B, C are fast and deterministic** — no `sleep`, no timing sensitivity, rc and stderr text are
  stable across repeated runs. These are the cheapest, most trustworthy gates in the set.
- **D and E cannot be driven through `temp_root.sh` directly**, because `temp_root.sh` provisions
  nothing until the first `uv` call and there is no hook to plant a lock directory in between. Both
  were built by replicating `temp_root.sh`'s environment scrub and export sequence by hand (same
  variable scrub, same `UVM_ROOT`/`XDG_CONFIG_HOME` layout, same offline fixture wiring) and then
  pre-creating the lock before invoking `uv`. This is mechanically faithful to what `temp_root.sh`
  does but is a second, hand-maintained copy of that logic — a real regression gate for these two
  should either add a `temp_root.sh` option to plant a lock before the first call, or accept
  duplicating the scrub inline, and should say which.
- **D and E are the only drives with wall-clock cost** (~6s and ~9s respectively, driven by
  `UVM_LOCK_TIMEOUT`/`UVM_LOCK_STALE` chosen small for this report). `date +%s`-resolution timing
  means "about 5s" reads as 6s here; a gate asserting elapsed time should allow a window (say 4-7s
  for a 5s timeout) rather than an exact value, since the loop's own `sleep 1` granularity plus
  process startup cost already accounts for a full second of slop.
- **E's "exactly one break note" was confirmed, but through a sub-path narrower than the general
  case** — see the caveat in section E. The construction denies only `rmdir`, not `rm -f` of the
  owner file, because making `.install.lock` itself non-writable would also block the wrapper's own
  `mkdir "${lock}"` re-entry attempts in a way that stops testing the intended state. A future gate
  wanting to test "both halves of the break denied" needs a different mechanism (e.g. an immutable
  owner file via `chflags uchg` on macOS / `chattr +i` on Linux, neither portable) and was not
  attempted here.
- **C could not be made to exercise "repeated" as distinct from "once"** against the current tree —
  recorded in section C as the single most useful negative finding in this set. It is not a flaw in
  the drive; it is the expected shape of "no retry loop exists yet," and confirms the fix genuinely
  has something to add rather than the gate being redundant with A.
- **No drive was flaky across repeated runs** (each was run at least twice during construction; A/B/C/F
  reproduced byte-identical stderr, D/E reproduced within the timing slop noted above).
- **The chmod-based drives (B, E) require `del`/cleanup discipline**: a directory left at `555` or a
  file at `500` will make later cleanup attempts fail unless permissions are restored first, which
  each drive above does explicitly before the sandbox is removed. `--keep` was used for F and G to
  inspect state after exit; both were deleted with `del` afterward, not `rm`.
