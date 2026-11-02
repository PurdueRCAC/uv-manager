#!/bin/sh
# P3 gate: a recorded tool comes back from its record (R1, R4, R8, R10).
# Real uv and network: pypi.org, files.pythonhosted.org, github.com,
# codeload.github.com, releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
grep -q '^uvm_tool_entry()' bin/uv-manager || { echo "FAIL: P2 has not landed" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
SEED_UV="$u" REPO="$PWD" GATES="$PWD/spec/installed-tool-parity/gates" .agents/factory/bin/temp_root.sh sh -s <<'DRIVE' || exit 1
set -u
. "$GATES/lib.sh"
UV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE
PATH="$data/bin:$UVM_ROOT/bin:$PATH"; export PATH
root="$UVM_ROOT/$a"; n=0
seed "$a"; run py uv python install 3.12
# The tool pair and a git tool, installed through the wrapper so each has a record.
run i1 uv tool install -p 3.12 pyflakes==3.2.0 --with tomli==2.0.1
run i2 uv tool install -p 3.12 pycodestyle==2.11.1 --with six==1.16.0
run i3 uv tool install -p 3.12 pycodestyle --with six
run i4 uv tool install -p 3.12 git+https://github.com/glentner/progressbar
tools="pyflakes pycodestyle progressbar"
for t in $tools; do frozen "$t" > "$o/f0.$t"; cp "$root/tools/$t/uv-receipt.toml" "$o/rcpt0.$t"; done
[ "$(grep -c '' "$o/f0.pycodestyle")" -eq 2 ] && grep -qx 'pycodestyle-2.11.1' "$o/f0.pycodestyle" || fail "the unpinned tool is not at its older release"
commit() { sed -n 's/.*"commit_id":"\([0-9a-f]*\)".*/\1/p' "$root/tools/progressbar"/lib/*/site-packages/progressbar-*.dist-info/direct_url.json 2>/dev/null; }
c0=$(commit); [ -n "$c0" ] || fail "no commit recorded for the git tool"
cp -R "$rec" "$o/rec0"
damage() {  # SHAPE: apply it to all three tools
    for t in pyflakes:pyflakes pycodestyle:pycodestyle progressbar:pb; do
        tool=${t%%:*} ep=${t##*:} d="$root/tools/${t%%:*}"; n=$((n + 1))
        case "$1" in
            W) mv "$d" "$trash/W.$tool.$n" ;;
            E) find "$d" -type f -delete ;;
            R) mv "$d/uv-receipt.toml" "$trash/R.$tool.$n" ;;
            S) mv "$root/bin/shims/$ep" "$trash/S.$tool.$n" ;;
        esac || fail "damage $1 on $tool"
    done
}
ranks() {  # N LABEL VIA: N concurrent knob-set calls, rank i running tool i mod 3, by name or through uvx
    _n=$1 _l=$2 _via=$3 _i=1 _p=''
    while [ "$_i" -le "$_n" ]; do
        case "$_via.$((_i % 3))" in
            name.0) set -- pyflakes --version ;;  name.1) set -- pycodestyle --version ;;  name.2) set -- pb --version ;;
            uvx.0) set -- uvx pyflakes --version ;; uvx.1) set -- uvx pycodestyle --version ;; uvx.2) set -- uvx --from progressbar pb --version ;;
        esac
        ( env UVM_REPAIR="$KNOB" UVM_LOCK_TIMEOUT=180 "$@" > "$o/$_l.out.$_i" 2> "$o/$_l.err.$_i"; echo $? > "$o/$_l.rc.$_i" ) &
        _p="$_p $!"; _i=$((_i + 1))
    done
    wait $_p
}
check() {  # N LABEL: every rank exits 0 with its tool's output; exactly one announces the restore
    _n=$1 _l=$2 _i=1 _r=0
    while [ "$_i" -le "$_n" ]; do
        [ "$(cat "$o/$_l.rc.$_i")" = 0 ] || { cat "$o/$_l.err.$_i" >&2; fail "$_l: rank $_i exited $(cat "$o/$_l.rc.$_i")"; }
        _out=$(cat "$o/$_l.out.$_i")
        case "$((_i % 3)).$_out" in 0."3.2.0 Python 3.12."*|1.2.11.1|2."pb v1.2.1") ;; *) fail "$_l: rank $_i printed [$_out]" ;; esac
        _r=$((_r + $(grep -c 'uv-manager: restoring the installed tools' "$o/$_l.err.$_i")))
        _i=$((_i + 1))
    done
    [ "$_r" -eq 1 ] || fail "$_l: $_r ranks announced a restore, expected exactly 1"
    [ ! -d "$root/.repair.lock" ] || fail "$_l: the repair lock was left"
}
equal() {  # LABEL: R1's equalities
    for t in $tools; do
        frozen "$t" | cmp -s "$o/f0.$t" - || fail "$1: R1: $t's dist-info listing changed: $(frozen "$t" | tr '\n' ' ')"
        grep -q '^version_info = 3\.12\.' "$root/tools/$t/pyvenv.cfg" || fail "$1: R1: $t is not on 3.12"
        cmp -s "$o/rcpt0.$t" "$root/tools/$t/uv-receipt.toml" || fail "$1: N1: $t's receipt was not put back"
        [ ! -e "$root/tools/$t/.uvm-restored" ] || fail "$1: N1: $t is marked pinned in its own tree"
    done
    [ "$(commit)" = "$c0" ] || fail "$1: R1: the git tool's commit changed"
    diff -r "$o/rec0" "$rec" > /dev/null || fail "$1: R1: a record changed"
}
# R4 and R1: each shape, 16 ranks by name, then 3 through uvx.
for s in W E R S; do
    damage "$s"; KNOB="r4-$s"; ranks 16 "$s" name; check 16 "$s"; equal "$s"
    damage "$s"; KNOB="r4x-$s"; ranks 3 "x$s" uvx; check 3 "x$s"; equal "x$s"
done
# R4: a restore that fails fails every rank promptly, with its reason.
damage W; KNOB=r4-fail
_i=1 _p=''; while [ "$_i" -le 4 ]; do ( env UVM_REPAIR="$KNOB" UV_OFFLINE=1 pyflakes --version > "$o/f.out.$_i" 2> "$o/f.err.$_i"; echo $? > "$o/f.rc.$_i" ) & _p="$_p $!"; _i=$((_i + 1)); done; wait $_p
_i=1; while [ "$_i" -le 4 ]; do
    [ "$(cat "$o/f.rc.$_i")" != 0 ] || fail "R4: a rank exited 0 after a failed restore"
    grep -q 'the repair for UVM_REPAIR=r4-fail failed: the restore of tool [a-z]* from its record failed' "$o/f.err.$_i" || { cat "$o/f.err.$_i" >&2; fail "R4: rank $_i does not carry the reason"; }
    _i=$((_i + 1))
done
KNOB=r4-again; ranks 3 again name; check 3 again
# N1: the unpinned tool, restored, still upgrades as an unpurged twin does.
run up uv tool upgrade pycodestyle
if frozen pycodestyle | grep -qx 'pycodestyle-2.11.1'; then fail "N1: uv tool upgrade left the restored tool at 2.11.1"; fi
# R4: a twin with no record, in shape (E), fails the scope naming pyvenv.cfg, as on 0.7.0.
mv "$rec/pycodestyle" "$trash/rec.pycodestyle"; find "$root/tools/pycodestyle" -type f -delete
if env UVM_REPAIR=r4-norec pycodestyle --version > "$o/nr.out" 2> "$o/nr.err"; then fail "R4: an unrecorded tool in shape E ran"; fi
grep -q 'pyvenv.cfg' "$o/nr.err" || { cat "$o/nr.err" >&2; fail "R4: the refusal does not name pyvenv.cfg"; }
run fix uv tool install -p 3.12 --force pycodestyle==2.11.1 --with six==1.16.0
# N9: a local source is recorded, and its restore refuses naming the tool and the source.
printf 'six==1.16.0\n' > "$o/reqs.txt"
run lc uv tool install -p 3.12 pycowsay==0.0.0.2 --with-requirements "$o/reqs.txt"
mv "$root/tools/pycowsay" "$trash/W.pycowsay"
if env UVM_REPAIR=n9 pycowsay > "$o/lc.out" 2> "$o/lc.err"; then fail "N9: a local-source tool was restored"; fi
grep -q 'tool pycowsay was installed from --with-requirements' "$o/lc.err" || { cat "$o/lc.err" >&2; fail "N9: the refusal"; }
# R2: an uninstall removes the record and the trampoline.
run rmlc uv tool install -p 3.12 --force pycowsay==0.0.0.2
run un uv tool uninstall pycowsay
[ ! -e "$rec/pycowsay" ] && [ ! -e "$data/bin/pycowsay" ] || fail "R2: uninstall left the record or the trampoline"
# R10: uvx on a tree with no installed tool: one repaired outcome, nothing under UVM_DATA.
r10="$UVM_SANDBOX/r10"; mkdir -p "$r10"; d10="$UVM_SANDBOX/d10"
(UVM_ROOT="$r10"; seed "$a")
run r10 env UVM_ROOT="$r10" UVM_DATA="$d10" SLURM_JOB_ID=200 UVM_REPAIR=1 uvx pycowsay==0.0.0.2
test -e "$r10/$a/.repair/job-200.ok" || fail "R10: no repaired outcome for job 200"
if [ -d "$d10" ] && [ -n "$(find "$d10" -type f)" ]; then fail "R10: uvx wrote under UVM_DATA"; fi
# R8: a tree the 0.7.0 wrapper built; doctor backfills, writes nothing under UVM_ROOT.
r8="$UVM_SANDBOX/r8"; d8="$UVM_SANDBOX/d8"; mkdir -p "$r8" "$o/old/bin"
git -C "$REPO" show 0.7.0:bin/uv-manager > "$o/old/bin/uv-manager"; chmod +x "$o/old/bin/uv-manager"
for l in uv uvx uvm; do ln -s uv-manager "$o/old/bin/$l"; done
(UVM_ROOT="$r8"; seed "$a")
for spec in "pyflakes==3.2.0 --with tomli==2.0.1" "pycodestyle==2.11.1 --with six==1.16.0" "pycodestyle --with six" "git+https://github.com/glentner/progressbar"; do
    # shellcheck disable=SC2086
    run old env UVM_ROOT="$r8" UVM_DATA="$d8" PATH="$o/old/bin:$PATH" uv tool install -p 3.12 $spec
done
[ ! -d "$d8/tools" ] || fail "R8: the 0.7.0 wrapper wrote records"
for t in $tools; do (UVM_ROOT="$r8"; frozen "$t") > "$o/f8.$t"; done
(cd "$r8" && find . -type f -exec cksum {} + | LC_ALL=C sort) > "$o/r8.before"
env UVM_ROOT="$r8" UVM_DATA="$d8" uvm doctor > "$o/doc8.out" 2>&1 || { cat "$o/doc8.out" >&2; fail "R8: doctor on a healthy tree exited non-zero"; }
(cd "$r8" && find . -type f -exec cksum {} + | LC_ALL=C sort) | cmp -s "$o/r8.before" - || fail "R8: doctor wrote under UVM_ROOT"
for t in $tools; do test -f "$d8/tools/$t/request" || fail "R8: doctor wrote no record for $t"; done
for e in pyflakes pycodestyle pb; do test -x "$d8/bin/$e" || fail "R8: doctor did not generate the trampoline $e"; done
for t in pyflakes:pyflakes pycodestyle:pycodestyle progressbar:pb; do mv "$r8/$a/tools/${t%%:*}" "$trash/r8.${t%%:*}"; done
for e in "pyflakes --version" "pycodestyle --version" "pb --version"; do
    # shellcheck disable=SC2086
    run r8run env UVM_ROOT="$r8" UVM_DATA="$d8" UVM_REPAIR=r8 PATH="$d8/bin:$PATH" $e
done
for t in $tools; do (UVM_ROOT="$r8"; frozen "$t") | cmp -s "$o/f8.$t" - || fail "R8: $t did not come back from its backfilled record"; done
# R8: a recorded tool with no trace here is an advisory naming its remedy.
cp -R "$d8/tools/pyflakes" "$d8/tools/ghost"; printf 'ghost\n' > "$d8/tools/ghost/entrypoints"
env UVM_ROOT="$r8" UVM_DATA="$d8" uvm doctor > "$o/doc8b.out" 2>&1 || { cat "$o/doc8b.out" >&2; fail "R8: an absent recorded tool failed doctor"; }
grep -q '^WARN  tool ghost is recorded but not installed' "$o/doc8b.out" && grep -q UVM_REPAIR "$o/doc8b.out" || { cat "$o/doc8b.out" >&2; fail "R8: no advisory for the absent tool"; }
# R7, R8: a user who only runs jobs after the upgrade. The walk's holder backfills the record and
# writes its trampoline with it, so once a purge takes the tool and its 0.7.0 trampoline on scratch,
# the tool still runs by name.
rj="$UVM_SANDBOX/rj" dj="$UVM_SANDBOX/dj"; mkdir -p "$rj"
(UVM_ROOT="$rj"; seed "$a")
run oldj env UVM_ROOT="$rj" PATH="$o/old/bin:$PATH" uv tool install -p 3.12 pycodestyle==2.11.1
test -x "$rj/bin/pycodestyle" && [ ! -d "$dj" ] || fail "jobs-only: could not build the 0.7.0 tree"
run j1 env UVM_ROOT="$rj" UVM_DATA="$dj" SLURM_JOB_ID=401 UVM_REPAIR=1 uv --version
test -f "$dj/tools/pycodestyle/request" || fail "R8: the walk's holder wrote no record"
test -x "$dj/bin/pycodestyle" || fail "R7: the walk's holder wrote the record without its trampoline"
find "$rj/$a/tools/pycodestyle" -type f -delete; mv "$rj/bin/pycodestyle" "$trash/rj.pycodestyle"
_out=$(env UVM_ROOT="$rj" UVM_DATA="$dj" PATH="$dj/bin:$rj/bin:$PATH" SLURM_JOB_ID=402 UVM_REPAIR=1 pycodestyle --version 2> "$o/j2.err") \
    || { cat "$o/j2.err" >&2; fail "R7: after a purge, a tool backfilled in a job does not run by name"; }
[ "$_out" = 2.11.1 ] || fail "R7: the tool backfilled in a job printed [$_out]"
# R1, R4: a git tool built from a subdirectory restores at its commit, from the record its
# install wrote and from a backfilled one; uv renders that requirement across two lines.
mono="$UVM_SANDBOX/mono"; mkdir -p "$mono/pkg"
printf '[build-system]\nrequires = ["setuptools>=61"]\nbuild-backend = "setuptools.build_meta"\n[project]\nname = "subtool"\nversion = "0.1.0"\n[project.scripts]\nsubtool = "subtool:main"\n' > "$mono/pkg/pyproject.toml"
printf 'def main():\n    print("subtool-ran")\n' > "$mono/pkg/subtool.py"
{ git -C "$mono" init -q && git -C "$mono" add -A && git -C "$mono" -c user.email=gate@example.invalid -c user.name=gate commit -qm one; } || fail "building the subdirectory repository"
run sub uv tool install -p 3.12 "git+file://$mono#subdirectory=pkg"
grep -Eqx "subtool @ git\+file://$mono@[0-9a-f]{40}#subdirectory=pkg" "$rec/subtool/constraints" || fail "R1: the VCS constraint dropped its subdirectory: $(cat "$rec/subtool/constraints")"
for how in install backfill; do
    if [ "$how" = backfill ]; then
        mv "$rec/subtool" "$trash/rec.subtool"; run sublist uv tool list
        grep -qx "git+file://$mono#subdirectory=pkg" "$rec/subtool/request" || fail "R8: the backfilled request is not the subdirectory URL: $(cat "$rec/subtool/request")"
    fi
    find "$root/tools/subtool" -type f -delete
    _out=$(env UVM_REPAIR="sub-$how" subtool 2> "$o/sub.$how.err") || { cat "$o/sub.$how.err" >&2; fail "R4: the subdirectory tool was not restored from its $how record"; }
    [ "$_out" = subtool-ran ] || fail "R4: the restored subdirectory tool printed [$_out]"
done
# R8: a --with direct URL is backfilled in the form uv reads, and the tool comes back with it.
w6="six @ https://files.pythonhosted.org/packages/d9/5a/e7c31adbe875f2abbb91bd84cf2dc52d792b5a01506781dbcf25c91daf11/six-1.16.0-py2.py3-none-any.whl"
run wu uv tool install -p 3.12 pycowsay==0.0.0.2 --with "$w6"
frozen pycowsay > "$o/f0.pycowsay"
mv "$rec/pycowsay" "$trash/rec.pycowsay.w"; run wulist uv tool list
grep -qxF "$w6" "$rec/pycowsay/request" || fail "R8: the --with direct URL was not backfilled as name @ URL: $(cat "$rec/pycowsay/request")"
mv "$root/tools/pycowsay" "$trash/W.pycowsay.w"
env UVM_REPAIR=wurl pycowsay hi > /dev/null 2> "$o/wu.err" || { cat "$o/wu.err" >&2; fail "R8: the tool with a --with direct URL was not restored"; }
frozen pycowsay | cmp -s "$o/f0.pycowsay" - || fail "R8: the restore of a --with direct URL changed the environment"
# R8: the receipt's index options are carried into a backfilled request, so its restore uses them.
run ix uv tool install -p 3.12 --index-url https://pypi.org/simple --extra-index-url https://pypi.org/simple/ pygments==2.18.0
mv "$rec/pygments" "$trash/rec.pygments"; run ixlist uv tool list
[ "$(cat "$rec/pygments/request")" = "$(printf '%s\n' pygments==2.18.0 --index-url https://pypi.org/simple --extra-index-url https://pypi.org/simple/)" ] || fail "R8: the backfilled request lacks the receipt's indexes: $(cat "$rec/pygments/request")"
mv "$root/tools/pygments" "$trash/W.pygments"
env UV_INDEX_URL=http://127.0.0.1:9/simple UVM_REPAIR=ix pygmentize -V > /dev/null 2> "$o/ix.err" || { cat "$o/ix.err" >&2; fail "R8: a backfilled record did not restore from its own index"; }
# R8: indexes uv writes as an array of inline tables, the default among them, and the strategy.
run dx uv tool install -p 3.12 --force --default-index https://pypi.org/simple --index https://pypi.org/simple/ --index-strategy unsafe-best-match pygments==2.18.0
mv "$rec/pygments" "$trash/rec.pygments.dx"; run dxlist uv tool list
[ "$(cat "$rec/pygments/request")" = "$(printf '%s\n' pygments==2.18.0 --default-index https://pypi.org/simple --index https://pypi.org/simple/ --index-strategy unsafe-best-match)" ] || fail "R8: the backfilled request lacks the receipt's index tables or strategy: $(cat "$rec/pygments/request")"
mv "$root/tools/pygments" "$trash/W.pygments.dx"
env UV_DEFAULT_INDEX=http://127.0.0.1:9/simple UVM_REPAIR=dx pygmentize -V > /dev/null 2> "$o/dx.err" || { cat "$o/dx.err" >&2; fail "R8: a backfilled record did not restore from its own default index"; }
# R8: with uv's tools/.lock gone, as a purge takes it, doctor writes nothing under UVM_ROOT and
# names the tool with no record and the command that writes one.
mv "$rec/pycowsay" "$trash/rec.pycowsay.lock"; mv "$root/tools/.lock" "$trash/tools.lock"
(cd "$UVM_ROOT" && find . -type f -exec cksum {} + | LC_ALL=C sort) > "$o/lk.before"
uvm doctor > "$o/lk.doc" 2>&1
(cd "$UVM_ROOT" && find . -type f -exec cksum {} + | LC_ALL=C sort) | cmp -s "$o/lk.before" - || fail "R8: doctor wrote under UVM_ROOT where uv's tools/.lock was missing"
[ ! -e "$rec/pycowsay" ] || fail "R8: doctor backfilled without uv's lock file"
grep -q '^WARN  tool pycowsay has no record.* uv tool list writes one' "$o/lk.doc" || { cat "$o/lk.doc" >&2; fail "R8: doctor does not name the tool with no record and the command that writes one"; }
mv "$trash/tools.lock" "$root/tools/.lock"; run lklist uv tool list; test -f "$rec/pycowsay/request" || fail "R8: uv tool list did not backfill"
# R8: a git tool whose direct_url.json a purge took gets no record, keeps 0.7.0's refusal,
# and doctor names it; a record pinned by version alone would restore the branch head.
r1g="$UVM_SANDBOX/repo1"; mkdir -p "$r1g"
printf '[build-system]\nrequires = ["setuptools>=61"]\nbuild-backend = "setuptools.build_meta"\n[project]\nname = "roottool"\nversion = "0.1.0"\n[project.scripts]\nroottool = "roottool:main"\n' > "$r1g/pyproject.toml"
printf 'def main():\n    print("roottool-one")\n' > "$r1g/roottool.py"
{ git -C "$r1g" init -q && git -C "$r1g" add -A && git -C "$r1g" -c user.email=gate@example.invalid -c user.name=gate commit -qm one; } || fail "building the git repository"
run rt uv tool install -p 3.12 "git+file://$r1g"
printf 'def main():\n    print("roottool-two")\n' > "$r1g/roottool.py"
git -C "$r1g" -c user.email=gate@example.invalid -c user.name=gate commit -qam two || fail "moving the branch"
mv "$rec/roottool" "$trash/rec.roottool"
for _j in "$root"/tools/roottool/lib/*/site-packages/roottool-*.dist-info/direct_url.json; do mv "$_j" "$trash/durl.roottool"; done
run rtlist uv tool list
[ ! -e "$rec/roottool" ] || fail "R8: a git tool whose direct_url.json is gone was backfilled: $(cat "$rec/roottool/constraints")"
uvm doctor > "$o/rt.doc" 2>&1
grep -q '^WARN  tool roottool has no record: its receipt records roottool from its git source' "$o/rt.doc" || { cat "$o/rt.doc" >&2; fail "R8: doctor does not name the tool it could not record"; }
if env UVM_REPAIR=rt roottool > "$o/rt.out" 2> "$o/rt.err"; then fail "R4: an unpinnable git tool ran: [$(cat "$o/rt.out")]"; fi
grep -q 'roottool from its git source in its receipt' "$o/rt.err" || { cat "$o/rt.err" >&2; fail "R4: the unpinnable git tool lost 0.7.0's refusal"; }
# R8: the check is per requirement. A git tool whose own direct_url.json a purge took gets no
# record, though a git dependency of it kept its own.
dg="$UVM_SANDBOX/depgit" tg="$UVM_SANDBOX/topgit"; mkdir -p "$dg" "$tg"
printf '[build-system]\nrequires = ["setuptools>=61"]\nbuild-backend = "setuptools.build_meta"\n[project]\nname = "depgit"\nversion = "0.1.0"\n' > "$dg/pyproject.toml"
printf 'VALUE = 1\n' > "$dg/depgit.py"
printf '[build-system]\nrequires = ["setuptools>=61"]\nbuild-backend = "setuptools.build_meta"\n[project]\nname = "topgit"\nversion = "0.1.0"\ndependencies = ["depgit @ git+file://%s"]\n[project.scripts]\ntopgit = "topgit:main"\n' "$dg" > "$tg/pyproject.toml"
printf 'def main():\n    print("topgit-one")\n' > "$tg/topgit.py"
for _g in "$dg" "$tg"; do
    { git -C "$_g" init -q && git -C "$_g" add -A && git -C "$_g" -c user.email=gate@example.invalid -c user.name=gate commit -qm one; } || fail "building the git repositories"
done
run tg uv tool install -p 3.12 "git+file://$tg"
mv "$rec/topgit" "$trash/rec.topgit"
for _j in "$root"/tools/topgit/lib/*/site-packages/topgit-*.dist-info/direct_url.json; do mv "$_j" "$trash/durl.topgit"; done
[ -n "$(find "$root/tools/topgit" -path '*depgit-*.dist-info/direct_url.json')" ] || fail "the git dependency kept no direct_url.json"
run tglist uv tool list
[ ! -e "$rec/topgit" ] || fail "R8: a git tool whose own direct_url.json is gone was backfilled on its dependency's: $(cat "$rec/topgit/constraints")"
echo "P3 ok"
DRIVE
