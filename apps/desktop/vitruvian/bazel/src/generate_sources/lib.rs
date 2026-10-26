// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Generate the test sources that list what the app declares.
//!
//! Native Rust counterpart to `Tests/generate_sources.py`. Extracts every
//! `FeatureStrings` language factory from `Sources/Vitruvian/Core/*Strings.swift`
//! and writes `LocalizationCatalog.swift` to the output directory while pruning
//! stale `*.swift` files.

use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Config {
    pub app_dir: PathBuf,
    pub output_dir: Option<PathBuf>,
}

pub fn default_app_dir() -> PathBuf {
    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        PathBuf::from(ws).join("apps/desktop/vitruvian")
    } else if Path::new("apps/desktop/vitruvian/Sources/Vitruvian/Core").is_dir() {
        PathBuf::from("apps/desktop/vitruvian")
    } else {
        env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
    }
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut app_dir = None;
    let mut output_dir = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--app-dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--app-dir requires a value".into());
                }
                app_dir = Some(PathBuf::from(&args[i]));
            }
            "--output-dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--output-dir requires a value".into());
                }
                output_dir = Some(PathBuf::from(&args[i]));
            }
            "-h" | "--help" => {
                return Err(
                    "usage: generate_sources [--app-dir <folder>] [--output-dir <folder>]".into(),
                );
            }
            other => return Err(format!("unknown argument: {}", other)),
        }
        i += 1;
    }
    let resolved_app_dir = app_dir.unwrap_or_else(default_app_dir);
    Ok(Config {
        app_dir: resolved_app_dir,
        output_dir,
    })
}

fn is_ident_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Extract all `FeatureStrings` scopes matching `(?:extension|enum) FeatureStrings \{(.*?)^\}`
/// with `re.S | re.M` semantics (non-greedy up to a `}` at the start of a line).
pub fn extract_feature_strings_scopes(source: &str) -> Vec<&str> {
    let mut scopes = Vec::new();
    let prefixes = ["extension FeatureStrings {", "enum FeatureStrings {"];
    let mut pos = 0;
    while pos < source.len() {
        let rest = &source[pos..];
        let mut next_match: Option<(usize, usize)> = None;
        for prefix in prefixes {
            if let Some(idx) = rest.find(prefix) {
                let abs_idx = pos + idx;
                let body_start = abs_idx + prefix.len();
                match next_match {
                    None => next_match = Some((abs_idx, body_start)),
                    Some((best_idx, _)) if abs_idx < best_idx => {
                        next_match = Some((abs_idx, body_start))
                    }
                    _ => {}
                }
            }
        }
        let Some((_, body_start)) = next_match else {
            break;
        };
        // Find the first `}` at the beginning of a line (either at body_start if it's at line start,
        // or immediately following `\n`).
        let body_rest = &source[body_start..];
        let mut end_offset = None;
        if body_rest.starts_with('}')
            && (body_start == 0 || source.as_bytes()[body_start - 1] == b'\n')
        {
            end_offset = Some(0);
        } else if let Some(nl_brace) = body_rest.find("\n}") {
            // `.*?` before `^}` in Python `re.S | re.M` includes the newline before `}`!
            end_offset = Some(nl_brace + 1);
        }
        if let Some(off) = end_offset {
            scopes.push(&body_rest[..off]);
            pos = body_start + off + 1;
        } else {
            break;
        }
    }
    scopes
}

