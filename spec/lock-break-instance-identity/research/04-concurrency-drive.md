# 04 — The concurrency drive

Prototyped, run and measured for GOAL **R1** and **R2**. Everything marked **measured** was driven on
this machine (macOS 25 / APFS, Apple silicon, `/bin/sh` = bash 3.2.57) against copies of the tree
outside the working directory: `$probe/repo` at `634caaa` unmodified, and `$probe/noguard` with the
identity test at `bin/uv-manager:458` replaced by `if true; then`. Nothing tracked was touched. The
prototype is two POSIX `sh` files, 183 + 89 lines, reproduced below in full.

Totals across the runs quoted here: **318 planted bursts, 20 352 planted ranks, 8 control bursts, 512
control ranks, and zero drive-invalid exits** outside the two deliberate injections.

## Findings first

1. **The straggler problem is solved by putting collection state outside the sandbox and requiring
   every writer to register liveness.** Ranks and installers create a `live.*` marker and clear it on
   exit; the driver polls to quiescence after each burst and exits **3 with empty stdout** if anything
   is still standing at the deadline. A second, independent guard counts each burst *at its own time*
   and recounts every burst at the end, so a write that lands after its burst closed is named rather
   than absorbed. Both fire. **Measured:** `--straggler` (a detached installer child) → rc 3, 0 bytes
   on stdout, `live.inst.41288.1.straggler` named on stderr; `--late 3` (a late write that registers
   no liveness) → rc 3, 0 bytes on stdout, `concurrent 0 -> 2`.
2. **A robbed lock is observable from outside with no instrumentation of the script, and the better
   observable is not the one `05` expected.** `uvm_unlock`'s own note at `bin/uv-manager:266`,
   `provisioning lock is no longer ours, leaving it in place`, fires exactly when a break removed an
   instance it never judged *after* ownership was recorded — which is R3's target and the case that
   produces two installers. The narrower ENOENT case (robbed inside the 0.10 ms acquire window) is
   visible too, because the redirect at `:351` deliberately does not suppress the shell's diagnostic.
   Two counters, both grepped from per-rank stderr. **Measured:** `stolen_holds` tracked
   `concurrent_installers` **1:1 in every run**, and both were 0 across 512 control ranks. This
   answers `05` §4's "counting robbed locks needs a counter in the script" — it does not.
3. **The tracked fixture needs no change.** `temp_root.sh` copies it into the sandbox per invocation,
   so the burst script splices an entry hook into `$UVM_FIXTURE_DIR/install.sh` — the same technique
   `lock-ownership-and-hold-time/PLAN.md` used for a sleep. The hook takes a marker directory before
   the fixture body and releases it after, so the marker is held strictly *inside* the lock hold and a
   sequentially serialized installer cannot overlap. That is what makes the control's zero mean
   something.
4. **Attribution must be per burst.** Confirmed independently of `05` finding 5, and by the same
   mechanism: in a red burst the rank that installs often emitted no break note, because it won
   `mkdir` on a lock somebody *else* broke. The drive splits `concurrent` into `via_break` and
   `no_break_in_burst`. **Measured:** `no_break_in_burst = 0` in all 318 planted bursts, and the
   control's legitimate single entry is correctly labelled with `break_notes=0`.
5. **The red state is confirmed, and cycle 3's figures reproduce.** The owner-less plant is the hot
   one, at 4.0% of ranks against 0.30% with an owner — a 13x ratio where the GOAL says 4.5x.
6. **The P8 guard at `:458` buys about a third, not an order of magnitude.** Matched A/B at 3840 ranks
   per cell: removing it moves the owner-less plant 165 → 214 concurrent entries (2.5σ) and the
   owner-carrying plant 9 → 14 (1.0σ, not significant at that size). The drive reaches the race, and
   the guard is measurably far from closing either case.
7. **A gate is affordable.** `control×5 + none×12 + owner×40`, all at 64 ranks, costs **103 s** and
   leaves a false green of 3.5e-4 on the owner plant and 1.2e-11 on the owner-less one at the measured
   rates. Per burst: 1.8 s.
