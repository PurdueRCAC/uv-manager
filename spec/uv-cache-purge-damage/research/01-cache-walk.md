# 01 — The cache's live entries, the walk, and what it costs

Measured with uv 0.13.6 (macOS arm64, APFS, default link mode) under
`.agents/factory/bin/temp_root.sh`, the wrapper at `8e03774`, real uv seeded into `versions/` as
`tests/repair-race.sh --uv-bin` does. Drives in [`drives/`](drives/).

## Layout (what a live entry is)

A cache holding two `uv run --no-project` script environments, two `uvx` environments and one
`uv run --with` overlay:

```
cache/
├── environments-v2/
│   ├── s-5c69eb8d6ee8a2f1/          script environment: a real directory
│   │   ├── pyvenv.cfg  .lock  CACHEDIR.TAG  bin/{python→managed, tqdm, activate*}  lib/python3.12/site-packages/
│   └── 62aba82b281f7b70/            one directory per interpreter hash, holding only links
│       ├── 6bce7087d2f1c3b6 -> ../../archive-v0/<id>     uvx tqdm==4.67.1
│       ├── 745c9b7679f1f48d -> ../../archive-v0/<id>     uvx ruff==0.8.4
│       └── cc335434315ec743 -> ../../archive-v0/<id>     uv run --with six==1.16.0
├── wheels-v7/pypi/tqdm/
│   ├── 4.67.1-py3-none-any -> ../../../archive-v0/<id>   unpacked wheel
│   ├── 4.67.1-py3-none-any.http                          the archive pointer uv follows
│   ├── 4.67.1-py3-none-any.msgpack                       the wheel's metadata
│   └── 4.67.1-py3-none-any.lock                          uv's flock file
├── archive-v0/<id>/ …   builds-v0/  sdists-v10/  simple-v27/  interpreter-v4/
```

- `uv run --with` overlays are cached environments of the same shape as `uvx`'s, so the walk covers
  them too.
- A wheel's link depth depends on its source: `pypi/<name>/<stem>` is 3 below the bucket,
  `index|url|path/<digest>/<name>/<stem>` 4, `git/<digest>/<sha>/<name>/<stem>` 5. `find <bucket>
  -type l` lists them at any depth without descending through them into the archives.
- A script environment and a cached one differ by content: the script environment holds `lib/`,
  `bin/` and `pyvenv.cfg`; the interpreter-hash directory holds only links. A script environment
  that lost every file keeps `lib/` and `bin/`.
- `RECORD` in an environment lists the console scripts as `../../../bin/<name>` relative to
  `site-packages` (tqdm and ruff both measured), so `<site-packages>/<path>` reaches `bin/` through
  `..`, and through a link the kernel resolves the link first. The tools walk skips `../` paths;
  the cache walk must not, or R2's "an executable under `bin/`" goes unseen.

## Which name uv follows for a wheel ([`drives/wheel-pointer-which.sh`](drives/wheel-pointer-which.sh))

With `tqdm/std.py` removed from the unpacked wheel, a new script needing it:

| Removed | Result |
|---|---|
| the link only | fails, `No module named 'tqdm.std'`; uv still builds from the damaged archive |
| `.msgpack` only | fails |
| `.http` only, or `.http` with anything | heals: a new archive is downloaded and the link rewritten |
| the archive directory | heals |

`.http` carries the archive id (`strings` shows it first). uv reaches the archive through it, and
the link is its own bookkeeping. **A repair that removes only the link leaves the damage in use and
makes the walk blind to it**: a false clean.

## `uv cache prune` ([`drives/wheel-pointer-prune.sh`](drives/wheel-pointer-prune.sh))

It removes every `environments-v2` entry, a dot-named one included, and every archive no link
reaches. A script environment renamed aside is never reused by `uv run`, which rebuilds under the
original name.

## The baseline (R1, re-run)

[`drives/shaping-matrix.sh`](drives/shaping-matrix.sh) and
[`shaping-supp.sh`](drives/shaping-supp.sh), the shaping drives with local paths scrubbed, re-run at
`8e03774`: every row's exit status, stdout and cause matches the shaping run at `648496d`; only
cache hashes differ ([`shaping-matrix.out`](drives/shaping-matrix.out),
[`shaping-supp.out`](drives/shaping-supp.out)). The knob-set call still exits 1 with zero repair
lines and records `value-g1.ok`, and doctor still says `OK`. This is the baseline R2–R5 are graded
against.

## The walk

Builtins only, except one `find` per `wheels-v*` bucket:

- **Script environment** (`environments-v2/*/` holding `lib/`, `bin/` or `pyvenv.cfg`) and **cached
  environment** (each link under an `environments-v2/*/` that holds none of those): `pyvenv.cfg`
  present; then for each `lib/*/site-packages/*.dist-info`, `RECORD` present, `METADATA` present,
  and every path `RECORD` lists, absolute ones aside, present (`-e` or `-L`).
- **Unpacked wheel** (each link `find` lists): at least one `*.dist-info` at its root, then the same
  three checks per dist-info.
- Dangling links are skipped: uv rebuilds those (R1, "entry removed"). Dot-named
  `environments-v2` entries are skipped by the glob.

Prototyped and driven against every R1 *fail* or *wrong* shape (`gates/p1.sh`): each gives a FAIL
naming the entry, the healthy cache none, an unreached damaged archive none, and the tree's
listing is unchanged by doctor, with nothing newer than a marker.

## Cost ([`drives/walk-cost.sh`](drives/walk-cost.sh), [`walk-cost.out`](drives/walk-cost.out))

The R6 drive's cache, ten script environments and ten `uvx` environments over a mix of packages
plus two subjects: 3142 files, 54 live entries, 65 dist-info directories, 2713 `RECORD` lines.
`uvm doctor` takes 0.29–0.33 s with the cache and 0.155 s with it moved away, so the walk is about
0.15 s, some 55 µs per `RECORD` line, bash's `read` loop and one `stat` each.

On Lustre each `stat` is a metadata round trip. At 0.2–0.5 ms per cold `stat`, this cache walks in
roughly 0.5–1.5 s. A cache holding large stacks costs more in proportion: an environment of a
package with 15 000 files, plus the wheels it was built from, is some 30 000 stats, 6–15 s. M1's
30 s finding is reachable by a user with several such environments; R6 records the figure on the
drive's cache, and the README states the per-line cost so a reader can scale it.

The walk runs once per scope, in the call holding the repair lock, after the outcome test, inside
`uvm_detect`; doctor runs the same walk. With the knob off nothing reaches it.
