# PLAN — `uvm doctor` reports OK on the damage it exists to find

> **Status:** Draft for review · **Last updated:** 2026-08-14
> **Authoritative technical design.** The *how*. The contract is [`GOAL.md`](GOAL.md); the phased
> executable roadmap is [`TECH.md`](TECH.md). Backing detail is in [`research/`](research/).

## 1. Summary

Every change lands inside `uvm_doctor` (`bin/uv-manager:665-751`) and one section of `README.md`.
The `RECORD` walk is re-driven from a `*.dist-info` glob instead of a `*.dist-info/RECORD` glob, which
detects a missing manifest and removes six processes per distribution from the same loop — one edit
serving R1 and R5. A five-stat `pyvenv.cfg` probe joins the existing tools loop. The single `problems`
counter becomes two, under the rule *`FAIL` sets the exit status, `WARN` does not*. The trailing
remediation block becomes a heredoc naming two idioms that repair instead of three that do not.
Nothing outside `uvm_doctor` and `README.md` changes.

## 2. Design

**The walk (R1, R5).** `uvm_doctor`'s third block currently globs
`tools/*/lib/*/site-packages/*.dist-info/RECORD`, so a distribution whose manifest is gone does not
match and is invisible. Globbing `*.dist-info` instead makes the missing manifest a case the loop
handles rather than one it cannot see, and it keeps R1 and R5 in **one** glob where the naive reading
of R1 adds a second — measured at 19.6 ms per 800 distributions in the prior cycle's research.

Inside the loop, `sp="$(dirname -- "$(dirname -- "${record}")")"` becomes `${di%/*}`, the
`$(basename -- "$(dirname …)" .dist-info)` chain becomes `${di##*/}` / `${name%.dist-info}`, and
`< <(awk -F, …)` becomes a direct `< "${record}"` redirect with the field split done by
`IFS=, read -r rel _` and the quote strip by `${rel#\"}` / `${rel%\"}`. Measured 6.5× on a
100-distribution tree (§4).

One detail is load-bearing and is not an optimization: the read loop's condition must be
`while IFS=, read -r rel _ || [[ -n "${rel}" ]]`. `RECORD` files whose final line lacks a trailing
newline exist; `awk` reads that line and bash's `read` does not, so without the guard the walk drops
the entry and goes **silent** on a damaged distribution. `research/01` §4 has the measurement.

Byte-identical also means preserving `awk`'s behavior on a quoted path containing a comma — both
implementations truncate at the first comma. That is wrong and reproducing it is deliberate; correcting
it would change findings on real trees and is not R5.

**The `pyvenv.cfg` probe (R2).** One `[[ -f "${d}pyvenv.cfg" ]]` inside the existing
`for d in "${uvm_root}/tools"/*/` loop, so it adds no glob and no fork; measured below timer
resolution. It reports:

```
FAIL  tool <name> has no pyvenv.cfg; no automated repair is safe for it
```

This class is the most dangerous in the set. uv stops recognizing the directory as a virtualenv,
resolves the base interpreter, and an in-place repair writes into the base `site-packages` — observed
in the prior cycle escaping into `/opt/homebrew/lib/python3.14/site-packages`.

**The exit-status split (R3).** `problems` becomes `problems` (failures) and `advisories`. The rule,
which is what gets documented so the next finding added to doctor has a home: **a `FAIL` means the
tree does not work and sets the exit status; a `WARN` is information about a tree that does work and
does not.** Exactly one existing finding moves — the receipt-less tool directory, already spelled
`WARN` and already the only non-`FAIL`. Its line becomes self-contained, since a tree with no failures
now prints no remediation block:

```
WARN  tool <name> has no receipt; uv ignores it. Remove the directory, or reinstall the tool by name.
```

The success line has to stay true when advisories exist, so it gains a suffix rather than pretending
nothing was printed above it:

```
OK    no damage detected under <root> (<n> advisory finding(s) above)
```

**The remediation block (R4).** Six `printf`s become one heredoc through `cat`, per invariant §7.
Three commands become two:

```
<n> problem(s) found. A scratch purge removes files from under a tree uv still
believes is intact, and uv re-checks nothing, so a repair has to bypass its cache:

    uv tool upgrade --all --reinstall --no-cache
    uv python install --reinstall

--no-cache carries the repair: uv runs no integrity check on its unpacked archive
store, so a rebuild that reuses the cache reinstalls the same damage. The python
command needs network access; uv never caches interpreter tarballs. A missing uv
binary needs no command at all — the next uv call re-provisions it and honors
UVM_PIN.

Neither command repairs a tool whose pyvenv.cfg is gone, and neither is safe to run
against one: uv falls back to the base interpreter and writes outside this tree.
Remove that tool's directory and install the tool again, naming the version you
want — the recorded requirement may not be the version that was installed.

Consider pointing UVM_ROOT at non-purged storage instead.
```

