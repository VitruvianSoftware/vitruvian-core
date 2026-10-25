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

//! Device profiles: the built-in catalog, per-machine overrides, and
//! matching discovered or attached devices to a profile.

use crate::py::{s, strip, utf8_error, Dict, Val};
use crate::pyjson;
use crate::Tool;

pub const SERVICE_TLS_CONNECT: &str = "_adb-tls-connect._tcp";
pub const SERVICE_LEGACY: &str = "_adb._tcp";
pub const ADB_MDNS_SERVICES: [&str; 2] = [SERVICE_TLS_CONNECT, SERVICE_LEGACY];
pub const ADB_PAIRING_SERVICE: &str = "_adb-tls-pairing._tcp";

#[allow(clippy::too_many_arguments)]
fn profile(
    key: &str,
    display_name: &str,
    role: &str,
    default: bool,
    codename: &str,
    service_type: &str,
    aliases: &[&str],
    model_patterns: &[&str],
) -> Dict {
    let list = |xs: &[&str]| Val::List(xs.iter().map(|x| s(*x)).collect());
    Dict::from_pairs(vec![
        ("key", s(key)),
        ("display_name", s(display_name)),
        ("role", s(role)),
        ("default", Val::Bool(default)),
        ("codename", s(codename)),
        ("service_type", s(service_type)),
        ("aliases", list(aliases)),
        ("model_patterns", list(model_patterns)),
    ])
}

/// `KNOWN_DEVICE_PROFILES`.
pub fn known_device_profiles() -> Vec<Dict> {
    vec![
        profile(
            "fold",
            "Pixel 11 Pro Fold",
            "primary",
            true,
            "yogi",
            SERVICE_TLS_CONNECT,
            &[
                "fold",
                "pixel-fold",
                "pixelfold",
                "pixel-11-pro-fold",
                "pixel11",
                "yogi",
                "primary",
            ],
            &["pixel 11 pro fold", "pixel_11_pro_fold", "yogi"],
        ),
        profile(
            "pixel4",
            "Pixel 4 XL",
            "secondary",
            false,
            "coral",
            SERVICE_TLS_CONNECT,
            &[
                "pixel4",
                "pixel-4",
                "pixel-4-xl",
                "pixel4xl",
                "coral",
                "secondary",
                "test",
            ],
            &["pixel 4 xl", "pixel_4_xl", "coral"],
        ),
        profile(
            "watch",
            "Pixel Watch 4",
            "watch",
            false,
            "kenari_lte",
            SERVICE_TLS_CONNECT,
            &[
                "watch",
                "pixel-watch",
                "pixelwatch",
                "pixel-watch-4",
                "pixelwatch4",
                "pw4",
                "kenari",
                "kenari_lte",
                "wear",
            ],
            &["pixel watch 4", "pixel_watch_4", "kenari_lte", "kenari"],
        ),
        profile(
            "tv",
            "Living Room Sony TV",
            "tv",
            false,
            "bravia",
            SERVICE_LEGACY,
            &[
                "tv",
                "sony",
                "bravia",
                "sony-tv",
                "living-room-tv",
                "android-tv",
            ],
            &["bravia", "living room sony tv"],
        ),
    ]
}

/// `extract_serial_from_id(identifier)` for an identifier that is a str.
pub fn extract_serial(identifier: &str) -> String {
    if identifier.is_empty() {
        return String::new();
    }
    let mut clean = identifier;
    for suffix in [
        "._adb-tls-connect._tcp",
        "._adb._tcp",
        "._adb-tls-pairing._tcp",
    ] {
        if let Some(stripped) = clean.strip_suffix(suffix) {
            clean = stripped;
            break;
        }
    }
    match clean.strip_prefix("adb-") {
        Some(raw) => raw.split('-').next().unwrap_or("").to_string(),
        None => String::new(),
    }
}

