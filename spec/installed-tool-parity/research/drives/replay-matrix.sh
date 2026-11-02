#!/bin/bash
# Run as: temp_root.sh bash replay-matrix.sh <uv>. Its B section reinstalls the
# unpinned tool with --force, which moved it to its newest release, so B says nothing
# about N1; receipt-copy-back.sh is the N1 drive. C-K stand.
# Plan drive for installed-tool-parity. Runs inside temp_root.sh (cwd = sandbox).
# $1 = a local uv binary with uvx beside it. Prints sandbox-relative output.
set -u
UVBIN="$1"
v=$("$UVBIN" --version | awk '{print $2}')
a=$(uname -m)
root="$UVM_ROOT/$a"
mkdir -p "$root/versions/$v"
cp "$UVBIN" "$root/versions/$v/uv"; cp "$(dirname "$UVBIN")/uvx" "$root/versions/$v/uvx"
ln -s "versions/$v" "$root/current"
export XDG_DATA_HOME="$UVM_SANDBOX/xdg-data" UV_PYTHON_PREFERENCE=only-managed
T="$UVM_SANDBOX/trash"; mkdir -p "$T"; W="$UVM_SANDBOX/w"; mkdir -p "$W"; cd "$W"
S() { sed -e "s#$UVM_SANDBOX#<sb>#g"; }
hdr() { printf '\n=== %s\n' "$*"; }
frozen() { for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do [ -d "$di" ] || continue; b=${di##*/}; echo "${b%.dist-info}"; done | sort; }
pins() { # tool -> constraints, VCS/URL from direct_url.json
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
uv --version
uv python install 3.12 -q 2>&1 | tail -1
iold() { uv tool install -q -p 3.12 --force pycodestyle==2.11.1 --with six==1.16.0 2>&1; uv tool install -q -p 3.12 --force pycodestyle --with six 2>&1; }

hdr "A: receipt anatomy (unpinned pycodestyle at 2.11.1 with six 1.16.0)"
iold
S < "$root/tools/pycodestyle/uv-receipt.toml"
echo "--- pyvenv.cfg"; S < "$root/tools/pycodestyle/pyvenv.cfg"
echo "--- shim"; ls -l "$root/bin/shims/" | S | tail -n +2
frozen pycodestyle

hdr "B0: twin upgrade (unpurged)"
cp "$root/tools/pycodestyle/uv-receipt.toml" "$W/R0.toml"
uv tool upgrade pycodestyle 2>&1 | tail -3 | S; frozen pycodestyle | tr '\n' ' '; echo

for shape in W E R S; do
  hdr "B-$shape: purge, replay with pins, copy receipt back, upgrade"
  iold; cp "$root/tools/pycodestyle/uv-receipt.toml" "$W/R0.toml"; frozen pycodestyle > "$W/F0"; pins pycodestyle > "$W/P0"
  cat "$W/P0" | tr '\n' ' '; echo
  case $shape in
    W) mv "$root/tools/pycodestyle" "$T/W.$$.$RANDOM" ;;
    E) find "$root/tools/pycodestyle" -type f -delete ;;
    R) mv "$root/tools/pycodestyle/uv-receipt.toml" "$T/R.$RANDOM" ;;
    S) mv "$root/bin/shims/pycodestyle" "$T/S.$RANDOM" ;;
  esac
  (cd / && uv tool install --force --no-cache -c "$W/P0" -p 3.12 pycodestyle --with six) > "$W/out" 2>&1; echo "replay rc=$?"; tail -1 "$W/out" | S
  frozen pycodestyle | cmp -s "$W/F0" - && echo "frozen IDENTICAL" || { echo "frozen DIFFERS"; frozen pycodestyle; }
  test -x "$root/bin/shims/pycodestyle" && echo "shim back"
  echo "--- replayed receipt (pinned by uv):"; S < "$root/tools/pycodestyle/uv-receipt.toml"
  if [ "$shape" = W ]; then
    echo "--- without copy-back, upgrade:"; uv tool upgrade pycodestyle 2>&1 | tail -2 | S
    iold; cp "$root/tools/pycodestyle/uv-receipt.toml" "$W/R0.toml"; frozen pycodestyle > "$W/F0"; mv "$root/tools/pycodestyle" "$T/W2.$RANDOM"
    (cd / && uv tool install --force --no-cache -c "$W/P0" -p 3.12 pycodestyle --with six) > "$W/out" 2>&1; echo "replay again rc=$?"
  fi
  cp "$W/R0.toml" "$root/tools/pycodestyle/uv-receipt.toml"
  "$UVM_ROOT/bin/pycodestyle" --version; echo "run rc=$?"
  uv tool list 2>&1 | grep -A2 pycodestyle | S; echo "list rc=${PIPESTATUS[0]}"
  uv tool upgrade pycodestyle 2>&1 | tail -3 | S; echo "upgrade rc=${PIPESTATUS[0]}"
  frozen pycodestyle | tr '\n' ' '; echo
  "$UVM_ROOT/bin/pycodestyle" --version
