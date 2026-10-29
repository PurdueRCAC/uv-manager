# Research 02: publish (R4, R10)

Measured on macOS 27 with `/bin/bash` 3.2.57 and BSD `mv`, against throwaway copies of the worktree
under `$TMPDIR`. Anything about GNU or busybox is marked **read, not run**: neither is installed and
no container is available.

## Verdict on the hypothesis

The hypothesis holds: keep `mv "${tmp}" "${dest}"`, capture its stderr, and detect the outcome
afterwards. Two corrections:

1. **Window (b) also kills a rank on `main`.** When the rival lands between `mv`'s stat and
   rename(2), `main` exits **rc 1 with empty stdout** and leaves `.incoming.*` behind. R4's
   "every process SHALL exit 0" is red here as well as in the nesting case.
2. **R4 has a second nesting source: `uvm_point_current`.** Its fallback `rm -f current; mv tmp
   current` runs on every macOS call, because `mv -T` does not exist there. If a concurrent rank
   recreates `current` between the `rm` and the `mv`, `mv` follows the symlink and moves the
   `.current.<pid>` symlink inside `versions/<ver>`, still at rc 0. Measured on the unpatched copy
   with 3 rounds of 16 pinned ranks re-pointing `current`: **23 `.current.*` symlinks** inside
   `versions/6.6.6`. BSD `mv -h` does not follow a symlink target and replaces it with rename(2).
   Inserting it between `-T` and the fallback brought the count to **0** under the same probe.
   R12's `ln` shim (sleep 2) widens exactly this window.

## Q1: `mv dir existing_dir`

| implementation | onto an existing non-empty dir | `-n` | status |
|---|---|---|---|
| BSD/macOS `mv` | moves inside (`dest/.incoming.X`), rc 0 | skips silently, **rc 0** | run |
| BSD, nested name already exists and is non-empty | `rename … Directory not empty`, rc 1 | n/a | run |
| BSD `mv -T` | `illegal option -- T`, rc 64 | n/a | run |
| rename(2) (perl) | `Directory not empty`, atomic, nothing moved | n/a | run |
| rename(2) onto an **empty** dir | succeeds and replaces it | n/a | run |
| GNU coreutils (master) | tries `renameatu(…, RENAME_NOREPLACE)` first. On failure, `target_directory_operand` sees a directory and moves the source inside it | `-n` maps to `--update=none` | read, not run |
| busybox | stats dest; for a directory it appends the basename and moves inside | skips at `RET_0`, rc 0 | read, not run |

`RENAME_NOREPLACE` does not change the outcome. When dest already exists, GNU still nests. It
does change window (b): there is no separate stat, so GNU nests where BSD gets `ENOTEMPTY`. The
detection handles both. Which coreutils release introduced the `renameatu` call was not
established. `mv -n` is useless as a guard, because it reports a skip as rc 0 (BSD, busybox).

## Q2: windows and residue

- **(a) dest appears before `mv`'s stat:** `mv` nests and returns rc 0. Caught by
  `[[ -e "${dest}/${tmp##*/}" ]]`. Constructed by the R4(a) shim.
- **(b) dest appears between the stat and rename(2):** BSD fails `ENOTEMPTY`. Caught by "mv failed
  and `${dest}/uv` is executable", which discards `${tmp}` and carries on. Constructed by a shim
  that runs `cp -R "$1" "$2"` and then calls rename(2) through perl. Unpatched: `rc=1 stdout=[]`,
  1 `.incoming.*` left. Patched: `rc=0 stdout=[uv 9.9.9 (fixture)]`, `9.9.9=[uv uvx]`, 0 left,
  `current=versions/9.9.9`.
