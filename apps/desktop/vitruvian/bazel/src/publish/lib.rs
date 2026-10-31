// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Builds, packages and publishes the Vitruvian DMGs to a GitHub Release.
//!
//! ONE program, TWO triggers (delivery-orchestrator spec §4.1): the generated
//! .github/workflows/delivery-vitruvian.yaml runs it for the `vitruvian`
//! unit, and the break-glass path is the same command,
//! `bazel run //apps/desktop/vitruvian:publish`. The rung selects the grade:
//!
//!   GRADE=beta        (push to main)  rolling prerelease `vitruvian-beta-latest`;
//!                     its Vitruvian-beta*.dmg are overwritten and the tag
//!                     moved to this commit.
//!   GRADE=production  (release event) attach Vitruvian-X.Y.Z*.dmg to the
//!                     release-please release named by RELEASE_TAG
//!                     (vitruvian-vX.Y.Z), and point the Homebrew cask at it
//!                     when HOMEBREW_TAP_TOKEN is set.
//!
//! macOS only: it builds the app with --config=macos-app and packages it with
//! package_release, which signs with the Developer ID identity when one is in
//! the keychain (ad-hoc otherwise) and notarizes when NOTARY_* are set.
//!
//! Break-glass for production, on a Mac: check out the release tag, then
//!   GRADE=production RELEASE_TAG=vitruvian-vX.Y.Z bazel run //apps/desktop/vitruvian:publish

use release_exec::{capture, make_temp_dir, redact, run, Cmd, Runner, PKG_REL};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const TAG_PREFIX: &str = "vitruvian-v";
pub const DEFAULT_BETA_TAG: &str = "vitruvian-beta-latest";
pub const TAP: &str = "VitruvianSoftware/homebrew-tap";
pub const USAGE: &str =
    "usage: publish [--dry-run] (env: GRADE=beta|production, RELEASE_TAG=vitruvian-vX.Y.Z)";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PublishGrade {
    Beta,
    Production,
}

impl PublishGrade {
    pub fn as_str(&self) -> &'static str {
        match self {
            PublishGrade::Beta => "beta",
            PublishGrade::Production => "production",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PublishPlan {
    pub grade: PublishGrade,
    pub app_version: String,
    pub version: String,
    pub tag: String,
    pub sha: String,
    pub primary_asset: String,
    pub bazel_flags: Vec<String>,
    /// (file package_release writes into dist/, name it is uploaded as)
    pub staged_assets: Vec<(String, String)>,
    pub homebrew_tap_token: Option<String>,
    pub dry_run: bool,
}

fn non_empty<'a>(env_map: &'a BTreeMap<String, String>, key: &str) -> Option<&'a String> {
    env_map.get(key).filter(|s| !s.is_empty())
}

/// What this run publishes, from the environment and the checkout's version.
/// An error is the exit code and the message.
pub fn resolve_publish_plan(
    args: &[String],
    env_map: &BTreeMap<String, String>,
    app_version: &str,
    sha: &str,
) -> Result<PublishPlan, (i32, String)> {
    let mut dry_run = false;
    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => return Err((0, USAGE.to_string())),
            other => return Err((2, format!("publish: unknown argument '{}'", other))),
        }
    }

    let grade_raw = non_empty(env_map, "GRADE")
        .map(String::as_str)
        .unwrap_or("beta");
    let short_sha: String = sha.chars().take(7).collect();

    let (grade, tag, version, primary_asset) = match grade_raw {
        "beta" => (
            PublishGrade::Beta,
            non_empty(env_map, "TAG")
                .cloned()
                .unwrap_or_else(|| DEFAULT_BETA_TAG.to_string()),
            format!("{}-beta.{}", app_version, short_sha),
            "Vitruvian-beta.dmg".to_string(),
        ),
        "production" => {
            // A dispatch of the production rung carries no release event.
            // Running it from the release tag itself names the tag; anything
            // else must say which release it means, because re-uploading a
            // release's DMG from a different commit would silently replace
            // what was released.
            let mut tag = env_map.get("RELEASE_TAG").cloned().unwrap_or_default();
            if tag.is_empty() && env_map.get("GITHUB_REF_TYPE").map(String::as_str) == Some("tag") {
                tag = env_map.get("GITHUB_REF_NAME").cloned().unwrap_or_default();
            }
            if tag.is_empty() {
                return Err((
                    2,
                    format!(
                        "publish: GRADE=production needs RELEASE_TAG={}X.Y.Z (the release-please tag); refusing to guess",
                        TAG_PREFIX
                    ),
                ));
            }
            let Some(ver) = tag.strip_prefix(TAG_PREFIX) else {
                return Err((
                    2,
                    format!(
                        "publish: RELEASE_TAG={} is not a {}* release; another component's release reached this rung",
                        tag, TAG_PREFIX
                    ),
                ));
            };
            if ver != app_version {
                return Err((
                    2,
                    format!(
                        "publish: {} is version {}, but this checkout builds {}; check out the release tag first",
                        tag, ver, app_version
                    ),
                ));
            }
            let ver = ver.to_string();
            (
                PublishGrade::Production,
                tag.clone(),
                ver.clone(),
                format!("Vitruvian-{}.dmg", ver),
            )
        }
        other => {
            return Err((
                2,
                format!("publish: unknown GRADE={} (beta|production)", other),
            ));
        }
    };

    let mut bazel_flags = vec![
        "--config=macos-app".to_string(),
        "--macos_cpus=arm64,x86_64".to_string(),
    ];
    if let Some(key) = non_empty(env_map, "BUILDBUDDY_API_KEY") {
        // Cache-only (see --config=remotecache-ci): reuse the build the macOS
        // pipeline unit already cached. Absent (a laptop, a fork), build
        // locally.
        bazel_flags.push("--config=remotecache-ci".to_string());
        bazel_flags.push(format!("--remote_header=x-buildbuddy-api-key={}", key));
    }

    let uploaded = |suffix: &str| match grade {
        PublishGrade::Beta => format!("Vitruvian-beta{}", suffix),
        PublishGrade::Production => format!("Vitruvian-{}{}", version, suffix),
    };
    let staged_assets = [
        "-universal.dmg",
        "-arm64.dmg",
        "-x86_64.dmg",
        "-universal.zip",
        ".dmg",
    ]
    .iter()
    .map(|suffix| {
        (
            format!("Vitruvian-{}{}", app_version, suffix),
            uploaded(suffix),
        )
    })
    .collect();

    Ok(PublishPlan {
        grade,
        app_version: app_version.to_string(),
        version,
        tag,
        sha: sha.to_string(),
        primary_asset,
        bazel_flags,
        staged_assets,
        homebrew_tap_token: non_empty(env_map, "HOMEBREW_TAP_TOKEN").cloned(),
        dry_run,
    })
}

