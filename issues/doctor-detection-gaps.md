---
status: shaped
kind: fix
appetite: medium
lane: public
---

# `uvm doctor` reports OK on the damage it exists to find

## Problem

`uvm_doctor` (`bin/uv-manager:648-734`) is the one command the README, the modulefile help text and
the troubleshooting section all point a user at when something that used to work stops importing.
Four defects, each reproduced with real `uv 0.12.3` and real packages in a `temp_root.sh` sandbox
during the `purge-resilient-run` research cycle.

**It is blind when the purge takes `RECORD`.** The file-level walk at `:689` is driven by
`tools/*/lib/*/site-packages/*.dist-info/RECORD`. `RECORD` is read only on uninstall, making it the
coldest file in a distribution and an early casualty of an atime-ordered purge. Gut a `tqdm`
environment and remove `RECORD` with the files and doctor prints `OK    no damage detected`, exit 0.
Restore `RECORD` alone and the same tree reports `FAIL  tqdm-4.70.0 is missing 197 of 201 files`. The
detector's sight depends on the survival of the file a purge removes first.

**A `dist-info` with no `RECORD` at all is not treated as damage.** The glob simply does not match, so
a distribution whose manifest is gone is invisible rather than suspicious. Adding that probe costs
about 0.02 s on a realistic tree and catches the case above.

**Warnings set the exit status.** A tool directory missing `uv-receipt.toml` produces `WARN` at
`:671-674` and increments `problems`, so doctor exits 1. Observed on a tree where `httpie` had lost
its receipt: `uvm doctor` exits 1 forever while `http --version` prints `3.2.4` and the tool works.
Any automation keyed to doctor's status fails permanently over a working tool, and the only way to
reach exit 0 is to delete it.

**The printed remedies are wrong, and one is dangerous.** `:729-731` prints three commands.
`uv tool install <name>` no-ops on a gutted-but-receipted environment — the exact failure the banner
above the function describes. `uv tool uninstall && uv tool install` still yields a broken tree when
the cache is damaged, because uv performs no integrity check on its unpacked `archive-v0` store; only
`--no-cache` forces a clean rebuild. And `uv-manager install` with no argument re-resolves *latest*
from the network and repoints `current`: driven with `UVM_PIN=6.6.6`, it left `current -> versions/9.9.9`.
The block is also six `printf`s where the file's own SIGPIPE discipline (`:605-608`) requires a
heredoc — `uvm doctor | head` emits `printf: write error: Broken pipe`.

Two further probes are cheap and catch classes doctor cannot currently see. A tool whose `pyvenv.cfg`
is missing is not merely broken: any repair attempted against it writes into the **base** interpreter's
`site-packages`, outside the tree the wrapper owns. Five stats detect it. And the whole `RECORD` walk
can be made fork-free for a byte-identical verdict, taking a realistic tree from **1.33 s to 0.33 s**.

## Why it was deferred

**Pre-existing** on `main`, all four. Found during `purge-resilient-run` research
(`spec/purge-resilient-run/research/02-bounded-integrity-check.md` and the adversarial pass recorded
in `00-digest.md`), which narrowed to the hot-path guard and left detection untouched. Deferred rather
than folded in because that cycle's GOAL had no criterion covering `uvm_doctor`, and because these
fixes are worth landing on their own schedule: they are correctness owed regardless of what shape the
repair work eventually takes, and the repair cycle depends on them.

## Outcome / vision

`uvm doctor` detects the damage a purge actually causes, distinguishes advice from failure in its exit
status, and prints remedies that work. It gets cheaper doing it.

## Sketch of the acceptance criteria

- **R1** — WHEN a `*.dist-info` directory contains no `RECORD`, doctor SHALL report it as damage.
- **R2** — WHEN a tool directory is missing `pyvenv.cfg`, doctor SHALL report it, and SHALL say that
  no automated repair is safe for that class.
- **R3** — Advisory findings SHALL NOT set the exit status. A tree whose only finding is a
  receipt-less tool directory SHALL exit 0, with the advisory on stdout.
- **R4** — The remediation text SHALL name only idioms that repair a damaged tree, SHALL NOT recommend
  `uv-manager install` at a pinned site, and SHALL be emitted through a heredoc.
- **R5** — The `RECORD` walk SHALL reach the same verdict without forking per file.
- **R6** — Detection SHALL remain read-only: `uvm doctor` takes no lock and writes nothing.

## Notes

- Sequencing: **before** [`issues/purge-tree-repair.md`](purge-tree-repair.md), which needs doctor as
  its detector and cannot use its exit status as an oracle until R3 lands.
- A caution for whoever implements R5: the current walk *reads* every `RECORD`, and `read(2)` updates
  atime where `[[ -e ]]` does not. Running doctor keeps `RECORD` warm and the module files cold,
  preserving doctor's sight for trees that are checked often and least likely to be damaged, and
  absent for the thirty-day-idle tree that motivates it.
- Detection has a floor no budget removes, and R1–R5 do not lift it. A distribution deleted entirely
  leaves no ground truth: `uv-receipt.toml` records only the top-level request (`jupyterlab`), not the
  91 distributions it resolves to. Managed interpreters carry no manifest at all — doctor's oracle is
  `import json, os, ssl`, and removing `email/`, `xml/` and `unittest/` leaves it silent. Say this in
  the documentation rather than implying doctor is exhaustive.
- Found by: the `purge-resilient-run` research fan-out, 2026-08-12.
