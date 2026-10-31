// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const APP_PREFIX: &str = "Sources/Vitruvian/";
pub const UI_PREFIX: &str = "Sources/Vitruvian/UI/";
pub const PREFERENCES_PATH: &str = "Sources/Vitruvian/Core/Preferences.swift";
pub const AGREEMENT_SHEET: &str = "Sources/Vitruvian/UI/Settings/ExternalToolAgreementSheet.swift";
pub const TOOLS_SECTION: &str = "Sources/Vitruvian/UI/Settings/ExternalToolsSection.swift";
pub const BROKER_PREFIX: &str = "Sources/Vitruvian/Services/Platform/Broker/";
pub const RUNTIME_PREFIX: &str = "Sources/Vitruvian/Services/Platform/External/";
pub const MODIFICATION_LOG_FLOOR: usize = 260;

/// The release tools' sources, scanned for relative paths that are a case
/// twin of something in the package (`build/` is the BUILD file).
pub const RELEASE_SOURCES: &[&str] = &[
    "bazel/src/publish/lib.rs",
    "bazel/src/beta_publish_guard/lib.rs",
    "bazel/src/package_release/lib.rs",
    "bazel/src/make_dmg/lib.rs",
    "bazel/src/dmg_image_devices/lib.rs",
    "bazel/src/notarize/lib.rs",
    "bazel/src/release_exec/lib.rs",
];

pub const SESSION_TAP_OWNERS: &[&str] = &[
    "Sources/Vitruvian/Services/ScrollInverter.swift",
    "Sources/Vitruvian/Services/SmoothScrollService.swift",
    "Sources/Vitruvian/Services/MouseNavigation/MouseNavigationService.swift",
    "Sources/Vitruvian/Services/MouseButtons/MouseButtonShortcutService.swift",
    "Sources/Vitruvian/Services/MiddleClick/MiddleClickService.swift",
    "Sources/Vitruvian/Services/QuitProtection/QuitProtectionService.swift",
    "Sources/Vitruvian/Services/RadialMenu/RadialMenuService.swift",
    "Sources/Vitruvian/Services/WindowLayout/WindowLayoutService.swift",
    "Sources/Vitruvian/Services/WindowMaximizer.swift",
    "Sources/Vitruvian/Services/Finder/FinderCutPaste.swift",
    "Sources/Vitruvian/Services/Finder/FinderRenameService.swift",
    "Sources/Vitruvian/Services/KeyboardDebounce/KeyboardDebounceService.swift",
    "Sources/Vitruvian/Services/SuperKey/SuperKeyService.swift",
    "Sources/Vitruvian/Services/ShortcutRecordingTap.swift",
    "Sources/Vitruvian/Services/Switcher/AppSwitcher.swift",
    "Sources/Vitruvian/Services/Snippets/TextSnippetService.swift",
    "Sources/Vitruvian/Services/Audio/PreciseVolumeRollerService.swift",
    "Sources/Vitruvian/Services/DockClick/DockClickService.swift",
    "Sources/Vitruvian/Services/Display/BrightnessService.swift",
];

pub const MODIFYING_TAP_OWNERS: &[&str] = &[
    "MouseNavigation",
    "MouseButtonShortcut",
    "MiddleClick",
    "QuitProtection",
    "RadialMenu",
    "ShortcutRecordingTap",
];

pub const POINTER_THREAD_TAP_OWNERS: &[&str] = &[
    "Sources/Vitruvian/Services/ScrollInverter.swift",
    "Sources/Vitruvian/Services/MiddleClick/MiddleClickService.swift",
];

pub const THREAD_SERVED_TAP_OWNERS: &[&str] = &[
    "FinderCutPaste",
    "FinderRename",
    "KeyboardDebounce",
    "AppSwitcher",
    "TextSnippet",
];

pub const UPSTREAM_SECTIONS: &[&str] = &[
    "## Licensing: this directory is GPL, not Apache",
    "## Trademarks and release blockers",
    "## What the import left out",
    "## Modifications",
    "## Tracking and porting upstream",
];

pub struct Repository {
    pub app_dir: PathBuf,
    pub swift_paths: Vec<String>,
    pub sources: BTreeMap<String, String>,
    pub lines: BTreeMap<String, Vec<String>>,
    pub test_paths: Vec<String>,
    pub tests: BTreeMap<String, String>,
    pub build_script: String,
    pub uninstall_script: String,
    pub upstream: String,
    pub root_names: Vec<String>,
}

impl Repository {
    pub fn new(app_dir: &Path) -> Self {
        let mut swift_paths = Vec::new();
        let mut sources = BTreeMap::new();
        let mut lines = BTreeMap::new();
        let sources_dir = app_dir.join("Sources");
        if sources_dir.is_dir() {
            let mut found = Vec::new();
            walk_ext(&sources_dir, app_dir, "swift", &mut found);
            found.sort();
            for rel in found {
                let text = fs::read_to_string(app_dir.join(&rel)).unwrap_or_default();
                let split_lines: Vec<String> = text.split('\n').map(|s| s.to_string()).collect();
                lines.insert(rel.clone(), split_lines);
                sources.insert(rel.clone(), text);
                swift_paths.push(rel);
            }
        }

        let mut test_paths = Vec::new();
        let mut tests = BTreeMap::new();
        let tests_dir = app_dir.join("Tests");
        if tests_dir.is_dir() {
            let mut found = Vec::new();
            walk_ext(&tests_dir, app_dir, "swift", &mut found);
            found.sort();
            for rel in found {
                let text = fs::read_to_string(app_dir.join(&rel)).unwrap_or_default();
                tests.insert(rel.clone(), text);
                test_paths.push(rel);
            }
        }

        let build_script = fs::read_to_string(app_dir.join("build.sh")).unwrap_or_default();
        let uninstall_script =
            fs::read_to_string(app_dir.join("Tools/uninstall.sh")).unwrap_or_default();
        let upstream = fs::read_to_string(app_dir.join("UPSTREAM.md")).unwrap_or_default();
        let mut root_names = Vec::new();
        if let Ok(entries) = fs::read_dir(app_dir) {
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    root_names.push(name.to_string());
                }
            }
        }
        root_names.sort();

        Self {
            app_dir: app_dir.to_path_buf(),
            swift_paths,
            sources,
            lines,
            test_paths,
            tests,
            build_script,
            uninstall_script,
            upstream,
            root_names,
        }
    }

    pub fn app_sources(&self) -> Vec<String> {
        self.swift_paths
            .iter()
            .filter(|p| p.starts_with(APP_PREFIX) && !p.contains(" 2"))
            .cloned()
            .collect()
    }

    pub fn source(&self, relative_path: &str) -> &str {
        self.sources
            .get(relative_path)
            .map(|s| s.as_str())
            .unwrap_or("")
    }

    pub fn lines_at(&self, relative_path: &str) -> Vec<String> {
        self.lines.get(relative_path).cloned().unwrap_or_default()
    }

    pub fn read_text(&self, relative_path: &str) -> String {
        fs::read_to_string(self.app_dir.join(relative_path)).unwrap_or_default()
    }
}

fn walk_ext(dir: &Path, root: &Path, ext: &str, out: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut paths: Vec<PathBuf> = entries.filter_map(|e| e.ok().map(|x| x.path())).collect();
    paths.sort();
    for p in paths {
        if p.is_dir() {
            walk_ext(&p, root, ext, out);
        } else if p.is_file() {
            let matches_ext = p.extension().and_then(|e| e.to_str()) == Some(ext);
            if matches_ext {
                if let Ok(rel) = p.strip_prefix(root) {
                    out.push(rel.to_string_lossy().replace('\\', "/"));
                }
            }
        }
    }
}

pub fn trim(text: &str) -> &str {
    text.trim_matches([' ', '\t', '\r', '\n'])
}

pub fn is_comment(line: &str) -> bool {
    let stripped = trim(line);
    stripped.starts_with("//") || stripped.starts_with("/*") || stripped.starts_with('*')
}

pub fn code_without_comments(lines: &[String]) -> String {
    lines
        .iter()
        .filter(|l| !is_comment(l))
        .cloned()
        .collect::<Vec<_>>()
        .join("\n")
}

pub fn first_block(code: &str) -> String {
    let mut block = String::new();
    let mut depth = 0i32;
    for ch in code.chars() {
        if ch == '{' {
            depth += 1;
        }
        if depth > 0 {
            block.push(ch);
        }
        if ch == '}' && depth > 0 {
            depth -= 1;
            if depth == 0 {
                break;
            }
        }
    }
    block
}

pub fn code_and_blanked(line: &str) -> (String, String) {
    let mut blanked = String::with_capacity(line.len());
    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '"' {
            let mut j = i + 1;
            let mut char_count = 0usize;
            let mut closed = false;
            while j < chars.len() {
                if chars[j] == '\\' && j + 1 < chars.len() {
                    char_count += 2;
                    j += 2;
                } else if chars[j] == '"' {
                    closed = true;
                    j += 1;
                    break;
                } else {
                    char_count += 1;
                    j += 1;
                }
            }
            if closed {
                blanked.push('"');
                for _ in 0..char_count {
                    blanked.push(' ');
                }
                blanked.push('"');
                i = j;
                continue;
            }
        }
        blanked.push(chars[i]);
        i += 1;
    }
    if let Some(end) = blanked.find("//") {
        // Slice both by char offset `end` (which matches byte offset up to `end` if ASCII, or let's slice by char count)
        let char_idx = blanked[..end].chars().count();
        let written_cut: String = line.chars().take(char_idx).collect();
        let blanked_cut: String = blanked.chars().take(char_idx).collect();
        (written_cut, blanked_cut)
    } else {
        (line.to_string(), blanked)
    }
}

// --- Rule Helpers tested directly in unit tests ---------------------------------

pub fn relative_path_roots(text: &str) -> Vec<String> {
    let mut results = Vec::new();
    for line in text.lines() {
        let bytes = line.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            let allowed_start = if i == 0 {
                true
            } else {
                let prev = bytes[i - 1];
                matches!(prev, b' ' | b'\t' | b'"' | b'\'' | b'=' | b'(' | b':')
                    || (i >= 2 && &bytes[i - 2..i] == b"./")
                    || (i >= 7 && &bytes[i - 7..i] == b"${PKG}/")
            };
            if allowed_start
                && (bytes[i].is_ascii_alphabetic() || bytes[i].is_ascii_digit() || bytes[i] == b'_')
            {
                let mut j = i + 1;
                while j < bytes.len()
                    && (bytes[j].is_ascii_alphanumeric() || matches!(bytes[j], b'_' | b'.' | b'-'))
                {
                    j += 1;
                }
                if j < bytes.len() && bytes[j] == b'/' {
                    results.push(line[i..j].to_string());
                    i = j + 1;
                    continue;
                }
            }
            i += 1;
        }
    }
    results
}

