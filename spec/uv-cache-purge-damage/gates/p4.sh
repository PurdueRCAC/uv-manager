#!/bin/sh
# P4 gate: the cross-node drive (R6). Local half: the drive's srun guard, the
# flock key, and U at 16 ranks on the large cache. Evidence half: the
# foreman's two jobs on a Lustre scratch, 2 nodes x 64 ranks, copied unedited
# into evidence/lustre.txt.
# Real uv and network for the local half: pypi.org, files.pythonhosted.org,
# releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
grep -q 'REPAIRRACE_ROLE:-}" = flock' tests/repair-race.sh || { echo "FAIL: P4 Run A has not landed" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
fail() { echo "FAIL: $*" >&2; exit 1; }
o=$(mktemp -d "${TMPDIR:-/tmp}/ucpd-p4.XXXXXX") || fail "no scratch directory"
key() { sed -n "s/^$1=//p" "$2" | tail -n 1; }
# Local half.
r=0; (unset REPAIRRACE_SHARED; tests/repair-race.sh --scenario U --launch srun > /dev/null 2>&1) || r=$?
[ "$r" = 2 ] || fail "--launch srun without REPAIRRACE_SHARED exited $r, expected 2"
tests/repair-race.sh --scenario U --ranks 16 --uv-bin "$u" --large-cache --summary "$o/U.txt" > /dev/null 2> "$o/U.err" \
    || { cat "$o/U.err" "$o/U.txt" >&2; fail "repair-race U x16"; }
[ "$(key flock "$o/U.txt")" = not-measured ] || [ "$(key flock "$o/U.txt")" = unknown ] || fail "M4: a local launch measured flock"
for k in walk_s cache_files live_entries record_lines link_mode flock rebuilt; do
    [ -n "$(key "$k" "$o/U.txt")" ] || fail "R6: the summary has no $k"
done
# M1: the walk is timed on a cache of tens of thousands of RECORD lines.
[ "$(key record_lines "$o/U.txt")" -ge 10000 ] 2>/dev/null || fail "M1: record_lines=$(key record_lines "$o/U.txt"), expected the large cache"
# Evidence half.
e=spec/uv-cache-purge-damage/evidence/lustre.txt
[ -f "$e" ] || fail "cluster evidence $e not recorded yet"
if grep -q / "$e"; then fail "the evidence carries a path"; fi
awk -v d="$o" '/^scenario=/ { f = d "/ev." substr($0, 10) } f { print > f }' "$e"
for s in U S ukill; do
    f="$o/ev.$s"; [ -f "$f" ] || fail "R6: no $s summary in the evidence"
    for kv in launch=srun ranks=128 nodes=2 progress=ok exit=0; do
        [ "$(key "${kv%%=*}" "$f")" = "${kv#*=}" ] || fail "R6: $s: ${kv%%=*}=$(key "${kv%%=*}" "$f"), expected ${kv#*=}"
    done
    case "$(key walk_s "$f")" in *[!0-9.]*|'') fail "R6: $s: walk_s" ;; esac
    [ "$(key live_entries "$f")" -ge 22 ] 2>/dev/null || fail "M1: $s: live_entries=$(key live_entries "$f")"
    [ "$(key record_lines "$f")" -ge 10000 ] 2>/dev/null || fail "M1: $s: record_lines=$(key record_lines "$f"), expected the large cache"
    case "$(key link_mode "$f")" in hardlink|symlink|copy-or-clone) ;; *) fail "R6: $s: link_mode" ;; esac
    case "$(key flock "$f")" in coherent|node-local|absent) ;; *) fail "M4: $s: flock=$(key flock "$f")" ;; esac
done
for s in U S; do
    f="$o/ev.$s"
    for kv in rc_hist=0:128 stdout_hist=expected:128 uv_resolved=wrapper:128 repairs=1 outcomes=1 \
              outcome_kind=ok locks_left=0 restored=1 rebuilt=0; do
        [ "$(key "${kv%%=*}" "$f")" = "${kv#*=}" ] || fail "R6: $s: ${kv%%=*}=$(key "${kv%%=*}" "$f"), expected ${kv#*=}"
    done
done
f="$o/ev.ukill"
for kv in rc_hist=1:127,137:1 timeout_named_lock=127 repairs=0 outcomes=0 locks_left=1 restored=0 \
          doctor_warn_repair_lock=1 clean_rc_hist=0:128 clean_stdout_hist=expected:128 clean_repairs=1 \
          clean_outcomes=1 clean_locks_left=0 clean_restored=1 clean_rebuilt=0; do
    [ "$(key "${kv%%=*}" "$f")" = "${kv#*=}" ] || fail "R6: ukill: ${kv%%=*}=$(key "${kv%%=*}" "$f"), expected ${kv#*=}"
done
grep -q '^\*\*Cluster evidence' spec/uv-cache-purge-damage/PLAN.md || fail "PLAN.md records no cluster evidence"
echo "P4 ok"
