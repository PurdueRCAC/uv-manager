# PLAN — Stop breaking the lock, and split provisioning from repair

> **Status:** Draft for review · **Last updated:** 2026-10-27
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/)
> ([digest](research/00-digest.md)). Every design element traces to a GOAL R-ID.

## 1. Summary

The provisioning lock becomes a `mkdir` that only its creator ever removes. A waiter runs a predicate
its caller names. It speaks once after `min(30 s, UVM_LOCK_TIMEOUT)`, and at the timeout it either
proceeds (provisioning) or fails naming the holder (any other caller). Proceeding is safe because two
changes land beside it:
- the publish into `versions/<ver>` detects a rival and discards its own copy;
- every success path in `uvm_install` converges on one selection step.

The heartbeat, lock ageing, liveness probing, both break paths, the robbed retake, the
ownership-qualified release and `UVM_LOCK_STALE` are deleted. The lock section shrinks from 335 lines
to about 90, and `bin/uv-manager` from 1224 to about 1010. `tests/lock-race.sh` is re-pointed at a
correct-tree assertion and gains a Slurm mode for the cross-node drive. Five phases.

## 2. Design

### What is removed

| Removed | Where (`main`) | Why it can go |
|---|---|---|
| `uvm_proc_start`, `uvm_lock_heartbeat`, the detached refresher and its `kill`/`wait` reap | `:179-228`, `:243-250`, `:490-500` | Liveness inference (decision). |
| `uvm_age` and the age test | `:277-284`, `:423-438` | Same. |
| The `kill -0` probe, the host-token comparison and both break paths with their re-read guard | `:403-471` | Same. `uname -n` survives only as content of the owner line, for a human. |
| The robbed retake (`robbed`, its bound and message) | `:366-378` | Nothing removes a lock it did not create, so a winner cannot be robbed. The GOAL's Clarification leaves the choice to the plan; with the retake gone, R11's path is the only one. |
| The ownership-qualified release (`uvm_lock_owner`, the `owner` comparison, the "no longer ours" note) | `:230-268` | R7. It is sound by path once no rank removes another's lock (GOAL Clarification). |
| `UVM_LOCK_STALE`, `lock_stale`, the timeout<stale guard, `lock_beat` | `:166`, `:323-341`, `:495` | R7. An inherited value is ignored silently. |
| The nonce in the owner line | `:309` | It existed to disambiguate a recycled pid for a comparison that no longer exists. |
| `uvm_ensure_uv`'s duplicate fast path | `:628-632` | `uvm_install`'s own fast path does the same work (R13). |
| The `|| return 0` early-out that skipped selection | `:570` | R12. |
| The `owner`/`none` plants and the `stolen_holds`/`robbed_winners`/`break_notes` counters in `tests/lock-race.sh` | `tests/` | R15. They can no longer fire. |

### `bin/uv-manager`, function by function

**Knobs.** `lock_stale` goes. `lock_timeout` stays. Its form test (`^[0-9]+$`) and base-10
normalisation stay inside `uvm_acquire_lock`, so `uvm help` still answers on a misconfigured node.

**`uvm_unlock`** is release by path:
```bash
  [[ -n "${uvm_lock}" ]] || return 0
  local lock="${uvm_lock}"; uvm_lock=""
  rm -f "${lock}/owner" 2>/dev/null || true
  rmdir "${lock}" 2>/dev/null || true
```
The traps are unchanged: `EXIT`, `INT` (130) and `TERM` (143). So are the four `uvm_unlock` guards
in front of `exec`. A rank that proceeded past the timeout holds nothing, so every guard costs one
builtin test (research 01 Q4).

**`uvm_acquire_lock ON_TIMEOUT PREDICATE [ARG...]`.** `ON_TIMEOUT` is `proceed` or `fail`. The
predicate is a command run as `"$@"` once per second; true means the caller's work is already done.
Return codes:
- **0:** go and do the work. The lock is held iff `uvm_lock` is non-empty, and it is empty after a
  `proceed` timeout.
- **1:** the predicate came true while waiting. Nothing is held.

