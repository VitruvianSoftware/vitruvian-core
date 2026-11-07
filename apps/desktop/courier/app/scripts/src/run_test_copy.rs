// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Runs the test copy of Courier (`:CourierTestCopy`): a real build, with its own bundle identifier, in its own data
//! folder, so a change can be tried by hand or by a script without touching the installed Courier, its data in
//! ~/Library/Application Support/Courier, or its Keychain items.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The test copy's bundle identifier, as BUILD and CourierCore's `TestCopy` give it.
pub const BUNDLE_ID: &str = "com.vitruviansoftware.courier.dev";
/// The app's name in the archive.
pub const APP_NAME: &str = "Courier Test Copy.app";

/// The archive among Bazel's `rootpaths` (the .zip, or a path with a .zip beside it).
pub fn resolve_archive(candidates: &str) -> Option<PathBuf> {
    let mut chosen: Option<PathBuf> = None;
    for candidate in candidates.split_whitespace() {
        if candidate.ends_with(".zip") {
            chosen = Some(PathBuf::from(candidate));
        } else if chosen.is_none() {
            let zip = format!("{}.zip", candidate);
            if Path::new(&zip).exists() {
                chosen = Some(PathBuf::from(zip));
            }
        }
    }
    chosen
}

/// Whether `data` is the installed Courier's data folder (or inside it), which the test copy must never use.
pub fn is_installed_apps_data(data: &Path, home: &Path) -> bool {
    let real = home.join("Library/Application Support/Courier");
    let normalized =
        |p: &Path| -> PathBuf { fs::canonicalize(p).unwrap_or_else(|_| p.components().collect()) };
    normalized(data).starts_with(normalized(&real))
}

