# 00 — Digest: what research settled, and what it broke

Six briefs, then three adversarial verifiers re-running the load-bearing claims independently. Where
a brief and its verifier disagree, the verifier's number is used and the disagreement is stated —
several briefs were optimistic in ways that would have shipped an inert gate or a second concurrent
repairer.

The headline: **R1 is ready and better-evidenced than the GOAL claims. The repair half has three
contract defects that no amount of implementation care fixes**, because they are in the criteria
themselves.

## Decisions

**D1 — R1 is six `[[ -d ]]` tests, outside the subshell. No stamp file anywhere.**
The saving is 2.0 ms of 12.0 ms: 17% of the invocation, 27% of the overhead above the exec'd binary,
so the GOAL's "about a quarter of the wrapper's overhead" is right on its own denominator. Two of the
three warm-path process creations go. The guard must sit **outside** `( umask 077; … )` — a guard
inside it keeps the fork and gives away a third of the saving, and R1's exec-counting gate cannot
see the difference. Brief 01's "~40 stats, 6:1 ratio" is wrong and must not reach `PLAN.md`: the real
model is 25 `mkdir(2)` calls all failing EEXIST plus 6 stats, against the guard's 6 stats. The
correction favours the guard, since a failing `mkdir` RPC cannot be served from a client attribute
cache and a `stat` often can.

**D2 — the stamp is dead in both forms, and this contradicts a resolved GOAL clarification.**
A verdict stamp records that the layout was right once; a purge removes a directory and leaves the
stamp, so the drive with `bin/shims` removed leaves the tree broken — R1's second clause fails by
construction. Brief 02's fingerprint stamp escapes that horn and dies on the other: its atime is the
last wrapper invocation, and the motivating case is a job that has not run in thirty days, so the
stamp is exactly as cold as the tree it vouches for and is purged with it. The check then degenerates
to "no stamp, assume damaged" and commits the wrapper to a whole-tree reinstall for a tree that lost
only its stamp. `GOAL.md:154` records, resolved and dated, that R1's sentinel and R3's marker are one
mechanism. They are not. This needs an amendment with sign-off, not a silent design departure.

**D3 — the repair idiom is `uv tool upgrade --all --reinstall --no-cache` and
`uv python install --reinstall` with no target.** Both are whole-tree, so the wrapper never
enumerates and never reconstructs a spec. That matters more than it looks: `uv tool install
--reinstall tqdm` against a tool installed as `tqdm==4.66.0` upgraded it to 4.70.0 and rewrote the
receipt, destroying the user's pin permanently. `uv tool upgrade --reinstall` reads the receipt
itself and preserved both the pin and the `--with` packages. Doctor's currently printed idiom is
wrong twice over: `uv tool install <name>` no-ops on a gutted-but-receipted environment, and
`uninstall && install` still produces a broken tree when the cache is damaged, because uv performs no
integrity check on its unpacked `archive-v0` store. `--no-cache` is load-bearing, not an optimization.

**D4 — the repair must never hold `.install.lock` for its duration.** This is the verifier's
single most important finding and it reverses brief 03's recommendation. The `uvm_install` /
`uvm_install_locked` split is sound and should be taken; reusing the install lock for a repair whose
hold time is two to three orders of magnitude longer is not. `UVM_LOCK_STALE` was sized for one
binary download. A repair that outlives 600 s gets its live lock broken by a waiter, and a second
repairer starts while the first is still running — demonstrated at scaled knobs, and reachable on
shipped defaults whenever arrivals are continuous, which at ten thousand ranks they are. Early
waiters are meanwhile told, verbatim, to `rmdir` a lock held by a correct live repair.

**D5 — `uvm_unlock` releases locks it does not own.** Proven, not theorised: it matches on the path
(`bin/uv-manager:177-182`), never on ownership, and the EXIT/INT/TERM traps inherit it. A watcher
caught process A removing process C's owner file and `rmdir`ing C's lock after C had broken A's.
Latent on `main`, because reaching it needs a hold longer than `UVM_LOCK_STALE`; routine once repair
hold times exist. Any repair design must add an ownership check, or heartbeat the lock so its age
reflects liveness rather than acquisition time.

