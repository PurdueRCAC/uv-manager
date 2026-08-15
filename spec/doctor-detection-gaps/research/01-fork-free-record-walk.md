# 01 — The fork-free `RECORD` walk: where the cost actually is, and what equivalence requires

**Conclusion, high confidence (measured): the walk is 6.5× faster fork-free, the forks are per
*distribution* rather than per file, and one guard — `|| [[ -n "${rel}" ]]` — is the difference
between a byte-identical verdict and silent blindness on a class of real `RECORD` files.**

Host: macOS 25.5, arm64, APFS on local SSD, **bash 3.2.57** (the portability floor, so every construct
below is proven at the floor rather than assumed). Synthetic tree: 4 tools × 25 distributions × 40
files = 100 `dist-info`s, 4112 files.

## 1. R5's wording is loose; the saving is real anyway

R5 says "without forking per file". The per-file loop is already fork-free — `[[ -e ]]` is a builtin.
The forks are **per distribution**, and there are six of them:

| Site (`bin/uv-manager:706-721`) | Processes per `dist-info` |
|---|---|
| `sp="$(dirname -- "$(dirname -- "${record}")")"` | 2 command substitutions + 2 `dirname` execs = 4 |
| `< <(awk -F, … "${record}")` | process substitution + `awk` exec = 2 |
| `$(basename -- "$(dirname -- …)" .dist-info)` — only on a finding | 4 more |

At 100 distributions that is ~600 processes before any finding. The design replaces all of them with
parameter expansion and a plain `< "${record}"` redirect.

Measured, three runs each, intact tree:

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| current | 0.55 s | 0.51 s | 0.52 s |
| fork-free | 0.08 s | 0.08 s | 0.08 s |

**6.5×**, better than the seed's estimated 4× on its differently-shaped tree. The absolute numbers are
tree-shaped, so the phase gate should assert the *verdict*, not a threshold — see §4.

## 2. The design

```bash
for di in "${uvm_root}"/tools/*/lib/*/site-packages/*.dist-info; do
  [[ -d "${di}" ]] || continue
  name="${di##*/}"; name="${name%.dist-info}"
  record="${di}/RECORD"
  sp="${di%/*}"
  if [[ ! -f "${record}" ]]; then
    ... report the missing manifest ...      # R1
    continue
  fi
  missing=0; total=0
  while IFS=, read -r rel _ || [[ -n "${rel}" ]]; do
    [[ -n "${rel}" ]] || continue
    rel="${rel#\"}"; rel="${rel%\"}"
    case "${rel}" in ../*|/*) continue ;; esac
    total=$(( total + 1 ))
    [[ -e "${sp}/${rel}" ]] || missing=$(( missing + 1 ))
  done < "${record}"
  ...
done
```

Globbing `*.dist-info` instead of `*.dist-info/RECORD` collapses R1 and R5 into **one** glob where the
naive reading of R1 adds a second. Research `02-bounded-integrity-check.md` measured that glob at
19.6 ms per 800 `dist-info`s, so the collapse is worth having rather than cosmetic.

## 3. Equivalence, including the parts that look like bugs

`awk -F,` splits on every comma regardless of CSV quoting, so a `RECORD` line for a path containing a
comma yields a truncated first field, which `gsub(/^"|"$/…)` then unquotes. That is wrong, and the
bash version reproduces it **exactly** — `IFS=, read -r rel _` truncates at the same comma and
`${rel#\"}`/`${rel%\"}` strips the same quote. Byte-identical verdict means preserving this, not
fixing it; a correct CSV parse would change findings on real trees and is outside R5.

Verified identical on a `RECORD` combining every case — normal line, blank line, `"quoted,comma.py"`,
a `../` escape, an absolute path, a bare `,,`, and a final line with no trailing newline — and again on
a CRLF variant. On the damaged 100-distribution tree, the two implementations' `FAIL … is missing N of
M files` lines are identical.

## 4. The guard is load-bearing, and its absence is silent

`RECORD` files whose final line has no trailing newline exist. Without `|| [[ -n "${rel}" ]]`, bash's
`read` returns non-zero on that last line and the loop discards it:

```
awk (current, ground truth): FAIL  e-1.0 is missing 1 of 2 files (partial purge)
new WITH guard:              FAIL  e-1.0 is missing 1 of 2 files (partial purge)
new WITHOUT guard:           (silent)
```

`awk` has no such behavior, so this is a regression the rewrite can introduce and nothing else would
catch: the tree is damaged, the walk is fast, and doctor says nothing. **The phase gate must include a
no-trailing-newline `RECORD`.** A gate built only from well-formed fixtures goes green with this bug in
place.

A methodology note for whoever writes the gate: the first attempt to test this used `sed` to strip the
guard from a copy, and the `sed` silently matched nothing, so "without guard" and "with guard" were the
same file and the test passed meaninglessly. Assert that a fixture mutation actually applied.

## 5. What this does not establish

Local SSD, warm metadata, one host. On Lustre with a cold MDS the filesystem term dominates and the
ratio compresses — the fork saving stays, the relative win shrinks. Consistent with the parallel-
filesystem caveat already recorded in `spec/purge-resilient-run/research/02-bounded-integrity-check.md`;
neither can be measured off-cluster.
