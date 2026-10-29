# 05 — Surface: `uvm doctor`, `uvm clean`, and the R9/R7 census

Measured on this branch's base (`main` content) and on a throwaway copy patched as below, under
`temp_root.sh --offline`.

## A. R8 — doctor and clean

**WARN, not FAIL.** Doctor's own rule is that FAIL means the tree does not work. A standing lock is
seen by every rank while any rank provisions, and README recommends doctor in a job prologue keyed on
exit status, so FAIL would fail healthy ranks beside a healthy provisioner. The lock costs a
provisioning call a full `UVM_LOCK_TIMEOUT` wait, then the call proceeds; on a warm tree the fast path
never touches the lock. That is information about a tree that works. A WARN line carries its own
remedy, because a run with no FAIL prints no remediation block.

Finding, appended to `findings` ahead of the final `cat` (one line, as the receipt WARN is):

```bash
  # A standing lock is advice, never a failure. Every rank sees one while any
  # rank provisions, so a prologue keyed on the exit status would fail beside
  # a healthy provisioner. The line reports what the lock records and judges
  # nothing; the wrapper does not ask whether its holder is alive.
  local lock="${uvm_root}/.install.lock" holder=""
  if [[ -d "${lock}" ]]; then
    read -r holder 2>/dev/null < "${lock}/owner" || true
    findings+="WARN  provisioning lock standing: ${lock}"
    findings+=" (owner: ${holder:-<none recorded>})."
    findings+=" Its holder may still be running; once nothing is provisioning"
    findings+=" this tree, remove it with uvm clean lock --yes."$'\n'
    advisories=$(( advisories + 1 ))
  fi
```

Driven: rc 0, `WARN … (owner: host=elsewhere.example pid=4242 nonce=plant). …` then
`OK … (1 advisory finding(s) above)`. With no `owner`, `(owner: <none recorded>)`. On a cold tree
the existing `FAIL uv binary missing` sets rc 1 with the WARN beside it; that is pre-existing.
Optional: a holder that releases between `-d` and `read` yields a `<none recorded>` report for a lock
that is gone. Guard with `[[ -n "${holder}" || -d "${lock}" ]]` before appending if the plan wants it.

**`uvm clean lock`.** The hypothesis holds: one case arm, `lock) target="${uvm_root}/.install.lock" ;;`,
the `die` string becomes `clean: expected one of: cache, lock, arch, all`, and the existing
`--yes`/`rm -rf` path runs unchanged. `rm -rf` also takes any entry a failed owner write left. `clean`
runs after `uvm_init` only: no `uvm_set_paths` and nothing that provisions. Doctor's `uvm_set_paths`
only exports variables.

The dry run's `du -sh` prints `4.0K	<lock>`, which tells a human nothing. The Clarification wants the
wording to say the lock may be live, so for the `lock` target replace it with the owner line:

```
Would remove: <root>/<arch>/.install.lock
owner: host=elsewhere.example pid=4242 nonce=plant
Its holder may still be running. Removing a live holder's lock lets a second
call provision beside it.
Re-run with --yes to proceed.
```

An absent lock prints `(absent)` through the existing `du` fallback. `--yes` on an absent lock
prints `removing <path>` with rc 0, the same as the other targets. Help: `clean [WHAT] --yes  Remove
cache (default), lock, arch tree, or all`. README table: `uv-manager clean [cache\|lock\|arch\|all] --yes`.

**Red on main:** doctor rc 0 with only `OK    no damage detected under …`. `uvm clean lock --yes`
gives rc 1 with `uv-manager: clean: expected one of: cache, arch, all`, and the lock stands.

**Gate** (red on main at the doctor assertion, green on the patched copy):

```sh
.agents/factory/bin/temp_root.sh --offline sh -c '
  r="$UVM_ROOT/$(uname -m)"; l="$r/.install.lock"; o="host=elsewhere.example pid=4242 nonce=plant"
  uv --version >/dev/null || { echo "FAIL: provision"; exit 1; }
  mkdir "$l" && printf "%s\n" "$o" > "$l/owner"
  uvm doctor > d 2>&1 || { echo "FAIL: doctor rc!=0 on a working tree"; cat d; exit 1; }
  grep -F -q "$l" d && grep -F -q "$o" d || { echo "FAIL: doctor omits the lock path or owner line"; cat d; exit 1; }
  uvm clean lock > n 2>&1 && [ -d "$l" ] && grep -F -q "$o" n || { echo "FAIL: dry run removed the lock or hid its owner"; cat n; exit 1; }
  uvm clean lock --yes && [ ! -e "$l" ] || { echo "FAIL: lock still standing"; exit 1; }
  [ "$(readlink "$r/current")" = versions/9.9.9 ] && [ -x "$r/versions/9.9.9/uv" ] || { echo "FAIL: clean lock touched the tree"; exit 1; }
  uvm doctor > d 2>&1 || { echo "FAIL: doctor rc!=0 after clean"; exit 1; }
  if grep -q install.lock d; then echo "FAIL: doctor still reports a lock"; exit 1; fi
  echo PASS'
```

