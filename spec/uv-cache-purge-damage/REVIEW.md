# REVIEW — A purge that damages uv's cache breaks `uv run` and `uvx`

> Adversarial QA by `uvm-review`, run in an isolated context. The correctness pass grades the branch
> diff against [`GOAL.md`](GOAL.md) and the `AGENTS.md` invariants **only**; it does not see
> `PLAN.md` or `TECH.md`. Every finding cites an **executed** command.

## Review cycle 1 — changes-requested (2026-11-02)

- **Reviewed commit:** `50d4508` · **Base:** `8e03774` (`release/0.8.0`)
- **Verdict:** changes-requested
- **Cycle:** 1 of ≤3
- **Mode:** `debate`. Two fresh blind reviewers, each denied `PLAN.md`, `TECH.md` and every other
  file under this spec.

### Verification run

- **Static and lint:** `bash -n` and `lint.sh` are green.
- **Purge shapes:** the ship reviewer reconstructed R1's twelve failing or wrong shapes at `8e03774`.
  Every one recorded the scope repaired with no repair run, and the shapes without `pyvenv.cfg`
  wrote into the managed interpreter. At `50d4508` each shape gives a named doctor FAIL, then one
  repair under the lock, then rc 0 with the same dist-info set. The managed interpreter is
  unchanged, the repair runs from `/`, and a second call is silent.
- **Concurrency and R4:** at 16 ranks, U and S give `rebuilt=0`. The ukill scenario is green. R4
  holds for processes started through a `uvx` link. The F, T, P, kill, I and ikill scenarios are
  green, and the knob-off path is unchanged.
- **Cluster:** the cross-node run was queued at `50d4508` and cancelled once this review found
  defects in the arm.

### Requirement → evidence matrix

| R-ID | Status |
|------|--------|
| R1 | ✅ (reconstructed at the base) |
| R2 | ✅, with C1-F3's gap |
| R3 | ❌ for cached environments of unknown or command-line source (C1-F1, C1-F2); ✅ for index sources |
| R4 | ✅ |
| R5 | ✅ locally; C1-F1's script half and C1-F5 qualify it |
| R6 | local ✅; cross-node pending; C1-F4 limits what it can show |
| R7 | ✅ |
| R8 | ✅ except the walk figure, which waits on R6 (C1-F6) |

### Findings

#### C1-F1 [HIGH, wrong-source execution / CONFIRMED] A cached environment whose dist-info files were all purged is reinstalled by version from the index
- **Scenario:** `RECORD` and `direct_url.json` go together, and `RECORD` is the coldest file. Nothing
  then records the source, so the arm pins `name==version` and installs PyPI's release in place of
  a locally or URL-sourced one.
- **Observed:** reproduced with `uv run --with <local fork wheel>`. The scope recorded ok, and the
  swap persisted past the job.
- **Script environments:** the same reinstall happens, and the user's own `uv run` then re-syncs
  the environment back to the declared source. That is a waiter rebuilding an entry the repair
  "restored".
- **Breaks:** the risk row `AGENTS.md` itself gives for `uvm_repair_cache`. The README's claimed
  parity with the tool arm is false, because the tool arm also needs the receipt gone.

#### C1-F2 [HIGH / CONFIRMED] A cached environment built with a command-line `--find-links` or `--index` fails the whole scope
- **Mechanism:** the reinstall runs from `/` under `uv.toml` only, so the pin does not resolve.
  Every call in the job fails, unrelated ones included.
- **Breaks:** R3.

#### C1-F3 [MEDIUM / CONFIRMED observation] A wheel whose link was purged but whose `.http` pointer survived is never walked
- **Mechanism:** uv reaches the archive through the pointer, so a new environment is built from the
  damaged archive.
- **Observed:** doctor reports `OK no damage detected`, and the scope records ok.

