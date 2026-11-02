// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Each plugin is installed (and gh-watch exported) as its own folder, so the
//! files every plugin shares are copied into each one rather than referenced.
//! This keeps the copies identical: change one, change them all.
//!
//! The files come from BUILD in $CONFORMANCE_FILES (every plugin's
//! :conformance_files). For each shared path below, every plugin's copy must
//! match the first one given.

use std::fs;

/// Path inside a plugin, and how many copies must exist (0: any number).
const SHARED: &[(&str, usize)] = &[
    ("hooks/rust-hook.sh", 9),
    ("hooks/rust-hook_test.sh", 9),
    ("hooks/src/json.rs", 0),
];

/// Whether `path` is `<anything>/plugins/<plugin...>/<rel>`.
fn is_copy_of(path: &str, rel: &str) -> bool {
    match path.find("/plugins/") {
        Some(i) => path[i + "/plugins/".len()..].ends_with(&format!("/{rel}")),
        None => false,
    }
}

/// Every mismatch among `files` (path, contents) for the shared paths.
fn shared_problems(files: &[(String, Vec<u8>)]) -> Vec<String> {
    let mut out = Vec::new();
    for &(rel, want) in SHARED {
        let copies: Vec<&(String, Vec<u8>)> =
            files.iter().filter(|(p, _)| is_copy_of(p, rel)).collect();
        if let Some((first, first_bytes)) = copies.first() {
            for (path, bytes) in &copies[1..] {
                if bytes != first_bytes {
                    out.push(format!("{path} differs from {first}"));
                }
            }
        }
        if want != 0 && copies.len() != want {
            out.push(format!(
                "{rel}: {} copies, want one in each of the {want} plugins",
                copies.len()
            ));
        }
    }
    out
}

#[test]
fn every_shared_file_is_identical_in_every_plugin() {
    let list = std::env::var("CONFORMANCE_FILES")
        .expect("CONFORMANCE_FILES is set by BUILD to every plugin's :conformance_files");
    let files: Vec<(String, Vec<u8>)> = list
        .split_whitespace()
        .map(|p| {
            let bytes = fs::read(p).unwrap_or_else(|e| panic!("{p}: {e}"));
            (p.to_string(), bytes)
        })
        .collect();
    let problems = shared_problems(&files);
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn the_check_flags_a_differing_copy_and_a_missing_one() {
    let copy = |plugin: &str, rel: &str, body: &str| {
        (
            format!("a/plugins/{plugin}/{rel}"),
            body.as_bytes().to_vec(),
        )
    };
    let mut files: Vec<(String, Vec<u8>)> = (0..9)
        .flat_map(|i| {
            let p = format!("p{i}");
            vec![
                copy(&p, "hooks/rust-hook.sh", "launcher"),
                copy(&p, "hooks/rust-hook_test.sh", "test"),
            ]
        })
        .collect();
    files.push(copy("p0", "hooks/src/json.rs", "json"));
    files.push(copy("p1", "hooks/src/json.rs", "json"));
    assert_eq!(shared_problems(&files), Vec::<String>::new());

    let mut drifted = files.clone();
    drifted[2].1 = b"launcher, edited".to_vec();
    let problems = shared_problems(&drifted);
    assert_eq!(problems.len(), 1, "{problems:?}");
    assert!(
        problems[0].contains("p1/hooks/rust-hook.sh differs"),
        "{problems:?}"
    );

    let mut drifted_json = files.clone();
    drifted_json.last_mut().unwrap().1 = b"json, edited".to_vec();
    assert_eq!(shared_problems(&drifted_json).len(), 1);

    files.remove(0);
    let problems = shared_problems(&files);
    assert_eq!(
        problems,
        vec!["hooks/rust-hook.sh: 8 copies, want one in each of the 9 plugins"]
    );
}
