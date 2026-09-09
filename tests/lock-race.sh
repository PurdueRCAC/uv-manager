#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# Construct a provisioning-lock race and count what it produces.
#
#   tests/lock-race.sh [--plant owner|none|control] [--ranks N] [--bursts B]
#                      [--deadline S] [--straggler] [--late S] [--quiet] [--keep]
#
# Exit 0  no robbed lock and no concurrent installer entry.
# Exit 1  the race was observed; stdout names which counter caught it.
# Exit 2  usage.
# Exit 3  the count is not trustworthy. Nothing on stdout.
# Exit 4  the wrapper made no progress, so the counters mean nothing.
#
# Collection state lives OUTSIDE the sandbox. temp_root.sh removes the sandbox on
# every exit path, so a straggling installer writes into a directory that is
# already gone -- which is how the prior cycle's sentinel emitted
# `violations: No such file or directory` and contaminated every count it made.
# Two independent guards keep a straggler from being reported as a number: every
# rank and every installer registers a liveness marker and clears it on exit, and
# every marker carries a run and burst id, so a burst counted at its own time can
# be recounted at the end and any later arrival named rather than absorbed.
#
# --straggler and --late inject those two failures deliberately, so the guards
# can be shown to fire. --straggler leaves a detached installer child holding a
# liveness marker past the deadline; --late writes a marker after its burst was
# counted, without registering liveness at all.
#
# Burst sizing is arithmetic, not taste. P_burst = 1 - (1-p)^n per burst, and a
# false green after B bursts is (1-P_burst)^B. Measured on APFS at n=64 against
# the wrapper before this fix: p = 0.30% for --plant owner, giving P_burst 0.175
# predicted and 0.175 observed; p = 4.05% for --plant none, giving 0.930
# predicted and 0.878 observed. The observed figure is the one to size against --
# stolen holds cluster within a burst, so independence is optimistic. Hence the
# gate's shape: control x5, none x12 (false green 1.2e-11), owner x40 (3.5e-4),
# about 103 s in total. Do not economize the owner plant: at 20 bursts its false
# green is 1.9e-2, which is not a gate.

set -u

plant=owner ranks=64 bursts=20 deadline=5 straggler='' late='' quiet='' keep=''

while [ $# -gt 0 ]; do
    case "$1" in
        --plant)     plant="${2:?--plant needs owner|none|control}"; shift 2 ;;
        --ranks)     ranks="${2:?--ranks needs a count}"; shift 2 ;;
        --bursts)    bursts="${2:?--bursts needs a count}"; shift 2 ;;
        --deadline)  deadline="${2:?--deadline needs seconds}"; shift 2 ;;
        --straggler) straggler=1; shift ;;
        --late)      late="${2:?--late needs seconds}"; shift 2 ;;
        --quiet)     quiet=1; shift ;;
        --keep)      keep=1; shift ;;
        *) echo "lock-race.sh: unknown option: $1" >&2; exit 2 ;;
    esac
done
case "$plant" in owner|none|control) ;; *) echo "lock-race.sh: bad --plant: $plant" >&2; exit 2 ;; esac

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(CDPATH='' cd -- "$here/.." && pwd -P)
temp_root="$repo/.agents/factory/bin/temp_root.sh"
burst="$here/lock-race-burst.sh"
[ -x "$temp_root" ] || { echo "lock-race.sh: missing $temp_root" >&2; exit 2; }
[ -f "$burst" ]     || { echo "lock-race.sh: missing $burst" >&2; exit 2; }

# A robbed lock is visible only as the shell's own redirect diagnostic, and
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

t_inst=0 t_over=0 t_robbed=0 t_stolen=0 t_broke=0 t_nonzero=0
t_over_break=0 t_over_nobreak=0 t_timeout=0 t_ownfail=0 t_quota=0 t_left=0
red_over=0 red_robbed=0 red_stolen=0
live=0