#### C1-F4 [MEDIUM / CONFIRMED locally] The walk is linear in `RECORD` lines and runs under the lock
- **Measured locally:**
  - A data-science cache (pandas, scipy, scikit-learn, matplotlib, jupyterlab) has 37,633 lines;
    doctor takes 2.77 s.
  - Twenty such environments have 184,033 lines; doctor takes 11.29 s.
- **Gap in R6:** R6's prepared cache, about 2,700 lines, cannot approach M1's 30 s line, while
  per-stat round trips on a parallel filesystem plausibly cross it.

#### C1-F5 [LOW / PLAUSIBLE] The `rebuilt` key cannot see an in-place re-sync by a waiter

#### C1-F6 [LOW] The README's walk figure is a workstation figure, not the walk time R6 records

### Rulings (foreman, standing in for the human gate)

All six findings touch `uvm_repair_cache` or the walk, which are high-blast-radius regions. The
maintainer delegated the human gate to the foreman for this release.

1. **C1-F1, cached environments (the link kind).**
   - Any dist-info without `RECORD`, or any distribution whose source cannot be shown to be the
     configured index, sends the entry to the drop list: the link is removed and the archive kept,
     as M2 allows. The next call's own spec rebuilds it faithfully.
   - Pinning by version stays only where every distribution's source is known.
2. **C1-F1, script environments.**
   - Keep the in-place reinstall by version for a dist-info without `RECORD`. That is the
     commonest purge shape, M2 forbids removing a live script environment, and failing the scope
     would leave the purge unrepaired.
   - Then re-walk, and drop the entry if anything still disagrees (cycle-2 ruling of P2).
   - The README states the class plainly: such an environment comes back from the configured
     index, and when the script declares another source, uv re-syncs to it on the next call. That
     re-sync is listed among the R5 exceptions.
   - Remove the false parity claim with the tool arm.
3. **C1-F2.**
   - A failed reinstall of a cached environment falls back to dropping its link instead of failing
     the scope.
   - A failed reinstall of a script environment still fails the scope, and the README names the
     class: a script environment built with an index or find-links given only on the command line.
     Its remedies are `uv-manager clean cache --yes`, or putting the index in `uv.toml`. This is
     the same concession the tool arm makes for `uv tool install --index`.
4. **C1-F3.** Detect an unpacked wheel through its pointer files as well as its link. Do this by
   fixed-string extraction of the archive id the pointer names, if the pointer carries it readably;
   measure that first. If it does not, list the case among what is still unseen, and say why.
   Never remove an archive that no link or pointer reaches, because a running process may hold it.
5. **C1-F4.**
   - The R6 drive gains a realistic large cache: at least one data-science stack, of the order of
     tens of thousands of `RECORD` lines. Its summary records `record_lines` beside `walk_s`, so
     the cluster run measures what M1 cares about.
   - Skip `wheels-v*` buckets that the pinned uv no longer uses only if that can be shown from the
     layout, not guessed.
   - Whether to narrow the check waits for the cluster figure. The foreman rules on it with that
     number.
6. **C1-F5.** `rebuilt` also counts a dist-info set whose mtimes changed after the repair finished.
7. **C1-F6.** Run B writes R6's `walk_s` and `record_lines` into the README's figure.

#### Foreman rulings on remediation (2026-11-02)

1. **Q1, ruling 4 against R2: approved as a GOAL clarification.** R2 and the non-goal now read "no
   link or pointer (`.http`/`.rev`) reaches", with a dated clarification for C1-F3 and the measured
   pointer layout. The pointer walk is built, with gate clauses for a pointer that cannot be read
   or parsed, for one that names a missing archive, and for parity across bash versions.
2. **Q2: confirmed.** Ruling 2's "drop if anything still disagrees" covers cached environments
   only; a script environment still damaged after its reinstall fails the scope (M2).
3. **Q3: keep the `uv_cache.json` refusal for script environments.** A find-links requirement names
   only a version, so the index's release satisfies it and the swap would be silent and lasting.