Contract for predicate authors, recorded in the function's header comment: errexit is suspended
inside a predicate, so its status must be the deciding test's; it must not touch `uvm_lock`. Shape,
following research 01 Q2:

```text
on_timeout=$1; shift; (( $# >= 1 )) || die "…needs a predicate"   # explicit: ${1:?} exits 0 under the EXIT trap on 3.2
form-test + base-10 lock_timeout; notice=min(30, lock_timeout)
owner="host=$(uname -n) pid=$$"
(umask 077; mkdir -p "${uvm_root}") || die …
while ! mkdir "${lock}" 2>/dev/null; do
  lock absent → absent+=1; <3 → continue; else die (permissions/quota)   # unchanged rationale
  "$@" → return 1
  at waited == notice or waited >= timeout: holder=""; read holder < owner
  waited == notice → note (once): lock path, "held by: <owner line | <none recorded>>",
                     "may belong to a process still running", and the path-form removal command
  waited >= timeout → proceed: return 0 | fail: die naming the lock and the owner line
  waited+=1; sleep 1
done
uvm_lock="${lock}"                                   # before the write: R11's cleanup is the EXIT trap
printf '%s\n' "${owner}" > "${lock}/owner" || die "cannot record ownership of the provisioning lock at ${lock}/owner"
```

Points in that shape:
- **The redirect keeps the shell's errno line (R11).** A failed write leaves an entry, the EXIT trap
  removes it, then removes the directory.
- **Where the notice fires.** It fires inside the loop, so a lock acquired before the threshold
  never speaks. At `UVM_LOCK_TIMEOUT` of 30 or less, the notice and the timeout fall on the same
  iteration, so every wait that reaches its timeout has spoken exactly once.
- **The recovery command is the path form, not `uvm clean lock`.** Under another architecture or
  root, `uvm clean lock --yes` reported success and cleared nothing (research 05).
- **No liveness words.** The message never says or implies whether the holder is alive. It says the
  holder may be.
- **Every test sits in `if` or `||`.** Bash 5 exits on a bare false `(( ))` where 3.2 does not, so
  the floor would hide the hazard (research 01 Q6).

**`uvm_install WANT FORCE`.** Every success path converges on one selection step *before* the
release:

```text
satisfied = (false) if FORCE else (uvm_have WANT)
if ! satisfied:
    if uvm_acquire_lock proceed <satisfied> && ! <satisfied>:      # 0 → work; then re-check under the lock
        fetch | install into versions/.incoming.XXXXXXXX            # failure paths unchanged
        ver = read back from the binary
        publish (below)
# one selection step, reached by the fast path, the early-out, the re-check and a fresh install
if WANT: uvm_have WANT || die "uv WANT is not installed after provisioning${ver:+ (the installer delivered ver)}"
         uvm_point_current WANT
elif ver: uvm_point_current ver
uvm_unlock
```

A pinned call whose installer delivered another version now dies naming the pin. On `main` it
publishes and execs the other version at rc 0: 16 of 16 ranks, warm and cold (research 03 F1). The
die names the pin on the last stderr line, which is the line the R12 failure gate reads.

**Publish** (research 02). The call stays `mv "${tmp}" "${dest}"` byte for byte (§ Verification
limits):

```bash
  if [[ -d "${dest}" ]]; then
    rm -rf "${tmp}" 2>/dev/null || true                     # already had this version
  elif ! err="$(mv "${tmp}" "${dest}" 2>&1)"; then
    rm -rf "${tmp}" 2>/dev/null || true
    if [[ ! -x "${dest}/uv" ]]; then                        # no rival published it either
      uvm_unlock
      die "cannot publish uv ${ver} into ${dest}: ${err}"
    fi
  elif [[ -e "${dest}/${tmp##*/}" ]]; then
    rm -rf "${dest:?}/${tmp##*/}" 2>/dev/null || true       # a rival won; mv nested ours inside it
  fi
```

The two races it closes:
- **Window (a).** The destination appears before `mv`'s stat, so `mv` nests and returns 0.
- **Window (b).** The destination appears between the stat and rename(2), so `mv` fails ENOTEMPTY.
  On `main` this exits rc 1 with empty stdout.

