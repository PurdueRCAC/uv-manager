# Research — enforcing `UVM_LOCK_TIMEOUT < UVM_LOCK_STALE`

Scope: R3, and the non-goal forbidding a new subcommand or environment variable. Every claim below
was measured, either by driving the working tree's script under
`.agents/factory/bin/temp_root.sh --offline` or by driving a patched copy in `$(mktemp -d)/probe`.
The working tree was not edited. bash 4.4 and 5.2 were reached through `docker run bash:4.4` /
`bash:5.2`; the local `/bin/bash` is 3.2.57, the portability floor.

## Conclusion

**Guard at the top of `uvm_acquire_lock`, before the `mkdir -p`, with a numeric-form check ahead of
the ordering comparison.** A prototype in that position passes `lint.sh`, parses under bash 3.2,
refuses the inverted and equal cases with exit 1, leaves a pre-existing foreign lock and its `owner`
file untouched, and leaves `help`, `--version`, `status` and the default ordering unchanged.

## 1. Placement

**Rejected: the knob assignment (`:164-167`).** Load time runs before `uvm_manager_main`'s
`help`/`--version` short-circuit at `:892-895`, so an inverted pair would take down the two commands
that document the knobs' defaults — `bin/uv-manager:878-879` is where a site reads that they are 180
and 600. That is the trap invariants.md §3 exists to prevent, transposed one variable over: the one
command that tells you how to fix the configuration is the one command the configuration stops you
running. Driven against the prototype, `uvm help` and `uvm --version` both still answer 0 under
`UVM_LOCK_TIMEOUT=60 UVM_LOCK_STALE=2`; a load-time guard forfeits that.

**Rejected: `uvm_init`.** It is called after the short-circuit, so §3 is satisfied, and two `(( ))`
tests are far below the 5 ms budget. It fails on scope instead. `uvm_init` resolves the root and the
platform key; validating an unrelated pair of knobs there is a second job in a high-blast-radius
function. Worse, it would refuse `uvm doctor` — the subcommand whose whole purpose is to report what
is wrong with a tree — for a misconfiguration `doctor` should be describing, not dying on. It also
puts the check on the `uv run` hot path to catch a condition that can only do harm elsewhere.

**Chosen: `uvm_acquire_lock`, first statement in the body.** The knobs are read at `:225` and `:233`
and nowhere else, so the guard sits against the code it protects and cannot drift away from it. It
costs the hot path nothing: `uvm_install` fast-paths at `:308` and never enters the function on a warm
tree. It cannot fire for `help`, `--version`, `status`, `versions` or `doctor`. `uvm install` with no
argument passes `force=1` and always acquires, so a site still has one command that reports the
misconfiguration on demand without a cold tree.

The accepted cost: a warm tree with inverted knobs runs indefinitely without complaint. The
misconfiguration surfaces on the first contended provisioning — which is the first moment it could
have caused the harm R3 names, and one call before the break at `:226`.

## 2. Non-numeric and empty values

Measured end-to-end against the unpatched wrapper with a foreign lock in place.

| `UVM_LOCK_STALE` | bash 3.2 | bash 4.4 / 5.2 | live lock |
| --- | --- | --- | --- |
| unset or empty | `${:-600}` treats empty as unset → 600 | same | survives |
| `abc` | `line 225: abc: unbound variable`, **exit 0**, no version on stdout | same message, **exit 1** | survives |
| `12x` | `((: 12x: value too great for base`, once per second for the whole wait; never stale; times out, exit 1 | same | survives |
| `' '`, `0`, `-1` | arithmetic 0 or negative → every lock instantly stale; breaks it, provisions, exit 0 | same | **deleted** |
| `0600` | arithmetic octal → 384 s | same | — |

Three things follow.

**Empty is already safe** and needs nothing; `:-` covers it.

**The whitespace and non-positive values reproduce R3's exact harm by another route.** Driven with
`UVM_LOCK_STALE=' '`: `breaking stale provisioning lock (8s old)`, install proceeded, lock GONE. An
ordering comparison catches all three for free, because they collapse to `timeout >= 0`.

**`abc` makes the guard itself unsafe unless the form is checked first.** `(( lock_timeout >=
lock_stale ))` with `lock_stale=abc` hits the same `set -u` unbound-variable fatality, one function
earlier. On bash 3.2 that fatality **exits 0**: the EXIT trap's own return status overrides the
error's. Confirmed with the wrapper's exact trap shape — bash 3.2 `rc=0`, bash 4.4 `rc=1`, bash 5.2
`rc=1`. So on the declared portability floor, an R3 guard written as a bare comparison silently
returns success and prints nothing, and `VER=$(uv --version)` comes back empty and true. Avoiding
that is not scope creep — it is the difference between a guard and a new silent-failure path — but
it does mean R3's implementation refuses non-numeric values, which the GOAL did not ask for. It
belongs in PLAN's deviation table.