4. **Q4: conceded.** A remote index given only on the command line, with the same name and version
   on the configured index, is reinstalled from the configured index; the README says so beside the
   tool arm's concession, with `uv.toml` as the remedy.
5. **5b.** Cluster figure past M1's line; the walk lists directories instead of stat-ing each path;
   narrowing is held back unless the re-run is still past 30 s.
   Re-run past the change: `walk_s` 2.6–4.7 s on the same cache, so the check is not narrowed.

## Review cycle 2 — changes-requested (2026-11-02)

- **Reviewed commit:** `47a4f07` · **Base:** `release/0.8.0` (`b8b58cc`), two-dot diff, because the
  base's harness commit is carried identically.
- **Verdict:** changes-requested
- **Cycle:** 2 of ≤3
- **Mode:** `debate`. Two fresh blind reviewers ran a full pass over the spec-excluded diff, each in its
  own scratch directory. Each was given `GOAL.md` and the raw cross-node evidence file. Neither
  received `PLAN.md`, `TECH.md`, any other spec file, or this review's earlier findings.

### Verification run

- **Static checks:**
  - `bash -n` is green under bash 3.2.
  - `lint.sh` is green.
  - On the cluster, P1, including the clause on how pointer files are read across bash versions, is
    green under bash 5.1.
- **Purge shapes:**
  - **Detection:** across 27 constructed shapes (ship reviewer) and drives d1–d13 (block reviewer),
    doctor gives a FAIL naming the damaged entry.
  - **Healthy caches:** a 50,919-file cache and a 53k-file cache, each holding a data-science stack,
    give no FAIL in about 1 s.
  - **Doctor writes nothing:** checked with a stat snapshot.
  - **Fallback:** when the awk pass is forced to fail, the fallback gives the same verdicts.
  - **Odd paths:** roots containing `//`, `/./`, `..`, a space, `[`, `*` or `,` give the same verdicts.
- **Repair:**
  - Each damaged shape is repaired by one knob-set call. The second call does no repair, and the
    managed interpreter is unchanged.
  - A process running from the environment keeps importing across the repair, in all 7 drives of
    that check.
  - With the knob unset, no cache function runs.
- **Concurrency:**
  - U, S and ukill at 16 ranks: one repair each, `rebuilt=0`.
  - F, T, P, kill, I and ikill stay green.
- **Cross-node (R6):** graded against `evidence/lustre.txt`. 128 ranks on 2 nodes, one repair,
  `rebuilt=0`, and `walk_s` of 2.6–4.7 s.

### Requirement → evidence matrix

| R-ID | Status |
|------|--------|
| R1 | ✅ (shaping drive, base side reproduced by the block reviewer) |
| R2 | ✅ |
| R3 | ❌ for a script environment whose distribution came from a find-links directory or a local file and lost its `RECORD` (C2-F1); ✅ otherwise |
| R4 | ✅ |
| R5 | ✅ |
| R6 | ✅ (evidence file) |
| R7 | ✅ |
| R8 | ✅ except the remedy text (C2-F2) and stale drive help (C2-F3) |

### Findings

#### C2-F1 [HIGH, wrong-source execution / CONFIRMED] A script environment's find-links or local-file distribution that lost its `RECORD` is reinstalled from the index
- **Where:** `bin/uv-manager` `uvm_cache_unpinnable`. For a script environment, a dist-info without
  `RECORD` is treated as pinnable, and `uv_cache.json` still on disk is never tested.
- **Observed:** a fork of `mdurl` 0.1.2 was served from a find-links directory, with the script
  declaring `find-links` and `no-index`.
  - **`RECORD` alone purged:** at `release/0.8.0` the script runs the fork. On the branch, the
    knob-set call reinstalls `mdurl==0.1.2` from the index and prints `pypi`. Every later call, with
    the knob on or off, keeps the swap.
  - **Every file of the dist-info purged:** at the base, the call fails loudly. On the branch, the
    swap is silent.