Both are handled. A loser killed between nesting and cleanup leaves a complete hidden copy inside
`versions/<ver>`. `uvm versions`, `status` and `uv --version` all read past it (research 02 Q2), and
`uvm doctor` names it for a human to remove (P4). No primitive at the floor avoids that residue (§3 deviation table).

**`uvm_point_current`** gains one step. It tries `mv -T`, then `mv -h`, then the existing `rm`+`mv`
tail. The new line:

```bash
if ! mv -T "${tmp}" "${uvm_current}" 2>/dev/null && ! mv -h "${tmp}" "${uvm_current}" 2>/dev/null; then
```

GNU succeeds at `-T`, so Linux pays nothing new. BSD/macOS rejects `-T` (rc 64) and renames onto the
link with `-h`, without following it. The tail survives for an `mv` with neither option.

**`uvm_ensure_uv`** becomes `uvm_install "${pin}" ""` followed by the existing `[[ -x "${real_uv}" ]]`
check. It adds no fork on any path (research 03 F3).

**`uvm_doctor`** gains one WARN finding, never a FAIL. It is placed before the final `cat`, as
research 05 drafted it:
```text
WARN  provisioning lock standing: <lock> (owner: <line | <none recorded>>). Its holder may still be running; once nothing is provisioning this tree, remove it with uvm clean lock --yes.
```

**`uvm_doctor`** also gains one WARN per stranded staging copy, `versions/.incoming.*` or a hidden
copy nested inside `versions/<ver>/`. The line names the path, says it may belong to an install still
running, and gives `rm -rf '<path>'`. It is report only: no liveness inference, no automatic removal,
no new subcommand. That is how a crashed publisher's leftovers reach a human (deviation 2, R10's
worst case).

**`uvm_clean`** gains `lock) target="${uvm_root}/.install.lock" ;;`, and the usage string becomes
`cache, lock, arch, all`. For `lock`, the dry run prints the owner line and "Its holder may still be
running. Removing a live holder's lock lets a second call provision beside it." in place of `du -sh`.
`--yes` takes the existing `rm -rf` path, which also removes any entry a failed owner write left.
This is the Clarification's live-lock wording.

**`uvm_help`.** The two `UVM_LOCK_STALE` lines go. `UVM_LOCK_TIMEOUT` reads "Seconds to wait for the
provisioning lock before installing without it (default: 180)". `clean` lists `lock`.

### State tree afterwards

The tree is unchanged in shape: `<arch>/{current -> versions/<ver>, versions/<ver>/{uv,uvx},
.install.lock/owner}`. The owner line is `host=<uname -n> pid=<pid>`, and nothing reads it but a
human, `uvm doctor` and `uvm clean`'s dry run. After a concurrent publish, `versions/<ver>` holds
exactly `uv` and `uvx`. The one exception is a loser killed mid-cleanup, which leaves a hidden
`.incoming.*` copy.

### User-facing surface (same-commit rule)

Each phase updates what its code invalidates:
- **P1:** `uvm_help`, README (lock passages, knob table, NFS note, troubleshooting), the config
  example's lock block, `AGENTS.md` § Invariants lock paragraphs, and `invariants.md` §5.
- **P2:** `invariants.md` §4/§6/§10 and `AGENTS.md` (publish, swap, and the `tests/lock-race.sh`
  paragraph at `:269-279`).
- **P3:** `invariants.md` §4 (selection).
- **P4:** README's command table, doctor list (the lock and stranded staging copies) and Design
  notes.