- **Residue from a loser killed between the nest and its cleanup** is
  `versions/<ver>/.incoming.XXXXXXXX`, a complete copy. I planted one and measured:
  - `uvm versions` printed `9.9.9`. The `*/` glob skips dot-dirs and `uvm_list_versions` reads
    only `${d}uv`.
  - `uvm doctor` rc 0, OK. It checks only `real_uv`.
  - `uvm status` was correct.
  - `uv --version` printed `uv 9.9.9 (fixture)`.

  It costs one uv's disk space, `uvm clean` removes it with the tree, and nothing misreads it. It
  is also invisible to `doctor`, as top-level `.incoming.*` already is. A WARN for it is optional.
- **A residue-free primitive at the floor: none.**
  - `mkdir dest` claim + fill puts a partial tree at a version path, which §6 forbids. A killed
    filler can leave `uv` without `uvx`, and that passes `uvm_have`.
  - Publishing with `ln -s` nests too: `ln -s .incoming.A v/9.9.9` onto a real dir returned rc 0
    with the link inside. `ln -sn` refuses only a symlink. It also changes the layout:
    `versions/<ver>` becomes a symlink, the hidden dir stays, and `*/` follows symlinks.
  - Rename to a fresh name then swap needs `RENAME_EXCHANGE` (Linux syscall; `mv --exchange` only
    in recent coreutils), which is not a floor primitive.
  - rename(2) through perl or python is atomic and leaves no residue. It adds a dependency and
    changes the call shape, so the shims stop reaching it.

## Rejected list: is this the "exclusive rename"?

No. The rejected design used rename as a mutual-exclusion primitive. Its failure was that `mv`
nests and exits 0, so both breakers believe they hold the lock, and acting on that belief destroys
an established lock. Publish needs no exclusion. Both copies are the same version, and either
winning is correct. The proposal does not trust `mv`'s rc 0 as "I won". It turns the nesting the
rejection documents into the loss signal, and the loser removes only its own uniquely named
`mktemp` directory, never the rival's tree. Nothing is composed or restored. The `mv -h` swap of
`current` is not a lock either: it is an atomic last-writer-wins replace of a symlink.

## Recommended publish (patched copy, `bash -n` ok)

```bash
  local url tmp ver dest err
  ...
  dest="${uvm_versions}/${ver}"
  # mv onto an existing directory moves the source inside it and exits 0, and
  # no no-clobber directory rename exists at the floor; so detect, don't prevent.
  if [[ -d "${dest}" ]]; then
    rm -rf "${tmp}" 2>/dev/null || true   # already had this version
  elif ! err="$(mv "${tmp}" "${dest}" 2>&1)"; then
    rm -rf "${tmp}" 2>/dev/null || true
    if [[ ! -x "${dest}/uv" ]]; then      # no rival published it either
      uvm_unlock
      die "cannot publish uv ${ver} into ${dest}: ${err}"
    fi
  elif [[ -e "${dest}/${tmp##*/}" ]]; then
    rm -rf "${dest:?}/${tmp##*/}" 2>/dev/null || true  # a rival won; mv nested ours
  fi
```

The change to `uvm_point_current`: `if ! mv -T "${tmp}" "${uvm_current}" 2>/dev/null && ! mv -h
"${tmp}" "${uvm_current}" 2>/dev/null; then` followed by the existing fallback. With
`set -e` under bash 3.2, `if ! err="$(/bin/mv /nonexistent/a /nonexistent/b 2>&1)"` caught
`mv: rename … No such file or directory` and execution continued.

Patched R10 stderr:
`uv-manager: cannot publish uv 9.9.9 into <root>/versions/9.9.9: mv: rename <root>/versions/.incoming.aLOzPC5V to <root>/versions/9.9.9: Permission denied`.
rc 1, no `.incoming.*`, lock released.

## Q3: gates (red on unpatched, green on patched)

Both run as `.agents/factory/bin/temp_root.sh --offline sh <file>`. Each shim appends to
`mv.hits`, and the first assertion fails if the shim never fired (see Q4).

