// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

//! `bazel run //apps/desktop/vitruvian-courier/app:publish [-- --dry-run]`
//!
//! Builds the release Vitruvian Courier.app (app and engine, each for arm64 and
//! x86_64), adds Vitruvian Courier's Telegram app ID, and hands the app to
//! `//tools/desktop-package`, which signs it (the engine, then the app, with
//! the hardened runtime), notarises it when the notary key is in the
//! environment, makes the DMGs and the ZIP with their checksums and the
//! Homebrew cask, and, on a real release, uploads them and pushes the cask.
//!
//! Inputs, from the environment:
//!   RELEASE_TAG (or TAG)   vitruvian-courier-vX.Y.Z. Needed for a real release; it must
//!                          match app/version.bzl. A dry run may leave it out.
//!   DRY_RUN=true           the same as --dry-run: package and check, upload
//!                          nothing, push nothing.
//!   COURIER_TELEGRAM_API_ID, COURIER_TELEGRAM_API_HASH
//!                          Vitruvian Courier's Telegram app ID (secrets of the
//!                          vitruvian-courier-release GitHub Environment). A real release refuses
//!                          to start without both; a dry run goes on without.
//!   NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_API_KEY_P8
//!                          the notary key. A real release refuses to start
//!                          without all three; a dry run is not notarised.
//!   BUILDBUDDY_API_KEY     optional: read the remote cache CI warmed.
//!   SIGNING_IDENTITY, GH_TOKEN, HOMEBREW_TAP_TOKEN
//!                          read by //tools/desktop-package.
//!
//! The release workflow is .github/workflows/vitruvian-courier-release.yaml.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::archs;

pub const APP_NAME: &str = "Vitruvian Courier";
pub const ARTIFACT_STEM: &str = "VitruvianCourier";
pub const CASK_NAME: &str = "vitruvian-courier";
pub const TAG_PREFIX: &str = "vitruvian-courier-v";
pub const TARGET: &str = "//apps/desktop/vitruvian-courier/app:VitruvianCourier";
pub const VERSION_FILE: &str = "apps/desktop/vitruvian-courier/app/version.bzl";
pub const DIST_DIR: &str = "apps/desktop/vitruvian-courier/dist";
pub const CASK_DESC: &str = "Every chat app in one inbox, on this Mac";
pub const CASK_HOMEPAGE: &str =
    "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian-courier";
const TELEGRAM_ID: &str = "COURIER_TELEGRAM_API_ID";
const TELEGRAM_HASH: &str = "COURIER_TELEGRAM_API_HASH";

const USAGE: &str =
    "usage: publish [--dry-run]   (env: RELEASE_TAG=vitruvian-courier-vX.Y.Z, DRY_RUN=true)";

/// What one run does.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Plan {
    pub version: String,
    /// Empty for a dry run with no tag.
    pub tag: String,
    pub dry_run: bool,
    /// Flags for `bazel build` and `bazel cquery`.
    pub bazel_flags: Vec<String>,
}

/// `vitruvian-courier-v1.2.3` -> `1.2.3`. Anything else is refused: the tag is what
/// release-please cut, and a release built from a guess is worse than none.
pub fn version_from_tag(tag: &str) -> Result<String, String> {
    let rest = tag.strip_prefix(TAG_PREFIX).ok_or_else(|| {
        format!("publish: {tag} is not a Vitruvian Courier release tag ({TAG_PREFIX}X.Y.Z)")
    })?;
    let parts: Vec<&str> = rest.split('.').collect();
    let numeric = parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()));
    if !numeric {
        return Err(format!(
            "publish: {tag} is not a Vitruvian Courier release tag ({TAG_PREFIX}X.Y.Z)"
        ));
    }
    Ok(rest.to_string())
}