**D6 — repair must decide `want` from the pin.** Brief 03's prototype called `uvm_install_locked ""`
unconditionally. Driven with `UVM_PIN=0.4.0` against a tree already at 0.4.0 whose only damage was a
tool environment, it repointed `current` to 9.9.9 — silently overriding the pin for every other rank
in the job, including ranks already past `uvm_ensure_uv` and about to exec `${uvm_current}/uv`. That
is an invariant §4 violation. The same hole makes repair fetch uv over the network when uv is intact,
so an egress-less compute node — the wrapper's central case — turns a locally repairable tool venv
into a hard failure that blames the network.

**D7 — `uvm doctor` is not the exhaustive authority, and cannot be R4's oracle.** Confirmed with real
uv and real `tqdm`, not synthetics: gut a tool environment and remove `RECORD` along with the files,
and doctor prints `OK    no damage detected` and exits 0. `RECORD` is read only on uninstall, making
it the coldest file in a distribution and an early casualty of an atime purge. So R4's stated
oracle — "asserts `uvm doctor` subsequently exits 0" — is satisfiable with zero repair code, on
exactly the failure the cycle exists to fix. Pre-existing on `main`; fatal to R4 as written.

**D8 — five of the eight criteria are inert as the GOAL words them.** R2, R3's scaling half, R4, R6
and R8 all assert properties the current tree already has. R8 is the exception that is genuinely red
(`UVM_REPAIR` appears zero times in all four surfaces). Each of the others needs a red-capable
pairing, given in `05-verification-methodology.md` and corrected in the verifier's pass — most
importantly R4, whose proposed drive never sets `UVM_REPAIR` and never exercises the wrapper at all.

