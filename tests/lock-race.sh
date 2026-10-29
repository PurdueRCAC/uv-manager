#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# Release bursts of concurrent ranks at the provisioning lock and check the tree
# and the answers they leave.
#
#   tests/lock-race.sh [--plant held|control] [--ranks N] [--bursts B]
#                      [--timeout S] [--deadline S] [--pin VER]
#                      [--launch local|srun] [--summary FILE]
#                      [--straggler] [--late S] [--quiet] [--keep]
#
# --plant held   stands a lock whose holder is alive and never releases. Every
#                rank waits out --timeout (the burst's UVM_LOCK_TIMEOUT), then
#                installs and publishes without the lock, concurrently with the
#                others. The plant must still stand untouched afterwards.
# --plant control  plants nothing. One rank installs under the lock and the
#                rest wait for it: one installer per burst, never two at once.
# --pin VER      installs 9.9.9 first, unhooked, then every rank asks for VER
#                (UVM_PIN): the ranks install and select a version other than
#                the one already current.
# --launch srun  starts the ranks with srun inside a Slurm allocation, so they
#                race from several nodes against one tree on a parallel
#                filesystem. It is never chosen automatically: srun can be a
#                wrapper on a workstation. LOCKRACE_SHARED must name a directory
#                on the filesystem under test, and is the only place the mode
#                looks for one: the scratch variables are not reliably set in a
#                batch job. The sandbox and the collection directory both go
#                there, and the checkout must be on a filesystem every node
#                mounts, because the ranks re-execute the burst by its path.
# --summary FILE writes the result block below to FILE as well as stdout.
#
# The result block is key=value lines holding counts, version numbers and the
# scenario name, and nothing else: no hostname, username or path. A summary
# from a cluster run is committed to a public repository as evidence.
# stdout_hist counts each rank's answer by the version in `uv <ver> (fixture)`,
# and anything else as `other` (or `none` when empty), so a uv that is not the
# wrapper under test cannot pass for it. uv_resolved counts the ranks whose uv
# on PATH was this checkout's wrapper. nodes counts the distinct nodes the
# ranks ran on, and bash lists the bash versions that ran the wrapper. Never
# use --keep on a cluster: it prints a path.
#
# Exit 0  every burst left a correct tree, and every rank exited 0 printing the
#         version it asked for; under control, one installer ran per burst and
#         none ran concurrently.
# Exit 1  a correctness defect; stdout names the counter that caught it.
# Exit 2  usage.
# Exit 3  the count is not trustworthy. Nothing on stdout.
# Exit 4  the wrapper made no progress, or the burst never constructed the race,
#         so the correctness counters mean nothing.
#
# A correct tree holds exactly one distribution at versions/<ver>: no staging
# copy (nested_staging) or swap link (nested_current) inside it, no staging copy
# left beside it (stray_staging), and `current` resolving to it (bad_trees
# counts any burst whose tree is wrong in any way). The burst records the tree
# before temp_root.sh removes the sandbox.
#
# Collection state lives OUTSIDE the sandbox. temp_root.sh removes the sandbox on
# every exit path, so a straggling installer writes into a directory that is
# already gone -- which is how a prior cycle's sentinel emitted
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
# Burst sizing is arithmetic, not taste. A false green after B bursts is
# (1-p)^B for a per-burst detection rate p. Measured on APFS at 64 ranks under
# --plant held, a wrapper whose publish is a bare `mv` onto the version path
# nested its staging copy in 14 of 20 bursts on one run and 31 of 40 on
# another; without the burst's barrier, which makes the ranks publish together,
# the rate was about 1 in 10. The defaults, held x10, put a false green against
# that publish at about 0.3^10, or 6e-6, in about 25 s. The guarded publish left
# a correct tree in 40 of 40 bursts (2560 ranks).

set -u

plant=held ranks=64 bursts=10 timeout=1 deadline=5 straggler='' late='' quiet='' keep=''
pin='' launch=local summary=''