- **uv does not undo it:** uv does not re-sync a by-name requirement, so the README's claim that uv
  re-syncs to the declared source does not hold for find-links.

#### C2-F2 [MEDIUM / CONFIRMED] The README's remedy for an unpinnable script environment does not work
- **The advice:** "put the source in `uv.toml`, where the repair finds it". But the refusal reads
  `RECORD` only and never reads `uv.toml`, and `uv.toml` cannot hold `sources`.
- **The scope:** a stale environment whose undamaged distribution came from find-links fails every
  call in the scope, unrelated `uvx` calls included, even when the damaged distribution came from
  the index.

#### C2-F3 [LOW / CONFIRMED] `tests/repair-race.sh` help text still describes the per-path walk
- **Where:** lines 103 and 180.

### Rulings (foreman, standing in for the human gate)

`uvm_repair_cache` is a high-blast-radius region. The maintainer delegated the human gate to the
foreman for this release.

1. **C2-F1, the mark that survives.** A script environment's dist-info that has no `RECORD` but keeps
   `uv_cache.json`, without a `direct_url.json`, is unpinnable, the same as when a surviving `RECORD`
   lists it.
2. **C2-F1, no mark survives.**
   - Before a dist-info with no `RECORD` and no `direct_url.json` is reinstalled by version, the repair
     shows that the configured index serves the same files. It fetches `name==version` with
     `--no-deps` into a temporary target, run from `/` under the same `uv.toml`. It then compares
     the sha256 in that wheel's `RECORD` against every listed file still present in the environment.
   - Any mismatch, or a version the index does not have, makes the distribution unpinnable. The
     scope then fails naming it, with `uv-manager clean cache --yes` as the remedy.
   - A fork whose every distinguishing file was purged stays unseen. The README says so.
3. **C2-F2, the reinstall touches only damaged distributions.**
   - The in-place reinstall reinstalls only the distributions the check found damaged. Every other
     distribution in the environment stays byte-identical, and the unpinnable test applies only to
     the damaged ones.
   - An undamaged find-links distribution no longer fails the scope.
   - If uv cannot express this cleanly, keep the whole-environment reinstall and escalate.
4. **C2-F2, the README.**
   - Remove the `uv.toml` remedy. Name `uv-manager clean cache --yes` and what it costs.
   - Narrow the re-sync claim to URL, git and path sources the script declares.
   - Describe ruling 2's check and what it cannot see.
5. **C2-F3.** Correct the drive's help text to describe the listing walk.
6. **Gates.** The block reviewer's drives `d14_scope.sh`, `d15_uvtoml.sh` and `d16_fork.sh` become
   gate clauses, red at `47a4f07` and green after.
7. **Cluster.** Re-run S on Lustre after the fix, since its damage shape reaches the changed path.

## Review cycle 3 — changes-requested (2026-11-02)

- **Reviewed commit:** `4400c60` · **Base:** `release/0.8.0` (`b8b58cc`), two-dot diff.
- **Verdict:** changes-requested
- **Cycle:** 3 of ≤3
- **Mode:** `debate`. Two fresh blind reviewers ran a full pass over the spec-excluded diff, each given
  `GOAL.md` and the raw cross-node evidence file, and nothing else under `spec/`.

### Verification run

- **Static checks:** `bash -n` and `lint.sh` are green.
- **Purge shapes:**
  - **Detection:** 23 shapes across the three entry kinds (ship reviewer) and drives E1–E12 (block
    reviewer) each give a FAIL naming the entry.
  - **Doctor writes nothing:** checked with a stat snapshot.
  - **Healthy and orphan entries:** healthy caches and damaged orphan archives give no FAIL.
- **Repair:**
  - Each shape is repaired by one knob-set call with the same dist-info listing. The managed
    interpreter is untouched, and undamaged distributions stay byte-identical.
  - R4 holds for both kinds of environment.
  - The failure paths name the entry and its remedy.
  - No temporary target survives.