**The waiter's notice prints the path form**, `rm -f '<lock>/owner' && rmdir '<lock>'`, not
`uvm clean lock --yes`. Measured: with a lock planted under `aarch64`,
`UVM_PLATFORM=x86_64 uvm clean lock --yes` prints `removing <root>/x86_64/.install.lock`, exits 0, and
leaves the `aarch64` lock standing. A human reading a compute rank's log on a login node of another
architecture, or under a different `UVM_ROOT`, gets a silent success that cleared nothing. The
absolute path is exact from any node and needs no wrapper. Doctor's WARN can name `uvm clean lock
--yes` because doctor and clean resolve the same root in the same environment. The two-step form
keeps today's rationale (a bare `rmdir` reports `Directory not empty`) and refuses an unexpected
entry rather than taking it.

## B. R9 and R7 census

R9 pattern on main: **37** hits (invariants.md 19, AGENTS.md 9, README.md 6, conf example 3).
`uvm help | grep -c UVM_LOCK_STALE` prints 1. R7 pattern on `bin/uv-manager`: **25** lines. All
three match GOAL.

**The R9 pattern under-matches.** It misses conf example `:86`/`:88` ("refreshes its lock", "as
abandoned and breaks it."), invariants `:88` ("a full stale window"), `:111` ("successful break"),
`:128` (`uvm_age`), `:133-135` ("Liveness is a fast path", `kill -0`), and `:160` ("Every break note").
It also misses AGENTS `:156-157` ("stale window", "retaken"), `:180-181` (liveness, `kill -0`),
`:187` (`uvm_proc_start`), `:204` ("Break notes"), and `:273/:275` (the lock-race paragraph's "robbed",
"declines every break"). A two-word alternation like `breaks the lock` also misses when a rewrap
splits it (Gate traps, wrapped lines). Add a single-token supplement:

`stale|kill -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher`

On main its AGENTS.md hits fall only in the lock paragraphs and `:273-275`, and its invariants.md hits
fall only in §5. Both files can be gated at **zero**. On README its one unrelated hit is `:547`,
"`du -sh` … breaks down cost", so README gets the R9 pattern at zero and the supplement printed for
the reviewer.

**Phrasing that states the contract without tripping either pattern:** "removes only a lock it
created"; "no call removes or takes another call's lock, whatever its age or its owner line
records"; "never asks whether a holder is alive". Avoid *break* in any form, *stale*, *liveness*.
Do not name `UVM_LOCK_STALE` in invariants or AGENTS. "An inherited value is ignored" is guarded by
R7's grep and drive, and naming the knob trips R9.

| Passage | Verdict |
|---|---|
| AGENTS `:143-147` mkdir paragraph | rewrite: keep mkdir rationale and EXIT/INT/TERM; early-out runs the caller-named predicate, provisioning's tests the requested version; drop "break itself" |
| AGENTS `:149-160` release by ownership | rewrite: only the creator removes the lock, by path; owner write fatal with the errno and leaves no directory; retake per plan |
| AGENTS `:162-167` no lock survives exec | keep |
| AGENTS `:169-174` persistence | keep; rewrite the last clause's "successful break" rationale |
| AGENTS `:176-189` live holder never ages out | delete |
| AGENTS `:191-198` TIMEOUT < STALE | rewrite: `UVM_LOCK_TIMEOUT` numeric/base-10 guard inside the function survives alone |
| AGENTS `:200-205` timeout message | rewrite: one notice at the threshold with the owner line and the path-form command; provisioning proceeds, repair fails naming the holder; drop break notes |
| AGENTS new | the publish into `versions/<ver>` is guarded; every success path selects |
| AGENTS high-risk table, lock row | rewrite "blocks the user until manual repair": an orphan costs each provisioning call a timeout and fails repair until cleared |
| AGENTS `:271-277` lock-race paragraph | rewrite with R15 (same commit as the instrument) |
| inv §5 b1 mkdir | keep |
| inv §5 b2 "only while still ours" | rewrite: released by path; only the creator holds it |
| inv §5 b3 ownership | rewrite as AGENTS `:149`; delete the 0.265 ms window figure (it bounded a robbery that is gone) |
| inv §5 b4 exec | keep; delete the "Under the heartbeat" sentence `:101-103` |
| inv §5 b5 persistence | keep; rewrite `:111` |
| inv §5 b6 early-out tests the version | rewrite: caller names the predicate |
| inv §5 b7 age, b8 leash, b9 liveness | delete |
| inv §5 b10 host token `uname -n` | rewrite: it now only makes the owner line name the right node for a human |
| inv §5 b11 TIMEOUT < STALE | rewrite as AGENTS `:191` |
| inv §5 b12 break/timeout | rewrite as AGENTS `:200` plus doctor reports and never judges, clean is the human's act |
| inv §4 "used by the caller, by the lock's early-out, and inside `uvm_install`" | rewrite: `uvm_have` stays the single spelling of the provisioning question; the lock runs the caller's predicate, which for provisioning is it; every success return from `uvm_install` selects |
| inv §6 "guarded by nothing" | rewrite: guarded publish, loser discards, failed rename cleans up and names the publish |
| README `:137-138` | rewrite: releases on signals; a waiter past the timeout installs for itself |
| README `:184` table, `:416-420` doctor list | add `lock`; add "a provisioning lock left standing" as an advisory |
| README `:458` Design notes, mkdir | keep; add a note recording the rejected designs in plain words ("a holder refreshing its lock", "an age threshold", "a probe of a recorded pid"), which keeps README at zero R9 hits |
| README `:526-534` troubleshooting | rewrite for the notice text, `uvm doctor` / `uvm clean lock`, may be live |
| README `:561-569` knob table, NFS note | delete the STALE row, the "Must be less than" clause and the NFS paragraph; TIMEOUT = wait, then install |
| conf `:71-88` | keep the TIMEOUT line with a new comment; delete `:74-76`, `:78-84`, `:86-88` |
| `uvm_help` | delete the two STALE lines; TIMEOUT "…before installing without it"; add `lock` to clean |
| modulefile | keep (no lock content) |

**R9 gate** (paths literal; no `git grep -c`; no bare `! cmd`):

```sh
p='UVM_LOCK_STALE|heartbeat|refresher|stale.?breaker|broken as stale|break(s|ing)? (itself|the lock|a lock|stale|its)|breaks itself'
s='stale|kill -0|uvm_age|uvm_proc_start|liveness|retake|robbed|forfeit|break|heartbeat|refresher'
if git grep -n -i -E "$p" -- AGENTS.md .agents/factory/invariants.md README.md etc/uv-manager.conf.example; then echo "FAIL: R9 pattern"; exit 1; fi
if git grep -n -i -E "$s" -- AGENTS.md .agents/factory/invariants.md etc/uv-manager.conf.example; then echo "FAIL: supplement"; exit 1; fi
if .agents/factory/bin/temp_root.sh uvm help | grep -n UVM_LOCK_STALE; then echo "FAIL: help"; exit 1; fi
git grep -n -i -E "$s" -- README.md   # printed for the reviewer, not asserted
```

**Trap found:** GOAL's `uvm help | grep -c UVM_LOCK_STALE` prints `0` *and exits 1* on a correct tree
(measured). A `verify:` that keys on exit status reads it red. Use the `if … grep -n` form above.

**This cycle (same-commit or same-phase):** all rows above; `tests/lock-race-burst.sh:68,96` still
sets and cites `UVM_LOCK_STALE` and goes with R15; AGENTS `:271-277` goes with R15.
**`/uvm-roadmap` leftovers at landing:** `ROADMAP.md` (6 hits: lock-simplification,
lock-break-instance-identity and lock-owner-write-errno entries, and the test-harness entry's R3d/R3e/R3f/R7
summary); `issues/test-harness.md` R3 ("a stale lock"), R3d (breakable as stale, inverted
TIMEOUT/STALE), R3e (retake, per the plan's decision), R3f (break instance identity), R7 (heartbeat
`ps` fork, orphaned `sleep`); retire `issues/lock-break-instance-identity.md`,
`issues/lock-owner-write-errno.md`, `issues/pin-early-out-selects-nothing.md` and
`issues/lock-simplification.md`. `issues/invariant-audit-gaps.md` already records R3 absorbed and R4
moot, so it needs nothing more.
