#!/bin/sh
# P2 gate: trampolines under UVM_DATA and UVM_ROOT that enter the wrapper (R3, R6, R7, R9). Offline.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
grep -q '^uvm_record_write()' bin/uv-manager || { echo "FAIL: P1 has not landed" >&2; exit 1; }
REPO="$PWD" GATES="$PWD/spec/installed-tool-parity/gates" .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE' || exit 1
set -u
. "$GATES/lib.sh"
root="$UVM_ROOT/$a"
run warm uv --version
# Tree (F), a damaged tool the fixture repairs, beside a shim fx that is not it.
sp="$root/tools/fx/lib/python3.12/site-packages"; mkdir -p "$sp/fx-1.0.dist-info" "$root/tools/fx/bin"
: > "$root/tools/fx/pyvenv.cfg"; : > "$root/tools/fx/uv-receipt.toml"; ln -s /bin/sh "$root/tools/fx/bin/python"
printf 'fx/__init__.py,,\n' > "$sp/fx-1.0.dist-info/RECORD"
mkdir -p "$root/bin/shims"
printf '#!/bin/sh\n: > "%s/fx.ran"\necho fx-ran\nexit "${FX_RC:-0}"\n' "$o" > "$root/bin/shims/fx"; chmod +x "$root/bin/shims/fx"
run sync uvm trampolines
# fx has a shim and no record: its trampoline is this root's, in UVM_ROOT/bin, and UVM_DATA/bin has none.
t="$UVM_ROOT/bin/fx"
test -x "$t" || fail "R7: no trampoline at $t"
head -n 2 "$t" | grep -q 'uv-manager-trampoline' && head -n 1 "$t" | grep -qx '#!/bin/sh' && grep -q 'uname -m' "$t" || fail "R7: trampoline marker, /bin/sh or exec-time platform key"
test -d "$data/bin" || fail "R7: the sync did not create UVM_DATA/bin"
[ ! -e "$data/bin/fx" ] || fail "R7: a tool with no record has a trampoline in UVM_DATA/bin"
# The module's PATH: the record trampolines, then this root's.
PATH="$data/bin:$UVM_ROOT/bin:$PATH"; export PATH
pips() { grep -c 'pip install' "$@" 2>/dev/null | awk -F: '{ s += $NF } END { print s + 0 }'; }
# R3: a knob-set call by name checks the scope, then runs the tool with its own stdout and status.
if ! env SLURM_JOB_ID=100 UVM_REPAIR=1 fx > "$o/r3.out" 2> "$o/r3.err"; then cat "$o/r3.err" >&2; fail "R3: knob-set fx exited non-zero"; fi
[ "$(pips "$o/r3.err")" = 1 ] || { cat "$o/r3.err" >&2; fail "R3: expected one repair line on stderr"; }
[ "$(cat "$o/r3.out")" = fx-ran ] || fail "R3: stdout is not the tool's own: [$(cat "$o/r3.out")]"
test -e "$root/.repair/job-100.ok" || fail "R3: the job-100 scope was not recorded repaired"
env SLURM_JOB_ID=100 UVM_REPAIR=1 fx > "$o/r3b.out" 2> "$o/r3b.err" || fail "R3: second call exited non-zero"
[ "$(pips "$o/r3b.err")" = 0 ] || fail "R3: a second call in the scope repaired again"
env SLURM_JOB_ID=100 UVM_REPAIR=1 FX_RC=7 fx > /dev/null 2>&1; [ $? -eq 7 ] || fail "R3: the tool's exit status 7 was not kept"
mv "$o/fx.ran" "$trash/fx.ran.1"
if env SLURM_JOB_ID=101 UVM_REPAIR=1 UVM_FIXTURE_REPAIR_EXIT=1 fx > "$o/r3f.out" 2> "$o/r3f.err"; then fail "R3: a failed repair let fx exit 0"; fi
[ ! -e "$o/fx.ran" ] || fail "R3: the tool ran after a failed repair"
grep -q 'the repair for Slurm job 101 failed' "$o/r3f.err" || { cat "$o/r3f.err" >&2; fail "R3: the failure does not name its scope"; }
# R6: knob unset, the trampoline runs the shim and never starts the wrapper.
mkdir -p "$o/fake"; printf '#!/bin/sh\n: > "%s/entered"\nexit 99\n' "$o" > "$o/fake/uv-manager"; chmod +x "$o/fake/uv-manager"
for v in unset '' 0; do
    if [ "$v" = unset ]; then env -u UVM_REPAIR PATH="$o/fake:$PATH" fx > "$o/r6.out" 2>&1; else env UVM_REPAIR="$v" PATH="$o/fake:$PATH" fx > "$o/r6.out" 2>&1; fi
    [ "$(cat "$o/r6.out")" = fx-ran ] && [ ! -e "$o/entered" ] || fail "R6: UVM_REPAIR=$v started the wrapper or did not run the shim"