t0=$(date +%s)
b=1
while [ "$b" -le "$bursts" ]; do
    tag="$LOCKRACE_RUN.$b"
    # Short knobs, not the shipped 600/180. The plant is timestamped to 2020, so
    # its age dwarfs any threshold and the forfeiture decision is unchanged; what
    # these buy is a burst bounded at about 5 s rather than 180. The shipped
    # defaults are covered by the single-download gate instead.
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
    leftlock=$(count "$LOCKRACE_DIR"/leftlock."$tag")
    over=$(count "$LOCKRACE_DIR"/over."$tag".*)
    # A lock robbed after ownership was recorded. uvm_unlock's own note is the
    # direct observable of a break that removed an instance it never judged, so
    # this needs no instrumentation of the wrapper at all.
    stolen=$(grepc 'provisioning lock is no longer ours' "$LOCKRACE_DIR"/err."$tag".*)
    # A lock robbed inside the acquire window, before the owner write landed.
    # That redirect in uvm_acquire_lock deliberately does not suppress the
    # shell's diagnostic, which is the only reason this is observable at all.
    robbed=$(grepc 'line [0-9]+: .*\.install\.lock/owner: No such file' "$LOCKRACE_DIR"/err."$tag".*)
    broke=$(grepc 'provisioning lock is forfeit|breaking (stale )?provisioning lock' "$LOCKRACE_DIR"/err."$tag".*)
    timeout=$(grepc 'timed out after' "$LOCKRACE_DIR"/err."$tag".*)
    ownfail=$(grepc 'cannot (record ownership|hold the provisioning lock)' "$LOCKRACE_DIR"/err."$tag".*)
    quota=$(grepc 'check permissions and quota' "$LOCKRACE_DIR"/err."$tag".*)
    nonzero=0
    for f in "$LOCKRACE_DIR"/rc."$tag".*; do
        [ -e "$f" ] || continue
        [ "$(cat "$f")" = 0 ] || nonzero=$((nonzero + 1))
    done

    # Attribution is per burst, never per rank. A rank can win mkdir only because
    # some *other* rank broke the lock, so "this rank printed no break note" is
    # not evidence that the break path went untaken -- measured at 23 of 32
    # concurrent entries coming from ranks that broke nothing. A burst with no
    # break note anywhere is the other case, and it belongs to one of the
    # break-free routes to a second installer: an explicit force, the
    # absent-lock retry, or a re-download when `current` is missing or dangling
    # while `versions/` is populated. Those are serialized by the lock and
    # produce an extra *entry* without ever producing simultaneity, which is why
    # entries are reported below and never asserted on.
    if [ "$broke" -gt 0 ]; then t_over_break=$((t_over_break + over))
    else                        t_over_nobreak=$((t_over_nobreak + over))
    fi

    [ "$over" -eq 0 ]   || red_over=$((red_over + 1))
    [ "$robbed" -eq 0 ] || red_robbed=$((red_robbed + 1))
    [ "$stolen" -eq 0 ] || red_stolen=$((red_stolen + 1))
    t_inst=$((t_inst + inst));       t_over=$((t_over + over))
    t_robbed=$((t_robbed + robbed)); t_stolen=$((t_stolen + stolen))
    t_broke=$((t_broke + broke));    t_nonzero=$((t_nonzero + nonzero))
    t_timeout=$((t_timeout + timeout)); t_ownfail=$((t_ownfail + ownfail))
    t_quota=$((t_quota + quota)); t_left=$((t_left + leftlock))

    [ -n "$quiet" ] || printf 'burst %-3s installs=%-3s concurrent=%-3s stolen=%-3s robbed=%-3s breaks=%-3s rc!=0=%s\n' \
        "$b" "$inst" "$over" "$stolen" "$robbed" "$broke" "$nonzero" >&2
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

total=$((ranks * bursts))
printf 'plant=%s ranks=%s bursts=%s total_ranks=%s wall=%ss\n' \
    "$plant" "$ranks" "$bursts" "$total" "$((t1 - t0))"
printf 'stolen_holds=%s/%s red_bursts=%s/%s\n'   "$t_stolen" "$total" "$red_stolen" "$bursts"
printf 'robbed_winners=%s/%s red_bursts=%s/%s\n' "$t_robbed" "$total" "$red_robbed" "$bursts"
printf 'concurrent_installers=%s/%s red_bursts=%s/%s via_break=%s no_break_in_burst=%s\n' \
    "$t_over" "$total" "$red_over" "$bursts" "$t_over_break" "$t_over_nobreak"
printf 'installer_entries=%s (expect 1/burst) break_notes=%s nonzero_ranks=%s\n' \
    "$t_inst" "$t_broke" "$t_nonzero"
printf 'nonzero_causes: timeout=%s ownership=%s quota=%s  locks_left_standing=%s/%s\n' \
    "$t_timeout" "$t_ownfail" "$t_quota" "$t_left" "$bursts"

# Progress, asserted before any race verdict. A candidate that declines every
# break makes the lock unbreakable: every rank times out, nothing installs, and
# all three race counters are legitimately zero. Measured on a composition that
# did exactly that, where this drive reported success -- a false green is worse
# than no gate at all.
progress=ok
[ "$t_inst" -ge "$bursts" ] || progress="only $t_inst installer entries for $bursts bursts"
[ "$t_left" -eq 0 ]         || progress="$t_left/$bursts bursts left a lock standing"
[ "$t_nonzero" -eq 0 ]      || progress="$t_nonzero rank(s) exited non-zero"
printf 'progress=%s\n' "$progress"
if [ "$progress" != ok ]; then
    echo "lock-race.sh: the wrapper did not make progress -- this is not a race result" >&2
    exit 4
fi

rc=0
[ "$t_stolen" -eq 0 ] || rc=1
[ "$t_robbed" -eq 0 ] || rc=1
[ "$t_over" -eq 0 ]   || rc=1
exit "$rc"
