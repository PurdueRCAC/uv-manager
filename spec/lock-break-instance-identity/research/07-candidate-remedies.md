# 07 — Where the owner plant's signal comes from, and which remedy closes it

Follow-up to [`04`](04-concurrency-drive.md), using its drive. Everything marked **measured** was
driven on this machine (macOS 25 / APFS, Apple silicon, `/bin/bash` 3.2.57) against out-of-tree copies
of the tree at `634caaa`. Nothing tracked was touched. Totals: **23 552 planted ranks** across an
instrumented `main` and six candidate compositions.

**The `-ot` correction is confirmed and applied throughout.** On bash 3.2.57
`[[ MISSING -ot existing ]]` is **TRUE** and `[[ -d nosuchdir && nosuchdir -ot existing ]]` is FALSE.
Every age test below is written `[[ -d "${lock}" && "${lock}" -ot "${mark}" ]]`; a bare `-ot` passes
exactly when the instance is already gone.

## Findings first

1. **The fatal branch at `:361-364` owns none of the owner plant's signal. The break block owns all of
   it.** The coordinator's hypothesis is **refuted**. **Measured** over 7680 planted ranks: `:363` was
   entered **once** and its `rmdir` **failed**, destroying nothing; the break block at `:459-460`
   performed 170 successful `rmdir`s, of which 50 removed a rank-created instance — accounting for all
   48 observed robbery events, per burst. **An owner-plant gate asserting zero can go green from a fix
   confined to the break block.** Write it.
2. **`:363` is nearly unreachable by construction, not by luck.** It requires our own `mkdir` to have
   succeeded, our `owner` write to have failed ENOENT, *and* a third rank to have re-`mkdir`'d inside
   that window — and then `rmdir` still refuses as soon as that rank writes its own `owner`. Its reach
   is the square of a 0.27 ms window. This **corrects `05` §5**, which measured it twice in 1280 ranks.
3. **No pre-removal predicate can close this race, and C1 alone measurably does not.** The exposure is
   between the predicate and the `rmdir`, not before the predicate — `01` F4 said so and the drive now
   shows it. **Measured:** C1 moved the owner-less plant 4.2% → 1.7% and the owner plant 0.43% → 0.31%.
   Narrowing, not closure.
4. **The smallest composition that goes green is C1 + C2″ + C3, and all three are load-bearing.**
   **Measured:** zero stolen holds, zero robbed winners, zero concurrent installers across
   `none×12 + owner×40 + control×5` (3648 ranks), progress ok, wall clock unchanged at 103 s. So C2 is
   **necessary**, not merely available.
5. **Dropping C1 wedges the lock.** C2″+C3 without C1 scored zero on every race counter and then
   **left one burst in 40 with a lock standing and 64 ranks timed out**. C1's age test is what keeps
   the pin off a live holder's directory; without it the pin lands inside a live hold, that holder's
   own `rmdir` is refused, and an empty directory with a fresh mtime is left at the path — which
   nothing reads as stale and no rank can break.
6. **My own drive had a false green, and finding 5 is why the fix matters.** The first C2 ordering made
   every break decline: 768/768 ranks timed out, zero installs, a lock left standing in all 12 bursts —
   and the drive **exited 0**, because all three race counters were legitimately zero. The drive now
   asserts progress (≥1 installer entry per burst, zero locks left standing, zero non-zero ranks) and
   exits **4** with `progress=` naming the failure. Without it, a gate rewards a candidate that
   deadlocks the lock.
7. **C2's ordering is load-bearing and non-obvious: the pin must come after the age test.** Creating an
   entry inside the directory bumps its mtime, so a pin placed before C1's comparison makes that
   comparison unsatisfiable forever. That is finding 6's deadlock.
8. **C3's predicate needs no `dotglob`.** Explicit dot patterns (`"${lock}"/.[!.]*`, `"${lock}"/..?*`)
   decline the stray dot-entry with no global shell state. **Measured** on bash 3.2 across eleven
   states. The `[[ -e || -L ]] || continue` guard is load-bearing: with `nullglob` unset a
   non-matching pattern expands to itself.
9. **R7 survives every candidate.** **Measured** exactly one break note and one timeout message per
   wait in all six constructions on all six wrappers. R4 goes green: `owner` survives every denied
   break and the message names the holder.
10. **C2 has three measured costs, all fixable, and one residual.** A repeated raw shell diagnostic
    (~180 lines at the default timeout), an orphaned pin that wedges the lock, and a recovery command
    that stops working. All three are fixed in C2″. The residual is an orphaned pin from another node.

## Q1 — measured: per-site attribution of the removals