The modulefile carries no lock text and is untouched (research 05). The wording rules: state the
contract without the words *break*, *stale*, *liveness*, *heartbeat*, *refresher*, *retake*,
*robbed*, *forfeit*, and do not name `UVM_LOCK_STALE` in `AGENTS.md`, `invariants.md` or the config
example. Use instead: "removes only a lock it created", "no call removes or takes another call's
lock, whatever its age or its owner line records", "never asks whether a holder is alive". README §
Design notes records the rejected designs in plain words ("a holder refreshing its lock", "an age
threshold", "a probe of a recorded pid"), which keeps it at zero hits on the GOAL's pattern.

### `tests/lock-race.sh` and `tests/lock-race-burst.sh` (research 04)

**P2 changes:**
- **Plants.** `control` and `held`. A `held` plant is `mkdir` plus `host=<uname -n> pid=<burst
  shell> nonce=lockrace`, saved as `plant.<tag>`. `owner` and `none` exit 2.
- **Knobs.** `LOCKRACE_STALE` and the `UVM_LOCK_STALE` export are gone. `--timeout S` (default 1) is
  the burst's `UVM_LOCK_TIMEOUT`.
- **Barrier.** Under `held`, the spliced fixture hook gains a release barrier: each installer
  touches `arr.<tag>.<id>`, then polls every 10 ms until all ranks have arrived or `TICKS` polls
  have passed. Nothing in `bin/` is instrumented.
- **Tree record.** The burst writes `tree.<tag>`, captured before `temp_root.sh` tears the sandbox
  down: `nested_staging`, `nested_current`, `stray_staging`, `dist_ok`, `current_ok`.
- **Progress (exit 4), asserted first:**
  - installer entries ≥ bursts;
  - no lock left after a `control` burst;
  - after a `held` burst, the plant is the only lock, holding only `owner`, byte-identical
    (`plant_intact=B/B`);
  - under `held`, `concurrent_bursts ≥ 1`, without which the tree assertion is vacuous.
- **Correctness (exit 1):**
  - the summed tree keys (`nested_*`, `stray_staging`, `bad_trees`);
  - `wrong_stdout` against `uv <want> (fixture)`;
  - `nonzero_ranks`, moved here from progress, so the red state reads 1 and not 4;
  - under `control`, also `installer_entries == bursts` and `concurrent_installers == 0` (R14).
- **Reported only.** `concurrent_installers` stays as a number and is never asserted under `held`.
- **Header.** The exit-code text and the sizing rationale are rewritten.

**P5 adds the Slurm mode:**
- `--launch local|srun` (default `local`, never auto-detected).
- `--pin VER`: warms 9.9.9 unhooked, then copies the hooked fixture to `VER/`.
- `--summary FILE`, written as key=value.
- `LOCKRACE_SHARED`, required under `srun`. The driver sets `TMPDIR` to it, so the sandbox and the
  collection directory both live on the filesystem under test.

Under `srun`, ranks re-exec the burst with `LOCKRACE_ROLE=rank`, launched as `srun
--ntasks=N --kill-on-bad-exit=0 --distribution=cyclic --cpu-bind=none --export=ALL`.

The summary records only counts:
- `scenario`, `ranks`, `bursts`, `nodes` (distinct-node count), `wall`;
- `rc_hist`, `stdout_hist`;
- installer and concurrency counts, the tree keys, `plant_intact`, `locks_left_standing`,
  `progress`.

It carries no hostnames, usernames or absolute paths. That is required, because the repository is
public.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | No break path. `uvm_unlock` acts only on `uvm_lock`, which only this rank's own `mkdir` sets. Liveness, age and identity code deleted. |
| R2 | One `note` at `waited == min(30, lock_timeout)`, carrying the owner line and the path-form removal command. |
| R3 | `uvm_acquire_lock proceed …` returns 0 holding nothing at the timeout; `uvm_install` installs, publishes and selects. |
| R4 | Guarded publish (detect nest, detect rival, discard ours), `mv -h` in `uvm_point_current`, selection under concurrency. Plus (b) the re-pointed `tests/lock-race.sh` `held` mode and (c) its `--launch srun` mode on Lustre and GPFS. |
| R5 | `ON_TIMEOUT=fail` dies naming the lock and the owner line, and returns nothing to run the work. Exercised by a harness that sources the lock section, with no repair code. |
| R6 | `PREDICATE [ARG...]` named by the caller. Provisioning passes `uvm_have "${want}"` (or `false` when forced). |
| R7 | Deletions listed above. `UVM_LOCK_STALE` is never read. |
| R8 | Doctor WARN with path and owner line. `uvm clean lock` with the owner line and live-holder warning in the dry run. Doctor WARNs on stranded staging copies, which also serves R4. |
| R9 | Rewrites of `invariants.md` §5 (and §4/§6/§10), `AGENTS.md` § Invariants and the lock-race paragraph, README, config example and `uvm_help`, worded so both the GOAL's pattern and the supplement match nothing. |
| R10 | The publish's `mv` failure branch, with no rival: remove staging, release, die naming the publish plus `mv`'s errno line. |
| R11 | `uvm_lock` is set before the owner write. The redirect keeps the errno line. The EXIT trap's release-by-path removes the entry and the directory. |
| R12 | Single selection step after every success path. A pinned call whose installer delivered another version dies naming the pin. `mv -h` so concurrent selection is atomic on BSD. |
| R13 | That step is the only place `uvm_install` selects, so agreement is structural. `uvm_ensure_uv` collapses into it. Inspection-only. |
| R14 | Unpinned path unchanged. `mkdir` discipline unchanged. `--plant control` asserts one installer per burst and no concurrency. |
| R15 | Counters removed. Tree and stdout assertions. Progress accounts for a plant no rank clears. Red against the P1 build (unguarded publish), green on HEAD. |

## 3. Invariant gate (AGENTS.md constitution check)

**Gate #1 (pre-research).** The change touches the following sections, and the GOAL's intent is sane
against each:
- **§2:** the `exec` guards stay.
- **§4:** the pin stays authoritative and is strengthened, and `uvm_have` stays the single
  spelling.
- **§5:** rewritten by decision.
- **§6:** the publish.
- **§7:** the notice goes to stderr.
- **§10:** bash 3.2, and the hot path.
- **§12:** same-commit, and no spec ids in the script.

It does not touch §1, §3, §8, §9 or §11. No conflict with §1–§11 is unavoidable. §5 is overturned by
the maintainer's decision, and the phases that land the code rewrite it, as R9 requires.

**Gate #2 (post-design), section by section:**

- **§2 Process semantics.** `exec` sites are unchanged. Each is preceded by `uvm_unlock`, which is a
  builtin no-op on every path that holds nothing, including a provisioning rank that proceeded
  unlocked.
- **§4 Version selection.**
  - A pin is now authoritative on every success path, not just two of three. The early-out selects,
    and a mismatched delivery dies rather than silently selecting the other version.
  - `uvm_have` remains the one spelling of the provisioning question. The lock no longer hard-codes
    it; provisioning passes it. P3 rewrites the bullet to say so.
  - `uvm_point_current` stays atomic and relative, and is now atomic on BSD too. P2 rewrites the
    "documented non-atomic fallback" sentence.
- **§5 Provisioning lock.** Rewritten to the new contract in P1:
  - `mkdir`, never `flock`.
  - Release on EXIT/INT/TERM, by path.
  - Only the creator removes the lock, except a human through `uvm clean`.
  - The owner write is fatal and leaves nothing behind.
  - The persistence bound survives.
  - The caller names the predicate.
  - One notice; proceed or fail at the timeout.
  - `UVM_LOCK_TIMEOUT` is form-tested inside the function.
  - Doctor reports and never judges.
- **§6 Installer environment.** The scrub is untouched. Staging stays a `mktemp -d` in `versions/`,
  and publish stays a same-directory rename. The "guarded by nothing" bullet becomes the guarded
  publish in P2.
- **§7 Output discipline.** The notice, the WARN and the publish die all go to stderr. `uvm doctor`
  keeps its single-`cat` accumulator.
- **§10 Portability floor.**
  - Every idiom recommended here was executed under `/bin/bash` 3.2.57 (research 01 Q1, Q6; 02 Q3;
    03 F3).
  - Unavailable at the floor and not used: `source <(…)`, namerefs, `$BASHPID`, `${1:?}` as a guard.
  - The hot path gains no fork (03 F3): unpinned warm 0→0, pinned selected 1→1, pinned swap on
    macOS 6→5.
- **§12 Conventions.** No R-ids in `bin/` or README. The doc surfaces move in the same phase as the
  code. `bin/{uv,uvx,uvm}` stay symlinks (lint).

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| `uvm_point_current` gains a `mv -h` step. This is a high-blast-radius edit the GOAL does not name. | Once waiters select (R12) and timed-out ranks publish (R3/R4), many ranks swap `current` at once. BSD's `rm`+`mv` tail then loses `current` and nests `.current.<pid>` inside `versions/<ver>`. Measured: 58,062 reader misses and 64 strays in 32×100 swaps; 5–6 of 6 `held` bursts nested. That makes R4, R12 and R15 red on macOS with correct publish code. | Leaving it was measured red. `ln -sfn` was measured worse (`File exists`, `current` still briefly missing). A lock around the swap re-adds a hold the decision avoids. |
| A loser killed between `mv` nesting its copy and removing it leaves a hidden `.incoming.*` inside `versions/<ver>`. R4's "nothing nested" holds for every process that runs to completion, not for one killed in that window. | No no-clobber directory rename exists at the floor. | `mkdir` claim + fill puts a partial tree at a version path (§6). `ln -s` publish nests too and changes the layout. rename(2) via perl/python adds a dependency and moves the call shape out of the shims' reach. The residue is read correctly by every consumer (research 02 Q2). `uvm doctor` reports it, and any `versions/.incoming.*`, as a WARN naming the path to remove (P4). That meets R4's "nothing nested" through the human-clears-unexpected-faults path, without automatic removal or liveness inference. |
| The Slurm drive (R4 (c)) is a `--launch srun` mode of `tests/lock-race.sh`. The foreman asked for "a committed, generic, scheduler-light script". | The GOAL's non-goal says "No committed suite beyond `tests/lock-race.sh`", and `lint.sh` lists test files by name, so a new file would go unlinted without an edit to `.agents/factory/`. | A separate `tests/lock-race-slurm.sh` breaks the non-goal, needs a factory edit for lint, and carries a second copy of the tree predicate that would drift. The mode still meets the foreman's brief: scratch root from the environment, private `UVM_ROOT`, `srun`, a machine-readable summary file. |
| A pinned call whose installer reports another version now **fails** where `main` succeeded. | R12 says a call SHALL NOT exec a different version at rc 0. On `main` the wrong-delivery case did exactly that on 16 of 16 ranks. | Selecting the delivered version is the defect. Re-trying the download repeats a deterministic mismatch. |
| P2's R15 gate reads git history: it rebuilds the first `Build lock-simplification P1:` commit's wrapper. | R15 asks for the red state "against a build that proceeds on timeout but still publishes with `main`'s unguarded `mv`", recorded. P1 is exactly that build. | A sed-patched "unguarded" copy of HEAD would test a build that never existed. The gate is valid on the branch until `uvm-publish` squashes it; the red run is also pasted into P2's commit body so the record survives the squash. |

No knob is added. The notice threshold is a literal 30, clamped to the timeout, and the repair-mode
timeout reuses `UVM_LOCK_TIMEOUT` (see §5).

## 4. Rabbit holes (resolved)

- **Lock API at bash 3.2, predicate indirection, `set -e` inside predicates, guard against a missing
  predicate, and the R5/R6 caller with no repair code** → `"$@"` plus an explicit `(( $# ))` guard.
  The harness extracts the lock section by its banners into a temp file and sources it with `.`,
  because `source <(…)` is a silent no-op on 3.2. Proven against `main` and against a draft
  ([01](research/01-lock-wait-contract.md)).
- **Notice threshold** → 30 s, clamped to the timeout. A real uv tarball downloads in about 0.4 s;
  10 s would put about 381 lines into a 128-rank job log on slow egress
  ([01](research/01-lock-wait-contract.md)).
- **`mv` onto an existing directory, GNU vs BSD vs busybox, `RENAME_NOREPLACE`, `-n`** → nesting is
  universal; detect it afterwards. Window (b) is also red on `main` ([02](research/02-publish.md)).
- **Concurrent `current` swaps on BSD** → `mv -h` ([02](research/02-publish.md),
  [03](research/03-selection.md), [04](research/04-instrument.md), three independent measurements).
- **R12's failure construction** → wrong delivery, not a missing installer
  ([03](research/03-selection.md)).
- **Making R15's red state reachable** → a release barrier in the spliced fixture hook. The
  unguarded publish then nests in about 70% of 64-rank `held` bursts against about 10% without it
  ([04](research/04-instrument.md)).
- **Doctor severity, clean surface, recovery-command spelling, R9's under-matching pattern, and the
  `grep -c` trap** ([05](research/05-surface.md)).

## 5. Risks & open questions

- **Cluster-only.** Two properties can only be shown across nodes on a real parallel filesystem:
  `mkdir` atomicity, and concurrent publish of one `versions/<ver>`. P5's Slurm drive on Lustre (2
  nodes) and GPFS (1 node) is evidence, not proof. NFS is not exercised at all. GNU `mv -T` is the
  path taken there, so the `mv -h` step goes unexercised on clusters, and the macOS sandbox is its
  only evidence.
