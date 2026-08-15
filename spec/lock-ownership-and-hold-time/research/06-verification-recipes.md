# 06 — How each acceptance criterion is driven in the sandbox (R1–R6)

Every recipe below was run against the working tree at `653b770` (unmodified) on macOS 25.5, bash
3.2.57, APFS, `uname -m` = `arm64`. Output quoted here is real. Nothing tracked was edited.

## 0. The `temp_root.sh` interface, as it actually is

`temp_root.sh [--offline] [--arch KEY] [--keep] COMMAND [ARG...]` runs `"$@"` directly — any command,
including `sh -c '…'` and **`sh -s` with a heredoc on stdin** (stdin is not redirected; verified). The
heredoc form is the one to use: it removes the quote-escaping that makes the
`doctor-detection-gaps` `verify:` blocks unreadable.

The sandbox is `mktemp -d`'d per invocation and removed on exit, so **two invocations never share a
tree** — a holder and a waiter must both be started from inside one invocation. `--keep` leaves the
sandbox and prints its path on stderr, but a follow-up command then runs unscrubbed; it is for
inspection, not for gates. Assertions belong inside the same drive.

Available inside: `UVM_ROOT` (the **base**; the wrapper appends `<arch>`, so the lock is
`$UVM_ROOT/$(uname -m)/.install.lock`), `UVM_SANDBOX` (scratch for captured output), and with
`--offline` `UVM_FIXTURE_DIR` + `UVM_INSTALL_URL`.

**The fixture is copied into the sandbox** (`temp_root.sh:95`), so a drive may append to
`$UVM_FIXTURE_DIR/install.sh` freely — that is the lever for every timing-dependent recipe, and it
dirties nothing tracked. The installer runs *while the wrapper holds the lock*, and exported variables
survive the `env -u … sh` at `bin/uv-manager:337`, so the installer can be handed the lock path.

```sh
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"
uv --version                       # provisions: this is how a drive reaches the acquire path
test "$(readlink "$A/current")" = versions/9.9.9
DRIVE
```

## R1 — release must not remove another process's lock

The wrapper exposes no "acquire" subcommand; the only acquire path is provisioning, reached by
`uv --version` on a cold tree. The owner file is stolen from inside the installer, which runs under the
lock — no timing race, no helper needed.

```sh
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; export UVM_TEST_LOCK="$L"
printf '%s\n' 'printf "host=elsewhere pid=999999 time=1\n" > "$UVM_TEST_LOCK/owner"' \
    >> "$UVM_FIXTURE_DIR/install.sh"
uv --version >/dev/null
[ -d "$L" ] || { echo "FAIL: a process that does not hold the lock removed it" >&2; exit 1; }
[ -f "$L/owner" ] || { echo "FAIL: foreign owner file removed" >&2; exit 1; }
grep -q 'pid=999999' "$L/owner" || { echo "FAIL: foreign owner overwritten" >&2; exit 1; }
DRIVE
# matching-owner half: an ordinary drive must still leave no lock behind
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
uv --version >/dev/null
L="$UVM_ROOT/$(uname -m)/.install.lock"
[ -d "$L" ] && { echo "FAIL: own lock not released" >&2; exit 1; }; exit 0
DRIVE
```

**RED today**, first half: `lock dir exists: GONE`, `owner file exists: GONE`. Second half green today
and must stay green.

## R2 — a live holder is not breakable as stale

`UVM_FIXTURE_SLOW` does not exist in the tracked fixture; the drive appends it to the sandbox copy.
Holder and waiter run in one invocation. STALE=3 / TIMEOUT=2 keeps the ordering valid, so this gate
does not depend on R3's refusal. The waiter starts at t≈5, when the lock is already older than STALE,
so it evaluates staleness on its **first** loop iteration — the only way a waiter can reach the breaker
once R3 pins TIMEOUT < STALE.

```sh
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"
printf '%s\n' 'if [ -n "${UVM_FIXTURE_SLOW:-}" ]; then sleep "$UVM_FIXTURE_SLOW"; fi' \
    >> "$UVM_FIXTURE_DIR/install.sh"
( UVM_FIXTURE_SLOW=8 uv --version >/dev/null 2>"$UVM_SANDBOX/holder.err" ) & holder=$!
sleep 1; first=$(sed -n 's/.*\(pid=[0-9]*\).*/\1/p' "$L/owner")
sleep 4
set +e; UVM_LOCK_STALE=3 UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>"$UVM_SANDBOX/waiter.err"; set -e
now=$(sed -n 's/.*\(pid=[0-9]*\).*/\1/p' "$L/owner" 2>/dev/null || true)
grep -q 'breaking stale provisioning lock' "$UVM_SANDBOX/waiter.err" \
  && { echo "FAIL: a live holder's lock was broken as stale" >&2; exit 1; }
[ -n "$first" ] && [ "$first" = "$now" ] \
  || { echo "FAIL: lock was $first, now ${now:-gone}" >&2; exit 1; }
wait "$holder"
DRIVE
```

