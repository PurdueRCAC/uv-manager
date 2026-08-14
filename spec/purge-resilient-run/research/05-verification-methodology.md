# 05 — Verification methodology: which gates can go red, and how

Every technique below was run against this branch on 2026-08-12. Host `uname -m` is `arm64`; the
cluster equivalent is `aarch64` (§1), so no gate may hardcode either — read it from `uname -m`.

**Conclusion, high confidence.** Seven of the eight criteria are driveable on this machine, and R4 is
driveable too — the GOAL's claim that it "needs egress and one small real package" is correct, but the
drive costs 18 seconds and roughly 100 MB, not a cluster. The gates that will be **inert** if written
naively are R2, R3's scaling half, and R8: all three assert properties the current tree already has.
Each has a red-capable pairing, given below. R5's Lustre/GPFS/NFS clause is the one thing genuinely
out of reach.

## R1 — the `mkdir` counting stub works, and the baseline is exactly 1

A stub first on `PATH` is reached from inside the wrapper's `( umask 077; mkdir -p ... )` subshell.
The inner command must capture the real `mkdir` before prepending, because the stub shadows it.
`uvm_path_prepend` puts three shim directories ahead of the stub dir, which does not matter — the stub
still precedes `/bin`.

    .agents/factory/bin/temp_root.sh --offline sh -c '
      set -eu; real=$(command -v mkdir); mkdir -p "$UVM_SANDBOX/stub"
      printf "#!/bin/sh\necho x >> %s/mkdir.log\nexec %s \"\$@\"\n" "$UVM_SANDBOX" "$real" \
        > "$UVM_SANDBOX/stub/mkdir"; chmod 0755 "$UVM_SANDBOX/stub/mkdir"
      PATH="$UVM_SANDBOX/stub:$PATH"; export PATH
      uv --version >/dev/null 2>&1
      : > "$UVM_SANDBOX/mkdir.log"
      uv --version >/dev/null
      n=$(wc -l < "$UVM_SANDBOX/mkdir.log" | tr -d " ")
      echo "warm mkdir invocations: $n"; [ "$n" -eq 0 ]'

Ran it: prints `1`, exits 1. Correctly red. The count is a known number, not zero, so the assertion
needs no scoping: **warm intact tree issues exactly 1 `mkdir`** (the `uvm_export_env` call at `:407`),
and **cold issues 5** — `:205`, `:208`, `:325`, `mktemp -d`, `:407`, plus the fixture's own `mkdir -p`
inside the installer, which the stub also sees because the installer inherits `PATH`. Real `uv` is a
Rust binary and does not fork `/bin/mkdir`, so the stub does not over-count on a network drive.

The missing-directory half: `rmdir "$UVM_ROOT/$(uname -m)/cache"`, drive, assert the count is 1 and
`stat -c %a … 2>/dev/null || stat -f %Lp …` reports `700`. Ran it; both hold today and must keep
holding.

Timing, 50 warm invocations, local SSD, fixture uv: wrapper **9.7 ms**, fixture uv called directly
**3.0 ms**, the six-directory `mkdir -p` subshell alone **1.9 ms**. The seed's 9.6 / 3.1 / 2.4
reproduce.

## R2, R3, R8 — inert unless paired

`temp_root.sh --offline sh -c` with a damaged tree and `UVM_REPAIR` unset already exits 0, writes
**0 bytes** to stderr, and creates no lock directory. That is R2's post-condition, satisfied today.
Write it only as the control arm of a two-arm gate whose other arm sets `UVM_REPAIR=1` and asserts a
repair happened; the pair is red, the control alone is not.

R3's scaling half is the same trap. Measured warm hot path with a synthetic tool environment holding
100 files versus 10 000: **9.9 ms/call** and **9.4 ms/call** — flat, because the wrapper scans nothing
today. `uvm doctor` over the same two trees costs **29 ms** and **225 ms**, which is the unbounded
comparator the gate exists to rule out. State the gate as "cost at 10 000 stays within the 100-file
figure *while* damage at 10 000 is still found", so the detection half carries the redness.

R8: `UVM_REPAIR` appears **0 times** in `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`,
`share/modulefiles/uv/main.lua`, and 0 times in `temp_root.sh uvm help`. A grep gate on those five is
red today. `lint.sh` and the three baseline drives all pass now and are pure regression.

## R3/R4/R7 — the damaged-tree fixture

`uvm_doctor:689` globs `tools/*/lib/*/site-packages/*.dist-info/RECORD` and, per line, takes field 1
comma-split, skipping entries beginning `../` or `/`. Reusable snippet, verified:

    a=$(uname -m); R="$UVM_ROOT/$a"; sp="$R/tools/demo/lib/python3.12/site-packages"
    mkdir -p "$sp/demo" "$sp/demo-1.0.dist-info"
    : > "$R/tools/demo/uv-receipt.toml"; : > "$sp/demo/__init__.py"
    printf 'demo/__init__.py,sha256=a,0\ndemo/purged.py,sha256=b,0\n' \
      > "$sp/demo-1.0.dist-info/RECORD"

`uvm doctor` then prints `FAIL  demo-1.0 is missing 1 of 2 files (partial purge)` and exits 1. The
receipt file is required or doctor also emits the no-receipt WARN and the gate stops discriminating.
The other four damage classes are equally synthesizable and were each driven: dangling shim
(`ln -s` to a nonexistent target under `bin/shims`), broken interpreter link, missing receipt, and a
managed interpreter whose `lib/python3.12/json` was removed.

## R5 — N-way concurrency, with a barrier that makes the race real

