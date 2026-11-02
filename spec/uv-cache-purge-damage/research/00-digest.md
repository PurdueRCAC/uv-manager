# 00 — Digest

The fan-out was narrowed to three sequential briefs run by the planner, each needing a seeded
real-uv sandbox and the previous brief's answer; the shaping run had measured R1 already, and its
drives were re-run here as the baseline. Every claim below was executed with uv 0.13.6 under
`temp_root.sh`, most of them on a throwaway prototype of the design
([`drives/prototype.diff`](drives/prototype.diff)) through the gate scripts in
[`../gates/`](../gates/).

| # | Decision | Brief |
|---|---|---|
| D1 | **Live entries** are script environments (`environments-v2/*/` holding `lib/`, `bin/` or `pyvenv.cfg`), cached environments (links under the other `environments-v2/*/`, which covers `uvx` and `uv run --with`), and unpacked wheels (links under `wheels-v*`, listed by one `find -type l` per bucket since their depth varies by source). The walk goes through the links, so no `readlink` forks; dangling links and dot-named entries are skipped. | [01](01-cache-walk.md) |
| D2 | **Checks**, per environment: `pyvenv.cfg`; per dist-info: `RECORD`, `METADATA`, and every path `RECORD` lists, `../../../bin/<script>` included; per wheel: a dist-info exists, then the same. One FAIL per damaged entry, naming its path. | [01](01-cache-walk.md) |
| D3 | **Cost**: 55 µs per `RECORD` line on APFS (2713 lines, 0.15 s); on Lustre a metadata round trip per line, so 0.5-1.5 s on the R6 cache and tens of seconds on a cache of large stacks. Recorded, not bounded (M1). | [01](01-cache-walk.md) |
| D4 | **In place** for any environment with `pyvenv.cfg` and a running `bin/python`, after the interpreter arm: the tool arm's reinstall with every distribution pinned from its dist-info name or `direct_url.json` (`uvm_record_constraints`), from `/`, `--no-cache`. Restores every R1 *fail* shape with the same listing, the same entry, nothing rebuilt, and a running process unaffected. | [02](02-repair.md) |
| D5 | **Removed**: a cached environment's link (no `pyvenv.cfg`, no interpreter, or a non-index source); a script environment without `pyvenv.cfg` or interpreter, renamed aside then `rm -rf`; an unpacked wheel's pointer files then its link. Removals run before any reinstall. | [02](02-repair.md) |
| D6 | **The wheel's pointer is what uv follows.** Removing the link alone leaves the damaged archive in use and the walk blind to it; removing `<link>.http` heals. The arm removes every `<link>.*` but `.lock`, then the link, so a renamed pointer in a later uv still goes. | [01](01-cache-walk.md) |
| D7 | **Failure** of any removal or reinstall sets the reason, naming the entry, and returns, as every arm does; a rename that succeeded and an `rm -rf` that did not leave the aside and a note, and the scope proceeds. | [02](02-repair.md) |
| D8 | **R6** extends `tests/repair-race.sh` with `U`, `S`, `ukill` on a cache of 20 other live environments plus their wheels, and keys `walk_s`, `cache_files`, `live_entries`, `link_mode`, `flock`, `rebuilt`. Two jobs. | [03](03-cluster-drive.md) |

Cross-brief contradictions: none. The one design change the drives forced was D6: the plan's first
draft removed the wheel's link, and the pointer drive showed that to be a false clean.