The heredoc delimiter stays **unquoted** because the failure count interpolates; the body must
therefore contain no unescaped `$`. The drafted text contains none, and `/uvm-build` should re-check
that rather than trust this sentence.

**Documentation (R7).** `README.md:416-418` enumerates four detected classes and names the `RECORD`
walk as the mechanism, which reads as a complete list. It is rewritten to state the floor: a
distribution deleted entirely leaves no ground truth, because `uv-receipt.toml` records only the
top-level request rather than the distributions it resolves to; and managed interpreters carry no
manifest, so doctor's oracle there is `import json, os, ssl`, which survives the removal of `email/`,
`xml/` and `unittest/`. The `uvm_help` line ("Check for a partially purged / damaged tree") and
`share/modulefiles/uv/main.lua:78,92` stay accurate under the new behavior and are re-read rather
than assumed.

**What is removed.** Two `dirname` calls, one `awk`, two `basename` calls and one process substitution
per distribution; one of two globs over the same paths; six `printf` calls; and one whole remedy line
— `uv-manager install`, which is **deleted rather than replaced**, because an ordinary `uv` call
already re-provisions and honors `UVM_PIN` (measured, `research/02` §5). The function should not grow
materially: two probes and one counter arrive, and the process machinery of the walk leaves.

### Requirement → design map

| R-ID | Design element(s) that satisfy it |
|------|-----------------------------------|
| R1 | `*.dist-info` glob replaces `*.dist-info/RECORD`; missing-manifest branch reports and `continue`s |
| R2 | `[[ -f "${d}pyvenv.cfg" ]]` in the existing tools loop; `no automated repair is safe` wording |
| R3 | `problems`/`advisories` counters; `FAIL` sets status, `WARN` does not; `OK` line gains the advisory suffix; the `WARN` line carries its own remedy |
| R4 | `cat <<EOF` remediation; `uv tool upgrade --all --reinstall --no-cache` + `uv python install --reinstall`; `uv-manager install` deleted; `pyvenv.cfg` paragraph |
| R5 | `${di%/*}`, `${di##*/}`, `${name%.dist-info}`, `< "${record}"`, `IFS=, read -r rel _`, and the `|| [[ -n "${rel}" ]]` guard |
| R6 | No writes introduced; `uvm_set_paths` untouched; asserted by a path+hash manifest in the P2 and P3 gates |
| R7 | `README.md` § scratch-purge mitigation rewritten to state the detection floor |

## 3. Invariant gate (AGENTS.md constitution check)

Checked before research and again against this drafted design.

- **§7 Output discipline** — the remediation block moves from six `printf`s to a heredoc through
  `cat`, which is the invariant's own prescription and fixes the observed
  `printf: write error: Broken pipe`. Doctor's findings stay on **stdout**: §7 sends *provisioning
  chatter* to stderr because it is a side effect of another command, whereas doctor's report is the
  product of the command the user ran. No finding moves streams.
- **§8 Environment** — `uvm_set_paths` stays pure and is not edited; doctor adds no filesystem write
  and takes no lock. R6 exists to keep this true, and `research/02` §3 shows it is true today.
- **§10 Portability floor** — the rewritten walk uses only bash 3.2 constructs: parameter expansion,
  `IFS=, read`, `case`, `[[ -e ]]`. No `mapfile`, no associative arrays, no GNU-only tool. Proven on
  bash 3.2.57, which is the dev host's `/bin/bash`. Doctor is not on the hot path, so the hot-path
  clause does not bind; the change reduces cost regardless.
- **§12 Project conventions** — R7 lands `README.md` in the same commit as the behavior it describes;
  `uvm_help` and the modulefile are re-read for invalidation. `uvm_version` is untouched. No
  feature-scoped spec ids enter the script or the README.

Not touched, and deliberately so: §1 (no architecture-bearing path is exported; doctor reads
`uvm_root`, which already carries the key), §2 (doctor is a manager subcommand and never `exec`s),
§3, §4, §5, §6, §9, §11.

**One invariant is restored rather than merely respected.** The remedy this cycle deletes,
`uv-manager install` with no argument, re-resolves latest and repoints `current` — so a user who
followed doctor's own advice at a pinned site violated §4 ("a pin is authoritative"). Removing the
line removes that instruction.

### Deviation justifications

| Deviation | Why needed | Simpler alternative rejected because |
|-----------|-----------|--------------------------------------|
| —         | —         | — |

## 4. Rabbit holes (resolved)

- **Is R5's 4× real, and where is the cost?** → The forks are per *distribution* (six of them), not per
  file; the per-file loop is already builtin-only. Measured **6.5×** — 0.52 s → 0.08 s over 100
  distributions and 4112 files, bash 3.2 ([`01`](research/01-fork-free-record-walk.md)).