pub fn render_homebrew_cask(version: &str, universal_dmg_sha256: &str) -> String {
    [
        "cask \"vitruvian\" do".to_string(),
        format!("  version \"{}\"", version),
        format!("  sha256 \"{}\"", universal_dmg_sha256),
        String::new(),
        format!("  url \"https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v{v}/Vitruvian-{v}-universal.dmg\"", v = version),
        "  name \"Vitruvian\"".to_string(),
        "  desc \"Desktop control hub for Vitruvian and AI coding sessions\"".to_string(),
        "  homepage \"https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian\"".to_string(),
        String::new(),
        "  app \"Vitruvian.app\"".to_string(),
        "end".to_string(),
        String::new(),
    ]
    .join("\n")
}

pub fn render_beta_release_notes(version: &str, sha: &str, iso_timestamp: &str) -> String {
    format!(
        "Latest beta build: {version}\n\
Commit: {sha}\n\
Built: {iso_timestamp}\n\
\n\
Vitruvian is built from main and is not a release. It is signed ad-hoc unless a Developer ID is configured, so macOS asks you to approve it on first launch (see the README's Install section)."
    )
}

/// Packages the Bazel-built zip into `<package>/dist`.
pub trait Packager {
    fn package(&mut self, r: &mut dyn Runner, archive: &Path) -> Result<(), i32>;
}

/// package_release, for real.
pub struct ReleasePackager {
    pub pkg_dir: PathBuf,
    pub tmp_root: PathBuf,
}

impl Packager for ReleasePackager {
    fn package(&mut self, r: &mut dyn Runner, archive: &Path) -> Result<(), i32> {
        let mut tools = package_release::ReleaseTools::from_env(&self.pkg_dir, &self.tmp_root);
        package_release::package_release(r, &mut tools, &self.pkg_dir, archive, &self.tmp_root)
            .map(|_| ())
    }
}

fn gh_api(path: &str, jq: &str) -> Cmd {
    Cmd::new("gh").args(["api", path, "--jq", jq])
}

/// How this commit relates to the rolling tag's, as GitHub's compare API
/// says (`absent` when there is no tag). Decided BEFORE building and
/// uploading: uploading an older DMG over a newer one cannot be undone by
/// moving the tag back, which GITHUB_TOKEN may not do (it would undo workflow
/// changes).
fn beta_compare_status(r: &mut dyn Runner, plan: &PublishPlan) -> Result<(String, String), i32> {
    let tag_ref = r.output(&gh_api(
        &format!("repos/{{owner}}/{{repo}}/git/ref/tags/{}", plan.tag),
        ".object.type + \" \" + .object.sha",
    ));
    if tag_ref.success() {
        let mut fields = tag_ref.stdout.split_whitespace();
        let tag_type = fields.next().unwrap_or_default().to_string();
        let mut tag_sha = fields.next().unwrap_or_default().to_string();
        if tag_type == "tag" {
            // An annotated tag: its object is the tag, not the commit.
            tag_sha = capture(
                r,
                &gh_api(
                    &format!("repos/{{owner}}/{{repo}}/git/tags/{}", tag_sha),
                    ".object.sha",
                ),
            )?
            .trim()
            .to_string();
        }
        let status = capture(
            r,
            &gh_api(
                &format!(
                    "repos/{{owner}}/{{repo}}/compare/{}...{}",
                    tag_sha, plan.sha
                ),
                ".status",
            ),
        )?;
        Ok((status.trim().to_string(), tag_sha))
    } else if tag_ref.stderr.contains("HTTP 404") {
        Ok(("absent".to_string(), String::new()))
    } else {
        r.report(&format!(
            "publish: could not read the tag {}; refusing to publish blind:\n{}",
            plan.tag, tag_ref.stderr
        ));
        Err(1)
    }
}

fn files_in(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = fs::read_dir(dir)
        .map(|it| {
            it.filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| p.is_file())
                .collect()
        })
        .unwrap_or_default();
    v.sort();
    v
}

fn io_step<T>(what: &str, res: std::io::Result<T>) -> Result<T, i32> {
    res.map_err(|e| {
        eprintln!("publish: {}: {}", what, e);
        1
    })
}

