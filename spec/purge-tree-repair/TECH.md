---
slug: purge-tree-repair
title: uv run rehydrates a purged tree, gated by UVM_REPAIR
kind: feature
appetite: big
status: done
branch: feature/purge-tree-repair
base: main
current_phase: done
last_updated: '2026-10-30'
phases:
- id: P1
  name: The lock takes its name (repair lock beside the provisioning lock)
  status: done
  satisfies:
  - R13
  depends_on: []
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\nbash -n bin/uv-manager || { echo \"FAIL: bash -n\" >&2; exit 1;\
    \ }\n.agents/factory/bin/lint.sh >/dev/null || { echo \"FAIL: lint.sh\" >&2; exit\
    \ 1; }\nB=\"$PWD/bin/uv-manager\" .agents/factory/bin/temp_root.sh sh -s <<'KIND'\
    \ || exit 1\nset -u\nh=\"$UVM_SANDBOX/harness.bash\"\ncat > \"$h\" <<'HARNESS'\n\
    #!/bin/bash\n# The two lock functions, extracted by name and sourced, called as\
    \ a repair\n# caller would call them. No repair code is involved.\nset -euo pipefail\n\
    bin=\"$1\" kind=\"$2\" work=\"$3\"\nsed -n -e '/^uvm_unlock() {$/,/^}$/p' -e '/^uvm_acquire_lock()\
    \ {$/,/^}$/p' \"$bin\" > \"$work/section.sh\"\n[[ $(grep -c -e '^uvm_unlock()\
    \ {$' -e '^uvm_acquire_lock() {$' \"$work/section.sh\") == 2 ]] \\\n  || { echo\
    \ \"harness: lock functions not found by name\" >&2; exit 2; }\nnote() { printf\
    \ 'uv-manager: %s\\n' \"$*\" >&2; }\ndie()  { printf 'uv-manager: %s\\n' \"$*\"\
    \ >&2; exit 1; }\nuvm_base=\"$work/base\"; uvm_root=\"$uvm_base/arch\"; mkdir\
    \ -p \"$uvm_root\"\nlock_timeout=2; uvm_lock=\"\"\nnever() { return 1; }\n. \"\
    $work/section.sh\"\ntrap 'uvm_unlock' EXIT\nmkdir \"$uvm_root/.$kind.lock\"\n\
    sleep 10 &\nprintf 'host=%s pid=%s nonce=plant-%s\\n' \"$(uname -n)\" \"$!\" \"\
    $kind\" > \"$uvm_root/.$kind.lock/owner\"\ncp \"$uvm_root/.$kind.lock/owner\"\
    \ \"$work/planted\"\nrc=0; uvm_acquire_lock \"$kind\" fail never || rc=$?\necho\
    \ \"$rc\" > \"$work/acquire.rc\"\n: > \"$work/critical\"\nHARNESS\nw=\"$UVM_SANDBOX/repair\"\
    ; mkdir -p \"$w\"\nif /bin/bash \"$h\" \"$B\" repair \"$w\" 2> \"$w/err\"; then\n\
    \  echo \"FAIL: a repair waiter on a standing .repair.lock returned (rc $(cat\
    \ \"$w/acquire.rc\" 2>/dev/null)) instead of failing at the timeout\" >&2; cat\
    \ \"$w/err\" >&2; exit 1; fi\n[ ! -e \"$w/critical\" ] || { echo \"FAIL: the repair\
    \ waiter ran its critical section\" >&2; exit 1; }\ngrep -q \"timed out after\
    \ 2s waiting for the repair lock at $w/base/arch/.repair.lock\" \"$w/err\" \\\n\
    \  || { echo \"FAIL: the timeout line does not name the repair lock and its path\"\
    \ >&2; cat \"$w/err\" >&2; exit 1; }\ngrep -q 'If nothing is repairing this tree'\
    \ \"$w/err\" \\\n  || { echo \"FAIL: the notice does not say repairing\" >&2;\
    \ cat \"$w/err\" >&2; exit 1; }\ngrep -F -q \"$(cat \"$w/planted\")\" \"$w/err\"\
    \ || { echo \"FAIL: stderr does not carry the planted owner line\" >&2; exit 1;\
    \ }\nif grep -n 'provisioning' \"$w/err\"; then echo \"FAIL: a repair waiter's\
    \ message says provisioning\" >&2; exit 1; fi\nif [ -e \"$w/base/arch/.install.lock\"\
    \ ]; then echo \"FAIL: a repair caller touched .install.lock\" >&2; exit 1; fi\n\
    cmp -s \"$w/base/arch/.repair.lock/owner\" \"$w/planted\" || { echo \"FAIL: the\
    \ plant was disturbed\" >&2; exit 1; }\nw=\"$UVM_SANDBOX/bogus\"; mkdir -p \"\
    $w\"\nif /bin/bash \"$h\" \"$B\" bogus \"$w\" 2> \"$w/err\"; then echo \"FAIL:\
    \ an unknown lock name was accepted\" >&2; exit 1; fi\ngrep -q 'unknown lock:\
    \ bogus' \"$w/err\" || { echo \"FAIL: an unknown lock name did not die naming\
    \ it\" >&2; cat \"$w/err\" >&2; exit 1; }\necho \"lock kind ok\"\nKIND\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'INSTALL' || exit 1\nset -u\nroot=\"$UVM_ROOT/$(uname -m)\"\
    ; lock=\"$root/.install.lock\"; mkdir -p \"$lock\"\nsleep 30 & printf 'host=%s\
    \ pid=%s nonce=plant-install\\n' \"$(uname -n)\" \"$!\" > \"$lock/owner\"\nif\
    \ ! UVM_LOCK_TIMEOUT=2 uv --version > \"$UVM_SANDBOX/out\" 2> \"$UVM_SANDBOX/err\"\
    ; then\n  echo \"FAIL: a provisioning waiter at the timeout did not proceed\"\
    \ >&2; cat \"$UVM_SANDBOX/err\" >&2; exit 1; fi\n[ \"$(cat \"$UVM_SANDBOX/out\"\
    )\" = \"uv 9.9.9 (fixture)\" ] || { echo \"FAIL: stdout [$(cat \"$UVM_SANDBOX/out\"\
    )]\" >&2; exit 1; }\ngrep -q \"waiting for the provisioning lock at $lock\" \"\
    $UVM_SANDBOX/err\" || { echo \"FAIL: provisioning notice changed\" >&2; cat \"\
    $UVM_SANDBOX/err\" >&2; exit 1; }\ngrep -q 'If nothing is provisioning this tree'\
    \ \"$UVM_SANDBOX/err\" || { echo \"FAIL: provisioning notice wording changed\"\
    \ >&2; exit 1; }\nif grep -n 'repair' \"$UVM_SANDBOX/err\"; then echo \"FAIL:\
    \ a provisioning message mentions repair\" >&2; exit 1; fi\n[ -d \"$lock\" ] ||\
    \ { echo \"FAIL: the provisioning plant was removed\" >&2; exit 1; }\n[ ! -e \"\
    $root/.repair.lock\" ] || { echo \"FAIL: provisioning created .repair.lock\" >&2;\
    \ exit 1; }\necho \"provisioning unchanged ok\"\nINSTALL\nfor args in \"--plant\
    \ control --ranks 32 --bursts 2\" \"--plant held --ranks 16 --bursts 2\" \"--plant\
    \ control --pin 6.6.6 --ranks 16 --bursts 2\"; do\n  # shellcheck disable=SC2086\n\
    \  o=$(tests/lock-race.sh $args --quiet) || { echo \"FAIL: tests/lock-race.sh\
    \ $args\" >&2; echo \"$o\" >&2; exit 1; }\n  echo \"$o\" | grep -q '^progress=ok$'\
    \ || { echo \"FAIL: lock-race $args made no progress\" >&2; echo \"$o\" >&2; exit\
    \ 1; }\ndone\nif git grep -n 'uvm_acquire_lock ON_TIMEOUT' -- bin/uv-manager AGENTS.md\
    \ .agents/factory/invariants.md; then\n  echo \"FAIL: the old signature is still\
    \ documented\" >&2; exit 1; fi\necho \"P1 ok\"\n"
- id: P2
  name: The knob repairs a damaged tree once per scope (offline core)
  status: done
  satisfies:
  - R1
  - R2
  - R3
  - R7
  - R8
  - R9
  - R10
  - R13
  - R14
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\ntest -n \"$(git grep -n 'uvm_acquire_lock LOCK ON_TIMEOUT' -- bin/uv-manager)\"\
    \ || { echo \"FAIL: P1 has not landed\" >&2; exit 1; }\nbash -n bin/uv-manager\
    \ || { echo \"FAIL: bash -n\" >&2; exit 1; }\n.agents/factory/bin/lint.sh >/dev/null\
    \ || { echo \"FAIL: lint.sh\" >&2; exit 1; }\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'P2' || exit 1\n# shared by the offline gates; pasted inline\
    \ into each gate in TECH.md\na=$(uname -m)\nfresh() {  # NAME: a new root of its\
    \ own, provisioned from the fixture, with tree (F) planted unless NAME ends in\
    \ .intact\n  UVM_ROOT=\"$UVM_SANDBOX/root.$1\"; export UVM_ROOT; root=\"$UVM_ROOT/$a\"\
    ; o=\"$UVM_SANDBOX/o.$1\"; mkdir -p \"$o\"\n  if ! uv --version > \"$o/warm.out\"\
    \ 2> \"$o/warm.err\"; then echo \"FAIL ($1): provisioning the fixture\" >&2; cat\
    \ \"$o/warm.err\" >&2; exit 1; fi\n  case \"$1\" in *.intact) return 0 ;; esac\n\
    \  sp=\"$root/tools/fx/lib/python3.12/site-packages\"; mkdir -p \"$sp/fx-1.0.dist-info\"\
    \n  : > \"$root/tools/fx/pyvenv.cfg\"; : > \"$root/tools/fx/uv-receipt.toml\"\
    ; mkdir -p \"$root/tools/fx/bin\"; ln -s /bin/sh \"$root/tools/fx/bin/python\"\
    \n  printf 'fx/__init__.py,,\\n' > \"$sp/fx-1.0.dist-info/RECORD\"\n}\nlines()\
    \ { cat \"$@\" 2>/dev/null | grep -c -e 'pip install' -e 'python install'; }\n\
    ranks() {  # N CMD...: N concurrent calls, each with its own out/err/rc under\
    \ $o\n  n=\"$1\"; shift; i=1; pids=''\n  while [ \"$i\" -le \"$n\" ]; do ( \"\
    $@\" > \"$o/out.$i\" 2> \"$o/err.$i\"; echo $? > \"$o/rc.$i\" ) & pids=\"$pids\
    \ $!\"; i=$((i + 1)); done\n  wait $pids\n}\nplantlock() {  # KIND: a live holder\
    \ that never releases\n  mkdir -p \"$root/.$1.lock\"; sleep 60 & printf 'host=%s\
    \ pid=%s nonce=plant-%s\\n' \"$(uname -n)\" \"$!\" \"$1\" > \"$root/.$1.lock/owner\"\
    \n  cp \"$root/.$1.lock/owner\" \"$o/planted\"\n}\nset -u\nfx='uv 9.9.9 (fixture)'\n\
    # R1: knob off. 16 ranks unset, then empty and 0.\nfresh r1\nranks 16 uv --version\n\
    i=1; while [ $i -le 16 ]; do\n  [ \"$(cat \"$o/rc.$i\")\" = 0 ] && [ \"$(cat \"\
    $o/out.$i\")\" = \"$fx\" ] || { echo \"FAIL R1: rank $i rc $(cat \"$o/rc.$i\"\
    ) stdout [$(cat \"$o/out.$i\")]\" >&2; cat \"$o/err.$i\" >&2; exit 1; }\n  i=$((i\
    \ + 1)); done\nfor v in '' 0; do UVM_REPAIR=\"$v\" uv --version >> \"$o/out.v\"\
    \ 2>> \"$o/err.v\" || { echo \"FAIL R1: UVM_REPAIR=[$v] exited non-zero\" >&2;\
    \ exit 1; }; done\nn=$(lines \"$o\"/out.* \"$o\"/err.*); [ \"$n\" -eq 0 ] || {\
    \ echo \"FAIL R1: $n repair lines with the knob off\" >&2; exit 1; }\n[ \"$(ls\
    \ -A \"$root\" | tr '\\n' ' ')\" = \"bin cache current python tools versions \"\
    \ ] || { echo \"FAIL R1: root holds [$(ls -A \"$root\" | tr '\\n' ' ')]\" >&2;\
    \ exit 1; }\n# R2: a planted failed outcome is honored (red on main: nothing reads\
    \ an outcome).\nfresh r2f; mkdir -p \"$root/.repair\"; echo 'planted reason r2'\
    \ > \"$root/.repair/value-t.failed\"\nif UVM_REPAIR=t UVM_FIXTURE_MARK=\"$o/mark\"\
    \ uv --version > \"$o/out\" 2> \"$o/err\"; then\n  echo \"FAIL R2: a failed outcome\
    \ for the scope did not fail the call (stdout [$(cat \"$o/out\")])\" >&2; exit\
    \ 1; fi\ngrep -q 'planted reason r2' \"$o/err\" || { echo \"FAIL R2: stderr lacks\
    \ the planted reason\" >&2; cat \"$o/err\" >&2; exit 1; }\n[ ! -e \"$o/mark\"\
    \ ] && [ ! -s \"$o/out\" ] || { echo \"FAIL R2: the command ran under a failed\
    \ outcome\" >&2; exit 1; }\n[ \"$(lines \"$o/out\" \"$o/err\")\" -eq 0 ] && [\
    \ ! -e \"$root/.repair.lock\" ] || { echo \"FAIL R2: repaired or locked under\
    \ a failed outcome\" >&2; exit 1; }\nfresh r2ok; mkdir -p \"$root/.repair\"; :\
    \ > \"$root/.repair/value-t.ok\"\nUVM_REPAIR=t uv --version > \"$o/out\" 2> \"\
    $o/err\" || { echo \"FAIL R2: repaired outcome, call failed\" >&2; cat \"$o/err\"\
    \ >&2; exit 1; }\n[ \"$(cat \"$o/out\")\" = \"$fx\" ] && [ \"$(lines \"$o/out\"\
    \ \"$o/err\")\" -eq 0 ] && [ ! -e \"$root/.repair.lock\" ] || { echo \"FAIL R2:\
    \ a repaired outcome did not short-circuit\" >&2; exit 1; }\n# R2's pair, R3's\
    \ fixture halves: no outcome repairs once and records; an intact tree records\
    \ with no repair.\nfresh r2none\nUVM_REPAIR=t uv --version > \"$o/out\" 2> \"\
    $o/err\" || { echo \"FAIL R3: knob set on tree F exited non-zero\" >&2; cat \"\
    $o/err\" >&2; exit 1; }\n[ \"$(lines \"$o/err\")\" -eq 1 ] && [ \"$(lines \"$o/out\"\
    )\" -eq 0 ] && [ -e \"$root/.repair/value-t.ok\" ] || { echo \"FAIL R3: expected\
    \ one repair line on stderr and a repaired outcome\" >&2; cat \"$o/err\" >&2;\
    \ exit 1; }\nfresh r3.intact\nUVM_REPAIR=t uv --version > \"$o/out\" 2> \"$o/err\"\
    \ || { echo \"FAIL R3: intact tree exited non-zero\" >&2; exit 1; }\n[ \"$(lines\
    \ \"$o/out\" \"$o/err\")\" -eq 0 ] && [ -e \"$root/.repair/value-t.ok\" ] || {\
    \ echo \"FAIL R3: intact tree repaired or recorded nothing\" >&2; cat \"$o/err\"\
    \ >&2; exit 1; }\nfresh r3pin\nUVM_PIN=9.9.9 UVM_FIXTURE_VERSION=10.0.0 UVM_REPAIR=t\
    \ uv --version > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL R3: pinned repair exited\
    \ non-zero\" >&2; exit 1; }\n[ \"$(readlink \"$root/current\")\" = versions/9.9.9\
    \ ] && [ ! -e \"$root/versions/10.0.0\" ] || { echo \"FAIL R3: repair moved current\
    \ to $(readlink \"$root/current\")\" >&2; exit 1; }\n# R7: 16 ranks of one Slurm\
    \ job, the repair held 4 s; then the same failing.\nfresh r7\nt0=$(date +%s);\
    \ ranks 16 env SLURM_JOB_ID=100 UVM_REPAIR=1 UVM_FIXTURE_REPAIR_SLEEP=4 uv --version;\
    \ t=$(( $(date +%s) - t0 ))\nn=$(lines \"$o\"/out.* \"$o\"/err.*); [ \"$n\" -eq\
    \ 1 ] || { echo \"FAIL R7: $n repair lines across 16 ranks, expected 1\" >&2;\
    \ exit 1; }\ni=1; while [ $i -le 16 ]; do [ \"$(cat \"$o/rc.$i\")\" = 0 ] && [\
    \ \"$(cat \"$o/out.$i\")\" = \"$fx\" ] || { echo \"FAIL R7: rank $i rc $(cat \"\
    $o/rc.$i\")\" >&2; cat \"$o/err.$i\" >&2; exit 1; }; i=$((i + 1)); done\n[ \"\
    $(ls -A \"$root/.repair\")\" = job-100.ok ] && [ ! -e \"$root/.repair.lock\" ]\
    \ || { echo \"FAIL R7: outcomes [$(ls -A \"$root/.repair\")] or a lock left\"\
    \ >&2; exit 1; }\n[ \"$t\" -le 9 ] || { echo \"FAIL R7: 16 ranks took ${t}s for\
    \ a 4s repair\" >&2; exit 1; }\nfresh r7f\nt0=$(date +%s); ranks 16 env SLURM_JOB_ID=100\
    \ UVM_REPAIR=1 UVM_FIXTURE_REPAIR_SLEEP=4 UVM_FIXTURE_REPAIR_EXIT=1 uv --version;\
    \ t=$(( $(date +%s) - t0 ))\nn=$(lines \"$o\"/out.* \"$o\"/err.*); [ \"$n\" -eq\
    \ 1 ] || { echo \"FAIL R9d: $n repair lines on a failing repair, expected 1\"\
    \ >&2; exit 1; }\ni=1; while [ $i -le 16 ]; do\n  [ \"$(cat \"$o/rc.$i\")\" !=\
    \ 0 ] && [ ! -s \"$o/out.$i\" ] || { echo \"FAIL R9d: rank $i ran its command\"\
    \ >&2; exit 1; }\n  grep -q 'the repair for Slurm job 100 failed: the tool environment\
    \ repair failed' \"$o/err.$i\" || { echo \"FAIL R9d: rank $i lacks the holder's\
    \ reason\" >&2; cat \"$o/err.$i\" >&2; exit 1; }\n  i=$((i + 1)); done\n[ \"$t\"\
    \ -le 8 ] || { echo \"FAIL R9d: waiters took ${t}s to fail after a 4s repair\"\
    \ >&2; exit 1; }\n[ -e \"$root/.repair/job-100.failed\" ] && [ ! -e \"$root/.repair.lock\"\
    \ ] || { echo \"FAIL R9d: no failed outcome, or a lock left\" >&2; exit 1; }\n\
    # R8: the command's own status and stdout; repair output on stderr.\nfresh r8\n\
    UVM_REPAIR=t UVM_FIXTURE_EXIT=7 uv run app > \"$o/out\" 2> \"$o/err\"; rc=$?\n\
    [ \"$rc\" = 7 ] && [ \"$(cat \"$o/out\")\" = 'uv-fixture: run app' ] && [ \"$(lines\
    \ \"$o/err\")\" -eq 1 ] || { echo \"FAIL R8: rc $rc stdout [$(cat \"$o/out\")]\"\
    \ >&2; cat \"$o/err\" >&2; exit 1; }\n# R9 (a): the repair command fails; a second\
    \ call fails with the same reason and no repair.\nfresh r9a\nif UVM_REPAIR=a UVM_FIXTURE_REPAIR_EXIT=1\
    \ UVM_FIXTURE_MARK=\"$o/mark\" uv run app > \"$o/out\" 2> \"$o/err\"; then echo\
    \ \"FAIL R9a: exited 0\" >&2; exit 1; fi\ngrep -q '^uv-manager: the repair for\
    \ UVM_REPAIR=a failed: the tool environment repair failed' \"$o/err\" && [ ! -e\
    \ \"$o/mark\" ] && [ -e \"$root/.repair/value-a.failed\" ] \\\n  || { echo \"\
    FAIL R9a: reason, marker or failed outcome\" >&2; cat \"$o/err\" >&2; exit 1;\
    \ }\nif UVM_REPAIR=a UVM_FIXTURE_MARK=\"$o/mark\" uv run app > \"$o/out2\" 2>\
    \ \"$o/err2\"; then echo \"FAIL R9a: the second call exited 0\" >&2; exit 1; fi\n\
    grep -q 'the tool environment repair failed' \"$o/err2\" && [ \"$(lines \"$o/out2\"\
    \ \"$o/err2\")\" -eq 0 ] && [ ! -e \"$o/mark\" ] || { echo \"FAIL R9a: the second\
    \ call retried or ran\" >&2; cat \"$o/err2\" >&2; exit 1; }\n# R9 (b) and R13\
    \ (d): a repair lock that never releases.\nfresh r9b; plantlock repair\nt0=$(date\
    \ +%s)\nif UVM_LOCK_TIMEOUT=3 UVM_REPAIR=1 UVM_FIXTURE_MARK=\"$o/mark\" uv --version\
    \ > \"$o/out\" 2> \"$o/err\"; then echo \"FAIL R9b: exited 0 past a held repair\
    \ lock\" >&2; exit 1; fi\nt=$(( $(date +%s) - t0 ))\n[ \"$t\" -ge 3 ] && [ \"\
    $t\" -le 6 ] || { echo \"FAIL R9b: failed after ${t}s against a 3s timeout\" >&2;\
    \ exit 1; }\ngrep -q \"timed out after 3s waiting for the repair lock at $root/.repair.lock\"\
    \ \"$o/err\" && grep -F -q \"$(cat \"$o/planted\")\" \"$o/err\" \\\n  || { echo\
    \ \"FAIL R9b: stderr does not name the lock and its owner line\" >&2; cat \"$o/err\"\
    \ >&2; exit 1; }\n[ ! -e \"$o/mark\" ] && cmp -s \"$root/.repair.lock/owner\"\
    \ \"$o/planted\" || { echo \"FAIL R9b: command ran or plant disturbed\" >&2; exit\
    \ 1; }\n[ \"$(grep -c 'repair lock' \"$o/err\")\" -ge 2 ] || { echo \"FAIL R13d:\
    \ notice and timeout should both say repair lock\" >&2; cat \"$o/err\" >&2; exit\
    \ 1; }\nif grep -n 'provisioning' \"$o/err\"; then echo \"FAIL R13d: a repair\
    \ waiter's message says provisioning\" >&2; exit 1; fi\n# R10: values and scopes.\n\
    fresh r10z\nUVM_REPAIR=0 uv --version > \"$o/out\" 2> \"$o/err\" || exit 1\n[\
    \ \"$(lines \"$o/out\" \"$o/err\")\" -eq 0 ] && [ ! -e \"$root/.repair\" ] &&\
    \ [ ! -e \"$root/.repair.lock\" ] || { echo \"FAIL R10: UVM_REPAIR=0 repaired\
    \ or recorded\" >&2; exit 1; }\nfresh r10j\nfor j in 100 100 101; do SLURM_JOB_ID=$j\
    \ UVM_REPAIR=1 uv --version >> \"$o/out\" 2>> \"$o/err\" || { echo \"FAIL R10:\
    \ job $j exited non-zero\" >&2; exit 1; }; done\nn=$(lines \"$o/out\" \"$o/err\"\
    ); [ \"$n\" -eq 2 ] || { echo \"FAIL R10: jobs 100,100,101 gave $n repair lines,\
    \ expected 2\" >&2; exit 1; }\nfresh r10a\nfor j in 301 302; do env SLURM_ARRAY_JOB_ID=300\
    \ SLURM_ARRAY_TASK_ID=$j SLURM_JOB_ID=$j UVM_REPAIR=1 uv --version >> \"$o/out\"\
    \ 2>> \"$o/err\" || { echo \"FAIL R10: array task $j exited non-zero\" >&2; exit\
    \ 1; }; done\nn=$(lines \"$o/out\" \"$o/err\"); [ \"$n\" -eq 1 ] && [ \"$(ls -A\
    \ \"$root/.repair\")\" = job-300.ok ] || { echo \"FAIL R10: two tasks of array\
    \ 300 gave $n repair lines and [$(ls -A \"$root/.repair\")], expected 1 and job-300.ok\"\
    \ >&2; exit 1; }\nenv SLURM_CLUSTER_NAME=cx SLURM_JOB_ID=300 UVM_REPAIR=1 uv --version\
    \ >> \"$o/out\" 2>> \"$o/err\" || exit 1\n[ -e \"$root/.repair/job-cx-300.ok\"\
    \ ] && [ \"$(lines \"$o/out\" \"$o/err\")\" -eq 2 ] || { echo \"FAIL R10: the\
    \ cluster name does not namespace the job key\" >&2; exit 1; }\nfresh r10v\nfor\
    \ v in a a b; do env -u SLURM_JOB_ID UVM_REPAIR=$v uv --version >> \"$o/out\"\
    \ 2>> \"$o/err\" || { echo \"FAIL R10: value $v exited non-zero\" >&2; exit 1;\
    \ }; done\nn=$(lines \"$o/out\" \"$o/err\"); [ \"$n\" -eq 2 ] || { echo \"FAIL\
    \ R10: values a,a,b gave $n repair lines, expected 2\" >&2; exit 1; }\n# R10,\
    \ array: a repaired record is the array's, a failed one the task's. Tasks 401\
    \ and 402 fail in turn,\n# each trying for itself; 403 repairs; 404 rides on the\
    \ array's record.\nfresh r10af\nfor j in 401 402; do\n  if env SLURM_ARRAY_JOB_ID=400\
    \ SLURM_ARRAY_TASK_ID=$j SLURM_JOB_ID=$j UVM_REPAIR=1 UVM_FIXTURE_REPAIR_EXIT=1\
    \ uv --version >> \"$o/out\" 2> \"$o/err.$j\"; then echo \"FAIL R10: failing array\
    \ task $j exited 0\" >&2; exit 1; fi\n  grep -q \"the repair for Slurm job $j\
    \ failed: the tool environment repair failed\" \"$o/err.$j\" && grep -q \"array's\
    \ next task checks again\" \"$o/err.$j\" \\\n    || { echo \"FAIL R10: task $j's\
    \ failure does not name the task and say the next task checks again\" >&2; cat\
    \ \"$o/err.$j\" >&2; exit 1; }\ndone\nfor j in 403 404; do env SLURM_ARRAY_JOB_ID=400\
    \ SLURM_ARRAY_TASK_ID=$j SLURM_JOB_ID=$j UVM_REPAIR=1 uv --version >> \"$o/out\"\
    \ 2> \"$o/err.$j\" || { echo \"FAIL R10: array task $j exited non-zero after other\
    \ tasks failed\" >&2; cat \"$o/err.$j\" >&2; exit 1; }; done\nn=$(lines \"$o/out\"\
    \ \"$o\"/err.*); [ \"$n\" -eq 3 ] && [ \"$(LC_ALL=C ls -A \"$root/.repair\" |\
    \ tr '\\n' ' ')\" = \"job-400.ok job-401.failed job-402.failed \" ] \\\n  || {\
    \ echo \"FAIL R10: array 400 gave $n repair lines and [$(LC_ALL=C ls -A \"$root/.repair\"\
    \ | tr '\\n' ' ')], expected 3 and job-400.ok job-401.failed job-402.failed\"\
    \ >&2; exit 1; }\n# R7 across an array: 16 ranks, two tasks of array 500 alternating.\
    \ Repairing, one repair serves both\n# tasks; failing, each task's ranks fail\
    \ on their own holder's record, so exactly two repairs.\nfresh r7a\ni=1; pids='';\
    \ while [ $i -le 16 ]; do\n  ( env SLURM_ARRAY_JOB_ID=500 SLURM_ARRAY_TASK_ID=$((1\
    \ + i % 2)) SLURM_JOB_ID=$((501 + i % 2)) UVM_REPAIR=1 UVM_FIXTURE_REPAIR_SLEEP=2\
    \ uv --version > \"$o/out.$i\" 2> \"$o/err.$i\"; echo $? > \"$o/rc.$i\" ) & pids=\"\
    $pids $!\"; i=$((i + 1)); done\nwait $pids\nn=$(lines \"$o\"/out.* \"$o\"/err.*);\
    \ [ \"$n\" -eq 1 ] || { echo \"FAIL R7: $n repair lines across two tasks of one\
    \ array, expected 1\" >&2; exit 1; }\ni=1; while [ $i -le 16 ]; do [ \"$(cat \"\
    $o/rc.$i\")\" = 0 ] && [ \"$(cat \"$o/out.$i\")\" = \"$fx\" ] || { echo \"FAIL\
    \ R7: array rank $i rc $(cat \"$o/rc.$i\")\" >&2; cat \"$o/err.$i\" >&2; exit\
    \ 1; }; i=$((i + 1)); done\n[ \"$(ls -A \"$root/.repair\")\" = job-500.ok ] &&\
    \ [ ! -e \"$root/.repair.lock\" ] || { echo \"FAIL R7: array outcomes [$(ls -A\
    \ \"$root/.repair\")] or a lock left\" >&2; exit 1; }\nfresh r7af\ni=1; pids='';\
    \ while [ $i -le 16 ]; do\n  ( env SLURM_ARRAY_JOB_ID=500 SLURM_ARRAY_TASK_ID=$((1\
    \ + i % 2)) SLURM_JOB_ID=$((501 + i % 2)) UVM_REPAIR=1 UVM_FIXTURE_REPAIR_SLEEP=2\
    \ UVM_FIXTURE_REPAIR_EXIT=1 uv --version > \"$o/out.$i\" 2> \"$o/err.$i\"; echo\
    \ $? > \"$o/rc.$i\" ) & pids=\"$pids $!\"; i=$((i + 1)); done\nwait $pids\nn=$(lines\
    \ \"$o\"/out.* \"$o\"/err.*); [ \"$n\" -eq 2 ] || { echo \"FAIL R9: $n repair\
    \ lines across two failing tasks of one array, expected 2\" >&2; exit 1; }\ni=1;\
    \ while [ $i -le 16 ]; do\n  j=$((501 + i % 2))\n  [ \"$(cat \"$o/rc.$i\")\" !=\
    \ 0 ] && grep -q \"the repair for Slurm job $j failed\" \"$o/err.$i\" || { echo\
    \ \"FAIL R9: array rank $i (task $j) did not fail with its task's reason\" >&2;\
    \ cat \"$o/err.$i\" >&2; exit 1; }\n  i=$((i + 1)); done\n[ \"$(LC_ALL=C ls -A\
    \ \"$root/.repair\" | tr '\\n' ' ')\" = \"job-501.failed job-502.failed \" ] &&\
    \ [ ! -e \"$root/.repair.lock\" ] || { echo \"FAIL R9: array outcomes [$(LC_ALL=C\
    \ ls -A \"$root/.repair\" | tr '\\n' ' ')] or a lock left\" >&2; exit 1; }\n#\
    \ R10, array: the task id marks an array task, so the array's first task, whose\
    \ job id is the\n# array's, gets the array's wording, and its failure does not\
    \ stop the next task.\nfresh r10first\nif env SLURM_ARRAY_JOB_ID=600 SLURM_ARRAY_TASK_ID=0\
    \ SLURM_JOB_ID=600 UVM_REPAIR=1 UVM_FIXTURE_REPAIR_EXIT=1 uv --version > \"$o/out\"\
    \ 2> \"$o/err.600\"; then echo \"FAIL R10: the failing first task exited 0\" >&2;\
    \ exit 1; fi\ngrep -q \"array's next task checks again\" \"$o/err.600\" || { echo\
    \ \"FAIL R10: the array's first task gets the plain-job wording\" >&2; cat \"\
    $o/err.600\" >&2; exit 1; }\nenv SLURM_ARRAY_JOB_ID=600 SLURM_ARRAY_TASK_ID=1\
    \ SLURM_JOB_ID=601 UVM_REPAIR=1 uv --version >> \"$o/out\" 2> \"$o/err.601\" &&\
    \ [ \"$(LC_ALL=C ls -A \"$root/.repair\" | tr '\\n' ' ')\" = \"job-600.failed\
    \ job-600.ok \" ] \\\n  || { echo \"FAIL R10: after the first task failed, task\
    \ 601 did not repair under the array's id\" >&2; cat \"$o/err.601\" >&2; exit\
    \ 1; }\n# R10, values: the record name is injective. Four values that differ only\
    \ outside [a-z0-9.-] are four scopes.\nfresh r10enc\nfor v in 'run/1' 'run 1'\
    \ 'run_1' 'run:1' 'run/1' 'run 1' 'run_1' 'run:1'; do env -u SLURM_JOB_ID UVM_REPAIR=\"\
    $v\" uv --version >> \"$o/out\" 2>> \"$o/err\" || { echo \"FAIL R10: value [$v]\
    \ exited non-zero\" >&2; exit 1; }; done\nn=$(lines \"$o/out\" \"$o/err\"); [\
    \ \"$n\" -eq 4 ] && [ \"$(LC_ALL=C ls -A \"$root/.repair\" | tr '\\n' ' ')\" =\
    \ \"value-run_201.ok value-run_2F1.ok value-run_3A1.ok value-run_5F1.ok \" ] \\\
    \n  || { echo \"FAIL R10: run/1, run 1, run_1, run:1 twice each gave $n repair\
    \ lines and [$(LC_ALL=C ls -A \"$root/.repair\" | tr '\\n' ' ')], expected 4 records\
    \ and 4 repairs\" >&2; exit 1; }\nenv -u SLURM_JOB_ID LC_ALL=en_US.UTF-8 UVM_REPAIR=\"\
    $(printf 'r\\303\\251')\" uv --version > /dev/null 2>> \"$o/err\" && [ -e \"$root/.repair/value-r_C3_A9.ok\"\
    \ ] \\\n  || { echo \"FAIL R10: a multibyte value under a UTF-8 locale is not\
    \ encoded byte by byte\" >&2; ls -A \"$root/.repair\" >&2; exit 1; }\nv=$(printf\
    \ '%066d' 0 | tr 0 /)\nif env -u SLURM_JOB_ID UVM_REPAIR=\"$v\" uv --version >\
    \ /dev/null 2> \"$o/err.cap\"; then echo \"FAIL R10: a value whose encoded name\
    \ passes 200 bytes was accepted\" >&2; exit 1; fi\ngrep -q 'its record name would\
    \ be 204 bytes, and the limit is 200' \"$o/err.cap\" || { echo \"FAIL R10: the\
    \ cap does not apply to the encoded name\" >&2; cat \"$o/err.cap\" >&2; exit 1;\
    \ }\n# C3-F2: an uppercase letter is escaped, so it costs three bytes, and two\
    \ values differing only in\n# case are two records and two repairs, on a filesystem\
    \ that ignores case too (macOS's default).\nv=$(printf '%066d' 0 | tr 0 R)\nif\
    \ env -u SLURM_JOB_ID UVM_REPAIR=\"$v\" uv --version > /dev/null 2> \"$o/err.cap\"\
    ; then echo \"FAIL C3-F2: 66 uppercase letters were accepted\" >&2; exit 1; fi\n\
    grep -q 'its record name would be 204 bytes, and the limit is 200' \"$o/err.cap\"\
    \ || { echo \"FAIL C3-F2: an uppercase letter does not cost three bytes\" >&2;\
    \ cat \"$o/err.cap\" >&2; exit 1; }\nfresh r10case\nenv -u SLURM_JOB_ID UVM_REPAIR=Run1\
    \ uv --version >> \"$o/out\" 2>> \"$o/err\" && env -u SLURM_JOB_ID UVM_REPAIR=run1\
    \ uv --version >> \"$o/out\" 2>> \"$o/err\" \\\n  || { echo \"FAIL C3-F2: Run1\
    \ then run1 exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\nn=$(lines \"\
    $o/out\" \"$o/err\"); [ \"$n\" -eq 2 ] && [ \"$(LC_ALL=C ls -A \"$root/.repair\"\
    \ | tr '\\n' ' ')\" = \"value-_52un1.ok value-run1.ok \" ] \\\n  || { echo \"\
    FAIL C3-F2: Run1 then run1 gave $n repair lines and [$(LC_ALL=C ls -A \"$root/.repair\"\
    \ | tr '\\n' ' ')], expected 2 records and 2 repairs\" >&2; exit 1; }\nfresh r10dec\n\
    if env -u SLURM_JOB_ID UVM_REPAIR='Run/1 x_y' UVM_FIXTURE_REPAIR_EXIT=1 uv --version\
    \ > /dev/null 2>&1; then echo \"FAIL R10: setup, the failing repair exited 0\"\
    \ >&2; exit 1; fi\nuvm doctor > \"$o/doc\" 2>&1\n[ -e \"$root/.repair/value-_52un_2F1_20x_5Fy.failed\"\
    \ ] && grep -q '^WARN  repair failed for UVM_REPAIR=Run/1 x_y: the tool environment\
    \ repair failed' \"$o/doc\" \\\n  || { echo \"FAIL R10: the record is not value-_52un_2F1_20x_5Fy,\
    \ or doctor does not decode the value from its name\" >&2; ls -A \"$root/.repair\"\
    \ >&2; cat \"$o/doc\" >&2; exit 1; }\n# R13 (a): a standing provisioning lock\
    \ does not hold up a repair.\nfresh r13a; plantlock install\nt0=$(date +%s); UVM_LOCK_TIMEOUT=10\
    \ UVM_REPAIR=1 uv --version > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL R13a:\
    \ exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\nt=$(( $(date +%s) - t0\
    \ ))\n[ \"$t\" -lt 5 ] && [ \"$(lines \"$o/err\")\" -eq 1 ] && cmp -s \"$root/.install.lock/owner\"\
    \ \"$o/planted\" || { echo \"FAIL R13a: ${t}s, $(lines \"$o/err\") repair lines,\
    \ or plant disturbed\" >&2; exit 1; }\n# R13 (b): a standing repair lock does\
    \ not hold up provisioning.\nUVM_ROOT=\"$UVM_SANDBOX/root.r13b\"; export UVM_ROOT;\
    \ root=\"$UVM_ROOT/$a\"; o=\"$UVM_SANDBOX/o.r13b\"; mkdir -p \"$o\" \"$root\"\
    ; plantlock repair\nt0=$(date +%s); UVM_LOCK_TIMEOUT=10 uv --version > \"$o/out\"\
    \ 2> \"$o/err\" || { echo \"FAIL R13b: exited non-zero\" >&2; exit 1; }\nt=$((\
    \ $(date +%s) - t0 ))\n[ \"$t\" -lt 5 ] && [ \"$(cat \"$o/out\")\" = \"$fx\" ]\
    \ || { echo \"FAIL R13b: ${t}s stdout [$(cat \"$o/out\")]\" >&2; exit 1; }\necho\
    \ \"P2 drives ok\"\nP2\n# The encoder, extracted by name, walks bytes and hands\
    \ the caller's locale back, set or unset.\nf=\"$(mktemp -d \"${TMPDIR:-/tmp}/p2enc.XXXXXX\"\
    )/enc.sh\"; sed -n '/^uvm_repair_encode() {$/,/^}$/p' bin/uv-manager > \"$f\"\n\
    [ \"$(grep -c '^uvm_repair_encode() {$' \"$f\")\" = 1 ] || { echo \"FAIL R10:\
    \ uvm_repair_encode not found by name\" >&2; exit 1; }\nLC_ALL=en_US.UTF-8 /bin/bash\
    \ -c '. \"$1\"; uvm_repair_encode \"$(printf \"Ar\\303\\251 _Z\")\"; [ \"$uvm_repair_name\"\
    \ = _41r_C3_A9_20_5F_5A ] && [ \"$LC_ALL\" = en_US.UTF-8 ]' sh \"$f\" \\\n  ||\
    \ { echo \"FAIL R10: the encoder under LC_ALL=en_US.UTF-8 (bytes, or LC_ALL not\
    \ restored)\" >&2; exit 1; }\nenv -u LC_ALL LANG=en_US.UTF-8 /bin/bash -c '. \"\
    $1\"; uvm_repair_encode \"$(printf \"r\\303\\251\")\"; [ \"$uvm_repair_name\"\
    \ = r_C3_A9 ] && [ -z \"${LC_ALL+set}\" ]' sh \"$f\" \\\n  || { echo \"FAIL R10:\
    \ the encoder with LC_ALL unset (bytes, or LC_ALL left set)\" >&2; exit 1; }\n\
    n=$(.agents/factory/bin/temp_root.sh uvm help | grep -c UVM_REPAIR); [ \"$n\"\
    \ -ge 1 ] || { echo \"FAIL R10: uvm help does not document UVM_REPAIR\" >&2; exit\
    \ 1; }\n# R10 and R14, per surface: the help, the conf example and the modulefile\
    \ carry the knob, its values,\n# its scope and the length limit, and point to\
    \ README.md; README.md carries the limit, the array\n# task's mark and the queue's\
    \ arithmetic.\n.agents/factory/bin/temp_root.sh uvm help > \"${TMPDIR:-/tmp}/p2help.$$\"\
    \nfor f in \"${TMPDIR:-/tmp}/p2help.$$\" etc/uv-manager.conf.example share/modulefiles/uv/main.lua;\
    \ do\n  for w in UVM_REPAIR 'empty' 'Slurm job' 'per-run|value of its own' '194\
    \ bytes' 'uppercase' 'README'; do\n    grep -E -q \"$w\" \"$f\" || { echo \"FAIL\
    \ R14: $f does not carry [$w]\" >&2; exit 1; }\n  done\ndone\nfor w in '194' 'uppercase'\
    \ '`Run1` and' 'SLURM_ARRAY_TASK_ID' 'UVM_LOCK_TIMEOUT / w + 1'; do grep -F -q\
    \ \"$w\" README.md || { echo \"FAIL R14: README.md does not carry [$w]\" >&2;\
    \ exit 1; }; done\nn=$(git grep -l UVM_REPAIR -- bin/uv-manager README.md etc/uv-manager.conf.example\
    \ share/modulefiles/uv/main.lua AGENTS.md .agents/factory/invariants.md | wc -l\
    \ | tr -d ' ')\n[ \"$n\" -eq 6 ] || { echo \"FAIL R14 (same commit): UVM_REPAIR\
    \ is documented in $n of the six surfaces\" >&2; exit 1; }\necho \"P2 ok\""
- id: P3
  name: The interpreter arm, the orphan refusal, and real uv
  status: done
  satisfies:
  - R3
  - R4
  - R5
  - R6
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\ngrep -q '^uvm_repair()' bin/uv-manager || { echo \"FAIL: P2 has\
    \ not landed\" >&2; exit 1; }\nbash -n bin/uv-manager || { echo \"FAIL: bash -n\"\
    \ >&2; exit 1; }\n.agents/factory/bin/lint.sh >/dev/null || { echo \"FAIL: lint.sh\"\
    \ >&2; exit 1; }\n.agents/factory/bin/temp_root.sh --offline sh -s <<'P3OFF' ||\
    \ exit 1\n# shared by the offline gates; pasted inline into each gate in TECH.md\n\
    a=$(uname -m)\nfresh() {  # NAME: a new root of its own, provisioned from the\
    \ fixture, with tree (F) planted unless NAME ends in .intact\n  UVM_ROOT=\"$UVM_SANDBOX/root.$1\"\
    ; export UVM_ROOT; root=\"$UVM_ROOT/$a\"; o=\"$UVM_SANDBOX/o.$1\"; mkdir -p \"\
    $o\"\n  if ! uv --version > \"$o/warm.out\" 2> \"$o/warm.err\"; then echo \"FAIL\
    \ ($1): provisioning the fixture\" >&2; cat \"$o/warm.err\" >&2; exit 1; fi\n\
    \  case \"$1\" in *.intact) return 0 ;; esac\n  sp=\"$root/tools/fx/lib/python3.12/site-packages\"\
    ; mkdir -p \"$sp/fx-1.0.dist-info\"\n  : > \"$root/tools/fx/pyvenv.cfg\"; : >\
    \ \"$root/tools/fx/uv-receipt.toml\"; mkdir -p \"$root/tools/fx/bin\"; ln -s /bin/sh\
    \ \"$root/tools/fx/bin/python\"\n  printf 'fx/__init__.py,,\\n' > \"$sp/fx-1.0.dist-info/RECORD\"\
    \n}\nlines() { cat \"$@\" 2>/dev/null | grep -c -e 'pip install' -e 'python install';\
    \ }\nranks() {  # N CMD...: N concurrent calls, each with its own out/err/rc under\
    \ $o\n  n=\"$1\"; shift; i=1; pids=''\n  while [ \"$i\" -le \"$n\" ]; do ( \"\
    $@\" > \"$o/out.$i\" 2> \"$o/err.$i\"; echo $? > \"$o/rc.$i\" ) & pids=\"$pids\
    \ $!\"; i=$((i + 1)); done\n  wait $pids\n}\nplantlock() {  # KIND: a live holder\
    \ that never releases\n  mkdir -p \"$root/.$1.lock\"; sleep 60 & printf 'host=%s\
    \ pid=%s nonce=plant-%s\\n' \"$(uname -n)\" \"$!\" \"$1\" > \"$root/.$1.lock/owner\"\
    \n  cp \"$root/.$1.lock/owner\" \"$o/planted\"\n}\nset -u\npystub() {  # EXIT:\
    \ a managed interpreter whose probe exits EXIT\n  mkdir -p \"$root/python/cpython-3.12.0-fixture/bin\"\
    \n  printf '#!/bin/sh\\nexit %s\\n' \"$1\" > \"$root/python/cpython-3.12.0-fixture/bin/python3\"\
    ; chmod +x \"$root/python/cpython-3.12.0-fixture/bin/python3\"\n}\npylines() {\
    \ cat \"$@\" 2>/dev/null | grep -c 'python install'; }\n# R6: no managed interpreter;\
    \ one that passes the probe; one that fails it.\nfresh r6none.intact; UVM_REPAIR=t\
    \ uv --version > \"$o/out\" 2> \"$o/err\" || exit 1\n[ \"$(pylines \"$o/out\"\
    \ \"$o/err\")\" -eq 0 ] || { echo \"FAIL R6: python repair with no managed interpreter\"\
    \ >&2; exit 1; }\nfresh r6pass.intact; pystub 0; UVM_REPAIR=t uv --version > \"\
    $o/out\" 2> \"$o/err\" || exit 1\n[ \"$(pylines \"$o/out\" \"$o/err\")\" -eq 0\
    \ ] || { echo \"FAIL R6: python repair on an interpreter that passes the probe\"\
    \ >&2; exit 1; }\nfresh r6fail.intact; pystub 1\nUVM_REPAIR=t uv --version > \"\
    $o/out\" 2> \"$o/err\" || { echo \"FAIL R6: knob on a damaged interpreter exited\
    \ non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\n[ \"$(pylines \"$o/err\")\" -eq\
    \ 1 ] && [ \"$(lines \"$o/err\")\" -eq 1 ] && [ -e \"$root/.repair/value-t.ok\"\
    \ ] || { echo \"FAIL R6: expected exactly one python repair line and nothing else\"\
    \ >&2; cat \"$o/err\" >&2; exit 1; }\n# Order: interpreters before tools.\nfresh\
    \ order; pystub 1\nUVM_REPAIR=t uv --version > \"$o/out\" 2> \"$o/err\" || exit\
    \ 1\n[ \"$(grep -o -e 'python install' -e 'pip install' \"$o/err\" | tr '\\n'\
    \ ,)\" = \"python install,pip install,\" ] \\\n  || { echo \"FAIL: the interpreter\
    \ arm must run before the tool arm\" >&2; cat \"$o/err\" >&2; exit 1; }\n# R5,\
    \ fixture variant: an orphan without pyvenv.cfg beside tree F.\nfresh r5; mkdir\
    \ -p \"$root/tools/orph\"; : > \"$root/tools/orph/uv-receipt.toml\"\nif UVM_REPAIR=t\
    \ UVM_FIXTURE_MARK=\"$o/mark\" uv --version > \"$o/out\" 2> \"$o/err\"; then echo\
    \ \"FAIL R5: exited 0 with an orphan\" >&2; exit 1; fi\n[ \"$(lines \"$o/out\"\
    \ \"$o/err\")\" -eq 0 ] || { echo \"FAIL R5: a repair ran beside an orphan\" >&2;\
    \ cat \"$o/err\" >&2; exit 1; }\ngrep 'uv-manager: the repair for' \"$o/err\"\
    \ | grep 'orph' | grep -q 'pyvenv.cfg' || { echo \"FAIL R5: stderr does not name\
    \ the orphan and pyvenv.cfg\" >&2; cat \"$o/err\" >&2; exit 1; }\ngrep -q orph\
    \ \"$root/.repair/value-t.failed\" && [ ! -e \"$o/mark\" ] || { echo \"FAIL R5:\
    \ no failed outcome naming the orphan, or the command ran\" >&2; exit 1; }\n#\
    \ C2-F2: one command per damaged tool, every dist-info pinned, --no-cache, a healthy\
    \ tool never named.\n# A damaged tool with no receipt is repaired like any other;\
    \ a failed arm names the tool.\nfresh pins; d2=\"$root/tools/fx/lib/python3.12/site-packages/dep-2.0.dist-info\"\
    ; mkdir -p \"$d2\"; : > \"$d2/RECORD\"\nmkdir -p \"$root/tools/hl/lib/python3.12/site-packages/hl-3.0.dist-info\"\
    \ \"$root/tools/hl/bin\"; : > \"$root/tools/hl/pyvenv.cfg\"; : > \"$root/tools/hl/uv-receipt.toml\"\
    \n: > \"$root/tools/hl/lib/python3.12/site-packages/hl-3.0.dist-info/RECORD\"\
    ; ln -s /bin/sh \"$root/tools/hl/bin/python\"\nmkdir -p \"$root/tools/nr/lib/python3.12/site-packages/nr-1.5.dist-info\"\
    \ \"$root/tools/nr/bin\"; : > \"$root/tools/nr/pyvenv.cfg\"; ln -s /bin/sh \"\
    $root/tools/nr/bin/python\"\nUVM_REPAIR=t uv --version > \"$o/out\" 2> \"$o/err\"\
    \ || { echo \"FAIL C2-F2: knob beside damaged tools exited non-zero\" >&2; cat\
    \ \"$o/err\" >&2; exit 1; }\n[ \"$(lines \"$o/out\" \"$o/err\")\" -eq 2 ] && grep\
    \ -q \"^uv-fixture: pip install --python $root/tools/fx/bin/python --reinstall\
    \ --no-cache dep==2.0 fx==1.0$\" \"$o/err\" \\\n  && grep -q \"^uv-fixture: pip\
    \ install --python $root/tools/nr/bin/python --reinstall --no-cache nr==1.5$\"\
    \ \"$o/err\" && ! grep -q 'tools/hl' \"$o/err\" && [ -e \"$root/.repair/value-t.ok\"\
    \ ] \\\n  || { echo \"FAIL C2-F2: expected one pinned, --no-cache pip line each\
    \ for fx and nr, and none naming the healthy hl\" >&2; cat \"$o/err\" >&2; exit\
    \ 1; }\nfresh pinsfail\nif UVM_REPAIR=t UVM_FIXTURE_REPAIR_EXIT=1 uv --version\
    \ > \"$o/out\" 2> \"$o/err\"; then echo \"FAIL: a failed tool arm exited 0\" >&2;\
    \ exit 1; fi\ngrep -q 'the repair for UVM_REPAIR=t failed: the tool environment\
    \ repair failed for fx$' \"$o/err\" || { echo \"FAIL: the reason does not name\
    \ the tool\" >&2; cat \"$o/err\" >&2; exit 1; }\n# C2-F2: the arm never aims --python\
    \ at a tool whose bin/python does not run, nor restores a\n# distribution from\
    \ a URL, git or path source by version; each fails the scope naming it.\nfresh\
    \ nopy; mkdir -p \"$root/tools/np/lib/python3.12/site-packages/np-1.0.dist-info\"\
    ; : > \"$root/tools/np/pyvenv.cfg\"\nmkdir -p \"$root/tools/np/bin\"; ln -s \"\
    $root/python/gone/bin/python3\" \"$root/tools/np/bin/python\"\nif UVM_REPAIR=t\
    \ UVM_FIXTURE_MARK=\"$o/mark\" uv --version > \"$o/out\" 2> \"$o/err\"; then echo\
    \ \"FAIL C2-F2: exited 0 beside a tool whose interpreter is gone\" >&2; exit 1;\
    \ fi\n! grep -q 'pip install --python [^ ]*/tools/np/' \"$o/err\" && grep -q 'tool\
    \ np has no interpreter at bin/python' \"$root/.repair/value-t.failed\" && [ !\
    \ -e \"$o/mark\" ] \\\n  || { echo \"FAIL C2-F2: a tool whose bin/python does\
    \ not run was repaired, or the reason does not name it\" >&2; cat \"$o/err\" >&2;\
    \ exit 1; }\nfresh durl; dl=\"$root/tools/fx/lib/python3.12/site-packages/loc-0.1.dist-info\"\
    ; mkdir -p \"$dl\"; printf '{\"url\": \"file:///x\"}\\n' > \"$dl/direct_url.json\"\
    \nif UVM_REPAIR=t UVM_FIXTURE_MARK=\"$o/mark\" uv --version > \"$o/out\" 2> \"\
    $o/err\"; then echo \"FAIL C2-F2: exited 0 on a distribution from a path source\"\
    \ >&2; exit 1; fi\n[ \"$(lines \"$o/out\" \"$o/err\")\" -eq 0 ] && grep -q 'tool\
    \ fx has loc from a URL, git or path source' \"$root/.repair/value-t.failed\"\
    \ && [ ! -e \"$root/.repair/value-t.ok\" ] && [ ! -e \"$o/mark\" ] \\\n  || {\
    \ echo \"FAIL C2-F2: a path-source distribution was reinstalled by version, or\
    \ the reason does not name the tool and the distribution\" >&2; cat \"$o/err\"\
    \ >&2; exit 1; }\n# C3-F1: a receipt recording a requirement, constraint or override\
    \ from another source fails the\n# scope naming the tool and what it records,\
    \ with no direct_url.json, no pip line and the receipt\n# byte-identical; doctor\
    \ gives the tool no command. The forms are uv 0.13.6's, as measured. Registry\n\
    # forms, every index option, string values that spell a key and an entrypoint's\
    \ install-path do not\n# trip it: those tools are repaired with the receipt byte-identical.\n\
    fresh c3; ep='entrypoints = [\n    { name = \"fx\", install-path = \"/b/fx\",\
    \ from = \"fx\" },\n]'\nreceipt() {  # SCOPE: fx's receipt from stdin, kept as\
    \ $o/receipt.SCOPE\n  cat > \"$root/tools/fx/uv-receipt.toml\"; cp \"$root/tools/fx/uv-receipt.toml\"\
    \ \"$o/receipt.$1\"\n}\nrefused() {  # SCOPE WANT\n  if UVM_REPAIR=\"$1\" UVM_FIXTURE_MARK=\"\
    $o/mark\" uv --version > \"$o/out.$1\" 2> \"$o/err.$1\"; then echo \"FAIL C3-F1\
    \ ($1): exited 0\" >&2; exit 1; fi\n  [ \"$(lines \"$o/out.$1\" \"$o/err.$1\"\
    )\" -eq 0 ] && grep -F -q \"tool fx has $2 in its receipt\" \"$root/.repair/value-$1.failed\"\
    \ \\\n    && grep 'uv-manager: the repair for' \"$o/err.$1\" | grep -F -q \"tool\
    \ fx has $2 in its receipt\" && [ ! -e \"$root/.repair/value-$1.ok\" ] && [ !\
    \ -e \"$o/mark\" ] \\\n    && cmp -s \"$o/receipt.$1\" \"$root/tools/fx/uv-receipt.toml\"\
    \ \\\n    || { echo \"FAIL C3-F1 ($1): expected the scope failed naming fx and\
    \ [$2], no pip line, the receipt unchanged\" >&2; cat \"$o/err.$1\" >&2; exit\
    \ 1; }\n}\nrepaired() {  # SCOPE\n  UVM_REPAIR=\"$1\" uv --version > \"$o/out.$1\"\
    \ 2> \"$o/err.$1\" || { echo \"FAIL C3-F1 ($1): a registry receipt failed the\
    \ scope\" >&2; cat \"$o/err.$1\" >&2; exit 1; }\n  [ \"$(lines \"$o/out.$1\" \"\
    $o/err.$1\")\" -eq 1 ] && [ -e \"$root/.repair/value-$1.ok\" ] && cmp -s \"$o/receipt.$1\"\
    \ \"$root/tools/fx/uv-receipt.toml\" \\\n    || { echo \"FAIL C3-F1 ($1): a registry\
    \ receipt was not repaired once, or changed\" >&2; cat \"$o/err.$1\" >&2; exit\
    \ 1; }\n}\nfor k in directory:/src/fx path:/d/fx-1.0-py3-none-any.whl path:/d/fx-1.0.tar.gz\
    \ editable:/src/fx git:https://github.com/o/fx?rev=1.0 url:https://h/fx-1.0-py3-none-any.whl;\
    \ do\n  s=\"t$(echo \"${k%%:*}${k#*:}\" | tr -c -d 'a-z0-9')\"\n  printf '[tool]\\\
    nrequirements = [{ name = \"fx\", %s = \"%s\" }]\\npython = \"3.12\"\\n%s\\n'\
    \ \"${k%%:*}\" \"${k#*:}\" \"$ep\" | receipt \"$s\"; refused \"$s\" \"fx from\
    \ its ${k%%:*} source\"\n  s=\"w$s\"; printf '[tool]\\nrequirements = [\\n   \
    \ { name = \"fx\" },\\n    { name = \"dep\", %s = \"%s\" },\\n]\\npython = \"\
    3.12\"\\n%s\\n' \"${k%%:*}\" \"${k#*:}\" \"$ep\" | receipt \"$s\"; refused \"\
    $s\" \"dep from its ${k%%:*} source\"\n  for arr in constraints overrides; do\n\
    \    s2=\"$(echo \"$arr\" | cut -c 1)${s#w}\"; printf '[tool]\\nrequirements =\
    \ [{ name = \"fx\" }]\\n%s = [{ name = \"six\", %s = \"%s\" }]\\npython = \"3.12\"\
    \\n%s\\n' \"$arr\" \"${k%%:*}\" \"${k#*:}\" \"$ep\" | receipt \"$s2\"; refused\
    \ \"$s2\" \"six from its ${k%%:*} source\"\n  done\ndone\nfor k in 'index = [{\
    \ url = \"https://pypi.org/simple\", explicit = false, default = false, format\
    \ = \"simple\", authenticate = \"auto\" }]' \\\n         'index = [{ name = \"\
    pypi\", url = \"https://pypi.org/simple\", explicit = false, default = true, format\
    \ = \"simple\", authenticate = \"auto\" }]' \\\n         'index-url = \"https://pypi.org/simple\"\
    ' 'extra-index-url = [\"https://pypi.org/simple\"]' 'find-links = [\"file:///d\"\
    ]'; do\n  s=\"o$(echo \"$k\" | tr -c -d 'a-z')\"; s=\"$(echo \"$s\" | cut -c 1-40)\"\
    \n  printf '[tool]\\nrequirements = [{ name = \"fx\", specifier = \"==1.0\" }]\\\
    npython = \"3.12\"\\n%s\\n\\n[tool.options]\\n%s\\n' \"$ep\" \"$k\" | receipt\
    \ \"$s\"; repaired \"$s\"\ndone\nreceipt c3doc < \"$o/receipt.tgithttpsgithubcomofxrev10\"\
    \nif uvm doctor > \"$o/doc\" 2>&1; then echo \"FAIL C3-F1: doctor passed a damaged\
    \ tool\" >&2; exit 1; fi\ngrep -q '^    # fx: its receipt records fx from its\
    \ git source; install fx again from that source$' \"$o/doc\" && ! grep -q 'tools/fx/bin/python'\
    \ \"$o/doc\" \\\n  || { echo \"FAIL C3-F1: doctor must give fx no command and\
    \ name what its receipt records\" >&2; cat \"$o/doc\" >&2; exit 1; }\nprintf '[tool]\\\
    nrequirements = [{ name = \"fx\" }]\\npython = \"3.12\"\\n%s\\n' \"$ep\" | receipt\
    \ rpl; repaired rpl\nprintf '[tool]\\nrequirements = [\\n    { name = \"fx\",\
    \ specifier = \"==1.0\" },\\n    { name = \"dep\", extras = [\"url\"], marker\
    \ = \"extra == '\"'git'\"' and sys_platform != '\"'path'\"'\", specifier = \"\
    >=2\" },\\n]\\nconstraints = [{ name = \"six\", specifier = \"==1.16.0\" }]\\\
    npython = \"3.12\"\\n%s\\n\\n[tool.options]\\nexclude-newer = \"2024-01-02T05:00:00Z\"\
    \\nindex-strategy = \"first-index\"\\n' \"$ep\" | receipt rwith; repaired rwith\n\
    : | receipt rempty; repaired rempty\n# C2-F1: an install whose binary is gone\
    \ is damaged and named by its key; a dangling shim through the\n# minor-version\
    \ link names the install it resolves to.\nfresh nobin.intact; mkdir -p \"$root/python/cpython-3.7.0-fixture/bin\"\
    \ \"$root/python/cpython-3.7.0-fixture/lib\"; ln -s \"$root/python/cpython-3.7.0-fixture\"\
    \ \"$root/python/cpython-3.7-fixture\"\nUVM_REPAIR=t uv --version > \"$o/out\"\
    \ 2> \"$o/err\" || { echo \"FAIL C2-F1: knob on an interpreter with no binary\
    \ exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\n[ \"$(lines \"$o/out\"\
    \ \"$o/err\")\" -eq 1 ] && grep -q '^uv-fixture: python install --reinstall cpython-3.7.0-fixture$'\
    \ \"$o/err\" \\\n  || { echo \"FAIL C2-F1: an install whose binary is gone must\
    \ be repaired by its own key\" >&2; cat \"$o/err\" >&2; exit 1; }\nif uvm doctor\
    \ > \"$o/doc\" 2>&1; then echo \"FAIL C2-F1: doctor passed an interpreter with\
    \ no binary\" >&2; exit 1; fi\ngrep -q '^FAIL  managed interpreter cpython-3.7.0-fixture\
    \ is damaged (its binary is missing)$' \"$o/doc\" && grep -q '^    uv python install\
    \ --reinstall cpython-3.7.0-fixture$' \"$o/doc\" \\\n  || { echo \"FAIL C2-F1:\
    \ doctor must report the missing binary and name the key\" >&2; cat \"$o/doc\"\
    \ >&2; exit 1; }\nfresh shimlink.intact; mkdir -p \"$root/python/cpython-3.8.0-fixture/bin\"\
    \ \"$root/bin/python-shims\"; printf '#!/bin/sh\\nexit 0\\n' > \"$root/python/cpython-3.8.0-fixture/bin/python3\"\
    ; chmod +x \"$root/python/cpython-3.8.0-fixture/bin/python3\"\nln -s \"$root/python/cpython-3.8.0-fixture\"\
    \ \"$root/python/cpython-3.8-fixture\"; ln -s \"$root/python/cpython-3.8-fixture/bin/python3.8\"\
    \ \"$root/bin/python-shims/python3.8\"\nUVM_REPAIR=t uv --version > \"$o/out\"\
    \ 2> \"$o/err\" || { echo \"FAIL C2-F1: knob beside a shim through the minor-version\
    \ link exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\n[ \"$(lines \"$o/out\"\
    \ \"$o/err\")\" -eq 1 ] && grep -q '^uv-fixture: python install --reinstall cpython-3.8.0-fixture$'\
    \ \"$o/err\" \\\n  || { echo \"FAIL C2-F1: a dangling shim through the minor-version\
    \ link must name the install's key\" >&2; cat \"$o/err\" >&2; exit 1; }\n# F1:\
    \ the interpreter arm names exactly the damaged installs, by key; never a passing\
    \ one, never the minor-version link.\nfresh keys.intact; pystub 1\nmkdir -p \"\
    $root/python/cpython-3.11.0-fixture/bin\"; printf '#!/bin/sh\\nexit 0\\n' > \"\
    $root/python/cpython-3.11.0-fixture/bin/python3\"; chmod +x \"$root/python/cpython-3.11.0-fixture/bin/python3\"\
    \nln -s \"$root/python/cpython-3.12.0-fixture\" \"$root/python/cpython-3.12-fixture\"\
    \nUVM_REPAIR=t uv --version > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL F1: knob\
    \ on a damaged interpreter exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1;\
    \ }\n[ \"$(grep -c 'python install' \"$o/err\")\" -eq 1 ] && grep -q '^uv-fixture:\
    \ python install --reinstall cpython-3.12.0-fixture$' \"$o/err\" \\\n  || { echo\
    \ \"FAIL F1: the interpreter arm must name exactly cpython-3.12.0-fixture\" >&2;\
    \ cat \"$o/err\" >&2; exit 1; }\n# Doctor's advice names the same keys and the\
    \ repair's own per-tool command, interpreters first.\nfresh keysdoc; pystub 1\n\
    if uvm doctor > \"$o/doc\" 2>&1; then echo \"FAIL F1: doctor passed a damaged\
    \ interpreter\" >&2; exit 1; fi\n[ \"$(grep -o -e '^    uv python install --reinstall\
    \ cpython-3.12.0-fixture$' -e \"^    uv pip install --python '$root/tools/fx/bin/python'\
    \ --reinstall --no-cache fx==1.0$\" \"$o/doc\" | sed 's/ --.*//' | tr '\\n' ,)\"\
    \ = \"    uv python install,    uv pip install,\" ] \\\n  && ! grep -q 'tool upgrade'\
    \ \"$o/doc\" \\\n  || { echo \"FAIL F1: doctor's advice must name cpython-3.12.0-fixture,\
    \ then fx's pinned pip command\" >&2; cat \"$o/doc\" >&2; exit 1; }\n# F4: a dangling\
    \ shim whose whole directory is gone is doctor's alone; with its directory present\
    \ it is repaired.\nfresh gonepy.intact; pystub 0; mkdir -p \"$root/bin/python-shims\"\
    ; ln -s \"$root/python/cpython-3.9.0-gone/bin/python3.9\" \"$root/bin/python-shims/python3.9\"\
    \nfor s in s1 s2 s3; do UVM_REPAIR=$s uv --version >> \"$o/out\" 2>> \"$o/err\"\
    \ || { echo \"FAIL F4: scope $s exited non-zero beside a gone interpreter's shim\"\
    \ >&2; cat \"$o/err\" >&2; exit 1; }; done\n[ \"$(pylines \"$o/out\" \"$o/err\"\
    )\" -eq 0 ] && [ \"$(LC_ALL=C ls -A \"$root/.repair\" | tr '\\n' ' ')\" = \"value-s1.ok\
    \ value-s2.ok value-s3.ok \" ] \\\n  || { echo \"FAIL F4: a shim whose interpreter\
    \ is gone triggered $(pylines \"$o/out\" \"$o/err\") python repair(s) across 3\
    \ scopes, expected 0\" >&2; cat \"$o/err\" >&2; exit 1; }\nif uvm doctor > \"\
    $o/doc\" 2>&1; then echo \"FAIL F4: doctor passed a dangling interpreter shim\"\
    \ >&2; exit 1; fi\ngrep -q \"^FAIL  dangling executable: $root/bin/python-shims/python3.9$\"\
    \ \"$o/doc\" || { echo \"FAIL F4: doctor no longer reports the dangling interpreter\
    \ shim\" >&2; cat \"$o/doc\" >&2; exit 1; }\nfresh gonetool.intact; mkdir -p \"\
    $root/bin/shims\"; ln -s \"$root/tools/gone/bin/gone\" \"$root/bin/shims/gone\"\
    \nfor s in s1 s2 s3; do UVM_REPAIR=$s uv --version >> \"$o/out\" 2>> \"$o/err\"\
    \ || { echo \"FAIL F4: scope $s exited non-zero beside a gone tool's shim\" >&2;\
    \ cat \"$o/err\" >&2; exit 1; }; done\n[ \"$(cat \"$o/out\" \"$o/err\" | grep\
    \ -c 'pip install')\" -eq 0 ] || { echo \"FAIL F4: a shim whose tool is gone triggered\
    \ a tool repair\" >&2; cat \"$o/err\" >&2; exit 1; }\nif uvm doctor > \"$o/doc\"\
    \ 2>&1; then echo \"FAIL F4: doctor passed a dangling tool shim\" >&2; exit 1;\
    \ fi\ngrep -q \"^FAIL  dangling executable: $root/bin/shims/gone$\" \"$o/doc\"\
    \ || { echo \"FAIL F4: doctor no longer reports the dangling tool shim\" >&2;\
    \ cat \"$o/doc\" >&2; exit 1; }\nif grep -n 'python install' \"$o/doc\"; then\
    \ echo \"FAIL C2-F5: doctor prints an interpreter command with no interpreter\
    \ damaged\" >&2; exit 1; fi\n# C3-F4: a shim whose interpreter cannot be keyed,\
    \ its install gone and its minor-version link too,\n# gets the fallback a gone\
    \ tool's shim gets, and no python command or placeholder.\nfresh gonepydoc.intact;\
    \ mkdir -p \"$root/bin/python-shims\"; ln -s \"$root/python/cpython-3.9.0-gone/bin/python3.9\"\
    \ \"$root/bin/python-shims/python3.9\"\nln -s \"$root/python/cpython-3.9-fixture/bin/python3.9\"\
    \ \"$root/bin/python-shims/python3\"\nif uvm doctor > \"$o/doc\" 2>&1; then echo\
    \ \"FAIL C3-F4: doctor passed dangling interpreter shims\" >&2; exit 1; fi\n[\
    \ \"$(grep -c '^FAIL  dangling executable: ' \"$o/doc\")\" -eq 2 ] && ! grep -n\
    \ -e 'python install' -e '<install>' -e 'Name each damaged interpreter' \"$o/doc\"\
    \ \\\n  && grep -q '^    # nothing above is repaired in place; remove a shim whose\
    \ tool or interpreter is gone$' \"$o/doc\" \\\n  || { echo \"FAIL C3-F4: with\
    \ interpreter shims it cannot key, doctor's advice must be the remove-the-shim\
    \ fallback alone\" >&2; cat \"$o/doc\" >&2; exit 1; }\nfresh keptdir.intact; mkdir\
    \ -p \"$root/python/cpython-3.10.0-fixture/bin\" \"$root/bin/python-shims\" \"\
    $root/tools/kept/bin\" \"$root/bin/shims\" \"$root/tools/kept/lib/python3.12/site-packages/kept-1.0.dist-info\"\
    \nln -s /bin/sh \"$root/tools/kept/bin/python\"; : > \"$root/tools/kept/lib/python3.12/site-packages/kept-1.0.dist-info/RECORD\"\
    \nln -s \"$root/python/cpython-3.10.0-fixture/bin/python3.10\" \"$root/bin/python-shims/python3.10\"\
    \n: > \"$root/tools/kept/pyvenv.cfg\"; : > \"$root/tools/kept/uv-receipt.toml\"\
    ; ln -s \"$root/tools/kept/bin/kept\" \"$root/bin/shims/kept\"\nUVM_REPAIR=t uv\
    \ --version > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL F4: knob beside repairable\
    \ shims exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\n[ \"$(grep -o -e\
    \ 'python install --reinstall cpython-3.10.0-fixture$' -e 'pip install' \"$o/err\"\
    \ | tr '\\n' ,)\" = \"python install --reinstall cpython-3.10.0-fixture,pip install,\"\
    \ ] \\\n  || { echo \"FAIL F4: a dangling shim whose directory is present must\
    \ be repaired\" >&2; cat \"$o/err\" >&2; exit 1; }\necho \"P3 offline ok\"\nP3OFF\n\
    # Needs real uv and network. SEED_UV and SEED_UVX name a local uv; the sandbox\
    \ seeds from it\n# because the installer's mktemp is denied in the agent sandbox.\n\
    SEED_UV=$(command -v uv) SEED_UVX=$(command -v uvx)\ncase \"$SEED_UV\" in ''|\"\
    $PWD\"/bin/*) echo \"FAIL: need a real uv on PATH, not this checkout's wrapper\"\
    \ >&2; exit 1 ;; esac\nSEED_UV=\"$SEED_UV\" SEED_UVX=\"$SEED_UVX\" .agents/factory/bin/temp_root.sh\
    \ sh -s <<'P3REAL' || exit 1\nset -u\n# Real uv and network: pypi.org, files.pythonhosted.org,\
    \ releases.astral.sh.\na=$(uname -m); ver=$(\"$SEED_UV\" --version | awk '{print\
    \ $2}')\nUV_PYTHON_PREFERENCE=only-managed; export UV_PYTHON_PREFERENCE\nseed()\
    \ {  # NAME [VER]: a root seeded from the local uv, with cpython VER (default\
    \ 3.12) installed\n  UVM_ROOT=\"$UVM_SANDBOX/root.$1\"; export UVM_ROOT; root=\"\
    $UVM_ROOT/$a\"; o=\"$UVM_SANDBOX/o.$1\"; t=\"$UVM_SANDBOX/trash.$1\"\n  mkdir\
    \ -p \"$root/versions/$ver\" \"$o\" \"$t\"; cp \"$SEED_UV\" \"$SEED_UVX\" \"$root/versions/$ver/\"\
    ; ln -s \"versions/$ver\" \"$root/current\"\n  if ! uv python install \"${2:-3.12}\"\
    \ > \"$o/py.out\" 2> \"$o/py.err\"; then echo \"FAIL ($1): uv python install ${2:-3.12}\
    \ (network?)\" >&2; cat \"$o/py.err\" >&2; exit 1; fi\n}\nq() { \"$@\" > \"$o/q.out\"\
    \ 2> \"$o/q.err\" || { echo \"FAIL: setup: $* (network?)\" >&2; cat \"$o/q.err\"\
    \ >&2; exit 1; }; }\ngut() {  # TOOL: tree (T), a module file and RECORD moved\
    \ out\n  sp=$(echo \"$root/tools/$1/lib/python3.12/site-packages\")\n  mv \"$sp/pyflakes/checker.py\"\
    \ \"$sp\"/pyflakes-*.dist-info/RECORD \"$t/\"\n}\n# R3 (T)\nseed t\nuv tool install\
    \ pyflakes==3.2.0 --python 3.12 > \"$o/ti.out\" 2> \"$o/ti.err\" || { echo \"\
    FAIL R3T: tool install\" >&2; cat \"$o/ti.err\" >&2; exit 1; }\nfind \"$root/tools/pyflakes\"\
    \ -type f | sort > \"$o/before\"; cp \"$root/tools/pyflakes/uv-receipt.toml\"\
    \ \"$o/receipt\"\ngut pyflakes\nif uvx pyflakes --version > \"$o/red.out\" 2>\
    \ \"$o/red.err\"; then echo \"FAIL R3T: the damage did not break uvx\" >&2; exit\
    \ 1; fi\nUVM_REPAIR=t uvx pyflakes --version > \"$o/out\" 2> \"$o/err\" || { echo\
    \ \"FAIL R3T: knob-set uvx exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1;\
    \ }\n[ \"$(wc -l < \"$o/out\" | tr -d ' ')\" = 1 ] && grep -q '^3\\.2\\.0 Python\
    \ 3\\.12\\.' \"$o/out\" || { echo \"FAIL R3T/R8: stdout [$(cat \"$o/out\")]\"\
    \ >&2; exit 1; }\nfind \"$root/tools/pyflakes\" -type f | sort > \"$o/after\"\n\
    [ -z \"$(comm -23 \"$o/before\" \"$o/after\")\" ] || { echo \"FAIL R3T: manifest\
    \ paths still missing: $(comm -23 \"$o/before\" \"$o/after\")\" >&2; exit 1; }\n\
    \"$root/bin/shims/pyflakes\" --version > /dev/null 2>&1 || { echo \"FAIL R3T:\
    \ the console script does not run\" >&2; exit 1; }\ncmp -s \"$o/receipt\" \"$root/tools/pyflakes/uv-receipt.toml\"\
    \ && [ -e \"$root/.repair/value-t.ok\" ] || { echo \"FAIL R3T: receipt changed\
    \ or no repaired outcome\" >&2; exit 1; }\n# R4: an older pin and a --with package\
    \ survive.\nseed r4\nuv tool install 'pyflakes==3.1.0' --with six --python 3.12\
    \ > \"$o/ti.out\" 2> \"$o/ti.err\" || { echo \"FAIL R4: tool install\" >&2; cat\
    \ \"$o/ti.err\" >&2; exit 1; }\ncp \"$root/tools/pyflakes/uv-receipt.toml\" \"\
    $o/receipt\"; gut pyflakes\nUVM_REPAIR=r4 uvx pyflakes --version > \"$o/out\"\
    \ 2> \"$o/err\" || { echo \"FAIL R4: knob-set uvx exited non-zero\" >&2; cat \"\
    $o/err\" >&2; exit 1; }\ngrep -q '^3\\.1\\.0 ' \"$o/out\" || { echo \"FAIL R4:\
    \ the pin did not survive: [$(cat \"$o/out\")]\" >&2; exit 1; }\n\"$root/tools/pyflakes/bin/python\"\
    \ -c 'import six' || { echo \"FAIL R4: six does not import from the tool\" >&2;\
    \ exit 1; }\ncmp -s \"$o/receipt\" \"$root/tools/pyflakes/uv-receipt.toml\" ||\
    \ { echo \"FAIL R4: uv-receipt.toml changed\" >&2; exit 1; }\n# R3 (P), on the\
    \ trees a real purge leaves: every file of the interpreter removed, its directories\
    \ and\n# links kept; only its bin/ files; every file and the minor-version link\
    \ too; and every file with a\n# tool on it damaged as (T), through uvx, so both\
    \ arms run.\nprintf 'import json\\nprint(\"t-ok\", json.dumps([1]))\\n' > \"$UVM_SANDBOX/t.py\"\
    \nfor v in all bin nolink tool; do\n  seed \"p$v\"; for d in \"$root\"/python/cpython-3.12.*/;\
    \ do [ -L \"${d%/}\" ] || base=\"${d%/}\"; done\n  if [ \"$v\" = tool ]; then\
    \ q uv tool install pyflakes==3.2.0 --python 3.12; gut pyflakes; fi\n  if [ \"\
    $v\" = bin ]; then find \"$base/bin\" -type f -delete; else find \"$base\" -type\
    \ f -delete; fi\n  if [ \"$v\" = nolink ]; then for l in \"$root\"/python/cpython-3.12-*;\
    \ do [ -L \"$l\" ] && mv \"$l\" \"$t/\"; done; fi\n  [ ! -e \"$base/bin/python3\"\
    \ ] && [ -d \"$base/lib/python3.12\" ] || { echo \"FAIL R3P ($v): setup, the purge\
    \ shape\" >&2; exit 1; }\n  if [ \"$v\" = tool ]; then\n    # Not uvx for the\
    \ red: on a broken tool interpreter uv falls back to an ephemeral environment\
    \ on\n    # a newly downloaded interpreter, which would change the tree under\
    \ test.\n    if \"$root/bin/shims/pyflakes\" --version > \"$o/red.out\" 2> \"\
    $o/red.err\"; then echo \"FAIL R3P ($v): the damage did not break the tool\" >&2;\
    \ exit 1; fi\n    UVM_REPAIR=\"p$v\" uvx pyflakes --version > \"$o/out\" 2> \"\
    $o/err\" || { echo \"FAIL R3P ($v): knob-set uvx exited non-zero\" >&2; cat \"\
    $o/err\" >&2; exit 1; }\n    grep -q '^3\\.2\\.0 Python 3\\.12\\.' \"$o/out\"\
    \ && grep -q 'repairing the managed interpreters' \"$o/err\" && grep -q 'repairing\
    \ the tool environments for [^:]*: pyflakes$' \"$o/err\" \\\n      || { echo \"\
    FAIL R3P ($v): stdout [$(cat \"$o/out\")], or both arms did not run\" >&2; cat\
    \ \"$o/err\" >&2; exit 1; }\n  else\n    if uv run --no-project -p 3.12 \"$UVM_SANDBOX/t.py\"\
    \ > \"$o/red.out\" 2> \"$o/red.err\"; then echo \"FAIL R3P ($v): the damage did\
    \ not break uv run\" >&2; exit 1; fi\n    UVM_REPAIR=\"p$v\" uv run --no-project\
    \ -p 3.12 \"$UVM_SANDBOX/t.py\" > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL R3P\
    \ ($v): knob-set uv run exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\n\
    \    [ \"$(cat \"$o/out\")\" = 't-ok [1]' ] || { echo \"FAIL R3P ($v): stdout\
    \ [$(cat \"$o/out\")]\" >&2; exit 1; }\n    if grep -q 'repairing the tool environments'\
    \ \"$o/err\"; then echo \"FAIL R6: the tool arm ran with no tool damage\" >&2;\
    \ exit 1; fi\n  fi\n  \"$base/bin/python3\" -c 'import json, os, ssl' && [ -e\
    \ \"$root/.repair/value-p$v.ok\" ] || { echo \"FAIL R3P ($v): the interpreter\
    \ is still damaged, or no outcome\" >&2; exit 1; }\ndone\n# C2-F2 (R4): an unpinned\
    \ tool at an older release with an unpinned --with package at an older release,\n\
    # damaged with that package's RECORD gone too; beside it a healthy unpinned tool\
    \ at an older release\n# and a pinned tool with --with, also damaged. Every version\
    \ and every receipt is kept, no second\n# dist-info directory is left, and the\
    \ healthy tool is not touched.\nseed unp\nq uv tool install 'pyflakes==3.1.0'\
    \ --with 'six==1.16.0' --python 3.12; q uv tool install pyflakes --with six --python\
    \ 3.12\nq uv tool install 'pycodestyle==2.11.1' --python 3.12; q uv tool install\
    \ pycodestyle --python 3.12\nq uv tool install 'pycowsay==0.0.0.2' --with six\
    \ --python 3.12\ngrep -q '{ name = \"pyflakes\" }' \"$root/tools/pyflakes/uv-receipt.toml\"\
    \ && grep -q '{ name = \"pycodestyle\" }' \"$root/tools/pycodestyle/uv-receipt.toml\"\
    \ \\\n  && [ -d \"$root/tools/pyflakes/lib/python3.12/site-packages/six-1.16.0.dist-info\"\
    \ ] && [ -d \"$root/tools/pycodestyle/lib/python3.12/site-packages/pycodestyle-2.11.1.dist-info\"\
    \ ] \\\n  || { echo \"FAIL C2-F2: setup, the unpinned receipts at older releases\"\
    \ >&2; exit 1; }\ndists() { for tl in pyflakes pycodestyle pycowsay; do printf\
    \ '%s: ' \"$tl\"; (cd \"$root/tools/$tl/lib/python3.12/site-packages\" && ls -d\
    \ ./*.dist-info | tr '\\n' ' '); echo; done; }\ndists > \"$o/before\"; for tl\
    \ in pyflakes pycodestyle pycowsay; do cp \"$root/tools/$tl/uv-receipt.toml\"\
    \ \"$o/receipt.$tl\"; done\nsp=\"$root/tools/pyflakes/lib/python3.12/site-packages\"\
    ; mv \"$sp/pyflakes/checker.py\" \"$sp\"/pyflakes-*.dist-info/RECORD \"$sp\"/six-*.dist-info/RECORD\
    \ \"$t/\"\nmkdir -p \"$t/c\"; sp=\"$root/tools/pycowsay/lib/python3.12/site-packages\"\
    ; mv \"$sp\"/pycowsay-*.dist-info/RECORD \"$sp\"/six-*.dist-info/RECORD \"$sp/six.py\"\
    \ \"$t/c/\"\n: > \"$o/stamp\"; sleep 1\nUVM_REPAIR=unp uvx pyflakes --version\
    \ > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL C2-F2: knob-set uvx exited non-zero\"\
    \ >&2; cat \"$o/err\" >&2; exit 1; }\ngrep -q '^3\\.1\\.0 Python 3\\.12\\.' \"\
    $o/out\" || { echo \"FAIL C2-F2: the unpinned tool did not come back at 3.1.0:\
    \ [$(cat \"$o/out\")]\" >&2; exit 1; }\ndists > \"$o/after\"; cmp -s \"$o/before\"\
    \ \"$o/after\" || { echo \"FAIL C2-F2: a version moved, or a second dist-info\
    \ is left\" >&2; diff \"$o/before\" \"$o/after\" >&2; exit 1; }\nfor tl in pyflakes\
    \ pycodestyle pycowsay; do cmp -s \"$o/receipt.$tl\" \"$root/tools/$tl/uv-receipt.toml\"\
    \ || { echo \"FAIL C2-F2: $tl's receipt changed\" >&2; exit 1; }; done\n[ -z \"\
    $(find \"$root/tools/pycodestyle\" -newer \"$o/stamp\")\" ] && grep -q 'repairing\
    \ the tool environments for [^:]*: pycowsay pyflakes$' \"$o/err\" || { echo \"\
    FAIL C2-F2: the healthy tool was touched\" >&2; exit 1; }\n[ \"$(\"$root/tools/pyflakes/bin/python\"\
    \ -c 'import six; print(six.__version__)')\" = 1.16.0 ] && \"$root/tools/pycowsay/bin/python\"\
    \ -c 'import six' && uvm doctor > /dev/null 2>&1 \\\n  || { echo \"FAIL C2-F2:\
    \ a --with package does not import, or doctor still finds damage\" >&2; exit 1;\
    \ }\n# C2-F2: a dependency whose whole dist-info directory went with the purge\
    \ comes back.\nseed dep\nq uv tool install 'flake8==7.1.0' --python 3.12; q uv\
    \ tool install flake8 --python 3.12\nsp=\"$root/tools/flake8/lib/python3.12/site-packages\"\
    ; mc=$(cd \"$sp\" && ls -d mccabe-*.dist-info)\nmv \"$sp/flake8/main/application.py\"\
    \ \"$sp\"/flake8-*.dist-info/RECORD \"$sp/$mc\" \"$sp/mccabe.py\" \"$t/\"\nUVM_REPAIR=dep\
    \ uvx flake8 --version > \"$o/out\" 2> \"$o/err\" || { echo \"FAIL C2-F2: knob-set\
    \ uvx flake8 exited non-zero\" >&2; cat \"$o/err\" >&2; exit 1; }\ngrep -q '^7\\\
    .1\\.0 ' \"$o/out\" && [ -d \"$sp/$mc\" ] && \"$root/tools/flake8/bin/python\"\
    \ -c 'import mccabe' || { echo \"FAIL C2-F2: the dependency with no dist-info\
    \ did not come back\" >&2; cat \"$o/out\" \"$o/err\" >&2; exit 1; }\n# C2-F2:\
    \ a distribution installed from a path has no version an index restores; the scope\
    \ fails\n# naming the tool and the distribution, and records no repair.\nseed\
    \ src\n\"$(ls -d \"$root\"/python/cpython-3.12.*/bin/python3 | head -n 1)\" -\
    \ \"$UVM_SANDBOX/whl\" <<'WHEEL'\nimport os, sys, zipfile\nw = sys.argv[1]; os.makedirs(w,\
    \ exist_ok=True); di = \"localtool-0.1.dist-info\"\nfiles = {\"localtool/__init__.py\"\
    : \"def main():\\n    print('localtool 0.1')\\n\",\n         di + \"/METADATA\"\
    : \"Metadata-Version: 2.1\\nName: localtool\\nVersion: 0.1\\n\",\n         di\
    \ + \"/WHEEL\": \"Wheel-Version: 1.0\\nGenerator: hand\\nRoot-Is-Purelib: true\\\
    nTag: py3-none-any\\n\",\n         di + \"/entry_points.txt\": \"[console_scripts]\\\
    nlocaltool = localtool:main\\n\"}\nfiles[di + \"/RECORD\"] = \"\".join(k + \"\
    ,,\\n\" for k in files) + di + \"/RECORD,,\\n\"\nwith zipfile.ZipFile(os.path.join(w,\
    \ \"localtool-0.1-py3-none-any.whl\"), \"w\") as z:\n    for k, v in files.items():\n\
    \        z.writestr(k, v)\nWHEEL\nq uv tool install \"$UVM_SANDBOX/whl/localtool-0.1-py3-none-any.whl\"\
    \ --python 3.12\nsp=\"$root/tools/localtool/lib/python3.12/site-packages\"; [\
    \ -e \"$sp/localtool-0.1.dist-info/direct_url.json\" ] || { echo \"FAIL C2-F2:\
    \ setup, no direct_url.json\" >&2; exit 1; }\nmv \"$sp/localtool/__init__.py\"\
    \ \"$sp/localtool-0.1.dist-info/RECORD\" \"$t/\"\nif UVM_REPAIR=src uvx localtool\
    \ > \"$o/out\" 2> \"$o/err\"; then echo \"FAIL C2-F2: exited 0 on a tool from\
    \ a path source\" >&2; exit 1; fi\ngrep 'uv-manager: the repair for' \"$o/err\"\
    \ | grep -q 'tool localtool has localtool from a URL, git or path source' && [\
    \ -e \"$root/.repair/value-src.failed\" ] && [ ! -e \"$root/.repair/value-src.ok\"\
    \ ] \\\n  || { echo \"FAIL C2-F2: the path-source failure does not name the tool\
    \ and the distribution\" >&2; cat \"$o/err\" >&2; exit 1; }\n# C3-F1, real: a\
    \ tool installed from a directory, a wheel, an sdist, editable, git or a URL,\
    \ or with\n# such a --with package, or with a URL constraint or override, damaged\
    \ with every direct_url.json\n# gone, fails its scope naming the tool and what\
    \ its receipt records. No uv pip runs, the damage\n# stays, and the receipt is\
    \ byte-identical. One tool is damaged at a time and put back after. Tools\n# installed\
    \ with an index or find-links option, damaged the same way, are repaired with\
    \ their\n# versions and receipts kept.\nseed c3; src=\"$UVM_SANDBOX/c3src\"; mkdir\
    \ -p \"$src\"\nproj() {  # NAME: a local project with a console script, built\
    \ by uv's own backend\n  mkdir -p \"$src/$1/src/$1\"; printf 'def main():\\n \
    \   print(\"%s 0.1\")\\n' \"$1\" > \"$src/$1/src/$1/__init__.py\"\n  printf '[project]\\\
    nname = \"%s\"\\nversion = \"0.1\"\\nrequires-python = \">=3.8\"\\n[project.scripts]\\\
    n%s = \"%s:main\"\\n[build-system]\\nrequires = [\"uv_build>=0.8,<0.14\"]\\nbuild-backend\
    \ = \"uv_build\"\\n' \"$1\" \"$1\" \"$1\" > \"$src/$1/pyproject.toml\"\n}\nfor\
    \ pj in cdir cwhl csd ced cgit wdir wwhl wed wgit uvmfl; do proj \"$pj\"; done\n\
    printf 'six @ %s\\n' \"https://files.pythonhosted.org/packages/d9/5a/e7c31adbe875f2abbb91bd84cf2dc52d792b5a01506781dbcf25c91daf11/six-1.16.0-py2.py3-none-any.whl\"\
    \ > \"$src/six.txt\"\nq uv build -q --wheel --out-dir \"$src/dist\" \"$src/cwhl\"\
    ; q uv build -q --sdist --out-dir \"$src/dist\" \"$src/csd\"\nq uv build -q --wheel\
    \ --out-dir \"$src/dist\" \"$src/wwhl\"; q uv build -q --wheel --out-dir \"$src/fl\"\
    \ \"$src/uvmfl\"\nfor pj in cgit wgit; do (cd \"$src/$pj\" && git init -q && git\
    \ add -A && git -c user.name=g -c user.email=g@g.invalid commit -q -m i) || {\
    \ echo \"FAIL C3-F1: setup, git\" >&2; exit 1; }; done\ncow=https://files.pythonhosted.org/packages/eb/bd/17f894b13037499e615048a6daeb9cae28142ee85ce6eb8d24d10504860b/pycowsay-0.0.0.2-py3-none-any.whl\n\
    six=https://files.pythonhosted.org/packages/d9/5a/e7c31adbe875f2abbb91bd84cf2dc52d792b5a01506781dbcf25c91daf11/six-1.16.0-py2.py3-none-any.whl\n\
    ix=https://pypi.org/simple\nq uv tool install --python 3.12 \"$src/cdir\"; q uv\
    \ tool install --python 3.12 \"$src/dist/cwhl-0.1-py3-none-any.whl\"\nq uv tool\
    \ install --python 3.12 \"$src/dist/csd-0.1.tar.gz\"; q uv tool install --python\
    \ 3.12 -e \"$src/ced\"\nq uv tool install --python 3.12 \"git+file://$src/cgit\"\
    ; q uv tool install --python 3.12 \"$cow\"\nq uv tool install --python 3.12 pyflakes==3.2.0\
    \ --with \"$src/wdir\"; q uv tool install --python 3.12 pycodestyle==2.11.1 --with\
    \ \"$src/dist/wwhl-0.1-py3-none-any.whl\"\nq uv tool install --python 3.12 tabulate\
    \ --with-editable \"$src/wed\"; q uv tool install --python 3.12 sqlparse --with\
    \ \"git+file://$src/wgit\"\nq uv tool install --python 3.12 cowsay --with \"$six\"\
    \nq uv tool install --python 3.12 wheel --index \"$ix\"; q uv tool install --python\
    \ 3.12 chardet --index-url \"$ix\"\nq uv tool install --python 3.12 markdown --extra-index-url\
    \ \"$ix\"; q uv tool install --python 3.12 isort --default-index \"$ix\"\nq uv\
    \ tool install --python 3.12 pygments --find-links \"$src/fl\"\nq uv tool install\
    \ --python 3.12 pyupgrade --with six -c \"$src/six.txt\"; q uv tool install --python\
    \ 3.12 autopep8 --with six --overrides \"$src/six.txt\"\nuvm doctor > \"$o/doc.c3\"\
    \ 2>&1 || { echo \"FAIL C3-F1: setup, the installed tree is not clean\" >&2; cat\
    \ \"$o/doc.c3\" >&2; exit 1; }\nn=0\nfor c in cdir:'cdir from its directory source'\
    \ cwhl:'cwhl from its path source' csd:'csd from its path source' ced:'ced from\
    \ its editable source' \\\n         cgit:'cgit from its git source' pycowsay:'pycowsay\
    \ from its url source' pyflakes:'wdir from its directory source' \\\n        \
    \ pycodestyle:'wwhl from its path source' tabulate:'wed from its editable source'\
    \ sqlparse:'wgit from its git source' cowsay:'six from its url source' \\\n  \
    \       pyupgrade:'six from its url source' autopep8:'six from its url source';\
    \ do\n  tl=\"${c%%:*}\"; want=\"${c#*:}\"; n=$((n + 1)); tt=\"$t/c3.$n\"; mkdir\
    \ -p \"$tt\"; : > \"$tt/moved\"\n  cp \"$root/tools/$tl/uv-receipt.toml\" \"$o/receipt.$tl\"\
    \n  for f in \"$root/tools/$tl\"/lib/python3.12/site-packages/*.dist-info/RECORD\
    \ \"$root/tools/$tl\"/lib/python3.12/site-packages/*.dist-info/direct_url.json;\
    \ do\n    [ -e \"$f\" ] || continue; m=$(($(wc -l < \"$tt/moved\") + 1)); mv \"\
    $f\" \"$tt/f.$m\" && echo \"$f\" >> \"$tt/moved\"\n  done\n  [ -z \"$(find \"\
    $root/tools/$tl\" -name direct_url.json)\" ] && grep -q RECORD \"$tt/moved\" ||\
    \ { echo \"FAIL C3-F1 ($tl): setup, the damage\" >&2; exit 1; }\n  (cd \"$root/tools/$tl\"\
    \ && find . | LC_ALL=C sort) > \"$o/files.$tl\"\n  if UVM_REPAIR=\"c3-$n\" uv\
    \ --version > \"$o/out.$tl\" 2> \"$o/err.$tl\"; then echo \"FAIL C3-F1 ($tl):\
    \ exited 0\" >&2; cat \"$o/err.$tl\" >&2; exit 1; fi\n  grep 'uv-manager: the\
    \ repair for' \"$o/err.$tl\" | grep -F -q \"tool $tl has $want in its receipt\"\
    \ && [ -e \"$root/.repair/value-c3-$n.failed\" ] && [ ! -e \"$root/.repair/value-c3-$n.ok\"\
    \ ] \\\n    || { echo \"FAIL C3-F1 ($tl): the scope did not fail naming $tl and\
    \ [$want]\" >&2; cat \"$o/err.$tl\" >&2; exit 1; }\n  ! grep -q -e '^Resolved\
    \ ' -e '^Prepared ' -e '^Installed ' -e '^Uninstalled ' \"$o/err.$tl\" && (cd\
    \ \"$root/tools/$tl\" && find . | LC_ALL=C sort) | cmp -s - \"$o/files.$tl\" \\\
    \n    && cmp -s \"$o/receipt.$tl\" \"$root/tools/$tl/uv-receipt.toml\" \\\n  \
    \  || { echo \"FAIL C3-F1 ($tl): uv pip ran, the tool changed, or its receipt\
    \ did\" >&2; cat \"$o/err.$tl\" >&2; exit 1; }\n  m=0; while IFS= read -r f; do\
    \ m=$((m + 1)); mv \"$tt/f.$m\" \"$f\"; done < \"$tt/moved\"\ndone\nuvm doctor\
    \ > \"$o/doc.c3\" 2>&1 || { echo \"FAIL C3-F1: the tree is not clean once the\
    \ damage is put back\" >&2; cat \"$o/doc.c3\" >&2; exit 1; }\ngrep -q '^index\
    \ = ' \"$root/tools/wheel/uv-receipt.toml\" && grep -q '^index-url = ' \"$root/tools/chardet/uv-receipt.toml\"\
    \ && grep -q '^extra-index-url = ' \"$root/tools/markdown/uv-receipt.toml\" \\\
    \n  && grep -q '^index = .*default = true' \"$root/tools/isort/uv-receipt.toml\"\
    \ && grep -q '^find-links = ' \"$root/tools/pygments/uv-receipt.toml\" \\\n  ||\
    \ { echo \"FAIL C3-F1: setup, the index-option receipts\" >&2; exit 1; }\nfor\
    \ c in wheel:wheel chardet:chardetect markdown:markdown_py isort:isort pygments:pygmentize;\
    \ do\n  tl=\"${c%%:*}\"; n=$((n + 1)); sp=\"$root/tools/$tl/lib/python3.12/site-packages\"\
    \n  cp \"$root/tools/$tl/uv-receipt.toml\" \"$o/receipt.$tl\"; (cd \"$sp\" &&\
    \ ls -d ./*.dist-info) > \"$o/dists.$tl\"\n  for f in \"$sp\"/*.dist-info/RECORD;\
    \ do mv \"$f\" \"$t/c3r.$tl.$(basename \"$(dirname \"$f\")\")\"; done\n  UVM_REPAIR=\"\
    c3-$n\" uv --version > \"$o/out.$tl\" 2> \"$o/err.$tl\" || { echo \"FAIL C3-F1\
    \ ($tl): an index-option receipt failed the scope\" >&2; cat \"$o/err.$tl\" >&2;\
    \ exit 1; }\n  grep -q \"repairing the tool environments for [^:]*: $tl$\" \"\
    $o/err.$tl\" && [ -e \"$root/.repair/value-c3-$n.ok\" ] && (cd \"$sp\" && ls -d\
    \ ./*.dist-info) | cmp -s - \"$o/dists.$tl\" \\\n    && [ -z \"$(cd \"$sp\" &&\
    \ for d in ./*.dist-info; do [ -e \"$d/RECORD\" ] || echo \"$d\"; done)\" ] &&\
    \ cmp -s \"$o/receipt.$tl\" \"$root/tools/$tl/uv-receipt.toml\" \\\n    && \"\
    $root/bin/shims/${c#*:}\" --help > /dev/null 2>&1 \\\n    || { echo \"FAIL C3-F1\
    \ ($tl): not repaired with its versions and receipt kept\" >&2; cat \"$o/err.$tl\"\
    \ >&2; exit 1; }\ndone\n# R5, real: an orphan beside a damaged tool. The base\
    \ interpreter must not change.\nseed r5\nuv tool install pyflakes==3.2.0 --python\
    \ 3.12 > /dev/null 2>&1 && uv tool install pycowsay==0.0.0.2 --python 3.12 > /dev/null\
    \ 2>&1 || { echo \"FAIL R5: tool installs\" >&2; exit 1; }\ngut pyflakes; mv \"\
    $root/tools/pycowsay/pyvenv.cfg\" \"$t/\"\nfor d in \"$root\"/python/cpython-3.12.*/;\
    \ do [ -L \"${d%/}\" ] || base=\"${d%/}\"; done\nls -A \"$base/lib/python3.12/site-packages\"\
    \ \"$base/bin\" > \"$o/base.before\"\nif UVM_REPAIR=r5 uvx pyflakes --version\
    \ > \"$o/out\" 2> \"$o/err\"; then echo \"FAIL R5: exited 0 beside an orphan\"\
    \ >&2; exit 1; fi\ngrep 'uv-manager: the repair for' \"$o/err\" | grep pycowsay\
    \ | grep -q pyvenv.cfg || { echo \"FAIL R5: stderr does not name the orphan\"\
    \ >&2; cat \"$o/err\" >&2; exit 1; }\nls -A \"$base/lib/python3.12/site-packages\"\
    \ \"$base/bin\" > \"$o/base.after\"\ncmp -s \"$o/base.before\" \"$o/base.after\"\
    \ || { echo \"FAIL R5: the base interpreter changed\" >&2; diff \"$o/base.before\"\
    \ \"$o/base.after\" >&2; exit 1; }\ngrep -q pycowsay \"$root/.repair/value-r5.failed\"\
    \ || { echo \"FAIL R5: no failed outcome naming the orphan\" >&2; exit 1; }\n\
    # F1: a repair restores what is installed and never applies the job's Python request.\
    \ Each source\n# asks for 3.13, the control for nothing. Every round damages both\
    \ arms; the knob-set call must\n# restore 3.12.1 in place, keep the tool on 3.12.1,\
    \ and install no 3.13.\nseed req 3.12.1\nkey=$(cd \"$root/python\" && for k in\
    \ cpython-3.12.1-*; do [ -L \"$k\" ] || echo \"$k\"; done)\nuv tool install pyflakes==3.2.0\
    \ > \"$o/ti.out\" 2> \"$o/ti.err\" || { echo \"FAIL F1: tool install\" >&2; cat\
    \ \"$o/ti.err\" >&2; exit 1; }\ngrep -q '^version_info = 3\\.12\\.1$' \"$root/tools/pyflakes/pyvenv.cfg\"\
    \ || { echo \"FAIL F1: setup, the tool is not on 3.12.1\" >&2; exit 1; }\nw=\"\
    $UVM_SANDBOX/w.req\"; mkdir -p \"$w/sub\"; bad=''\nfor src in none cwd parent\
    \ global env; do\n  r=\"$t/$src\"; mkdir -p \"$r\"; mv \"$root/python/$key/lib/python3.12/json\"\
    \ \"$r/\"; gut pyflakes\n  cd \"$w\"; req=''\n  case \"$src\" in\n    cwd)   \
    \ echo 3.13 > \"$w/.python-version\" ;;\n    parent) echo 3.13 > \"$w/.python-version\"\
    ; cd \"$w/sub\" ;;\n    global) mkdir -p \"$XDG_CONFIG_HOME/uv\"; echo 3.13 >\
    \ \"$XDG_CONFIG_HOME/uv/.python-version\" ;;\n    env)    req=UV_PYTHON=3.13 ;;\n\
    \  esac\n  env $req UVM_REPAIR=\"req-$src\" uv --version > \"$o/out.$src\" 2>\
    \ \"$o/err.$src\"; rc=$?\n  cd \"$UVM_SANDBOX\"; mv \"$w/.python-version\" \"\
    $r/\" 2> /dev/null; mv \"$XDG_CONFIG_HOME/uv/.python-version\" \"$r/global\" 2>\
    \ /dev/null\n  [ \"$rc\" = 0 ] && grep -q '^uv ' \"$o/out.$src\" && [ -e \"$root/.repair/value-req-$src.ok\"\
    \ ] || bad=\"$bad $src:rc=$rc\"\n  grep -q 'repairing the managed interpreters'\
    \ \"$o/err.$src\" && grep -q 'repairing the tool environments' \"$o/err.$src\"\
    \ || bad=\"$bad $src:arms-not-both-run\"\n  \"$root/python/$key/bin/python3\"\
    \ -c 'import json' 2> /dev/null || bad=\"$bad $src:interpreter-still-damaged\"\
    \n  [ -z \"$(cd \"$root/python\" && ls -d cpython-3.13* 2> /dev/null)\" ] || bad=\"\
    $bad $src:installed-3.13\"\n  grep -q '^version_info = 3\\.12\\.1$' \"$root/tools/pyflakes/pyvenv.cfg\"\
    \ || bad=\"$bad $src:tool-moved-to-$(sed -n 's/^version_info = //p' \"$root/tools/pyflakes/pyvenv.cfg\"\
    )\"\n  \"$root/bin/shims/pyflakes\" --version 2> /dev/null | grep -q '^3\\.2\\\
    .0 Python 3\\.12\\.1 ' || bad=\"$bad $src:tool-does-not-run-on-3.12.1\"\n  if\
    \ [ -n \"$bad\" ]; then break; fi\ndone\n[ -z \"$bad\" ] || { echo \"FAIL F1:\
    \ the repair followed the job's Python request:$bad\" >&2; cat \"$o/err.$src\"\
    \ >&2; exit 1; }\n# C4-F1: both arms run from /, so the project configuration\
    \ of the job's working directory reaches\n# neither. From a project that sets\
    \ a pip target, one whose exclude-newer predates the installed\n# release, and\
    \ one that forbids Python downloads, the knob-set call repairs in place, writes\
    \ nothing\n# under the project, records the scope repaired and runs the command.\
    \ A flat index in the user's\n# uv.toml still applies to the tool arm: the tool\
    \ it alone holds is repaired from it.\nseed c4; pj=\"$UVM_SANDBOX/c4proj\"; mkdir\
    \ -p \"$pj/sub\"\nc4tool() {  # KEY TOOL FILE OUT: damage TOOL (FILE and every\
    \ RECORD moved out), repair it from $pj/sub\n  sp=\"$root/tools/$2/lib/python3.12/site-packages\"\
    ; mkdir -p \"$t/c4.$1\"; (cd \"$pj\" && find . | LC_ALL=C sort) > \"$o/pj.c4$1\"\
    \n  mv \"$sp/$3\" \"$sp\"/*.dist-info/RECORD \"$t/c4.$1/\"\n  if \"$root/bin/shims/$2\"\
    \ --version > /dev/null 2>&1; then echo \"FAIL C4-F1 ($1): setup, the damage did\
    \ not break $2\" >&2; exit 1; fi\n  (cd \"$pj/sub\" && env UVM_REPAIR=\"c4-$1\"\
    \ uvx \"$2\" --version) > \"$o/out.c4$1\" 2> \"$o/err.c4$1\" \\\n    || { echo\
    \ \"FAIL C4-F1 ($1): knob-set uvx $2 exited non-zero from the project\" >&2; cat\
    \ \"$o/err.c4$1\" >&2; exit 1; }\n  [ \"$(cat \"$o/out.c4$1\")\" = \"$4\" ] &&\
    \ [ -e \"$sp/$3\" ] && [ -z \"$(cd \"$sp\" && for d in ./*.dist-info; do [ -e\
    \ \"$d/RECORD\" ] || echo \"$d\"; done)\" ] \\\n    && \"$root/bin/shims/$2\"\
    \ --version > /dev/null 2>&1 && [ -e \"$root/.repair/value-c4-$1.ok\" ] \\\n \
    \   || { echo \"FAIL C4-F1 ($1): $2 not repaired in place, or no repaired outcome:\
    \ stdout [$(cat \"$o/out.c4$1\")]\" >&2; cat \"$o/err.c4$1\" >&2; exit 1; }\n\
    \  (cd \"$pj\" && find . | LC_ALL=C sort) | cmp -s - \"$o/pj.c4$1\" || { echo\
    \ \"FAIL C4-F1 ($1): the repair wrote under the project\" >&2; (cd \"$pj\" &&\
    \ find .) >&2; exit 1; }\n}\nq uv tool install pycodestyle==2.11.1 --python 3.12\n\
    printf '[tool.uv.pip]\\ntarget = \"tgt\"\\n' > \"$pj/pyproject.toml\"; c4tool\
    \ tgt pycodestyle pycodestyle.py 2.11.1\nprintf '[tool.uv]\\nexclude-newer = \"\
    2023-01-01T00:00:00Z\"\\n' > \"$pj/pyproject.toml\"; c4tool exn pycodestyle pycodestyle.py\
    \ 2.11.1\nprintf '[tool.uv]\\npython-downloads = \"never\"\\n' > \"$pj/pyproject.toml\"\
    ; (cd \"$pj\" && find . | LC_ALL=C sort) > \"$o/pj.c4py\"\nfor d in \"$root\"\
    /python/cpython-3.12.*/; do [ -L \"${d%/}\" ] || base=\"${d%/}\"; done\nmv \"\
    $base/lib/python3.12/json\" \"$t/c4.json\"\n(cd \"$pj/sub\" && env UVM_REPAIR=c4-py\
    \ uv run --no-project -p 3.12 \"$UVM_SANDBOX/t.py\") > \"$o/out.c4py\" 2> \"$o/err.c4py\"\
    \ \\\n  || { echo \"FAIL C4-F1 (py): knob-set uv run exited non-zero from the\
    \ project\" >&2; cat \"$o/err.c4py\" >&2; exit 1; }\n[ \"$(cat \"$o/out.c4py\"\
    )\" = 't-ok [1]' ] && \"$base/bin/python3\" -c 'import json' && [ -e \"$root/.repair/value-c4-py.ok\"\
    \ ] \\\n  || { echo \"FAIL C4-F1 (py): the interpreter not repaired, or no repaired\
    \ outcome: stdout [$(cat \"$o/out.c4py\")]\" >&2; cat \"$o/err.c4py\" >&2; exit\
    \ 1; }\n(cd \"$pj\" && find . | LC_ALL=C sort) | cmp -s - \"$o/pj.c4py\" || {\
    \ echo \"FAIL C4-F1 (py): the repair wrote under the project\" >&2; exit 1; }\n\
    fl=\"$UVM_SANDBOX/c4flat\"; mkdir -p \"$XDG_CONFIG_HOME/uv\"\n\"$base/bin/python3\"\
    \ - \"$fl\" <<'WHEEL'\nimport os, sys, zipfile\nw = sys.argv[1]; os.makedirs(w,\
    \ exist_ok=True); di = \"uvmcfour-0.1.dist-info\"\nfiles = {\"uvmcfour/__init__.py\"\
    : \"def main():\\n    print('uvmcfour 0.1')\\n\",\n         di + \"/METADATA\"\
    : \"Metadata-Version: 2.1\\nName: uvmcfour\\nVersion: 0.1\\n\",\n         di +\
    \ \"/WHEEL\": \"Wheel-Version: 1.0\\nGenerator: hand\\nRoot-Is-Purelib: true\\\
    nTag: py3-none-any\\n\",\n         di + \"/entry_points.txt\": \"[console_scripts]\\\
    nuvmcfour = uvmcfour:main\\n\"}\nfiles[di + \"/RECORD\"] = \"\".join(k + \",,\\\
    n\" for k in files) + di + \"/RECORD,,\\n\"\nwith zipfile.ZipFile(os.path.join(w,\
    \ \"uvmcfour-0.1-py3-none-any.whl\"), \"w\") as z:\n    for k, v in files.items():\n\
    \        z.writestr(k, v)\nWHEEL\nprintf '[[index]]\\nname = \"c4flat\"\\nurl\
    \ = \"%s\"\\nformat = \"flat\"\\n' \"$fl\" > \"$XDG_CONFIG_HOME/uv/uv.toml\"\n\
    q uv tool install uvmcfour --python 3.12\n[ -z \"$(find \"$root/tools/uvmcfour\"\
    \ -name direct_url.json)\" ] || { echo \"FAIL C4-F1 (idx): setup, uvmcfour recorded\
    \ as a path source\" >&2; exit 1; }\nprintf '[tool.uv.pip]\\ntarget = \"tgt\"\\\
    n' > \"$pj/pyproject.toml\"; c4tool idx uvmcfour uvmcfour/__init__.py 'uvmcfour\
    \ 0.1'\nmv \"$XDG_CONFIG_HOME/uv/uv.toml\" \"$t/c4.uv.toml\"\necho \"P3 real-uv\
    \ ok\"\nP3REAL\necho \"P3 ok\""
- id: P4
  name: 'The human path: doctor and clean over both locks and the outcomes'
  status: done
  satisfies:
  - R9
  - R13
  - R14
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\ngrep -q 'repairing the managed interpreters' bin/uv-manager ||\
    \ { echo \"FAIL: P3 has not landed\" >&2; exit 1; }\nbash -n bin/uv-manager ||\
    \ { echo \"FAIL: bash -n\" >&2; exit 1; }\n.agents/factory/bin/lint.sh >/dev/null\
    \ || { echo \"FAIL: lint.sh\" >&2; exit 1; }\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'P4' || exit 1\n# shared by the offline gates; pasted inline\
    \ into each gate in TECH.md\na=$(uname -m)\nfresh() {  # NAME: a new root of its\
    \ own, provisioned from the fixture, with tree (F) planted unless NAME ends in\
    \ .intact\n  UVM_ROOT=\"$UVM_SANDBOX/root.$1\"; export UVM_ROOT; root=\"$UVM_ROOT/$a\"\
    ; o=\"$UVM_SANDBOX/o.$1\"; mkdir -p \"$o\"\n  if ! uv --version > \"$o/warm.out\"\
    \ 2> \"$o/warm.err\"; then echo \"FAIL ($1): provisioning the fixture\" >&2; cat\
    \ \"$o/warm.err\" >&2; exit 1; fi\n  case \"$1\" in *.intact) return 0 ;; esac\n\
    \  sp=\"$root/tools/fx/lib/python3.12/site-packages\"; mkdir -p \"$sp/fx-1.0.dist-info\"\
    \n  : > \"$root/tools/fx/pyvenv.cfg\"; : > \"$root/tools/fx/uv-receipt.toml\"\
    ; mkdir -p \"$root/tools/fx/bin\"; ln -s /bin/sh \"$root/tools/fx/bin/python\"\
    \n  printf 'fx/__init__.py,,\\n' > \"$sp/fx-1.0.dist-info/RECORD\"\n}\nlines()\
    \ { cat \"$@\" 2>/dev/null | grep -c -e 'pip install' -e 'python install'; }\n\
    ranks() {  # N CMD...: N concurrent calls, each with its own out/err/rc under\
    \ $o\n  n=\"$1\"; shift; i=1; pids=''\n  while [ \"$i\" -le \"$n\" ]; do ( \"\
    $@\" > \"$o/out.$i\" 2> \"$o/err.$i\"; echo $? > \"$o/rc.$i\" ) & pids=\"$pids\
    \ $!\"; i=$((i + 1)); done\n  wait $pids\n}\nplantlock() {  # KIND: a live holder\
    \ that never releases\n  mkdir -p \"$root/.$1.lock\"; sleep 60 & printf 'host=%s\
    \ pid=%s nonce=plant-%s\\n' \"$(uname -n)\" \"$!\" \"$1\" > \"$root/.$1.lock/owner\"\
    \n  cp \"$root/.$1.lock/owner\" \"$o/planted\"\n}\nset -u\n# R13 (c): doctor names\
    \ a planted repair lock; the dry run keeps it; --yes removes both locks.\nfresh\
    \ r13c; plantlock repair\nuvm doctor > \"$o/doc\" 2>&1\ngrep -q \"^WARN  repair\
    \ lock standing: $root/.repair.lock (owner: $(cat \"$o/planted\"))\" \"$o/doc\"\
    \ || { echo \"FAIL R13c: doctor does not name the repair lock and its owner line\"\
    \ >&2; cat \"$o/doc\" >&2; exit 1; }\nuvm clean lock > \"$o/dry\" 2>&1; grep -F\
    \ -q \"$(cat \"$o/planted\")\" \"$o/dry\" && [ -d \"$root/.repair.lock\" ] ||\
    \ { echo \"FAIL R13c: the dry run removed the lock or hid its owner\" >&2; cat\
    \ \"$o/dry\" >&2; exit 1; }\nuvm clean lock --yes > /dev/null 2>&1\n[ ! -e \"\
    $root/.repair.lock\" ] && [ -x \"$root/current/uv\" ] || { echo \"FAIL R13c: clean\
    \ lock left the repair lock or broke current\" >&2; exit 1; }\n# R9 (c): four\
    \ ranks, the holder killed with KILL mid-repair.\nfresh r9c\ni=1; while [ $i -le\
    \ 4 ]; do\n  ( env UVM_LOCK_TIMEOUT=4 SLURM_JOB_ID=200 UVM_REPAIR=1 UVM_FIXTURE_REPAIR_SLEEP=10\
    \ uv --version > \"$o/out.$i\" 2> \"$o/err.$i\"; echo $? > \"$o/rc.$i\" ) &\n\
    \  pids=\"${pids:-} $!\"; i=$((i + 1)); done\nw=0; while [ ! -s \"$root/.repair.lock/owner\"\
    \ ] && [ $w -lt 50 ]; do sleep 0.1; w=$((w + 1)); done\nsleep 1; owner=$(cat \"\
    $root/.repair.lock/owner\"); pid=${owner##*pid=}\n[ -n \"$pid\" ] || { echo \"\
    FAIL R9c: no holder to kill\" >&2; exit 1; }\n# The wrapper alone, as a node failure\
    \ would take it; its repair child runs on and records nothing.\nkill -KILL \"\
    $pid\"; wait $pids\nkilled=0 timedout=0; i=1\nwhile [ $i -le 4 ]; do\n  r=$(cat\
    \ \"$o/rc.$i\")\n  if [ \"$r\" = 137 ]; then killed=$((killed + 1))\n  elif [\
    \ \"$r\" != 0 ] && grep -q \"timed out after 4s waiting for the repair lock at\
    \ $root/.repair.lock\" \"$o/err.$i\" && grep -F -q \"$owner\" \"$o/err.$i\"; then\
    \ timedout=$((timedout + 1)); fi\n  i=$((i + 1)); done\n[ \"$killed\" = 1 ] &&\
    \ [ \"$timedout\" = 3 ] || { echo \"FAIL R9c: killed=$killed, waiters failing\
    \ at the timeout naming the lock=$timedout/3\" >&2; cat \"$o\"/err.* >&2; exit\
    \ 1; }\n[ -z \"$(ls -A \"$root/.repair\" 2>/dev/null)\" ] || { echo \"FAIL R9c:\
    \ an outcome was recorded by a killed holder: $(ls -A \"$root/.repair\")\" >&2;\
    \ exit 1; }\nuvm doctor > \"$o/doc\" 2>&1; grep -q \"^WARN  repair lock standing:\
    \ $root/.repair.lock\" \"$o/doc\" || { echo \"FAIL R9c: doctor does not WARN the\
    \ leaked repair lock\" >&2; exit 1; }\nuvm clean lock --yes > /dev/null 2>&1\n\
    env SLURM_JOB_ID=200 UVM_REPAIR=1 uv --version > \"$o/out\" 2> \"$o/err\" || {\
    \ echo \"FAIL R9c: the call after uvm clean lock failed\" >&2; cat \"$o/err\"\
    \ >&2; exit 1; }\n[ \"$(lines \"$o/err\")\" -eq 1 ] && [ -e \"$root/.repair/job-200.ok\"\
    \ ] || { echo \"FAIL R9c: the call after uvm clean lock did not repair\" >&2;\
    \ exit 1; }\n# A failed outcome under a constant value: doctor names it; uvm clean\
    \ outcomes removes it.\nfresh human\nif env -u SLURM_JOB_ID UVM_REPAIR=k UVM_FIXTURE_REPAIR_EXIT=1\
    \ uv --version > /dev/null 2>&1; then echo \"FAIL: setup, the failing repair exited\
    \ 0\" >&2; exit 1; fi\nuvm doctor > \"$o/doc\" 2>&1\ngrep -q '^WARN  repair failed\
    \ for UVM_REPAIR=k: the tool environment repair failed' \"$o/doc\" && grep -q\
    \ 'uvm clean outcomes --yes' \"$o/doc\" || { echo \"FAIL: doctor does not report\
    \ the failed outcome\" >&2; cat \"$o/doc\" >&2; exit 1; }\nuvm clean outcomes\
    \ > \"$o/dry\" 2>&1; grep -q '1 failed' \"$o/dry\" && [ -e \"$root/.repair/value-k.failed\"\
    \ ] || { echo \"FAIL: the outcomes dry run\" >&2; cat \"$o/dry\" >&2; exit 1;\
    \ }\nuvm clean outcomes --yes > /dev/null 2>&1; [ ! -e \"$root/.repair\" ] ||\
    \ { echo \"FAIL: uvm clean outcomes --yes left the records\" >&2; exit 1; }\n\
    env -u SLURM_JOB_ID UVM_REPAIR=k uv --version > \"$o/out\" 2> \"$o/err\" && [\
    \ \"$(lines \"$o/err\")\" -eq 1 ] || { echo \"FAIL: after uvm clean outcomes the\
    \ value did not repair again\" >&2; exit 1; }\necho \"P4 drives ok\"\nP4\nh=$(.agents/factory/bin/temp_root.sh\
    \ uvm help)\nfor w in UVM_REPAIR outcomes; do echo \"$h\" | grep -q \"$w\" ||\
    \ { echo \"FAIL R14: uvm help does not mention $w\" >&2; exit 1; }; done\nn=$(git\
    \ grep -l UVM_REPAIR -- bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua\
    \ AGENTS.md .agents/factory/invariants.md | wc -l | tr -d ' ')\n[ \"$n\" -eq 6\
    \ ] || { echo \"FAIL R14: UVM_REPAIR appears in $n of the six surfaces\" >&2;\
    \ git grep -c UVM_REPAIR -- bin/uv-manager README.md etc/uv-manager.conf.example\
    \ share/modulefiles/uv/main.lua AGENTS.md .agents/factory/invariants.md >&2; exit\
    \ 1; }\nfor f in README.md share/modulefiles/uv/main.lua; do\n  for w in 'repair\
    \ lock' 'uvm clean outcomes' 'SLURM_JOB_ID' 'releases.astral.sh' 'uvx'; do\n \
    \   grep -q \"$w\" \"$f\" || { echo \"FAIL R14: $f does not mention $w\" >&2;\
    \ exit 1; }\n  done\ndone\ngrep -q 'pip install --python' bin/uv-manager && sed\
    \ -n '/^uvm_doctor() {/,/^}/p' bin/uv-manager | grep -q UVM_REPAIR || { echo \"\
    FAIL R14: doctor's remediation block does not name UVM_REPAIR\" >&2; exit 1; }\n\
    echo \"P4 ok\""
- id: P5
  name: 'Cross-node drive on Lustre and GPFS (external wait: Run A, then Run B)'
  status: done
  satisfies:
  - R12
  depends_on:
  - P4
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -u\ntest -x tests/repair-race.sh || { echo \"FAIL: P5 Run A has not\
    \ landed (tests/repair-race.sh)\" >&2; exit 1; }\nbash -n bin/uv-manager || {\
    \ echo \"FAIL: bash -n\" >&2; exit 1; }\n.agents/factory/bin/lint.sh >/dev/null\
    \ || { echo \"FAIL: lint.sh\" >&2; exit 1; }\nenv -u REPAIRRACE_SHARED tests/repair-race.sh\
    \ --scenario F --launch srun > /dev/null 2>&1; [ $? -eq 2 ] || { echo \"FAIL:\
    \ --launch srun without REPAIRRACE_SHARED must exit 2\" >&2; exit 1; }\ns=\"$(mktemp\
    \ -d \"${TMPDIR:-/tmp}/p5.XXXXXX\")\"\ntests/repair-race.sh --scenario F --ranks\
    \ 16 --summary \"$s/F.txt\" > /dev/null || { echo \"FAIL: local F run\" >&2; cat\
    \ \"$s/F.txt\" >&2; exit 1; }\ngrep -q '^repairs=1$' \"$s/F.txt\" && grep -q '^rc_hist=0:16$'\
    \ \"$s/F.txt\" || { echo \"FAIL: local F summary\" >&2; cat \"$s/F.txt\" >&2;\
    \ exit 1; }\n# Real uv and network (pypi.org, files.pythonhosted.org, releases.astral.sh),\
    \ seeded from a local uv.\nu=$(command -v uv); case \"$u\" in ''|\"$PWD\"/bin/*)\
    \ echo \"FAIL: need a real uv on PATH\" >&2; exit 1 ;; esac\nfor sc in T P kill;\
    \ do\n  tests/repair-race.sh --scenario \"$sc\" --ranks 8 --uv-bin \"$u\" --summary\
    \ \"$s/$sc.txt\" > /dev/null || { echo \"FAIL: local $sc run\" >&2; cat \"$s/$sc.txt\"\
    \ >&2; exit 1; }\ndone\n# The trees a purge leaves: T's unpinned tool keeps its\
    \ versions and receipts, with no second\n# dist-info; P's interpreter, every file\
    \ of it removed, comes back.\nfor k in unpinned_version=2.11.1 unpinned_with=1.16.0\
    \ second_dist_info=0 receipts_kept=2 restored=1; do grep -q \"^$k$\" \"$s/T.txt\"\
    \ || { echo \"FAIL: local T summary lacks $k\" >&2; cat \"$s/T.txt\" >&2; exit\
    \ 1; }; done\ngrep -q '^restored=1$' \"$s/P.txt\" && grep -q '^repairs=1$' \"\
    $s/P.txt\" || { echo \"FAIL: local P summary\" >&2; cat \"$s/P.txt\" >&2; exit\
    \ 1; }\nif grep -n -e '/' -e \"$(uname -n)\" \"$s\"/*.txt; then echo \"FAIL: a\
    \ local summary carries a path or this host's name\" >&2; exit 1; fi\nfor fs in\
    \ lustre gpfs; do\n  e=\"spec/purge-tree-repair/evidence/$fs.txt\"\n  test -s\
    \ \"$e\" || { echo \"FAIL: cluster evidence $e not recorded yet (the external\
    \ wait)\" >&2; exit 1; }\n  if grep -n -e '/' \"$e\"; then echo \"FAIL: $e carries\
    \ a path\" >&2; exit 1; fi\n  for sc in P T kill; do grep -q \"^scenario=$sc$\"\
    \ \"$e\" || { echo \"FAIL: $e lacks scenario $sc\" >&2; exit 1; }; done\n  [ \"\
    $(grep -c '^exit=0$' \"$e\")\" -eq 3 ] && [ \"$(grep -c '^progress=ok$' \"$e\"\
    )\" -eq 3 ] || { echo \"FAIL: $e: a scenario did not exit 0 with progress=ok\"\
    \ >&2; exit 1; }\n  for k in repairs outcomes; do [ \"$(grep -c \"^$k=1$\" \"\
    $e\")\" -eq 2 ] || { echo \"FAIL: $e: $k=1 in P and T\" >&2; exit 1; }; done\n\
    \  [ \"$(grep -c '^locks_left=0$' \"$e\")\" -eq 2 ] && grep -q '^clean_locks_left=0$'\
    \ \"$e\" || { echo \"FAIL: $e: a lock was left\" >&2; exit 1; }\n  grep '^ranks='\
    \ \"$e\" | while IFS== read -r _ n; do [ \"$n\" -ge 64 ] || { echo \"FAIL: $e:\
    \ ranks=$n under 64\" >&2; exit 1; }; done || exit 1\n  grep -q '^stdout_hist=expected:[0-9]*$'\
    \ \"$e\" && grep -q '^stdout_hist=3\\.2\\.0:[0-9]*$' \"$e\" || { echo \"FAIL:\
    \ $e: stdout_hist\" >&2; exit 1; }\n  for k in unpinned_version=2.11.1 unpinned_with=1.16.0\
    \ second_dist_info=0 receipts_kept=2; do grep -q \"^$k$\" \"$e\" || { echo \"\
    FAIL: $e: scenario T lacks $k\" >&2; exit 1; }; done\n  [ \"$(grep -c '^restored=1$'\
    \ \"$e\")\" -eq 2 ] && grep -q '^clean_restored=1$' \"$e\" || { echo \"FAIL: $e:\
    \ the damage was not restored\" >&2; exit 1; }\n  for k in killed doctor_warn_repair_lock\
    \ clean_repairs clean_outcomes; do grep -q \"^$k=1$\" \"$e\" || { echo \"FAIL:\
    \ $e: kill scenario $k\" >&2; exit 1; }; done\n  grep -q '^hold_s=[0-9]' \"$e\"\
    \ && grep -q '^notice_lines=' \"$e\" || { echo \"FAIL: $e: hold or notice keys\"\
    \ >&2; exit 1; }\ndone\ngrep -q '^nodes=2$' spec/purge-tree-repair/evidence/lustre.txt\
    \ || { echo \"FAIL: lustre evidence not across 2 nodes\" >&2; exit 1; }\necho\
    \ \"P5 ok\""
review:
  last_reviewed_commit: 55cddf7
  verdict: approved
  blocked_reason: ''
  cycle: 4
---
# TECH.md — `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`

The **context engine and finite-state machine** for building this feature. The YAML frontmatter above
is the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/purge-tree-repair/TECH.md`); the per-phase checklists
below are the work. `uvm-build` executes the next actionable phase, runs its `verify:` command
(`uv run .agents/factory/bin/run_verify.py spec/purge-tree-repair/TECH.md --phase P<n>`), updates
state via `uv run .agents/factory/bin/set_phase.py …`, and makes one atomic code-plus-state commit.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md). R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus briefs 01-04.

## Frontmatter field reference

See [`templates/TECH.md`](../../.agents/factory/templates/TECH.md). Every phase here is
`parallel: false` (one source file) and `hammerable: false` (each touches §1-§11).

## Gate notes (read before retuning any gate)

Every gate below was run green against a prototype in a throwaway copy, and red against this
branch's HEAD at plan time (PLAN §6). Each runs under `/bin/sh` from the repository root. They share
four helpers, pasted inline into each offline gate:

- `fresh NAME` gives a new root of its own, provisions the fixture, and plants tree (F) unless NAME
  ends in `.intact`.
- `lines FILE…` counts lines naming `tool upgrade` or `python install`.
- `ranks N CMD…` runs N concurrent calls and waits on their own pids.
- `plantlock KIND` plants a live holder that never releases.

Traps these gates already avoid, which a retune must keep avoiding:

- **No `VAR=x` in front of a shell function.** POSIX `sh` keeps the assignment after the call. `VAR=x
  ranks …` leaked `UVM_REPAIR` into the next drive's provisioning call, which recorded an outcome
  before the damage existed. Pass variables through `env` on the command.
- **No bare `wait`.** It also waits for a planted holder's `sleep 60`. Wait on named pids.
- **No `\|` in `sed` or `grep` basic regexps.** BSD treats it as a literal. Use `grep -o -e … -e …`.
- **No message on the `uv` and `uvx` path names `tool upgrade` or `python install`.** The fixture
  stub echoes its own command line, and those lines are the repair count. A note or a failure reason
  naming the command double-counts and breaks R7, R9 and R10 at once. Doctor's remediation block
  names both; it runs only under `uv-manager`, which no drive counts.
- **Sort listings under `LC_ALL=C`.** A gate comparing `ls -A` of `.repair/` against a fixed string
  of escaped names (`value-run_201.ok value-run_2F1.ok …`) depends on collation otherwise.
- **No `rm` inside a drive.** The agent harness refuses `rm` written inline in `sh -c`. Each drive
  uses a fresh root, and damage is `mv` into a trash directory.
- **Real uv comes from `command -v uv` outside `temp_root.sh`.** It is passed in as `SEED_UV` and
  `SEED_UVX`, because the scrub removes only `UV_*` and `UVM_*`, and is copied into `versions/<ver>/`.
  The installer cannot run in the agent sandbox (its `mktemp -d` is denied). This is a harness step,
  never product code.
- **`date +%s` only.** `%N` is GNU-only.

**The real-uv gates (P3, P5) need network.** Declare `pypi.org`, `files.pythonhosted.org` and
`releases.astral.sh`, and export `UV_CACHE_DIR` and `UV_TOOL_DIR` to scratch for `lint.sh`. A red
that names `uv python install 3.12 (network?)` or `tool install` is the environment, not the code. Do
not `--record-attempt` it. Fix the access and re-run.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md). Consult [`invariants.md`](../../.agents/factory/invariants.md)
  §1, §2, §4, §5, §7, §8, §10 for this change.
- One phase per `uvm-build` invocation; one atomic commit with **both** the code and the `TECH.md`
  state change. Subjects follow `[feature] Build purge-tree-repair P<n>: …`.
- Keep the `Co-Authored-By` trailer.
- A behavior change updates the `uvm_help` heredoc, `README.md`, `etc/uv-manager.conf.example` and
  `share/modulefiles/uv/main.lua` (whichever it invalidates) **in the same commit**. A phase that
  changes §5 also updates `AGENTS.md` § Invariants and `invariants.md` in that commit. PLAN §2
  *User-facing surface* says which phase owns which sentence.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager` or `README.md`.
- No wrapper message names the repair commands (see *Gate notes*).
- **No step and no subagent uses any cluster tool**, meaning any tool of a cluster MCP server.
  Remote commands need the maintainer's per-task approval. The only approved class is the
  foreman's test jobs, which the foreman submits. Put this line in any sub-brief a phase writes.

---

## Phase P1 — The lock takes its name
**Satisfies:** R13 (the lock and its wording) · **Depends on:** —
**Goal:** `uvm_acquire_lock LOCK ON_TIMEOUT PREDICATE [ARG...]`. A repair caller gets its own lock
and its own words, and provisioning is byte-identical. This isolates the one edit to the
highest-blast-radius function in a commit whose only regression drive is the lock's own.

- [x] `uvm_acquire_lock` (research 01):
  - Arity becomes `(( $# >= 3 ))`, keeping the comment on why an explicit count.
  - `local kind="$1" on_timeout="$2"; shift 2`; the lock is `${uvm_root}/.${kind}.lock`.
  - A `case` sets `what` (`provisioning lock` | `repair lock`) and `doing` (`provisioning` |
    `repairing`). Anything else dies `uvm_acquire_lock: unknown lock: <name>`.
  - The five message sites use `${what}` and `${doing}`.
  - Rewrite the header comment's argument list.
- [x] `uvm_install`: `uvm_acquire_lock install proceed "${satisfied[@]}"`.
- [x] `invariants.md` §5: the quoted signature becomes `uvm_acquire_lock LOCK ON_TIMEOUT PREDICATE
  [ARG...]`. Add one clause saying LOCK names the lock and the message words. No user-facing surface
  changes in this phase.
- **Verify:** the frontmatter gate.
  - The two lock functions are extracted *by name* and sourced. A repair caller on a held
    `.repair.lock` with a 2 s timeout fails, runs no critical section, says `timed out after 2s
    waiting for the repair lock at <path>` and `If nothing is repairing this tree`, carries the
    owner line, says nothing of provisioning, never creates `.install.lock`, and leaves the plant
    intact.
  - An unknown name dies naming it.
  - Provisioning past a held `.install.lock` prints the notice unchanged, proceeds, and creates no
    `.repair.lock`.
  - `tests/lock-race.sh` control, held and pin give `progress=ok`.
  - The old signature is absent from `bin/uv-manager`, `AGENTS.md` and `invariants.md`.
  - Observed at plan time: HEAD red at the first assertion (`returned (rc 0)`), because `repair` is
    read as ON_TIMEOUT and the lock taken is `.install.lock`.
- **Touches:** `bin/uv-manager`, `.agents/factory/invariants.md`.

## Phase P2 — The knob repairs a damaged tree once per scope (offline core)
**Satisfies:** R1, R2, R3 (fixture halves), R7, R8, R9 (a, b, d), R10, R13 (a, b, d), R14 (census) ·
**Depends on:** P1
**Goal:** `UVM_REPAIR` on the dispatch:
- the scope key and the outcome store;
- the repair lock with `uvm_repair_recorded` as predicate;
- `uvm_detect` extracted from `uvm_doctor`;
- the tool arm, failure recording, and the waiters' path;
- the fixture knobs that let the gates drive all of it;
- the documentation of everything above.

- [x] Fixture (`.agents/factory/fixtures/uv-install/install.sh`): three knobs, documented in its
  header.
  - `UVM_FIXTURE_MARK`: the stub creates this file whenever it runs a non-repair command. `uvx`
    too.
  - `UVM_FIXTURE_REPAIR_SLEEP`.
  - `UVM_FIXTURE_REPAIR_EXIT`: default 0, and `UVM_FIXTURE_EXIT` does not reach it.
  - A repair command is `tool upgrade …` or `python install …`. The stub echoes its line, then
    sleeps, then exits.
- [x] `uvm_detect`. Move `uvm_doctor`'s walk into it unchanged in its findings, and add the flags
  (PLAN §2 table): `uvm_damaged_tools`, `uvm_damaged_pythons`, `uvm_orphans`, `uvm_receiptless`.
  `uvm_doctor` calls it and keeps its own locals. Doctor's output on a tree without new state is
  unchanged.
- [x] Rename the banner to `# ---- locks`; update `AGENTS.md`'s section list.
- [x] New `# ---- purge repair` section before the dispatch, with a banner on why:
  - the knob fires on the executing node;
  - an outcome records a check, never integrity;
  - the job scope;
  - the false-clean reason for a constant value.

  It holds:
  - `uvm_repair_recorded`;
  - `uvm_repair_run`, tool arm only in this phase: `note` each finding, then `note "repairing the
    tool environments for ${arch}"` and the arm with `>&2`. The reason is "the tool environment
    repair failed", plus the receipt-less clause;
  - `uvm_repair`, PLAN §2's pseudo-code:
    - the key: `job-[<SLURM_CLUSTER_NAME>-]<SLURM_ARRAY_JOB_ID, else SLURM_JOB_ID>` inside Slurm,
      else `value-<UVM_REPAIR>`, with the listed character class and the 200-byte bound. The scope
      text in messages is `Slurm job <array id, else job id>`;
    - the `.ok` fast path;
    - `uvm_install`'s three-test shape around `uvm_acquire_lock repair fail uvm_repair_recorded`;
    - `mkdir -p` under `umask 077`;
    - the record before `uvm_unlock`;
    - the `.failed` read and `die "the repair for <scope> failed: <reason>"`, with a second line
      saying nothing retries in this scope (and, inside Slurm, that it ends with the job).
- [x] Dispatch: after `uvm_export_env`, `if [[ -n "${UVM_REPAIR:-}" && "${UVM_REPAIR}" != 0 ]];
  then uvm_repair; fi`, with a one-line comment. Rewrite the pre-exec `uvm_unlock` comment, which
  claims nothing takes a lock this late.
- [x] `uvm_help`: the `UVM_REPAIR` row (values, `00` and `false` are on, scope); the
  `UVM_LOCK_TIMEOUT` row (PLAN §2).
- [x] Same commit, per PLAN §2 *User-facing surface* (P2 row) and research 04 Q5:
  - `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`;
  - `AGENTS.md` (§ Invariants for two locks, the execution-model diagram, the high-risk table);
  - `invariants.md` (§5 for two locks; the "this late" bullet; the high-blast list adds
    `uvm_repair`);
  - doctor's remediation block naming `UVM_REPAIR=1`.

  State that one repair covers a whole Slurm allocation, because every step shares `SLURM_JOB_ID`,
  and a whole array, because every task shares `SLURM_ARRAY_JOB_ID`. State the limit that
  remains: separately submitted jobs starting together each walk the tree in turn under the repair
  lock, and any job past `UVM_LOCK_TIMEOUT / w` fails (`issues/repair-scope-queueing.md`).
- Amended at build, 2026-10-29: `uvm_damaged_pythons` moves to P3. Nothing in P2 reads it, so
  shellcheck fails lint on it (SC2034), and a disable directive would carry a comment that is false
  until the interpreter arm exists. P2's `uvm_detect` sets `uvm_damaged_tools`, `uvm_orphans` and
  `uvm_receiptless`; a dangling `bin/python-shims` entry and a failed stdlib probe set no flag yet.
  Likewise the user-facing text that describes the interpreter arm (its download host
  `releases.astral.sh`, and interpreter damage among what the repair handles in `README.md`, the
  conf example and the modulefile) lands with the arm in P3, so each commit documents what it does.
- **Verify:** the frontmatter gate (offline), in order:
  - the P1 guard; `bash -n`; lint;
  - **R1**: 16 ranks with the knob unset, then empty and `0`. All exit 0 with the fixture version,
    no repair line on either stream, and the root holds exactly `bin cache current python tools
    versions`;
  - **R2**: a planted `value-t.failed` fails the call with the planted reason, runs nothing, no
    repair line, no lock. A planted `value-t.ok` gives the fixture version with no line and no lock;
  - **R3** fixture halves: tree F with no outcome gives one line on stderr and none on stdout, plus
    `value-t.ok`. An intact tree gives no line and `value-t.ok`. Under `UVM_PIN=9.9.9` with 10.0.0
    on offer, `current` stays `versions/9.9.9`;
  - **R7**: 16 ranks, job 100, the repair held 4 s. Exactly 1 line, 16/16 fixture version, only
    `job-100.ok`, no lock, at most 9 s;
  - **R9 (d)**: the same, failing. 1 line, 16/16 non-zero with empty stdout, each naming `the repair
    for Slurm job 100 failed: the tool environment repair failed`, at most 8 s, a `.failed` record,
    no lock;
  - **R8**: rc 7, stdout exactly `uv-fixture: run app`, one line on stderr;
  - **R9 (a)**: the reason line; no marker; a `.failed` record. A second call fails the same way with
    no repair line;
  - **R9 (b)** and **R13 (d)**: a held repair lock and a 3 s timeout. Fails in 3-6 s naming the path
    and owner line, no marker, plant intact, `repair lock` at least twice, no `provisioning`;
  - **R10**: `0` gives nothing; jobs 100, 100, 101 give 2 lines. Two tasks of array 300 give 1
    line and only `job-300.ok`. `SLURM_CLUSTER_NAME=cx` gives `job-cx-300.ok`. Values a, a, b give
    2;
  - **R13 (a)**: a held `.install.lock` does not slow a repair (under 5 s, 1 line, plant intact);
  - **R13 (b)**: a held repair lock does not slow provisioning;
  - help census;
  - six-file census.

  Observed at plan time:
  - HEAD red at the P1 guard;
  - with the guard removed, on HEAD, R1 passes (the regression half) and the first red is `FAIL R2:
    a failed outcome for the scope did not fail the call (stdout [uv 9.9.9 (fixture)])`, which
    matches GOAL's observed state;
  - the prototype is green in about 15 s.
- **Inspection-only:**
  - The unset path forks nothing, and the 200-call timing against `main` (PLAN §5).
  - The outcome test precedes every walk.
  - The walk runs only after the lock is won.
  - Each documentation sentence against R14's list.
- **Review cycle 1 remediation (2026-10-29), reopened for R1, R10 and R14 prose:**
  - [x] **F2.** A repaired record stays array-wide (`job-[<cluster>-]<SLURM_ARRAY_JOB_ID, else
    SLURM_JOB_ID>.ok`); a failed one is the task's (`job-[<cluster>-]<SLURM_JOB_ID>.failed`), so the
    predicate passes a waiter of any task on the array's repair, and after another task's holder
    fails a waiter takes the lock and tries itself. The die text names the task and says the array's
    next task checks again; doctor's job count says an array's tasks share only a repaired record.
    README, the conf example and the modulefile say what an array shares, and README concedes that
    the array-wide record outlives a purge landing partway through the array. GOAL R10, its *Checked
    by* and the *Scope* term are amended, with a dated clarification (foreman's ruling).
  - [x] **F5.** `uvm_repair_encode` writes every byte outside `[A-Za-z0-9.-]`, `_` included, as `_`
    and two hex digits, with `printf -v` under `LC_ALL=C`, restoring the caller's `LC_ALL` whether
    set or unset. The 200-byte cap applies to the encoded name. Doctor decodes the value
    (`uvm_repair_decode`).
  - [x] **F3.** README and `AGENTS.md` say what R1 measures: no fork, and a cost of parsing the
    added code. `invariants.md` §10 likewise. The review measured about 0.4 ms per call at
    `7b4c960`; this remediation adds code, so it was measured again: 800 interleaved warm fixture
    `uv --version` calls per arm, medians `main` 12.10 ms, `32d7cbe` 12.53 ms, remediated 12.71 ms
    (two runs agreeing within 0.03 ms). The prose says about 0.6 ms.
  - [x] **F6.** `AGENTS.md` scopes the "no message names the repair commands" sentence to the `uv`
    and `uvx` path; the gate notes above likewise.
  - The retuned gate adds: array tasks 401 and 402 failing in turn and 403 repairing (3 lines,
    `job-400.ok job-401.failed job-402.failed`); 16 ranks over two tasks of array 500, repairing (1
    line, `job-500.ok`) and failing (2 lines, each rank naming its own task); `run/1`, `run 1`,
    `run_1`, `run:1` twice each (4 lines, 4 records); a UTF-8 value (`value-r_C3_A9.ok`); 66 `/`
    refused at 204 encoded bytes; doctor decoding `run/1 x_y`; and the encoder extracted by name,
    under `LC_ALL=en_US.UTF-8` and with `LC_ALL` unset.
  - Observed: each new block run alone against `32d7cbe`'s `bin/uv-manager` is red (`task 401's
    failure does not name the task`; `1 repair lines across two failing tasks`; `gave 1 repair lines
    and [value-run_1.ok ]`; `doctor does not decode`; `uvm_repair_encode not found by name`), except
    the repairing array race, which guards the waiter's predicate and is green on both. The whole
    gate is green after, in about 25 s.
  - Gate setup retuned at P3's cycle-2 remediation (2026-10-29), phase left `done`: tree F's tool
    gets a `bin/python`, which the tool arm's guard now requires, and `lines()` counts `pip install`,
    the tool arm's command, in place of `tool upgrade`. No assertion changed; green after.
- **Review cycle 2 remediation (2026-10-29), reopened for R1, R10 and R14** (REVIEW.md rulings 3, 4,
  6, 7 and 8):
  - [x] **C2-F7.** `uvm_repair` takes an array task to be one with `SLURM_ARRAY_TASK_ID` set, not
    one whose two ids differ, so the array's first task (`SLURM_JOB_ID == SLURM_ARRAY_JOB_ID`) gets
    the array's wording and its repaired record is the array's. Every other record, a failed one in
    an array included, is keyed on the task's own job id, as before.
  - [x] **C2-F4.** The length limit is documented with the values: a value may be 194 bytes, each
    byte outside `A-Z a-z 0-9 . -` counting as three (the record name is `value-` plus the encoded
    value, at most 200). In the help, README (prose and reference table), the conf example and the
    modulefile.
  - [x] **C2-F6.** The help, the conf example and the modulefile each carry the knob, its values, its
    scope and the limit, and point to README's *Repairing inside a job*; the modulefile gains the
    values. GOAL R14 is read per surface by a dated clarification.
  - [x] **C2-F3 (deferred by ruling 3).** README *Many jobs at once* states the arithmetic: the job
    in place `k` waits about `(k - 1) × w`, so about `UVM_LOCK_TIMEOUT / w + 1` jobs starting within
    one check get through, with two worked figures, and a job failing there changed nothing.
  - [x] **C2-F8.** GOAL R1's *Checked by* says what the measurement shows, by a dated clarification.
    No code change.
  - The retuned gate: every array drive sets `SLURM_ARRAY_TASK_ID` as Slurm does (a setup the change
    requires); new, the array's first task failing gets "the array's next task checks again" and the
    next task then repairs under the array's id (`job-600.failed job-600.ok`); the help, the conf
    example and the modulefile each carry `UVM_REPAIR`, `empty`, `Slurm job`, the per-run advice,
    `194 bytes` and `README`, and README carries `194`, `SLURM_ARRAY_TASK_ID` and the queue's
    arithmetic.
  - Observed: against `abf84b9` the first-task block is red at `the array's first task gets the
    plain-job wording`, and the census, with `abf84b9`'s documentation, at `does not carry [194
    bytes]` (the help, first). Green after.
- **Review cycle 3 remediation (2026-10-29), reopened for R10** (REVIEW.md ruling 2, and ruling 6's
  case-collision drive):
  - [x] **C3-F2.** `uvm_repair_encode`'s class is `a-z 0-9 . -`: every uppercase letter is written as
    `_` and two hex digits, so `Run1` is `_52un1` and no two values share a record on a filesystem
    that ignores case. The 200-byte limit applies to the encoded name, so an uppercase letter costs
    three bytes, and the help, README (prose and reference table), the conf example and the
    modulefile say so where they state the limit. `AGENTS.md` and `invariants.md` §10 name the class
    and the case-insensitive filesystem. Doctor decodes as before. GOAL amended by a dated
    clarification.
  - The retuned gate adds: 66 uppercase letters refused at `204 bytes`; `UVM_REPAIR=Run1` then
    `run1` on the local filesystem (APFS, case-insensitive) give two repair lines and the records
    `value-_52un1.ok value-run1.ok`; the failing value for doctor's decode becomes `Run/1 x_y`, with
    its record `value-_52un_2F1_20x_5Fy.failed`; the encoder unit check takes `Ar\303\251 _Z` to
    `_41r_C3_A9_20_5F_5A`; the census asks each of the help, the conf example and the modulefile for
    `uppercase`, and README for `uppercase` and `` `Run1` and ``.
  - Observed: against `ec319dc`'s `bin/uv-manager`, red at `FAIL C3-F2: 66 uppercase letters were
    accepted`, and with that check cut, at `FAIL C3-F2: Run1 then run1 gave 1 repair lines and
    [value-Run1.ok ]`, which is C3-F2 itself on this host's APFS. Green after, in about 25 s.
- **Review cycle 4 fix (2026-10-30), for R1** (REVIEW.md, *Maintainer decision*, ruling 2):
  - [x] **C4-F2.** Documentation only. `invariants.md` §2 states the exception to "`--dry-run` and
    `-h/--help` answer without the network": with `UVM_REPAIR` on, the repair runs first on every
    invocation, help and dry-run included, as GOAL R1 and README *Reach* already say. `AGENTS.md`
    does not restate that line of §2, so it is unchanged. No code change; the gate is unchanged and
    green.
- **Touches:**
  - `bin/uv-manager`;
  - `.agents/factory/fixtures/uv-install/install.sh`;
  - `README.md`, `etc/uv-manager.conf.example`, `share/modulefiles/uv/main.lua`;
  - `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P3 — The interpreter arm, the orphan refusal, and real uv
**Satisfies:** R3 (real), R4, R5, R6 · **Depends on:** P2
**Goal:** complete the arms, then prove them against real damaged trees.

- [x] `uvm_repair_run`, before the tool arm:
  - **The orphan refusal.** If `uvm_orphans` is non-empty, set the reason to "tool <first> has no
    pyvenv.cfg, so no automated repair is safe; remove <tools>/<first> and install the tool again"
    and return before any arm. Comment why: uv exits 0 while it writes into the base interpreter.
  - **The interpreter arm.** If `uvm_damaged_pythons` is set and a `python/*/` directory exists,
    `note "repairing the managed interpreters for ${arch}"` and run `python install --reinstall >&2`.
    The reason is "the managed interpreter repair failed (uv exited N)". Comment why it is guarded:
    with nothing installed, uv installs a pre-release.
- [x] `uvm_detect` (moved from P2): `uvm_damaged_pythons`, set by a dangling `bin/python-shims`
  entry and by an interpreter failing `import json, os, ssl`.
- [x] `README.md`: the interpreter arm's condition, the orphan refusal and its remedy, and the
  receipt-less failure with its remedy. Moved from P2 with the arm: `releases.astral.sh` in the
  *Network* paragraph of *Repairing inside a job*, and interpreter damage in its *What happens*
  paragraph; the conf example's `UVM_REPAIR` block and the modulefile's help text likewise.
- **Verify:** the frontmatter gate.
  - **Offline:**
    - **R6**: no interpreter gives no `python install` line. A stub interpreter that passes the
      probe gives none. One that fails it gives exactly one, with no tool line, and a `.ok`.
    - Order: `python install` before `tool upgrade`.
    - **R5** (fixture): an orphan beside F. Non-zero, no repair line, stderr names `orph` and
      `pyvenv.cfg`, the `.failed` record names it, no marker.
    - A receipt-less tool with a failing tool arm: the reason names it.
  - **Real uv + network:**
    - **R3 (T)**: pyflakes 3.2.0 gutted. `uvx` is red before the repair. With the knob, stdout is
      one line `^3.2.0 Python 3.12.`, `comm -23` of the manifest is empty, the shim runs, the
      receipt is identical, and `.ok` is recorded.
    - **R4**: `pyflakes==3.1.0 --with six`. It still reports `3.1.0`, `import six` works in the
      tool's interpreter, and the receipt is identical.
    - **R3 (P)**: `json/` moved out. `uv run` is red before. With the knob it prints `t-ok [1]`,
      records `.ok`, and the tool arm does not run.
    - **R5 (real)**: pycowsay's `pyvenv.cfg` moved out beside gutted pyflakes. Non-zero, stderr
      names pycowsay, the base interpreter's `site-packages` and `bin/` listings are identical, and
      the `.failed` record names it.
  - Observed at plan time: HEAD red at the P2 guard; the prototype green in about 12 s, network
    included.
  - Observed at build, 2026-10-29: red on the P2 tree at `FAIL R6: expected exactly one python
    repair line…`; the scope recorded a repaired outcome while the interpreter stayed damaged, and
    run alone the real-uv half went red at `FAIL R3P: knob-set uv run exited non-zero`. Green after,
    in about 13 s, network included. Local repair hold, three fresh roots each, measured as the
    knob-set call less the same call on the repaired path: (T) 0.61-0.65 s, (P) 1.27-1.31 s,
    of which the 23.9 MiB interpreter download and install is about 0.8 s.
- **Review cycle 1 remediation (2026-10-29), reopened for R3 and R6:**
  - [x] **F1.** `uvm_detect` collects `uvm_damaged_pythons` as an array of install keys: an
    install failing the probe (never its minor-version symlink), and the directory a dangling python
    shim points into when that directory survives. The interpreter arm runs `python install
    --reinstall <key>…`; the old `installed` guard and its pre-release comment are deleted, since
    a key exists only for an install on disk. The tool arm runs with `UV_PYTHON` unset in a subshell.
    The comment claiming the reinstall restores each patch version now sits where it is true.
  - [x] **F4.** A dangling shim sets a damaged flag only when its directory (`<dir>` of its
    `<dir>/bin/<name>` target) still exists. Doctor's output is unchanged.
  - [x] **F1, doctor's advice** (foreman's ruling, 2026-10-29: in scope as part of F1, since a human
    following it from a project directory gets the same wrong install). Doctor's remediation block
    prints `uv python install --reinstall <key>…` with the keys `uvm_detect` found, or
    `<install>...` and "naming each one reported above" when it found none, and
    `env -u UV_PYTHON uv tool upgrade --all --reinstall --no-cache`, with a paragraph saying why.
    The rest of doctor's output is unchanged. The gate's install-key block now also requires both
    lines from doctor, and the gone-tool block the placeholder. Observed: against `2deb76d`'s
    `bin/uv-manager` red at `doctor's advice must name cpython-3.12.0-fixture`; a mutant that prints
    no placeholder red at `with no install to name, doctor's advice must say to name them`.
  - Measured with uv 0.13.6, cpython 3.12.1 damaged, 3.13 requested by each source (`.python-version`
    in the working directory, in its parent, the global pin under `$XDG_CONFIG_HOME/uv/`,
    `UV_PYTHON`):
    - `python install --reinstall` with no target: steered by all four. Installs 3.13.18, exits 0,
      3.12.1 stays damaged.
    - `python install --reinstall cpython-3.12.1-<platform>`: steered by none. 3.12.1 restored, no
      3.13. The minor-version key `cpython-3.12-<platform>` also resolves to the installed 3.12.1.
    - `tool upgrade --all --reinstall --no-cache`: steered by `UV_PYTHON` alone (the tool moves to
      3.13.18), whether the receipt pins `python = "3.12"` or names none. The three file sources
      leave it on 3.12.1.
    - So the neutralization is the named keys for the interpreter arm and `UV_PYTHON` unset for the
      tool arm. No working-directory change and no `UV_NO_CONFIG`, which would also hide the user's
      `uv.toml` (index, mirror, auth), against invariant §8.
  - The retuned gate adds, offline: the arm names exactly `cpython-3.12.0-fixture` beside a passing
    3.11 and a minor-version symlink; a shim into a gone interpreter beside a passing one gives 0
    `python install` lines across 3 scopes, and a shim into a gone tool 0 `tool upgrade` lines, with
    doctor still FAILing each; shims into surviving directories are repaired (`python install
    --reinstall cpython-3.10.0-fixture`, then `tool upgrade`). Real uv: cpython 3.12.1 and pyflakes
    on it, both arms damaged in each of five rounds (control, cwd, parent, global, `UV_PYTHON`, each
    asking for 3.13). Each round must restore 3.12.1 in place, keep the tool on 3.12.1, and install
    no 3.13.
  - Observed: against `32d7cbe`'s `bin/uv-manager`, every source round is red (`rc=1
    interpreter-still-damaged installed-3.13 tool-does-not-run-on-3.12.1`), and the key and F4
    blocks are red (`must name exactly cpython-3.12.0-fixture`; `triggered 3 python repair(s)`).
    Mutants of the fix: without the `UV_PYTHON` unset, the `UV_PYTHON` round is red at
    `tool-moved-to-3.13.18`; with the tool-shim guard removed, red at `a shim whose tool is gone
    triggered a tool repair`. Green after, in about 25 s, network included.
- **Review cycle 2 remediation (2026-10-29), reopened for R3, R4 and R6** (REVIEW.md rulings 1, 2
  and 5, and the foreman's follow-up rulings of the same day on the tool mechanism):
  - [x] **C2-F1.** `uvm_detect` treats an install as a real directory under `python/`: one with no
    executable `bin/python3` or `bin/python` is a FAIL (`its binary is missing`) and is keyed by its
    own name. A dangling python shim whose directory is the minor-version link follows the link to
    the install's key. The banner comment and README's concession now say so.
  - [x] **C2-F2.** The tool arm runs per damaged tool: `uv pip install --python
    <tools>/<tool>/bin/python --reinstall --no-cache <name>==<version>...`, every distribution
    pinned from its dist-info directory name (`uvm_tool_pins`). It never reads or writes a receipt and
    never touches a healthy tool. `uvm_damaged_tools` becomes an array of tool names; `uvm_receiptless`
    is deleted, since a receipt-less tool no longer fails the arm. Guards, in order: the orphan refusal
    (unchanged, before every arm); per tool, `pyvenv.cfg` and an executable `bin/python`; no
    distribution with a `direct_url.json` (URL, git or path source), naming the tool and the
    distribution; at least one distribution to pin. The `UV_PYTHON` subshell is deleted: `--python`
    overrides it. The fixture counts `pip install` as a repair (and still `tool upgrade`, so a drive
    can run against an older wrapper). GOAL R4 amended and the per-tool non-goal reworded by dated
    clarifications.
  - [x] **C2-F5.** Doctor prints the commands interpreters first, the python line only when an
    interpreter is damaged (the `<install>...` placeholder only when a finding named none), one pip
    line per damaged tool with its pins, and the concessions: the receipt's options are not applied,
    `uv.toml` and the environment are, a URL, git or path source fails. The receipt-less paragraph is
    gone.
  - [x] Prose: README (*What happens*, *Three tool states*, *What it catches*, *Network*,
    troubleshooting), the conf example, `AGENTS.md`, `invariants.md` §8. The help and the modulefile
    name no command and say nothing the change made false.
  - Measured with uv 0.13.6 before choosing (the table is in the hand-back of Run A, cycle 2):
    `tool upgrade --all --reinstall` moves an unpinned tool and fails on the missing `RECORD`;
    `--exclude-newer` writes itself into receipts; `tool upgrade <name>==<ver>` keeps the receipt but
    moves an unpinned `--with` package and leaves a second dist-info that doctor then FAILs in every
    scope; `tool install -c <pins>` writes the constraints into the receipt. The pip form, with and
    without `--no-deps`, left every version identical on both trees (an unpinned superseded tool;
    the same with an unpinned superseded `--with` package); with a dependency's whole dist-info
    directory gone (flake8 7.1.0 without `mccabe-0.7.0.dist-info` and `mccabe.py`) the form without
    `--no-deps` restored mccabe 0.7.0, and `--no-deps` left it missing while `uv pip check` reported
    the incompatibility. So dependencies are resolved: a mutant with `--no-deps` records the scope
    repaired with mccabe missing and is red at `the dependency with no dist-info did not come back`.
  - The retuned gate. Setup, in P2's and P4's gates too: tree F's tool gets `bin/python`, and
    `lines()` counts `pip install` in place of `tool upgrade` (a setup the guard and the new command
    outlawed; P2 and P4 stay `done`, and P4's R14 grep names `pip install --python`). Offline, new: one
    pinned `--no-cache` line each for two damaged tools, a receipt-less one among them, and none for a
    healthy one; a failing arm naming the tool; a tool whose `bin/python` is dangling and one with a
    `direct_url.json`, each failing the scope naming it with no pip line for it; an install with no
    binary and a shim through the minor-version link, each giving one line naming the install's key,
    and doctor's FAIL and key line; doctor's advice python line then fx's pip line; no python line from
    doctor beside a gone tool's shim; the placeholder beside a gone interpreter's shim. Real uv, new:
    (P) on four purge shapes (every file; `bin/` only; every file and the minor-version link; every
    file with a damaged tool on it, through `uvx`); the C2-F2 tree; flake8 with mccabe's dist-info
    gone; a tool installed from a local wheel failing naming `localtool` twice.
  - Observed: every new block, run alone against `abf84b9`'s `bin/uv-manager`, is red: (P) ×4 at
    `knob-set uv run exited non-zero` / `knob-set uvx exited non-zero`; the C2-F2 tree at `knob-set
    uvx exited non-zero`; mccabe at `knob-set uvx flake8 exited non-zero`; the wheel at `exited 0 on a
    tool from a path source`; offline, each at its own first assertion. The gone-interpreter
    placeholder block is red there only on its wording, since `abf84b9` already printed the
    placeholder in that case. The whole gate is green after, in about 45 s, network included.
  - Found while building the red check: on a purged interpreter, `uvx <tool>` with the knob unset
    exits 0 while it runs a different release (pyflakes 4.1.0) on a newly downloaded interpreter
    (3.15.2), because uv falls back to an ephemeral environment when the tool's interpreter is gone.
    The (P) tool variant's red check therefore runs the tool's shim, which changes nothing.
- **Review cycle 3 remediation (2026-10-29), reopened for R4** (REVIEW.md rulings 1, 3 and 4, and
  ruling 6's local half):
  - [x] **C3-F1.** `uvm_tool_receipt` reads a damaged tool's `uv-receipt.toml` to refuse, and for
    nothing else: it sets the first entry that names a source an index cannot stand in for, a
    requirement (the tool or a `--with` package), a constraint or an override from a directory,
    path, editable, git or URL source. `uvm_repair_run` fails the scope on it, naming the tool and
    what was found, after the `direct_url.json` refusal and before any `uv` call for that tool.
    Doctor gives such a tool a comment line in place of its pip command, and its paragraph states the
    refusal, that the repair runs under `uv.toml` and the environment, and what is left conceded. The
    match is on the recorded form: an inline table on one line inside the `requirements`,
    `constraints` or `overrides` array of `[tool]`, with string values blanked first so that a marker
    or an entrypoint's `install-path` cannot spell a key. No spec is built from the receipt and it is
    never written. GOAL R4 amended by a dated clarification.
  - **Ruling 1 amended (foreman, 2026-10-29, `f9ba222`), after the measurement below.** The first
    build of this item also refused the `index`, `index-url`, `extra-index-url` and `find-links`
    keys of `[tool.options]`. uv writes an index configured in `uv.toml` or a `UV_INDEX` variable
    into every receipt there, so that refused every damaged tool at a site with a mirror, the setup
    the README recommends. The option refusal is withdrawn: the repair runs under the user's
    `uv.toml` and environment, so a configured index is in effect for it, and an index or find-links
    given only on one install's command line is not applied again, the stated concession. The source
    refusal extends to `constraints` and `overrides`. The GOAL clarification was revised in place
    the same day.
  - [x] **C3-F3.** README's *Network* paragraph: with the cache bypassed, uv stages the tool
    repair's download under `TMPDIR`, which needs room for the tool's whole environment, and a
    `TMPDIR` that is not writable or is full fails the scope with uv's reason. The conf example says
    the same in a clause.
  - [x] **C3-F4.** A python shim whose interpreter cannot be keyed, its install and minor-version
    link both gone, gets no command, the same as a shim whose tool is gone, and the fallback line
    says to remove it. `uvm_python_unkeyed` and the `<install>...` placeholder are deleted.
  - [x] Prose: README (*What happens*, *Three tool states*, the two concessions, *Network*), the conf
    example, `AGENTS.md`, `invariants.md` §8. The help and the modulefile name no source and
    say nothing the change made false.
  - Measured with uv 0.13.6 before choosing, real installs of every kind into a scratch tool
    directory (`UV_NO_CONFIG=1`), the receipt read back after each. Git through `github.com` and a
    URL on `files.pythonhosted.org` were real; the gate uses a local `git+file://` repository, which
    records the same key.

    | Install | What `uv-receipt.toml` records |
    |---|---|
    | `uv tool install <dir>` | `requirements = [{ name = "loctool", directory = "<dir>" }]` |
    | a wheel or an sdist by path | `{ name = "whltool", path = "<file>" }` |
    | `-e <dir>` | `{ name = "edtool", editable = "<dir>" }` |
    | `git+https://…@3.2.0` | `{ name = "pyflakes", git = "https://github.com/PyCQA/pyflakes?rev=3.2.0" }` |
    | a URL, bare or `name @ url` | `{ name = "pycodestyle", url = "<url>" }` |
    | each of the five as `--with` (`--with-editable` for editable) | the same table as the array's second line, e.g. `{ name = "locwith", directory = "<dir>" }` |
    | `--index <url>` | `[tool.options]` `index = [{ url = …, explicit = false, default = false, format = "simple", authenticate = "auto" }]` (`name = …` first when named) |
    | `--default-index <url>` | the same `index` key with `default = true` |
    | `--index-url <url>` | `index-url = "<url>"` |
    | `--extra-index-url <url>` | `extra-index-url = ["<url>"]` |
    | `--find-links <dir>` | `find-links = ["file://<dir>"]`; with `--no-index`, `no-index = true` before it |
    | `pkg==1.0`, `pkg`, `--with six==1.16.0` | `{ name = …, specifier = "==1.0" }`, `{ name = … }`; no `[tool.options]` |
    | `--with 'coverage[toml]>=7; python_version >= "3.8"'` | `{ name = "coverage", extras = ["toml"], marker = "python_full_version >= '3.8'", specifier = ">=7" }` |
    | `-c` / `--overrides` | `constraints = [...]` / `overrides = [...]` beside `requirements`, the same table form, e.g. `overrides = [{ name = "six", url = "<url>" }]` |
    | `--exclude-newer` | `[tool.options]` `exclude-newer = "…"` |

    - Every entrypoint line carries `install-path = "…"`, so a grep for `path =` trips on every
      receipt; the match is anchored to the table's own keys and blanks strings first.
    - uv writes the index the environment or `uv.toml` sets into the receipt too:
      `UV_INDEX_URL` and `index-url` in `uv.toml` as `index-url`, `UV_DEFAULT_INDEX` and `UV_INDEX` as
      `index`. This is what amended ruling 1: no option key is a refusal.
    - Run over all 31 measured receipts, the amended check names the source in the 14 that record
      one: a directory, a wheel or an sdist by path, editable, git and URL requirements as the tool
      and as `--with`, and the URL constraint and the URL override. It names nothing in the 17 that
      do not: eleven with an index or find-links option, those set through `uv.toml` and the
      `UV_INDEX` variables among them, and pinned, unpinned, `--with` pinned, extras with a marker,
      a registry constraint and `exclude-newer`. The first build named 23, the eleven option
      receipts among them, and missed the URL constraint and override.
  - The retuned gate. Offline, new: fx's receipt set to each refused form, six sources as the tool,
    as a `--with` line, as a constraint and as an override, each failing its scope naming fx and the
    entry with no pip line, no mark and the receipt unchanged; doctor's comment line for fx and no
    pip command; the five option forms and the registry receipts (unpinned; pinned with a `--with`
    line carrying extras and a marker whose string spells `git` and `path`, a registry constraint,
    `exclude-newer` and `index-strategy`; empty) each repaired once with the receipt unchanged. Real
    uv, new: thirteen tools refused, a directory, a wheel, an sdist, editable, `git+file://` and a
    URL, the same five sources as `--with`, and six from a URL as a constraint and as an override;
    one at a time, every `RECORD` and `direct_url.json` moved out, the knob-set call fails naming the
    tool and what its receipt records, uv prints no `Resolved`/`Prepared`/`Installed` line, the
    tool's file list and receipt are unchanged, and the files are put back. Then five tools installed
    with `--index`, `--index-url`, `--extra-index-url`, `--default-index` and `--find-links`, each
    with every `RECORD` moved out: each is repaired, its dist-info listing (so every version) is
    unchanged, every `RECORD` is back, the receipt is byte-identical and its console script runs. C3-F4: two dangling python shims that
    cannot be keyed give doctor's fallback line and no python command (inverting the C2-F5
    placeholder block, whose assertion the ruling reversed).
  - Observed at the amendment: against `02f7a7f`'s `bin/uv-manager` (the first build), the gate is
    red at `FAIL C3-F1 (ctdirectorysrcfx): exited 0`, a directory constraint; the real block alone
    at `FAIL C3-F1 (pyupgrade): exited 0`, six reinstalled from the index over its URL constraint;
    and the real repaired loop alone at `FAIL C3-F1 (wheel): an index-option receipt failed the
    scope`. Green after, in about 100 s, network included. The find-links tool is now pygments from
    PyPI with a local `--find-links` directory, since a project only the find-links directory holds
    cannot be restored once that option is not applied.
  - Observed at the first build: against `ec637b0`'s `bin/uv-manager`, the offline block is red at
    `FAIL C3-F1 (tdirectorysrcfx): exited 0`; with it cut, red at `FAIL C3-F4: … the remove-the-shim fallback
    alone`; the real block alone red at its first tool, `cdir`, where `uv pip` asked the index for
    `cdir==0.1` and failed, and, started at `pycowsay` (installed from its URL), at `exited 0` with
    `~ pycowsay==0.0.0.2` reinstalled from the index, which is C3-F1 itself. The whole gate is green
    after, in about 70 s, network included. A first run named its find-links project `cfl`, a name
    on PyPI, and uv resolved PyPI's; the project is now `uvmfl` installed with `--no-index`.
- **Review cycle 4 fix (2026-10-30), for R3 and R4** (REVIEW.md, *Maintainer decision*, ruling 1):
  - [x] **C4-F1.** Both arms of `uvm_repair_run` run as `(cd / && exec "${real_uv}" …) >&2`. A
    project's `pyproject.toml` (`[tool.uv]`, `[tool.uv.pip]`) or `uv.toml` in the job's working
    directory or above it no longer reaches the repair; the user's and the system's `uv.toml` and
    the `UV_*` variables still do. The subshell confines the directory change: the dispatch tail,
    and the exec of the user's command, run in the job's directory as before. Prose: the banner
    comment above `uvm_repair_run`, README *What happens*, the conf example, `AGENTS.md`,
    `invariants.md` §8. Doctor's printed commands are unchanged (the ruling keeps the change to the
    two calls).
  - Measured with uv 0.13.6 before choosing, `uv pip install --python <venv> --reinstall --no-cache
    pycodestyle==2.11.1` from a project's subdirectory:
    - `[tool.uv.pip] target = "tgt"`: run in place, uv installs into `<project>/sub/tgt` and the
      venv gets nothing. Under a subshell `cd /` and under `uv --directory /`, the venv gets it and
      no `tgt` appears.
    - `[tool.uv] exclude-newer = "2023-01-01T00:00:00Z"`, in `pyproject.toml` or the project's
      `uv.toml`: in place, `pycodestyle` is filtered out and nothing installs. Under either
      mechanism it installs.
    - A user `uv.toml` (`$XDG_CONFIG_HOME/uv/uv.toml`) with the same `exclude-newer`: applied under
      both mechanisms, and `UV_CONFIG_FILE` too. So neither drops the user's configuration, which
      `--no-config` would.
    - The python arm, `python install --reinstall <key>` with `[tool.uv] python-downloads =
      "never"` or a bogus `python-install-mirror` in the project: in place it refuses ("Python
      downloads are not allowed") or fails on the mirror, and the interpreter stays damaged. Under
      either mechanism the interpreter is restored.
    - `UV_PROJECT=<project>` still brings that project's configuration in under both mechanisms,
      since it names the project rather than finding it from the working directory; adding
      `--project /` overrides it. Not acted on: the ruling keeps the `UV_*` environment in effect,
      and this is the foreman's call.
    - Relative paths: every path an arm passes, `real_uv`, `--python` and the `UV_*` directories the
      wrapper exports, is under `UVM_ROOT`. With a relative `UVM_ROOT` both mechanisms break (a
      relative `--python` is "No virtual environment … found", a relative `UV_CACHE_DIR` resolves
      against `/`), and `cd /` also leaves `real_uv` unreachable. The module and the cascade set an
      absolute root, and a relative one already gives each working directory a tree of its own; such
      a scope fails with a recorded reason rather than repairing.
    - **Chosen: a subshell `cd /`.** Both mechanisms are equally clean. `cd /` asks nothing of the
      uv version a site pins with `UVM_PIN`; `--directory` is a newer flag. The `exec` keeps it one
      fork.
  - The retuned gate adds, real uv: pycodestyle 2.11.1 as a tool, damaged (its module and `RECORD`
    moved out), and the knob-set `uvx pycodestyle --version` run from `<project>/sub`, once under a
    project `[tool.uv.pip] target = "tgt"` and once under `[tool.uv] exclude-newer =
    "2023-01-01T00:00:00Z"`. Each prints `2.11.1`, puts the module and every `RECORD` back, the shim
    runs, `.ok` is recorded, and `find` over the project is unchanged. The python arm: `json/` moved
    out of the 3.12 install, a project with `python-downloads = "never"`, the knob-set `uv run
    --no-project -p 3.12 t.py` from `<project>/sub` prints `t-ok [1]`, the interpreter imports
    `json`, `.ok`, the project unchanged. The positive control: a flat index in
    `$XDG_CONFIG_HOME/uv/uv.toml` holding the only `uvmcfour` wheel (404 on PyPI), the tool
    installed through it, damaged, and repaired from the `target` project the same way.
  - Observed: against `7ba7f11`'s `bin/uv-manager` the gate is red at `FAIL C4-F1 (tgt): knob-set
    uvx pycodestyle exited non-zero from the project`, the earlier blocks green. Each case alone
    against `7ba7f11`: `exn` red at the same line, uv's `filtered by exclude-newer` hint in the
    stderr; `py` red at `knob-set uv run exited non-zero`, with "Python downloads are not allowed";
    `idx` red at `knob-set uvx uvmcfour exited non-zero`, uv having resolved and installed it into
    the project's `tgt`. Mutants of the fix, the whole block: `--no-config` on the tool arm is red
    only at `idx` ("uvmcfour was not found in the package registry"); the python arm reverted, red
    at `py`; the tool arm reverted, red at `tgt`. Green after, the whole gate in about 66 s, network
    included.
- **Inspection-only:** R4's "the named command is the only tool repair".
- **Touches:** `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`,
  `share/modulefiles/uv/main.lua`.

## Phase P4 — The human path: doctor and clean over both locks and the outcomes
**Satisfies:** R9 (c), R13 (c), R14 · **Depends on:** P3
**Goal:** a leaked repair lock and a standing failed outcome each have a reporter and a remover.

- [x] `uvm_doctor`:
  - One loop over `install` and `repair` locks: WARN with the owner line, "provisioning or
    repairing".
  - One WARN per failed outcome recorded under a value, with its reason and `uvm clean outcomes
    --yes`.
  - One counting WARN for failed outcomes under Slurm jobs, which it does not read. Comment why: a
    read refreshes atime.
  - All are advisories, never FAILs.
- [x] `uvm_clean`:
  - `lock` removes both locks, and its dry run prints each standing owner line and the reworded
    caution.
  - New `outcomes` removes `${uvm_root}/.repair`, and its dry run counts repaired and failed records
    and says what removing them costs.
  - The `die` list names `outcomes`.
- [x] Same commit:
  - `uvm_help` (`clean` line);
  - `README.md` (the `clean` table rows, troubleshooting for "waiting for the repair lock" and for
    a failed outcome);
  - `etc/uv-manager.conf.example` (the timeout block's mention of `uvm clean lock`);
  - `invariants.md` §5 (`uvm clean lock` removes both lock directories and nothing else; doctor
    reports both);
  - `AGENTS.md` § Invariants to match.
- **Verify:** the frontmatter gate.
  - **R13 (c)**: doctor's `WARN  repair lock standing: <path> (owner: <planted>)`. The dry run keeps
    the lock and prints the owner. `--yes` removes it, and `current/uv` stays executable.
  - **R9 (c)**: 4 ranks, the holder killed with `KILL` once it holds the lock. Exactly one rank is
    rc 137, and 3 fail naming `timed out after 4s waiting for the repair lock at <path>` and the
    owner line. No outcome is recorded, doctor WARNs, `uvm clean lock --yes` clears it, and the next
    call repairs once and records `.ok`.
  - **Consequence 1**: doctor names `UVM_REPAIR=k` with its reason and `uvm clean outcomes --yes`.
    The dry run says `1 failed` and keeps the record. `--yes` removes it, and the value repairs
    again.
  - Help mentions `UVM_REPAIR` and `outcomes`.
  - The six-file census.
  - `README.md` and the modulefile each mention `repair lock`, `uvm clean outcomes`,
    `SLURM_JOB_ID`, `releases.astral.sh` and `uvx`.
  - Doctor's remediation block names `UVM_REPAIR`.
  - Observed at plan time: HEAD red at the P3 guard; the prototype green in about 6 s.
  - Observed at build, 2026-10-29: red on the P3 tree at `FAIL R13c: doctor does not name the
    repair lock and its owner line`, and red there again with only `bin/uv-manager` reverted over
    the finished documentation. Green after, in about 6 s. Doctor's output, before and after, on
    trees holding every existing finding (with and without the uv binary), on an advisories-only
    tree and on a clean one: byte-identical except the provisioning lock's caution, which now reads
    "provisioning or repairing", since the `uvm clean lock --yes` it names removes both locks.
  - Gate setup retuned at P3's cycle-2 remediation (2026-10-29), phase left `done`: as P2's, tree F's
    tool gets a `bin/python` and `lines()` counts `pip install`; the R14 check that doctor's block
    names `UVM_REPAIR` now finds the tool command by `pip install --python`. Green after.
- **Inspection-only:** each R14 hit read against R14's list. `uvx <script>.py` is said to be not a uv
  form, the false-clean reason is stated, and reach excludes a tool run by its own name.
- **Touches:** `bin/uv-manager`, `README.md`, `etc/uv-manager.conf.example`,
  `share/modulefiles/uv/main.lua`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P5 — Cross-node drive on Lustre and GPFS
**Satisfies:** R12 · **Depends on:** P4
**Goal:** R12's evidence. `tests/repair-race.sh` (research 03) is built and checked locally, then the
foreman runs it on a Lustre cluster (2 nodes, 128 ranks) and a GPFS cluster (1 node, 64 ranks), as
two jobs per cluster within the approved test-job class.
**This phase has an external wait, so it is two runs.**

**Run A — build, check locally, hand back:**
- [x] `tests/repair-race.sh`, one POSIX `sh` file with the roles driver, job and rank (research
  03):
  - Scenarios: `F` (offline fixture), `T`, `P`, and `kill` (P, holder killed on sight, then doctor,
    `uvm clean lock --yes` and a clean pass).
  - Options: `--ranks`, `--timeout` (default 180; 20 for kill), `--launch local|srun`, `--summary`,
    `--uv-bin` (seed a local binary), `--uv-version` (default 0.13.6, pinned through the installer).
  - Under `srun`, `REPAIRRACE_SHARED` is required (exit 2) and becomes `TMPDIR`; `srun` must be on
    PATH (exit 2).
  - Ranks run `srun --ntasks=N --kill-on-bad-exit=0 --distribution=cyclic --cpu-bind=none
    --export=ALL`.
  - The `nowrapper` guard applies.
  - Each rank starts the wrapper directly in the background, so `$!` is the owner line's pid.
- [x] Summary keys, as research 03 lists them: counts, whole seconds, versions and fixed words. **No
  hostnames, usernames, paths, cluster names, accounts, partitions or dates.** Never `--keep` on a
  cluster.
- [x] `AGENTS.md`'s `tests/` paragraph and repository map name the second drive in one sentence
  each.
- [x] Run the gate. It is expected red **only** at `cluster evidence … not recorded yet`, and every
  check above that line must pass. **This red is the external wait, not a failed attempt: do not
  `--record-attempt` for it.** Commit Run A as `[feature] Build purge-tree-repair P5: Run A — …`, with
  the phase left `in_progress`, and stop.
- [x] Hand back to the foreman: the commit, the local summaries, and the two job bodies below.
  - The bodies are generic. Their `#SBATCH` lines size the job only, and the foreman adds account,
    partition and QoS, which are not committed.
  - Both fit the approved test-job class: at most 30 min wall and 16 GB per node.
  - The foreman stages this commit's tree on a filesystem every node mounts: at least `bin/` with
    its symlinks, `tests/`, `.agents/factory/bin/temp_root.sh` and `.agents/factory/fixtures/`. They
    check the staged blobs against `git ls-tree -r`, then pass `REPAIRRACE_REPO` and, for each job,
    its own empty `REPAIRRACE_RUN_DIR`.
  - Both jobs may be queued together; each drive works in its own sandbox under its own run
    directory.

  **Job 1, scenarios P then T:**
  ```bash
  #!/bin/bash
  #SBATCH --nodes=2              # 1 on the GPFS cluster
  #SBATCH --ntasks=128           # 64 on the GPFS cluster
  #SBATCH --ntasks-per-node=64
  #SBATCH --mem=16G
  #SBATCH --time=00:30:00
  # REPAIRRACE_REPO     the staged tree of the commit under test, on a filesystem every node mounts
  # REPAIRRACE_RUN_DIR  an empty directory on the filesystem under test; the job writes only beneath it
  set -u
  : "${REPAIRRACE_REPO:?set REPAIRRACE_REPO to the staged tree}"
  : "${REPAIRRACE_RUN_DIR:?set REPAIRRACE_RUN_DIR to a directory on the filesystem under test}"
  n="${SLURM_NTASKS:?run inside a Slurm allocation}"
  REPAIRRACE_SHARED="$REPAIRRACE_RUN_DIR/shared"
  export REPAIRRACE_SHARED
  mkdir -p "$REPAIRRACE_SHARED" && cd "$REPAIRRACE_RUN_DIR" || exit 1
  run() {
      s="$1"; shift
      "$REPAIRRACE_REPO/tests/repair-race.sh" --launch srun --ranks "$n" --scenario "$s" \
          --summary "$REPAIRRACE_RUN_DIR/$s.txt" "$@"
      echo "exit=$?" >> "$REPAIRRACE_RUN_DIR/$s.txt"
  }
  run P
  run T
  cat "$REPAIRRACE_RUN_DIR/P.txt" "$REPAIRRACE_RUN_DIR/T.txt" > "$REPAIRRACE_RUN_DIR/summary.txt"
  ```

  **Job 2, scenario kill:**
  ```bash
  #!/bin/bash
  #SBATCH --nodes=2              # 1 on the GPFS cluster
  #SBATCH --ntasks=128           # 64 on the GPFS cluster
  #SBATCH --ntasks-per-node=64
  #SBATCH --mem=16G
  #SBATCH --time=00:30:00
  # REPAIRRACE_REPO     the staged tree of the commit under test, on a filesystem every node mounts
  # REPAIRRACE_RUN_DIR  an empty directory on the filesystem under test; the job writes only beneath it
  set -u
  : "${REPAIRRACE_REPO:?set REPAIRRACE_REPO to the staged tree}"
  : "${REPAIRRACE_RUN_DIR:?set REPAIRRACE_RUN_DIR to a directory on the filesystem under test}"
  n="${SLURM_NTASKS:?run inside a Slurm allocation}"
  REPAIRRACE_SHARED="$REPAIRRACE_RUN_DIR/shared"
  export REPAIRRACE_SHARED
  mkdir -p "$REPAIRRACE_SHARED" && cd "$REPAIRRACE_RUN_DIR" || exit 1
  "$REPAIRRACE_REPO/tests/repair-race.sh" --launch srun --ranks "$n" --scenario kill --timeout 60 \
      --summary "$REPAIRRACE_RUN_DIR/kill.txt"
  echo "exit=$?" >> "$REPAIRRACE_RUN_DIR/kill.txt"
  cp "$REPAIRRACE_RUN_DIR/kill.txt" "$REPAIRRACE_RUN_DIR/summary.txt"
  ```
  - **Expected runtime:**
    - Job 1 is about 3-5 min. Per scenario: under a minute to provision uv through the installer,
      install cpython 3.12 (23.9 MiB) and, for T, pyflakes. Then one pass whose holder repairs in
      seconds while 127 ranks wait. Then collection.
    - Job 2 is about 3-4 min. One preparation, then the killed pass, whose waiters all run out the
      60 s timeout. Then `uvm doctor`, `uvm clean lock --yes`, and a clean pass of seconds.
    - The 30 min limit leaves a margin above 5× for a slow hold. A hold that reached the default
      180 s timeout in job 1 would itself be R12's finding.
  - **Memory:** 64 ranks per node, each a bash wrapper plus one `uv` or a Python 3.12 interpreter
    running a two-line script or `pyflakes --version`, at roughly 30-60 MB each. That is 2-4 GB per
    node, plus the holder's unpacking of one interpreter, well inside 16 GB.
  - **Run B's evidence file per filesystem** is job 1's `summary.txt` followed by job 2's
    `summary.txt`, in that order (P, T, kill): `cat <job1>/summary.txt <job2>/summary.txt >
    <fs>.txt`.
  - **Egress** was probed and is present from compute nodes on both clusters: `releases.astral.sh`,
    `github.com`, `objects.githubusercontent.com`, `pypi.org` and `files.pythonhosted.org`. The
    installer's own host, `astral.sh`, was probed in shaping.
  - **The foreman pushes the branch and submits both jobs on both clusters.**
- Amended at build, 2026-10-29 (Run A): the kill takes the wrapper's process group, not the wrapper
  alone. The first local kill ×8 killed the wrapper alone and failed: the holder had announced its
  interpreter arm before the kill landed (`repair_lines=1`), the orphaned reinstall ran on and
  restored the interpreter (`restored=1` after the killed pass), and the clean pass had nothing to
  repair (`clean_repairs=0`). Under `srun` the step's end comes only after every waiter's timeout, so
  the orphan would outlive the kill there too. A node fault takes the whole group, so the group kill
  is the closer model. The group comes from `set -m`, which dash refuses without a terminal, so the
  job and the ranks run under `bash`, which every node that runs the wrapper has. Two keys are added:
  `kill_took` (`group`, or `wrapper` where the shell gave no group) and `prep_s`. `lint.sh` parses
  and shellchecks the new drive.
- Observed at build, 2026-10-29 (Run A), macOS, bash 3.2, uv 0.13.6 seeded with `--uv-bin`:
  - F ×16 offline: `rc_hist=0:16 stdout_hist=9.9.9:16 repairs=1 outcomes=1 locks_left=0`, 4 s.
  - T ×8 and P ×8: `rc_hist=0:8`, `repairs=1`, `outcomes=1`, `restored=1`, `hold_s` 1-2.
  - kill ×8, four runs: `rc_hist=1:7,137:1 killed=1 kill_took=group timeout_named_lock=7
    outcomes=0 locks_left=1 restored=0 doctor_warn_repair_lock=1`, then `clean_repairs=1
    clean_rc_hist=0:8 clean_restored=1`, about 24 s.
  - At 64 ranks: P and T `rc_hist=0:64 repairs=1`; kill `rc_hist=1:63,137:1 notice_lines=63
    timeout_named_lock=63` and `clean_repairs=1 clean_rc_hist=0:64`. Fed to the gate's evidence
    half as both files (with `nodes=2` set by hand for Lustre), they pass, and the same files with
    `clean_repairs=0` fail at `kill scenario clean_repairs`.

**Run B — read the evidence, close the phase:**
- [x] Copy each filesystem's evidence to `spec/purge-tree-repair/evidence/lustre.txt` and
  `spec/purge-tree-repair/evidence/gpfs.txt`, unedited: job 1's summary, then job 2's (P, T, kill).
  If either contains anything identifying, stop and ask the foreman. Do not scrub by hand.
- [x] Run the gate. A scenario can fail for an infrastructure reason: a host lost since the egress
  probe (a failed outcome or `progress` not ok), `REPAIRRACE_SHARED` not shared, or `srun` refused. Then record that in the commit body and escalate to the foreman. Do not close the
  phase on one filesystem silently.
- [x] Record in `PLAN.md` §5 the measured `hold_s`, `wait_max_s` and `notice_lines` per filesystem.
  A hold near `UVM_LOCK_TIMEOUT` is a finding, not a reason for a knob.
- [x] Mark the phase `done` and commit as `[feature] Build purge-tree-repair P5: Run B — …`.
- Observed at build, 2026-10-29 (Run B), both filesystems run against `4c08e9c`, uv 0.13.6:
  - Lustre (2 nodes × 64 ranks), bash 5.1: P and T `rc_hist=0:128`, `repairs=1`, `outcomes=1`,
    `locks_left=0`; kill `rc_hist=1:127,137:1 timeout_named_lock=127 kill_took=group
    doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:128 clean_locks_left=0`.
  - GPFS (1 node × 64 ranks), bash 4.4: P and T `rc_hist=0:64`, `repairs=1`, `outcomes=1`,
    `locks_left=0`; kill `rc_hist=1:63,137:1 timeout_named_lock=63 kill_took=group
    doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:64 clean_locks_left=0`.
  - In the kill scenario `repair_lines` is 0 on Lustre and 1 on GPFS: the holder was killed before
    printing its start line on one and after it on the other. Neither run recorded a repair
    (`repairs=0`, `outcomes=0`), and both clean passes repaired once. The gate does not key on
    `repair_lines`, so the kill's timing relative to the start line is not asserted.
  - Holds, waits and notice counts per filesystem are in `PLAN.md` §5. The gate, and P1-P4's gates
    re-run, are green.

**Review cycle 1 — reopened (2026-10-29).** The cycle 0 evidence above graded R12 at `4c08e9c`.
F1's remediation changes the interpreter arm that scenario P drives, so that evidence no longer
describes the code. It is kept, moved with `git mv` to `evidence/cycle0/`, and the gate is red again
at `cluster evidence … not recorded yet`, the external wait. The gate itself is unchanged.

**Run A, cycle 1 — re-run locally, hand back:**
- [x] Re-run the gate at the remediated tree: every check above the evidence line passes (`--launch
  srun` without `REPAIRRACE_SHARED` exits 2; local F ×16; local T and kill ×8 with real uv; no `/` or
  host name in a summary), and it is red only at `cluster evidence
  spec/purge-tree-repair/evidence/lustre.txt not recorded yet`.
- Observed, macOS, bash 3.2, uv 0.13.6 seeded with `--uv-bin`:
  - F ×16 offline: `rc_hist=0:16 repairs=1 outcomes=1 locks_left=0 progress=ok`.
  - P ×8 and T ×8: `rc_hist=0:8`, `repairs=1`, `outcomes=1`, `restored=1`, `hold_s=1`.
  - kill ×8: `rc_hist=1:7,137:1 killed=1 kill_took=group timeout_named_lock=7 outcomes=0
    doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:8 clean_outcomes=1
    clean_locks_left=0`.
  - P ×64 and T ×64: `rc_hist=0:64`, `repairs=1`, `outcomes=1`, `locks_left=0`, `restored=1`.
- [x] Hand back to the foreman: the same two job bodies above, against this commit's tree.

**Run B, cycle 1 — read the evidence, close the phase:**
- [x] Copy each filesystem's new evidence to `evidence/lustre.txt` and `evidence/gpfs.txt`,
  unedited, as in Run B above.
- [x] Run the gate; re-run P1-P4's.
- [x] Record the new `hold_s`, `wait_max_s` and `notice_lines` in `PLAN.md` §5 beside cycle 0's.
- [x] Mark the phase `done` with `--top-status in_review`.
- Observed at build, 2026-10-29 (Run B, cycle 1), both filesystems run against `40e6120`, uv 0.13.6:
  - Lustre (2 nodes × 64 ranks), bash 5.1: P and T `rc_hist=0:128`, `repairs=1`, `outcomes=1`,
    `locks_left=0`; kill `rc_hist=1:127,137:1 timeout_named_lock=127 kill_took=group
    doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:128 clean_locks_left=0`.
  - GPFS (1 node × 64 ranks), bash 4.4: P and T `rc_hist=0:64`, `repairs=1`, `outcomes=1`,
    `locks_left=0`; kill `rc_hist=1:63,137:1 timeout_named_lock=63 kill_took=group
    doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:64 clean_locks_left=0`.
  - `hold_s` / `wait_max_s` / `notice_lines` per scenario:
    - Lustre: P 5 / 5 / 0; T 2 / 3 / 0; kill, killed pass none / 60 / 127; kill, clean pass
      6 / 7 / 0.
    - GPFS: P 34 / 34 / 63; T 2 / 2 / 0; kill, killed pass none / 61 / 63; kill, clean pass
      13 / 14 / 0.
  - On GPFS, scenario P held the repair lock for 34 s, against 5 s at cycle 0 and 5 s on Lustre at
    this commit. Every one of the 63 waiters printed the 30 s wait notice (`notice_lines=63`), and
    all exited 0. The same job's `prep_s` was 12 s, against 4 s at cycle 0, which points at the node
    or the filesystem at that moment rather than the code. The foreman is re-running that job once
    to check, and will record the rerun separately.
  - On GPFS the kill job's clean pass held 13 s against 5 s at cycle 0, and that job's `prep_s` was
    16 s against 4 s.
  - `repair_lines` is 0 in the kill scenario on both filesystems this time.
  - Both tables are in `PLAN.md` §5. The gate, and P1-P4's gates re-run, are green.

**Review cycle 2 — reopened (2026-10-29).** The cycle 1 evidence graded R12 at `40e6120`, on trees
that hid C2-F1 and C2-F2. It is kept, moved with `git mv` to `evidence/cycle1/`, and the gate is red
again at `cluster evidence … not recorded yet`, the external wait.

**Run A, cycle 2 — extend the trees (ruling 9), re-run locally, hand back:**
- [x] `tests/repair-race.sh`:
  - (P) and kill remove every file of the interpreter with `find -type f -delete`, keeping its
    directories and links, and check the shape; `restored` probes `import json, os, ssl`.
  - (T) adds pycodestyle installed at 2.11.1 with six 1.16.0, then again unpinned, beside pinned
    pyflakes 3.2.0, and damages it the same way (`pycodestyle.py` and both `RECORD`s). Four keys,
    T only: `unpinned_version`, `unpinned_with`, `second_dist_info`, `receipts_kept`, each checked
    by the drive (2.11.1, 1.16.0, 0, 2). `restored` covers both tools.
  - (F) plants `bin/python` in its tool, which the tool arm now requires.
  - Counts, versions and fixed words only; no `/` or host name in a summary.
- [x] The gate, retuned the script-safe way: the local runs add P ×8; the local T summary must carry
  the four keys at their values and `restored=1`, and P `restored=1` and `repairs=1`; each evidence
  file's T must carry the four keys, and P, T and the clean pass `restored=1`.
- [x] Re-run the gate: every check above the evidence line passes, and it is red only at `cluster
  evidence spec/purge-tree-repair/evidence/lustre.txt not recorded yet`.
- Observed, macOS, bash 3.2, uv 0.13.6 seeded with `--uv-bin`:
  - F ×16 offline: `rc_hist=0:16 repairs=1 outcomes=1 locks_left=0 progress=ok`.
  - T ×8: `rc_hist=0:8 stdout_hist=3.2.0:8 repairs=1 outcomes=1 restored=1 unpinned_version=2.11.1
    unpinned_with=1.16.0 second_dist_info=0 receipts_kept=2`, `hold_s=0`.
  - P ×8: `rc_hist=0:8 stdout_hist=expected:8 repairs=1 outcomes=1 restored=1`, `hold_s=2`.
  - kill ×8: `rc_hist=1:7,137:1 killed=1 kill_took=group timeout_named_lock=7 outcomes=0
    restored=0 doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:8 clean_restored=1
    clean_locks_left=0`.
  - At 64 ranks: P and T `rc_hist=0:64 repairs=1 restored=1`, T's four keys as above; kill
    `rc_hist=1:63,137:1`, then `clean_rc_hist=0:64 clean_restored=1`. Assembled as both evidence
    files (with `nodes=2` set by hand for Lustre) they pass the gate's evidence half; the cycle 1
    files fail it at `scenario T lacks unpinned_version=2.11.1`, and the assembled files with
    `unpinned_version=2.11.1,2.15.0` fail the same way.
  - Against `abf84b9`'s `bin/uv-manager`, the extended drive is red: T at `rc_hist=1:8`,
    `outcome_kind=failed`, `unpinned_version=2.11.1,2.15.0`, `unpinned_with=1.16.0,1.17.0`,
    `second_dist_info=2`; P at `rc_hist=2:8`, `repairs=0`, `restored=0` with an `ok` outcome
    recorded, which is C2-F1 itself.
- [x] Hand back to the foreman: the same two job bodies above, against this commit's tree.
- Amended at build, 2026-10-29 (Run A, cycle 2, harness fix): on Linux (GNU coreutils) the cycle 2
  drive's T exited 4 at `progress=preparation failed: the damage could not be made`. Its damage step
  moved pycodestyle's and six's `RECORD` into one directory in one `mv`, and GNU `mv` refuses to
  overwrite a file it created earlier in the same call; BSD `mv` overwrites silently, which is why
  the local runs passed. Each damaged file now moves alone to a destination named for it, and the
  `--uv-bin` seed copies `uv` and `uvx` to explicit names. No other drive or gate under `tests/` or
  `.agents/factory/` moves or copies several sources into one directory.
  - No GNU `mv` on the build host. A PATH shim that refuses, as GNU `mv` does, a second source
    sharing a basename in one call reproduced the failure at `4b34ffb` (T exit 4, same line); after
    the fix T exits 0 under the shim, which logged no multi-source `mv` in the whole run.
  - Locally, macOS, bash 3.2, uv 0.13.6 seeded with `--uv-bin`, ×8: T `rc_hist=0:8 restored=1`
    with the four keys at 2.11.1, 1.16.0, 0, 2; P `rc_hist=0:8 repairs=1 restored=1`; F
    `rc_hist=0:8 repairs=1`; kill `rc_hist=1:7,137:1 killed=1`, then `clean_repairs=1
    clean_rc_hist=0:8`. P1-P4's gates green; P5's red only at the evidence line.
- [x] Hand back to the foreman: the same two job bodies above, against the harness fix's tree.

**Run B, cycle 2 — read the evidence, close the phase:**
- [x] Copy each filesystem's new evidence to `evidence/lustre.txt` and `evidence/gpfs.txt`,
  unedited, as in Run B above.
- [x] Run the gate; re-run P1-P4's.
- [x] Record the new `hold_s`, `wait_max_s` and `notice_lines` in `PLAN.md` §5 beside cycle 1's.
- [x] Mark the phase `done` with `--top-status in_review`.
- Observed at build, 2026-10-29 (Run B, cycle 2), both filesystems run against `5e1e6d9`, uv 0.13.6:
  - Lustre (2 nodes × 64 ranks), bash 5.1: P and T `rc_hist=0:128`, `repairs=1`, `outcomes=1`,
    `locks_left=0`, `restored=1`; T `unpinned_version=2.11.1 unpinned_with=1.16.0
    second_dist_info=0 receipts_kept=2`; kill `rc_hist=1:127,137:1 timeout_named_lock=127
    kill_took=group doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:128
    clean_outcomes=1 clean_locks_left=0 clean_restored=1`.
  - GPFS (1 node × 64 ranks), bash 4.4: P and T `rc_hist=0:64`, `repairs=1`, `outcomes=1`,
    `locks_left=0`, `restored=1`; T `unpinned_version=2.11.1 unpinned_with=1.16.0
    second_dist_info=0 receipts_kept=2`; kill `rc_hist=1:63,137:1 timeout_named_lock=63
    kill_took=group doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:64
    clean_outcomes=1 clean_locks_left=0 clean_restored=1`.
  - `hold_s` / `wait_max_s` / `notice_lines` per scenario:
    - Lustre: P 4 / 4 / 0; T 2 / 4 / 0; kill, killed pass none / 61 / 127; kill, clean pass
      5 / 7 / 0.
    - GPFS: P 4 / 5 / 0; T 2 / 2 / 0; kill, killed pass none / 61 / 63; kill, clean pass
      3 / 3 / 0.
  - GPFS's P hold is 4 s, against 34 s at cycle 1; that job's `prep_s` is 6 s, against 12 s.
  - `repair_lines` is 1 in the kill scenario on both filesystems this time (cycle 0: 0 on Lustre,
    1 on GPFS; cycle 1: 0 on both). Neither killed pass recorded a repair (`repairs=0`,
    `outcomes=0`, `restored=0`), and both clean passes repaired once. The gate does not key on
    `repair_lines`.
  - Both tables are in `PLAN.md` §5. The gate, and P1-P4's gates re-run, are green.

**Review cycle 3 — reopened (2026-10-29).** The cycle 2 evidence graded R12 at `5e1e6d9`. C3-F1
changes the tool arm that scenario T drives, and C3-F2 changes record names (ruling 6), so it no
longer describes the code. It is kept, moved with `git mv` to `evidence/cycle2/`, and the gate is red
again at `cluster evidence … not recorded yet`, the external wait. The gate itself is unchanged; the
local real-uv drives ruling 6 adds are P3's (every refused receipt form) and P2's (the case
collision).

**Run A, cycle 3 — re-run locally, hand back:**
- [x] Re-run `tests/repair-race.sh` locally for F, P, T and kill. The drive is unchanged: T's tools
  are installed from the registry with no index option, so its receipts do not trip the receipt
  refusal, and the drive's scope values are digits.
- [x] Re-run the gate: every check above the evidence line passes, and it is red only at `cluster
  evidence spec/purge-tree-repair/evidence/lustre.txt not recorded yet`.
- Observed, macOS, bash 3.2, uv 0.13.6 seeded with `--uv-bin`:
  - F ×16 offline: `rc_hist=0:16 repairs=1 outcomes=1 locks_left=0 progress=ok`.
  - P ×8: `rc_hist=0:8 stdout_hist=expected:8 repairs=1 outcomes=1 restored=1`, `hold_s=2`.
  - T ×8: `rc_hist=0:8 stdout_hist=3.2.0:8 repairs=1 outcomes=1 restored=1 unpinned_version=2.11.1
    unpinned_with=1.16.0 second_dist_info=0 receipts_kept=2`, `hold_s=1`.
  - kill ×8: `rc_hist=1:7,137:1 killed=1 kill_took=group timeout_named_lock=7 outcomes=0
    restored=0 doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:8 clean_outcomes=1
    clean_locks_left=0 clean_restored=1`.
- A system `uv.toml` with an index on a cluster, which `temp_root.sh` does not redirect, is written
  into T's receipts, and under the amended ruling 1 that is not a refusal: T is repaired under the
  same configuration.
- [x] Hand back to the foreman: the same two job bodies above, against this commit's tree.

**Review cycle 4 — reopened (2026-10-30).** The maintainer chose "fix, verify, ship" (REVIEW.md,
*Maintainer decision*, ruling 3): C4-F1 changes both repair arms, so R12 is graded again at the fix
commit on both filesystems. Cycle 3's cluster run left no evidence file in the tree: its Lustre
result is recorded in REVIEW.md *Review cycle 4* and its GPFS jobs were cancelled while queued, so
there is nothing to move to `evidence/cycle3/`. The gate is unchanged and red only at `cluster
evidence … not recorded yet`, the external wait, so P5 stays `in_progress` and this is not an
attempt.

**Run A, cycle 4 — re-run locally, hand back:**
- [x] Re-run `tests/repair-race.sh` locally for F, P, T and kill. The drive is unchanged: its ranks
  start in a `temp_root.sh` sandbox, which holds no project configuration, so C4-F1 changes the
  directory the arms run from and nothing the drive asserts.
- [x] Re-run the gate: every check above the evidence line passes, and it is red only at `cluster
  evidence spec/purge-tree-repair/evidence/lustre.txt not recorded yet`.
- Observed, macOS, bash 3.2, uv 0.13.6 seeded with `--uv-bin`:
  - F ×16 offline: `rc_hist=0:16 repairs=1 outcomes=1 locks_left=0 progress=ok`, `hold_s=3`.
  - P ×8: `rc_hist=0:8 stdout_hist=expected:8 repairs=1 outcomes=1 restored=1`, `hold_s=1`.
  - T ×8: `rc_hist=0:8 stdout_hist=3.2.0:8 repairs=1 outcomes=1 restored=1 unpinned_version=2.11.1
    unpinned_with=1.16.0 second_dist_info=0 receipts_kept=2`, `hold_s=1`.
  - kill ×8: `rc_hist=1:7,137:1 killed=1 kill_took=group timeout_named_lock=7 outcomes=0
    restored=0 doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:8 clean_outcomes=1
    clean_locks_left=0 clean_restored=1`.
- [x] Hand back to the foreman: the same two job bodies above, unchanged, against the C4-F1 commit's
  tree.

**Run B, cycle 4 — read the evidence, close the phase:**
- [x] Copy each filesystem's new evidence to `evidence/lustre.txt` and `evidence/gpfs.txt`,
  unedited, as in Run B above.
- [x] Run the gate; re-run P1-P4's.
- [x] Record the new `hold_s`, `wait_max_s`, `wait_p50_s` and `notice_lines` in `PLAN.md` §5 beside
  cycle 2's.
- [x] Mark the phase `done` with `--top-status in_review`.
- Observed at build, 2026-10-30 (Run B, cycle 4), both filesystems run against `bdc38d6`, uv 0.13.6:
  - Lustre (2 nodes × 64 ranks), bash 5.1: P and T `rc_hist=0:128`, `repairs=1`, `outcomes=1`,
    `locks_left=0`, `restored=1`; T `unpinned_version=2.11.1 unpinned_with=1.16.0
    second_dist_info=0 receipts_kept=2`; kill `rc_hist=1:127,137:1 timeout_named_lock=127
    kill_took=group doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:128
    clean_outcomes=1 clean_locks_left=0 clean_restored=1`.
  - GPFS (1 node × 64 ranks), bash 4.4: P and T `rc_hist=0:64`, `repairs=1`, `outcomes=1`,
    `locks_left=0`, `restored=1`; T `unpinned_version=2.11.1 unpinned_with=1.16.0
    second_dist_info=0 receipts_kept=2`; kill `rc_hist=1:63,137:1 timeout_named_lock=63
    kill_took=group doctor_warn_repair_lock=1`, then `clean_repairs=1 clean_rc_hist=0:64
    clean_outcomes=1 clean_locks_left=0 clean_restored=1`.
  - `hold_s` / `wait_max_s` / `wait_p50_s` / `notice_lines` per scenario:
    - Lustre: P 3 / 4 / 4 / 0; T 2 / 3 / 3 / 0; kill, killed pass none / 66 / 60 / 127; kill, clean
      pass 4 / 5 / 4 / 0.
    - GPFS: P 5 / 5 / 5 / 0; T 1 / 2 / 1 / 0; kill, killed pass none / 61 / 61 / 63; kill, clean
      pass 5 / 6 / 6 / 0.
  - The Lustre killed pass's slowest waiter took 66 s against the 60 s timeout (60-61 s at cycles
    0-2); its median is 60 s, and every waiter named the lock.
  - `repair_lines` in the kill scenario is 0 on Lustre and 1 on GPFS, as at cycle 0. Neither killed
    pass recorded a repair, and both clean passes repaired once. The gate does not key on it.
  - The table is in `PLAN.md` §5. The gate, and P1-P4's gates re-run, are green.

**Verify:** the frontmatter gate.
- The drive exists (the phase's own forward guard); `bash -n`; lint.
- `--launch srun` without `REPAIRRACE_SHARED` exits 2.
- Local F ×16 (offline) gives `repairs=1` and `rc_hist=0:16`.
- Local T and kill ×8 (real uv + network) exit 0.
- No local summary carries `/` or this host's name.
- For each of `lustre.txt` and `gpfs.txt`:
  - no `/`;
  - scenarios P, T and kill present;
  - `exit=0` and `progress=ok` three times each;
  - `repairs=1` and `outcomes=1` in P and T;
  - `locks_left=0` twice and `clean_locks_left=0`;
  - every `ranks` at least 64;
  - both stdout forms;
  - `killed=1`, `doctor_warn_repair_lock=1`, `clean_repairs=1`, `clean_outcomes=1`;
  - `hold_s` and `notice_lines` present.
- `nodes=2` on Lustre.

Observed at plan time:
- HEAD red at the forward guard.
- On the prototype, every check through the local runs passed, and the gate went red at `cluster
  evidence … not recorded yet`.
- Fed evidence assembled from local 64-rank P, T and kill runs (in the throwaway copy only), the gate
  went green. Those runs gave `rc_hist=0:64` and `repairs=1` for P and T. For kill they gave
  `rc_hist=1:63,137:1`, `timeout_named_lock=63`, `doctor_warn_repair_lock=1` and `clean_repairs=1`.

**Inspection-only:** the reviewer reads both evidence files for anything identifying that a pattern
cannot catch. R12 is evidence taken on trust; NFS is not exercised.

**Touches:** `tests/repair-race.sh`, `AGENTS.md`, `.agents/factory/bin/lint.sh`,
`spec/purge-tree-repair/evidence/`, `spec/purge-tree-repair/PLAN.md`.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative; the `current_phase`
   pointer is reconciled against them.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` with `run_verify.py`. Never advance on a checkbox alone, and never on
   exit 0 alone. P5 Run A is the one sanctioned stop on a red gate.
5. Amend this file freely if reality diverges. Regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**, or on a
   reading of the PLAN §5 rulings that a phase cannot honor.
6. Mark the phase `done`, advance `current_phase`, and `--touch`. Make one `[feature]` commit, then
   stop and report.