- **Concurrency:** all nine scenarios pass locally at 8 or 16 ranks.
- **Cross-node (R6):** green against `evidence/lustre.txt`, but measured with one damaged entry only
  (C3-F1).

### Requirement → evidence matrix

| R-ID | Status |
|------|--------|
| R1 | ✅ |
| R2 | ✅ for detection; the walk is slow on a cache with many damaged entries (C3-F1) |
| R3 | ❌ for a distribution from an HTTP index the script names (C3-F2); a scope fails on an entry the repair cannot reinstall (C3-F3, conceded class) |
| R4 | ✅ |
| R5 | ✅ |
| R6 | ✅ per the evidence, for one damaged entry |
| R7 | ✅ |
| R8 | ✅ except the walk figure (C3-F1) and the ordering prose (C3-F4) |

### Findings

#### C3-F1 [HIGH / CONFIRMED] The walk is quadratic in the number of damaged dist-info directories
- **Where:** `bin/uv-manager` `uvm_cache_check`, `rest="${gaps#*"${nl}${di}${tab}"}"`. It runs once
  per damaged dist-info, and each strip costs O(len²) in the length of `gaps`.
- **Doctor timing:** 231 dist-info directories with 30% of their files purged at random, which is
  R1's first shape. Doctor takes 47 s; at the base it takes 0 s. With only that line replaced it
  takes 1 s, with the same FAIL lines.
- **With the knob:** 451 dist-info directories. Every waiter in the scope fails at the 180 s lock
  timeout while the holder is still walking.
- **The evidence:** R6's `walk_s` measured one damaged entry.

#### C3-F2 [HIGH, wrong-source execution / CONFIRMED] A distribution from an HTTP index the script names is replaced by the configured index's build
- **Observed:** a script declares `[[tool.uv.index]]` serving its own build of `six==1.16.0`.
  `six.py` is purged, and the repair reinstalls `six==1.16.0` from PyPI. Every later call runs
  PyPI's six.
- **Why the code misses it:** the surviving `RECORD` held the fork's hashes, but the index check runs
  only when `RECORD` is gone. An HTTP index leaves no `uv_cache.json`.

#### C3-F3 [MEDIUM / CONFIRMED] An entry the repair cannot reinstall fails every call in the scope
- **Examples:** a script-named index serving a local version such as `+hpc`, or latent damage in a
  file://-index environment. In each, every call in the scope fails, unrelated calls included.
- **Context:** this is the documented failure semantics of R3 and M2.

#### C3-F4 [LOW / CONFIRMED] Prose says every removal precedes the arm's first `uv` call
- **Where:** `invariants.md` §8, `AGENTS.md` and the README.
- **What the code does:** the index check's `uv pip install --target` runs before the drop loop. The
  protected property still holds: no uv call reaches the base interpreter through a pyvenv-less
  environment.

### Foreman ruling at the cycle cap (ship / abandon / rescope)

Cycle 3 is the last that may request changes, so this choice falls to the maintainer. The maintainer
delegated the human gate for this release to the foreman, with the instruction to stop only for a
significant departure from the seeds' spirit. These findings are defects inside the seed's intent, not
a departure from it. **Ruling: rescope.**

1. **C3-F1.** Make the walk linear in the total number of gap lines: one pass, with no per-dist-info
   strip of the whole buffer. A P1 clause runs the walk on a many-damaged-entries cache and must finish
   within a small multiple of the healthy walk. Report the 30%-random-purge figure in the README beside
   the one-entry figure.