/// Runs the publish. `Ok` covers a beta that skips because the release
/// already holds a newer build.
pub fn publish(
    r: &mut dyn Runner,
    packager: &mut dyn Packager,
    root: &Path,
    plan: &PublishPlan,
    runner_temp: Option<&Path>,
    tmp_root: &Path,
) -> Result<(), i32> {
    let pkg = root.join(PKG_REL);
    println!(
        "=== vitruvian publish: grade={} version={} tag={} commit={} ===",
        plan.grade.as_str(),
        plan.version,
        plan.tag,
        plan.sha
    );

    if plan.grade == PublishGrade::Beta {
        let (status, tag_sha) = beta_compare_status(r, plan)?;
        match beta_publish_guard::decide(&status) {
            beta_publish_guard::Decision::Publish => {}
            beta_publish_guard::Decision::Skip => {
                println!(
                    "publish: {} already holds a newer build ({}); this run's commit {} is older, so it publishes nothing",
                    plan.tag, tag_sha, plan.sha
                );
                return Ok(());
            }
            beta_publish_guard::Decision::Refuse => {
                eprintln!(
                    "publish: {} is at {} and this run's commit {} relates to it as '{}'; that cannot happen on main, so refusing to publish",
                    plan.tag,
                    if tag_sha.is_empty() { "nothing" } else { &tag_sha },
                    plan.sha,
                    status
                );
                return Err(1);
            }
        }
    }

    let target = format!("//{}:Vitruvian", PKG_REL);
    run(
        r,
        &Cmd::new("bazel")
            .arg("build")
            .args(&plan.bazel_flags)
            .arg(&target),
    )?;
    let files = capture(
        r,
        &Cmd::new("bazel")
            .arg("cquery")
            .args(&plan.bazel_flags)
            .args(["--output=files", &target]),
    )?;
    let archive = files
        .lines()
        .map(str::trim)
        .find(|l| l.ends_with(".zip"))
        .map(|l| root.join(l));
    let Some(archive) = archive.filter(|a| a.is_file()) else {
        eprintln!("publish: bazel produced no Vitruvian.zip for {}", target);
        return Err(1);
    };

    let dist = pkg.join("dist");
    let _ = fs::remove_dir_all(&dist);
    packager.package(r, &archive)?;
    let universal = dist.join(format!("Vitruvian-{}-universal.dmg", plan.app_version));
    if !universal.is_file() {
        eprintln!(
            "publish: package_release did not produce Vitruvian-{}-universal.dmg",
            plan.app_version
        );
        return Err(1);
    }

    let base = match runner_temp {
        Some(t) => t.to_path_buf(),
        None => io_step("mktemp", make_temp_dir(tmp_root, "vitruvian-publish"))?,
    };
    let work = base.join("vitruvian-dist");
    let _ = fs::remove_dir_all(&work);
    io_step("mkdir", fs::create_dir_all(&work))?;
    for (src, dst) in &plan.staged_assets {
        io_step(
            &format!("cp {}", src),
            fs::copy(dist.join(src), work.join(dst)),
        )?;
    }

    let staged = files_in(&work);
    for f in &staged {
        run(r, &Cmd::new("shasum").args(["-a", "256"]).path(f))?;
    }

    if plan.grade == PublishGrade::Beta
        && !r
            .output(&Cmd::new("gh").args(["release", "view", &plan.tag]))
            .success()
    {
        run(
            r,
            &Cmd::new("gh").args([
                "release",
                "create",
                &plan.tag,
                "--prerelease",
                "--target",
                &plan.sha,
                "--title",
                "Vitruvian (Beta Rolling Release)",
                "--notes",
                "Rolling pre-release built automatically from commits landing on main.",
            ]),
        )?;
    }

    for f in &staged {
        println!(
            "Uploading {}...",
            f.file_name().unwrap_or_default().to_string_lossy()
        );
        run(
            r,
            &Cmd::new("gh")
                .args(["release", "upload", &plan.tag])
                .path(f)
                .arg("--clobber"),
        )?;
    }

    if plan.grade == PublishGrade::Beta {
        // Move the rolling tag to the commit whose DMG now sits on the
        // release, so the release page's "compare"/source links agree with
        // the notes.
        let moved = r.output(&Cmd::new("gh").args([
            "api",
            "-X",
            "PATCH",
            &format!("repos/{{owner}}/{{repo}}/git/refs/tags/{}", plan.tag),
            "-f",
            &format!("sha={}", plan.sha),
            "-F",
            "force=true",
        ]));
        if !moved.success() {
            // The DMGs are up but the tag still names the old commit; notes
            // naming this commit would then lie, so stop here and say so.
            r.report(&format!(
                "publish: could not move {} to {}; the release notes are left as they were:\n{}",
                plan.tag, plan.sha, moved.stderr
            ));
            return Err(if moved.code == 0 { 1 } else { moved.code });
        }
        let built = capture(r, &Cmd::new("date").args(["-u", "+%Y-%m-%dT%H:%M:%SZ"]))?;
        run(
            r,
            &Cmd::new("gh").args([
                "release",
                "edit",
                &plan.tag,
                "--notes",
                &render_beta_release_notes(&plan.version, &plan.sha, built.trim()),
            ]),
        )?;
    }

    if plan.grade == PublishGrade::Production {
        if let Some(token) = &plan.homebrew_tap_token {
            update_tap(r, &work, &plan.version, token)?;
        }
    }

    println!(
        "=== vitruvian publish complete: {} ({}, {}) ===",
        plan.tag,
        plan.version,
        plan.grade.as_str()
    );
    Ok(())
}

