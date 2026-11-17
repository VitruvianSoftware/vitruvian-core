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
// SOFTWARE.

//! Builds and publishes a Vitruvian Wand release.
//!
//! `bazel run //apps/suites/vitruvian-wand/build/release:publish -- <part> [--dry-run]`
//!
//! A release is three parts, each built where it can be: the Android APK and
//! the Linux desktop program on Linux, the Mac app on a Mac. Each part uploads
//! its own files to the GitHub Release named by `TAG`, so the three jobs of
//! `.github/workflows/vitruvian-wand-release.yaml` neither wait for nor
//! overwrite each other. `expected-assets` prints every file a finished
//! release holds; the workflow's last job checks the release against it.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const TAG_PREFIX: &str = "vitruvian-wand-v";
pub const PACKAGE_PATH: &str = "apps/suites/vitruvian-wand";
pub const APP_NAME: &str = "Vitruvian Wand";
/// What //tools/desktop-package names the Mac files after (`APP_NAME` without spaces).
pub const ARTIFACT_STEM: &str = "VitruvianWand";
pub const CASK_NAME: &str = "vitruvian-wand";
pub const CASK_DESC: &str = "Use a Daydream controller as a mouse and remote";
pub const CASK_HOMEPAGE: &str =
    "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/suites/vitruvian-wand";

pub const APK_TARGET: &str = "//apps/suites/vitruvian-wand/android:vitruvian_wand_apk";
pub const LINUX_TARGET: &str = "//apps/suites/vitruvian-wand/desktop:vitruvian-wand";
pub const MAC_TARGET: &str = "//apps/suites/vitruvian-wand/desktop/macos:VitruvianWand";
pub const MAC_ARCHS: &[&str] = &["arm64", "x86_64"];

const USAGE: &str = "usage: publish <android|linux|macos> [--dry-run]
       publish expected-assets <version>

  android  build the Android APK and upload it with its checksum
  linux    build the Linux desktop program and upload a .tar.gz with its checksum
  macos    build Vitruvian Wand.app for both Mac CPUs; //tools/desktop-package signs,
           notarises, makes the DMGs and the Homebrew cask, and uploads them
  --dry-run  build and check the files; upload nothing

Environment: TAG (vitruvian-wand-vX.Y.Z; without it nothing is uploaded),
VERSION (optional; must match TAG), BUILDBUDDY_API_KEY (optional cache),
GH_TOKEN for uploads.";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Part {
    Android,
    Linux,
    Macos,
}

impl Part {
    pub fn parse(s: &str) -> Option<Part> {
        match s {
            "android" => Some(Part::Android),
            "linux" => Some(Part::Linux),
            "macos" => Some(Part::Macos),
            _ => None,
        }
    }
}

/// The version a tag names: `vitruvian-wand-v0.2.0` is `0.2.0`.
pub fn version_from_tag(tag: &str) -> Option<String> {
    let v = tag.strip_prefix(TAG_PREFIX)?;
    is_semver(v).then(|| v.to_string())
}

pub fn is_semver(v: &str) -> bool {
    let parts: Vec<&str> = v.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
}

/// `VITRUVIAN_WAND_VERSION = "x.y.z"` in version.bzl.
pub fn version_in_bzl(text: &str) -> Option<String> {
    text.lines().find_map(|line| {
        let rest = line.trim().strip_prefix("VITRUVIAN_WAND_VERSION")?;
        quoted(rest.trim_start().strip_prefix('=')?)
    })
}

/// The `version` under `[workspace.package]` in Cargo.toml.
pub fn version_in_cargo(text: &str) -> Option<String> {
    let mut in_section = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_section = line == "[workspace.package]";
            continue;
        }
        if in_section {
            if let Some(rest) = line.strip_prefix("version") {
                if let Some(v) = rest.trim_start().strip_prefix('=') {
                    return quoted(v);
                }
            }
        }
    }
    None
}

