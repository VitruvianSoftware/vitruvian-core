// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Adversarial challenge and stress-test suite for Milestone 2:
//! - Frontmost application detection and profile resolution edge cases
//! - Debounce state machine under rapid focus switching and clock anomalies
//! - Fuzzy heuristics and substring collision analysis
//! - Wire protocol serialization, malformed JSON, and buffer capacity
//! Migrated from `tests/test_challenger_m2.py`.

use app_profiles::{build_app_payload, get_profile_for_bundle_and_name, AppProfile, MacroKey};

use crate::json_escape_str;

/// Stateful debounce detector matching `FrontmostAppDetector` in `app_profiles.py`.
#[derive(Clone, Debug)]
pub struct FrontmostAppDetectorModel {
    pub debounce_seconds: f64,
    pub confirmed_bundle_id: Option<String>,
    pub confirmed_app_name: Option<String>,
    pub pending_bundle_id: Option<String>,
    pub pending_app_name: Option<String>,
    pub pending_since: f64,
}

impl FrontmostAppDetectorModel {
    pub fn new(debounce_seconds: f64) -> Self {
        Self {
            debounce_seconds,
            confirmed_bundle_id: None,
            confirmed_app_name: None,
            pending_bundle_id: None,
            pending_app_name: None,
            pending_since: 0.0,
        }
    }

    pub fn update_with_sample(
        &mut self,
        raw_bundle: &str,
        raw_name: &str,
        now: f64,
        force_immediate: bool,
    ) -> Option<String> {
        if force_immediate || self.confirmed_bundle_id.is_none() {
            self.confirmed_bundle_id = Some(raw_bundle.to_string());
            self.confirmed_app_name = Some(raw_name.to_string());
            self.pending_bundle_id = None;
            self.pending_app_name = None;
            return self.confirmed_bundle_id.clone();
        }

        if self.confirmed_bundle_id.as_deref() == Some(raw_bundle) {
            self.pending_bundle_id = None;
            self.pending_app_name = None;
            return None;
        }

        if self.pending_bundle_id.as_deref() != Some(raw_bundle) {
            self.pending_bundle_id = Some(raw_bundle.to_string());
            self.pending_app_name = Some(raw_name.to_string());
            self.pending_since = now;
            return None;
        }

        if now - self.pending_since >= self.debounce_seconds {
            self.confirmed_bundle_id = self.pending_bundle_id.take();
            self.confirmed_app_name = self.pending_app_name.take();
            return self.confirmed_bundle_id.clone();
        }

        None
    }

    pub fn fallback_on_query_error() -> (String, String) {
        ("com.apple.finder".to_string(), "Finder".to_string())
    }
}

/// Resolves an application profile trimming whitespace (mirroring `get_profile_for_app` in Python).
pub fn resolve_profile(bundle_id: Option<&str>, app_name: Option<&str>) -> &'static AppProfile {
    let b = bundle_id.unwrap_or("").trim();
    let a = app_name.unwrap_or("").trim();
    get_profile_for_bundle_and_name(b, a)
}

/// Serializes an arbitrary custom profile with JSON escaping to test framing resilience.
pub fn build_escaped_app_payload(
    app: &str,
    color: &str,
    buttons: &[(&str, u8, u8, u16, &str); 6],
) -> String {
    let btns: Vec<String> = buttons
        .iter()
        .map(|(label, mod_mask, key, cons, btn_color)| {
            format!(
                r#"{{"label":"{}","mod":{},"key":{},"cons":{},"color":"{}"}}"#,
                json_escape_str(label),
                mod_mask,
                key,
                cons,
                json_escape_str(btn_color)
            )
        })
        .collect();
    format!(
        r#"{{"type":"app","app":"{}","color":"{}","buttons":[{}]}}"#,
        json_escape_str(app),
        json_escape_str(color),
        btns.join(",")
    )
}