/// Points the Homebrew cask at this release's universal DMG.
fn update_tap(r: &mut dyn Runner, work: &Path, version: &str, token: &str) -> Result<(), i32> {
    let tap_dir = work.join("tap");
    run(
        r,
        &Cmd::new("git")
            .args(["clone", "--depth", "1"])
            .arg(format!(
                "https://x-access-token:{}@github.com/{}.git",
                token, TAP
            ))
            .path(&tap_dir),
    )?;
    io_step("mkdir Casks", fs::create_dir_all(tap_dir.join("Casks")))?;
    let dmg = work.join(format!("Vitruvian-{}-universal.dmg", version));
    let sum = capture(r, &Cmd::new("shasum").args(["-a", "256"]).path(&dmg))?;
    let sha = sum
        .split_whitespace()
        .next()
        .unwrap_or_default()
        .to_string();
    io_step(
        "write Casks/vitruvian.rb",
        fs::write(
            tap_dir.join("Casks/vitruvian.rb"),
            render_homebrew_cask(version, &sha),
        ),
    )?;
    let git = |args: &[&str]| Cmd::new("git").arg("-C").path(&tap_dir).args(args);
    run(r, &git(&["add", "Casks/vitruvian.rb"]))?;
    if r.status(&git(&["diff", "--cached", "--quiet"])) == 0 {
        println!("publish: {} already has vitruvian {}", TAP, version);
    } else {
        run(
            r,
            &git(&[
                "-c",
                "user.name=github-actions[bot]",
                "-c",
                "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                "commit",
                "-q",
                "-m",
                &format!("vitruvian {}", version),
            ]),
        )?;
        run(r, &git(&["push", "-q", "origin", "HEAD"]))?;
        println!("publish: {} Casks/vitruvian.rb is now {}", TAP, version);
    }
    Ok(())
}

/// What `--dry-run` prints: the plan, never a secret in it.
pub fn dry_run_lines(plan: &PublishPlan) -> Vec<String> {
    let mut lines = vec![
        format!(
            "=== vitruvian publish (dry run): grade={} version={} tag={} commit={} ===",
            plan.grade.as_str(),
            plan.version,
            plan.tag,
            plan.sha
        ),
        format!(
            "dry-run: bazel build {} //{}:Vitruvian",
            redact(&plan.bazel_flags.join(" ")),
            PKG_REL
        ),
    ];
    for (src, dst) in &plan.staged_assets {
        lines.push(format!("dry-run: upload dist/{} as {}", src, dst));
    }
    lines
}