/// `VITRUVIAN_COURIER_VERSION = "0.3.0"  # x-release-please-version` -> `0.3.0`.
pub fn version_from_bzl(text: &str) -> Result<String, String> {
    for line in text.lines() {
        let line = line.trim();
        if let Some(rest) = line.strip_prefix("VITRUVIAN_COURIER_VERSION") {
            let rest = rest.trim_start();
            if let Some(rest) = rest.strip_prefix('=') {
                let rest = rest.trim_start();
                if let Some(rest) = rest.strip_prefix('"') {
                    if let Some(end) = rest.find('"') {
                        let v = &rest[..end];
                        if !v.is_empty() {
                            return Ok(v.to_string());
                        }
                    }
                }
            }
        }
    }
    Err(format!(
        "publish: no VITRUVIAN_COURIER_VERSION = \"X.Y.Z\" in {VERSION_FILE}"
    ))
}

fn non_empty<'a>(env: &'a BTreeMap<String, String>, key: &str) -> Option<&'a str> {
    env.get(key)
        .map(String::as_str)
        .filter(|v| !v.trim().is_empty())
}

/// Reads the arguments and the environment into a plan, or says why not.
pub fn resolve_plan(
    args: &[String],
    env: &BTreeMap<String, String>,
    version_bzl: &str,
) -> Result<Plan, String> {
    let mut dry_run = non_empty(env, "DRY_RUN") == Some("true");
    for a in args {
        match a.as_str() {
            "--dry-run" => dry_run = true,
            other => return Err(format!("publish: unknown argument {other}\n{USAGE}")),
        }
    }

    let version = version_from_bzl(version_bzl)?;
    let tag = non_empty(env, "RELEASE_TAG")
        .or_else(|| non_empty(env, "TAG"))
        .unwrap_or("")
        .trim()
        .to_string();
    if tag.is_empty() {
        if !dry_run {
            return Err(format!(
                "publish: a real release needs RELEASE_TAG={TAG_PREFIX}X.Y.Z (the release-please tag); \
                 use --dry-run to package without one"
            ));
        }
    } else {
        let tagged = version_from_tag(&tag)?;
        if tagged != version {
            return Err(format!(
                "publish: {tag} says {tagged} but {VERSION_FILE} says {version}; \
                 the checkout is not the release's commit"
            ));
        }
    }

    if !dry_run
        && (non_empty(env, TELEGRAM_ID).is_none() || non_empty(env, TELEGRAM_HASH).is_none())
    {
        return Err(format!(
            "publish: a real release needs Vitruvian Courier's Telegram app ID ({TELEGRAM_ID} and {TELEGRAM_HASH}); \
             without it Telegram would ask each person for developer keys. Set both in the vitruvian-courier-release GitHub Environment \
             (bazel run //tools/sync-env-secrets:apply -- vitruvian-courier-release)"
        ));
    }

    // Sold directly, so a release is notarised or it does not ship: without the
    // key, //tools/desktop-package would skip notarisation and carry on, and
    // Gatekeeper would refuse the app on every Mac that downloads it.
    let notary_key =
        non_empty(env, "NOTARY_API_KEY_P8").or_else(|| non_empty(env, "NOTARY_KEY_FILE"));
    if !dry_run
        && (notary_key.is_none()
            || non_empty(env, "NOTARY_KEY_ID").is_none()
            || non_empty(env, "NOTARY_ISSUER_ID").is_none())
    {
        return Err(
            "publish: a real release must be notarised: set NOTARY_KEY_ID, NOTARY_ISSUER_ID and \
             NOTARY_API_KEY_P8 (the release workflow passes the VITRUVIAN_NOTARY_* secrets)"
                .to_string(),
        );
    }

    let mut bazel_flags = vec![
        "--config=macos-app".to_string(),
        format!("--macos_cpus={}", archs::RELEASE_ARCHS.join(",")),
    ];
    if let Some(key) = non_empty(env, "BUILDBUDDY_API_KEY") {
        bazel_flags.push("--config=remotecache-ci".to_string());
        bazel_flags.push(format!("--remote_header=x-buildbuddy-api-key={key}"));
    }

    Ok(Plan {
        version,
        tag,
        dry_run,
        bazel_flags,
    })
}