/// `extract_serial_from_id(identifier)` for any value.
pub fn extract_serial_from_id(identifier: &Val) -> String {
    if !identifier.truthy() {
        return String::new();
    }
    extract_serial(identifier.expect_str("endswith"))
}

/// `(d.get("serial") or extract_serial_from_id(d.get(id_key, ""))).lower()`.
pub fn serial_of(d: &Dict, id_key: &str) -> String {
    d.get_none("serial")
        .or_else(|| s(extract_serial_from_id(&d.get_str_default(id_key))))
        .lower()
}

impl<'a> Tool<'a> {
    /// `load_device_profiles(config_path)`: the catalog merged with the
    /// user's `adb-devices.json`.
    pub fn load_device_profiles(&self, config_path: Option<&str>) -> Vec<Dict> {
        let profiles = known_device_profiles();
        let path = config_path.unwrap_or(&self.default_config_path).to_string();
        let is_file = std::fs::metadata(&path).map_or(false, |m| m.is_file());
        if !is_file {
            return profiles;
        }
        let user_data = match read_json(&path) {
            Ok(v) => v,
            Err(exc) => {
                self.eprint(&format!(
                    "Warning: ignoring invalid JSON in {}: {}",
                    path, exc
                ));
                return profiles;
            }
        };
        let entries = match &user_data {
            Val::Dict(d) => d.get_or("devices", Val::List(vec![])),
            other => other.clone(),
        };
        let Val::List(entries) = entries else {
            return profiles;
        };

        let mut by_key: Vec<(String, Dict)> = profiles
            .into_iter()
            .map(|p| (p.item("key").py_str(), p))
            .collect();
        let mut extra: Vec<Dict> = Vec::new();
        for entry in entries {
            let Val::Dict(entry) = entry else { continue };
            let Some(Val::Str(raw_key)) = entry.get("key") else {
                continue;
            };
            if strip(raw_key).is_empty() {
                continue;
            }
            let k = strip(raw_key).to_lowercase();
            let mut normalized = entry.clone();
            normalized.set("key", s(k.clone()));
            if let Some(slot) = by_key.iter_mut().find(|(key, _)| *key == k) {
                let mut merged = slot.1.clone();
                merged.update(&normalized);
                slot.1 = merged;
            } else {
                extra.push(normalized);
            }
        }
        by_key.into_iter().map(|(_, p)| p).chain(extra).collect()
    }
}

/// `open(path, encoding="utf-8")` + `json.load`, with Python's messages.
fn read_json(path: &str) -> Result<Val, String> {
    let bytes = std::fs::read(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::PermissionDenied => {
            format!(
                "[Errno 13] Permission denied: {}",
                crate::py::repr_str(path)
            )
        }
        _ => e.to_string(),
    })?;
    if let Some(msg) = utf8_error(&bytes) {
        return Err(msg);
    }
    let text = crate::py::universal_newlines(std::str::from_utf8(&bytes).expect("checked"));
    pyjson::loads(&text).map_err(|e| e.0)
}

/// `match_device_profile(dev, profiles)`: serial first, then codename and
/// model patterns (a `_adb._tcp` profile only matches `_adb._tcp` devices).
pub fn match_device_profile<'p>(dev: &Dict, catalog: &'p [Dict]) -> Option<&'p Dict> {
    let dev_serial = serial_of(dev, "instance");
    let dev_codename = dev
        .get_none("device")
        .or_else(|| dev.get_none("product"))
        .or(s(""))
        .lower();
    let dev_svc = dev.get_str_default("service_type");
    let haystack = [
        "given_name",
        "name",
        "model",
        "device",
        "product",
        "instance",
    ]
    .iter()
    .map(|f| dev.get_str_default(f).py_str())
    .collect::<Vec<_>>()
    .join(" ")
    .to_lowercase();

    if !dev_serial.is_empty() {
        for prof in catalog {
            let prof_serial = prof.get_str_default("serial").py_str().to_lowercase();
            if !prof_serial.is_empty() && prof_serial == dev_serial {
                return Some(prof);
            }
        }
    }

    for prof in catalog {
        if prof.get_str_default("service_type").eq_str(SERVICE_LEGACY)
            && dev_svc.truthy()
            && !dev_svc.eq_str(SERVICE_LEGACY)
        {
            continue;
        }
        let prof_code = prof.get_str_default("codename").py_str().to_lowercase();
        if !prof_code.is_empty() && !dev_codename.is_empty() && prof_code == dev_codename {
            return Some(prof);
        }
        for pat in prof
            .get_or("model_patterns", Val::List(vec![]))
            .iter_items()
        {
            if haystack.contains(&pat.lower()) {
                return Some(prof);
            }
        }
    }
    None
}