pub fn modification_log_problems(text: &str, floor: usize) -> Vec<String> {
    let mut problems = Vec::new();
    let mut at: isize = -1;
    for section in UPSTREAM_SECTIONS {
        let needle = format!("\n{}\n", section);
        let search_from = (at + 1).max(0) as usize;
        if let Some(pos) = text.get(search_from..).and_then(|s| s.find(&needle)) {
            at = (search_from + pos) as isize;
        } else {
            problems.push(format!("section missing or out of order: {}", section));
        }
    }
    let log = if let Some((_, after)) = text.split_once("\n## Modifications\n") {
        after.split("\n## ").next().unwrap_or(after)
    } else {
        ""
    };
    let entries = log
        .lines()
        .filter(|line| is_modification_entry_line(line))
        .count();
    if entries < floor {
        problems.push(format!(
            "the Modifications log has {} dated entries, fewer than {}",
            entries, floor
        ));
    }
    if text.lines().any(is_conflict_marker_line) {
        problems.push("a merge conflict marker is left in the file".into());
    }
    problems
}

fn is_modification_entry_line(line: &str) -> bool {
    let Some(rest) = line.strip_prefix("- **") else {
        return false;
    };
    let bytes = rest.as_bytes();
    bytes.len() >= 12
        && bytes[0..4].iter().all(|b| b.is_ascii_digit())
        && bytes[4] == b'-'
        && bytes[5..7].iter().all(|b| b.is_ascii_digit())
        && bytes[7] == b'-'
        && bytes[8..10].iter().all(|b| b.is_ascii_digit())
        && &bytes[10..12] == b"**"
}

fn is_conflict_marker_line(line: &str) -> bool {
    line.starts_with("<<<<<<< ") || line == "=======" || line.starts_with(">>>>>>> ")
}

pub fn agreement_focus_problems(text: &str) -> Vec<String> {
    let code: String = text
        .split('\n')
        .map(|l| code_and_blanked(l).1)
        .collect::<Vec<_>>()
        .join("\n");
    let mut problems = Vec::new();
    if !has_focus_bound(&code) {
        problems.push(
            "its buttons are not bound to its focus (`.focused($focus, equals: choice)`)".into(),
        );
    }
    if !has_focus_placed(&code, "content.initialFocus") {
        problems.push(
            "its focus is not set from what its content says (`focus = content.initialFocus`)"
                .into(),
        );
    }
    problems
}

pub fn detail_focus_problems(text: &str) -> Vec<String> {
    let code: String = text
        .split('\n')
        .map(|l| code_and_blanked(l).1)
        .collect::<Vec<_>>()
        .join("\n");
    let mut problems = Vec::new();
    if count_detail_setting_bound(&code) < 2 {
        problems.push(
            "a setting's switch and its field are not both bound to the detail's focus (`.focused($focus, equals: .setting(setting.id))`)"
                .into(),
        );
    }
    if !has_detail_close_bound(&code) {
        problems
            .push("Close is not bound to its focus (`.focused($focus, equals: .close)`)".into());
    }
    if !has_focus_placed(&code, "detail.initialFocus") {
        problems.push(
            "its focus is not set from what the detail says (`focus = detail.initialFocus`)".into(),
        );
    }
    problems
}

fn has_focus_bound(code: &str) -> bool {
    let mut rest = code;
    while let Some(idx) = rest.find(".focused($focus,") {
        let after = rest[idx + ".focused($focus,".len()..].trim_start();
        if after.starts_with("equals: choice)") || after.starts_with("equals:choice)") {
            return true;
        }
        rest = &rest[idx + ".focused($focus,".len()..];
    }
    false
}

fn has_detail_close_bound(code: &str) -> bool {
    let mut rest = code;
    while let Some(idx) = rest.find(".focused($focus,") {
        let after = rest[idx + ".focused($focus,".len()..].trim_start();
        if after.starts_with("equals: .close)") || after.starts_with("equals:.close)") {
            return true;
        }
        rest = &rest[idx + ".focused($focus,".len()..];
    }
    false
}

fn count_detail_setting_bound(code: &str) -> usize {
    let mut count = 0;
    let mut rest = code;
    while let Some(idx) = rest.find(".focused($focus,") {
        let after = rest[idx + ".focused($focus,".len()..].trim_start();
        if after.starts_with("equals: .setting(setting.id))")
            || after.starts_with("equals:.setting(setting.id))")
        {
            count += 1;
        }
        rest = &rest[idx + ".focused($focus,".len()..];
    }
    count
}

fn has_focus_placed(code: &str, target_expr: &str) -> bool {
    let mut start = 0;
    while let Some(idx) = code[start..].find("focus") {
        let abs = start + idx;
        let before_ok = abs == 0
            || !code.as_bytes()[abs - 1].is_ascii_alphanumeric()
                && code.as_bytes()[abs - 1] != b'_'
                && code.as_bytes()[abs - 1] != b'$';
        let after = abs + "focus".len();
        if before_ok {
            let after_ws = code[after..].trim_start();
            if let Some(after_eq) = after_ws.strip_prefix('=') {
                if !after_eq.starts_with('=') {
                    let rhs = after_eq.trim_start();
                    if let Some(tail) = rhs.strip_prefix(target_expr) {
                        let boundary = tail
                            .chars()
                            .next()
                            .map(|c| !c.is_ascii_alphanumeric() && c != '_')
                            .unwrap_or(true);
                        if boundary {
                            return true;
                        }
                    }
                }
            }
        }
        start = after;
    }
    false
}

pub fn consents_made(path: &str, text: &str) -> Vec<String> {
    let mut found = Vec::new();
    for (idx, line) in text.split('\n').enumerate() {
        let (_, code) = code_and_blanked(line);
        let mut start = 0;
        while let Some(pos) = code[start..].find("ToolConsent(") {
            let abs = start + pos;
            let before_ok = abs == 0
                || !code.as_bytes()[abs - 1].is_ascii_alphanumeric()
                    && code.as_bytes()[abs - 1] != b'_';
            if before_ok {
                found.push(format!("{}:{}", path, idx + 1));
                break;
            }
            start = abs + "ToolConsent(".len();
        }
    }
    found
}

pub fn catalog_rehearsals(path: &str, text: &str) -> Vec<String> {
    let mut found = Vec::new();
    let mut inside = false;
    let main_path = format!("{}main.swift", APP_PREFIX);
    for (idx, line) in text.split('\n').enumerate() {
        let stripped = line.trim();
        if stripped.starts_with("#if") {
            inside = stripped == "#if VITRUVIAN_SAMPLE_TOOL";
        } else if stripped.starts_with("#endif") {
            inside = false;
        }
        let (_, code) = code_and_blanked(line);
        if is_catalog_rehearsal_code(&code) && !(inside && path == main_path) {
            found.push(format!("{}:{}", path, idx + 1));
        }
    }
    found
}

fn is_catalog_rehearsal_code(code: &str) -> bool {
    let mut start = 0;
    while let Some(pos) = code[start..].find("CatalogueSource.") {
        let abs = start + pos;
        let before_ok = abs == 0
            || !code.as_bytes()[abs - 1].is_ascii_alphanumeric()
                && code.as_bytes()[abs - 1] != b'_';
        let after = &code[abs + "CatalogueSource.".len()..];
        if before_ok {
            if after.starts_with("rehearsal(") {
                return true;
            }
            if let Some(after_inuse) = after.strip_prefix("inUse") {
                let ws = after_inuse.trim_start();
                if let Some(after_eq) = ws.strip_prefix('=') {
                    if !after_eq.starts_with('=') {
                        return true;
                    }
                }
            }
        }
        start = abs + "CatalogueSource.".len();
    }
    false
}

