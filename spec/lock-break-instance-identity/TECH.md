---
slug: lock-break-instance-identity
title: A losing breaker deletes the lock a third rank just won
kind: fix
appetite: big
status: in_progress
branch: fix/lock-break-instance-identity
base: main
current_phase: P3
last_updated: '2026-09-08'
phases:
- id: P1
  name: 'The instrument: a committed lock-race drive at tests/'
  status: done
  satisfies:
  - R1
  - R2
  depends_on: []
  parallel: false
  hammerable: false
  hill: downhill
  verify: "set -eu\n.agents/factory/bin/lint.sh >/dev/null\ntest -x tests/lock-race.sh\
    \ || { echo \"FAIL R1: tests/lock-race.sh is missing or not executable\" >&2;\
    \ exit 1; }\ntest -x tests/lock-race-burst.sh || { echo \"FAIL R1: tests/lock-race-burst.sh\
    \ is missing or not executable\" >&2; exit 1; }\nfor f in tests/lock-race.sh tests/lock-race-burst.sh;\
    \ do\n  n=$(grep -c -F \"$f\" .agents/factory/bin/lint.sh || true)\n  [ \"$n\"\
    \ -ge 2 ] || { echo \"FAIL: $f appears $n time(s) in lint.sh; it owes the sh -n\
    \ loop AND the shellcheck list\" >&2; exit 1; }\ndone\nout=$(tests/lock-race.sh\
    \ --plant control --ranks 64 --bursts 2 --quiet) \\\n  || { echo \"FAIL R2: the\
    \ control run reported a race where none is reachable\" >&2; exit 1; }\nfor k\
    \ in stolen_holds=0 robbed_winners=0 concurrent_installers=0 break_notes=0 progress=ok;\
    \ do\n  printf '%s\\n' \"$out\" | grep -q -F \"$k\" \\\n    || { echo \"FAIL R2:\
    \ the control run did not report $k -- got:\" >&2; printf '%s\\n' \"$out\" >&2;\
    \ exit 1; }\ndone\nif out=$(tests/lock-race.sh --plant control --ranks 8 --bursts\
    \ 2 --straggler --deadline 3 --quiet); then rc=0; else rc=$?; fi\n[ \"$rc\" -eq\
    \ 3 ] || { echo \"FAIL R1: the straggler injection gave rc $rc, not 3\" >&2; exit\
    \ 1; }\n[ -z \"$out\" ] || { echo \"FAIL R1: the straggler run put a count on\
    \ stdout: $out\" >&2; exit 1; }\nif out=$(tests/lock-race.sh --plant control --ranks\
    \ 8 --bursts 4 --late 3 --quiet); then rc=0; else rc=$?; fi\n[ \"$rc\" -eq 3 ]\
    \ || { echo \"FAIL R1: the late-write injection gave rc $rc, not 3\" >&2; exit\
    \ 1; }\n[ -z \"$out\" ] || { echo \"FAIL R1: the late-write run put a count on\
    \ stdout: $out\" >&2; exit 1; }"
