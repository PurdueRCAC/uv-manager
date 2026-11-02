#!/bin/sh
# P1 gate: what a uv tool command records under UVM_DATA (R2, R9).
# Real uv and network: pypi.org, files.pythonhosted.org, github.com,
# codeload.github.com, releases.astral.sh.
set -u
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
git grep -q -n UVM_DATA -- share/modulefiles/uv/main.lua || { echo "FAIL R9: the modulefile does not set UVM_DATA" >&2; exit 1; }
SEED_UV="$u" GATES="$PWD/spec/installed-tool-parity/gates" .agents/factory/bin/temp_root.sh sh -s <<'DRIVE' || exit 1
set -u
. "$GATES/lib.sh"
seed "$a"
UV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE
run py uv python install 3.12
# R2: an install writes the record, the request as typed.
run i1 uv tool install -p 3.12 pycodestyle==2.11.1 --with six==1.16.0
r="$rec/pycodestyle"
test -f "$r/request" || fail "R2: uv tool install wrote no record under $rec"
[ "$(cat "$r/request")" = "$(printf '%s\n' -p 3.12 pycodestyle==2.11.1 --with six==1.16.0)" ] || fail "R2: request is not the arguments as typed: $(cat "$r/request")"
[ "$(LC_ALL=C sort "$r/constraints" | tr '\n' ' ')" = "pycodestyle==2.11.1 six==1.16.0 " ] || fail "R2: constraints $(cat "$r/constraints")"
[ "$(cat "$r/python")" = 3.12 ] && [ "$(cat "$r/entrypoints")" = pycodestyle ] || fail "R2: python or entrypoints"
cmp -s "$r/uv-receipt.toml" "$UVM_ROOT/$a/tools/pycodestyle/uv-receipt.toml" || fail "R2: the receipt copy differs from the receipt"
# Unpinned at the older releases, then an upgrade moves the pins with the environment.
run i2 uv tool install -p 3.12 pycodestyle --with six
[ "$(cat "$r/request")" = "$(printf '%s\n' -p 3.12 pycodestyle --with six)" ] || fail "R2: a reinstall did not rewrite the request"
[ "$(LC_ALL=C sort "$r/constraints" | tr '\n' ' ')" = "pycodestyle==2.11.1 six==1.16.0 " ] || fail "R2: the unpinned tool is not at its older releases"
run up uv tool upgrade pycodestyle
grep -qx 'pycodestyle==2.11.1' "$r/constraints" && fail "R2: the upgrade did not move the record's pins"
[ "$(LC_ALL=C sort "$r/constraints")" = "$(envpins pycodestyle)" ] || fail "R2: pins after upgrade differ from the environment"
[ "$(cat "$r/request")" = "$(printf '%s\n' -p 3.12 pycodestyle --with six)" ] || fail "R2: an upgrade changed the request"
# A git source records its commit as a constraint.
run g uv tool install -p 3.12 git+https://github.com/glentner/progressbar
grep -Eqx 'progressbar @ git\+https://github\.com/glentner/progressbar@[0-9a-f]{40}' "$rec/progressbar/constraints" || fail "R2: no VCS pin: $(cat "$rec/progressbar/constraints")"
[ "$(cat "$rec/progressbar/entrypoints")" = pb ] || fail "R2: the git tool's entrypoint is not pb"
# upgrade --all rewrites each record to its environment.
run i3 uv tool install -p 3.12 pyflakes==3.2.0
run all uv tool upgrade --all
for t in pycodestyle progressbar pyflakes; do
    [ "$(grep -v ' @ ' "$rec/$t/constraints" | LC_ALL=C sort)" = "$(envpins $t)" ] || fail "R2: $t's record differs from its environment after upgrade --all"