while [ $# -gt 0 ]; do
    case "$1" in
        --plant)     plant="${2:?--plant needs held|control}"; shift 2 ;;
        --ranks)     ranks="${2:?--ranks needs a count}"; shift 2 ;;
        --bursts)    bursts="${2:?--bursts needs a count}"; shift 2 ;;
        --timeout)   timeout="${2:?--timeout needs seconds}"; shift 2 ;;
        --deadline)  deadline="${2:?--deadline needs seconds}"; shift 2 ;;
        --straggler) straggler=1; shift ;;
        --late)      late="${2:?--late needs seconds}"; shift 2 ;;
        --quiet)     quiet=1; shift ;;
        --keep)      keep=1; shift ;;
        --pin)       pin="${2:?--pin needs a version}"; shift 2 ;;
        --launch)    launch="${2:?--launch needs local|srun}"; shift 2 ;;
        --summary)   summary="${2:?--summary needs a file}"; shift 2 ;;
        *) echo "lock-race.sh: unknown option: $1" >&2; exit 2 ;;
    esac
done
case "$plant" in held|control) ;; *) echo "lock-race.sh: bad --plant: $plant (held or control)" >&2; exit 2 ;; esac
case "$launch" in local|srun) ;; *) echo "lock-race.sh: bad --launch: $launch (local or srun)" >&2; exit 2 ;; esac
case "$pin" in
    '') ;;
    9.9.9) echo "lock-race.sh: --pin 9.9.9 is the version already current; pin another" >&2; exit 2 ;;
    *[!0-9.]*|.*|*.) echo "lock-race.sh: bad --pin: $pin (a version such as 6.6.6)" >&2; exit 2 ;;
esac
if [ "$launch" = srun ]; then
    if [ -z "${LOCKRACE_SHARED:-}" ] || [ ! -d "$LOCKRACE_SHARED" ]; then
        echo "lock-race.sh: --launch srun needs LOCKRACE_SHARED to name a directory on the filesystem under test" >&2
        exit 2
    fi
    command -v srun >/dev/null 2>&1 || { echo "lock-race.sh: --launch srun needs srun on PATH, inside a Slurm allocation" >&2; exit 2; }
    TMPDIR="$LOCKRACE_SHARED"; export TMPDIR
fi
if [ -n "$summary" ]; then
    # Emptied now, so a run that stops before its result block cannot leave an
    # earlier run's summary standing under its name.
    : > "$summary" || { echo "lock-race.sh: cannot write --summary $summary" >&2; exit 2; }
fi
if [ -n "$pin" ]; then scenario=pin; else scenario="$plant"; fi

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(CDPATH='' cd -- "$here/.." && pwd -P)
temp_root="$repo/.agents/factory/bin/temp_root.sh"
burst="$here/lock-race-burst.sh"
[ -x "$temp_root" ] || { echo "lock-race.sh: missing $temp_root" >&2; exit 2; }
[ -f "$burst" ]     || { echo "lock-race.sh: missing $burst" >&2; exit 2; }

# The wrapper's answers are compared as text, and strerror text is localized.
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
# The value of KEY in a tree record, or 0 when the record or the key is missing.
treeval() { v=$(sed -n "s/^$1=//p" "$2" 2>/dev/null); echo "${v:-0}"; }
# One value per line on stdin, as value:count pairs joined by commas.
hist() { sort | uniq -c | awk '{ printf "%s%s:%s", (NR > 1 ? "," : ""), $2, $1 } END { print "" }'; }

want="${pin:-9.9.9}"
t_inst=0 t_over=0 t_cbursts=0 t_nonzero=0 t_wrong=0 t_left=0 t_plantok=0
t_nstage=0 t_ncur=0 t_stray=0 t_bad=0 t_warmfail=0 t_launchfail=0
live=0

