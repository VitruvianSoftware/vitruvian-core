#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Verifies that tokens.json, tokens.css, tokens.ts, and vendored fonts stay in sync."""

import json
from pathlib import Path
import re
import unittest


def _find_pkg_dir() -> Path:
    here = Path(__file__).resolve()
    for parent in [here.parent, *here.parents]:
        candidate = parent / "src" / "tokens.json"
        if candidate.is_file():
            return parent
        workspace_candidate = (
            parent / "packages" / "design-system" / "src" / "tokens.json"
        )
        if workspace_candidate.is_file():
            return parent / "packages" / "design-system"
    raise RuntimeError("Could not locate packages/design-system/src/tokens.json")


class DesignSystemIntegrityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pkg_dir = _find_pkg_dir()
        cls.src_dir = cls.pkg_dir / "src"
        cls.tokens_json = json.loads(
            (cls.src_dir / "tokens.json").read_text(encoding="utf-8")
        )
        cls.tokens_css = (cls.src_dir / "tokens.css").read_text(encoding="utf-8")
        cls.tokens_ts = (cls.src_dir / "tokens.ts").read_text(encoding="utf-8")
        cls.index_ts = (cls.src_dir / "index.ts").read_text(encoding="utf-8")

    def test_no_remote_font_import_in_tokens_css(self) -> None:
        self.assertNotIn(
            "fonts.googleapis.com",
            self.tokens_css,
            "tokens.css must not use remote Google Fonts @import (stripped by Vite/lightningcss)",
        )

    def test_all_font_face_urls_exist_on_disk(self) -> None:
        urls = re.findall(r'url\(["\']\.\/fonts\/([^"\']+)["\']\)', self.tokens_css)
        self.assertGreaterEqual(
            len(urls), 12, "Expected 12 woff2 @font-face declarations"
        )
        for fname in urls:
            fpath = self.src_dir / "fonts" / fname
            self.assertTrue(fpath.is_file(), f"Missing vendored font file: {fpath}")
        self.assertTrue(
            (self.src_dir / "fonts" / "OFL.txt").is_file(),
            "Missing SIL Open Font License (OFL.txt) in src/fonts/",
        )

    def test_color_ramps_match_between_json_css_and_ts(self) -> None:
        for ramp_name, css_prefix in [
            ("accent", "--color-accent-"),
            ("sanguine", "--color-sanguine-"),
            ("neutral", "--color-neutral-"),
        ]:
            ramp = self.tokens_json["color"][ramp_name]
            for step in ("100", "200", "300", "400", "500", "600", "700", "800", "900"):
                self.assertIn(
                    step,
                    ramp,
                    f"Missing color.{ramp_name}.{step} in tokens.json",
                )
                hex_val = ramp[step]["$value"].lower()
                expected_css = f"{css_prefix}{step}: {hex_val};"
                self.assertIn(
                    expected_css,
                    self.tokens_css.lower(),
                    f"Missing or mismatched '{expected_css}' in tokens.css",
                )
                self.assertIn(
                    hex_val,
                    self.tokens_ts.lower(),
                    f"Missing '{hex_val}' ({ramp_name}.{step}) in tokens.ts",
                )

    def test_fibonacci_spacing_and_zero_radius(self) -> None:
        expected_fib = {
            "1": "3px",
            "2": "5px",
            "3": "8px",
            "4": "13px",
            "5": "21px",
            "6": "34px",
            "7": "55px",
            "8": "89px",
        }
        for k, v in expected_fib.items():
            self.assertEqual(self.tokens_json["space"][k]["$value"], v)
            self.assertIn(f"--space-{k}: {v};", self.tokens_css)

        for r in ("sm", "md", "lg"):
            self.assertEqual(
                self.tokens_json["radius"][r]["$value"],
                "0px",
                f"radius.{r} must be 0px (Vitruvian square geometry)",
            )
            self.assertIn(f"--radius-{r}: 0px;", self.tokens_css)

    def test_index_exports_complete_component_surface(self) -> None:
        required_exports = [
            "VitruvianTokens",
            "tokens",
            "Plate",
            "RegistrationMarks",
            "VMark",
            "Rule",
            "Glass",
            "Button",
            "Tag",
            "Label",
            "Kbd",
            "Card",
            "Field",
            "Input",
            "Textarea",
            "Select",
            "Checkbox",
            "Radio",
            "Switch",
            "Segmented",
            "Slider",
            "CopyButton",
            "Nav",
            "Tabs",
            "Shell",
            "SideGroup",
            "SideItem",
            "Crumbs",
            "HostChip",
            "TopBar",
            "TabBar",
            "Rail",
            "SectionHeader",
            "Section",
            "MobileShell",
            "Pagination",
            "Avatar",
            "Status",
            "Metric",
            "Meter",
            "SegBar",
            "Spark",
            "BarChart",
            "LogStream",
            "Table",
            "Terminal",
            "Code",
            "BlinkingCursor",
            "Dialog",
            "Banner",
            "Menu",
            "MenuItem",
            "MenuDivider",
            "BottomSheet",
            "Tooltip",
            "Popover",
            "Toast",
            "Drawer",
            "CommandPalette",
            "EmptyState",
            "Skeleton",
            "Spinner",
            "VIcon",
            "VitruvianIcons",
            "ListItem",
            "AutoGrid",
            "KeyValue",
            "Accordion",
            "VitruvianPlate",
            "PlateFigure",
            "VitruvianStockImages",
            "DuotoneImage",
        ]
        for sym in required_exports:
            self.assertRegex(
                self.index_ts,
                rf"\b{re.escape(sym)}\b",
                f"Missing export '{sym}' in packages/design-system/src/index.ts",
            )


if __name__ == "__main__":
    unittest.main()