`temp_root.sh` builds and destroys one sandbox per call, so N children go inside a single inner
`sh -c`, synchronized by a busy-wait barrier. Process startup is ~10 ms and would otherwise stagger
them; the barrier closes that to microseconds.

    N=8; GO="$UVM_SANDBOX/go"; OUT="$UVM_SANDBOX/out"; mkdir -p "$OUT"
    i=0; while [ $i -lt $N ]; do
      ( while [ ! -f "$GO" ]; do :; done
        UVM_REPAIR=1 uv --version >"$OUT/$i.out" 2>"$OUT/$i.err"; echo $? >"$OUT/$i.rc" ) &
      i=$((i+1)); done
    sleep 1; : > "$GO"; wait

Against a warm damaged tree today: **0 repair markers, 8 successes** — correctly red for R5.

The barrier alone does not prove contention: eight cold children produced exactly one install, but the
losers may have taken the `uvm_install` fast path rather than the lock. To force the lock, slow the
winner inside the sandbox — `sed -i.bak 's|^set -eu|set -eu\nsleep 3|' "$UVM_FIXTURE_DIR/install.sh"`.
Per-child elapsed then reads `4 4 3 4 4 4 4 4` seconds: seven children genuinely sat in
`uvm_acquire_lock`'s wait loop. Use that shape, or the gate can pass on a sequential run.

Use `grep -c … || true`; `grep -c` returns 1 on zero matches and kills a `set -e` gate before it can
report.

## R7 — lock timeout

Held lock plus `UVM_LOCK_TIMEOUT=1` works today on the provisioning path: `mkdir -p
"$UVM_ROOT/$(uname -m)/.install.lock"`, then `UVM_LOCK_TIMEOUT=1 uv --version` on a **cold** tree dies
with `timed out after 1s waiting for provisioning lock` and exits 1, leaving the foreign lock intact
(`uvm_unlock` is a no-op because `uvm_lock` is empty).

The hazard the planner must design around: on a **warm** tree the same held lock is invisible.
`uvm_install:308` returns before `uvm_acquire_lock` is ever called, so `UVM_LOCK_TIMEOUT=1 uv
--version` against a warm damaged tree with the lock held exits **0** and execs into the damage. That
is precisely R7's red baseline, and it means the repair path needs its own acquisition — reusing
`.install.lock` keeps this technique working; a differently named lock changes the gate's `mkdir`
target. R7 also demands the message name the damage, not only the lock; today's text names only the
lock, so `grep 'timed out'` alone is not enough to distinguish before from after.

## R6 — stdout purity and rc

Verified against cold offline provisioning: `VER=$(uv --version)` yields exactly
`uv 9.9.9 (fixture)` while the two installer lines land on stderr. `UVM_FIXTURE_EXIT=3` propagates
through all three tails — `uv --version` exits 3, `uvx foo` exits 3, and the non-exec `uv tool list`
path exits 3. Repair chatter added on the `UVM_REPAIR` path must not disturb this; the same command
is the gate.

## R4 — driveable here, at a price

Contrary to the GOAL's framing, R4 does not need a cluster. This machine has egress (`pypi.org` 200,
`astral.sh` 301) and a `temp_root.sh` drive **without** `--offline` provisions the real uv from
Astral. Full cycle, run and passing:

    .agents/factory/bin/temp_root.sh sh -c '
      uv tool install --python "$(command -v python3)" tqdm
      uvm doctor                                   # OK, exit 0
      rec=$(ls "$UVM_ROOT/$(uname -m)"/tools/tqdm/lib/*/site-packages/tqdm-*.dist-info/RECORD|head -1)
      sp=$(dirname "$(dirname "$rec")")
      awk -F, "NF{print \$1}" "$rec" | grep "^tqdm/" | head -5 | while read -r f; do rm -f "$sp/$f"; done
      uvm doctor                                   # FAIL tqdm-4.70.0 is missing 5 of 41 files, exit 1
      uv tool uninstall tqdm && uv tool install --python "$(command -v python3)" tqdm
      uvm doctor'                                  # OK, exit 0

**18.5 s wall**, roughly 35 MB of uv plus a 78 KB wheel. `tqdm` is the right package: no dependencies
and a console script, which `uv tool install` requires. The managed-python class costs more —
`uv python install 3.12` lands 66 MB and the whole drive took 2.0 s on a warm link; removing
`lib/python3.12/json` makes doctor report `managed interpreter … is damaged (stdlib import failed)`.

Mark this gate as network-dependent and keep it out of the per-phase loop. It fails on an air-gapped
reviewer's box, and `--python "$(command -v python3)"` is a local shortcut that dodges the interpreter
download — drop it and the tool drive costs 66 MB more.

## What could not be established

**R5 on Lustre, GPFS and NFS.** A `mktemp -d` under `/var/folders` on APFS is none of those. `mkdir`
atomicity, the `rmdir`-based release and stale-lock breaking are taken on trust from §5 plus a
real-cluster drive. Nothing local substitutes; say so in the record rather than implying the eight-way
APFS race covered it.

**Ten-thousand-rank scale.** Eight children is what a laptop sustains. `UVM_LOCK_TIMEOUT` at the scale
R5 makes it load-bearing is a cluster measurement, already a declared non-goal.

**Damage classes doctor itself misses.** Every fixture here is built to what `uvm_doctor` walks, so a
gate written against it inherits doctor's blind spots. R3's `README.md` obligation is the only place
that gets named.

## Operational notes

`rm` is blocked in the agent's outer shell but works normally inside `temp_root.sh … sh -c`, where it
is the real binary. A `verify:` line that calls `rm` at the outer level fails with
`"rm" not supported - use "del" instead`; inside the sandbox it is fine. `--keep` prints the sandbox
path and leaves it behind, which then needs a `del` — the single inner `sh -c` shape above avoids
that and is what every gate here uses.
