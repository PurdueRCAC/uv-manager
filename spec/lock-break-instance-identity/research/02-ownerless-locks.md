# 02 — Owner-less locks: reachability, the acquire window, and the wedge

Read-only investigation of `uvm_acquire_lock`'s vacuous identity test at `bin/uv-manager:458`.
Everything below marked **measured** was driven on this machine (macOS 25 / APFS, `/bin/bash`
3.2.57, the only bash present) against a copy of the tree outside the working directory. Everything
marked **reasoned** was not.

## Findings first

1. **The wedge is real, and it is not hypothetical.** A one-line "refuse when the judged lock had no
   owner" patch turns every owner-less lock into a permanent outage that only a human `rmdir` clears.
   **Measured:** rc 1, empty stdout, one misleading break note, and the lock still standing.
2. **`main` manufactures owner-less locks itself.** A denied break strips `owner` and leaves the
   directory (GOAL R4). So the naive refusal does not merely inherit owner-less locks from old
   wrappers — it makes `main`'s own R4 residue permanent. **R4 is a prerequisite for any policy that
   refuses to break an owner-less lock, not a co-requirement.**
3. **The window is 2.7x wider than the invariant claims.** In situ, the lock stands with no readable
   `owner` for a **median 0.265 ms** (p10 0.239, p90 0.292, max 0.728 ms; n=40, sampled at 740 kHz).
   The documented 0.10 ms counts only the parent's redirect — measured at 0.060 ms here — and omits
   the interval between `mkdir(2)` completing in the forked child and the parent shell regaining
   control, which is the larger half.
4. **Age is the discriminator, and it is already computed.** A live winner inside its acquire window
   has a directory whose mtime is *now*; an abandoned owner-less lock has one older than
   `lock_stale`. Nothing else a shell can observe separates them.
5. **`[[ dir -ot mark ]]` is a fork-free way to re-test that age.** **Measured** at 0.0035 ms against
   1.596 ms for a `stat` fork — a 450x difference, and it works on bash 3.2.

## 1. Reachability inventory

| # | Origin | Reachable on `main`? | Construction |
|---|--------|----------------------|--------------|
| 1 | Live winner between `mkdir` (`:341`) and the `owner` write (`:343`) | **Yes**, 0.265 ms per acquisition (measured) | §2 |
| 2 | Owner write refused, directory removable | **No residue.** `:365-367` `rmdir`s then dies | §3 E |
| 3 | Owner write refused, directory *not* removable | **Yes, permanent** | §3 F |
| 4 | `owner` created but zero bytes (ENOSPC/EDQUOT: `creat` succeeds, `write` fails) | **Reasoned yes**, same residue as row 3 | `: > "$L/owner"` reads identically (§3 D) |
| 5 | Denied break — `rm -f owner` succeeds, `rmdir` denied (**GOAL R4**) | **Yes, permanent** | §3 A |
| 6 | Denied release in `uvm_unlock` (`:259-264`) — same two calls, same denial | **Yes, permanent** | same plant as §3 A, holder alive |
| 7 | Pre-0.6.0 wrapper (0.3.0–0.5.0), acquire window | **Yes**, and ~3.0 ms wide, because the owner line spends two command substitutions | `git show d4b84f3:bin/uv-manager` |
| 8 | Pre-0.6.0 wrapper, refused owner write | **Yes, for the whole hold.** All of 0.3.0/0.4.1/0.5.0 write `> "${lock}/owner" 2>/dev/null \|\| true` *after* the loop, so a refused write is silent and the holder installs with no `owner` at all | plant an owner-less dir; indistinguishable |
| 9 | `owner` unreadable (mode 000, ACL, foreign uid) | **Yes** — `read` fails, `holder=""` | §3 D |
| 10 | `owner` truncated | **No.** `read -r` returns 1 *with the data assigned*, so a partial line reads as **foreign**, not absent. Only a zero-length file is owner-less | — |
| 11 | `owner` is a directory | **Yes**, via row 3 | §3 F |
| 12 | Operator or restore — a human `mkdir`, an `rsync`/archive that recreated the mode-700 dir but not the mode-600 file, or the R1 drive's own plant | **Yes** | `mkdir "$L"` |