done
# R6: the unset path costs no more than release/0.8.0's trampoline.
printf '#!/bin/sh\nexit 0\n' > "$root/bin/shims/noop"; chmod +x "$root/bin/shims/noop"; run sync2 uvm trampolines
mkdir -p "$o/old/bin" "$o/oldroot/$a/bin/shims"; git -C "$REPO" show release/0.8.0:bin/uv-manager > "$o/old/bin/uv-manager"
chmod +x "$o/old/bin/uv-manager"; ln -s uv-manager "$o/old/bin/uvm"; ln -s uv-manager "$o/old/bin/uv"; cp "$root/bin/shims/noop" "$o/oldroot/$a/bin/shims/noop"
env UVM_ROOT="$o/oldroot" "$o/old/bin/uvm" trampolines > /dev/null 2>&1; test -x "$o/oldroot/bin/noop" || fail "R6: could not build release/0.8.0's trampoline"
loop() { _i=0; _s=$(date +%s); while [ "$_i" -lt 600 ]; do "$1"; _i=$((_i + 1)); done; echo $(( $(date +%s) - _s )); }
old=0 new=0
for r in 1 2; do old=$((old + $(loop "$o/oldroot/bin/noop"))); new=$((new + $(loop "$UVM_ROOT/bin/noop"))); done
echo "R6 timing: 1200 calls, release/0.8.0 ${old}s, this tree ${new}s" >&2
[ "$new" -le $((old + 1)) ] || fail "R6: the unset path costs more than release/0.8.0's (${new}s against ${old}s)"
# Upgrade path: a tree release/0.8.0 built, the 0.8.x module's PATH ($UVM_DATA/bin, then
# $UVM_ROOT/bin), no uv call yet. Ranks run the tool by name through its 0.7.0 trampoline.
m="$UVM_SANDBOX/mig" md="$UVM_SANDBOX/migdata"; mkdir -p "$m"
run mwarm env UVM_ROOT="$m" PATH="$o/old/bin:$PATH" uv --version
mkdir -p "$m/$a/bin/shims"; printf '#!/bin/sh\necho mig-ran\n' > "$m/$a/bin/shims/mig"; chmod +x "$m/$a/bin/shims/mig"
run msync env UVM_ROOT="$m" "$o/old/bin/uvm" trampolines
test -x "$m/bin/mig" && [ ! -e "$md" ] || fail "upgrade path: could not build the release/0.8.0 tree"
mp="$md/bin:$m/bin:$PATH"
_i=1 _p=''; while [ "$_i" -le 8 ]; do ( env UVM_ROOT="$m" UVM_DATA="$md" PATH="$mp" mig > "$o/mig.out.$_i" 2>&1; echo $? > "$o/mig.rc.$_i" ) & _p="$_p $!"; _i=$((_i + 1)); done; wait $_p
_i=1; while [ "$_i" -le 8 ]; do
    [ "$(cat "$o/mig.rc.$_i")" = 0 ] && [ "$(cat "$o/mig.out.$_i")" = mig-ran ] || fail "upgrade path: rank $_i: rc $(cat "$o/mig.rc.$_i") [$(cat "$o/mig.out.$_i")]"
    _i=$((_i + 1))
