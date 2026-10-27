// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Hermetic validation tests for the Daytona Platinum 126506 Wear OS Watch Face Format package.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

fn base_dir() -> PathBuf {
    let from_root = PathBuf::from("apps/mobile/wearos/faces/daytona-platinum/src/main");
    if from_root.exists() {
        return from_root;
    }
    PathBuf::from("src/main")
}

fn read_png_dimensions(path: &Path) -> (u32, u32) {
    let data = fs::read(path).unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    assert!(
        data.len() >= 24 && &data[..8] == b"\x89PNG\r\n\x1a\n",
        "{} is not a valid PNG",
        path.display()
    );
    let width = u32::from_be_bytes([data[16], data[17], data[18], data[19]]);
    let height = u32::from_be_bytes([data[20], data[21], data[22], data[23]]);
    (width, height)
}

#[derive(Debug, Clone)]
struct XmlElement {
    tag: String,
    attrib: BTreeMap<String, String>,
    text: String,
    children: Vec<XmlElement>,
}

impl XmlElement {
    fn attr(&self, key: &str) -> Option<&str> {
        self.attrib.get(key).map(|s| s.as_str())
    }

    fn find(&self, tag: &str) -> Option<&XmlElement> {
        self.children.iter().find(|c| c.tag == tag)
    }

    fn findall(&self, tag: &str) -> Vec<&XmlElement> {
        self.children.iter().filter(|c| c.tag == tag).collect()
    }

    fn findall_descendants(&self, tag: &str) -> Vec<&XmlElement> {
        let mut out = Vec::new();
        self.collect_descendants(tag, &mut out);
        out
    }

    fn collect_descendants<'a>(&'a self, tag: &str, out: &mut Vec<&'a XmlElement>) {
        for child in &self.children {
            if child.tag == tag {
                out.push(child);
            }
            child.collect_descendants(tag, out);
        }
    }
}

fn parse_xml_file(path: &Path) -> XmlElement {
    let src = fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("failed to read XML {}: {e}", path.display()));
    parse_xml(&src)
}

fn parse_xml(src: &str) -> XmlElement {
    let mut pos = 0;
    let bytes = src.as_bytes();
    let mut stack: Vec<XmlElement> = Vec::new();
    let mut root: Option<XmlElement> = None;

    while pos < bytes.len() {
        if let Some(rel) = src[pos..].find('<') {
            let text_chunk = &src[pos..pos + rel];
            if let Some(top) = stack.last_mut() {
                if !text_chunk.trim().is_empty() {
                    top.text.push_str(text_chunk);
                }
            }
            pos += rel;
        } else {
            break;
        }

        if src[pos..].starts_with("<!--") {
            let end = src[pos + 4..]
                .find("-->")
                .expect("unterminated XML comment");
            pos += 4 + end + 3;
            continue;
        }
        if src[pos..].starts_with("<?") {
            let end = src[pos + 2..]
                .find("?>")
                .expect("unterminated XML processing instruction");
            pos += 2 + end + 2;
            continue;
        }
        if src[pos..].starts_with("</") {
            let end = src[pos + 2..].find('>').expect("unterminated closing tag");
            let close_tag = src[pos + 2..pos + 2 + end].trim();
            pos += 2 + end + 1;
            let elem = stack.pop().expect("unexpected closing tag");
            assert_eq!(elem.tag, close_tag, "mismatched closing tag");
            if let Some(parent) = stack.last_mut() {
                parent.children.push(elem);
            } else {
                root = Some(elem);
            }
            continue;
        }

        // Opening or self-closing tag: scan until '>' outside quotes.
        let mut i = pos + 1;
        let mut in_quote: Option<u8> = None;
        while i < bytes.len() {
            let b = bytes[i];
            if let Some(q) = in_quote {
                if b == q {
                    in_quote = None;
                }
            } else if b == b'"' || b == b'\'' {
                in_quote = Some(b);
            } else if b == b'>' {
                break;
            }
            i += 1;
        }
        assert!(i < bytes.len(), "unterminated opening tag");
        let inside = src[pos + 1..i].trim();
        let self_closing = inside.ends_with('/');
        let inside = if self_closing {
            inside[..inside.len() - 1].trim()
        } else {
            inside
        };
        pos = i + 1;

        let (tag, attrib) = parse_tag_and_attrs(inside);
        let elem = XmlElement {
            tag,
            attrib,
            text: String::new(),
            children: Vec::new(),
        };
        if self_closing {
            if let Some(parent) = stack.last_mut() {
                parent.children.push(elem);
            } else {
                root = Some(elem);
            }
        } else {
            stack.push(elem);
        }
    }

    root.expect("no root XML element found")
}

