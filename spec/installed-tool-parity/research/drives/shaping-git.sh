#!/bin/bash
# From the shaping run (GOAL Clarifications Q1, Q3). Run as: temp_root.sh bash shaping-git.sh <uv>.
# R1 cheap drive, part 2: older-pin hold, UV_CONSTRAINT, git source, uvx forms.
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
P="--python 3.12"

frozen() { for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do b=${di##*/}; echo "${b%.dist-info}"; done | sort; }
record() { for di in "$root/tools/$1"/lib/*/site-packages/*.dist-info; do b=${di##*/}; b=${b%.dist-info}; echo "${b%-*}==${b##*-}"; done; }
hdr() { printf '\n=== %s\n' "$*"; }
envs() { ls -d "$UV_CACHE_DIR_X"/archive-v0/*/ 2>/dev/null | wc -l | tr -d ' '; }
UV_CACHE_DIR_X="$root/cache"

hdr "F: record pins older than latest; replay with unpinned argv holds them?"
uv tool install $P pycodestyle==2.11.1 --with six==1.16.0 -q 2>&1
frozen pycodestyle > F.before; record pycodestyle > F.c.txt; cat F.before
rm -rf "$root/tools/pycodestyle" "$root/bin/shims/pycodestyle"
uv tool install $P --force --no-cache -c F.c.txt pycodestyle --with six -q 2>&1; echo "rc=$?"
frozen pycodestyle > F.after
cmp -s F.before F.after && echo "F frozen set: IDENTICAL" || { echo "F DIFFERS"; cat F.after; }

hdr "G: UV_CONSTRAINT instead of -c: honored? written to receipt?"
rm -rf "$root/tools/pycodestyle" "$root/bin/shims/pycodestyle"
UV_CONSTRAINT="$PWD/F.c.txt" uv tool install $P --force --no-cache pycodestyle --with six -q 2>&1; echo "rc=$?"
frozen pycodestyle
grep -c constraints "$root/tools/pycodestyle/uv-receipt.toml"
uv tool upgrade pycodestyle 2>&1 | tail -2; frozen pycodestyle

hdr "H: git source (glentner/progressbar)"
uv tool install $P git+https://github.com/glentner/progressbar 2>&1 | tail -3
ls "$root/tools"; ls "$root/bin/shims"
gt=$(ls "$root/tools" | grep -v -e pycodestyle -e pyflakes | head -1); echo "tool dir: $gt"
frozen "$gt" > H.before; cat H.before
for di in "$root/tools/$gt"/lib/*/site-packages/*.dist-info; do [ -f "$di/direct_url.json" ] && { echo "${di##*/}:"; cat "$di/direct_url.json"; echo; }; done
echo "--- receipt"; cat "$root/tools/$gt/uv-receipt.toml"
url=$(cat "$root/tools/$gt"/lib/*/site-packages/*.dist-info/direct_url.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["url"]); print(d["vcs_info"]["commit_id"])')
repo_url=$(echo "$url" | sed -n 1p); commit=$(echo "$url" | sed -n 2p)
pkg=$(cat "$root/tools/$gt"/lib/*/site-packages/*.dist-info/direct_url.json >/dev/null; for di in "$root/tools/$gt"/lib/*/site-packages/*.dist-info; do [ -f "$di/direct_url.json" ] && { b=${di##*/}; b=${b%.dist-info}; echo "${b%-*}"; }; done)
echo "pkg=$pkg url=$repo_url commit=$commit"
# H1: constraint file carries a direct-URL line for the VCS pkg, argv is the bare git URL
{ for di in "$root/tools/$gt"/lib/*/site-packages/*.dist-info; do b=${di##*/}; b=${b%.dist-info}; [ -f "$di/direct_url.json" ] || echo "${b%-*}==${b##*-}"; done
  echo "$pkg @ git+$repo_url@$commit"; } > H.c.txt
cat H.c.txt
rm -rf "$root/tools/$gt"; rm -f "$root/bin/shims/"pb*
hdr "H1: replay argv=git+URL (unpinned), -c with 'pkg @ git+URL@commit', UV_OFFLINE unset"
uv tool install $P --force --no-cache -c H.c.txt "git+$repo_url" 2>&1 | tail -3; echo "rc=${PIPESTATUS[0]}"
frozen "$gt" | cmp -s H.before - && echo "H1 frozen IDENTICAL" || { echo H1 DIFFERS; frozen "$gt"; }
cat "$root/tools/$gt"/lib/*/site-packages/*.dist-info/direct_url.json 2>/dev/null; echo
hdr "H2: replay with argv rewritten to git+URL@commit, no VCS line in -c"
grep -v ' @ ' H.c.txt > H2.c.txt
rm -rf "$root/tools/$gt"; rm -f "$root/bin/shims/"pb*
uv tool install $P --force --no-cache -c H2.c.txt "git+$repo_url@$commit" 2>&1 | tail -2; echo "rc=${PIPESTATUS[0]}"
frozen "$gt" | cmp -s H.before - && echo "H2 frozen IDENTICAL" || { echo H2 DIFFERS; frozen "$gt"; }
echo "--- receipt H2"; cat "$root/tools/$gt/uv-receipt.toml"
hdr "H3: H2 offline (cache present, UV_OFFLINE=1) — does a pinned git replay need network?"
rm -rf "$root/tools/$gt"; rm -f "$root/bin/shims/"pb*
UV_OFFLINE=1 uv tool install $P --force -c H2.c.txt "git+$repo_url@$commit" 2>&1 | tail -2; echo "rc=${PIPESTATUS[0]}"

hdr "U: which uvx forms resolve to an installed tool environment?"
uv tool install $P --force pycodestyle==2.11.1 -q 2>&1
n0=$(envs)
try() { local before after out; before=$(envs); out=$(uvx "$@" 2>&1 | tail -1); after=$(envs); echo "uvx $*  -> new_cache_envs=$((after-before))  out=[$out]"; }
try pycodestyle --version
try --from pycodestyle pycodestyle --version
try --from pycodestyle==2.11.1 pycodestyle --version
try pycodestyle@2.11.1 --version
try pycodestyle@latest --version
try --isolated pycodestyle --version
# git tool: package name vs command name differ
gcmd=$(ls "$root/bin/shims" | grep -v -e pycodestyle -e pyflakes | head -1); echo "git tool cmd=$gcmd"
try "$gcmd" --version
try --from "git+$repo_url@$commit" "$gcmd" --version
try --from "git+$repo_url" "$gcmd" --version
try --from "$pkg" "$gcmd" --version
hdr "U-v: verbose evidence for bare name"
uvx -v pycodestyle --version 2>&1 | grep -i -E 'tool|environment|install' | head -5
uvx -v "$gcmd" --version 2>&1 | grep -i -E 'tool|environment|install' | head -5
hdr "U-purged: bare uvx on a tool whose dir is gone but receipt...: whole dir removed"
rm -rf "$root/tools/pycodestyle"
try pycodestyle --version
