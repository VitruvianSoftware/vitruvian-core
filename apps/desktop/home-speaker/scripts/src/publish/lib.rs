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

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct Config {
    pub workspace: PathBuf,
    pub tag_name: String,
    pub version: String,
    pub is_beta: bool,
    pub dry_run: bool,
    pub skip_build: bool,
    pub zip_out_dir: Option<String>,
}

pub fn derive_version(tag: &str) -> String {
    if let Some(v) = tag.strip_prefix("home-speaker-v") {
        return v.to_string();
    }
    if let Some(v) = tag.strip_prefix("v") {
        return v.to_string();
    }
    tag.to_string()
}

pub fn read_version_from_swift(path: &Path) -> Result<String, String> {
    let content =
        fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    for line in content.lines() {
        if let Some(pos) = line.find("current = \"") {
            let after = &line[pos + "current = \"".len()..];
            if let Some(end) = after.find('"') {
                let ver = &after[..end];
                if !ver.is_empty() {
                    return Ok(ver.to_string());
                }
            }
        }
    }
    Err(format!(
        "no current = \"...\" version found in {}",
        path.display()
    ))
}

pub fn read_manifest_version(manifest_path: &Path) -> Result<String, String> {
    let content = fs::read_to_string(manifest_path)
        .map_err(|e| format!("cannot read {}: {e}", manifest_path.display()))?;
    for line in content.lines() {
        if let Some(pos) = line.find("\"version\"") {
            let after = line[pos + "\"version\"".len()..].trim_start();
            if let Some(rest) = after.strip_prefix(':') {
                let rest = rest.trim_start();
                if let Some(rest) = rest.strip_prefix('"') {
                    if let Some(end) = rest.find('"') {
                        return Ok(rest[..end].to_string());
                    }
                }
            }
        }
    }
    Err(format!(
        "no \"version\" field in {}",
        manifest_path.display()
    ))
}

pub fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            _ => out.push(c),
        }
    }
    out
}

pub fn parse_config() -> Result<Config, String> {
    let workspace = std::env::var("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let tag_name = std::env::var("TAG")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| std::env::var("TAG_NAME").ok())
        .unwrap_or_default();
    let mut version = std::env::var("VERSION").unwrap_or_default();
    let is_beta = std::env::var("IS_BETA").unwrap_or_default() == "true";
    let dry_run = std::env::var("DRY_RUN").unwrap_or_default() == "true";
    let skip_build = std::env::var("PUBLISH_SKIP_BUILD").unwrap_or_default() == "1";
    let zip_out_dir = std::env::var("HOME_SPEAKER_ZIP_OUT_DIR").ok();

    if version.is_empty() && !tag_name.is_empty() {
        version = derive_version(&tag_name);
    }

    if version.is_empty() {
        let app_dir = resolve_app_dir(&workspace);
        let version_swift = app_dir.join("Sources/HomeSpeakerCore/Version.swift");
        if version_swift.is_file() {
            version = read_version_from_swift(&version_swift)?;
        }
    }

    if version.is_empty() {
        return Err("VERSION is not set and TAG is empty; cannot determine version".into());
    }

    Ok(Config {
        workspace,
        tag_name,
        version,
        is_beta,
        dry_run,
        skip_build,
        zip_out_dir,
    })
}

pub fn resolve_app_dir(workspace: &Path) -> PathBuf {
    let candidate = workspace.join("apps/desktop/home-speaker");
    if candidate.join("Package.swift").is_file() {
        return candidate;
    }
    if workspace.join("Package.swift").is_file()
        && workspace
            .join("Sources/HomeSpeakerCore/Version.swift")
            .is_file()
    {
        return workspace.to_path_buf();
    }
    candidate
}

pub fn resolve_repo_root(app_dir: &Path) -> PathBuf {
    if let Ok(out) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .current_dir(app_dir)
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return PathBuf::from(s);
            }
        }
    }
    let fallback = app_dir.join("../../..");
    fs::canonicalize(&fallback).unwrap_or(fallback)
}

