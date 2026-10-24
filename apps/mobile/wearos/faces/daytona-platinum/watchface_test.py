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


if __name__ == "__main__":
    unittest.main()
