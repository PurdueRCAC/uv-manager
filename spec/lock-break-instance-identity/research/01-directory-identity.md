# 01 — Can a shell read a directory's identity?

Research for R3 of [`GOAL.md`](../GOAL.md). Tests the load-bearing claim in § *Problem*: "a directory
has no identity a shell can read." The claim is **correct and understated** — the tokens that exist
are worse than absent, because they are sound on the development machine and false on the filesystems
the wrapper runs on. Every number is labelled **measured** or **reasoned**. Nothing in the working
tree was touched; the probes were thrown away.

**Environment.** macOS 26.6.2 / APFS / `/bin/bash` 3.2.57 (the portability floor, and the platform
every local drive measures). Linux via Docker Desktop (`almalinux:9`, bash 5.1.8): `tmpfs`, genuine
`ext4` (`/dev/vda1 … type ext4`), and `xfs`/`ext4` on 400 MB loop images under `--privileged`. Lustre,
GPFS, NFS and btrfs were **not reached**.

## F1 — Token inventory (measured)

| Token | BSD `stat -f` | GNU `stat -c` | Stable for one instance? |
|---|---|---|---|
| inode | `%i` | `%i` | yes — but see F3 |
| device | `%d` | `%d` | yes |
| link count | `%l` | `%h` | **no** — moves when a subdirectory appears |
| mtime / ctime | `%m` `%c` | `%Y` `%Z` | **no** — tracks the entry list; why `uvm_age` moved to `owner` |
| birthtime (1 s) | `%B` | `%W` | yes, but see F4 |
| birthtime (sub-second) | `%FB` | `%w` (formatted) | different spellings, needs parsing |
| inode generation | `%v` → **`0`** on APFS | none | unusable |
| `ls -di` | yes | yes | identical to `%i` |

`stat -c` does not exist on macOS (`stat: illegal option -- c`) and `stat -f` means *filesystem* on
GNU, so any token needs the dual-flavor fallback `uvm_age` already carries (`bin/uv-manager:280`).

**A held fd is not a portable identity test.** `exec 9< "${lock}"` succeeds on both platforms. On
Linux `[[ /dev/fd/9 -ef "${lock}" ]]` is correct both ways — SAME while the instance stands,
DIFFERENT after `rmdir`+`mkdir` — a **zero-fork builtin identity test**. On macOS `/dev/fd/9` reports
the held inode but a *different device* (`3388406882` vs `16777231`), so `-ef` says DIFFERENT even for
the same instance: a guard built on it would never break a lock on macOS while working on Linux. That
is the silent platform-conditional degradation the GOAL's § *Non-goals* already refuses for the
`ps -o lstart=` leash.

## F2 — Cost (measured, APFS / bash 3.2, amortized over 200–300 reps)

Zero forks: `read -r x < owner` 40 µs · `[[ a == b ]]` 12 µs · `[[ -d ]]` 13 µs ·
`printf … > file` 96 µs.
Forking: `$(stat -f %i)` **1 540 µs** (2 forks) · dual-flavor `stat` **1 950 µs** ·
`$(ls -di)` 1 605 µs · `find … -inum … -delete` 1 884 µs (1 fork) · `rm -f` 1 545 µs · `rmdir`
1 495 µs.

In the Linux container `stat -c %i` cost 549 µs, so a cluster node sits nearer 0.5 ms per fork.
**bash 3.2 has no builtin path to an inode** — no `stat` builtin, and `-ef` is unusable per F1. A read
token costs one command substitution per wait-loop iteration, which the provisioning path can afford.
Cost is not what disqualifies it.

## F3 — Inode reuse: the disqualifying result (measured)

`mkdir X; stat; rmdir X` at one path, plus the race shape directly (judge A, remove it, let a fresh
winner `mkdir`, compare):

| Filesystem | consecutive-identical | distinct inodes | fresh winner presented the judged inode |
|---|---|---|---|
| APFS | 0 / 999 | 4 200 / 4 200 | 0 / 200 |
| tmpfs | 0 / 999 | 1 000 / 1 000 | — (strictly monotonic) |
| **ext4** | **999 / 999** | **1 / 1 000** | **200 / 200 (100 %)** |
| **xfs** | 0 / 499 | **13 / 500** | 0 / 400 at k=0–2, **150 / 400 (37 %) at k=3** |

- **APFS and tmpfs** allocate from a monotonic counter: 4 200 consecutive instances, zero reuse,
  strictly increasing. A token is sound *here*.
- **ext4 recycles deterministically and immediately.** Every cycle returned inode `7837`; 64
  intervening sibling create/removes did not perturb it; a 32-way concurrent burst produced 15
  successful `mkdir`s and **one** distinct inode. Widening the token does not help —
  `dev+ino+birthtime(%W)` false-matched **299 / 300** in the race shape, because the recycled inode is
  reissued inside the same second, and the race is milliseconds wide. (Reasoned mechanism: ext4's
  Orlov allocator prefers the parent's block group and takes the lowest free inode, so a freed
  directory inode is the next one handed out.)
- **xfs recycles from a rotating pool** — 13 distinct values across 500 instances, 124 non-monotonic
  steps, and a **periodic** false match: 0 % at k=0,1,2 and **37 % at k=3**. Under real churn the
  phase is arbitrary. The pool *size* is plausibly an artifact of a 400 MB image; the rotation is not.

