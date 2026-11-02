#!/bin/bash
# From the shaping run (GOAL Clarification Q1). Run as: temp_root.sh bash shaping-index.sh <uv>.
# R1 cheap drive, index sources. Runs inside temp_root.sh (cwd = sandbox).
set -u
UVBIN="$1"
v=0.13.6
a=$(uname -m)
root="$UVM_ROOT/$a"
mkdir -p "$root/versions/$v"
cp "$UVBIN" "$root/versions/$v/uv"; cp "$(dirname "$UVBIN")/uvx" "$root/versions/$v/uvx"
ln -s "versions/$v" "$root/current"
export XDG_DATA_HOME="$UVM_SANDBOX/xdg-data"
uv --version
uv python install 3.12 2>&1 | tail -1

frozen() { # tool -> sorted dist-info names
  for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do b=${di##*/}; echo "${b%.dist-info}"; done | sort
}
record() { # tool -> constraints from dist-info names
  for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do b=${di##*/}; b=${b%.dist-info}; echo "${b%-*}==${b##*-}"; done
}

print_hdr() { printf '\n=== %s\n' "$*"; }

# --- Case A: unpinned tool at an older release, unpinned --with at an older release
print_hdr "A: unpinned pycodestyle + unpinned --with six, installed old then reinstalled unpinned"
uv tool install pycodestyle==2.11.1 --with six==1.16.0 -q 2>&1
uv tool install --force pycodestyle --with six -q 2>&1   # receipt now unpinned; does env move?
frozen pycodestyle > A.before
cat A.before
echo "--- receipt:"; cat "$root/tools/pycodestyle/uv-receipt.toml"
record pycodestyle > A.constraints.txt
grep -E '^(Version|implementation|version_info)' "$root/tools/pycodestyle/pyvenv.cfg"
# purge: whole tool dir + shim
rm -rf "$root/tools/pycodestyle"; rm -f "$root/bin/shims/pycodestyle"
print_hdr "A replay: tool install --force --no-cache -c constraints pycodestyle --with six"
uv tool install --force --no-cache -c A.constraints.txt pycodestyle --with six 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"
frozen pycodestyle > A.after
diff A.before A.after && echo "A frozen set: IDENTICAL"
echo "--- receipt after replay:"; cat "$root/tools/pycodestyle/uv-receipt.toml"
print_hdr "A: does a later upgrade move past the replayed constraints?"
uv tool upgrade pycodestyle 2>&1 | tail -3
frozen pycodestyle

# --- Case B: pinned tool with pinned --with
print_hdr "B: pyflakes==3.2.0 --with tomli==2.0.1"
uv tool install pyflakes==3.2.0 --with tomli==2.0.1 -q 2>&1
frozen pyflakes > B.before; record pyflakes > B.constraints.txt
rm -rf "$root/tools/pyflakes"; rm -f "$root/bin/shims/pyflakes"
uv tool install --force --no-cache -c B.constraints.txt pyflakes==3.2.0 --with tomli==2.0.1 2>&1 | tail -1
frozen pyflakes > B.after
diff B.before B.after && echo "B frozen set: IDENTICAL"

# --- Case C: receipt only removed, shim kept; replay with --force
print_hdr "C: receipt only removed (pyflakes), replay over existing dir"
rm -f "$root/tools/pyflakes/uv-receipt.toml"
uv tool install --force --no-cache -c B.constraints.txt pyflakes==3.2.0 --with tomli==2.0.1 2>&1 | tail -1; echo "rc=${PIPESTATUS[0]}"
frozen pyflakes | diff B.before - && echo "C frozen set: IDENTICAL"
ls "$root/tools/pyflakes/uv-receipt.toml"

# --- Case D: shim only removed, without --force
print_hdr "D: shim only removed; replay without --force"
rm -f "$root/bin/shims/pyflakes"
uv tool install --no-cache -c B.constraints.txt pyflakes==3.2.0 --with tomli==2.0.1 2>&1 | tail -2; echo "rc=${PIPESTATUS[0]}"
ls -l "$root/bin/shims/pyflakes" 2>&1

# --- Case E: whole dir gone, shim kept (orphaned shim), replay without --force
print_hdr "E: dir gone, shim kept; replay without --force (expect rc 2)"
rm -rf "$root/tools/pyflakes"
uv tool install --no-cache -c B.constraints.txt pyflakes==3.2.0 --with tomli==2.0.1 2>&1 | tail -2; echo "rc=${PIPESTATUS[0]}"
uv tool install --force --no-cache -c B.constraints.txt pyflakes==3.2.0 --with tomli==2.0.1 2>&1 | tail -1; echo "with --force rc=${PIPESTATUS[0]}"

# --- Python question: what does pyvenv.cfg record, and does -p <patch> replay?
print_hdr "Python: pyvenv.cfg and replay with recorded patch"
grep -E '^(version|version_info)' "$root/tools/pyflakes/pyvenv.cfg"
uv python list --only-installed 2>&1
