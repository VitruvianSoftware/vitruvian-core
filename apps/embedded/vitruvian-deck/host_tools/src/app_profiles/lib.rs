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

use std::process::Command;

pub const MOD_NONE: u8 = 0x00;
pub const MOD_CTRL: u8 = 0x01;
pub const MOD_SHIFT: u8 = 0x02;
pub const MOD_ALT: u8 = 0x04;
pub const MOD_CMD: u8 = 0x08;

pub const KEY_UP_ARROW: u8 = 0xDA;
pub const KEY_DOWN_ARROW: u8 = 0xD9;
pub const KEY_LEFT_ARROW: u8 = 0xD8;
pub const KEY_RIGHT_ARROW: u8 = 0xD7;
pub const KEY_RETURN: u8 = 0xB0;
pub const KEY_ESC: u8 = 0xB1;
pub const KEY_TAB: u8 = 0xB3;
pub const KEY_BACKSPACE: u8 = 0xB2;
pub const KEY_F11: u8 = 0xCC;

pub const CONS_NONE: u16 = 0;
pub const CONS_MUTE: u16 = 0x00E2;
pub const CONS_VOL_UP: u16 = 0x00E9;
pub const CONS_VOL_DOWN: u16 = 0x00EA;
pub const CONS_PLAY_PAUSE: u16 = 0x00CD;

#[derive(Debug, Clone)]
pub struct MacroKey {
    pub label: &'static str,
    pub mod_mask: u8,
    pub key: u8,
    pub cons: u16,
    pub color: &'static str,
}

#[derive(Debug, Clone)]
pub struct AppProfile {
    pub name: &'static str,
    pub app: &'static str,
    pub bundle_ids: &'static [&'static str],
    pub color: &'static str,
    pub buttons: [MacroKey; 6],
}