done
# The first uv call syncs once: it creates UVM_DATA/bin and rewrites the 0.7.0 trampoline in place,
# so a job script whose shell hashed that path before the call still runs the tool after it.
printf 'mig || exit 11\nuv --version > /dev/null 2>&1 || exit 12\nmig || exit 13\n' > "$o/job.sh"
env UVM_ROOT="$m" UVM_DATA="$md" PATH="$mp" bash "$o/job.sh" > "$o/job.out" 2> "$o/job.err"; rc=$?
[ "$rc" -eq 0 ] || { cat "$o/job.err" >&2; fail "upgrade path: a job script that ran the tool before the first uv call exited $rc"; }
[ "$(cat "$o/job.out")" = "$(printf 'mig-ran\nmig-ran')" ] || fail "upgrade path: the job script printed [$(cat "$o/job.out")]"
test -d "$md/bin" || fail "self-heal: no UVM_DATA/bin after the first uv call"
grep -q 'uv-manager-trampoline' "$m/bin/mig" && grep -q '_trampoline' "$m/bin/mig" || fail "self-heal: the 0.7.0 trampoline was not rewritten in place"
[ "$(env UVM_ROOT="$m" UVM_DATA="$md" PATH="$mp" mig 2>&1)" = mig-ran ] || fail "upgrade path: the rewritten trampoline does not run the tool"
# The self-heal is per root. Doctor run first, as the README says after an upgrade, or another
# root's first call, creates UVM_DATA/bin; the first uv call on this root still rewrites its 0.7.0
# trampoline, and a knob-set call by name then runs the scope check.
for how in doctor other; do
    h="$UVM_SANDBOX/h-$how" hd="$UVM_SANDBOX/hd-$how"; mkdir -p "$h"
    run "hw-$how" env UVM_ROOT="$h" PATH="$o/old/bin:$PATH" uv --version
    mkdir -p "$h/$a/bin/shims"; printf '#!/bin/sh\necho heal-ran\n' > "$h/$a/bin/shims/heal"; chmod +x "$h/$a/bin/shims/heal"
    run "hs-$how" env UVM_ROOT="$h" "$o/old/bin/uvm" trampolines
    if [ "$how" = doctor ]; then
        env UVM_ROOT="$h" UVM_DATA="$hd" uvm doctor > "$o/hd.out" 2>&1
    else
        mkdir -p "$UVM_SANDBOX/h-first"; run hfirst env UVM_ROOT="$UVM_SANDBOX/h-first" UVM_DATA="$hd" uv --version
    fi
    test -d "$hd/bin" && [ ! -e "$h/bin/.uv-manager-synced" ] || fail "self-heal ($how first): the setup did not create UVM_DATA/bin alone"
    run "hu-$how" env UVM_ROOT="$h" UVM_DATA="$hd" uv --version
    grep -q '_trampoline' "$h/bin/heal" || fail "self-heal ($how first): the first uv call did not rewrite this root's 0.7.0 trampoline"
    env UVM_ROOT="$h" UVM_DATA="$hd" PATH="$hd/bin:$h/bin:$PATH" SLURM_JOB_ID=300 UVM_REPAIR=1 heal > "$o/hk.out" 2> "$o/hk.err" || { cat "$o/hk.err" >&2; fail "R3 ($how first): knob-set heal exited non-zero"; }
    [ "$(cat "$o/hk.out")" = heal-ran ] && test -e "$h/$a/.repair/job-300.ok" || fail "R3 ($how first): a knob-set call by name skipped the scope check"
