# Research 04 — the instrument: re-pointing `tests/lock-race.sh` (R14, R15) and the Slurm drive (R4 (c))

Every number below was measured on this worktree's base (`09ec1ea`) on APFS through
`temp_root.sh --offline`. Phase 1 does not exist yet, so its behavior was **emulated** in a
throwaway copy under `$TMPDIR`: the timeout `die` in `uvm_acquire_lock` preceded by `return 0`
(proceed unlocked; `uvm_lock` stays empty, so `uvm_unlock` is a no-op), the publish left as
`main`'s unguarded `mv`. "Guard" below is an emulation too (`mv`, then remove `${dest}/${tmp##*/}`),
used only to show the drive can go green. It is not a design proposal.

## Findings that change the plan

1. **The `current` swap fails under concurrent publish on BSD `mv`, which is the sandbox.**
   `uvm_point_current` falls back to `rm -f current; mv .current.$$ current` when `mv -T` is
   missing. Under a held plant, a rival's swap lands between the two commands. BSD `mv` then follows
   the new `current` into `versions/9.9.9` and leaves `.current.<pid>` there. That happened in
   **5–6 of 6 bursts** at 32 ranks, and **5–10 %** of ranks failed (rc 127 `current/uv: No such
   file`, or rc 1 `uv is still missing`). With the fallback changed to `mv -h` (BSD: do not follow a
   symlink target, then `rename(2)`; verified to replace a directory symlink in place), the result was
   **0 nested `.current.*` and 0 non-zero ranks across 24 bursts / 1 408 ranks**. GNU `mv -T` exists
   on the Linux clusters, so the Slurm drive will not see this. The sandbox gate will. Unless the plan
   makes this swap atomic without `-T`, R4 ("every process SHALL exit 0", "`current` resolving") and
   R15's green cannot pass on macOS. That is a scope item for the plan in `uvm_point_current`, a
   high-blast-radius region.
2. **Without help, the unguarded publish rarely nests.** With the `current` swap fixed, the unguarded
   `mv` nested `.incoming.*` in only **1 of 10** bursts at 64 ranks. The check-to-rename window is a
   single fork, and the fixture installers finish spread over ~100 ms. A red gate built on that rate
   would need about 45 bursts.
3. **A release barrier in the fixture hook makes the red state cheap.** The hook already spliced into
   the sandbox fixture gets a barrier: each installer touches `arr.<tag>.<id>`, then polls at 10 ms
   until all `ranks` have arrived or 1 s has passed. Nothing in `bin/` is instrumented. Measured on
   the emulated P1: **14 of 20 bursts red at 64 ranks** (p ≈ 0.7), 4 of 8 at 32. On the emulated
   guard: **0 of 16** at 64 and 32. One emulated-P1 burst also produced R10's case naturally: a
   sibling `versions/.incoming.*` plus one non-zero rank.
4. **The progress check must not count non-zero ranks.** On P1, non-zero ranks occur (finding 3), and
   today they exit **4** before any tree verdict. R15's red would then flip between 4 and 1. Move
   `nonzero_ranks` into the correctness verdict (exit 1).

## Part A — re-point `tests/lock-race.sh`

**Remove:** `stolen`, `robbed` and `broke` (and `t_`/`red_` twins), the `stolen_holds=`,
`robbed_winners=` and `break_notes=` lines, `via_break`/`no_break_in_burst`, the `timeout=`/
`ownership=` causes (no longer reachable as causes: a timeout proceeds), the "red_bursts" framing,
the header's burst-sizing arithmetic (p for `owner`/`none`), the `LOCKRACE_STALE=10` and 2020
comment at `:101-107`, the burst's `: "${LOCKRACE_STALE:?}"`, `UVM_LOCK_STALE=` export, the `owner`
plant (`sh -c 'exit 0'` reaped pid + `touch -t 2020…`) and the `none` plant. Exit-code text and
`AGENTS.md:271-279` must be rewritten in the same commit (R9 grep does not catch them).