8. **Standalone `sh`, no runner.** 272 lines, `shellcheck -s sh --severity=style` clean, no bats, no
   corpus, no `verify:` glue beyond the exit code.

## Measured — red state against `main` (HEAD `634caaa`, guard present)

`concurrent` is a marker overlap inside `install.sh`; `stolen` is `:266`; `robbed` is the ENOENT
diagnostic from `:351`; `red bursts` is bursts with at least one concurrent entry.

| plant | bursts × ranks | concurrent | per-rank *p* | stolen | robbed | red bursts | installer entries |
|---|---|---|---|---|---|---|---|
| `control` | 8 × 64 = 512 | **0** | 0 | 0 | 0 | **0/8** | 8, exactly 1/burst, 0 break notes |
| `owner` | 120 × 64 = 7680 | **23** | **0.30%** | 23 | 11 | **21/120 (0.175)** | 143 |
| `none` | 98 × 64 = 6272 | **254** | **4.05%** | 254 | 42 | **86/98 (0.878)** | 352 |

Against cycle 3, which reported 9 of 29 with an owner and 41 of 61 without: **confirmed in direction
and magnitude.** One representative run of the same size reproduces it closely — `owner` 64×20 gave
3 concurrent of 23 entries (cycle 3: 9 of 29), `none` 64×20 gave 47 of 67 (cycle 3: 41 of 61). Pooled
over more ranks the owner plant settles ~2x below cycle 3's point estimate, which is a sample-size
difference, not a contradiction: 9/1280 has a 95% interval that contains 0.30%.

### Measured — the guard at `:458`, matched A/B, 60 × 64 = 3840 ranks per cell

| plant | wrapper | concurrent | stolen | robbed | red bursts |
|---|---|---|---|---|---|
| `owner` | HEAD | 9 | 9 | 5 | 9/60 |
| `owner` | `:458` → `if true` | **14** | 14 | 6 | 12/60 |
| `none` | HEAD | 165 | 165 | 21 | 53/60 |
| `none` | `:458` → `if true` | **214** | 214 | 38 | 59/60 |

The `none` cell is the sensitivity demonstration R1 asks for (2.5σ on concurrency, 2.2σ on robbery).
The `owner` cell moves the same way and is not significant at 3840 ranks; proving sensitivity there
needs ~10x more ranks, which is not worth the wall clock when the `none` cell already shows it.

## Measured — sizing, with the arithmetic from `lock-ownership-and-hold-time/PLAN.md:392-397`

`P_burst = 1 - (1 - p)^n`; false green after `B` bursts is `(1 - P_burst)^B`.

The model is validated rather than assumed. At `n = 64` and the measured `p = 0.30%`, the owner plant
predicts `P_burst = 0.175`; the drive measured 21/120 = **0.175**. The owner-less plant predicts 0.930
and measured 0.878 — the formula *over*-estimates there, because several stolen holds cluster in one
burst and the independence assumption is optimistic. **Sizing therefore uses the measured `P_burst`,
not the derived one**, which is conservative for both plants.

| plant | *p* | `P_burst` (n=64) | B | false green | wall clock |
|---|---|---|---|---|---|
| `owner` | 0.30% | 0.175 | 20 | 1.9e-2 | 36 s |
| `owner` | 0.30% | 0.175 | **40** | **3.5e-4** | **72 s** |
| `owner` | 0.15% (2x-pessimistic floor) | 0.092 | 40 | 2.0e-2 | 72 s |
| `owner` | 0.15% (floor) | 0.092 | 70 | 1.2e-3 | 126 s |
| `none` | 4.05% | 0.878 | 6 | 3.5e-6 | 11 s |
| `none` | 4.05% | 0.878 | **12** | **1.2e-11** | **22 s** |
| `none` | 2.0% (floor) | 0.726 | 12 | 1.8e-7 | 22 s |
| `control` | — | — | **5** | n/a (asserts zero) | 9 s |