done

hdr "C: git tool, shape E, replay + copy-back + upgrade"
uv tool install -q -p 3.12 git+https://github.com/glentner/progressbar 2>&1 | tail -2
gt=progressbar
ls "$root/tools"; ls -l "$root/bin/shims" | S | tail -n +2
cp "$root/tools/$gt/uv-receipt.toml" "$W/G0.toml"; frozen $gt > "$W/GF0"; pins $gt > "$W/GP0"; cat "$W/GP0"
for di in "$root/tools/$gt"/lib/*/site-packages/*.dist-info; do [ -f "$di/direct_url.json" ] && { echo "${di##*/}:"; cat "$di/direct_url.json"; echo; }; done
S < "$W/G0.toml"
"$UVM_ROOT/bin/pb" --version; echo "pb rc=$?"
find "$root/tools/$gt" -type f -delete
(cd / && uv tool install --force --no-cache -c "$W/GP0" -p 3.12 git+https://github.com/glentner/progressbar) > "$W/out" 2>&1; echo "replay rc=$?"; tail -1 "$W/out" | S
frozen $gt | cmp -s "$W/GF0" - && echo "G frozen IDENTICAL"
cat "$root/tools/$gt"/lib/*/site-packages/progressbar*.dist-info/direct_url.json; echo
cp "$W/G0.toml" "$root/tools/$gt/uv-receipt.toml"
uv tool upgrade $gt 2>&1 | tail -2 | S; echo "G upgrade rc=${PIPESTATUS[0]}"
"$UVM_ROOT/bin/pb" --version; echo "pb rc=$?"

hdr "D: @latest recorded, pins older than latest"
uv tool install -q -p 3.12 --force pycodestyle@latest 2>&1
S < "$root/tools/pycodestyle/uv-receipt.toml"; frozen pycodestyle | tr '\n' ' '; echo
printf 'pycodestyle==2.11.1\n' > "$W/D.c"
mv "$root/tools/pycodestyle" "$T/D.$RANDOM"
(cd / && uv tool install --force --no-cache -c "$W/D.c" -p 3.12 pycodestyle@latest) > "$W/out" 2>&1; echo "D replay rc=$?"; tail -3 "$W/out" | S
frozen pycodestyle | tr '\n' ' '; echo

hdr "E: duplicate flags in argv"
(cd / && uv tool install --force --no-cache -c "$W/D.c" -p 3.12 --force --no-cache pycodestyle) > "$W/out" 2>&1; echo "dup --force/--no-cache rc=$?"; tail -2 "$W/out" | S
(cd / && uv tool install --force --no-cache -c "$W/D.c" -p 3.12 --python 3.12 pycodestyle) > "$W/out" 2>&1; echo "dup --python rc=$?"; tail -2 "$W/out" | S
(cd / && uv tool install --force --no-cache -c "$W/D.c" -c "$W/D.c" -p 3.12 pycodestyle) > "$W/out" 2>&1; echo "dup -c rc=$?"; tail -2 "$W/out" | S

hdr "F: URL archive source"
url=$(curl -s https://pypi.org/pypi/pycowsay/0.0.0.2/json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print([u["url"] for u in d["urls"] if u["packagetype"]=="bdist_wheel"][0])')
echo "url=$url"
uv tool install -q -p 3.12 "$url" 2>&1 | tail -1
ls "$root/tools"; cat "$root/tools/pycowsay"/lib/*/site-packages/pycowsay*.dist-info/direct_url.json; echo
S < "$root/tools/pycowsay/uv-receipt.toml"
frozen pycowsay > "$W/UF0"; pins pycowsay > "$W/UP0"; cat "$W/UP0"
find "$root/tools/pycowsay" -type f -delete
(cd / && uv tool install --force --no-cache -c "$W/UP0" -p 3.12 "$url") > "$W/out" 2>&1; echo "F replay rc=$?"; tail -1 "$W/out" | S
frozen pycowsay | cmp -s "$W/UF0" - && echo "F frozen IDENTICAL"
# the constraint alone, argv by name: does a URL constraint pin a by-name request?
mv "$root/tools/pycowsay" "$T/F.$RANDOM"
(cd / && uv tool install --force --no-cache -c "$W/UP0" -p 3.12 pycowsay) > "$W/out" 2>&1; echo "F by-name + url constraint rc=$?"; tail -2 "$W/out" | S
cat "$root/tools/pycowsay"/lib/*/site-packages/pycowsay*.dist-info/direct_url.json 2>/dev/null; echo
"$UVM_ROOT/bin/pycowsay" --version 2>&1 | head -2; echo "pycowsay rc=$?"

hdr "G: credentials in an index URL"
(cd / && uv tool install -p 3.12 --force --index-url https://__token__:SECRETMARK@pypi.org/simple pyflakes==3.2.0) > "$W/out" 2>&1; echo "index-url creds rc=$?"; tail -2 "$W/out" | S
grep -rl SECRETMARK "$root/tools/pyflakes" 2>/dev/null | S
grep -n -i 'index\|SECRET' "$root/tools/pyflakes/uv-receipt.toml" | S
(cd / && uv tool install -p 3.12 --force --index https://__token__:SECRETMARK@pypi.org/simple pyflakes==3.2.0) > "$W/out" 2>&1; echo "index creds rc=$?"; tail -2 "$W/out" | S
grep -rl SECRETMARK "$root/tools/pyflakes" 2>/dev/null | S
grep -n -i 'index\|SECRET' "$root/tools/pyflakes/uv-receipt.toml" | S

hdr "H: uv tool list renderings"
uv tool install -q -p 3.12 --force 'coverage[toml]==7.6.1' --with tomli==2.0.1 2>&1 | tail -1
uv tool install -q -p 3.12 --force pyflakes==3.2.0 2>&1 | tail -1
uv tool install -q -p 3.12 --force iold-dummy 2>/dev/null; iold
uv tool list --show-version-specifiers --show-with --show-extras --show-python 2>&1 | S
echo "--- python request recorded?"; grep -n python "$root/tools/coverage/uv-receipt.toml" | S

hdr "I: a stray file in the tool dir"
: > "$root/tools/pycodestyle/.uv-manager-restored"
uv tool list > /dev/null 2>"$W/err"; echo "list rc=$?"; S < "$W/err"
uv tool upgrade pycodestyle > /dev/null 2>"$W/err"; echo "upgrade rc=$?"; tail -2 "$W/err" | S
ls -a "$root/tools/pycodestyle" | tr '\n' ' '; echo

hdr "J: version lines"
uv tool install -q -p 3.12 pygments==2.18.0 2>&1 | tail -1
uv tool install -q -p 3.12 wheel==0.45.1 2>&1 | tail -1
uv tool install -q -p 3.12 ruff==0.8.4 2>&1 | tail -1
for c in "pyflakes --version" "pycodestyle --version" "pygmentize -V" "wheel version" "ruff --version" "pb --version" "pycowsay --version" "coverage --version"; do
  set -- $c; o=$("$UVM_ROOT/bin/$1" "${@:2}" 2>&1); echo "$c -> rc=$? lines=$(printf '%s\n' "$o" | wc -l | tr -d ' ') [$(printf '%s' "$o" | head -1 | S)]"
done
ls -l "$root/bin/shims" | S | tail -n +2

hdr "K: record size"
mkdir -p "$W/rec/pycodestyle"; cp "$W/R0.toml" "$W/rec/pycodestyle/uv-receipt.toml"; printf 'pycodestyle\n--with\nsix\n' > "$W/rec/pycodestyle/request"
cp "$W/P0" "$W/rec/pycodestyle/constraints"; echo 3.12 > "$W/rec/pycodestyle/python"; echo pycodestyle > "$W/rec/pycodestyle/entrypoints"
du -sk "$W/rec/pycodestyle"; wc -c "$W/rec/pycodestyle"/* | tail -1
