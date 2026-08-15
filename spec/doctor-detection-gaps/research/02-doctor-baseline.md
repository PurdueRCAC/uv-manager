# 02 — Pre-change baseline: every defect reproduced through the real wrapper

All four GOAL defects and both detection gaps reproduce under
`.agents/factory/bin/temp_root.sh --offline`, with **no network and no real `uv`** — the fixture's stub
binary plus a fabricated tool tree is enough, because doctor only reads the filesystem. That makes
every phase gate in this cycle offline and fast, and it is the single most useful finding here for
`/uvm-build`.

## 1. Doctor needs no real uv and no provisioned packages

A tool tree is a directory shape. `pyvenv.cfg`, `uv-receipt.toml`, `bin/python`, and
`lib/*/site-packages/*.dist-info/RECORD` fabricated by hand drive every branch of `uvm_doctor`. The
only thing requiring the `--offline` fixture is `real_uv`, so that the `uv binary missing` FAIL does
not contaminate an exit-status assertion — one `uv --version` call seeds it.

## 2. The defects, as observed

**R1 — blind when the purge takes `RECORD`.** Files removed *and* their manifest removed:

```
OK    no damage detected under …/root/arm64
rc=0
```

**R2 — `pyvenv.cfg` gone, doctor silent.** Same `OK`, `rc=0`. Per
`spec/purge-resilient-run/research/04-uv-repair-idioms.md` §4 this is the most dangerous class in the
set: uv stops recognizing the directory as a virtualenv and resolves the base interpreter, and an
in-place repair then writes into the base `site-packages` — observed there escaping into
`/opt/homebrew/lib/python3.14/site-packages`.

**R3 — advice sets the exit status.** One receipt-less tool on an otherwise intact tree:

```
WARN  tool tool2 has no receipt (uv will treat it as not installed)

1 problem(s) found. …
rc=1
```

**R4 — SIGPIPE.** `uvm doctor | head -1` on a tree with any finding:

```
bin/uvm: line 744: printf: write error: Broken pipe
```

## 3. R6 is a preservation criterion, not a repair

Doctor is **already** read-only. A `find`-based manifest of paths plus `shasum` of every file, taken
before and after a run, shows no content and no path difference — no lock directory is created and
nothing is written. `uvm_set_paths` (`bin/uv-manager:386-397`) is pure, and the dispatch tail calls
only it (`doctor) uvm_set_paths; uvm_doctor ;;`).

R6 therefore guards against a regression the new probes could introduce, rather than describing
something to fix. Two ways this cycle could break it: a probe that writes a scratch file, or a design
that reaches for provisioning to answer a question. Neither is in the plan; the gate exists so neither
arrives later.

Note the deliberate exception in R6's own text: `read(2)` updates atime, and the walk reads every
`RECORD`. A manifest of paths, mtimes and hashes is the right instrument; anything comparing atime
would fail on correct code.

## 4. The advisory class, and why exactly one finding moves

`uv tool upgrade --all` against a receipt-less directory exits 1 with `` `pycowsay` is not installed ``
and leaves the directory (research `04` §4). uv ignores it; the tool on disk keeps working, as the
GOAL's `httpie`/`3.2.4` observation shows. So the finding is real information but not brokenness —
which is exactly the definition R3 adopts. Every other existing finding (missing binary, dangling
shim, broken interpreter link, missing files, damaged managed interpreter) describes a tree that does
not work. **One finding changes class; the classification rule is what gets written down.**

## 5. Automatic re-provisioning makes R4's dangerous remedy deletable

`uv-manager install` with no argument re-resolves latest and repoints `current`, overriding a pin — the
GOAL's `UVM_PIN=6.6.6` → `current -> versions/9.9.9` observation. The remedy does not need replacing
with a safer spelling, because it is unnecessary: an ordinary `uv` call re-provisions on its own and
honors the pin. Measured both ways in the sandbox:

```
current removed, no pin  →  uv --version  →  current -> versions/9.9.9
current removed, UVM_PIN=1.2.3  →  uv --version  →  current -> versions/1.2.3
```

So the line is **deleted**, and the `uv binary missing` FAIL can say that the next `uv` call restores
it. That is the repository's stated bias — prefer deleting to adding — landing on its own.