```sh
# R4(a): a rival publishes between the -d check and the rename.
sh="$UVM_SANDBOX/shim"; mkdir -p "$sh"
cat > "$sh/mv" <<'SHIM'
#!/bin/sh
case "${1:-}" in
  */versions/.incoming.*)
    echo hit >> "$UVM_SANDBOX/mv.hits"
    [ -e "$2" ] || cp -R "$1" "$2" ;;
esac
exec /bin/mv "$@"
SHIM
chmod +x "$sh/mv"; PATH="$sh:$PATH"; export PATH
root="$UVM_ROOT/$(uname -m)"
uv --version > "$UVM_SANDBOX/out" 2> "$UVM_SANDBOX/err"; rc=$?
if [ ! -s "$UVM_SANDBOX/mv.hits" ]; then echo "FAIL: shim never intercepted the publish (call shape changed)" >&2; exit 1; fi
if [ "$rc" -ne 0 ]; then echo "FAIL: rc=$rc" >&2; cat "$UVM_SANDBOX/err" >&2; exit 1; fi
if [ "$(cat "$UVM_SANDBOX/out")" != "uv 9.9.9 (fixture)" ]; then echo "FAIL: stdout=[$(cat "$UVM_SANDBOX/out")]" >&2; exit 1; fi
got=$(ls -A "$root/versions/9.9.9" | tr '\n' ' ')
if [ "$got" != "uv uvx " ]; then echo "FAIL: versions/9.9.9 holds [$got]" >&2; exit 1; fi
left=$(find "$root/versions" -name '.incoming.*' | wc -l | tr -d ' ')
if [ "$left" -ne 0 ]; then echo "FAIL: $left .incoming.* left" >&2; exit 1; fi
if [ "$(readlink "$root/current")" != "versions/9.9.9" ]; then echo "FAIL: current -> $(readlink "$root/current")" >&2; exit 1; fi
if [ -e "$root/.install.lock" ]; then echo "FAIL: lock left" >&2; exit 1; fi
echo "R4a ok"
```

The R10 gate uses the same frame with a different shim body and different assertions.

- **Shim body:** `echo hit >> "$UVM_SANDBOX/mv.hits"; echo "mv: rename $1 to $2: Permission denied" >&2; exit 1 ;;`
- **Assertions,** after the hits check:
  - `[ "$rc" -eq 0 ]` → FAIL
  - `! grep -q '^uv-manager: .*publish.*9\.9\.9.*Permission denied' err` → FAIL
  - stdout non-empty → FAIL
  - `.incoming.*` count ≠ 0 → FAIL
  - `versions/9.9.9` exists → FAIL
  - `.install.lock` exists → FAIL
  - otherwise `echo "R10 ok"`

Recorded:
- **Unpatched R4(a):** `FAIL: versions/9.9.9 holds [.incoming.bCRAqinB uv uvx ]`, rc 1.
- **Unpatched R10:** `FAIL: no uv-manager: line naming the failed publish` (stderr shows only the
  bare `mv: rename … Permission denied`), rc 1.
- **Patched:** `R4a ok` and `R10 ok`, rc 0 for both.

A gate for the `current` nesting needs pinned ranks re-pointing `current` concurrently on a tree
holding two versions. The assertion is that no `.current.*` exists under `versions/*/`. It is red
on unpatched (23 symlinks) and green with `mv -h`.

## Q4: call shape

`err="$(mv "${tmp}" "${dest}" 2>&1)"` still reaches the shim (hits recorded), because command
substitution changes neither PATH lookup nor argv. What breaks the shim silently is anything that
moves the staging path out of `$1` or bypasses PATH:
- `mv -- …` or `mv -f …`
- `/bin/mv`
- a relative `cd versions && mv .incoming.X …`
- staging outside `versions/.incoming.*`

Measured with `mv -- "${tmp}" "${dest}"`: the shaping drive `r4_nested_publish.sh` went **green
vacuously** (`uv uvx`, 0 incoming), and the gate above failed with `shim never intercepted the
publish`. Keep the call byte-shaped as `mv "${tmp}" "${dest}"`, and keep the hit-count assertion
beside the gate.