**Recommended gate: `control×5 + none×12 + owner×40`, 64 ranks each — 103 s measured end to end**
(9 + 22 + 72), false green 3.5e-4 / 1.2e-11 at measured rates. Do not economize the owner plant below
40: at 20 bursts a false green is 1.9e-2, which is not a gate. A reviewer who wants 1e-3 at a
2x-pessimistic floor for both plants should ask for `owner×70`, at 126 s and a 160 s total.

## Reasoned — decisions a reader should be able to reject

- **`UVM_LOCK_STALE=10 UVM_LOCK_TIMEOUT=5`, not the shipped 600/180.** The plant is timestamped
  `202001010000.00`, so its age dwarfs any threshold and the forfeiture decision is unchanged; what
  the short knobs buy is a burst bounded at ~5 s instead of 180 s, which is the whole wall-clock
  budget. The cost is that the drive does not exercise the shipped defaults, and that the heartbeat
  beats at 1 s rather than 60 s. R6's own gate covers the defaults.
- **Marker directory rather than timestamps.** `date +%s%N` is a GNU extension and prints `N` on BSD;
  `mkdir` is atomic and needs no clock. Peak occupancy is not computed — "did an entrant find the
  marker held" is the same assertion for this construction and needs no shared counter.
- **Entry count is reported and never asserted.** `05` finding: `versions/` populated with `current`
  broken legitimately gives a second serialized entry. Asserting `installer_entries == bursts` would
  flap.
- **The `:570` double-entry is not constructible from the sandbox**, so the attribution split is
  exercised only in the direction where the answer is known (the control's legitimate entry, labelled
  `break_notes=0`). `05` finding 3 argues `:570` produces no installer entry at all, which if right
  makes `no_break_in_burst` a permanent zero and the split a tripwire rather than a measurement. It
  should still ship: R2 requires the drive to name the other cause if it ever appears.
- **`sleep 0.05` in the hook and `sleep 0.2` in the poll are fractional**, which POSIX does not
  require. Both are guarded (`sleep 0.05 2>/dev/null || true`, `sleep 0.2 … || sleep 1`), so a
  fractional-less `sleep` costs the drive precision and not correctness.

## The interface `tests/` should carry

**Two files, both POSIX `sh`, no runner.** `bats` is a dependency a cluster operator may not have and
this cycle lands one case; the exit code *is* the interface. Split so both are lintable — a driver
holding the burst body in a heredoc is invisible to `sh -n` and to shellcheck.

- `tests/lock-race.sh` — the driver. Runs outside the sandbox, owns the collection directory, the
  bursts, the quiescence guard and the counting.
- `tests/lock-race-burst.sh` — one burst, run *inside* a `temp_root.sh --offline` sandbox. Splices the
  fixture hook, plants the lock, forks the ranks, `wait`s.

```
tests/lock-race.sh [--plant owner|none|control] [--ranks N] [--bursts B]
                   [--deadline S] [--straggler] [--late S] [--quiet] [--keep]
```

Exit **0** no robbed lock and no concurrent installer entry; **1** the race was observed and stdout
names which; **2** usage; **3** the drive could not produce a trustworthy count, with **nothing on
stdout**. Per-burst progress goes to stderr (`--quiet` suppresses it) so stdout carries only the five
summary lines. `--straggler` and `--late` inject the two collection failures so the guards can be
shown to fire; they are the negative tests, not options a gate passes.

`verify:` lines for a phase, red today and green on a fix:

```
tests/lock-race.sh --plant control --ranks 64 --bursts 5  --quiet
tests/lock-race.sh --plant none    --ranks 64 --bursts 12 --quiet
tests/lock-race.sh --plant owner   --ranks 64 --bursts 40 --quiet
tests/lock-race.sh --plant control --ranks 8  --bursts 2 --straggler --deadline 3 --quiet; test $? -eq 3
tests/lock-race.sh --plant control --ranks 8  --bursts 4 --late 3 --quiet; test $? -eq 3
```

