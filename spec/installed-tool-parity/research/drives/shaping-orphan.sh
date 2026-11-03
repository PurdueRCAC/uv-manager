#!/bin/bash
# From the shaping run (GOAL Clarification Q2). Run as: temp_root.sh bash shaping-orphan.sh <uv>.
# R1 supplement 2: the realistic purge shape (every file gone, dirs and links kept)
# replayed from a record; and what uv tool list exposes for a backfill.
set -u
UVBIN="$1"
v=0.13.6
a=$(uname -m)
root="$UVM_ROOT/$a"
mkdir -p "$root/versions/$v"
cp "$UVBIN" "$root/versions/$v/uv"; cp "$(dirname "$UVBIN")/uvx" "$root/versions/$v/uvx"
ln -s "versions/$v" "$root/current"
export XDG_DATA_HOME="$UVM_SANDBOX/xdg-data"
uv python install 3.12 -q 2>&1
frozen() { for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do b=${di##*/}; echo "${b%.dist-info}"; done | sort; }
record() { for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do b=${di##*/}; b=${b%.dist-info}; echo "${b%-*}==${b##*-}"; done; }
hdr() { printf '\n=== %s\n' "$*"; }
base=$(ls -d "$root"/python/cpython-3.12.*/ | head -1)
sp_base=$(ls -d "$base"lib/python3.12/site-packages)

uv tool install -p 3.12 pycodestyle==2.11.1 --with six==1.16.0 -q 2>&1
uv tool install -p 3.12 'pyflakes>=3' -q 2>&1
uv tool install -p 3.12 git+https://github.com/glentner/progressbar -q 2>&1

hdr "uv tool list with every --show flag"
uv tool list --show-paths --show-version-specifiers --show-with --show-extras --show-python 2>&1 | sed "s#$UVM_SANDBOX#<sandbox>#g"

hdr "O: every file of pycodestyle removed, dirs and links kept (pyvenv.cfg gone too)"
frozen pycodestyle > O.before; record pycodestyle > O.c.txt
ls "$sp_base" | sort > O.base.before
find "$root/tools/pycodestyle" -type f -delete
uvm doctor 2>&1 | grep -i pycodestyle | head -3
UVM_REPAIR=o1 uv --version 2>&1 | tail -2; echo "knob-set call on 0.7.0 code rc=$?"
uv tool install -p 3.12 --force --no-cache -c O.c.txt pycodestyle --with six 2>&1 | tail -2; echo "replay rc=${PIPESTATUS[0]}"
frozen pycodestyle | cmp -s O.before - && echo "O frozen IDENTICAL"
ls "$sp_base" | sort | cmp -s O.base.before - && echo "O base site-packages UNCHANGED"
test -f "$root/tools/pycodestyle/pyvenv.cfg" && echo "O pyvenv.cfg back"
"$UVM_ROOT/bin/pycodestyle" --version 2>&1; echo "trampoline rc=$?"

hdr "S: shim purged; next uv tool call's sync and the trampoline"
rm -f "$root/bin/shims/pyflakes"
uv tool list >/dev/null 2>&1
ls "$UVM_ROOT/bin" | tr '\n' ' '; echo
