#!/bin/sh
# P5 gate: the cross-node drive (R11) and the surface census (R12).
# Local half: real uv and network (pypi.org, files.pythonhosted.org, github.com,
# codeload.github.com, releases.astral.sh). Cluster half: the committed evidence.
set -u
grep -q 'ikill' tests/repair-race.sh || { echo "FAIL: P5 Run A has not landed (tests/repair-race.sh scenario ikill)" >&2; exit 1; }
bash -n bin/uv-manager || { echo "FAIL: bash -n" >&2; exit 1; }
.agents/factory/bin/lint.sh > /dev/null || { echo "FAIL: lint.sh" >&2; exit 1; }
env -u REPAIRRACE_SHARED tests/repair-race.sh --scenario I --launch srun > /dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL: --launch srun without REPAIRRACE_SHARED must exit 2" >&2; exit 1; }
u=$(command -v uv); case "$u" in ''|"$PWD"/bin/*) echo "FAIL: need a real uv on PATH" >&2; exit 1 ;; esac
s="$(mktemp -d "${TMPDIR:-/tmp}/itp-p5.XXXXXX")"
key() { sed -n "s/^$1=//p" "$2" | head -n 1; }
tests/repair-race.sh --scenario F --ranks 16 --summary "$s/F.txt" > /dev/null || { echo "FAIL: local F" >&2; cat "$s/F.txt" >&2; exit 1; }
tests/repair-race.sh --scenario T --ranks 8 --uv-bin "$u" --summary "$s/T.txt" > /dev/null || { echo "FAIL: local T" >&2; cat "$s/T.txt" >&2; exit 1; }
tests/repair-race.sh --scenario I --ranks 16 --uv-bin "$u" --summary "$s/I.txt" > /dev/null || { echo "FAIL: local I" >&2; cat "$s/I.txt" >&2; exit 1; }
tests/repair-race.sh --scenario ikill --ranks 8 --uv-bin "$u" --summary "$s/ikill.txt" > /dev/null || { echo "FAIL: local ikill" >&2; cat "$s/ikill.txt" >&2; exit 1; }
for k in rc_hist=0:16 stdout_hist=expected:16 restores=1 outcomes=1 locks_left=0 frozen_identical=5 manifests_kept=5 records_identical=5 receipts_kept=5 commit_kept=1 unpinned_upgrade=moved; do
    grep -qx "$k" "$s/I.txt" || { echo "FAIL: local I lacks $k" >&2; cat "$s/I.txt" >&2; exit 1; }
done
for k in killed=1 rc_hist=1:7,137:1 timeout_named_lock=7 timeout_named_owner=7 outcomes=0 doctor_warn_repair_lock=1 clean_restores=1 clean_rc_hist=0:8 clean_locks_left=0 clean_frozen_identical=5 clean_records_identical=5; do
    grep -qx "$k" "$s/ikill.txt" || { echo "FAIL: local ikill lacks $k" >&2; cat "$s/ikill.txt" >&2; exit 1; }
done
grep -qx 'receipts_kept=2' "$s/T.txt" && grep -qx 'unpinned_version=2.11.1' "$s/T.txt" || { echo "FAIL: scenario T regressed" >&2; cat "$s/T.txt" >&2; exit 1; }
if grep -n -e '/' -e "$(uname -n)" "$s"/*.txt; then echo "FAIL: a local summary carries a path or this host's name" >&2; exit 1; fi
# R12: the surface census, every file named; each hit is then read against R12's list.
for f in bin/uv-manager README.md etc/uv-manager.conf.example share/modulefiles/uv/main.lua AGENTS.md .agents/factory/invariants.md; do
    git grep -q UVM_DATA -- "$f" || { echo "FAIL R12: $f does not name UVM_DATA" >&2; exit 1; }
done
if git grep -n -e 'none under \$HOME' -e 'use .uvx <tool>. in the job script' -- README.md; then echo "FAIL R12: a statement R12 drops still stands" >&2; exit 1; fi
[ "$(.agents/factory/bin/temp_root.sh uvm help | grep -c UVM_DATA)" -ge 1 ] || { echo "FAIL R12: uvm help does not name UVM_DATA" >&2; exit 1; }
for f in README.md share/modulefiles/uv/main.lua; do
    git grep -q -i 'once after upgrading' -- "$f" || { echo "FAIL R12: $f does not say to run doctor once after upgrading" >&2; exit 1; }
done
if git grep -n -E '^#+ .*[0-9]+\.[0-9]+\.[0-9]+' -- README.md; then echo "FAIL R12: a README section is titled by a version" >&2; exit 1; fi
sed -n '/^### Release note$/,/^### /p' spec/installed-tool-parity/PLAN.md | grep -q 'UVM_DATA/bin' || { echo "FAIL R12: PLAN.md has no Release note naming UVM_DATA/bin" >&2; exit 1; }
git grep -q 'uvm_tool_entry' -- AGENTS.md || { echo "FAIL R12: AGENTS.md does not name uvm_tool_entry among the high-risk regions" >&2; exit 1; }
# R11: the cluster evidence, job 1's summary then job 2's, unedited.
e=spec/installed-tool-parity/evidence/lustre.txt
test -s "$e" || { echo "FAIL: cluster evidence $e not recorded yet (the external wait)" >&2; exit 1; }
if grep -n -e '/' "$e"; then echo "FAIL: $e carries a path" >&2; exit 1; fi
for sc in I ikill; do grep -qx "scenario=$sc" "$e" || { echo "FAIL: $e lacks scenario $sc" >&2; exit 1; }; done
[ "$(grep -c '^exit=0$' "$e")" -eq 2 ] && [ "$(grep -c '^progress=ok$' "$e")" -eq 2 ] || { echo "FAIL: $e: a scenario did not exit 0 with progress=ok" >&2; exit 1; }
[ "$(grep -c '^ranks=128$' "$e")" -eq 2 ] && [ "$(grep -c '^nodes=2$' "$e")" -eq 2 ] && grep -qx 'clean_nodes=2' "$e" || { echo "FAIL: $e: not 128 ranks across 2 nodes" >&2; exit 1; }
for k in rc_hist=0:128 stdout_hist=expected:128 restores=1 outcomes=1 locks_left=0 unpinned_upgrade=moved \
         clean_rc_hist=0:128 clean_stdout_hist=expected:128 clean_restores=1 clean_outcomes=1 clean_locks_left=0 \
         killed=1 rc_hist=1:127,137:1 timeout_named_lock=127 timeout_named_owner=127 outcomes=0 locks_left=1 doctor_warn_repair_lock=1; do
    grep -qx "$k" "$e" || { echo "FAIL: $e lacks $k" >&2; exit 1; }
done
for k in frozen_identical manifests_kept records_identical receipts_kept minor_kept; do
    grep -qx "$k=5" "$e" && grep -qx "clean_$k=5" "$e" || { echo "FAIL: $e: $k" >&2; exit 1; }
done
grep -qx 'commit_kept=1' "$e" && grep -qx 'clean_commit_kept=1' "$e" || { echo "FAIL: $e: the git commit moved" >&2; exit 1; }
grep -q '^hold_s=[0-9]' "$e" && grep -q '^notice_lines=' "$e" || { echo "FAIL: $e: hold or notice keys" >&2; exit 1; }
echo "P5 ok"
