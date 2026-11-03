#!/bin/bash
# Run as: temp_root.sh bash list-renderings.sh <uv>.
# Plan drive 3: uv tool list renderings for backfill; does --force drop a stray file;
# a local source's direct_url.json and list line.
set -u
UVBIN="$1"
v=$("$UVBIN" --version | awk '{print $2}')
a=$(uname -m); root="$UVM_ROOT/$a"
mkdir -p "$root/versions/$v"; cp "$UVBIN" "$root/versions/$v/uv"; cp "$(dirname "$UVBIN")/uvx" "$root/versions/$v/uvx"; ln -s "versions/$v" "$root/current"
export XDG_DATA_HOME="$UVM_SANDBOX/xdg-data" UV_PYTHON_PREFERENCE=only-managed
W="$UVM_SANDBOX/w"; mkdir -p "$W"; cd "$W"
S() { sed -e "s#$UVM_SANDBOX#<sb>#g"; }
uv python install -q 3.12 2>&1
uv tool install -q -p 3.12 'pycodestyle[x]==2.11.1' --with six==1.16.0 --with 'tomli==2.0.1' 2>&1 | tail -1
uv tool install -q -p 3.12 'git+https://github.com/glentner/progressbar@837e34e8e4d846c8d1d92ff8a72448f99aaadac7' 2>&1 | tail -1
mkdir -p lp/src/lp; printf '[project]\nname = "lp"\nversion = "0.1"\n[project.scripts]\nlp = "lp:main"\n[build-system]\nrequires = ["hatchling"]\nbuild-backend = "hatchling.build"\n' > lp/pyproject.toml
printf 'def main():\n    print("lp ok")\n' > lp/src/lp/__init__.py
uv tool install -q -p 3.12 ./lp 2>&1 | tail -1
uv tool install -q -p 3.12 -e ./lp --force 2>&1 | tail -1
printf 'six==1.16.0\n' > reqs.txt
uv tool install -q -p 3.12 pyflakes==3.2.0 --with-requirements reqs.txt 2>&1 | tail -1
uv tool list --show-version-specifiers --show-with --show-extras 2>&1 | grep -v '^- ' | S
echo "--- lp direct_url:"; cat "$root/tools/lp"/lib/*/site-packages/lp-*.dist-info/direct_url.json | S; echo
echo "--- lp receipt:"; S < "$root/tools/lp/uv-receipt.toml"
echo "--- pyflakes receipt (with-requirements):"; S < "$root/tools/pyflakes/uv-receipt.toml"
: > "$root/tools/pycodestyle/.uvm-restored"
uv tool install -q -p 3.12 --force 'pycodestyle[x]==2.11.1' --with six==1.16.0 --with tomli==2.0.1 2>&1 | tail -1
ls -a "$root/tools/pycodestyle" | tr '\n' ' '; echo
