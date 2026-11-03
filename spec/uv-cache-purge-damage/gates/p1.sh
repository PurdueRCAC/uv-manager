#!/bin/sh
# P1 gate: doctor reports each damaged live cache entry, writes nothing, and
# never walks an archive no link reaches (R2). Real uv and network: pypi.org,
# files.pythonhosted.org, releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
SEED_UV="$u" GATES="$PWD/spec/uv-cache-purge-damage/gates" .agents/factory/bin/temp_root.sh sh -s <<'DRIVE' || exit 1
set -u
. "$GATES/lib.sh"
seed; subjects
# Healthy: no FAIL, rc 0.
uvm doctor > "$o/h.out" 2>&1 || { cat "$o/h.out" >&2; fail "R2: doctor exits non-zero on a healthy cache"; }
if grep -q '^FAIL' "$o/h.out"; then cat "$o/h.out" >&2; fail "R2: a FAIL on a healthy cache"; fi
# SHAPE KIND: damage one entry, then doctor must exit 1 with a FAIL naming it.
n=0
shape() {
    restore; n=$((n + 1))
    case "$2" in
        script) e=$(senv tqdm); p=tqdm ;; uvx) e=$(xlink tqdm); p=tqdm ;;
        flake8) e=$(xlink flake8); p=pyflakes ;; ruff) e=$(xlink ruff); p=ruff ;;
        wheel) e=$(wlink tqdm); p=tqdm ;;
    esac
    [ -n "$e" ] || fail "no $2 entry to damage"
    r=$(real "$e")
    case "$2" in wheel) sp="$r" ;; *) sp="$r/lib/python3.12/site-packages" ;; esac
    case "$1" in
        module) echo "$sp/$p/$( [ "$p" = pyflakes ] && echo checker.py || echo std.py )" | purge ;;
        distinfo) files "$sp"/$p-*.dist-info | purge ;;
        record) echo "$sp"/$p-*.dist-info/RECORD | purge ;;
        metadata) echo "$sp"/$p-*.dist-info/METADATA | purge ;;
        third) files "$r" | nth 3 | purge ;;
        all) files "$r" | purge ;;
        pyvenv) echo "$r/pyvenv.cfg" | purge ;;
        exe) echo "$r/bin/ruff" | purge ;;
    esac
    if uvm doctor > "$o/d$n.out" 2>&1; then cat "$o/d$n.out" >&2; fail "R2: $1 on $2: doctor exits 0"; fi
    grep -qF "FAIL  cache entry $e " "$o/d$n.out" || { cat "$o/d$n.out" >&2; fail "R2: $1 on $2: no FAIL naming $e"; }
}
for k in script uvx; do for s in module distinfo record metadata third pyvenv; do shape "$s" "$k"; done; done
shape module flake8; shape distinfo flake8; shape pyvenv flake8
shape exe ruff; shape record ruff
for s in module distinfo record metadata third all; do shape "$s" wheel; done
# Read-only: a damaged tree lists the same after doctor, nothing newer.
restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
treelist > "$o/t0"; : > "$UVM_SANDBOX/mark"
uvm doctor > /dev/null 2>&1
treelist > "$o/t1"
cmp -s "$o/t0" "$o/t1" || { diff "$o/t0" "$o/t1" >&2; fail "R2: doctor changed the tree"; }
[ -z "$(find "$UVM_ROOT" -newer "$UVM_SANDBOX/mark")" ] || fail "R2: doctor wrote under UVM_ROOT"
# The walk lists each entry and resolves RECORD's paths by name; each shape
# reads as testing every path did: a console script reached through ../, a
# file two directories down, a RECORD path that is a link (dangling counts as
# present, removed as missing), and a quoted RECORD path.
says() {  # LABEL ENTRY WHY: doctor names ENTRY with WHY, or reports nothing when WHY is empty
    uvm doctor > "$o/w.$1" 2>&1
    if [ -z "$3" ]; then
        if grep -q '^FAIL' "$o/w.$1"; then cat "$o/w.$1" >&2; fail "R2: $1: a FAIL where none is due"; fi
    else
        grep -qxF "FAIL  cache entry $2 is damaged ($3, partial purge)" "$o/w.$1" || { cat "$o/w.$1" >&2; fail "R2: $1: expected ($3)"; }
    fi
}
restore; l=$(xlink flake8); echo "$(real "$l")/bin/flake8" | purge
says console "$l" "flake8-7.1.1.dist-info is missing 1 of 42 files"
restore; e=$(senv tqdm); sp="$e/lib/python3.12/site-packages"
echo "$sp/tqdm/contrib/logging.py" | purge
says deep "$e" "tqdm-4.67.1.dist-info is missing 1 of 43 files"
restore; unlink "$sp/tqdm/std.py" && ln -s nowhere "$sp/tqdm/std.py" || fail "planting a dangling link"
says dangling "$e" ""
unlink "$sp/tqdm/std.py" || fail "removing the link"
says unlinked "$e" "tqdm-4.67.1.dist-info is missing 1 of 43 files"
restore; di=$(echo "$sp"/tqdm-*.dist-info)
sed 's|^tqdm/std.py,|"tqdm/std.py",|' "$di/RECORD" > "$o/rec" && cat "$o/rec" > "$di/RECORD" || fail "quoting a RECORD path"
grep -q '^"tqdm/std.py",' "$di/RECORD" || fail "no quoted RECORD path"
says quoted "$e" ""
echo "$sp/tqdm/std.py" | purge
says quotedpurged "$e" "tqdm-4.67.1.dist-info is missing 1 of 43 files"
# A wheel whose link is gone is still reached through its .http pointer, and
# a new environment built from it would copy the damage.
restore; l=$(wlink tqdm); r=$(real "$l"); echo "$r/tqdm/std.py" | purge; mv "$l" "$trash/wlink" || fail "unlinking the wheel"
[ -f "$l.http" ] || fail "the wheel has no .http pointer"
if uvm doctor > "$o/p.out" 2>&1; then cat "$o/p.out" >&2; fail "R2: a wheel reached through its pointer: doctor exits 0"; fi
grep -qF "FAIL  cache entry $l " "$o/p.out" || { cat "$o/p.out" >&2; fail "R2: no FAIL naming the wheel reached through its pointer"; }
# The same FAIL under every bash at hand: the pointer is read byte by byte,
# and bash 3.2 and bash 5 differ in how a locale reaches a pattern.
grep '^FAIL' "$o/p.out" > "$o/p.fail"; nb=0 seen=
for b in /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash "$(command -v bash)"; do
    [ -x "$b" ] || continue
    v=$("$b" -c 'echo "$BASH_VERSION"'); case " $seen " in *" $v "*) continue ;; esac; seen="$seen $v"; nb=$((nb + 1))
    "$b" "$(command -v uvm)" doctor 2>&1 | grep '^FAIL' | cmp -s "$o/p.fail" - || fail "R2: bash $v reads the pointer otherwise"
