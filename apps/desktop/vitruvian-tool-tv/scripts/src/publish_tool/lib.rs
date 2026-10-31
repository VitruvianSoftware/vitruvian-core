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
use std::path::{Path, PathBuf};
use std::process::Command;

const PKG: &str = "apps/desktop/vitruvian-tool-tv";

pub struct Config {
    pub root: PathBuf,
    pub tool_dir: PathBuf,
    pub tag: String,
    pub version: String,
    pub dry_run: bool,
}

pub fn derive_version(tag: &str) -> String {
    tag.strip_prefix("vitruvian-tool-tv-v")
        .unwrap_or(tag)
        .to_string()
}

pub fn parse_args(args: &[String]) -> Result<bool, String> {
    let mut dry_run = false;
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            other => {
                return Err(format!(
                    "error: unknown argument {} (only --dry-run)",
                    other
                ));
            }
        }
    }
    Ok(dry_run)
}

pub fn read_manifest_version(tool_dir: &Path) -> Result<String, String> {
    let manifest_path = tool_dir.join("vitruvian-tool.json");
    let content = fs::read_to_string(&manifest_path)
        .map_err(|e| format!("error: cannot read {}: {}", manifest_path.display(), e))?;
    let parsed: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| format!("error: invalid JSON in {}: {}", manifest_path.display(), e))?;
    parsed["version"]
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| format!("error: no \"version\" in {}", manifest_path.display()))
}

pub fn resolve_version(tag: &str, env_version: &str, tool_dir: &Path) -> Result<String, String> {
    if !env_version.is_empty() {
        return Ok(env_version.to_string());
    }
    if !tag.is_empty() {
        return Ok(derive_version(tag));
    }
    read_manifest_version(tool_dir)
}

pub fn check_manifest_version(tool_dir: &Path, version: &str) -> Result<(), String> {
    let manifest_version = read_manifest_version(tool_dir)?;
    if manifest_version != version {
        return Err(format!(
            "error: vitruvian-tool.json says {}, the release is {}",
            manifest_version, version
        ));
    }
    Ok(())
}

fn bazel_build(root: &Path) -> Result<(), String> {
    let mut cmd = Command::new("bazel");
    cmd.arg("build");
    if let Ok(key) = std::env::var("BUILDBUDDY_API_KEY") {
        cmd.arg("--config=remotecache-ci");
        cmd.arg(format!("--remote_header=x-buildbuddy-api-key={}", key));
    }
    cmd.arg(format!("//{}:tool-folder", PKG));
    cmd.current_dir(root);
    let status = cmd
        .status()
        .map_err(|e| format!("error: failed to run bazel: {}", e))?;
    if !status.success() {
        return Err("error: bazel build failed".to_string());
    }
    Ok(())
}

fn stage_folder(root: &Path, version: &str) -> Result<(PathBuf, PathBuf), String> {
    let built_dir = root.join("bazel-bin").join(PKG).join("built/vitruvian-tv");
    let manifest = built_dir.join("vitruvian-tool.json");
    if !manifest.exists() {
        return Err("error: bazel left no built/vitruvian-tv/vitruvian-tool.json".to_string());
    }

    let work_base = std::env::var("RUNNER_TEMP")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let work = work_base.join("vitruvian-tv-dist");
    if work.exists() {
        fs::remove_dir_all(&work)
            .map_err(|e| format!("error: cannot clean {}: {}", work.display(), e))?;
    }
    let stage = work.join("stage");
    let dist = work.join("dist");
    fs::create_dir_all(&stage)
        .map_err(|e| format!("error: cannot create {}: {}", stage.display(), e))?;
    fs::create_dir_all(&dist)
        .map_err(|e| format!("error: cannot create {}: {}", dist.display(), e))?;

    copy_dir_all(&built_dir, &stage)?;

    let tool_bin = stage.join("bin/tool");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&tool_bin, fs::Permissions::from_mode(0o755))
            .map_err(|e| format!("error: chmod bin/tool: {}", e))?;
    }

    check_macho(&tool_bin)?;

    let asset = format!("VitruvianTV-{}-tool.zip", version);
    let asset_path = dist.join(&asset);
    let status = Command::new("zip")
        .args(["-q", "-r", "-X"])
        .arg(&asset_path)
        .arg(".")
        .current_dir(&stage)
        .status()
        .map_err(|e| format!("error: zip: {}", e))?;
    if !status.success() {
        return Err("error: zip failed".to_string());
    }

    write_sha256(&dist, &asset)?;

    Ok((dist, asset_path))
}

