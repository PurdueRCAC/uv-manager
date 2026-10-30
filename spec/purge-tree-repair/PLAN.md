# PLAN — `uv run` rehydrates a purged tree, gated by `UVM_REPAIR`

> **Status:** Approved at the plan gate, with the foreman's rulings in §5 · **Last updated:** 2026-10-29
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/). Every
> design element traces to a GOAL R-ID.

## 1. Summary

With `UVM_REPAIR` on, every `uv` and `uvx` call does one thing before it runs the user's command: it
looks for an outcome recorded for its scope, which is the Slurm job, or else the knob's value. On a
repaired outcome it proceeds after one `stat`. On a failed one it exits with the recorded reason.
With no outcome, it takes a second `mkdir` lock, `.repair.lock`, beside `.install.lock`. The one call
that wins runs `uvm doctor`'s detection, repairs only the damaged arms with uv's whole-tree commands,
records the outcome, and releases. The others wait on the lock, see the outcome, and act on it.
`uvm_acquire_lock` gains the lock's name as its first argument, which is the cycle's only edit to
the lock. `uvm doctor` and `uvm clean` gain the repair lock and the outcomes. A sibling drive,
`tests/repair-race.sh`, carries the claim to a cluster.

The whole design was prototyped in a throwaway copy before this plan was written. It repaired real
trees (T) and (P) with uv 0.13.6 at 64 local ranks. Every phase gate below ran green against the
prototype and red against this branch's HEAD.

## 2. Design

### What is removed

Little, and that is stated rather than hidden. The change is a feature the tree does not have.

- The literal `${uvm_root}/.install.lock` inside `uvm_acquire_lock`.
- The five hard-coded "provisioning lock" and "provisioning" message words there.
- `uvm_doctor`'s single-lock advisory block, replaced by one loop over both locks.
- `uvm_clean`'s single-target `lock` case.
- The help and README sentence saying `UVM_LOCK_TIMEOUT` always ends in "installing without it".
- Two statements become false and are rewritten rather than kept: the dispatch-tail comment and
  invariants §5's "Nothing acquires the lock this late", and "`uvm clean lock` removes the lock
  directory and nothing else".

### `bin/uv-manager`, function by function

**`uvm_acquire_lock LOCK ON_TIMEOUT PREDICATE [ARG...]`** (high-blast-radius;
[research 01](research/01-lock-api.md)).

- LOCK is `install` or `repair`. The path is `${uvm_root}/.${LOCK}.lock`.
- A `case` sets the message words: `provisioning lock`/`provisioning`, or
  `repair lock`/`repairing`. An unknown name dies.
- The arity check becomes `(( $# >= 3 ))`. Nothing else in the body changes: the loop, the absence
  count, the predicate, the notice at `min(30, timeout)`, the owner write and the timeout guard.
- `uvm_install` passes `install`.
- `uvm_unlock` and the traps are untouched. A process never holds both locks, because
  `uvm_ensure_uv` has released before the repair starts, so the one `uvm_lock` global still suffices.
- The banner becomes `# ---- locks`.