**An inode token is sound exactly where R1's drive will measure it and false exactly where the wrapper
runs.** A fix resting on it passes every gate this repository can build and fails silently on a
cluster. Lustre's backing store is ldiskfs, an ext4 derivative — an inference, not a measurement, and
the worst-case one.

## F4 — Does a real token close the race, or narrow it? (reasoned from F2, amortized measurements)

No timer inside the interval — a `date +%s%N` boundary is itself a fork and over-reads by ~1.5 ms;
direct instrumentation gave 3 541 / 6 986 µs, consistent with the fork model:

- compare at `:458` → `owner` actually unlinked: **1 579 µs**
- compare → directory actually removed: **2 974 µs**
- the winner's own `mkdir` → `owner` write: **272 µs** (`invariants.md` §5 records 0.10 ms; method,
  not disagreement)

Two consequences the seed's account does not state:

1. **The destructive window is set by the breaker's forks, not the winner's gap** — 2.97 ms, ~11x the
   0.27 ms claim window. And `rm -f "${lock}/owner"` *re-empties* the directory, so a fresh winner
   that already completed its `owner` write is robbed anyway. Exposure is our own two `fork`+`exec`s.
2. **No token narrows that window.** Every candidate is read *before* the compare; compare-to-removal
   is `rm -f` plus `rmdir` and is identical in all of them. An inode gate *adds* 1.5–2.0 ms of fork
   ahead of the compare and leaves act-exposure unchanged.

**On the asymmetry, plainly: a real token does beat a vacuous one, and that does not make an inode
token the answer.** The `owner` gate's defect is that absent matches absent, admitting an unbounded
class of instances. A sound token admits exactly one and leaves only the 2.97 ms window — the right
shape. But soundness is the whole premise, and F3 shows the only readable token is unsound on the
target filesystems: on ext4 an inode gate admits every instance too, with no visible tell. Trading a
documented vacuity for an invisible, filesystem-dependent one is not progress.

## F5 — Is any primitive conditional on identity? (measured / reasoned)

| Primitive | At the floor | Conditional on identity? |
|---|---|---|
| `rmdir` | yes | no — by name; refuses non-empty (measured on APFS, ext4, tmpfs, xfs) |
| `rm -d` | yes on both (measured) | no — by name; refuses non-empty |
| `rm -rf` | yes | no, and discards the non-empty refusal |
| `find -maxdepth 0 -inum N -type d -delete` | BSD and GNU, **not POSIX** | inode-filtered, so no better than F3 allows — and its status is not portable: GNU rc=1 with `Directory not empty`, **BSD rc=0 silently**, directory left standing |
| `mv` family | ruled out | rejected on evidence; see the seed § *Problem* |
| `unlink(1)` | POSIX | files only |

**Nothing at any level removes a directory conditional on identity, and this is not a shell
limitation** (reasoned). POSIX has no `rmdir`-by-handle;
`unlinkat(dirfd, name, AT_REMOVEDIR)` resolves the *name*, so a C implementation has the identical
TOCTOU. `find -inum -delete` narrows the window to one process's stat-then-unlinkat and costs one
fork instead of two — a real narrowing, not a closure — but it cannot express "remove `owner` then
the directory, both only if identity holds", and its non-portable exit status leaves the
denied-break fall-through at `:469` unbranchable.

## F6 — The token a shell *can* hold: authored, not read (measured primitives)

A directory has no identity a shell can **read**. It can be given one the shell **writes**:

- `printf … > "${lock}/mark"` fails **rc=1, ENOENT** when the directory is gone, and costs **96 µs,
  zero forks**. `set -C` makes it `O_EXCL` (first rc=0, second rc=1). The failed-redirect diagnostic
  reaches the user's stderr unless `2>/dev/null` precedes the output redirect — the same left-to-right
  ordering documented at `bin/uv-manager:360`.
- **A fresh instance cannot inherit a mark**: after `rmdir`/`mkdir` the directory is empty. No reuse
  hazard, because the token is not drawn from a kernel-managed number space.
- **A mark pins the instance**: with one file inside, 32 concurrent rival `rmdir`s removed it
  **0 / 32** times. While the mark stands no other breaker can remove the directory, so no fresh
  instance can appear at the path, so everything read after the mark describes the instance that will
  be removed.

Reasoned, and TECH.md's business rather than this brief's: this converts the TOCTOU into a lock on
the lock, and inverts the vacuous case — an absent judged instance fails the *create* instead of
passing the compare. Its cost is the objection that killed the rename: a breaker killed between mark
and cleanup leaves an entry no trap sweeps, and `rmdir`'s refusal then makes the lock permanently
unbreakable, recoverable only through the timeout message's manual command. That needs a sweep rule.

## Limits

- **Lustre, GPFS and NFS were not reached.** Inode reuse is per-filesystem policy and does not
  transfer by argument; ldiskfs being ext4-derived is the strongest available inference and is still
  an inference. Settling it needs a real cluster scratch filesystem.
- **The xfs pool size (13) is from a 400 MB loop image** and is probably not representative; the
  rotation is the finding.
- **NFS attribute caching was not tested.** A cached inode number is as stale as a cached `owner`
  line, so it degrades a read token at least as far as F3 already does.
