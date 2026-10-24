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
"""Hermetic validation tests for the Daytona Platinum 126506 Wear OS Watch Face Format package."""

from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET

ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
BASE_DIR = Path(__file__).resolve().parent / "src" / "main"


def read_png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a valid PNG")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


class DaytonaPlatinumWatchFaceTest(unittest.TestCase):
    def test_manifest_is_valid_code_free_wff_package(self) -> None:
        manifest_path = BASE_DIR / "AndroidManifest.xml"
        tree = ET.parse(manifest_path)
        root = tree.getroot()
        self.assertEqual(
            root.attrib.get("package"), "com.watchfacestudio.daytonaplatinum"
        )

        app = root.find("application")
        self.assertIsNotNone(app)
        assert app is not None
        self.assertEqual(app.attrib.get(f"{ANDROID_NS}hasCode"), "false")

        props = {
            p.attrib.get(f"{ANDROID_NS}name"): p.attrib.get(f"{ANDROID_NS}value")
            for p in app.findall("property")
        }
        self.assertEqual(props.get("com.google.wear.watchface.format.version"), "2")

    def test_required_xml_descriptors_exist_and_match_450_circle(self) -> None:
        shapes = ET.parse(BASE_DIR / "res" / "xml" / "watch_face_shapes.xml").getroot()
        wf = shapes.find("WatchFace")
        self.assertIsNotNone(wf)
        assert wf is not None
        self.assertEqual(wf.attrib.get("file"), "@raw/watchface")
        self.assertEqual(wf.attrib.get("shape"), "CIRCLE")
        self.assertEqual(wf.attrib.get("width"), "450")
        self.assertEqual(wf.attrib.get("height"), "450")

        info = ET.parse(BASE_DIR / "res" / "xml" / "watch_face_info.xml").getroot()
        preview = info.find("Preview")
        self.assertIsNotNone(preview)
        assert preview is not None
        self.assertEqual(preview.attrib.get("value"), "@drawable/preview")

        wallpaper = ET.parse(BASE_DIR / "res" / "xml" / "watch_face.xml").getroot()
        self.assertEqual(wallpaper.tag, "wallpaper")

    def test_watchface_xml_integrates_all_complications_and_assets(self) -> None:
        wf_path = BASE_DIR / "res" / "raw" / "watchface.xml"
        root = ET.parse(wf_path).getroot()
        self.assertEqual(root.tag, "WatchFace")
        self.assertEqual(root.attrib.get("width"), "450")
        self.assertEqual(root.attrib.get("height"), "450")
        self.assertEqual(root.attrib.get("clipShape"), "CIRCLE")

        strings_root = ET.parse(BASE_DIR / "res" / "values" / "strings.xml").getroot()
        defined_strings = {s.attrib["name"] for s in strings_root.findall("string")}

        slots = root.findall(".//ComplicationSlot")
        self.assertEqual(len(slots), 5)
        slot_names = {s.attrib.get("name") for s in slots}
        self.assertEqual(
            slot_names,
            {
                "world_clock_slot",
                "heart_rate_slot",
                "weather_slot",
                "steps_slot",
                "solar_slot",
            },
        )

        for slot in slots:
            display_name = slot.attrib.get("displayName")
            self.assertIn(display_name, defined_strings)
            x = int(slot.attrib["x"])
            y = int(slot.attrib["y"])
            w = int(slot.attrib["width"])
            h = int(slot.attrib["height"])
            self.assertGreaterEqual(x, 0)
            self.assertGreaterEqual(y, 0)
            self.assertLessEqual(x + w, 450)
            self.assertLessEqual(y + h, 450)

        drawable_dir = BASE_DIR / "res" / "drawable-nodpi"
        expected_450 = [
            "dial_interactive.png",
            "dial_ambient.png",
            "dial_expanded_interactive.png",
            "dial_expanded_ambient.png",
            "dial_ultra_ambient.png",
            "dial_expanded_ultra_ambient.png",
            "dial_panda_interactive.png",
            "dial_panda_expanded_interactive.png",
            "dial_revpanda_interactive.png",
            "dial_revpanda_expanded_interactive.png",
            "dial_lemans_interactive.png",
            "dial_lemans_expanded_interactive.png",
            "hand_hour.png",
            "hand_hour_aod.png",
            "hand_minute.png",
            "hand_minute_aod.png",
            "hand_second.png",
            "preview.png",
            "preview_circular.png",
        ]
        for filename in expected_450:
            png_path = drawable_dir / filename
            self.assertTrue(png_path.is_file(), f"Missing {filename}")
            self.assertEqual(read_png_dimensions(png_path), (450, 450))

        subdial_path = drawable_dir / "subdial_hand.png"
        self.assertTrue(subdial_path.is_file())
        self.assertEqual(read_png_dimensions(subdial_path), (88, 88))

        subdial_exp_path = drawable_dir / "subdial_hand_expanded.png"
        self.assertTrue(subdial_exp_path.is_file())
        self.assertEqual(read_png_dimensions(subdial_exp_path), (120, 120))

        unread_path = drawable_dir / "unread_badge.png"
        self.assertTrue(unread_path.is_file())
        self.assertEqual(read_png_dimensions(unread_path), (24, 24))

    def test_user_configurations_define_all_chronograph_options_and_launch_targets(
        self,
    ) -> None:
        wf_path = BASE_DIR / "res" / "raw" / "watchface.xml"
        root = ET.parse(wf_path).getroot()
        strings_root = ET.parse(BASE_DIR / "res" / "values" / "strings.xml").getroot()
        defined_strings = {}
        for s in strings_root.findall("string"):
            name = s.attrib["name"]
            text = s.text or ""
            # DeclarativeWatchFaceRuntime calls Resources.getString(id, Object...)
            # which runs String.format(text) and crashes on unescaped '%'.
            self.assertNotIn(
                "%",
                text,
                f"String '{name}' contains '%' which crashes DeclarativeWatchFaceRuntime.getUserStyleSchema()",
            )
            defined_strings[name] = text

        user_configs = root.find("UserConfigurations")
        self.assertIsNotNone(user_configs)
        assert user_configs is not None

        list_configs = {
            cfg.attrib["id"]: cfg for cfg in user_configs.findall("ListConfiguration")
        }
        expected_configs = {
            "theme_style": (
                "theme_platinum",
                [
                    "theme_platinum",
                    "theme_panda",
                    "theme_reverse_panda",
                    "theme_lemans",
                ],
            ),
            "bezel_mode": ("bezel_expanded", ["bezel_expanded", "bezel_full"]),
            "aod_mode": (
                "aod_chromalight",
                ["aod_chromalight", "aod_ultra"],
            ),
            "subdial_mode": (
                "subdials_smart",
                ["subdials_smart", "subdials_chrono", "subdials_minimal"],
            ),
            "status_badges": ("badges_on", ["badges_on", "badges_off"]),
            "font_scale": (
                "font_standard",
                ["font_standard", "font_large", "font_xlarge"],
            ),
        }

        for cfg_id, (expected_default, expected_opts) in expected_configs.items():
            self.assertIn(cfg_id, list_configs)
            cfg = list_configs[cfg_id]
            self.assertEqual(cfg.attrib.get("defaultValue"), expected_default)
            self.assertIn(cfg.attrib.get("displayName"), defined_strings)
            self.assertIn(cfg.attrib.get("screenReaderText"), defined_strings)
            self.assertTrue(cfg.attrib.get("icon"))
            opts = [opt.attrib["id"] for opt in cfg.findall("ListOption")]
            self.assertEqual(opts, expected_opts)
            for opt in cfg.findall("ListOption"):
                self.assertIn(opt.attrib.get("displayName"), defined_strings)
                self.assertIn(opt.attrib.get("screenReaderText"), defined_strings)
                self.assertTrue(opt.attrib.get("icon"))

        scene = root.find("Scene")
        self.assertIsNotNone(scene)
        assert scene is not None
        launches = [el.attrib.get("target") for el in scene.findall(".//Launch")]
        self.assertEqual(set(launches), {"ALARM", "CALENDAR", "BATTERY_STATUS"})


if __name__ == "__main__":
    unittest.main()
