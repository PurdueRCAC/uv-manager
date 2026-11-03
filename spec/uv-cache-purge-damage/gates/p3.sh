#!/bin/sh
# P3 gate: no waiter rebuilds what the repair restored (R5), across the local
# race drive's U, S and ukill; F, T, P and kill unchanged and the unset path
# no dearer (R7); the surfaces (R8). Real uv and network: pypi.org,
# files.pythonhosted.org, releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
grep -q '^uvm_repair_cache()' bin/uv-manager || { echo "FAIL: P2 has not landed" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
fail() { echo "FAIL: $*" >&2; exit 1; }
o=$(mktemp -d "${TMPDIR:-/tmp}/ucpd-p3.XXXXXX") || fail "no scratch directory"
key() { sed -n "s/^$1=//p" "$2" | tail -n 1; }
# SCENARIO RANKS [ARG...]: the drive must exit 0 with progress=ok.
race() {
    _s=$1 _n=$2; shift 2
    tests/repair-race.sh --scenario "$_s" --ranks "$_n" --summary "$o/$_s.txt" "$@" > /dev/null 2> "$o/$_s.err" \
        || { cat "$o/$_s.err" "$o/$_s.txt" >&2; fail "repair-race $_s x$_n"; }
    [ "$(key progress "$o/$_s.txt")" = ok ] || fail "$_s: progress=$(key progress "$o/$_s.txt")"
    if grep -q / "$o/$_s.txt"; then fail "$_s: the summary carries a path"; fi
}
cachekeys() {  # SCENARIO PREFIX
    _f="$o/$1.txt"
    [ "$(key "${2}rebuilt" "$_f")" = 0 ] || fail "R5: $1: ${2}rebuilt=$(key "${2}rebuilt" "$_f")"
    case "$(key walk_s "$_f")" in *[!0-9.]*|'') fail "R6: $1: walk_s=$(key walk_s "$_f")" ;; esac
    case "$(key cache_files "$_f")" in *[!0-9]*|'') fail "R6: $1: cache_files" ;; esac
    [ "$(key live_entries "$_f")" -ge 22 ] 2>/dev/null || fail "M1: $1: live_entries=$(key live_entries "$_f"), expected the subjects and 20 others"
    case "$(key link_mode "$_f")" in hardlink|symlink|copy-or-clone) ;; *) fail "R6: $1: link_mode" ;; esac
}
race U 16 --uv-bin "$u"; cachekeys U ''
race S 16 --uv-bin "$u"; cachekeys S ''
race ukill 8 --uv-bin "$u"; cachekeys ukill clean_
[ "$(key restored "$o/ukill.txt")" = 0 ] || fail "ukill: the killed holder had already repaired, so the clean pass proves nothing"
# R7: the interpreter and tool arms as release/0.8.0 has them.
race F 16
race T 8 --uv-bin "$u"
race P 8 --uv-bin "$u"
race kill 8 --uv-bin "$u"
# R7: the unset path costs no more than the base's, 1200 warm calls each.
REPO="$PWD" .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE' || exit 1
set -u
mkdir -p "$UVM_SANDBOX/old/bin"
git -C "$REPO" show 8e03774:bin/uv-manager > "$UVM_SANDBOX/old/bin/uv-manager" || { echo "FAIL: no base wrapper" >&2; exit 1; }
chmod +x "$UVM_SANDBOX/old/bin/uv-manager"; ln -s uv-manager "$UVM_SANDBOX/old/bin/uv"
"$REPO/bin/uv" --version > /dev/null 2>&1 || { echo "FAIL: provisioning the fixture" >&2; exit 1; }
# Three alternating rounds of 400 calls a side; each side's fastest round
# is compared, so load on the machine reads as neither side's cost.
loop() { _i=0; _s=$(date +%s); while [ "$_i" -lt 400 ]; do "$1" --version > /dev/null; _i=$((_i + 1)); done; echo $(( $(date +%s) - _s )); }
old=999 new=999
for r in 1 2 3; do
    t=$(loop "$UVM_SANDBOX/old/bin/uv"); [ "$t" -lt "$old" ] && old=$t
    t=$(loop "$REPO/bin/uv"); [ "$t" -lt "$new" ] && new=$t
done
echo "R7 timing: fastest of three rounds of 400 calls, base ${old}s, this tree ${new}s" >&2
[ "$new" -le $((old + 1)) ] || { echo "FAIL: R7: the unset path costs more than the base's (${new}s against ${old}s)" >&2; exit 1; }
DRIVE
# R8: the surfaces.
if grep -q "Damage inside uv's cache is not checked" README.md; then fail "R8: README.md still concedes cache damage"; fi
for f in README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua; do
    grep -q "uv's cache" "$f" || fail "R8: $f does not name uv's cache"
done
bin/uvm help | grep -q "uv's cache" || fail "R8: uvm help does not name uv's cache"
grep -q "^| \*\*Files inside uv's cache\*\* |" README.md || fail "R8: no purge-table row for partial cache loss"
grep -q 'UV_LINK_MODE=symlink' README.md || fail "R8: README.md does not concede UV_LINK_MODE=symlink"
grep -q 'uv cache clean <package>' README.md && grep -q 'uv-manager clean cache' README.md || fail "R8: README.md does not name the manual remedy and the partial ones"
grep -q 'ukill' AGENTS.md || fail "AGENTS.md's tests paragraph does not name the cache scenarios"
echo "P3 ok"
