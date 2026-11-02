# 02 — Records: format, writing, and the backfill (R2, R8, R9, N7)

Measured 2026-11-01, uv 0.13.6, bash 3.2.57 (macOS `/bin/bash` and `/bin/sh`). Drives:
[`drives/list-renderings.sh`](drives/list-renderings.sh),
[`drives/replay-matrix.sh`](drives/replay-matrix.sh) (sections G-K). Every idiom below was
executed at the portability floor before the design adopted it.

## Format

One directory per tool, `$UVM_DATA/tools/<name>/`, `<name>` being uv's own directory name under
`UV_TOOL_DIR`. Plain files, one item per line, never TOML:

| File | Holds | From |
|---|---|---|
| `request` | the arguments after `uv tool install`, one per line, URL userinfo stripped | the command line (or the backfill) |
| `constraints` | one per distribution: `name==version`, or `name @ <vcs>+<url>@<commit>` / `name @ <url>` | dist-info names; `direct_url.json` |
| `python` | the interpreter's major.minor | `pyvenv.cfg` `version_info` |
| `entrypoints` | the executables uv linked into `UV_TOOL_BIN_DIR` for this tool | `bin/*` whose shim is the same file |
| `uv-receipt.toml` | uv's receipt, byte for byte, copied and never parsed | the tool directory |

`constraints` is a file uv reads with `-c` as is. Size, measured for the unpinned pair tool: 329
bytes of content in five files; `du -sk` reports 20 on APFS (one 4 KB block per file). The gate
bounds `du -sk` per record at 24.

**Entrypoints without a fork.** For each `tools/<name>/bin/*`, the test `[[
"${UV_TOOL_BIN_DIR}/${f##*/}" -ef "${f}" ]]` is true exactly for the executables uv linked (uv's
shims are symlinks into `tools/<name>/bin/`, measured for 10 tools including `coverage`'s three and
the git tool's `pb`); `python` and the activate scripts have no shim. Builtin, bash 3.2.

**`direct_url.json` without a JSON parser.** uv writes it compact on one line:
`{"url":"https://github.com/glentner/progressbar","vcs_info":{"vcs":"git","commit_id":"837e…"}}`.
`[[ "${json}" =~ \"url\":\"([^\"]*)\" ]]`, `\"commit_id\":\"([0-9a-f]+)\"` and
`\"vcs\":\"([a-z]+)\"` extract the three fields under bash 3.2 (executed). PEP 610 forbids
credentials in that URL; the wrapper strips them again anyway.

**Userinfo.** Executed under bash 3.2:

```bash
while [[ "${a}" =~ ^(.*://)([^/@]*)@(.*)$ ]]; do
  pre="${BASH_REMATCH[1]}" ui="${BASH_REMATCH[2]}" post="${BASH_REMATCH[3]}"
  if [[ "${pre}" == *ssh:// && "${ui}" != *:* ]]; then break; fi
  a="${pre}${post}"
done
```

| In | Out |
|---|---|
| `--index-url=https://__token__:SECRETMARK@pypi.org/simple` | `--index-url=https://pypi.org/simple` |
| `git+https://user:tok@github.com/x/y@v1` | `git+https://github.com/x/y@v1` |
| `https://__token__@host/simple` | `https://host/simple` |
| `git+ssh://git@github.com/x/y@v2` | unchanged: a login, not a secret, and the replay needs it |
| `git+ssh://git:pw@github.com/x/y` | `git+ssh://github.com/x/y` |
| `git+https://github.com/x/y@v1`, `pkg==1.0` | unchanged (`[^/@]*` cannot cross the first `/`) |

The receipt copy is kept only when no `http(s)`/`ftp` URL in it carries userinfo; uv strips it
anyway (01), so this is a guard, never the common path.

## Writing: which tools, and atomically

**Which tools a `uv tool` command changed.** Before `uv tool install|upgrade|uninstall`, one line
per tool: its name, its receipt's `cksum`, its receipt's inode (`ls -i`), and its dist-info names
(one `cksum` and one `ls` for all receipts, globs for the rest). After an exit 0, each changed or
new line is a tool the command installed or upgraded. The inode is load-bearing: `uv tool install
--force pyflakes==3.2.0` over an identical install writes a new receipt (inode 54304452 →
54304561) with the same bytes and the same dist-infos, and without the inode it read as unchanged.
For `install`, exactly one changed tool takes the arguments as typed; any other count rewrites each
changed tool keeping its recorded request. For `uninstall`, a tool present before and gone after
loses its record. A non-zero exit writes nothing (R2).

**No reader sees half a record.** A directory cannot be renamed over a non-empty one, and `mv`
onto an existing directory moves the source inside it (re-executed: BSD `mv` nests, as §6 records
for GNU and busybox). So the writer stages the whole record as `tools/.<name>.<pid>/`, moves the
old record aside, renames the stage in, and removes the old one. A reader sees the old record,
none, or the new one. "None" for that instant reads as an unrecorded tool, which is 0.7.0's
behaviour. A rival writer landing between the two renames nests the stage inside its record; the
writer removes its own nested stage, as §6's publisher does.

## The backfill (N7)

Where it runs: in doctor, after every `uv tool` command that exits 0, and in the knob-set walk's
holder before it detects. Each writes a record only for a tool that has a receipt and `pyvenv.cfg`
and no record, and never rewrites one. The request comes from uv's own rendering, one `uv tool
list --show-version-specifiers --show-with --show-extras` call (run from `/` with
`UV_NO_CACHE=1`), made only when some tool lacks a record. Renderings measured:

```
coverage v7.6.1 [required: ==7.6.1] [extras: toml] [with: tomli==2.0.1] [CPython 3.12.16]
pycodestyle v2.11.1 [required: ==2.11.1] [extras: x] [with: six==1.16.0, tomli==2.0.1]
pycodestyle v2.15.0 [with: six]
progressbar v1.2.1 [required:  git+https://github.com/glentner/progressbar]
progressbar v1.2.1 [required:  git+https://github.com/glentner/progressbar@837e34e…]
pycowsay v0.0.0.2
lp v0.1 [required: file:///…/lp]
pyflakes v3.2.0 [required: ==3.2.0] [with: six==1.16.0]
```

Rebuilt as a request: a `[required: ]` naming a URL is the request; otherwise
`<name>[<extras>]<specifier>`; each `[with: ]` item, split on `, `, is `--with <item>`. Notes:

- `[required:` is followed by two spaces before a VCS URL; the match takes ` +`.
- A URL archive has no `[required: ]` (`pycowsay v0.0.0.2`). Its backfilled request is the name,
  and its constraint `pycowsay @ <url>` pins the source; that form restores from the URL (01).
- `--with-requirements reqs.txt` is folded by uv into the receipt's requirements, so the rendering
  is `[with: six==1.16.0]` and a backfilled record of such a tool is restorable, where a record
  written from the typed command (which names the file) is refused (N9).
- A local source renders `file://`, so its constraint carries `@ file:` and the restore refuses it.
- Interpreter: the record's `python` comes from `pyvenv.cfg` as for any record.

The R8 drive (P3 gate) builds a tree with `release/0.8.0`'s wrapper (the tool pair and the git
tool), then runs the branch's `uvm doctor`: three records, a `find "$UVM_ROOT" -type f -exec cksum
{} +` listing identical before and after, and each tool in shape (W) restored by name from its
backfilled record with the dist-info listing unchanged. Green on the prototype.
