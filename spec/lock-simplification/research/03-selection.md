# 03 — Every success path selects what it was asked for (R12, R13), under concurrency

Measured on macOS 27.0.1, `/bin/bash` 3.2.57, BSD `mv`, against a throwaway copy of the worktree at
`09ec1ea` under `temp_root.sh --offline`. "Restructure" below is the planner's hypothesis applied to
the copy; "+ `mv -h`" adds the swap fix in Finding 2.

## Recommendations

1. **Adopt the restructure, with one change to the selection step's message.** Every success path
   in `uvm_install` falls through to one block at its end, *before* `uvm_unlock`:
   `if want: uvm_have want || die …; uvm_point_current want; elif ver: uvm_point_current ver`. Select
   while still holding the lock: an unpinned waiter re-checks `uvm_have ""` (`current/uv`), so a holder
   that unlocked before selecting would let a second rank install (R14). Word the die so it is right on
   both reachable causes, a wrong delivery and a version removed under you:
   `die "uv ${want} is not installed after provisioning${ver:+ (the installer delivered ${ver})}"`.
   Keep it one line; the gate reads the last stderr line.
2. **The restructure alone is not enough: it is red on R12.** Every waiter now selects, and they
   select at the same moment. The `mv -T` fallback (`rm -f current; mv tmp current`) then loses
   `current` and moves `.current.<pid>` inside `versions/<ver>/`. Fix `uvm_point_current` at the
   floor:
   ```bash
   if ! mv -T "${tmp}" "${uvm_current}" 2>/dev/null &&
      ! mv -h "${tmp}" "${uvm_current}" 2>/dev/null; then
     rm -f "${uvm_current}" 2>/dev/null || true
     mv "${tmp}" "${uvm_current}"
   fi
   ```
   GNU's `-T` goes first because the production clusters are Linux, so they still pay one fork.
   BSD/macOS reject `-T` before touching anything (`mv: illegal option -- T`, rc 64), and `-h` then
   renames onto the link without following it. Keep the `rm`+`mv` tail only for an `mv` that has
   neither option, and update invariants §4/§10's "documented non-atomic fallback" wording.
3. **`uvm_ensure_uv` collapses to `uvm_install "${pin}" ""` plus the `[[ -x ]]` check.** This costs
   no fork (table below).
4. **The R12 failure drive uses "the 6.6.6 installer delivers 9.9.9"**, not "6.6.6/install.sh
   missing" (Finding 4).

## Finding 1 — R12 histograms (16 ranks, `ln` shim `sleep 2`)

| build | satisfiable, cold | satisfiable, warm at 9.9.9 |
|---|---|---|
| main | 1 rc 0 `6.6.6`; **15 rc 1** `uv is still missing after provisioning` | 1 rc 0 `6.6.6`; **15 rc 0 `uv 9.9.9`** |
| restructure only | 9 ok; 4 rc 1 "still missing"; 2 rc 1 `current/uv: No such file`; 1 rc 127; stray `.current.*` in `versions/6.6.6/` | 14 ok; 2 rc 1; stray `.current.*` |
| restructure + `mv -h` | 16/16 rc 0 `uv 6.6.6 (fixture)`, three trials | 16/16, three trials; also 32/32 once |

Main's results match the GOAL's red record exactly. The operator spellings behave the same way. With
8 concurrent ranks, warm, and the shim, main gave `uvm install 6.6.6` 7 of 8 printing
`selected uv 9.9.9` at rc 0, and `uv self update 6.6.6` 7 of 8 printing `uv 9.9.9` at rc 0. With the
restructure and `mv -h`, all 8 picked 6.6.6 on both spellings.