pub static PROFILES: &[AppProfile] = &[
    AppProfile {
        name: "vscode",
        app: "VS Code",
        bundle_ids: &[
            "com.microsoft.VSCode",
            "com.vscodium",
            "com.microsoft.VSCodeInsiders",
            "com.visualstudio.code.oss",
        ],
        color: "0x007ACC",
        buttons: [
            MacroKey {
                label: "Pal",
                mod_mask: MOD_CMD | MOD_SHIFT,
                key: b'p',
                cons: 0,
                color: "0x007ACC",
            },
            MacroKey {
                label: "File",
                mod_mask: MOD_CMD,
                key: b'p',
                cons: 0,
                color: "0x007ACC",
            },
            MacroKey {
                label: "Term",
                mod_mask: MOD_CTRL,
                key: b'`',
                cons: 0,
                color: "0x30D158",
            },
            MacroKey {
                label: "Split",
                mod_mask: MOD_CMD,
                key: b'\\',
                cons: 0,
                color: "0x007ACC",
            },
            MacroKey {
                label: "Git",
                mod_mask: MOD_CTRL | MOD_SHIFT,
                key: b'g',
                cons: 0,
                color: "0xFF9F0A",
            },
            MacroKey {
                label: "Fmt",
                mod_mask: MOD_SHIFT | MOD_ALT,
                key: b'f',
                cons: 0,
                color: "0xBF5AF2",
            },
        ],
    },
    AppProfile {
        name: "chrome",
        app: "Chrome",
        bundle_ids: &[
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.brave.Browser",
            "com.apple.Safari",
            "company.thebrowser.Browser",
            "org.mozilla.firefox",
        ],
        color: "0x4285F4",
        buttons: [
            MacroKey {
                label: "DevTools",
                mod_mask: MOD_CMD | MOD_ALT,
                key: b'i',
                cons: 0,
                color: "0x4285F4",
            },
            MacroKey {
                label: "Reopen",
                mod_mask: MOD_CMD | MOD_SHIFT,
                key: b't',
                cons: 0,
                color: "0x34A853",
            },
            MacroKey {
                label: "New Tab",
                mod_mask: MOD_CMD,
                key: b't',
                cons: 0,
                color: "0x4285F4",
            },
            MacroKey {
                label: "Reload",
                mod_mask: MOD_CMD | MOD_SHIFT,
                key: b'r',
                cons: 0,
                color: "0xEA4335",
            },
            MacroKey {
                label: "Close",
                mod_mask: MOD_CMD,
                key: b'w',
                cons: 0,
                color: "0xFBBC05",
            },
            MacroKey {
                label: "Bookmark",
                mod_mask: MOD_CMD,
                key: b'd',
                cons: 0,
                color: "0x4285F4",
            },
        ],
    },
    AppProfile {
        name: "terminal",
        app: "Terminal",
        bundle_ids: &[
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "com.mitchellh.ghostty",
            "io.alacritty",
            "net.kovidgoyal.kitty",
        ],
        color: "0x30D158",
        buttons: [
            MacroKey {
                label: "Clear",
                mod_mask: MOD_CMD,
                key: b'k',
                cons: 0,
                color: "0x30D158",
            },
            MacroKey {
                label: "New Tab",
                mod_mask: MOD_CMD,
                key: b't',
                cons: 0,
                color: "0x30D158",
            },
            MacroKey {
                label: "Split",
                mod_mask: MOD_CMD,
                key: b'd',
                cons: 0,
                color: "0x0A84FF",
            },
            MacroKey {
                label: "Find",
                mod_mask: MOD_CMD,
                key: b'f',
                cons: 0,
                color: "0xFF9F0A",
            },
            MacroKey {
                label: "Cancel",
                mod_mask: MOD_CTRL,
                key: b'c',
                cons: 0,
                color: "0xFF453A",
            },
            MacroKey {
                label: "Close",
                mod_mask: MOD_CMD,
                key: b'w',
                cons: 0,
                color: "0x8E8E93",
            },
        ],
    },
    AppProfile {
        name: "slack",
        app: "Slack",
        bundle_ids: &["com.tinyspeck.slackmacgap"],
        color: "0x4A154B",
        buttons: [
            MacroKey {
                label: "Switch",
                mod_mask: MOD_CMD,
                key: b'k',
                cons: 0,
                color: "0x4A154B",
            },
            MacroKey {
                label: "Unread",
                mod_mask: MOD_CMD | MOD_SHIFT,
                key: b'a',
                cons: 0,
                color: "0x1264A3",
            },
            MacroKey {
                label: "DMs",
                mod_mask: MOD_CMD | MOD_SHIFT,
                key: b'k',
                cons: 0,
                color: "0x2BAC76",
            },
            MacroKey {
                label: "Search",
                mod_mask: MOD_CMD,
                key: b'g',
                cons: 0,
                color: "0xECB22E",
            },
            MacroKey {
                label: "Huddle",
                mod_mask: MOD_CMD | MOD_SHIFT,
                key: b' ',
                cons: 0,
                color: "0xE01E5A",
            },
            MacroKey {
                label: "Back",
                mod_mask: MOD_CMD,
                key: b'[',
                cons: 0,
                color: "0x4A154B",
            },
        ],
    },
    AppProfile {
        name: "default",
        app: "Default",
        bundle_ids: &["com.apple.finder", "default"],
        color: "0x0A84FF",
        buttons: [
            MacroKey {
                label: "Mission",
                mod_mask: MOD_CTRL,
                key: KEY_UP_ARROW,
                cons: 0,
                color: "0x0A84FF",
            },
            MacroKey {
                label: "Desktop",
                mod_mask: MOD_NONE,
                key: KEY_F11,
                cons: 0,
                color: "0x5E5CE6",
            },
            MacroKey {
                label: "Space L",
                mod_mask: MOD_CTRL,
                key: KEY_LEFT_ARROW,
                cons: 0,
                color: "0x30D158",
            },
            MacroKey {
                label: "Space R",
                mod_mask: MOD_CTRL,
                key: KEY_RIGHT_ARROW,
                cons: 0,
                color: "0x30D158",
            },
            MacroKey {
                label: "Mute",
                mod_mask: MOD_NONE,
                key: 0,
                cons: CONS_MUTE,
                color: "0xFF453A",
            },
            MacroKey {
                label: "Display Sleep",
                mod_mask: MOD_NONE,
                key: 0,
                cons: 0x30,
                color: "0x5E5CE6",
            },
        ],
    },
];

