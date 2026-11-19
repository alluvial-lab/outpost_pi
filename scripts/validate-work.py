#!/usr/bin/env python3
"""Project Workbench validator wrapper for Outpost-Pi.

Runs Workbench's bundled validator (`--builtin`) and allows only the documented
local-only `.work/session-notes/` directory when it is gitignored and contains
zero tracked files. All other errors and all warnings pass through unchanged.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

SESSION_NOTES_ERROR = "ERROR: noncanonical work directory: .work/session-notes"
SUMMARY_PREFIXES = ("Workbench validation passed:", "Workbench validation failed:")


def session_notes_is_clean_local_only(root: Path) -> tuple[bool, str | None]:
    """Verify `.work/session-notes` is gitignored and has zero git-tracked files."""
    ignored = subprocess.run(
        ["git", "check-ignore", "-q", ".work/session-notes"],
        cwd=root,
        check=False,
    )
    if ignored.returncode != 0:
        return False, "ERROR: .work/session-notes must be gitignored"
    tracked = subprocess.run(
        ["git", "ls-files", ".work/session-notes"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if tracked.returncode != 0:
        return False, "ERROR: failed to verify git-tracked files under .work/session-notes"
    if tracked.stdout.strip():
        return False, "ERROR: tracked files found under local-only .work/session-notes"
    return True, None


def main() -> int:
    root = Path(".").resolve()
    validator = os.environ.get("WORKBENCH_VALIDATOR")
    if not validator:
        print(
            "ERROR: WORKBENCH_VALIDATOR not set; invoke via Workbench's validate-workbench.py",
            file=sys.stderr,
        )
        return 2

    proc = subprocess.run(
        [sys.executable, validator, "--builtin", "."],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.stderr:
        sys.stderr.write(proc.stderr)
    if proc.returncode not in (0, 1):
        if proc.stdout:
            sys.stdout.write(proc.stdout)
        return proc.returncode if proc.returncode > 0 else 128 - proc.returncode

    errors: list[str] = []
    warnings: list[str] = []
    other_lines: list[str] = []
    saw_summary = False

    for line in proc.stdout.splitlines():
        if line.startswith(SUMMARY_PREFIXES):
            saw_summary = True
            continue
        if line == SESSION_NOTES_ERROR:
            ok, reason = session_notes_is_clean_local_only(root)
            if ok:
                continue
            errors.append(reason or line)
            continue
        if line.startswith("ERROR:"):
            errors.append(line)
        elif line.startswith("WARNING:"):
            warnings.append(line)
        elif line.strip():
            other_lines.append(line)

    for line in other_lines:
        print(line)
    for warning in warnings:
        print(warning)
    for error in errors:
        print(error)

    if not saw_summary and proc.returncode != 0 and not errors:
        print("ERROR: bundled Workbench validator exited nonzero without diagnostics")
        return proc.returncode

    if errors:
        print(f"Workbench validation failed: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    print(f"Workbench validation passed: {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
