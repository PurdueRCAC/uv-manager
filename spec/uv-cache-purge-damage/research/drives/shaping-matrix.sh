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
echo "uv: $(uv --version)  link-mode: $UV_LINK_MODE"
echo "script env: $(senv tqdm | sed "s|$c/||")   uvx tqdm: $(xlink tqdm | sed "s|$c/||") -> $(readlink "$(xlink tqdm)")"
echo "--- healthy"; : > "$W/deleted"; row "healthy s.py" cmd_s; row "healthy uvx tqdm" cmd_t; row "healthy uvx flake8" cmd_f; row "healthy uvx ruff" cmd_u; row "healthy r.py" cmd_r

# shapes on an environment: KIND(s|t|f) LABEL-PREFIX
env_shapes() {
  local k=$1 E pkg mod di cmd
  case $k in
    s) pkg=tqdm; mod=tqdm/std.py; cmd=cmd_s ;;
    r) pkg=pygments; mod=pygments/lexers/python.py; cmd=cmd_r ;;
    t) pkg=tqdm; mod=tqdm/std.py; cmd=cmd_t ;;
    f) pkg=pyflakes; mod=pyflakes/checker.py; cmd=cmd_f ;;
  esac
  get() { case $k in s) senv tqdm ;; r) senv rich ;; t) xenv tqdm ;; f) xenv flake8 ;; esac; }
  for shape in random1 random2 newest module distinfo-dir distinfo-files pyvenv binpython allfiles; do
    restore; E=$(get); sp="$E/lib/python3.12/site-packages"; di=$(ls -d "$sp/$pkg"-*.dist-info)
    case $shape in
      random1) python3 -I "$here/sel.py" random "$E" 1 | del_files ;;
      random2) python3 -I "$here/sel.py" random "$E" 2 | del_files ;;
      newest) python3 -I "$here/sel.py" newest "$E" | del_files ;;
      module) echo "$sp/$mod" | del_files ;;
      distinfo-dir) python3 -I "$here/sel.py" all "$di" | del_files; find "$di" -delete ;;
      distinfo-files) python3 -I "$here/sel.py" all "$di" | del_files ;;
      pyvenv) echo "$E/pyvenv.cfg" | del_files ;;
      binpython) echo "$E/bin/python" | del_files ;;
      allfiles) python3 -I "$here/sel.py" all "$E" | del_files ;;
    esac
    row "$k env: $shape" $cmd
  done
}
echo "--- script env (s.py, tqdm)"; env_shapes s
echo "--- script env (r.py, rich + deps)"; env_shapes r
echo "--- uvx env (tqdm)"; env_shapes t
echo "--- uvx env (flake8 + deps)"; env_shapes f
echo "--- uvx env (ruff, binary)"
restore; E=$(xenv ruff); echo "$E/bin/ruff" | del_files; row "u env: bin/ruff" cmd_u
restore; E=$(xenv ruff); find "$E/lib" -name 'RECORD' | del_files; row "u env: RECORD only" cmd_u
echo "--- uvx env, entry removal"
restore; l=$(xlink tqdm); E=$(xenv tqdm); : > "$W/deleted"; find "$E" -delete; row "t: archive dir removed (link dangles)" cmd_t
restore; l=$(xlink tqdm); : > "$W/deleted"; printf "%s\n" "$l" | unl; row "t: environments-v2 link removed" cmd_t
restore; E=$(xenv tqdm); : > "$W/deleted"; mv "$E" "$E.aside"; row "t: archive dir mv aside" cmd_t
restore; E=$(senv tqdm); : > "$W/deleted"; mv "$E" "$E.aside"; row "s: script env mv aside" cmd_s
echo "--- unpacked wheel archive (tqdm), then a new environment"
mk n.py 'tqdm==4.67.1' 'import tqdm, tqdm.std; print("n ok", tqdm.__version__)'
cmd_n() { uv run --no-project n.py; }
cmd_tw() { uvx --with mdurl==0.1.2 tqdm==4.67.1 --version; }
wa() { local l; l="$c/wheels-v7/pypi/tqdm/4.67.1-py3-none-any"; (cd "$(dirname "$l")" && cd "$(readlink "$l")" && pwd -P); }
for shape in module distinfo-files allfiles random1 dir-removed; do
  restore; A=$(wa)
  case $shape in
    module) echo "$A/tqdm/std.py" | del_files ;;
    distinfo-files) python3 -I "$here/sel.py" all "$A/tqdm-4.67.1.dist-info" | del_files ;;
    allfiles) python3 -I "$here/sel.py" all "$A" | del_files ;;
    random1) python3 -I "$here/sel.py" random "$A" 1 | del_files ;;
    dir-removed) : > "$W/deleted"; find "$A" -delete ;;
  esac
  row "wheel $shape: existing s.py" cmd_s
  row "wheel $shape: new script n.py" cmd_n
  row "wheel $shape: new uvx --with" cmd_tw
  E=$(senv tqdm); [[ -n "$E" ]] && find "$E" -delete
  row "wheel $shape: s.py after env removed" cmd_s
