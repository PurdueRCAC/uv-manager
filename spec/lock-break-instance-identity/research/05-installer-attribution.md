# 05 — Attributing the two-installer signal

Read-only investigation of GOAL **R2**: what reaches the `install.sh` pipe at `bin/uv-manager:598`,
and whether the early-out at `:570` is one of the causes. Everything marked **measured** was driven
on this machine (macOS 25 / APFS, `/bin/bash` 3.2.57) against an instrumented copy of the tree
outside the working directory: a counter around the pipe, one around the hold, and a log of every
`:570` return, break decision, break removal and robbed retake. Everything marked **reasoned** was
not.

## Findings first

1. **Two ranks can be inside the installer at once only through the break path.** Every other route
   to `:598` is serialized by the `mkdir` lock. **Measured:** 34 control bursts, 2816 ranks, one
   installer entry per burst and a maximum simultaneity of 1; against 42 entries in 10 planted bursts
   with an owner and 70 in 10 without, at up to 11 simultaneous.
2. **Simultaneity and entry *count* are different measurements, and R2 must assert the first.**
   A second, serialized entry per burst is reachable with no break at all — a spurious re-download,
   not a mutual-exclusion failure. **Measured:** `current` missing or dangling with `versions/`
   populated gives 2 entries per burst, max simultaneity 1; eight concurrent `uvm install` (forced)
   give 8 entries, max simultaneity 1.
3. **The seed's hypothesis is wrong on the count and right that something is there.** The `:570`
   early-out produces **no installer entry, ever** — it returns before any fetch and modifies
   nothing. It is a *version-selection* defect, not a second-installer one. **Measured** across 2962
   early-outs on the control: zero installs, zero wrong trees.
4. **Where it does bite, it is not self-correcting.** With a non-empty `want`, `:570` returns 0
   without the `uvm_point_current` that `:566` and `:574` both perform. **Measured:** 31 of 32 ranks
   pinned to a version another rank was installing ran a *different* version, rc 0, no diagnostic;
   and on a cold tree, 31 of 32 died with `uv is still missing after provisioning`. `uvm install
   6.6.6` reported `selected uv 9.9.9 (fixture)` and exited 0.
5. **Per-rank attribution mis-attributes most of the signal.** A rank that never touched the break
   path is routinely one of the simultaneous installers, because it won a `mkdir` on a lock somebody
   else broke. **Measured:** 23 of 32 concurrent entries under the owner plant came from ranks with
   `brk_taken == 0`; 20 had never even decided a break. Attribution has to be per burst, or per lock
   instance — never per rank.
6. **Attribution is possible without instrumenting `bin/uv-manager`; counting robbed locks is not.**
   The break note at `:446` is on stderr and names the instance *judged*, never the instance
   destroyed — **measured** at 538 notes across the planted runs, every one naming the planted owner
   line and none naming a live rank's. It answers "was the break path entered" (0 of 2816 control
   ranks) and nothing finer. §4.

## 1. Every path to the pipe at `:598`

| # | Path | Precondition | Break path required? |
|---|------|--------------|----------------------|
| A | Lock won at `:347`, `uvm_have` false at the re-check `:573` | `versions/<want>/uv` absent (or `force`) when the winner tests it | **No** — the legitimate single install |
| B | A second holder created by a break at `:459-460` and a fresh `mkdir` | some rank declared the lock forfeit at `:420-437` and removed it | **Yes** |
| C | A robbed winner retaking at `:373-378` while the breaker also holds | this rank's own directory was removed between its `mkdir` and its `owner` write | **Yes** — only a breaker removes a directory it does not own |
| D | Fatal branch at `:362-364` misreading a robbery, `rmdir`ing a third rank's fresh lock | robbed, and the path re-occupied before `[[ -d "${lock}" ]]` | **Yes** (see §5, note) |
| E | `absent` retry at `:388-392` | `mkdir` failed and the lock was gone at the test — an ordinary release race | **No**, and it produces no extra entry: the retry re-enters `mkdir`, which one rank wins |
| F | `force` non-empty (`uvm install` with no argument, `uv self update`) | skips the fast path, the `:399` early-out and the `:573` re-check | **No**. N forced ranks give N entries, serialized |
| G | Spurious re-download: `current` absent or dangling with `versions/` populated | `uvm_have ""` false for every rank though the version is on disk | **No**. One extra entry per burst, serialized; `dest` exists at `:615` so the download is discarded |
| H | `:570` early-out | — | **Produces no entry at all.** See §3 |