pub fn build_gh_create_args(tag: &str, is_beta: bool, zip: &Path, sha: &Path) -> Vec<String> {
    let mut args = vec![
        "release".to_string(),
        "create".to_string(),
        tag.to_string(),
        zip.display().to_string(),
        sha.display().to_string(),
        "--title".to_string(),
        tag.to_string(),
    ];
    if is_beta {
        args.push("--prerelease".to_string());
    } else {
        args.push("--latest".to_string());
    }
    args
}

pub fn build_gh_upload_args(tag: &str, zip: &Path, sha: &Path) -> Vec<String> {
    vec![
        "release".to_string(),
        "upload".to_string(),
        tag.to_string(),
        zip.display().to_string(),
        sha.display().to_string(),
        "--clobber".to_string(),
    ]
}

pub fn dry_run_message(zip_path: &Path, sha_path: &Path) -> String {
    format!(
        "[DRY RUN] Built {} and {}, skipping GitHub release upload.",
        zip_path.display(),
        sha_path.display()
    )
}

fn run_command_in(program: &str, args: &[&str], cwd: Option<&Path>) -> Result<(), String> {
    let mut cmd = Command::new(program);
    cmd.args(args);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let status = cmd
        .status()
        .map_err(|e| format!("failed to run {}: {}", program, e))?;
    if !status.success() {
        return Err(format!(
            "{} {} exited with {}",
            program,
            args.first().copied().unwrap_or(""),
            status
        ));
    }
    Ok(())
}

pub fn check_universal_archs(binary: &Path, label: &str) -> Result<(), String> {
    let out = Command::new("lipo")
        .arg("-archs")
        .arg(binary)
        .output()
        .map_err(|e| format!("failed to run lipo -archs on {}: {}", binary.display(), e))?;
    if !out.status.success() {
        return Err(format!("lipo -archs failed on {}", binary.display()));
    }
    let archs = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if !archs.contains("arm64") || !archs.contains("x86_64") {
        return Err(format!("expected a universal {label}, got: {archs}"));
    }
    Ok(())
}

fn make_temp_dir(prefix: &str) -> Result<PathBuf, String> {
    let base = std::env::temp_dir();
    let pid = std::process::id();
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = base.join(format!("{prefix}-{pid}-{ts}"));
    fs::create_dir_all(&dir)
        .map_err(|e| format!("cannot create temp dir {}: {e}", dir.display()))?;
    Ok(dir)
}