**Two same-commit obligations `lint.sh` imposes.** Both files must join the `sh -n` loop at
`.agents/factory/bin/lint.sh:46` and the shellcheck list at `:73`. `--severity=style` includes info,
so `finish()` needs `# shellcheck disable=SC2329` above it (invoked from a trap); with that, both
files are clean.

## The prototype

`tests/lock-race-burst.sh`, in full — it carries all of the technique:

```sh
#!/bin/sh
# One burst of tests/lock-race.sh, run inside a temp_root.sh sandbox. Not useful
# on its own: the driver owns the collection directory, the plant, and the counts.
set -u
: "${UVM_ROOT:?}" "${UVM_FIXTURE_DIR:?}" "${LOCKRACE_DIR:?}" "${LOCKRACE_RUN:?}"
: "${LOCKRACE_BURST:?}" "${LOCKRACE_PLANT:?}" "${LOCKRACE_RANKS:?}"

arch=$(uname -m)
root="$UVM_ROOT/$arch"
lock="$root/.install.lock"
tag="$LOCKRACE_RUN.$LOCKRACE_BURST"

# Splice an entry hook into the sandbox's copy of the fixture. temp_root.sh
# copies the fixture per invocation, so nothing tracked is touched. The hook runs
# before the fixture body and releases after it, so the marker it takes is held
# strictly inside the lock hold: a rank that installs sequentially cannot
# overlap, which is what makes a control run's zero mean something.
fixture="$UVM_FIXTURE_DIR/install.sh"
{
  cat <<'PRE'
_lr_id="${LOCKRACE_RANK:-x}.$$"
: > "$LOCKRACE_DIR/inst.$LOCKRACE_TAG.$_lr_id"
: > "$LOCKRACE_DIR/live.inst.$LOCKRACE_TAG.$_lr_id"
if mkdir "$LOCKRACE_DIR/marker.$LOCKRACE_TAG" 2>/dev/null; then
  _lr_held=1
else
  _lr_held=''
  : > "$LOCKRACE_DIR/over.$LOCKRACE_TAG.$_lr_id"
fi
if [ -n "${LOCKRACE_STRAGGLER:-}" ]; then
  # Detached on purpose: it escapes the burst's wait, which is the shape of the
  # installer child that outlived the sandbox in the prior cycle.
  ( : > "$LOCKRACE_DIR/live.inst.$LOCKRACE_TAG.straggler"
    sleep 30
    rm -f "$LOCKRACE_DIR/live.inst.$LOCKRACE_TAG.straggler" ) >/dev/null 2>&1 &
fi
if [ -n "${LOCKRACE_LATE:-}" ]; then
  # Registers no liveness, so only the end-of-run recount can catch it.
  ( sleep "$LOCKRACE_LATE"
    : > "$LOCKRACE_DIR/over.$LOCKRACE_TAG.late" ) >/dev/null 2>&1 &
fi
PRE
  cat "$fixture"
  cat <<'POST'
sleep 0.05 2>/dev/null || true
[ -z "$_lr_held" ] || rmdir "$LOCKRACE_DIR/marker.$LOCKRACE_TAG" 2>/dev/null || true
rm -f "$LOCKRACE_DIR/live.inst.$LOCKRACE_TAG.$_lr_id"
POST
} > "$fixture.hooked"
mv "$fixture.hooked" "$fixture"
chmod 0755 "$fixture"

mkdir -p "$root"
case "$LOCKRACE_PLANT" in
    owner)
        # A dead pid on this node is forfeit by the fast path instantly; the
        # timestamp puts the same lock past UVM_LOCK_STALE for the age path too.
        sh -c 'exit 0' & dead=$!
        wait "$dead" 2>/dev/null || true
        mkdir "$lock"
        printf 'host=%s pid=%s nonce=lockrace\n' "$(uname -n)" "$dead" > "$lock/owner"
        touch -t 202001010000.00 "$lock/owner" "$lock"
        ;;
    none)
        # No owner file at all: the identity test at bin/uv-manager:458 compares
        # an absent line with an absent line and passes vacuously.
        mkdir "$lock"
        touch -t 202001010000.00 "$lock"
        ;;
    control) ;;
esac

i=1
while [ "$i" -le "$LOCKRACE_RANKS" ]; do
    (
        : > "$LOCKRACE_DIR/live.rank.$tag.$i"
        LOCKRACE_RANK="$i" LOCKRACE_TAG="$tag" \
        UVM_LOCK_STALE="$LOCKRACE_STALE" UVM_LOCK_TIMEOUT="$LOCKRACE_TIMEOUT" \
            uv --version > "$LOCKRACE_DIR/out.$tag.$i" 2> "$LOCKRACE_DIR/err.$tag.$i"
        echo $? > "$LOCKRACE_DIR/rc.$tag.$i"
        rm -f "$LOCKRACE_DIR/live.rank.$tag.$i"
    ) &
    i=$((i + 1))
done
wait
```