done
# A failed install changes nothing under UVM_DATA.
datalist > "$o/before"
if uv tool install -p 3.12 uvm-no-such-distribution-xyzzy > "$o/bad.out" 2>&1; then fail "R2: installing a missing name exited 0"; fi
datalist | cmp -s "$o/before" - || fail "R2: a failed install changed UVM_DATA"
# No credential from a URL's userinfo reaches UVM_DATA.
run sec uv tool install -p 3.12 --force --index-url https://__token__:SECRETMARK@pypi.org/simple pyflakes==3.2.0
if grep -r -l SECRETMARK "$data"; then fail "R2: a credential reached UVM_DATA"; fi
grep -qx 'https://pypi.org/simple' "$rec/pyflakes/request" || fail "R2: the index URL was not kept without its userinfo"
# The receipt is copied only when no URL in it carries userinfo, under any scheme; a
# password-less ssh login is kept, as in the request. Planted as a comment, rewritten by a backfill.
rc0="$UVM_ROOT/$a/tools/pyflakes/uv-receipt.toml"; cp "$rc0" "$o/rcpt.pyflakes"
mv "$rec/pyflakes" "$trash/rec.pyflakes.ssh1"; printf '# git+ssh://user:SECRETSSH@example.invalid/repo\n' >> "$rc0"
run ssh1 uv tool list
test -f "$rec/pyflakes/request" || fail "R2: the backfill wrote no record"
if grep -r -l SECRETSSH "$data"; then fail "R2: an ssh URL's password reached UVM_DATA through the receipt copy"; fi
cp "$o/rcpt.pyflakes" "$rc0"; mv "$rec/pyflakes" "$trash/rec.pyflakes.ssh2"; printf '# git+ssh://git@example.invalid/repo\n' >> "$rc0"
run ssh2 uv tool list
cmp -s "$rc0" "$rec/pyflakes/uv-receipt.toml" || fail "R2: a password-less ssh login kept the receipt from the record"
cp "$o/rcpt.pyflakes" "$rc0"
# An uninstall deletes the record.
run un uv tool uninstall pyflakes
[ ! -e "$rec/pyflakes" ] || fail "R2: uninstall left the record"
# R9: a second platform key shares the records; nothing under UVM_DATA names a key.
seed uvmfake
run k2 env UVM_PLATFORM=uvmfake uv tool install -p 3.12 pyflakes==3.2.0
test -f "$rec/pyflakes/request" || fail "R9: an install on a second key wrote no record"
if find "$data" | grep -e "/$a" -e uvmfake; then fail "R9: a path under UVM_DATA names a platform key"; fi
if find "$data" -type f | grep -v -E -e '/tools/[^/]+/(request|constraints|python|entrypoints|uv-receipt\.toml)$' -e "^$data/bin/[^/]+\$"; then fail "R9: a file under UVM_DATA is neither a record nor a trampoline"; fi
for t in "$rec"/*/; do k=$(du -sk "$t" | awk '{ print $1 }'); [ "$k" -le 24 ] || fail "R9: record $t is $k KB"; done
uvm status > "$o/st" 2>&1
grep -q "^UVM_DATA: *$data  (from \$XDG_DATA_HOME)" "$o/st" || { cat "$o/st" >&2; fail "R9: status does not name UVM_DATA and its origin"; }
[ "$(uvm help | grep -c UVM_DATA)" -ge 1 ] || fail "R9: uvm help does not name UVM_DATA"
# R9: the default chain, UVM_DATA first, then XDG_DATA_HOME, then HOME.
run ex env UVM_DATA="$UVM_SANDBOX/explicit" uv tool install -p 3.12 --force pyflakes==3.2.0
test -f "$UVM_SANDBOX/explicit/tools/pyflakes/request" || fail "R9: UVM_DATA was not used"
run hm env -u XDG_DATA_HOME HOME="$UVM_SANDBOX/home" uv tool install -p 3.12 --force pyflakes==3.2.0
test -f "$UVM_SANDBOX/home/.local/share/uvm/tools/pyflakes/request" || fail "R9: HOME/.local/share/uvm was not the default"
env -u XDG_DATA_HOME HOME="$UVM_SANDBOX/home" uvm status 2>&1 | grep -q "^UVM_DATA: *$UVM_SANDBOX/home/.local/share/uvm  (from \$HOME)" || fail "R9: status under HOME"
echo "P1 ok"
DRIVE