fn copy_dir_all(src: &Path, dst: &Path) -> Result<(), String> {
    for entry in
        fs::read_dir(src).map_err(|e| format!("error: read_dir {}: {}", src.display(), e))?
    {
        let entry = entry.map_err(|e| format!("error: dir entry: {}", e))?;
        let ty = entry
            .file_type()
            .map_err(|e| format!("error: file_type: {}", e))?;
        let dest = dst.join(entry.file_name());
        if ty.is_dir() {
            fs::create_dir_all(&dest)
                .map_err(|e| format!("error: mkdir {}: {}", dest.display(), e))?;
            copy_dir_all(&entry.path(), &dest)?;
        } else {
            fs::copy(entry.path(), &dest)
                .map_err(|e| format!("error: copy to {}: {}", dest.display(), e))?;
        }
    }
    Ok(())
}

fn check_macho(tool_bin: &Path) -> Result<(), String> {
    let output = Command::new("file")
        .arg("-b")
        .arg(tool_bin)
        .output()
        .map_err(|e| format!("error: file -b: {}", e))?;
    let desc = String::from_utf8_lossy(&output.stdout);
    if !desc.contains("Mach-O") {
        return Err(format!(
            "error: bin/tool is not a Mac program ({}); package it on macOS",
            desc.trim()
        ));
    }
    Ok(())
}

fn write_sha256(dist: &Path, asset: &str) -> Result<(), String> {
    let sha_file = dist.join(format!("{}.sha256", asset));
    let result = Command::new("sha256sum")
        .arg(asset)
        .current_dir(dist)
        .output();
    let output = match result {
        Ok(o) if o.status.success() => o,
        _ => Command::new("shasum")
            .args(["-a", "256", asset])
            .current_dir(dist)
            .output()
            .map_err(|e| format!("error: shasum: {}", e))?,
    };
    if !output.status.success() {
        return Err("error: sha256 computation failed".to_string());
    }
    fs::write(&sha_file, &output.stdout)
        .map_err(|e| format!("error: write {}: {}", sha_file.display(), e))?;
    print!("{}", String::from_utf8_lossy(&output.stdout));
    Ok(())
}

fn print_size(asset_path: &Path) -> Result<(), String> {
    let meta = fs::metadata(asset_path)
        .map_err(|e| format!("error: stat {}: {}", asset_path.display(), e))?;
    eprintln!("==> {} (size: {})", asset_path.display(), meta.len());
    Ok(())
}

