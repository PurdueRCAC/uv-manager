# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
# SPDX-FileCopyrightText: 2026 Geoffrey Lentner
# SPDX-License-Identifier: MIT
"""Run one phase's verify: gate from a spec/<slug>/TECH.md FSM under /bin/sh.

``uvm-build`` Step 4 requires a new or retuned gate to be executed as
``/bin/sh -c '…'``: the string is authored in an interactive shell and run
later by CI and by anyone reading TECH.md under plain ``sh``, where aliases,
shell functions and GNU-versus-BSD utilities all diverge. The gate lives in
folded YAML across wrapped lines, so copying it by hand means reflowing it,
and reflowing is where a quoting error enters.

An **empty** gate is the failure this script exists to make loud. ``/bin/sh -c
''`` exits 0, so a hand-rolled reader that silently produced nothing satisfies
"confirm the gate is red" while proving nothing.

Usage:
    uv run .agents/factory/bin/run_verify.py spec/<slug>/TECH.md --phase P2
    uv run .agents/factory/bin/run_verify.py spec/<slug>/TECH.md --phase P2 --print

Exit codes: the gate's own status when it runs · 2 parse/validation error,
unknown phase, or an empty gate (message on stderr).
"""
from __future__ import annotations

# Standard libs
import argparse
import os
import sys
from pathlib import Path

# Internal libs — sibling import, resolved explicitly so the script works from any cwd.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _fsm import FSMError, split_frontmatter, validate  # noqa: E402


# Public interface
__all__ = ["main"]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="run_verify.py",
        description="Execute one phase's verify: gate under /bin/sh -c.",
    )
    parser.add_argument("tech", help="path to spec/<slug>/TECH.md")
    parser.add_argument("--phase", required=True, metavar="P<n>", help="phase id to run")
    parser.add_argument(
        "--print",
        dest="print_only",
        action="store_true",
        help="write the gate to stdout instead of running it",
    )
    args = parser.parse_args(argv)

    path = Path(args.tech)
    try:
        data, _body = split_frontmatter(path.read_text(encoding="utf-8"))
    except (OSError, FSMError) as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        return 2

    errors = validate(data)
    if errors:
        print(f"{path}: invalid TECH.md frontmatter:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 2

    phases = [p for p in (data.get("phases") or []) if isinstance(p, dict)]
    match = [p for p in phases if p.get("id") == args.phase]
    if not match:
        known = ", ".join(str(p.get("id")) for p in phases) or "none"
        print(f"{path}: no phase {args.phase!r} (known: {known})", file=sys.stderr)
        return 2

    gate = str(match[0].get("verify") or "").strip()
    if not gate:
        # /bin/sh -c '' exits 0. A gate that cannot fail is not a gate.
        print(f"{path}: phase {args.phase} has an empty verify:", file=sys.stderr)
        return 2

    if args.print_only:
        print(gate)
        return 0

    # exec, not a subprocess: the gate's exit status, signals and streams are the
    # caller's, so a `verify:` behaves the same here as it does run by hand.
    print(f"+ /bin/sh -c {gate!r}", file=sys.stderr)
    sys.stderr.flush()
    try:
        os.execv("/bin/sh", ["/bin/sh", "-c", gate])
    except OSError as exc:
        print(f"cannot exec /bin/sh: {exc}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
