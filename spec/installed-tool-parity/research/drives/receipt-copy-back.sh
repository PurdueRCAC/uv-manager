#!/bin/bash
# Run as: temp_root.sh bash receipt-copy-back.sh <uv>. It calls the real uv the way the
# restore does, so it exports the storage variables the wrapper would.
# Plan drive 2: N1 receipt copy-back on a tool held at older releases; the replay's
# flag form (UV_PYTHON, UV_NO_CACHE, --force filtered); @latest; a global pin.
set -u
UVBIN="$1"
v=$("$UVBIN" --version | awk '{print $2}')
a=$(uname -m)
root="$UVM_ROOT/$a"
mkdir -p "$root/versions/$v"
cp "$UVBIN" "$root/versions/$v/uv"; cp "$(dirname "$UVBIN")/uvx" "$root/versions/$v/uvx"
ln -s "versions/$v" "$root/current"
export XDG_DATA_HOME="$UVM_SANDBOX/xdg-data" UV_PYTHON_PREFERENCE=only-managed
export UV_CACHE_DIR="$root/cache" UV_TOOL_DIR="$root/tools" UV_TOOL_BIN_DIR="$root/bin/shims" UV_PYTHON_INSTALL_DIR="$root/python" UV_PYTHON_BIN_DIR="$root/bin/python-shims"
T="$UVM_SANDBOX/trash"; mkdir -p "$T"; W="$UVM_SANDBOX/w"; mkdir -p "$W"; cd "$W"
S() { sed -e "s#$UVM_SANDBOX#<sb>#g"; }
hdr() { printf '\n=== %s\n' "$*"; }
frozen() { for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do [ -d "$di" ] || continue; b=${di##*/}; echo "${b%.dist-info}"; done | sort; }
pins() {
  for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do
    b=${di##*/}; b=${b%.dist-info}; n=${b%-*}
    if [ -f "$di/direct_url.json" ]; then
      j=$(cat "$di/direct_url.json")
      u=$(printf '%s' "$j" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
      c=$(printf '%s' "$j" | sed -n 's/.*"commit_id":"\([0-9a-f]*\)".*/\1/p')
      if [ -n "$c" ]; then echo "$n @ git+$u@$c"; else echo "$n @ $u"; fi
    else echo "$n==${b##*-}"; fi
  done
}
RU="$root/current/uv"   # the real uv, as the restore calls it
replay() { # PINS ARGV...: the restore's form
  p="$1"; shift
  (cd / && UV_PYTHON=3.12 UV_NO_CACHE=1 exec "$RU" tool install --force -c "$p" "$@") > "$W/out" 2>&1; r=$?
  echo "replay rc=$r"; [ "$r" = 0 ] || tail -3 "$W/out" | S
}
"$RU" python install 3.12 -q 2>&1 | tail -1
iold() { # the unpinned tool at older releases, as repair-race.sh's T builds it
  "$RU" tool uninstall pycodestyle > /dev/null 2>&1
  "$RU" tool install -q -p 3.12 pycodestyle==2.11.1 --with six==1.16.0 2>&1
  "$RU" tool install -q -p 3.12 pycodestyle --with six 2>&1
}

hdr "twin: unpurged unpinned tool at older releases, then upgrade"
iold; frozen pycodestyle | tr '\n' ' '; echo; S < "$root/tools/pycodestyle/uv-receipt.toml"
"$RU" tool upgrade pycodestyle 2>&1 | tail -2 | S; frozen pycodestyle | tr '\n' ' '; echo

for shape in W E R S; do
  hdr "N1 $shape: copy-back"
  iold; cp "$root/tools/pycodestyle/uv-receipt.toml" "$W/R0"; frozen pycodestyle > "$W/F0"; pins pycodestyle > "$W/P0"; tr '\n' ' ' < "$W/P0"; echo
  case $shape in
    W) mv "$root/tools/pycodestyle" "$T/W.$RANDOM" ;;
    E) find "$root/tools/pycodestyle" -type f -delete ;;
    R) mv "$root/tools/pycodestyle/uv-receipt.toml" "$T/R.$RANDOM" ;;
    S) mv "$root/bin/shims/pycodestyle" "$T/S.$RANDOM" ;;
  esac
  replay "$W/P0" pycodestyle --with six
  frozen pycodestyle | cmp -s "$W/F0" - && echo "frozen IDENTICAL" || { echo "frozen DIFFERS:"; frozen pycodestyle | tr '\n' ' '; echo; }
  grep -E '^version_info' "$root/tools/pycodestyle/pyvenv.cfg"
  [ -x "$root/bin/shims/pycodestyle" ] && echo "shim executable"
  n_all=$(grep -c 'install-path = "' "$W/R0"); n_here=$(grep -cF "install-path = \"$root/bin/shims/" "$W/R0"); echo "install-paths: $n_all, naming this tree: $n_here"
  cp "$W/R0" "$root/tools/pycodestyle/uv-receipt.toml"
  "$root/bin/shims/pycodestyle" --version
  "$RU" tool list 2>&1 | grep -c '^pycodestyle v2.11.1'
  "$RU" tool upgrade pycodestyle 2>&1 | tail -2 | S; frozen pycodestyle | tr '\n' ' '; echo
  cmp -s "$W/R0" "$root/tools/pycodestyle/uv-receipt.toml" && echo "receipt unchanged by upgrade" || echo "receipt rewritten by upgrade"