**Plant vocabulary:** `control` (no plant) and `held` (`mkdir` + `host=$(uname -n) pid=$$
nonce=lockrace` from the burst shell, so the holder really is alive; copy saved as
`plant.<tag>`). `none` is no longer distinct: after this cycle the `owner` line only feeds messages,
and R1's drive already covers the ownerless lock. Reject `owner`/`none` with exit 2.

**Progress (exit 4), asserted first:** `installer_entries >= bursts`; no lock standing after a
`control` burst; after a `held` burst the lock standing is the plant itself (`ls -A` = `owner`,
`cmp` byte-identical against `plant.<tag>`), counted as `plant_intact=B/B`; and under `held`,
`concurrent_bursts >= 1`. Without that last condition the tree assertion is vacuous. Measured:
every held burst had 25–63 concurrent entries.

**Verdict (exit 1), naming counters:** per burst, inside the sandbox before `temp_root` tears it
down, `versions/<want>` `ls -A` is exactly `uv uvx`. Defects are split by kind so attribution is
greppable: `nested_staging` (`.incoming.*` inside), `nested_current` (`.current.*` inside),
`stray_staging` (`versions/.incoming.*`), `current_bad` (readlink ≠ `versions/<want>` or
`current/uv` not executable). Then `wrong_stdout` (≠ `uv <want> (fixture)`) and `nonzero_ranks`.
Under `control`, also `installer_entries == bursts` and `concurrent_installers == 0` (R14).
`concurrent_installers` stays as a **reported** number and is never asserted under `held`.

**Sizes:** `--timeout` (new, default 1: the burst's `UVM_LOCK_TIMEOUT`) and `--deadline 5`
(unchanged; quiescence was immediate in every run). `held` 64×10 ≈ 30 s (false green against the
unguarded publish ≈ 0.3¹⁰ ≈ 6e-6); `control` 32×2 ≈ 3 s. Keep `--straggler`/`--late`.

**R14 baseline (worktree as-is):** `tests/lock-race.sh --plant control --ranks 32 --bursts 2` → rc 0,
`installer_entries=2`, `concurrent_installers=0/64`, `nonzero_ranks=0`, `locks_left_standing=0/2`,
`progress=ok`, wall 3 s. This matches GOAL's recorded green.

**The copy approach works today.** I ran `tests/lock-race.sh --plant control --ranks 8 --bursts 1`
from a `cp -R` copy and from a `git archive HEAD | tar -x` copy: rc 0. The copy runs its own `bin/`,
because it behaved as the emulated build, not as HEAD. `git archive` is the cleaner choice: no
`.git` file, symlinks kept.

**R15 red/green gate (proposed `verify:`):**

```sh
p1=$(git log -1 --format=%H -F --grep='Build lock-simplification P1:' HEAD)
[ -n "$p1" ] || { echo 'no P1 commit on HEAD'; exit 1; }
X=$(mktemp -d "${TMPDIR:-/tmp}/lr-red.XXXXXX")
git archive HEAD | tar -x -C "$X"
git show "${p1}:bin/uv-manager" > "$X/bin/uv-manager"
grep -qF 'mv "${tmp}" "${dest}"' "$X/bin/uv-manager" || { echo 'P1 publish is not the unguarded mv'; exit 1; }
"$X/tests/lock-race.sh" --plant held --ranks 64 --bursts 10 > "$X/red.out"; red=$?
[ "$red" -eq 1 ] && grep -qE '^nested_staging=[1-9]' "$X/red.out" || { cat "$X/red.out"; exit 1; }
tests/lock-race.sh --plant held --ranks 64 --bursts 10 && tests/lock-race.sh --plant control --ranks 32 --bursts 2
```

`-F --grep` on `HEAD` only: on `--all`, an earlier cycle's P1 subject appears twice (rebased
copies), and on HEAD's ancestry once. The match is on the `nested_staging` key, not just rc 1. If P1
leaves `uvm_point_current` as is, the red run also shows `nested_current` and non-zero ranks (finding
1), and only the key pins attribution to the publish. Total ≈ 65 s.

## Part B — the multi-rank Slurm drive