/// The flags as they may be printed: the cache key never reaches a log.
pub fn redacted(flags: &[String]) -> Vec<String> {
    flags
        .iter()
        .map(|f| {
            if f.starts_with("--remote_header=") {
                "--remote_header=x-buildbuddy-api-key=<redacted>".to_string()
            } else {
                f.clone()
            }
        })
        .collect()
}

/// The injector's arguments: a dry run may go on without the Telegram app ID.
pub fn injector_args(plan: &Plan, entitlements: &Path, app: &Path) -> Vec<String> {
    let mut a = Vec::new();
    if plan.dry_run {
        a.push("--allow-missing".to_string());
    }
    a.push("--entitlements".to_string());
    a.push(entitlements.display().to_string());
    a.push(app.display().to_string());
    a
}

/// //tools/desktop-package's arguments.
pub fn package_args(plan: &Plan, app: &Path, entitlements: &Path, dist: &Path) -> Vec<String> {
    let mut a: Vec<String> = vec![
        "--app-path".into(),
        app.display().to_string(),
        "--app-name".into(),
        APP_NAME.into(),
        "--version".into(),
        plan.version.clone(),
        "--cask-name".into(),
        CASK_NAME.into(),
        "--cask-desc".into(),
        CASK_DESC.into(),
        "--cask-homepage".into(),
        CASK_HOMEPAGE.into(),
        "--entitlements".into(),
        entitlements.display().to_string(),
        "--dist-dir".into(),
        dist.display().to_string(),
    ];
    if !plan.tag.is_empty() {
        a.push("--tag".into());
        a.push(plan.tag.clone());
    }
    if plan.dry_run {
        a.push("--dry-run".into());
    }
    a
}

/// Every file a packaged release leaves in dist, each non-empty.
pub fn expected_dist_files(version: &str) -> Vec<String> {
    let artifacts = [
        format!("{ARTIFACT_STEM}-{version}-universal.dmg"),
        format!("{ARTIFACT_STEM}-{version}.dmg"),
        format!("{ARTIFACT_STEM}-{version}-arm64.dmg"),
        format!("{ARTIFACT_STEM}-{version}-x86_64.dmg"),
        format!("{ARTIFACT_STEM}-{version}-universal.zip"),
    ];
    let mut files = Vec::with_capacity(artifacts.len() * 2 + 1);
    for artifact in &artifacts {
        files.push(artifact.clone());
        files.push(format!("{artifact}.sha256"));
    }
    files.push(format!("{CASK_NAME}.rb"));
    files
}

/// The expected files that are missing or empty.
pub fn missing_from_dist(dist: &Path, version: &str) -> Vec<String> {
    expected_dist_files(version)
        .into_iter()
        .filter(|f| {
            !fs::metadata(dist.join(f))
                .map(|m| m.len() > 0)
                .unwrap_or(false)
        })
        .collect()
}

/// The archive among `bazel cquery --output=files` lines.
pub fn archive_from_cquery(output: &str) -> Option<String> {
    output
        .lines()
        .map(str::trim)
        .find(|l| l.ends_with(".zip"))
        .map(str::to_string)
}

fn run_in(dir: &Path, program: &str, args: &[String], shown: &[String]) -> Result<(), String> {
    println!("+ {} {}", program, shown.join(" "));
    let status = Command::new(program)
        .args(args)
        .current_dir(dir)
        .status()
        .map_err(|e| format!("cannot run {program}: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{program} failed ({status})"))
    }
}

fn absolute(p: &str) -> PathBuf {
    fs::canonicalize(p).unwrap_or_else(|_| PathBuf::from(p))
}

