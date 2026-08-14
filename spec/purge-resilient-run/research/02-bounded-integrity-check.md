# Bounded integrity check: what fits, and what it must admit it cannot see

Research for R3. All numbers measured on this machine — macOS 25.5, arm64, APFS on local SSD,
bash 3.2 — inside `.agents/factory/bin/temp_root.sh --offline` sandboxes with synthetic tool trees.
Local SSD is the optimistic case; the parallel-filesystem caveat is at the end.

## Conclusion

**O(1) is unreachable, O(#tools) is what R3 actually buys, and the stamp the GOAL assumes cannot
work in the form the GOAL assumes.** Confidence: high on the first two (measured), high on the
third (measured, and the mechanism is a POSIX guarantee).

Three findings the plan has to absorb:

1. **A verdict-stamp is a lie either way; a fingerprint-stamp is not.** A file recording "the tree
   was intact at time T" fails in both disciplines the topic names. What escapes the dilemma is a
   stamp that records a *fingerprint* of the tree's cold structure rather than a verdict about it.
   Freshness then costs nothing, because the comparison is made against the tree as it is now.
2. **Every probe a designer reaches for first is a hot file, and hot files are exactly what an atime
   purge spares.** Measured false-negative rate on the motivating failure: 6 of 6 natural probes
   stayed silent while 198 of 201 module files were gone.
3. **`uvm doctor` is not the exhaustive authority R3 wants to point users at.** It goes silent on
   the same tree when the purge takes `RECORD` — which, being the coldest file in a distribution, is
   among the first things a purge takes. This is a pre-existing defect on `main`, not something this
   cycle introduces, but R3's README sentence cannot be written honestly until it is faced.

## What doctor detects, and what each detection costs

| Damage class | Cost class | Measured |
|---|---|---|
| uv binary missing | O(1) | below noise (< 5 µs) |
| dangling tool/python shims | O(#shims) | 0.30 ms at 40 |
| tool env missing `uv-receipt.toml` | O(#tools) | part of the 0.70 ms below |
| tool env with broken interpreter link | O(#tools) | 0.70 ms at 40 for both stats plus the glob |
| files missing per `dist-info/RECORD` | O(#FILES) | 327 ms at 400 files, 1069 ms at 40 000 |
| managed interpreter stdlib import | O(#pythons), forks | **29.7 ms per interpreter** |

Baselines in the same sandbox: wrapper `uv --version` warm 10.4 ms, real uv direct 2.9 ms, the
six-directory `mkdir -p` 1.63 ms, a bare `fork`+`exec` 1.49 ms. The `mkdir -p` R1 removes is
therefore ~90 % process cost and ~10 % metadata on local SSD; R1's saving is a fork, not six stats.

**No forking probe is admissible.** `stat(1)` costs 1.89 ms per call, so one `stat` per tool is
70 ms at 40 tools — 7× the whole wrapper. Bash has no builtin that reads an mtime. Any mtime-based
design is out unless it can be expressed as `[[ ]]` tests.

## 1. Is O(#tools) acceptable?

Yes, on the GOAL's own text: R3 binds "the number of installed **files**", and its verification
drive varies the file count by two orders of magnitude. Measured directly — 40 tools, receipt plus
interpreter probe: **0.7592 ms at 400 recorded files, 0.7544 ms at 40 000**. Flat, while doctor over
the same two trees went 327 ms → 1069 ms. That is R3's assertion, already reproducible.

O(1) is not merely hard, it is **excluded by R4**: R4's drive damages all three classes and asserts
`uvm doctor` exits 0 afterwards, which forces a whole-tree scope. A check narrowed to the one tool
the invocation is about to use cannot satisfy it. R3 and R4 jointly pin the design at O(#tools).

The constant matters, and it is bash, not the filesystem: 17–21 µs per tool, of which the `tools/*/`
glob is ~43 %. Scaling measured at 1/10/40/100/400 tools: 0.07 / 0.21 / 0.74 / 1.92 / 8.59 ms.
Against R1's 1.63 ms saving, the check is net-free to roughly 90 tools and doubles the wrapper at
400. Two designs are already dead on cost: globbing `tools/*/lib/*/site-packages/*.dist-info/RECORD`
costs 19.6 ms at 800 dist-infos and 82 ms at 3200; counting site-packages entries against a recorded
count costs **94.5 ms** at 40 tools, because it re-reads 8 000 directory entries.

## 2. The stamp — both horns, and the way between them

`[[ -e ]]` and `stat(2)` do **not** update atime; `read(2)` does. Verified: a file backdated to
2020 kept its atime through `[[ -e ]]` and through `stat(1)`, and moved to now under `cat`. So a
probe file the wrapper only tests is never warmed by the testing, and both horns of the topic's
dilemma are about *what the stamp asserts*, not about how it is read.

- A stamp asserting **"intact"** is touched at install time by the code that was in a position to
  know. It then ages exactly like the environment it vouches for and is purged with it — giving a
  false alarm, not a lie. Refresh it per invocation to stop the false alarms and it becomes the lie.
- A stamp asserting **"here is the cheap shape of the tree"** is true no matter how fresh it is,
  because the verdict is computed at check time by comparing the recorded shape to the observed one.
  Freshness is then a feature: the stamp must survive to be useful.

So the discipline that works is a **fingerprint**, kept at the arch root (one file, one open) and
listing per-environment probe paths. Measured: one open plus `[[ -e ]]` per entry costs 0.62 ms for
40 canaries, 1.70 ms for 120, 5.48 ms for 400 — ~14 µs each, the same slope as the receipt probe but
with far better detection, and it avoids the `readdir` of `tools/` that the glob pays.

## 3. Which cheap signals actually fire

Simulated purge: one tool env, 201 module files, everything backdated 40 days, then the files a real
run touches (shim, console script, interpreter, receipt, `__init__.py`, three imported modules,
`METADATA`) warmed to yesterday, then every file with atime older than 30 days unlinked. 198 files
removed. Probe results:

```
uv binary -x                              PASS (silent)
shim bin/shims/demo -x                    PASS (silent)
uv-receipt.toml -f                        PASS (silent)
bin/python -x                             PASS (silent)
console script bin/demo -x                PASS (silent)
demo/__init__.py -f                       PASS (silent)
site-packages mtime vs recorded           PASS (silent)
site-packages entry count vs recorded     2 vs 2 -> PASS (silent)
dist-info/RECORD -f                       FIRES
demo/ dir mtime vs recorded               FIRES
demo/ entry count vs recorded             4 vs 201 -> FIRES
uvm doctor                                OK    no damage detected
```

Two mechanisms explain the whole table. **An atime purge selects against exactly the files a probe
designer would choose**: the interpreter, the console script and the receipt are the hottest files
in the environment and are the last to go. **Directory mtime propagates one level only** — verified
separately: removing `pkg/sub/deep.py` bumped `pkg/sub`'s mtime and left `pkg`'s and the root's
untouched. A site-packages-root probe is structurally blind to damage inside a package directory,
which is the damage that produces the ImportError this cycle exists to prevent.

Do not use directory `nlink` as an entry count. APFS reports entries+2 and moved 5 → 4 when a plain
file was removed; ext4, XFS and Lustre report 2+#subdirectories and would not move at all. It works
in the sandbox and fails on the cluster — the worst available failure shape.

The one probe that both fires and stays cheap is a **cold canary**, chosen per environment at install
time from files nothing reads at runtime. `dist-info/RECORD` is the natural choice: pip and uv read
it only on uninstall, so it is the coldest file in the distribution and therefore the earliest
casualty. A canary can only fire early, never late, so its error mode is a needless reinstall — it
fails safe.

The irony is load-bearing: **the cheap check detects precisely the case doctor cannot**, because
doctor's walk is driven by the manifest the purge eats first. Confirmed by re-running the same purge
with `RECORD` warmed: doctor then reports `FAIL demo-1.0 is missing 199 of 201 files`.

## 4. Check scope versus repair scope

They are separable, and the GOAL's rejection of "only what this invocation will use" was about
repair depth. But R4's acceptance drive re-couples them: it damages all three classes and asserts
`uvm doctor` exits 0, so a per-invocation-scoped check fails it. Scope is whole-tree by contract.

Independently: **a purged tool invoked by its own name never enters the wrapper.** The generated
trampoline (`bin/uv-manager:481-495`) execs `$d/$a/bin/shims/$n` directly, and `$UVM_ROOT/bin` is
what the modulefile puts on `PATH`. `UVM_REPAIR` reaches `uv`, `uvx` and `uvm` and nothing else. A
user typing `ruff` on a purged tree still gets the ImportError.

## What I could not establish

- **Parallel-filesystem cost.** Every number here is bash-interpreter-bound on warm local metadata:
  17–21 µs per tool against a raw `stat(2)` of 1–2 µs. On Lustre with a cold MDS the ratio inverts
  and the filesystem term dominates. The amplification is the number to worry about: the `mkdir -p`
  R1 removes is ~15 metadata operations; an O(#tools) check at 40 tools is one `readdir` plus ~120
  stats, roughly 8×, and ~80× at 400 tools — issued by every rank of a 10 000-rank job in a burst.
  A local sandbox cannot measure this and should not pretend to. It needs a cluster drive.
- **Real purge semantics.** The purge here is a Python simulation of atime-ordered unlink. Whether a
  site's implementation prunes emptied directories, honours `relatime` skew, or reads `atime` from
  the Lustre MDS at all changes which probes fire. `noatime` mounts flatten the whole age ordering,
  which makes the canary representative rather than leading — safe, but for a different reason.
- **Realistic tool shapes.** The trees are synthetic. The dist-info counts that make the RECORD glob
  cost 82 ms (40 tools × 80 distributions) are plausible for a `jupyterlab`-class tool but were not
  measured against a real install; `--offline` installs a shell stub, not uv.