t0=$(date +%s)
b=1
while [ "$b" -le "$bursts" ]; do
    tag="$LOCKRACE_RUN.$b"
    LOCKRACE_BURST="$b" LOCKRACE_PLANT="$plant" LOCKRACE_RANKS="$ranks" \
    LOCKRACE_STRAGGLER="$straggler" LOCKRACE_LATE="$late" LOCKRACE_TIMEOUT="$timeout" \
    LOCKRACE_PIN="$pin" LOCKRACE_LAUNCH="$launch" \
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
    leftlock=$(count "$LOCKRACE_DIR"/leftlock."$tag")
    plantok=$(count "$LOCKRACE_DIR"/plantok."$tag")
    # Every rank's status, answer and resolved uv, missing ones included: a rank
    # that never ran is a rank that did not exit 0.
    nonzero=0 wrong=0 i=1
    while [ "$i" -le "$ranks" ]; do
        r=$(cat "$LOCKRACE_DIR/rc.$tag.$i" 2>/dev/null)
        [ "$r" = 0 ] || nonzero=$((nonzero + 1))
        echo "${r:-none}" >> "$LOCKRACE_DIR/hist.rc"
        o=$(cat "$LOCKRACE_DIR/out.$tag.$i" 2>/dev/null)
        [ "$o" = "uv $want (fixture)" ] || wrong=$((wrong + 1))
        case "$o" in
            '') o=none ;;
            "uv "*" (fixture)")
                o="${o#uv }"; o="${o% (fixture)}"
                case "$o" in ''|*[!0-9.]*) o=other ;; esac ;;
            *) o=other ;;
        esac
        echo "$o" >> "$LOCKRACE_DIR/hist.out"
        # node, bash version, wrapper|other: three words, split on purpose.
        who=$(cat "$LOCKRACE_DIR/who.$tag.$i" 2>/dev/null) || who=''
        # shellcheck disable=SC2086
        set -- $who
        echo "${1:-none}" >> "$LOCKRACE_DIR/hist.node"
        echo "${2:-none}" >> "$LOCKRACE_DIR/hist.bash"
        echo "${3:-none}" >> "$LOCKRACE_DIR/hist.path"
        i=$((i + 1))
    done
    [ ! -e "$LOCKRACE_DIR/warmfail.$tag" ] || t_warmfail=$((t_warmfail + 1))
    if [ -e "$LOCKRACE_DIR/launchfail.$tag" ]; then
        t_launchfail=$((t_launchfail + 1))
        # srun's own words go to stderr only: they can name nodes, and the
        # result block is meant for a public repository.
        echo "lock-race.sh: burst $b -- srun exited non-zero:" >&2
        sed 's/^/    /' "$LOCKRACE_DIR/srun.$tag" >&2
    fi
    tf="$LOCKRACE_DIR/tree.$tag"
    nstage=$(treeval nested_staging "$tf")
    ncur=$(treeval nested_current "$tf")
    stray=$(treeval stray_staging "$tf")
    if [ "$(treeval dist_ok "$tf")" = 1 ] && [ "$(treeval current_ok "$tf")" = 1 ]; then bad=0
    else bad=1
    fi

    [ "$over" -eq 0 ] || t_cbursts=$((t_cbursts + 1))
    t_inst=$((t_inst + inst));          t_over=$((t_over + over))
    t_nonzero=$((t_nonzero + nonzero)); t_wrong=$((t_wrong + wrong))
    t_left=$((t_left + leftlock));      t_plantok=$((t_plantok + plantok))
    t_nstage=$((t_nstage + nstage));    t_ncur=$((t_ncur + ncur))
    t_stray=$((t_stray + stray));       t_bad=$((t_bad + bad))

    [ -n "$quiet" ] || printf 'burst %-3s installs=%-3s concurrent=%-3s nested=%s/%s stray=%s bad_tree=%s rc!=0=%s wrong_stdout=%s\n' \
        "$b" "$inst" "$over" "$nstage" "$ncur" "$stray" "$bad" "$nonzero" "$wrong" >&2
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

