#!/bin/sh
# P2 gate: a knob-set call repairs each damaged live cache entry under the
# repair lock and outcome contract, keeps what it held, protects a running
# process, and fails the scope with its reason (R3, R4). Real uv and network:
# pypi.org, files.pythonhosted.org, releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
grep -q '^uvm_detect_cache()' bin/uv-manager || { echo "FAIL: P1 has not landed" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
SEED_UV="$u" GATES="$PWD/spec/uv-cache-purge-damage/gates" .agents/factory/bin/temp_root.sh sh -s <<'DRIVE' || exit 1
set -u
. "$GATES/lib.sh"
seed; subjects
sp0=$(base_sp); [ -d "$sp0" ] || fail "no managed interpreter site-packages"
ls "$sp0" > "$o/base0"
for k in script uvx flake8 ruff; do
    case "$k" in script) e=$(senv tqdm) ;; uvx) e=$(xlink tqdm) ;; flake8) e=$(xlink flake8) ;; ruff) e=$(xlink ruff) ;; esac
    distinfo "$e" > "$o/di0.$k"
done
# Healthy: a scope with no damage runs no cache repair.
knob healthy h1 call uvx
[ "$(rc healthy)" = 0 ] && [ "$(said healthy 'repairing the cache')" = 0 ] || fail "R3: a healthy scope ran a repair"
[ -e "$root/.repair/value-h1.ok" ] || fail "R3: the healthy scope recorded no outcome"
n=0
# SHAPE KIND [CALL]: damage, one knob-set call, then every R3 post-condition.
repair() {
    restore; n=$((n + 1)); s="$1" k="$2" cl="${3:-$2}"
    case "$k" in
        script) e=$(senv tqdm); p=tqdm/std.py ;; uvx) e=$(xlink tqdm); p=tqdm/std.py ;;
        flake8) e=$(xlink flake8); p=pyflakes/checker.py ;; ruff) e=$(xlink ruff); p=ruff/__init__.py ;;
        wheel) e=$(wlink tqdm); p=tqdm/std.py ;;
    esac
    r=$(real "$e")
    case "$k" in wheel) sp="$r" ;; *) sp="$r/lib/python3.12/site-packages" ;; esac
    d=${p%%/*}; [ "$k" = flake8 ] && d=pyflakes
    case "$s" in
        module) echo "$sp/$p" | purge ;;
        distinfo) files "$sp"/$d-*.dist-info | purge ;;
        record) echo "$sp"/$d-*.dist-info/RECORD | purge ;;
        metadata) echo "$sp"/$d-*.dist-info/METADATA | purge ;;
        third) files "$r" | nth 3 | purge ;;
        all) files "$r" | purge ;;
        pyvenv) echo "$r/pyvenv.cfg" | purge ;;
        exe) echo "$r/bin/ruff" | purge ;;
    esac
    a0=$(archives) l0=$(envlinks)
    knob "r$n" "g$n" call "$cl"
    [ "$(rc "r$n")" = 0 ] || { cat "$o/r$n.err" >&2; fail "R3: $s on $k: rc $(rc "r$n")"; }
    expect "$cl" "$(cat "$o/r$n.out")" || fail "R3: $s on $k: printed [$(cat "$o/r$n.out")]"
    [ "$(said "r$n" 'uv-manager: repairing the cache')" = 1 ] || { cat "$o/r$n.err" >&2; fail "R3: $s on $k: expected one repair line"; }
    ls "$sp0" | cmp -s "$o/base0" - || fail "R3: $s on $k: the managed interpreter's site-packages changed"
    if [ "$k" != wheel ]; then
        case "$k" in script) e2=$(senv tqdm) ;; uvx) e2=$(xlink tqdm) ;; flake8) e2=$(xlink flake8) ;; ruff) e2=$(xlink ruff) ;; esac
        distinfo "$e2" | cmp -s "$o/di0.$k" - || fail "R3: $s on $k: the dist-info listing changed"
        # Restored in place: nothing rebuilt, the same entry. A cached
        # environment that lost a RECORD cannot show its source, so its link
        # is removed and its own spec rebuilds it: the link reaches a new
        # archive, and the old one stays for a process running from it.
        if [ "$s" != pyvenv ] && [ "$s" != third ]; then
            case "$k.$s" in
                uvx.distinfo|uvx.record|flake8.distinfo|ruff.record|ruff.distinfo|flake8.record)
                    [ "$e2" = "$e" ] && [ "$(real "$e2")" != "$r" ] && [ -d "$r" ] && [ "$(archives)" = "$((a0 + 1))" ] \
                        || fail "R3: $s on $k: the link of an environment without its RECORD was not removed and rebuilt from its spec" ;;
                *)
                    [ "$e2" = "$e" ] && [ "$(archives)" = "$a0" ] && [ "$(envlinks)" = "$l0" ] || fail "R3: $s on $k: the entry was rebuilt, not restored" ;;
            esac
        fi
    fi
    knob "r$n.2" "g$n" call "$cl"
    [ "$(rc "r$n.2")" = 0 ] && [ "$(said "r$n.2" 'uv-manager: repairing')" = 0 ] || fail "R3: $s on $k: the second call repaired again"
    uvm doctor > "$o/r$n.doc" 2>&1 || { cat "$o/r$n.doc" >&2; fail "R3: $s on $k: doctor still finds damage"; }
}
for s in module distinfo record metadata third pyvenv; do repair "$s" script; repair "$s" uvx; done
repair module flake8; repair distinfo flake8; repair pyvenv flake8
repair exe ruff; repair record ruff
# A damaged wheel: a new script that needs it runs after the repair.
for s in module distinfo third all; do repair "$s" wheel new; done
# A damaged wheel whose link is gone, reached through its .http pointer: the
# pointer goes, the archive stays, and a new script that needs it runs on the
# wheel downloaded again.
restore; l=$(wlink tqdm); r=$(real "$l"); echo "$r/tqdm/std.py" | purge; mv "$l" "$trash/wlink.p" || fail "unlinking the wheel"
knob ptr pt1 call new
[ "$(rc ptr)" = 0 ] && expect new "$(cat "$o/ptr.out")" || { cat "$o/ptr.err" >&2; fail "R3: a wheel reached through its pointer: rc $(rc ptr), printed [$(cat "$o/ptr.out")]"; }
[ "$(said ptr 'uv-manager: repairing the cache')" = 1 ] && [ "$(real "$l")" != "$r" ] && [ -d "$r" ] || fail "R3: the wheel was not downloaded again, or its old archive was removed"
uvm doctor > "$o/ptr.doc" 2>&1 || { cat "$o/ptr.doc" >&2; fail "R3: the wheel reached through its pointer left damage"; }
# The repair never applies the working directory's configuration.
restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
mkdir -p "$w/proj" && printf '[pip]\ntarget = "leak"\n' > "$w/proj/uv.toml"
(cd "$w/proj" && knob cwd cwd1 call script)
[ "$(rc cwd)" = 0 ] && [ ! -e "$w/proj/leak" ] || fail "R3: the repair read the working directory's uv.toml"
# Doctor first changes nothing the repair needs.
restore; e=$(xlink tqdm); echo "$(real "$e")/lib/python3.12/site-packages/tqdm/std.py" | purge
uvm doctor > "$o/df.doc" 2>&1
grep -q 'uv-manager clean cache --yes' "$o/df.doc" || { cat "$o/df.doc" >&2; fail "doctor names no remedy for cache damage"; }
knob docfirst df1 call uvx
[ "$(rc docfirst)" = 0 ] && [ "$(said docfirst 'repairing the cache')" = 1 ] || fail "R3: doctor first, then no repair"
# R4: a process running from each environment imports a module present
# throughout, after the repair.
sleeper() {  # PYTHON TAG
    "$1" -c 'import os, sys, time
open(sys.argv[1] + ".up", "w").close()
while not os.path.exists(sys.argv[2]): time.sleep(0.1)
import tqdm.contrib.logging
print("late ok")' "$o/$2" "$o/go" > "$o/$2.late" 2>&1 &
}
for s in module distinfo; do
    restore; [ ! -e "$o/go" ] || mv "$o/go" "$trash/go.$s"
    e=$(senv tqdm); x=$(xlink tqdm); xr=$(real "$x")
    sleeper "$e/bin/python" "s.$s"; p1=$!; sleeper "$x/bin/python" "l.$s"; p2=$!; sleeper "$xr/bin/python" "a.$s"; p3=$!
    for t in s l a; do i=0; while [ ! -e "$o/$t.$s.up" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; done
    for t in "$e" "$xr"; do
        case "$s" in
            module) echo "$t/lib/python3.12/site-packages/tqdm/std.py" ;;
            distinfo) files "$t"/lib/python3.12/site-packages/tqdm-*.dist-info ;;
        esac
    done | purge
    knob "r4s.$s" "r4s$s" call script; knob "r4x.$s" "r4x$s" call uvx
    : > "$o/go"; wait "$p1" "$p2" "$p3"
    for t in s l a; do [ "$(cat "$o/$t.$s.late")" = "late ok" ] || { cat "$o/$t.$s.late" >&2; fail "R4: $s: process $t could not import after the repair"; }; done
done
# Concurrent first calls: one repairs, every call runs.
restore; e=$(xlink tqdm); echo "$(real "$e")/lib/python3.12/site-packages/tqdm/std.py" | purge
i=1; pids=''; while [ $i -le 8 ]; do ( knob "cc$i" cc1 call uvx ) & pids="$pids $!"; i=$((i + 1)); done; wait $pids
reps=0; i=1
while [ $i -le 8 ]; do
    [ "$(rc "cc$i")" = 0 ] && expect uvx "$(cat "$o/cc$i.out")" || fail "R3: concurrent call $i: rc $(rc "cc$i")"
    reps=$((reps + $(said "cc$i" 'repairing the cache'))); i=$((i + 1))
done
[ "$reps" = 1 ] || fail "R3: $reps concurrent calls repaired, expected 1"
# A repair that cannot reach the index fails every call in the scope with
# its reason: the release is fetched to compare before the reinstall. uv
# reports an offline fetch as a version not in its cache, with a hint, which
# is a fetch that failed, not a release the index lacks.
restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
i=1; pids=''; while [ $i -le 4 ]; do ( UV_OFFLINE=1; export UV_OFFLINE; knob "off$i" off1 call script ) & pids="$pids $!"; i=$((i + 1)); done; wait $pids
i=1; while [ $i -le 4 ]; do
    [ "$(rc "off$i")" != 0 ] || fail "R3: an offline repair let call $i run"
    grep -q "the cache environment $e is damaged, and uv-manager could not fetch tqdm 4.67.1 from the configured index to check its source (the index may be unreachable); the scope is not repaired" "$o/off$i.err" \
        || { cat "$o/off$i.err" >&2; fail "R3: call $i does not name the failed entry"; }
    ! grep -q 'clean cache' "$o/off$i.err" || fail "R3: an offline fetch prescribed clean cache to call $i"
    i=$((i + 1))
done
[ -e "$root/.repair/value-off1.failed" ] || fail "R3: no failed outcome recorded"
# A removal that cannot happen fails the scope and changes nothing.
for k in uvx wheel script; do
    restore
    case "$k" in
        uvx) e=$(xlink tqdm); echo "$(real "$e")/pyvenv.cfg" | purge; dir=${e%/*} ;;
        wheel) e=$(wlink tqdm); echo "$(real "$e")/tqdm/std.py" | purge; dir=${e%/*} ;;
        script) e=$(senv tqdm); echo "$e/pyvenv.cfg" | purge; dir=${e%/*} ;;
    esac
    chmod a-w "$dir"
    case "$k" in wheel) knob "ro.$k" "ro$k" call new ;; *) knob "ro.$k" "ro$k" call "$k" ;; esac
    chmod u+w "$dir"
    [ "$(rc "ro.$k")" != 0 ] || fail "R3: an unremovable $k entry let the call run"
    grep -q "cannot remove the cache entry $e" "$o/ro.$k.err" || { cat "$o/ro.$k.err" >&2; fail "R3: the $k failure does not name the entry"; }
    [ -L "$e" ] || [ -d "$e" ] || fail "R3: the $k entry went missing on a failed removal"
    ls "$sp0" | cmp -s "$o/base0" - || fail "R3: a failed $k removal reached the managed interpreter"
done
# An aside that cannot be removed is left, and the scope still runs.
restore; e=$(senv tqdm); echo "$e/pyvenv.cfg" | purge; chmod a-w "$e/lib/python3.12/site-packages"
knob aside as1 call script
for d in "$c"/environments-v2/.s-*; do chmod u+w "$d/lib/python3.12/site-packages" 2>/dev/null; done
[ "$(rc aside)" = 0 ] && grep -q 'uv cache prune removes it' "$o/aside.err" || { cat "$o/aside.err" >&2; fail "R3: a leftover aside failed the scope"; }
ls "$sp0" | cmp -s "$o/base0" - || fail "R3: the aside path reached the managed interpreter"
# A cached environment built from a local wheel that lost the direct_url.json
# its RECORD lists is removed and rebuilt from its own spec, never pinned by
# version from the index, which holds a different tqdm 4.67.1.
restore
"${sp0%/lib/python3.12/site-packages}/bin/python3" - "$w/tqdm-4.67.1-py3-none-any.whl" <<'WHEEL' || fail "building the local wheel"
import base64, hashlib, sys, zipfile
fs = {"tqdm/__init__.py": 'MARK = "local"\n', "tqdm/std.py": "X = 1\n",
      "tqdm-4.67.1.dist-info/METADATA": "Metadata-Version: 2.1\nName: tqdm\nVersion: 4.67.1\n",
      "tqdm-4.67.1.dist-info/WHEEL": "Wheel-Version: 1.0\nGenerator: gate\nRoot-Is-Purelib: true\nTag: py3-none-any\n"}
rec = []
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for n, t in fs.items():
        z.writestr(n, t)
        h = base64.urlsafe_b64encode(hashlib.sha256(t.encode()).digest()).rstrip(b"=").decode()
        rec.append("%s,sha256=%s,%d" % (n, h, len(t)))
    z.writestr("tqdm-4.67.1.dist-info/RECORD", "\n".join(rec + ["tqdm-4.67.1.dist-info/RECORD,,"]) + "\n")
WHEEL
lw() { uvx --from "$w/tqdm-4.67.1-py3-none-any.whl" python -c 'import tqdm, tqdm.std; print(tqdm.MARK)'; }
run lw0 lw
e=''; for l in "$c"/environments-v2/*/*; do [ -L "$l" ] && [ -f "$l/lib/python3.12/site-packages/tqdm-4.67.1.dist-info/direct_url.json" ] && e="$l"; done
[ -n "$e" ] || fail "no cached environment from the local wheel"
grep -q '^tqdm-4.67.1.dist-info/direct_url.json,' "$e/lib/python3.12/site-packages/tqdm-4.67.1.dist-info/RECORD" || fail "RECORD does not list direct_url.json"
sp=$(real "$e")/lib/python3.12/site-packages
printf '%s\n' "$sp/tqdm/std.py" "$sp/tqdm-4.67.1.dist-info/direct_url.json" | purge
knob lpath lp1 lw
[ "$(rc lpath)" = 0 ] && [ "$(cat "$o/lpath.out")" = local ] || { cat "$o/lpath.err" >&2; fail "R3: a path-sourced environment that lost direct_url.json was pinned from the index: rc $(rc lpath), printed [$(cat "$o/lpath.out")]"; }
grep -q 'environment(s) in place, 1 entry(ies) removed' "$o/lpath.err" || { cat "$o/lpath.err" >&2; fail "R3: the path-sourced environment was not removed"; }
uvm doctor > "$o/lpath.doc" 2>&1 || { cat "$o/lpath.doc" >&2; fail "R3: the path-sourced environment left damage"; }
# A script environment in the same state cannot be removed (M2) or pinned by
# version, so it fails the scope naming the entry and records no ok.
script l.py "\"tqdm @ file://$w/tqdm-4.67.1-py3-none-any.whl\"" 'import tqdm, tqdm.std; print(tqdm.MARK)'
run ls0 uv run --no-project "$w/l.py"
e=''; for d in "$c"/environments-v2/l-*/; do [ -f "${d}lib/python3.12/site-packages/tqdm-4.67.1.dist-info/direct_url.json" ] && e="${d%/}"; done
[ -n "$e" ] || fail "no script environment from the local wheel"
printf '%s\n' "$e/lib/python3.12/site-packages/tqdm/std.py" "$e/lib/python3.12/site-packages/tqdm-4.67.1.dist-info/direct_url.json" | purge
knob lscript ls1 uv run --no-project "$w/l.py"
[ "$(rc lscript)" != 0 ] || fail "R3: a script environment that lost direct_url.json let the call run"
grep -q "the cache environment $e holds a distribution whose source is not recorded" "$o/lscript.err" || { cat "$o/lscript.err" >&2; fail "R3: the sourceless script environment's failure does not name the entry"; }
[ -e "$root/.repair/value-ls1.failed" ] && [ ! -e "$root/.repair/value-ls1.ok" ] || fail "R3: a sourceless script environment recorded ok"
[ -d "$e" ] || fail "R3: the sourceless script environment was removed"
# The cached environment from the local wheel with every file of its
# dist-info purged, RECORD and direct_url.json included, leaves nothing to
# show its source: its link is removed and its own spec rebuilds it, never
# PyPI's tqdm 4.67.1.
restore
run lw1 lw
e=''; for l in "$c"/environments-v2/*/*; do [ -L "$l" ] && [ -f "$l/lib/python3.12/site-packages/tqdm-4.67.1.dist-info/direct_url.json" ] && e="$l"; done
[ -n "$e" ] || fail "no cached environment from the local wheel"
sp=$(real "$e")/lib/python3.12/site-packages
{ echo "$sp/tqdm/std.py"; files "$sp/tqdm-4.67.1.dist-info"; } | purge
knob lrec lr1 lw
[ "$(rc lrec)" = 0 ] && [ "$(cat "$o/lrec.out")" = local ] || { cat "$o/lrec.err" >&2; fail "R3: a path-sourced environment that lost its RECORD was pinned from the index: rc $(rc lrec), printed [$(cat "$o/lrec.out")]"; }
grep -q 'environment(s) in place, 1 entry(ies) removed' "$o/lrec.err" || { cat "$o/lrec.err" >&2; fail "R3: the environment that lost its RECORD was not removed"; }
knob lrec.2 lr2 lw
[ "$(cat "$o/lrec.2.out")" = local ] || fail "R3: the environment that lost its RECORD came back as [$(cat "$o/lrec.2.out")]"
# A find-links directory given on the command line: a package the index
# does not have. Its cached environment, a module purged, is removed and
# rebuilt by its own call; an unrelated call in the same scope runs.
mkdir -p "$w/fl"
"${sp0%/lib/python3.12/site-packages}/bin/python3" - "$w/fl/uvmgate-0.1-py3-none-any.whl" <<'WHEEL' || fail "building the find-links wheel"
import base64, hashlib, sys, zipfile
fs = {"uvmgate/__init__.py": "", "uvmgate/extra.py": 'X = "fl ok"\n',
      "uvmgate-0.1.dist-info/METADATA": "Metadata-Version: 2.1\nName: uvmgate\nVersion: 0.1\n",
      "uvmgate-0.1.dist-info/WHEEL": "Wheel-Version: 1.0\nGenerator: gate\nRoot-Is-Purelib: true\nTag: py3-none-any\n"}
rec = []
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for n, t in fs.items():
        z.writestr(n, t)
        h = base64.urlsafe_b64encode(hashlib.sha256(t.encode()).digest()).rstrip(b"=").decode()
        rec.append("%s,sha256=%s,%d" % (n, h, len(t)))
    z.writestr("uvmgate-0.1.dist-info/RECORD", "\n".join(rec + ["uvmgate-0.1.dist-info/RECORD,,"]) + "\n")
WHEEL
fl() { uv run --no-project --find-links "$w/fl" --with uvmgate==0.1 python -c 'import uvmgate.extra; print(uvmgate.extra.X)'; }
restore; run fl0 fl
e=''; for l in "$c"/environments-v2/*/*; do [ -L "$l" ] && [ -d "$l/lib/python3.12/site-packages/uvmgate" ] && e="$l"; done
[ -n "$e" ] || fail "no cached environment from the find-links directory"
echo "$(real "$e")/lib/python3.12/site-packages/uvmgate/extra.py" | purge
knob flu fl1 call uvx
[ "$(rc flu)" = 0 ] && expect uvx "$(cat "$o/flu.out")" || { cat "$o/flu.err" >&2; fail "R3: a find-links environment failed an unrelated call's scope: rc $(rc flu)"; }
knob flc fl1 fl
[ "$(rc flc)" = 0 ] && [ "$(cat "$o/flc.out")" = "fl ok" ] || { cat "$o/flc.err" >&2; fail "R3: the find-links call after the repair: rc $(rc flc)"; }
# A cached environment whose release cannot be fetched loses its link
# instead of failing the scope, and the call rebuilds it from the wheel it
# holds.
restore; e=$(xlink tqdm); echo "$(real "$e")/lib/python3.12/site-packages/tqdm/std.py" | purge
( UV_OFFLINE=1; export UV_OFFLINE; knob xoff xo1 call uvx )
[ "$(rc xoff)" = 0 ] && expect uvx "$(cat "$o/xoff.out")" || { cat "$o/xoff.err" >&2; fail "R3: a cached environment whose reinstall failed failed the scope: rc $(rc xoff)"; }
grep -q "$e is not shown to come from the configured index; its link is removed" "$o/xoff.err" || { cat "$o/xoff.err" >&2; fail "R3: the failed fetch's link removal is not noted"; }
# A script environment built with that find-links directory fails the scope
# naming the entry: its source is not recorded, and it is not removed.
script f.py '"uvmgate==0.1"' 'import uvmgate.extra; print(uvmgate.extra.X)'
restore; run fs0 uv run --no-project --find-links "$w/fl" "$w/f.py"
e=''; for d in "$c"/environments-v2/f-*/; do [ -d "${d}lib/python3.12/site-packages/uvmgate" ] && e="${d%/}"; done
[ -n "$e" ] || fail "no script environment from the find-links directory"
echo "$e/lib/python3.12/site-packages/uvmgate/extra.py" | purge
knob fls fs1 uv run --no-project --find-links "$w/fl" "$w/f.py"
[ "$(rc fls)" != 0 ] || fail "R3: a script environment from a find-links directory let the call run"
grep -q "the cache environment $e holds a distribution whose source is not recorded" "$o/fls.err" || { cat "$o/fls.err" >&2; fail "R3: the find-links script environment's failure does not name the entry"; }
[ -e "$root/.repair/value-fs1.failed" ] && [ ! -e "$root/.repair/value-fs1.ok" ] && [ -d "$e" ] || fail "R3: the find-links script environment recorded ok or was removed"
# A reinstall that exits 0 and changes nothing fails the scope, naming the
# entry, rather than recording ok over the damage. The stand-in passes the
# index check's fetch, the one pip install with --target, to uv.
restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
uvr=$(real "$root/current")/uv
mv "$uvr" "$uvr.real" || fail "setting the stand-in uv aside"
printf '#!/bin/sh\nif [ "$1 $2" = "pip install" ]; then case " $* " in *" --target "*) ;; *) exit 0 ;; esac; fi\nexec "$0.real" "$@"\n' > "$uvr" && chmod +x "$uvr" || fail "writing the stand-in uv"
knob noop np1 call script
# A cached environment in the same state loses its link instead, and the
# call rebuilds it.
restore; ex=$(xlink tqdm); echo "$(real "$ex")/lib/python3.12/site-packages/tqdm/std.py" | purge
knob noopx npx1 call uvx
mv "$uvr.real" "$uvr" || fail "restoring uv"
[ "$(rc noopx)" = 0 ] && expect uvx "$(cat "$o/noopx.out")" || { cat "$o/noopx.err" >&2; fail "R3: a cached environment still damaged after its reinstall failed the scope: rc $(rc noopx)"; }
grep -q "$ex is still damaged after its reinstall; its link is removed" "$o/noopx.err" || { cat "$o/noopx.err" >&2; fail "R3: the still-damaged cached environment's link removal is not noted"; }
[ "$(rc noop)" != 0 ] || fail "R3: a reinstall that did nothing let the call run"
grep -q "the cache environment $e is still damaged after its repair" "$o/noop.err" || { cat "$o/noop.err" >&2; fail "R3: a reinstall that did nothing does not fail naming the entry"; }
[ -e "$root/.repair/value-np1.failed" ] && [ ! -e "$root/.repair/value-np1.ok" ] || fail "R3: a reinstall that did nothing recorded ok"
# >>> review cycle 2 (C2-F1, C2-F2): only the damaged distributions are
# reinstalled, and one whose source is unknown is never swapped.
# DIR...: inode, size and cksum of every file under each DIR, sorted.
ident() { find "$@" -type f | LC_ALL=C sort | while IFS= read -r _f; do echo "$(ls -in "$_f" | awk '{ print $1, $6 }') $(cksum < "$_f") $_f"; done; }
# d14: a script environment whose uvmgate came from a find-links directory
# the script declares loses a PyPI distribution's module. An unrelated call
# in the scope runs, then its own; uvmgate is byte-identical.
c2_scope() {
    restore
    printf '# /// script\n# requires-python = ">=3.12"\n# dependencies = ["uvmgate==0.1", "tqdm==4.67.1"]\n# [tool.uv]\n# find-links = ["%s"]\n# ///\nimport uvmgate.extra, tqdm.std; print("fd", uvmgate.extra.X)\n' "$w/fl" > "$w/fd.py"
    run fd0 uv run --no-project "$w/fd.py"
    e=''; for d in "$c"/environments-v2/fd-*/; do e="${d%/}"; done
    [ -n "$e" ] || fail "no script environment for fd.py"
    s="$e/lib/python3.12/site-packages"; ident "$s"/uvmgate "$s"/uvmgate-0.1.dist-info > "$o/fd.before"
    echo "$s/tqdm/std.py" | purge
    knob fdu fd1 call ruff
    [ "$(rc fdu)" = 0 ] && expect ruff "$(cat "$o/fdu.out")" || { cat "$o/fdu.err" >&2; fail "C2-F2: an undamaged find-links distribution failed an unrelated call's scope: rc $(rc fdu)"; }
    knob fdc fd1 uv run --no-project "$w/fd.py"
    [ "$(rc fdc)" = 0 ] && [ "$(cat "$o/fdc.out")" = "fd fl ok" ] || { cat "$o/fdc.err" >&2; fail "C2-F2: the damaged environment's own call: rc $(rc fdc)"; }
    ident "$s"/uvmgate "$s"/uvmgate-0.1.dist-info | cmp -s "$o/fd.before" - || fail "C2-F2: the undamaged find-links distribution changed"
}
# d15: the find-links directory in uv.toml. A PyPI distribution's module
# purged is repaired; the find-links distribution's module purged fails the
# scope naming it and the remedy, uv.toml notwithstanding.
c2_uvtoml() {
    mkdir -p "$XDG_CONFIG_HOME/uv" && printf 'find-links = ["%s"]\n' "$w/fl" > "$XDG_CONFIG_HOME/uv/uv.toml" || fail "writing uv.toml"
    script fu.py '"uvmgate==0.1", "tqdm==4.67.1"' 'import uvmgate.extra, tqdm.std; print("fu", uvmgate.extra.X)'
    for p in tqdm/std.py uvmgate/extra.py; do
        restore; run fu0 uv run --no-project "$w/fu.py"
        e=''; for d in "$c"/environments-v2/fu-*/; do e="${d%/}"; done
        [ -n "$e" ] || fail "no script environment for fu.py"
        echo "$e/lib/python3.12/site-packages/$p" | purge
        knob "fu.${p%%/*}" "fu${p%%/*}" uv run --no-project "$w/fu.py"
    done
    mv "$XDG_CONFIG_HOME/uv/uv.toml" "$trash/uv.toml.fu" || fail "removing uv.toml"
    [ "$(rc fu.tqdm)" = 0 ] && [ "$(cat "$o/fu.tqdm.out")" = "fu fl ok" ] || { cat "$o/fu.tqdm.err" >&2; fail "C2-F2: a uv.toml find-links environment with a PyPI module purged: rc $(rc fu.tqdm)"; }
    [ "$(rc fu.uvmgate)" != 0 ] || fail "C2-F2: a find-links distribution with no source recorded was reinstalled by version"
    grep -q "the cache environment $e holds a distribution whose source is not recorded (uvmgate 0.1); clear the cache with uv-manager clean cache --yes" "$o/fu.uvmgate.err" \
        || { cat "$o/fu.uvmgate.err" >&2; fail "C2-F2: the failure does not name uvmgate 0.1 and the remedy"; }
}
# d16: a fork of mdurl 0.1.2 from a find-links directory, the script naming
# it with no-index. SHAPE A takes every file of its dist-info, B its RECORD
# only. Neither knob-set call nor the knob-off call after runs PyPI's mdurl;
# the scope fails naming mdurl 0.1.2 and the remedy; the fork's file stays.
c2_fork() {
    restore
    printf '# /// script\n# requires-python = ">=3.12"\n# dependencies = ["mdurl==0.1.2"]\n# [tool.uv]\n# find-links = ["%s"]\n# no-index = true\n# ///\nimport mdurl; print("fk", getattr(mdurl, "ORIGIN", "pypi"))\n' "$w/fk" > "$w/fk.py"
    run fk0 uv run --no-project "$w/fk.py"
    [ "$(cat "$o/fk0.out")" = "fk local-fork" ] || fail "the fork's environment runs [$(cat "$o/fk0.out")]"
    e=''; for d in "$c"/environments-v2/fk-*/; do e="${d%/}"; done
    di="$e/lib/python3.12/site-packages/mdurl-0.1.2.dist-info"
    case "$1" in A) files "$di" | purge ;; B) echo "$di/RECORD" | purge; [ -f "$di/uv_cache.json" ] || fail "no uv_cache.json in the fork's dist-info" ;; esac
    knob "fk$1" "fk$1" uv run --no-project "$w/fk.py"
    knob "fk$1.2" "fk$1" uv run --no-project "$w/fk.py"
    ( UVM_REPAIR=''; export UVM_REPAIR; uv run --no-project "$w/fk.py" ) > "$o/fk$1.off.out" 2> "$o/fk$1.off.err"
    ! grep -q 'fk pypi' "$o/fk$1.out" "$o/fk$1.2.out" "$o/fk$1.off.out" || fail "C2-F1: shape $1: PyPI's mdurl ran in place of the fork"
    [ "$(rc "fk$1")" != 0 ] && grep -q "the cache environment $e holds a distribution whose source is not recorded (mdurl 0.1.2).*; clear the cache with uv-manager clean cache --yes" "$o/fk$1.err" \
        || { cat "$o/fk$1.err" >&2; fail "C2-F1: shape $1: the scope did not fail naming mdurl 0.1.2 and the remedy"; }
    grep -q local-fork "$e/lib/python3.12/site-packages/mdurl/__init__.py" || fail "C2-F1: shape $1: the fork's file was replaced"
    ! ls -a "$c/environments-v2" | grep -q '^\.fk-' || fail "C2-F1: shape $1: the fetched release was left behind"
}
# Ruling 3: two distributions damaged, both reinstalled, every other
# distribution's files the same inodes, sizes and bytes.
c2_sibling() {
    restore; e=$(senv rich); s="$e/lib/python3.12/site-packages"
    ident "$s"/markdown_it "$s"/markdown_it_py-*.dist-info "$s"/pygments "$s"/pygments-*.dist-info > "$o/sib.before"
    printf '%s\n' "$s/rich/console.py" "$s/mdurl/_parse.py" | purge
    knob sib sb1 uv run --no-project "$w/r.py"
    [ "$(rc sib)" = 0 ] && case "$(cat "$o/sib.out")" in "r ok "*) ;; *) false ;; esac || { cat "$o/sib.err" >&2; fail "ruling 3: rc $(rc sib)"; }
    ident "$s"/markdown_it "$s"/markdown_it_py-*.dist-info "$s"/pygments "$s"/pygments-*.dist-info | cmp -s "$o/sib.before" - \
        || fail "ruling 3: an undamaged distribution was rewritten by the repair"
    uvm doctor > "$o/sib.doc" 2>&1 || { cat "$o/sib.doc" >&2; fail "ruling 3: a damaged distribution was left damaged"; }
}
mkdir -p "$w/fk"
"${sp0%/lib/python3.12/site-packages}/bin/python3" - "$w/fk/mdurl-0.1.2-py2.py3-none-any.whl" <<'WHEEL' || fail "building the fork's wheel"
import base64, hashlib, sys, zipfile
fs = {"mdurl/__init__.py": 'ORIGIN = "local-fork"\n',
      "mdurl-0.1.2.dist-info/METADATA": "Metadata-Version: 2.1\nName: mdurl\nVersion: 0.1.2\n",
      "mdurl-0.1.2.dist-info/WHEEL": "Wheel-Version: 1.0\nGenerator: gate\nRoot-Is-Purelib: true\nTag: py3-none-any\n"}