done
echo "pointer read under $nb bash version(s):$seen" >&2
# A pointer that cannot be parsed, or that names an archive that is gone, is
# passed over without a word: uv downloads the wheel again.
cp "$l.http" "$o/http.keep" || fail "keeping the pointer"
for bad in garbage missing unreadable; do
    case "$bad" in
        garbage) printf 'not a pointer\n' > "$l.http" ;;
        missing) printf '\225\260%s\221' AAAAAAAAAAAAAAAA > "$l.http" ;;
        unreadable) cp "$o/http.keep" "$l.http" && chmod 000 "$l.http" ;;
    esac
    uvm doctor > "$o/pb.out" 2> "$o/pb.err" || { cat "$o/pb.out" "$o/pb.err" >&2; fail "R2: a $bad pointer: doctor exits non-zero"; }
    [ ! -s "$o/pb.err" ] && ! grep -q '^FAIL' "$o/pb.out" || { cat "$o/pb.out" "$o/pb.err" >&2; fail "R2: a $bad pointer was not passed over silently"; }
done
chmod 644 "$l.http"; cp "$o/http.keep" "$l.http" || fail "restoring the pointer"
# A healthy cache reads no pointer file: each one's link is live. The trace
# names the reader where a pointer is read, and nowhere else.
bash -x "$(command -v uvm)" doctor > /dev/null 2> "$o/trace0"
grep -q 'uvm_cache_pointee' "$o/trace0" || fail "the trace does not show a pointer read where one is"
restore
bash -x "$(command -v uvm)" doctor > /dev/null 2> "$o/trace" || fail "R2: doctor exits non-zero on a healthy cache"
if grep -q 'uvm_cache_pointee' "$o/trace"; then fail "R2: a healthy cache read a pointer"; fi
# Unreached: an archive whose link is gone is not walked, however damaged.
restore; l=$(xlink flake8); r=$(real "$l"); mv "$l" "$trash/link" || fail "unlinking"
files "$r" | purge
uvm doctor > "$o/u.out" 2>&1 || { cat "$o/u.out" >&2; fail "R2: doctor walked an unreached archive"; }
if grep -qF "$r" "$o/u.out"; then fail "R2: doctor named an unreached archive"; fi
# >>> review cycle 3 (C3-F1): a cache with many damaged entries. One script
# environment of eleven distributions copied to twenty more, 231 dist-info
# directories, then 30% of the files under their site-packages purged at
# random (seed 1), R1's first shape. Doctor names them within a small multiple
# of its walk of the same tree healthy: the fastest of three runs each, so a
# loaded machine moves both sides.
restore
py=$(base_sp); py="${py%/lib/python3.12/site-packages}/bin/python3"
now() { "$py" -c 'import time; print("%.3f" % time.time())'; }
script many.py '"rich==13.9.4", "requests==2.32.3", "click==8.1.7", "attrs==24.2.0"' 'print("many ok")'
run many0 uv run --no-project "$w/many.py"
e0=''; for d in "$c"/environments-v2/many-*/; do e0="${d%/}"; done
[ -n "$e0" ] || fail "no environment for many.py"
i=1; while [ $i -le 20 ]; do cp -pPR "$e0" "$c/environments-v2/many-copy$i-$(printf '%016x' $i)" || fail "copying"; i=$((i + 1)); done
ndi=$(ls -d "$c"/environments-v2/many-*/lib/python3.12/site-packages/*.dist-info | wc -l | tr -d ' ')
[ "$ndi" -ge 200 ] || fail "only $ndi dist-info directories"
fastest() {  # LABEL: the fastest of three doctor runs, in seconds
    _b=''; for _k in 1 2 3; do
        _t0=$(now); uvm doctor > "$o/$1.$_k" 2>&1; _t1=$(now)
        _b=$(awk -v a="$_t0" -v b="$_t1" -v m="$_b" 'BEGIN { d = b - a; if (m == "" || d < m) m = d; printf "%.3f", m }')
    done; echo "$_b"
}
healthy=$(fastest mh)
grep -q '^FAIL' "$o/mh.1" && { cat "$o/mh.1" >&2; fail "a FAIL on the healthy many-entry cache"; }
"$py" - "$c/environments-v2" <<'PURGE' || fail "the random purge"
import os, random, sys
random.seed(1)
fs = []
for r, ds, ns in os.walk(sys.argv[1]):
    if "/many-" in r and "site-packages" in r:
        fs += [os.path.join(r, n) for n in ns]
fs.sort()
for f in random.sample(fs, int(0.3 * len(fs))):
    os.unlink(f)
PURGE
damaged=$(fastest md)
nf=$(grep -c '^FAIL  cache entry .*/many-' "$o/md.1")
[ "$nf" -eq 21 ] || { cat "$o/md.1" >&2; fail "C3-F1: $nf of 21 damaged entries named"; }
echo "many-entry walk: $ndi dist-info directories, healthy ${healthy}s, damaged ${damaged}s" >&2
awk -v h="$healthy" -v d="$damaged" 'BEGIN { exit !(d <= 4 * h + 0.5) }' \
    || fail "C3-F1: doctor took ${damaged}s on the damaged cache against ${healthy}s healthy, past 4x + 0.5s"
# <<< review cycle 3
echo "P1 ok"
DRIVE
