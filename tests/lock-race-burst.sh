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
: "${LOCKRACE_BURST:?}" "${LOCKRACE_PLANT:?}" "${LOCKRACE_RANKS:?}"
: "${LOCKRACE_STALE:?}" "${LOCKRACE_TIMEOUT:?}"

arch=$(uname -m)
root="$UVM_ROOT/$arch"
lock="$root/.install.lock"
tag="$LOCKRACE_RUN.$LOCKRACE_BURST"

# Splice an entry hook into the sandbox's copy of the fixture. temp_root.sh
# copies the fixture per invocation, so nothing tracked is touched -- the same
# technique the previous cycle used to stretch a hold with a sleep. The hook runs
# before the fixture body and releases after it, so the marker it takes is held
# strictly inside the lock hold. A rank that installs sequentially therefore
# cannot overlap another, which is what makes a control run's zero mean
# something rather than merely being a small number.
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
        # A reaped pid on this node is forfeit by the liveness fast path at
        # once; the 2020 timestamp puts the same lock past UVM_LOCK_STALE so the
        # age path reaches the same verdict. Both routes are exercised, and
        # neither depends on the other holding.
        sh -c 'exit 0' & dead=$!
        wait "$dead" 2>/dev/null || true
        mkdir "$lock"
        printf 'host=%s pid=%s nonce=lockrace\n' "$(uname -n)" "$dead" > "$lock/owner"
        touch -t 202001010000.00 "$lock/owner" "$lock"
        ;;
    none)
        # No owner file at all. This is the hot plant, and the reason is that an
        # identity test comparing the recorded line against a re-read of it has
        # nothing to compare: an absent line matches an absent line and the test
        # passes without deciding anything. Reachable in production and not only
        # from old wrappers -- mkdir on NFSv3 and NFSv4.0 is documented not to
        # tell its winner it won, so a rank told EEXIST after a retransmission
        # records no owner and leaves exactly this behind.
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

# A lock left standing once every rank has exited is a user-visible outage for
# the next caller, not an untidy sandbox: mkdir fails, the directory's mtime is
# now, so nothing reads it as stale and the next rank waits out the whole
# timeout. The driver asserts on this before it reports any race counter.
[ -d "$lock" ] && : > "$LOCKRACE_DIR/leftlock.$tag"
exit 0
