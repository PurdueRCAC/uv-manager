# 01 — What the unconditional `mkdir -p` costs, and the cheapest correct replacement

**Conclusion, high confidence: six `[[ -d ]]` builtin tests falling through to the existing subshell.
Do not introduce a stamp file.** The stamp is 12 µs cheaper in isolation, indistinguishable end to
end, and it fails the second half of R1 by construction — a drive with one state directory removed
leaves the tree broken. The GOAL's clarification assumes R1's sentinel and R3's marker are the same
mechanism; they answer different questions, and only the contents question needs a marker.

The saving is real but smaller than the GOAL states: **~1.5 ms of ~12 ms**, and **2 of the 3 process
creations** on the warm path.

Host: macOS 26.5.2, arm64, APFS on local SSD, sandbox under `$TMPDIR`. `#!/usr/bin/env bash` resolves
to `/bin/bash` **3.2.57** here, so every drive below ran at the portability floor. Method: three
copies of the tree under `/tmp` (working tree untouched), each driven through its own
`temp_root.sh --offline`, tree warmed, fixture stub replaced by the real `uv` 0.12.3 binary so the
exec'd cost matches the GOAL's setup.

## 1. The numbers, and how they compare to the GOAL's

| Measurement (n=200 unless noted) | ms/call |
|---|---|
| `/bin/bash -c :` | 1.62 |
| `/usr/bin/env bash -c :` | 2.69 |
| `bash -n bin/uv-manager` (parse the 856 lines) | 2.49 |
| real `uv --version`, direct | 4.13 – 4.92 |
| `uvm --version` (answers before `uvm_init`) | 4.22 |
| **`uv --version` through the wrapper, warm intact tree** | **10.98 – 12.73** |

Interleaved A/B/C, five reps of 50 invocations each, alternating so machine drift hits all three:

| rep | status quo | six `[[ -d ]]` | `.layout` stamp |
|---|---|---|---|
| mean of 5 | **12.18** | **10.66** | **10.40** |

Within-variant spread is ±0.7 ms. Status quo minus guard is **1.52 ms**. Guard minus stamp is 0.26 ms
— below the noise floor, and twenty times the 0.012 ms the isolated measurement says it should be.

The GOAL's 9.6 / 3.1 / 2.4 do not reproduce as absolutes; the ratio roughly does (GOAL 3.1x wrapper
over direct, measured 2.7x). The share attributed to the `mkdir` does not: it is **12–15% of the
invocation and ~22% of the overhead above the exec'd binary**, not a quarter. Report it as ~1.5 ms of
~12 ms, or as two removable forks.

## 2. The block in isolation, and the candidate guards

| Construct, all six directories present | ms/call | n |
|---|---|---|
| (c) status quo `( umask 077; mkdir -p ×6 )` | 1.5100 | 200 |
| bare subshell `( : )` alone | 0.2650 | 200 |
| `mkdir -p ×6` without the subshell | 1.2050 | 200 |
| (a) six `[[ -d ]]` tests, all pass | 0.0168 | 20000 |
| (b) one `[[ -e "${uvm_root}/.layout" ]]` | 0.0047 | 20000 |
| empty loop (bash floor) | 0.0016 | 20000 |

Net of the loop floor: (a) is 15.2 µs, (b) is 3.1 µs. **The stamp buys 12 µs**, one part in nine
hundred of a single invocation. It is not worth a byte of complexity, let alone new on-disk state.

Counting stubs for 27 externals, one warm `uv --version`:

| variant | externals exec'd |
|---|---|
| status quo | `uname -m`, `mkdir -p …` |
| six `[[ -d ]]` | `uname -m` |

Three process creations on the warm path — `uname`, the `umask` subshell, `mkdir` — and the guard
removes two. `uname -m` is the third and it stays: §1 requires the key be resolved on the executing
node, and a standalone launch measures 1.19 ms. The largest remaining item the wrapper controls is
the `#!/usr/bin/env bash` shebang, whose extra exec costs 1.05 ms here and which cannot be traded
away, because bash is not at a fixed path across cluster images. **After the guard, the mkdir block
is no longer the biggest removable item — nothing removable is left.**

