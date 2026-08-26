---
slug: lock-ownership-and-hold-time
title: The provisioning lock can be released by a process that does not hold it
kind: fix
appetite: big
status: done
branch: fix/lock-ownership-and-hold-time
base: main
current_phase: done
last_updated: '2026-08-26'
phases:
- id: P1
  name: Give the lock an identity, and release only what matches it
  status: done
  satisfies:
  - R1
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: 'set -eu

    bash -n bin/uv-manager

    .agents/factory/bin/lint.sh >/dev/null

    .agents/factory/bin/temp_root.sh --offline sh -s <<''DRIVE''

    set -e

    A="$UVM_ROOT/$(uname -m)"; L="$A/.install.lock"; export UVM_TEST_LOCK="$L"

    printf ''%s\n'' ''printf "host=elsewhere pid=999999 nonce=0\n" > "$UVM_TEST_LOCK/owner"''
    >> "$UVM_FIXTURE_DIR/install.sh"

    uv --version >/dev/null

    if [ ! -d "$L" ]; then echo "FAIL: release removed a lock this process does not
    own" >&2; exit 1; fi

    if [ ! -f "$L/owner" ]; then echo "FAIL: foreign owner file removed" >&2; exit
    1; fi

    if ! grep -q ''pid=999999'' "$L/owner"; then echo "FAIL: foreign owner overwritten"
    >&2; exit 1; fi

    DRIVE

    .agents/factory/bin/temp_root.sh --offline sh -s <<''DRIVE''

    set -e

    uv --version >/dev/null

    L="$UVM_ROOT/$(uname -m)/.install.lock"

    if [ -d "$L" ]; then echo "FAIL: own lock not released" >&2; exit 1; fi

    DRIVE

    '