**Recommendation: a mode of `tests/lock-race.sh`, not a new script.** The non-goal ("no committed
suite beyond `tests/lock-race.sh`") would need a deviation row for a new file. `lint.sh` lists test
files explicitly (`:46-48`, `:74-79`), so a new file is unlinted unless `.agents/factory/` changes. A
second script would also carry a second copy of the tree predicate, which drifts. In favor of the
mode: it reuses temp_root's scrubbing, offline fixture copy and `file://` URL (`uvm_fetch` is
`curl -LsSf … "${url}"` at `:509`, and the `wget` fallback cannot read `file://`, so curl is
required), plus the liveness and straggler guards. The cost is about 40 lines in two files.

Additions:

- `--launch local|srun` (default `local`). It is never auto-detected: `srun` can be a wrapper on a
  workstation.
- `--pin VER` (R12 warm): one `uv --version` before the hook (so `versions/9.9.9` is current and
  no `inst` marker is written), then the hooked fixture is copied to `$UVM_FIXTURE_DIR/VER/`, and
  ranks export `UVM_PIN=VER UVM_FIXTURE_VERSION=VER`.
- `srun` requires `LOCKRACE_SHARED` (exit 2, `LOCKRACE_SHARED must name a directory on the
  filesystem under test`), and the driver sets `TMPDIR="$LOCKRACE_SHARED"` before its `mktemp`.
  That puts both `LOCKRACE_DIR` and temp_root's sandbox on the shared FS. The checkout must be on a
  shared FS too, because ranks re-exec the burst by path.

Burst sketch (`tests/lock-race-burst.sh`):

```sh
want="${LOCKRACE_PIN:-9.9.9}"
if [ -n "${LOCKRACE_PIN:-}" ]; then
    UVM_PIN="$LOCKRACE_PIN" UVM_FIXTURE_VERSION="$LOCKRACE_PIN"; export UVM_PIN UVM_FIXTURE_VERSION
fi
if [ "${LOCKRACE_ROLE:-}" = rank ]; then          # one rank, local or on any node
    i="${LOCKRACE_RANK:-$(( ${SLURM_PROCID:-0} + 1 ))}"
    : > "$LOCKRACE_DIR/live.rank.$tag.$i"
    uname -n > "$LOCKRACE_DIR/node.$tag.$i"        # counted by the driver, never printed
    LOCKRACE_RANK="$i" LOCKRACE_TAG="$tag" UVM_LOCK_TIMEOUT="$LOCKRACE_TIMEOUT" \
        uv --version > "$LOCKRACE_DIR/out.$tag.$i" 2> "$LOCKRACE_DIR/err.$tag.$i"
    echo $? > "$LOCKRACE_DIR/rc.$tag.$i"
    rm -f "$LOCKRACE_DIR/live.rank.$tag.$i"
    exit 0
fi
[ -z "${LOCKRACE_PIN:-}" ] || UVM_PIN='' UVM_FIXTURE_VERSION='' uv --version >/dev/null 2>&1  # warm, unhooked
# ... splice PRE/POST hook as today; POST gains, before its sleep 0.05:
#   if [ -n "${LOCKRACE_BARRIER:-}" ]; then : > "$LOCKRACE_DIR/arr.$LOCKRACE_TAG.$_lr_id"; _n=0
#     while [ "$_n" -lt "$LOCKRACE_BARRIER_TICKS" ]; do set -- "$LOCKRACE_DIR"/arr."$LOCKRACE_TAG".*
#       [ "$#" -ge "$LOCKRACE_BARRIER" ] && break; sleep 0.01; _n=$((_n + 1)); done; fi
[ -z "${LOCKRACE_PIN:-}" ] || { mkdir -p "$UVM_FIXTURE_DIR/$want"; cp "$fixture" "$UVM_FIXTURE_DIR/$want/install.sh"; }
case "$LOCKRACE_PLANT" in
    held) mkdir "$lock"
          printf 'host=%s pid=%s nonce=lockrace\n' "$(uname -n)" "$$" > "$lock/owner"
          cp "$lock/owner" "$LOCKRACE_DIR/plant.$tag"
          LOCKRACE_BARRIER="$LOCKRACE_RANKS"; export LOCKRACE_BARRIER ;;
    control) ;;
esac
case "${LOCKRACE_LAUNCH:-local}" in
    srun) LOCKRACE_ROLE=rank srun --ntasks="$LOCKRACE_RANKS" --kill-on-bad-exit=0 \
              --distribution=cyclic --cpu-bind=none --export=ALL sh "$0" ;;
    *)    i=1; while [ "$i" -le "$LOCKRACE_RANKS" ]; do
              LOCKRACE_ROLE=rank LOCKRACE_RANK="$i" sh "$0" & i=$((i + 1)); done; wait ;;
esac
v="$root/versions" f="$LOCKRACE_DIR/tree.$tag"
{ n=0; c=0; for e in "$v/$want"/.incoming.*; do [ -e "$e" ] && n=$((n+1)); done
  for e in "$v/$want"/.current.*; do [ -e "$e" ] && c=$((c+1)); done
  echo "nested_staging=$n nested_current=$c"
  s=0; for e in "$v"/.incoming.*; do [ -e "$e" ] && s=$((s+1)); done; echo "stray_staging=$s"
  [ "$(ls -A "$v/$want" 2>/dev/null | tr '\n' ' ')" = 'uv uvx ' ] && echo dist_ok=1 || echo dist_ok=0
  [ "$(readlink "$root/current")" = "versions/$want" ] && [ -x "$root/current/uv" ] \
      && echo current_ok=1 || echo current_ok=0; } > "$f"
# plant check: plant.<tag> present -> plantok.<tag> iff ls -A "$lock" = owner and cmp -s; else leftlock as today
```

