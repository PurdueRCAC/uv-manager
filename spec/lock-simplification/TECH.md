---
slug: lock-simplification
title: Stop breaking the lock, and split provisioning from repair
kind: fix
appetite: big
status: in_review
branch: fix/lock-simplification
base: main
current_phase: done
last_updated: '2026-10-28'
phases:
- id: P1
  name: 'The lock never breaks: caller-named predicate, one notice, proceed or fail'
  status: done
  satisfies:
  - R1
  - R2
  - R3
  - R5
  - R6
  - R7
  - R9
  - R11
  - R14
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\nbash -n bin/uv-manager || { echo \"FAIL: bash -n\" >&2; exit 1;\
    \ }\n.agents/factory/bin/lint.sh >/dev/null || { echo \"FAIL: lint.sh\" >&2; exit\
    \ 1; }\nif git grep -n -E 'uvm_lock_heartbeat|uvm_proc_start|uvm_age|lock_stale|UVM_LOCK_STALE|kill\
    \ -0' -- bin/uv-manager; then\n  echo \"FAIL R7: liveness, age or stale-knob code\
    \ remains in bin/uv-manager\" >&2; exit 1; fi\nif git grep -n -i -E 'UVM_LOCK_STALE|heartbeat|refresher|stale.?breaker|broken\
    \ as stale|break(s|ing)? (itself|the lock|a lock|stale|its)|breaks itself' --\
    \ AGENTS.md .agents/factory/invariants.md README.md etc/uv-manager.conf.example;\
    \ then\n  echo \"FAIL R9: a passage still describes a break, a stale threshold\
    \ or a heartbeat\" >&2; exit 1; fi\nif git grep -n -i -E 'stale|kill -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher'\
    \ -- .agents/factory/invariants.md etc/uv-manager.conf.example; then\n  echo \"\
    FAIL R9: invariants.md or the config example still carries the retired mechanism\"\
    \ >&2; exit 1; fi\nif .agents/factory/bin/temp_root.sh uvm help | grep -n UVM_LOCK_STALE;\
    \ then\n  echo \"FAIL R9: uvm help still documents UVM_LOCK_STALE\" >&2; exit\
    \ 1; fi\nn=$(git grep -n flock -- bin/uv-manager | wc -l | tr -d ' ')\n[ \"$n\"\
    \ -eq 1 ] || { echo \"FAIL R14: flock appears on $n lines of bin/uv-manager, expected\
    \ the one rationale comment\" >&2; exit 1; }\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'R1R3' || exit 1\nset -u\nroot=\"$UVM_ROOT/$(uname -m)\";\
    \ lock=\"$root/.install.lock\"\nplant() {  # KIND: dead (reaped pid on this host,\
    \ aged to 2020) | bare (no owner) | live (never releases)\n  mkdir -p \"$root\"\
    ; mkdir \"$lock\"\n  case \"$1\" in\n    dead) sh -c 'exit 0' & d=$!; wait \"\
    $d\" 2>/dev/null\n          printf 'host=%s pid=%s nonce=plant\\n' \"$(uname -n)\"\
    \ \"$d\" > \"$lock/owner\"\n          touch -t 202001010000.00 \"$lock/owner\"\
    \ \"$lock\" ;;\n    bare) touch -t 202001010000.00 \"$lock\" ;;\n    live) sleep\
    \ 30 & printf 'host=%s pid=%s nonce=plant\\n' \"$(uname -n)\" \"$!\" > \"$lock/owner\"\
    \ ;;\n  esac\n  ls -A \"$lock\" > \"$UVM_SANDBOX/plant.ls\"; cat \"$lock/owner\"\
    \ > \"$UVM_SANDBOX/plant.owner\" 2>/dev/null || : > \"$UVM_SANDBOX/plant.owner\"\
    \n}\nfor kind in dead bare live; do\n  UVM_ROOT=\"$UVM_SANDBOX/root.$kind\"; export\
    \ UVM_ROOT\n  root=\"$UVM_ROOT/$(uname -m)\"; lock=\"$root/.install.lock\"; plant\
    \ \"$kind\"\n  out=\"$UVM_SANDBOX/out.$kind\"; err=\"$UVM_SANDBOX/err.$kind\"\n\
    \  if ! UVM_LOCK_TIMEOUT=3 uv --version > \"$out\" 2> \"$err\"; then\n    echo\
    \ \"FAIL R3 ($kind plant): waiter at the timeout exited non-zero instead of installing\"\
    \ >&2; cat \"$err\" >&2; exit 1; fi\n  [ \"$(cat \"$out\")\" = \"uv 9.9.9 (fixture)\"\
    \ ] || { echo \"FAIL R3 ($kind plant): stdout [$(cat \"$out\")]\" >&2; exit 1;\
    \ }\n  [ \"$(readlink \"$root/current\")\" = versions/9.9.9 ] || { echo \"FAIL\
    \ R3 ($kind plant): current -> $(readlink \"$root/current\")\" >&2; exit 1; }\n\
    \  [ -d \"$lock\" ] || { echo \"FAIL R1 ($kind plant): the planted lock was removed\"\
    \ >&2; cat \"$err\" >&2; exit 1; }\n  [ \"$(ls -A \"$lock\")\" = \"$(cat \"$UVM_SANDBOX/plant.ls\"\
    )\" ] || { echo \"FAIL R1 ($kind plant): lock entries changed to [$(ls -A \"$lock\"\
    )]\" >&2; exit 1; }\n  if [ -s \"$UVM_SANDBOX/plant.owner\" ] && ! cmp -s \"$lock/owner\"\
    \ \"$UVM_SANDBOX/plant.owner\"; then\n    echo \"FAIL R1 ($kind plant): owner\
    \ line rewritten to [$(cat \"$lock/owner\")]\" >&2; exit 1; fi\n  if grep -i 'break'\
    \ \"$err\"; then echo \"FAIL R1 ($kind plant): a stderr line announces a break\"\
    \ >&2; exit 1; fi\ndone\necho \"R1/R3 ok\"\nR1R3\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'R2' || exit 1\nset -u\nroot=\"$UVM_ROOT/$(uname -m)\"; lock=\"\
    $root/.install.lock\"; mkdir -p \"$lock\"\nsleep 60 & live=$!\nprintf 'host=%s\
    \ pid=%s nonce=plant-r2\\n' \"$(uname -n)\" \"$live\" > \"$lock/owner\"\n( sleep\
    \ 33; mv \"$lock\" \"$UVM_SANDBOX/released\" ) &\nif ! UVM_LOCK_TIMEOUT=60 uv\
    \ --version > \"$UVM_SANDBOX/out\" 2> \"$UVM_SANDBOX/err\"; then\n  kill \"$live\"\
    \ 2>/dev/null; wait \"$live\" 2>/dev/null; echo \"FAIL R2: waiter exited non-zero\"\
    \ >&2; cat \"$UVM_SANDBOX/err\" >&2; exit 1; fi\nkill \"$live\" 2>/dev/null; wait\
    \ \"$live\" 2>/dev/null\n[ \"$(cat \"$UVM_SANDBOX/out\")\" = \"uv 9.9.9 (fixture)\"\
    \ ] || { echo \"FAIL R2: stdout [$(cat \"$UVM_SANDBOX/out\")]\" >&2; exit 1; }\n\
    n=$(grep -c 'nonce=plant-r2' \"$UVM_SANDBOX/err\")\n[ \"$n\" -eq 1 ] || { echo\
    \ \"FAIL R2: $n stderr lines name the holder, expected exactly 1\" >&2; cat \"\
    $UVM_SANDBOX/err\" >&2; exit 1; }\necho \"R2 ok\"\nR2\nB=\"$PWD/bin/uv-manager\"\
    \ .agents/factory/bin/temp_root.sh sh -s <<'R5R6' || exit 1\nset -u\nh=\"$UVM_SANDBOX/harness.bash\"\
    \ncat > \"$h\" <<'HARNESS'\n#!/bin/bash\n# A non-provisioning caller of the lock,\
    \ with no repair code: the lock section is\n# extracted from the script by its\
    \ banners and sourced (process substitution is a\n# silent no-op on bash 3.2,\
    \ so it goes through a file).\nset -euo pipefail\nbin=\"$1\" mode=\"$2\" work=\"\
    $3\"\nsed -n '/^# ---- provisioning lock/,/^# ---- fetching/p' \"$bin\" > \"$work/section.sh\"\
    \ngrep -q '^uvm_acquire_lock()' \"$work/section.sh\" || { echo \"harness: lock\
    \ section not found by its banners\" >&2; exit 2; }\nnote() { printf 'uv-manager:\
    \ %s\\n' \"$*\" >&2; }\ndie()  { printf 'uv-manager: %s\\n' \"$*\" >&2; exit 1;\
    \ }\nuvm_base=\"$work/base\"; uvm_root=\"$uvm_base/arch\"; mkdir -p \"$uvm_root\"\
    \nlock_timeout=3\nuvm_have() { return 0; }               # the provisioning question\
    \ answers \"satisfied\"\nrepaired() { [[ -e \"$work/flag\" ]]; }  # the caller's\
    \ own predicate\n. \"$work/section.sh\"\nlock=\"$uvm_root/.install.lock\"; mkdir\
    \ \"$lock\"\nsleep 10 &\nprintf 'host=%s pid=%s nonce=plant-r5\\n' \"$(uname -n)\"\
    \ \"$!\" > \"$lock/owner\"\ncp \"$lock/owner\" \"$work/planted\"\nif [[ \"$mode\"\
    \ == flip ]]; then ( sleep 2; : > \"$work/flag\" ) & fi\nrc=0; uvm_acquire_lock\
    \ fail repaired || rc=$?\necho \"$rc\" > \"$work/acquire.rc\"\nif (( rc == 0 ));\
    \ then : > \"$work/critical\"; uvm_unlock; fi\nHARNESS\nw=\"$UVM_SANDBOX/never\"\
    ; mkdir -p \"$w\"; t0=$(date +%s)\nif /bin/bash \"$h\" \"$B\" never \"$w\" 2>\
    \ \"$w/err\"; then echo \"FAIL R5: a waiter whose predicate stayed false returned\
    \ at the timeout\" >&2; cat \"$w/err\" >&2; exit 1; fi\nt=$(( $(date +%s) - t0\
    \ ))\n[ \"$t\" -le 6 ] || { echo \"FAIL R5: took ${t}s against a 3s timeout\"\
    \ >&2; exit 1; }\n[ ! -e \"$w/critical\" ] || { echo \"FAIL R5: the critical section\
    \ ran\" >&2; exit 1; }\ngrep -F -q \"$(cat \"$w/planted\")\" \"$w/err\" || { echo\
    \ \"FAIL R5: stderr does not name the holder\" >&2; cat \"$w/err\" >&2; exit 1;\
    \ }\ncmp -s \"$w/base/arch/.install.lock/owner\" \"$w/planted\" || { echo \"FAIL\
    \ R1: the repair-mode waiter disturbed the plant\" >&2; exit 1; }\nw=\"$UVM_SANDBOX/flip\"\
    ; mkdir -p \"$w\"\nif ! /bin/bash \"$h\" \"$B\" flip \"$w\" 2> \"$w/err\"; then\
    \ echo \"FAIL R6: harness died when the predicate came true\" >&2; cat \"$w/err\"\
    \ >&2; exit 1; fi\n[ \"$(cat \"$w/acquire.rc\" 2>/dev/null)\" = 1 ] || { echo\
    \ \"FAIL R6: acquire returned [$(cat \"$w/acquire.rc\" 2>/dev/null)], expected\
    \ 1 (predicate satisfied)\" >&2; exit 1; }\n[ ! -e \"$w/critical\" ] || { echo\
    \ \"FAIL R6: the critical section ran after the predicate came true\" >&2; exit\
    \ 1; }\necho \"R5/R6 ok\"\nR5R6\n.agents/factory/bin/temp_root.sh --offline sh\
    \ -s <<'R7R11' || exit 1\nset -u\nif ! UVM_LOCK_STALE=1 uv --version > \"$UVM_SANDBOX/out\"\
    \ 2> \"$UVM_SANDBOX/err\"; then\n  echo \"FAIL R7: an inherited UVM_LOCK_STALE\
    \ made the call fail\" >&2; cat \"$UVM_SANDBOX/err\" >&2; exit 1; fi\n[ \"$(cat\
    \ \"$UVM_SANDBOX/out\")\" = \"uv 9.9.9 (fixture)\" ] || { echo \"FAIL R7: stdout\
    \ [$(cat \"$UVM_SANDBOX/out\")]\" >&2; exit 1; }\nUVM_ROOT=\"$UVM_SANDBOX/root.r11\"\
    ; export UVM_ROOT; mkdir -p \"$UVM_ROOT\"\nsh=\"$UVM_SANDBOX/shim\"; mkdir -p\
    \ \"$sh\"\ncat > \"$sh/mkdir\" <<'SHIM'\n#!/bin/sh\ncase \"${1:-}\" in\n  *.install.lock)\
    \ echo hit >> \"$UVM_SANDBOX/mkdir.hits\"\n                  /bin/mkdir \"$1\"\
    \ || exit $?; ln -s /nonexistent/target/owner \"$1/owner\"; exit 0 ;;\nesac\n\
    exec /bin/mkdir \"$@\"\nSHIM\nchmod +x \"$sh/mkdir\"\nif PATH=\"$sh:$PATH\" uv\
    \ --version > \"$UVM_SANDBOX/out\" 2> \"$UVM_SANDBOX/err\"; then\n  echo \"FAIL\
    \ R11: a failed owner write exited 0\" >&2; exit 1; fi\n[ -s \"$UVM_SANDBOX/mkdir.hits\"\
    \ ] || { echo \"FAIL R11: mkdir shim never fired (call shape changed)\" >&2; exit\
    \ 1; }\ngrep -q 'No such file or directory' \"$UVM_SANDBOX/err\" || { echo \"\
    FAIL R11: the shell's errno line is missing\" >&2; cat \"$UVM_SANDBOX/err\" >&2;\
    \ exit 1; }\ngrep -q 'cannot record ownership' \"$UVM_SANDBOX/err\" || { echo\
    \ \"FAIL R11: cannot record ownership is missing\" >&2; cat \"$UVM_SANDBOX/err\"\
    \ >&2; exit 1; }\nif [ -e \"$UVM_ROOT/$(uname -m)/.install.lock\" ] || [ -L \"\
    $UVM_ROOT/$(uname -m)/.install.lock\" ]; then\n  echo \"FAIL R11: .install.lock\
    \ left standing: [$(ls -A \"$UVM_ROOT/$(uname -m)/.install.lock\")]\" >&2; exit\
    \ 1; fi\necho \"R7/R11 ok\"\nR7R11\no=\"$(tests/lock-race.sh --plant control --ranks\
    \ 32 --bursts 2)\" || { echo \"FAIL R14: control burst exited non-zero\" >&2;\
    \ echo \"$o\" >&2; exit 1; }\necho \"$o\" | grep -q -E '^installer_entries=2(\
    \ |$)' || { echo \"FAIL R14: expected one installer entry per burst\" >&2; echo\
    \ \"$o\" >&2; exit 1; }\necho \"$o\" | grep -q '^progress=ok$' || { echo \"FAIL\
    \ R14: progress\" >&2; echo \"$o\" >&2; exit 1; }\necho \"P1 ok\"\n"
- id: P2
  name: A concurrent publish leaves a correct tree, and the instrument asserts it
  status: done
  satisfies:
  - R4
  - R10
  - R14
  - R15
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\nbash -n bin/uv-manager || { echo \"FAIL: bash -n\" >&2; exit 1;\
    \ }\n.agents/factory/bin/lint.sh >/dev/null || { echo \"FAIL: lint.sh\" >&2; exit\
    \ 1; }\nif git grep -n -E 'stolen_holds|robbed_winners|break_notes|LOCKRACE_STALE|UVM_LOCK_STALE'\
    \ -- tests/; then\n  echo \"FAIL R15: tests/ still carries the counters or the\
    \ knob that can no longer fire\" >&2; exit 1; fi\nif git grep -n -i -E 'stale|kill\
    \ -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher'\
    \ -- AGENTS.md .agents/factory/invariants.md etc/uv-manager.conf.example; then\n\
    \  echo \"FAIL R9: AGENTS.md, invariants.md or the config example still carries\
    \ the retired mechanism\" >&2; exit 1; fi\nif git grep -n 'guarded by nothing'\
    \ -- AGENTS.md .agents/factory/invariants.md; then\n  echo \"FAIL R4: an invariant\
    \ still records the publish as unguarded\" >&2; exit 1; fi\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'R4A' || exit 1\nset -u\nsh=\"$UVM_SANDBOX/shim\"; mkdir -p\
    \ \"$sh\"\ncat > \"$sh/mv\" <<'SHIM'\n#!/bin/sh\ncase \"${1:-}\" in\n  */versions/.incoming.*)\
    \ echo hit >> \"$UVM_SANDBOX/mv.hits\"; [ -e \"$2\" ] || cp -R \"$1\" \"$2\" ;;\n\
    esac\nexec /bin/mv \"$@\"\nSHIM\nchmod +x \"$sh/mv\"\nroot=\"$UVM_ROOT/$(uname\
    \ -m)\"\nPATH=\"$sh:$PATH\" uv --version > \"$UVM_SANDBOX/out\" 2> \"$UVM_SANDBOX/err\"\
    ; rc=$?\n[ -s \"$UVM_SANDBOX/mv.hits\" ] || { echo \"FAIL R4(a): mv shim never\
    \ intercepted the publish (call shape changed)\" >&2; exit 1; }\n[ \"$rc\" -eq\
    \ 0 ] || { echo \"FAIL R4(a): rc=$rc\" >&2; cat \"$UVM_SANDBOX/err\" >&2; exit\
    \ 1; }\n[ \"$(cat \"$UVM_SANDBOX/out\")\" = \"uv 9.9.9 (fixture)\" ] || { echo\
    \ \"FAIL R4(a): stdout [$(cat \"$UVM_SANDBOX/out\")]\" >&2; exit 1; }\ngot=$(ls\
    \ -A \"$root/versions/9.9.9\" | tr '\\n' ' ')\n[ \"$got\" = \"uv uvx \" ] || {\
    \ echo \"FAIL R4(a): versions/9.9.9 holds [$got]\" >&2; exit 1; }\nleft=$(find\
    \ \"$root/versions\" -name '.incoming.*' | wc -l | tr -d ' ')\n[ \"$left\" -eq\
    \ 0 ] || { echo \"FAIL R4(a): $left .incoming.* left\" >&2; exit 1; }\n[ \"$(readlink\
    \ \"$root/current\")\" = versions/9.9.9 ] || { echo \"FAIL R4(a): current -> $(readlink\
    \ \"$root/current\")\" >&2; exit 1; }\n[ ! -e \"$root/.install.lock\" ] || { echo\
    \ \"FAIL R4(a): lock left standing\" >&2; exit 1; }\necho \"R4(a) ok\"\nR4A\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'R10' || exit 1\nset -u\nsh=\"\
    $UVM_SANDBOX/shim\"; mkdir -p \"$sh\"\ncat > \"$sh/mv\" <<'SHIM'\n#!/bin/sh\n\
    case \"${1:-}\" in\n  */versions/.incoming.*) echo hit >> \"$UVM_SANDBOX/mv.hits\"\
    ; echo \"mv: rename $1 to $2: Permission denied\" >&2; exit 1 ;;\nesac\nexec /bin/mv\
    \ \"$@\"\nSHIM\nchmod +x \"$sh/mv\"\nroot=\"$UVM_ROOT/$(uname -m)\"\nif PATH=\"\
    $sh:$PATH\" uv --version > \"$UVM_SANDBOX/out\" 2> \"$UVM_SANDBOX/err\"; then\n\
    \  echo \"FAIL R10: a failed publish exited 0\" >&2; exit 1; fi\n[ -s \"$UVM_SANDBOX/mv.hits\"\
    \ ] || { echo \"FAIL R10: mv shim never intercepted the publish (call shape changed)\"\
    \ >&2; exit 1; }\ngrep -q '^uv-manager: .*publish.*9\\.9\\.9.*Permission denied'\
    \ \"$UVM_SANDBOX/err\" || { echo \"FAIL R10: no uv-manager: line naming the failed\
    \ publish and its errno\" >&2; cat \"$UVM_SANDBOX/err\" >&2; exit 1; }\n[ ! -s\
    \ \"$UVM_SANDBOX/out\" ] || { echo \"FAIL R10: stdout [$(cat \"$UVM_SANDBOX/out\"\
    )]\" >&2; exit 1; }\nleft=$(find \"$root/versions\" -name '.incoming.*' | wc -l\
    \ | tr -d ' ')\n[ \"$left\" -eq 0 ] || { echo \"FAIL R10: $left .incoming.* left\"\
    \ >&2; exit 1; }\n[ ! -e \"$root/versions/9.9.9\" ] || { echo \"FAIL R10: versions/9.9.9\
    \ exists after a failed publish\" >&2; exit 1; }\n[ ! -e \"$root/.install.lock\"\
    \ ] || { echo \"FAIL R10: lock left standing\" >&2; exit 1; }\necho \"R10 ok\"\
    \nR10\np1=$(git log --reverse --format=%H -F --grep='Build lock-simplification\
    \ P1:' HEAD | head -n 1)\n[ -n \"$p1\" ] || { echo \"FAIL: P1 has not landed (no\
    \ 'Build lock-simplification P1:' commit on HEAD)\" >&2; exit 1; }\nX=$(mktemp\
    \ -d \"${TMPDIR:-/tmp}/lr-red.XXXXXX\")\ngit archive HEAD | tar -x -C \"$X\" ||\
    \ { echo \"FAIL: could not export HEAD\" >&2; exit 1; }\ngit show \"${p1}:bin/uv-manager\"\
    \ > \"$X/bin/uv-manager\" || { echo \"FAIL: could not read P1's wrapper\" >&2;\
    \ exit 1; }\nif grep -q 'tmp##\\*/' \"$X/bin/uv-manager\"; then echo \"FAIL R15:\
    \ P1's wrapper already guards the publish, so it cannot show the red state\" >&2;\
    \ exit 1; fi\n\"$X/tests/lock-race.sh\" --plant held --ranks 64 --bursts 10 >\
    \ \"$X/red.out\" 2> \"$X/red.err\"; red=$?\nif [ \"$red\" -ne 1 ] || ! grep -qE\
    \ '^nested_staging=[1-9]' \"$X/red.out\"; then\n  echo \"FAIL R15: against P1's\
    \ unguarded publish the held drive exited $red without nested_staging>0\" >&2;\
    \ cat \"$X/red.out\" >&2; exit 1; fi\necho \"R15 red against P1 ($p1):\"; cat\
    \ \"$X/red.out\"\no=$(tests/lock-race.sh --plant held --ranks 64 --bursts 10)\
    \ || { echo \"FAIL R4(b)/R15: held drive on HEAD\" >&2; echo \"$o\" >&2; exit\
    \ 1; }\necho \"$o\"\no=$(tests/lock-race.sh --plant control --ranks 32 --bursts\
    \ 2) || { echo \"FAIL R14: control drive on HEAD\" >&2; echo \"$o\" >&2; exit\
    \ 1; }\necho \"$o\" | grep -q -E '^installer_entries=2( |$)' || { echo \"FAIL\
    \ R14: expected one installer entry per burst\" >&2; echo \"$o\" >&2; exit 1;\
    \ }\necho \"P2 ok\"\n"
- id: P3
  name: Every success path in uvm_install selects the version it was asked for
  status: done
  satisfies:
  - R12
  - R13
  - R14
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\nbash -n bin/uv-manager || { echo \"FAIL: bash -n\" >&2; exit 1;\
    \ }\n.agents/factory/bin/lint.sh >/dev/null || { echo \"FAIL: lint.sh\" >&2; exit\
    \ 1; }\n.agents/factory/bin/temp_root.sh --offline sh -s <<'R12' || exit 1\nset\
    \ -u\narch=$(uname -m)\nmkdir -p \"$UVM_FIXTURE_DIR/6.6.6\"; cp \"$UVM_FIXTURE_DIR/install.sh\"\
    \ \"$UVM_FIXTURE_DIR/6.6.6/install.sh\"\nshim=\"$UVM_SANDBOX/shim\"; mkdir -p\
    \ \"$shim\"\nprintf '#!/bin/sh\\necho x >> \"%s/ln.calls\"\\nsleep 2\\nexec /bin/ln\
    \ \"$@\"\\n' \"$UVM_SANDBOX\" > \"$shim/ln\"; chmod +x \"$shim/ln\"\nburst() {\
    \  # LABEL WARM FIXVER RANKS CMD...: concurrent ranks on a fresh root, ln widened\n\
    \  label=$1 warm=$2 fv=$3 k=$4; shift 4\n  r=\"$UVM_SANDBOX/$label\"; mkdir -p\
    \ \"$r\"\n  if [ -n \"$warm\" ]; then\n    UVM_ROOT=\"$r\" uv --version >/dev/null\
    \ 2>&1\n    [ \"$(readlink \"$r/$arch/current\")\" = versions/9.9.9 ] || { echo\
    \ \"FAIL: $label: warm-up did not select 9.9.9\" >&2; exit 1; }\n  fi\n  : > \"\
    $UVM_SANDBOX/ln.calls\"\n  i=1; while [ \"$i\" -le \"$k\" ]; do\n    ( if [ -n\
    \ \"$fv\" ]; then UVM_FIXTURE_VERSION=\"$fv\"; export UVM_FIXTURE_VERSION; fi\n\
    \      PATH=\"$shim:$PATH\" UVM_ROOT=\"$r\" \"$@\" > \"$r.out.$i\" 2> \"$r.err.$i\"\
    ; echo $? > \"$r.rc.$i\" ) &\n    i=$((i + 1)); done; wait\n}\nwidened() { [ -s\
    \ \"$UVM_SANDBOX/ln.calls\" ] || { echo \"FAIL: $1: ln shim never called; the\
    \ drive no longer widens the gap\" >&2; exit 1; }; }\nrow() { echo \"rc=$(cat\
    \ \"$1.rc.$2\") out=[$(cat \"$1.out.$2\")] err=[$(tail -n 1 \"$1.err.$2\")]\"\
    ; }\nfor t in cold warm; do\n  if [ \"$t\" = warm ]; then w=1; else w=; fi\n \
    \ burst \"ok-$t\" \"$w\" 6.6.6 16 env UVM_PIN=6.6.6 uv --version; widened \"ok-$t\"\
    \n  i=1; while [ \"$i\" -le 16 ]; do r=\"$UVM_SANDBOX/ok-$t\"\n    if [ \"$(cat\
    \ \"$r.rc.$i\")\" != 0 ] || [ \"$(cat \"$r.out.$i\")\" != \"uv 6.6.6 (fixture)\"\
    \ ]; then\n      echo \"FAIL R12: ok-$t rank $i: $(row \"$r\" \"$i\")\" >&2; exit\
    \ 1; fi\n    i=$((i + 1)); done\n  # The 6.6.6 installer delivers 9.9.9, so the\
    \ pin cannot be selected. The last stderr\n  # line is read on purpose: the \"\
    installing uv (6.6.6)\" note names 6.6.6 on main too.\n  burst \"bad-$t\" \"$w\"\
    \ \"\" 16 env UVM_PIN=6.6.6 uv --version\n  i=1; while [ \"$i\" -le 16 ]; do r=\"\
    $UVM_SANDBOX/bad-$t\"\n    if [ \"$(cat \"$r.rc.$i\")\" = 0 ] || [ -s \"$r.out.$i\"\
    \ ] || ! tail -n 1 \"$r.err.$i\" | grep -q '6\\.6\\.6'; then\n      echo \"FAIL\
    \ R12: bad-$t rank $i: $(row \"$r\" \"$i\")\" >&2; exit 1; fi\n    i=$((i + 1));\
    \ done\ndone\nburst op-install 1 6.6.6 8 uvm install 6.6.6; widened op-install\n\
    i=1; while [ \"$i\" -le 8 ]; do r=\"$UVM_SANDBOX/op-install\"\n  if [ \"$(cat\
    \ \"$r.rc.$i\")\" != 0 ] || [ \"$(tail -n 1 \"$r.err.$i\")\" != \"uv-manager:\
    \ selected uv 6.6.6 (fixture)\" ]; then\n    echo \"FAIL R12: uvm install 6.6.6\
    \ rank $i: $(row \"$r\" \"$i\")\" >&2; exit 1; fi\n  i=$((i + 1)); done\nburst\
    \ op-self 1 6.6.6 8 uv self update 6.6.6; widened op-self\ni=1; while [ \"$i\"\
    \ -le 8 ]; do r=\"$UVM_SANDBOX/op-self\"\n  if [ \"$(cat \"$r.rc.$i\")\" != 0\
    \ ] || [ \"$(cat \"$r.out.$i\")\" != \"uv 6.6.6 (fixture)\" ]; then\n    echo\
    \ \"FAIL R12: uv self update 6.6.6 rank $i: $(row \"$r\" \"$i\")\" >&2; exit 1;\
    \ fi\n  i=$((i + 1)); done\nfor r in ok-cold ok-warm op-install op-self; do\n\
    \  if find \"$UVM_SANDBOX/$r/$arch/versions\" -mindepth 2 -name '.*' | grep .;\
    \ then\n    echo \"FAIL R4: $r left an entry nested inside a published version\"\
    \ >&2; exit 1; fi\ndone\necho \"R12 ok\"\nR12\no=$(tests/lock-race.sh --plant\
    \ control --ranks 32 --bursts 2) || { echo \"FAIL R14: control drive\" >&2; echo\
    \ \"$o\" >&2; exit 1; }\necho \"$o\" | grep -q -E '^installer_entries=2( |$)'\
    \ || { echo \"FAIL R14: expected one installer entry per burst\" >&2; echo \"\
    $o\" >&2; exit 1; }\no=$(tests/lock-race.sh --plant held --ranks 32 --bursts 3)\
    \ || { echo \"FAIL R4(b): held drive\" >&2; echo \"$o\" >&2; exit 1; }\necho \"\
    P3 ok\"\n"
- id: P4
  name: uvm doctor reports a standing lock and stranded staging copies, uvm clean
    lock removes the lock; surface census
  status: done
  satisfies:
  - R4
  - R7
  - R8
  - R9
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\nbash -n bin/uv-manager || { echo \"FAIL: bash -n\" >&2; exit 1;\
    \ }\n.agents/factory/bin/lint.sh >/dev/null || { echo \"FAIL: lint.sh\" >&2; exit\
    \ 1; }\n.agents/factory/bin/temp_root.sh --offline sh -s <<'R8' || exit 1\nset\
    \ -u\nr=\"$UVM_ROOT/$(uname -m)\"; l=\"$r/.install.lock\"; o=\"host=elsewhere.example\
    \ pid=4242 nonce=plant-r8\"\nuv --version >/dev/null 2>&1 || { echo \"FAIL R8:\
    \ could not provision\" >&2; exit 1; }\nmkdir \"$l\" && printf '%s\\n' \"$o\"\
    \ > \"$l/owner\"\nuvm doctor > \"$UVM_SANDBOX/d\" 2>&1 || { echo \"FAIL R8: doctor\
    \ exited non-zero on a working tree with a lock standing\" >&2; cat \"$UVM_SANDBOX/d\"\
    \ >&2; exit 1; }\ngrep -F -q \"$l\" \"$UVM_SANDBOX/d\" || { echo \"FAIL R8: doctor\
    \ does not name the lock path\" >&2; cat \"$UVM_SANDBOX/d\" >&2; exit 1; }\ngrep\
    \ -F -q \"$o\" \"$UVM_SANDBOX/d\" || { echo \"FAIL R8: doctor does not carry the\
    \ owner line\" >&2; cat \"$UVM_SANDBOX/d\" >&2; exit 1; }\ngrep -q 'may still\
    \ be running' \"$UVM_SANDBOX/d\" || { echo \"FAIL R8: doctor does not say the\
    \ holder may be live\" >&2; cat \"$UVM_SANDBOX/d\" >&2; exit 1; }\nuvm clean lock\
    \ > \"$UVM_SANDBOX/n\" 2>&1 || { echo \"FAIL R8: clean lock dry run exited non-zero\"\
    \ >&2; cat \"$UVM_SANDBOX/n\" >&2; exit 1; }\n[ -d \"$l\" ] || { echo \"FAIL R8:\
    \ the dry run removed the lock\" >&2; exit 1; }\ngrep -F -q \"$o\" \"$UVM_SANDBOX/n\"\
    \ || { echo \"FAIL R8: the dry run hides the owner line\" >&2; cat \"$UVM_SANDBOX/n\"\
    \ >&2; exit 1; }\ngrep -q 'may still be running' \"$UVM_SANDBOX/n\" || { echo\
    \ \"FAIL R8: the dry run does not say the holder may be live\" >&2; cat \"$UVM_SANDBOX/n\"\
    \ >&2; exit 1; }\nuvm clean lock --yes 2>/dev/null || { echo \"FAIL R8: clean\
    \ lock --yes exited non-zero\" >&2; exit 1; }\n[ ! -e \"$l\" ] || { echo \"FAIL\
    \ R8: lock still standing after clean lock --yes\" >&2; exit 1; }\n[ \"$(readlink\
    \ \"$r/current\")\" = versions/9.9.9 ] && [ -x \"$r/versions/9.9.9/uv\" ] || {\
    \ echo \"FAIL R8: clean lock touched the installed tree\" >&2; exit 1; }\nuvm\
    \ doctor > \"$UVM_SANDBOX/d\" 2>&1 || { echo \"FAIL R8: doctor exited non-zero\
    \ after clean\" >&2; cat \"$UVM_SANDBOX/d\" >&2; exit 1; }\nif grep -q 'install.lock'\
    \ \"$UVM_SANDBOX/d\"; then echo \"FAIL R8: doctor still reports a lock\" >&2;\
    \ exit 1; fi\n# Stranded staging copies: one beside the versions, one nested inside\
    \ a published one.\ns1=\"$r/versions/.incoming.strandA\"; s2=\"$r/versions/9.9.9/.incoming.strandB\"\
    \nmkdir \"$s1\" \"$s2\" && cp \"$r/versions/9.9.9/uv\" \"$s1/uv\" && cp \"$r/versions/9.9.9/uv\"\
    \ \"$s2/uv\"\nuvm doctor > \"$UVM_SANDBOX/d\" 2>&1 || { echo \"FAIL R4: doctor\
    \ exited non-zero over a stranded staging copy\" >&2; cat \"$UVM_SANDBOX/d\" >&2;\
    \ exit 1; }\nfor s in \"$s1\" \"$s2\"; do\n  grep -F \"$s\" \"$UVM_SANDBOX/d\"\
    \ | grep -q '^WARN' || { echo \"FAIL R4: doctor does not report the stranded copy\
    \ at $s as a WARN\" >&2; cat \"$UVM_SANDBOX/d\" >&2; exit 1; }\n  [ -d \"$s\"\
    \ ] || { echo \"FAIL R4: doctor removed $s; it reports and never clears\" >&2;\
    \ exit 1; }\ndone\necho \"R8 ok\"\nR8\nif git grep -n -E 'uvm_lock_heartbeat|uvm_proc_start|uvm_age|lock_stale|UVM_LOCK_STALE|kill\
    \ -0' -- bin/uv-manager; then\n  echo \"FAIL R7: liveness, age or stale-knob code\
    \ in bin/uv-manager\" >&2; exit 1; fi\nif git grep -n -i -E 'UVM_LOCK_STALE|heartbeat|refresher|stale.?breaker|broken\
    \ as stale|break(s|ing)? (itself|the lock|a lock|stale|its)|breaks itself' --\
    \ AGENTS.md .agents/factory/invariants.md README.md etc/uv-manager.conf.example;\
    \ then\n  echo \"FAIL R9: the GOAL's pattern matches\" >&2; exit 1; fi\nif git\
    \ grep -n -i -E 'stale|kill -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher'\
    \ -- AGENTS.md .agents/factory/invariants.md etc/uv-manager.conf.example; then\n\
    \  echo \"FAIL R9: the supplement matches in a file graded at zero\" >&2; exit\
    \ 1; fi\nif .agents/factory/bin/temp_root.sh uvm help | grep -n UVM_LOCK_STALE;\
    \ then\n  echo \"FAIL R9: uvm help documents UVM_LOCK_STALE\" >&2; exit 1; fi\n\
    .agents/factory/bin/temp_root.sh uvm help | grep -q 'clean.*lock' || { echo \"\
    FAIL R8: uvm help does not list the lock target\" >&2; exit 1; }\necho \"README\
    \ hits on the supplement, for the reviewer to read (not asserted):\"\ngit grep\
    \ -n -i -E 'stale|kill -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher'\
    \ -- README.md || echo \"  (none)\"\necho \"P4 ok\"\n"
- id: P5
  name: 'Cross-node drive on Lustre and GPFS (external wait: Run A, then Run B)'
  status: done
  satisfies:
  - R1
  - R4
  - R12
  - R14
  depends_on:
  - P4
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\ngrep -q -- '--launch' tests/lock-race.sh || { echo \"FAIL: P5 Run\
    \ A has not landed (tests/lock-race.sh has no --launch mode)\" >&2; exit 1; }\n\
    bash -n bin/uv-manager || { echo \"FAIL: bash -n\" >&2; exit 1; }\n.agents/factory/bin/lint.sh\
    \ >/dev/null || { echo \"FAIL: lint.sh\" >&2; exit 1; }\nLOCKRACE_SHARED='' tests/lock-race.sh\
    \ --launch srun --plant control --ranks 2 --bursts 1 >/dev/null 2>&1; rc=$?\n\
    [ \"$rc\" -eq 2 ] || { echo \"FAIL R4(c): --launch srun without LOCKRACE_SHARED\
    \ exited $rc, expected the usage refusal 2\" >&2; exit 1; }\nX=$(mktemp -d \"\
    ${TMPDIR:-/tmp}/lr-p5.XXXXXX\")\ntests/lock-race.sh --launch local --plant held\
    \ --ranks 16 --bursts 2 --summary \"$X/held\" >/dev/null || { echo \"FAIL R4(b):\
    \ local held run\" >&2; cat \"$X/held\" >&2; exit 1; }\ntests/lock-race.sh --launch\
    \ local --plant control --pin 6.6.6 --ranks 16 --bursts 2 --summary \"$X/pin\"\
    \ >/dev/null || { echo \"FAIL R12: local pinned run\" >&2; cat \"$X/pin\" >&2;\
    \ exit 1; }\ngrep -qx 'stdout_hist=6.6.6:32' \"$X/pin\" || { echo \"FAIL R12:\
    \ pinned summary\" >&2; cat \"$X/pin\" >&2; exit 1; }\nfor f in \"$X/held\" \"\
    $X/pin\"; do\n  grep -qx 'progress=ok' \"$f\" || { echo \"FAIL: $f lacks progress=ok\"\
    \ >&2; cat \"$f\" >&2; exit 1; }\n  if grep -n -E '(^|[=:, ])/' \"$f\" || grep\
    \ -n -F \"$(uname -n)\" \"$f\"; then\n    echo \"FAIL: summary carries an absolute\
    \ path or a hostname; it is committed to a public repository\" >&2; exit 1; fi\n\
    done\nfor fs in lustre gpfs; do\n  f=\"spec/lock-simplification/evidence/$fs.txt\"\
    \n  [ -s \"$f\" ] || { echo \"FAIL R4(c): $f not recorded yet (P5 Run B, after\
    \ the foreman's cluster submission)\" >&2; exit 1; }\n  for k in scenario rc_hist\
    \ stdout_hist nested_staging nested_current stray_staging bad_trees plant_intact\
    \ concurrent_bursts locks_left_standing progress nodes bash; do\n    grep -q \"\
    ^$k=\" \"$f\" || { echo \"FAIL R4(c): $f has no $k= line\" >&2; exit 1; }; done\n\
    \  for s in control held pin; do grep -qx \"scenario=$s\" \"$f\" || { echo \"\
    FAIL R4(c): $f has no $s scenario\" >&2; exit 1; }; done\n  if grep -v -x 'progress=ok'\
    \ \"$f\" | grep -n '^progress='; then echo \"FAIL R4(c): $f records a run without\
    \ progress\" >&2; exit 1; fi\n  if grep '^rc_hist=' \"$f\" | grep -v -x -E 'rc_hist=0:[0-9]+';\
    \ then echo \"FAIL R4(c): $f records a non-zero rank\" >&2; exit 1; fi\n  if grep\
    \ '^stdout_hist=' \"$f\" | grep -v -x -E 'stdout_hist=(9\\.9\\.9|6\\.6\\.6):[0-9]+';\
    \ then echo \"FAIL R4(c): $f records a wrong or missing version\" >&2; exit 1;\
    \ fi\n  if grep -n -E '^(nested_staging|nested_current|stray_staging|bad_trees|locks_left_standing)=[1-9]'\
    \ \"$f\"; then echo \"FAIL R4(c): $f records a damaged tree or a leftover lock\"\
    \ >&2; exit 1; fi\n  if grep '^plant_intact=' \"$f\" | grep -v -x 'plant_intact=\\\
    ([0-9][0-9]*\\)/\\1'; then echo \"FAIL R1/R4(c): $f records a disturbed plant\"\
    \ >&2; exit 1; fi\n  grep -q -E '^concurrent_bursts=[1-9]' \"$f\" || { echo \"\
    FAIL R4(c): $f shows no burst that published concurrently\" >&2; exit 1; }\n \
    \ if grep -n -E '(^|[=:, ])/' \"$f\"; then echo \"FAIL: $f carries an absolute\
    \ path\" >&2; exit 1; fi\ndone\ngrep -qx 'nodes=2' spec/lock-simplification/evidence/lustre.txt\
    \ || { echo \"FAIL R4(c): the Lustre run did not span 2 nodes\" >&2; exit 1; }\n\
    echo \"P5 ok\"\n"
review:
  last_reviewed_commit: 3d17c6bc7e494f007a215e0316e1d0e7960d2007
  verdict: approved
  blocked_reason: ''
  cycle: 4
---
# TECH.md — Stop breaking the lock, and split provisioning from repair

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/lock-simplification/TECH.md`); the per-phase
checklists below are the work. `uvm-build` executes the next actionable phase, runs its `verify:`
command, updates state via `uv run .agents/factory/bin/set_phase.py …`, and makes one atomic
code-plus-state commit.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md). R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) and briefs 01–05.

## Frontmatter field reference

As in [the template](../../.agents/factory/templates/TECH.md). Points specific to this file:
- **`hammerable` is `false` everywhere.** Every phase touches `invariants.md` §4, §5 or §6, or the
  cross-node evidence for them.
- **`parallel` is `false` everywhere.** Every phase edits `bin/uv-manager` or `tests/`.
- **Gates run under `/bin/sh`.** Test one with
  `uv run .agents/factory/bin/run_verify.py spec/lock-simplification/TECH.md --phase P<n>`.

## Gate traps

These are the template's table, plus two this plan hit:
- **`grep -c` at zero.** `cmd | grep -c P` prints `0` *and exits 1* when nothing matches. A gate
  keyed on status then reads a correct tree as red. The GOAL's R9 `uvm help | grep -c
  UVM_LOCK_STALE` is that shape, so the gates use `if cmd | grep -n P; then FAIL; fi`.
- **A shim that never fires.** If a call shape changes (`mv -- …`, `/bin/mv`, a relative `cd`), the
  shim stops intercepting and the drive goes green vacuously. This was measured with `mv --` in
  research 02. Every shim here appends to a `*.hits` / `*.calls` file, and the gate fails if that
  file is empty.

## Conventions (apply to every phase)

- [`AGENTS.md`](../../AGENTS.md) is the constitution. Consult
  [`invariants.md`](../../.agents/factory/invariants.md) §2, §4, §5, §6, §7, §10 and §12.
- **Commits.** One phase per `uvm-build` invocation, in one atomic commit that holds the code and the
  `TECH.md` state. The subject is `[fix] Build lock-simplification P<n>: …`. **P2's gate finds P1 by
  that exact subject prefix**, so keep it.
- Keep the `Co-Authored-By` trailer.
- **Same-commit rule.** A behavior change updates `uvm_help`, `README.md` and
  `etc/uv-manager.conf.example`, whichever it invalidates, plus `AGENTS.md` § Invariants and
  `invariants.md` where the change overturns an assertion. The modulefile carries no lock text.
- **No spec ids** (`R1`, `P3`) in `bin/uv-manager`, `README.md` or `tests/`.
- **Wording rule** (PLAN §2): state the contract without *break* (any form), *stale*, *liveness*,
  *heartbeat*, *refresher*, *retake*, *robbed* or *forfeit*. Never name `UVM_LOCK_STALE` in
  `AGENTS.md`, `invariants.md` or the config example. The gates assert zero hits on those files.
- **Bash 5 hazard** (research 01 Q6). Every test in the lock and install code sits inside `if`, `&&`
  or `||`. A bare false `(( ))` or `[[ ]]` statement continues on the Mac's 3.2 and exits on a
  cluster's bash 5, so the reviewer checks this by reading.
- **Call shapes the shims depend on:**
  - `mkdir "${lock}"` with the lock path alone (R11);
  - `mv "${tmp}" "${dest}"` with the staging path as `$1` (R4 (a), R10);
  - an external `ln` found through `PATH` in `uvm_point_current` (R12);
  - the banners `# ---- provisioning lock` and `# ---- fetching` around the lock section, with
    `lock_timeout` defined outside it (R5/R6 harness).

---

## Phase P1 — The lock never breaks
**Satisfies:** R1, R2, R3, R5, R6, R7, R9 (lock passages), R11, R14 · **Depends on:** —

**Goal:** `uvm_acquire_lock` becomes the PLAN §2 shape:
- a caller-named predicate;
- one notice at `min(30, UVM_LOCK_TIMEOUT)`;
- `proceed` or `fail` at the timeout;
- `uvm_lock` set before the owner write;
- release by path.

Every line of liveness and age inference goes, and the lock's documentation is rewritten in the same
commit. The publish stays `main`'s unguarded `mv` on purpose. P2's red-state gate rebuilds exactly
this commit's wrapper, so **do not touch the publish block in P1**.

**Code (`bin/uv-manager`):**
- [x] Delete `uvm_proc_start`, `uvm_lock_heartbeat` and `uvm_age`, along with the globals
  `uvm_lock_owner`/`uvm_lock_beat_pid`, the `lock_stale` knob and the timeout<stale guard.
- [x] `uvm_unlock`: release by path (PLAN §2). The three traps are unchanged.
- [x] `uvm_acquire_lock ON_TIMEOUT PREDICATE [ARG...]`, per PLAN §2:
  - The predicate guard is an explicit `(( $# ))` check that dies when no predicate is given, not
    `${1:?}`.
  - Keep `UVM_LOCK_TIMEOUT`'s form test and base-10 normalisation, inside the function.
  - Keep the absent-retry bound of 3 and its rationale comment.
  - The notice carries the owner line, says the holder may still be running, and prints the
    path-form removal command `rm -f '<lock>/owner' && rmdir '<lock>'`.
  - `fail` dies naming the lock and the owner line.
  - `uvm_lock` is set before `printf … > "${lock}/owner" || die "cannot record ownership of the
    provisioning lock at ${lock}/owner"`. The redirect stays unsuppressed, so the errno line
    reaches stderr.
  - Update the header comment with the return-code contract and the predicate-author rules (errexit
    is suspended inside a predicate; never touch `uvm_lock`).
- [x] `uvm_install` calls the lock with a predicate. It keeps `main`'s early-out semantics for now:
  - the call is `uvm_acquire_lock proceed "${satisfied[@]}" || return 0`, where `satisfied` is
    `(uvm_have "${want}")`, or `(false)` when forced, and never empty;
  - the re-check under the lock runs the same predicate.

  P3 replaces that `|| return 0`.
- [x] `uvm_self_update`'s and the dispatch tail's comments about "the stale timer" are reworded. The
  `uvm_unlock` guards in front of `exec` stay.

**Surface, same commit:**
- [x] `uvm_help`: remove the two `UVM_LOCK_STALE` lines. `UVM_LOCK_TIMEOUT` reads "Seconds to wait
  for the provisioning lock before installing without it (default: 180)".
- [x] `README.md`, rewriting research 05's rows for these passages:
  - `:137-138` (signals, and a waiter past the timeout installs for itself);
  - `:526-534` (troubleshooting: the notice, the path-form command, "may still be running");
  - `:561-569` (delete the `UVM_LOCK_STALE` row, the "Must be less than" clause and the NFS
    paragraph).
- [x] `etc/uv-manager.conf.example`: keep the `UVM_LOCK_TIMEOUT` line with a new comment. Delete the
  stale-knob block (`:74-88`).
- [x] `AGENTS.md` § Invariants (`:143-205`), per research 05's table: rewrite the mkdir paragraph,
  the release paragraph, the persistence clause, the TIMEOUT guard and the timeout-message
  paragraph, and delete "A live holder's lock never ages out". Leave `:269-279` (the
  `tests/lock-race.sh` paragraph) for P2.
- [x] `.agents/factory/invariants.md` §5, rewritten bullet by bullet per research 05:
  - delete the age, leash and liveness bullets;
  - rewrite the ownership, early-out, host-token, TIMEOUT and timeout bullets;
  - keep the mkdir, exec and persistence bullets, reworded where they cite the retired mechanism.

  The new §5 asserts the decision: only the creator removes the lock, apart from a human through
  `uvm clean`.
  §4 and §6 wait for P2/P3.

**Verify:** the frontmatter gate. It asserts, in order:
- `bash -n` and lint;
- R7's grep finds nothing;
- R9: the GOAL's pattern finds nothing in the four files, the supplement finds nothing in
  `invariants.md` and the config example, and `uvm help` carries no `UVM_LOCK_STALE`;
- `flock` appears on exactly one line (R14);
- R1/R3: dead, bare and live plants survive byte-identical, with rc 0, the fixture version, `current`
  set, and no `break` line;
- R2: release at 33 s under timeout 60, rc 0, exactly one stderr line carrying the owner;
- R5/R6: the harness sources the lock section with `fail repaired` and the provisioning stub true. A
  never-released plant gives non-zero within 6 s, the owner line on stderr and no critical section;
  a predicate flipped at 2 s gives acquire rc 1 and no critical section;
- R7: an inherited `UVM_LOCK_STALE=1` still gives rc 0 and the fixture version;
- R11: the `mkdir` shim fired, rc≠0, the errno line, `cannot record ownership`, and no
  `.install.lock`;
- R14: `tests/lock-race.sh --plant control --ranks 32 --bursts 2` gives rc 0, `installer_entries=2`
  and `progress=ok`.

The run takes about 60 s. Observed against the current tree: red at the R7 grep. The drive segment
was proven green on a throwaway copy carrying research 01's draft.

**Inspection-only:**
- R9's "SHALL NOT retain a sentence describing a break", for any sentence the patterns cannot see.
- R7's "nothing reads a pid, a start time, a heartbeat or an mtime".
- The bash 5 rule above.

**Touches:** `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`, `AGENTS.md`,
`.agents/factory/invariants.md`.

**Remediation, review cycle 1 (2026-10-28), prose only — no executable line changes:**
- [x] F1: `invariants.md` §5 and `AGENTS.md` say the traps release a lock this process holds, once
  `uvm_lock` is set, and drop "the instant `mkdir` wins". A signal between the winning `mkdir` and
  that assignment leaves an ownerless lock that `uvm doctor` reports and `uvm clean lock` removes;
  that window is the accepted failure mode. The comment above `uvm_lock="${lock}"` says the same.
- [x] Every phase gate P1–P5 re-run green after the edit.

**Remediation, review cycle 2 (2026-10-28), prose only — no executable line changes:**
- [x] C2-F1, C2-F2: `invariants.md` §5, `AGENTS.md`'s lock paragraphs and the comments at
  `uvm_unlock` and above `uvm_lock="${lock}"` state the guarantee as a principle: a process holds a
  lock exactly while `uvm_lock` names it and removes only a lock it holds. They give why
  `uvm_unlock` clears `uvm_lock` first, and the cost: a signal while the lock is being created or
  removed can leave it standing for `uvm doctor` and `uvm clean lock`. "On the statement after the
  winning `mkdir`" becomes "as soon as the winning `mkdir` returns".
- [x] Every phase gate P1–P5 re-run green after the edit.

**Remediation, review cycle 3 (2026-10-28, maintainer override: final wording, foreman-verified),
prose only — no executable line changes:**
- [x] C3-F3: `invariants.md` §5, `AGENTS.md`'s lock paragraph and high-risk-regions row, the
  comments above `uvm_lock=""` and the traps, `README.md`'s lock troubleshooting paragraph and the
  `UVM_LOCK_TIMEOUT` entry in `etc/uv-manager.conf.example` say no call removes a standing lock on
  its own: `uvm doctor` reports it and a human removes it with `uvm clean lock`. Until then a
  provisioning call whose request is not yet satisfied waits until it is or until `UVM_LOCK_TIMEOUT`
  passes, and a forced `uvm install` waits even on a warm tree.
- [x] Every phase gate P1–P5 re-run green after the edit.

## Phase P2 — A concurrent publish leaves a correct tree, and the instrument asserts it
**Satisfies:** R4 (a)(b), R10, R14, R15 · **Depends on:** P1

**Goal:** Ranks that proceed past the timeout can now publish the same version at once. The publish
detects a rival and discards its own copy (research 02), and `uvm_point_current` stops losing
`current` under concurrent swaps on BSD `mv` (research 02, 03, 04). `tests/lock-race.sh` stops
counting break artefacts and asserts the tree instead. Its red state is shown against P1's build and
its green state against this one.

**Code (`bin/uv-manager`):**
- [x] The publish block, as in PLAN §2. Keep `mv "${tmp}" "${dest}"` byte for byte inside
  `err="$(…2>&1)"`.
- [x] `uvm_point_current`: `mv -T` → `mv -h` → the existing `rm`+`mv` tail. Reword its comment: GNU
  takes `-T`, BSD takes `-h`, and the tail is for an `mv` with neither.

**Instrument (`tests/lock-race.sh`, `tests/lock-race-burst.sh`, per PLAN §2 and research 04):**
- [x] Plants are `control` and `held`. `owner` and `none` exit 2. Delete `LOCKRACE_STALE`, the
  `UVM_LOCK_STALE` export and the 2020 rationale.
- [x] Add `--timeout S` (default 1) as the burst's `UVM_LOCK_TIMEOUT`.
- [x] Arm the release barrier in the spliced fixture hook under `held` only.
- [x] The burst writes `tree.<tag>` before the sandbox goes, and the driver prints `nested_staging=`,
  `nested_current=`, `stray_staging=` and `bad_trees=`, each at the start of its own line. **P2's
  gate greps `^nested_staging=`.**
- [x] Progress (exit 4) and correctness (exit 1) are split as in PLAN §2. `nonzero_ranks` moves to
  exit 1. Under `held`, `locks_left_standing` counts locks *other than* the intact plant.
- [x] Remove `stolen`, `robbed` and `broke` and their twins and output lines. Rewrite the header's
  exit-code text and sizing rationale.

**Surface, same commit:**
- [x] `invariants.md` §6: the "guarded by nothing" bullet becomes the guarded publish.
- [x] `invariants.md` §4 and §10, and `AGENTS.md:237`: the `mv -T` fallback sentence names `-h`.
- [x] `AGENTS.md:269-279`: the `tests/lock-race.sh` paragraph describes the tree assertion, the plants
  and the progress rule. This clears the supplement's last `AGENTS.md` hits ("robbed", "declines
  every break").
- [x] Paste the R15 red run (the gate prints it) into the commit body, so the record survives
  `uvm-publish`'s squash.

**Amendments made while building (2026-10-27):**
- **The barrier's arrivals live in a per-burst directory** (`arr.<tag>/`), not as `arr.<tag>.<id>`
  in the collection directory. Every installer globs the arrivals every 10 ms, and the collection
  directory grows by several hundred files a burst, so the polls slowed until the barrier stopped
  releasing the ranks together. Measured at 64 ranks against P1's wrapper with the PLAN's layout:
  nesting in about half of a run's first 16 bursts and in none of the 23 after them, twice. With the
  per-burst directory: 31 of 40 bursts nested, stationary across the run.
- **Every instrument key prints on its own line** (`key=value`), so P5's summary file can be the
  same lines. The per-burst progress line on stderr carries `nested=<staging>/<current>`.
- **Line references moved.** On the tree P2 started from, the `mv -T` sentence this body places at
  `AGENTS.md:237` was at `:220`, and the `tests/lock-race.sh` paragraph at `:252-262`, not
  `:269-279`.
- **README** gains one clause in the provisioning summary (several calls publishing the same version
  keep one copy), under the same-commit rule.
- **The gate's R15 half archives `HEAD`**, so it grades the committed instrument. Before the commit
  it runs the old instrument against `--plant held` and exits 2. The gate was therefore run against
  a commit carrying the code, and the state change was folded into that same commit afterwards.

**Verify:** the frontmatter gate. It asserts, in order:
- `bash -n` and lint;
- `tests/` carries no retired counter or knob (R15);
- the supplement finds nothing in `AGENTS.md`, `invariants.md` and the config example;
- "guarded by nothing" is gone;
- R4 (a): the `mv` shim fired, rc 0, the fixture version, `versions/9.9.9` = `uv uvx`, no
  `.incoming.*`, `current` correct, and no lock;
- R10: the shim fired, rc≠0, `uv-manager: … publish … 9.9.9 … Permission denied`, empty stdout, no
  `.incoming.*`, no `versions/9.9.9`, and no lock;
- R15 red: the first `Build lock-simplification P1:` commit's wrapper, run in a `git archive` copy,
  exits 1 with `nested_staging≥1` on `--plant held --ranks 64 --bursts 10`. The gate checks first
  that that wrapper lacks the guard;
- R4 (b) and R15 green: the same drive exits 0 on HEAD;
- R14: control gives one installer per burst.

The run takes about 100 s.

**The R15 half reads git history, so this gate is valid on the branch, not after squash.** Observed
against the current tree: red at the `tests/` grep, which is this phase's own forward post-condition.
The R4 (a) and R10 segments were proven red on an unpatched copy and green on research 02's patched
copy.

**Inspection-only:** `mv -h` is unmeasured on GNU (unreachable after `-T`) and on busybox (PLAN §5).

**Touches:** `bin/uv-manager`, `tests/lock-race.sh`, `tests/lock-race-burst.sh`,
`.agents/factory/invariants.md`, `AGENTS.md`.

**Remediation, review cycle 1 (2026-10-28), prose only — no executable line changes:**
- [x] F2: `invariants.md` §4 and the two comments in `uvm_point_current` say the `rm`+`mv` fallback
  can also leave `current` briefly missing for a concurrent reader, besides nesting a
  `.current.<pid>` link. `AGENTS.md` scopes "never observes a missing `current`" to GNU (`-T`) and
  BSD/macOS (`-h`) `mv`.
- [x] Every phase gate P1–P5 re-run green after the edit.

**Remediation, review cycle 2 (2026-10-28), prose only — no executable line changes:**
- [x] C2-F3: `invariants.md` §4, `AGENTS.md`'s `current` paragraph and the fallback comment in
  `uvm_point_current` say that under the `rm`+`mv` fallback a concurrent swap makes a call's `mv`
  follow the new link, so `current` never names the version that call selected and the call execs
  the other version at status 0. Each place scopes the pin guarantee to an `mv` with `-T` or `-h`.
- [x] Every phase gate P1–P5 re-run green after the edit.

**Remediation, review cycle 3 (2026-10-28, maintainer override: final wording, foreman-verified),
prose only — no executable line changes:**
- [x] C3-F2: `invariants.md` §4's fallback sentence, `AGENTS.md`'s `current` paragraph and the
  fallback comment in `uvm_point_current` say a concurrent swap nests the call's `.current.<pid>`
  link so its own swap never lands, and that `current` names another version, which the call
  execs, only when that swap selected a different version. The "pin is authoritative only with
  `-T` or `-h`" qualifiers go.
- [x] Every phase gate P1–P5 re-run green after the edit.

## Phase P3 — Every success path selects the version it was asked for
**Satisfies:** R12, R13, R14 · **Depends on:** P2

**Goal:** `uvm_install`'s fast path, the lock's early-out, the re-check under the lock and a fresh
install all reach one selection step before the release. A pinned call whose installer delivered
another version dies naming the pin. `uvm_ensure_uv` collapses into `uvm_install`.

- [x] `uvm_install` restructured per PLAN §2:
  - the satisfied-predicate array, never empty;
  - `if uvm_acquire_lock proceed … && ! <satisfied>; then install; fi`;
  - one selection block before `uvm_unlock`;
  - the die `uv ${want} is not installed after provisioning${ver:+ (the installer delivered ${ver})}`
    as the last stderr line.
- [x] `uvm_ensure_uv` becomes `uvm_install "${pin}" ""` plus the `[[ -x "${real_uv}" ]]` check.
  `uvm install` and `uvm_self_update` keep calling `uvm_install` unchanged.
- [x] Update `uvm_install`'s header comment: every success path selects.
- [x] `invariants.md` §4: `uvm_have` stays the single spelling of the provisioning question; the lock
  runs the caller's predicate, which for provisioning is `uvm_have`; every success return from
  `uvm_install` has selected the requested version. Mirror the change in `AGENTS.md`'s pin paragraph
  if it names the early-out.
- [x] Hot path: no new fork on the unpinned-warm or pinned-selected paths (research 03 F3). Read it
  in the trace if in doubt.

Built 2026-10-27. `AGENTS.md`'s pin paragraph does not name the early-out, and its critical-regions
row ("a wrong early-out hands a pinned caller the wrong version") still holds, so `AGENTS.md` is
untouched. The three install conditions are one `&&` chain, so the install body is reachable only
when the work is undone, the lock did not early-out, and the re-check still finds it undone; every
other outcome falls through to the selection step. Traced: unpinned warm 0 forks, pinned selected 1
(`readlink`), pinned swap on macOS 5, as research 03 F3.

**Verify:** the frontmatter gate. It asserts:
- `bash -n` and lint.
- R12, with the `ln` shim (`sleep 2`), which must fire:
  - 16 pinned ranks cold and 16 warm all give rc 0 and `uv 6.6.6 (fixture)`;
  - with the 6.6.6 installer delivering 9.9.9, 16 cold and 16 warm all give rc≠0, empty stdout and
    a last stderr line naming 6.6.6;
  - 8 warm `uvm install 6.6.6` ranks give rc 0, with `uv-manager: selected uv 6.6.6 (fixture)` as
    the last line;
  - 8 warm `uv self update 6.6.6` ranks give rc 0 and `uv 6.6.6 (fixture)`;
  - no dot-entry inside any `versions/<ver>`.
- R14: control gives one installer per burst.
- A `held` regression run.

The run takes about 60 s. Observed against the current tree: red at `ok-cold rank 1: rc=1 … uv is
still missing after provisioning`. The R12 segment was proven green on research 03's patched copy in
45 s.

**Inspection-only:** R13 has no command. The reviewer reads `uvm_install` and its three callers
(`uvm_ensure_uv`, `uvm install`, `uvm_self_update`) and confirms that selection happens in exactly
one place.

**Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`, possibly `AGENTS.md`.

**Remediation, review cycle 2 (2026-10-28), prose only — no executable line changes:**
- [x] C2-F3: the `uvm_point_current` bullet in `invariants.md` §4 scopes "a pin is authoritative"
  and "a success return from `uvm_install` has selected the requested version" to an `mv` that
  takes `-T` or `-h`.
- [x] Every phase gate P1–P5 re-run green after the edit.

**Remediation, review cycle 3 (2026-10-28, maintainer override: final wording, foreman-verified),
prose only — no executable line changes:**
- [x] C3-F1: the pin headlines in `invariants.md` §4 and `AGENTS.md`, the "A pin is honoured"
  comment above `uvm_ensure_uv` and `README.md`'s "Pin the version" bullet bound the pin by
  conflicting pins, not by the `mv` path: a pin is authoritative over which version a call selects,
  and over `current` while no concurrent call on the same root selects a different version;
  differently pinned concurrent calls race for `current` and the last swap wins. "Every success
  return from `uvm_install` has selected the requested version" keeps its fallback exception.
- [x] Every phase gate P1–P5 re-run green after the edit.

## Phase P4 — `uvm doctor` reports a standing lock and stranded staging copies, `uvm clean lock` removes the lock; surface census
**Satisfies:** R4 (stranded copies a human can find), R7, R8, R9 · **Depends on:** P3

**Goal:** A crashed holder costs a line in `uvm doctor` and one human command. So does a crashed
publisher's staging copy. Neither line judges liveness. The full R9 census closes.

- [x] `uvm_doctor`: the WARN finding from PLAN §2 / research 05, with path, owner line or `<none
  recorded>`, "may still be running" and `uvm clean lock --yes`. It is advisory, never a FAIL. Add a
  comment saying why (a job prologue keyed on exit status).
- [x] `uvm_doctor`: one WARN per stranded staging copy. It covers each `versions/.incoming.*` and each
  hidden copy nested inside a published version (`versions/*/.incoming.*`). The line names the path,
  says it may belong to an install still running, and gives the removal command
  `rm -rf '<path>'`.
  - Report only: no liveness inference, no automatic removal, no new subcommand.
  - This is how deviation 2's residue (a loser killed between nesting and cleanup) and R10's
    worst case reach a human.
  - Sketch, proven on a throwaway copy:
    `for stray in "${uvm_versions}"/.incoming.* "${uvm_versions}"/*/.incoming.*; do [[ -e "${stray}" ]] || continue; findings+="WARN  staging copy left at ${stray}; …"; advisories+=1; done`.
  - Mention it in README's doctor list too.
- [x] `uvm_clean`:
  - add the `lock)` arm and the usage string `cache, lock, arch, all`;
  - the dry run for `lock` prints the owner line and "Its holder may still be running. Removing a
    live holder's lock lets a second call provision beside it." in place of `du -sh`;
  - `--yes` takes the existing path.
- [x] `uvm_help`: `clean [WHAT] --yes  Remove cache (default), lock, arch tree, or all`.
- [x] `README.md`:
  - the command table (`:184`) lists `lock`;
  - the doctor list (`:416-420`) gains "a provisioning lock left standing", as advisory;
  - troubleshooting mentions `uvm doctor` / `uvm clean lock`;
  - § Design notes records the rejected designs in plain words (PLAN §2), at zero R9 hits.
- [x] Re-read every passage the GOAL's pattern and the supplement matched on `main` (research 05's
  table), and confirm each is gone or rewritten.

Built 2026-10-27, with these amendments:
- **The dry run's live-holder warning names the chain.** PLAN's sentence stopped at "a second call
  provisions beside it". The foreman's note asked that it also say the holder's release then removes
  that call's lock, and so on down the line of waiters (PLAN §5's residual), so the dry run says
  both and tells the reader to remove the lock only once nothing is provisioning the tree. The
  doctor WARN keeps PLAN's one-line wording.
- **The doctor staging line** reads `WARN  staging copy left at <path>. It may belong to an install
  still running; once nothing is provisioning this tree, remove it with rm -rf '<path>'.`
- **Same-commit surfaces beyond the Touches line.** `AGENTS.md`'s and `invariants.md` §5's "by hand
  or through `uvm clean`" now name `uvm clean lock`, which is true as written. `invariants.md` §5
  gains the "doctor reports the lock and judges nothing" bullet PLAN §3 lists, `invariants.md` §6
  says doctor reports the staging residue, and `AGENTS.md`'s lock paragraph says doctor reports
  both as WARNs and removes neither. `uvm_help`'s `doctor` line and the modulefile are unchanged.
- **README's one supplement hit** (`du -sh` "breaks down cost") is reworded to "gives the cost of
  each architecture", so the census prints `(none)` for README rather than a hit to justify.
- **Census, repository-wide.** The GOAL pattern finds nothing outside `spec/`, `issues/` and
  `ROADMAP.md`. Those are dated records and seeds, and research 05 assigns the `issues/` and
  `ROADMAP.md` hits to `/uvm-roadmap` at landing. The supplement's other hits are unrelated: the
  shell keyword `break` (`bin/uv-manager`, `temp_root.sh`, the burst), "circuit breaker" and
  "staleness" in the factory's own tooling, and the instrument's rank "liveness marker" in
  `tests/lock-race.sh`, which tracks test ranks and decides nothing about the lock.
- **Red, then green.** Red before the change at `FAIL R8: doctor does not name the lock path`. Green
  after. With only the staging loop removed, red at `FAIL R4: doctor does not report the stranded
  copy at …/versions/.incoming.strandA as a WARN`.

**Verify:** the frontmatter gate. It asserts:
- `bash -n` and lint;
- R8: doctor gives rc 0 naming the path, the owner line and "may still be running"; the dry run
  keeps the lock and shows the owner line and the warning; `clean lock --yes` removes it; `current`
  and `versions/9.9.9/uv` are intact; doctor is silent about the lock afterwards;
- R4, stranded copies: plant `versions/.incoming.strandA` and `versions/9.9.9/.incoming.strandB`. Doctor
  gives rc 0 with a `WARN` line naming each path, and both copies are still there afterwards;
- R7's grep finds nothing;
- R9: the GOAL's pattern finds nothing in the four files, the supplement finds nothing in `AGENTS.md`,
  `invariants.md` and the config example, and `uvm help` carries no `UVM_LOCK_STALE` but lists
  `lock`.

It then prints README's supplement hits for the reviewer. Observed against the current tree: red at
`FAIL R8: doctor does not name the lock path`. The R8 segment, stranded-copy clause included, was
proven green on research 05's patched copy plus the doctor sketch above. It was proven red at the
stranded-copy clause without the sketch, so the clause is not vacuous.

**Inspection-only:** every README supplement hit the gate prints (`:547` "breaks down cost" is
unrelated), and R9's sentence-level reading.

**Touches:** `bin/uv-manager`, `README.md`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P5 — Cross-node drive on Lustre and GPFS
**Satisfies:** R4 (c), with R1, R12 and R14 on a real parallel filesystem · **Depends on:** P4

**Goal:** R4 (c) evidence: `tests/lock-race.sh` gains a Slurm mode, and the foreman runs it on a
Lustre cluster (2 nodes, up to 128 tasks) and a GPFS cluster (1 node, up to 64 tasks), at most
30 min each. **This phase has an external wait, so it is two runs.**

**Run A — build, check locally, hand back:**
- [x] `tests/lock-race.sh` / `tests/lock-race-burst.sh` (research 04 Part B):
  - `--launch local|srun` (default `local`, never auto-detected);
  - `--pin VER` (warm 9.9.9 unhooked, then copy the hooked fixture to `VER/`, ranks export
    `UVM_PIN` and `UVM_FIXTURE_VERSION`);
  - `--summary FILE`;
  - `LOCKRACE_SHARED`, required under `srun` (exit 2 otherwise). The driver sets `TMPDIR` to it.
    It is the only source of the shared root: a batch job's environment does not reliably carry
    the scratch variables, so the mode never guesses from them. `srun` missing from `PATH` is
    also exit 2.
  - Ranks re-exec the burst with `LOCKRACE_ROLE=rank` via `srun --ntasks=N --kill-on-bad-exit=0
    --distribution=cyclic --cpu-bind=none --export=ALL`. Local ranks run the same `rank` function
    in a subshell, so the two modes share one rank body.
  - Under `srun` the barrier allows 500 ticks.
  - **A rank runs only the wrapper under test.** A compute node can carry a user-installed `uv`
    on `PATH`. Each rank checks that `command -v uv` is the checkout's `bin/uv` before calling it;
    otherwise it runs nothing and records `nowrapper` as its status.
- [x] The summary is key=value lines:
  - `scenario` (`control`, `held` or `pin`), `ranks`, `bursts`, `nodes` (a count), `wall`;
  - `bash` (the bash `major.minor` that ran the wrapper on the ranks' nodes: the only bash 5
    execution this cycle gets);
  - `rc_hist=0:N[,1:M…]` (a rank with no status counts as `none`, and as non-zero);
  - `stdout_hist=<ver>:N[,…]`, counting only answers of the form `uv <ver> (fixture)` by version,
    and anything else as `other` or `none`, so a uv other than the wrapper cannot pass for it;
  - `uv_resolved=wrapper:N[,other:M]`, and `launch_failures=K/B` (bursts in which `srun` exited
    non-zero; its own messages go to stderr only, since they can name nodes);
  - `installer_entries`, `concurrent_installers`, `concurrent_bursts`;
  - `nested_staging`, `nested_current`, `stray_staging`, `bad_trees`;
  - `plant_intact=B/B` (`0/0` under control), `locks_left_standing`, `progress`;
  - and `launch`, `plant`, `pin`, `total_ranks`, `timeout`, `nonzero_ranks`, `wrong_stdout`.

  **No hostnames, usernames, absolute paths, cluster names, accounts, partitions or dates**: the
  file is committed to a public repository. Never use `--keep` on a cluster.
- [x] `AGENTS.md`'s `tests/` paragraph mentions the mode in one sentence.
- [x] Run the gate. It is expected red **only** at `cluster evidence … not recorded yet`, and every
  check above that line must pass, including the local `held` and `pin` runs and the scrub of their
  summaries. **This red is the external wait, not a failed attempt: do not `--record-attempt` for
  it.** Commit Run A as `[fix] Build lock-simplification P5: Run A — …`, with the phase left
  `in_progress`, and stop.
- [x] Hand back to the foreman: the commit, the local summaries, and this job body. It is generic:
  its `#SBATCH` lines size the job only, and the foreman adds account, partition and QoS, which are
  not committed. The foreman stages this commit's tree (at least `bin/`, `tests/`,
  `.agents/factory/bin/temp_root.sh` and `.agents/factory/fixtures/`, with the `bin/` symlinks
  intact) on a filesystem every node mounts, checks the staged blobs with `git hash-object`
  against `git ls-tree -r` of the commit, and passes `LOCKRACE_REPO` and `LOCKRACE_RUN_DIR`.
  ```bash
  #!/bin/bash
  #SBATCH --nodes=2              # 1 on the GPFS cluster
  #SBATCH --ntasks=128           # 64 on the GPFS cluster
  #SBATCH --ntasks-per-node=64
  #SBATCH --mem=16G
  #SBATCH --time=00:15:00
  # LOCKRACE_REPO     the staged tree of the commit under test, on a filesystem every node mounts
  # LOCKRACE_RUN_DIR  an empty directory on the filesystem under test; the job writes only beneath it
  set -u
  : "${LOCKRACE_REPO:?set LOCKRACE_REPO to the staged tree}"
  : "${LOCKRACE_RUN_DIR:?set LOCKRACE_RUN_DIR to a directory on the filesystem under test}"
  n="${SLURM_NTASKS:?run inside a Slurm allocation}"
  LOCKRACE_SHARED="$LOCKRACE_RUN_DIR/shared"
  export LOCKRACE_SHARED
  mkdir -p "$LOCKRACE_SHARED" && cd "$LOCKRACE_RUN_DIR" || exit 1
  run() {
      s="$1"; shift
      "$LOCKRACE_REPO/tests/lock-race.sh" --launch srun --ranks "$n" --timeout 3 --deadline 15 \
          --summary "$LOCKRACE_RUN_DIR/$s.txt" "$@"
      echo "exit=$?" >> "$LOCKRACE_RUN_DIR/$s.txt"
  }
  run control --plant control --bursts 4
  run held    --plant held    --bursts 8
  run pin     --plant control --pin 6.6.6 --bursts 4
  cat "$LOCKRACE_RUN_DIR/control.txt" "$LOCKRACE_RUN_DIR/held.txt" "$LOCKRACE_RUN_DIR/pin.txt" \
      > "$LOCKRACE_RUN_DIR/summary.txt"
  ```
  `summary.txt` is the evidence file for Run B, and each run's `exit=` line is the driver's exit
  status. The expected runtime is about 2 min; request 15. **The foreman pushes the branch and
  submits on both clusters.**

**Run B — read the evidence, close the phase:**
- [x] Copy the two concatenated summaries the foreman provides to
  `spec/lock-simplification/evidence/lustre.txt` and `spec/lock-simplification/evidence/gpfs.txt`,
  unedited. If either contains anything identifying, stop and ask the foreman. Do not scrub by hand.
- [x] Run the gate. If a scenario failed for an infrastructure reason (no `curl` on compute nodes,
  `LOCKRACE_SHARED` not shared, the burst unreadable from a node), record that in the commit body
  and escalate to the foreman. Do not close the phase on one filesystem silently.
- [x] Mark the phase `done` and commit as `[fix] Build lock-simplification P5: Run B — …`.

**Verify:** the frontmatter gate. It asserts, in order:
- the `--launch` mode exists (the phase's own forward guard);
- `bash -n` and lint;
- `--launch srun` without `LOCKRACE_SHARED` exits 2;
- local `held` 16×2 and `pin` 16×2 runs give `progress=ok` and `stdout_hist=6.6.6:32`;
- the summaries carry no absolute path or this host's name;
- for each of `lustre.txt` and `gpfs.txt`:
  - every required key and all three scenarios are present;
  - every `progress=ok`, every `rc_hist` all zero, and every `stdout_hist` a wanted version;
  - every tree key and `locks_left_standing` zero, and every `plant_intact=B/B`;
  - `concurrent_bursts≥1`, and no absolute path;
- `nodes=2` on Lustre.

Observed before Run A: red at `P5 Run A has not landed`, its own forward guard. Observed after
Run A: every check through the local `held` and `pin` runs and their scrub passes, and the gate is
red at `evidence/lustre.txt not recorded yet`, the external wait.

**Inspection-only:**
- The reviewer reads both evidence files for anything identifying the gate cannot pattern-match.
- R4 (c) is evidence taken on trust (GOAL § Verification limits). NFS is not exercised.

**Touches:** `tests/lock-race.sh`, `tests/lock-race-burst.sh`, `AGENTS.md`,
`spec/lock-simplification/evidence/`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative; the `current_phase`
   pointer is reconciled against them.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
   P5 Run A is the one sanctioned stop on a red gate (see its body).
5. Amend this file freely if reality diverges: regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