Instrumented `main` logs, at each removal site, the `rmdir` exit status. Logging is **after** the
removals, so the destructive window is not widened. Attribution is by counting rather than by reading
the victim: the planted lock accounts for exactly one successful removal per burst, so every
additional successful `rmdir` in that burst removed a directory a rank created.

| plant | bursts × ranks | S1 (`:459-460`) successful `rmdir` | − planted | S2 (`:363`) entered | S2 successful | stolen | robbed | stolen+robbed | bursts where extra ≠ events |
|---|---|---|---|---|---|---|---|---|---|
| `owner` | 120 × 64 = 7680 | 170 | **50** | **1** | **0** | 28 | 20 | 48 | 2/120 |
| `none` | 20 × 64 = 1280 | 78 | **58** | **1** | **0** | 48 | 10 | 58 | **0/20** |

The per-burst correlation is what makes this decisive rather than aggregate: in 138 bursts the extra
removals matched stolen+robbed exactly in 136. The two owner-plant misses are each one extra removal
with no reported victim — a removal of an instance whose `owner` a previous breaker had already
stripped, which destroys nothing anyone was relying on.

**A method note worth recording, because it nearly produced the wrong answer.** The instrumentation
first read the victim's `owner` line immediately *before* the `rm -f` and classified it. That
classified 169 of 170 removals as "the planted instance" and reported zero live-rank victims — because
the read happens before the substitution it is trying to observe. It measures what the breaker
believed, not what it destroyed. The counting argument has no such instant.

## Q2 — measured: the candidate matrix

64 ranks per burst throughout. `stolen` / `robbed` / `concurrent` as defined in `04`. `progress` is
the new assertion: ≥1 installer entry per burst, no lock left standing, no non-zero rank.

| wrapper | `none×12` (768 ranks) | `owner×40` (2560 ranks) | `control×5` | progress | wall |
|---|---|---|---|---|---|
| **`main`** (634caaa) | 32 / 8 / 32 | 11 / 3 / 11 | 0 / 0 / 0 | ok | 103 s |
| **C1** | 13 / 4 / 13 | 8 / 5 / 8 | 0 / 0 / 0 | ok | 104 s |
| **C1+C3** | 9 / 0 / 9 | 6 / 4 / 6 | — | ok | 94 s |
| **C1+C2+C3** — pin *before* the age test | 0 / 0 / 0 | — | — | **FAIL: 768 timeouts, 12/12 locks left** | 74 s |
| **C2″+C3** — C1 dropped | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | **FAIL: 1/40 bursts wedged, 64 timeouts** | 86 s |
| **C1+C2″+C3** | **0 / 0 / 0** | **0 / 0 / 0** | **0 / 0 / 0** | **ok** | **103 s** |

`C1b` (re-run `uvm_age` instead of `-ot`) and `C1r` (identity test removed) were built and left
unmeasured when the budget ran out — see *Untested*. `C4` (a guard on `:363`) was built and is
**not needed**: finding 1 removes its motivation.

### Measured: R4 / R7 and the orphan matrix

`UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=5`, one rank, lock aged to 2020.

| construction | `main` | C1+C2″+C3 |
|---|---|---|
| aged, removable (control) | rc 0, provisions, 1 note | rc 0, provisions, 1 note |
| stray entry | rc 1, 1 note, **`owner` GONE**, `<none recorded>` | rc 1, 1 note, **`owner` present**, holder named |
| stray **dot**-entry | rc 1, 1 note, **`owner` GONE**, `<none recorded>` | rc 1, 1 note, **`owner` present**, holder named |
| orphaned pin, dead local pid | — | **rc 0, swept, provisions** |
| orphaned pin, foreign host | — | rc 1, wedged, 0 stderr leaks, advice names `mark` |
| orphaned pin, no identity recorded | — | rc 1, wedged — **unsweepable**, see below |

### Measured: C2's costs

- **A repeated raw shell diagnostic.** `set -C; : > "${lock}/mark"` on an existing mark emits
  `bin/uv: line 487: …/mark: cannot overwrite existing file` **once per wait iteration** — 3 lines in a
  2 s wait, so ~180 at the shipped default. `2>/dev/null` **before** the output redirect suppresses it
  (measured: rc 1, no message), which is the ordering already documented at `bin/uv-manager:360`.
- **An orphaned pin wedges the lock permanently.** A breaker killed between the pin and its cleanup
  leaves an entry no trap sweeps; `rmdir` then refuses for everyone. The sweep that works is the one
  the function already contains: write `${owner}` into the mark, and on EEXIST probe the recorded pid —
  same host and gone means sweep. **Measured:** full recovery, rc 0, provisions. No new bound, and
  recovery is immediate rather than a stale window away.
- **The mark must carry identity.** A pin created with `: >` records no pid and cannot be swept, so
  it wedges the lock exactly as the un-swept version did. `printf '%s\n' "${owner}"` costs the same one
  redirect.
