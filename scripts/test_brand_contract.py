import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from brand_contract import (  # noqa: E402
    ContractError,
    build_theme_fixture,
    load_mark_geometry,
    render_mark_typescript,
    render_theme_json,
)


_SYNC_SPEC = importlib.util.spec_from_file_location(
    "sync_brand_contracts", ROOT / "scripts/sync-brand-contracts.py"
)
assert _SYNC_SPEC is not None and _SYNC_SPEC.loader is not None
_sync = importlib.util.module_from_spec(_SYNC_SPEC)
_SYNC_SPEC.loader.exec_module(_sync)


class BrandContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tokens = (ROOT / ".mockups/design-system/tokens.css").read_text()
        cls.foreground = (ROOT / "branding/logo-foreground.svg").read_text()

    def test_stale_fixture_fails_freshness_check(self) -> None:
        fixture = build_theme_fixture(self.tokens)
        mark = load_mark_geometry(ROOT / "branding/logo-foreground.svg")
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            fixture_path = directory_path / "theme-contract.json"
            projection_path = directory_path / "constellation_mark.generated.ts"
            fixture_path.write_text(render_theme_json(fixture))
            projection_path.write_text(render_mark_typescript(mark))
            with patch.object(_sync, "THEME_FIXTURE", fixture_path), patch.object(
                _sync, "MARK_PROJECTION", projection_path
            ):
                self.assertTrue(_sync.sync_contracts(check=True))
                fixture_path.write_text("stale\n")
                self.assertFalse(_sync.sync_contracts(check=True))

    def test_unsupported_css_selector_grammar_is_rejected(self) -> None:
        unsupported = self.tokens + "\n:root { --color-accent: #FFFFFF; }\n"
        with self.assertRaisesRegex(ContractError, "outside the canonical contract"):
            build_theme_fixture(unsupported)

    def test_unexpected_svg_attribute_is_rejected(self) -> None:
        malformed = self.foreground.replace(
            'stroke="#E4EFE8"',
            'stroke="#E4EFE8" transform="translate(10 0)"',
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".svg") as file:
            file.write(malformed)
            file.flush()
            with self.assertRaisesRegex(ContractError, "unsupported attribute"):
                load_mark_geometry(Path(file.name))

    def test_missing_svg_primitive_is_rejected(self) -> None:
        malformed = self.foreground.replace(
            '  <circle cx="633" cy="693" r="71" fill="#E4EFE8"/>\n',
            "",
        )
        with tempfile.NamedTemporaryFile(mode="w", suffix=".svg") as file:
            file.write(malformed)
            file.flush()
            with self.assertRaisesRegex(ContractError, "exactly one path"):
                load_mark_geometry(Path(file.name))

    def test_projection_output_is_deterministic(self) -> None:
        fixture_output = render_theme_json(build_theme_fixture(self.tokens))
        self.assertEqual(
            fixture_output,
            (ROOT / "branding/theme-contract.json").read_text(),
        )

        mark = load_mark_geometry(ROOT / "branding/logo-foreground.svg")
        self.assertEqual(
            render_mark_typescript(mark),
            (ROOT / "site/src/generated/constellation_mark.generated.ts").read_text(),
        )


if __name__ == "__main__":
    unittest.main()