`[[ ! "${lock_timeout}" =~ ^[0-9]+$ || ! "${lock_stale}" =~ ^[0-9]+$ ]]` is the minimum that works:
bash 3.2 supports `=~`, shellcheck is clean, and it rejects `abc`, `12x`, `' '`, `-1` and `18:0`. A
single `case` on the two values joined by `:` was tried first and is wrong — `UVM_LOCK_TIMEOUT=18:0`
slips through and dies at `:213` with an arithmetic syntax error. Leading zeros stay accepted and
stay octal: `0600` is 384 seconds at `:225` today, and the guard reading it the same way keeps the two
consistent. Normalizing with `10#` would have to be done at all three sites or none; that is a
separate defect and a candidate for `issues/`.

Arithmetic injection through the array-subscript form (`UVM_LOCK_STALE='a[$(cmd)]'`) is blocked on
both 3.2 and 5.2 — `set -u` kills it on the unbound `a` before the substitution runs. Nothing
executed. It is blocked only because `set -u` is on.

## 3. The message

Both guards use `die`, matching the timeout message's four-space continuation indent:

```
uv-manager: UVM_LOCK_TIMEOUT must be less than UVM_LOCK_STALE.
    UVM_LOCK_TIMEOUT=600  UVM_LOCK_STALE=600
    A waiter that outlives the stale threshold breaks the lock it is waiting
    for while the process holding it is still running. Lower the timeout or
    raise the stale threshold.

uv-manager: UVM_LOCK_TIMEOUT and UVM_LOCK_STALE must be whole numbers of seconds.
    UVM_LOCK_TIMEOUT=5  UVM_LOCK_STALE=abc
```

Both name both variables with their current values, which is what R3's *Checked by* requires.

On §7: `die` at `:41` is one `printf` and the timeout message at `:234-236` is already multi-line
through it, so the tension is pre-existing, not introduced here. It is also defensible. §7's rule is
justified by SIGPIPE, and the case it protects is `uvm_status | head` — a pipe on **stdout**. `die`
writes to stderr, which that pipe does not close. A single `printf` is also one write where a `cat`
heredoc is a fork, which matters when many ranks share a job log. Follow the neighbor: use `die`.
Record it in PLAN's deviation table so the reviewer does not read it as a fresh §7 violation.

## 4. Exit status and blast radius

`die` exits 1. An explicit `exit` is not subject to the bash 3.2 trap-override quirk in §2 — measured
`rc=1` on 3.2, 4.4 and 5.2 with the wrapper's trap shape in place.

The guard is the first statement in the function, ahead of `(umask 077; mkdir -p "${uvm_root}")` at
`:205` and the `while ! mkdir` loop, so it creates nothing and removes nothing. `uvm_lock` is still
empty when the EXIT trap fires, so `uvm_unlock` returns at `:178` without touching the filesystem.
Driven against the prototype with a foreign lock and `owner` file pre-placed: exit 1, `lock: PRESENT`,
`owner: PRESENT`, for the inverted, equal, `abc` and `18:0` cases alike. `--offline uv --version`
under the defaults still reports the fixture version and leaves `current -> versions/9.9.9`.

## 5. The same-commit surface

Three of the four files change; the modulefile does not.

- **`bin/uv-manager:878-879`** — the two `Environment:` lines describe the knobs independently. The
  heredoc's widest line is 81 characters and `:878` is already 78, so the constraint does not fit
  inline. Add one continuation line under the pair: `The timeout must be less than the stale
  threshold.` at the 22-column description indent.
- **`etc/uv-manager.conf.example:71-76`** — `# Seconds to wait for another process's provisioning
  lock.` and `# Seconds after which an untouched lock is assumed abandoned and broken.` are exactly
  the "documented and independently settable, with no note that one bounds the other" the GOAL cites.
  One sentence in the section, stating the constraint and that the wrapper refuses the inversion.
- **`README.md:551-552`** — the reference table rows `| UVM_LOCK_TIMEOUT | Seconds to wait for the
  provisioning lock. Default 180. |` and `| UVM_LOCK_STALE | Seconds after which an untouched lock is
  broken. Default 600. |`. Same defect, same fix. Recommended but not required: a Troubleshooting
  entry near `README.md:514`, where two other `die` messages are already quoted verbatim.
- **`share/modulefiles/uv/main.lua`** — no change. It mentions only `UVM_ROOT` (`:22`, `:119`) and
  `UVM_PIN` (`:129`); neither lock knob appears.

`AGENTS.md` and `.agents/factory/invariants.md` are not *forced*: R3 adds a constraint to §5 rather
than overturning one, and §5's existing bullet at `:81` stays true. Adding the ordering to that
bullet is still worth doing, and §12 says such an edit is graded on its merits inside the diff.

Not established