2. **C3-F2.** Every damaged distribution that the script arm would pin by version, `RECORD` or not, goes
   through the index check. Batch the fetch: one `uv pip install --target --no-deps` per environment,
   for all its damaged distributions.
   - Where `RECORD` survives, compare its sha256 entries with the fetched release's `RECORD`. Exclude
     the files uv writes at install: `RECORD`, `INSTALLER`, `REQUESTED`, `direct_url.json`,
     `uv_cache.json` and `bin/`.
   - Where `RECORD` is gone, compare the files still present, as now.
   - A mismatch fails the scope naming the distribution, with `uv-manager clean cache --yes` as the
     remedy.
3. **C3-F3: conceded and documented.** The README names the class:
   - a distribution from an index the script names, when the configured index lacks that build or
     serves another;
   - for which a damaged environment fails every call in the scope under the knob, while
     `uv-manager clean cache --yes` clears it.

   Failing loudly is preferred to a swap, and that is the project's stated failure mode.
4. **C3-F4.** Restate the prose: "before the arm's first `uv` call that could reach the base
   interpreter".
5. **Verification.** After the fix:
   - re-run U, S and ukill on Lustre at the final commit;
   - run a confirmation review scoped to the remediation delta, recorded as cycle 4 under this ruling;
   - the 0.8.0 PR names the cycle cap as exceeded under the foreman's delegation, so the maintainer's
     PR review is the final gate.

## Review cycle 4 — changes-requested, maintainer ruling (2026-11-02)

- **Reviewed commit:** `3a9ac04` · **Range:** `4400c60..3a9ac04`, spec-excluded. The scope is the
  cycle-3 remediation delta: 5 files, mostly code (`bin/uv-manager`, about 245 lines), plus prose in
  `README.md`, `AGENTS.md`, `invariants.md` and `etc/uv-manager.conf.example`.
- **Mode:** scoped, one fresh blind reviewer arguing "block". This cycle runs past the cap under the
  foreman's cycle-3 rescope, and its verdict went to the maintainer.
- **Cross-node:** Lustre at `3a9ac04` is green: U and S at 128/128 with one repair, and ukill green.
  P1 and P2 are green under bash 5.1.

### Verification run

- **Bookkeeping:** the new walk bookkeeping gives doctor output byte-identical to `4400c60`. This held
  on 6 seeds of synthetic caches and on the edge cases: symlinked directories, dangling links and
  shared pointers. It held through awk and with awk forced to fail.
- **Speed:** about 900 dist-infos with a 30% purge take 0.74 s, against 345.7 s at `4400c60`.
- **Index check on wheels:** no false refusal across setuptools (`.pth`), docutils (`.data/scripts`),
  zope.interface, ruamel.yaml, typing_extensions and tqdm. That held with `RECORD` kept and gone, and
  with and without `UV_COMPILE_BYTECODE`.
- **Temporary targets:** none left on success or on a failed fetch.
- **Concurrency:** U, S and F are green at 16 ranks.

### Findings

#### C4-F1 [HIGH / CONFIRMED] The widened index check refuses configured-index distributions that uv built from an sdist
- **Cause:** a build is not byte-reproducible. A C extension's `.so` differs between builds, and so do
  `METADATA` and `WHEEL` once the build backend has had a newer release.
- **Observed:**
  - markupsafe 2.0.1 (cp312 sdist) with one module purged and `RECORD` kept: the scope fails. At
    `4400c60` the call exits 0.
  - docopt 0.6.2 built under an older `UV_EXCLUDE_NEWER`: the same.
  - In a cached environment the mismatch only removes the link, which is benign.

#### C4-F2 [LOW / CONFIRMED] An unreachable index is reported as one that does not serve the distribution
- **Why it misleads:** the reason prescribes `clean cache`, which cannot help while the network is down.

### Maintainer ruling (Geoffrey, 2026-11-02, in chat): narrow the check

1. **Compare source files only.** For every distribution checked, compare only the source files
   (`*.py` and `*.pyi` outside the dist-info) against the fetched release.
   - This holds whether the environment's `RECORD` survives, when its hashes are compared, or is gone,
     when the files present are hashed.
   - A fork that changes Python code is still refused.
   - A fork that differs only in compiled binaries or packaging metadata is conceded in the README.