fn upload(tag: &str, dist: &Path, asset: &str) -> Result<(), String> {
    let repo = std::env::var("GITHUB_REPOSITORY")
        .unwrap_or_else(|_| "VitruvianSoftware/vitruvian-core".to_string());
    let asset_path = dist.join(asset);
    let sha_path = dist.join(format!("{}.sha256", asset));
    eprintln!(
        "==> Attaching {} to GitHub Release {} in {}",
        asset, tag, repo
    );
    let status = Command::new("gh")
        .args(["release", "upload", tag])
        .arg(&asset_path)
        .arg(&sha_path)
        .args(["--repo", &repo, "--clobber"])
        .status()
        .map_err(|e| format!("error: gh release upload: {}", e))?;
    if !status.success() {
        return Err("error: gh release upload failed".to_string());
    }
    eprintln!("==> Upload completed.");
    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let dry_run = match parse_args(args) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };

    let script_dir = match std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
    {
        Some(d) => d,
        None => std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
    };

    let tool_dir = std::env::var("TOOL_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            if let Ok(bwd) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
                return PathBuf::from(bwd).join(PKG);
            }
            script_dir
                .ancestors()
                .find(|p| p.join("vitruvian-tool.json").exists())
                .map(|p| p.to_path_buf())
                .unwrap_or_else(|| PathBuf::from("."))
        });
    let root = std::env::var("ROOT")
        .or_else(|_| std::env::var("BUILD_WORKSPACE_DIRECTORY"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            tool_dir
                .ancestors()
                .nth(3)
                .map(|p| p.to_path_buf())
                .unwrap_or_else(|| PathBuf::from("."))
        });

    let tag = std::env::var("TAG").unwrap_or_default();
    let env_version = std::env::var("VERSION").unwrap_or_default();
    let version = match resolve_version(&tag, &env_version, &tool_dir) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("{}", e);
            return 1;
        }
    };

    if let Err(e) = check_manifest_version(&tool_dir, &version) {
        eprintln!("{}", e);
        return 1;
    }

    eprintln!(
        "==> Packaging Vitruvian TV extension v{}{}",
        version,
        if tag.is_empty() {
            String::new()
        } else {
            format!(" (tag: {})", tag)
        }
    );

    if let Err(e) = bazel_build(&root) {
        eprintln!("{}", e);
        return 1;
    }

    let (dist, asset_path) = match stage_folder(&root, &version) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("{}", e);
            return 1;
        }
    };

    if let Err(e) = print_size(&asset_path) {
        eprintln!("{}", e);
        return 1;
    }

    let asset = format!("VitruvianTV-{}-tool.zip", version);

    if dry_run {
        eprintln!(
            "==> Dry run: the extension's zip is in {}; nothing uploaded.",
            dist.display()
        );
        return 0;
    }
    if tag.is_empty() {
        eprintln!(
            "==> No TAG: the extension's zip is in {}; nothing uploaded.",
            dist.display()
        );
        return 0;
    }

    if let Err(e) = upload(&tag, &dist, &asset) {
        eprintln!("{}", e);
        return 1;
    }

    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_derive_version_with_prefix() {
        assert_eq!(derive_version("vitruvian-tool-tv-v1.2.3"), "1.2.3");
    }

    #[test]
    fn test_derive_version_without_prefix() {
        assert_eq!(derive_version("1.0.0"), "1.0.0");
    }

    #[test]
    fn test_derive_version_partial_prefix() {
        assert_eq!(derive_version("v1.0.0"), "v1.0.0");
    }

    #[test]
    fn test_parse_args_dry_run() {
        let args = vec!["publish-tool".into(), "--dry-run".into()];
        assert_eq!(parse_args(&args).unwrap(), true);
    }

    #[test]
    fn test_parse_args_no_flags() {
        let args = vec!["publish-tool".into()];
        assert_eq!(parse_args(&args).unwrap(), false);
    }

    #[test]
    fn test_parse_args_unknown() {
        let args = vec!["publish-tool".into(), "--foo".into()];
        let err = parse_args(&args).unwrap_err();
        assert!(err.contains("unknown argument --foo"));
    }

    #[test]
    fn test_read_manifest_version_valid() {
        let dir = std::env::temp_dir().join("publish_tool_test_valid");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("vitruvian-tool.json"),
            r#"{"id":"dev.vitruvian.tv","version":"2.1.0"}"#,
        )
        .unwrap();
        assert_eq!(read_manifest_version(&dir).unwrap(), "2.1.0");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_manifest_version_missing_file() {
        let dir = std::env::temp_dir().join("publish_tool_test_missing");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        assert!(read_manifest_version(&dir).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_manifest_version_no_version_key() {
        let dir = std::env::temp_dir().join("publish_tool_test_nokey");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join("vitruvian-tool.json"),
            r#"{"id":"dev.vitruvian.tv"}"#,
        )
        .unwrap();
        assert!(read_manifest_version(&dir).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_check_manifest_version_match() {
        let dir = std::env::temp_dir().join("publish_tool_test_match");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("vitruvian-tool.json"), r#"{"version":"1.0.0"}"#).unwrap();
        assert!(check_manifest_version(&dir, "1.0.0").is_ok());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_check_manifest_version_mismatch() {
        let dir = std::env::temp_dir().join("publish_tool_test_mismatch");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("vitruvian-tool.json"), r#"{"version":"1.0.0"}"#).unwrap();
        let err = check_manifest_version(&dir, "2.0.0").unwrap_err();
        assert!(err.contains("vitruvian-tool.json says 1.0.0"));
        assert!(err.contains("the release is 2.0.0"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_resolve_version_env_version_takes_priority() {
        let dir = std::env::temp_dir().join("publish_tool_test_resolve_env");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("vitruvian-tool.json"), r#"{"version":"3.0.0"}"#).unwrap();
        assert_eq!(
            resolve_version("vitruvian-tool-tv-v1.0.0", "2.0.0", &dir).unwrap(),
            "2.0.0"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_resolve_version_from_tag() {
        let dir = std::env::temp_dir().join("publish_tool_test_resolve_tag");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("vitruvian-tool.json"), r#"{"version":"3.0.0"}"#).unwrap();
        assert_eq!(
            resolve_version("vitruvian-tool-tv-v1.2.3", "", &dir).unwrap(),
            "1.2.3"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_resolve_version_from_manifest() {
        let dir = std::env::temp_dir().join("publish_tool_test_resolve_manifest");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("vitruvian-tool.json"), r#"{"version":"3.0.0"}"#).unwrap();
        assert_eq!(resolve_version("", "", &dir).unwrap(), "3.0.0");
        let _ = fs::remove_dir_all(&dir);
    }
}
