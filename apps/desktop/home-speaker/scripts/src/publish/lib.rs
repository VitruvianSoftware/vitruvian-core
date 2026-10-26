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

pub fn parse_config() -> Result<Config, String> {
    let workspace = std::env::var("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let tag_name = std::env::var("TAG_NAME").unwrap_or_default();
    let mut version = std::env::var("VERSION").unwrap_or_default();
    let is_beta = std::env::var("IS_BETA").unwrap_or_default() == "true";
    let dry_run = std::env::var("DRY_RUN").unwrap_or_default() == "true";
    let skip_build = std::env::var("PUBLISH_SKIP_BUILD").unwrap_or_default() == "1";
    let zip_out_dir = std::env::var("HOME_SPEAKER_ZIP_OUT_DIR").ok();

    if version.is_empty() && !tag_name.is_empty() {
        version = derive_version(&tag_name);
    }

    if version.is_empty() {
        return Err("VERSION is not set and TAG_NAME is empty; cannot determine version".into());
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

fn build_gh_edit_args(tag: &str) -> Vec<String> {
    vec![
        "release".to_string(),
        "edit".to_string(),
        tag.to_string(),
        "--title".to_string(),
        tag.to_string(),
    ]
}

fn run_command(program: &str, args: &[String]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|e| format!("failed to run {}: {}", program, e))?;
    if !status.success() {
        return Err(format!(
            "{} {} exited with {}",
            program,
            args.first().unwrap_or(&String::new()),
            status
        ));
    }
    Ok(())
}

fn release_exists(tag: &str) -> bool {
    Command::new("gh")
        .args(["release", "view", tag])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn dry_run_message(zip_path: &Path, sha_path: &Path) -> String {
    format!(
        "[DRY RUN] Built {} and {}, skipping GitHub release upload.",
        zip_path.display(),
        sha_path.display()
    )
}

pub fn run(args: &[String]) -> i32 {
    for arg in args.iter().skip(1) {
        if arg == "--help" || arg == "-h" {
            eprintln!(
                "Usage: publish\n\n\
                 Reads configuration from environment variables:\n  \
                 BUILD_WORKSPACE_DIRECTORY, TAG_NAME, VERSION, IS_BETA,\n  \
                 DRY_RUN, PUBLISH_SKIP_BUILD, HOME_SPEAKER_ZIP_OUT_DIR"
            );
            return 0;
        }
    }

    let config = match parse_config() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {}", e);
            return 1;
        }
    };

    if !config.skip_build {
        eprintln!("==> Building home-speaker-tool with Bazel");
        let build_args: Vec<String> = [
            "build",
            "--config=macos-app",
            "//apps/desktop/home-speaker:home-speaker-tool",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        if let Err(e) = run_command("bazel", &build_args) {
            eprintln!("error: bazel build failed: {}", e);
            return 1;
        }
    }

    let app_dir = config.workspace.join("apps/desktop/home-speaker");
    let zip_tool = app_dir.join("scripts/zip-tool.sh");
    let zip_args = vec!["--version".to_string(), config.version.clone()];

    eprintln!("==> Running zip-tool.sh --version {}", config.version);
    let mut cmd = Command::new("bash");
    cmd.arg(&zip_tool).args(&zip_args);
    if let Some(ref dir) = config.zip_out_dir {
        cmd.env("HOME_SPEAKER_ZIP_OUT_DIR", dir);
    }
    let status = cmd.status();
    match status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!("error: zip-tool.sh exited with {}", s);
            return 1;
        }
        Err(e) => {
            eprintln!("error: failed to run zip-tool.sh: {}", e);
            return 1;
        }
    }

    let out_dir = config
        .zip_out_dir
        .as_ref()
        .map(PathBuf::from)
        .unwrap_or_else(|| app_dir.join("dist"));
    let zip_name = format!("home-speaker-tool-{}.zip", config.version);
    let zip_path = out_dir.join(&zip_name);
    let sha_path = out_dir.join(format!("{}.sha256", zip_name));

    if !zip_path.exists() {
        eprintln!("error: expected zip not found: {}", zip_path.display());
        return 1;
    }
    if !sha_path.exists() {
        eprintln!(
            "error: expected sha256 sidecar not found: {}",
            sha_path.display()
        );
        return 1;
    }

    if config.dry_run {
        println!("{}", dry_run_message(&zip_path, &sha_path));
        return 0;
    }

    if config.tag_name.is_empty() {
        eprintln!("error: TAG_NAME is required for publishing (not a dry run)");
        return 1;
    }

    let tag = &config.tag_name;
    if release_exists(tag) {
        eprintln!("==> Uploading to existing release {}", tag);
        let upload_args = build_gh_upload_args(tag, &zip_path, &sha_path);
        if let Err(e) = run_command("gh", &upload_args) {
            eprintln!("error: gh release upload failed: {}", e);
            return 1;
        }
        let edit_args = build_gh_edit_args(tag);
        if let Err(e) = run_command("gh", &edit_args) {
            eprintln!("error: gh release edit failed: {}", e);
            return 1;
        }
    } else {
        eprintln!("==> Creating release {}", tag);
        let create_args = build_gh_create_args(tag, config.is_beta, &zip_path, &sha_path);
        if let Err(e) = run_command("gh", &create_args) {
            eprintln!("error: gh release create failed: {}", e);
            return 1;
        }
    }

    println!(
        "Published home-speaker-tool {} to release {}",
        config.version, tag
    );
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
}