- **Not run, read only:**
  - GNU `mv -h`: expected to be an invalid option, rc 1, before any file operation; unreachable
    after `-T` succeeds.
  - busybox `mv` without `-T`: falls to the same tail as today.
  - Bash 5's errexit on a bare false `(( ))`. The design keeps every test inside `if`/`||`, and the
    reviewer checks that by reading, because no bash 5 exists on the measuring Mac. The cluster
    drive runs the wrapper under the cluster's bash 4/5, which is the only execution there.
- **The residual of a human clear is wider than the Clarification states** (research 01 Q5, derived,
  not measured). One `uvm clean lock` against a live lock shifts ownership by one rank for the rest
  of that contention episode, not for one rank. A clears, B acquires; A's release removes B's lock;
  C acquires; B's release removes C's lock; and so on. For provisioning this ends at the first
  publish, because waiters' predicates turn true. For a repair caller every repairer in the chain
  would overlap its predecessor. The decision stands, and R8's wording warns. **Maintainer:** this
  sharpens the case for the open question below.
- **Open for the next cycle (`issues/purge-tree-repair.md`), not decided here: does repair take
  `.install.lock` or a lock of its own?**
  - *Shared:* repair and provisioning serialize. A provisioning waiter past its timeout proceeds
    during a repair, and a provisioning predicate can come true mid-repair.
  - *Own:* `uvm_acquire_lock` gains a path argument, and doctor and clean cover two locks.

  This cycle keeps the path internal and the API ready for either. The repair caller then also needs
  its own timeout value. It reuses `UVM_LOCK_TIMEOUT` here, and a repair hold of 1–30 s may want a
  different wait. That is the next cycle's knob decision.
