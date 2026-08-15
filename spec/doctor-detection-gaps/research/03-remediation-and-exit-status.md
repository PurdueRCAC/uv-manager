# 03 — What the remediation block should say, and how the exit status splits

Grounded in `spec/purge-resilient-run/research/04-uv-repair-idioms.md`, which measured the idioms
directly against real `uv 0.12.3`. Nothing here re-derives those measurements; this brief turns them
into text and pins the classification rule R3 needs.

## 1. `FAIL` sets the exit status, `WARN` does not

R3 needs a rule, not a list, or the next finding added to doctor has no home. The rule that fits the
existing output with no new vocabulary:

> A `FAIL` means the tree does not work and sets the exit status. A `WARN` is information about a tree
> that does work and does not.

Exactly one existing finding moves under it — the receipt-less tool directory, already spelled `WARN`
at `bin/uv-manager:689` and already the only non-`FAIL` in the function. Every other finding describes
something broken. So the code change is two counters where there was one, and the documented contract
is the sentence above.

The `problems == 0` branch still has to say something true when advisories exist. `OK    no damage
detected` alone would read as though nothing was printed above it:

```
OK    no damage detected under <root> (1 advisory above)
```

keeps the `OK` token that automation greps for while not contradicting the line above it.

## 2. The remediation text

Three commands become two, and the two are whole-tree, so the wrapper never enumerates anything and
never reconstructs a version spec — which is what makes them safe (research `04` §1, §2).

- **`uv tool upgrade --all --reinstall --no-cache`.** `--no-cache` is the load-bearing flag: uv runs no
  integrity check on its unpacked `archive-v0` store, so every repair that reuses the cache reinstalls
  the same damage. Measured: `uv tool install`, `uninstall && install`, and `--reinstall` alone all
  exit 0 and leave the tool broken; only the `--no-cache` forms work. `upgrade --reinstall` rather than
  `install --reinstall` because the latter destroyed a user's pin permanently — `tqdm==4.66.0` was
  silently upgraded to 4.70.0 and the receipt rewritten.
- **`uv python install --reinstall`**, no target, which reinstalls every managed python. This one
  requires egress: uv never caches the interpreter tarball, so it is a fresh ~24 MiB fetch.

**`uv-manager install` is deleted, not replaced.** It re-resolves latest and repoints `current`,
overriding a site pin (`UVM_PIN=6.6.6` → `current -> versions/9.9.9`), and it is unnecessary: an
ordinary `uv` call re-provisions and honors the pin, measured both ways in `02-doctor-baseline.md` §5.
The missing-binary case needs a sentence, not a command.

**The `pyvenv.cfg` class needs its own sentence** and R2 requires it. Neither command above repairs it,
and an in-place repair escapes the tree entirely — observed writing into
`/opt/homebrew/lib/python3.14/site-packages`. `uv tool install --force --no-cache <spec>` does rebuild
the venv, but `<spec>` is the version trap from research `04` §2, so the honest instruction is manual
and names the cost: remove the directory and install the tool again, choosing the version, because the
receipt's recorded requirement may not be the version that was installed.

## 3. Emission

A heredoc through `cat`, per invariant §7 — `cat` dies quietly on `SIGPIPE` where bash's `printf`
builtin reports `write error: Broken pipe`, which `uvm doctor | head -1` produces today at
`bin/uv-manager:744`. The block interpolates one value (the failure count), which a quoted-delimiter
heredoc would suppress, so the delimiter stays unquoted and every literal `$` in the body must be
escaped or absent. There are none in the drafted text — worth re-checking at build time rather than
trusting this sentence.

## 4. The advisory's own line has to carry its remedy

With the block above gated on failures, a tree whose only finding is advisory prints no remediation at
all. The advisory line therefore has to be self-contained: uv ignores a receipt-less directory
(`uv tool upgrade --all` exits 1 with `` `<name>` is not installed `` and leaves it), so the reader is
told to remove the directory or reinstall the tool by name.