Rows 3, 5, 6, 8 and 11 are *permanent* on `main` in the sense that nothing removes them except the
stale breaker — which is exactly the mechanism a naive fix would disable.

## 2. Measured: the acquire window

Two independent estimators, both under `/bin/bash` 3.2.57 on APFS.

**In situ**, watching the real wrapper with a busy-polling observer (no `sleep`, so the 1.35 µs
sampling period bounds the error), 40 forced acquisitions in one sandbox:

```
# scratch/probe_window.pl busy-polls: -d "$lock" && ! -s "$lock/owner"
.agents/factory/bin/temp_root.sh --offline --arch probe sh -c '
  L="$UVM_ROOT/probe/.install.lock"
  perl /path/to/probe_window.pl "$L" 60 40 > out 2> err &
  pp=$!
  i=0; while [ $i -lt 40 ]; do uvm install >/dev/null 2>&1; i=$((i+1)); done
  wait $pp'
```

`n=40  min=0.0091  p10=0.2389  p25=0.2520  med=0.2649  p75=0.2789  p90=0.2921  max=0.7279` ms.
(`prober: windows=40 samples=7355479 rate=739604/s`. The 0.0091 ms minimum is a late first
observation, not a short window.)

**Batch-mean estimator** for the redirect alone — bash 3.2 has no `EPOCHREALTIME`, so this times
N=2000 `creat`+`write`+`close` calls into fresh directories and subtracts loop overhead, 40 batches:
`med=0.0597 ms` (min 0.0565, max 0.0671). This reproduces the invariant's 0.10 ms figure to within a
factor of two and shows what it leaves out.

**Per-encounter probability.** A waiter breaks at most once per `sleep 1`, so the naive figure is
**0.265 ms / 1 s = 2.7e-4** per break attempt per contending fresh winner.

**Reasoned:** that figure must not be used to size the R1 drive. Cycle 3 measured 41 of 61
concurrent installer entries for the owner-less plant; 2.7e-4 over 61 ranks and a few iterations
predicts ~0.05. The reconciliation is phase locking: the ranks start together and all sit on the
same `sleep 1` boundary, and against an owner-less plant *every* rank's identity test is vacuous, so
their `rm -f`/`rmdir` pairs fire in one cluster a few milliseconds wide. A 0.265 ms winner window
inside a ~5 ms cluster of 60 removals is a near-certainty, not a 1-in-4000 event. The rate to size
against is the observed ~0.7/rank under a burst, not the window fraction.

## 3. Measured constructions

All commands are verbatim and were run from the repo root. `--arch probe` keeps the plant in one
architecture directory; `UVM_LOCK_STALE`/`UVM_LOCK_TIMEOUT` go on the *inner* command because
`temp_root.sh` scrubs `UVM_*`.

**Baseline — `main` self-heals an owner-less aged lock (rc 0, `LOCK_AFTER=gone`):**

```sh
.agents/factory/bin/temp_root.sh --offline --arch probe sh -c '
  L="$UVM_ROOT/probe/.install.lock"; mkdir -p "$L"; touch -t 202001010000 "$L"
  UVM_LOCK_STALE=5 UVM_LOCK_TIMEOUT=2 uv --version; rc=$?
  echo "RC=$rc LOCK_AFTER=$( [ -d "$L" ] && echo present || echo gone )" >&2'
```
→ `breaking stale provisioning lock (…s old)` / `its owner file recorded: <none recorded>`,
then `uv 9.9.9 (fixture)`, `RC=0 LOCK_AFTER=gone`.

**A — the R4 state, and it is an owner-less-lock factory.** Plant an owner *and* a stray entry, aged:

```sh
.agents/factory/bin/temp_root.sh --offline --arch probe sh -c '
  L="$UVM_ROOT/probe/.install.lock"; mkdir -p "$L"
  printf "host=othernode pid=99999 nonce=123456\n" > "$L/owner"
  : > "$L/stray"; touch -t 202001010000 "$L/owner" "$L"
  UVM_LOCK_STALE=8 UVM_LOCK_TIMEOUT=4 uv --version; rc=$?
  echo "RC=$rc OWNER_AFTER=$( [ -e "$L/owner" ] && echo present || echo absent )" >&2'
```
→ break note naming `host=othernode pid=99999 nonce=123456`, then
`holder, from the lock's owner file: <none recorded>`, `RC=1 OWNER_AFTER=absent`, `stray` left.
**And the recovery command the message prints does not work in this state** —
`rm -f "$L/owner" && rmdir "$L"` returns `Directory not empty`, `RECOVERY=failed`. `invariants.md`
§5's "a recovery command that works" is already false here.

**D — empty and unreadable `owner` both break on `main`** (`: > "$L/owner"`, and
`chmod 000 "$L/owner"`, each aged): `RC=0 LOCK_AFTER=gone` for both.

**E / F — refused owner write.** A `mkdir` PATH shim intercepting `*.install.lock`:
`mkdir -m 500 "$a"` gives `Permission denied`, `cannot record ownership …`, `RC=1 LOCK_AFTER=gone`
— no residue. `/bin/mkdir "$a" && /bin/mkdir "$a/owner"` gives `Is a directory`, the same die, and
`RC=1 LOCK_AFTER=present` with `owner` reading empty — a permanent owner-less lock. F is the
constructible stand-in for row 4 (ENOSPC), which cannot be produced on APFS.

## 4. Measured: the wedge

A copy of the tree at `$probe/repo` with one edit — `:458` becomes
`if [[ -n "${holder}" && "${still}" == "${holder}" ]]; then` — driven against the baseline plant:

```
uv-manager: breaking stale provisioning lock (211044550s old): …/.install.lock
    its owner file recorded: <none recorded>
uv-manager: timed out after 4s waiting for provisioning lock: …/.install.lock
    holder, from the lock's owner file: <none recorded>
INNER_RC=1  LOCK_AFTER=present  OWNER_AFTER=absent
RECOVERY=ok
AFTER_RECOVERY_RC=0
```

Three things this establishes:

- **The outage is permanent and repeats per invocation.** rc 1, empty stdout,
  `VER=$(uv --version)` empty and false, `UVM_LOCK_TIMEOUT` (default **180 s**) burned per rank per
  call. Nothing in the wrapper ever removes the lock again.
- **The blast radius is cold provisioning only.** `uvm_install` fast-paths on `uvm_have` before
  taking the lock, so with `uv` already installed the same plant is harmless — **measured** rc 0,
  `uv 9.9.9 (fixture)`, lock left standing. The wedge bites a first use on a new architecture, a
  changed `UVM_PIN`, and `self update`; for a 1000-rank cold job that is the whole job.
- **The printed recovery command does work for a bare owner-less lock** (`RECOVERY=ok`: `rm -f` on
  an absent file succeeds, `rmdir` on an empty directory succeeds), and the next call provisions
  normally. So the escape hatch exists — it is just a human on a login node, which is not available
  to a rank inside an allocation. It does **not** work in state A above.
- The break note fires at `:452`, *before* the guard, so a refused break announces
  `breaking stale provisioning lock` and then times out. Whatever lands, the note has to move inside
  the decision or say something else.

## 5. Correct policy per origin

The asymmetry the invariant already states — a false leave is reclaimed by the stale breaker, a
false delete is bounded by nothing — inverts the moment the stale breaker is the thing being
disabled. So the policy cannot be "owner-less means unbreakable".