pub fn run_cli(args: &[String]) -> i32 {
    let root = release_exec::workspace_root();
    if let Err(e) = std::env::set_current_dir(&root) {
        eprintln!("publish: cd {}: {}", root.display(), e);
        return 1;
    }
    let env_map: BTreeMap<String, String> = std::env::vars().collect();
    let mut r = release_exec::SystemRunner::new();

    let sha = match non_empty(&env_map, "GITHUB_SHA") {
        Some(s) => s.clone(),
        None => match capture(&mut r, &Cmd::new("git").args(["rev-parse", "HEAD"])) {
            Ok(s) => s.trim().to_string(),
            Err(code) => return code,
        },
    };
    let pkg = root.join(PKG_REL);
    let app_version =
        match release_exec::plist_short_version(&mut r, &pkg.join("Resources/Info.plist")) {
            Ok(v) => v,
            Err(code) => return code,
        };

    let plan = match resolve_publish_plan(args, &env_map, &app_version, &sha) {
        Ok(p) => p,
        Err((0, msg)) => {
            println!("{}", msg);
            return 0;
        }
        Err((code, msg)) => {
            eprintln!("{}", msg);
            return code;
        }
    };

    if plan.dry_run {
        for line in dry_run_lines(&plan) {
            println!("{}", line);
        }
        return 0;
    }

    let tmp_root = release_exec::temp_root();
    let runner_temp = non_empty(&env_map, "RUNNER_TEMP").map(PathBuf::from);
    let mut packager = ReleasePackager {
        pkg_dir: pkg,
        tmp_root: tmp_root.clone(),
    };
    match publish(
        &mut r,
        &mut packager,
        &root,
        &plan,
        runner_temp.as_deref(),
        &tmp_root,
    ) {
        Ok(()) => 0,
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use release_exec::{FakeRunner, Out, TempDir};
    use std::cell::RefCell;
    use std::rc::Rc;

    const SHA: &str = "abcdef1234567890abcdef1234567890abcdef12";
    const TAG_SHA: &str = "1111111111111111111111111111111111111111";

    fn env(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn beta_plan_defaults_and_buildbuddy_flags() {
        let plan = resolve_publish_plan(
            &[],
            &env(&[("BUILDBUDDY_API_KEY", "bb_secret")]),
            "3.86.0",
            SHA,
        )
        .unwrap();
        assert_eq!(plan.grade, PublishGrade::Beta);
        assert_eq!(plan.tag, "vitruvian-beta-latest");
        assert_eq!(plan.version, "3.86.0-beta.abcdef1");
        assert_eq!(plan.primary_asset, "Vitruvian-beta.dmg");
        assert_eq!(
            plan.bazel_flags,
            vec![
                "--config=macos-app",
                "--macos_cpus=arm64,x86_64",
                "--config=remotecache-ci",
                "--remote_header=x-buildbuddy-api-key=bb_secret"
            ]
        );
        assert_eq!(
            plan.staged_assets,
            vec![
                (
                    "Vitruvian-3.86.0-universal.dmg".into(),
                    "Vitruvian-beta-universal.dmg".into()
                ),
                (
                    "Vitruvian-3.86.0-arm64.dmg".into(),
                    "Vitruvian-beta-arm64.dmg".into()
                ),
                (
                    "Vitruvian-3.86.0-x86_64.dmg".into(),
                    "Vitruvian-beta-x86_64.dmg".into()
                ),
                (
                    "Vitruvian-3.86.0-universal.zip".into(),
                    "Vitruvian-beta-universal.zip".into()
                ),
                ("Vitruvian-3.86.0.dmg".into(), "Vitruvian-beta.dmg".into()),
            ]
        );
        let local =
            resolve_publish_plan(&[], &env(&[("BUILDBUDDY_API_KEY", "")]), "3.86.0", SHA).unwrap();
        assert_eq!(local.bazel_flags.len(), 2);
        let named =
            resolve_publish_plan(&[], &env(&[("TAG", "other-beta")]), "3.86.0", SHA).unwrap();
        assert_eq!(named.tag, "other-beta");
    }

    #[test]
    fn production_validation_gates() {
        let mut e = env(&[("GRADE", "production")]);
        let err = resolve_publish_plan(&[], &e, "3.86.0", SHA).unwrap_err();
        assert_eq!(err.0, 2);
        assert!(err.1.contains("needs RELEASE_TAG=vitruvian-vX.Y.Z"));

        e.insert("RELEASE_TAG".into(), "tabula-v1.0.0".into());
        let err = resolve_publish_plan(&[], &e, "3.86.0", SHA).unwrap_err();
        assert_eq!(err, (2, "publish: RELEASE_TAG=tabula-v1.0.0 is not a vitruvian-v* release; another component's release reached this rung".to_string()));

        e.insert("RELEASE_TAG".into(), "vitruvian-v3.85.0".into());
        let err = resolve_publish_plan(&[], &e, "3.86.0", SHA).unwrap_err();
        assert_eq!(err, (2, "publish: vitruvian-v3.85.0 is version 3.85.0, but this checkout builds 3.86.0; check out the release tag first".to_string()));

        e.insert("RELEASE_TAG".into(), "vitruvian-v3.86.0".into());
        let plan = resolve_publish_plan(&[], &e, "3.86.0", SHA).unwrap();
        assert_eq!(
            (plan.version.as_str(), plan.primary_asset.as_str()),
            ("3.86.0", "Vitruvian-3.86.0.dmg")
        );
        assert_eq!(plan.staged_assets[0].1, "Vitruvian-3.86.0-universal.dmg");
        assert_eq!(plan.staged_assets[4].1, "Vitruvian-3.86.0.dmg");

        // A dispatch from the release tag names the release.
        let tagged = env(&[
            ("GRADE", "production"),
            ("GITHUB_REF_TYPE", "tag"),
            ("GITHUB_REF_NAME", "vitruvian-v3.86.0"),
        ]);
        assert_eq!(
            resolve_publish_plan(&[], &tagged, "3.86.0", SHA)
                .unwrap()
                .tag,
            "vitruvian-v3.86.0"
        );
        let branch = env(&[
            ("GRADE", "production"),
            ("GITHUB_REF_TYPE", "branch"),
            ("GITHUB_REF_NAME", "vitruvian-v3.86.0"),
        ]);
        assert_eq!(
            resolve_publish_plan(&[], &branch, "3.86.0", SHA)
                .unwrap_err()
                .0,
            2
        );

        let unknown =
            resolve_publish_plan(&[], &env(&[("GRADE", "nightly")]), "3.86.0", SHA).unwrap_err();
        assert_eq!(
            unknown,
            (
                2,
                "publish: unknown GRADE=nightly (beta|production)".to_string()
            )
        );
    }

    #[test]
    fn render_homebrew_cask_names_the_universal_dmg() {
        let cask = render_homebrew_cask("3.86.0", "deadbeef");
        assert_eq!(
            cask,
            "cask \"vitruvian\" do\n  version \"3.86.0\"\n  sha256 \"deadbeef\"\n\n  url \"https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-v3.86.0/Vitruvian-3.86.0-universal.dmg\"\n  name \"Vitruvian\"\n  desc \"Desktop control hub for Vitruvian and AI coding sessions\"\n  homepage \"https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/vitruvian\"\n\n  app \"Vitruvian.app\"\nend\n"
        );
    }

    /// A package_release that leaves nothing in dist/.
    struct EmptyPackager {
        packaged: Vec<PathBuf>,
    }

    impl Packager for EmptyPackager {
        fn package(&mut self, _r: &mut dyn Runner, archive: &Path) -> Result<(), i32> {
            self.packaged.push(archive.to_path_buf());
            Ok(())
        }
    }

    struct Scene {
        _guard: TempDir,
        root: PathBuf,
        runner_temp: PathBuf,
    }

    fn scene(name: &str) -> Scene {
        let base = make_temp_dir(&std::env::temp_dir(), name).unwrap();
        let root = base.join("ws");
        fs::create_dir_all(root.join("bazel-out/darwin/bin").join(PKG_REL)).unwrap();
        fs::write(
            root.join("bazel-out/darwin/bin")
                .join(PKG_REL)
                .join("Vitruvian.zip"),
            b"zip",
        )
        .unwrap();
        let runner_temp = base.join("runner");
        fs::create_dir_all(&runner_temp).unwrap();
        Scene {
            _guard: TempDir(base.clone()),
            root,
            runner_temp,
        }
    }

    /// package_release, standing in: it writes dist/ under `root`.
    struct DistPackager {
        root: PathBuf,
        app_version: String,
        calls: Rc<RefCell<Vec<String>>>,
    }

    impl Packager for DistPackager {
        fn package(&mut self, r: &mut dyn Runner, archive: &Path) -> Result<(), i32> {
            run(r, &Cmd::new("PACKAGE").path(archive))?;
            let dist = self.root.join(PKG_REL).join("dist");
            fs::create_dir_all(&dist).unwrap();
            for suffix in [
                "-universal.dmg",
                "-arm64.dmg",
                "-x86_64.dmg",
                "-universal.zip",
                ".dmg",
            ] {
                fs::write(
                    dist.join(format!("Vitruvian-{}{}", self.app_version, suffix)),
                    suffix,
                )
                .unwrap();
            }
            self.calls
                .borrow_mut()
                .push(archive.to_string_lossy().to_string());
            Ok(())
        }
    }

    /// GitHub and the tools as a beta or production run sees them.
    struct World {
        tag: Result<String, String>,
        annotated_commit: String,
        compare: String,
        /// The compare call fails with this stderr.
        compare_error: Option<String>,
        /// The rolling tag's PATCH fails with this code and stderr.
        patch_error: Option<(i32, String)>,
        release_exists: bool,
        tap_has_it: bool,
    }

    fn world_runner(w: World) -> FakeRunner {
        FakeRunner::new(move |c| {
            let a: Vec<&str> = c.args.iter().map(String::as_str).collect();
            match (c.program.as_str(), a.as_slice()) {
                ("gh", ["api", path, "--jq", _]) if path.contains("/git/ref/tags/") => match &w.tag {
                    Ok(s) => Out::ok(&format!("{}\n", s)),
                    Err(e) => Out::fail(1, e),
                },
                ("gh", ["api", path, "--jq", ".object.sha"]) if path.contains("/git/tags/") => {
                    Out::ok(&format!("{}\n", w.annotated_commit))
                }
                ("gh", ["api", path, "--jq", ".status"]) if path.contains("/compare/") => {
                    match &w.compare_error {
                        Some(e) => Out::fail(1, e),
                        None => Out::ok(&format!("{}\n", w.compare)),
                    }
                }
                ("gh", ["api", "-X", "PATCH", ..]) => match &w.patch_error {
                    Some((code, e)) => Out::fail(*code, e),
                    None => Out::ok(""),
                },
                ("gh", ["release", "view", _]) => {
                    if w.release_exists {
                        Out::ok("")
                    } else {
                        Out::fail(1, "release not found")
                    }
                }
                ("bazel", ["cquery", ..]) => Out::ok(&format!(
                    "bazel-out/darwin/bin/{}/Vitruvian.zip\nbazel-out/darwin/bin/{}/Vitruvian.app\n",
                    PKG_REL, PKG_REL
                )),
                ("date", _) => Out::ok("2026-10-31T12:00:00Z\n"),
                ("shasum", [_, _, f]) => Out::ok(&format!("cafef00d  {}\n", f)),
                ("git", ["clone", _, _, _, dir]) => {
                    fs::create_dir_all(dir).unwrap();
                    Out::ok("")
                }
                ("git", ["-C", _, "diff", "--cached", "--quiet"]) => {
                    if w.tap_has_it {
                        Out::ok("")
                    } else {
                        Out::fail(1, "")
                    }
                }
                _ => Out::ok(""),
            }
        })
    }

    fn beta_world(tag: Result<&str, &str>, compare: &str) -> World {
        World {
            tag: tag.map(String::from).map_err(String::from),
            annotated_commit: String::new(),
            compare: compare.into(),
            compare_error: None,
            patch_error: None,
            release_exists: true,
            tap_has_it: false,
        }
    }

    fn go(s: &Scene, r: &mut FakeRunner, plan: &PublishPlan) -> Result<(), i32> {
        let mut p = DistPackager {
            root: s.root.clone(),
            app_version: plan.app_version.clone(),
            calls: Rc::new(RefCell::new(Vec::new())),
        };
        publish(
            r,
            &mut p,
            &s.root,
            plan,
            Some(&s.runner_temp),
            &s.runner_temp,
        )
    }

    fn beta_plan() -> PublishPlan {
        resolve_publish_plan(&[], &env(&[]), "3.86.0", SHA).unwrap()
    }

    fn first_write(r: &FakeRunner) -> Option<usize> {
        r.calls.iter().position(|c| {
            c.starts_with("bazel build")
                || c.starts_with("gh release create")
                || c.starts_with("gh release upload")
                || c.starts_with("gh api -X PATCH")
        })
    }

    #[test]
    fn a_first_beta_creates_the_release_uploads_moves_the_tag_and_writes_the_notes() {
        let s = scene("publish_beta_first");
        let mut w = beta_world(Err("gh: Not Found (HTTP 404)"), "");
        w.release_exists = false;
        let mut r = world_runner(w);
        assert_eq!(go(&s, &mut r, &beta_plan()), Ok(()));

        let c = &r.calls;
        assert_eq!(
            c[0],
            "gh api repos/{owner}/{repo}/git/ref/tags/vitruvian-beta-latest --jq .object.type + \" \" + .object.sha"
        );
        assert_eq!(c[1], "bazel build --config=macos-app --macos_cpus=arm64,x86_64 //apps/desktop/vitruvian:Vitruvian");
        assert_eq!(c[2], "bazel cquery --config=macos-app --macos_cpus=arm64,x86_64 --output=files //apps/desktop/vitruvian:Vitruvian");
        assert_eq!(
            c[3],
            format!(
                "PACKAGE {}",
                s.root
                    .join("bazel-out/darwin/bin")
                    .join(PKG_REL)
                    .join("Vitruvian.zip")
                    .display()
            )
        );
        let work = s.runner_temp.join("vitruvian-dist");
        let names = [
            "Vitruvian-beta-arm64.dmg",
            "Vitruvian-beta-universal.dmg",
            "Vitruvian-beta-universal.zip",
            "Vitruvian-beta-x86_64.dmg",
            "Vitruvian-beta.dmg",
        ];
        for (i, n) in names.iter().enumerate() {
            assert_eq!(
                c[4 + i],
                format!("shasum -a 256 {}", work.join(n).display())
            );
        }
        assert_eq!(c[9], "gh release view vitruvian-beta-latest");
        assert_eq!(c[10], format!("gh release create vitruvian-beta-latest --prerelease --target {} --title Vitruvian (Beta Rolling Release) --notes Rolling pre-release built automatically from commits landing on main.", SHA));
        for (i, n) in names.iter().enumerate() {
            assert_eq!(
                c[11 + i],
                format!(
                    "gh release upload vitruvian-beta-latest {} --clobber",
                    work.join(n).display()
                )
            );
        }
        assert_eq!(c[16], format!("gh api -X PATCH repos/{{owner}}/{{repo}}/git/refs/tags/vitruvian-beta-latest -f sha={} -F force=true", SHA));
        assert_eq!(c[17], "date -u +%Y-%m-%dT%H:%M:%SZ");
        assert_eq!(
            r.cmds[18].args,
            vec![
                "release".to_string(),
                "edit".into(),
                "vitruvian-beta-latest".into(),
                "--notes".into(),
                render_beta_release_notes("3.86.0-beta.abcdef1", SHA, "2026-10-31T12:00:00Z"),
            ]
        );
        assert_eq!(c.len(), 19);
        // The staged files are package_release's, renamed.
        assert_eq!(
            fs::read_to_string(work.join("Vitruvian-beta.dmg")).unwrap(),
            ".dmg"
        );
        assert_eq!(
            fs::read_to_string(work.join("Vitruvian-beta-universal.zip")).unwrap(),
            "-universal.zip"
        );
    }

    #[test]
    fn a_beta_ahead_of_the_tag_or_a_rerun_of_it_publishes_without_creating_the_release() {
        for compare in ["ahead", "identical"] {
            let s = scene("publish_beta_ahead");
            let mut r = world_runner(beta_world(Ok(&format!("commit {}", TAG_SHA)), compare));
            assert_eq!(go(&s, &mut r, &beta_plan()), Ok(()), "{}", compare);
            assert_eq!(
                r.calls[1],
                format!(
                    "gh api repos/{{owner}}/{{repo}}/compare/{}...{} --jq .status",
                    TAG_SHA, SHA
                )
            );
            assert_eq!(r.count("gh release create"), 0);
            assert_eq!(r.count("gh release upload"), 5);
            assert!(first_write(&r).unwrap() > 1, "decides before it writes");
        }
    }

    #[test]
    fn an_annotated_tag_is_compared_by_its_commit() {
        let s = scene("publish_beta_annotated");
        let mut w = beta_world(Ok("tag 9999999999999999999999999999999999999999"), "ahead");
        w.annotated_commit = TAG_SHA.into();
        let mut r = world_runner(w);
        assert_eq!(go(&s, &mut r, &beta_plan()), Ok(()));
        assert_eq!(r.calls[1], "gh api repos/{owner}/{repo}/git/tags/9999999999999999999999999999999999999999 --jq .object.sha");
        assert_eq!(
            r.calls[2],
            format!(
                "gh api repos/{{owner}}/{{repo}}/compare/{}...{} --jq .status",
                TAG_SHA, SHA
            )
        );
    }

    #[test]
    fn a_beta_behind_the_tag_publishes_nothing_and_succeeds() {
        let s = scene("publish_beta_behind");
        let mut r = world_runner(beta_world(Ok(&format!("commit {}", TAG_SHA)), "behind"));
        assert_eq!(go(&s, &mut r, &beta_plan()), Ok(()));
        assert_eq!(first_write(&r), None);
        assert_eq!(r.calls.len(), 2);
    }

    #[test]
    fn a_diverged_or_unknown_relation_refuses_before_any_write() {
        for compare in ["diverged", ""] {
            let s = scene("publish_beta_diverged");
            let mut r = world_runner(beta_world(Ok(&format!("commit {}", TAG_SHA)), compare));
            assert_eq!(go(&s, &mut r, &beta_plan()), Err(1));
            assert_eq!(first_write(&r), None);
        }
    }

    #[test]
    fn a_tag_that_cannot_be_read_refuses_to_publish_blind() {
        let s = scene("publish_beta_blind");
        let mut r = world_runner(beta_world(Err("gh: Bad credentials (HTTP 401)"), ""));
        assert_eq!(go(&s, &mut r, &beta_plan()), Err(1));
        assert_eq!(r.calls.len(), 1);
        assert!(
            r.stderr.contains("gh: Bad credentials (HTTP 401)"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn a_compare_that_fails_says_why_and_refuses_before_any_write() {
        let s = scene("publish_beta_compare_fails");
        let mut w = beta_world(Ok(&format!("commit {}", TAG_SHA)), "");
        w.compare_error = Some("gh: API rate limit exceeded for installation (HTTP 403)\n".into());
        let mut r = world_runner(w);
        assert_eq!(go(&s, &mut r, &beta_plan()), Err(1));
        assert_eq!(first_write(&r), None);
        assert!(
            r.stderr
                .contains("gh: API rate limit exceeded for installation (HTTP 403)"),
            "gh's own error reaches the log: {:?}",
            r.stderr
        );
        assert!(
            r.stderr.contains("/compare/"),
            "and names the call: {:?}",
            r.stderr
        );
    }

    #[test]
    fn a_rolling_tag_that_will_not_move_fails_the_run_before_the_notes() {
        let s = scene("publish_beta_patch_fails");
        let mut w = beta_world(Ok(&format!("commit {}", TAG_SHA)), "ahead");
        w.patch_error = Some((22, "gh: Reference update failed (HTTP 422)\n".into()));
        let mut r = world_runner(w);
        assert_eq!(go(&s, &mut r, &beta_plan()), Err(22));
        assert_eq!(r.count("gh api -X PATCH"), 1);
        assert_eq!(r.count("date"), 0);
        assert_eq!(
            r.count("gh release edit"),
            0,
            "no notes naming a commit the tag does not point at"
        );
        assert!(
            r.stderr.contains("Reference update failed"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn dry_run_never_prints_the_buildbuddy_key() {
        let plan = resolve_publish_plan(
            &["--dry-run".to_string()],
            &env(&[("BUILDBUDDY_API_KEY", "bb_SECRET_value")]),
            "3.86.0",
            SHA,
        )
        .unwrap();
        let out = dry_run_lines(&plan).join("\n");
        assert!(!out.contains("bb_SECRET_value"), "{}", out);
        assert!(
            out.contains("--config=remotecache-ci --remote_header=x-buildbuddy-api-key=<redacted> //apps/desktop/vitruvian:Vitruvian"),
            "{}",
            out
        );
        assert!(out.contains("dry-run: upload dist/Vitruvian-3.86.0.dmg as Vitruvian-beta.dmg"));
    }

    #[test]
    fn production_uploads_the_versioned_files_and_never_touches_the_tag() {
        let s = scene("publish_production");
        let e = env(&[
            ("GRADE", "production"),
            ("RELEASE_TAG", "vitruvian-v3.86.0"),
        ]);
        let plan = resolve_publish_plan(&[], &e, "3.86.0", SHA).unwrap();
        let mut r = world_runner(beta_world(Ok(""), ""));
        assert_eq!(go(&s, &mut r, &plan), Ok(()));
        assert!(
            r.calls[0].starts_with("bazel build"),
            "no beta guard for production"
        );
        assert_eq!(r.count("gh release view"), 0);
        assert_eq!(r.count("gh release create"), 0);
        assert_eq!(r.count("gh api"), 0);
        assert_eq!(r.count("gh release edit"), 0);
        assert_eq!(r.count("git"), 0, "no tap without a token");
        let uploads: Vec<&String> = r
            .calls
            .iter()
            .filter(|c| c.starts_with("gh release upload"))
            .collect();
        assert_eq!(uploads.len(), 5);
        assert!(uploads
            .iter()
            .all(|u| u.starts_with("gh release upload vitruvian-v3.86.0 ")));
        assert!(uploads[0].contains("/Vitruvian-3.86.0-arm64.dmg "));
        assert!(uploads[4].contains("/Vitruvian-3.86.0.dmg "));
    }

    #[test]
    fn production_with_a_tap_token_commits_the_cask_once() {
        for tap_has_it in [false, true] {
            let s = scene("publish_tap");
            let e = env(&[
                ("GRADE", "production"),
                ("RELEASE_TAG", "vitruvian-v3.86.0"),
                ("HOMEBREW_TAP_TOKEN", "tok"),
            ]);
            let plan = resolve_publish_plan(&[], &e, "3.86.0", SHA).unwrap();
            let mut w = beta_world(Ok(""), "");
            w.tap_has_it = tap_has_it;
            let mut r = world_runner(w);
            assert_eq!(go(&s, &mut r, &plan), Ok(()));
            let work = s.runner_temp.join("vitruvian-dist");
            let tap = work.join("tap");
            let at = r.position("git clone").unwrap();
            assert!(
                at > r.position("gh release upload").unwrap(),
                "the cask follows the uploads"
            );
            assert_eq!(r.calls[at], format!("git clone --depth 1 https://x-access-token:tok@github.com/VitruvianSoftware/homebrew-tap.git {}", tap.display()));
            assert_eq!(
                r.calls[at + 1],
                format!(
                    "shasum -a 256 {}",
                    work.join("Vitruvian-3.86.0-universal.dmg").display()
                )
            );
            assert_eq!(
                r.calls[at + 2],
                format!("git -C {} add Casks/vitruvian.rb", tap.display())
            );
            assert_eq!(
                r.calls[at + 3],
                format!("git -C {} diff --cached --quiet", tap.display())
            );
            assert_eq!(
                fs::read_to_string(tap.join("Casks/vitruvian.rb")).unwrap(),
                render_homebrew_cask("3.86.0", "cafef00d")
            );
            if tap_has_it {
                assert_eq!(r.calls.len(), at + 4);
            } else {
                assert_eq!(r.calls[at + 4], format!("git -C {} -c user.name=github-actions[bot] -c user.email=41898282+github-actions[bot]@users.noreply.github.com commit -q -m vitruvian 3.86.0", tap.display()));
                assert_eq!(
                    r.calls[at + 5],
                    format!("git -C {} push -q origin HEAD", tap.display())
                );
            }
        }
    }

    #[test]
    fn a_build_without_a_zip_or_a_package_without_the_dmg_fails() {
        let s = scene("publish_no_zip");
        let mut r = FakeRunner::new(|c| {
            if c.program == "bazel" && c.args[0] == "cquery" {
                Out::ok("bazel-out/darwin/bin/apps/desktop/vitruvian/Vitruvian.app\n")
            } else {
                Out::ok("")
            }
        });
        let plan = resolve_publish_plan(
            &[],
            &env(&[
                ("GRADE", "production"),
                ("RELEASE_TAG", "vitruvian-v3.86.0"),
            ]),
            "3.86.0",
            SHA,
        )
        .unwrap();
        assert_eq!(go(&s, &mut r, &plan), Err(1));
        assert_eq!(r.count("PACKAGE"), 0);

        let s = scene("publish_no_dmg");
        let mut r = world_runner(beta_world(Ok(""), ""));
        let mut p = EmptyPackager {
            packaged: Vec::new(),
        };
        assert_eq!(
            publish(
                &mut r,
                &mut p,
                &s.root,
                &plan,
                Some(&s.runner_temp),
                &s.runner_temp
            ),
            Err(1)
        );
        assert_eq!(p.packaged.len(), 1);
        assert_eq!(r.count("gh release upload"), 0);
    }

    #[test]
    fn a_failed_build_stops_with_its_code() {
        let s = scene("publish_build_fail");
        let mut r = FakeRunner::new(|c| {
            if c.program == "bazel" {
                Out::fail(37, "")
            } else {
                Out::ok("")
            }
        });
        let plan = resolve_publish_plan(
            &[],
            &env(&[
                ("GRADE", "production"),
                ("RELEASE_TAG", "vitruvian-v3.86.0"),
            ]),
            "3.86.0",
            SHA,
        )
        .unwrap();
        assert_eq!(go(&s, &mut r, &plan), Err(37));
    }
}
