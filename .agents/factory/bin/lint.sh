#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# The static gate: syntax, shellcheck, and repository-shape checks that a factory
# `verify:` command can depend on. Until the project has a test suite this is the
# cheapest real signal available, so it must stay green — a gate with a known
# failure is not a gate.
#
# Usage:
#   .agents/factory/bin/lint.sh            # all checks
#   .agents/factory/bin/lint.sh --no-net   # skip shellcheck if it needs downloading
#
# The linter is preferred from PATH, and otherwise obtained through
# `uvx --from shellcheck-py shellcheck` — no system install, and the tool this
# project wraps supplies its own linter.
#
# Exit codes: 0 all checks passed · 1 a check failed · 3 a check could not be run
# (missing tool). 3 is distinct from 1 on purpose: "could not run" must never be
# mistaken for "passed".

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(CDPATH='' cd -- "$here/../../.." && pwd -P)
cd "$repo"

no_net=''
[ "${1:-}" = "--no-net" ] && no_net=1

failed=0
note() { printf 'lint: %s\n' "$*"; }
fail() { printf 'lint: FAIL  %s\n' "$*"; failed=1; }

# ---- 1. syntax -------------------------------------------------------------
#
# Run under whatever bash is present. On macOS that is 3.2, which is the real
# portability floor the script is written against (invariant §10).

if bash -n bin/uv-manager; then
    note "OK    bash -n bin/uv-manager  ($(bash --version | sed -n '1s/.*version \([^ ]*\).*/\1/p'))"
else
    fail "bin/uv-manager does not parse"
fi

for f in .agents/factory/bin/temp_root.sh .agents/factory/bin/lint.sh \
         .agents/factory/fixtures/uv-install/install.sh; do
    sh -n "$f" || fail "$f does not parse"
done

# ---- 2. shellcheck ---------------------------------------------------------

shellcheck_mode=''
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck_mode=system
elif [ -z "$no_net" ] && command -v uvx >/dev/null 2>&1; then
    shellcheck_mode=uvx
fi

run_shellcheck() {
    case "$shellcheck_mode" in
        system) shellcheck "$@" ;;
        uvx)    uvx --quiet --from shellcheck-py shellcheck "$@" ;;
    esac
}

if [ -n "$shellcheck_mode" ]; then
    if run_shellcheck --severity=style bin/uv-manager; then
        note "OK    shellcheck bin/uv-manager  (via $shellcheck_mode)"
    else
        fail "shellcheck reported findings in bin/uv-manager"
    fi
    if run_shellcheck --severity=style \
            .agents/factory/bin/temp_root.sh \
            .agents/factory/bin/lint.sh \
            .agents/factory/fixtures/uv-install/install.sh; then
        note "OK    shellcheck .agents/ shell scripts"
    else
        fail "shellcheck reported findings in the factory scripts"
    fi
elif [ -n "$no_net" ]; then
    note "SKIP  shellcheck (--no-net, and no shellcheck on PATH)"
else
    note "CANNOT RUN  shellcheck: neither shellcheck nor uvx is available"
    exit 3
fi

# ---- 3. repository shape ---------------------------------------------------
#
# bin/{uv,uvx,uvm} must stay symlinks (git mode 120000). Four independent copies
# still dispatch correctly — mode comes from the invoked name — but they drift
# apart on the next update, which is the failure this check exists to catch.

links_ok=1
for name in uv uvx uvm; do
    mode=$(git ls-files -s "bin/$name" | awk '{print $1}')
    target=$(git cat-file -p ":bin/$name" 2>/dev/null || echo '?')
    if [ "$mode" != "120000" ]; then
        fail "bin/$name is not a symlink in the index (mode $mode)"
        links_ok=0
    elif [ "$target" != "uv-manager" ]; then
        fail "bin/$name points at '$target', expected 'uv-manager'"
        links_ok=0
    fi
done
if [ "$links_ok" -eq 1 ]; then
    note "OK    bin/{uv,uvx,uvm} are symlinks to uv-manager"
fi

# The version is single-sourced (invariant §12). Report it so a release drive can
# assert against it, and catch the line going missing under a refactor.
version=$(sed -n 's/^readonly uvm_version="\(.*\)"$/\1/p' bin/uv-manager)
if [ -n "$version" ]; then
    note "OK    version single-source reads $version"
else
    fail "cannot find 'readonly uvm_version=' in bin/uv-manager"
fi

# ---- report ----------------------------------------------------------------

if [ "$failed" -eq 0 ]; then
    note "all checks passed"
    exit 0
fi
note "one or more checks failed"
exit 1