- id: P2
  name: Release before every exec of the real uv
  status: done
  satisfies:
  - R4
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\nn=$(git grep -n 'exec \"\\${real_' bin/uv-manager\
    \ | wc -l | tr -d ' ')\nif [ \"$n\" != 4 ]; then echo \"FAIL: exec census is $n,\
    \ expected 4\" >&2; exit 1; fi\n.agents/factory/bin/lint.sh >/dev/null\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nuv --version >/dev/null 2>&1\nfor probe in\
    \ \"--version\" \"self update\"; do\n  PS4='+ ' bash -x \"$(command -v uv)\" $probe\
    \ >/dev/null 2>\"$UVM_SANDBOX/t\" || true\n  u=$(grep -n '^++* uvm_unlock$' \"\
    $UVM_SANDBOX/t\" | tail -1 | cut -d: -f1 || true)\n  p=$(grep -n '^++* export\
    \ PATH$' \"$UVM_SANDBOX/t\" | tail -1 | cut -d: -f1 || true)\n  e=$(grep -n '^++*\
    \ exec ' \"$UVM_SANDBOX/t\" | tail -1 | cut -d: -f1 || true)\n  if [ -z \"$u\"\
    \ ] || [ -z \"$e\" ] || [ \"$u\" -lt \"$p\" ] || [ \"$u\" -gt \"$e\" ]; then\n\
    \    echo \"FAIL: no release between uvm_export_env and exec on 'uv $probe' (unlock=$u\
    \ path=$p exec=$e)\" >&2\n    exit 1\n  fi\ndone\nDRIVE\n"
- id: P3
  name: Keep a live holder's lock alive for as long as the holder is
  status: done
  satisfies:
  - R2
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: downhill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"\nprintf '%s\\n' 'if [ -n \"${UVM_FIXTURE_SLOW:-}\"\
    \ ]; then sleep \"$UVM_FIXTURE_SLOW\"; fi' >> \"$UVM_FIXTURE_DIR/install.sh\"\n\
    ( UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=3 UVM_FIXTURE_SLOW=8 uv --version >/dev/null\
    \ 2>\"$UVM_SANDBOX/holder.err\" ) & holder=$!\nsleep 1\nfirst=$(sed -n 's/.*\\\
    (pid=[0-9][0-9]*\\).*/\\1/p' \"$L/owner\" 2>/dev/null || true)\nsleep 4\nset +e\n\
    UVM_LOCK_STALE=3 UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/waiter.err\"\
    \nset -e\nnow=$(sed -n 's/.*\\(pid=[0-9][0-9]*\\).*/\\1/p' \"$L/owner\" 2>/dev/null\
    \ || true)\nif grep -q 'breaking stale provisioning lock' \"$UVM_SANDBOX/waiter.err\"\
    ; then\n  echo \"FAIL: a live holder's lock was broken as stale\" >&2; exit 1\n\
    fi\nif [ -z \"$first\" ] || [ \"$first\" != \"$now\" ]; then\n  echo \"FAIL: lock\
    \ was $first, now ${now:-gone}\" >&2; exit 1\nfi\nwait \"$holder\"\nDRIVE\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\
    \nprintf '%s\\n' 'if [ -n \"${UVM_FIXTURE_SLOW:-}\" ]; then sleep \"$UVM_FIXTURE_SLOW\"\
    ; fi' >> \"$UVM_FIXTURE_DIR/install.sh\"\n( UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=10\
    \ UVM_FIXTURE_SLOW=20 uv --version >/dev/null 2>&1 ) & holder=$!\nsleep 2\np=$(sed\
    \ -n 's/.*pid=\\([0-9][0-9]*\\).*/\\1/p' \"$L/owner\" 2>/dev/null || true)\nif\
    \ [ -z \"$p\" ]; then echo \"FAIL: no holder pid recorded\" >&2; exit 1; fi\n\
    kill -9 \"$p\" 2>/dev/null || true\nsleep 1; m1=$(stat -f %m \"$L/owner\" 2>/dev/null\
    \ || stat -c %Y \"$L/owner\" 2>/dev/null || true)\nsleep 3; m2=$(stat -f %m \"\
    $L/owner\" 2>/dev/null || stat -c %Y \"$L/owner\" 2>/dev/null || true)\nwait \"\
    $holder\" 2>/dev/null || true\nif [ \"$m1\" != \"$m2\" ]; then\n  echo \"FAIL:\
    \ something refreshed the lock after its holder was killed ($m1 -> $m2)\" >&2;\
    \ exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\n\
    set -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\nmkdir -p \"$A\";\
    \ mkdir \"$L\"\nsleep 30 & victim=$!\nprintf 'host=%s pid=%s nonce=recycled\\\
    n' \"$(uname -n)\" \"$victim\" > \"$L/owner\"\ntouch -t 202001010000 \"$L/owner\"\
    \ \"$L\"\nset +e\nUVM_LOCK_STALE=5 UVM_LOCK_TIMEOUT=4 uv --version >/dev/null\
    \ 2>\"$UVM_SANDBOX/reuse.err\"\nrc=$?\nset -e\nkill \"$victim\" 2>/dev/null ||\
    \ true\nwait \"$victim\" 2>/dev/null || true\nif ! grep -q 'breaking stale provisioning\
    \ lock' \"$UVM_SANDBOX/reuse.err\"; then\n  echo \"FAIL: a lock past UVM_LOCK_STALE\
    \ went unbroken because its recorded pid was reused\" >&2\n  cat \"$UVM_SANDBOX/reuse.err\"\
    \ >&2; exit 1\nfi\nif [ \"$rc\" -ne 0 ]; then\n  echo \"FAIL: waiter did not acquire\
    \ after breaking the stale lock (rc=$rc)\" >&2\n  cat \"$UVM_SANDBOX/reuse.err\"\
    \ >&2; exit 1\nfi\nt=$(readlink \"$A/current\" 2>/dev/null || true)\nif [ \"$t\"\
    \ != \"versions/9.9.9\" ]; then echo \"FAIL: current is ${t:-missing}\" >&2; exit\
    \ 1; fi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset\
    \ -e\nA=\"$UVM_ROOT/$(uname -m)\"\nUVM_TEST_CAP=\"$UVM_SANDBOX/owner.captured\"\
    ; export UVM_TEST_CAP\nUVM_TEST_LOCK=\"$A/.install.lock\"; export UVM_TEST_LOCK\n\
    printf '%s\\n' 'cp \"$UVM_TEST_LOCK/owner\" \"$UVM_TEST_CAP\" 2>/dev/null || true'\
    \ >> \"$UVM_FIXTURE_DIR/install.sh\"\nHOSTNAME=spoofed.invalid; export HOSTNAME\n\
    uv --version >/dev/null\nif [ ! -s \"$UVM_TEST_CAP\" ]; then echo \"FAIL: no owner\
    \ line captured\" >&2; exit 1; fi\nif grep -q 'host=spoofed.invalid' \"$UVM_TEST_CAP\"\
    ; then\n  echo \"FAIL: an inherited HOSTNAME reached the lock's owner record\"\
    \ >&2\n  cat \"$UVM_TEST_CAP\" >&2; exit 1\nfi\nif ! grep -q \"host=$(uname -n)\
    \ \" \"$UVM_TEST_CAP\"; then\n  echo \"FAIL: the owner line does not record uname\
    \ -n\" >&2\n  cat \"$UVM_TEST_CAP\" >&2; exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\
    \nprintf '%s\\n' 'if [ -n \"${UVM_FIXTURE_SLOW:-}\" ]; then sleep \"$UVM_FIXTURE_SLOW\"\
    ; fi' >> \"$UVM_FIXTURE_DIR/install.sh\"\n( UVM_FIXTURE_SLOW=600 uv --version\
    \ >/dev/null 2>&1 ) & holder=$!\nsleep 3\nP=$(sed -n 's/.*pid=\\([0-9][0-9]*\\\
    ).*/\\1/p' \"$L/owner\" 2>/dev/null || true)\n[ -n \"$P\" ] || { echo \"FAIL:\
    \ no holder pid recorded\" >&2; exit 1; }\nkill -9 \"$P\" 2>/dev/null || true\n\
    wait \"$holder\" 2>/dev/null || true\nt0=$(date +%s)\nvictim=\"\"\nwhile [ -z\
    \ \"$victim\" ]; do\n  i=0; while [ $i -lt 200 ]; do ( : ) & i=$(( i + 1 )); done;\
    \ wait\n  ( : ) & c=$!; wait \"$c\" 2>/dev/null || true\n  if [ \"$c\" -lt \"\
    $P\" ] && [ $(( P - c )) -le 600 ]; then\n    while :; do\n      sleep 300 & c=$!\n\
    \      if [ \"$c\" = \"$P\" ]; then victim=$c; break; fi\n      kill -9 \"$c\"\
    \ 2>/dev/null || true; wait \"$c\" 2>/dev/null || true\n      [ \"$c\" -lt \"\
    $P\" ] || break\n    done\n  fi\ndone\nburn=$(( $(date +%s) - t0 ))\nif [ \"$burn\"\
    \ -ge 50 ]; then\n  kill -9 \"$victim\" 2>/dev/null || true\n  echo \"FAIL: the\
    \ walk took ${burn}s against a 60s beat -- the refresher stood down for want of\
    \ a pid, not for want of its holder\" >&2\n  exit 1\nfi\nm1=$(stat -f %m \"$L/owner\"\
    \ 2>/dev/null || stat -c %Y \"$L/owner\" 2>/dev/null || true)\nsleep 75\nm2=$(stat\
    \ -f %m \"$L/owner\" 2>/dev/null || stat -c %Y \"$L/owner\" 2>/dev/null || true)\n\
    kill -9 \"$victim\" 2>/dev/null || true\nif [ \"$m1\" != \"$m2\" ]; then\n  echo\
    \ \"FAIL: the refresher outlived its holder and kept the lock fresh ($m1 -> $m2)\
    \ -- a recycled pid makes the lock immortal\" >&2\n  exit 1\nfi\nDRIVE"
- id: P4
  name: Refuse a knob configuration that lets a waiter break a live lock
  status: done
  satisfies:
  - R3
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=%s\
    \ pid=%s nonce=0\\n' \"$(uname -n)\" \"$$\" > \"$L/owner\"\nsleep 3\nset +e\n\
    UVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"\
    ; rc=$?\nset -e\nif [ \"$rc\" -eq 0 ]; then echo \"FAIL: inverted knobs accepted\
    \ (rc=0)\" >&2; exit 1; fi\nif ! grep -q UVM_LOCK_TIMEOUT \"$UVM_SANDBOX/err\"\
    \ || ! grep -q UVM_LOCK_STALE \"$UVM_SANDBOX/err\"; then\n  echo \"FAIL: refusal\
    \ does not name both variables\" >&2; exit 1\nfi\nif [ ! -d \"$L\" ]; then echo\
    \ \"FAIL: the live lock was destroyed\" >&2; exit 1; fi\nset +e\nUVM_LOCK_STALE=abc\
    \ uv --version >/dev/null 2>&1; rcn=$?\nset -e\nif [ \"$rcn\" -eq 0 ]; then echo\
    \ \"FAIL: non-numeric UVM_LOCK_STALE accepted (rc=0)\" >&2; exit 1; fi\nUVM_LOCK_TIMEOUT=10\
    \ UVM_LOCK_STALE=2 uvm --version >/dev/null\nUVM_LOCK_TIMEOUT=10 UVM_LOCK_STALE=2\
    \ uvm help >/dev/null\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s\
    \ <<'DRIVE'\nset +e\nUVM_LOCK_TIMEOUT=0600 UVM_LOCK_STALE=500 uv --version >/dev/null\
    \ 2>\"$UVM_SANDBOX/oct\"; rc=$?\nset -e\nif [ \"$rc\" -eq 0 ]; then\n  echo \"\
    FAIL: 0600 vs 500 accepted -- the guard judged 384, not 600\" >&2; exit 1\nfi\n\
    if ! grep -q 'UVM_LOCK_TIMEOUT=600' \"$UVM_SANDBOX/oct\"; then\n  echo \"FAIL:\
    \ the refusal prints the raw string, not the seconds it judged\" >&2; exit 1\n\
    fi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\n\
    out=$(UVM_LOCK_TIMEOUT=500 UVM_LOCK_STALE=0600 uv --version 2>\"$UVM_SANDBOX/oct2\"\
    )\nif [ \"$out\" != \"uv 9.9.9 (fixture)\" ]; then\n  echo \"FAIL: a legal pair\
    \ spelled 500/0600 was refused: $(cat \"$UVM_SANDBOX/oct2\")\" >&2; exit 1\nfi\n\
    DRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"\
    $UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\"; mkdir \"$L\"\
    \nprintf 'host=%s pid=%s nonce=0\\n' \"$(uname -n)\" \"$$\" > \"$L/owner\"\nset\
    \ +e\nUVM_LOCK_TIMEOUT=3 UVM_LOCK_STALE=0800 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"\
    \nset -e\nif grep -q 'value too great for base' \"$UVM_SANDBOX/err\"; then\n \
    \ echo \"FAIL: the form check passed a value the arithmetic cannot evaluate\"\
    \ >&2; exit 1\nfi\nDRIVE\nif ! grep -q 'UVM_LOCK_TIMEOUT' etc/uv-manager.conf.example;\
    \ then echo \"FAIL: conf example silent\" >&2; exit 1; fi\nfor f in README.md\
    \ etc/uv-manager.conf.example bin/uv-manager; do\n  if ! grep -q 'less than' \"\
    $f\"; then echo \"FAIL: $f does not state the ordering constraint\" >&2; exit\
    \ 1; fi\ndone\n"
- id: P5
  name: Tell a stalled user how to tell an abandoned lock from a live one
  status: done
  satisfies:
  - R5
  - R6
  depends_on:
  - P4
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=node0042\
    \ pid=12345 nonce=0\\n' > \"$L/owner\"\nset +e\nUVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=600\
    \ uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"; rc=$?\nset -e\nif [ \"$rc\"\
    \ -eq 0 ]; then echo \"FAIL: waiter did not time out\" >&2; exit 1; fi\nfor tok\
    \ in owner host pid; do\n  if ! grep -qw \"$tok\" \"$UVM_SANDBOX/err\"; then\n\
    \    echo \"FAIL: timeout message never mentions '$tok'\" >&2; exit 1\n  fi\n\
    done\nif ! grep -q \"rm -f .*owner.* && rmdir\" \"$UVM_SANDBOX/err\"; then\n \
    \ echo \"FAIL: recovery command still advises a bare rmdir that cannot succeed\"\
    \ >&2; exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\n\
    set -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$A\";\
    \ mkdir \"$L\"\nprintf 'host=node0042 pid=12345 nonce=0\\n' > \"$L/owner\"\nsleep\
    \ 3\nif ! UVM_LOCK_STALE=2 UVM_LOCK_TIMEOUT=1 uv --version >/dev/null 2>\"$UVM_SANDBOX/brk\"\
    ; then\n  echo \"FAIL: the stale-break drive exited non-zero:\" >&2; cat \"$UVM_SANDBOX/brk\"\
    \ >&2; exit 1\nfi\nif ! grep -q 'breaking' \"$UVM_SANDBOX/brk\"; then echo \"\
    FAIL: no break occurred\" >&2; exit 1; fi\nif ! grep -q 'pid=12345' \"$UVM_SANDBOX/brk\"\
    ; then\n  echo \"FAIL: stale-break note does not name the owner it deleted\" >&2;\
    \ exit 1\nfi\nDRIVE\nif ! grep -q 'install\\.lock' README.md; then\n  echo \"\
    FAIL: README documents no lock troubleshooting entry\" >&2; exit 1\nfi\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nout=$(uv --version)\nif [ \"$out\" != \"\
    uv 9.9.9 (fixture)\" ]; then echo \"FAIL: stdout was '$out'\" >&2; exit 1; fi\n\
    A=\"$UVM_ROOT/$(uname -m)\"\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9\
    \ ]; then echo \"FAIL: current target moved\" >&2; exit 1; fi\nDRIVE\nif git grep\
    \ -n flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#';\
    \ then\n  echo \"FAIL: flock invoked outside a comment\" >&2; exit 1\nfi"
- id: P6
  name: Make UVM_LOCK_TIMEOUT bound a waiter it cannot break free of
  status: done
  satisfies:
  - R7
  - R6
  depends_on:
  - P5
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; L=\"$A/.install.lock\"\nmkdir -p \"$L/stuck\"\nsleep 4\nUVM_LOCK_STALE=3\
    \ UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\" &\np=$!\n\
    sleep 6\nif kill -0 \"$p\" 2>/dev/null; then\n  kill -9 \"$p\" 2>/dev/null ||\
    \ true\n  echo \"FAIL: still spinning 6s after a 2s timeout ($(wc -l < \"$UVM_SANDBOX/err\"\
    \ | tr -d ' ') lines)\" >&2\n  exit 1\nfi\nif ! grep -q 'timed out after' \"$UVM_SANDBOX/err\"\
    ; then\n  echo \"FAIL: the waiter exited without the timeout message\" >&2; exit\
    \ 1\nfi\nif [ \"$(grep -c 'breaking' \"$UVM_SANDBOX/err\" || true)\" -gt 1 ];\
    \ then\n  echo \"FAIL: the denied break re-announced itself every iteration\"\
    \ >&2; exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\n\
    set -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"; mkdir -p \"$L\"\n\
    printf 'host=%s pid=999999 nonce=0\\n' \"$(uname -n)\" > \"$L/owner\"\nchmod 500\
    \ \"$L\"\nUVM_LOCK_STALE=600 UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/dead\"\
    \ &\np=$!\nsleep 6\nalive=no\nif kill -0 \"$p\" 2>/dev/null; then alive=yes; kill\
    \ -9 \"$p\" 2>/dev/null || true; fi\nchmod 700 \"$L\"\nif [ \"$alive\" = yes ];\
    \ then\n  echo \"FAIL: a denied break of a dead holder's lock spun past the timeout\"\
    \ >&2; exit 1\nfi\nif ! grep -q 'timed out after' \"$UVM_SANDBOX/dead\"; then\n\
    \  echo \"FAIL: the dead-holder waiter exited without the timeout message\" >&2;\
    \ exit 1\nfi\nif [ \"$(grep -c 'breaking' \"$UVM_SANDBOX/dead\" || true)\" -gt\
    \ 1 ]; then\n  echo \"FAIL: the denied dead-holder break re-announced itself every\
    \ iteration\" >&2; exit 1\nfi\nDRIVE\n.agents/factory/bin/temp_root.sh --offline\
    \ sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\
    ; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=node0042 pid=12345 nonce=0\\n' >\
    \ \"$L/owner\"\nsleep 3\nif ! UVM_LOCK_STALE=2 UVM_LOCK_TIMEOUT=1 uv --version\
    \ >/dev/null 2>\"$UVM_SANDBOX/brk\"; then\n  echo \"FAIL: the stale-break drive\
    \ exited non-zero:\" >&2; cat \"$UVM_SANDBOX/brk\" >&2; exit 1\nfi\nif ! grep\
    \ -q 'breaking' \"$UVM_SANDBOX/brk\"; then\n  echo \"FAIL: an ordinary stale break\
    \ no longer works\" >&2; exit 1\nfi\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9\
    \ ]; then echo \"FAIL: break did not provision\" >&2; exit 1; fi\nDRIVE\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nout=$(uv --version)\nif [ \"$out\" != \"\
    uv 9.9.9 (fixture)\" ]; then echo \"FAIL: stdout was '$out'\" >&2; exit 1; fi\n\
    A=\"$UVM_ROOT/$(uname -m)\"\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9\
    \ ]; then echo \"FAIL: current target moved\" >&2; exit 1; fi\nDRIVE\nif git grep\
    \ -n flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#';\
    \ then\n  echo \"FAIL: flock invoked outside a comment\" >&2; exit 1\nfi"
- id: P7
  name: Stop misreading a released lock as a broken filesystem
  status: done
  satisfies:
  - R8
  depends_on:
  - P6
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    total=0; dead=0\nfor b in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20;\
    \ do\n  r=$(.agents/factory/bin/temp_root.sh --offline sh -s <<'DRIVE'\nfor k\
    \ in $(seq 1 64); do ( uv --version >/dev/null 2>\"$UVM_SANDBOX/err.$k\" || echo\
    \ x >> \"$UVM_SANDBOX/fail\" ) & done\nwait\nq=$(grep -l 'check permissions and\
    \ quota' \"$UVM_SANDBOX\"/err.* 2>/dev/null | wc -l | tr -d ' ')\nf=0; [ -f \"\
    $UVM_SANDBOX/fail\" ] && f=$(wc -l < \"$UVM_SANDBOX/fail\" | tr -d ' ')\necho\
    \ \"$q $f\"\nDRIVE\n)\n  total=$(( total + ${r% *} )); dead=$(( dead + ${r#* }\
    \ ))\ndone\necho \"misdiagnosed=${total}/1280 nonzero=${dead}/1280\"\nif [ \"\
    $total\" -ne 0 ]; then echo \"FAIL: ${total}/1280 ranks reported a permissions/quota\
    \ fault on a healthy filesystem\" >&2; exit 1; fi\nif [ \"$dead\" -ne 0 ]; then\
    \ echo \"FAIL: ${dead}/1280 ranks exited non-zero\" >&2; exit 1; fi\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nA=\"$UVM_ROOT/$(uname -m)\"; mkdir -p \"$A\"; chmod\
    \ 500 \"$A\"; s=$(date +%s)\nuv --version >/dev/null 2>\"$UVM_SANDBOX/e\" && {\
    \ chmod 700 \"$A\"; echo \"FAIL: unwritable root accepted\" >&2; exit 1; }\ne=$((\
    \ $(date +%s) - s )); chmod 700 \"$A\"\nif ! grep -q 'check permissions and quota'\
    \ \"$UVM_SANDBOX/e\"; then echo \"FAIL: a real permissions fault is no longer\
    \ named\" >&2; exit 1; fi\nif [ \"$e\" -ge 5 ]; then echo \"FAIL: the fault took\
    \ ${e}s -- the retry is not bounded by a constant\" >&2; exit 1; fi\nDRIVE"
- id: P8
  name: Narrow the break to the instance it judged; repair the seed's citations
  status: done
  satisfies: []
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: downhill
  attempts: 1
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    # Census, not a drive: the guard fires in a sub-millisecond window no sandbox\
    \ can\n# open on demand, so what is assertable is that both removals sit inside\
    \ it.\n# Gating the owner removal is what leaves rmdir a non-empty directory to\
    \ refuse.\nif ! grep -F -A3 'if [[ \"${still}\" == \"${holder}\" ]]; then' bin/uv-manager\
    \ | grep -F -q 'rm -f \"${lock}/owner\"'; then\n  echo \"FAIL: the owner removal\
    \ is not inside the identity guard\" >&2; exit 1\nfi\nif ! grep -F -A3 'if [[\
    \ \"${still}\" == \"${holder}\" ]]; then' bin/uv-manager | grep -F -q 'rmdir \"\
    ${lock}\"'; then\n  echo \"FAIL: the rmdir is not inside the identity guard --\
    \ it can still empty a lock it did not judge\" >&2; exit 1\nfi\n# Three removals\
    \ of the lock directory are legitimate and no more: uvm_unlock's,\n# which is\
    \ ownership-guarded; the break's, guarded above; and the cleanup of a\n# directory\
    \ we created and could not claim. A fourth is an unguarded path.\nif [ \"$(grep\
    \ -c -F 'rmdir \"${lock}\" 2>/dev/null' bin/uv-manager | tr -d ' ')\" != 3 ];\
    \ then\n  echo \"FAIL: rmdir census is $(grep -c -F 'rmdir \"${lock}\" 2>/dev/null'\
    \ bin/uv-manager | tr -d ' '), expected 3\" >&2; exit 1\nfi\n# The guard must\
    \ not decline a break that is genuinely owed.\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\
    ; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=node0042 pid=12345 nonce=0\\n' >\
    \ \"$L/owner\"\nsleep 3\nif ! UVM_LOCK_STALE=2 UVM_LOCK_TIMEOUT=1 uv --version\
    \ >/dev/null 2>\"$UVM_SANDBOX/brk\"; then\n  echo \"FAIL: the identity guard declined\
    \ a break that was owed:\" >&2; cat \"$UVM_SANDBOX/brk\" >&2; exit 1\nfi\nif !\
    \ grep -q 'breaking' \"$UVM_SANDBOX/brk\"; then echo \"FAIL: no break occurred\"\
    \ >&2; exit 1; fi\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9 ]; then\
    \ echo \"FAIL: break did not provision\" >&2; exit 1; fi\nDRIVE\n# A dead holder\
    \ on this node is still broken at once, the guard notwithstanding.\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'DRIVE'\nset -e\nA=\"$UVM_ROOT/$(uname -m)\"; L=\"$A/.install.lock\"\
    ; mkdir -p \"$A\"; mkdir \"$L\"\nprintf 'host=%s pid=999999 nonce=0\\n' \"$(uname\
    \ -n)\" > \"$L/owner\"\nif ! UVM_LOCK_STALE=600 UVM_LOCK_TIMEOUT=5 uv --version\
    \ >/dev/null 2>\"$UVM_SANDBOX/dead\"; then\n  echo \"FAIL: a dead holder's lock\
    \ was not reclaimed:\" >&2; cat \"$UVM_SANDBOX/dead\" >&2; exit 1\nfi\nif ! grep\
    \ -q 'abandoned by a dead process' \"$UVM_SANDBOX/dead\"; then\n  echo \"FAIL:\
    \ the dead-holder fast path did not fire\" >&2; cat \"$UVM_SANDBOX/dead\" >&2;\
    \ exit 1\nfi\nDRIVE\n# Full R6 regression.\n.agents/factory/bin/temp_root.sh --offline\
    \ sh -s <<'DRIVE'\nset -e\nout=$(uv --version)\nif [ \"$out\" != \"uv 9.9.9 (fixture)\"\
    \ ]; then echo \"FAIL: stdout was '$out'\" >&2; exit 1; fi\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"\nif [ \"$(readlink \"$A/current\")\" != versions/9.9.9 ]; then echo \"\
    FAIL: current target moved\" >&2; exit 1; fi\nif [ -d \"$A/.install.lock\" ];\
    \ then echo \"FAIL: lock left behind\" >&2; exit 1; fi\nDRIVE\nif git grep -n\
    \ flock bin/uv-manager | grep -qvE '^bin/uv-manager:[0-9]+:[[:space:]]*#'; then\n\
    \  echo \"FAIL: flock invoked outside a comment\" >&2; exit 1\nfi\n# Every citation\
    \ the seed makes must land inside the file, and on what it names.\nfor c in $(sed\
    \ -n 's/.*bin\\/uv-manager:\\([0-9]*\\).*/\\1/p' issues/invariant-audit-gaps.md);\
    \ do\n  if [ \"$c\" -gt \"$(wc -l < bin/uv-manager)\" ]; then echo \"FAIL: seed\
    \ cites bin/uv-manager:$c, past end of file\" >&2; exit 1; fi\ndone\nsed -n '595p'\
    \ bin/uv-manager | grep -q 'mv \"${tmp}\" \"${dest}\"' || { echo \"FAIL: :595\
    \ is not the unguarded rename\" >&2; exit 1; }\nsed -n '725,729p' bin/uv-manager\
    \ | grep -q 'uvm_tramp_marker' || { echo \"FAIL: :725-729 is not the trampoline\
    \ overwrite guard\" >&2; exit 1; }\nsed -n '767,772p' bin/uv-manager | grep -q\
    \ 'cache-dir' || { echo \"FAIL: :767-772 is not the banner naming --cache-dir\"\
    \ >&2; exit 1; }"
review:
  last_reviewed_commit: 8eac4b73dfda91e54f1fb97746183234b658e5f3
  verdict: changes-requested
  blocked_reason: 'F9: the fatal owner write kills a rank robbed by the break race;
    main''s suppressed write let it live'
  cycle: 3
---
# TECH.md — The provisioning lock can be released by a process that does not hold it

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/lock-ownership-and-hold-time/TECH.md`); the per-phase
checklists below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus seven briefs — six from
  the planning fan-out, and [`07`](research/07-acquire-race.md) carrying R8's Anvil evidence.

## Ordering, and why it is not negotiable

**P2 (R4) lands before P3 (R2).** `exec` preserves the pid, so the heartbeat's `kill -0 "$$"` leash
still passes after the wrapper has been replaced by the real `uv`. Shipping the heartbeat first would
turn today's bounded 600-second leak into a lock nothing can ever break. This is the digest's headline
finding and the reason the GOAL was amended to cover all four `exec` sites.

**P7 (R8) lands after P6 (R7), and not folded into it.** The two predicates are duals evaluated at
different points of one iteration — `[[ ! -d ]]` after *our failed `mkdir`*, `[[ -d ]]` after *our own
`rmdir`* — and they must give one answer to the same question: when may the loop re-enter `mkdir`
without paying the accounting? P6 establishes the answer; P7 applies it one branch earlier. They are
kept separate because P6's gate is deterministic and P7's is statistical, and mixing them makes it
impossible to say which assertion discriminated; and because both edit the same `local` line, which is
a sequential edit if ordered and a conflict if not.

Every phase is `hammerable: false`: all six touch `invariants.md` §5 or §2, both in the
high-blast-radius list. Every phase is `parallel: false`; there is one source file.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and invariants come from [`AGENTS.md`](../../AGENTS.md);
  [`invariants.md`](../../.agents/factory/invariants.md) is the footgun checklist.
- One phase per `uvm-build` invocation; one atomic commit with both the code and the `TECH.md` state
  change. Subjects: `[fix] Build lock-ownership-and-hold-time P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids in `bin/uv-manager` or `README.md`.
- Gates run under bash 3.2.57 here, which is the portability floor, not an approximation of it.

---

## Phase P1 — Give the lock an identity, and release only what matches it
**Satisfies:** R1 · **Depends on:** —
**Goal:** a release removes the lock only when the `owner` file still names this process; every other
outcome leaves the directory standing.

- [x] Build the owner line before the `while ! mkdir` loop, from expansions only:
      `host=${HOSTNAME} pid=$$ nonce=${RANDOM}${RANDOM}${RANDOM}`. Remove `time=` and both command
      substitutions — they are what widen the `mkdir`-to-owner-write window from 0.10 ms to 3.0 ms.
- [x] Add the `uvm_lock_owner` global beside `uvm_lock`.
- [x] Make the owner write fatal: on failure, `rmdir` the lock and `die` **before** `uvm_lock` is set.
      Setting it first and dying leaves the EXIT trap reading an absent `owner`, declining ownership,
      and leaking the lock anyway. The shell's own redirect diagnostic is left unsuppressed — it
      carries the errno, and `die`'s line does not.
- [x] Rewrite `uvm_unlock`: early-out on empty `uvm_lock`; copy the path to a local and clear both
      globals; read `owner` with `read`, `2>/dev/null` **before** the input redirect, variable
      initialized in the same `local`; compare the whole line; `rm -f owner` and `rmdir` on a match,
      otherwise `note` and leave. Never branch on `read`'s return code.
- [x] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: release on EXIT/INT/TERM is now
      qualified by ownership.
- **Verify:** the R1 drive — a foreign `owner` written from inside the installer leaves both the lock
  directory and that `owner` file intact, and an ordinary drive still leaves no lock behind. Red today
  at `FAIL: release removed a lock this process does not own`.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P2 — Release before every exec of the real uv
**Satisfies:** R4 · **Depends on:** P1
**Goal:** no path reaches an `exec` holding the lock, and the hot path pays one builtin test for it.

- [x] `uvm_unlock` before `exec "${real_uv}" --version` in `uvm_self_update`.
- [x] `uvm_unlock` before the `case "${mode}"` block covering the other three sites.
- [x] Do **not** introduce `uvm_exec_real`. It is more miss-resistant and it makes R4's own census
      pattern match nothing, so the contract's verification would report zero sites.
- [x] **Amended:** add the release-before-`exec` rule to `invariants.md` §5 and `AGENTS.md`
      § *Invariants*. `PLAN.md` enumerated three invariant revisions and this was not among them,
      because R4 overturns nothing. The amendment is argued from the same asymmetry the cycle runs
      on: `uvm_exec_real` was rejected for making the census blind, so the census plus a comment at
      each site is all that stops a fifth `exec` from being added without a release — and under P3's
      heartbeat that omission is no longer a bounded leak but a lock nothing can break. The next
      cycle is the one that acquires the lock late in the dispatch path.
- **Verify:** the census returns 4, and xtrace ordering puts `uvm_unlock` between `uvm_export_env` and
  `exec` on both `uv --version` and `uv self update`. Red today at
  `FAIL: no release between uvm_export_env and exec on 'uv --version'`.
- **Observed:** cold drive traced `export PATH` (153) → `uvm_unlock` (157) → `exec` (161), with the
  guard costing three trace lines and no fork; `uv tool list` still releases from the EXIT trap after
  its `exit 0`.
- **Inspection-only for the reviewer:** "the release must be a builtin test that forks nothing when no
  lock is held" — the GOAL assigns this to a human, and no command decides it. Confirm the ownership
  read sits *after* the empty-`uvm_lock` early-out; before it, every hot-path call pays a failed
  `open(2)`. "Every site covered" is likewise a reading of the four-line census, not a proximity grep.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P3 — Keep a live holder's lock alive for as long as the holder is
**Satisfies:** R2 · **Depends on:** P2
**Goal:** a hold longer than `UVM_LOCK_STALE` is never broken, and nothing outlives the drive.

- [x] Derive `lock_beat=$(( lock_stale / 10 ))`, floored at 1. No new environment variable — the GOAL
      forbids one. **Amended:** derived inside `uvm_acquire_lock`, not beside the knobs as planned.
      Measured on bash 3.2.57: `UVM_LOCK_STALE=abc` makes that arithmetic fatal under `set -u`
      (`abc: unbound variable`), so at load time it would kill `uvm help` and `uvm --version` — the
      two commands that document these knobs, and the reason `PLAN.md` §3 puts R3's guard inside the
      function rather than at load. Load-time derivation would also read `0600` as 38 rather than 60,
      because P4 normalizes `lock_stale` inside the function, after load. Keeping the arithmetic in
      `uvm_acquire_lock` confines it to where `(( age > lock_stale ))` already lives, so P3 adds no
      new failure surface.
- [x] Add `uvm_lock_heartbeat`: sleep `lock_beat`; exit when `kill -0 "$$"` fails; re-read `owner` and
      exit unless it still matches `uvm_lock_owner`; rewrite it with byte-identical content. The
      re-read is what stops a refresher stamping our identity over a new holder's `owner` after a
      break — which R1 would then turn into an immortal lock. Also `trap - EXIT INT TERM` in the
      subshell: research measured async subshells resetting traps anyway, but a refresher whose EXIT
      trap did fire would find its inherited `uvm_lock`/`uvm_lock_owner` matching and delete the live
      lock it exists to protect.
- [x] Spawn it after the owner write as `… >/dev/null 2>&1 &`, recording the pid. The redirection is
      load-bearing: a surviving child holds the caller's pipe open and `VER=$(uv --version)` was
      measured blocking 9 s on one.
- [x] Reap in `uvm_unlock` — `kill` then `wait`, before reading `owner`. Without the `wait`, bash
      prints `Terminated: 15` and the subshell body to stderr, and the refresher can recreate `owner`
      between the `rm -f` and the `rmdir`.
- [x] Change `uvm_age` to `uvm_age "${lock}/owner" || uvm_age "${lock}"`. A directory's mtime tracks
      its entry list, not writes to files inside it, so on the directory the heartbeat is invisible.
- [x] Add the waiter's liveness probe ahead of the age test: same host with a dead pid loses the lock
      at once, same host with a live pid keeps it, anything else falls through to the mtime. A pid
      that is not all digits is treated as unprobeable rather than dead — `kill -0` would fail on it
      and manufacture a break with no evidence behind it.
      **Reopened and amended by review cycle 1 — see the two items below.**
- [x] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: the stale age is now measured from the
      heartbeat, not from acquisition.

Review cycle 1 reopened this phase. Both findings were in the probe this phase added.

- [x] **F1** — stop gating the age test on the probe. The item above shipped
      `elif [[ -z "${pid}" ]] && … (( age > lock_stale ))`, which makes `UVM_LOCK_STALE` unreachable
      whenever a recorded pid answers `kill -0`. `kill -0` answers for a pid *number*, and this
      phase's own reasoning is that pid space wraps in under a minute — so a lock left by a killed
      holder was unbreakable for the lifetime of whatever inherited its number, where `main`
      self-heals in one second. The age test now runs whatever the probe answered; the probe is
      retained as the fast path that skips the stale window for a provably dead holder. What protects
      a live holder is the heartbeat, not the age test failing to run.
- [x] **F2** — source the host token from `uname -n`, hoisted above the `mkdir` loop, and compare
      against it. `${HOSTNAME}` is inherited, and the token decides whether a recorded pid may be
      probed locally, so two nodes presenting one name had a waiter break a live remote holder's lock
      on its first iteration. One fork, on the provisioning path only: the warm path never enters
      `uvm_acquire_lock`, confirmed by trace. This also disposes of the review's F4, since `uname -n`
      cannot carry the newline an exported `HOSTNAME` could.
- [x] **F3** — `invariants.md` §5 asserted "the probe covers `kill -0`'s residual pid-reuse gap",
      which inverted the truth: the probe *is* the gap. Both that bullet and `AGENTS.md`'s parallel
      paragraph now state that age is consulted whatever the probe answered, and a new bullet records
      the `uname -n` requirement.
- **Amendment — the gate was under-specified, and the fix exposed it.** Drive 1 ran the holder at the
  *default* `UVM_LOCK_STALE=600` and the waiter at `3`. The beat is `lock_stale / 10` derived from
  each process's own value (`bin/uv-manager:435`), so the holder refreshed every 60 s against a 3 s
  threshold, and drive 1 passed only because the pid probe suppressed the age test — the very defect
  F1 names. Both processes now carry `UVM_LOCK_STALE=3`, giving a 1 s beat against a 3 s threshold,
  which is what R2's "`UVM_LOCK_STALE` set below the hold duration" describes: one site-wide value,
  below an 8 s hold. R2 is unchanged and still graded by the same assertion. The coupling is now
  user-visible, so `etc/uv-manager.conf.example` says to set the threshold site-wide and why.
- **Gate additions:** drive 3 plants an `owner` backdated to 2020 naming a live unrelated pid and
  asserts the lock is broken and `current -> versions/9.9.9`; drive 4 exports
  `HOSTNAME=spoofed.invalid` and asserts the captured owner line records `uname -n` instead. Both
  measured red before the fix (drive 3 at `FAIL: a lock past UVM_LOCK_STALE went unbroken because its
  recorded pid was reused`) and green after.
- **Verify:** an 8-second hold against `UVM_LOCK_STALE=3` produces no `breaking stale provisioning
  lock` on the waiter's stderr and leaves `owner` naming the original pid; and a plain drive leaves no
  background job behind. The gate keeps `set +e` around the waiter and does **not** assert `rc=0` —
  after the fix the waiter dies of an ordinary timeout. Red today at
  `FAIL: a live holder's lock was broken as stale`.
- **Note on the second drive:** the orphan clause — SIGKILL the holder, assert `owner`'s mtime freezes
  — is **green today by construction**, because nothing refreshes anything yet. It is a regression
  guard against the failure this phase can introduce, not a post-condition it delivers, and the gate's
  red comes from the first drive. `jobs -p` was tried here and is blind: the refresher is a grandchild
  of the drive shell, so it reports nothing whether or not one leaked.
- **Observed beyond the gate:** with `UVM_LOCK_STALE=20` against a 9 s hold, `owner`'s mtime advanced
  1786823336 → 1786823342 while the lock directory stayed pinned at 1786823336 — the measurement that
  makes the `uvm_age` change necessary rather than defensive. `VER=$(uv --version)` on a cold tree
  returned in 0 s with no `uv-manager` process left running, and stderr carried no `Terminated`. An
  owner-less lock still ages out through the directory fallback; a live pid past `UVM_LOCK_STALE` is
  never broken; a dead pid on this host is broken at once inside a 600 s window.
- **Re-run after the amendment:** the P1, P2, P4, P5, P6 and P7 gates all re-run green, since the fix
  changed the function four of them assert against.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`,
  `etc/uv-manager.conf.example`.

Review cycle 2 reopened this phase a second time. The finding is in the heartbeat this phase added,
and it is the same error cycle 1 removed from the waiter, one function away.

- [x] **F6** — leash the refresher to a pid *and* a start time. `kill -0 "$$"` answers for a number
      the kernel reuses, so a holder killed without running its traps leaves a refresher that
      resumes rewriting `owner` the moment that number is reoccupied. Nothing recovers the lock
      afterwards: the age net cannot fire because the mtime keeps moving, and the waiter's probe
      cannot fire because it finds the reoccupying process alive. `uvm_proc_start` reads
      `ps -o lstart=`, `uvm_acquire_lock` records the holder's own start time beside the host token
      above the `mkdir` loop, and the refresher forfeits on a mismatch. Both readings must be
      non-empty to forfeit, so a `ps` that cannot answer degrades to today's bare probe rather than
      costing a live holder its lock — the same direction §5 already argues for, where a false leave
      is reclaimed by the stale breaker and a false delete is bounded by nothing.
- [x] A refresher lifetime ceiling was **not** the fix. `GOAL.md` rejects it outright, and the
      rejection holds here: a hold that outlives the ceiling silently loses the protection R2 exists
      to give. The defect is that the leash asks the wrong question, not that it asks it forever.
- [x] The waiter's own probe is left alone. It has the same blind spot, but cycle 1 made the age test
      run whatever the probe answers, so a recycled pid there costs only the fast path — provided the
      age actually grows, which is exactly what this fix restores.
- [x] Update `invariants.md` §5 and `AGENTS.md` § *Invariants*: both asserted the refresher stops when
      `kill -0 "$$"` fails, a property the code did not have. §5 gains a bullet for the leash;
      `AGENTS.md` gains the sentence. `etc/uv-manager.conf.example:75` promises `UVM_LOCK_STALE`
      covers a holder killed by SIGKILL or job cancellation, which is true again and needs no edit.
- **Gate addition, and why it costs 100 s.** A fifth drive holds the lock at the shipped
  `UVM_LOCK_STALE=600`, SIGKILLs the holder, walks the pid space back around to its number and parks
  a long-lived process there, then samples `owner`'s mtime across a beat. The walk is inherent: a
  freed pid is not reused promptly, it returns only after a full wrap of roughly 99,999 allocations,
  measured at 28 s in batches of 200. The beat has to outlast the walk or the refresher stands down
  for want of a pid rather than for want of its holder, which would pass against the unfixed code —
  so the drive asserts `burn < 50` against a 60 s beat and fails the construction rather than
  reporting a green it did not earn.
- **Observed red, then green.** Red against the committed code at
  `the refresher outlived its holder and kept the lock fresh` — `owner` advanced 1786849795 →
  1786849855, exactly one 60 s beat, with the holder dead throughout. Green after at frozen mtime.
  Both runs walked 28 s to the same construction, so the two differ only in the leash.
- **Re-run after the fix:** P1, P2, P4, P5, P6 and P7 all green.
- **Touches (cycle 2):** `bin/uv-manager`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P4 — Refuse a knob configuration that lets a waiter break a live lock
**Satisfies:** R3 · **Depends on:** P3
**Goal:** `UVM_LOCK_TIMEOUT >= UVM_LOCK_STALE` is refused before any lock is touched, and `help` still
answers.

- [x] Guard at the top of `uvm_acquire_lock`: numeric form first, then ordering, then `die` naming both
      variables and their values. Placement is inside the consuming function so `uvm help` and
      `uvm --version` still answer with a broken configuration.
- [x] The numeric test is not optional and is a recorded deviation: with `UVM_LOCK_STALE=abc`, `set -u`
      kills the arithmetic at `:225` but bash 3.2 **exits 0**, so `VER=$(uv --version)` returns empty
      and true. It also catches `' '`, `0` and `-1`, each of which makes every lock instantly stale.
- [x] Force base 10 after the form test and before the comparison, assigning back to the **existing
      globals**: `lock_timeout=$(( 10#${lock_timeout} ))`, same for `lock_stale`. Not `local` — `:225`,
      `:233` and the timeout message must read the same seconds. `0600` is 384 to bash and `0800` is
      not a number at all, so a guard on the raw strings judges seconds the operator never wrote and
      prints a refusal its own two numbers satisfy.
- [x] Keep the form test **ahead** of the normalization: `$(( 10#${x} ))` on an empty or all-space
      value is silently `0` on bash 3.2 and an error on 5.2, and a `0` stale makes every lock
      instantly stale.
- [x] No extra user-facing surface for the normalization — a padded value now means what it looks
      like. `etc/uv-manager.conf.example` gains "whole seconds, decimal"; `uvm_help` and `README.md`
      still only gain the ordering constraint.
- [x] Same-commit surface: the `uvm_help` knob lines (`:878` is already 78 columns against an 81-column
      heredoc, so this needs a continuation line), `etc/uv-manager.conf.example:71-76`, and
      `README.md`'s knob table at `:551-552`. Document the NFS floor — `UVM_LOCK_STALE` below roughly
      120 s is unsafe for cross-node waiters. `share/modulefiles/uv/main.lua` needs no change.
- [x] Add the ordering constraint to `invariants.md` §5 and `AGENTS.md` § *Invariants*.
- **Verify:** inverted knobs exit non-zero, name both variables, and leave a pre-existing live lock
  present; a non-numeric value is refused; `uvm --version` and `uvm help` still answer; and all three
  user-facing files state the constraint; plus `TIMEOUT=0600 STALE=500` refused with the refusal
  printing `600`, `TIMEOUT=500 STALE=0600` accepted, and `STALE=0800` reaching no arithmetic. Red
  today at `FAIL: inverted knobs accepted (rc=0)`. The `500/0600` drive is green today and red against
  a guard that omits the normalization — it is the row that discriminates the correct guard from the
  one the first draft of this plan specified.
- **Red state moved, and the reason matters.** The gate went red at `FAIL: refusal does not name both
  variables`, not at the predicted `FAIL: inverted knobs accepted (rc=0)`. P3 landed first, and its
  liveness probe already keeps a lock whose recorded pid is alive on this host, so the inverted-knob
  drive now times out non-zero instead of breaking the lock. The remaining harm R3 names — a waiter
  breaking a *cross-node* live holder, which no probe can rescue — is unreachable from one machine,
  so the assertion that still discriminates is the refusal itself.
- **Observed beyond the gate:** `' '`, `0`, `-1`, `abc`, `12x`, `18:0` and `0x10` each refused with a
  pre-placed foreign lock and its `owner` file surviving intact; `0600/500` refused printing
  `UVM_LOCK_TIMEOUT=600` — the seconds judged, not the string written; `500/0600` and the defaults
  both accepted through to `current -> versions/9.9.9`; `uvm help` answering 0 under inverted knobs
  and carrying the new constraint line.
- **P3's gate was retuned in this phase, and P3 stays `done`.** Its second drive held the lock with
  `UVM_LOCK_STALE=10` against the default `UVM_LOCK_TIMEOUT=180` — a pair this phase now refuses, so
  the holder never acquired and the gate failed at `FAIL: no holder pid recorded`. The drive was
  written before the ordering constraint existed; the knobs became illegal, not the assertion. Fixed
  to `UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=10` through `set_phase.py --verify`, re-run green. P1 and P2
  were re-run and needed nothing — both use the defaults.
- **Touches:** `bin/uv-manager`, `etc/uv-manager.conf.example`, `README.md`,
  `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P5 — Tell a stalled user how to tell an abandoned lock from a live one
**Satisfies:** R5, R6 · **Depends on:** P4
**Goal:** the timeout message names the holder and gives a recovery command that works.

- [x] Rewrite the timeout message: the owner line inline, the caveat that a recorded pid is on that
      host and not this one, and `rm -f '<lock>/owner' && rmdir '<lock>'`. With no `owner`, print
      `<none recorded>` and keep line 3 phrased conditionally so it still parses. The line the loop
      already reads for the liveness probe is the one printed; nothing re-reads the file.
- [x] Fix the recovery command, which has **never** worked — `rmdir '<lock>'` fails with
      `Directory not empty` for every successful acquisition, because `owner` lives inside the
      directory. `invariants.md` §5's "the exact `rmdir` command to recover" is currently unsatisfied
      by the code; this is what makes it true.
- [x] Keep the message on `die` rather than a `cat` heredoc. Recorded deviation, argued from
      measurement: one `printf` behind a departed reader emits one diagnostic line, the same count BSD
      `cat` produces, and only when the caller ignores SIGPIPE.
- [x] Give the stale-break note the same owner line. After R1, "whose lock was that" is the first
      question following a break. **Amended:** the dead-process break note carries it too. Both
      branches delete a specific holder's record, the note is the only trace left of which one, and
      splitting the rule across two adjacent branches is how the next reader concludes one of them
      meant something. One comment above the first branch covers both.
- [x] Add `README.md` § *Troubleshooting*'s first lock entry, naming
      `$UVM_ROOT/<arch>/.install.lock`, its `owner` file and the two-step removal. The `owner` file is
      currently documented nowhere a user will look, and a message that points at it owes one.
- [x] Update `invariants.md` §5 and `AGENTS.md` § *Invariants* for the recovery-command wording.
      `AGENTS.md` asserted nothing about this message before, so there it is a new paragraph rather
      than a revision.
- **Verify:** a drive to timeout whose stderr matches `owner`, `host` and `pid` as whole words and
  carries the two-step recovery; a stale break naming the owner it deleted; `README.md` mentioning
  `install.lock`; plus the full R6 regression — `uv 9.9.9 (fixture)`, `current -> versions/9.9.9`, and
  no `flock` outside a comment. Red today at `FAIL: timeout message never mentions 'owner'`, which is
  where it was observed red.
- **The gate was retuned, and the failure it hid is the point.** The stale-break drive carried
  `UVM_LOCK_STALE=1 UVM_LOCK_TIMEOUT=10` — a pair P4 now refuses — so under the drive's own `set -e`
  the refusal aborted it before any assertion ran and `run_verify.py` exited 1 printing **nothing**.
  Retuned through `set_phase.py --verify` to `UVM_LOCK_STALE=2 UVM_LOCK_TIMEOUT=1` against a 3 s-old
  lock, and the drive now prints the wrapper's stderr when that call exits non-zero, so the next knob
  pair a later phase outlaws names itself instead of failing blank. Same mechanism as P4's retune of
  P3's gate, one phase further on: there the constraint invalidated a `done` gate, here a pending one.
- **P6's gate has the same defect, left for P6.** Both its drives carry inverted pairs
  (`UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=1`, and the same `STALE=1 TIMEOUT=10` stale-break drive).
  Retuning a gate for a phase this invocation is not building would produce a gate never observed
  failing against the code it grades.
- **Observed beyond the gate:** the message renders both branches — `host=node0042 pid=12345
  nonce=8143120227` inline, and `<none recorded>` with line 3 still parsing. `rmdir` on a claimed lock
  returns 1 with `Directory not empty`; the advised two-step returns 0, leaves no directory, and the
  next call provisions through to `current -> versions/9.9.9` with `uv 9.9.9 (fixture)` alone on
  stdout. The dead-process break names the owner it deleted. P1 through P4 were re-run after the
  message and documentation edits and are green.
- **Touches:** `bin/uv-manager`, `README.md`, `.agents/factory/invariants.md`, `AGENTS.md`.

## Phase P6 — Make `UVM_LOCK_TIMEOUT` bound a waiter it cannot break free of
**Satisfies:** R7, R6 · **Depends on:** P5
**Goal:** a stale lock that cannot be removed produces a timeout, not an unbounded spin.

- [x] Retry the `mkdir` immediately only when the directory is actually gone. After the break attempt,
      `[[ -d "${lock}" ]] || continue`; otherwise fall through to the accounting and the sleep.
- [x] A bare `die` on `rmdir` failure is **wrong**: two waiters can declare the same lock stale, and
      the loser's `rmdir` gets `ENOENT` having done nothing wrong. The discriminator is whether the
      directory survived, not whether our own `rmdir` returned zero.
- [x] Add `broke` to the existing `local waited=0 age` line and use it to suppress re-announcing a
      denied break. At the default timeout that would otherwise be 180 identical lines.
- [x] No user-facing surface change and no `invariants.md` edit: §5 already asserts the wrapper times
      out after `UVM_LOCK_TIMEOUT`. This phase is what makes that assertion true.
- [x] **Amended — the loop has two break sites, not one, and both spin.** `PLAN.md` §*The timeout has
      to actually bound* was written against `:229`, the only break that existed before P3 added the
      liveness probe. A lock whose `owner` names a dead local pid, inside a directory whose entries
      cannot be removed, re-announces and re-`continue`s exactly as the stale path does: measured
      2386 stderr lines and 1193 break announcements in 6 s, still running when the harness killed
      it. Fixing one site and not the other leaves R7 half-true in the branch the wrapper reaches
      first.
- [x] **Amended — the two break bodies are folded into one.** With R7's tail they would have been
      eight identical lines twice, differing only in the note, and the next reader of a lock-breaking
      change has to notice there are two of them. A `reason` local decides *which* forfeiture applies
      — the branches were already mutually exclusive through the stale test's `[[ -z "${pid}" ]]`
      guard, so the `elif` changes no behavior — and one block announces, removes, and charges the
      timeout. It is a deletion, and it gives R7 and P7's counter one site each rather than two.
- **Verify:** against a lock directory holding an entry the wrapper did not write, aged past
  `UVM_LOCK_STALE`, the call exits within the timeout carrying the timeout message and announces the
  break at most once; the same against a dead holder's lock the waiter cannot remove; an ordinary
  stale break still works and still provisions; plus the full R6 regression, so the last phase ends on
  the cold-provisioning check.
- **Gate retuned, then observed red and green.** Both original drives carried knob pairs P4 refuses,
  which abort a drive at the `uv` call and report nothing — the failure P5 hit and recorded. Retuned
  to `STALE=3 TIMEOUT=2` against a 4 s-old lock, and to P5's `STALE=2 TIMEOUT=1` for the ordinary
  break. A third drive was added for the second break site, because a gate that exercises only the
  stale path grades a fix to only the stale path as complete. Red against `HEAD` at
  `FAIL: still spinning 6s after a 2s timeout (794 lines)`, and the new drive red on its own at
  1193 announcements in 6 s; green after.
- **Observed beyond the gate:** the dead-holder denied break now emits 6 stderr lines — one break
  note, then the four-line timeout message — and exits 1 in 2 s against `UVM_LOCK_TIMEOUT=2`. P1
  through P5 re-run green against the folded loop.
- **Touches:** `bin/uv-manager`.

## Phase P7 — Stop misreading a released lock as a broken filesystem
**Satisfies:** R8 · **Depends on:** P6
**Goal:** a failed `mkdir` whose lock is absent is a transient to retry, and only persistence across a
bounded number of attempts reports a filesystem fault.

- [x] Add `absent=0` to the `local waited=0 age holder pid` line — the same line P6 adds `broke` to,
      so build P6 first and this is a sequential edit rather than a conflict.
- [x] Replace the `[[ ! -d "${lock}" ]]` die with: increment `absent`; `continue` while
      `absent < 3`; `die` with **today's message, unchanged** at the bound. The message is right when
      it is finally reached; only the evidence for reaching it changes.
- [x] The bound is a literal, in the style of `lock_beat`. `GOAL.md`'s non-goals forbid a new
      environment variable, and this needs no site tuning: three consecutive absences is not a
      threshold anyone tunes, it is the difference between a race and a broken mount.
- [x] `absent` is **monotonic** — never reset on the lock-present branch. With P6's
      `[[ -d "${lock}" ]] || continue` in place, an alternation of absent-retry and successful-break
      would otherwise never reach the accounting. "No agent can produce that alternation" is the
      weaker guarantee R7 exists because someone accepted once. Monotonic bounds total iterations at
      `lock_timeout + 3`, each extra one a single `mkdir` syscall.
- [x] Do **not** write the retry as a bare `continue`. It would spin forever on EACCES, EDQUOT or
      ENOSPC — the ordinary operational faults — turning a clean sub-second non-zero exit into a hot
      loop, which is strictly worse than the R7 defect nine lines below it.
- [x] Do **not** delete the `die` and do not parse errno. Deleting it stalls every rank for the full
      `UVM_LOCK_TIMEOUT` on a genuinely unwritable mount and then reports the wrong fault; errno means
      parsing a locale-dependent string.
- [x] Overturn `invariants.md` §5's contention bullet in this commit — it states the false premise as
      doctrine, and it is the only place the premise is written down. `AGENTS.md` never states it and
      `README.md` never mentions it, so this is one bullet in one file. The imperative survives; the
      evidence changes from one observation to persistence.
- **Verify:** twenty cold bursts of 64 ranks leave no rank carrying `check permissions and quota` and
  no rank exiting non-zero; and an unwritable architecture directory still names that fault,
  non-zero, in under five seconds. Red today at
  `FAIL: 33/1280 ranks reported a permissions/quota fault on a healthy filesystem` — measured, 2.6%,
  with `nonzero` also 33, so every failure in the burst is this defect and nothing else. Gate cost
  measured at 24.5 s.
- **Do not shorten the gate.** Twenty bursts is arithmetic: at a pessimistic 0.5% per-rank floor one
  burst is red with probability `1 - 0.995^64 = 0.27`, so twenty leave a false green at
  `0.73^20 ≈ 1.6e-3`. The second drive is green today and green after — it exists so nobody satisfies
  the first by deleting the `die`.
- **Observed red, then green.** Red at `FAIL: 44/1280 ranks reported a permissions/quota fault on a
  healthy filesystem` — 3.4%, above the 2.6% the brief measured and within its 2–4% band, with
  `nonzero` also 44, so the burst lost ranks to this defect and to nothing else. Green after at
  `misdiagnosed=0/1280 nonzero=0/1280`. The second drive held throughout: an unwritable architecture
  directory still exits 1 in 0 s carrying `check permissions and quota`, so the three retries cost a
  genuine fault nothing measurable.
- **`AGENTS.md` needed no edit after all.** The checklist named it as a *Touches* file on the strength
  of the same-commit rule, but it never stated the premise — `grep quota AGENTS.md` finds only the
  project summary's home-directory quota. The overturn is one bullet in `invariants.md`, as the brief
  said.
- **The retry reads `(( absent >= 3 )) || continue`, not `(( absent < 3 )) && continue`.** The `||`
  form leaves the statement's status zero on both paths. The `&&` form's status is the failed
  arithmetic's when the bound is reached, and this loop runs under `set -e` in a function whose EXIT
  trap would overwrite the exit status — the same shape that made a bare ordering test exit 0 in P4.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`.

## Phase P8 — Narrow the break to the instance it judged; repair the seed's citations
**Satisfies:** — · **Depends on:** P3
**Goal:** a waiter that judges a lock forfeit cannot delete the directory a rival breaker has already
replaced.

Added by review cycle 2. It maps to no R-ID: the break is *meant* to remove a lock it does not own,
so this is not an R1 gap but a time-of-check-to-time-of-use window between the forfeiture decision at
`:381` and the `rmdir` at `:390`. Two waiters declaring the same lock forfeit in one tick have the
loser remove the winner's fresh, still-empty directory, and the winner then dies `ENOENT` proving
ownership at `:424`. Measured at 4 ranks of 1280 plus three bursts with two concurrent installers.
The window is the same `mkdir`-to-`owner` interval §5 already names as the only one in which a stale
release can destroy a live lock — reached here through the break path rather than the release path.

- [x] **The design was settled against the maintainer's first choice, on evidence.** An exclusive
      rename was costed, approved, and then rejected: `mv` is not `rename(2)`, `mv -T` is absent at
      the portability floor so `mv` nests instead of failing, and `rmdir` refusing a non-empty
      directory turned out to be what protects an established lock and what makes R7 true for the
      stray-entry construction. Full reasoning in *Attempt 1* below.
- [x] The break re-reads `owner` immediately before acting and removes the file **and** the directory
      only while it still holds the line the forfeiture was decided on. Gating the owner removal is
      what leaves `rmdir` a non-empty directory to refuse, so the two calls sit inside one test
      rather than one of them.
- [x] **F8** — repair `issues/invariant-audit-gaps.md`'s citations. Anchored to function names as
      well as lines (`uvm_install` `:595`, `uvm_trampolines` `:725-729`, `uvm_global_takes_value`'s
      banner `:767-772`), so the next shift degrades the reference rather than silently misdirecting
      it. The fourth citation, inside R1, is now a name with no number at all.
- [x] **The closure is deferred, and the deferral is recorded, not implied.**
      [`issues/lock-break-instance-identity.md`](../../issues/lock-break-instance-identity.md) plus
      its `ROADMAP.md` entry carry the residual, the rejected rename and why, the measurement debt
      that blocks any candidate fix, the lock's unmeasured performance claims, and its
      taken-on-trust safety properties. Decided by the maintainer on 2026-08-16.
- **Verify (re-scoped to what shipped).** The original gate graded a closure this phase no longer
  claims, and it stayed red on both the control and the candidate. What is assertable is: a census
  that both removals sit inside the identity guard and that the file holds exactly three removals of
  the lock directory, the other two being `uvm_unlock`'s ownership-guarded one and the cleanup of a
  directory we created and could not claim; that the guard does not decline a break that is owed,
  driven both for an aged lock and for a dead holder on this node; the full R6 regression; and every
  seed citation landing on what it names. A statistical gate for the closure belongs to the seed,
  which owes the harness first.
- **Why a census and not a drive.** The guard fires in a window no sandbox can open on demand — a
  breaker's decision and its act are separated by microseconds — so a drive that exercised it would
  be a drive that got lucky. The census is the R4 pattern: pin the count, and a fourth unguarded
  removal added later trips the gate.
- **Touches:** `bin/uv-manager`, `issues/invariant-audit-gaps.md`, `issues/lock-break-instance-identity.md`,
  `ROADMAP.md`, `spec/lock-ownership-and-hold-time/REVIEW.md`.

### Attempt 1 — the rename is out, and the replacement is not yet proven

**Design A is rejected on evidence, not taste.** Four independent design critiques converged on
`rename-is-unsound`, and the two decisive reasons hold up against the file:

- **`mv` is not `rename(2)`.** The exclusivity argument is an argument about the syscall. A shell can
  only call `mv`, and `mv -T` does not exist at the portability floor — `uvm_point_current` already
  carries a documented non-atomic fallback for exactly that reason, and it does not generalize here.
  Without `-T`, `mv` onto an existing name moves the source *inside* it and exits 0, so two breakers
  can both believe they won and the second nests a live tree inside a lock.
- **`rmdir` refusing a non-empty directory was load-bearing and unremarked.** It is what stops a
  stale breaker destroying an *established* lock today, and it is what makes R7 true for the
  stray-entry construction. A rename removes the directory whatever it contains, so Design A widens
  the destructive window from the 0.10 ms acquire gap to the whole hold, and defeats **both** of P6's
  denied-break constructions — the stray entry and `chmod 500`, since a same-parent rename needs no
  write permission on the directory itself.

Litter compounds it: a breaker that dies between the rename and the delete leaves a permanent
sibling that nothing reaps and no trap covers, because a breaker holds no lock and `uvm_unlock`
early-returns.

**Design C is built and is not yet sufficient.** The break now re-reads `owner` immediately before
acting and removes the file *and* the directory only while it still names the holder the forfeiture
was decided on. It parses, lints, and is a strict narrowing — a declined break falls through to the
timeout accounting and the next iteration re-decides — but the gate is **red** and the measurements
do not support calling it done:

| | robbed (`cannot record ownership`) | simultaneous installers | installer entries |
|---|---|---|---|
| committed code, 320 ranks | 5 | 2 | 12 |
| Design C, 320 ranks | 2 | 4 | 14 |

The gate failed at burst 9 on the two-installers assertion. Two things are wrong and both are the
measurement's fault before they are the design's: 320 ranks give counts too small to separate from
noise, and the simultaneity sentinel emitted `violations: No such file or directory` on several
bursts, so the concurrency column is contaminated and cannot be read as a regression.

**The open question is which defect the two-installer signal names.** `uvm_install` re-checks
`uvm_have` under the lock (`:550`), so a second *sequential* acquisition should not reach the
installer — but the early-out at `:547` returns before `uvm_point_current`, which a prior review
recorded as a real, pre-existing, self-correcting defect on `main`. Until the sentinel is fixed and
the burst is large enough, this gate cannot say whether it is catching F7 or that. A gate that
cannot name the mechanism it failed on is the trap `META.md` F18 already records.

**What the next attempt owes:** repair the sentinel so it cannot write into a removed sandbox, size
the burst by the arithmetic P7's notes use rather than by guess, and separate the robbed-winner
signal from the two-installer signal so each has its own assertion. Only then is the residual — the
case where the judged lock carried *no* owner line, which makes the identity test vacuous — worth
designing against.

**Resolution.** None of that was done in this cycle. The maintainer deferred the closure rather than
take a third review round, in the highest-blast-radius function in the repository, on evidence that
could not separate a fix from noise. What shipped is the narrowing above, on the argument that it
cannot make anything worse: a declined break falls through to the timeout accounting and the next
iteration re-decides, and the only line that ever matches the re-read is one a live heartbeat rewrote
byte-identically. All eight phase gates were re-run green afterwards, including P7's 1280-rank burst
at `misdiagnosed=0/1280 nonzero=0/1280`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note the
   amendment in the commit body. STOP and escalate only on a `GOAL.md` contradiction.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