done
echo "--- uv cache commands on damage"
restore; E=$(senv tqdm); X=$(xenv tqdm); A=$(wa); printf '%s\n' "$E/lib/python3.12/site-packages/tqdm/std.py" "$X/lib/python3.12/site-packages/tqdm/std.py" "$A/tqdm/std.py" | del_files
uv cache clean tqdm 2>&1 | tail -1 | sed "s|$UVM_SANDBOX|SB|g"
echo "after clean tqdm: script env exists=$([[ -d $E ]] && echo y || echo n) uvx env exists=$([[ -d $X ]] && echo y || echo n) wheel archive exists=$([[ -d $A ]] && echo y || echo n) uvx link exists=$([[ -L $(xlink tqdm) ]] && echo y || echo n)"
row "after uv cache clean tqdm: s.py" cmd_s; row "after uv cache clean tqdm: uvx tqdm" cmd_t
restore; E=$(senv tqdm); X=$(xenv tqdm); A=$(wa); printf '%s\n' "$E/lib/python3.12/site-packages/tqdm/std.py" "$X/lib/python3.12/site-packages/tqdm/std.py" "$A/tqdm/std.py" | del_files
uv cache prune 2>&1 | tail -1 | sed "s|$UVM_SANDBOX|SB|g"
echo "after prune: script env exists=$([[ -d $E ]] && echo y || echo n) uvx env exists=$([[ -d $X ]] && echo y || echo n) wheel archive exists=$([[ -d $A ]] && echo y || echo n)"
row "after uv cache prune: s.py" cmd_s; row "after uv cache prune: uvx tqdm" cmd_t
echo "--- a running process when its entry is moved or unlinked"
late() { "$1/bin/python" -c 'import time; time.sleep(3); import tqdm.contrib.logging; print("late import ok")' > "$W/late" 2>&1 & }
restore; E=$(senv tqdm); late "$E"; p=$!; sleep 1; mv "$E" "$E.aside"; wait $p; echo "script env, mv aside during run: $(tail -1 "$W/late")"
restore; E=$(senv tqdm); late "$E"; p=$!; sleep 1; mv "$E" "$E.aside"; uv run -q --no-project s.py >/dev/null 2>&1; wait $p; echo "script env, mv aside then rebuilt before late import: $(tail -1 "$W/late")"
restore; X=$(xenv tqdm); l=$(xlink tqdm); late "$l"; p=$!; sleep 1; printf "%s\n" "$l" | unl; uvx -q tqdm==4.67.1 --version >/dev/null 2>&1; wait $p; echo "uvx env via link, link removed and rebuilt: $(tail -1 "$W/late"); old archive kept=$([[ -d $X ]] && echo y || echo n); new link target differs=$([[ "$(xenv tqdm)" != "$X" ]] && echo y || echo n)"
restore; X=$(xenv tqdm); late "$X"; p=$!; sleep 1; mv "$X" "$X.aside"; wait $p; echo "uvx env, archive mv aside during run: $(tail -1 "$W/late")"
restore; X=$(xenv tqdm); l=$(xlink tqdm); late "$X"; p=$!; sleep 1; printf "%s\n" "$l" | unl; uvx -q tqdm==4.67.1 --version >/dev/null 2>&1; wait $p; echo "uvx env run by archive path, link removed and rebuilt: $(tail -1 "$W/late"); old archive kept=$([[ -d $X ]] && echo y || echo n)"
echo "--- in-place reinstall (the tool arm's idiom) on a damaged environment"
inplace() { (cd / && uv pip install -q --python "$1/bin/python" --reinstall --no-cache $2) 2>&1 | tail -1 | cut -c1-90 | sed "s|$UVM_SANDBOX|SB|g"; }
for shape in module random1 distinfo-files allfiles; do
  restore; E=$(senv tqdm); X=$(xenv tqdm)
  for T in "$E" "$X"; do sp="$T/lib/python3.12/site-packages"
    case $shape in
      module) echo "$sp/tqdm/std.py" ;;
      random1) python3 -I "$here/sel.py" random "$T" 1 ;;
      distinfo-files) python3 -I "$here/sel.py" all "$sp/tqdm-4.67.1.dist-info" ;;
      allfiles) python3 -I "$here/sel.py" all "$T" ;;
    esac; done | del_files
  echo "  $shape script env: $(inplace "$E" tqdm==4.67.1)"; echo "  $shape uvx env: $(inplace "$X" tqdm==4.67.1)"
  row "in-place $shape: s.py" cmd_s; row "in-place $shape: uvx tqdm" cmd_t
done
echo "--- detail: uvx tqdm with its dist-info directory removed"
restore; X=$(xenv tqdm); find "$X/lib/python3.12/site-packages/tqdm-4.67.1.dist-info" -delete; uvx tqdm==4.67.1 --version 2>&1 | tail -3 | sed "s|$UVM_SANDBOX|SB|g"
echo "--- pre-build candidates"
restore; E=$(senv tqdm); find "$E" -delete; uv sync -q --script s.py >/dev/null 2>"$W/err"; echo "uv sync --script s.py: rc=$? env rebuilt=$([[ -d $(senv tqdm) ]] && echo y || echo n) $(tail -1 "$W/err")"
restore; l=$(xlink tqdm); printf "%s\n" "$l" | unl; uvx -q --from tqdm==4.67.1 python -c pass >/dev/null 2>"$W/err"; echo "uvx --from tqdm python -c pass: rc=$? link back=$([[ -L $(xlink tqdm) ]] && echo y || echo n) same key=$([[ $(xlink tqdm) == "$l" ]] && echo y || echo n) $(tail -1 "$W/err" | cut -c1-100)"
echo "--- ruff-only check of RECORD walk cost"
n=0; for r in "$c"/archive-v0/*/*.dist-info/RECORD "$c"/archive-v0/*/lib/python3.12/site-packages/*.dist-info/RECORD "$c"/environments-v2/s-*/lib/python3.12/site-packages/*.dist-info/RECORD; do [[ -f $r ]] && n=$((n+1)); done; echo "RECORD files in cache: $n; files in cache: $(find "$c" -type f | wc -l)"
