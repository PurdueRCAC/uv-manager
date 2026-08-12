# 06 — The documentation surface this cycle drags in

**R8 is incomplete. Confirmed, high confidence.** It names three surfaces — the `uvm_help` heredoc,
`README.md`, `etc/uv-manager.conf.example`. The cycle invalidates statements in **eight** places
across six files. Two of the misses are ordinary omissions from the same-commit list
(`share/modulefiles/uv/main.lua`, `uvm_doctor`'s remediation text). Three are worse: they are
*claims the repository makes about itself* that R1 turns false, and none of them is on any checklist
a build agent reads. The `uvm-build`, `uvm-plan` and `uvm-publish` skills all recite the same
four-file same-commit list; not one mentions `AGENTS.md` or `invariants.md`. A cycle that follows
the skills faithfully ships a repository whose own invariant file contradicts its code.

One premise in the assignment is wrong and worth correcting before the planner acts on it.
**`AGENTS.md` does not assert the unconditional `mkdir`.** `git grep -i 'sentinel|unconditional|
handful of metadata'` returns zero hits in `AGENTS.md`; its Invariants section keeps only
`AGENTS.md:170` ("State directories are created under `umask 077`"), which R1 preserves. So
`invariants.md:122-123` is a derived claim with no source-file counterpart — pre-existing lockstep
drift, in the direction the lockstep rule says loses. Either way the bullet has to change.

## 1. Every assertion R1 falsifies

| Location | What it says now | What it must become |
|---|---|---|
| `bin/uv-manager:402-404` | "`mkdir -p` unconditionally rather than behind a sentinel: it is a handful of metadata operations, and it repairs a tree that a scratch purge has partially removed." | The inverse decision, with the measurement as its warrant and the surviving half of the old claim stated: a missing directory is still created, under `umask 077`. |
| `README.md:462-463` (Design notes) | "**`mkdir -p` on every invocation** rather than behind a sentinel. It is a handful of metadata operations, and it repairs a tree that a purge has partially eaten." | Same reversal. Design notes are the record of what was rejected, so this entry becomes the record of a rejection reversed by measurement, not a deletion. |
| `.agents/factory/invariants.md:122-123` | The same claim, as §8's last bullet, i.e. as a gate a reviewer grades against. | Rewrite. Left alone it makes the correct implementation an **auto-CRITICAL** §8 violation in `uvm-review`, inside a high-blast-radius region (`uvm_export_env`), which forces a human sign-off gate on correct code. |
| `AGENTS.md:109` | "The wrapper adds roughly 7 ms." | Stale by ~28% once R1 lands (measurement below). `AGENTS.md`'s own preamble makes the code ground truth, so this is an obligation, not a courtesy. |
| `README.md:141-142` | "adds roughly 7 ms per invocation on top of `uv` itself" | Same number, same commit. |
| `README.md:202-204` | Partial purge is "the one remaining problem the wrapper cannot fully solve." | Becomes half-true. A site with `UVM_REPAIR` set does solve it, within the bounded check's coverage that R3 requires be named. |
| `README.md:411-422` | Four mitigations "in order of effectiveness", of which `doctor` is #2 and detects only. | `UVM_REPAIR` is a new mitigation and belongs in this ordered list, or the list quietly recommends the manual path the cycle exists to replace. |
| `README.md:520-521` (Troubleshooting) | "`ImportError` from something that used to work is usually a partial purge. Run `uv-manager doctor`." | Should name the knob as the unattended route. |

`ROADMAP.md:29-31` also describes the sentinel, but as this cycle's *work*; it stays true and
`/uvm-roadmap` retires the whole entry on merge. No edit.

**The measurement.** macOS, APFS, local SSD, `temp_root.sh --offline`, 50 warm invocations of
`uv --version` against an intact tree: wrapper 10.62 ms, the installed binary directly 3.68 ms —
**6.95 ms of wrapper overhead**, which corroborates the documented 7 ms. The same drive against a
working-tree copy whose `mkdir` block is guarded: **5.02 ms** with six `[[ -d ]]` tests, **4.94 ms**
with a single sentinel-file test. Isolated, 50 iterations of `(umask 077; mkdir -p <six existing
dirs>)` cost 3.36 ms each against 1.54 ms for a bare `bash -c true`: 1.8 ms of `mkdir` syscalls plus
the 1.5 ms subshell fork that R1 also deletes. **Two findings for the planner.** The wrapper's
overhead falls from about 7 ms to about 5 ms, so both prose figures move. And a six-`[[ -d ]]` guard
measures the same as a one-file sentinel — R1 needs no sentinel of its own, and the marker R3 wants
should be justified by R3's needs rather than by R1's arithmetic.

## 2. Where a knob is documented, taking `UVM_LOCK_STALE` and `UVM_PLATFORM` as templates

| Surface | ROOT | PIN | PLATFORM | INSTALL_URL | LOCK_TIMEOUT | LOCK_STALE |
|---|---|---|---|---|---|---|
| knob block / read site (`bin/uv-manager:162-167`) | `:84` | `:164` | `:151` | `:167` | `:165` | `:166` |
| `uvm_help` heredoc (`:774-780`) | `:775` | `:776` | `:777` | `:778` | `:779` | `:780` |
| README reference table (`:535-542`) | `:537` | `:538` | `:539` | `:540` | `:541` | `:542` |
| `etc/uv-manager.conf.example` | §1 `:35-49` | `:60` | `:78-85` | `:64` | `:71-72` | `:74-76` |
| README prose section | `:317-344` | `:485-486` | `:346-355` | `:291-292` | — | — |
| `share/modulefiles/uv/main.lua` | `:119` | `:129` (commented) | — | — | — | — |
| `uvm_status` (`:609-633`) | `:617` | `:631` | `:616` (resolved) | — | — | — |

Four surfaces are unanimous: the knob block, the help heredoc, the README table, the conf example.
`UVM_REPAIR` must hit all four; R8 names three of them and omits the knob block itself, which is
where the default is chosen and therefore where the truthiness decision in §4 is made.

**The modulefile is not optional here, despite only two of six knobs reaching it.** The GOAL's own
non-goal argues the opt-in is safe because "a site that wants it everywhere sets it in the
modulefile". That sentence sends an operator to `main.lua`, and `main.lua` will not mention the
variable. A commented `setenv("UVM_REPAIR", "1")` beside the `UVM_PIN` precedent at `:127-129` is
the matching change. The modulefile's user-visible help at `:86-93` also tells users a partly purged
tree "is not detected by uv. Run `uv-manager doctor`" — accurate at a site that leaves the knob
unset, incomplete at one that sets it, and site-editable either way; the planner should decide
deliberately rather than by omission.

**Status: a judgment call, and the precedent points both ways.** Four of six knobs never appear.
`pin` does, because it silently changes which version is selected and nothing else in the printed
state reveals it. `UVM_REPAIR` is invisible in exactly the same way and changes far more — whether
an invocation may take a lock and rebuild environments before running the user's command. One
appended line costs nothing downstream: the README sample at `:13-21` truncates with `...` at `:20`,
so a field added after `pin:` does not invalidate it. Recommend adding it; note it is not forced by
the templates.

## 3. Has automatic repair been rejected before? No.

`README.md:426-464` was read in full. The eight design notes cover dispatch on `basename $0`, the
`UVM_*` prefix, `exec` over subprocess, version-keyed installs with an atomic swap, the `mkdir` lock,
neutral trampolines, not overriding `XDG_CONFIG_HOME`, and the unconditional `mkdir -p`. **Nothing
rejects automatic repair, a repair verb, or a knob that triggers one.** Troubleshooting (`:504-527`)
and the purge section (`:388-422`) treat `doctor` as a detector and recommend running it from a job
prologue, which is the manual workaround this cycle replaces, not a considered refusal.

The one rejection this cycle overturns is the *sentinel*, and its stated reason is a cost claim:
"a handful of metadata operations". The planner must answer it on its own terms rather than
re-propose past it — §1's numbers do that, and the second half of the claim ("it repairs a tree a
purge has partially eaten") is not a cost argument but a behavior R1 must keep and prove.

## 4. `UVM_REPAIR`: collision-free; its shape is the live hazard

Collision, verified today rather than assumed. `uv`'s env-var registry
(`crates/uv-static/src/env_vars.rs`, 68,694 bytes, fetched 2026-08-12) contains **zero** `UVM_`
strings and **zero** occurrences of "repair" in any casing; the live `install.sh` (71,225 bytes) is
the same on both counts. The name is consistent with the `UVM_*` rationale at `README.md:436-442`.
`spec/uvm-env-prefix/research/05-namespace-safety.md` already cleared the EDA and NVIDIA `UVM_`
namespaces; `UVM_REPAIR` does not touch `UVM_HOME`, the one real environment variable there.

**Shape is where the contract has a hole.** All six existing knobs carry a value — a path, a version,
a key, a URL, two durations. `UVM_REPAIR` would be the first boolean, and the script has no boolean
convention for an *environment* variable. Its internal booleans are non-emptiness tests: `force` at
`:304`/`:308`/`:316` via `[[ -z ]]`, `dry_run` at `:590` via `[[ -n ]]`, `want_help` at `:573`. The
one place the script compares a literal is `uvm_clean`'s `[[ "${confirm}" != "--yes" ]]` (`:745`).
Follow the dominant convention and `UVM_REPAIR=0` **enables** repair, which is the opposite of what
an operator writing it means and is the kind of defect that surfaces as an unexpected lock and a
rebuild inside a charged allocation. R2 does not close this: it is written "WHILE `UVM_REPAIR` is
unset", so a literal reading leaves `=0` enabled and contract-compliant. The knob defaults at
`:164-167` use `:-`, so an exported-but-empty value already reads as unset; only `0`, `false` and
`no` are exposed. Either test a value explicitly and document the accepted spellings, or document in
all four surfaces that any non-empty value enables it. Silence is the one option that ships the
footgun.

## 5. `uvm_doctor`'s remediation text

`:727-732` prints three commands for a human. Once the knob exists, that block is the last place a
reader lands after being told their tree is damaged, and it will not mention the automatic route.
One added line naming `UVM_REPAIR=1` is the fix. It is **not** the excluded non-goal: the GOAL rules
out a `uvm doctor --repair` *flag* — new user-facing surface — and a sentence in existing output adds
no verb, no argument parsing, and no new behavior. Keep it a sentence.

## What I could not establish

Nothing about the eight locations is inferred; every one was read and every line cited was grepped.
Three limits. The timings are macOS on APFS and local SSD, single-user, quiet machine — they
establish the *ratio* the prose claims depend on, not a cluster figure, and the parallel-filesystem
number that actually matters to a ten-thousand-rank burst cannot be produced here at all. Whether
`uvm_status` should carry a repair line and how far `main.lua`'s help text should move are judgment
calls the evidence informs but does not settle; both are flagged rather than decided. And the
`UVM_REPAIR=0` reading of R2 is a contract question, not a research finding: it needs the same
sign-off a rename would.