`tests/lock-race.sh`, load-bearing parts. Option parsing, `$here`/`$repo` resolution from `$0`, and
the five `printf` summary lines are omitted as mechanical.

```sh
# A robbed lock leaves the shell's own redirect diagnostic and nothing else, and
# strerror text is localized.
LC_ALL=C; export LC_ALL

LOCKRACE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/uvm-lockrace.XXXXXX")
LOCKRACE_RUN="$$"
export LOCKRACE_DIR LOCKRACE_RUN

# shellcheck disable=SC2329  # invoked from the trap below
finish() {
    if [ -n "$keep" ]; then echo "lock-race.sh: keeping $LOCKRACE_DIR" >&2
    else rm -rf "$LOCKRACE_DIR"
    fi
}
trap 'finish' EXIT INT TERM

count() { n=0; for f in "$@"; do [ -e "$f" ] && n=$((n + 1)); done; echo "$n"; }
grepc() {
    pat="$1"; shift; c=0
    for f in "$@"; do
        [ -e "$f" ] || continue
        grep -q -E "$pat" "$f" 2>/dev/null && c=$((c + 1))
    done
    echo "$c"
}

t0=$(date +%s)
b=1
while [ "$b" -le "$bursts" ]; do
    tag="$LOCKRACE_RUN.$b"
    LOCKRACE_BURST="$b" LOCKRACE_PLANT="$plant" LOCKRACE_RANKS="$ranks" \
    LOCKRACE_STRAGGLER="$straggler" LOCKRACE_LATE="$late" \
    LOCKRACE_STALE=10 LOCKRACE_TIMEOUT=5 \
        "$temp_root" --offline sh "$burst" >/dev/null 2>&1

    # Quiescence. Anything still holding a liveness marker at the deadline
    # outlived the collection window, and that is a failed drive rather than a
    # number: say so on stderr and print nothing on stdout.
    w=0
    while :; do
        live=$(count "$LOCKRACE_DIR"/live.*."$tag".*)
        [ "$live" -eq 0 ] && break
        [ "$w" -ge "$((deadline * 5))" ] && break
        sleep 0.2 2>/dev/null || sleep 1
        w=$((w + 1))
    done
    if [ "$live" -ne 0 ]; then
        echo "lock-race.sh: FAIL burst $b -- $live rank(s) or installer(s) outlived the" >&2
        echo "  ${deadline}s collection window, so no count from this run is trustworthy:" >&2
        for f in "$LOCKRACE_DIR"/live.*."$tag".*; do [ -e "$f" ] && echo "    ${f##*/}" >&2; done
        exit 3
    fi

    # Counted here, at this burst's own time, so the recount after the last
    # burst has a real interval in which to notice a late arrival.
    inst=$(count "$LOCKRACE_DIR"/inst."$tag".*)
    over=$(count "$LOCKRACE_DIR"/over."$tag".*)
    # A lock robbed after ownership was recorded. uvm_unlock's own note is the
    # direct observable of a break that removed an instance it never judged, and
    # it needs no instrumentation of the script at all.
    stolen=$(grepc 'provisioning lock is no longer ours' "$LOCKRACE_DIR"/err."$tag".*)
    # A lock robbed inside the 0.10 ms acquire window, before the owner write.
    # bin/uv-manager:351 deliberately does not suppress the shell's diagnostic,
    # which is why this is visible from outside at all.
    robbed=$(grepc 'line [0-9]+: .*\.install\.lock/owner: No such file' "$LOCKRACE_DIR"/err."$tag".*)
    broke=$(grepc 'breaking (stale )?provisioning lock' "$LOCKRACE_DIR"/err."$tag".*)
    timeout=$(grepc 'timed out after' "$LOCKRACE_DIR"/err."$tag".*)
    ownfail=$(grepc 'cannot (record ownership|hold the provisioning lock)' "$LOCKRACE_DIR"/err."$tag".*)
    quota=$(grepc 'check permissions and quota' "$LOCKRACE_DIR"/err."$tag".*)
    nonzero=0
    for f in "$LOCKRACE_DIR"/rc."$tag".*; do
        [ -e "$f" ] || continue
        [ "$(cat "$f")" = 0 ] || nonzero=$((nonzero + 1))
    done

    # Attribution is per burst, not per rank. A rank can win mkdir only because
    # some *other* rank broke the lock, so "this rank printed no break note" is
    # not evidence the break path went untaken. A burst with zero break notes is:
    # any concurrency in it belongs to the pre-existing early-out at
    # bin/uv-manager:570 and not to the break race.
    if [ "$broke" -gt 0 ]; then t_over_break=$((t_over_break + over))
    else                        t_over_nobreak=$((t_over_nobreak + over))
    fi
    # ... accumulate the rest into t_* and red_* ...
    b=$((b + 1))
done
t1=$(date +%s)

# The generation half of the straggler guard. Every burst was counted at its own
# time; recount now and a marker that arrived later has nowhere to hide.
r_inst=$(count "$LOCKRACE_DIR"/inst."$LOCKRACE_RUN".*)
r_over=$(count "$LOCKRACE_DIR"/over."$LOCKRACE_RUN".*)
if [ "$r_inst" -ne "$t_inst" ] || [ "$r_over" -ne "$t_over" ]; then
    echo "lock-race.sh: FAIL -- markers arrived after their burst was counted:" >&2
    echo "  installer entries $t_inst -> $r_inst, concurrent $t_over -> $r_over" >&2
    exit 3
fi

# ... five summary printf lines ...

rc=0
[ "$t_stolen" -eq 0 ] || rc=1
[ "$t_robbed" -eq 0 ] || rc=1
[ "$t_over" -eq 0 ]   || rc=1
exit "$rc"
```