/// Firmware prefilter + structural check for incoming JSON frames.
pub fn firmware_prefilter_and_validate(line: &str) -> bool {
    let trimmed = line.trim();
    if trimmed.is_empty() || !trimmed.starts_with('{') || !trimmed.ends_with('}') {
        return false;
    }
    if trimmed.contains('\'') || trimmed.contains("[}") || trimmed.contains(": }") {
        return false;
    }
    true
}

pub fn run_suite() -> usize {
    let mut checks = 0usize;

    // 1. Empty & whitespace inputs
    assert_eq!(resolve_profile(Some(""), Some("")).app, "Default");
    assert_eq!(resolve_profile(Some("   "), Some("   ")).app, "Default");
    assert_eq!(resolve_profile(None, None).app, "Default");
    assert_eq!(resolve_profile(None, Some("")).app, "Default");
    assert_eq!(resolve_profile(Some(""), None).app, "Default");
    checks += 5;

    // 2. Unknown applications
    assert_eq!(
        resolve_profile(Some("com.spotify.client"), Some("Spotify")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(Some("org.blender.blender"), Some("Blender")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(Some("com.docker.docker"), Some("Docker Desktop")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(Some("com.figma.Desktop"), Some("Figma")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(Some("com.valvesoftware.steam"), Some("Steam")).app,
        "Default"
    );
    checks += 5;

    // 3. Unicode & special character names
    assert_eq!(
        resolve_profile(Some("com.example.🚀"), Some("🚀 Fast App")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(Some("com.example.app"), Some("日本語エディタ")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(Some("com.example.app"), Some("محرر النصوص")).app,
        "Default"
    );
    assert_eq!(
        resolve_profile(
            Some("com.example.app"),
            Some("App <script>alert(1)</script>")
        )
        .app,
        "Default"
    );
    checks += 4;

    // 4. Substring bundle_id & fuzzy name collisions
    assert_eq!(resolve_profile(Some("com"), None).app, "VS Code");
    assert_eq!(resolve_profile(Some("com.apple"), None).app, "Chrome");
    assert_eq!(resolve_profile(Some("io"), None).app, "VS Code");
    assert_eq!(resolve_profile(Some("net"), None).app, "Terminal");
    assert_eq!(resolve_profile(Some("org"), None).app, "Chrome");
    assert_eq!(resolve_profile(Some("app"), None).app, "Chrome");
    assert_eq!(
        resolve_profile(Some("com.apple.dt.Xcode"), Some("Xcode")).app,
        "VS Code"
    );
    assert_eq!(
        resolve_profile(Some("com.example.barcode"), Some("Barcode Scanner")).app,
        "VS Code"
    );
    assert_eq!(
        resolve_profile(Some("com.example.passcode"), Some("Passcode Manager")).app,
        "VS Code"
    );
    assert_eq!(
        resolve_profile(Some("com.example.unicode"), Some("Unicode Converter")).app,
        "VS Code"
    );
    assert_eq!(
        resolve_profile(Some("missing value"), Some("Calculator")).app,
        "Default"
    );
    checks += 11;

    // 5. Rapid-fire app switching stress
    let mut detector = FrontmostAppDetectorModel::new(0.25);
    detector.update_with_sample("com.apple.finder", "Finder", 1000.0, true);
    let mut t = 1000.0;
    for i in 0..20 {
        t += 0.015;
        let app = format!("com.app.{}", i);
        assert!(detector.update_with_sample(&app, &app, t, false).is_none());
    }
    assert_eq!(
        detector.confirmed_bundle_id.as_deref(),
        Some("com.apple.finder")
    );
    checks += 1;

    // 6. Near-boundary debounce timing & flicker reset
    let mut det2 = FrontmostAppDetectorModel::new(0.25);
    det2.update_with_sample("com.apple.finder", "Finder", 0.0, true);
    assert!(det2
        .update_with_sample("com.google.Chrome", "Google Chrome", 500.0, false)
        .is_none());
    assert!(det2
        .update_with_sample("com.google.Chrome", "Google Chrome", 500.249, false)
        .is_none());
    assert_eq!(
        det2.update_with_sample("com.google.Chrome", "Google Chrome", 500.251, false)
            .as_deref(),
        Some("com.google.Chrome")
    );
    assert!(det2
        .update_with_sample("com.google.Chrome", "Google Chrome", 500.252, false)
        .is_none());
    checks += 2;

    // 7. Wire protocol newline injection & max-length labels
    let wire_str = build_escaped_app_payload(
        "Test\nApp",
        "0x007ACC",
        &[("Line1\nLine2", 0, b'a', 0, "0x007ACC"); 6],
    );
    assert!(!wire_str.contains('\n'));
    assert!(wire_str.replace("\\n", "\n").split('\n').count() > 1);

    let max_label = "W".repeat(31);
    let max_app = "A".repeat(32);
    let max_wire = build_escaped_app_payload(
        &max_app,
        "0xFFFFFF",
        &[(&max_label, 15, 255, 65535, "0xFFFFFF"); 6],
    );
    let wire_bytes = format!("{}\n", max_wire).into_bytes();
    assert!(wire_bytes.len() < 800);
    assert!(wire_bytes.len() < 1024);

    let default_wire = build_app_payload(get_profile_for_bundle_and_name("", ""));
    assert!(default_wire.len() < 1024);
    let _ = MacroKey {
        label: "X",
        mod_mask: 0,
        key: 0,
        cons: 0,
        color: "0x000000",
    };
    checks += 3;

    checks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_empty_and_whitespace_inputs() {
        assert_eq!(resolve_profile(Some(""), Some("")).app, "Default");
        assert_eq!(resolve_profile(Some("   "), Some("   ")).app, "Default");
        assert_eq!(resolve_profile(None, None).app, "Default");
        assert_eq!(resolve_profile(None, Some("")).app, "Default");
        assert_eq!(resolve_profile(Some(""), None).app, "Default");
    }

    #[test]
    fn test_unknown_and_unicode_applications() {
        assert_eq!(
            resolve_profile(Some("com.spotify.client"), Some("Spotify")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("org.blender.blender"), Some("Blender")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("com.docker.docker"), Some("Docker Desktop")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("com.figma.Desktop"), Some("Figma")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("com.valvesoftware.steam"), Some("Steam")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("com.example.🚀"), Some("🚀 Fast App")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("com.example.app"), Some("日本語エディタ")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("com.example.app"), Some("محرر النصوص")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(
                Some("com.example.app"),
                Some("App <script>alert(1)</script>")
            )
            .app,
            "Default"
        );
    }

    #[test]
    fn test_substring_and_fuzzy_collision_risks() {
        assert_eq!(resolve_profile(Some("com"), None).app, "VS Code");
        assert_eq!(resolve_profile(Some("com.apple"), None).app, "Chrome");
        assert_eq!(resolve_profile(Some("io"), None).app, "VS Code");
        assert_eq!(resolve_profile(Some("net"), None).app, "Terminal");
        assert_eq!(resolve_profile(Some("org"), None).app, "Chrome");
        assert_eq!(resolve_profile(Some("app"), None).app, "Chrome");

        assert_eq!(
            resolve_profile(Some("com.apple.dt.Xcode"), Some("Xcode")).app,
            "VS Code"
        );
        assert_eq!(
            resolve_profile(Some("com.example.barcode"), Some("Barcode Scanner")).app,
            "VS Code"
        );
        assert_eq!(
            resolve_profile(Some("com.example.passcode"), Some("Passcode Manager")).app,
            "VS Code"
        );
        assert_eq!(
            resolve_profile(Some("com.example.unicode"), Some("Unicode Converter")).app,
            "VS Code"
        );
        assert_eq!(
            resolve_profile(Some("missing value"), Some("Calculator")).app,
            "Default"
        );
        assert_eq!(
            resolve_profile(Some("missing value"), Some("")).app,
            "Default"
        );
    }

    #[test]
    fn test_rapid_fire_switching_and_debounce_boundaries() {
        let mut detector = FrontmostAppDetectorModel::new(0.25);
        detector.update_with_sample("com.apple.finder", "Finder", 1000.0, true);

        let mut t = 1000.0;
        for i in 0..20 {
            t += 0.015;
            let app = format!("com.app.{}", i);
            assert!(detector.update_with_sample(&app, &app, t, false).is_none());
        }
        assert_eq!(
            detector.confirmed_bundle_id.as_deref(),
            Some("com.apple.finder")
        );

        // Near-boundary timing (249ms vs 251ms)
        let mut det2 = FrontmostAppDetectorModel::new(0.25);
        det2.update_with_sample("com.apple.finder", "Finder", 0.0, true);
        let t0 = 500.0;
        assert!(det2
            .update_with_sample("com.google.Chrome", "Google Chrome", t0, false)
            .is_none());
        assert!(det2
            .update_with_sample("com.google.Chrome", "Google Chrome", t0 + 0.249, false)
            .is_none());
        assert_eq!(
            det2.confirmed_bundle_id.as_deref(),
            Some("com.apple.finder")
        );
        assert_eq!(
            det2.update_with_sample("com.google.Chrome", "Google Chrome", t0 + 0.251, false)
                .as_deref(),
            Some("com.google.Chrome")
        );
        assert!(det2
            .update_with_sample("com.google.Chrome", "Google Chrome", t0 + 0.252, false)
            .is_none());
    }

    #[test]
    fn test_flicker_to_third_app_resets_debounce_and_query_fallback() {
        let mut detector = FrontmostAppDetectorModel::new(0.25);
        detector.update_with_sample("com.app.A", "A", 0.0, true);

        detector.update_with_sample("com.app.B", "B", 100.0, false);
        detector.update_with_sample("com.app.B", "B", 100.20, false);
        detector.update_with_sample("com.app.C", "C", 100.21, false);
        assert_eq!(detector.pending_bundle_id.as_deref(), Some("com.app.C"));

        detector.update_with_sample("com.app.B", "B", 100.22, false);
        assert_eq!(detector.pending_bundle_id.as_deref(), Some("com.app.B"));
        assert!(detector
            .update_with_sample("com.app.B", "B", 100.26, false)
            .is_none());
        assert_eq!(
            detector
                .update_with_sample("com.app.B", "B", 100.48, false)
                .as_deref(),
            Some("com.app.B")
        );

        let (fb_bundle, fb_name) = FrontmostAppDetectorModel::fallback_on_query_error();
        assert_eq!(fb_bundle, "com.apple.finder");
        assert_eq!(fb_name, "Finder");
    }

    #[test]
    fn test_newline_injection_max_labels_and_malformed_json() {
        let wire_str = build_escaped_app_payload(
            "Test\nApp",
            "0x007ACC",
            &[("Line1\nLine2", 0, b'a', 0, "0x007ACC"); 6],
        );
        assert!(!wire_str.contains('\n'));
        assert!(wire_str.replace("\\n", "\n").split('\n').count() > 1);

        let max_label = "W".repeat(31);
        let max_app = "A".repeat(32);
        let max_wire = build_escaped_app_payload(
            &max_app,
            "0xFFFFFF",
            &[(&max_label, 15, 255, 65535, "0xFFFFFF"); 6],
        );
        let wire_len = format!("{}\n", max_wire).len();
        assert!(wire_len < 800);
        assert!(wire_len < 1024);

        for bad in [
            "",
            "   ",
            "{",
            "}",
            "{'type': 'app'}",
            "{\"type\": \"app\", \"buttons\": [}",
            "{\"type\": \"app\", \"buttons\": [{\"label\": \"A\", \"mod\": }]}",
            "\x00\x01\x02",
        ] {
            assert!(!firmware_prefilter_and_validate(bad));
        }
    }
}
