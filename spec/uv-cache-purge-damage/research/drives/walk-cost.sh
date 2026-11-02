#!/bin/bash
# Walk cost on a cache shaped like the R6 drive's: time doctor with and
# without the cache, and count what the walk stats. Runs inside temp_root.sh
# with the wrapper under test first on PATH; SEED_DIR names a real uv.
set -u
UV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE
a=$(uname -m); root="$UVM_ROOT/$a"; c="$root/cache"; v=$("$SEED_DIR/uv" --version | awk '{print $2}')
mkdir -p "$root/versions/$v" && cp "$SEED_DIR/uv" "$SEED_DIR/uvx" "$root/versions/$v/" && ln -s "versions/$v" "$root/current"
uv python install -q 3.12 2>/dev/null
s="$UVM_SANDBOX/s"; mkdir -p "$s"
for d in requests==2.32.3 click==8.1.7 attrs==24.2.0 pyyaml==6.0.2 packaging==24.1 jinja2==3.1.4 tabulate==0.9.0 python-dateutil==2.9.0.post0 toolz==0.12.1 more-itertools==10.5.0 tqdm==4.67.1; do
  printf '# /// script\n# requires-python = ">=3.12"\n# dependencies = ["%s"]\n# ///\nprint("ok")\n' "$d" > "$s/${d%%=*}.py"; uv run -q --no-project "$s/${d%%=*}.py" >/dev/null
done
for d in pycowsay==0.0.0.2 black==24.10.0 isort==5.13.2 cowsay==6.1 pyflakes==3.2.0 pycodestyle==2.12.1 docutils==0.21.2 pygments==2.18.0 sqlparse==0.5.1 wheel==0.45.1 tqdm==4.67.1; do
  uvx -q --from "$d" python -c pass
done
t() { local TIMEFORMAT=%R; { time uvm doctor >/dev/null 2>&1; } 2>&1; }
lines=0 recs=0
for r in "$c"/environments-v2/*/lib/*/site-packages/*.dist-info/RECORD "$c"/environments-v2/*/*/lib/*/site-packages/*.dist-info/RECORD "$c"/wheels-v*/*/*/*/*.dist-info/RECORD; do
  [ -f "$r" ] || continue; recs=$((recs + 1)); lines=$((lines + $(grep -c . "$r")))
done
echo "files=$(find "$c" -type f | wc -l | tr -d ' ') records=$recs record_lines=$lines"
for i in 1 2 3; do echo "doctor with cache: $(t)s"; done
mv "$c" "$UVM_SANDBOX/aside"; for i in 1 2 3; do echo "doctor without cache: $(t)s"; done