**The wrong-delivery claim is confirmed.** Run `UVM_PIN=6.6.6` with `UVM_FIXTURE_VERSION` unset (so
the 6.6.6 installer delivers 9.9.9). On main, all 16 ranks exit 0 printing `uv 9.9.9 (fixture)`, warm
and cold. Every rank re-runs the installer in turn, because 6.6.6 never appears (11–16 s). With the
restructure, all 16 exit 1, stdout is empty, and the last stderr line names 6.6.6, warm and cold. The
serialized re-install per rank is pre-existing, and the patch leaves it as it is.

## Finding 2 — concurrent `current` swaps (`swap.bash`, bash 3.2)

The writers alternate `current` between `versions/a` and `versions/b`, each using a distinct
`.current.<n>`. A bash reader polls `[ -L current ]` with no fork.

| variant | writers × rounds | rc≠0 | reader saw `current` missing | strays in `versions/*/` |
|---|---|---|---|---|
| main (`-T` → `rm`+`mv`) | 16×20 / 32×20 / 32×100 | 1 / 5 / 23 | 12 651 / 19 950 / 58 062 | 32 / 63 / 64 |
| `-T` → `-h` → `rm`+`mv` | 16×20, 32×20, 3× 32×100 | 0 | 0 | 0 |
| `ln -sfn` | 16×20 / 32×20 | 17 / 24 (`ln: current: File exists`) | 953 / 1 261 | 0 |

The rc≠0 under main is `mv: rename .current.N to current/.current.N: No such file or directory`. A
rival removed `current` between `mv`'s stat and its rename. Under `set -e` this is a bare `mv:` death.
**`ln -sfn` hurts:** it does unlink-then-symlink, so it is not atomic, and it fails with EEXIST when it
races. It is not a candidate.

