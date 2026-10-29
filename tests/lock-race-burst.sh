#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# One burst of tests/lock-race.sh, run inside a temp_root.sh sandbox. Not useful
# on its own: the driver owns the collection directory, the plant and the counts.
#
# The knobs arrive under LOCKRACE_ names and are re-exported onto the inner uv
# call below, because temp_root.sh scrubs every inherited UVM_* variable -- which
# is the behavior that makes the sandbox trustworthy, so the burst works with it
# rather than around it.
set -u
: "${UVM_ROOT:?}" "${UVM_FIXTURE_DIR:?}" "${LOCKRACE_DIR:?}" "${LOCKRACE_RUN:?}"
: "${LOCKRACE_BURST:?}" "${LOCKRACE_PLANT:?}" "${LOCKRACE_RANKS:?}" "${LOCKRACE_TIMEOUT:?}"
# Optional: LOCKRACE_PIN (a version to pin) and LOCKRACE_LAUNCH (local or srun).

arch=$(uname -m)
root="$UVM_ROOT/$arch"
lock="$root/.install.lock"
tag="$LOCKRACE_RUN.$LOCKRACE_BURST"
want="${LOCKRACE_PIN:-9.9.9}"
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(CDPATH='' cd -- "$here/.." && pwd -P)

# One rank: a single `uv --version`, run here in a subshell under --launch local,
# or as this script re-executed by srun on any node of the allocation.
#
# The uv on PATH must be the wrapper under test. temp_root.sh puts this
# checkout's bin/ first, but a compute node can carry a user-installed uv, and a
# launch environment that reordered PATH would run that one and report its
# answers as the wrapper's. Such a rank runs nothing and records `nowrapper` as
# its status, so it can only ever count against the run.
#
# The node and the bash that runs the wrapper are recorded after the call, so
# the forks that read them do not spread the ranks' arrival at the lock. The
# driver turns them into counts and version numbers; it never prints a name.
rank() {
    _r="$1"
    : > "$LOCKRACE_DIR/live.rank.$tag.$_r"
    if [ "$(command -v uv)" = "$repo/bin/uv" ]; then
        if [ -n "${LOCKRACE_PIN:-}" ]; then
            UVM_PIN="$LOCKRACE_PIN" UVM_FIXTURE_VERSION="$LOCKRACE_PIN"
            export UVM_PIN UVM_FIXTURE_VERSION
        fi
        LOCKRACE_RANK="$_r" LOCKRACE_TAG="$tag" UVM_LOCK_TIMEOUT="$LOCKRACE_TIMEOUT" \
            uv --version > "$LOCKRACE_DIR/out.$tag.$_r" 2> "$LOCKRACE_DIR/err.$tag.$_r"
        echo $? > "$LOCKRACE_DIR/rc.$tag.$_r"
        _w=wrapper
    else
        echo nowrapper > "$LOCKRACE_DIR/rc.$tag.$_r"
        _w=other
    fi
    # shellcheck disable=SC2016  # expanded by the inner bash, not this shell
    _b=$(bash -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null) || _b=''
    printf '%s %s %s\n' "$(uname -n)" "${_b:-none}" "$_w" > "$LOCKRACE_DIR/who.$tag.$_r"
    rm -f "$LOCKRACE_DIR/live.rank.$tag.$_r"
}

if [ "${LOCKRACE_ROLE:-}" = rank ]; then
    : "${SLURM_PROCID:?a rank re-executed by srun needs SLURM_PROCID}"
    rank "$((SLURM_PROCID + 1))"
    exit 0
fi

# --pin: select a version other than the one already current. One unhooked
# install puts 9.9.9 in place first, so no installer marker is written for it,
# then the hooked fixture is copied to the pinned version's URL below and every
# rank asks for that version.
if [ -n "${LOCKRACE_PIN:-}" ]; then
    uv --version >/dev/null 2>&1 || : > "$LOCKRACE_DIR/warmfail.$tag"
fi

