# 06 — Filesystem semantics: what is measured, what is documented, what is assumed

## Findings

1. **Errno-discrimination is not available.** All seven `rmdir` failures constructed on APFS return
   **rc=1**, and POSIX defines only `0` / `>0` for the utility and leaves the diagnostic's wording
   unspecified. The raw errno *is* present in `rmdir`'s stderr — that is a real difference in kind
   from a failed shell redirect, which has no process to write one — but the only channel to it is
   locale- and vendor-dependent text. Do not branch on it.
2. **`mkdir` on NFSv3 and NFSv4.0 is documented not to give the winner self-attribution.** A rank
   that genuinely created the lock can be told `EEXIST`. That manufactures an owner-less lock with
   no live holder — the exact plant R3 must survive — from the transport rather than from an old
   wrapper. `invariants.md` §5's "`mkdir` is atomic on … NFS" is true of mutual exclusion and false
   of exactly-once.
3. **Under NFS the shipped re-read is fail-open in its dominant mode and fail-closed in the other,
   and an inode token is fail-closed in both.** Negative-dentry caching is the mechanism, and it is
   on by default. This makes an inode-based token *better*, not merely different.
4. **`find -inum … -delete` fails silently.** Measured: BSD `find` returned **rc=0, no stderr**, and
   left the non-empty directory standing. No shell-reachable primitive removes a directory by
   identity.

---

## 1. What a shell learns from a failed removal

**Measured on APFS** (`/bin/rmdir`, bash 3.2.57, Darwin 25.6.0) — every case `rc=1`:

| construction | stderr (BSD, `LC_ALL=C`) |
|---|---|
| absent (`ENOENT`) | `rmdir: <p>: No such file or directory` |
| `owner` inside (`ENOTEMPTY`) | `rmdir: <p>: Directory not empty` |
| path is a file (`ENOTDIR`) | `rmdir: <p>: Not a directory` |
| parent `r-x` or `---` (`EACCES`) | `rmdir: <p>: Permission denied` |
| trailing dot (`EINVAL`) | `rmdir: <p>: Invalid argument` |
| symlink to a directory | `rmdir: <p>: Not a directory` |

`mkdir` is the same shape: `EEXIST`, `ENOENT`, `EACCES` and `EEXIST`-on-a-file all give rc=1.
`rm -f` on a missing file is rc=0 silent; `rm -f` denied by the parent's mode is rc=1 with
`Permission denied`.