E, F and G are the whole of the break-free residue, and none of them puts two ranks in the pipe
together. That is the assertion R2 needs: **the discriminator is simultaneity, not the count.**

## 2. The control (measured)

`.agents/factory/bin/temp_root.sh --offline --arch probe` driving one shared `UVM_ROOT`, ranks
released from a spin barrier, nothing planted. The offline fixture is instantaneous, so the install
window was widened through a knob the scrub does not reach (`PROBE_SLOW`), at 0, 0.4 and 1.5 s.

| Run | Bursts × ranks | Installer entries | Max simultaneous | Break decided | Robbed | `:570` returns | Bad `current` |
|-----|----------------|-------------------|------------------|---------------|--------|----------------|---------------|
| slow 0.4 | 10 × 64 | 10 | 1 | 0 | 0 | 609 | 0 |
| slow 0 | 6 × 64 | 6 | 1 | 0 | 0 | 354 | 0 |
| slow 1.5 | 4 × 64 | 4 | 1 | 0 | 0 | 225 | 0 |
| slow 0 | 20 × 96 | 20 | 1 | 0 | 0 | 1774 | 0 |

**Exactly one installer per burst in 34 of 34 bursts, 2816 ranks, rc 0 everywhere, `current ->
versions/9.9.9` everywhere.** This confirms the prior cycle's "exactly one installer per burst" and
its 0-robbed-winners on the ordinary cold path. `absent` reached 1 on 20 records and never the fatal
bound of 3.

For sizing: the control's per-rank rate of an extra entry is 0 of 2816, so the 95% upper bound is
3/2816 = 0.11% per rank (rule of three); per 64-rank burst, 0 of 34 bounds it at 8.8%. The planted
bursts were red 20 of 20, so the *red* gate needs few bursts and the *control* is what needs volume.

Planted, for contrast — a dead-holder lock aged past `UVM_LOCK_STALE`, 10 × 64 each:

| Plant | Entries (expected 10) | Max simultaneous | Break decided | Break taken | Robbed | Nonzero rc |
|-------|----------------------|------------------|---------------|-------------|--------|------------|
| owner recorded | 42 | 7 | 239 | 116 | 7 | 1 |
| owner-less | 70 | 11 | 299 | 257 | 15 | 1 |

Owner-less is 1.9x hotter here (60 extra entries against 32), the same direction cycle 3 measured at
4.5x with a different instrument.

## 3. What `:570` actually does — constructed, not argued

The asymmetry the GOAL points at is the crux. `uvm_have ""` tests `-x "${real_uv}"`, which is
`current/uv`, so it cannot be true unless `current` already resolves — there is nothing left to
repair, and the missing `uvm_point_current` costs nothing. That is why 2962 early-outs on the control
were harmless. `uvm_have "$want"` tests `versions/$want/uv` **directly**, and that becomes true at the
rename at `:618` — one line *before* `uvm_point_current` at `:620`. A pinned waiter whose early-out
lands in that gap returns 0 having selected nothing.

Both constructions below plant no lock, decide no break, and produce zero extra installer entries.
The gap was widened with a `ln` PATH shim (`sleep 2; exec /bin/ln "$@"`) — no edit to the wrapper,
the technique `lock-acquire-retake` R1 used for `mkdir`.

**A. Cold tree, 32 ranks, `UVM_PIN=6.6.6`.** 31 early-outs, all with `current=NONE`:

```
installer entries : 1        break decided : 0     robbed winners : 0
early-out at :570 : 31       ...with current=NONE : 31
nonzero rc ranks  : 31
     31 uv-manager: uv is still missing after provisioning: <path>
```

**B. Tree already selecting 9.9.9, 32 ranks, `UVM_PIN=6.6.6`.** Same 31 early-outs, `current`
resolving to the *wrong* version:

```
early-out at :570 : 31       ...with current=versions/9.9.9 : 31
nonzero rc ranks  : 0
stdout histogram  :    1 uv 6.6.6 (fixture)
                      31 uv 9.9.9 (fixture)
```

Thirty-one ranks that pinned 6.6.6 executed 9.9.9, rc 0, nothing on stderr. **C.** The operator
spelling, two concurrent `uvm install 6.6.6` on a tree at 9.9.9:

```
--- rank 1 rc=0
uv-manager: selected uv 9.9.9 (fixture)
```

