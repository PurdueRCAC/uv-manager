#!/bin/bash
. "$(dirname "$0")/qlib.sh"
seed; cd "$W"
uv python install -q 3.12 2>/dev/null
mk n.py '"tqdm==4.67.1"' 'import tqdm, tqdm.std; print("n ok", tqdm.__version__)'
uvx -q tqdm==4.67.1 --version >/dev/null
cp -a "$c" "$UVM_SANDBOX/golden"
restore() { find "$c" -delete; cp -a "$UVM_SANDBOX/golden" "$c"; }
wl="$c/wheels-v7/pypi/tqdm/4.67.1-py3-none-any"
na() { ls "$c/archive-v0" | wc -l | tr -d ' '; }
for drop in http msgpack "http msgpack" "link http msgpack" "link http"; do
  restore; A=$(cd "$wl" && pwd -P); unlink "$A/tqdm/std.py"; n0=$(na)
  for k in $drop; do case $k in link) unlink "$wl" ;; *) unlink "$wl.$k" ;; esac; done
  out=$(uv run --no-project n.py 2>&1 | tail -1); echo "drop [$drop]: $out new=$(( $(na) - n0 )) link=$([ -L "$wl" ] && readlink "$wl" | sed 's|.*/||')  http=$([ -f "$wl.http" ] && echo y || echo n) msgpack=$([ -f "$wl.msgpack" ] && echo y || echo n)"
done
echo "--- .http head (strings)"; restore; LC_ALL=C strings "$wl.http" | head -8; echo "--- msgpack strings"; LC_ALL=C strings "$wl.msgpack" | head -5