pub fn get_profile_for_app(app_name: &str) -> &'static AppProfile {
    get_profile_for_bundle_and_name("", app_name)
}

pub fn get_profile_for_bundle_and_name(bundle_id: &str, app_name: &str) -> &'static AppProfile {
    let bundle_lower = bundle_id.to_lowercase();
    let app_lower = app_name.to_lowercase();

    for profile in PROFILES {
        for bid in profile.bundle_ids {
            let bid_lower = bid.to_lowercase();
            if !bundle_lower.is_empty()
                && (bid_lower == bundle_lower
                    || bid_lower.contains(&bundle_lower)
                    || bundle_lower.contains(&bid_lower))
            {
                return profile;
            }
        }
    }

    if app_lower.contains("code") || app_lower.contains("codium") {
        return &PROFILES[0]; // vscode
    }
    if app_lower.contains("chrome")
        || app_lower.contains("safari")
        || app_lower.contains("brave")
        || app_lower.contains("firefox")
    {
        return &PROFILES[1]; // chrome
    }
    if app_lower.contains("terminal")
        || app_lower.contains("iterm")
        || app_lower.contains("warp")
        || app_lower.contains("ghostty")
    {
        return &PROFILES[2]; // terminal
    }
    if app_lower.contains("slack") {
        return &PROFILES[3]; // slack
    }

    &PROFILES[4] // default
}

pub fn get_frontmost_app() -> (String, String) {
    if let Ok(output) = Command::new("/usr/bin/lsappinfo").arg("front").output() {
        let asn = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !asn.is_empty() {
            if let Ok(info_output) = Command::new("/usr/bin/lsappinfo")
                .args(["info", "-app", &asn])
                .output()
            {
                let info = String::from_utf8_lossy(&info_output.stdout).to_string();
                let bundle_id = extract_quoted(&info, "bundleID=\"");
                let name = extract_first_quoted(&info);
                if !bundle_id.is_empty() {
                    return (bundle_id, name);
                }
            }
        }
    }

    ("com.apple.finder".into(), "Finder".into())
}

fn extract_quoted(text: &str, prefix: &str) -> String {
    if let Some(start) = text.find(prefix) {
        let rest = &text[start + prefix.len()..];
        if let Some(end) = rest.find('"') {
            return rest[..end].to_string();
        }
    }
    String::new()
}

fn extract_first_quoted(text: &str) -> String {
    if text.starts_with('"') {
        if let Some(end) = text[1..].find('"') {
            return text[1..1 + end].to_string();
        }
    }
    String::new()
}

pub fn build_app_payload(profile: &AppProfile) -> String {
    let buttons: Vec<String> = profile
        .buttons
        .iter()
        .map(|btn| {
            format!(
                r#"{{"label":"{}","mod":{},"key":{},"cons":{},"color":"{}"}}"#,
                btn.label, btn.mod_mask, btn.key, btn.cons, btn.color
            )
        })
        .collect();

    format!(
        r#"{{"type":"app","app":"{}","color":"{}","buttons":[{}]}}"#,
        profile.app,
        profile.color,
        buttons.join(",")
    )
}

#[derive(Debug, Clone)]
pub struct FrontmostAppDetector {
    pub debounce_s: f64,
    pub confirmed_bundle_id: Option<String>,
    pub confirmed_app_name: Option<String>,
    pub pending_bundle_id: Option<String>,
    pub pending_app_name: Option<String>,
    pub pending_since: f64,
}

impl Default for FrontmostAppDetector {
    fn default() -> Self {
        Self::new()
    }
}

impl FrontmostAppDetector {
    pub const DEBOUNCE_S: f64 = 0.25;