/// Match `static\s+func\s+(\w+)\s*\(\s*_\s+\w+:\s*AppLanguage\s*\)\s*->` inside `scope`.
pub fn extract_factory_names_from_scope(scope: &str) -> Vec<String> {
    let mut names = Vec::new();
    let bytes = scope.as_bytes();
    let len = bytes.len();
    let mut i = 0;

    while i < len {
        // Look for "static"
        let Some(rel) = scope[i..].find("static") else {
            break;
        };
        let start = i + rel;
        let mut p = start + "static".len();

        // Require `\s+`
        let ws_start = p;
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }
        if p == ws_start {
            i = start + 1;
            continue;
        }

        // Require `func`
        if !scope[p..].starts_with("func") {
            i = start + 1;
            continue;
        }
        p += "func".len();

        // Require `\s+`
        let ws2_start = p;
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }
        if p == ws2_start {
            i = start + 1;
            continue;
        }

        // Capture `(\w+)`
        let name_start = p;
        while p < len && is_ident_char(bytes[p]) {
            p += 1;
        }
        if p == name_start {
            i = start + 1;
            continue;
        }
        let fn_name = &scope[name_start..p];

        // `\s*`
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }

        // `\(`
        if p >= len || bytes[p] != b'(' {
            i = start + 1;
            continue;
        }
        p += 1;

        // `\s*`
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }

        // `_`
        if p >= len || bytes[p] != b'_' {
            i = start + 1;
            continue;
        }
        p += 1;

        // `\s+`
        let ws3_start = p;
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }
        if p == ws3_start {
            i = start + 1;
            continue;
        }

        // `\w+`
        let param_start = p;
        while p < len && is_ident_char(bytes[p]) {
            p += 1;
        }
        if p == param_start {
            i = start + 1;
            continue;
        }

        // `:`
        if p >= len || bytes[p] != b':' {
            i = start + 1;
            continue;
        }
        p += 1;

        // `\s*`
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }

        // `AppLanguage`
        if !scope[p..].starts_with("AppLanguage") {
            i = start + 1;
            continue;
        }
        p += "AppLanguage".len();

        // `\s*`
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }

        // `\)`
        if p >= len || bytes[p] != b')' {
            i = start + 1;
            continue;
        }
        p += 1;

        // `\s*`
        while p < len && bytes[p].is_ascii_whitespace() {
            p += 1;
        }

        // `->`
        if !scope[p..].starts_with("->") {
            i = start + 1;
            continue;
        }
        p += "->".len();

        names.push(fn_name.to_string());
        i = p;
    }

    names
}

pub fn collect_factories(app_dir: &Path) -> Result<Vec<String>, String> {
    let core_dir = app_dir.join("Sources/Vitruvian/Core");
    let entries = fs::read_dir(&core_dir)
        .map_err(|e| format!("failed to read {}: {}", core_dir.display(), e))?;
    let mut paths: Vec<PathBuf> = entries
        .filter_map(|e| e.ok().map(|x| x.path()))
        .filter(|p| {
            p.is_file()
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| n.ends_with("Strings.swift"))
                    .unwrap_or(false)
        })
        .collect();
    paths.sort();

    let mut factories = Vec::new();
    for path in paths {
        let source = fs::read_to_string(&path)
            .map_err(|e| format!("failed to read {}: {}", path.display(), e))?;
        if source.contains("extension FeatureStrings") || source.contains("enum FeatureStrings") {
            let scopes = extract_feature_strings_scopes(&source);
            let mut names = Vec::new();
            for scope in scopes {
                names.extend(extract_factory_names_from_scope(scope));
            }
            if names.is_empty() {
                return Err(format!("No language factory found in {}", path.display()));
            }
            factories.extend(names);
        }
    }

    let unique: BTreeSet<&String> = factories.iter().collect();
    if factories.is_empty() || factories.len() != unique.len() {
        return Err("Missing or duplicate localization factories".into());
    }

    Ok(factories)
}

pub fn render_localization_catalog(factories: &[String]) -> String {
    let mut out = String::from(
        "extension LocalizationTests {\nstatic let factories: [(String, (AppLanguage) -> Any)] = [\n",
    );
    for name in factories {
        out.push_str(&format!(
            "(\"{}\", {{ FeatureStrings.{}($0) }}),\n",
            name, name
        ));
    }
    out.push_str("]\n}\n");
    out
}

