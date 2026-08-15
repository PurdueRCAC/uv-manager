---
slug: doctor-detection-gaps
title: '`uvm doctor` reports OK on the damage it exists to find'
kind: fix
appetite: big
status: blocked
branch: fix/doctor-detection-gaps
base: main
current_phase: done
last_updated: '2026-08-15'
phases:
- id: P1
  name: 'Drive the walk from the dist-info glob: detect a missing manifest, drop the
    per-distribution forks'
  status: done
  satisfies:
  - R1
  - R5
  depends_on: []
  parallel: false
  hammerable: false
  hill: crest
  verify: 'set -eu

    bash -n bin/uv-manager

    .agents/factory/bin/lint.sh >/dev/null

    .agents/factory/bin/temp_root.sh --offline sh -c ''

    set -e

    uv --version >/dev/null 2>&1

    A="$UVM_ROOT/$(uname -m)"; T="$A/tools/t"; S="$T/lib/python3.12/site-packages"

    mkdir -p "$T/bin" "$S/a-1.0.dist-info" "$S/c-1.0.dist-info" "$S/c" "$S/d-1.0.dist-info"
    "$S/d" "$S/e-1.0.dist-info" "$S/e"

    printf "home = /usr\\n" > "$T/pyvenv.cfg"

    printf "[tool]\\n" > "$T/uv-receipt.toml"

    : > "$S/c/here.py"; : > "$S/d/here.py"; : > "$S/e/here.py"

    printf "c/here.py,sha,1\\n\\n\"c/quoted,comma.py\",sha,2\\n../../bin/x,sha,3\\n/abs/x.py,sha,4\\n,,\\nc/gone.py,sha,5\\n"
    > "$S/c-1.0.dist-info/RECORD"

    printf "d/here.py,sha,1\\r\\nd/gone.py,sha,2\\r\\n" > "$S/d-1.0.dist-info/RECORD"

    printf "e/here.py,sha,1\\ne/gone.py,sha,2" > "$S/e-1.0.dist-info/RECORD"

    out=$(uvm doctor) && { echo "FAIL: doctor exited 0 on a damaged tree" >&2; exit
    1; }

    case "$out" in *"a-1.0 has no RECORD"*) ;; *) echo "FAIL: dist-info with no RECORD
    not reported" >&2; exit 1 ;; esac

    case "$out" in *"c-1.0 is missing 2 of 3"*) ;; *) echo "FAIL: verdict moved on
    quoted-comma, ../, absolute or blank lines" >&2; exit 1 ;; esac

    case "$out" in *"d-1.0 is missing 1 of 2"*) ;; *) echo "FAIL: verdict moved on
    a CRLF RECORD" >&2; exit 1 ;; esac

    case "$out" in *"e-1.0 is missing 1 of 2"*) ;; *) echo "FAIL: RECORD with no trailing
    newline not walked" >&2; exit 1 ;; esac

    '''
- id: P2
  name: Probe for a missing pyvenv.cfg, and hold detection read-only
  status: done
  satisfies:
  - R2
  - R6
  depends_on:
  - P1
  parallel: false
  hammerable: false
  hill: crest
  verify: "set -eu\n.agents/factory/bin/lint.sh >/dev/null\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -c '\nset -e\nuv --version >/dev/null 2>&1\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; S=\"$A/tools/t/lib/python3.12/site-packages\"\nmkdir -p \"$S/a-1.0.dist-info\"\
    \ \"$S/a\" \"$A/tools/t/bin\"\nprintf \"[tool]\\n\" > \"$A/tools/t/uv-receipt.toml\"\
    \nprintf \"a/x.py,sha,1\\n\" > \"$S/a-1.0.dist-info/RECORD\"; : > \"$S/a/x.py\"\
    \nfind \"$A\" -type f -exec shasum {} + | sort > \"$UVM_SANDBOX/before\"\nfind\
    \ \"$A\" | sort >> \"$UVM_SANDBOX/before\"\nout=$(uvm doctor) && { echo \"FAIL:\
    \ tool with no pyvenv.cfg but doctor exited 0\" >&2; exit 1; }\ncase \"$out\"\
    \ in *pyvenv*) ;; *) echo \"FAIL: missing pyvenv.cfg not reported\" >&2; exit\
    \ 1 ;; esac\ncase \"$out\" in *\"no automated repair\"*) ;; *) echo \"FAIL: no-safe-repair\
    \ wording absent\" >&2; exit 1 ;; esac\nfind \"$A\" -type f -exec shasum {} +\
    \ | sort > \"$UVM_SANDBOX/after\"\nfind \"$A\" | sort >> \"$UVM_SANDBOX/after\"\
    \nif ! diff \"$UVM_SANDBOX/before\" \"$UVM_SANDBOX/after\" >/dev/null; then\n\
    \  echo \"FAIL: doctor wrote to the state tree\" >&2; exit 1\nfi\n'\n"
- id: P3
  name: Split advice from failure in the exit status, and print remedies that repair
  status: done
  satisfies:
  - R3
  - R4
  depends_on:
  - P2
  parallel: false
  hammerable: false
  hill: crest
  verify: "set -eu\n.agents/factory/bin/lint.sh >/dev/null\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -c '\nset -e\nuv --version >/dev/null 2>&1\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; T=\"$A/tools/t\"; S=\"$T/lib/python3.12/site-packages\"\nmkdir -p \"\
    $S/a-1.0.dist-info\" \"$S/a\" \"$T/bin\"\nprintf \"home = /usr\\n\" > \"$T/pyvenv.cfg\"\
    \nprintf \"a/x.py,sha,1\\n\" > \"$S/a-1.0.dist-info/RECORD\"; : > \"$S/a/x.py\"\
    \nfind \"$A\" -type f -exec shasum {} + | sort > \"$UVM_SANDBOX/before\"\nfind\
    \ \"$A\" | sort >> \"$UVM_SANDBOX/before\"\nout=$(uvm doctor) || { echo \"FAIL:\
    \ advisory-only tree exited non-zero\" >&2; exit 1; }\ncase \"$out\" in *receipt*)\
    \ ;; *) echo \"FAIL: advisory line absent\" >&2; exit 1 ;; esac\nfind \"$A\" -type\
    \ f -exec shasum {} + | sort > \"$UVM_SANDBOX/after\"\nfind \"$A\" | sort >> \"\
    $UVM_SANDBOX/after\"\nif ! diff \"$UVM_SANDBOX/before\" \"$UVM_SANDBOX/after\"\
    \ >/dev/null; then\n  echo \"FAIL: doctor wrote to the state tree\" >&2; exit\
    \ 1\nfi\nunlink \"$S/a/x.py\"\nout2=$(uvm doctor) && { echo \"FAIL: real damage\
    \ did not set the exit status\" >&2; exit 1; }\ncase \"$out2\" in *\"uv-manager\
    \ install\"*) echo \"FAIL: remediation still recommends uv-manager install\" >&2;\
    \ exit 1 ;; esac\ncase \"$out2\" in *\"--no-cache\"*) ;; *) echo \"FAIL: remediation\
    \ omits the --no-cache idiom\" >&2; exit 1 ;; esac\ncase \"$out2\" in *\"exits\
    \ 1 on a tool reported above\"*) ;; *) echo \"FAIL: remediation does not say a\
    \ receipt-less tool fails the first command\" >&2; exit 1 ;; esac\nuvm doctor\
    \ 2>\"$UVM_SANDBOX/err\" | head -1 >/dev/null\nif grep -q \"write error\" \"$UVM_SANDBOX/err\"\
    ; then\n  echo \"FAIL: printf SIGPIPE leaked through the remediation block\" >&2;\
    \ exit 1\nfi\n'"
- id: P4
  name: State the detection floor in README rather than implying the check is exhaustive
  status: done
  satisfies:
  - R7
  depends_on:
  - P3
  parallel: false
  hammerable: false
  hill: uphill
  verify: "set -eu\n.agents/factory/bin/lint.sh >/dev/null\nif git grep -q \"detects\
    \ what uv does not\" -- README.md; then\n  echo \"FAIL: README still presents\
    \ doctor's detection as a complete list\" >&2; exit 1\nfi\n.agents/factory/bin/temp_root.sh\
    \ --offline sh -c '\nset -e\nuv --version >/dev/null 2>&1\nA=\"$UVM_ROOT/$(uname\
    \ -m)\"; S=\"$A/tools/t/lib/python3.12/site-packages\"\nmkdir -p \"$S/a-1.0.dist-info\"\
    \ \"$S/a\" \"$A/tools/t/bin\"\nprintf \"home = /usr\\n\" > \"$A/tools/t/pyvenv.cfg\"\
    \nprintf \"[tool]\\n\" > \"$A/tools/t/uv-receipt.toml\"\nprintf \"a/x.py,sha,1\\\
    n\" > \"$S/a-1.0.dist-info/RECORD\"; : > \"$S/a/x.py\"\nout=$(uvm doctor) || {\
    \ echo \"FAIL: intact tree no longer exits 0\" >&2; exit 1; }\ncase \"$out\" in\
    \ \"OK\"*) ;; *) echo \"FAIL: intact tree did not report OK\" >&2; exit 1 ;; esac\n\
    '\n"
review:
  last_reviewed_commit: 4208498a33b14aa8181e50ea945d033f1e892310
  verdict: changes-requested
  blocked_reason: Clearing the receipt-less orphan leaves a dangling shim the block
    never names
  cycle: 2
---
# TECH.md — `uvm doctor` reports OK on the damage it exists to find

The **context engine and finite-state machine** for building this fix. The YAML frontmatter above is
the resume ground truth (read it with
`uv run .agents/factory/bin/next_phase.py spec/doctor-detection-gaps/TECH.md`); the per-phase
checklists below are the work.

- **Vision / requirements (locked):** [`GOAL.md`](GOAL.md) — R-IDs are the contract.
- **Authoritative design:** [`PLAN.md`](PLAN.md).
- **Backing research:** [`research/00-digest.md`](research/00-digest.md) plus three briefs.

## Conventions (apply to every phase)

- Commit conventions, code style, prose voice and load-bearing invariants come from
  [`AGENTS.md`](../../AGENTS.md); [`invariants.md`](../../.agents/factory/invariants.md) is the
  footgun checklist. §7, §8, §10 and §12 are the sections this cycle touches.
- One phase per `uvm-build` invocation; one atomic commit containing both the code and the `TECH.md`
  state change. Subjects follow `[fix] Build doctor-detection-gaps P<n>: …`.
- Keep the `Co-Authored-By: Claude Opus 5` trailer.
- No feature-scoped spec ids (`R1`, `P3`) in `bin/uv-manager` or `README.md`.
- Every gate fabricates its own tool tree inside the sandbox. None needs a real uv, real packages, or
  network — doctor reads the filesystem only.

---

## Phase P1 — Drive the walk from the dist-info glob
**Satisfies:** R1, R5 · **Depends on:** —
**Goal:** a distribution whose `RECORD` is gone is reported instead of being invisible, and the same
loop stops spawning six processes per distribution. One edit, because R1's probe and R5's rewrite are
the same loop.

- [x] Change the glob at `bin/uv-manager:706` from `*.dist-info/RECORD` to `*.dist-info`, and derive
      `record="${di}/RECORD"` and `sp="${di%/*}"` inside the loop.
- [x] Report a `dist-info` with no `RECORD` as a failure and `continue`.
- [x] Replace `sp="$(dirname -- "$(dirname -- "${record}")")"` with parameter expansion, and the
      `$(basename -- "$(dirname …)" .dist-info)` chain with `${di##*/}` / `${name%.dist-info}`.
- [x] Replace `< <(awk -F, …)` with `< "${record}"`, splitting via `IFS=, read -r rel _` and stripping
      quotes with `${rel#\"}` / `${rel%\"}`.
- [x] **Keep the `|| [[ -n "${rel}" ]]` guard on the read loop.** Without it a `RECORD` whose final
      line lacks a trailing newline loses that entry and the walk goes silent on a damaged
      distribution — see [`research/01`](research/01-fork-free-record-walk.md) §4. This is the one
      detail in the phase that fails silently if dropped.
- [x] Preserve `awk`'s truncation of a quoted path containing a comma. Byte-identical means
      reproducing that, not correcting it.
- **Verify:** the gate builds `a-1.0.dist-info` (no `RECORD` at all) and three manifests carrying the
  shapes the rewrite could move — `c-1.0` (a quoted path containing a comma, a `../` escape, an
  absolute path, a blank line, a bare `,,`), `d-1.0` (CRLF), and `e-1.0` (final line with **no
  trailing newline**). Post-conditions: doctor exits non-zero, reports `a-1.0 has no RECORD`, and
  reaches `c-1.0 is missing 2 of 3`, `d-1.0 is missing 1 of 2`, `e-1.0 is missing 1 of 2`.
  **Amended during the build** (was: `a-1.0` named plus a single `b-1.0 is missing 1 of 1`). Those
  three counts are what `git show main:bin/uv-manager` produces on the same tree, verified by running
  both against it, so they are R5's verdict-equality half made durable — the original gate left it
  unchecked, and a comparison against `main` cannot be written into a gate that outlives the merge.
  No speed threshold is asserted — the ratio is tree-shaped (PLAN §5); measured 0.505 s → 0.090 s over
  100 distributions.
- **Touches:** `bin/uv-manager`.

## Phase P2 — Probe for a missing `pyvenv.cfg`, and hold detection read-only
**Satisfies:** R2, R6 · **Depends on:** P1
**Goal:** the damage class that makes any in-place repair escape the tree becomes visible, and the
whole detection surface is proven to write nothing.

- [x] Add `[[ -f "${d}pyvenv.cfg" ]]` to the existing `for d in "${uvm_root}/tools"/*/` loop — no new
      glob, no fork.
- [x] Report it as a failure whose text states that no automated repair is safe for the class, because
      uv falls back to the base interpreter and writes outside this tree.
- [x] Add nothing that writes. R6 is preservation, not repair: doctor is already read-only
      ([`research/02`](research/02-doctor-baseline.md) §3).
- **Verify:** post-conditions are that a tool with no `pyvenv.cfg` is named, the phrase
  `no automated repair` appears, doctor exits 1, and a path list plus `shasum` of every file under the
  arch root is byte-identical across the run. The manifest deliberately compares paths, mtimes and
  content and **not** atime — the walk reads every `RECORD`, so an atime comparison would fail on
  correct code (R6's own carve-out). Observed: `FAIL  tool t1 has no pyvenv.cfg; no automated repair
  is safe for it`, exit 1, a fully intact tool alongside it silent, and a tool missing both markers
  reporting both. The gate's two halves were proven separately against the pre-change tree — the
  `pyvenv` assertion red, the read-only manifest green — and the manifest was proven non-vacuous by
  writing a file into the tree mid-run and watching it go red. A preservation assertion is green on
  both sides of the fix, so red-before-green-after cannot certify it; tampering can.
- **Touches:** `bin/uv-manager`.

## Phase P3 — Split advice from failure, and print remedies that repair
**Satisfies:** R3, R4 · **Depends on:** P2
**Goal:** automation can key on doctor's exit status, and a user who follows its advice repairs the
tree instead of overriding the site's pin.

- [x] Split `problems` into failures and advisories. The rule to implement and document: a `FAIL`
      means the tree does not work and sets the exit status; a `WARN` is information about a tree that
      does work and does not. Exactly one existing finding moves — the receipt-less tool directory.
- [x] Make the `WARN` line self-contained, since a tree with no failures now prints no remediation
      block: uv ignores such a directory, so say to remove it or reinstall the tool by name.
- [x] Give the success line an advisory suffix so it does not contradict what was printed above it.
- [x] Replace the six `printf`s at `bin/uv-manager:744-749` with one heredoc through `cat`
      (invariant §7). The delimiter stays unquoted because the failure count interpolates — confirm
      the body contains no unescaped `$`.
- [x] **Amendment — every finding leaves through `cat`, not only the remediation block.** The plan
      scoped the heredoc to the trailing block, and that is not enough to satisfy R4's own check:
      `uvm doctor | head -1` closes the pipe after the *first finding*, so the second finding's
      `printf` reports `write error: Broken pipe` while the remediation block is never reached. The
      gate caught it — red on the first run of this phase. Findings therefore accumulate into one
      `findings` string and the whole report leaves through a single `cat`, which also deletes the
      remaining ten `printf` calls in the function. Buffering costs incremental output on a slow scan;
      the managed-interpreter probe execs a python per interpreter, so a large tree now prints nothing
      until it finishes. Judged the cheaper side of the trade against an invariant that exists because
      the noise lands in a job log.
- [x] Name `uv tool upgrade --all --reinstall --no-cache` and `uv python install --reinstall`, and say
      why `--no-cache` carries the repair. **Delete `uv-manager install` rather than replacing it**: an
      ordinary `uv` call re-provisions and honors `UVM_PIN`
      ([`research/02`](research/02-doctor-baseline.md) §5).
- [x] Add the `pyvenv.cfg` paragraph — neither command repairs that class and neither is safe against
      it. PLAN §2 has the drafted text.
- [x] **Remediation, review cycle 1 (F1).** Say what the first command does when the same tree also
      carries the receipt-less advisory this phase made non-failing. Reopened rather than deferred
      because the finding is against R4's own text, which is this phase's deliverable.

      The finding reported the command as failing without repairing. Measured before writing the
      sentence, against real `uv 0.12.4` with `UV_TOOL_DIR`, `UV_CACHE_DIR`, `UV_TOOL_BIN_DIR` and
      `XDG_CONFIG_HOME` isolated under `$TMPDIR`: with one orphaned tool and one tool missing a
      recorded file, `uv tool upgrade --all --reinstall --no-cache` **restored the missing file** and
      then exited 1 naming the orphan. It is not all-or-nothing, and it does not stop at the first
      failure — the orphan sorts first and the healthy tool was still repaired. Both the reviewer's
      repro and `spec/purge-resilient-run/research/04-uv-repair-idioms.md` §4 characterized this class
      with a single tool in the tree, where "exits 1" and "repairs nothing" are indistinguishable.
      The block therefore states the real behavior rather than warning the command is useless, which
      would have been the wrong repair and would have talked a user out of a command that works.
- **Verify:** post-conditions are that an advisory-only tree exits **0** with the advisory printed and
  the state tree unchanged; that adding a real failure makes it exit **1**; that the output contains
  no `uv-manager install` and does contain `--no-cache`; and that `uvm doctor | head -1` writes
  nothing matching `write error` to stderr. The read-only manifest is repeated here so the assertion
  covers the completed implementation, not just P2's snapshot. Observed: advisory-only tree prints
  `WARN … Remove it or reinstall by name.` then `OK … (1 advisory finding(s) above)` and exits 0;
  removing one recorded file flips it to exit 1 with the two-command block. The SIGPIPE assertion was
  first shown non-vacuous — 20 of 20 runs leak at `main`, 0 of 20 after — since a race asserted once
  proves little either way. The heredoc's single expansion was checked against a tool directory named
  ``ev$(id)x-${HOME}-`id`-il``: all three forms reach stdout literally and nothing executes.
  **Retuned in review cycle 1** with a fourth assertion on `out2`, which the gate already builds as
  the mixed tree the finding describes — a receipt-less tool alongside a real failure. Proven red
  before the edit and green after, both under `run_verify.py` so the folded YAML is what executed.
  The anchor sits inside one line of the block: `git grep` is line-based and this file's prose is
  hard-wrapped, which produced a false green once already while authoring P4.
- **Touches:** `bin/uv-manager`.

## Phase P4 — State the detection floor in `README.md`
**Satisfies:** R7 · **Depends on:** P3
**Goal:** the document that sends users to doctor stops implying doctor sees everything.

- [x] Rewrite `README.md:416-418`. It currently enumerates four detected classes and names the
      `RECORD` walk as the mechanism, which reads as a complete list.
- [x] State the two facts that have to survive the edit: a distribution deleted entirely leaves no
      ground truth, because `uv-receipt.toml` records only the top-level request rather than the
      distributions it resolves to; and managed interpreters carry no manifest, so doctor's oracle is
      `import json, os, ssl`, which survives the removal of `email/`, `xml/` and `unittest/`.
- [x] Re-read the `uvm_help` doctor line and `share/modulefiles/uv/main.lua:78,92` against the
      behavior P1–P3 landed, and change them only if they became untrue. The same-commit rule requires
      the check, not an edit. **Checked, all still true, so nothing moved:** the help line and the
      modulefile both describe doctor as a check for a purged or damaged tree without claiming
      completeness or an exit-status contract, and the modulefile's "run it if something that used to
      work stops importing" is more true after P1 than before it.
- [x] Update the README doctor row at `:180` and the verification block at `:294` if the exit-status
      contract from P3 invalidated either. **Neither was invalidated** — the row is a one-line effect
      description and the verification block runs doctor without asserting a status. The contract is
      stated instead where it is actionable: beside the job-prologue advice in the rewritten bullet,
      which is the sentence P3 made true and which is useless without knowing advisories do not fail.
- **Verify:** the mechanical half asserts the completeness-implying sentence is gone
  (`detects what uv does not`, chosen because it lives on one line — the longer phrase
  `found by walking each distribution` wraps and `git grep` is line-based, which produced a false
  green while authoring this plan), plus `lint.sh` and a drive proving an intact tree still reports
  `OK` and exits 0. **The other half is inspection-only:** no grep can decide whether the replacement
  prose is honest and in the project's voice. `/uvm-review` grades it against the two facts above and
  against `AGENTS.md` § *Prose and comments*, rather than treating the green gate as coverage.
  Observed: the anchor was present and the gate red before the edit, absent and green after, with an
  intact tree still reporting `OK` and exiting 0. **For the reviewer**, the replacement makes one
  claim beyond the two required facts — that the walk now starts from the distribution rather than
  from its manifest — which is what makes "a distribution whose `RECORD` manifest is gone" a
  detectable class rather than a contradiction. That sentence was rewritten once during this phase
  because the first draft still said doctor walks each distribution's `RECORD`, which would have been
  a documented mechanism P1 had already replaced.
- **Touches:** `README.md`. The same-commit check found `bin/uv-manager` and
  `share/modulefiles/uv/main.lua` still true, so neither moved.

---

## How `uvm-build` drives this

1. `next_phase.py` prints the next actionable phase. Statuses are authoritative.
2. Pre-flight: clean tree, on `fix/doctor-detection-gaps`, `main` reachable.
3. Execute every `[ ]` in the phase, consulting `PLAN.md` and `research/` for detail.
4. Run the phase's `verify:` command. Never advance on a checkbox alone, and never on exit 0 alone.
5. Amend this file freely if reality diverges — regenerate frontmatter with `set_phase.py` and note
   the amendment in the commit body. STOP and escalate only on a `GOAL.md` contradiction.
6. Mark the phase `done`, advance `current_phase`, `--touch`; one `[fix]` commit; stop and report.