    pub fn new() -> Self {
        Self {
            debounce_s: Self::DEBOUNCE_S,
            confirmed_bundle_id: None,
            confirmed_app_name: None,
            pending_bundle_id: None,
            pending_app_name: None,
            pending_since: 0.0,
        }
    }

    pub fn observe(
        &mut self,
        candidate_bundle: &str,
        candidate_name: &str,
        now: f64,
        force_immediate: bool,
    ) -> Option<String> {
        if force_immediate || self.confirmed_bundle_id.is_none() {
            self.confirmed_bundle_id = Some(candidate_bundle.to_string());
            self.confirmed_app_name = Some(candidate_name.to_string());
            self.pending_bundle_id = None;
            self.pending_app_name = None;
            let profile = get_profile_for_bundle_and_name(candidate_bundle, candidate_name);
            return Some(build_app_payload(profile));
        }

        if self.confirmed_bundle_id.as_deref() == Some(candidate_bundle) {
            self.pending_bundle_id = None;
            self.pending_app_name = None;
            return None;
        }

        if self.pending_bundle_id.as_deref() != Some(candidate_bundle) {
            self.pending_bundle_id = Some(candidate_bundle.to_string());
            self.pending_app_name = Some(candidate_name.to_string());
            self.pending_since = now;
            return None;
        }

        if (now - self.pending_since) >= self.debounce_s {
            self.confirmed_bundle_id = Some(candidate_bundle.to_string());
            self.confirmed_app_name = Some(candidate_name.to_string());
            self.pending_bundle_id = None;
            self.pending_app_name = None;
            let profile = get_profile_for_bundle_and_name(candidate_bundle, candidate_name);
            return Some(build_app_payload(profile));
        }

        None
    }