/// args: <inject-app-credentials> <VitruvianCourier.entitlements> <package-desktop>
/// <sync_downloads> [--dry-run]. Bazel's `args` supply the first four.
pub fn run(args: &[String]) -> i32 {
    if args.iter().skip(1).any(|a| a == "--help" || a == "-h") {
        println!("{USAGE}");
        return 0;
    }
    if args.len() < 5 {
        eprintln!(
            "publish: run it with `bazel run //apps/desktop/vitruvian-courier/app:publish`\n{USAGE}"
        );
        return 2;
    }
    let injector = absolute(&args[1]);
    let entitlements = absolute(&args[2]);
    let packager = absolute(&args[3]);
    let sync_tool = absolute(&args[4]);

    let env: BTreeMap<String, String> = std::env::vars().collect();
    let Some(workspace) = non_empty(&env, "BUILD_WORKSPACE_DIRECTORY").map(PathBuf::from) else {
        eprintln!("publish: run it with `bazel run`, which says where the checkout is");
        return 2;
    };
    let version_bzl = match fs::read_to_string(workspace.join(VERSION_FILE)) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("publish: cannot read {VERSION_FILE}: {e}");
            return 2;
        }
    };
    let plan = match resolve_plan(&args[5..], &env, &version_bzl) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{e}");
            return 2;
        }
    };
    println!(
        "==> Vitruvian Courier {}{}{}",
        plan.version,
        if plan.tag.is_empty() {
            String::new()
        } else {
            format!(" (tag {})", plan.tag)
        },
        if plan.dry_run {
            ", dry run: nothing is uploaded"
        } else {
            ""
        }
    );

    match publish(
        &plan,
        &workspace,
        &injector,
        &entitlements,
        &packager,
        &sync_tool,
    ) {
        Ok(()) => {
            println!("==> Vitruvian Courier {} packaged.", plan.version);
            0
        }
        Err(e) => {
            eprintln!("publish: {e}");
            eprintln!(
                "publish: Vitruvian Courier {} was NOT released",
                plan.version
            );
            1
        }
    }
}