- **The advised recovery command stops working.** `rm -f '<lock>/owner' && rmdir '<lock>'` fails
  `Directory not empty` while a mark stands. It must become
  `rm -f '<lock>/owner' '<lock>/mark' && rmdir '<lock>'` — measured working.

### Measured: C1's cost

C1's per-iteration reference file is left behind. After one ordinary offline drive the architecture
directory contains `.install.mark.49739`, one file per pid that ever contended, accumulating in the
user's own tree forever. It needs cleanup: `rm -f "${mark}"` on the loop's exits, or a global the EXIT
trap clears. Dropping C1 removes the litter and re-opens finding 5's wedge, so the litter has to be
paid for rather than avoided.

## Q3 — the break note

**Measured:** the note at `:446-447` fires before the guard, so a break that is then declined still
announces `breaking stale provisioning lock` and times out two lines later. Every candidate declines
more often than `main`, so the note is misleading more often — `C1+C2″+C3` emitted 151 notes across
40 owner-plant bursts where only 40 breaks succeeded.

**Recommendation: leave the note where it is and reword it.** Moving it inside the decision costs R7's
contract — one note per wait is what stops 180 identical lines, and a note emitted after a successful
removal cannot report the `owner` line it just deleted, which is the note's entire purpose
(`invariants.md` §5). Reword from an accomplished act to an attempted one, and let the timeout message
be the record of what happened:

```
uvm-manager: provisioning lock is forfeit and will be broken (211062573s old): <lock>
    its owner file recorded: host=… pid=… nonce=…
```

**R7 holds either way** — exactly one note and one timeout per wait, measured on all six wrappers
across all six constructions. The wording is not quoted in `README.md`, `uvm_help`,
`etc/uv-manager.conf.example` or the modulefile, so the same-commit obligation is `invariants.md` §5
and `AGENTS.md`'s copy of it.

## The recommended composition, as source

Ordering is the whole design: **age, then pin, then verify, then remove.**

```bash
# C1's reference, at the top of every wait iteration, before the mkdir attempt.
# Per-pid: a shared mark another rank bumps forward reopens the hole it closes.
: > "${mark}" 2>/dev/null || true
```

```bash
      still=""
      read -r still 2>/dev/null < "${lock}/owner" || true
      # -d first is not decoration: bash 3.2 reports [[ MISSING -ot existing ]]
      # TRUE, so a bare -ot passes exactly when the instance is already gone.
      # The age test runs before the pin, because creating an entry inside the
      # directory bumps its mtime: pin first and this comparison can never pass
      # again. Measured — that ordering declined every break, timed out every
      # rank, and left the lock unbreakable.
      if [[ "${still}" == "${holder}" && -d "${lock}" && "${lock}" -ot "${mark}" ]]; then
        # A breaker killed between the pin and its cleanup leaves a mark no trap
        # sweeps, and rmdir then refuses forever. Sweep it the way the lock
        # itself is swept, by probing the pid it records — no new bound, and
        # recovery is immediate rather than a stale window away. A mark from
        # another node is left standing and the timeout message names it.
        _pin=""
        read -r _pin 2>/dev/null < "${lock}/mark" || true
        if [[ -n "${_pin}" && "${_pin%% *}" == "host=${host}" ]]; then
          _ppid="${_pin#*pid=}"; _ppid="${_ppid%% *}"
          if [[ -n "${_ppid}" && -z "${_ppid//[0-9]/}" ]] \
             && ! kill -0 "${_ppid}" 2>/dev/null; then
            rm -f "${lock}/mark" 2>/dev/null || true
          fi
        fi
        # Pin the instance. set -C makes the redirect O_EXCL: it fails ENOENT
        # when the instance is already gone and EEXIST when another breaker
        # already owns this break. While the mark stands no other rank's rmdir
        # can succeed and no mkdir can put a new instance at the path, so what
        # is removed below is what was judged above. 2>/dev/null precedes the
        # output redirect for the reason documented at the owner write.
        set -C
        if printf '%s\n' "${owner}" 2>/dev/null > "${lock}/mark"; then
          set +C
          _post=""
          read -r _post 2>/dev/null < "${lock}/owner" || true
          if [[ "${_post}" == "${still}" ]] && uvm_lock_removable "${lock}"; then
            rm -f "${lock}/owner" "${lock}/mark" 2>/dev/null || true
            rmdir "${lock}" 2>/dev/null || true
          else
            rm -f "${lock}/mark" 2>/dev/null || true
          fi
        else
          set +C
        fi
      fi
```

C3's predicate, unit-tested on bash 3.2 across eleven states (removable: empty, `owner` only,
`owner`+`mark`, restored; declined: stray file, stray dot-file, subdirectory, dangling symlink, lock
mode 500, parent mode 500, lock absent):