done
# An unwritable UVM_DATA costs the first call's one attempt: the second call syncs nothing.
u="$UVM_SANDBOX/h-ro" ud="$UVM_SANDBOX/hd-ro"; mkdir -p "$u" "$ud"
run hwro env UVM_ROOT="$u" PATH="$o/old/bin:$PATH" uv --version
mkdir -p "$u/$a/bin/shims"; printf '#!/bin/sh\necho ro-ran\n' > "$u/$a/bin/shims/rot"; chmod +x "$u/$a/bin/shims/rot"
run hsro env UVM_ROOT="$u" "$o/old/bin/uvm" trampolines
chmod 0555 "$ud"
run hro1 env UVM_ROOT="$u" UVM_DATA="$ud" uv --version; i1=$(ls -i "$u/bin/rot" | awk '{ print $1 }')
run hro2 env UVM_ROOT="$u" UVM_DATA="$ud" uv --version; i2=$(ls -i "$u/bin/rot" | awk '{ print $1 }')
chmod 0755 "$ud"
grep -q '_trampoline' "$u/bin/rot" || fail "self-heal: the first call did not sync this root beside an unwritable UVM_DATA"
[ ! -e "$ud/bin" ] || fail "self-heal: a sync wrote into an unwritable UVM_DATA"
[ "$i1" = "$i2" ] || fail "self-heal: with UVM_DATA unwritable, a second uv call synced again"
# The trigger is a marker in UVM_ROOT/bin that only a sync of that directory writes.
test -e "$m/bin/.uv-manager-synced" && test -e "$u/bin/.uv-manager-synced" || fail "self-heal: the sync wrote no marker in UVM_ROOT/bin"
# A trampoline write that fails after creating its file (a block quota) leaves every trampoline as it
# was and running, and leaves no marker, so the next call retries. The stand-in cat fails a write as
# cat does under EDQUOT: it creates nothing past the shell's redirection, and exits 1.
mkdir -p "$md/tools/mig" "$o/fq"; printf 'mig\n' > "$md/tools/mig/request"; printf 'mig\n' > "$md/tools/mig/entrypoints"
printf '#!/bin/sh\nif [ $# -eq 0 ]; then "%s" > /dev/null; echo "cat: stdout: Disc quota exceeded" >&2; exit 1; fi\nexec "%s" "$@"\n' "$(command -v cat)" "$(command -v cat)" > "$o/fq/cat"; chmod +x "$o/fq/cat"
run fq0 env UVM_ROOT="$m" UVM_DATA="$md" uvm trampolines
cp "$md/bin/mig" "$o/fq.data"; cp "$m/bin/mig" "$o/fq.root"; mv "$m/bin/.uv-manager-synced" "$trash/fq.marker"
for how in heal tool; do
    if [ "$how" = heal ]; then c='uv --version'; else c='uvm trampolines'; fi
    env UVM_ROOT="$m" UVM_DATA="$md" PATH="$o/fq:$PATH" $c > "$o/fq.out" 2> "$o/fq.err" || { cat "$o/fq.err" >&2; fail "failed write ($how): the call exited non-zero"; }
    cmp -s "$o/fq.data" "$md/bin/mig" && cmp -s "$o/fq.root" "$m/bin/mig" || fail "failed write ($how): a trampoline changed: $(wc -c < "$md/bin/mig") and $(wc -c < "$m/bin/mig") bytes"
    [ "$(env UVM_ROOT="$m" UVM_DATA="$md" PATH="$mp" mig 2>&1)" = mig-ran ] || fail "failed write ($how): the tool no longer runs"
    [ ! -e "$m/bin/.uv-manager-synced" ] || fail "failed write ($how): the sync wrote the marker"
    [ -z "$(ls -A "$m/bin" "$md/bin" | grep '^\.mig\.')" ] || fail "failed write ($how): a temporary file was left"