fn bundle_identifier(app: &Path) -> Option<String> {
    let out = Command::new("/usr/bin/plutil")
        .args(["-extract", "CFBundleIdentifier", "raw", "-o", "-"])
        .arg(app.join("Contents/Info.plist"))
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// What `run` was asked to do. Bazel puts the archive first and `--scenarios PATH...` (the seed files) next; the
/// rest is the person's: `--data DIR`, `--seed NAME`, `--no-open`.
#[derive(Debug, Default, PartialEq)]
pub struct Options {
    pub archive: String,
    pub scenarios: Vec<PathBuf>,
    pub data: Option<PathBuf>,
    pub seed: Option<String>,
    pub open: bool,
}

pub const USAGE: &str =
    "Usage: run_test_copy <CourierTestCopy.zip> [--scenarios FILE...] [--data DIR] [--seed NAME] [--no-open]";

pub fn parse_args(args: &[String]) -> Result<Options, String> {
    if args.len() < 2 {
        return Err(USAGE.to_string());
    }
    let mut opts = Options {
        archive: args[1].clone(),
        open: true,
        ..Options::default()
    };
    let mut i = 2;
    while i < args.len() {
        match args[i].as_str() {
            "--scenarios" => {
                while i + 1 < args.len() && !args[i + 1].starts_with("--") {
                    i += 1;
                    opts.scenarios.push(PathBuf::from(&args[i]));
                }
            }
            "--data" if i + 1 < args.len() => {
                i += 1;
                opts.data = Some(PathBuf::from(&args[i]));
            }
            "--seed" if i + 1 < args.len() => {
                i += 1;
                opts.seed = Some(args[i].clone());
            }
            "--no-open" => opts.open = false,
            other => return Err(format!("unknown argument {}\n{}", other, USAGE)),
        }
        i += 1;
    }
    Ok(opts)
}

/// The scenario names among `scenarios` (each file's name without `.json`), sorted.
pub fn scenario_names(scenarios: &[PathBuf]) -> Vec<String> {
    let mut names: Vec<String> = scenarios
        .iter()
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .filter_map(|p| p.file_stem().map(|s| s.to_string_lossy().to_string()))
        .collect();
    names.sort();
    names.dedup();
    names
}

/// The file of the scenario `name` among `scenarios`, or an error that lists the ones there are.
pub fn find_scenario(scenarios: &[PathBuf], name: &str) -> Result<PathBuf, String> {
    scenarios
        .iter()
        .find(|p| {
            p.extension().is_some_and(|e| e == "json") && p.file_stem().is_some_and(|s| s == name)
        })
        .cloned()
        .ok_or_else(|| {
            let names = scenario_names(scenarios);
            if names.is_empty() {
                format!(
                    "no seed scenario {:?}: none were passed in (--scenarios)",
                    name
                )
            } else {
                format!(
                    "no seed scenario {:?}; there are: {}",
                    name,
                    names.join(", ")
                )
            }
        })
}

/// The data folder to use, and whether to empty it first: --data as given (never emptied); else, with a seed,
/// `base/seed-NAME`, emptied on every run so the scenario plays into an empty folder; else `base/data`.
pub fn data_dir(base: &Path, data: Option<&Path>, seed: Option<&str>) -> (PathBuf, bool) {
    match (data, seed) {
        (Some(d), _) => (d.to_path_buf(), false),
        (None, Some(name)) => (base.join(format!("seed-{}", name)), true),
        (None, None) => (base.join("data"), false),
    }
}

pub fn run(args: &[String]) -> i32 {
    let opts = match parse_args(args) {
        Ok(o) => o,
        Err(msg) => {
            eprintln!("run_test_copy: {}", msg);
            return 2;
        }
    };
    let base = PathBuf::from(env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string()))
        .join("courier-test-copy");
    let seed_file = match &opts.seed {
        None => None,
        Some(name) => match find_scenario(&opts.scenarios, name) {
            // open's --env reaches the app from another directory: the path must be absolute.
            Ok(p) => Some(fs::canonicalize(&p).unwrap_or(p)),
            Err(msg) => {
                eprintln!("run_test_copy: {}", msg);
                return 2;
            }
        },
    };
    let (data, wipe) = data_dir(&base, opts.data.as_deref(), opts.seed.as_deref());
    let home = PathBuf::from(env::var("HOME").unwrap_or_default());
    if is_installed_apps_data(&data, &home) {
        eprintln!(
            "run_test_copy: {} is the installed Courier's data; give the test copy its own",
            data.display()
        );
        return 2;
    }
    let Some(archive) = resolve_archive(&opts.archive) else {
        eprintln!("run_test_copy: no CourierTestCopy.zip in {}", opts.archive);
        return 2;
    };

    let unpacked = base.join("app");
    let _ = fs::remove_dir_all(&unpacked);
    if wipe {
        let _ = fs::remove_dir_all(&data);
    }
    if fs::create_dir_all(&unpacked).is_err() || fs::create_dir_all(&data).is_err() {
        eprintln!(
            "run_test_copy: cannot make {} or {}",
            unpacked.display(),
            data.display()
        );
        return 1;
    }
    let unzipped = Command::new("/usr/bin/unzip")
        .arg("-q")
        .arg(&archive)
        .arg("-d")
        .arg(&unpacked)
        .status();
    if !unzipped.map(|s| s.success()).unwrap_or(false) {
        eprintln!("run_test_copy: unzip failed");
        return 1;
    }
    let app = unpacked.join(APP_NAME);
    match bundle_identifier(&app) {
        Some(id) if id == BUNDLE_ID => {}
        other => {
            eprintln!(
                "run_test_copy: {} has bundle identifier {:?}, not {}; refusing to run it",
                app.display(),
                other,
                BUNDLE_ID
            );
            return 1;
        }
    }
    println!("Test copy: {}", app.display());
    println!("Its data:  {}", data.display());
    if let Some(file) = &seed_file {
        println!("Seeded:    {}", file.display());
    }
    if !opts.open {
        return 0;
    }
    // -n: a new instance even if one is running; --env reaches the app, which hands its environment to its engine.
    let mut open = Command::new("/usr/bin/open");
    open.arg("-n")
        .arg("--env")
        .arg(format!("COURIER_DATA_DIR={}", data.display()));
    if let Some(file) = &seed_file {
        open.arg("--env")
            .arg(format!("COURIER_SEED={}", file.display()));
    }
    let opened = open.arg(&app).status();
    if opened.map(|s| s.success()).unwrap_or(false) {
        println!("Opened. Quit it from its menu (Courier Test Copy) when done.");
        0
    } else {
        eprintln!("run_test_copy: open failed");
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_the_installed_apps_data() {
        let home = Path::new("/Users/example");
        assert!(is_installed_apps_data(
            Path::new("/Users/example/Library/Application Support/Courier"),
            home
        ));
        assert!(is_installed_apps_data(
            Path::new("/Users/example/Library/Application Support/Courier/sub"),
            home
        ));
        assert!(!is_installed_apps_data(
            Path::new("/Users/example/Library/Application Support/Courier Test Copy"),
            home
        ));
        assert!(!is_installed_apps_data(
            Path::new("/tmp/courier-test-copy/data"),
            home
        ));
    }

    #[test]
    fn finds_the_archive() {
        assert_eq!(
            resolve_archive("a/CourierTestCopy.zip"),
            Some(PathBuf::from("a/CourierTestCopy.zip"))
        );
        assert_eq!(resolve_archive("nothing-here"), None);
    }

    #[test]
    fn no_arguments_is_a_usage_error() {
        assert_eq!(run(&["run_test_copy".to_string()]), 2);
    }

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn parses_bazels_arguments_then_the_persons() {
        let got = parse_args(&args(&[
            "run_test_copy",
            "x/CourierTestCopy.zip",
            "--scenarios",
            "s/direct.json",
            "s/group-threads.json",
            "--seed",
            "direct",
            "--no-open",
        ]))
        .unwrap();
        assert_eq!(
            got,
            Options {
                archive: "x/CourierTestCopy.zip".to_string(),
                scenarios: vec![
                    PathBuf::from("s/direct.json"),
                    PathBuf::from("s/group-threads.json")
                ],
                data: None,
                seed: Some("direct".to_string()),
                open: false,
            }
        );
        let plain = parse_args(&args(&["run_test_copy", "a.zip", "--data", "/tmp/d"])).unwrap();
        assert_eq!(plain.data, Some(PathBuf::from("/tmp/d")));
        assert_eq!(plain.seed, None);
        assert!(plain.open);
        assert!(parse_args(&args(&["run_test_copy", "a.zip", "--bogus"])).is_err());
        // --seed with no name is not a seed called "".
        assert!(parse_args(&args(&["run_test_copy", "a.zip", "--seed"])).is_err());
    }

    #[test]
    fn finds_a_scenario_by_name_or_lists_them() {
        let files = vec![
            PathBuf::from("s/group-threads.json"),
            PathBuf::from("s/direct.json"),
            PathBuf::from("s/README.md"),
        ];
        assert_eq!(
            find_scenario(&files, "direct"),
            Ok(PathBuf::from("s/direct.json"))
        );
        let err = find_scenario(&files, "nope").unwrap_err();
        assert!(err.contains("\"nope\""), "{}", err);
        assert!(err.contains("there are: direct, group-threads"), "{}", err);
        assert!(find_scenario(&[], "direct")
            .unwrap_err()
            .contains("none were passed in"));
        assert_eq!(scenario_names(&files), vec!["direct", "group-threads"]);
    }

    #[test]
    fn a_seed_gets_its_own_fresh_folder_unless_data_is_given() {
        let base = Path::new("/t/courier-test-copy");
        assert_eq!(
            data_dir(base, None, Some("direct")),
            (PathBuf::from("/t/courier-test-copy/seed-direct"), true)
        );
        assert_eq!(
            data_dir(base, Some(Path::new("/d")), Some("direct")),
            (PathBuf::from("/d"), false)
        );
        assert_eq!(
            data_dir(base, None, None),
            (PathBuf::from("/t/courier-test-copy/data"), false)
        );
    }

    #[test]
    fn an_unknown_seed_is_a_usage_error() {
        assert_eq!(
            run(&args(&[
                "run_test_copy",
                "a.zip",
                "--scenarios",
                "s/direct.json",
                "--seed",
                "nope",
                "--no-open"
            ])),
            2
        );
    }
}