- id: P2
  name: A denied break destroys no evidence (R4 sequences before R3)
  status: done
  satisfies:
  - R4
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: downhill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    for c in stray dotstray parent500 lock500; do\n  .agents/factory/bin/temp_root.sh\
    \ --offline --arch probe sh -s \"$c\" <<'R4DRIVE'\nset -u\nc=\"$1\"\nL=\"$UVM_ROOT/probe/.install.lock\"\
    \nmkdir -p \"$L\"\nprintf 'host=othernode pid=99999 nonce=r4gate\\n' > \"$L/owner\"\
    \ncase \"$c\" in\n  stray)    : > \"$L/stray\" ;;\n  dotstray) : > \"$L/.stray\"\
    \ ;;\nesac\ntouch -t 202001010000 \"$L/owner\" \"$L\"\n[ \"$c\" = parent500 ]\
    \ && chmod 500 \"$UVM_ROOT/probe\"\n[ \"$c\" = lock500 ] && chmod 500 \"$L\"\n\
    err=\"$UVM_SANDBOX/err\"\nUVM_LOCK_STALE=5 UVM_LOCK_TIMEOUT=2 uv --version >/dev/null\
    \ 2>\"$err\" || true\nchmod 700 \"$UVM_ROOT/probe\" 2>/dev/null || true\nchmod\
    \ 700 \"$L\" 2>/dev/null || true\n[ -f \"$L/owner\" ] || { echo \"FAIL R4 [$c]:\
    \ a denied break removed the owner file\" >&2; cat \"$err\" >&2; exit 1; }\nif\
    \ grep -q '<none recorded>' \"$err\"; then\n  echo \"FAIL R4 [$c]: the timeout\
    \ message lost the holder\" >&2; cat \"$err\" >&2; exit 1; fi\ngrep -q 'nonce=r4gate'\
    \ \"$err\" \\\n  || { echo \"FAIL R4 [$c]: no message named the recorded holder\"\
    \ >&2; cat \"$err\" >&2; exit 1; }\ngrep -q \"rmdir '$L'\" \"$err\" \\\n  || {\
    \ echo \"FAIL R4 [$c]: the timeout message printed no recovery command\" >&2;\
    \ cat \"$err\" >&2; exit 1; }\ngrep -q \"mark' && rmdir\" \"$err\" \\\n  || {\
    \ echo \"FAIL R4 [$c]: the recovery command does not account for the mark file\"\
    \ >&2; cat \"$err\" >&2; exit 1; }\nn=$(grep -c 'provisioning lock is forfeit'\
    \ \"$err\" || true)\n[ \"$n\" = 1 ] || { echo \"FAIL R7 [$c]: $n break notes in\
    \ one wait, want exactly 1\" >&2; cat \"$err\" >&2; exit 1; }\nt=$(grep -c 'timed\
    \ out after' \"$err\" || true)\n[ \"$t\" = 1 ] || { echo \"FAIL R4 [$c]: $t timeout\
    \ messages, want exactly 1\" >&2; exit 1; }\nR4DRIVE\ndone\n.agents/factory/bin/temp_root.sh\
    \ --offline --arch probe sh -s <<'STALEDRIVE'\nset -u\nL=\"$UVM_ROOT/probe/.install.lock\"\
    \nmkdir -p \"$L\"\nprintf 'host=othernode pid=99999 nonce=stalegate\\n' > \"$L/owner\"\
    \n: > \"$L/stray\"\ntouch -t 202001010000 \"$L/owner\" \"$L\"\nUVM_LOCK_STALE=5\
    \ UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/e1\" || true\nUVM_LOCK_STALE=5\
    \ UVM_LOCK_TIMEOUT=2 uv --version >/dev/null 2>\"$UVM_SANDBOX/e2\" || true\nn=$(grep\
    \ -c 'provisioning lock is forfeit' \"$UVM_SANDBOX/e2\" || true)\n[ \"$n\" = 1\
    \ ] || { echo \"FAIL R4: a denied break left the lock unbreakable -- the second\
    \ rank emitted $n break notes, want 1. The first break bumped the directory mtime\
    \ and uvm_age fell back to it.\" >&2; cat \"$UVM_SANDBOX/e2\" >&2; exit 1; }\n\
    STALEDRIVE\ngit grep -q -F 'rm -f \"$L/owner\" \"$L/mark\"' -- README.md \\\n\
    \  || { echo \"FAIL: README.md still documents a recovery command that leaves\
    \ the mark file behind\" >&2; exit 1; }"