done

hdr "N1 W: no copy-back (baseline hold)"
iold; pins pycodestyle > "$W/P0"; mv "$root/tools/pycodestyle" "$T/WN.$RANDOM"
replay "$W/P0" pycodestyle --with six
"$RU" tool upgrade pycodestyle 2>&1 | tail -2 | S; frozen pycodestyle | tr '\n' ' '; echo

hdr "N1 G: git tool, E, copy-back, then upgrade against the twin's"
"$RU" tool install -q -p 3.12 git+https://github.com/glentner/progressbar 2>&1
cp "$root/tools/progressbar/uv-receipt.toml" "$W/G0"; frozen progressbar > "$W/GF0"; pins progressbar > "$W/GP0"
"$RU" tool upgrade progressbar > "$W/twin.up" 2>&1; echo "twin upgrade: $(tail -1 "$W/twin.up" | S)"
find "$root/tools/progressbar" -type f -delete
replay "$W/GP0" git+https://github.com/glentner/progressbar
frozen progressbar | cmp -s "$W/GF0" - && echo "G frozen IDENTICAL"
sed -n 's/.*"commit_id":"\([0-9a-f]*\)".*/commit \1/p' "$root/tools/progressbar"/lib/*/site-packages/progressbar-*.dist-info/direct_url.json
echo "--- replayed receipt:"; S < "$root/tools/progressbar/uv-receipt.toml"
cp "$W/G0" "$root/tools/progressbar/uv-receipt.toml"
"$RU" tool upgrade progressbar > "$W/g.up" 2>&1; echo "after copy-back upgrade: $(tail -1 "$W/g.up" | S)"
"$root/bin/shims/pb" --version

hdr "@latest: argv pycodestyle@latest, pins at 2.11.1; replay with the suffix dropped"
"$RU" tool install -q -p 3.12 --force pycodestyle@latest 2>&1; S < "$root/tools/pycodestyle/uv-receipt.toml" | head -3
printf 'pycodestyle==2.11.1\n' > "$W/D.c"; mv "$root/tools/pycodestyle" "$T/D.$RANDOM"
replay "$W/D.c" pycodestyle; frozen pycodestyle | tr '\n' ' '; echo

hdr "flag form: argv carries --no-cache and --python 3.12; UV_PYTHON=3.12 and UV_NO_CACHE=1 beside them"
mv "$root/tools/pycodestyle" "$T/F1.$RANDOM"
replay "$W/D.c" --no-cache --python 3.12 pycodestyle; grep version_info "$root/tools/pycodestyle/pyvenv.cfg"

hdr "UV_PYTHON against a global pin and a user's UV_PYTHON (downloads off, 3.11 absent)"
mkdir -p "$XDG_CONFIG_HOME/uv"; echo 3.11 > "$XDG_CONFIG_HOME/uv/.python-version"
mv "$root/tools/pycodestyle" "$T/F2.$RANDOM"
UV_PYTHON_DOWNLOADS=never replay "$W/D.c" pycodestyle; grep version_info "$root/tools/pycodestyle/pyvenv.cfg"
(cd / && UV_PYTHON_DOWNLOADS=never exec "$RU" tool install --force -c "$W/D.c" pycodestyle) > "$W/out" 2>&1; echo "no UV_PYTHON, global pin 3.11: rc=$? $(tail -1 "$W/out" | S)"
mv "$XDG_CONFIG_HOME/uv/.python-version" "$T/pin.$RANDOM"

hdr "shim entrypoint discovery: readlink of each shim"
for s in "$root"/bin/shims/*; do t=$(readlink "$s"); t=${t#"$root/tools/"}; echo "${s##*/} -> tool ${t%%/*}"; done