2. **Separate a failed fetch from a differing release.** A fetch that fails, for an unreachable index or
   any other reason, gets its own reason, which does not prescribe `clean cache`. A release that the
   configured index lacks, or that differs, keeps the current reason and remedy.
3. **Gates.** C4-F1 (markupsafe 2.0.1 sdist, and docopt built under an older `UV_EXCLUDE_NEWER`) and
   C4-F2 become gate clauses, red at `3a9ac04`.
4. **Verification.** Re-run Lustre at the final commit, then run one more scoped confirmation review.
   The 0.8.0 PR names the cycle-cap overrun, and the maintainer's PR review is the final gate.

## Review cycle 5 — changes-requested, maintainer ruling (2026-11-02)

- **Reviewed commit:** `e61e360` · **Range:** `3a9ac04..e61e360`, spec-excluded, 5 files. Of the
  roughly 78 changed lines in `bin/uv-manager`, most are code. The rest of the delta is prose in
  `README.md`, `AGENTS.md`, `invariants.md` and `etc/uv-manager.conf.example`.
- **Mode:** scoped, with one fresh blind reviewer arguing "block". The cycle runs past the cap under the
  maintainer's cycle-4 ruling.
- **Cross-node:** green at `e61e360` on a second Lustre scratch, 2 nodes × 64 ranks, with bash 4.4.
  P1 and P2 are also green under bash 4.4.

### Verification run

- **Refusal of a fork:** a fork from an index the script names, differing in a `.py` file, is refused
  both with `RECORD` kept and with it gone.
- **Error capture:** the stderr capture works under bash 3.2. uv's output never reaches stdout.
- **Clean exit:** no temporary target is left on any path, and an unset knob never reaches the check.
- **Concurrency:** U and S pass at 16 ranks.

### Findings

#### C5-F1 [HIGH / CONFIRMED, not a regression] A distribution uv built from the configured index's own sdist is still refused when its build writes a build-time path into a `.py`
- **Example:** numpy 2.1.3 under `no-binary`. Meson writes the temporary build interpreter's path into
  `numpy/__config__.py`, so every build differs. The scope fails.
- **History:** `3a9ac04` refused the same case.

#### C5-F2 [MEDIUM / CONFIRMED] A version the index lacks, reported with a uv `hint:`, reads as a failed fetch
- **Example:** an `exclude-newer` cutoff. Clearing the cache is the remedy that works, but the reason
  drops it.

#### C5-F3 [LOW / CONFIRMED] Under `FORCE_COLOR=1`, the `hint:` match fails on ANSI codes
- **Effect:** a 401 reads as a release the index does not serve.

### Maintainer ruling (Geoffrey, 2026-11-02, in chat): compare wheels only

1. **Where the hash comparison applies.**
   - The hash comparison applies only to wheels. When the environment's dist-info or the fetched
     release's dist-info carries `uv_build.json`, uv built that distribution from an sdist. The check
     then only confirms that the configured index serves `name==version`.
   - The README concedes the remaining gap: a fork served as an sdist, from an index the script names,
     at the same version.
2. **How a fetch failure is decided.**
   - A fetch failure is decided from positive markers: exit status 2, `Failed to fetch`, the offline
     wording, or a 401/403 hint.
   - Colour is forced off for the fetch.
   - Every other non-zero exit is a release the index does not serve, and its reason names
     `uv-manager clean cache --yes`.
3. **Gates.** New clauses cover:
   - numpy built under `no-binary` (or a lighter package whose build writes a path into a `.py`);
   - a version missing behind an `exclude-newer` hint;
   - a 401 under `FORCE_COLOR=1`.

   Each must be red at `e61e360`.
4. **Close-out.** Re-run the cross-node scenarios at the final commit. No further review cycle runs:
   the maintainer's review of the 0.8.0 PR is the final gate.