- **Can a bash read loop reproduce `awk`'s verdict byte-for-byte?** → Yes, verified across blank lines,
  `"quoted,comma.py"`, `../` escapes, absolute paths, bare `,,`, CRLF, and a final line with no
  trailing newline — **provided** the `|| [[ -n "${rel}" ]]` guard is present; without it the walk goes
  silent on that last class ([`01`](research/01-fork-free-record-walk.md) §3–§4).
- **Do the gates need a real uv, packages, or egress?** → No. Doctor reads the filesystem only, so a
  fabricated tool tree plus the `--offline` fixture's stub binary drives every branch. Every phase gate
  in this cycle is offline ([`02`](research/02-doctor-baseline.md) §1).
- **Is R6 a fix or a preservation?** → Preservation. Doctor already writes nothing and takes no lock,
  verified by a path+hash manifest before and after ([`02`](research/02-doctor-baseline.md) §3).
- **What replaces the dangerous `uv-manager install` remedy?** → Nothing; it is deleted. An ordinary
  `uv` call re-provisions and honors `UVM_PIN`, measured both ways
  ([`02`](research/02-doctor-baseline.md) §5, [`03`](research/03-remediation-and-exit-status.md) §2).
- **Which findings are advisory?** → Exactly one, under a rule rather than a list
  ([`03`](research/03-remediation-and-exit-status.md) §1).

## 5. Risks & open questions

- **R5's wording is looser than the design.** The criterion says "without forking per file"; there are
  no per-file forks to remove, and the design removes per-distribution ones. The measured post-
  condition R5 actually asks for — same verdict, measurably faster — is met. Flagged so `/uvm-review`
  reads the criterion against what was built rather than against its literal phrasing. Not a GOAL
  contradiction and not worth an amendment.
- **The speed ratio is tree-shaped**, and the GOAL says "roughly four times" where this host measures
  6.5×. The phase gate therefore asserts **verdict equality and not a speed threshold**; a threshold
  would encode one host's tree shape as a contract.
- **Cluster-only, taken on trust.** Every measurement is warm local APFS on one macOS/arm64 host. On
  Lustre with a cold MDS the filesystem term dominates and the relative win compresses — the fork
  saving remains but the ratio does not. This cannot be measured off-cluster and no gate in this cycle
  covers it.
- **Inherited assumption.** `--reinstall` suppressing the upgrade in `uv tool upgrade` is observed
  behavior on `uv 0.12.3`, not documented contract (prior cycle's `research/04` §6). The remediation
  text depends on it. It should be re-checked when the pinned uv moves.
- **R7 is partly inspection-only.** A grep can prove the sentence implying completeness is gone; no
  grep can prove its replacement is honest. The P4 phase body says which half is graded by the
  reviewer.

## 6. Verification strategy

Three layers on every phase: `bash -n`, `.agents/factory/bin/lint.sh`, and a sandbox drive under
`.agents/factory/bin/temp_root.sh --offline`. `--arch` is not used — nothing here touches the
architecture split. Each gate fabricates its own tool tree inside the sandbox, so no phase depends on
network, real packages, or the developer's state root.

Post-conditions asserted, by R-ID:

| R-ID | Post-condition the drive asserts |
|------|----------------------------------|
| R1 | A `dist-info` with no `RECORD` is named on stdout and the exit status is 1 |
| R2 | A tool with no `pyvenv.cfg` is named, the `no automated repair` wording appears, exit 1 |
| R3 | Receipt-less tool alone → exit 0 with the advisory line; add a real failure → exit 1 |
| R4 | Doctor's output contains no `uv-manager install` and does contain `--no-cache`; `uvm doctor \| head -1` writes nothing matching `write error` to stderr |
| R5 | A `RECORD` whose final line has no trailing newline is still walked (`is missing 1 of 1`) |
| R6 | A `find`-based path list plus `shasum` of every file is unchanged across a doctor run |
| R7 | `git grep` shows the completeness-implying sentence is gone; the replacement's honesty is reviewer-graded |

**All four gates were authored and run against the current tree before this plan was committed, and
each exits non-zero on its own first unmet post-condition** — R1's missing-manifest line, R2's
`pyvenv.cfg` report, R3's advisory-only exit 0, and R7's `README.md` sentence. `lint.sh` is green on
the current tree, so a later red is attributable to the phase rather than to a pre-existing failure.

One gate-authoring hazard is recorded because it produced a false green during this planning run: the
R7 anchor `found by walking each distribution` **wraps across two lines** in `README.md`, and
`git grep` is line-based, so the gate reported success while the sentence was still there. The
committed anchor is `detects what uv does not`, which lives on one line and was re-tested red.

---

*Backing research: [`research/00-digest.md`](research/00-digest.md).*