`LOCKRACE_BARRIER_TICKS` is 100 locally and 500 under `srun`, where task start spreads across nodes.
The `held` export is the only place the barrier is armed, so `control` and `--pin` bursts pay nothing.

**Driver summary (stdout, key=value, `> "$LOCKRACE_SHARED/summary.<scenario>"`):** `scenario=`,
`ranks=`, `bursts=`, `nodes=` (distinct `node.*` contents, a count only), `wall=`,
`rc_hist=0:N[,1:M…]`, `stdout_hist=9.9.9:N[,none:M]` (field 2 of each `out`),
`installer_entries=`, `concurrent_installers=`, `concurrent_bursts=`, the five tree keys summed,
`bad_trees=`, `plant_intact=B/B` (this boolean stands in for the owner line's hostname),
`locks_left_standing=`, `progress=`. These are counts and relative names only. Never use `--keep`
on a cluster: it prints a path.

**srun assumptions:** inside an allocation, `srun --ntasks=N --kill-on-bad-exit=0
--distribution=cyclic --cpu-bind=none --export=ALL`. For 2 nodes × 64 the allocation is
`--nodes=2 --ntasks=128`; cyclic alternates rank ids across nodes, so neighbors in arrival order
are on different nodes. GPFS: `--nodes=1 --ntasks=64`. `--export=ALL` carries temp_root's scrubbed
environment (`PATH` with the checkout's `bin/`, `UVM_ROOT`, `UVM_INSTALL_URL=file://…`).

**Job body (foreman's, not committed; it holds account, partition and paths):** `--timeout 3
--deadline 15 --launch srun --ranks 128`, run as `control --bursts 4`, `held --bursts 8`, and
`control --pin 6.6.6 --bursts 4`. Expect about 4 s, 10 s and 5 s per burst, roughly 2 min in all;
request 15 min. Read back: every `rc_hist` is all `0`, every `stdout_hist` is the one wanted
version, every tree key is 0, `plant_intact=8/8`, `nodes=2` on Lustre, `concurrent_bursts ≥ 1`
under `held`.

**Sandbox pre-push check of the mode:** `tests/lock-race.sh --plant control --pin 6.6.6 --ranks 16
--bursts 2` and `--plant held --ranks 16 --bursts 2`, both `--launch local`. Note: `--pin` locally
on the finished branch is also a cheap statistical complement to R12's `ln`-shim drive.