pub fn generate(app_dir: &Path, output_dir: &Path) -> Result<Vec<String>, String> {
    fs::create_dir_all(output_dir)
        .map_err(|e| format!("failed to create {}: {}", output_dir.display(), e))?;
    let factories = collect_factories(app_dir)?;
    let catalog_text = render_localization_catalog(&factories);

    let mut written = BTreeSet::new();
    let catalog_name = "LocalizationCatalog.swift";
    written.insert(catalog_name.to_string());

    let catalog_path = output_dir.join(catalog_name);
    let needs_write = match fs::read_to_string(&catalog_path) {
        Ok(existing) => existing != catalog_text,
        Err(_) => true,
    };
    if needs_write {
        fs::write(&catalog_path, &catalog_text)
            .map_err(|e| format!("failed to write {}: {}", catalog_path.display(), e))?;
    }

    // Remove stale *.swift files not in `written`.
    if let Ok(entries) = fs::read_dir(output_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                    if name.ends_with(".swift") && !written.contains(name) {
                        let _ = fs::remove_file(&path);
                    }
                }
            }
        }
    }

    Ok(written.into_iter().collect())
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    let output_dir = config
        .output_dir
        .unwrap_or_else(|| config.app_dir.join("build/generated-tests"));
    match generate(&config.app_dir, &output_dir) {
        Ok(_) => 0,
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    #[test]
    fn test_extract_factories_and_prune_stale_files() {
        let tmp = env::temp_dir().join("test_vitruvian_generate_sources_rs_unit");
        let _ = fs::remove_dir_all(&tmp);
        let core_dir = tmp.join("Sources/Vitruvian/Core");
        let out_dir = tmp.join("build/generated-tests");
        fs::create_dir_all(&core_dir).unwrap();
        fs::create_dir_all(&out_dir).unwrap();

        fs::write(
            core_dir.join("AlphaStrings.swift"),
            "extension FeatureStrings {\n    static func alpha(_ language: AppLanguage) -> AlphaStrings {\n        AlphaStrings()\n    }\n}\n",
        )
        .unwrap();
        fs::write(
            core_dir.join("BetaStrings.swift"),
            "enum FeatureStrings {\n    static func beta(_ lang: AppLanguage) -> BetaStrings {\n        BetaStrings()\n    }\n}\n",
        )
        .unwrap();
        fs::write(out_dir.join("StaleCopy.swift"), "// stale\n").unwrap();

        let written = generate(&tmp, &out_dir).unwrap();
        assert_eq!(written, vec!["LocalizationCatalog.swift"]);
        assert!(!out_dir.join("StaleCopy.swift").exists());

        let content = fs::read_to_string(out_dir.join("LocalizationCatalog.swift")).unwrap();
        assert_eq!(
            content,
            "extension LocalizationTests {\nstatic let factories: [(String, (AppLanguage) -> Any)] = [\n(\"alpha\", { FeatureStrings.alpha($0) }),\n(\"beta\", { FeatureStrings.beta($0) }),\n]\n}\n"
        );

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_missing_or_duplicate_factories_rejected() {
        let tmp = env::temp_dir().join("test_vitruvian_generate_sources_rs_err");
        let _ = fs::remove_dir_all(&tmp);
        let core_dir = tmp.join("Sources/Vitruvian/Core");
        let out_dir = tmp.join("build/generated-tests");
        fs::create_dir_all(&core_dir).unwrap();

        // Empty FeatureStrings extension -> error
        fs::write(
            core_dir.join("EmptyStrings.swift"),
            "extension FeatureStrings {\n}\n",
        )
        .unwrap();
        let err = generate(&tmp, &out_dir).unwrap_err();
        assert!(err.contains("No language factory found"), "got: {}", err);

        // Duplicate factory names -> error
        fs::remove_file(core_dir.join("EmptyStrings.swift")).unwrap();
        fs::write(
            core_dir.join("AStrings.swift"),
            "extension FeatureStrings {\n    static func dup(_ language: AppLanguage) -> Int { 1 }\n}\n",
        )
        .unwrap();
        fs::write(
            core_dir.join("BStrings.swift"),
            "extension FeatureStrings {\n    static func dup(_ language: AppLanguage) -> Int { 2 }\n}\n",
        )
        .unwrap();
        let err2 = generate(&tmp, &out_dir).unwrap_err();
        assert_eq!(err2, "Missing or duplicate localization factories");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_parity_with_python_generate_sources() {
        let app_dir = Path::new("apps/desktop/vitruvian");
        if !app_dir.join("Tests/generate_sources.py").exists() {
            return;
        }
        let tmp = env::temp_dir().join("test_vitruvian_generate_sources_parity");
        let _ = fs::remove_dir_all(&tmp);

        let py_root = tmp.join("py_root");
        let rs_out = tmp.join("rs_out");
        fs::create_dir_all(py_root.join("Tests")).unwrap();
        fs::copy(
            app_dir.join("Tests/generate_sources.py"),
            py_root.join("Tests/generate_sources.py"),
        )
        .unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(
            fs::canonicalize(app_dir.join("Sources")).unwrap(),
            py_root.join("Sources"),
        )
        .unwrap();

        let status = Command::new("python3")
            .arg(py_root.join("Tests/generate_sources.py"))
            .status()
            .expect("failed to run python3");
        assert!(status.success(), "python3 generate_sources.py failed");

        generate(app_dir, &rs_out).unwrap();

        let py_catalog =
            fs::read_to_string(py_root.join("build/generated-tests/LocalizationCatalog.swift"))
                .unwrap();
        let rs_catalog = fs::read_to_string(rs_out.join("LocalizationCatalog.swift")).unwrap();
        assert_eq!(
            rs_catalog, py_catalog,
            "Rust generate_sources output must be byte-for-byte identical to Python generate_sources.py"
        );
        assert!(rs_catalog.lines().count() > 50);

        let _ = fs::remove_dir_all(&tmp);
    }
}