fn parse_tag_and_attrs(s: &str) -> (String, BTreeMap<String, String>) {
    let mut chars = s.char_indices().peekable();
    let mut tag_end = s.len();
    for (idx, ch) in chars.by_ref() {
        if ch.is_whitespace() {
            tag_end = idx;
            break;
        }
    }
    let tag = s[..tag_end].to_string();
    let mut attrib = BTreeMap::new();
    let mut rest = s[tag_end..].trim();
    while !rest.is_empty() {
        let eq = rest.find('=').expect("attribute missing '='");
        let key = rest[..eq].trim().to_string();
        rest = rest[eq + 1..].trim_start();
        let quote = rest.chars().next().expect("attribute missing quote");
        assert!(quote == '"' || quote == '\'');
        rest = &rest[quote.len_utf8()..];
        let val_end = rest.find(quote).expect("unterminated attribute value");
        let val = rest[..val_end].to_string();
        attrib.insert(key, val);
        rest = rest[val_end + quote.len_utf8()..].trim_start();
    }
    (tag, attrib)
}

#[test]
fn test_manifest_is_valid_code_free_wff_package() {
    let manifest_path = base_dir().join("AndroidManifest.xml");
    let root = parse_xml_file(&manifest_path);
    assert_eq!(
        root.attr("package"),
        Some("com.watchfacestudio.daytonaplatinum")
    );

    let app = root.find("application").expect("missing <application>");
    assert_eq!(app.attr("android:hasCode"), Some("false"));

    let mut props = BTreeMap::new();
    for p in app.findall("property") {
        if let (Some(k), Some(v)) = (p.attr("android:name"), p.attr("android:value")) {
            props.insert(k.to_string(), v.to_string());
        }
    }
    assert_eq!(
        props
            .get("com.google.wear.watchface.format.version")
            .map(|s| s.as_str()),
        Some("2")
    );
}

#[test]
fn test_required_xml_descriptors_exist_and_match_450_circle() {
    let base = base_dir();
    let shapes = parse_xml_file(&base.join("res/xml/watch_face_shapes.xml"));
    let wf = shapes.find("WatchFace").expect("missing <WatchFace>");
    assert_eq!(wf.attr("file"), Some("@raw/watchface"));
    assert_eq!(wf.attr("shape"), Some("CIRCLE"));
    assert_eq!(wf.attr("width"), Some("450"));
    assert_eq!(wf.attr("height"), Some("450"));

    let info = parse_xml_file(&base.join("res/xml/watch_face_info.xml"));
    let preview = info.find("Preview").expect("missing <Preview>");
    assert_eq!(preview.attr("value"), Some("@drawable/preview"));

    let wallpaper = parse_xml_file(&base.join("res/xml/watch_face.xml"));
    assert_eq!(wallpaper.tag, "wallpaper");
}

#[test]
fn test_watchface_xml_integrates_all_complications_and_assets() {
    let base = base_dir();
    let root = parse_xml_file(&base.join("res/raw/watchface.xml"));
    assert_eq!(root.tag, "WatchFace");
    assert_eq!(root.attr("width"), Some("450"));
    assert_eq!(root.attr("height"), Some("450"));
    assert_eq!(root.attr("clipShape"), Some("CIRCLE"));

    let strings_root = parse_xml_file(&base.join("res/values/strings.xml"));
    let defined_strings: BTreeSet<String> = strings_root
        .findall("string")
        .into_iter()
        .map(|s| s.attr("name").expect("string missing name").to_string())
        .collect();

    let slots = root.findall_descendants("ComplicationSlot");
    assert_eq!(slots.len(), 5);
    let slot_names: BTreeSet<&str> = slots.iter().filter_map(|s| s.attr("name")).collect();
    let expected_slots: BTreeSet<&str> = [
        "world_clock_slot",
        "heart_rate_slot",
        "weather_slot",
        "steps_slot",
        "solar_slot",
    ]
    .into_iter()
    .collect();
    assert_eq!(slot_names, expected_slots);

    for slot in slots {
        let display_name = slot.attr("displayName").expect("slot missing displayName");
        assert!(
            defined_strings.contains(display_name),
            "undefined slot displayName {display_name}"
        );
        let x: i32 = slot.attr("x").unwrap().parse().unwrap();
        let y: i32 = slot.attr("y").unwrap().parse().unwrap();
        let w: i32 = slot.attr("width").unwrap().parse().unwrap();
        let h: i32 = slot.attr("height").unwrap().parse().unwrap();
        assert!(x >= 0);
        assert!(y >= 0);
        assert!(x + w <= 450);
        assert!(y + h <= 450);
    }

    let drawable_dir = base.join("res/drawable-nodpi");
    let expected_450 = [
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
    ];
    for filename in expected_450 {
        let png_path = drawable_dir.join(filename);
        assert!(png_path.is_file(), "Missing {filename}");
        assert_eq!(read_png_dimensions(&png_path), (450, 450));
    }

    let subdial_path = drawable_dir.join("subdial_hand.png");
    assert!(subdial_path.is_file());
    assert_eq!(read_png_dimensions(&subdial_path), (88, 88));

    let subdial_exp_path = drawable_dir.join("subdial_hand_expanded.png");
    assert!(subdial_exp_path.is_file());
    assert_eq!(read_png_dimensions(&subdial_exp_path), (120, 120));

    let unread_path = drawable_dir.join("unread_badge.png");
    assert!(unread_path.is_file());
    assert_eq!(read_png_dimensions(&unread_path), (24, 24));
}