fn publish(
    plan: &Plan,
    workspace: &Path,
    injector: &Path,
    entitlements: &Path,
    packager: &Path,
    sync_tool: &Path,
) -> Result<(), String> {
    // 1. Build the app for both CPUs.
    let mut build = vec!["build".to_string()];
    build.extend(plan.bazel_flags.iter().cloned());
    build.push(TARGET.to_string());
    let mut shown = vec!["build".to_string()];
    shown.extend(redacted(&plan.bazel_flags));
    shown.push(TARGET.to_string());
    run_in(workspace, "bazel", &build, &shown)?;

    let mut query = vec!["cquery".to_string()];
    query.extend(plan.bazel_flags.iter().cloned());
    query.extend(["--output=files".to_string(), TARGET.to_string()]);
    let out = Command::new("bazel")
        .args(&query)
        .current_dir(workspace)
        .output()
        .map_err(|e| format!("cannot run bazel cquery: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "bazel cquery failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let archive = archive_from_cquery(&String::from_utf8_lossy(&out.stdout))
        .ok_or("bazel cquery named no VitruvianCourier.zip")?;
    let archive = workspace.join(archive);

    // 2. Unpack it into a clean dist.
    let dist = workspace.join(DIST_DIR);
    let _ = fs::remove_dir_all(&dist);
    let stage = dist.join("stage");
    fs::create_dir_all(&stage).map_err(|e| format!("cannot create {}: {e}", stage.display()))?;
    let unpack = vec![
        "-x".to_string(),
        "-k".to_string(),
        archive.display().to_string(),
        stage.display().to_string(),
    ];
    run_in(workspace, "ditto", &unpack, &unpack)?;
    let app = stage.join(format!("{APP_NAME}.app"));
    if !app.is_dir() {
        return Err(format!("{} holds no {APP_NAME}.app", archive.display()));
    }

    // 3. Both the app and its engine run on both CPUs.
    for (what, path) in [
        ("the app", app.join("Contents/MacOS/VitruvianCourier")),
        (
            "the engine",
            app.join("Contents/Helpers/vitruvian-courier-engine"),
        ),
    ] {
        let have = archs::read(&path)?;
        let lacking = archs::missing(&archs::RELEASE_ARCHS, &have);
        if !lacking.is_empty() {
            return Err(format!(
                "{what} ({}) is built for {} but not {}",
                path.display(),
                have.join(" "),
                lacking.join(" ")
            ));
        }
        println!("ok: {what} runs on {}", have.join(" "));
    }

    // 4. Vitruvian Courier's Telegram app ID. The injector signs too; package-desktop
    //    signs again, for the release.
    let inject = injector_args(plan, entitlements, &app);
    run_in(workspace, &injector.display().to_string(), &inject, &inject)?;
    let telegram = app.join("Contents/Resources/TelegramApp.plist");
    if !telegram.is_file() {
        if plan.dry_run {
            println!("note: no Telegram app ID in this dry run; a real release refuses to ship without one");
        } else {
            return Err("the app has no TelegramApp.plist after the injector ran".into());
        }
    }

    // 5. Sign, notarise, package, upload, cask.
    let pkg = package_args(plan, &app, entitlements, &dist);
    println!("+ {} {}", packager.display(), pkg.join(" "));
    let status = Command::new(packager)
        .args(&pkg)
        .current_dir(workspace)
        .env("PACKAGE_DESKTOP_SYNC_DOWNLOADS", sync_tool)
        .status()
        .map_err(|e| format!("cannot run package-desktop: {e}"))?;
    if !status.success() {
        return Err(format!("package-desktop failed ({status})"));
    }

    // 6. Proof: every file is there.
    let missing = missing_from_dist(&dist, &plan.version);
    if !missing.is_empty() {
        return Err(format!(
            "packaging left no {} in {}",
            missing.join(", "),
            dist.display()
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const BZL: &str =
        "\"\"\"doc\"\"\"\n\nVITRUVIAN_COURIER_VERSION = \"0.3.0\"  # x-release-please-version\n";

    fn env(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    /// What a real release has in its environment besides the tag.
    fn telegram() -> Vec<(&'static str, &'static str)> {
        vec![
            (TELEGRAM_ID, "4242424"),
            (TELEGRAM_HASH, "0123456789abcdef0123456789abcdef"),
            ("NOTARY_KEY_ID", "KEYID"),
            ("NOTARY_ISSUER_ID", "issuer"),
            ("NOTARY_API_KEY_P8", "pem"),
        ]
    }

    #[test]
    fn tag_gives_the_version() {
        assert_eq!(
            version_from_tag("vitruvian-courier-v1.2.3").unwrap(),
            "1.2.3"
        );
        assert_eq!(
            version_from_tag("vitruvian-courier-v0.10.0").unwrap(),
            "0.10.0"
        );
    }

    #[test]
    fn other_tags_are_refused() {
        for bad in [
            "v1.2.3",
            "vitruvian-speaker-v1.2.3",
            "courier-v1.2.3",
            "vitruvian-courier-v1.2",
            "vitruvian-courier-v1.2.x",
            "vitruvian-courier-v",
            "vitruvian-courier-v1.2.3-beta",
        ] {
            assert!(version_from_tag(bad).is_err(), "{bad} was accepted");
        }
    }

    #[test]
    fn version_comes_from_version_bzl() {
        assert_eq!(version_from_bzl(BZL).unwrap(), "0.3.0");
        assert!(version_from_bzl("NOT_IT = \"1.0.0\"\n").is_err());
    }

    #[test]
    fn version_bzl_in_the_tree_parses() {
        // The real file, as release-please rewrites it (BUILD gives it to this
        // test as data): the marker must not stop the reader.
        let text = fs::read_to_string(VERSION_FILE).expect("version.bzl is in the test's runfiles");
        assert!(
            text.contains("x-release-please-version"),
            "release-please could not bump {VERSION_FILE}"
        );
        let v = version_from_bzl(&text).unwrap();
        assert!(version_from_tag(&format!("{TAG_PREFIX}{v}")).is_ok(), "{v}");
    }

    #[test]
    fn a_dry_run_needs_no_tag_and_no_secret() {
        let p = resolve_plan(&["--dry-run".to_string()], &env(&[]), BZL).unwrap();
        assert!(p.dry_run);
        assert_eq!(p.tag, "");
        assert_eq!(p.version, "0.3.0");
        assert_eq!(
            p.bazel_flags,
            vec!["--config=macos-app", "--macos_cpus=arm64,x86_64"]
        );
        let p = resolve_plan(&[], &env(&[("DRY_RUN", "true")]), BZL).unwrap();
        assert!(p.dry_run);
    }

    #[test]
    fn a_real_release_needs_its_tag() {
        let mut e = env(&telegram());
        let err = resolve_plan(&[], &e, BZL).unwrap_err();
        assert!(err.contains("RELEASE_TAG"), "{err}");
        e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.3.0".into());
        let p = resolve_plan(&[], &e, BZL).unwrap();
        assert!(!p.dry_run);
        assert_eq!(p.tag, "vitruvian-courier-v0.3.0");
    }

    #[test]
    fn tag_is_read_from_tag_too() {
        let mut e = env(&telegram());
        e.insert("TAG".into(), "vitruvian-courier-v0.3.0".into());
        assert_eq!(
            resolve_plan(&[], &e, BZL).unwrap().tag,
            "vitruvian-courier-v0.3.0"
        );
    }

    #[test]
    fn a_tag_that_does_not_match_version_bzl_is_refused() {
        let mut e = env(&telegram());
        e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.4.0".into());
        let err = resolve_plan(&[], &e, BZL).unwrap_err();
        assert!(err.contains("0.4.0") && err.contains("0.3.0"), "{err}");
        // A dry run of a tag is held to the same rule.
        let err = resolve_plan(&["--dry-run".to_string()], &e, BZL).unwrap_err();
        assert!(err.contains("not the release's commit"), "{err}");
    }

    #[test]
    fn a_real_release_without_the_telegram_app_id_is_refused() {
        for drop in [TELEGRAM_ID, TELEGRAM_HASH] {
            let mut e = env(&telegram());
            e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.3.0".into());
            e.remove(drop);
            let err = resolve_plan(&[], &e, BZL).unwrap_err();
            assert!(
                err.contains(TELEGRAM_ID) && err.contains(TELEGRAM_HASH),
                "without {drop}: {err}"
            );
        }
    }

    #[test]
    fn a_real_release_that_cannot_be_notarised_is_refused() {
        for drop in ["NOTARY_KEY_ID", "NOTARY_ISSUER_ID", "NOTARY_API_KEY_P8"] {
            let mut e = env(&telegram());
            e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.3.0".into());
            e.remove(drop);
            let err = resolve_plan(&[], &e, BZL).unwrap_err();
            assert!(err.contains("notarised"), "without {drop}: {err}");
        }
        // A key file stands in for the key itself, as it does for package-desktop.
        let mut e = env(&telegram());
        e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.3.0".into());
        e.remove("NOTARY_API_KEY_P8");
        e.insert("NOTARY_KEY_FILE".into(), "/k/AuthKey.p8".into());
        assert!(resolve_plan(&[], &e, BZL).is_ok());
    }

    #[test]
    fn the_cache_key_is_used_but_never_shown() {
        let p = resolve_plan(
            &["--dry-run".to_string()],
            &env(&[("BUILDBUDDY_API_KEY", "sekrit")]),
            BZL,
        )
        .unwrap();
        assert!(p
            .bazel_flags
            .contains(&"--config=remotecache-ci".to_string()));
        assert!(p.bazel_flags.iter().any(|f| f.contains("sekrit")));
        let shown = redacted(&p.bazel_flags).join(" ");
        assert!(!shown.contains("sekrit"), "{shown}");
        assert!(shown.contains("<redacted>"));
    }

    #[test]
    fn unknown_arguments_are_refused() {
        assert!(resolve_plan(&["--yes".to_string()], &env(&[]), BZL).is_err());
    }

    #[test]
    fn injector_may_go_without_the_app_id_only_in_a_dry_run() {
        let ent = Path::new("/e/VitruvianCourier.entitlements");
        let app = Path::new("/d/Vitruvian Courier.app");
        let dry = resolve_plan(&["--dry-run".to_string()], &env(&[]), BZL).unwrap();
        assert_eq!(
            injector_args(&dry, ent, app),
            vec![
                "--allow-missing",
                "--entitlements",
                "/e/VitruvianCourier.entitlements",
                "/d/Vitruvian Courier.app"
            ]
        );
        let mut e = env(&telegram());
        e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.3.0".into());
        let real = resolve_plan(&[], &e, BZL).unwrap();
        assert!(!injector_args(&real, ent, app).contains(&"--allow-missing".to_string()));
    }

    #[test]
    fn package_desktop_gets_the_entitlements_cask_and_tag() {
        let mut e = env(&telegram());
        e.insert("RELEASE_TAG".into(), "vitruvian-courier-v0.3.0".into());
        let real = resolve_plan(&[], &e, BZL).unwrap();
        let a = package_args(
            &real,
            Path::new("/d/Vitruvian Courier.app"),
            Path::new("/e/C.ent"),
            Path::new("/d"),
        );
        let joined = a.join(" ");
        assert!(joined.contains("--app-name Vitruvian Courier"));
        assert!(joined.contains("--cask-name vitruvian-courier"));
        assert!(joined.contains("--entitlements /e/C.ent"));
        assert!(joined.contains("--tag vitruvian-courier-v0.3.0"));
        assert!(!joined.contains("--dry-run"));
        assert!(!joined.to_lowercase().contains("beeper"));

        let dry = resolve_plan(&["--dry-run".to_string()], &env(&[]), BZL).unwrap();
        let a = package_args(
            &dry,
            Path::new("/d/Vitruvian Courier.app"),
            Path::new("/e/C.ent"),
            Path::new("/d"),
        );
        assert!(a.contains(&"--dry-run".to_string()));
        assert!(!a.contains(&"--tag".to_string()));
    }

    #[test]
    fn expected_files_cover_every_dmg_zip_checksum_and_the_cask() {
        let f = expected_dist_files("0.3.0");
        for name in [
            "VitruvianCourier-0.3.0-universal.dmg",
            "VitruvianCourier-0.3.0-universal.dmg.sha256",
            "VitruvianCourier-0.3.0.dmg",
            "VitruvianCourier-0.3.0-arm64.dmg.sha256",
            "VitruvianCourier-0.3.0-x86_64.dmg",
            "VitruvianCourier-0.3.0-universal.zip.sha256",
            "vitruvian-courier.rb",
        ] {
            assert!(f.contains(&name.to_string()), "{name} is not expected");
        }
        assert_eq!(f.len(), 11);
    }

    #[test]
    fn missing_and_empty_files_are_named() {
        let dir = std::env::temp_dir().join(format!(
            "vitruvian-courier-publish-test-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        for f in expected_dist_files("0.3.0") {
            fs::write(dir.join(&f), b"x").unwrap();
        }
        assert!(missing_from_dist(&dir, "0.3.0").is_empty());
        fs::write(dir.join("VitruvianCourier-0.3.0-arm64.dmg"), b"").unwrap();
        fs::remove_file(dir.join("vitruvian-courier.rb")).unwrap();
        assert_eq!(
            missing_from_dist(&dir, "0.3.0"),
            vec![
                "VitruvianCourier-0.3.0-arm64.dmg".to_string(),
                "vitruvian-courier.rb".to_string()
            ]
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_archive_is_found_in_cquery_output() {
        assert_eq!(
            archive_from_cquery(
                "bazel-out/x/bin/apps/desktop/vitruvian-courier/app/VitruvianCourier.zip\n"
            )
            .as_deref(),
            Some("bazel-out/x/bin/apps/desktop/vitruvian-courier/app/VitruvianCourier.zip")
        );
        assert_eq!(
            archive_from_cquery("bazel-out/x/Vitruvian Courier.app\n"),
            None
        );
    }
}
