#!/usr/bin/env python3
"""Reconcile one nightly soak's machine-readable findings inventory."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_expected(path: Path) -> set[str]:
    """Load non-comment tracking ids from the expected-findings manifest."""
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }


def load_findings(path: Path) -> dict[str, Any]:
    """Load and validate the bounded findings fields emitted by live_soak.py."""
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("findings must be a JSON object")
    for field in ("known_open", "observed", "suspicious", "unexpected"):
        entries = value.get(field)
        if not isinstance(entries, list) or not all(
            isinstance(entry, str) for entry in entries
        ):
            raise ValueError(f"findings.{field} must be a string list")
    return value


def reconcile(expected: set[str], findings: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Return newly inventoried and missing expected finding ids."""
    actual = set(findings["known_open"])
    return sorted(actual - expected), sorted(expected - actual)


def render_summary(
    *,
    findings: dict[str, Any],
    new: list[str],
    missing: list[str],
    runner_status: int,
) -> str:
    """Render the content-free nightly triage and drift summary."""
    lines = [
        "# Nightly soak summary",
        "",
        f"- Soak exit: `{runner_status}`",
        f"- Known-open findings: `{len(findings['known_open'])}`",
        f"- Observed in this soak lane: `{len(findings['observed'])}`",
        f"- New inventory findings: `{len(new)}`",
        f"- Missing expected findings: `{len(missing)}`",
        f"- Unexpected invariant/environment findings: `{len(findings['unexpected'])}`",
        f"- Suspicious targeted absences: `{len(findings['suspicious'])}`",
        "",
        "## Known-open inventory",
        "",
    ]
    lines.extend(f"- `{item}`" for item in findings["known_open"])
    lines.extend(["", "## Observed by this soak", ""])
    lines.extend(f"- `{item}`" for item in findings["observed"])
    if not findings["observed"]:
        lines.append("- None")
    for heading, values in (
        ("New inventory findings", new),
        ("Missing expected findings", missing),
        ("Unexpected findings", findings["unexpected"]),
        ("Suspicious findings", findings["suspicious"]),
    ):
        lines.extend(["", f"## {heading}", ""])
        lines.extend(f"- {item}" for item in values)
        if not values:
            lines.append("- None")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--findings", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--runner-status", required=True, type=int)
    args = parser.parse_args()

    try:
        expected = load_expected(args.expected)
        findings = load_findings(args.findings)
        new, missing = reconcile(expected, findings)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        args.summary.write_text(
            f"# Nightly soak summary\n\n- Reconciliation failed: `{type(error).__name__}`\n",
            encoding="utf-8",
        )
        return 2

    args.summary.write_text(
        render_summary(
            findings=findings,
            new=new,
            missing=missing,
            runner_status=args.runner_status,
        ),
        encoding="utf-8",
    )
    return 1 if new or missing or args.runner_status != 0 else 0


if __name__ == "__main__":
    raise SystemExit(main())
