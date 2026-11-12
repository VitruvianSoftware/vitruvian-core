// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Which CPUs a Mach-O file runs on, as `lipo -archs` prints them, and what a
//! release needs of the app and the engine it bundles.

use std::path::Path;
use std::process::Command;

/// The CPUs a release is built for. Every DMG the release makes is cut from
/// an app that has both.
pub const RELEASE_ARCHS: [&str; 2] = ["arm64", "x86_64"];

/// The architectures in `lipo -archs` output ("x86_64 arm64\n"), sorted.
pub fn parse_lipo_archs(output: &str) -> Vec<String> {
    let mut archs: Vec<String> = output.split_whitespace().map(str::to_string).collect();
    archs.sort();
    archs.dedup();
    archs
}

/// The architectures `wanted` names that `have` lacks, in `wanted`'s order.
pub fn missing<'a>(wanted: &[&'a str], have: &[String]) -> Vec<&'a str> {
    wanted
        .iter()
        .copied()
        .filter(|w| !have.iter().any(|h| h == w))
        .collect()
}

/// The architectures in the app binary that the engine lacks. A one-CPU
/// development build passes (both are arm64); a universal app whose engine was
/// built for one CPU does not, because on the other CPU the app would start
/// and its engine would not.
pub fn engine_lacks<'a>(app: &'a [String], engine: &[String]) -> Vec<&'a str> {
    app.iter()
        .map(String::as_str)
        .filter(|a| !engine.iter().any(|e| e == a))
        .collect()
}

/// Runs `lipo -archs` on `path`.
pub fn read(path: &Path) -> Result<Vec<String>, String> {
    let out = Command::new("lipo")
        .arg("-archs")
        .arg(path)
        .output()
        .map_err(|e| format!("cannot run lipo: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "lipo -archs {} failed: {}",
            path.display(),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(parse_lipo_archs(&String::from_utf8_lossy(&out.stdout)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_lipo_output_sorted() {
        assert_eq!(parse_lipo_archs("x86_64 arm64\n"), vec!["arm64", "x86_64"]);
        assert_eq!(parse_lipo_archs("arm64\n"), vec!["arm64"]);
        assert!(parse_lipo_archs("").is_empty());
    }

    #[test]
    fn missing_names_what_is_not_there() {
        let have = parse_lipo_archs("arm64");
        assert_eq!(missing(&RELEASE_ARCHS, &have), vec!["x86_64"]);
        let both = parse_lipo_archs("arm64 x86_64");
        assert!(missing(&RELEASE_ARCHS, &both).is_empty());
    }

    #[test]
    fn a_universal_app_with_a_one_cpu_engine_is_caught() {
        let app = parse_lipo_archs("x86_64 arm64");
        let engine = parse_lipo_archs("arm64");
        assert_eq!(engine_lacks(&app, &engine), vec!["x86_64"]);
    }

    #[test]
    fn a_one_cpu_development_build_passes() {
        let app = parse_lipo_archs("arm64");
        let engine = parse_lipo_archs("arm64");
        assert!(engine_lacks(&app, &engine).is_empty());
    }
}