done
grep -q "left $md/bin and $m/bin as it was" "$o/fq.err" || { cat "$o/fq.err" >&2; fail "failed write: uvm trampolines reports a directory it did not finish"; }
run fq1 env UVM_ROOT="$m" UVM_DATA="$md" uv --version
test -e "$m/bin/.uv-manager-synced" || fail "failed write: the next call did not retry the sync"
mv "$md/tools/mig" "$trash/fq.rec"
# A marker that cannot be created beside a writable UVM_ROOT/bin (an inode quota; here a dangling
# link into a directory that cannot be written) skips the sync rather than run one on every call.
mkdir -p "$UVM_SANDBOX/mro"; mv "$u/bin/.uv-manager-synced" "$trash/mro.marker"; ln -s "$UVM_SANDBOX/mro/m" "$u/bin/.uv-manager-synced"
chmod 0555 "$UVM_SANDBOX/mro"; i1=$(ls -i "$u/bin/rot" | awk '{ print $1 }')
run mro1 env UVM_ROOT="$u" UVM_DATA="$ud" uv --version; run mro2 env UVM_ROOT="$u" UVM_DATA="$ud" uv --version
i2=$(ls -i "$u/bin/rot" | awk '{ print $1 }'); chmod 0755 "$UVM_SANDBOX/mro"
[ "$i1" = "$i2" ] || fail "self-heal: a marker that cannot be created cost a sync per call"
# R6: shape (S) with a record, rc 127, the tool named, the remedy, no lock, no outcome.
mkdir -p "$rec/fx"; printf 'fx\n' > "$rec/fx/request"; printf 'fx==1.0\n' > "$rec/fx/constraints"; printf '3.12\n' > "$rec/fx/python"; printf 'fx\n' > "$rec/fx/entrypoints"
mv "$root/bin/shims/fx" "$trash/fx.shim"; mv "$root/.repair" "$trash/repair.1"
env -u UVM_REPAIR fx > "$o/s.out" 2> "$o/s.err"; rc=$?
[ "$rc" -eq 127 ] || fail "R6: shape S exited $rc, not 127"
grep -q "'fx' is recorded but not installed" "$o/s.err" && grep -q UVM_REPAIR "$o/s.err" && grep -q 'uv-manager doctor' "$o/s.err" || { cat "$o/s.err" >&2; fail "R6: shape S message"; }
if grep -q 'another architecture' "$o/s.err"; then fail "R6: shape S still says another architecture"; fi
[ ! -e "$root/.repair" ] && [ ! -e "$root/.repair.lock" ] && [ ! -e "$root/.install.lock" ] || fail "R6: shape S took a lock or recorded an outcome"
mv "$rec/fx" "$trash/rec.fx"
env -u UVM_REPAIR fx > /dev/null 2> "$o/s0.err"; [ $? -eq 127 ] && grep -q "'fx' is not installed for architecture '$a'" "$o/s0.err" || fail "R6: without a record the 0.7.0 text"
mv "$trash/rec.fx" "$rec/fx"
# R7: a record keeps the trampoline past its shim; a sync and uv tool list leave it.
run sync3 uvm trampolines; run list uv tool list
test -x "$data/bin/fx" || fail "R7: the trampoline went with its shim"
[ ! -e "$UVM_ROOT/bin/fx" ] || fail "R7: this root kept a trampoline no shim of it names"
# R7: UVM_ROOT unset, the trampoline finds the tree through the cascade, and the wrapper exports both trees.
scr="$UVM_SANDBOX/scr"; mkdir -p "$scr"
run cwarm env -u UVM_ROOT SCRATCH="$scr" uv --version
mkdir -p "$scr/.uv/$a/bin/shims"; printf '#!/bin/sh\necho "fx2 $UVM_ROOT $UVM_DATA"\n' > "$scr/.uv/$a/bin/shims/fx2"; chmod +x "$scr/.uv/$a/bin/shims/fx2"
mkdir -p "$rec/fx2"; printf 'fx2\n' > "$rec/fx2/request"; printf 'fx2\n' > "$rec/fx2/entrypoints"
run csync env -u UVM_ROOT SCRATCH="$scr" uvm trampolines
[ "$(env -u UVM_ROOT SCRATCH="$scr" fx2)" = "fx2 $scr/.uv $data" ] || fail "R7: through the cascade: [$(env -u UVM_ROOT SCRATCH="$scr" fx2 2>&1)]"
[ "$(env -u UVM_ROOT SCRATCH="$scr" "$scr/.uv/bin/fx2")" = "fx2 $scr/.uv $data" ] || fail "R7: the root's trampoline through the cascade"
# R6: the knob-off entry the cascade takes creates nothing, missing directories included.
mv "$scr/.uv/$a/cache" "$trash/scr.cache"; mv "$scr/.uv/$a/python" "$trash/scr.python"
[ "$(env -u UVM_ROOT -u UVM_REPAIR SCRATCH="$scr" fx2)" = "fx2 $scr/.uv $data" ] || fail "R6: knob off through the cascade"
[ ! -e "$scr/.uv/$a/cache" ] && [ ! -e "$scr/.uv/$a/python" ] || fail "R6: the knob-off entry created the tree's directories"
if env -u UVM_ROOT fx2 > /dev/null 2> "$o/noroot.err"; then fail "R7: no root resolved, yet exit 0"; fi
grep -q UVM_ROOT "$o/noroot.err" || fail "R7: the failure does not name UVM_ROOT"
# R7: in UVM_ROOT/bin a sync rewrites in place a marked 0.7.0 trampoline a shim names, removes
# one no shim names, and leaves an unmarked script.
mkdir -p "$UVM_ROOT/bin"; cp "$o/oldroot/bin/noop" "$UVM_ROOT/bin/old"; cp "$o/oldroot/bin/noop" "$UVM_ROOT/bin/noop"
printf '#!/bin/sh\necho mine\n' > "$UVM_ROOT/bin/mine"; chmod +x "$UVM_ROOT/bin/mine"
run sync4 uvm trampolines
[ ! -e "$UVM_ROOT/bin/old" ] || fail "R7: a 0.7.0 trampoline no shim names stayed"
grep -q '_trampoline' "$UVM_ROOT/bin/noop" || fail "R7: a 0.7.0 trampoline a shim names was not rewritten in place"
[ "$(cat "$UVM_ROOT/bin/mine")" = "$(printf '#!/bin/sh\necho mine')" ] || fail "R7: an unmarked script was touched"
# R7: a UVM_DATA/bin that cannot be written is left as it is, and this root's trampolines still sync.
cp "$o/oldroot/bin/noop" "$UVM_ROOT/bin/noop"; cp "$data/bin/fx" "$data/bin/stale"
ls "$data/bin" > "$o/ro.before"; chmod 0555 "$data/bin"
uvm trampolines > "$o/ro.out" 2> "$o/ro.err"; rc=$?
ls "$data/bin" > "$o/ro.after"; chmod 0755 "$data/bin"
[ "$rc" -eq 0 ] || { cat "$o/ro.err" >&2; fail "R7: a sync into an unwritable UVM_DATA/bin exited $rc"; }
if grep -i 'denied' "$o/ro.err"; then fail "R7: a sync wrote into an unwritable UVM_DATA/bin"; fi
cmp -s "$o/ro.before" "$o/ro.after" || fail "R7: an unwritable UVM_DATA/bin changed"
if grep -q "synced in.*$data/bin" "$o/ro.err"; then cat "$o/ro.err" >&2; fail "uvm trampolines reports a sync of the UVM_DATA/bin it left"; fi
grep -q "left $data/bin as it was" "$o/ro.err" || { cat "$o/ro.err" >&2; fail "uvm trampolines does not name the directory it left"; }
grep -q '_trampoline' "$UVM_ROOT/bin/noop" || fail "R7: this root's trampolines did not sync beside an unwritable UVM_DATA/bin"
# R7: one UVM_DATA shared by two roots. Root B holds a managed interpreter's shim, a tool with no
# record and a tool with one; syncs, doctor and uv tool list on root A leave all three running on B.
ra="$UVM_SANDBOX/ra" rb="$UVM_SANDBOX/rb" sd="$UVM_SANDBOX/sd"; mkdir -p "$ra" "$rb"
run raw env UVM_ROOT="$ra" UVM_DATA="$sd" uv --version; run rbw env UVM_ROOT="$rb" UVM_DATA="$sd" uv --version
mkdir -p "$rb/$a/bin/python-shims" "$rb/$a/bin/shims" "$sd/tools/rx"
printf '#!/bin/sh\necho python3.12-ran\n' > "$rb/$a/bin/python-shims/python3.12"
for n in gx rx; do printf '#!/bin/sh\necho %s-ran\n' "$n" > "$rb/$a/bin/shims/$n"; done
chmod +x "$rb/$a/bin/python-shims/python3.12" "$rb/$a/bin/shims/gx" "$rb/$a/bin/shims/rx"
printf 'rx\n' > "$sd/tools/rx/request"; printf 'rx\n' > "$sd/tools/rx/entrypoints"
run rbsync env UVM_ROOT="$rb" UVM_DATA="$sd" uvm trampolines
env UVM_ROOT="$ra" UVM_DATA="$sd" uvm doctor > "$o/radoc.out" 2>&1
run ralist env UVM_ROOT="$ra" UVM_DATA="$sd" uv tool list
run rasync env UVM_ROOT="$ra" UVM_DATA="$sd" uvm trampolines
for n in python3.12 gx rx; do
    [ "$(env UVM_ROOT="$rb" UVM_DATA="$sd" PATH="$sd/bin:$rb/bin:$PATH" "$n" 2>&1)" = "$n-ran" ] || fail "R7: a sync on root A broke $n on root B"