**D9 — R8 is incomplete; the cycle touches eight places across six files.** Beyond the three R8
names: `share/modulefiles/uv/main.lua` (whose help text tells users a partial purge "is not detected
by uv"), `uvm_doctor`'s remediation block, `README.md`'s design note at `:462`, its purge-mitigation
list at `:411-422`, its troubleshooting line at `:520`, and the stale **7 ms** figure at
`AGENTS.md:109` and `README.md:141`, which becomes ~5 ms. One correction to the planner's own
pre-flight reading: **`AGENTS.md` never asserts the unconditional `mkdir`** — `invariants.md:122-123`
is a derived claim with no source-file counterpart, which is pre-existing lockstep drift in the
direction the lockstep rule says loses. Left unedited it makes the correct implementation an
auto-CRITICAL §8 violation in `uvm-review`, inside a high-blast-radius region.

**D10 — `UVM_REPAIR` is collision-free but its shape is a footgun.** Zero `UVM_` strings and zero
"repair" occurrences in uv's env-var registry or its live `install.sh`. It would be the first boolean
knob; every existing one carries a value, and the script's internal convention is non-emptiness. Left
implicit, `UVM_REPAIR=0` **enables** repair, and R2's wording ("WHILE `UVM_REPAIR` is unset") does not
close it. Test a value explicitly and document the spellings, or document that any non-empty value
enables it.

## The three contract defects

These are not implementation problems. They are in the criteria, and building against them ships
something that passes review while doing nothing.

1. **R4's oracle is blind to the motivating damage** (D7). Replace with a post-condition independent
   of `RECORD`: capture the manifest before damage and assert re-materialisation, and assert the
   tool's console script runs. Add an explicit `RECORD`-purged arm.
2. **R3 promises more than any bounded check delivers.** Three misses were built in minutes against
   the best candidate probe set: 200 of 201 module files gone with `RECORD` intact (check silent,
   doctor fails); a shim left at mode 0644 (doctor tests `-x`, an `[[ -e ]]` canary is silent); and a
   managed interpreter with a purged stdlib file.
3. **R3 and R4 contradict each other on managed pythons.** R4 requires repairing them. The only
   detector is doctor's 29.7 ms interpreter fork, which R3's own boundedness rule excludes — one
   `stat(1)` fork alone costs 1.89 ms, seven times the whole wrapper at 40 tools. Either the bounded
   check cannot see python damage, in which case R4's python repair never fires from the hot path, or
   R3 is violated. No brief noticed this.

## Scope and cost, corrected

O(1) is unreachable; O(#tools) is what R3 buys, and it is flat against file count — 40 tools cost the
same at 400 recorded files and at 40 000, while doctor goes 29 ms to 223 ms. The per-tool constant is
bash, not the filesystem, and the verifier measured it about twice the brief's figure: the check is
net-free against R1's saving to roughly **60** tools, not 90, and the canary-bearing glob variant
costs 3.53 ms at 40 tools, already more than R1's entire saving.

Two traps for the implementer. Directory mtime propagates one level only, so a site-packages-root
probe is structurally blind to damage inside a package directory — the damage that produces the
ImportError. And directory `nlink` is not an entry count: APFS reports entries+2 and moves when a
plain file is unlinked, while ext4, XFS and Lustre report 2+subdirectories and would not move at all.
It passes in the sandbox and fails on the cluster, which is the worst available failure shape.

## Reach: narrower than the GOAL implies

A purged tool invoked by its own name never enters the wrapper. The generated trampoline
(`bin/uv-manager:481-495`) execs `$d/$a/bin/shims/$n` directly, and `$UVM_ROOT/bin` is what the
modulefile puts on `PATH`. `UVM_REPAIR` reaches `uv`, `uvx` and `uvm` and nothing else, so a user
typing `ruff` on a purged tree still gets the ImportError. This is not a defect in the design; it is
a limit that has to be documented, because the GOAL's vision paragraph reads as though it covers the
user's whole experience of a purged tree.

## Verified pre-existing defects, exposed by this cycle

Reachable on `main` only at hold times this cycle would introduce, which is why they are listed here
rather than filed as live bugs — but a repair design must fix them, not inherit them.

- `uvm_unlock` matches on path, not ownership (D5).
- `UVM_LOCK_TIMEOUT > UVM_LOCK_STALE` makes a process break its own lock, then exit 0 with mutual
  exclusion gone. Nothing enforces an ordering between the two knobs.
- A lock held across the dispatch tail's `exec` is leaked until `UVM_LOCK_STALE` elapses; `exec`
  replaces the process image and the EXIT trap never runs. `main` never holds a lock at `exec`, so
  this is a constraint on the new design rather than a current bug.
- `uvm_doctor` is silent when a purge takes `RECORD` (D7).

## What no local drive can settle

Parallel-filesystem cost, and it is the number that decides the cycle's premise. Every figure here is
bash-interpreter-bound on warm APFS: 17–21 µs per tool against a raw `stat(2)` of 1–2 µs. On a cold
Lustre MDS the ratio inverts and the filesystem term dominates. The amplification is what matters —
the `mkdir -p` R1 removes is ~31 metadata operations, an O(#tools) check at 40 tools is one `readdir`
plus ~120 stats, and every rank of a ten-thousand-rank job issues it in a burst. R1 reduces that
traffic; R3 increases it. Whether the cycle is net-positive on a real metadata server is unmeasured.

Also unsettled: the real duration of a repair, which decides whether D4's stale-breaker race fires at
all; and Lustre/GPFS/NFS `mkdir` semantics, taken on trust from the existing discipline per R5's own
wording.

*Briefs: [01](01-hot-path-cost.md) · [02](02-bounded-integrity-check.md) ·
[03](03-lock-reentrancy-and-concurrency.md) · [04](04-uv-repair-idioms.md) ·
[05](05-verification-methodology.md) · [06](06-surface-and-docs.md). Verifier findings are folded in
above rather than kept separately; where they overturn a brief, the brief is left as written and the
digest records the correction.*
