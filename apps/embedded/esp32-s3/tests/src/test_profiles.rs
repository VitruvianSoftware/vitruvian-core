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
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Rust migration of `test_profiles.py`:
//! Context-Aware App Profiles, modifier bitmask orthogonality, 6-button schema conformance,
//! JSON wire protocol <1024B constraint, and frontmost app detector debounce.

use app_profiles::{
    build_app_payload, get_profile_for_app, CONS_MUTE, KEY_BACKSPACE, KEY_ESC, KEY_TAB, MOD_ALT,
    MOD_CMD, MOD_CTRL, MOD_NONE, MOD_SHIFT, PROFILES,
};

pub fn test_modifier_bitmask_orthogonality() {
    assert_eq!(MOD_NONE, 0);
    let mods = [MOD_CTRL, MOD_SHIFT, MOD_ALT, MOD_CMD];
    for m in mods {
        assert!(m > 0 && (m & (m - 1)) == 0);
    }
    for i in 0..mods.len() {
        for j in (i + 1)..mods.len() {
            assert_eq!(mods[i] & mods[j], 0);
        }
    }
    assert_eq!(MOD_CMD | MOD_SHIFT, 10);
    assert_eq!(MOD_CTRL | MOD_ALT, 5);
    assert_eq!(MOD_CMD | MOD_ALT, 12);
    assert_eq!(MOD_CMD | MOD_CTRL | MOD_SHIFT | MOD_ALT, 15);
}

pub fn test_profile_resolution_and_schema() {
    for name in ["Code", "Visual Studio Code", "VSCodium", "vscode"] {
        assert_eq!(get_profile_for_app(name).app, "VS Code");
    }
    for name in ["Google Chrome", "Safari", "Brave Browser", "Firefox"] {
        assert_eq!(get_profile_for_app(name).app, "Chrome");
    }
    for name in ["iTerm2", "Terminal", "Warp", "Ghostty"] {
        assert_eq!(get_profile_for_app(name).app, "Terminal");
    }
    assert_eq!(get_profile_for_app("Slack").app, "Slack");
    for name in ["Finder", "Spotify", "UnknownApp", ""] {
        assert_eq!(get_profile_for_app(name).app, "Default");
    }

    for profile in PROFILES {
        assert_eq!(profile.buttons.len(), 6);
        assert!(profile.color.starts_with("0x") || profile.color.starts_with('#'));
        for btn in &profile.buttons {
            assert!(!btn.label.is_empty() && btn.label.len() <= 16);
            assert!(btn.mod_mask <= 15);
            assert!(
                (btn.key > 0 && btn.cons == 0) || (btn.cons > 0 && btn.key == 0),
                "button {} must set either key or cons",
                btn.label
            );
        }
    }
}

pub fn test_wire_protocol_and_keycodes() {
    for app in ["VS Code", "Chrome", "Terminal", "Slack", "Finder"] {
        let p = get_profile_for_app(app);
        let line = format!("{}\n", build_app_payload(p));
        assert!(line.ends_with('\n'));
        assert!(line.len() < 1024);
        assert!(!line[..line.len() - 1].contains('\n'));
        assert!(line.contains("\"type\":\"app\""));
    }

    let vscode = get_profile_for_app("VS Code");
    let b_pal = vscode.buttons.iter().find(|b| b.label == "Pal").unwrap();
    assert_eq!(b_pal.mod_mask, MOD_CMD | MOD_SHIFT);
    assert_eq!(b_pal.key, b'p');

    let b_term = vscode.buttons.iter().find(|b| b.label == "Term").unwrap();
    assert_eq!(b_term.mod_mask, MOD_CTRL);
    assert_eq!(b_term.key, b'`');

    let term = get_profile_for_app("Terminal");
    let b_cancel = term.buttons.iter().find(|b| b.label == "Cancel").unwrap();
    assert_eq!(b_cancel.mod_mask, MOD_CTRL);
    assert_eq!(b_cancel.key, b'c');

    let def = get_profile_for_app("Default");
    let b_mute = def.buttons.iter().find(|b| b.label == "Mute").unwrap();
    assert_eq!(b_mute.cons, CONS_MUTE);
    assert_eq!(b_mute.key, 0);

    assert_ne!(KEY_TAB, KEY_ESC);
    assert_ne!(KEY_BACKSPACE, b'`');
}

pub fn test_frontmost_app_detector_debounce() {
    let sequence = ["Code", "Code", "Google Chrome", "Google Chrome", "iTerm2"];
    let mut last_profile: Option<&str> = None;
    let mut emitted = Vec::new();
    for raw in sequence {
        let p = get_profile_for_app(raw);
        if last_profile != Some(p.app) {
            last_profile = Some(p.app);
            emitted.push(p.app);
        }
    }
    assert_eq!(emitted, vec!["VS Code", "Chrome", "Terminal"]);
}

pub fn run_suite() -> usize {
    test_modifier_bitmask_orthogonality();
    test_profile_resolution_and_schema();
    test_wire_protocol_and_keycodes();
    test_frontmost_app_detector_debounce();
    4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profiles_suite() {
        assert_eq!(run_suite(), 4);
    }
}