done
[ ! -e "$ra/bin/gx" ] && [ ! -e "$sd/bin/gx" ] || fail "R7: root B's trampoline for a tool with no record left root B"
echo "P2 ok"
DRIVE
st=$?; [ "$st" -eq 0 ] || exit "$st"
# R9: UVM_DATA/bin first on PATH, the 0.7.0 UVM_ROOT/bin after it (a later prepend lands first).
lr=$(grep -n 'prepend_path("PATH", pathJoin(root, "bin"))' share/modulefiles/uv/main.lua | cut -d: -f1)
ld=$(grep -n 'prepend_path("PATH".*uvm/bin' share/modulefiles/uv/main.lua | cut -d: -f1)
[ -n "$lr" ] && [ -n "$ld" ] && [ "$ld" -gt "$lr" ] || { echo "FAIL R9: the modulefile must prepend UVM_DATA/bin after UVM_ROOT/bin" >&2; exit 1; }
grep -qF 'tag="${HOSTNAME:-}.$$.${RANDOM}"' bin/uv-manager || { echo "FAIL: a trampoline's temporary name does not carry the host" >&2; exit 1; }
for f in AGENTS.md .agents/factory/invariants.md; do git grep -q 'UVM_DATA/bin' -- "$f" || { echo "FAIL: $f does not state the trampoline directory" >&2; exit 1; }; done
if git grep -n 'never enters the wrapper; use `uvx <tool>` in the job script' -- README.md; then echo "FAIL R12: README still says a tool by name skips the check" >&2; exit 1; fi
echo "P2 gate ok"