**`uvm_detect`** (new; it is `uvm_doctor`'s walk, extracted).

- It sets `uvm_findings`, `uvm_problems` and `uvm_advisories`, which are doctor's existing three,
  plus `uvm_damaged_tools`, `uvm_damaged_pythons`, `uvm_orphans` (one tool name per line) and
  `uvm_receiptless` (names, space-separated).
- How each finding maps to an arm:

  | Finding | Arm |
  |---|---|
  | Dangling shim in `bin/shims` | tool |
  | Broken tool interpreter link | tool |
  | `dist-info` with no `RECORD` | tool |
  | Missing files | tool |
  | Dangling shim in `bin/python-shims` | interpreter |
  | Interpreter failing `import json, os, ssl` | interpreter |
  | Missing `pyvenv.cfg` | orphan |

- `uvm_doctor` becomes `uvm_detect` followed by its advisories and report. Its text on a tree with
  no new state is unchanged.

**`uvm_repair`** (new, under a `# ---- purge repair` banner before the dispatch).

```
key    = job-[<SLURM_CLUSTER_NAME>-]<SLURM_ARRAY_JOB_ID, else SLURM_JOB_ID>   inside Slurm
         value-<UVM_REPAIR>                          otherwise
key    = key with every byte outside [A..Za..z0..9._-] (listed, not ranged) -> _
die if ${#key} > 200
ok     = ${uvm_root}/.repair/<key>.ok        empty
failed = ${uvm_root}/.repair/<key>.failed    one line: the reason

[[ -e ok ]] && return 0                                  # one stat on the repaired path
if ! recorded && uvm_acquire_lock repair fail recorded && ! recorded; then
  mkdir -p .repair (umask 077)
  uvm_repair_run                                         # sets the reason on failure
  : > ok   |   printf reason > failed.$$ && mv -f failed.$$ failed
fi
uvm_unlock
[[ -e ok ]] && return 0
die "the repair for <Slurm job N | UVM_REPAIR=v> failed: <reason>"
```

`recorded` is `uvm_repair_recorded`, `[[ -e ok || -e failed ]]`. It is the waiter's predicate, and
the same test R2 makes on arrival. The re-test after winning the lock is `uvm_install`'s shape, and
it covers a holder that recorded and released between this call's last poll and its `mkdir`.

**`uvm_repair_run`** (new).

1. It calls `uvm_detect` and prints each finding through `note`.
2. If there is an orphan, it records the reason "tool N has no pyvenv.cfg, so no automated repair is
   safe; remove …/tools/N and install the tool again" and runs nothing.
3. If an interpreter is damaged and a `python/*/` install exists, it prints "repairing the managed
   interpreters for <arch>" and runs `"${real_uv}" python install --reinstall >&2`.
4. If a tool is damaged, it prints "repairing the tool environments for <arch>" and runs
   `"${real_uv}" tool upgrade --all --reinstall --no-cache >&2`.

On failure the reason is "the managed interpreter repair failed (uv exited N)" or "the tool
environment repair failed". When receipt-less tools exist, the second gets "; uv reports a tool with
no receipt as not installed: <names>". **No wrapper string names `tool upgrade` or `python install`.**
The fixture's stub echoes its command line, and the GOAL counts those lines as repairs, so a note or
a reason naming the command would double-count. The prototype hit this by design review, before any
gate ran.

**The dispatch tail** (high-blast-radius). After `uvm_ensure_uv; uvm_export_env`, it adds:

```bash
if [[ -n "${UVM_REPAIR:-}" && "${UVM_REPAIR}" != 0 ]]; then uvm_repair; fi
```

- Off costs that one builtin test. There is no fork and no filesystem access.
- The check sits before `self update`, before the `tool`/`python` path and before the execs, so the
  knob fires under every subcommand.
- `uvm_repair` releases before it returns. The pre-exec `uvm_unlock` stays a guard, and its comment
  is rewritten, since something now does take a lock this late.
- `uvm` (manager mode) never repairs.

**`uvm_doctor`.**

- One loop WARNs each standing lock: `WARN  provisioning|repair lock standing: <path> (owner: …).
  Its holder may still be running; once nothing is provisioning or repairing this tree, remove it
  with uvm clean lock --yes.`
- Failed outcomes under a value each get `WARN  repair failed for UVM_REPAIR=<value>: <reason>.
  Every call with that value fails the same way until the value changes; remove the record with uvm
  clean outcomes --yes.`
- Failed outcomes under Slurm jobs are counted on one WARN line and not read. Each ended with its
  job, and reading one would refresh its atime and keep it alive through the purge.
- Repaired outcomes are not reported.
- Everything here is WARN, never FAIL, under the banner's rule. The remediation block gains:
  "Inside a job, `UVM_REPAIR=1` runs these for you, once per Slurm job."

**`uvm_clean`.**

- WHAT gains `outcomes`, which removes `${uvm_root}/.repair`.
- `lock` now removes `.install.lock` and `.repair.lock`. Its dry run prints each standing lock's
  owner line and the caution, reworded "once nothing is provisioning or repairing this tree".
- The `outcomes` dry run prints "N repaired and F failed repair outcome(s)". It also says that
  removing one costs a fresh check, never a false clean, and that removing a failed one lets its
  scope retry.

**`uvm_help`.**

- A `UVM_REPAIR` row: repair what a purge removed before running, once per Slurm job, else once per
  value; off when unset, empty or `0`; any other value, `00` and `false` included, is on.
- `UVM_LOCK_TIMEOUT`: "Seconds to wait for a lock. Past it, provisioning installs without the lock
  and a repair fails."
- The `clean` line names `outcomes`.

### State tree afterwards

```
$UVM_ROOT/<arch>/
  .install.lock/owner     while provisioning (unchanged)
  .repair.lock/owner      while one call repairs
  .repair/                created by the first holder, umask 077
    job-[<cluster>-]<id>.ok | .failed
    value-<value>.ok | .failed
  versions/ current cache tools python bin/   (unchanged)
```

### The two consequences of the rulings

1. **A failed outcome under a constant value stands until the value changes.** It has three human
   paths:
   - the failing call's own message names the scope and the reason;
   - `uvm doctor` WARNs it with its reason and the remedy;
   - `uvm clean outcomes --yes` removes it.

   `uvm clean outcomes` takes the noun form of `uvm clean lock`, `uvm clean cache`, and the rest.
   It is all outcomes at once, never one scope: removing any outcome costs a re-check and never a
   false clean, so a narrower form buys nothing.
2. **Outcomes accumulate, one empty file per job or value.** They are bounded by the purge, with a
   manual bound, and they are not pruned ([research 04](research/04-outcome-scope-surface.md) Q4;
   digest D9).
   - The knob does work only on purged storage. There an outcome is only ever `stat`ed, so it ages
     from its creation and goes with the window: about 43k empty files at a 10k-task array a week
     over 30 days.
   - On storage that is not purged, the documentation says to leave the knob unset. The
     `uvm clean outcomes` dry run counts what is there.
   - A holder-side `find -mtime +30` was rejected for this cycle. It stats every outcome once per
     scope, roughly 4×10⁸ metadata operations a week at that array rate, on the metadata server, at
     the scale it exists for.
   - Accepted by the foreman at the plan gate (§5, ruling 4).

**One repair per allocation, and per array.** Every step and task of one Slurm allocation shares
`SLURM_JOB_ID`, so the first `uv` call in a job that sets the knob checks the tree, and every later
call in every later step costs one `stat`.

- **Arrays.** Every task of an array shares `SLURM_ARRAY_JOB_ID`, and the key uses it when it is set
  (ruling 2). One array is therefore one scope, and its tasks do not queue to walk the tree one after
  another.
- **Heterogeneous jobs.** Every component sees the leader's id, and the outcomes are
  per-architecture root. A job spanning two architectures therefore checks each tree once.
- **The limit that remains.** Jobs submitted separately are separate scopes. N of them starting
  together on one tree each walk it in turn under the repair lock. Any job past
  `UVM_LOCK_TIMEOUT / w` in that queue fails at the timeout, w being the walk time.
  [`issues/repair-scope-queueing.md`](../../issues/repair-scope-queueing.md) carries it.

The README and the conf example say all three.

### User-facing surface (the same-commit rule)

Brief 04 § Q5 has the line-by-line census. Each item lands in the phase that changes the behavior it
documents:

- **P1**: `invariants.md` §5's quoted signature.
- **P2**: all six files.
  - `uvm_help`.
  - `README.md`:
    - the `UVM_REPAIR` and `UVM_LOCK_TIMEOUT` reference rows;
    - the purge section's mitigations: the knob, its scope and the per-run advice outside a job;
    - the false-clean reason;
    - one repair per allocation, so a Slurm job needs nothing per run;
    - what repair detects and concedes: cache damage, a distribution deleted whole, and interpreter
      damage outside `import json, os, ssl`;
    - the network: `pypi.org`, `files.pythonhosted.org`, `releases.astral.sh`;
    - reach: `uv` and `uvx` under any subcommand, not a tool run by its own name;
    - that `uvx <script>.py` is not a uv form;
    - the troubleshooting `ImportError` line;
    - design notes: why a knob and not a subcommand, why the job id, and why a lock of its own;
    - the "Keep `uv run` off the hot path" paragraph, reconciled.
  - `etc/uv-manager.conf.example`: a commented `UVM_REPAIR` block, and the `UVM_LOCK_TIMEOUT` block's
    repair sentence.
  - `share/modulefiles/uv/main.lua`: the help text at `:89-92`.
  - `AGENTS.md`:
    - § Invariants: two locks, never both held, and a repair waiter fails at the timeout;
    - the execution-model diagram;
    - the banner list;
    - the high-risk table: `uvm_repair`.
  - `invariants.md`: §5 for two locks, the high-blast list adding `uvm_repair`, and the "this late"
    bullet.
  - `uvm_doctor`'s remediation block.
- **P3**: README text for the interpreter arm's condition, the orphan refusal and the receipt-less
  failure.
- **P4**:
  - help, README and conf: `uvm clean outcomes` and `uvm clean lock` covering both locks;
  - the README `clean` table row "`lock` removes only the provisioning lock", which becomes false;
  - troubleshooting entries for "waiting for the repair lock" and for a failed outcome;
  - `invariants.md` §5's `uvm clean lock` bullet.
- **P5**: the `tests/` paragraph in `AGENTS.md`.

### Requirement → design map

| R-ID | Design element(s) | Phase |
|------|-------------------|-------|
| R1 | The dispatch test `[[ -n … && … != 0 ]]`; nothing else runs when it is false | P2 |
| R2 | `[[ -e ok ]]`, then the predicate and the `.failed` read and `die`; the arrival test precedes `uvm_detect` | P2 |
| R3 | `uvm_repair_run`: `uvm_detect`, the arms, the record; never `uvm_install`, so `current` and the pin are untouched. Real (T)/(P) | P2 (fixture halves), P3 (real) |
| R4 | The tool arm is `uv tool upgrade --all --reinstall --no-cache`, the only tool repair | P3 |
| R5 | The orphan check before any arm; a failed outcome naming it | P3 |
| R6 | The interpreter arm only on interpreter damage with an install present | P3 |
| R7 | `uvm_acquire_lock repair fail uvm_repair_recorded`; record before `uvm_unlock`; the waiter path reads the outcome | P2 |
| R8 | Both arms `>&2`; the user's command is exec'd or run exactly as before, so its rc is its own | P2 |
| R9 | Failed outcome + `die` naming the reason; holder death leaves no outcome, so waiters time out naming the repair lock (`fail` mode); doctor + clean | P2 (a, b, d), P4 (c) |
| R10 | The off test; the key derivation; help and docs | P2 |
| R12 | `tests/repair-race.sh` P, T, kill; the cluster run | P5 |
| R13 | A separate `.repair.lock`; the message words; doctor and clean over both | P1, P2 (a, b, d), P4 (c) |
| R14 | Census of the six files, the help census, doctor's remediation block naming the knob | P2, P4 |

## 3. Invariant gate (AGENTS.md constitution check)

Walked before research, and again against this design and every TECH checklist item.

- **§1 Architecture.** Unchanged and served. The repair fires after `uvm_init` on the executing
  node. Outcomes, the repair lock and the arms live under `${uvm_root}`, which is per-architecture.
  Nothing is exported. A bring-up subcommand is not proposed.
- **§2 Process semantics.**
  - The user's command is still exec'd, or, for `tool` and `python`, run to completion with its rc
    kept.
  - The repair arms are subprocesses that run *before* that point and are not the user's command.
    "Exactly two commands do not `exec`" stays true.
  - A SIGTERM during a repair releases the lock through the trap and exits 143 with no outcome. The
    waiters then fail at the timeout, which is R9's dead-holder contract.
- **§3 State root.** Untouched.
- **§4 Pin.** The repair never calls `uvm_install`, so it cannot move `current` (decision record
  D6). The P2 gate asserts `current` unchanged under a pin with a newer fixture on offer.
- **§5 Lock.**
  - Overturned in its single-lock wording only, by ruling M1. Recorded below, and P2 rewrites §5 and
    `AGENTS.md` § Invariants in the same commit.
  - `mkdir` atomicity, creator-only release, the owner write, the absence count, the notice,
    `fail`-mode timeout and doctor-WARN-not-FAIL all apply to the repair lock unchanged.
  - No call holds both locks.
  - "No lock survives an `exec`": `uvm_repair` releases before it returns, and the pre-exec guard
    remains.
  - The predicate is the caller's own (`uvm_repair_recorded`), cheap, side-effect-free, a single
    `[[ ]]` whose status decides, and it never touches `uvm_lock`.
- **§6 Installer.** Untouched. The repair never provisions.
- **§7 Output.**
  - All repair output goes to stderr: notes, both arms' stdout, and the findings.
  - Doctor's new lines join the existing single-`cat` findings string.
  - `uvm clean`'s dry run stays a heredoc.
- **§8 Environment.** No new export. The arms inherit the `UV_*` paths `uvm_export_env` set, which is
  why the test sits after it. The drive sets `UV_PYTHON_PREFERENCE` itself, as user policy.
- **§9 Trampolines.** Untouched. Reach stops at a tool run by its own name, and the docs say so.
- **§10 Portability and hot path.**
  - Off: one builtin test.
  - Repaired: one `stat`.
  - The key is built by builtins, with a listed character class (`globasciiranges`).
  - Nothing uses GNU-only flags: the drive uses `date +%s`, BSD/GNU `sed -e`, and `grep -o`.
  - Measured warm-call cost: HEAD 12.0 ms, prototype 12.3 ms per call (200 calls, twice per arm). The
    0.3 ms is bash parsing about 150 more lines before the exec, and there is no fork (§5, Other risks).
- **§11 Argument inspection.** Untouched. The knob reads no argument.
- **§12 Conventions.** No spec ids in the script or README. Voice per `AGENTS.md`. The version is
  untouched: a release bump is `/uvm-release`'s.

### Deviation justifications

All rows were accepted by the foreman at the plan gate (2026-10-29).

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| A second lock (`.repair.lock`), overturning §5's single-lock wording in `AGENTS.md` and `invariants.md` | Ruling M1: a repair waiter must fail at its timeout and must not be held up by, or release, a provisioning hold | One shared lock: a repair waiter would fail because of an unrelated slow download, and a provisioning waiter past its timeout would exec mid-repair (GOAL M1) |
| `uvm_acquire_lock` gains a first argument | M1's stated cost | A path argument: it leaves the message words to a lookup outside the function that prints them (research 01) |
| `uvm_detect` split out of `uvm_doctor` | R3: "the detection `uvm doctor` performs", not a copy that can drift | Calling `uvm_doctor > /dev/null` and parsing its text: it forks `cat`, and it couples the repair to doctor's wording |
| The Slurm key adds `SLURM_CLUSTER_NAME` | Two clusters on one filesystem and architecture reuse job ids, so one's `.ok` would read as the other's check: a false clean | The bare `SLURM_JOB_ID`: free to fix, and the cluster name is the job id's own namespace (brief 04 Q2). It reads one variable beyond R10's "at least" |
| Array tasks key on `SLURM_ARRAY_JOB_ID` (foreman ruling 2), where R10 names `SLURM_JOB_ID` | Each array task has its own `SLURM_JOB_ID`, so N tasks starting together would walk the tree N times in turn under one lock, and every task past `UVM_LOCK_TIMEOUT / w` would fail on a healthy tree | Keeping `SLURM_JOB_ID` and documenting the limit: arrays are the commonest many-job pattern, and the failure is a healthy tree failing jobs |
| A 200-byte bound on the key | `NAME_MAX`: a longer value makes every outcome write fail after the expensive repair, and every rank in turn repeats it | Truncating: two long values sharing a prefix would silently share a scope |
| Test-harness knobs in the offline fixture (`UVM_FIXTURE_MARK`, `UVM_FIXTURE_REPAIR_SLEEP`, `UVM_FIXTURE_REPAIR_EXIT`) | R7, R8 and R9 ask the plan to name how the stub slows a repair, fails it, and tells a repair from the user's command | Splicing a wrapper around the stub in every gate: several dozen lines repeated in four gates. A fixture change is harness, never product |
| A committed `tests/repair-race.sh` | R12, the one committed suite the GOAL allows | Extending `tests/lock-race.sh`: its burst, fixture and counters share nothing with a damaged real tree (research 03) |

## 4. Rabbit holes (resolved)

- **Do uv 0.13.6's arms repair (T) and (P), and keep a pin and a `--with`?** Yes. They restore every
  manifest path, keep the receipt byte-identical, reinstall the installed interpreter patch (not
  the newest), and write nothing to stdout. The python arm must run first. ([02](research/02-real-uv-repair.md))
- **Orphans and receipt-less tools.** An orphan makes the tool arm exit 0 while it writes into the
  base interpreter: refuse before running anything (R5). A receipt-less tool makes it exit 1 after a
  full repair: record failed and name it (§5 Q2). (02 Q5, Q7)
- **A real uv in the agent sandbox.** The installer's `mktemp -d` is denied, so the sandbox is seeded
  from a local binary: copy `uv` and `uvx` into `versions/<ver>/` and link `current`. It is a
  harness step in the gates and `--uv-bin` in the drive, and never product code. (02 Q1)
- **bash portability of the scope key.** Range classes differ across 3.2, 4.4 and 5.1 under UTF-8,
  so the class lists its characters (04 Q1). Executed on 3.2.57 here. Brief 04 also has results from 4.4.20 and
  5.1.8; those came from the unapproved login-node test that §5 reports.
- **Killing the holder deterministically, across nodes.** Each rank backgrounds its wrapper directly,
  so `$!` matches the owner line's pid. The rank that reads its own `host= pid=` kills it on sight.
  No cross-node signal and no `pgrep` (denied in the sandbox) are needed. A 1 s delay let a 0.3 s
  tool repair finish first, so the kill scenario uses the interpreter arm. (03)
- **The lock API.** A name, not a path. Messages for provisioning stay byte-identical. (01)
- **Gate traps found while proving the gates.** They are written into the gates and recorded in
  `META.md`:
  - A POSIX `sh` variable assignment in front of a *function* call persists after the call. `VAR=x
    ranks …` leaked `UVM_REPAIR` and `SLURM_JOB_ID` into the next drive's provisioning, which then
    wrote the outcome. Ranks take `env VAR=x uv …` instead.
  - `wait` with no operands waits for a planted `sleep 60` holder too, so the gates wait on named
    pids.
  - BSD `sed` has no `\|`.

## 5. Risks & open questions

**Plan-gate rulings** (foreman, 2026-10-29). Each is folded into §2, §3 and `TECH.md`.

1. **The deviations in §3 are accepted.**
2. **Q1, distinct scopes queueing on one repair lock: accepted as recommended.**
   - An array task keys on `SLURM_ARRAY_JOB_ID`, under the cluster-name prefix, so one array is one
     scope.
   - Separately submitted jobs that start together still each walk the tree in turn. Any job past
     `UVM_LOCK_TIMEOUT / w` in the queue fails, w being the walk time: about 0.1 s on the
     prototype's small trees, 0.4-2.8 s on a realistic tree. The README documents the limit.
   - The limit is seeded as
     [`issues/repair-scope-queueing.md`](../../issues/repair-scope-queueing.md), with a `ROADMAP.md`
     entry.
   - R12 (one job, many ranks) is unaffected. The P2 gate adds a two-task array drive.
3. **Q2, a receipt-less tool: accepted as planned.** It fails the scope, the outcome's reason names
   the tool, and uv's stderr is not parsed.
4. **Q3, accumulation: accepted.** The purge bounds the outcome files, `uvm clean outcomes` is the
   manual bound, and there is no pruning code. The justification stays in §2.
5. **P5's jobs fit the approved test-job class: at most 30 min wall and 16 GB per node.** Each
   cluster gets two jobs: job 1 runs P and T, job 2 runs kill. Run B concatenates their summaries in
   a fixed order into one evidence file per filesystem (TECH P5).
6. **Egress: probed and present** from compute nodes on both target clusters, for `releases.astral.sh`,
   `github.com`, `objects.githubusercontent.com`, `pypi.org` and `files.pythonhosted.org`.
7. **R1's +0.3 ms of parse: accepted.** It is a known observation for the review (below).

**No step and no subagent of this cycle uses any cluster tool**, meaning any tool of a cluster MCP
server. Remote commands need the maintainer's per-task approval, and the only approved class is the
foreman's test jobs. In planning, one research subagent ran an unapproved read-only bash-version
test on two login nodes. It was reported to the foreman, and brief 04 carries only its version
results.

**Cluster-only, named so the review does not mistake them for covered:**

- Every repair hold here is a desktop on a fast link: tool arm 0.3 s, interpreter arm 0.8 s per
  23.9 MiB interpreter.
  - R12 records the cluster hold (`hold_s`) and the waiters' wait (`wait_max_s`, `wait_p50_s`).
  - A hold near `UVM_LOCK_TIMEOUT` (180 s) is a finding per the GOAL's timeout ruling, not a reason
    for a knob.
  - Measured in P5 Run B, 2026-10-29, uv 0.13.6, as `hold_s` / `wait_max_s` / `notice_lines`.
    Cycle 0, against `4c08e9c`:

    | Scenario | Lustre (2 nodes × 64 ranks) | GPFS (1 node × 64 ranks) |
    |---|---|---|
    | P | 5 / 5 / 0 | 5 / 5 / 0 |
    | T | 1 / 3 / 0 | 1 / 2 / 0 |
    | kill, killed pass | none / 61 / 127 | none / 61 / 63 |
    | kill, clean pass | 6 / 7 / 0 | 5 / 5 / 0 |

    The longest hold is 6 s against the 180 s timeout, so no hold is near it. In the killed pass
    every waiter ran out the 60 s timeout naming the lock, as designed.

    Cycle 1, against `40e6120`, after review cycle 1's remediation (P5 Run B, cycle 1):

    | Scenario | Lustre (2 nodes × 64 ranks) | GPFS (1 node × 64 ranks) |
    |---|---|---|
    | P | 5 / 5 / 0 | 34 / 34 / 63 |
    | T | 2 / 3 / 0 | 2 / 2 / 0 |
    | kill, killed pass | none / 60 / 127 | none / 61 / 63 |
    | kill, clean pass | 6 / 7 / 0 | 13 / 14 / 0 |

    On GPFS, scenario P held the repair lock for 34 s, against 5 s at cycle 0 and 5 s on Lustre at
    this commit. Every one of the 63 waiters printed the 30 s wait notice (`notice_lines=63`), and
    all exited 0. The same job's `prep_s` was 12 s, against 4 s at cycle 0, which points at the node
    or the filesystem at that moment rather than the code. The foreman is re-running that job once to
    check, and will record the rerun separately. On GPFS the kill job's clean pass held 13 s against
    5 s at cycle 0, and that job's `prep_s` was 16 s against 4 s. The longest hold is 34 s against
    the 180 s timeout. In the killed pass every waiter again ran out the 60 s timeout naming the
    lock.

    Cycle 2, against `5e1e6d9`, after review cycle 2's remediation and the drive's purge-shaped
    trees (P5 Run B, cycle 2):

    | Scenario | Lustre (2 nodes × 64 ranks) | GPFS (1 node × 64 ranks) |
    |---|---|---|
    | P | 4 / 4 / 0 | 4 / 5 / 0 |
    | T | 2 / 4 / 0 | 2 / 2 / 0 |
    | kill, killed pass | none / 61 / 127 | none / 61 / 63 |
    | kill, clean pass | 5 / 7 / 0 | 3 / 3 / 0 |

    The longest hold is 5 s against the 180 s timeout. GPFS's P hold is 4 s, against 34 s at cycle
    1, with that job's `prep_s` at 6 s against 12 s. No waiter outside the killed pass printed the
    30 s wait notice. In the killed pass every waiter again ran out the 60 s timeout naming the lock.

    Cycle 3's run, against `7ba7f11`, left no evidence file: its Lustre result is in REVIEW.md
    *Review cycle 4*, and its GPFS jobs were cancelled while queued for the C4-F1 fix.

    Cycle 4, against `bdc38d6`, after the C4-F1 fix (P5 Run B, cycle 4), uv 0.13.6. This table adds
    the waiters' median, as `hold_s` / `wait_max_s` / `wait_p50_s` / `notice_lines`:

    | Scenario | Lustre (2 nodes × 64 ranks) | GPFS (1 node × 64 ranks) |
    |---|---|---|
    | P | 3 / 4 / 4 / 0 | 5 / 5 / 5 / 0 |
    | T | 2 / 3 / 3 / 0 | 1 / 2 / 1 / 0 |
    | kill, killed pass | none / 66 / 60 / 127 | none / 61 / 61 / 63 |
    | kill, clean pass | 4 / 5 / 4 / 0 | 5 / 6 / 6 / 0 |

    The longest hold is 5 s against the 180 s timeout. No waiter outside the killed pass printed the
    30 s wait notice. In the killed pass every waiter ran out the 60 s timeout naming the lock; on
    Lustre the slowest took 66 s, against 60-61 s before, with the median at 60 s.
- Egress from compute nodes was probed and is present (ruling 6). That covers uv's offline fallback
  host `github.com` too. A host lost by the time of the run shows as a failed outcome, or as
  `progress` not ok and exit 4.
- `--launch srun` in the new drive runs first on the cluster. Its local twin, `--launch local`, and
  the `srun` usage guard are exercised here.
- NFS is not exercised. On NFS a lock winner's re-test can miss a just-written outcome for up to
  `acdirmax`, which costs one redundant walk (04 Recommendations 6). The README notes it.
- Bash 4/5 executes the wrapper only on the cluster run, which records `bash=`.

**Other risks.**

- **R1's hot path, a known observation for the review (ruling 7).** The off path adds no fork. The
  script grows by about 150 lines, and bash parses all of it before the exec: 12.0 ms to 12.3 ms per
  warm call here (200 calls, twice per arm). This is accepted. The review reads the fork-free path
  and does not grade the parse cost as a defect.
- **`uvm clean outcomes` during a live repair** removes the directory under the holder. Its record
  then fails, it dies, and the next waiter repairs again. The dry run says "once nothing is
  repairing this tree".
- **The dispatch tail and `uvm_doctor` are rewritten in P2.** They are high-blast-radius, and
  `lock-race.sh` and P2's R1 and R13 drives are the regression evidence.
- **Leftovers for `/uvm-roadmap` at landing** (not this cycle's code):
  - retire `issues/purge-tree-repair.md` and its `ROADMAP.md` entry;
  - seed doctor's double report of a damaged interpreter through uv's minor-version symlink (02 Q4);
  - update `issues/uv-cache-purge-damage.md`'s reference to this cycle as landed.
- **GOAL observed-on-main details** (brief 02):
  - (T): `uvx` fails inside uv with an empty line on stderr, not with an `ImportError`.
  - (P): `uv run` exits 1, not 2.
  - The red states stand. No gate keys on the detail.

**Schedule against about Nov 8** (today Oct 29).

| Phase | Work | Target |
|---|---|---|
| P1 | Lock name; small and proven | Oct 30 |
| P2 | The core: largest phase, most docs | Oct 30 – Nov 2 |
| P3 | Arms and the real-uv gate | Nov 3 |
| P4 | Doctor and clean | Nov 3 – 4 |
| P5 Run A | The drive | Nov 4 |
| Cluster runs | Two jobs per cluster, each within the 30 min, 16 GB class; queue wait; the foreman's | Nov 4 – 5 |
| P5 Run B | Close the phase | Nov 5 |
| Review | Three bounded cycles | Nov 5 – 7 |
| Publish | | Nov 8 |

- It fits with one day of slack.
- **The riskiest phase is P5.** It has an external wait and the first `srun` run of a new drive, and
  a hold time nobody has measured. Egress is no longer a risk (ruling 6).
- **The runner-up is P2.** It has the most code, most of the same-commit documentation, and two
  high-blast-radius regions.
- If P5's cluster run slips, the rest of the cycle can be reviewed while it waits. The phase must not
  be closed on one filesystem silently.

## 6. Verification strategy

Three layers per phase: `bash -n`, `.agents/factory/bin/lint.sh` (which shellchecks `tests/` too), and
drives under `temp_root.sh`. Offline gates use the fixture. Two gates are marked **real uv +
network**, P3's second half and P5's local T and kill runs, and they seed from a local uv
(`command -v uv`, never this checkout's wrapper). They need `pypi.org`, `files.pythonhosted.org` and
`releases.astral.sh`.

| Phase | Post-conditions | Before / after |
|---|---|---|
| P1 | A repair caller on a held `.repair.lock` fails at the timeout naming *repair lock*, *repairing* and the owner line, with no `provisioning` word and no `.install.lock`. An unknown name dies. Provisioning's notice is unchanged. `lock-race` control, held and pin give `progress=ok`. The old signature is gone from `bin/`, `AGENTS.md` and `invariants.md` | HEAD red at the first assertion (the repair call returns 0 holding `.install.lock`) |
| P2 | R1: 16 ranks off, plus empty and `0`: zero repair lines, root listing exact. R2 (failed, then repaired, then none). R3's fixture halves (intact tree; pin). R7 and R9 (d): 16 ranks, one line, 16/16, ≤ 9 s. R8 (rc 7). R9 (a) and (b). R10 (`0`; jobs 100, 100, 101; two tasks of array 300 give one repair and `job-300.ok`; `SLURM_CLUSTER_NAME` namespaces the key; values a, a, b). R13 (a), (b), (d). Help census. Six-file census | HEAD red at its P1 guard. On a P1 tree, R1 passes (regression) and the first red is R2's failed half (rc 0 with the fixture version), as GOAL records |
| P3 | Offline: R6 (three interpreter states), interpreter-before-tool order, R5 fixture (no repair line, named orphan, failed outcome), receipt-less reason. Real: R3 (T) (stdout one line `3.2.0 Python 3.12.*`, manifest `comm -23` empty, shim runs, receipt `cmp`, outcome), R4 (`3.1.0`, `import six`, receipt `cmp`), R3 (P) (`t-ok [1]`, no tool arm), R5 real (base `site-packages` and `bin/` listings identical, failed outcome) | HEAD red at the P2 guard |
| P4 | R13 (c) (doctor WARN with owner, dry run keeps, `--yes` removes, `current` resolves). R9 (c) (4 ranks, KILL: 1×137, 3 timed out naming lock and owner, no outcome, doctor WARN, clean, then one repair). Consequence 1 (doctor names a failed value outcome and `uvm clean outcomes --yes`; dry run counts; `--yes` removes; the value repairs again). Help mentions `outcomes`. Six-file census and README/modulefile keywords. Doctor's remediation block names the knob | HEAD red at the P3 guard |
| P5 | `--launch srun` without `REPAIRRACE_SHARED` exits 2. Local F ×16 offline. Local T and kill ×8, real uv. Summaries carry no `/` or host name. Then `evidence/lustre.txt` and `gpfs.txt`: P, T and kill present, `exit=0` ×3, `progress=ok` ×3, `repairs=1` and `outcomes=1` in P and T, no lock left, `ranks≥64`, both stdout forms, `killed=1`, `doctor_warn_repair_lock=1`, `clean_repairs=1`, `clean_outcomes=1`, hold and notice keys; `nodes=2` on Lustre | HEAD red at its guard. After Run A, red at "cluster evidence … not recorded yet", the external wait. Proven green in the throwaway copy with evidence assembled from local 64-rank runs |

**Inspection-only.** No command decides these, so `/uvm-review` reads them:

- R1's "forks nothing", and the 200-call timing.
- R2's "the outcome test precedes every walk".
- R4's "the named command is the only tool repair".
- R7's "the walk runs only once the lock is won".
- The prose of each R14 hit against the list in R14.
- The evidence files, for anything identifying that a pattern cannot catch.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
