#!/bin/sh
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
#
# Stand-in for https://astral.sh/uv/install.sh, used by
# `.agents/factory/bin/temp_root.sh --offline`.
#
# `uvm_fetch` uses curl, and curl speaks file://, so pointing
# UV_MANAGER_INSTALL_URL at a local directory exercises the wrapper's entire
# provisioning path — lock, fetch, install, version detection, atomic rename,
# `current` swap — with no network. This script is the payload that arrives.
#
# It also asserts, on every offline drive, that the wrapper scrubbed the two
# variables that take precedence over UV_UNMANAGED_INSTALL (invariant §6). That
# scrub is otherwise invisible: when it regresses, uv lands somewhere else and
# every later invocation re-runs the installer and fails.
#
# Knobs, read by the installed stub at run time:
#   UVM_FIXTURE_VERSION   version the stub reports (default 9.9.9)
#   UVM_FIXTURE_EXIT      exit status the stub returns, for rc-propagation drives
#   UVM_FIXTURE_BROKEN    make the stub unrunnable, to reach the wrong-architecture path
#
# temp_root.sh scrubs UVM_* from the inherited environment, so a drive sets these on
# the inner command: `temp_root.sh --offline sh -c 'UVM_FIXTURE_VERSION=6.6.6 uv --version'`.

set -eu

: "${UV_UNMANAGED_INSTALL:?fixture: UV_UNMANAGED_INSTALL is unset — the wrapper must set it}"

if [ -n "${UV_INSTALL_DIR:-}" ]; then
    echo "fixture: UV_INSTALL_DIR leaked into the installer environment (invariant §6)" >&2
    exit 90
fi
if [ -n "${CARGO_DIST_FORCE_INSTALL_DIR:-}" ]; then
    echo "fixture: CARGO_DIST_FORCE_INSTALL_DIR leaked into the installer environment (invariant §6)" >&2
    exit 90
fi

version="${UVM_FIXTURE_VERSION:-9.9.9}"
mkdir -p "$UV_UNMANAGED_INSTALL"

cat > "$UV_UNMANAGED_INSTALL/uv" <<STUB
#!/bin/sh
[ -n "\${UVM_FIXTURE_BROKEN:-}" ] && exit 126
case "\${1:-}" in
    --version) echo "uv $version (fixture)" ;;
    *)         echo "uv-fixture: \$*" ;;
esac
exit "\${UVM_FIXTURE_EXIT:-0}"
STUB

cat > "$UV_UNMANAGED_INSTALL/uvx" <<STUB
#!/bin/sh
[ -n "\${UVM_FIXTURE_BROKEN:-}" ] && exit 126
echo "uvx-fixture: \$*"
exit "\${UVM_FIXTURE_EXIT:-0}"
STUB

chmod 0755 "$UV_UNMANAGED_INSTALL/uv" "$UV_UNMANAGED_INSTALL/uvx"

# Real installer output goes to stderr, and so does this: stdout belongs to whatever
# the user actually asked for (invariant §7).
echo "fixture: installed uv $version into $UV_UNMANAGED_INSTALL" >&2