`mv -h` is documented in `man mv` here ("rename the file source to the destination path target rather
than moving source into the directory referenced by target"). That it is a single `rename(2)` is
inferred from zero reader misses in 9 600 swaps against tens of thousands for `rm`+`mv`. It is not
syscall-traced (no root for `dtruss`). **GNU `mv -h` is not measured:** this Mac has no GNU coreutils,
and no Linux host was used. From GNU's option table it should reject `-h` as an invalid option, with
exit status 1, before any file operation. Production never reaches it, because GNU succeeds on `-T`
first. The plan should mark it unmeasured or measure it on a Linux image.

## Finding 3 — hot path (invariants §10)

Trace of `uv --version` (`bash -x`, `PS4` carrying `BASH_SUBSHELL`), from `uvm_ensure_uv` to
`uvm_export_env`:

| path | main | after |
|---|---|---|
| unpinned, warm | 0 forks | 0 forks |
| pinned, `current` already at the pin | 1 (`readlink` substitution) | 1 |
| pinned, swap needed, macOS | 6 (readlink, rm, ln, mv -T, rm, mv) | 5 (readlink, rm, ln, mv -T, mv -h) |
| pinned, swap needed, GNU | 4 | 4 (by reading; the `-T` branch is unchanged) |

The collapse adds one builtin `[[ -x ]]` on the pinned fast path, because `uvm_have` runs twice, plus a
`uvm_unlock` builtin test. There is no new fork.

## Finding 4 — failure construction

If `6.6.6/install.sh` is missing, the fetch fails. Every rank exits 1 with empty stdout on **main
too**, and 6.6.6 appears only in the `installing uv (6.6.6)` note and curl's URL. The die message,
`install failed — no egress…`, does not name it. So this construction is green on main and cannot
grade the fix. The wrong-delivery construction is red on main (rc 0, `9.9.9`) and green after. Use
that one.

## Finding 5 — R14 unchanged

`sh tests/lock-race.sh --plant control --ranks 32 --bursts 2` gave the same result on the worktree
(main) and on the patched copy: `installs=1` per burst, `installer_entries=2 (expect 1/burst)`,
`nonzero_ranks=0`, `locks_left_standing=0/2`, `progress=ok`, rc 0, wall 3 s and 4 s.

## R12 gate (both drives)

Run it as `.agents/factory/bin/temp_root.sh --offline sh -s <<'EOF' … EOF`. It **depends on an
external `ln` reached through `PATH`** inside `uvm_point_current` (`ln -s versions/<ver> <tmp>`). The
shim logs each call, and the gate fails if the shim was never reached. That turns a changed call
shape into a FAIL instead of a silent pass.

Measured results:

- **main:** FAIL at `ok-cold rank 1: rc=1 … still missing after provisioning`.
- **Restructure only:** FAIL at `ok-cold`, three of three runs.
- **Restructure + `mv -h`:** `R12 ok`, three of three runs, 30–32 s each.

```sh
set -u
n=16; arch=$(uname -m)
mkdir -p "$UVM_FIXTURE_DIR/6.6.6"; cp "$UVM_FIXTURE_DIR/install.sh" "$UVM_FIXTURE_DIR/6.6.6/install.sh"
shim="$UVM_SANDBOX/shim"; mkdir -p "$shim"
printf '#!/bin/sh\necho x >> "%s/ln.calls"\nsleep 2\nexec /bin/ln "$@"\n' "$UVM_SANDBOX" > "$shim/ln"; chmod +x "$shim/ln"
burst() {   # LABEL WARM FIXVER: n concurrent UVM_PIN=6.6.6 ranks on a fresh root
  r="$UVM_SANDBOX/$1"; mkdir -p "$r"
  if [ -n "$2" ]; then
    UVM_ROOT="$r" uv --version >/dev/null 2>&1
    if [ "$(readlink "$r/$arch/current")" != versions/9.9.9 ]; then echo "FAIL: $1: warm-up did not select 9.9.9" >&2; exit 1; fi
  fi
  : > "$UVM_SANDBOX/ln.calls"
  i=1; while [ "$i" -le "$n" ]; do
    ( if [ -n "$3" ]; then UVM_FIXTURE_VERSION="$3"; export UVM_FIXTURE_VERSION; fi
      PATH="$shim:$PATH" UVM_ROOT="$r" UVM_PIN=6.6.6 uv --version >"$r.out.$i" 2>"$r.err.$i"; echo $? >"$r.rc.$i" ) &
    i=$((i + 1)); done; wait
}
for t in cold warm; do
  if [ "$t" = warm ]; then w=1; else w=; fi
  burst "ok-$t" "$w" 6.6.6
  if [ ! -s "$UVM_SANDBOX/ln.calls" ]; then echo "FAIL: ok-$t: ln shim never called; the drive no longer constructs the gap" >&2; exit 1; fi
  i=1; while [ "$i" -le "$n" ]; do r="$UVM_SANDBOX/ok-$t"
    if [ "$(cat "$r.rc.$i")" != 0 ] || [ "$(cat "$r.out.$i")" != "uv 6.6.6 (fixture)" ]; then
      echo "FAIL: ok-$t rank $i: rc=$(cat "$r.rc.$i") out=[$(cat "$r.out.$i")] err=[$(tail -n 1 "$r.err.$i")]" >&2; exit 1; fi
    i=$((i + 1)); done
  burst "bad-$t" "$w" ""          # fixture version unset: the 6.6.6 installer delivers 9.9.9
  i=1; while [ "$i" -le "$n" ]; do r="$UVM_SANDBOX/bad-$t"
    if [ "$(cat "$r.rc.$i")" = 0 ] || [ -s "$r.out.$i" ] || ! tail -n 1 "$r.err.$i" | grep -q '6\.6\.6'; then
      echo "FAIL: bad-$t rank $i: rc=$(cat "$r.rc.$i") out=[$(cat "$r.out.$i")] err=[$(tail -n 1 "$r.err.$i")]" >&2; exit 1; fi
    i=$((i + 1)); done
done
echo "R12 ok: 4 bursts x $n ranks"
```

The `bad-*` assertion reads the **last** stderr line on purpose. The `installing uv (6.6.6)` note
names 6.6.6 on every rank, on main too, so grepping the whole of stderr would pass vacuously.
