// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Which engine each app bundles: the released Courier's engine must hold no seed code (the made-up chats the test
//! copy can open with), and the test copy's must hold it. The seed package's `Marker` constant
//! (engine/internal/seed/seed.go) is a string only that code holds, so its presence in a binary says the binary links
//! the seed player.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The value of `const Marker = "..."` in the seed package's source.
pub fn marker_from_source(src: &str) -> Option<String> {
    src.lines().find_map(|line| {
        let rest = line.trim().strip_prefix("const Marker = \"")?;
        let end = rest.find('"')?;
        let marker = &rest[..end];
        (!marker.is_empty()).then(|| marker.to_string())
    })
}

/// Whether `needle` occurs in `haystack`.
pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && haystack.windows(needle.len()).any(|w| w == needle)
}

/// The arguments: the seed source, then `--release PATH...` (the :Courier rootpaths) and `--test-copy PATH...` (the
/// :CourierTestCopy rootpaths).
pub fn split_args(args: &[String]) -> Result<(PathBuf, Vec<String>, Vec<String>), String> {
    let source = args.get(1).ok_or("no seed source given")?;
    let (mut release, mut test_copy) = (Vec::new(), Vec::new());
    let mut into: Option<&mut Vec<String>> = None;
    for a in &args[2..] {
        match a.as_str() {
            "--release" => into = Some(&mut release),
            "--test-copy" => into = Some(&mut test_copy),
            _ => match into.as_mut() {
                Some(v) => v.push(a.clone()),
                None => return Err(format!("{} comes before --release or --test-copy", a)),
            },
        }
    }
    if release.is_empty() || test_copy.is_empty() {
        return Err("both --release and --test-copy need paths".to_string());
    }
    Ok((PathBuf::from(source), release, test_copy))
}

/// The bundled engine of the app among `paths` (an .app folder, or its .zip, unzipped under `dest`).
fn bundled_engine(paths: &[String], dest: &Path) -> Result<PathBuf, String> {
    let mut app: Option<PathBuf> = paths
        .iter()
        .map(PathBuf::from)
        .find(|p| p.extension().is_some_and(|e| e == "app") && p.is_dir());
    if app.is_none() {
        let archive = paths
            .iter()
            .map(|p| {
                if p.ends_with(".zip") {
                    PathBuf::from(p)
                } else {
                    PathBuf::from(format!("{}.zip", p))
                }
            })
            .find(|p| p.exists())
            .ok_or_else(|| format!("no .app or .zip among {}", paths.join(" ")))?;
        let _ = fs::remove_dir_all(dest);
        let status = Command::new("/usr/bin/unzip")
            .arg("-q")
            .arg(&archive)
            .arg("-d")
            .arg(dest)
            .status()
            .map_err(|e| format!("unzip: {}", e))?;
        if !status.success() {
            return Err(format!("unzip failed on {}", archive.display()));
        }
        app = fs::read_dir(dest)
            .map_err(|e| e.to_string())?
            .filter_map(|e| e.ok().map(|e| e.path()))
            .find(|p| p.extension().is_some_and(|e| e == "app"));
    }
    let app = app.ok_or_else(|| format!("no .app in {}", paths.join(" ")))?;
    let engine = app.join("Contents/Helpers/courier-engine");
    if engine.is_file() {
        Ok(engine)
    } else {
        Err(format!(
            "{} has no Contents/Helpers/courier-engine",
            app.display()
        ))
    }
}

pub fn run(args: &[String]) -> i32 {
    let (source, release, test_copy) = match split_args(args) {
        Ok(v) => v,
        Err(msg) => {
            eprintln!(
                "Usage: release-engine-has-no-seed <seed.go> --release PATH... --test-copy PATH...\n{}",
                msg
            );
            return 2;
        }
    };
    let marker = match fs::read_to_string(&source)
        .ok()
        .as_deref()
        .and_then(marker_from_source)
    {
        Some(m) => m,
        None => {
            eprintln!("FAIL: no `const Marker = \"...\"` in {}", source.display());
            return 2;
        }
    };
    let tmp = PathBuf::from(env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".to_string()));
    let mut failed = 0;
    for (label, paths, want) in [
        ("the released app (:Courier)", &release, false),
        ("the test copy (:CourierTestCopy)", &test_copy, true),
    ] {
        let dest = tmp.join(if want { "test-copy" } else { "release" });
        let bytes = match bundled_engine(paths, &dest)
            .and_then(|e| fs::read(&e).map_err(|err| format!("read {}: {}", e.display(), err)))
        {
            Ok(b) => b,
            Err(msg) => {
                eprintln!("FAIL: {}: {}", label, msg);
                failed = 1;
                continue;
            }
        };
        let has = contains(&bytes, marker.as_bytes());
        match (has, want) {
            (false, false) => println!("ok: {}'s engine holds no seed code", label),
            (true, true) => println!("ok: {}'s engine holds the seed player", label),
            (true, false) => {
                eprintln!(
                    "FAIL: {}'s engine holds the seed player ({:?}): it must bundle courier-engine, not courier-engine-seeded",
                    label, marker
                );
                failed = 1;
            }
            (false, true) => {
                eprintln!(
                    "FAIL: {}'s engine lacks the seed player ({:?}): it must bundle courier-engine-seeded",
                    label, marker
                );
                failed = 1;
            }
        }
    }
    failed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_marker_from_the_source() {
        let src = "package seed\n\n// Marker is ...\nconst Marker = \"courier-seed-player:abc\"\n";
        assert_eq!(
            marker_from_source(src),
            Some("courier-seed-player:abc".to_string())
        );
        assert_eq!(marker_from_source("const Other = \"x\""), None);
        assert_eq!(marker_from_source("const Marker = \"\""), None);
    }

    #[test]
    fn finds_bytes() {
        assert!(contains(
            b"..\x00courier-seed-player:abc\x00..",
            b"courier-seed-player:abc"
        ));
        assert!(!contains(
            b"courier-seed-player:ab",
            b"courier-seed-player:abc"
        ));
        assert!(!contains(b"anything", b""));
    }

    #[test]
    fn splits_the_two_apps_paths() {
        let args: Vec<String> = [
            "t",
            "seed.go",
            "--release",
            "a.zip",
            "--test-copy",
            "b.zip",
            "b",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        let (src, rel, tc) = split_args(&args).unwrap();
        assert_eq!(src, PathBuf::from("seed.go"));
        assert_eq!(rel, vec!["a.zip"]);
        assert_eq!(tc, vec!["b.zip", "b"]);
        let missing: Vec<String> = ["t", "seed.go", "--release", "a.zip"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert!(split_args(&missing).is_err());
    }
}