- **Messages say "provisioning lock".** For a future repair caller they will read oddly. Rewording is
  deferred with the question above.
- **Noise.** With a held lock, every waiter prints one 4–5-line notice at 30 s: a 128-rank job logs
  about 128 notices. That is accepted as the R2 contract.
- **P5 has an external wait.** It is split into two runs (TECH § P5). Run B depends on the foreman's
  submission. If a cluster run fails for an infrastructure reason (no `curl` on compute nodes, the
  filesystem not shared), Run B records that and the foreman decides. The phase must not be closed on
  one filesystem silently.
- **Schedule.** Five phases against a target of about 4 days, with P5's queue wait outside the build's
  control.
- **Leftovers for `/uvm-roadmap` at landing** (not this cycle's code):
  - Retire `issues/lock-break-instance-identity.md`, `issues/lock-owner-write-errno.md`,
    `issues/pin-early-out-selects-nothing.md` and `issues/lock-simplification.md`, and their
    `ROADMAP.md` entries (six hits).
  - `issues/test-harness.md`: R3d (breakable as stale; inverted TIMEOUT/STALE), R3e (the retake,
    now deleted), R3f (instance identity) and R7 (heartbeat `ps` fork, orphaned `sleep`) are stale
    once this lands. R3's "a stale lock" wording also needs restating against the new contract
    (proceed on timeout; doctor/clean).
  - `issues/invariant-audit-gaps.md` already records R3 as absorbed and R4 as moot, and needs
    nothing more (research 05).

## 6. Verification strategy

Every phase gate runs `bash -n bin/uv-manager` and `.agents/factory/bin/lint.sh`. Each one also runs
the drives below under `.agents/factory/bin/temp_root.sh --offline` (fixture `uv 9.9.9 (fixture)`).
Every shim records its hits, and a gate fails if its shim never fired, because a changed call shape
otherwise turns a drive silently green (research 02 Q4).

| R-ID | Drive and post-condition |
|---|---|
| R1 | Plant with a reaped pid on this host, 2020 timestamps; then plant with no `owner`. `UVM_LOCK_TIMEOUT=3 uv --version`. Plant standing and byte-identical (or still empty); rc 0; fixture version; no stderr line matching `break`. |
| R2 | Live holder, released at 33 s, `UVM_LOCK_TIMEOUT=60`. rc 0, fixture version, exactly one stderr line carrying the planted owner line. |
| R3 | Live holder never released, `UVM_LOCK_TIMEOUT=3`. rc 0, fixture version, `current -> versions/9.9.9`, plant intact. |
| R4 (a) | `mv` shim that publishes a rival copy first. `versions/9.9.9` = `uv uvx`, 0 `.incoming.*`, `current` correct, no lock, rc 0, fixture version. |
| R4 (b), R15 | `tests/lock-race.sh --plant held --ranks 64 --bursts 10` exits 1 with `nested_staging≥1` against P1's wrapper and 0 on HEAD. |
| R4 (c) | P5 evidence files for Lustre and GPFS: all ranks rc 0 with the wanted version, every tree key 0, `plant_intact=B/B`, `nodes=2` on Lustre, `concurrent_bursts≥1`. |
| R5, R6 | Bash harness sourcing the lock section, `uvm_acquire_lock fail <pred>` with the provisioning stub true. Never-released plant: non-zero, owner line on stderr, no critical-section marker, plant intact. Predicate flipped at 2 s: acquire rc 1, no marker. |
| R7 | `git grep` on `bin/uv-manager` matches nothing. `UVM_LOCK_STALE=1 uv --version` exits 0 with the fixture version. |
| R8 | Research 05's drive: doctor rc 0 naming path and owner line; dry run keeps the lock and shows the owner; `clean lock --yes` removes it; tree and `current` intact; doctor silent after. Then plant `versions/.incoming.strandA` and `versions/9.9.9/.incoming.strandB`: doctor rc 0 with a `WARN` naming each path, both left in place. |
| R9 | GOAL pattern zero on the four files. Supplement zero on `AGENTS.md`, `invariants.md` and the config example. `uvm help` has no `UVM_LOCK_STALE` (`if … grep -n`, not `grep -c`). README supplement hits printed for the reviewer. |
| R10 | `mv` shim failing `Permission denied`. rc≠0, `uv-manager: … publish … 9.9.9 … Permission denied`, empty stdout, no `.incoming.*`, no `versions/9.9.9`, no lock. |
| R11 | `mkdir` shim leaving a dangling `owner` symlink. rc≠0, errno line and `cannot record ownership`, no `.install.lock`. |
| R12 | `ln` shim (`sleep 2`), 16 pinned ranks, cold and warm: every rank rc 0 printing `uv 6.6.6 (fixture)`. Same with the 6.6.6 installer delivering 9.9.9: every rank non-zero, empty stdout, last stderr line naming 6.6.6. Plus `uvm install 6.6.6` and `uv self update 6.6.6`, 8 ranks warm, selecting 6.6.6. |
| R13 | Inspection only: the reviewer reads `uvm_install` and its three callers. |
| R14 | `tests/lock-race.sh --plant control --ranks 32 --bursts 2` exits 0 with one installer per burst. `git grep -n flock -- bin/uv-manager` matches one line. |

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