`uv self update 6.6.6` is the third spelling: `:873` calls `uvm_install "${target}" ""`, then
`exec "${real_uv}" --version` prints the version it did not select.

So the prior review's "real, pre-existing" holds; its "self-correcting" does not. The *tree* self-
corrects — the winner points `current` a millisecond later — but the invocation does not. Case A
fails the user's command; case B returns the wrong answer with no way to know.

## 4. How the drive should discriminate (recommendation)

**Assert simultaneity, not entries.** Two counters, both external to the wrapper:

1. **Was the break path entered** — the break note at `:446` goes to stderr carrying the owner line
   the decision was made on, so a per-rank stderr capture counts break decisions with no counter
   inside the script. **Measured:** 239 notes for 239 decisions under the owner plant, 299 for 299
   without, **0 across 2816 control ranks**. That is the attribution R2 asks for, and it is free.
   It does **not** count robberies: every one of those 538 notes named the *planted* owner line and
   none named a live rank's, because the note reports the instance judged and the victim is the
   instance that replaced it — the GOAL's point, restated as a measurement. Counting robbed locks
   needs either the drive's own plant knowledge combined with counter 2, or a counter in the script.
2. **Simultaneous installers** — the fixture `install.sh` is the drive's own file, and it runs once
   per installer entry with `UV_UNMANAGED_INSTALL` naming a unique `.incoming.` staging directory.
   Have it register itself in a directory the drive owns *outside* the sandbox, count the
   registrations while it holds one, sleep, then deregister. Peak occupancy > 1 is the assertion. No
   edit to `bin/uv-manager`, and the ledger survives a straggler that outlives the sandbox — which is
   also what R1's straggler half needs.

**Attribute per burst, never per rank** (finding 5). The burst is red-and-attributed-to-the-break
when peak occupancy > 1 **and** at least one break note was emitted anywhere in the burst; red with
no break note anywhere is the other cause and the drive should say so and name it. On the control
this is unambiguous, because zero break notes are emitted at all.

**Count entries separately and expect ≥ 1, not exactly 1.** `versions/` on disk with `current`
broken legitimately produces a second serialized entry (path G), and treating that as red would make
the gate flap on a state the drive itself can create by killing a rank.

## 5. The `:570` finding, shaped for a seed

- **Mechanism.** `uvm_install`'s `uvm_acquire_lock … || return 0` at `:570` returns without the
  `[[ -n "${want}" ]] && uvm_point_current "${want}"` that both the fast path (`:566`) and the
  re-check under the lock (`:574`) perform. The early-out at `:399` fires on `versions/<want>/uv`,
  which exists from the rename at `:618`; `current` is not swapped until `:620`.
- **Reachability.** Requires a non-empty `want` — `UVM_PIN`, `uvm install <ver>`, or
  `uv self update <ver>` — and a concurrent rank inside the `:618`→`:620` gap. Sub-millisecond on
  `main`, sampled once per waiter iteration; **measured** at 31 of 32 ranks with the gap widened to
  2 s, and 0 of 2816 unpinned control ranks (`want` empty cannot reach it).
- **Consequence.** Either `die "uv is still missing after provisioning"` with empty stdout (cold
  tree), or a silent pin violation — the wrapper `exec`s a version the caller did not ask for, rc 0,
  no diagnostic. The second contradicts `invariants.md` §4's "a pin is authoritative" and is the more
  serious: it is wrong output, not a failure.
- **Self-correcting?** No. The tree converges; the invocation does not.
- **Shape of a fix, reasoned.** `:570` should point `current` at the version whose presence the
  early-out just confirmed, i.e. take the `:574` line rather than returning bare — which makes the
  three return paths agree. Two callers already do the same test one frame up (`uvm_ensure_uv:628`),
  so the tidier form is for the early-out to return a status the caller can act on. Out of scope for
  this cycle; GOAL *Non-goals* requires only the finding.

**Note, separate defect, same family.** The fatal branch at `:362-364` decides "the owner write was
refused" from `[[ -d "${lock}" ]]`, which is a *path* test. **Measured** twice in 1280 planted ranks:
a rank robbed at `:351` found the path re-occupied by a third rank's fresh lock, `rmdir`ed **that**
lock at `:363` and died with `cannot record ownership of the provisioning lock`, rc 1, empty stdout.
This is `issues/lock-owner-write-errno.md`'s residue, reachable today, and it destroys an innocent
lock on the way out.
