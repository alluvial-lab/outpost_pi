#!/usr/bin/env python3
"""Synchronize checked-in theme and brand geometry projections."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

from brand_contract import (
    ContractError,
    build_theme_fixture,
    load_mark_geometry,
    render_mark_typescript,
    render_theme_json,
)

ROOT = Path(__file__).resolve().parents[1]
TOKENS_CSS = ROOT / ".mockups/design-system/tokens.css"
MARK_SVG = ROOT / "branding/logo-foreground.svg"
THEME_FIXTURE = ROOT / "branding/theme-contract.json"
MARK_PROJECTION = ROOT / "site/src/generated/constellation_mark.generated.ts"


def sync_contracts(*, check: bool) -> bool:
    """Check or write the projections derived from canonical brand inputs."""
    fixture = build_theme_fixture(TOKENS_CSS.read_text(encoding="utf-8"))
    mark = load_mark_geometry(MARK_SVG)
    expected = {
        THEME_FIXTURE: render_theme_json(fixture),
        MARK_PROJECTION: render_mark_typescript(mark),
    }
    stale = [path for path, content in expected.items() if not _matches(path, content)]
    if check:
        if stale:
            print("Stale brand contract projection(s):")
            for path in stale:
                print(f"  {path.relative_to(ROOT)}")
            return False
        print("Brand contract projections are fresh.")
        return True

    for path, content in expected.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if not _matches(path, content):
            path.write_text(content, encoding="utf-8")
            print(f"Updated {path.relative_to(ROOT)}")
    return True


def _matches(path: Path, expected: str) -> bool:
    try:
        return path.read_text(encoding="utf-8") == expected
    except FileNotFoundError:
        return False


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check or synchronize Outpost-Pi brand contract projections."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail without writing when a checked-in projection is stale",
    )
    args = parser.parse_args()
    try:
        return 0 if sync_contracts(check=args.check) else 1
    except (ContractError, OSError) as error:
        print(f"Brand contract error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