**RED today.** Waiter printed `breaking stale provisioning lock (5s old)`, provisioned concurrently
with the holder, and the owner check reported `pid=9741 -> gone`.

The gate is **not vacuous**: re-run with a heartbeat simulated inside the held lock (a background
`touch "$L"` loop during the sleep), both assertions flip green — `waiter rc=1` on the ordinary
timeout, `lock still pid=13620`. Two consequences for the plan: the waiter **exits non-zero** after the
fix, so the gate must keep `set +e` around it and must not assert `rc=0`; and the hold is a single
external command, so a heartbeat that only refreshes at step boundaries cannot pass this gate — it has
to be a background refresher.

Measured on APFS: rewriting an existing `owner` file does **not** move the lock directory's mtime
(`1786810297` before and after); `touch` on the directory does. `uvm_age` reads the directory.

## R3 — inverted knobs are refused

```sh
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$A"; mkdir "$L"
printf 'host=%s pid=%s time=%s\n' "$(uname -n)" "$$" "$(date +%s)" > "$L/owner"
sleep 3                                   # older than STALE below; its owner is alive
set +e; UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uv --version >"$UVM_SANDBOX/out" 2>"$UVM_SANDBOX/err"
rc=$?; set -e
[ "$rc" -ne 0 ] || { echo "FAIL: inverted knobs accepted" >&2; exit 1; }
grep -q UVM_LOCK_TIMEOUT "$UVM_SANDBOX/err" && grep -q UVM_LOCK_STALE "$UVM_SANDBOX/err" \
  || { echo "FAIL: no message naming both variables" >&2; exit 1; }
[ -d "$L" ] || { echo "FAIL: the live lock was destroyed" >&2; exit 1; }
UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uvm --version >/dev/null   # refusal must not eat help/--version
UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uvm help >/dev/null
DRIVE
```

**RED today on all three**, confirming the GOAL's recorded pre-fix state verbatim: `rc=0`,
`uv-manager: breaking stale provisioning lock (3s old)`, `lock dir: GONE`. The trailing two lines are a
collateral guard: `uvm --version` prints `0.5.0` and `uvm help` exits 0 with inverted knobs today, and
must keep doing so — `help` and `--version` answer before `uvm_init`, so a refusal placed in the knobs
section at `:165-166` would break that.

## R4 — no lock held across `exec`

The census, run today: `git grep -n 'exec "\${real_' bin/uv-manager` returns **4** matches —
`:617` (`uvm_self_update`), `:947`, `:949`, `:953`. Pin the count so a fifth site added later fails.

`uvm_install` releases before returning (`:365`), so **no path holds a lock at `exec` today** and no
post-condition on the tree can see the difference. The discriminating drive is xtrace ordering, which
is a genuine drive of the real script (argv[0] is `…/bin/uv`, so mode dispatch is real):

```sh
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
PS4='+ ' bash -x "$(command -v uv)" --version >/dev/null 2>"$UVM_SANDBOX/t"
u=$(grep -n '^++* uvm_unlock$' "$UVM_SANDBOX/t" | tail -1 | cut -d: -f1)
p=$(grep -n '^++* export PATH$' "$UVM_SANDBOX/t" | tail -1 | cut -d: -f1)
e=$(grep -n '^++* exec ' "$UVM_SANDBOX/t" | tail -1 | cut -d: -f1)
[ -n "$u" ] && [ "$u" -gt "$p" ] && [ "$u" -lt "$e" ] \
  || { echo "FAIL: no release between uvm_export_env and exec (unlock=$u path=$p exec=$e)" >&2; exit 1; }
DRIVE
```

**RED today**: `unlock=118 path=149 exec=153` — the last release is the one inside `uvm_install`,
nothing runs between `uvm_export_env` and `exec`. `PS4` is set explicitly because `temp_root.sh` does
not scrub it. The same probe run as `uv self update` reaches `:617` offline (`uvm_unlock` at trace 213,
`exec` at 218), so that site is drivable too.

**Inspection-only for the reviewer:** "the release must be a builtin test that forks nothing when no
lock is held" — the GOAL already assigns this to the reviewer; no command decides it. "Every site
covered" is likewise a reading of the 4-line census: a `grep -B2`-style proximity gate breaks depending
on whether one `uvm_unlock` precedes the `case` block or each `exec` gets its own.

