#!/bin/sh
# P4 gate: a recorded tool with no trace here comes back when run by name (R5).
# Real uv and network: pypi.org, files.pythonhosted.org, releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
grep -q '^uvm_restore()' bin/uv-manager || { echo "FAIL: P3 has not landed" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
SEED_UV="$u" GATES="$PWD/spec/installed-tool-parity/gates" .agents/factory/bin/temp_root.sh sh -s <<'DRIVE' || exit 1
set -u
. "$GATES/lib.sh"
UV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE
PATH="$data/bin:$PATH"; export PATH
b=uvmfake; seed "$a"; seed "$b"
run py uv python install 3.12
run i1 uv tool install -p 3.12 pyflakes==3.2.0
run i2 uv tool install -p 3.12 pycodestyle==2.11.1
frozen pyflakes > "$o/f0"
# Key B: 8 ranks by name, one restore of that tool alone.
_i=1 _p=''; while [ "$_i" -le 8 ]; do ( env UVM_PLATFORM="$b" UVM_REPAIR=1 SLURM_JOB_ID=500 pyflakes --version > "$o/k.out.$_i" 2> "$o/k.err.$_i"; echo $? > "$o/k.rc.$_i" ) & _p="$_p $!"; _i=$((_i + 1)); done; wait $_p
_i=1 _r=0; while [ "$_i" -le 8 ]; do
    [ "$(cat "$o/k.rc.$_i")" = 0 ] || { cat "$o/k.err.$_i" >&2; fail "R5: rank $_i exited $(cat "$o/k.rc.$_i")"; }
    case "$(cat "$o/k.out.$_i")" in "3.2.0 Python 3.12."*) ;; *) fail "R5: rank $_i printed [$(cat "$o/k.out.$_i")]" ;; esac
    _r=$((_r + $(grep -c 'uv-manager: restoring the installed tool pyflakes' "$o/k.err.$_i"))); _i=$((_i + 1))
done
[ "$_r" -eq 1 ] || fail "R5: $_r ranks restored, expected exactly 1"
frozen pyflakes "$b" | cmp -s "$o/f0" - || fail "R5: pyflakes on key B differs from key A"
[ ! -e "$UVM_ROOT/$b/tools/pycodestyle" ] || fail "R5: a tool not run by name was restored on key B"
[ ! -d "$UVM_ROOT/$b/.repair.lock" ] || fail "R5: the repair lock was left"
# Key B: the walk restores nothing that has no trace there.
env UVM_PLATFORM="$b" UVM_REPAIR=2 uv --version > /dev/null 2> "$o/w.err" || { cat "$o/w.err" >&2; fail "R5: knob-set uv --version on key B"; }
if grep -q 'uv-manager: restoring' "$o/w.err"; then fail "R5: the walk restored a tool with no trace"; fi
[ ! -e "$UVM_ROOT/$b/tools/pycodestyle" ] || fail "R5: the walk restored pycodestyle on key B"
# N1 across keys: the receipt names key A's tree, so the restored tool is reported pinned by a restore.
env UVM_PLATFORM="$b" uvm doctor > "$o/doc" 2>&1 || { cat "$o/doc" >&2; fail "doctor on key B exited non-zero"; }
grep -q '^WARN  tool pyflakes is pinned by a restore' "$o/doc" || { cat "$o/doc" >&2; fail "N1: doctor does not report the hold"; }
grep -q '^WARN  tool pycodestyle is recorded but not installed' "$o/doc" || fail "R8: no advisory for pycodestyle on key B"
# A failed restore by name fails every waiter promptly with its reason.
s0=$(date +%s)
_i=1 _p=''; while [ "$_i" -le 4 ]; do ( env UVM_PLATFORM="$b" UVM_REPAIR=1 SLURM_JOB_ID=501 UV_OFFLINE=1 UVM_LOCK_TIMEOUT=60 pycodestyle --version > /dev/null 2> "$o/f.err.$_i"; echo $? > "$o/f.rc.$_i" ) & _p="$_p $!"; _i=$((_i + 1)); done; wait $_p
el=$(( $(date +%s) - s0 ))
_i=1; while [ "$_i" -le 4 ]; do
    [ "$(cat "$o/f.rc.$_i")" != 0 ] || fail "R5: a rank exited 0 after a failed restore"
    grep -q 'the restore of tool pycodestyle from its record failed' "$o/f.err.$_i" || { cat "$o/f.err.$_i" >&2; fail "R5: rank $_i lacks the reason"; }
    _i=$((_i + 1))
done
[ "$el" -lt 30 ] || fail "R5: the waiters took ${el}s; they waited out the timeout"
ls "$UVM_ROOT/$b/.repair" | grep -q '+tool-pycodestyle\.failed$' || fail "R5: no failed record for the scope and the tool"
echo "P4 ok"
DRIVE