Sample output, `--plant none --ranks 64 --bursts 12`:

```
plant=none ranks=64 bursts=12 total_ranks=768 wall=22s
stolen_holds=32/768 red_bursts=11/12
robbed_winners=8/768 red_bursts=4/12
concurrent_installers=32/768 red_bursts=11/12 via_break=32 no_break_in_burst=0
installer_entries=44 (expect 1/burst) break_notes=151 nonzero_ranks=0
nonzero_causes: timeout=0 ownership=0 quota=0
```

## Verification limits

- **APFS on one machine**, as `GOAL.md` § *Verification limits* already declares. A rate measured here
  is not a rate on Lustre or GPFS, and `p` is what the burst count is derived from.
- **The `owner`-plant sensitivity to `:458` is not statistically established** at 3840 ranks per cell.
  The `none` cell carries that claim.
- **`nonzero_causes` is a census, not an assertion.** Two ranks in 20 352 died — one
  `cannot record ownership`/`cannot hold`, one `check permissions and quota` — both on the no-guard
  variant under the `none` plant. The drive reports them so a red gate cannot be mistaken for the R8
  defect returning, but does not fail on them.
- **The drive cannot see a lock broken across nodes**, which is the case the heartbeat exists for.

---

*Prototype run out of tree at `/tmp/uvm-probe.*/{repo,noguard}`; the working tree was not modified.*
