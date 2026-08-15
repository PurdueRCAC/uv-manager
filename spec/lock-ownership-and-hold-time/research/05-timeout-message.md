# 05 — The timeout message and the stale-break note (R5)

Baseline captured by driving the real wrapper to a lock timeout under `temp_root.sh`, and a
replacement drafted and driven in a copy outside the working tree. Nothing in the working tree was
modified.

## 1. Pre-change baseline, verbatim

Drive: a lock directory created by hand with a foreign `owner` line, `UVM_LOCK_TIMEOUT=2`,
`UVM_LOCK_STALE=600` so the stale breaker cannot fire first.

```
.agents/factory/bin/temp_root.sh --offline --arch testarch sh -c '
mkdir -p "$UVM_ROOT/testarch/.install.lock"
printf "host=node0042 pid=12345 time=%s\n" "$(date +%s)" > "$UVM_ROOT/testarch/.install.lock/owner"
UVM_LOCK_TIMEOUT=2 UVM_LOCK_STALE=600 uv --version'
```

stderr, exit 1 (`<lock>` stands for the sandbox path, printed in full both times):

```
uv-manager: timed out after 2s waiting for provisioning lock: <lock>
    If no other uv process is provisioning, remove it with:
        rmdir '<lock>'
```

The stale-break note, driven with `UVM_LOCK_STALE=2` and a 3 s-old lock:

```
uv-manager: breaking stale provisioning lock (4s old): <lock>
```

It names neither the owner it is deleting nor the host and pid recorded inside it, and the drive
confirms the breaker then provisioned normally (`uv 9.9.9 (fixture)`, rc 0).

## 2. The advised recovery command does not work

`rmdir '<lock>'` fails whenever the holder got as far as `:242-243`, which is every successful
acquisition:

```
rmdir: …/lock: Directory not empty
rmdir rc=1
```

The `owner` file is inside the directory the message tells the user to `rmdir`. So the message is not
merely under-informative — for the abandoned-lock case it is written for, it hands the user a command
that fails. Any R5 rewrite has to fix this; a message that names `owner` and still says bare `rmdir`
is self-contradicting.

## 3. Proposed replacement, verbatim

```
uv-manager: timed out after 180s waiting for provisioning lock: <lock>
    holder, from the lock's owner file: host=node0042 pid=12345 time=1786810172
    A pid recorded there is on that host, not this one. If it is gone, remove the lock:
        rm -f '<lock>/owner' && rmdir '<lock>'
```

With no `owner` file (holder died between the `mkdir` and the write, or the write failed under
`|| true`), line 2 reads `holder, from the lock's owner file: <none recorded>`; line 3 still parses,
which is why it is phrased conditionally rather than as an imperative about "that host".

Both branches were driven against a patched copy at `/tmp/uvm-proto/bin/uv-manager` and render as
shown. `bash -n` clean; `temp_root.sh --offline uv --version` still reports `uv 9.9.9 (fixture)`.

Why this satisfies R5: it names the `owner` file, prints the host and the pid it records rather than
telling the user to go read them, and states the discriminator that a stalled user gets wrong — the
pid is not local, so `kill -0` or `ps` here proves nothing. It does not prescribe `squeue`, `sacct` or
`ssh`; the wrapper has no idea which the site has, and naming the wrong one is worse than naming none.
The recovery is still a `rmdir`, as invariants §5 requires, now preceded by the removal that makes it
succeed.

Shape note for `/uvm-plan`: reading the owner should use the `read` builtin, not `cat` — this is a
cold path, but a fork here buys nothing:

```bash
owner="<none recorded>"
[[ -r "${lock}/owner" ]] && { IFS= read -r owner < "${lock}/owner" || true; }
```

Two traps confirmed by drive: redirections apply left to right, so `read … < file 2>/dev/null` still
prints the shell's own "No such file" — the `[[ -r ]]` guard is what suppresses it; and a failing
`[[ … ]] && { … }` at statement level does **not** trip `set -e` (verified under bash 3.2.57).

## 4. Output discipline: stay on `die`, and §7 does not reach here

Measured directly, by pointing a writer at a pipe whose reader has already exited and counting the
shell's own diagnostics on a separate fd:

| Output style | Diagnostic lines, SIGPIPE ignored | SIGPIPE default |
|---|---|---|
| one `printf` with embedded newlines | 1 (`printf: write error: Broken pipe`) | 0, shell dies silently |
| three separate `printf`s | 3 | 0 |
| `cat` heredoc | 1 (`cat: stdout: Broken pipe`, BSD `cat`; GNU is silent) | 0 |

Two conclusions. The §7 hazard needs SIGPIPE to be *ignored* by the invoking process — under the
default disposition no style emits anything, on this platform or the cluster's. And what §7 is
actually protecting against is **N writes behind a departed reader**, which is why `uvm_doctor` and
`uvm_status`, with one `printf` per finding, needed `cat`. `die` is a single `printf` and therefore a
single write: worst case one diagnostic line, the same count BSD `cat` produces. Moving the timeout
message to a heredoc would cost a fork and an exec, break `die`'s single spelling of the
`uv-manager: ` prefix plus `exit 1`, and buy zero lines of noise. Additionally, stderr is only a pipe
when the user writes `2>&1 |` or `2>|`, and this message is the last thing the process emits — there
is nothing queued behind it. **Recommendation: keep it on `die`.** The §7 rule's letter points at
`cat`; its measurement does not.

## 5. Length, voice, and what is added

The message grows 3 lines → 4. Inside the script the block at `:232-237` grows from 6 lines to about
12: one extra message line, two lines to read `owner`, one name on the `local`, and a 3-line comment
recording why the check must happen on another host and why bare `rmdir` was wrong. That is the whole
cost, and against "prefer deleting to adding" it buys the one thing the current text cannot do —
distinguish an abandoned lock from a slow live one before the user deletes it.

Voice: declarative, no filler, no hedging, no adjectives, no emoji, no spec ids. "A pid recorded there
is on that host, not this one" is the concrete failure mode, in the style of the state-root block at
`:100-123`.

## 6. Same-commit surface

- **`README.md` does not quote either message.** `grep -n "rmdir\|timed out\|provisioning lock"` hits
  only `:137`, `:372`, `:458-459` (design prose about `mkdir` atomicity) and the reference table at
  `:551-552`. No update is forced by the wording change itself.
- **`uvm_help` does not quote it either.** `bin/uv-manager:878-879` documents only the two knobs.
- **`etc/uv-manager.conf.example:71-76`** documents both knobs; `:74-76` already frames `UVM_LOCK_STALE`
  as "assumed abandoned". Untouched by this requirement, but it is where R3's ordering constraint will
  land.
- **The `owner` file is documented nowhere a user will look.** It appears only at
  `bin/uv-manager:179`, `:227` and `:242-243`. Pointing a stalled user at a file that neither the
  README nor `uvm help` mentions is a same-commit gap: `README.md` § *Troubleshooting* (`:514-538`) is
  the place — it already has an entry per diagnostic message the wrapper emits, and the lock has none.
  One entry, naming `$UVM_ROOT/<arch>/.install.lock`, its `owner` file, and the two-step removal.
- The **stale-break note** at `:226` should carry the same owner line, for the same reason: it is the
  only record that a specific holder's lock was deleted, and R1's ownership change makes "whose lock
  was that" the first question asked after one. Not required by R5; flagged for the plan.

Not established