**Recommended policy: breakable, on re-verified age rather than on identity.** Rows 3–12 are all
locks nobody holds, and every one of them is only recoverable through the age net. Row 1 — the live
winner — is the only row that must be protected, and the evidence separating it from the rest is
observable, portable and already being computed: **the directory's own mtime**. A winner inside its
acquire window has a directory created microseconds ago; every other row has one older than
`lock_stale`. `uvm_age`'s directory fallback at `:435` is not a legacy concession, it is the
discriminator.

| Rows | Policy | Evidence at the floor |
|------|--------|----------------------|
| 1 (live winner) | **Never breakable** | directory mtime is within the current second; `uvm_age "${lock}"` returns ~0 |
| 3, 4, 11 (refused write residue) | Breakable once aged | directory mtime, unmoved since the failed acquire |
| 5, 6 (denied break/release) | Breakable once aged; **and R4 must stop creating them** | as above |
| 7, 8 (pre-0.6.0) | Breakable once aged | as above; no other evidence exists, the wrapper that wrote it is gone |
| 9 (unreadable `owner`) | Breakable once aged | `-e "${lock}/owner"` is true while `read` yields nothing — distinguishable from absent, but the verdict is the same |
| 10 (truncated) | Not owner-less; already handled as foreign | `read -r` assigns the partial line |
| 12 (operator/restore) | Breakable once aged | indistinguishable from 7/8 by design |

**What the fix has to add** is that the age be re-tested *immediately before* the removal, the way
`:457` re-reads `owner`. Today the forfeiture decision at `:435` is up to a second old and nothing
re-checks it, which is what makes the vacuous test the whole guard.

**Reasoned, for the plan to weigh:** a re-`stat` closes the window from ~1 s to the two forks
between the stat and the `rmdir` (1.3–2.7 ms), which is *wider* than the 0.265 ms it is protecting
against. A fork-free comparison does better. `[[ "${lock}" -ot "${mark}" ]]` is a bash 3.2 builtin —
**measured at 0.0035 ms against 1.596 ms for a `stat` fork** — where `mark` is a file `touch`-ed to
`now - lock_stale` once per wait iteration, outside the removal path. **Measured** semantics on bash
3.2: an aged directory is `-ot` the mark, a freshly created one is not, and the comparison is
whole-seconds only (two directories 1.4 ms apart are neither `-ot` the other), so the granularity
errs toward protecting a fresh winner. That is a candidate, not a recommendation; the plan owns the
mechanism.

## Limits

- Single machine, APFS, one bash. Nothing here says anything about Lustre, GPFS or NFS, and the NFS
  attribute-caching exposure the GOAL declares applies to an mtime re-read exactly as it does to an
  `owner` re-read.
- Row 4 (ENOSPC) is reasoned from row 11's construction, not produced.
- The phase-locking argument in §2 is reasoned from cycle 3's numbers, not measured here. R1's drive
  is where it gets settled.

## Appendix — the observer used in §2

Not committed anywhere; reproduced here so the measurement can be repeated. It busy-polls, because
any `sleep` at this resolution is the measurement.

```perl
#!/usr/bin/perl
use strict; use warnings; use Time::HiRes qw(time);
my ($lock, $secs, $want) = @ARGV[0,1,2];
my $deadline = time + $secs;
my ($n, $samples, $t0s) = (0, 0, time);
while (time < $deadline && $n < $want) {
  until (-d $lock) { $samples++; last if time > $deadline; }
  last if time > $deadline;
  my ($t0, $owner, $ok) = (time, "$lock/owner", 0);
  while (time < $deadline) {
    $samples++;
    my $sz = -s $owner;
    if (defined($sz) && $sz > 0) { $ok = 1; last; }
    last unless -d $lock;               # robbed before it could claim
  }
  my $t1 = time;
  printf "%.4f\n", ($t1-$t0)*1000 if $ok and $n++ > -1;
  while (-d $lock && time < $deadline) { $samples++; }
}
printf STDERR "prober: windows=%d samples=%d rate=%.0f/s\n",
  $n, $samples, $samples/(time-$t0s);
```