- id: P3
  name: 'Age, pin, verify, remove: a break removes only the instance it judged'
  status: pending
  satisfies:
  - R3
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    test -x tests/lock-race.sh || { echo \"FAIL R3: tests/lock-race.sh is absent --\
    \ P1 has not landed\" >&2; exit 1; }\ntests/lock-race.sh --plant control --ranks\
    \ 64 --bursts 5  --quiet\ntests/lock-race.sh --plant none    --ranks 64 --bursts\
    \ 12 --quiet\ntests/lock-race.sh --plant owner   --ranks 64 --bursts 40 --quiet\n\
    tests/lock-race.sh --plant none --ranks 64 --bursts 2 --quiet | grep -q 'progress=ok'\
    \ \\\n  || { echo \"FAIL R3: the drive reported no progress, so its zeros are\
    \ a deadlock rather than a fix\" >&2; exit 1; }\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'LITTERDRIVE'\nset -u\nuv --version >/dev/null 2>&1 || { echo\
    \ \"FAIL R3: an ordinary offline drive did not provision\" >&2; exit 1; }\na=$(uname\
    \ -m)\nfor f in \"$UVM_ROOT/$a\"/.install.mark*; do\n  [ -e \"$f\" ] || continue\n\
    \  echo \"FAIL R3: the age reference was left behind in the user's tree: ${f##*/}\"\
    \ >&2\n  exit 1\ndone\n[ -d \"$UVM_ROOT/$a/.install.lock\" ] && { echo \"FAIL\
    \ R3: a lock was left behind\" >&2; exit 1; }\nexit 0\nLITTERDRIVE\ngit grep -q\
    \ 'forfeit' -- .agents/factory/invariants.md \\\n  || { echo \"FAIL: invariants.md\
    \ 5 does not carry the reworded break note\" >&2; exit 1; }\ngit grep -q 'mark'\
    \ -- .agents/factory/invariants.md \\\n  || { echo \"FAIL: invariants.md 5 does\
    \ not describe the pin this phase adds\" >&2; exit 1; }\ngit grep -q 'mark' --\
    \ AGENTS.md \\\n  || { echo \"FAIL: AGENTS.md Invariants does not describe the\
    \ pin this phase adds\" >&2; exit 1; }\nif git grep -q '0.10 ms' -- AGENTS.md\
    \ .agents/factory/invariants.md; then\n  echo \"FAIL: both files still quote the\
    \ 0.10 ms window, which measures only the redirect; the measured end-to-end window\
    \ is 0.265 ms\" >&2\n  exit 1\nfi\n"
- id: P4
  name: 'Collateral: the counters, the retake, and the single-download hold are untouched'
  status: pending
  satisfies:
  - R5
  - R6
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\nbash -n bin/uv-manager\n.agents/factory/bin/lint.sh >/dev/null\n\
    .agents/factory/bin/temp_root.sh --offline sh -s <<'HOLDDRIVE'\nset -u\nout=$(uv\
    \ --version 2>/dev/null) || { echo \"FAIL R6: the offline drive did not provision\"\
    \ >&2; exit 1; }\n[ \"$out\" = \"uv 9.9.9 (fixture)\" ] || { echo \"FAIL R6: stdout\
    \ was [$out], not the fixture version alone\" >&2; exit 1; }\na=$(uname -m)\n\
    t=$(readlink \"$UVM_ROOT/$a/current\" 2>/dev/null || true)\n[ \"$t\" = versions/9.9.9\
    \ ] || { echo \"FAIL R6: current points at [$t], not versions/9.9.9\" >&2; exit\
    \ 1; }\n[ -d \"$UVM_ROOT/$a/.install.lock\" ] && { echo \"FAIL R6: a lock was\
    \ left behind\" >&2; exit 1; }\nexit 0\nHOLDDRIVE\nn=$(grep -c flock bin/uv-manager\
    \ || true)\n[ \"$n\" = 1 ] || { echo \"FAIL R6: $n flock mentions in the script,\
    \ want exactly the one rationale comment\" >&2; exit 1; }\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -s <<'RETAKEDRIVE'\nset -u\nS=\"$UVM_SANDBOX/shim\"; mkdir -p \"\
    $S\"\nprintf '%s\\n' '#!/bin/sh' 'case \"${1:-}\" in *.install.lock) /bin/mkdir\
    \ \"$1\" || exit $?; [ -e \"$UVM_SANDBOX/fired\" ] || { : > \"$UVM_SANDBOX/fired\"\
    ; /bin/rmdir \"$1\"; }; exit 0;; esac; exec /bin/mkdir \"$@\"' > \"$S/mkdir\"\n\
    chmod +x \"$S/mkdir\"; PATH=\"$S:$PATH\"; export PATH\nout=$(uv --version 2>\"\
    $UVM_SANDBOX/err\") || { echo \"FAIL R5: the robbed winner stopped retaking the\
    \ lock\" >&2; cat \"$UVM_SANDBOX/err\" >&2; exit 1; }\n[ \"$out\" = \"uv 9.9.9\
    \ (fixture)\" ] || { echo \"FAIL R5: stdout was [$out] after a retake\" >&2; exit\
    \ 1; }\nRETAKEDRIVE\n.agents/factory/bin/temp_root.sh --offline sh -s <<'EACCESDRIVE'\n\
    set -u\nS=\"$UVM_SANDBOX/shim\"; mkdir -p \"$S\"\nprintf '%s\\n' '#!/bin/sh' 'case\
    \ \"${1:-}\" in *.install.lock) /bin/mkdir \"$1\" || exit $?; [ -e \"$UVM_SANDBOX/fired\"\
    \ ] || { : > \"$UVM_SANDBOX/fired\"; /bin/chmod 500 \"$1\"; }; exit 0;; esac;\
    \ exec /bin/mkdir \"$@\"' > \"$S/mkdir\"\nchmod +x \"$S/mkdir\"; PATH=\"$S:$PATH\"\
    ; export PATH\nif UVM_LOCK_TIMEOUT=5 UVM_LOCK_STALE=60 uv --version >/dev/null\
    \ 2>\"$UVM_SANDBOX/err\"; then\n  echo \"FAIL R5: an EACCES owner write was retried\
    \ into success\" >&2; exit 1; fi\ngrep -q 'Permission denied' \"$UVM_SANDBOX/err\"\
    \ || { echo \"FAIL R5: the errno no longer reaches stderr\" >&2; cat \"$UVM_SANDBOX/err\"\
    \ >&2; exit 1; }\ngrep -q 'cannot record ownership' \"$UVM_SANDBOX/err\" || {\
    \ echo \"FAIL R5: the fatal message is gone\" >&2; exit 1; }\nEACCESDRIVE\n.agents/factory/bin/temp_root.sh\
    \ --offline --arch probe sh -s <<'COUNTERDRIVE'\nset -u\nL=\"$UVM_ROOT/probe/.install.lock\"\
    ; mkdir -p \"$L\"\n# Our own pid: alive, and owned by us. A pid we do not own\
    \ reads as dead,\n# because kill -0 cannot distinguish EPERM from ESRCH.\nprintf\
    \ 'host=%s pid=%s nonce=fresh\\n' \"$(uname -n)\" \"$$\" > \"$L/owner\"\ns=$(date\
    \ +%s)\nif UVM_LOCK_TIMEOUT=3 UVM_LOCK_STALE=60 uv --version >/dev/null 2>\"$UVM_SANDBOX/err\"\
    ; then\n  echo \"FAIL R5: a fresh foreign lock did not time out\" >&2; exit 1;\
    \ fi\ne=$(date +%s)\n[ $((e-s)) -ge 3 ] || { echo \"FAIL R5: timed out in $((e-s))s,\
    \ before UVM_LOCK_TIMEOUT\" >&2; exit 1; }\n[ $((e-s)) -le 6 ] || { echo \"FAIL\
    \ R5: took $((e-s))s to honour a 3s timeout\" >&2; exit 1; }\nn=$(grep -c 'provisioning\
    \ lock is forfeit' \"$UVM_SANDBOX/err\" || true)\n[ \"$n\" = 0 ] || { echo \"\
    FAIL R5: a live foreign lock was declared forfeit ($n notes)\" >&2; exit 1; }\n\
    COUNTERDRIVE\ntest -x tests/lock-race.sh || { echo \"FAIL R5: tests/lock-race.sh\
    \ is absent -- P1 has not landed\" >&2; exit 1; }\ntests/lock-race.sh --plant\
    \ owner --ranks 64 --bursts 70 --quiet\n"
review:
  last_reviewed_commit: ''
  verdict: none
  blocked_reason: ''
  cycle: 0
---
# TECH.md — A losing breaker deletes the lock a third rank just won

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (`uv run .agents/factory/bin/next_phase.py spec/lock-break-instance-identity/TECH.md`);
the per-phase checklists below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus seven briefs.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); [`invariants.md`](../../.agents/factory/invariants.md) is the
  footgun checklist.
- One phase per `uvm-build` invocation; one atomic commit carrying both the code and the `TECH.md`
  state change. Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager`, `README.md` or `tests/`.
- **Every phase is `hammerable: false`.** All four touch `invariants.md` §5 behavior or the gate that
  measures it.
- **The order P2 → P3 is not cosmetic.** `main` manufactures owner-less locks through the R4 path, so
  R4 is a *prerequisite* for a break path that treats an owner-less lock carefully
  ([`research/02`](research/02-ownerless-locks.md) finding 2).

## Phase P1 — The instrument
**Satisfies:** R1, R2 · **Depends on:** —
**Goal:** a committed drive that constructs the race, counts three defects separately, and cannot
report a number it does not trust.

- [x] Add `tests/lock-race.sh` and `tests/lock-race-burst.sh`, lifting
      [`research/04`](research/04-concurrency-drive.md) § *The prototype* and
      [`research/07`](research/07-candidate-remedies.md) § *The drive's progress assertion*.
      Two files, not one: a driver holding the burst body in a heredoc is invisible to `sh -n` and to
      shellcheck.
- [x] Collection state outside the sandbox; every writer registers a liveness marker cleared on exit;
      each burst counted at its own time and every burst recounted at the end. Exit **3** with
      **nothing on stdout** when either guard fires.
- [x] The progress assertion, exit **4**: ≥1 installer entry per burst, no lock left standing, no
      non-zero rank — checked *before* any race verdict. Without it a candidate that declines every
      break scores green with all three race counters legitimately zero, which is measured, not
      hypothetical.
- [x] Splice the fixture hook into the sandbox's copy of `install.sh`; the tracked fixture is not
      edited.
- [x] Write the burst sizing into the file as a comment carrying `p`, `P_burst`, the burst count and
      the resulting false-green probability, so a reader can check the arithmetic rather than trust it.
- [x] Add both files to `.agents/factory/bin/lint.sh` at **both** `:46` (the `sh -n` loop) and `:73`
      (the shellcheck list), with `# shellcheck disable=SC2329` above `finish()`.
- [x] `AGENTS.md`: a `tests/` row in § *Repository map*, and § *Verification* no longer opens "There is
      no test suite yet" — it is one drive, not a suite, and saying so is the honest form.
- **Verify:** lint; both files present, executable and lint-covered in both lists; the control run
  clean with `break_notes=0`; all three counters reported as separate lines; and both collection
  guards exiting 3 with empty stdout.
- **Red today:** the files do not exist. **The measured red state of the wrapper is recorded here
  rather than gated**, because a gate asserting "the plants are red" would invert the moment P3 lands:
  `--plant none --ranks 64 --bursts 3` on this branch's HEAD gave `stolen_holds=7/192`,
  `concurrent_installers=7/192 via_break=7 no_break_in_burst=0`, `3/3` red bursts, `progress=ok`,
  rc 1 — reproduced by the coordinator, and the same construction on the candidate composition gave
  all zeros with one installer entry per burst and rc 0.
- **Touches:** `tests/`, `.agents/factory/bin/lint.sh`, `AGENTS.md`.
- **Amendment (2026-09-08).** The gate was retuned through `set_phase.py --verify`: it re-ran a
  64-rank control burst four times to grep four separate lines, so it now captures once and checks
  five keys against that output. Same assertion, a quarter of the wall clock, and less to flake.
- **Corrections applied to the lifted prototype**, none of them cosmetic. Its header documented exit
  codes 0–3 and omitted 4, the code it already had. Two comments cited `bin/uv-manager` line numbers
  that P3 moves. One quoted the 0.10 ms window this cycle corrects to 0.265 ms. One attributed a
  burst with no break note to the early-out at `:570`, which [`research/05`](research/05-installer-attribution.md)
  **refuted** — that path produces no installer entry at all — so it now names the three routes that
  really do produce a serialized extra entry. `LOCKRACE_STALE`/`LOCKRACE_TIMEOUT` were used without
  being in the `:?` guard list, and an unused `leftowner` marker was written and never read; both are
  fixed. The break-note regex matches the current wording **and** the one P2 introduces, so the drive
  works either side of that phase.
- **Observed:** gate green in 15 s. The control run reported `stolen_holds=0 robbed_winners=0
  concurrent_installers=0 break_notes=0 progress=ok`; `--straggler` exited 3 naming
  `live.inst.<pid>.1.straggler`; `--late` exited 3 with `installer entries 4 -> 4, concurrent 0 -> 2`.
  The five-key control block was then shown to fire — fed a `--plant none` run it rejects on
  `stolen_holds`, `concurrent_installers` and `break_notes` — because a gate never observed failing
  is not a gate, and this one is new.

## Phase P2 — A denied break destroys no evidence
**Satisfies:** R4 · **Depends on:** P1
**Goal:** a break that is decided and then refused leaves the lock exactly as it found it — `owner`
included — so the timeout message still names the holder and the next rank still sees a stale lock.

- [x] Add `uvm_lock_removable` ([`PLAN.md`](PLAN.md) § 2.1) and gate **both** removals behind it.
      Explicit dot patterns, not `shopt -s dotglob`: a bare glob cannot see a stray dot-entry and
      `shopt` is global state in a script that globs in `uvm_trampolines`. Keep the
      `[[ -e || -L ]] || continue` guard — with `nullglob` unset a non-matching pattern expands to
      itself.
- [x] Add a `last_holder` local, set from every non-empty `owner` read, and make the timeout message
      read it. Relabel to the past tense: `holder, as the lock's owner file recorded it:`.
- [x] Correct the recovery command everywhere it appears — the timeout message and `README.md:533` —
      to `rm -f '<lock>/owner' '<lock>/mark' && rmdir '<lock>'`. The current advice fails
      `Directory not empty` while any entry stands, and already fails in the state this phase fixes.
- [x] Reword the break note from an accomplished act to an attempted one:
      `provisioning lock is forfeit and will be broken (<n>s old)`. It stays where it is — moving it
      inside the decision costs the one-note-per-wait contract, and a note emitted after a successful
      removal cannot report the `owner` line it just deleted.
- [x] Update `invariants.md` §5 and `AGENTS.md`'s copy for the note wording and the recovery command.
- **Verify:** four constructions — stray entry, stray dot-entry, parent at mode 500, and `chmod 500`
  on the lock itself as the negative control — each asserting `owner` survives, the message names
  `nonce=r4gate` rather than `<none recorded>`, the recovery command accounts for `mark`, and exactly
  one break note and one timeout per wait. Plus the staleness half: a second rank one second after a
  denied break must still announce its break, which `main` prevents by bumping the directory mtime.
- **Red today:** `owner` is destroyed in three of the four constructions, the message reports
  `<none recorded>`, and the second rank emits **zero** break notes
  ([`research/03`](research/03-removal-order.md)).
- **Touches:** `bin/uv-manager`, `README.md`, `AGENTS.md`, `.agents/factory/invariants.md`.
- **Observed:** on a stray-entry plant aged past the threshold, `owner` survives, the note reads
  `provisioning lock is forfeit and will be broken (211066232s old)`, and the timeout reports
  `holder, as the lock's owner file recorded it: host=othernode pid=99999 nonce=demo` where `main`
  printed `<none recorded>`. All four constructions plus the second-rank staleness drive pass.
- **Amendment (2026-09-08), the gate's README anchor.** It was written as `mark' && rmdir`, the shape
  the *timeout message* has, and `README.md` documents the same command without those quotes — so the
  anchor could not match whatever the file said. The README paragraph also wrapped the command across
  two lines, which is both unmatchable by `git grep` and not copy-pasteable, so it is now a fenced
  block binding `L` once. The anchor is the recovery line itself, confirmed absent on `main` and
  present here.
- **Correction beyond the checklist.** The invariant asserts "a recovery command that works", and
  after this phase it still does not for a lock holding an entry the wrapper never wrote: `rm -f`
  clears `owner` and `mark`, then `rmdir` refuses. Rather than grow the wrapper's output with a line
  naming the blocker, all three documents now say the command covers what the wrapper writes and that
  `rmdir`'s own error is what reports anything else. Asserting a command works where it measurably
  does not is the defect this phase exists to remove, so the text had to move rather than the claim
  being left standing.

## Phase P3 — Age, pin, verify, remove
**Satisfies:** R3 · **Depends on:** P2
**Goal:** a break removes only the instance whose forfeiture it decided, including when that instance
recorded no `owner`.

- [ ] **Measure C1b first.** Re-running `uvm_age "${lock}"` in place of the `-ot` comparison would
      delete the reference file, its cleanup and its litter class for one fork on the provisioning
      path. [`research/01`](research/01-directory-identity.md) F4 predicts equivalence and
      [`research/07`](research/07-candidate-remedies.md) left it **unmeasured**. Run both against
      `--plant none --bursts 12`; prefer C1b if it holds, because it deletes a mechanism.
- [ ] Implement the break path in the order **age → sweep → pin → verify → remove**
      ([`PLAN.md`](PLAN.md) § 2.2). The ordering is load-bearing and non-obvious: creating an entry
      bumps the directory's mtime, so a pin placed before the age comparison makes that comparison
      unsatisfiable forever — measured as a total deadlock, 768/768 ranks timed out.
- [ ] `-d` precedes `-ot`. Bash reports `[[ MISSING -ot existing ]]` **true**, so a bare `-ot` passes
      exactly when the instance is already gone.
- [ ] `2>/dev/null` precedes the pin's output redirect, the ordering already documented at the `owner`
      write. Without it the EEXIST case emits a raw shell diagnostic once per iteration — ~180 lines
      at the shipped default timeout.
- [ ] The mark carries `${owner}`, not nothing. A pin recording no identity cannot be swept and wedges
      the lock exactly as an unswept one does.
- [ ] Sweep an abandoned pin by probing the pid it records — same host and gone means remove. No new
      environment variable and no new bound; it reuses the liveness rule already applied to `owner`.
- [ ] Declare `local` for every new variable. The prototype leaked three globals.
- [ ] Clean up the age reference on the wait loop's exits and from the EXIT trap. Left behind it
      accumulates one file per contending pid in the user's own tree forever. (Moot if C1b wins.)
- [ ] Update `invariants.md` §5 and `AGENTS.md`: the pin and its sweep are new mechanism, and the
      `mkdir`-to-`owner` window is **0.265 ms** measured end to end, not the 0.10 ms both files quote,
      which measures only the parent's redirect.
- **Verify:** the drive green on all three plants at the sized burst counts, `progress=ok`, no age
  reference and no lock left after an ordinary offline drive, and both documentation files carrying
  the pin and the corrected window.
- **Red today:** `32/8/32` on the owner-less plant and `11/3/11` on the owner plant
  ([`research/07`](research/07-candidate-remedies.md)); C1 alone reaches only `13/4/13`, and C1+C3
  only `9/0/9`, which is why the pin is in this phase rather than deferred.
- **Cost:** the gate is ~103 s. That is the price of a statistical assertion and it was sized, not
  guessed.
- **Touches:** `bin/uv-manager`, `AGENTS.md`, `.agents/factory/invariants.md`.

## Phase P4 — Collateral
**Satisfies:** R5, R6 · **Depends on:** P3
**Goal:** prove this cycle changed only what it aimed at. Every previous remediation to this function
shipped collateral rather than failing at its target, and P3's gate cannot see collateral.

- [ ] Re-run the gates of the two prior cycles rather than trusting this one's: `lock-acquire-retake`
      R1 (the `mkdir` shim's robbed winner still retakes, rc 0, fixture version on stdout) and R2 (an
      EACCES owner write still dies carrying `Permission denied` and `cannot record ownership`).
- [ ] Assert the wait-loop counters are unmoved: a fresh foreign lock still times out at
      `UVM_LOCK_TIMEOUT` and is never declared forfeit.
- [ ] The single-download hold: `uv 9.9.9 (fixture)` on stdout, `current -> versions/9.9.9`, no lock
      left, and exactly one `flock` mention in the script.
- [ ] The confirmation run the sizing brief asks for before a human signs off: `--plant owner` at
      **70** bursts, which takes the owner plant's false green from 3.5e-4 to 1.2e-3 at a
      2x-pessimistic floor. Adds ~126 s.
- **Verify:** all of the above. The regression gates are green before and after **by construction** —
  that is what makes them regression gates — and the 70-burst run is this phase's post-condition that
  is red today, since the drive does not exist yet.
- **Touches:** nothing by default. A red gate here is a finding, not a task.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase; statuses are authoritative.
2. Pre-flight: clean tree, on `branch`, `base` reachable.
3. Execute every `[ ]`, consulting `PLAN.md` and `research/`.
4. Run the phase's `verify:`. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges; regenerate frontmatter with `set_phase.py` and note the
   amendment in the commit body. STOP and escalate only on a **`GOAL.md` contradiction**.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
