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

"""Verifies cross-platform icon, illustration, and composable parity between Web and Android."""

from pathlib import Path
import re
import unittest

ANDROID_ROOT = Path(
    "packages/design-system-android/src/main/kotlin/dev/vitruvian/design"
)
WEB_ICONS = Path("packages/design-system/src/Icons.tsx")
WEB_ILLUSTRATIONS = Path("packages/design-system/src/Illustrations.tsx")

EXPECTED_COMPOSABLES = [
    "Accordion",
    "AutoGrid",
    "Avatar",
    "Banner",
    "BlinkingCursor",
    "BottomSheet",
    "BrandLogo",
    "BrandMark",
    "BrandMedallion",
    "Card",
    "Code",
    "CopyButton",
    "Crumbs",
    "EmptyState",
    "Field",
    "HostChip",
    "Kbd",
    "KeyValue",
    "Label",
    "ListItem",
    "LogStream",
    "MenuDivider",
    "MenuItem",
    "MenuSurface",
    "Meter",
    "Metric",
    "Pagination",
    "Plate",
    "PlateFigure",
    "Rail",
    "Rule",
    "Section",
    "SectionHeader",
    "SegBar",
    "Segmented",
    "Skeleton",
    "Spark",
    "Spinner",
    "Status",
    "TabBar",
    "Tabs",
    "Tag",
    "Terminal",
    "Toast",
    "TopBar",
    "VButton",
    "VCheckbox",
    "VDialog",
    "VIcon",
    "VInput",
    "VMark",
    "VRadio",
    "VSelect",
    "VSlider",
    "VSwitch",
    "VTable",
    "VText",
    "VTextarea",
    "VitruvianPlate",
    "VitruvianTheme",
]


class DesignSystemAndroidParityTest(unittest.TestCase):
    def test_icon_names_match_web_icons_tsx(self) -> None:
        web_text = WEB_ICONS.read_text(encoding="utf-8")
        android_text = (ANDROID_ROOT / "Icons.kt").read_text(encoding="utf-8")

        web_icon_names = set(
            re.findall(r"^\s*([A-Z0-9_]+):\s*\[", web_text, re.MULTILINE)
        )
        android_icon_names = set(
            re.findall(
                r"public const val ([A-Z0-9_]+): String =",
                android_text,
            )
        )

        self.assertEqual(len(web_icon_names), 28)
        self.assertEqual(web_icon_names, android_icon_names)

    def test_illustrations_match_web_plates(self) -> None:
        web_text = WEB_ILLUSTRATIONS.read_text(encoding="utf-8")
        android_text = (ANDROID_ROOT / "Illustrations.kt").read_text(encoding="utf-8")

        web_kinds = re.findall(r'^\s*\|\s*"([a-z]+)"', web_text, re.MULTILINE)
        self.assertEqual(len(web_kinds), 8)
        for kind_name in web_kinds:
            enum_name = kind_name.capitalize()
            self.assertIn(f"{enum_name}(", android_text)

    def test_all_expected_composables_exist(self) -> None:
        all_kt = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(ANDROID_ROOT.glob("*.kt"))
        )
        defined_functions = set(re.findall(r"public fun ([A-Za-z0-9_]+)\s*\(", all_kt))
        for name in EXPECTED_COMPOSABLES:
            self.assertIn(
                name,
                defined_functions,
                f"Expected public fun {name} in packages/design-system-android",
            )


if __name__ == "__main__":
    unittest.main()
