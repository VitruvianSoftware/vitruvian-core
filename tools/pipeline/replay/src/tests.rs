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

use super::*;
use std::fs;
use std::path::{Path, PathBuf};

fn v(s: &[&str]) -> Vec<String> {
    s.iter().map(|x| x.to_string()).collect()
}

const SUITE_BUILD: &str = r#"
pipeline_unit(
    name = "suite-macos",
    runner = "xcode-27",
    test_targets = ["//suite/desktop:desktop_test"],
)

pipeline_unit(
    name = "suite-android",
    test_targets = ["//suite/android:android_test"],
)
"#;

fn repo(tag: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let d = base.join(format!("replay-{tag}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&d);
    let w = |rel: &str, c: &str| {
        let p: &Path = &d.join(rel);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, c).unwrap();
    };
    w("suite/BUILD", SUITE_BUILD);
    for pkg in ["suite/android", "suite/core", "suite/desktop"] {
        w(&format!("{pkg}/BUILD"), "");
    }
    d
}

fn map() -> RdepsMap {
    let mut tests = BTreeMap::new();
    tests.insert(
        "suite/android".to_string(),
        v(&["//suite/android:android_test"]),
    );
    tests.insert(
        "suite/core".to_string(),
        v(&[
            "//suite/android:android_test",
            "//suite/desktop:desktop_test",
        ]),
    );
    tests.insert(
        "suite/desktop".to_string(),
        v(&["//suite/desktop:desktop_test"]),
    );
    let mut up = BTreeMap::new();
    up.insert(
        "suite-macos".to_string(),
        v(&["suite/core", "suite/desktop"]),
    );
    RdepsMap {
        schema: plan::RDEPS_MAP_SCHEMA,
        commit: "abc".into(),
        packages: Some(v(&[
            "suite",
            "suite/android",
            "suite/core",
            "suite/desktop",
        ])),
        tests: Some(tests),
        unit_packages: Some(up),
    }
}

#[test]
fn an_android_only_change_wakes_the_mac_unit_only_under_the_old_rule() {
    let d = repo("android");
    let o = replay_one(d.to_str().unwrap(), &map(), v(&["suite/android/Main.kt"]));
    assert_eq!(
        o,
        Outcome::Planned {
            old: v(&["suite-macos"]),
            new: vec![]
        }
    );
}

#[test]
fn shared_code_wakes_the_mac_unit_under_both_rules() {
    let d = repo("core");
    let o = replay_one(d.to_str().unwrap(), &map(), v(&["suite/core/lib.rs"]));
    assert_eq!(
        o,
        Outcome::Planned {
            old: v(&["suite-macos"]),
            new: v(&["suite-macos"])
        }
    );
}

#[test]
fn a_package_the_map_does_not_know_is_skipped_not_guessed() {
    let d = repo("unknown");
    fs::create_dir_all(d.join("suite/brand_new")).unwrap();
    fs::write(d.join("suite/brand_new/BUILD"), "").unwrap();
    let o = replay_one(d.to_str().unwrap(), &map(), v(&["suite/brand_new/x.rs"]));
    assert!(matches!(o, Outcome::Skipped(_)), "{o:?}");
}

#[test]
fn a_global_change_is_skipped() {
    let d = repo("global");
    let o = replay_one(d.to_str().unwrap(), &map(), v(&["MODULE.bazel"]));
    assert!(matches!(o, Outcome::Skipped(_)), "{o:?}");
}

#[test]
fn tally_counts_each_rule_and_flags_a_unit_only_the_new_rule_wakes() {
    let r = vec![
        (
            "a".to_string(),
            Outcome::Planned {
                old: v(&["x", "y"]),
                new: v(&["x"]),
            },
        ),
        (
            "b".to_string(),
            Outcome::Planned {
                old: v(&["x"]),
                new: v(&["x"]),
            },
        ),
        ("c".to_string(), Outcome::Skipped("live".into())),
    ];
    let t = tally(&r);
    assert_eq!((t.planned, t.skipped), (2, 1));
    assert_eq!(t.per_unit["x"], (2, 2));
    assert_eq!(t.per_unit["y"], (1, 0));
    assert!(t.new_only.is_empty());
    let bad = vec![(
        "z".to_string(),
        Outcome::Planned {
            old: vec![],
            new: v(&["u"]),
        },
    )];
    assert_eq!(tally(&bad).new_only, v(&["z: u"]));
    assert!(render(&tally(&bad)).contains("WARNING"));
}

#[test]
fn parse_files_drops_blank_lines() {
    assert_eq!(parse_files("a/b\n\n c \n"), v(&["a/b", "c"]));
}