**Documented.** POSIX `rmdir` (utility): "0 — Each directory entry specified by a *dir* operand was
removed successfully. >0 — An error occurred", and "The standard error shall be used only for
diagnostic messages" — no per-reason status, no specified wording
([POSIX rmdir(1p)](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/rmdir.html)). POSIX
`rmdir()` does require `[EEXIST]` and `[ENOTEMPTY]` to have distinct values in `<errno.h>`, but the
shell never sees `errno`
([POSIX rmdir(3p)](https://pubs.opengroup.org/onlinepubs/9799919799/functions/rmdir.html)).

**Is a text branch sound?** A *single-errno probe* is reachable and still a bad trade. Measured:
`LC_ALL=C` plus `case $err in *"Directory not empty"*)` matches BSD `rmdir` (`rmdir: <p>: …`) and
GNU coreutils `rmdir` (`rmdir: failed to remove '<p>': …`) alike, because the sentence shapes differ
but the `strerror` tail does not. It costs a command substitution (one fork, ~1.9 ms measured here),
and without `LC_ALL=C` it breaks: glibc translates `strerror` and coreutils ships gettext catalogs,
so a cluster node with `LANG=de_DE.UTF-8` and `coreutils-lang` installed returns a translated tail.
This machine has no such catalogs, so the locale sweep here shows no variation and **does not
disprove the trap** — that row is documented, not measured.

The sound alternative is the discipline §5 already names: observe, do not interrogate. Measured
post-hoc classification on APFS is clean — after a refused `rmdir`, `ENOTEMPTY` leaves
dir-present=yes/owner-present=yes, `ENOENT` leaves dir-present=no, `EACCES` leaves dir-present=yes.
It is the *NFS* case where that observation is itself cached (§2).

## 2. NFS attribute and directory caching against the re-read at `:457`

**Documented** ([`nfs(5)`](https://man7.org/linux/man-pages/man5/nfs.5.html)):

- `acregmin`/`acregmax` default **3 s / 60 s**; `acdirmin`/`acdirmax` default **30 s / 60 s**.
- `lookupcache=all` is the default: "the client assumes both types of directory cache entries are
  valid until their parent directory's cached attributes expire." **Both types includes negative
  entries.** `lookupcache=pos` is what "always revalidates negative entries before an application
  can use them."
- Close-to-open "does not protect against races during concurrent file access" — verbatim, and
  exactly our situation.
- `noac` disables attribute caching *and* "forces application writes to become synchronous."

**Reasoned from those semantics.** Split the guard by case:

- **Owner-present.** A new holder's `owner` is a *new* file: the old one was unlinked, so the
  breaker's cached filehandle is stale, the read fails, `still` stays empty, `still != holder`, the
  break is declined. **Fail-closed.** The one write that keeps a filehandle valid is the heartbeat's
  in-place rewrite, and it writes byte-identical content by design.
- **Owner-less (the vacuous case, and 4.5x hotter per GOAL).** Absent matches absent. NFS makes it
  *worse than untested*: a fresh winner's `owner` is a positive entry the breaker's client may not
  see, because its cached **negative** dentry for `owner` stays valid until the parent's attributes
  expire. The local window GOAL measures at 0.10 ms becomes bounded by `acdirmin`..`acdirmax` —
  **up to 60 s at defaults**, the same order as the `UVM_LOCK_STALE/10` heartbeat beat. The same
  caching defeats `[[ -d "${lock}" ]]` at `:469` and the `absent` counter: a removed directory can
  still read as present, and a created one as absent.

**Inode token vs `owner` re-read — better.** Two reasons, both from documented behavior:

1. It has **no absent-matches-absent state**, provided an unreadable id is treated as a mismatch.
   That deletes the dominant failure mode outright.
2. Both NFS outcomes decline. Stale cached filehandle → `NFS4ERR_STALE`/`ESTALE` → empty token →
   mismatch. Cache expired, fresh `LOOKUP` → the new directory's fileid → mismatch.

Its residual needs *two* things at once: the server reusing the fileid **and** the client serving it
from cache. Measured on APFS, 200 create/delete cycles at one name gave **200 distinct file ids**,
monotonically increasing — but ext4, Lustre and GPFS reuse inode numbers, so the residual is not
zero off APFS. Cost, measured: one fork (~2.0 ms for `stat -f %i`; ~2.1 ms for the portable
`ls -id`), two on macOS because `uvm_age`'s `stat -c || stat -f` order fails first. Provisioning
path only, not the hot path. **And it does not make the removal instance-scoped** — `rmdir` still
names a path; the token narrows the window, it does not close it.

`noac`/`actimeo=0` is not a remedy available to us: it is a mount option, not an environment
variable, and it forces synchronous writes across everything under `UVM_ROOT`, including `uv`'s
cache. `lookupcache=pos` would close the negative half at far lower cost and is the one thing a
**site operator** could act on — a README note at most, out of scope here.

## 3. `mkdir` atomicity — two properties, not one

**(a) Mutual exclusion: at most one of N concurrent creators succeeds.** POSIX specifies the
`[EEXIST]` error, not "atomicity" — neither
[POSIX `mkdir()`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/mkdir.html) nor
[`mkdir(2)`](https://man7.org/linux/man-pages/man2/mkdir.2.html) contains an atomicity statement.
It holds because the server executes `MKDIR` against a local filesystem. Sound everywhere.

**(b) Self-attribution: the creator learns it created it.** **Documented not to hold on NFSv3 or
NFSv4.0.** `MKDIR` carries `GUARDED` semantics and, unlike `CREATE`, has no verifier mode
([RFC 1813 §3.3.9](https://www.rfc-editor.org/rfc/rfc1813.txt)); §3.3.8 states it plainly:

> Use of the GUARDED attribute does not provide exactly-once semantics. In particular, if a reply is
> lost and the server does not detect the retransmission of the request, the procedure can fail with
> NFS3ERR_EXIST, even though the create was performed successfully.

The duplicate request cache that would cover it is optional and bounded — §4.5: "**Most** NFS
version 3 protocol server implementations use a cache of recent requests"; "This mechanism, however,
does not guarantee against these destructive side effects in all failure modes… A network partition
can cause a cache entry to be reused before a client receives a reply." NFSv4.0 relies on the same
DRC ([RFC 7530 §16](https://www.rfc-editor.org/rfc/rfc7530.txt)). **NFSv4.1 and later hold:**
[RFC 5661 §2.10.6](https://www.rfc-editor.org/rfc/rfc5661.txt) — "Each COMPOUND … sent with a
leading SEQUENCE … **MUST** be executed by the receiver exactly once" — with the same GUARDED
caveat preserved for sessionless use ("Unless a persistent session is used, use of the GUARDED4
attribute does not provide exactly once semantics").
[`mkdir(2)`](https://man7.org/linux/man-pages/man2/mkdir.2.html) NOTES corroborates in one line:
"There are many infelicities in the protocol underlying NFS. Some of these affect `mkdir()`."
`open(2)` gives the documented cure and it is not `mkdir`: "Portable programs that want to perform
atomic file locking using a lockfile, and need to avoid reliance on NFS support for **O_EXCL**, can
create a unique file on the same filesystem (e.g., incorporating hostname and PID), and use
[`link(2)`](https://man7.org/linux/man-pages/man2/link.2.html) to make a link to the lockfile."

**Consequence for this cycle, and it is the major finding.** On NFSv3/v4.0 a rank whose `mkdir` was
retransmitted after a lost reply gets `EEXIST`, skips the `robbed` retake (the directory *is*
there), reads no `owner` (it never wrote one), takes `pid=""` so the liveness probe cannot fire,
waits out `UVM_LOCK_TIMEOUT` on a lock of its own making, and dies. The state it leaves behind is a
fresh owner-less lock with no live holder. **The owner-less plant is not a legacy tail; it is a
production mode of the deployment target.** R3's insistence on covering it is load-bearing, and
whatever lands must not rely on the judged instance having recorded anything.

**Lustre and GPFS: documented by absence, not asserted.** Lustre's FAQ frames its own position —
"POSIX does not, strictly speaking, say anything about how a file system will operate on multiple
clients. However, Lustre conforms to the most reasonable interpretation of what the single-node
POSIX requirements would mean in a clustered environment" — and names exactly two exceptions, lazy
`atime` and configurable `flock`/`lockf`
([Lustre FAQ](https://wiki.lustre.org/Frequently_Asked_Questions)). IBM's "Exceptions to Open Group
technical standards" lists only `stat()` timestamp inaccuracy and `du`/`df` staleness
([IBM Storage Scale](https://www.ibm.com/docs/en/storage-scale/5.2.1?topic=applications-exceptions-open-group-technical-standards)).
Neither excepts `mkdir`, `rmdir` or directory-entry atomicity — but neither asserts them either.
Property (a) is entailed by the compliance claim; property (b) is a *transport* question and does
not arise for either, since both are native clients rather than RPC-retransmit protocols.

## 4. A shell-reachable conditional removal — survey

**Measured on APFS:**

| primitive | result |
|---|---|
| `find <d> -inum N -type d -delete` | **rc=0, no stderr, directory still present** when non-empty. `-print` matched. Silent failure; unusable as a gate. `-delete` is also name-based (`unlinkat` on the parent fd), so it re-resolves rather than acting on the id. |
| `mv a b` where `b` is a directory | rc=0, `a` moved *inside* `b`. Confirms GOAL's rejection of the rename family at the floor. |
| `ln src tgt` (hard link) | first rc=0; second **rc=1 `File exists`**; `st_nlink` 1→2. |
| `ln -s payload tgt` | first rc=0; second rc=1 `File exists`; identity readable in one `readlink`. |
| `set -C; : > f` | second rc=1 `cannot overwrite existing file` (`O_CREAT\|O_EXCL`). |
| `rmdir parent` with a **child directory** inside | rc=1 `Directory not empty`; `rmdir child && rmdir parent` rc=0. |
| `stat -c %i` | `illegal option` on macOS. `stat -f %i` and `ls -id` both work; `ls -id` is the one spelling portable across BSD and GNU. |

`unlinkat(AT_REMOVEDIR)` has no shell front-end that accepts a directory fd; reaching it needs a
helper binary, which §5 rules out.

**What R6 costs us.** The documented cure for finding 2 is `link(2)` — `open(2)` says so in as many
words — and the cure for the vacuous case is an identity carried *in the entry name* (`ln -s`, whose
payload is the owner line, read in one `readlink` with no separate file to be absent). Both are
forbidden by R6 and §5. The price is specific and worth stating: **we keep a primitive that is
documented not to tell its winner it won on the majority-deployed NFS versions**, and we keep an
identity in a file that can be absent. Neither is a reason to overturn R6 — `flock` unavailability
and helper-binary-freedom are the stated reasons and they still hold — but the plan should carry
the cost rather than inherit it silently.

**One shape that keeps `mkdir` and still removes the vacuous case** (an observation for the plan and
topic 01, not a recommendation — mechanism is the plan's call). A holder does
`mkdir "${lock}" && mkdir "${lock}/held.<nonce>"`. The nonce lives in a **directory entry name**, so
a breaker that judged `held.<nonceA>` removes *that* name — `rmdir "${lock}/held.<nonceA>"` fails
`ENOENT` when the instance is gone, and only then may `rmdir "${lock}"` succeed. The removal is
name-qualified on the identity itself, needing no re-read, and there is no state that can be
absent-and-match. It costs one `mkdir` and one `rmdir` per acquisition, it keeps `rmdir`'s
`ENOTEMPTY` refusal as the second half of the guard, and it inherits the same NFSv3
non-idempotency for the inner `mkdir`. Under NFS it also inherits negative-dentry caching on the
`held.*` lookup — the same exposure as everything else in this section.

## 5. The boundary

| Safety property the lock depends on | Status | What would discharge it |
|---|---|---|
| `rmdir` gives no per-errno exit status; wording is unspecified | **Measured** (7 constructions, APFS) + **documented** (POSIX `rmdir(1p)`) | — |
| `Directory not empty` tail is stable across BSD and GNU under `LC_ALL=C` | **Measured** (3 binaries) | — |
| That tail is translated under a non-C locale on glibc | **Documented** (glibc `strerror` + coreutils gettext); **not measured** — no catalogs installed here | A Linux node with `coreutils-lang` and `LANG=de_DE.UTF-8` |
| At most one of N concurrent `mkdir`s succeeds (mutual exclusion) | **Documented** for POSIX; **entailed** by Lustre's and GPFS's compliance claims; **assumed** on each in the specific | A concurrent-`mkdir` drive on each filesystem |
| A winning `mkdir` learns it won (exactly-once) | **Documented FALSE** on NFSv3 / NFSv4.0; **documented TRUE** on NFSv4.1+ sessions | — (settled; the fix must not depend on it) |
| `rmdir` refuses a non-empty directory — the second half of the `:457` guard | **Measured** (APFS) + **documented** (POSIX `[ENOTEMPTY]`) | Confirm on Lustre/GPFS/NFS; `nfs(5)` documents no exception |
| A re-read of `owner` reflects another client's write | **Assumed**, and **documented to be violable**: CTO "does not protect against races during concurrent file access" | A two-client NFS drive with default `actimeo` |
| A fresh winner's `owner` is visible to a breaker within the acquire window | **Assumed FALSE on NFS**: negative dentry valid until the parent's attributes expire, `acdirmin` 30 s / `acdirmax` 60 s at defaults | A two-client NFSv3 drive; or `lookupcache=pos` at the site |
| `[[ -d "${lock}" ]]` at `:469` and the `absent` counter observe the server's truth | **Assumed**; same attribute-cache exposure | Same drive |
| A directory's fileid is a usable instance identity | **Measured** APFS: 200/200 distinct, monotone. **Assumed** off APFS — ext4/Lustre/GPFS reuse inode numbers | A create/delete cycle count on each filesystem |
| An unreadable/stale fileid fails closed | **Reasoned** from `ESTALE` on a stale filehandle; **assumed** | Two-client NFS drive |
| R1's drive on APFS is evidence a fix works on a parallel filesystem | **FALSE — stated as such in GOAL.** It bounds what the sandbox can see | A real allocation |
| Per-call fork cost on the provisioning path (~1.9 ms baseline, ~2.0 ms `stat -f %i`) | **Measured** on this machine only; load-dependent | The timing A/B deferred to `issues/test-harness.md` R7 |