pub fn compute_sha256(path: &Path) -> Result<String, String> {
    let out = Command::new("shasum")
        .args(["-a", "256"])
        .arg(path)
        .output()
        .map_err(|e| format!("cannot run shasum: {e}"))?;
    if !out.status.success() {
        return Err("shasum -a 256 failed".to_string());
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    stdout
        .split_whitespace()
        .next()
        .map(|s| s.to_string())
        .ok_or_else(|| "shasum produced no output".to_string())
}

pub fn zip_tool_bundle(
    app_dir: &Path,
    tool_bin: &Path,
    version: &str,
    dist_dir: &Path,
    require_universal: bool,
) -> Result<PathBuf, String> {
    if require_universal {
        check_universal_archs(tool_bin, "tool binary")?;
    }

    let manifest = app_dir.join("tool/vitruvian-tool.json");
    let manifest_version = read_manifest_version(&manifest)?;
    if manifest_version != version {
        return Err(format!(
            "tool/vitruvian-tool.json says {manifest_version}, the release is {version}"
        ));
    }

    let stage = make_temp_dir("hs-tool-stage")?;
    let result = (|| -> Result<PathBuf, String> {
        let hs_dir = stage.join("homespeaker");
        let bin_dir = hs_dir.join("bin");
        fs::create_dir_all(&bin_dir)
            .map_err(|e| format!("cannot create {}: {e}", bin_dir.display()))?;
        fs::copy(&manifest, hs_dir.join("vitruvian-tool.json"))
            .map_err(|e| format!("cannot copy vitruvian-tool.json: {e}"))?;
        let dst_tool = bin_dir.join("tool");
        fs::copy(tool_bin, &dst_tool).map_err(|e| format!("cannot copy tool binary: {e}"))?;
        fs::set_permissions(&dst_tool, fs::Permissions::from_mode(0o755))
            .map_err(|e| format!("cannot chmod tool binary: {e}"))?;

        if let Ok(client_id) = std::env::var("HOMESPEAKER_GOOGLE_CLIENT_ID") {
            if !client_id.is_empty() {
                println!("==> Shipping the Google OAuth client in the tool");
                let client_secret =
                    std::env::var("HOMESPEAKER_GOOGLE_CLIENT_SECRET").unwrap_or_default();
                let oauth_json = format!(
                    "{{\"client_id\": \"{}\", \"client_secret\": \"{}\"}}\n",
                    json_escape(&client_id),
                    json_escape(&client_secret)
                );
                fs::write(hs_dir.join("google-oauth-client.json"), oauth_json)
                    .map_err(|e| format!("cannot write google-oauth-client.json: {e}"))?;
            }
        }

        fs::create_dir_all(dist_dir)
            .map_err(|e| format!("cannot create {}: {e}", dist_dir.display()))?;
        let dist_abs = fs::canonicalize(dist_dir)
            .map_err(|e| format!("cannot canonicalize {}: {e}", dist_dir.display()))?;
        let asset = dist_abs.join(format!("HomeSpeaker-{version}-tool.zip"));
        let _ = fs::remove_file(&asset);

        let asset_str = asset.to_str().ok_or("invalid asset path")?;
        run_command_in("zip", &["-q", "-r", "-X", asset_str, "."], Some(&hs_dir))?;

        let size = fs::metadata(&asset)
            .map_err(|e| format!("cannot stat {}: {e}", asset.display()))?
            .len();
        let sha = compute_sha256(&asset)?;
        println!("==> {}", asset.display());
        println!("size: {size}");
        println!("sha256: {sha}");
        Ok(asset)
    })();

    let _ = fs::remove_dir_all(&stage);
    result
}

pub fn bundle_app(
    app_dir: &Path,
    executable: &Path,
    version: &str,
    output_dir: &Path,
    require_universal: bool,
) -> Result<PathBuf, String> {
    let app_name = "HomeSpeaker";
    let app_bundle = output_dir.join(format!("{app_name}.app"));
    let plist = app_bundle.join("Contents/Info.plist");

    println!("==> Assembling {app_name}.app v{version}");

    let req_univ = require_universal
        || std::env::var("HOMESPEAKER_REQUIRE_UNIVERSAL").unwrap_or_default() == "1";
    if req_univ {
        check_universal_archs(executable, "binary")?;
    }

    let _ = fs::remove_dir_all(&app_bundle);
    let macos_dir = app_bundle.join("Contents/MacOS");
    let resources_dir = app_bundle.join("Contents/Resources");
    fs::create_dir_all(&macos_dir)
        .map_err(|e| format!("cannot create {}: {e}", macos_dir.display()))?;
    fs::create_dir_all(&resources_dir)
        .map_err(|e| format!("cannot create {}: {e}", resources_dir.display()))?;

    let dst_exe = macos_dir.join(app_name);
    fs::copy(executable, &dst_exe)
        .map_err(|e| format!("cannot copy executable {}: {e}", executable.display()))?;
    fs::set_permissions(&dst_exe, fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("cannot chmod {}: {e}", dst_exe.display()))?;

    let icon_src = app_dir.join("Resources/AppIcon.icns");
    if icon_src.is_file() {
        fs::copy(&icon_src, resources_dir.join("AppIcon.icns"))
            .map_err(|e| format!("cannot copy AppIcon.icns: {e}"))?;
    }

    let plist_src = app_dir.join("Resources/Info.plist");
    fs::copy(&plist_src, &plist)
        .map_err(|e| format!("cannot copy {}: {e}", plist_src.display()))?;

    let plist_str = plist.to_str().ok_or("invalid plist path")?;
    let set_short = format!("Set :CFBundleShortVersionString {version}");
    let set_ver = format!("Set :CFBundleVersion {version}");
    run_command_in(
        "/usr/libexec/PlistBuddy",
        &["-c", &set_short, plist_str],
        None,
    )?;
    run_command_in(
        "/usr/libexec/PlistBuddy",
        &["-c", &set_ver, plist_str],
        None,
    )?;

    if let Ok(client_id) = std::env::var("HOMESPEAKER_GOOGLE_CLIENT_ID") {
        if !client_id.is_empty() {
            println!("==> Embedding Google OAuth client id");
            let client_secret =
                std::env::var("HOMESPEAKER_GOOGLE_CLIENT_SECRET").unwrap_or_default();
            let set_cid = format!("Set :GoogleOAuthClientID {client_id}");
            let set_csec = format!("Set :GoogleOAuthClientSecret {client_secret}");
            run_command_in(
                "/usr/libexec/PlistBuddy",
                &["-c", &set_cid, plist_str],
                None,
            )?;
            run_command_in(
                "/usr/libexec/PlistBuddy",
                &["-c", &set_csec, plist_str],
                None,
            )?;
        }
    }

    fs::write(app_bundle.join("Contents/PkgInfo"), b"APPL????")
        .map_err(|e| format!("cannot write PkgInfo: {e}"))?;

    println!(
        "==> Signing {} (ad-hoc, hardened runtime)",
        app_bundle.display()
    );
    let bundle_str = app_bundle.to_str().ok_or("invalid bundle path")?;
    run_command_in(
        "codesign",
        &[
            "--force",
            "--deep",
            "--options",
            "runtime",
            "--sign",
            "-",
            bundle_str,
        ],
        None,
    )?;
    run_command_in(
        "codesign",
        &["--verify", "--deep", "--strict", bundle_str],
        None,
    )?;

    println!("==> {} successfully created", app_bundle.display());
    Ok(app_bundle)
}

pub fn expected_dist_files(version: &str) -> Vec<String> {
    let artifacts = [
        format!("HomeSpeaker-{version}-universal.dmg"),
        format!("HomeSpeaker-{version}-arm64.dmg"),
        format!("HomeSpeaker-{version}-x86_64.dmg"),
        format!("HomeSpeaker-{version}-universal.zip"),
        format!("HomeSpeaker-{version}-tool.zip"),
    ];
    let mut files = Vec::with_capacity(artifacts.len() * 2);
    for artifact in &artifacts {
        files.push(artifact.clone());
        files.push(format!("{artifact}.sha256"));
    }
    files
}

pub fn verify_dist_artifacts(dist_dir: &Path, version: &str) -> Result<(), Vec<String>> {
    let mut missing = Vec::new();
    for file in expected_dist_files(version) {
        let path = dist_dir.join(&file);
        let non_empty = fs::metadata(&path).map(|m| m.len() > 0).unwrap_or(false);
        if !non_empty {
            missing.push(file);
        }
    }
    if missing.is_empty() {
        Ok(())
    } else {
        Err(missing)
    }
}

pub fn run(args: &[String]) -> i32 {
    let mut cli_dry_run = false;
    for arg in args.iter().skip(1) {
        if arg == "--help" || arg == "-h" {
            eprintln!(
                "Usage: publish [--dry-run]\n\n\
                 Builds universal HomeSpeaker.app + homespeaker-tool, packages DMGs/zips,\n\
                 and publishes release assets via tools/desktop-package."
            );
            return 0;
        }
        if arg == "--dry-run" {
            cli_dry_run = true;
        }
    }

    let mut config = match parse_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {}", e);
            return 1;
        }
    };
    if cli_dry_run {
        config.dry_run = true;
    }

    let app_dir = resolve_app_dir(&config.workspace);
    let version = &config.version;
    let tag = &config.tag_name;

    if tag.is_empty() {
        println!("==> Packaging HomeSpeaker release v{version}");
    } else {
        println!("==> Packaging HomeSpeaker release v{version} (tag: {tag})");
    }

    println!("==> Building universal release binary with SwiftPM");
    if let Err(e) = run_command_in(
        "swift",
        &[
            "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64",
        ],
        Some(&app_dir),
    ) {
        eprintln!("error: {e}");
        return 1;
    }

    let show_bin = match Command::new("swift")
        .args([
            "build",
            "-c",
            "release",
            "--arch",
            "arm64",
            "--arch",
            "x86_64",
            "--show-bin-path",
        ])
        .current_dir(&app_dir)
        .output()
    {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        Ok(o) => {
            eprintln!(
                "error: swift build --show-bin-path failed: {}",
                String::from_utf8_lossy(&o.stderr)
            );
            return 1;
        }
        Err(e) => {
            eprintln!("error: failed to run swift: {e}");
            return 1;
        }
    };

    let bin_dir = PathBuf::from(&show_bin);
    let bin = bin_dir.join("HomeSpeaker");
    let bin_str = bin.to_str().unwrap_or("");
    if let Err(e) = run_command_in("lipo", &["-info", bin_str], Some(&app_dir)) {
        eprintln!("error: {e}");
        return 1;
    }

    let bin_arm64 = bin_dir.join("HomeSpeaker-arm64");
    let bin_x86_64 = bin_dir.join("HomeSpeaker-x86_64");
    if let Err(e) = run_command_in(
        "lipo",
        &[
            bin_str,
            "-thin",
            "arm64",
            "-output",
            bin_arm64.to_str().unwrap_or(""),
        ],
        Some(&app_dir),
    ) {
        eprintln!("error: {e}");
        return 1;
    }
    if let Err(e) = run_command_in(
        "lipo",
        &[
            bin_str,
            "-thin",
            "x86_64",
            "-output",
            bin_x86_64.to_str().unwrap_or(""),
        ],
        Some(&app_dir),
    ) {
        eprintln!("error: {e}");
        return 1;
    }

    println!("==> Assembling standalone HomeSpeaker.app bundles (universal, arm64, x86_64)");
    let dist_dir = app_dir.join("dist");
    let _ = fs::remove_dir_all(&dist_dir);
    let stage_universal = dist_dir.join("stage-universal");
    let stage_arm64 = dist_dir.join("stage-arm64");
    let stage_x86_64 = dist_dir.join("stage-x86_64");
    for d in [&stage_universal, &stage_arm64, &stage_x86_64] {
        if let Err(e) = fs::create_dir_all(d) {
            eprintln!("error: cannot create {}: {e}", d.display());
            return 1;
        }
    }

    println!("==> Zipping the HomeSpeaker tool for the Vitruvian app");
    let tool_bin = bin_dir.join("homespeaker-tool");
    if let Err(e) = run_command_in(
        "lipo",
        &["-info", tool_bin.to_str().unwrap_or("")],
        Some(&app_dir),
    ) {
        eprintln!("error: {e}");
        return 1;
    }
    if let Err(e) = zip_tool_bundle(&app_dir, &tool_bin, version, &dist_dir, true) {
        eprintln!("error: {e}");
        return 1;
    }

    if let Err(e) = bundle_app(&app_dir, &bin, version, &stage_universal, true) {
        eprintln!("error: {e}");
        return 1;
    }
    if let Err(e) = bundle_app(&app_dir, &bin_arm64, version, &stage_arm64, false) {
        eprintln!("error: {e}");
        return 1;
    }
    if let Err(e) = bundle_app(&app_dir, &bin_x86_64, version, &stage_x86_64, false) {
        eprintln!("error: {e}");
        return 1;
    }

    let universal_app = stage_universal.join("HomeSpeaker.app");
    let dist_app = dist_dir.join("HomeSpeaker.app");
    if let Err(e) = run_command_in(
        "ditto",
        &[
            universal_app.to_str().unwrap_or(""),
            dist_app.to_str().unwrap_or(""),
        ],
        Some(&app_dir),
    ) {
        eprintln!("error: {e}");
        return 1;
    }

    let root = resolve_repo_root(&app_dir);
    let tool_zip = format!("HomeSpeaker-{version}-tool.zip");

    println!(
        "==> Invoking shared tools/desktop-package helper for packaging and release distribution"
    );
    let pkg_tmp = match make_temp_dir("hs-pkg-desktop") {
        Ok(d) => d,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    let lib_rs = root.join("tools/desktop-package/src/lib.rs");
    let main_rs = root.join("tools/desktop-package/src/main.rs");
    let rlib_out = pkg_tmp.join("libpackage_desktop.rlib");
    let bin_out = pkg_tmp.join("package-desktop");

    let compile_res = run_command_in(
        "rustc",
        &[
            "--edition",
            "2021",
            "--crate-type",
            "lib",
            "--crate-name",
            "package_desktop",
            lib_rs.to_str().unwrap_or(""),
            "-o",
            rlib_out.to_str().unwrap_or(""),
        ],
        None,
    )
    .and_then(|_| {
        let extern_arg = format!("package_desktop={}", rlib_out.display());
        run_command_in(
            "rustc",
            &[
                "--edition",
                "2021",
                main_rs.to_str().unwrap_or(""),
                "-L",
                pkg_tmp.to_str().unwrap_or(""),
                "--extern",
                &extern_arg,
                "-o",
                bin_out.to_str().unwrap_or(""),
            ],
            None,
        )
    });

    if let Err(e) = compile_res {
        let _ = fs::remove_dir_all(&pkg_tmp);
        eprintln!("error: failed to compile tools/desktop-package: {e}");
        return 1;
    }

    let mut pkg_args: Vec<String> = vec![
        "--app-path".into(),
        dist_app.display().to_string(),
        "--app-name".into(),
        "HomeSpeaker".into(),
        "--version".into(),
        version.clone(),
        "--cask-name".into(),
        "home-speaker".into(),
        "--cask-desc".into(),
        "macOS menu bar app for speech notifications and smart speaker announcements".into(),
        "--cask-homepage".into(),
        "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/apps/desktop/home-speaker"
            .into(),
        "--dist-dir".into(),
        dist_dir.display().to_string(),
        "--sync-downloads".into(),
        "--require-asset".into(),
        tool_zip,
    ];
    if config.dry_run {
        pkg_args.push("--dry-run".into());
    }
    if !tag.is_empty() {
        pkg_args.push("--tag".into());
        pkg_args.push(tag.clone());
    }

    let pkg_status = Command::new(&bin_out).args(&pkg_args).status();
    let _ = fs::remove_dir_all(&pkg_tmp);
    match pkg_status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!("error: package-desktop exited with {s}");
            return 1;
        }
        Err(e) => {
            eprintln!("error: failed to run package-desktop: {e}");
            return 1;
        }
    }

    if let Err(missing) = verify_dist_artifacts(&dist_dir, version) {
        for file in missing {
            eprintln!("error: packaging left no {file} in dist");
        }
        eprintln!("error: HomeSpeaker {version} was NOT packaged; see the helper's output above");
        return 1;
    }

    println!("==> HomeSpeaker release packaging completed successfully.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_from_tag_home_speaker() {
        assert_eq!(derive_version("home-speaker-v1.2.3"), "1.2.3");
    }

    #[test]
    fn version_from_tag_v_prefix() {
        assert_eq!(derive_version("v1.2.3"), "1.2.3");
    }

    #[test]
    fn version_passthrough() {
        assert_eq!(derive_version("1.2.3"), "1.2.3");
    }

    #[test]
    fn version_from_tag_strips_only_first_prefix() {
        assert_eq!(derive_version("home-speaker-v0.1.0-beta"), "0.1.0-beta");
        assert_eq!(derive_version("v0.1.0-rc1"), "0.1.0-rc1");
    }

    #[test]
    fn dry_run_message_format() {
        let zip = Path::new("/tmp/dist/home-speaker-tool-1.2.3.zip");
        let sha = Path::new("/tmp/dist/home-speaker-tool-1.2.3.zip.sha256");
        let msg = dry_run_message(zip, sha);
        assert!(msg.starts_with("[DRY RUN]"));
        assert!(msg.contains("/tmp/dist/home-speaker-tool-1.2.3.zip"));
        assert!(msg.contains("/tmp/dist/home-speaker-tool-1.2.3.zip.sha256"));
        assert!(msg.contains("skipping GitHub release upload"));
    }

    #[test]
    fn is_beta_flag_creates_prerelease() {
        let zip = Path::new("tool.zip");
        let sha = Path::new("tool.zip.sha256");
        let args = build_gh_create_args("home-speaker-v1.0.0", true, zip, sha);
        assert!(args.contains(&"--prerelease".to_string()));
        assert!(!args.contains(&"--latest".to_string()));
    }

    #[test]
    fn non_beta_creates_latest() {
        let zip = Path::new("tool.zip");
        let sha = Path::new("tool.zip.sha256");
        let args = build_gh_create_args("home-speaker-v1.0.0", false, zip, sha);
        assert!(args.contains(&"--latest".to_string()));
        assert!(!args.contains(&"--prerelease".to_string()));
    }

    #[test]
    fn upload_args_include_clobber() {
        let zip = Path::new("tool.zip");
        let sha = Path::new("tool.zip.sha256");
        let args = build_gh_upload_args("home-speaker-v1.0.0", zip, sha);
        assert!(args.contains(&"--clobber".to_string()));
        assert!(args.contains(&"home-speaker-v1.0.0".to_string()));
    }

    #[test]
    fn create_args_include_title() {
        let zip = Path::new("tool.zip");
        let sha = Path::new("tool.zip.sha256");
        let args = build_gh_create_args("home-speaker-v2.0.0", false, zip, sha);
        let title_idx = args.iter().position(|a| a == "--title").unwrap();
        assert_eq!(args[title_idx + 1], "home-speaker-v2.0.0");
    }

    #[test]
    fn create_args_include_assets() {
        let zip = Path::new("/dist/tool.zip");
        let sha = Path::new("/dist/tool.zip.sha256");
        let args = build_gh_create_args("tag", false, zip, sha);
        assert!(args.contains(&"/dist/tool.zip".to_string()));
        assert!(args.contains(&"/dist/tool.zip.sha256".to_string()));
    }

    #[test]
    fn read_version_from_swift_extracts_current() {
        let dir = make_temp_dir("hs-ver-swift-test").unwrap();
        let file = dir.join("Version.swift");
        fs::write(
            &file,
            "public enum HomeSpeakerVersion {\n    public static let current = \"1.36.1\" // x-release-please-version\n}\n",
        )
        .unwrap();
        assert_eq!(read_version_from_swift(&file).unwrap(), "1.36.1");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn json_escape_handles_quotes_and_backslashes() {
        assert_eq!(json_escape(r#"ab"cd\ef"#), r#"ab\"cd\\ef"#);
    }

    #[test]
    fn verify_dist_artifacts_detects_missing_and_passes_when_present() {
        let dir = make_temp_dir("hs-verify-dist-test").unwrap();
        let err = verify_dist_artifacts(&dir, "1.2.3").unwrap_err();
        assert_eq!(err.len(), 10);

        for f in expected_dist_files("1.2.3") {
            fs::write(dir.join(f), b"non-empty").unwrap();
        }
        assert!(verify_dist_artifacts(&dir, "1.2.3").is_ok());
        let _ = fs::remove_dir_all(&dir);
    }
}
