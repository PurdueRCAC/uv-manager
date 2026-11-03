#!/bin/bash
# R1 damage matrix. Runs inside temp_root.sh. Prints one row per shape.
set -u
here=$(cd "$(dirname "$0")" && pwd)
arch=$(uname -m); root="$UVM_ROOT/$arch"; v=$("${SEED_DIR:?set SEED_DIR to the directory holding a real uv and uvx}"/uv --version | awk '{print $2}')
mkdir -p "$root/versions/$v" && cp "${SEED_DIR:?set SEED_DIR to the directory holding a real uv and uvx}"/uv "${SEED_DIR:?set SEED_DIR to the directory holding a real uv and uvx}"/uvx "$root/versions/$v/" && ln -s "versions/$v" "$root/current"
export UV_LINK_MODE=copy UV_PYTHON_PREFERENCE=only-managed XDG_DATA_HOME="$UVM_SANDBOX/data"
W="$UVM_SANDBOX/work"; mkdir -p "$W"; cd "$W"
mk() { cat > "$1" <<P
# /// script
# requires-python = ">=3.12"
# dependencies = ["$2"]
# ///
$3
P
}
mk s.py 'tqdm==4.67.1' 'import tqdm, tqdm.std, tqdm.contrib; print("s ok", tqdm.__version__)'
mk r.py 'rich==13.9.4' 'import rich.console, rich.syntax, pygments.lexers, markdown_it; print("r ok", pygments.__version__)'
c="$root/cache"
build() {
  uv run -q --no-project s.py >/dev/null 2>&1; uv run -q --no-project r.py >/dev/null 2>&1
  uvx -q tqdm==4.67.1 --version >/dev/null 2>&1; uvx -q flake8==7.1.1 --version >/dev/null 2>&1; uvx -q ruff==0.8.4 --version >/dev/null 2>&1
}
uv python install -q 3.12 2>/dev/null
build
cp -a "$c" "$UVM_SANDBOX/golden"
restore() { find "$c" -delete; cp -a "$UVM_SANDBOX/golden" "$c"; }
senv() { for d in "$c"/environments-v2/*-*/; do [[ -d "${d}lib/python3.12/site-packages/$1" ]] && { printf '%s' "${d%/}"; return; }; done; }
xlink() { for l in "$c"/environments-v2/*/*; do [[ -L "$l" && -d "$l/lib/python3.12/site-packages/$1" ]] && { printf '%s' "$l"; return; }; done; }
xenv() { local l; l=$(xlink "$1"); (cd "$(dirname "$l")" && cd "$(readlink "$l")" && pwd -P); }
cmd_s() { uv run --no-project s.py; }
cmd_r() { uv run --no-project r.py; }
cmd_t() { uvx tqdm==4.67.1 --version; }
cmd_f() { uvx flake8==7.1.1 --version; }
cmd_u() { uvx ruff==0.8.4 --version; }
deleted=""
unl() { python3 -I -c 'import os,sys
for l in sys.stdin.read().splitlines():
    if l: os.unlink(l)'; }
del_files() { cat > "$W/deleted"; unl < "$W/deleted"; }
back() { local n=0 t=0; while IFS= read -r p; do [[ -n "$p" ]] || continue; t=$((t+1)); [[ -e "$p" || -L "$p" ]] && n=$((n+1)); done < "$W/deleted"; printf '%s/%s' "$n" "$t"; }
row() { # LABEL CMD
  local out err rc na
  na=$(ls "$c/archive-v0" | wc -l)
  out=$("$2" 2>"$W/err"); rc=$?
  na=$(( $(ls "$c/archive-v0" | wc -l) - na ))
  err=$(grep -v '^ *$' "$W/err" | grep -iv 'warning: An executable\|^Installed\|^Resolved\|^Prepared\|^ *[+-] \|Audited\|Uninstalled' | tail -1 | cut -c1-110)
  out=$(printf '%s' "$out" | head -1 | cut -c1-40)
  local b; b=$(back)
  local rc2; "$2" >/dev/null 2>&1; rc2=$?
  printf '%-40s | rc=%-3s | out=%-22s | back %-7s | new-archive %-2s | 2nd rc=%s | %s\n' "$1" "$rc" "$out" "$b" "$na" "$rc2" "$err" | sed "s|$UVM_SANDBOX|SB|g"
}

echo "--- metadata buckets: 30% of files removed from simple-v*, interpreter-v*, and the .http/.msgpack files of wheels-v*"
restore
{ python3 -I "$here/sel.py" random "$c/simple-v27" 1; python3 -I "$here/sel.py" random "$c/interpreter-v4" 1; find "$c/wheels-v7" -type f \( -name '*.http' -o -name '*.msgpack' \) ; } | del_files
row "meta: existing s.py" cmd_s; row "meta: existing uvx tqdm" cmd_t
mk m.py 'tqdm==4.67.1' 'import tqdm, tqdm.std; print("m ok")'; cmd_m() { uv run --no-project m.py; }
row "meta: new script m.py" cmd_m
cmd_tw() { uvx --with mdurl==0.1.2 tqdm==4.67.1 --version; }; row "meta: new uvx --with" cmd_tw
echo "--- running process across an in-place reinstall"
restore; E=$(senv tqdm); printf '%s\n' "$E/lib/python3.12/site-packages/tqdm/std.py" | unl
"$E/bin/python" -c 'import time; time.sleep(4); import tqdm.contrib.logging; print("late import ok")' > "$W/late" 2>&1 & p=$!
sleep 1; (cd / && uv pip install -q --python "$E/bin/python" --reinstall --no-cache tqdm==4.67.1) >/dev/null 2>&1; wait $p; echo "script env, in-place reinstall during run: $(tail -1 "$W/late")"
echo "--- gates on this tree with the knob set (release/0.8.0 wrapper)"
restore; E=$(senv tqdm); X=$(xenv tqdm); printf '%s\n' "$E/lib/python3.12/site-packages/tqdm/std.py" "$X/lib/python3.12/site-packages/tqdm/std.py" | unl
UVM_REPAIR=g1 uv run --no-project s.py >/dev/null 2>"$W/err"; echo "UVM_REPAIR uv run s.py, module gone: rc=$? $(grep -c 'repairing' "$W/err") repair lines; outcome=$(ls "$root/.repair" 2>/dev/null | tr '\n' ' ')"
UVM_REPAIR=g2 uvx tqdm==4.67.1 --version >/dev/null 2>"$W/err"; echo "UVM_REPAIR uvx tqdm, module gone: rc=$? $(grep -c 'repairing' "$W/err") repair lines"
uvm doctor >/dev/null 2>&1; echo "uvm doctor rc=$? ($(uvm doctor 2>&1 | head -1 | cut -c1-40))"
restore; E=$(senv tqdm); printf '%s\n' "$E/pyvenv.cfg" | unl
UVM_REPAIR=g3 uv run --no-project s.py >/dev/null 2>&1; echo "UVM_REPAIR uv run s.py, pyvenv.cfg gone: rc=$? base site-packages: $(ls "$root"/python/cpython-3.12.*/lib/python3.12/site-packages | tr '\n' ' ')"
