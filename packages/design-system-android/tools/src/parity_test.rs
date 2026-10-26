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

//! Verifies cross-platform icon, illustration, and composable parity between Web and Android.
//! Native Rust replacement for `packages/design-system-android/tools/parity_test.py`.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

pub const ANDROID_ROOT: &str =
    "packages/design-system-android/src/main/kotlin/dev/vitruvian/design";
pub const WEB_ICONS: &str = "packages/design-system/src/Icons.tsx";
pub const WEB_ILLUSTRATIONS: &str = "packages/design-system/src/Illustrations.tsx";

pub const EXPECTED_COMPOSABLES: &[&str] = &[
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
];

fn is_upper_alnum_underscore(b: u8) -> bool {
    b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_'
}

fn is_ident_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Matches `re.findall(r"^\s*([A-Z0-9_]+):\s*\[", web_text, re.MULTILINE)`.
pub fn extract_web_icon_names(web_text: &str) -> BTreeSet<String> {
    let bytes = web_text.as_bytes();
    let len = bytes.len();
    let mut names = BTreeSet::new();
    let mut i = 0;
    let mut at_line_start = true;

    while i < len {
        if at_line_start {
            while i < len && bytes[i].is_ascii_whitespace() {
                i += 1;
            }
            let start = i;
            while i < len && is_upper_alnum_underscore(bytes[i]) {
                i += 1;
            }
            if i > start && i < len && bytes[i] == b':' {
                let name = &web_text[start..i];
                i += 1; // consume ':'
                let after_colon = i;
                while i < len && bytes[i].is_ascii_whitespace() {
                    i += 1;
                }
                if i < len && bytes[i] == b'[' {
                    names.insert(name.to_string());
                    i += 1;
                    at_line_start = false;
                    continue;
                } else {
                    // Rewind to right after ':' so newlines in skipped whitespace can trigger line start
                    i = after_colon;
                }
            }
            at_line_start = false;
        } else {
            if bytes[i] == b'\n' {
                at_line_start = true;
            }
            i += 1;
        }
    }

    names
}

/// Matches `re.findall(r"public const val ([A-Z0-9_]+): String =", android_text)`.
pub fn extract_android_icon_names(android_text: &str) -> BTreeSet<String> {
    const PREFIX: &str = "public const val ";
    const SUFFIX: &str = ": String =";
    let mut names = BTreeSet::new();
    let mut rest = android_text;

    while let Some(pos) = rest.find(PREFIX) {
        let after = &rest[pos + PREFIX.len()..];
        let bytes = after.as_bytes();
        let mut end = 0;
        while end < bytes.len() && is_upper_alnum_underscore(bytes[end]) {
            end += 1;
        }
        if end > 0 && after[end..].starts_with(SUFFIX) {
            names.insert(after[..end].to_string());
            rest = &after[end + SUFFIX.len()..];
        } else {
            rest = after;
        }
    }

    names
}

/// Matches `re.findall(r'^\s*\|\s*"([a-z]+)"', web_text, re.MULTILINE)`.
pub fn extract_web_illustration_kinds(web_text: &str) -> Vec<String> {
    let bytes = web_text.as_bytes();
    let len = bytes.len();
    let mut kinds = Vec::new();
    let mut i = 0;
    let mut at_line_start = true;

    while i < len {
        if at_line_start {
            while i < len && bytes[i].is_ascii_whitespace() {
                i += 1;
            }
            if i < len && bytes[i] == b'|' {
                let after_bar = i + 1;
                i += 1;
                while i < len && bytes[i].is_ascii_whitespace() {
                    i += 1;
                }
                if i < len && bytes[i] == b'"' {
                    i += 1;
                    let start = i;
                    while i < len && bytes[i].is_ascii_lowercase() {
                        i += 1;
                    }
                    if i > start && i < len && bytes[i] == b'"' {
                        kinds.push(web_text[start..i].to_string());
                        i += 1;
                        at_line_start = false;
                        continue;
                    }
                }
                i = after_bar;
            }
            at_line_start = false;
        } else {
            if bytes[i] == b'\n' {
                at_line_start = true;
            }
            i += 1;
        }
    }

    kinds
}

/// Matches Python `str.capitalize()`: first character uppercased, remaining lowercased.
pub fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => {
            let mut out = String::with_capacity(s.len());
            for c in first.to_uppercase() {
                out.push(c);
            }
            for c in chars {
                for lc in c.to_lowercase() {
                    out.push(lc);
                }
            }
            out
        }
    }
}