/// Each of this workspace's own crates in Cargo.lock, with the version it records.
pub fn workspace_crates_in_lock(text: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut name: Option<String> = None;
    for line in text.lines() {
        let line = line.trim();
        if line == "[[package]]" {
            name = None;
        } else if let Some(v) = line.strip_prefix("name = ") {
            name = Some(v.trim_matches('"').to_string());
        } else if let Some(v) = line.strip_prefix("version = ") {
            if let Some(n) = name.take().filter(|n| n.starts_with("vitruvian-wand")) {
                out.push((n, v.trim_matches('"').to_string()));
            }
        }
    }
    out
}

/// The version .release-please-manifest.json records for this package.
pub fn version_in_manifest(text: &str) -> Option<String> {
    let key = format!("\"{PACKAGE_PATH}\"");
    let rest = &text[text.find(&key)? + key.len()..];
    quoted(rest.trim_start().strip_prefix(':')?)
}

fn quoted(s: &str) -> Option<String> {
    let s = s.trim_start().strip_prefix('"')?;
    let v = &s[..s.find('"')?];
    is_semver(v).then(|| v.to_string())
}

/// The files each part uploads (each file is followed by its `.sha256`).
pub fn part_assets(part: Part, version: &str) -> Vec<String> {
    let files: Vec<String> = match part {
        Part::Android => vec![format!("{ARTIFACT_STEM}-{version}.apk")],
        Part::Linux => vec![linux_archive(version)],
        Part::Macos => vec![
            format!("{ARTIFACT_STEM}-{version}-universal.dmg"),
            format!("{ARTIFACT_STEM}-{version}.dmg"),
            format!("{ARTIFACT_STEM}-{version}-arm64.dmg"),
            format!("{ARTIFACT_STEM}-{version}-x86_64.dmg"),
            format!("{ARTIFACT_STEM}-{version}-universal.zip"),
            // The same zip under the name older download links use.
            format!("{ARTIFACT_STEM}-{version}-macOS.zip"),
        ],
    };
    files
        .into_iter()
        .flat_map(|f| [f.clone(), format!("{f}.sha256")])
        .collect()
}

pub fn linux_archive(version: &str) -> String {
    format!("{ARTIFACT_STEM}-{version}-linux-x86_64.tar.gz")
}

/// Every file a finished release holds.
pub fn expected_assets(version: &str) -> Vec<String> {
    [Part::Android, Part::Linux, Part::Macos]
        .into_iter()
        .flat_map(|p| part_assets(p, version))
        .collect()
}

#[derive(Debug, PartialEq, Eq)]
pub struct Plan {
    pub part: Part,
    pub version: String,
    pub tag: String,
    pub dry_run: bool,
    pub bazel_flags: Vec<String>,
}

/// Decides what to build from the arguments, the environment and the
/// checkout's version.bzl. The checkout must be the release: a tag that names
/// another version would publish files whose names and contents disagree.
pub fn resolve_plan(
    args: &[String],
    env: &BTreeMap<String, String>,
    version_bzl: &str,
    host_os: &str,
) -> Result<Plan, String> {
    let mut part = None;
    let mut dry_run = false;
    for a in args {
        match a.as_str() {
            "--dry-run" => dry_run = true,
            other => match Part::parse(other) {
                Some(p) if part.is_none() => part = Some(p),
                _ => return Err(format!("publish: unexpected argument {other:?}\n{USAGE}")),
            },
        }
    }
    let part = part.ok_or_else(|| format!("publish: name a part\n{USAGE}"))?;
    // The desktop parts build for the machine they run on, so each must run on
    // its own OS: a Linux part built on a Mac would be a Mac program.
    let needs = match part {
        Part::Android => None,
        Part::Linux => Some("linux"),
        Part::Macos => Some("macos"),
    };
    if let Some(os) = needs {
        if os != host_os {
            return Err(format!(
                "publish: the {part:?} part builds on {os}, not {host_os}"
            ));
        }
    }

    let built = version_in_bzl(version_bzl)
        .ok_or("publish: version.bzl has no VITRUVIAN_WAND_VERSION = \"x.y.z\"")?;
    let tag = non_empty(env, "TAG").unwrap_or_default();
    if !tag.is_empty() {
        let named = version_from_tag(&tag)
            .ok_or_else(|| format!("publish: TAG {tag:?} is not {TAG_PREFIX}X.Y.Z"))?;
        if named != built {
            return Err(format!(
                "publish: TAG {tag} names {named}, but this checkout builds {built} \
                 (version.bzl); check out the tag"
            ));
        }
    }
    if let Some(v) = non_empty(env, "VERSION") {
        if v != built {
            return Err(format!(
                "publish: VERSION is {v}, but this checkout builds {built}"
            ));
        }
    }

    let mut bazel_flags = vec!["--compilation_mode=opt".to_string()];
    if part == Part::Macos {
        bazel_flags.push("--config=macos-app".to_string());
        bazel_flags.push(format!("--macos_cpus={}", MAC_ARCHS.join(",")));
    }
    if let Some(key) = non_empty(env, "BUILDBUDDY_API_KEY") {
        bazel_flags.push("--config=remotecache-ci".to_string());
        bazel_flags.push(format!("--remote_header=x-buildbuddy-api-key={key}"));
    }
    if part == Part::Macos && !dry_run && !tag.is_empty() {
        for key in ["NOTARY_KEY_ID", "NOTARY_ISSUER_ID", "NOTARY_API_KEY_P8"] {
            if non_empty(env, key).is_none() {
                return Err(format!(
                    "publish: a released Mac app must be notarised: {key} is not set \
                     (the release workflow passes the VITRUVIAN_NOTARY_* secrets)"
                ));
            }
        }
    }
    Ok(Plan {
        part,
        version: built,
        tag,
        dry_run,
        bazel_flags,
    })
}

