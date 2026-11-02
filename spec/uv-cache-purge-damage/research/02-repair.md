# 02 — The repair per entry kind, R4, R5, and the failure paths

Measured with uv 0.13.6 on a throwaway prototype of the design (`drives/prototype.diff`, the
wrapper at `8e03774` plus the cache walk and arm), every claim through `gates/p2.sh`, which went
green on the prototype in about 70 s and red against the walk alone at its first post-condition
(`R3: module on script: rc 1`).

## In place

`(cd / && exec uv pip install --python <entry>/bin/python --reinstall --no-cache <pins>) >&2`, the
tool arm's idiom, with `<pins>` from `uvm_record_constraints <entry>`: `name==version` per
dist-info directory, or `name @ <url>` (a VCS one at its commit, with its subdirectory) where
`direct_url.json` survives. That helper globs `<dir>/lib/*/site-packages/*.dist-info`, the layout
every cache environment shares with a tool.

On a script environment and a `uvx` environment, for every shape R1 marks *fail*: one module, every
file of a dist-info directory, `RECORD` alone, `METADATA` alone, every third file, and for ruff its
`bin/ruff` and its `RECORD`:

- the knob-set call exits 0 with the command's own output, and prints exactly one repair line;
- the dist-info listing equals the one before the damage;
- the entry is the same directory or link, and no archive or link is added (R5 by construction);
- the managed interpreter's `site-packages` listing is unchanged;
- a second call in the scope prints no repair line, and doctor then reports no damage.

`--no-cache` installs from a temporary cache, never from an unpacked wheel, so a damaged wheel
cannot leak back in. Under `UV_LINK_MODE=hardlink`, where an environment's files share inodes
with the wheel's (verified by `ls -i`), the reinstall replaces the environment's names and leaves
the wheel whole: doctor reports nothing afterwards.

## Removed

| Entry | When | What goes | Why it is safe |
|---|---|---|---|
| cached environment (`uvx`, `uv run --with`) | no `pyvenv.cfg`, no running `bin/python` after the interpreter arm, or a distribution with `direct_url.json` | the link, `rm -f` | the archive stays, so a running process keeps importing (R4, measured); uv rebuilds from the spec the next call names; `uv cache prune` collects the archive |
| script environment | no `pyvenv.cfg`, or no running `bin/python` | renamed to `.<name>.<host>.<pid>.<random>` beside itself, then `rm -rf` | M2 allows it; the rename is atomic, so uv never sees half an environment; `uv run` rebuilds under the original name |
| unpacked wheel | any damage | every `<link>.*` but `<link>.lock`, then the link | uv follows `<link>.http`, not the link (01); the next build downloads it again; `.lock` is uv's flock file |

A cached environment holding a distribution from a URL, git or a path is removed rather than
reinstalled: the next `uvx` call rebuilds it from its own spec, which keeps an editable
`--with-editable` editable. A script environment keeps the in-place reinstall with its sources
pinned from `direct_url.json`, since a script cannot ask for an editable.

Removals run first, so a script environment without `pyvenv.cfg` is gone before the arm's first uv
call (M3). The arm runs after the interpreter, restore and tool arms, so `bin/python` is tested
against an interpreter that has been repaired.

## R4 (a running process)

For the module and dist-info-files shapes, three processes sleep before the damage: the script
environment's `bin/python`, the `uvx` environment's `bin/python` reached through its link, and the
same through the archive's real path. After the knob-set repair each imports
`tqdm.contrib.logging`, present throughout and not yet imported: all three print `late ok`. At
shaping, moving the entry aside failed this import; removing only a `uvx` link passed it.

## Failure paths

Each gives a non-zero exit, the reason naming the entry, the outcome recorded, and the managed
interpreter's `site-packages` unchanged:

| State | Reason |
|---|---|
| the reinstall cannot download (`UV_OFFLINE=1`), 4 concurrent calls | `the cache environment repair failed for <entry>`, every call |
| a `uvx` link in a read-only directory | `cannot remove the cache entry <link>: rm: … Permission denied`, the link still there |
| a wheel's pointer in a read-only directory | the same, the link still there |
| a pyvenv-less script environment in a read-only `environments-v2` | the same, the environment still there and nothing run against the base interpreter |
| the rename succeeds and `rm -rf` cannot finish (a read-only subdirectory) | none: the call runs, notes `left <aside> behind; uv cache prune removes it`, doctor reports nothing, since the walk skips dot names |

Also driven: doctor first, then the knob-set call, which still repairs once; a `uv.toml` in the
working directory with `[pip] target = "leak"`, which the repair does not apply; 8 concurrent first
calls, of which one repairs and all print the version.

## R5 at 16 ranks

`tests/repair-race.sh --scenario U` and `S`, prototyped: every rank exits 0 with the expected
output, one repairs, and the archives and environment links created during the pass number 0
(`rebuilt=0`). Under `ukill` the kill lands during the walk (`restored=0` in the killed pass) and the
clean pass repairs once with `clean_rebuilt=0`.