/// Matches `re.findall(r"public fun ([A-Za-z0-9_]+)\s*\(", all_kt)`.
pub fn extract_defined_functions(all_kt: &str) -> BTreeSet<String> {
    const PREFIX: &str = "public fun ";
    let mut funcs = BTreeSet::new();
    let mut rest = all_kt;

    while let Some(pos) = rest.find(PREFIX) {
        let after = &rest[pos + PREFIX.len()..];
        let bytes = after.as_bytes();
        let mut end = 0;
        while end < bytes.len() && is_ident_char(bytes[end]) {
            end += 1;
        }
        if end > 0 {
            let mut ws_end = end;
            while ws_end < bytes.len() && bytes[ws_end].is_ascii_whitespace() {
                ws_end += 1;
            }
            if ws_end < bytes.len() && bytes[ws_end] == b'(' {
                funcs.insert(after[..end].to_string());
                rest = &after[ws_end + 1..];
                continue;
            }
        }
        rest = after;
    }

    funcs
}

pub fn resolve_workspace_root() -> Result<PathBuf, String> {
    let mut candidates = Vec::new();
    if let Ok(cwd) = std::env::current_dir() {
        candidates.push(cwd);
    }
    if let Ok(ws) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        candidates.push(PathBuf::from(ws));
    }
    if let Ok(rf) = std::env::var("RUNFILES_DIR") {
        let rf_path = PathBuf::from(&rf);
        candidates.push(rf_path.join("_main"));
        candidates.push(rf_path);
    }
    if let Ok(ts) = std::env::var("TEST_SRCDIR") {
        let ts_path = PathBuf::from(&ts);
        candidates.push(ts_path.join("_main"));
        candidates.push(ts_path);
    }

    for candidate in candidates {
        if candidate.join(WEB_ICONS).is_file() {
            return Ok(candidate);
        }
        for ancestor in candidate.ancestors().skip(1) {
            if ancestor.join(WEB_ICONS).is_file() {
                return Ok(ancestor.to_path_buf());
            }
        }
    }

    Err(format!(
        "could not locate workspace root containing {WEB_ICONS}"
    ))
}

pub fn check_icon_names_match_web_icons_tsx(root: &Path) -> Result<(), String> {
    let web_path = root.join(WEB_ICONS);
    let android_path = root.join(ANDROID_ROOT).join("Icons.kt");

    let web_text = fs::read_to_string(&web_path)
        .map_err(|e| format!("failed to read {}: {e}", web_path.display()))?;
    let android_text = fs::read_to_string(&android_path)
        .map_err(|e| format!("failed to read {}: {e}", android_path.display()))?;

    let web_icon_names = extract_web_icon_names(&web_text);
    let android_icon_names = extract_android_icon_names(&android_text);

    if web_icon_names.len() != 28 {
        return Err(format!(
            "expected 28 web icon names, found {} ({:?})",
            web_icon_names.len(),
            web_icon_names
        ));
    }
    if web_icon_names != android_icon_names {
        let missing_in_android: Vec<_> = web_icon_names.difference(&android_icon_names).collect();
        let extra_in_android: Vec<_> = android_icon_names.difference(&web_icon_names).collect();
        return Err(format!(
            "web_icon_names != android_icon_names (missing in Android: {:?}, extra in Android: {:?})",
            missing_in_android, extra_in_android
        ));
    }
    Ok(())
}

pub fn check_illustrations_match_web_plates(root: &Path) -> Result<(), String> {
    let web_path = root.join(WEB_ILLUSTRATIONS);
    let android_path = root.join(ANDROID_ROOT).join("Illustrations.kt");

    let web_text = fs::read_to_string(&web_path)
        .map_err(|e| format!("failed to read {}: {e}", web_path.display()))?;
    let android_text = fs::read_to_string(&android_path)
        .map_err(|e| format!("failed to read {}: {e}", android_path.display()))?;

    let web_kinds = extract_web_illustration_kinds(&web_text);
    if web_kinds.len() != 8 {
        return Err(format!(
            "expected 8 web illustration kinds, found {} ({:?})",
            web_kinds.len(),
            web_kinds
        ));
    }
    for kind_name in &web_kinds {
        let enum_name = capitalize(kind_name);
        let needle = format!("{enum_name}(");
        if !android_text.contains(&needle) {
            return Err(format!("expected '{needle}' in {}", android_path.display()));
        }
    }
    Ok(())
}

pub fn check_all_expected_composables_exist(root: &Path) -> Result<(), String> {
    let android_dir = root.join(ANDROID_ROOT);
    let entries = fs::read_dir(&android_dir)
        .map_err(|e| format!("failed to read directory {}: {e}", android_dir.display()))?;

    let mut kt_paths: Vec<PathBuf> = entries
        .filter_map(|e| e.ok().map(|entry| entry.path()))
        .filter(|p| p.extension().and_then(|ext| ext.to_str()) == Some("kt"))
        .collect();
    kt_paths.sort();

    let mut chunks = Vec::with_capacity(kt_paths.len());
    for path in &kt_paths {
        let content = fs::read_to_string(path)
            .map_err(|e| format!("failed to read {}: {e}", path.display()))?;
        chunks.push(content);
    }
    let all_kt = chunks.join("\n");
    let defined_functions = extract_defined_functions(&all_kt);

    for &name in EXPECTED_COMPOSABLES {
        if !defined_functions.contains(name) {
            return Err(format!(
                "Expected public fun {name} in packages/design-system-android"
            ));
        }
    }
    Ok(())
}