fn non_empty(env: &BTreeMap<String, String>, key: &str) -> Option<String> {
    env.get(key).filter(|v| !v.trim().is_empty()).cloned()
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

/// //tools/desktop-package's arguments for the Mac part.
pub fn package_args(plan: &Plan, archive: &Path, dist: &Path) -> Vec<String> {
    let mut a: Vec<String> = vec![
        "--archive".into(),
        archive.display().to_string(),
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

/// The files of `wanted` that are missing or empty in `dist`.
pub fn missing_from(dist: &Path, wanted: &[String]) -> Vec<String> {
    wanted
        .iter()
        .filter(|f| {
            !fs::metadata(dist.join(f))
                .map(|m| m.is_file() && m.len() > 0)
                .unwrap_or(false)
        })
        .cloned()
        .collect()
}

/// `<sha256>  <name>`, the format `sha256sum -c` reads.
pub fn write_checksum(dist: &Path, name: &str) -> Result<(), String> {
    let (program, mut args) = if Command::new("sha256sum").arg("--version").output().is_ok() {
        ("sha256sum", vec![])
    } else {
        ("shasum", vec!["-a".to_string(), "256".to_string()])
    };
    args.push(name.to_string());
    let out = Command::new(program)
        .args(&args)
        .current_dir(dist)
        .output()
        .map_err(|e| format!("cannot run {program}: {e}"))?;
    if !out.status.success() {
        return Err(format!("{program} {name} failed"));
    }
    fs::write(dist.join(format!("{name}.sha256")), &out.stdout)
        .map_err(|e| format!("cannot write {name}.sha256: {e}"))?;
    print!("{}", String::from_utf8_lossy(&out.stdout));
    Ok(())
}

fn run_in(dir: &Path, program: &str, args: &[String], shown: &[String]) -> Result<(), String> {
    println!("+ {program} {}", shown.join(" "));
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

fn build_and_locate(plan: &Plan, workspace: &Path, target: &str) -> Result<PathBuf, String> {
    let mut build = vec!["build".to_string()];
    build.extend(plan.bazel_flags.iter().cloned());
    build.push(target.to_string());
    let mut shown = vec!["build".to_string()];
    shown.extend(redacted(&plan.bazel_flags));
    shown.push(target.to_string());
    run_in(workspace, "bazel", &build, &shown)?;

    let mut query = vec!["cquery".to_string()];
    query.extend(plan.bazel_flags.iter().cloned());
    query.extend(["--output=files".to_string(), target.to_string()]);
    let out = Command::new("bazel")
        .args(&query)
        .current_dir(workspace)
        .output()
        .map_err(|e| format!("cannot run bazel cquery: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "bazel cquery {target} failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    let file = String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map(|l| workspace.join(l))
        .ok_or_else(|| format!("bazel cquery named no output for {target}"))?;
    if !file.is_file() {
        return Err(format!("{} is not there after the build", file.display()));
    }
    Ok(file)
}

fn copy_out(src: &Path, dest: &Path) -> Result<(), String> {
    // Bazel outputs are read-only; the copy must not be, or a rerun cannot replace it.
    let bytes = fs::read(src).map_err(|e| format!("cannot read {}: {e}", src.display()))?;
    fs::write(dest, bytes).map_err(|e| format!("cannot write {}: {e}", dest.display()))
}

fn upload(plan: &Plan, dist: &Path, files: &[String]) -> Result<(), String> {
    let repo = std::env::var("GITHUB_REPOSITORY")
        .ok()
        .filter(|r| !r.is_empty())
        .unwrap_or_else(|| "VitruvianSoftware/vitruvian-core".to_string());
    let mut args = vec![
        "release".to_string(),
        "upload".to_string(),
        plan.tag.clone(),
    ];
    args.extend(files.iter().cloned());
    args.extend(["--repo".to_string(), repo, "--clobber".to_string()]);
    run_in(dist, "gh", &args, &args)
}

fn publish(plan: &Plan, workspace: &Path, packager: &Path) -> Result<(), String> {
    let dist = workspace.join(PACKAGE_PATH).join("dist");
    let _ = fs::remove_dir_all(&dist);
    fs::create_dir_all(&dist).map_err(|e| format!("cannot create {}: {e}", dist.display()))?;
    let wanted = part_assets(plan.part, &plan.version);

    match plan.part {
        Part::Android => {
            let apk = build_and_locate(plan, workspace, APK_TARGET)?;
            let name = &wanted[0];
            copy_out(&apk, &dist.join(name))?;
            write_checksum(&dist, name)?;
        }
        Part::Linux => {
            let bin = build_and_locate(plan, workspace, LINUX_TARGET)?;
            let stage = dist.join("stage");
            let folder = stage.join(format!("{ARTIFACT_STEM}-{}", plan.version));
            fs::create_dir_all(&folder).map_err(|e| format!("cannot create stage: {e}"))?;
            copy_out(&bin, &folder.join("vitruvian-wand"))?;
            set_executable(&folder.join("vitruvian-wand"))?;
            let pkg = workspace.join(PACKAGE_PATH);
            copy_out(&pkg.join("LICENSE"), &folder.join("LICENSE"))?;
            copy_out(&pkg.join("docs/setup-linux.md"), &folder.join("SETUP.md"))?;
            let archive = dist.join(&wanted[0]);
            let tar_args: Vec<String> = vec![
                "-czf".into(),
                archive.display().to_string(),
                "-C".into(),
                stage.display().to_string(),
                folder.file_name().unwrap().to_string_lossy().into_owned(),
            ];
            run_in(&dist, "tar", &tar_args, &tar_args)?;
            fs::remove_dir_all(&stage).map_err(|e| format!("cannot clean stage: {e}"))?;
            write_checksum(&dist, &wanted[0])?;
        }
        Part::Macos => {
            let archive = build_and_locate(plan, workspace, MAC_TARGET)?;
            // package-desktop signs, notarises, makes the DMGs and the cask,
            // and on a tagged release uploads them and pushes the cask.
            let args = package_args(plan, &archive, &dist);
            let status = Command::new(packager)
                .args(&args)
                .current_dir(workspace)
                .status()
                .map_err(|e| format!("cannot run package-desktop: {e}"))?;
            if !status.success() {
                return Err(format!("package-desktop failed ({status})"));
            }
            if !plan.tag.is_empty() && !plan.dry_run {
                // package-desktop uploaded and checked the release itself.
                return Ok(());
            }
        }
    }

    let missing = missing_from(&dist, &wanted);
    if !missing.is_empty() {
        return Err(format!("missing or empty in dist: {}", missing.join(", ")));
    }
    println!("==> {} in {}:", wanted.len(), dist.display());
    for f in &wanted {
        println!("  {f}");
    }
    if plan.dry_run || plan.tag.is_empty() || plan.part == Part::Macos {
        println!(
            "==> Nothing uploaded ({}).",
            if plan.dry_run { "dry run" } else { "no TAG" }
        );
        return Ok(());
    }
    upload(plan, &dist, &wanted)
}

#[cfg(unix)]
fn set_executable(p: &Path) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(p, fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("cannot chmod {}: {e}", p.display()))
}

#[cfg(not(unix))]
fn set_executable(_p: &Path) -> Result<(), String> {
    Ok(())
}

/// args[1] is //tools/desktop-package:package-desktop (Bazel's `args`), the rest
/// come from the command line.
pub fn run(args: &[String]) -> i32 {
    if args.iter().skip(1).any(|a| a == "--help" || a == "-h") {
        println!("{USAGE}");
        return 0;
    }
    if args.len() < 2 {
        eprintln!("publish: run it with `bazel run //apps/suites/vitruvian-wand/build/release:publish`\n{USAGE}");
        return 2;
    }
    let rest = &args[2..];
    if rest.first().map(String::as_str) == Some("expected-assets") {
        return match rest.get(1).filter(|v| is_semver(v)) {
            Some(v) if rest.len() == 2 => {
                for f in expected_assets(v) {
                    println!("{f}");
                }
                0
            }
            _ => {
                eprintln!("publish: expected-assets takes one version, X.Y.Z\n{USAGE}");
                2
            }
        };
    }

    let packager = fs::canonicalize(&args[1]).unwrap_or_else(|_| PathBuf::from(&args[1]));
    let env: BTreeMap<String, String> = std::env::vars().collect();
    let Some(workspace) = non_empty(&env, "BUILD_WORKSPACE_DIRECTORY").map(PathBuf::from) else {
        eprintln!("publish: run it with `bazel run`, which says where the checkout is");
        return 2;
    };
    let bzl_path = workspace.join(PACKAGE_PATH).join("version.bzl");
    let version_bzl = match fs::read_to_string(&bzl_path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("publish: cannot read {}: {e}", bzl_path.display());
            return 2;
        }
    };
    let plan = match resolve_plan(rest, &env, &version_bzl, std::env::consts::OS) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{e}");
            return 2;
        }
    };
    println!(
        "==> {APP_NAME} {} {:?}{}{}",
        plan.version,
        plan.part,
        if plan.tag.is_empty() {
            String::new()
        } else {
            format!(" (tag {})", plan.tag)
        },
        if plan.dry_run { ", dry run" } else { "" }
    );
    match publish(&plan, &workspace, &packager) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("publish: {e}");
            eprintln!(
                "publish: {APP_NAME} {} {:?} was NOT published",
                plan.version, plan.part
            );
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BZL: &str = "VITRUVIAN_WAND_VERSION = \"0.3.1\"  # x-release-please-version\n";

    fn env(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn args(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn reads_the_version_from_each_file() {
        assert_eq!(version_in_bzl(BZL).as_deref(), Some("0.3.1"));
        let cargo = "[workspace]\nmembers = []\n\n[workspace.package]\nversion = \"0.3.1\"\nedition = \"2024\"\n\n[workspace.dependencies]\nversion = \"9.9.9\"\n";
        assert_eq!(version_in_cargo(cargo).as_deref(), Some("0.3.1"));
        let manifest = "{\n  \"apps/suites/vitruvian-wand\": \"0.3.1\"\n}\n";
        assert_eq!(version_in_manifest(manifest).as_deref(), Some("0.3.1"));
        assert_eq!(version_in_manifest("{\"apps/other\": \"1.0.0\"}"), None);
        assert_eq!(version_in_bzl("VITRUVIAN_WAND_VERSION = \"1.2\""), None);
    }

    #[test]
    fn finds_the_workspace_crates_in_the_lock() {
        let lock = "[[package]]\nname = \"tokio\"\nversion = \"1.0.0\"\n\n[[package]]\nname = \"vitruvian-wand-core\"\nversion = \"0.3.1\"\ndependencies = []\n";
        assert_eq!(
            workspace_crates_in_lock(lock),
            vec![("vitruvian-wand-core".to_string(), "0.3.1".to_string())]
        );
    }

    #[test]
    fn a_tag_names_its_version() {
        assert_eq!(
            version_from_tag("vitruvian-wand-v0.2.0").as_deref(),
            Some("0.2.0")
        );
        assert_eq!(version_from_tag("vitruvian-watch-v0.2.0"), None);
        assert_eq!(version_from_tag("vitruvian-wand-v0.2"), None);
    }

    #[test]
    fn a_release_holds_every_part() {
        let all = expected_assets("0.3.1");
        assert_eq!(all.len(), 16, "{all:?}");
        for f in [
            "VitruvianWand-0.3.1.apk",
            "VitruvianWand-0.3.1.apk.sha256",
            "VitruvianWand-0.3.1-linux-x86_64.tar.gz",
            "VitruvianWand-0.3.1-linux-x86_64.tar.gz.sha256",
            "VitruvianWand-0.3.1-universal.dmg",
            "VitruvianWand-0.3.1.dmg",
            "VitruvianWand-0.3.1-arm64.dmg",
            "VitruvianWand-0.3.1-x86_64.dmg",
            "VitruvianWand-0.3.1-universal.zip.sha256",
            "VitruvianWand-0.3.1-macOS.zip",
        ] {
            assert!(all.contains(&f.to_string()), "{f} missing from {all:?}");
        }
        // Every file has its checksum beside it.
        for f in all.iter().filter(|f| !f.ends_with(".sha256")) {
            assert!(all.contains(&format!("{f}.sha256")), "{f} has no checksum");
        }
    }

    #[test]
    fn the_mac_names_match_what_package_desktop_writes() {
        // //tools/desktop-package names files after the app name, spaces removed.
        assert_eq!(APP_NAME.replace(' ', ""), ARTIFACT_STEM);
    }

    #[test]
    fn a_tag_for_another_version_is_refused() {
        let e = resolve_plan(
            &args(&["android"]),
            &env(&[("TAG", "vitruvian-wand-v0.3.0")]),
            BZL,
            "macos",
        )
        .unwrap_err();
        assert!(e.contains("0.3.0") && e.contains("0.3.1"), "{e}");
        let e = resolve_plan(
            &args(&["linux"]),
            &env(&[("VERSION", "0.4.0")]),
            BZL,
            "linux",
        )
        .unwrap_err();
        assert!(e.contains("0.4.0"), "{e}");
        let e =
            resolve_plan(&args(&["linux"]), &env(&[("TAG", "v0.3.1")]), BZL, "linux").unwrap_err();
        assert!(e.contains("vitruvian-wand-v"), "{e}");
    }

    #[test]
    fn a_matching_tag_plans_the_part() {
        let p = resolve_plan(
            &args(&["android"]),
            &env(&[("TAG", "vitruvian-wand-v0.3.1"), ("VERSION", "0.3.1")]),
            BZL,
            "macos",
        )
        .unwrap();
        assert_eq!(p.part, Part::Android);
        assert_eq!(p.version, "0.3.1");
        assert!(!p.dry_run);
        assert_eq!(p.bazel_flags, vec!["--compilation_mode=opt"]);
    }

    #[test]
    fn the_mac_part_builds_both_cpus_and_needs_notarising() {
        let e = resolve_plan(
            &args(&["macos"]),
            &env(&[("TAG", "vitruvian-wand-v0.3.1")]),
            BZL,
            "macos",
        )
        .unwrap_err();
        assert!(e.contains("notarised"), "{e}");
        let p = resolve_plan(
            &args(&["macos", "--dry-run"]),
            &env(&[("TAG", "vitruvian-wand-v0.3.1")]),
            BZL,
            "macos",
        )
        .unwrap();
        assert!(p
            .bazel_flags
            .contains(&"--macos_cpus=arm64,x86_64".to_string()));
        assert!(p.bazel_flags.contains(&"--config=macos-app".to_string()));
    }

    #[test]
    fn the_cache_key_is_never_printed() {
        let p = resolve_plan(
            &args(&["linux"]),
            &env(&[("BUILDBUDDY_API_KEY", "s3cret")]),
            BZL,
            "linux",
        )
        .unwrap();
        assert!(p.bazel_flags.iter().any(|f| f.contains("s3cret")));
        assert!(!redacted(&p.bazel_flags)
            .iter()
            .any(|f| f.contains("s3cret")));
    }

    #[test]
    fn bad_arguments_are_refused() {
        assert!(resolve_plan(&args(&[]), &env(&[]), BZL, "linux").is_err());
        assert!(resolve_plan(&args(&["ios"]), &env(&[]), BZL, "linux").is_err());
        assert!(resolve_plan(&args(&["android", "linux"]), &env(&[]), BZL, "linux").is_err());
    }

    #[test]
    fn each_desktop_part_builds_on_its_own_os() {
        let e = resolve_plan(&args(&["linux"]), &env(&[]), BZL, "macos").unwrap_err();
        assert!(e.contains("linux"), "{e}");
        assert!(resolve_plan(&args(&["macos", "--dry-run"]), &env(&[]), BZL, "linux").is_err());
        assert!(resolve_plan(&args(&["android"]), &env(&[]), BZL, "linux").is_ok());
        assert!(resolve_plan(&args(&["android"]), &env(&[]), BZL, "macos").is_ok());
    }

    #[test]
    fn package_desktop_gets_the_tag_only_when_there_is_one() {
        let mut p = resolve_plan(&args(&["macos", "--dry-run"]), &env(&[]), BZL, "macos").unwrap();
        let a = package_args(&p, Path::new("/x/VitruvianWand.zip"), Path::new("/d"));
        assert!(!a.contains(&"--tag".to_string()));
        assert!(a.contains(&"--dry-run".to_string()));
        assert!(a
            .windows(2)
            .any(|w| w[0] == "--app-name" && w[1] == "Vitruvian Wand"));
        assert!(a
            .windows(2)
            .any(|w| w[0] == "--archive" && w[1] == "/x/VitruvianWand.zip"));
        p.tag = "vitruvian-wand-v0.3.1".into();
        p.dry_run = false;
        let a = package_args(&p, Path::new("/x/VitruvianWand.zip"), Path::new("/d"));
        assert!(a
            .windows(2)
            .any(|w| w[0] == "--tag" && w[1] == "vitruvian-wand-v0.3.1"));
        assert!(!a.contains(&"--dry-run".to_string()));
    }

    #[test]
    fn missing_and_empty_files_are_named() {
        let dir = std::env::temp_dir().join(format!("wand-release-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("a"), b"x").unwrap();
        fs::write(dir.join("b"), b"").unwrap();
        let missing = missing_from(&dir, &args(&["a", "b", "c"]));
        assert_eq!(missing, args(&["b", "c"]));
        fs::remove_dir_all(&dir).unwrap();
    }

    /// The three files release-please bumps must agree, or the build stamps
    /// one version and the release is named another.
    #[test]
    fn the_checkout_agrees_on_one_version() {
        let read = |env_key: &str| {
            let p = std::env::var(env_key).unwrap_or_else(|_| panic!("{env_key} not set"));
            let p = std::env::var("RUNFILES_DIR")
                .map(|r| Path::new(&r).join("_main").join(&p))
                .ok()
                .filter(|p| p.is_file())
                .unwrap_or_else(|| PathBuf::from(&p));
            fs::read_to_string(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))
        };
        let bzl = version_in_bzl(&read("WAND_VERSION_BZL")).expect("version.bzl version");
        let cargo = version_in_cargo(&read("WAND_CARGO_TOML")).expect("Cargo.toml version");
        let manifest =
            version_in_manifest(&read("WAND_MANIFEST")).expect("release-please manifest version");
        assert_eq!(bzl, cargo, "version.bzl and Cargo.toml disagree");
        assert_eq!(
            bzl, manifest,
            "version.bzl and .release-please-manifest.json disagree"
        );
        // Cargo.lock records each of the workspace's crates at the workspace
        // version; release-please bumps them (release-please-config.json).
        let locked = workspace_crates_in_lock(&read("WAND_CARGO_LOCK"));
        let config = read("WAND_RELEASE_CONFIG");
        assert!(locked.len() >= 4, "Cargo.lock lists {locked:?}");
        for (name, version) in &locked {
            assert_eq!(&bzl, version, "Cargo.lock has {name} at {version}");
            assert!(
                config.contains(&format!("@.name.value=='{name}'")),
                "release-please-config.json does not bump {name} in Cargo.lock"
            );
        }
    }
}
