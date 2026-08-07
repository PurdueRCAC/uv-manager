#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# Run a command against a throwaway UV_MANAGER_ROOT, so factory verify commands and
# review drives never touch the developer's real state tree, cache, or managed
# interpreters. This is the substitute for a test fixture until the project has a
# real test harness.
#
# Usage:
#   .agents/factory/bin/temp_root.sh uvm status
#   .agents/factory/bin/temp_root.sh --offline uv --version
#   .agents/factory/bin/temp_root.sh --offline --arch aarch64 uvm status
#   .agents/factory/bin/temp_root.sh --offline --keep sh -c 'uv --version; uvm doctor'
#
# Options:
#   --offline     Point UV_MANAGER_INSTALL_URL at the local installer fixture, so
#                 provisioning runs with no egress. Exercises the whole path: lock,
#                 fetch, install, version detection, atomic rename, `current` swap.
#                 The fixture also asserts the installer environment was scrubbed.
#   --arch KEY    Set UV_MANAGER_PLATFORM, so one sandbox can hold several
#                 architectures and the heterogeneous-cluster behavior is reachable
#                 on one machine.
#   --keep        Leave the sandbox in place and print its path. For inspection.
#
# The command runs with its working directory inside the sandbox, so relative writes
# stay contained instead of leaking into the working tree. The sandbox is removed on
# every exit path unless --keep.
#
# Variables available to the command: UV_MANAGER_ROOT, UVM_SANDBOX, and — with
# --offline — UVM_FIXTURE_DIR (write <dir>/<version>/install.sh there to test a
# pinned install).

set -eu

# Repo root from this script's own location, not from $PWD, so the wrapper works
# when invoked from anywhere.
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(CDPATH='' cd -- "$here/../../.." && pwd -P)

offline=''
arch=''
keep=''

while [ $# -gt 0 ]; do
    case "$1" in
        --offline) offline=1; shift ;;
        --arch)    arch="${2:?--arch needs a platform key}"; shift 2 ;;
        --arch=*)  arch="${1#--arch=}"; shift ;;
        --keep)    keep=1; shift ;;
        --)        shift; break ;;
        -*)        echo "temp_root.sh: unknown option: $1" >&2; exit 2 ;;
        *)         break ;;
    esac
done

[ $# -gt 0 ] || { echo "usage: temp_root.sh [--offline] [--arch KEY] [--keep] COMMAND [ARG...]" >&2; exit 2; }

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/uv-manager-sandbox.XXXXXX")
if [ -n "$keep" ]; then
    echo "temp_root.sh: keeping sandbox at $sandbox" >&2
else
    trap 'rm -rf "$sandbox"' EXIT INT TERM
fi

# Scrub every UV_* variable and every scratch candidate uvm_resolve_root consults.
# Without this, a developer with UV_CACHE_DIR or $SCRATCH exported gets a drive that
# silently reads or writes real storage, and a green verify that proves nothing.
for name in $(env | sed -n 's/^\(UV_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$name"
done
unset CLUSTER_SCRATCH RCAC_SCRATCH SCRATCH PSCRATCH WORK PROJECT 2>/dev/null || true

# Redirected rather than unset: the wrapper deliberately leaves XDG_CONFIG_HOME alone
# (invariant §8), so a drive must still see a valid one — just not the developer's,
# whose ~/.config/uv/uv.toml would change resolution behavior under the test.
XDG_CONFIG_HOME="$sandbox/config"
UV_MANAGER_ROOT="$sandbox/root"
UVM_SANDBOX="$sandbox"
export XDG_CONFIG_HOME UV_MANAGER_ROOT UVM_SANDBOX
mkdir -p "$XDG_CONFIG_HOME" "$UV_MANAGER_ROOT"

if [ -n "$offline" ]; then
    # Copied into the sandbox rather than referenced in place, so a drive can add
    # version subdirectories for pinned installs without dirtying the working tree.
    UVM_FIXTURE_DIR="$sandbox/fixture"
    cp -R "$repo/.agents/factory/fixtures/uv-install" "$UVM_FIXTURE_DIR"
    UV_MANAGER_INSTALL_URL="file://$UVM_FIXTURE_DIR"
    export UVM_FIXTURE_DIR UV_MANAGER_INSTALL_URL
fi

[ -n "$arch" ] && { UV_MANAGER_PLATFORM="$arch"; export UV_MANAGER_PLATFORM; }

# The working tree's wrapper wins over any installed copy.
PATH="$repo/bin:$PATH"
export PATH

cd "$sandbox"

set +e
"$@"
rc=$?
set -e
exit "$rc"