## 3. Correctness: the status quo does not repair modes

`mkdir -p` does not `chmod` a directory that already exists. Verified directly, and through the
wrapper: `chmod 0755 "$UVM_ROOT/<arch>/cache"` survives an invocation on `main` unchanged. The
property today is "directories *we* create are 0700", not "our directories are 0700". A `[[ -d ]]`
guard preserves exactly that. Adding a mode check would be new behavior R1 does not ask for.

Edge cases, status quo versus guard, identical in all four:

| case | both variants |
|---|---|
| fresh tree | all six created, `drwx------` |
| one directory at 0755 | unchanged by an invocation |
| a state path replaced by a regular file | `mkdir: …: File exists` on stderr, rc=1 |
| whole arch subtree deleted but `current/uv` | rc=0, all six recreated `drwx------` |

The fourth is R1's repair clause and the guard satisfies it: `[[ -d ]]` is false, so control falls
into the unmodified subshell, which recreates parents and children alike under `umask 077`.

R1's own verification shape works as written. A counting `mkdir` stub first on `PATH` sees **1**
invocation today on a warm intact tree, **0** with the guard, and **1** with the guard after one
directory is removed, leaving it at mode `700`. The stub survives the wrapper's three `PATH`
prepends, which land ahead of it but behind nothing that shadows `mkdir`.

**The stamp variant sees 0 in both cases.** With `$UVM_ROOT/<arch>/bin/shims` removed, the drive
prints `ls: …/bin/shims: No such file or directory`: the stamp records that the layout was correct
once, and a purge that removes a directory does not remove the stamp. That is the whole argument. The
directories are free, authoritative and self-healing; a stamp is a cached claim about them that a
purge invalidates without clearing.

## 4. Portability

`bash -n` clean under 3.2.57 for all three variants, and every drive above executed under 3.2.57.
`shellcheck --severity=style` clean on all three. `[[ -d ]]`, `!` and `||` inside `[[ ]]`, and a line
continuation inside `[[ ]]` are bash 2.02 constructs. No bash 5 is installed on this machine, so
bash 5 was not exercised; nothing in the construct is version-sensitive.

## 5. Metadata operations — the part that transfers to a cluster

`mkdir -p` resolves an existing path with at least one `stat` per path component: it succeeds on an
existing child under a mode-0555 parent, for both `/bin/mkdir` and GNU `gmkdir`, so it is not relying
on a successful `mkdir(2)`. Six paths of six to eight components each is roughly forty explicit
`stat()` syscalls where the guard issues six. At the 2.5 µs warm APFS stat measured here that is
90 µs against 15 µs — noise beside the 1.5 ms of process creation locally, but it is the **6:1
syscall ratio**, not the fork, that survives the trip to a metadata server where a round trip costs
hundreds of microseconds and ten thousand ranks issue it in a burst.

## 6. What I could not establish

Real-cluster numbers. Everything here is local SSD with a warm dentry cache. macOS exec is expensive
(code signing, dyld), which inflates the fork saving; Lustre and GPFS metadata is far more expensive
than APFS, which inflates the stat saving. The two errors run in opposite directions and neither can
be sized from this machine.

Whether GNU `mkdir -p` attempts a failing `mkdir(2)` before it stats. The read-only-parent result
rules out dependence on `mkdir(2)` succeeding, but not an attempt-then-stat. `dtruss` and `fs_usage`
need root.

The GOAL's 9.6 / 3.1 / 2.4 were not reproduced as absolutes and I cannot say which machine state
produced them. No conclusion above depends on the answer.

## 7. For the planner

Take (a). Keep the fall-through target byte-identical to today's subshell — the rc=1 parity on the
file-in-place-of-a-directory case depends on `mkdir` still being the thing that reports it, under
`set -e`. `uvm_export_env` is also called by `uvm trampolines` and `uvm install`; one guard, no
special-casing. Leave R3's marker to R3: it is answering "are the contents intact", which has no free
test, and coupling R1 to it would make the layout guard only as accurate as the contents marker.