    pub fn update(&mut self, force_immediate: bool) -> Option<String> {
        let (candidate_bundle, candidate_name) = get_frontmost_app();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();
        self.observe(&candidate_bundle, &candidate_name, now, force_immediate)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vscode_by_bundle() {
        let p = get_profile_for_bundle_and_name("com.microsoft.VSCode", "");
        assert_eq!(p.name, "vscode");
        assert_eq!(p.app, "VS Code");
    }

    #[test]
    fn test_chrome_by_bundle() {
        let p = get_profile_for_bundle_and_name("com.google.Chrome", "");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_terminal_by_bundle() {
        let p = get_profile_for_bundle_and_name("com.googlecode.iterm2", "");
        assert_eq!(p.name, "terminal");
    }

    #[test]
    fn test_slack_by_bundle() {
        let p = get_profile_for_bundle_and_name("com.tinyspeck.slackmacgap", "");
        assert_eq!(p.name, "slack");
    }

    #[test]
    fn test_default_fallback() {
        let p = get_profile_for_bundle_and_name("com.unknown.App", "SomeApp");
        assert_eq!(p.name, "default");
    }

    #[test]
    fn test_fuzzy_name_code() {
        let p = get_profile_for_app("Visual Studio Code");
        assert_eq!(p.name, "vscode");
    }

    #[test]
    fn test_fuzzy_name_chrome() {
        let p = get_profile_for_app("Google Chrome");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_fuzzy_name_safari() {
        let p = get_profile_for_app("Safari");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_fuzzy_name_brave() {
        let p = get_profile_for_app("Brave Browser");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_fuzzy_name_firefox() {
        let p = get_profile_for_app("Firefox");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_fuzzy_name_terminal() {
        let p = get_profile_for_app("Terminal");
        assert_eq!(p.name, "terminal");
    }

    #[test]
    fn test_fuzzy_name_iterm() {
        let p = get_profile_for_app("iTerm2");
        assert_eq!(p.name, "terminal");
    }

    #[test]
    fn test_fuzzy_name_warp() {
        let p = get_profile_for_app("Warp");
        assert_eq!(p.name, "terminal");
    }

    #[test]
    fn test_fuzzy_name_ghostty() {
        let p = get_profile_for_app("Ghostty");
        assert_eq!(p.name, "terminal");
    }

    #[test]
    fn test_fuzzy_name_slack() {
        let p = get_profile_for_app("Slack");
        assert_eq!(p.name, "slack");
    }

    #[test]
    fn test_empty_defaults() {
        let p = get_profile_for_bundle_and_name("", "");
        assert_eq!(p.name, "default");
    }

    #[test]
    fn test_all_profiles_have_6_buttons() {
        for profile in PROFILES {
            assert_eq!(
                profile.buttons.len(),
                6,
                "{} has != 6 buttons",
                profile.name
            );
        }
    }

    #[test]
    fn test_build_app_payload_structure() {
        let p = &PROFILES[0]; // vscode
        let json = build_app_payload(p);
        assert!(json.contains(r#""type":"app""#));
        assert!(json.contains(r#""app":"VS Code""#));
        assert!(json.contains(r#""color":"0x007ACC""#));
        assert!(json.contains(r#""buttons":["#));
        assert!(json.contains(r#""label":"Pal""#));
        assert!(json.contains(r#""label":"Fmt""#));
    }

    #[test]
    fn test_default_profile_mute_button() {
        let p = &PROFILES[4]; // default
        let mute_btn = &p.buttons[4];
        assert_eq!(mute_btn.label, "Mute");
        assert_eq!(mute_btn.cons, CONS_MUTE);
        assert_eq!(mute_btn.key, 0);
    }

    #[test]
    fn test_vscode_profile_keys() {
        let p = &PROFILES[0];
        assert_eq!(p.buttons[0].label, "Pal");
        assert_eq!(p.buttons[0].mod_mask, MOD_CMD | MOD_SHIFT);
        assert_eq!(p.buttons[0].key, b'p');
    }

    #[test]
    fn test_safari_bundle_maps_to_chrome() {
        let p = get_profile_for_bundle_and_name("com.apple.Safari", "");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_arc_bundle_maps_to_chrome() {
        let p = get_profile_for_bundle_and_name("company.thebrowser.Browser", "");
        assert_eq!(p.name, "chrome");
    }

    #[test]
    fn test_warp_bundle_maps_to_terminal() {
        let p = get_profile_for_bundle_and_name("dev.warp.Warp-Stable", "");
        assert_eq!(p.name, "terminal");
    }

    #[test]
    fn test_finder_bundle_maps_to_default() {
        let p = get_profile_for_bundle_and_name("com.apple.finder", "");
        assert_eq!(p.name, "default");
    }

    #[test]
    fn test_frontmost_app_detector_debounce_and_force() {
        let mut detector = FrontmostAppDetector::new();

        // First observation confirms immediately
        let first = detector.observe("com.microsoft.VSCode", "Code", 1.00, false);
        assert!(first.is_some());
        assert!(first.unwrap().contains(r#""app":"VS Code""#));
        assert_eq!(
            detector.confirmed_bundle_id.as_deref(),
            Some("com.microsoft.VSCode")
        );

        // Same app returns None
        assert!(detector
            .observe("com.microsoft.VSCode", "Code", 1.05, false)
            .is_none());

        // Transient bounce (< 250ms) does not emit
        assert!(detector
            .observe("com.google.Chrome", "Google Chrome", 1.10, false)
            .is_none());
        assert!(detector
            .observe("com.microsoft.VSCode", "Code", 1.20, false)
            .is_none());
        assert!(detector.pending_bundle_id.is_none());

        // Stable transition (>= 250ms) emits Chrome
        assert!(detector
            .observe("com.google.Chrome", "Google Chrome", 2.00, false)
            .is_none());
        assert!(detector
            .observe("com.google.Chrome", "Google Chrome", 2.15, false)
            .is_none());
        let confirmed = detector.observe("com.google.Chrome", "Google Chrome", 2.26, false);
        assert!(confirmed.is_some());
        assert!(confirmed.unwrap().contains(r#""app":"Chrome""#));

        // Force immediate emits right away
        let forced = detector.observe("com.tinyspeck.slackmacgap", "Slack", 2.30, true);
        assert!(forced.is_some());
        assert!(forced.unwrap().contains(r#""app":"Slack""#));
    }
}