#[test]
fn test_user_configurations_define_all_chronograph_options_and_launch_targets() {
    let base = base_dir();
    let root = parse_xml_file(&base.join("res/raw/watchface.xml"));
    let strings_root = parse_xml_file(&base.join("res/values/strings.xml"));
    let mut defined_strings = BTreeMap::new();
    for s in strings_root.findall("string") {
        let name = s.attr("name").expect("string missing name");
        let text = &s.text;
        assert!(
            !text.contains('%'),
            "String '{name}' contains '%' which crashes DeclarativeWatchFaceRuntime.getUserStyleSchema()"
        );
        defined_strings.insert(name.to_string(), text.clone());
    }

    let user_configs = root
        .find("UserConfigurations")
        .expect("missing <UserConfigurations>");
    let list_configs: BTreeMap<&str, &XmlElement> = user_configs
        .findall("ListConfiguration")
        .into_iter()
        .map(|cfg| (cfg.attr("id").expect("ListConfiguration missing id"), cfg))
        .collect();

    let expected_configs: &[(&str, &str, &[&str])] = &[
        (
            "theme_style",
            "theme_platinum",
            &[
                "theme_platinum",
                "theme_panda",
                "theme_reverse_panda",
                "theme_lemans",
            ],
        ),
        (
            "bezel_mode",
            "bezel_expanded",
            &["bezel_expanded", "bezel_full"],
        ),
        (
            "aod_mode",
            "aod_chromalight",
            &["aod_chromalight", "aod_ultra"],
        ),
        (
            "subdial_mode",
            "subdials_smart",
            &["subdials_smart", "subdials_chrono", "subdials_minimal"],
        ),
        ("status_badges", "badges_on", &["badges_on", "badges_off"]),
        (
            "font_scale",
            "font_standard",
            &["font_standard", "font_large", "font_xlarge"],
        ),
    ];

    for (cfg_id, expected_default, expected_opts) in expected_configs {
        let cfg = list_configs
            .get(cfg_id)
            .unwrap_or_else(|| panic!("missing ListConfiguration {cfg_id}"));
        assert_eq!(cfg.attr("defaultValue"), Some(*expected_default));
        assert!(defined_strings.contains_key(cfg.attr("displayName").unwrap_or("")));
        assert!(defined_strings.contains_key(cfg.attr("screenReaderText").unwrap_or("")));
        assert!(!cfg.attr("icon").unwrap_or("").is_empty());

        let opts: Vec<&str> = cfg
            .findall("ListOption")
            .into_iter()
            .map(|opt| opt.attr("id").expect("ListOption missing id"))
            .collect();
        assert_eq!(&opts[..], *expected_opts);
        for opt in cfg.findall("ListOption") {
            assert!(defined_strings.contains_key(opt.attr("displayName").unwrap_or("")));
            assert!(defined_strings.contains_key(opt.attr("screenReaderText").unwrap_or("")));
            assert!(!opt.attr("icon").unwrap_or("").is_empty());
        }
    }

    let scene = root.find("Scene").expect("missing <Scene>");
    let launches: BTreeSet<&str> = scene
        .findall_descendants("Launch")
        .into_iter()
        .filter_map(|el| el.attr("target"))
        .collect();
    let expected_launches: BTreeSet<&str> = ["ALARM", "CALENDAR", "BATTERY_STATUS"]
        .into_iter()
        .collect();
    assert_eq!(launches, expected_launches);
}