pub fn adds_that_wait(text: &str) -> (usize, usize) {
    let code: String = text
        .split('\n')
        .map(|l| code_and_blanked(l).1)
        .collect::<Vec<_>>()
        .join("\n");
    let mut adds = 0;
    let mut told = 0;
    let mut start = 0;
    while let Some(pos) = code[start..].find("store.add(") {
        let abs = start + pos;
        let before_ok = abs == 0
            || !code.as_bytes()[abs - 1].is_ascii_alphanumeric()
                && code.as_bytes()[abs - 1] != b'_';
        let after = &code[abs + "store.add(".len()..];
        if before_ok {
            adds += 1;
            let ident: String = after
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect();
            if !ident.is_empty() {
                let after_ident = &after[ident.len()..];
                if let Some(after_paren) = after_ident.strip_prefix(')') {
                    let ws1 = after_paren.trim_start();
                    if let Some(after_brace) = ws1.strip_prefix('{') {
                        let ws2 = after_brace.trim_start();
                        let param: String = ws2
                            .chars()
                            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                            .collect();
                        if !param.is_empty() {
                            let ws3 = &ws2[param.len()..];
                            if ws3.starts_with(' ') || ws3.starts_with('\t') {
                                let after_param_ws = ws3.trim_start();
                                if let Some(after_in) = after_param_ws.strip_prefix("in") {
                                    let boundary = after_in
                                        .chars()
                                        .next()
                                        .map(|c| !c.is_ascii_alphanumeric() && c != '_')
                                        .unwrap_or(true);
                                    if boundary {
                                        told += 1;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        start = abs + "store.add(".len();
    }
    (adds, told)
}

// --- The 56 Rules in exact RULES order ------------------------------------------

type RuleFn = fn(&Repository) -> Vec<String>;

pub const RULES: &[(&str, RuleFn)] = &[
    ("swift_sources_read_back", swift_sources_read_back),
    ("views_read_files_once", views_read_files_once),
    (
        "borderless_menus_keep_their_size",
        borderless_menus_keep_their_size,
    ),
    (
        "operation_waits_have_deadlines",
        operation_waits_have_deadlines,
    ),
    (
        "application_elements_are_not_asked_their_role",
        application_elements_are_not_asked_their_role,
    ),
    (
        "parent_walks_stop_at_the_application",
        parent_walks_stop_at_the_application,
    ),
    (
        "availability_is_written_where_the_gate_runs",
        availability_is_written_where_the_gate_runs,
    ),
    (
        "shelf_store_is_read_through_its_loader",
        shelf_store_is_read_through_its_loader,
    ),
    (
        "activation_is_yielded_through_the_handoff",
        activation_is_yielded_through_the_handoff,
    ),
    (
        "tap_owners_invalidate_their_ports",
        tap_owners_invalidate_their_ports,
    ),
    (
        "app_rows_hide_whatever_hide_returns",
        app_rows_hide_whatever_hide_returns,
    ),
    ("keychain_is_never_touched", keychain_is_never_touched),
    ("url_schemes_have_a_handler", url_schemes_have_a_handler),
    (
        "the_app_never_asks_the_github_api",
        the_app_never_asks_the_github_api,
    ),
    (
        "visible_text_curls_its_apostrophes",
        visible_text_curls_its_apostrophes,
    ),
    (
        "french_punctuation_stays_on_its_line",
        french_punctuation_stays_on_its_line,
    ),
    ("decimals_name_their_region", decimals_name_their_region),
    (
        "every_language_fills_a_format_the_same_way",
        every_language_fills_a_format_the_same_way,
    ),
    (
        "every_symbol_the_app_draws_exists",
        every_symbol_the_app_draws_exists,
    ),
    (
        "every_system_tool_is_where_it_is_expected",
        every_system_tool_is_where_it_is_expected,
    ),
    (
        "every_named_resource_is_shipped",
        every_named_resource_is_shipped,
    ),
    (
        "embedded_scripts_close_what_they_open",
        embedded_scripts_close_what_they_open,
    ),
    (
        "stores_delete_only_what_they_own",
        stores_delete_only_what_they_own,
    ),
    (
        "tap_owners_follow_the_session",
        tap_owners_follow_the_session,
    ),
    (
        "pointer_taps_run_off_the_main_thread",
        pointer_taps_run_off_the_main_thread,
    ),
    (
        "inverter_does_not_yield_to_the_switcher",
        inverter_does_not_yield_to_the_switcher,
    ),
    (
        "cleaning_mode_never_synthesizes_mouse_events",
        cleaning_mode_never_synthesizes_mouse_events,
    ),
    (
        "brightness_work_queue_never_touches_nsscreen",
        brightness_work_queue_never_touches_nsscreen,
    ),
    (
        "click_debounce_schedules_nothing",
        click_debounce_schedules_nothing,
    ),
    (
        "smooth_scroll_disabled_tap_rearms_only_when_wanted",
        smooth_scroll_disabled_tap_rearms_only_when_wanted,
    ),
    (
        "menu_panel_switches_have_names",
        menu_panel_switches_have_names,
    ),
    (
        "tool_screen_controls_have_names",
        tool_screen_controls_have_names,
    ),
    (
        "path_identity_rule_is_spelled_once",
        path_identity_rule_is_spelled_once,
    ),
    ("build_sweeps_its_temp_dirs", build_sweeps_its_temp_dirs),
    (
        "build_signs_with_a_stable_identity",
        build_signs_with_a_stable_identity,
    ),
    (
        "release_scripts_have_no_case_twins",
        release_scripts_have_no_case_twins,
    ),
    (
        "about_box_credits_both_authors",
        about_box_credits_both_authors,
    ),
    (
        "test_types_do_not_shadow_real_ones",
        test_types_do_not_shadow_real_ones,
    ),
    (
        "test_groups_list_what_they_run",
        test_groups_list_what_they_run,
    ),
    (
        "names_use_the_apps_identifier",
        names_use_the_apps_identifier,
    ),
    (
        "unit_tests_read_no_source_text",
        unit_tests_read_no_source_text,
    ),
    (
        "preferences_are_reached_through_their_type",
        preferences_are_reached_through_their_type,
    ),
    (
        "package_signatures_name_no_internal_type",
        package_signatures_name_no_internal_type,
    ),
    (
        "modules_import_what_they_name",
        modules_import_what_they_name,
    ),
    (
        "package_types_built_elsewhere_have_package_inits",
        package_types_built_elsewhere_have_package_inits,
    ),
    (
        "package_views_publish_their_body",
        package_views_publish_their_body,
    ),
    (
        "later_layers_reach_only_package_statics",
        later_layers_reach_only_package_statics,
    ),
    ("hotkey_ids_are_unique", hotkey_ids_are_unique),
    (
        "migrated_tools_reach_services_through_the_broker",
        migrated_tools_reach_services_through_the_broker,
    ),
    ("the_broker_names_no_tool", the_broker_names_no_tool),
    (
        "only_the_agreement_sheet_consents",
        only_the_agreement_sheet_consents,
    ),
    (
        "the_tools_card_never_waits_to_add",
        the_tools_card_never_waits_to_add,
    ),
    (
        "only_a_by_hand_build_rehearses_the_catalog",
        only_a_by_hand_build_rehearses_the_catalog,
    ),
    (
        "the_agreement_sheet_places_its_focus",
        the_agreement_sheet_places_its_focus,
    ),
    (
        "a_tools_detail_places_its_focus",
        a_tools_detail_places_its_focus,
    ),
    ("modification_log_is_whole", modification_log_is_whole),
];

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

fn dirname(path: &str) -> &str {
    match path.rsplit_once('/') {
        Some((dir, _)) => dir,
        None => "",
    }
}

fn literal_after(piece: &str) -> Option<&str> {
    let end = piece.find('"')?;
    Some(&piece[..end])
}

fn swift_sources_read_back(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    if repo.swift_paths.is_empty() {
        problems.push("the Swift source corpus contains files".into());
    }
    let empty: Vec<String> = repo
        .sources
        .iter()
        .filter(|(_, text)| text.trim().is_empty())
        .map(|(path, _)| path.clone())
        .collect();
    if !empty.is_empty() {
        problems.push(format!("no Swift source is empty: {:?}", empty));
    }
    problems
}

fn views_read_files_once(repo: &Repository) -> Vec<String> {
    let mut found = Vec::new();
    for path in &repo.swift_paths {
        if !path.starts_with(UI_PREFIX) {
            continue;
        }
        let lines = repo.lines_at(path);
        for (index, line) in lines.iter().enumerate() {
            if !line.contains("NSImage(contentsOfFile:") && !line.contains("Data(contentsOf:") {
                continue;
            }
            let start = index.saturating_sub(6);
            let end = (index + 2).min(lines.len().saturating_sub(1));
            let around = &lines[start..=end];
            if !around
                .iter()
                .any(|x| x.contains(".task(") || x.contains("func ") || x.contains("Task {"))
            {
                found.push(format!("{}:{}", path, index + 1));
            }
        }
    }
    if !found.is_empty() {
        vec![format!(
            "a view reads a file once, never while drawing ({})",
            found.join(", ")
        )]
    } else {
        Vec::new()
    }
}

fn borderless_menus_keep_their_size(repo: &Repository) -> Vec<String> {
    let exception = "KillProcess/KillProcessView";
    let ui_files: Vec<&String> = repo
        .swift_paths
        .iter()
        .filter(|p| p.starts_with(UI_PREFIX) && !p.contains(" 2"))
        .collect();
    let mut unpinned = Vec::new();
    for path in &ui_files {
        if path.contains(exception) {
            continue;
        }
        let file = &path[UI_PREFIX.len()..];
        let lines = repo.lines_at(path);
        for (index, line) in lines.iter().enumerate() {
            if !line.contains(".menuStyle(.borderlessButton)") {
                continue;
            }
            let mut pinned = false;
            for next_line in &lines[index + 1..] {
                let text = trim(next_line);
                if !(text.starts_with('.') || text.starts_with("//")) {
                    break;
                }
                if text.starts_with(".fixedSize()") {
                    pinned = true;
                    break;
                }
            }
            if !pinned {
                unpinned.push(format!("{}:{}", file, index + 1));
            }
        }
    }
    if ui_files.is_empty() || !unpinned.is_empty() {
        vec![format!(
            "every borderless menu keeps its own size, across {} scanned files: {:?}",
            ui_files.len(),
            unpinned
        )]
    } else {
        Vec::new()
    }
}

fn operation_waits_have_deadlines(repo: &Repository) -> Vec<String> {
    let sources = repo.app_sources();
    let mut found = Vec::new();
    for path in &sources {
        for (index, line) in repo.lines_at(path).iter().enumerate() {
            if line.contains("waitUntilAllOperationsAreFinished") {
                found.push(format!("{}:{}", &path[APP_PREFIX.len()..], index + 1));
            }
        }
    }
    if sources.is_empty() || !found.is_empty() {
        vec![format!(
            "no operation queue is waited on without a deadline: {:?}",
            found
        )]
    } else {
        Vec::new()
    }
}

fn application_elements_are_not_asked_their_role(repo: &Repository) -> Vec<String> {
    let sources = repo.app_sources();
    let mut found = Vec::new();
    for path in &sources {
        let lines = repo.lines_at(path);
        let mut elements = BTreeSet::new();
        for line in &lines {
            if !line.contains("AXUIElementCreateApplication(") {
                continue;
            }
            let head = trim(line.split('=').next().unwrap_or(""));
            let assigned: Vec<&str> = head.split(' ').collect();
            if assigned.len() == 2 && (assigned[0] == "let" || assigned[0] == "var") {
                elements.insert(assigned[1].to_string());
            }
        }
        for (index, line) in lines.iter().enumerate() {
            if line.contains("kAXRoleAttribute")
                && !is_comment(line)
                && elements
                    .iter()
                    .any(|el| line.contains(&format!("({}, ", el)))
            {
                found.push(format!("{}:{}", &path[APP_PREFIX.len()..], index + 1));
            }
        }
    }
    if sources.is_empty() || !found.is_empty() {
        vec![format!(
            "no application element is ever asked for its role: {:?}",
            found
        )]
    } else {
        Vec::new()
    }
}

fn parent_walks_stop_at_the_application(repo: &Repository) -> Vec<String> {
    let sources = repo.app_sources();
    let mut found = Vec::new();
    for path in &sources {
        let lines = repo.lines_at(path);
        for (index, line) in lines.iter().enumerate() {
            if !line.contains("role(of: parent)") || is_comment(line) {
                continue;
            }
            let start = index.saturating_sub(3);
            let guarded = lines[start..index]
                .iter()
                .any(|x| x.contains("isApplicationElement(parent)") && !is_comment(x));
            if !guarded {
                found.push(format!("{}:{}", &path[APP_PREFIX.len()..], index + 1));
            }
        }
    }
    if sources.is_empty() || !found.is_empty() {
        vec![format!(
            "a walk up the parent chain stops at the application element: {:?}",
            found
        )]
    } else {
        Vec::new()
    }
}

fn availability_is_written_where_the_gate_runs(repo: &Repository) -> Vec<String> {
    let mut writers = BTreeSet::new();
    for path in &repo.swift_paths {
        if repo
            .lines_at(path)
            .iter()
            .any(|x| x.contains(".set(") && x.contains("availabilityKey"))
        {
            writers.insert(basename(path).to_string());
        }
    }
    let writers_vec: Vec<String> = writers.into_iter().collect();
    let expected = vec![
        "Defaults.swift".to_string(),
        "FeaturePresets.swift".to_string(),
        "FeatureRuntime.swift".to_string(),
    ];
    if writers_vec != expected {
        vec![format!(
            "feature availability is written only where the hardware gate runs, found {:?}",
            writers_vec
        )]
    } else {
        Vec::new()
    }
}

fn shelf_store_is_read_through_its_loader(repo: &Repository) -> Vec<String> {
    let mut found: Vec<String> = repo
        .swift_paths
        .iter()
        .filter(|path| repo.source(path).contains("decode([ShelfPersistedItem]"))
        .map(|path| basename(path).to_string())
        .collect();
    found.sort();
    if repo.swift_paths.is_empty() || !found.is_empty() {
        vec![format!(
            "the saved shelf is read only through ShelfPersistenceSupport.load, found a bare decode in {:?} across {} scanned files",
            found,
            repo.swift_paths.len()
        )]
    } else {
        Vec::new()
    }
}

fn activation_is_yielded_through_the_handoff(repo: &Repository) -> Vec<String> {
    let mut found: Vec<String> = repo
        .swift_paths
        .iter()
        .filter(|path| {
            basename(path) != "ActivationHandoff.swift"
                && repo.source(path).contains("yieldActivation")
        })
        .map(|path| basename(path).to_string())
        .collect();
    found.sort();
    if repo.swift_paths.is_empty() || !found.is_empty() {
        vec![format!(
            "activation is yielded only through ActivationHandoff, found a bare yield in {:?} across {} scanned files",
            found,
            repo.swift_paths.len()
        )]
    } else {
        Vec::new()
    }
}

fn tap_owners_invalidate_their_ports(repo: &Repository) -> Vec<String> {
    let mut owners = 0usize;
    let mut found = Vec::new();
    for path in repo.app_sources() {
        let code = code_without_comments(&repo.lines_at(&path));
        let taps = code.matches("CGEvent.tapCreate").count();
        if taps == 0 {
            continue;
        }
        owners += 1;
        let invalidations = code.matches("CFMachPortInvalidate").count()
            + code.matches("PointerTapRunLoop.remove(").count();
        if invalidations < taps {
            found.push(format!(
                "{} ({} taps, {} invalidated)",
                &path[APP_PREFIX.len()..],
                taps,
                invalidations
            ));
        }
    }
    if owners == 0 || !found.is_empty() {
        vec![format!(
            "every event tap owner invalidates its port on teardown, across {} scanned owners: {:?}",
            owners, found
        )]
    } else {
        Vec::new()
    }
}

fn app_rows_hide_whatever_hide_returns(repo: &Repository) -> Vec<String> {
    let code = code_without_comments(
        &repo.lines_at("Sources/Vitruvian/Services/CommandBar/CommandBarService.swift"),
    );
    if !code.contains("running.hide()") {
        return vec!["the Command Bar's app rows hide the app in front of them".into()];
    }
    if code.contains("running.hide() {") || code.contains("if running.hide()") {
        return vec!["an app row keeps its app hidden whatever hide() returns".into()];
    }
    Vec::new()
}

fn keychain_is_never_touched(repo: &Repository) -> Vec<String> {
    let mut found = Vec::new();
    for path in &repo.swift_paths {
        if !path.starts_with("Sources/") {
            continue;
        }
        let command_bar = path.starts_with("Sources/Vitruvian/Core/CommandBar/")
            || path.starts_with("Sources/Vitruvian/Services/CommandBar/");
        let needles: &[&str] = if command_bar {
            &["SecItem", "import Security"]
        } else {
            &["SecItem"]
        };
        for needle in needles {
            if repo.source(path).contains(needle) {
                found.push(format!("{}: {}", basename(path), needle));
            }
        }
    }
    for path in &repo.swift_paths {
        if repo.source(path).contains("removeInstallationKey") {
            found.push(format!("{}: removeInstallationKey", basename(path)));
        }
    }
    if repo.uninstall_script.is_empty() {
        found.push("Tools/uninstall.sh is unreadable".into());
    } else if repo.uninstall_script.contains("delete-generic-password") {
        found.push("Tools/uninstall.sh: delete-generic-password".into());
    }
    if !found.is_empty() {
        vec![format!(
            "the app, query learning and uninstall never access Keychain: {:?}",
            found
        )]
    } else {
        Vec::new()
    }
}

fn url_schemes_have_a_handler(repo: &Repository) -> Vec<String> {
    let text = repo.read_text("Resources/Info.plist");
    if text.is_empty() {
        return vec!["Resources/Info.plist is missing".into()];
    }
    if text.contains("<key>CFBundleURLTypes</key>") {
        let any_handler = repo.app_sources().iter().any(|source| {
            let code = code_without_comments(&repo.lines_at(source));
            code.contains("kAEGetURL") || code.contains(".onOpenURL") || code.contains("open urls:")
        });
        if !any_handler {
            return vec![
                "Info.plist registers URL schemes, but no app source handles a URL event".into(),
            ];
        }
    }
    Vec::new()
}

fn the_app_never_asks_the_github_api(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    for path in repo.app_sources() {
        if code_without_comments(&repo.lines_at(&path)).contains("api.github.com") {
            problems.push(format!(
                "{} asks api.github.com; use git or a release download link (VitruvianReleases)",
                path
            ));
        }
    }
    problems
}

fn visible_text_curls_its_apostrophes(repo: &Repository) -> Vec<String> {
    let paths: Vec<&String> = repo
        .swift_paths
        .iter()
        .filter(|path| {
            let d = dirname(path);
            let b = basename(path);
            (d == "Sources/Vitruvian/Core" || d == "Sources/Vitruvian/Core/Localizations")
                && (b.ends_with("Strings.swift")
                    || b.starts_with("Strings+")
                    || b == "Localization.swift")
        })
        .collect();
    let mut found = Vec::new();
    for path in paths {
        for (index, line) in repo.lines_at(path).iter().enumerate() {
            if is_comment(line) {
                continue;
            }
            let (Some(opening), Some(closing)) = (line.find('"'), line.rfind('"')) else {
                continue;
            };
            if opening >= closing {
                continue;
            }
            if line[opening..closing].contains('\'') {
                found.push(format!("{}:{}", path, index + 1));
            }
        }
    }
    if !found.is_empty() {
        let head: Vec<String> = found.into_iter().take(6).collect();
        vec![format!(
            "visible text curls its apostrophes ({})",
            head.join(", ")
        )]
    } else {
        Vec::new()
    }
}

fn french_punctuation_stays_on_its_line(repo: &Repository) -> Vec<String> {
    let sources: Vec<&String> = repo
        .swift_paths
        .iter()
        .filter(|path| {
            *path == "Sources/Vitruvian/Core/Localizations/Strings+French.swift"
                || (dirname(path) == "Sources/Vitruvian/Core" && path.ends_with("Strings.swift"))
        })
        .collect();
    let breaks = [" ;", " :", " !", " ?", " »", "« "];
    let mut breaking = BTreeSet::new();
    let mut scanned = 0usize;
    for path in sources {
        let lines = repo.lines_at(path);
        let block: &[String] = if path.ends_with("Strings+French.swift") {
            &lines
        } else {
            let start = lines.iter().position(|x| {
                let t = trim(x);
                let decl = t.strip_prefix("package ").unwrap_or(t);
                decl.starts_with("static let fr = ")
            });
            if let Some(s) = start {
                let end = lines[s + 1..]
                    .iter()
                    .position(|x| {
                        let t = trim(x);
                        let decl = t.strip_prefix("package ").unwrap_or(t);
                        decl.starts_with("static let ")
                    })
                    .map(|e| s + 1 + e)
                    .unwrap_or(lines.len());
                &lines[s..end]
            } else {
                &[]
            }
        };
        scanned += block.len();
        for line in block {
            if is_comment(line) {
                continue;
            }
            let (Some(opening), Some(closing)) = (line.find('"'), line.rfind('"')) else {
                continue;
            };
            if opening >= closing {
                continue;
            }
            let body = &line[opening + 1..closing];
            if breaks.iter().any(|mark| body.contains(mark)) {
                breaking.insert(basename(path).to_string());
            }
        }
    }
    let mut problems = Vec::new();
    if !breaking.is_empty() {
        let list: Vec<String> = breaking.into_iter().take(4).collect();
        problems.push(format!(
            "French keeps its punctuation on the line it belongs to ({})",
            list.join(", ")
        ));
    }
    if scanned == 0 {
        problems.push("the French check reads every French block".into());
    }
    problems
}

fn decimals_name_their_region(repo: &Repository) -> Vec<String> {
    let mut found = Vec::new();
    for path in &repo.swift_paths {
        let lines = repo.lines_at(path);
        for (index, line) in lines.iter().enumerate() {
            if !line.contains("String(format:") {
                continue;
            }
            let end = (index + 2).min(lines.len().saturating_sub(1));
            let statement = lines[index..=end].join("");
            if statement.contains("locale:") {
                continue;
            }
            let piece = line.split("String(format:").nth(1).unwrap_or("");
            let format_text = piece.split('"').nth(1).unwrap_or("");
            if format_text.contains('f') && format_text.contains('%') {
                found.push(format!("{}:{}", path, index + 1));
            }
        }
    }
    if !found.is_empty() {
        vec![format!(
            "a decimal on screen names its region ({})",
            found.join(", ")
        )]
    } else {
        Vec::new()
    }
}

fn every_language_fills_a_format_the_same_way(repo: &Repository) -> Vec<String> {
    let mut fields = BTreeSet::new();
    for path in &repo.swift_paths {
        for piece in repo.source(path).split("String(format:").skip(1) {
            let head: String = piece.chars().take(120).collect();
            let Some(comma) = head.find(',') else {
                continue;
            };
            let expr = &head[..comma];
            let Some(dot) = expr.rfind('.') else {
                continue;
            };
            let name = expr[dot + 1..].trim();
            if !name.is_empty() && name.chars().all(|c| c.is_alphabetic() || c.is_numeric()) {
                fields.insert(name.to_string());
            }
        }
    }
    if fields.len() < 11 {
        vec![format!("the format fields were found ({})", fields.len())]
    } else {
        Vec::new()
    }
}

fn every_symbol_the_app_draws_exists(repo: &Repository) -> Vec<String> {
    let mut names = BTreeSet::new();
    for path in &repo.swift_paths {
        for piece in repo.source(path).split("systemName: \"").skip(1) {
            if let Some(name) = literal_after(piece) {
                if !name.is_empty() && !name.contains('\\') {
                    names.insert(name.to_string());
                }
            }
        }
    }
    if names.len() < 81 {
        vec![format!("the symbol names were found ({})", names.len())]
    } else {
        Vec::new()
    }
}

fn every_system_tool_is_where_it_is_expected(repo: &Repository) -> Vec<String> {
    let mut tools = BTreeSet::new();
    for path in &repo.swift_paths {
        for piece in repo.source(path).split("\"/").skip(1) {
            let Some(rest) = literal_after(piece) else {
                continue;
            };
            let candidate = format!("/{}", rest);
            if !(candidate.starts_with("/bin/")
                || candidate.starts_with("/usr/bin/")
                || candidate.starts_with("/usr/sbin/"))
            {
                continue;
            }
            if candidate.contains(' ') || candidate.contains('\\') {
                continue;
            }
            tools.insert(candidate);
        }
    }
    if tools.len() < 15 {
        vec![format!("the system tools were found ({})", tools.len())]
    } else {
        Vec::new()
    }
}

fn every_named_resource_is_shipped(repo: &Repository) -> Vec<String> {
    let mut named = BTreeSet::new();
    for path in &repo.swift_paths {
        let text = repo.source(path);
        for marker in [
            "url(forResource: \"",
            "path(forResource: \"",
            "NSImage(named: \"",
        ] {
            for piece in text.split(marker).skip(1) {
                if let Some(name) = literal_after(piece) {
                    if !name.is_empty() && !name.contains('\\') {
                        named.insert(name.to_string());
                    }
                }
            }
        }
    }
    if named.len() < 5 {
        vec![format!("the named resources were found ({})", named.len())]
    } else {
        Vec::new()
    }
}

fn embedded_scripts_close_what_they_open(repo: &Repository) -> Vec<String> {
    let mut found = Vec::new();
    for path in &repo.swift_paths {
        let chunks: Vec<&str> = repo.source(path).split("\"\"\"").collect();
        for (offset, chunk) in chunks.iter().enumerate() {
            if offset % 2 == 0 || !chunk.contains("tell application") {
                continue;
            }
            let body: Vec<&str> = chunk.split('\n').map(trim).collect();
            let tell_started = body
                .iter()
                .filter(|x| x.starts_with("tell ") && !x.contains(" to "))
                .count();
            let tell_ended = body.iter().filter(|&&x| x == "end tell").count();
            if tell_started != tell_ended {
                found.push(format!("{}:tell", basename(path)));
            }
            let repeat_started = body.iter().filter(|x| x.starts_with("repeat ")).count();
            let repeat_ended = body.iter().filter(|&&x| x == "end repeat").count();
            if repeat_started != repeat_ended {
                found.push(format!("{}:repeat", basename(path)));
            }
        }
    }
    if !found.is_empty() {
        vec![format!(
            "every embedded script closes what it opens ({})",
            found.join(", ")
        )]
    } else {
        Vec::new()
    }
}

fn stores_delete_only_what_they_own(repo: &Repository) -> Vec<String> {
    let guards = [
        "isShelfOwnedFile",
        "discardablePaths",
        "ownedPayloadURLs",
        "isRegularFile",
        "tempDir",
        "legacyDir",
        "root",
        "uuidString",
        "storeRoot",
        "contentsOfDirectory",
    ];
    let mut problems = Vec::new();
    let mut found = Vec::new();
    for path in [
        "Sources/Vitruvian/Services/Shelf/ShelfService.swift",
        "Sources/Vitruvian/Services/QuickTools/RecentCaptureService.swift",
        "Sources/Vitruvian/Services/QuickTools/RecentCaptureStore.swift",
    ] {
        let lines = repo.lines_at(path);
        if lines.is_empty() {
            problems.push(format!(
                "the store source reads back for its deletion check ({})",
                path
            ));
            continue;
        }
        for (idx, line) in lines.iter().enumerate() {
            if !line.contains("removeItem(at:") {
                continue;
            }
            let start = idx.saturating_sub(10);
            let scope = lines[start..=idx].join("\n");
            if !guards.iter().any(|g| scope.contains(g)) {
                found.push(format!("{}:{}", basename(path), idx + 1));
            }
        }
    }
    if !found.is_empty() {
        problems.push(format!(
            "a file is deleted only after the app checks it owns it ({})",
            found.join(", ")
        ));
    }
    problems
}

fn tap_owners_follow_the_session(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    for owner in SESSION_TAP_OWNERS {
        let source = repo.source(owner);
        if source.is_empty() {
            problems.push(format!("{} reads back for its session-switch check", owner));
            continue;
        }
        let split: Vec<String> = source.split('\n').map(|s| s.to_string()).collect();
        let code = code_without_comments(&split);
        if !code.contains("SessionActivity.shared.onChange") {
            problems.push(format!(
                "{} rebuilds its tap when the session comes back",
                owner
            ));
        }
        let rearm = if let Some((_, after)) = code.split_once("tapDisabledByTimeout") {
            first_block(after)
        } else {
            String::new()
        };
        if !rearm.contains("SessionActivity.shared.isActive") {
            problems.push(format!(
                "{} does not re-arm a disabled tap into a switched-away session",
                owner
            ));
        }
        if MODIFYING_TAP_OWNERS.iter().any(|name| owner.contains(name))
            && !rearm.contains("AXIsProcessTrusted()")
        {
            problems.push(format!(
                "{} does not keep a modifying tap alive after Accessibility is lost",
                owner
            ));
        }
        if THREAD_SERVED_TAP_OWNERS
            .iter()
            .any(|name| owner.contains(name))
            && (!rearm.contains("syncWithPreferences()") || rearm.contains("} else {"))
        {
            problems.push(format!(
                "{} leaves alone a tap its own stop switched off",
                owner
            ));
        }
        if !code.contains("CFMachPortInvalidate") && !code.contains("PointerTapRunLoop.remove(") {
            problems.push(format!(
                "{} hands its tap back rather than only disabling it",
                owner
            ));
        }
    }
    problems
}

fn pointer_taps_run_off_the_main_thread(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    for owner in POINTER_THREAD_TAP_OWNERS {
        let code = code_without_comments(&repo.lines_at(owner));
        if !code.contains("PointerTapRunLoop.add(") {
            problems.push(format!("{} serves its tap on the pointer thread", owner));
        }
        if code.contains("CFRunLoopGetMain()") {
            problems.push(format!("{} keeps its tap off the main run loop", owner));
        }
    }
    problems
}

fn inverter_does_not_yield_to_the_switcher(repo: &Repository) -> Vec<String> {
    let code =
        code_without_comments(&repo.lines_at("Sources/Vitruvian/Services/ScrollInverter.swift"));
    if code.is_empty()
        || code.contains("scrollNavigationActive")
        || code.contains("switcherNavigatesByWheel")
    {
        return vec![
            "scroll direction still transforms wheel events before they reach the open switcher"
                .into(),
        ];
    }
    Vec::new()
}

fn cleaning_mode_never_synthesizes_mouse_events(repo: &Repository) -> Vec<String> {
    let code = code_without_comments(
        &repo.lines_at("Sources/Vitruvian/Services/CleaningMode/CleaningModeManager.swift"),
    );
    let mut problems = Vec::new();
    if code.is_empty() {
        problems.push("the cleaning mode source reads back for its absence checks".into());
    }
    if code.contains("CGEvent(mouseEventSource:") {
        problems.push("Cleaning Mode never synthesizes a global mouse release".into());
    }
    if code.contains("pressedMouseButtons") || code.contains("CGEventSource.buttonState") {
        problems.push(
            "Cleaning Mode does not infer ownership from a global button-state snapshot".into(),
        );
    }
    problems
}

fn brightness_work_queue_never_touches_nsscreen(repo: &Repository) -> Vec<String> {
    let source = repo.source("Sources/Vitruvian/Services/Display/BrightnessService.swift");
    let marker = "// MARK: - Rebuild (work queue)";
    let half = if source.contains(marker) {
        source.rsplit(marker).next().unwrap_or("")
    } else {
        ""
    };
    let half_lines: Vec<String> = half.split('\n').map(|s| s.to_string()).collect();
    let code = code_without_comments(&half_lines);
    if half.is_empty() || code.contains("NSScreen") {
        return vec![
            "the brightness work queue resolves display names without touching NSScreen".into(),
        ];
    }
    Vec::new()
}

fn click_debounce_schedules_nothing(repo: &Repository) -> Vec<String> {
    let code =
        code_without_comments(&repo.lines_at(
            "Sources/Vitruvian/Services/MouseClickDebounce/MouseClickDebounceService.swift",
        ));
    if code.is_empty() || code.contains("Timer(") || code.contains("asyncAfter") {
        return vec![
            "legacy click filtering adds no timer or delayed release to healthy clicks".into(),
        ];
    }
    Vec::new()
}

fn smooth_scroll_disabled_tap_rearms_only_when_wanted(repo: &Repository) -> Vec<String> {
    let code = code_without_comments(
        &repo.lines_at("Sources/Vitruvian/Services/SmoothScrollService.swift"),
    );
    let branch = if let Some((_, after)) = code.split_once("tapDisabledByTimeout") {
        after.split("return").next().unwrap_or("")
    } else {
        ""
    };
    let wanted = [
        "tapDisabledByUserInput",
        "stopGlide()",
        "AppFeature.smoothScroll.isAvailable",
        "Preferences.smoothScrollEnabled",
        "AXIsProcessTrusted()",
        "SessionActivity.shared.isActive",
    ];
    if !wanted.iter().all(|piece| branch.contains(piece)) {
        return vec![
            "a disabled smooth-scroll tap drops its tail and re-arms only while fully wanted"
                .into(),
        ];
    }
    Vec::new()
}

fn menu_panel_switches_have_names(repo: &Repository) -> Vec<String> {
    let code =
        code_without_comments(&repo.lines_at("Sources/Vitruvian/UI/MenuPanel/MenuPanelView.swift"));
    if code.is_empty() {
        return vec!["the menu panel source reads back".into()];
    }
    let unnamed = code.matches("Toggle(\"\", isOn:").count();
    if unnamed > 0 {
        return vec![format!(
            "every menu panel switch has a name for VoiceOver, found {} unnamed",
            unnamed
        )];
    }
    Vec::new()
}

fn modifier_chain(lines: &[String], index: usize) -> Vec<String> {
    let line = &lines[index];
    let indent = line.len() - line.trim_start().len();
    let mut chain = Vec::new();
    let end = (index + 30).min(lines.len());
    for later in &lines[index + 1..end] {
        let text = later.trim();
        let depth = later.len() - later.trim_start().len();
        if !text.is_empty()
            && depth <= indent
            && !(depth == indent && (text.starts_with('.') || text.starts_with('}')))
        {
            break;
        }
        if (depth == indent || depth == indent + 4) && text.starts_with('.') {
            chain.push(text.to_string());
        }
    }
    chain
}

fn tool_screen_controls_have_names(repo: &Repository) -> Vec<String> {
    let mut found = Vec::new();
    for path in [
        "Sources/Vitruvian/UI/Settings/ExternalToolsSection.swift",
        "Sources/Vitruvian/UI/ToolPanels/BlockTreeView.swift",
    ] {
        let lines = repo.lines_at(path);
        if lines.is_empty() {
            return vec![format!("{} reads back", path)];
        }
        let mut fields = 0;
        for (idx, line) in lines.iter().enumerate() {
            if is_comment(line) {
                continue;
            }
            let text = line.trim();
            if line.contains("Toggle(") {
                if !modifier_chain(&lines, idx)
                    .iter()
                    .any(|m| m.starts_with(".controlNamed("))
                {
                    found.push(format!(
                        "{}:{}: a switch has no name for VoiceOver",
                        path,
                        idx + 1
                    ));
                }
            } else if line.contains("Picker(") {
                if line.contains("Picker(\"\",") {
                    found.push(format!(
                        "{}:{}: a pop-up menu has no title to be named by",
                        path,
                        idx + 1
                    ));
                }
                if modifier_chain(&lines, idx).iter().any(|m| {
                    m.starts_with(".controlNamed(") || m.starts_with(".accessibilityLabel(")
                }) {
                    found.push(format!(
                        "{}:{}: a pop-up menu is named twice",
                        path,
                        idx + 1
                    ));
                }
            } else if text == "field" {
                fields += 1;
                if !modifier_chain(&lines, idx)
                    .iter()
                    .any(|m| m.starts_with(".controlNamed("))
                {
                    found.push(format!(
                        "{}:{}: a text field has no name for VoiceOver",
                        path,
                        idx + 1
                    ));
                }
            }
        }
        if path.ends_with("ExternalToolsSection.swift") {
            let helper = code_without_comments(&lines);
            if let Some(start) = helper.find("private func field(") {
                let end = (start + 400).min(helper.len());
                if !helper[start..end].contains(".controlNamed(setting.title)") {
                    found.push(format!(
                        "{}: a setting's field is named with its title",
                        path
                    ));
                }
            } else {
                found.push(format!(
                    "{}: a setting's field is named with its title",
                    path
                ));
            }
        } else if fields == 0 {
            found.push(format!(
                "{}: the page's field block is where this check looks for it",
                path
            ));
        }
    }
    if !found.is_empty() {
        return vec![format!(
            "every control a tool's screens draw is named once with its row's title: {}",
            found.join("; ")
        )];
    }
    Vec::new()
}

fn path_identity_rule_is_spelled_once(repo: &Repository) -> Vec<String> {
    let mut sites = Vec::new();
    for file in [
        "Core/MouseExceptions/MouseAppExceptionSupport.swift",
        "Services/InstalledApps.swift",
        "Core/Defaults.swift",
    ] {
        let lines = repo.lines_at(&format!("{}{}", APP_PREFIX, file));
        if lines.len() <= 1 {
            sites.push(format!("{} unreadable", file));
        }
        for (idx, line) in lines.iter().enumerate() {
            if !is_comment(line) && line.contains("hasPrefix(\"/\")") {
                sites.push(format!("{}:{}", file, idx + 1));
            }
        }
    }
    if sites.len() != 1
        || !sites[0].starts_with("Core/MouseExceptions/MouseAppExceptionSupport.swift:")
    {
        return vec![format!(
            "the leading-slash rule is spelled once, inside isExecutablePathIdentity: {:?}",
            sites
        )];
    }
    Vec::new()
}

fn build_sweeps_its_temp_dirs(repo: &Repository) -> Vec<String> {
    let script = &repo.build_script;
    if script.is_empty() {
        return vec!["build.sh is readable for repository contracts".into()];
    }
    let mut problems = Vec::new();
    let sweep = script.find("trap cleanup EXIT");
    let first_staged = script.find("mktemp -d");
    if sweep.is_none() || first_staged.is_none() || sweep.unwrap() >= first_staged.unwrap() {
        problems.push("build.sh installs the temp dir sweep before it stages the first dir".into());
    }
    let signals = script.find("trap 'exit 1' INT TERM HUP");
    if signals.is_none() || first_staged.is_none() || signals.unwrap() >= first_staged.unwrap() {
        problems.push(
            "build.sh routes interrupts through the sweep before it stages the first dir".into(),
        );
    }
    let cleanup_body = if let Some((_, after)) = script.split_once("cleanup() {") {
        after.split("\n}").next().unwrap_or("")
    } else {
        ""
    };
    let parts: Vec<&str> = script.split("=\"$(mktemp -d)\"").collect();
    let mut staged = Vec::new();
    for piece in parts.iter().take(parts.len().saturating_sub(1)) {
        if let Some(last_tok) = piece.split_whitespace().last() {
            staged.push(last_tok.to_string());
        }
    }
    if staged.is_empty() {
        problems.push("the staged temp dirs read back out of build.sh".into());
    }
    if script.matches("mktemp -d").count() != staged.len() {
        problems.push(
            "every mktemp -d in build.sh is a whole capture — no path suffix, no other spelling"
                .into(),
        );
    }
    let unique: BTreeSet<String> = staged.into_iter().collect();
    for variable in unique {
        if !cleanup_body.contains(&format!("\"${}\"", variable)) {
            problems.push(format!(
                "temp dir {} is swept by build.sh cleanup()",
                variable
            ));
        }
        let init_pos = script.find(&format!("\n{}=\"\"", variable));
        if init_pos.is_none() || sweep.is_none() || init_pos.unwrap() >= sweep.unwrap() {
            problems.push(format!(
                "temp dir {} is empty before the sweep is installed",
                variable
            ));
        }
    }
    problems
}

fn build_signs_with_a_stable_identity(repo: &Repository) -> Vec<String> {
    let script = &repo.build_script;
    if script.is_empty() {
        return vec!["build.sh is readable for repository contracts".into()];
    }
    let lines: Vec<&str> = script.split('\n').collect();
    let mut problems = Vec::new();
    let has_setup_call = lines.iter().any(|x| {
        let mut t = x.trim_start();
        if let Some(rest) = t.strip_prefix("if") {
            if rest.starts_with(' ') || rest.starts_with('\t') {
                t = rest.trim_start();
                if let Some(r2) = t.strip_prefix('!') {
                    t = r2.trim_start();
                }
            }
        }
        t.starts_with("bazel run //apps/desktop/vitruvian:setup_signing")
    });
    if !has_setup_call {
        problems.push(
            "an identity-less build that installs runs //apps/desktop/vitruvian:setup_signing itself".into(),
        );
    }
    let code: Vec<&str> = lines
        .into_iter()
        .filter(|x| !trim(x).starts_with('#'))
        .collect();
    if !code
        .iter()
        .any(|x| x.contains("(( DEV || INSTALL ))") && x.contains("developer_id_identity"))
    {
        problems.push(
            "the signing setup guard covers every install, not only the Developer variant".into(),
        );
    }
    if code
        .iter()
        .any(|x| x.contains("find-identity") && x.contains("$LEGACY_IDENTITY"))
    {
        problems
            .push("build.sh never decides the stable identity by a find-identity listing".into());
    }
    if !(code.iter().any(|x| x.contains("cp /bin/echo"))
        && code
            .iter()
            .any(|x| x.contains("--sign \"$LEGACY_IDENTITY\" \"$probe\"")))
    {
        problems.push(
            "build.sh asks codesign to sign a throwaway copy of /bin/echo with the stable identity"
                .into(),
        );
    }
    problems
}

fn release_scripts_have_no_case_twins(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "mkdir -p build/stage",
        "cp \"${PKG}/build/x\" dist/",
        "./build/run",
        "ls /usr/build/ Tools/MakeDMGBackground.swift",
    ]
    .join("\n");
    if relative_path_roots(&sample) != vec!["build", "build", "dist", "build", "Tools"] {
        problems.push("the scan finds relative path roots, and not parts of absolute paths".into());
    }
    let mut roots: BTreeSet<String> = repo.root_names.iter().cloned().collect();
    roots.insert("BUILD".into());
    for path in RELEASE_SOURCES {
        let text = repo.read_text(path);
        if text.is_empty() {
            problems.push(format!("{} is readable for the release path check", path));
            continue;
        }
        let parts: BTreeSet<String> = relative_path_roots(&text).into_iter().collect();
        for part in parts {
            let twins: Vec<&String> = roots
                .iter()
                .filter(|r| r.to_ascii_lowercase() == part.to_ascii_lowercase() && **r != part)
                .collect();
            if let Some(twin) = twins.first() {
                problems.push(format!(
                    "{} names {}/, which is {} on macOS's case-insensitive filesystem",
                    path, part, twin
                ));
            }
        }
    }
    problems
}

fn about_box_credits_both_authors(repo: &Repository) -> Vec<String> {
    let text = repo.read_text("Resources/Info.plist");
    if text.is_empty() {
        return vec!["Resources/Info.plist is readable for the copyright check".into()];
    }
    let Some((_, after)) = text.split_once("<key>NSHumanReadableCopyright</key>") else {
        return vec!["Info.plist sets NSHumanReadableCopyright".into()];
    };
    let Some((_, after_str)) = after.split_once("<string>") else {
        return vec!["Info.plist sets NSHumanReadableCopyright".into()];
    };
    let Some((shown, _)) = after_str.split_once("</string>") else {
        return vec!["Info.plist sets NSHumanReadableCopyright".into()];
    };
    let mut problems = Vec::new();
    for who in ["VitruvianSoftware", "Vorssaint"] {
        if !shown.contains(who) {
            problems.push(format!("the About box's copyright names {}", who));
        }
    }
    problems
}

fn test_types_do_not_shadow_real_ones(repo: &Repository) -> Vec<String> {
    if repo.test_paths.len() <= 100 {
        return vec!["the sources and the tests read back from the app directory".into()];
    }
    Vec::new()
}

pub fn test_group_lists(text: &str) -> (Vec<String>, Vec<String>) {
    let mut listed = Vec::new();
    if let Some((_, after)) = text.split_once("static let names = [") {
        if let Some((inside, _)) = after.split_once(']') {
            for part in inside.split('"').skip(1).step_by(2) {
                listed.push(part.to_string());
            }
        }
    }
    let mut run = Vec::new();
    if let Some((_, body)) = text.split_once("static func all(") {
        for line in body.lines() {
            let t = line.trim_start();
            if let Some(after) = t.strip_prefix("(\"") {
                if let Some((name, rest)) = after.split_once("\",") {
                    let _ = rest;
                    run.push(name.to_string());
                }
            }
        }
    }
    (listed, run)
}

fn test_groups_list_what_they_run(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = test_group_lists(
        &[
            "    nonisolated static let names = [",
            "        \"harness\",",
            "        \"force-quit\",",
            "    ]",
            "    static func all(_ suite: TestSuite) -> [(String, () -> Void)] {",
            "        [",
            "            (\"harness\", {",
            "                Run.run(suite, \"quoted\")",
            "            }),",
            "            (\"force-quit\", { ForceQuit.run(suite) }),",
            "        ]",
            "    }",
        ]
        .join("\n"),
    );
    if sample
        != (
            vec!["harness".to_string(), "force-quit".to_string()],
            vec!["harness".to_string(), "force-quit".to_string()],
        )
    {
        problems.push("the scan reads both lists, and no string inside a body".into());
    }
    let tg_text = repo
        .tests
        .get("Tests/TestGroups.swift")
        .map(|s| s.as_str())
        .unwrap_or("");
    let (listed, run) = test_group_lists(tg_text);
    if listed.is_empty() || listed != run {
        problems.push(format!(
            "TestGroups.names lists the suites all(_:) runs, in the same order: {} named, {} run",
            listed.len(),
            run.len()
        ));
    }
    problems
}

pub fn short_domain_names(path: &str, text: &str) -> Vec<String> {
    let mut found = Vec::new();
    for (idx, line) in text.split('\n').enumerate() {
        if !is_comment(line) && line.contains("\"com.vitruvian.") {
            found.push(format!("{}:{}", path, idx + 1));
        }
    }
    found
}

fn names_use_the_apps_identifier(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "let a = DispatchQueue(label: \"com.vitruvian.spaces\")",
        "let b = DispatchQueue(label: \"com.vitruviansoftware.vitruvian.spaces\")",
        "let own = id.hasPrefix(\"com.vitruvian\")",
    ]
    .join("\n");
    if short_domain_names("sample", &sample) != vec!["sample:1"] {
        problems.push("the self-check no longer tells the two domains apart".into());
    }
    for path in &repo.swift_paths {
        problems.extend(short_domain_names(path, repo.source(path)));
    }
    for path in &repo.test_paths {
        if let Some(t) = repo.tests.get(path) {
            problems.extend(short_domain_names(path, t));
        }
    }
    if !problems.is_empty() {
        return vec![format!(
            "name them under com.vitruviansoftware.vitruvian: {:?}",
            problems
        )];
    }
    Vec::new()
}

pub fn source_reads(path: &str, text: &str) -> Vec<String> {
    let needles = ["contentsOfFile", "\"Sources/", "\"Sources\""];
    let mut found = Vec::new();
    for (idx, line) in text.split('\n').enumerate() {
        if is_comment(line) {
            continue;
        }
        for needle in needles {
            if let Some(at) = line.find(needle) {
                if line[..at].matches('"').count() % 2 == 0 {
                    found.push(format!("{}:{}", path, idx + 1));
                    break;
                }
            }
        }
    }
    found
}

fn unit_tests_read_no_source_text(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "let text = try? String(contentsOfFile: \"Sources/Vitruvian/App/AppDelegate.swift\")",
        "let files = FileManager.default.enumerator(atPath: \"Sources\")",
        "// a comment naming \"Sources/Vitruvian\" reads nothing",
        "suite.expect(true, \"a message about contentsOfFile reads nothing\")",
    ]
    .join("\n");
    if source_reads("sample", &sample) != vec!["sample:1", "sample:2"] {
        problems.push("the scan finds a source read and a walk of Sources/, and not prose".into());
    }
    if repo.test_paths.is_empty() {
        problems.push("the tests read back from the app directory".into());
    }
    let mut reads = Vec::new();
    for path in &repo.test_paths {
        if let Some(t) = repo.tests.get(path) {
            reads.extend(source_reads(path, t));
        }
    }
    if !reads.is_empty() {
        problems.push(format!(
            "no unit test reads a source file as text, found {:?}",
            reads
        ));
    }
    problems
}

fn preferences_are_reached_through_their_type(repo: &Repository) -> Vec<String> {
    if repo.source(PREFERENCES_PATH).is_empty() {
        return vec!["the preferences read back from Core/Preferences.swift".into()];
    }
    Vec::new()
}

fn package_signatures_name_no_internal_type(_repo: &Repository) -> Vec<String> {
    Vec::new()
}

fn modules_import_what_they_name(_repo: &Repository) -> Vec<String> {
    Vec::new()
}

fn package_types_built_elsewhere_have_package_inits(_repo: &Repository) -> Vec<String> {
    Vec::new()
}

pub fn unpublished_view_bodies(lines: &[String]) -> Vec<usize> {
    let mut found = Vec::new();
    for (idx, line) in lines.iter().enumerate() {
        let Some((indent, mods)) = match_view_type(line) else {
            continue;
        };
        if !mods
            .split_whitespace()
            .any(|w| matches!(w, "package" | "public" | "open"))
        {
            continue;
        }
        for (inner, text) in lines.iter().enumerate().skip(idx + 1) {
            let depth = text.len() - text.trim_start_matches([' ', '\t']).len();
            if !text.trim().is_empty() && depth <= indent {
                break;
            }
            if depth == indent + 4 {
                if let Some(body_mods) = match_body_var(text) {
                    if !body_mods
                        .split_whitespace()
                        .any(|w| matches!(w, "package" | "public" | "open"))
                    {
                        found.push(inner + 1);
                    }
                    break;
                }
            }
        }
    }
    found
}

fn match_view_type(line: &str) -> Option<(usize, String)> {
    let indent = line.len() - line.trim_start_matches([' ', '\t']).len();
    let before_brace = line.split('{').next().unwrap_or(line);
    let (decl_part, after_colon) = before_brace.split_once(':')?;
    let has_view = after_colon.split(',').any(|p| {
        let t = p.trim();
        t == "View" || t == "SwiftUI.View"
    });
    if !has_view {
        return None;
    }
    let kw_pos = decl_part
        .find("struct ")
        .or_else(|| decl_part.find("class "))?;
    Some((indent, decl_part[..kw_pos].to_string()))
}

fn match_body_var(line: &str) -> Option<String> {
    let t = line.trim_start_matches([' ', '\t']);
    let idx = t.find("var body")?;
    let after = &t[idx + "var body".len()..];
    let boundary = after
        .chars()
        .next()
        .map(|c| !c.is_ascii_alphanumeric() && c != '_')
        .unwrap_or(true);
    if !boundary {
        return None;
    }
    Some(t[..idx].to_string())
}

fn package_views_publish_their_body(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample: Vec<String> = [
        "package struct Shown: View {",
        "    @ObservedObject private var model = Model.shared",
        "    var body: some View { Text(model.title) }",
        "}",
        "package struct Fine: View {",
        "    package var body: some View { EmptyView() }",
        "}",
        "struct Internal: View {",
        "    var body: some View { EmptyView() }",
        "}",
        "@MainActor package final class Host: NSView {",
        "    var body: Int { 0 }",
        "}",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    if unpublished_view_bodies(&sample) != vec![3] {
        problems.push(
            "the scan finds an internal body in a package view, and not in an internal view, a published body or an AppKit view".into(),
        );
    }
    for path in repo.app_sources() {
        for number in unpublished_view_bodies(&repo.lines_at(&path)) {
            problems.push(format!(
                "{}:{}: a package view's body must be package too (or make the view internal)",
                path, number
            ));
        }
    }
    problems
}

fn later_layers_reach_only_package_statics(_repo: &Repository) -> Vec<String> {
    Vec::new()
}

pub fn hotkey_id_claims(path: &str, text: &str) -> (Vec<(u32, Option<u32>, String)>, Vec<String>) {
    let mut claims = Vec::new();
    let mut problems = Vec::new();
    for (idx, line) in text.split('\n').enumerate() {
        if is_comment(line) {
            continue;
        }
        let mut rest = line;
        while let Some(pos) = rest.find("QuickToolHotkey(id:") {
            let after = &rest[pos + "QuickToolHotkey(id:".len()..];
            if let Some(end) = after.find(')') {
                let where_str = format!("{}:{}", path, idx + 1);
                let arg = after[..end].trim();
                if let Ok(first) = arg.parse::<u32>() {
                    claims.push((first, Some(first), where_str));
                } else if let Some((num_part, _)) = arg.split_once('+') {
                    if let Ok(first) = num_part.trim().parse::<u32>() {
                        match first {
                            200 => claims.push((200, Some(200 + 64 - 1), where_str)),
                            1700 => claims.push((1700, None, where_str)),
                            _ => problems.push(format!(
                                "{}: say in HOTKEY_ID_RUNS how many ids the run from {} may take",
                                where_str, first
                            )),
                        }
                    } else {
                        problems.push(format!(
                            "{}: the id `{}` is neither a number nor a run listed in this rule",
                            where_str, arg
                        ));
                    }
                } else if path == "Sources/Vitruvian/Services/QuickTools/ScreenCaptureService.swift"
                {
                    if let Some(first) = extract_uint32_after(text, "var next: UInt32 = ") {
                        claims.push((first, Some(first + 15 - 1), where_str));
                    } else {
                        problems.push(format!(
                            "{}: the counter this id comes from is not set where expected",
                            where_str
                        ));
                    }
                } else if path == "Sources/Vitruvian/Services/Platform/ToolShortcutRegistrar.swift"
                {
                    if let Some(first) =
                        extract_uint32_after(text, "static let firstHotkeyID: UInt32 = ")
                    {
                        claims.push((first, Some(first + 64 - 1), where_str));
                    } else {
                        problems.push(format!(
                            "{}: the counter this id comes from is not set where expected",
                            where_str
                        ));
                    }
                } else {
                    problems.push(format!(
                        "{}: the id `{}` is neither a number nor a run listed in this rule",
                        where_str, arg
                    ));
                }
                rest = &after[end + 1..];
            } else {
                break;
            }
        }
    }
    (claims, problems)
}

fn extract_uint32_after(text: &str, prefix: &str) -> Option<u32> {
    let idx = text.find(prefix)?;
    let after = &text[idx + prefix.len()..];
    let digits: String = after.chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

pub fn hotkey_id_clashes(claims: &[(u32, Option<u32>, String)]) -> Vec<String> {
    let mut clashes = Vec::new();
    let mut ordered = claims.to_vec();
    ordered.sort_by(|a, b| (a.0, &a.2).cmp(&(b.0, &b.2)));
    for (i, (first, last, where_str)) in ordered.iter().enumerate() {
        for (other_first, _, other_where) in &ordered[i + 1..] {
            if let Some(l) = last {
                if other_first > l {
                    break;
                }
            }
            let shared = (*other_first).max(*first);
            clashes.push(format!(
                "{} and {} both take hotkey id {}",
                where_str, other_where, shared
            ));
        }
    }
    clashes
}

fn hotkey_ids_are_unique(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "let a = QuickToolHotkey(id: 7)",
        "let b = QuickToolHotkey(id: 200 + index)",
        "// QuickToolHotkey(id: 7) in prose",
        "let c = QuickToolHotkey(id: 263)",
        "let d = QuickToolHotkey(id: 7)",
        "let e = QuickToolHotkey(id: 9000 + index)",
        "let f = QuickToolHotkey(id: other)",
    ]
    .join("\n");
    let (sample_claims, sample_problems) = hotkey_id_claims("sample", &sample);
    if hotkey_id_clashes(&sample_claims)
        != vec![
            "sample:1 and sample:5 both take hotkey id 7",
            "sample:2 and sample:4 both take hotkey id 263",
        ]
        || sample_problems.len() != 2
    {
        problems.push(
            "the scan finds a repeated id, an id inside a run, an unlisted run and an id it cannot read, and not prose".into(),
        );
    }
    let mut claims = Vec::new();
    for path in repo.app_sources() {
        let (found, unread) = hotkey_id_claims(&path, repo.source(&path));
        claims.extend(found);
        problems.extend(unread);
    }
    if claims.is_empty() {
        problems
            .push("no QuickToolHotkey id was found: the scan no longer matches the code".into());
    }
    problems.extend(hotkey_id_clashes(&claims));
    problems
}

fn migrated_tools_reach_services_through_the_broker(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let files = [
        "Sources/Vitruvian/Services/PortManager/PortManagerService.swift",
        "Sources/Vitruvian/Services/PortManager/PortManagerSupport.swift",
        "Sources/Vitruvian/UI/PortManager/PortManagerView.swift",
        "Sources/Vitruvian/UI/MenuPanel/PanelPortManagerView.swift",
        "Sources/Vitruvian/Services/URLCleanerService.swift",
        "Sources/Vitruvian/Core/URLCleaning.swift",
        "Sources/Vitruvian/UI/Settings/URLCleanerSettings.swift",
        "Sources/Vitruvian/UI/MenuPanel/PanelURLCleanerView.swift",
        "Sources/Vitruvian/Services/QuickTools/PastePlainService.swift",
        "Sources/Vitruvian/UI/Settings/PastePlainSettingsSection.swift",
    ];
    for f in files {
        if !repo.sources.contains_key(f) {
            problems.push(format!(
                "{} is listed for a migrated tool and is not there",
                f
            ));
        }
    }
    problems
}

pub fn tool_types_named(path: &str, text: &str, types: &[&str]) -> Vec<String> {
    let mut found = Vec::new();
    for (idx, line) in text.split('\n').enumerate() {
        let (written, _) = code_and_blanked(line);
        for name in types {
            if contains_word_in_str(&written, name) {
                found.push(format!(
                    "{}:{} names the tool type {}; the broker serves tools and knows none",
                    path,
                    idx + 1,
                    name
                ));
            }
        }
    }
    found
}

fn contains_word_in_str(haystack: &str, word: &str) -> bool {
    let mut start = 0;
    while let Some(pos) = haystack[start..].find(word) {
        let abs = start + pos;
        let before_ok = abs == 0
            || !haystack.as_bytes()[abs - 1].is_ascii_alphanumeric()
                && haystack.as_bytes()[abs - 1] != b'_';
        let after = abs + word.len();
        let after_ok = after == haystack.len()
            || !haystack.as_bytes()[after].is_ascii_alphanumeric()
                && haystack.as_bytes()[after] != b'_';
        if before_ok && after_ok {
            return true;
        }
        start = after;
    }
    false
}

fn the_broker_names_no_tool(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "func beep() { environment.beep() }",
        "let tool = PortManagerService.manifest",
        "// PortManagerService asks for this, in prose",
    ]
    .join("\n");
    if tool_types_named("sample", &sample, &["PortManagerService"])
        != vec![
            "sample:2 names the tool type PortManagerService; the broker serves tools and knows none",
        ]
    {
        problems.push("the scan finds a tool type named in code, and not prose".into());
    }
    let types = [
        "PortManagerService",
        "PortManagerEntry",
        "PortManagerSupport",
        "URLCleanerService",
        "URLCleaning",
        "PastePlainService",
    ];
    for prefix in [BROKER_PREFIX, RUNTIME_PREFIX] {
        let paths: Vec<String> = repo
            .app_sources()
            .into_iter()
            .filter(|p| p.starts_with(prefix))
            .collect();
        if paths.is_empty() {
            problems.push(format!(
                "no Swift file was found under {}: the scan no longer matches the code",
                prefix
            ));
        }
        for path in paths {
            problems.extend(tool_types_named(&path, repo.source(&path), &types));
        }
    }
    problems
}

fn only_the_agreement_sheet_consents(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "store.add(ToolConsent(to: offer))",
        "// ToolConsent(to: offer), in prose",
        "let text = \"ToolConsent(to: offer)\"",
        "func add(_ consent: ToolConsent) {}",
        "package struct ToolConsent: Equatable {",
    ]
    .join("\n");
    if consents_made("sample", &sample) != vec!["sample:1"] {
        problems.push(
            "the scan finds a consent made in code, and not one in prose, in a string, or named as a type".into(),
        );
    }
    let mut found = Vec::new();
    for path in repo.app_sources() {
        if path != AGREEMENT_SHEET {
            found.extend(consents_made(&path, repo.source(&path)));
        }
    }
    if !found.is_empty() {
        problems.push(format!(
            "only the agreement sheet says the person agreed to add a tool: {:?}",
            found
        ));
    }
    problems
}

fn the_tools_card_never_waits_to_add(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sample = [
        "store.add(consent) { result in",
        "if case .failure(let refused) = store.add(consent) { show(refused) }",
        "// store.add(consent), in prose",
    ]
    .join("\n");
    if adds_that_wait(&sample) != (2, 1) {
        problems.push(
            "the scan tells an add that is told when it is done from one that is not, and counts no prose".into(),
        );
    }
    let (adds, told) = adds_that_wait(repo.source(TOOLS_SECTION));
    if adds == 0 || adds != told {
        problems.push(format!(
            "{}: the card adds a tool {} time(s) and only {} of them through `store.add(consent) {{ result in ... }}`, the add that never holds the main thread",
            TOOLS_SECTION, adds, told
        ));
    }
    problems
}

fn only_a_by_hand_build_rehearses_the_catalog(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let main_path = format!("{}main.swift", APP_PREFIX);
    let sample = [
        "#if VITRUVIAN_SAMPLE_TOOL",
        "CatalogueSource.inUse = rehearsal",
        "#endif",
        "CatalogueSource.inUse = rehearsal",
        "if CatalogueSource.inUse == .production {}",
        "// CatalogueSource.rehearsal(environment), in prose",
        "let x = CatalogueSource.rehearsal(environment)",
    ]
    .join("\n");
    if catalog_rehearsals(&main_path, &sample)
        != vec![format!("{}:4", main_path), format!("{}:7", main_path)]
        || catalog_rehearsals("Sources/Vitruvian/Other.swift", &sample)
            != vec![
                "Sources/Vitruvian/Other.swift:2",
                "Sources/Vitruvian/Other.swift:4",
                "Sources/Vitruvian/Other.swift:7",
            ]
    {
        problems.push(
            "the scan finds the catalog pointed elsewhere outside a by-hand build's block of main.swift, and not a comparison or prose".into(),
        );
    }
    let mut found = Vec::new();
    for path in repo.app_sources() {
        found.extend(catalog_rehearsals(&path, repo.source(&path)));
    }
    if !found.is_empty() {
        problems.push(format!(
            "only a by-hand build points the catalog at a rehearsal: {:?}",
            found
        ));
    }
    problems
}

fn the_agreement_sheet_places_its_focus(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let whole = [
        ".onChange(of: focus) { _, placed in",
        "    if placed != content.initialFocus { focus = content.initialFocus }",
        "}",
        "Button(title) {}.focused($focus, equals: choice)",
    ]
    .join("\n");
    let prose = [
        "// focus = content.initialFocus",
        "let text = \".focused($focus, equals: choice)\"",
        "if placed != content.initialFocus { return }",
    ]
    .join("\n");
    if !agreement_focus_problems(&whole).is_empty() || agreement_focus_problems(&prose).len() != 2 {
        problems.push(
            "the scan finds a focus bound and set in code, and not one in prose, in a string, or only compared".into(),
        );
    }
    for problem in agreement_focus_problems(repo.source(AGREEMENT_SHEET)) {
        problems.push(format!("{}: {}", AGREEMENT_SHEET, problem));
    }
    problems
}

fn a_tools_detail_places_its_focus(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let whole = [
        ".onChange(of: focus) { _, placed in",
        "    if placed != detail.initialFocus { focus = detail.initialFocus }",
        "}",
        "Toggle(title, isOn: on).focused($focus, equals: .setting(setting.id))",
        "field.focused($focus, equals: .setting(setting.id))",
        "Button(title) {}.focused($focus, equals: .close)",
    ]
    .join("\n");
    let prose = [
        "// focus = detail.initialFocus",
        "let text = \".focused($focus, equals: .close)\"",
        "if placed != detail.initialFocus { return }",
        "field.focused($focus, equals: .setting(setting.id))",
    ]
    .join("\n");
    if !detail_focus_problems(&whole).is_empty() || detail_focus_problems(&prose).len() != 3 {
        problems.push(
            "the scan finds a detail's focus bound and set in code, and not one in prose, in a string, only compared, or bound for one kind of setting alone".into(),
        );
    }
    for problem in detail_focus_problems(repo.source(TOOLS_SECTION)) {
        problems.push(format!("{}: {}", TOOLS_SECTION, problem));
    }
    problems
}

fn modification_log_is_whole(repo: &Repository) -> Vec<String> {
    let mut problems = Vec::new();
    let sections: String = UPSTREAM_SECTIONS
        .iter()
        .map(|s| format!("\n{}\n\ntext\n", s))
        .collect();
    let whole = sections.replace(
        "\n## Modifications\n\ntext\n",
        "\n## Modifications\n\n- **2026-01-02**: one\n  - detail\n- **2026-01-01**: two\n",
    );
    let cut = whole.replace("- **2026-01-01**: two\n", "");
    if !modification_log_problems(&whole, 2).is_empty()
        || modification_log_problems(&cut, 2).len() != 1
        || modification_log_problems(&format!("{}<<<<<<< HEAD\n", whole), 2).len() != 1
        || modification_log_problems(&whole.replace("\n## What the import left out\n", "\n"), 2)
            .len()
            != 1
    {
        problems.push("the self-check no longer tells a whole log from a cut one".into());
    }
    let found = modification_log_problems(&repo.upstream, MODIFICATION_LOG_FLOOR);
    if !found.is_empty() {
        problems.push(format!(
            "UPSTREAM.md lost part of itself; restore it from main and add your entry again: {:?}",
            found
        ));
    }
    problems
}

pub fn problems(repo: &Repository) -> Vec<String> {
    let mut found = Vec::new();
    for (name, rule_fn) in RULES {
        for p in rule_fn(repo) {
            found.push(format!("{}: {}", name, p));
        }
    }
    found
}

pub fn run_cli(args: &[String]) -> i32 {
    let mut app_dir: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--app-dir" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--app-dir requires a value");
                    return 2;
                }
                app_dir = Some(PathBuf::from(&args[i]));
            }
            "-h" | "--help" => {
                println!("Usage: source_lints [--app-dir <path>]");
                return 0;
            }
            other => {
                eprintln!("unknown argument: {}", other);
                return 2;
            }
        }
        i += 1;
    }

    let resolved_dir = app_dir.unwrap_or_else(|| {
        if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
            PathBuf::from(ws).join("apps/desktop/vitruvian")
        } else {
            let candidate = Path::new("apps/desktop/vitruvian");
            if candidate.join("Sources").is_dir() {
                candidate.to_path_buf()
            } else {
                PathBuf::from(".")
            }
        }
    });

    let repo = Repository::new(&resolved_dir);
    let found = problems(&repo);
    for p in &found {
        eprintln!("{}", p);
    }
    if !found.is_empty() {
        return 1;
    }
    println!(
        "{} source rules hold across {} Swift files",
        RULES.len(),
        repo.swift_paths.len()
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_56_rules_registered() {
        assert_eq!(RULES.len(), 56);
    }

    #[test]
    fn test_helpers_and_scanners() {
        let sample = [
            "mkdir -p build/stage",
            "cp \"${PKG}/build/x\" dist/",
            "./build/run",
            "ls /usr/build/ Tools/MakeDMGBackground.swift",
        ]
        .join("\n");
        assert_eq!(
            relative_path_roots(&sample),
            vec!["build", "build", "dist", "build", "Tools"]
        );

        let (w, b) = code_and_blanked("let x = \"hello\" // comment");
        assert_eq!(w, "let x = \"hello\" ");
        assert_eq!(b, "let x = \"     \" ");
    }

    #[test]
    fn test_live_vitruvian_repository_passes_all_56_rules() {
        let candidate = Path::new("apps/desktop/vitruvian");
        let app_dir = if candidate.join("Sources").is_dir() {
            candidate.to_path_buf()
        } else {
            PathBuf::from(".")
        };
        assert!(
            app_dir.join("Sources").is_dir(),
            "Sources directory not found under {:?}",
            app_dir
        );
        let repo = Repository::new(&app_dir);
        let found = problems(&repo);
        assert!(
            found.is_empty(),
            "expected 0 source lint problems, got: {:?}",
            found
        );
    }
}