# Splice an entry hook into the sandbox's copy of the fixture. temp_root.sh
# copies the fixture per invocation, so nothing tracked is touched -- the same
# technique the previous cycle used to stretch a hold with a sleep. The hook runs
# before the fixture body and releases after it, so the marker it takes is held
# strictly inside the lock hold. A rank that installs sequentially therefore
# cannot overlap another, which is what makes a control run's zero mean
# something rather than merely being a small number.
#
# Under a held plant the hook also holds every installer at a barrier after the
# fixture body, until all ranks have arrived or LOCKRACE_BARRIER_TICKS polls of
# 10 ms have passed. The ranks then publish together. Without it the fixture
# installers finish spread over about 100 ms and the check-to-rename window in
# the publish is one fork wide, so concurrent publishes rarely collide and a red
# state built on that rate needs dozens of bursts. Nothing in bin/ is touched.
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
if [ -n "${LOCKRACE_BARRIER:-}" ]; then
  : > "$LOCKRACE_BARRIER_DIR/$_lr_id"
  _lr_n=0
  while [ "$_lr_n" -lt "${LOCKRACE_BARRIER_TICKS:-100}" ]; do
    set -- "$LOCKRACE_BARRIER_DIR"/*
    [ "$#" -ge "$LOCKRACE_BARRIER" ] && break
    sleep 0.01 2>/dev/null || sleep 1
    _lr_n=$((_lr_n + 1))
  done
fi
sleep 0.05 2>/dev/null || true
[ -z "$_lr_held" ] || rmdir "$LOCKRACE_DIR/marker.$LOCKRACE_TAG" 2>/dev/null || true
rm -f "$LOCKRACE_DIR/live.inst.$LOCKRACE_TAG.$_lr_id"
POST
} > "$fixture.hooked"
mv "$fixture.hooked" "$fixture"
chmod 0755 "$fixture"
if [ -n "${LOCKRACE_PIN:-}" ]; then
    mkdir -p "$UVM_FIXTURE_DIR/$want"
    cp "$fixture" "$UVM_FIXTURE_DIR/$want/install.sh"
fi

mkdir -p "$root"
case "$LOCKRACE_PLANT" in
    held)
        # A lock whose holder is this burst shell, alive for the whole burst and
        # never releasing. Every rank waits out LOCKRACE_TIMEOUT and proceeds
        # without the lock, so the ranks install and publish concurrently. The
        # copy lets the driver show that no rank removed or rewrote the plant.
        mkdir "$lock"
        printf 'host=%s pid=%s nonce=lockrace\n' "$(uname -n)" "$$" > "$lock/owner"
        cp "$lock/owner" "$LOCKRACE_DIR/plant.$tag"
        # The arrivals get a directory of their own: every installer globs it
        # every 10 ms, and globbing the collection directory, which grows by
        # several hundred files a burst, slowed the polls until the barrier no
        # longer released the ranks together. Measured at 64 ranks against a
        # bare `mv` publish: nesting in about half of a run's first 16 bursts and
        # in none of the 23 after them; with the arrivals kept apart, in 31 of
        # 40 bursts throughout.
        # Under srun the ranks start spread across nodes, so the barrier waits
        # up to 500 polls rather than 100.
        LOCKRACE_BARRIER="$LOCKRACE_RANKS" LOCKRACE_BARRIER_DIR="$LOCKRACE_DIR/arr.$tag"
        LOCKRACE_BARRIER_TICKS=100
        [ "${LOCKRACE_LAUNCH:-local}" = srun ] && LOCKRACE_BARRIER_TICKS=500
        mkdir "$LOCKRACE_BARRIER_DIR"
        export LOCKRACE_BARRIER LOCKRACE_BARRIER_DIR LOCKRACE_BARRIER_TICKS
        ;;
    control) ;;
esac

case "${LOCKRACE_LAUNCH:-local}" in
    srun)
        # --export=ALL carries temp_root.sh's scrubbed environment to every
        # node: PATH with this checkout's bin/ first, UVM_ROOT, and the file://
        # installer URL. srun's own diagnostics stay in the collection
        # directory, and a failed launch is counted, never named.
        LOCKRACE_ROLE=rank srun --ntasks="$LOCKRACE_RANKS" --kill-on-bad-exit=0 \
            --distribution=cyclic --cpu-bind=none --export=ALL \
            sh "$here/lock-race-burst.sh" >/dev/null 2> "$LOCKRACE_DIR/srun.$tag" \
            || : > "$LOCKRACE_DIR/launchfail.$tag"
        ;;
    *)
        i=1
        while [ "$i" -le "$LOCKRACE_RANKS" ]; do
            ( rank "$i" ) &
            i=$((i + 1))
        done
        wait
        ;;
esac

# The tree each burst left, recorded here because temp_root.sh removes the
# sandbox as soon as this script exits. A correct tree holds exactly one
# distribution at versions/<want>, with no staging copy or swap link nested
# inside it, no staging copy beside it, and `current` resolving to it.
v="$root/versions"
{
    n=0; for e in "$v/$want"/.incoming.*; do [ -e "$e" ] && n=$((n + 1)); done
    echo "nested_staging=$n"
    # A nested swap link is relative, so it dangles: test the link, not its target.
    n=0; for e in "$v/$want"/.current.*; do [ -L "$e" ] && n=$((n + 1)); done
    echo "nested_current=$n"
    n=0; for e in "$v"/.incoming.*; do [ -e "$e" ] && n=$((n + 1)); done
    echo "stray_staging=$n"
    # shellcheck disable=SC2012  # every name in the tree is the wrapper's own
    if [ "$(ls -A "$v/$want" 2>/dev/null | tr '\n' ' ')" = 'uv uvx ' ]; then echo dist_ok=1
    else echo dist_ok=0
    fi
    if [ "$(readlink "$root/current" 2>/dev/null)" = "versions/$want" ] && [ -x "$root/current/uv" ]; then
        echo current_ok=1
    else echo current_ok=0
    fi
} > "$LOCKRACE_DIR/tree.$tag"

# A lock left standing once every rank has exited is a user-visible outage for
# the next caller: mkdir fails and every later call waits out the whole timeout.
# Under a held plant the plant itself is expected to stand, untouched: only its
# own directory with only its own owner line, byte-identical to the copy.
if [ -f "$LOCKRACE_DIR/plant.$tag" ] && [ "$(ls -A "$lock" 2>/dev/null)" = owner ] \
        && cmp -s "$lock/owner" "$LOCKRACE_DIR/plant.$tag"; then
    : > "$LOCKRACE_DIR/plantok.$tag"
elif [ -d "$lock" ]; then
    : > "$LOCKRACE_DIR/leftlock.$tag"
fi
exit 0
