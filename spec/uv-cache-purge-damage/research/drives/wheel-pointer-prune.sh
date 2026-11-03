#!/bin/bash
. "$(dirname "$0")/qlib.sh"
seed; cd "$W"
uv python install -q 3.12 2>/dev/null
mk s.py '"tqdm==4.67.1"' 'import tqdm, tqdm.std; print("s ok", tqdm.__version__)'
mk n.py '"tqdm==4.67.1"' 'import tqdm, tqdm.std; print("n ok", tqdm.__version__)'
uv run -q --no-project s.py; uvx -q tqdm==4.67.1 --version >/dev/null
cp -a "$c" "$UVM_SANDBOX/golden"
restore() { find "$c" -delete; cp -a "$UVM_SANDBOX/golden" "$c"; }
wl="$c/wheels-v7/pypi/tqdm/4.67.1-py3-none-any"
na() { ls "$c/archive-v0" | wc -l | tr -d ' '; }
echo "--- Q-A: wheel damaged (module), only the wheels-v7 link removed, new script"
restore; A=$(cd "$wl" && pwd -P); unlink "$A/tqdm/std.py"; unlink "$wl"; n0=$(na)
uv run --no-project n.py 2>&1 | tail -1; echo "rc=$? new archives=$(( $(na) - n0 )) link back=$([ -L "$wl" ] && echo y || echo n) -> $(readlink "$wl")"
echo "--- Q-A2: wheel damaged (module), link kept, .http and .msgpack removed"
restore; A=$(cd "$wl" && pwd -P); unlink "$A/tqdm/std.py"; unlink "$wl.http"; unlink "$wl.msgpack"; n0=$(na)
uv run --no-project n.py 2>&1 | tail -1; echo "new archives=$(( $(na) - n0 ))"
echo "--- Q-A3: wheel damaged (module), archive dir removed whole, link dangling"
restore; A=$(cd "$wl" && pwd -P); find "$A" -delete; n0=$(na)
uv run --no-project n.py 2>&1 | tail -1; echo "new archives=$(( $(na) - n0 ))"
echo "--- Q-B: prune and an aside dir in environments-v2, and an orphan archive"
restore; E=$(ls -d "$c"/environments-v2/s-*); mv "$E" "$c/environments-v2/.uvm-aside.x.1"; l=$(ls -d "$c"/environments-v2/*/* | head -1); X=$(cd "$l" && pwd -P); unlink "$l"
uv cache prune 2>&1 | tail -1 | sed "s|$UVM_SANDBOX|SB|g"
echo "aside survives prune=$([ -d "$c/environments-v2/.uvm-aside.x.1" ] && echo y || echo n) orphan archive survives=$([ -d "$X" ] && echo y || echo n)"
ls -a "$c/environments-v2"
echo "--- Q-B2: aside dir named like a script env? does uv run reuse? (no)"
restore; E=$(ls -d "$c"/environments-v2/s-*); mv "$E" "$E.uvm-removed"; uv run -q --no-project s.py; ls "$c/environments-v2"