/// `enrich_device_with_profile(dev, profiles)`.
pub fn enrich_device_with_profile(dev: &mut Dict, catalog: &[Dict]) {
    if let Some(prof) = match_device_profile(dev, catalog).cloned() {
        dev.set("profile_key", prof.item("key"));
        dev.set("role", prof.get_or("role", s("secondary")));
        dev.set(
            "is_default",
            Val::Bool(prof.get_or("default", Val::Bool(false)).truthy()),
        );
        dev.set(
            "aliases",
            Val::List(prof.get_or("aliases", Val::List(vec![])).iter_items()),
        );
        dev.set("codename", prof.get_or("codename", s("")));
        if !dev.get_none("name").truthy() {
            dev.set("name", prof.get_or("display_name", s("")));
        }
        if !dev.get_none("given_name").truthy() {
            dev.set("given_name", prof.get_or("display_name", s("")));
        }
    } else {
        dev.setdefault("profile_key", s(""));
        let role = if dev.get_none("service_type").eq_str(SERVICE_LEGACY) {
            "tv"
        } else {
            "phone"
        };
        dev.setdefault("role", s(role));
        dev.setdefault("is_default", Val::Bool(false));
        dev.setdefault("aliases", Val::List(vec![]));
        let codename = dev.get_str_default("device");
        dev.setdefault("codename", codename);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{dev, MockSystem};

    #[test]
    fn extract_serial_handles_instance_and_transport_ids() {
        assert_eq!(
            extract_serial("adb-66211FDDJ000XR-DYsKrZ"),
            "66211FDDJ000XR"
        );
        assert_eq!(extract_serial("adb-24adbf003005591"), "24adbf003005591");
        assert_eq!(
            extract_serial("adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp"),
            "98271FFBA007YW"
        );
        assert_eq!(extract_serial("192.168.86.31:5555"), "");
        assert_eq!(extract_serial(""), "");
    }

    #[test]
    fn serial_in_custom_profile_wins_over_builtin_model_pattern() {
        let mut profiles = known_device_profiles();
        profiles.push(Dict::from_pairs(vec![
            ("key", s("pixel4-lab")),
            ("display_name", s("Pixel 4 XL Lab")),
            ("serial", s("SECONDPIXEL4SERIAL")),
            ("codename", s("coral")),
            ("role", s("secondary")),
            ("default", Val::Bool(false)),
            ("aliases", Val::List(vec![s("pixel4-lab")])),
            ("model_patterns", Val::List(vec![s("pixel 4 xl")])),
        ]));
        let second = dev(&[
            ("instance", "adb-SECONDPIXEL4SERIAL-xyz"),
            ("serial", "SECONDPIXEL4SERIAL"),
            ("name", "Pixel 4 XL"),
            ("given_name", "Pixel 4 XL"),
            ("service_type", "_adb-tls-connect._tcp"),
        ]);
        let matched = match_device_profile(&second, &profiles).unwrap();
        assert_eq!(matched.get("key"), Some(&s("pixel4-lab")));
    }

    #[test]
    fn tv_profile_only_matches_legacy_service() {
        let profiles = known_device_profiles();
        let phone_named_bravia = dev(&[
            ("instance", "adb-X"),
            ("name", "bravia"),
            ("service_type", "_adb-tls-connect._tcp"),
        ]);
        assert!(match_device_profile(&phone_named_bravia, &profiles).is_none());
        let tv = dev(&[
            ("instance", "adb-Y"),
            ("name", "Bravia"),
            ("service_type", "_adb._tcp"),
        ]);
        assert_eq!(
            match_device_profile(&tv, &profiles).unwrap().get("key"),
            Some(&s("tv"))
        );
    }

    #[test]
    fn load_device_profiles_merges_user_config() {
        let dir = crate::testutil::TempDir::new();
        let path = dir.write(
            "adb-devices.json",
            r#"{"devices": [{"key": "Fold", "serial": "66211FDDJ000XR"},
                {"key": "pixel4", "serial": "98271FFBA007YW"},
                {"key": 12345, "serial": "INVALID_KEY"},
                {"key": "lab", "display_name": "Lab phone"}]}"#,
        );
        let sys = MockSystem::new();
        let (tool, _, err) = crate::testutil::tool(&sys);
        let profiles = tool.load_device_profiles(Some(&path));
        let find = |k: &str| {
            profiles
                .iter()
                .find(|p| p.get("key") == Some(&s(k)))
                .cloned()
        };
        assert_eq!(
            find("fold").unwrap().get("serial"),
            Some(&s("66211FDDJ000XR"))
        );
        assert_eq!(find("fold").unwrap().get("codename"), Some(&s("yogi")));
        assert_eq!(
            find("pixel4").unwrap().get("serial"),
            Some(&s("98271FFBA007YW"))
        );
        assert_eq!(profiles.len(), 5);
        assert_eq!(profiles[4].get("key"), Some(&s("lab")));
        assert_eq!(err.text(), "");
    }

    #[test]
    fn load_device_profiles_warns_on_invalid_json() {
        let dir = crate::testutil::TempDir::new();
        let path = dir.write("adb-devices.json", "{\"devices\": [}");
        let sys = MockSystem::new();
        let (tool, _, err) = crate::testutil::tool(&sys);
        let profiles = tool.load_device_profiles(Some(&path));
        assert_eq!(profiles.len(), 4);
        assert_eq!(
            err.text(),
            format!(
                "Warning: ignoring invalid JSON in {}: Expecting value: line 1 column 14 (char 13)\n",
                path
            )
        );
        // A list at the top level is the entries; a scalar is ignored.
        let list_path = dir.write("list.json", r#"[{"key": "tv", "serial": "TVSERIAL"}]"#);
        let tv = tool.load_device_profiles(Some(&list_path))[3].clone();
        assert_eq!(tv.get("serial"), Some(&s("TVSERIAL")));
        let scalar = dir.write("scalar.json", "42");
        assert_eq!(tool.load_device_profiles(Some(&scalar)).len(), 4);
    }

    #[test]
    fn enrich_sets_profile_fields_or_defaults() {
        let profiles = known_device_profiles();
        let mut watch = dev(&[
            ("instance", "adb-58301WRBNL30SD-js57rs"),
            ("name", "Pixel Watch 4"),
        ]);
        enrich_device_with_profile(&mut watch, &profiles);
        assert_eq!(watch.get("profile_key"), Some(&s("watch")));
        assert_eq!(watch.get("role"), Some(&s("watch")));
        assert_eq!(watch.get("given_name"), Some(&s("Pixel Watch 4")));
        let mut unknown = dev(&[("id", "emulator-5554"), ("device", "emu64a")]);
        enrich_device_with_profile(&mut unknown, &profiles);
        assert_eq!(unknown.get("profile_key"), Some(&s("")));
        assert_eq!(unknown.get("role"), Some(&s("phone")));
        assert_eq!(unknown.get("codename"), Some(&s("emu64a")));
        assert_eq!(unknown.get("aliases"), Some(&Val::List(vec![])));
    }
}