## R5 — the timeout message names the discriminator

```sh
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; mkdir -p "$A"; mkdir "$L"
printf 'host=%s pid=%s time=%s\n' "$(uname -n)" "$$" "$(date +%s)" > "$L/owner"
set +e; UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=600 uv --version 2>"$UVM_SANDBOX/err"; rc=$?; set -e
[ "$rc" -ne 0 ] || { echo "FAIL: waiter did not time out" >&2; exit 1; }
for tok in owner host pid; do
  grep -qw "$tok" "$UVM_SANDBOX/err" \
    || { echo "FAIL: timeout message never mentions '$tok'" >&2; exit 1; }
done
DRIVE
```

**RED today** on all three tokens. Baseline verbatim: `timed out after 2s waiting for provisioning
lock: …`, then `If no other uv process is provisioning, remove it with:` / `rmdir '…'`. Runtime ≈3 s
(the counter increments before the sleep). `grep -qw` rather than `grep -q`, so a sandbox path
containing one of the tokens cannot green the gate by accident.

## R6 — no regression, discipline stays `mkdir`

`.agents/factory/bin/temp_root.sh --offline uv --version` today prints `uv 9.9.9 (fixture)` on stdout
and leaves `current -> versions/9.9.9`. `.agents/factory/bin/lint.sh` passes (`all checks passed`,
version single-source `0.5.0`).

```sh
.agents/factory/bin/lint.sh >/dev/null
.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'
set -e
out=$(uv --version)
[ "$out" = "uv 9.9.9 (fixture)" ] || { echo "FAIL: stdout was '$out'" >&2; exit 1; }
A="$UVM_ROOT/$(uname -m)"
[ "$(readlink "$A/current")" = versions/9.9.9 ] || { echo "FAIL: current target moved" >&2; exit 1; }
DRIVE
if git grep -n flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#'; then
  echo "FAIL: flock outside a comment" >&2; exit 1
fi
```

**The GOAL's literal R6 clause is wrong and must not be transcribed into a `verify:` block.**
`git grep -c flock bin/uv-manager` returns `bin/uv-manager:1`, exit 0 — the word appears at `:172`, in
the comment that records *why* the discipline is `mkdir`. Three forms, measured:

- `test "$(git grep -c flock bin/uv-manager)" = 0` — **never true**. With matches the substitution is
  `bin/uv-manager:1` (the file prefix is emitted even for one path); with none it is the empty string.
  Permanently red, therefore an inert gate that will simply be deleted.
- `n=$(git grep -c flock …)` under bash `set -e` — **aborts the gate** on zero matches, because
  `grep -c` exits 1 when it counts nothing. (Under zsh it does not; the gates run under bash.)
- `if git grep -n flock … | grep -qvE '…#'` — safe under `set -e` (the `if` protects the pipeline),
  and states the real requirement: no `flock` in code, the rationale comment retained.

## Gate hygiene, summary

| R | Recipe | Against today |
|---|--------|---------------|
| R1 | foreign `owner` written from inside the installer | **RED** (lock and owner both deleted) |
| R2 | slow fixture + late waiter, STALE 3 / TIMEOUT 2 | **RED** (`breaking stale …`, owner gone) |
| R3 | inverted knobs over a live lock | **RED** (rc 0, no message, lock destroyed) |
| R4 | xtrace ordering `uvm_export_env` → `uvm_unlock` → `exec` | **RED** (unlock 118 < path 149) |
| R5 | drive to timeout, `grep -qw owner host pid` | **RED** (none present) |
| R6 | fixture version, `current` target, code-only flock census | green, must stay green |

Nothing here needs a helper that exists only in the build. Two clauses no command can decide, for the
reviewer: R4's fork-free-release cost claim (the GOAL already says so), and "every `exec` site
covered", which is a reading of the 4-line census.

Not established

- Whether `/uvm-harness` should be asked for a `UVM_FIXTURE_SLOW` knob in the tracked fixture. Every
  timing recipe appends it to the sandbox copy instead, which works and keeps `.agents/` out of this
  cycle's diff, at the cost of three lines repeated per gate.
- Sleep-based timings (1 s, 4 s, 8 s) were reliable here; they have not been run on a loaded shared
  machine, and a `verify:` block that is retried under load may need wider margins.
- Whether R3's refusal fires at knob-read time or only on contention. The collateral lines in the R3
  recipe assume it must not break `uvm help` / `uvm --version`; the placement is `/uvm-plan`'s.