```bash
uvm_lock_removable() {
  local lock="$1" e
  [[ -d "${lock}" ]] || return 1
  [[ -w "${lock}" && -w "${lock%/*}" ]] || return 1
  # Dot-entries need their own patterns: a bare glob cannot see them, and a
  # stray dot-file is what makes rmdir refuse invisibly. shopt is global state
  # in a script that globs elsewhere, so dotglob is not an option.
  for e in "${lock}"/* "${lock}"/.[!.]* "${lock}"/..?*; do
    [[ -e "${e}" || -L "${e}" ]] || continue
    case "${e##*/}" in
      owner|mark) ;;
      *) return 1 ;;
    esac
  done
  return 0
}
```

C3's (e): keep the decided line, and change the message to past tense.

```bash
    read -r holder 2>/dev/null < "${lock}/owner" || true
    [[ -z "${holder}" ]] || last_holder="${holder}"
...
    holder, as the lock's owner file recorded it: ${last_holder:-<none recorded>}
    A pid recorded there is on that host, not this one. If it is gone, remove the lock:
        rm -f '${lock}/owner' '${lock}/mark' && rmdir '${lock}'
```

## The drive's progress assertion (lift this into `tests/`)

```sh
# Progress, asserted before any race verdict. A candidate that declines every
# break makes the lock unbreakable: every rank times out, nothing installs, and
# the race counters are all legitimately zero. Measured on a composition that
# did exactly that, and the drive reported rc 0 — a false green is worse than
# no gate.
progress=ok
[ "$t_inst" -ge "$bursts" ] || progress="only $t_inst installer entries for $bursts bursts"
[ "$t_left" -eq 0 ]         || progress="$t_left/$bursts bursts left a lock standing"
[ "$t_nonzero" -eq 0 ]      || progress="$t_nonzero rank(s) exited non-zero"
printf 'progress=%s\n' "$progress"
if [ "$progress" != ok ]; then
    echo "lock-race.sh: the wrapper did not make progress -- this is not a race result" >&2
    exit 4
fi
```

`t_left` comes from one line the burst script adds after its `wait`:
`[ -d "$lock" ] && : > "$LOCKRACE_DIR/leftlock.$tag"`. Exit **4** is a new code, distinct from 1 (race
observed) and 3 (collection untrustworthy).

## Reasoned

- **Why the pin closes what a predicate cannot.** Every predicate is evaluated before the removals and
  the exposure is the two forks after it. The pin is not evidence, it is an occupancy: while our mark
  stands no other rank's `rmdir` succeeds and no `mkdir` can create an instance at the path, so the
  path cannot change identity between the judgment and the act. The residual window is between our
  `rm -f` and our `rmdir`, and another breaker arriving there pins the emptied directory itself, which
  makes *our* `rmdir` fail rather than letting a fresh winner appear. Measured zero at 3648 ranks;
  the argument is what says it is zero rather than rare.
- **`set -euo pipefail` is at `bin/uv-manager:19`.** The pin's redirect is inside an `if` condition so
  its failure is not fatal, and `set +C` runs on both branches. `_pin`, `_ppid` and `_post` must be
  declared `local` in the shipped form; as prototyped they leak globals.
- **NFS is untouched by any of this.** The post-pin re-read of `owner` has the same attribute-cache
  exposure the GOAL already declares, and the pin's O_EXCL create depends on NFS exclusive-create
  semantics, which this machine cannot exercise. C2 adds a dependency the shipped code does not have.
- **`:361-364` still deserves its seed.** Finding 1 says it is not this cycle's signal; it does not
  say the branch is correct. `[[ -d "${lock}" ]]` remains a path test, and the honest reading is that
  removing only what is still ours to remove means removing nothing, because this process never
  recorded ownership. That belongs in `issues/lock-owner-write-errno.md`, unchanged in scope.

## Untested — declared, not hidden

- **C1b** (`uvm_age` re-run in place of `-ot`) and **C1r** (identity test removed) were built and never
  run. `01` F4 predicts C1b measures the same as C1 and costs one fork, which would make the mark file
  and its litter avoidable; that prediction is unverified and it changes the diff materially.
- **The `none×12` cell for `main`** is quoted from `04`'s run, not re-measured under the progress guard.
- **A live breaker's pin is never observed being swept.** The pid-probe sweep cannot fire on a live
  local pid by construction, but no drive constructed a breaker that survives one wait iteration.
- **The recommended composition has not been run at the sizing brief's full false-green budget** — 40
  owner bursts gives 3.5e-4 at the measured `main` rate, which is the `04` recommendation, but a green
  result deserves the 70-burst run before a human signs it off.
- **Cross-node anything.** One machine, APFS.