# One key=value per line, so a reader can grep for any key by name. Every value
# is a count, a version number or a fixed word; the node names are reduced to
# their number here and go no further.
total=$((ranks * bursts))
if [ "$plant" = held ]; then intact="$t_plantok/$bursts"; else intact=0/0; fi
nodes=$(grep -v -x none "$LOCKRACE_DIR/hist.node" | sort -u | wc -l | tr -d ' ')
result=$(printf '%s\n' "scenario=$scenario" "launch=$launch" "plant=$plant" "pin=${pin:-none}" \
    "ranks=$ranks" "bursts=$bursts" "total_ranks=$total" "nodes=$nodes" \
    "bash=$(grep -v -x none "$LOCKRACE_DIR/hist.bash" | sort -u | paste -s -d , -)" \
    "timeout=$timeout" "wall=$((t1 - t0))" \
    "rc_hist=$(hist < "$LOCKRACE_DIR/hist.rc")" \
    "stdout_hist=$(hist < "$LOCKRACE_DIR/hist.out")" \
    "uv_resolved=$(hist < "$LOCKRACE_DIR/hist.path")" \
    "launch_failures=$t_launchfail/$bursts" \
    "installer_entries=$t_inst" "concurrent_installers=$t_over/$total" \
    "concurrent_bursts=$t_cbursts/$bursts" \
    "nonzero_ranks=$t_nonzero/$total" "wrong_stdout=$t_wrong/$total" \
    "nested_staging=$t_nstage" "nested_current=$t_ncur" "stray_staging=$t_stray" \
    "bad_trees=$t_bad/$bursts" \
    "plant_intact=$intact" "locks_left_standing=$t_left/$bursts")

# Progress, asserted before any correctness verdict. A wrapper that installs
# nothing leaves no tree to be wrong, and a held burst in which no two installers
# overlapped never constructed a concurrent publish, so a clean tree from it says
# nothing about the publish. Non-zero ranks are a correctness defect, not a
# progress one: against an unguarded publish they occur, and counting them here
# would make the same defect read as 4 on one run and 1 on the next.
progress=ok
[ "$t_inst" -ge "$bursts" ] || progress="only $t_inst installer entries for $bursts bursts"
[ "$t_warmfail" -eq 0 ]     || progress="the unpinned first install failed in $t_warmfail/$bursts bursts"
[ "$t_launchfail" -eq 0 ]   || progress="srun failed to launch the ranks in $t_launchfail/$bursts bursts"
[ "$t_left" -eq 0 ]         || progress="$t_left/$bursts bursts left a lock standing"
if [ "$plant" = held ]; then
    [ "$t_plantok" -eq "$bursts" ] || progress="the plant stood intact after only $t_plantok/$bursts bursts"
    [ "$t_cbursts" -ge 1 ]         || progress="no burst ran two installers at once, so no publish raced"
fi
result=$(printf '%s\nprogress=%s' "$result" "$progress")
printf '%s\n' "$result"
[ -z "$summary" ] || printf '%s\n' "$result" > "$summary"
if [ "$progress" != ok ]; then
    echo "lock-race.sh: the wrapper did not make progress -- this is not a race result" >&2
    exit 4
fi

rc=0
[ "$t_nstage" -eq 0 ]  || rc=1
[ "$t_ncur" -eq 0 ]    || rc=1
[ "$t_stray" -eq 0 ]   || rc=1
[ "$t_bad" -eq 0 ]     || rc=1
[ "$t_wrong" -eq 0 ]   || rc=1
[ "$t_nonzero" -eq 0 ] || rc=1
if [ "$plant" = control ]; then
    [ "$t_inst" -eq "$bursts" ] || rc=1
    [ "$t_over" -eq 0 ]         || rc=1
fi
exit "$rc"