pub fn run_all_checks(root: &Path) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if let Err(e) = check_icon_names_match_web_icons_tsx(root) {
        errors.push(e);
    }
    if let Err(e) = check_illustrations_match_web_plates(root) {
        errors.push(e);
    }
    if let Err(e) = check_all_expected_composables_exist(root) {
        errors.push(e);
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

fn main() {
    let root = match resolve_workspace_root() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("error: {e}");
            std::process::exit(1);
        }
    };
    if let Err(errors) = run_all_checks(&root) {
        for err in &errors {
            eprintln!("FAIL: {err}");
        }
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_icon_names_match_web_icons_tsx() {
        let root = resolve_workspace_root().expect("resolve workspace root");
        check_icon_names_match_web_icons_tsx(&root).expect("icon names match web Icons.tsx");
    }

    #[test]
    fn test_illustrations_match_web_plates() {
        let root = resolve_workspace_root().expect("resolve workspace root");
        check_illustrations_match_web_plates(&root).expect("illustrations match web plates");
    }

    #[test]
    fn test_all_expected_composables_exist() {
        let root = resolve_workspace_root().expect("resolve workspace root");
        check_all_expected_composables_exist(&root).expect("all expected composables exist");
    }

    #[test]
    fn unit_extract_web_icon_names_handles_single_and_multiline_arrays() {
        let sample = r#"
export const VitruvianIcons = {
  /** Home */
  HOME: ["M3 10.5"],
  GRID_2X2: [
    "M3 3h18v18H3z",
  ],
  not_an_icon: ["ignored"],
  ALSO_IGNORED: "not an array",
};
"#;
        let names = extract_web_icon_names(sample);
        let expected: BTreeSet<String> =
            ["HOME", "GRID_2X2"].into_iter().map(String::from).collect();
        assert_eq!(names, expected);
    }

    #[test]
    fn unit_extract_android_icon_names_filters_only_public_const_val_string() {
        let sample = r#"
public object VitruvianIcons {
  public const val HOME: String = "M3 11"
  public const val GRID_2X2: String =
      "M3 3h7"
  private const val VIEWPORT = 24f
  public val ALL: Map<String, String> = mapOf()
}
"#;
        let names = extract_android_icon_names(sample);
        let expected: BTreeSet<String> =
            ["HOME", "GRID_2X2"].into_iter().map(String::from).collect();
        assert_eq!(names, expected);
    }

    #[test]
    fn unit_extract_web_illustration_kinds_and_capitalize() {
        let sample = r#"
export type VitruvianPlateVariant =
  | "proportion"
  | "spaces"
  | "InvalidUpper"
  | "harmonic";
"#;
        let kinds = extract_web_illustration_kinds(sample);
        assert_eq!(kinds, vec!["proportion", "spaces", "harmonic"]);
        assert_eq!(capitalize("proportion"), "Proportion");
        assert_eq!(capitalize(""), "");
        assert_eq!(capitalize("sPACES"), "Spaces");
    }

    #[test]
    fn unit_extract_defined_functions_handles_whitespace_before_paren() {
        let sample = r#"
@Composable
public fun Accordion(title: String) {}
public fun VButton (onClick: () -> Unit) {}
private fun HiddenHelper() {}
public val NotAFunction: Int = 1
"#;
        let funcs = extract_defined_functions(sample);
        let expected: BTreeSet<String> = ["Accordion", "VButton"]
            .into_iter()
            .map(String::from)
            .collect();
        assert_eq!(funcs, expected);
    }

    #[test]
    fn unit_detects_missing_composable_and_icon_mismatch() {
        let dir = std::env::temp_dir().join(format!("dsa_parity_unit_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let android_dir = dir.join(ANDROID_ROOT);
        let web_dir = dir.join("packages/design-system/src");
        fs::create_dir_all(&android_dir).unwrap();
        fs::create_dir_all(&web_dir).unwrap();

        fs::write(web_dir.join("Icons.tsx"), "  HOME: [\"M0 0\"],\n").unwrap();
        fs::write(
            android_dir.join("Icons.kt"),
            "public const val HOME: String = \"M0 0\"\n",
        )
        .unwrap();
        fs::write(web_dir.join("Illustrations.tsx"), "  | \"proportion\"\n").unwrap();
        fs::write(android_dir.join("Illustrations.kt"), "Proportion(\n").unwrap();

        let errs = run_all_checks(&dir).unwrap_err();
        assert_eq!(errs.len(), 3);
        assert!(errs[0].contains("expected 28 web icon names, found 1"));
        assert!(errs[1].contains("expected 8 web illustration kinds, found 1"));
        assert!(errs[2].contains("Expected public fun Accordion in packages/design-system-android"));

        let _ = fs::remove_dir_all(&dir);
    }
}