rec = []
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for n, t in fs.items():
        z.writestr(n, t)
        h = base64.urlsafe_b64encode(hashlib.sha256(t.encode()).digest()).rstrip(b"=").decode()
        rec.append("%s,sha256=%s,%d" % (n, h, len(t)))
    z.writestr("mdurl-0.1.2.dist-info/RECORD", "\n".join(rec + ["mdurl-0.1.2.dist-info/RECORD,,"]) + "\n")
WHEEL
# <<< review cycle 2
c2_scope; c2_uvtoml; c2_fork A; c2_fork B; c2_sibling
# >>> review cycle 3 (C3-F2): six 1.16.0 from an index the script names, over
# HTTP, which leaves no mark in the environment. Its module is purged and its
# RECORD kept. The release fetched from the configured index has another
# RECORD, so the scope fails naming six 1.16.0 and the remedy, and no call
# runs PyPI's six. A cached environment from the same index, named on the
# command line, loses its link instead, and its own call rebuilds it from
# that index.
c3_index() {
    py="${sp0%/lib/python3.12/site-packages}/bin/python3"
    mkdir -p "$w/idx/simple/six"
    "$py" - "$w/idx/six-1.16.0-py2.py3-none-any.whl" <<'WHEEL' || fail "building the index's six"
import base64, hashlib, sys, zipfile
fs = {"six.py": 'ORIGIN = "index-fork"\n',
      "six-1.16.0.dist-info/METADATA": "Metadata-Version: 2.1\nName: six\nVersion: 1.16.0\n",
      "six-1.16.0.dist-info/WHEEL": "Wheel-Version: 1.0\nGenerator: gate\nRoot-Is-Purelib: true\nTag: py2-none-any\nTag: py3-none-any\n"}
rec = []
with zipfile.ZipFile(sys.argv[1], "w") as z:
    for n, t in fs.items():
        z.writestr(n, t)
        h = base64.urlsafe_b64encode(hashlib.sha256(t.encode()).digest()).rstrip(b"=").decode()
        rec.append("%s,sha256=%s,%d" % (n, h, len(t)))
    z.writestr("six-1.16.0.dist-info/RECORD", "\n".join(rec + ["six-1.16.0.dist-info/RECORD,,"]) + "\n")
WHEEL
    printf '<a href="../../six-1.16.0-py2.py3-none-any.whl">six-1.16.0-py2.py3-none-any.whl</a>\n' > "$w/idx/simple/six/index.html"
    "$py" -u -m http.server -b 127.0.0.1 --directory "$w/idx" 0 > "$o/idx.log" 2>&1 &
    srv=$!; trap 'kill "$srv" 2>/dev/null' EXIT
    port='' i=0
    while [ -z "$port" ] && [ $i -lt 100 ]; do
        port=$(sed -n 's/.* port \([0-9][0-9]*\) .*/\1/p' "$o/idx.log"); [ -n "$port" ] || sleep 0.1; i=$((i + 1))
    done
    [ -n "$port" ] || fail "the gate's index did not start"
    idx="http://127.0.0.1:$port/simple"
    restore
    printf '# /// script\n# requires-python = ">=3.12"\n# dependencies = ["six==1.16.0"]\n# [[tool.uv.index]]\n# url = "%s"\n# ///\nimport six; print("six", getattr(six, "ORIGIN", "pypi"))\n' "$idx" > "$w/si.py"
    run si0 uv run --no-project "$w/si.py"
    [ "$(cat "$o/si0.out")" = "six index-fork" ] || fail "the index's six runs [$(cat "$o/si0.out")]"
    e=''; for d in "$c"/environments-v2/si-*/; do e="${d%/}"; done
    di="$e/lib/python3.12/site-packages/six-1.16.0.dist-info"
    [ -f "$di/RECORD" ] && [ ! -e "$di/uv_cache.json" ] && [ ! -e "$di/direct_url.json" ] || fail "the index's six left a mark of its source"
    cp "$di/RECORD" "$o/si.record" || fail "keeping the RECORD"
    echo "$e/lib/python3.12/site-packages/six.py" | purge
    knob si si1 uv run --no-project "$w/si.py"
    knob si.2 si1 uv run --no-project "$w/si.py"
    ( UVM_REPAIR=''; export UVM_REPAIR; uv run --no-project "$w/si.py" ) > "$o/si.off.out" 2> "$o/si.off.err"
    ! grep -q 'six pypi' "$o/si.out" "$o/si.2.out" "$o/si.off.out" || fail "C3-F2: PyPI's six ran in place of the index's"
    [ "$(rc si)" != 0 ] && grep -q "the cache environment $e holds a distribution whose source is not recorded (six 1.16.0), whose files differ from the configured index's release; clear the cache with uv-manager clean cache --yes" "$o/si.err" \
        || { cat "$o/si.err" >&2; fail "C3-F2: the scope did not fail naming six 1.16.0 and the remedy"; }
    [ ! -e "$e/lib/python3.12/site-packages/six.py" ] && cmp -s "$o/si.record" "$di/RECORD" || fail "C3-F2: the index's six was replaced"
    ! ls -a "$c/environments-v2" | grep -q '^\.si-' || fail "C3-F2: the fetched release was left behind"
    restore
    xi() { uv run --no-project --index "$idx" --with six==1.16.0 python -c 'import six; print("six", getattr(six, "ORIGIN", "pypi"))'; }
    run xi0 xi
    [ "$(cat "$o/xi0.out")" = "six index-fork" ] || fail "the cached environment runs [$(cat "$o/xi0.out")]"
    x=''; for l in "$c"/environments-v2/*/*; do [ -L "$l" ] && [ -d "$l/lib/python3.12/site-packages/six-1.16.0.dist-info" ] && x="$l"; done
    [ -n "$x" ] || fail "no cached environment from the gate's index"
    echo "$(real "$x")/lib/python3.12/site-packages/six.py" | purge
    knob xi xi1 xi
    [ "$(rc xi)" = 0 ] && [ "$(cat "$o/xi.out")" = "six index-fork" ] \
        || { cat "$o/xi.err" >&2; fail "C3-F2: the cached environment from the index its call names: rc $(rc xi), printed [$(cat "$o/xi.out")]"; }
    grep -q "$x is not shown to come from the configured index; its link is removed" "$o/xi.err" || { cat "$o/xi.err" >&2; fail "C3-F2: the cached environment's link removal is not noted"; }
    kill "$srv"; trap - EXIT
}
# <<< review cycle 3
c3_index
# >>> review cycle 4 (C4-F1, C4-F2): the index check compares source files
# only, and a fetch that fails is told from a release the index lacks.
# LABEL SCRIPT MODULE OUTPUT [TAG]: a script environment uv built from an sdist,
# one module purged and its RECORD kept. The release fetched to compare is
# another build of the same source, whose binaries and metadata need not
# match, so the call repairs it and runs.
c4_built() {
    t="${5:-C4-F1}"
    e=''; for d in "$c"/environments-v2/"${2%.py}"-*/; do e="${d%/}"; done
    [ -n "$e" ] || fail "no script environment for $2"
    s="$e/lib/python3.12/site-packages"
    [ -f "$s/$3" ] || fail "$2's environment has no $3"
    echo "$s/$3" | purge
    knob "$1" "$1" uv run --no-project "$w/$2"
    [ "$(rc "$1")" = 0 ] && [ "$(cat "$o/$1.out")" = "$4" ] \
        || { cat "$o/$1.err" >&2; fail "$t: $4 built from its sdist, $3 purged: rc $(rc "$1"), printed [$(cat "$o/$1.out")]"; }
    [ "$(said "$1" 'uv-manager: repairing the cache')" = 1 ] && [ -f "$s/$3" ] || fail "$t: $3 was not restored in place"
    ! ls -a "$c/environments-v2" | grep -q "^\.${2%.py}-" || fail "$t: the fetched release of $2's distribution was left behind"
    uvm doctor > "$o/$1.doc" 2>&1 || { cat "$o/$1.doc" >&2; fail "$t: $2's environment left damage"; }
}
c4_sdist() {
    # MarkupSafe 2.0.1 publishes no cp312 wheel, so uv builds its C extension.
    if ! cc --version > /dev/null 2>&1; then
        echo "SKIP: C4-F1 markupsafe 2.0.1: no C compiler to build its sdist" >&2; return 0
    fi
    restore
    script ms.py '"markupsafe==2.0.1"' 'import markupsafe, markupsafe._native; print("ms", markupsafe.__version__)'
    run ms0 uv run --no-project "$w/ms.py"
    ls "$c"/environments-v2/ms-*/lib/python3.12/site-packages/markupsafe/_speedups*.so > /dev/null 2>&1 \
        || fail "markupsafe 2.0.1 was built without its C extension"
    c4_built ms1 ms.py markupsafe/_native.py "ms 2.0.1"
}
c4_docopt() {
    # docopt 0.6.2 is an sdist only; built under an older UV_EXCLUDE_NEWER its
    # metadata comes from an older setuptools than the check's build uses.
    restore
    script dp.py '"docopt==0.6.2"' 'import docopt; print("dp", docopt.__version__)'
    ( UV_EXCLUDE_NEWER=2024-06-01T00:00:00Z; export UV_EXCLUDE_NEWER; uv run --no-project "$w/dp.py" ) > "$o/dp0.out" 2> "$o/dp0.err" \
        || { cat "$o/dp0.err" >&2; fail "building docopt 0.6.2 under UV_EXCLUDE_NEWER"; }
    c4_built dp1 dp.py docopt.py "dp 0.6.2"
}
# An index that cannot be reached fails the scope with a reason of its own,
# naming the distribution, without the clean cache remedy, which cannot help
# while the index is down.
c4_fetch() {
    restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
    ( UV_INDEX_URL=http://127.0.0.1:9/simple UV_HTTP_RETRIES=0; export UV_INDEX_URL UV_HTTP_RETRIES; knob unr un1 call script )
    [ "$(rc unr)" != 0 ] || fail "C4-F2: a repair against an unreachable index let the call run"
    ! grep -q 'clean cache' "$o/unr.err" || { cat "$o/unr.err" >&2; fail "C4-F2: an unreachable index prescribed clean cache"; }
    grep -q "the cache environment $e is damaged, and uv-manager could not fetch tqdm 4.67.1 from the configured index to check its source (the index may be unreachable); the scope is not repaired" "$o/unr.err" \
        || { cat "$o/unr.err" >&2; fail "C4-F2: the unreachable index's failure does not name the fetch and the distribution"; }
    [ -e "$root/.repair/value-un1.failed" ] && [ ! -e "$root/.repair/value-un1.ok" ] || fail "C4-F2: the failed fetch recorded ok"
    ! ls -a "$c/environments-v2" | grep -q '^\.s-' || fail "C4-F2: the failed fetch left its target behind"
}
# <<< review cycle 4
c4_sdist; c4_docopt; c4_fetch
# >>> review cycle 5 (C5-F1, C5-F2, C5-F3): only wheels are compared, and a
# failed fetch is told by positive markers, read with colour off.
# numpy 2.1.3 built from its sdist under no-binary: meson writes the path of
# its temporary build interpreter into numpy/__config__.py, so no two builds
# match. A module purged, RECORD kept: the call repairs it in place and runs.
c5_numpy() {
    if ! cc --version > /dev/null 2>&1; then
        echo "SKIP: C5-F1 numpy 2.1.3: no C compiler to build its sdist" >&2; return 0
    fi
    restore
    mkdir -p "$XDG_CONFIG_HOME/uv" && printf 'no-binary-package = ["numpy"]\n[pip]\nno-binary = ["numpy"]\n' > "$XDG_CONFIG_HOME/uv/uv.toml" \
        || fail "writing uv.toml"
    script nu.py '"numpy==2.1.3"' 'import numpy; print("nu", numpy.__version__)'
    run nu0 uv run --no-project "$w/nu.py"
    s=''; for d in "$c"/environments-v2/nu-*/; do s="${d%/}/lib/python3.12/site-packages"; done
    [ -f "$s/numpy-2.1.3.dist-info/uv_build.json" ] || fail "numpy 2.1.3 was not built from its sdist"
    grep -q 'builds-v0/' "$s/numpy/__config__.py" || fail "numpy's build wrote no build path into numpy/__config__.py"
    c4_built nu1 nu.py numpy/_pytesttester.py "nu 2.1.3" C5-F1
    mv "$XDG_CONFIG_HOME/uv/uv.toml" "$trash/uv.toml.np" || fail "removing uv.toml"
}
# A version the job's exclude-newer filters out, which uv reports with a
# hint: the configured index does not serve it, and clearing the cache is the
# remedy that works.
c5_excl() {
    restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
    ( UV_EXCLUDE_NEWER=2024-06-01T00:00:00Z; export UV_EXCLUDE_NEWER; knob exn ex1 call script )
    grep -q 'hint: `tqdm` was filtered by `exclude-newer`' "$o/exn.err" || { cat "$o/exn.err" >&2; fail "uv gave no exclude-newer hint"; }
    [ "$(rc exn)" != 0 ] && grep -q "the cache environment $e holds a distribution whose source is not recorded (tqdm 4.67.1), which the configured index does not serve; clear the cache with uv-manager clean cache --yes" "$o/exn.err" \
        || { cat "$o/exn.err" >&2; fail "C5-F2: a version exclude-newer filters out does not name clean cache"; }
    [ -e "$root/.repair/value-ex1.failed" ] && [ ! -e "$root/.repair/value-ex1.ok" ] || fail "C5-F2: the missing version recorded ok"
    ! ls -a "$c/environments-v2" | grep -q '^\.s-' || fail "C5-F2: the fetch left its target behind"
}
# An index that answers 401, with FORCE_COLOR=1 in the job: a fetch that
# failed, with its own reason and no clean cache.
c5_401() {
    py="${sp0%/lib/python3.12/site-packages}/bin/python3"
    "$py" -u -c '
import http.server as h
class H(h.BaseHTTPRequestHandler):
    def do_GET(s):
        s.send_response(401); s.send_header("WWW-Authenticate", "Basic realm=gate")
        s.send_header("Content-Length", "0"); s.end_headers()
    def log_message(s, *a): pass
v = h.HTTPServer(("127.0.0.1", 0), H); print("port", v.server_port); v.serve_forever()' > "$o/u401.log" 2>&1 &
    srv=$!; trap 'kill "$srv" 2>/dev/null' EXIT
    port='' i=0
    while [ -z "$port" ] && [ $i -lt 100 ]; do
        port=$(sed -n 's/^port \([0-9][0-9]*\)$/\1/p' "$o/u401.log"); [ -n "$port" ] || sleep 0.1; i=$((i + 1))
    done
    [ -n "$port" ] || fail "the gate's 401 index did not start"
    restore; e=$(senv tqdm); echo "$e/lib/python3.12/site-packages/tqdm/std.py" | purge
    ( UV_INDEX_URL="http://127.0.0.1:$port/simple" FORCE_COLOR=1; export UV_INDEX_URL FORCE_COLOR; knob u401 a401 call script )
    kill "$srv"; trap - EXIT
    grep -q '401 Unauthorized' "$o/u401.err" || { cat "$o/u401.err" >&2; fail "uv gave no 401 hint"; }
    [ "$(rc u401)" != 0 ] || fail "C5-F3: a repair against an index answering 401 let the call run"
    ! grep -q 'clean cache' "$o/u401.err" || { cat "$o/u401.err" >&2; fail "C5-F3: a 401 under FORCE_COLOR=1 prescribed clean cache"; }
    grep -q "the cache environment $e is damaged, and uv-manager could not fetch tqdm 4.67.1 from the configured index to check its source" "$o/u401.err" \
        || { cat "$o/u401.err" >&2; fail "C5-F3: the 401's failure does not name the fetch and the distribution"; }
    [ -e "$root/.repair/value-a401.failed" ] && [ ! -e "$root/.repair/value-a401.ok" ] || fail "C5-F3: the failed fetch recorded ok"
}
# <<< review cycle 5
c5_numpy; c5_excl; c5_401
# Hardlink mode: the reinstall leaves the wheel the environment shares inodes with whole.
find "$c" -delete
env UV_LINK_MODE=hardlink uv run --no-project "$w/s.py" > /dev/null 2>&1 || fail "hardlink build"
e=$(senv tqdm); wl=$(wlink tqdm)
[ "$(ls -i "$e/lib/python3.12/site-packages/tqdm/std.py" | awk '{print $1}')" = "$(ls -i "$(real "$wl")/tqdm/std.py" | awk '{print $1}')" ] || fail "the hardlink build did not hardlink"
echo "$e/lib/python3.12/site-packages/tqdm/cli.py" | purge
UV_LINK_MODE=hardlink; export UV_LINK_MODE
knob hl hl1 call script
[ "$(rc hl)" = 0 ] || { cat "$o/hl.err" >&2; fail "R3: hardlink repair"; }
uvm doctor > "$o/hl.doc" 2>&1 || { cat "$o/hl.doc" >&2; fail "R3: the hardlink repair left damage"; }
echo "P2 ok"
DRIVE
