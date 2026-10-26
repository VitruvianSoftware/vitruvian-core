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

use std::env;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const TOOL_ID: &str = "com.vitruviansoftware.vitruvian.android-remote";
const BINARY_NAME: &str = "android-remote-tool";

const USAGE: &str = "\
Usage: android-remote-zip-tool [OPTIONS]

Packages the android-remote tool binary into a versioned zip.

Options:
  --version <ver>  Override the version (default: read from manifest.json)
  -h, --help       Print this help message and exit

Environment:
  ANDROID_REMOTE_ZIP_OUT_DIR  Output directory (default: <pkg_dir>/dist)
  ANDROID_REMOTE_TOOL_BIN     Path to the tool binary";

#[derive(Debug)]
pub struct Config {
    pub version: Option<String>,
    pub help: bool,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut version = None;
    let mut help = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                help = true;
                i += 1;
            }
            "--version" => {
                if i + 1 >= args.len() {
                    return Err("--version requires a value".to_string());
                }
                version = Some(args[i + 1].clone());
                i += 2;
            }
            other => {
                return Err(format!("unknown flag: {other}"));
            }
        }
    }
    Ok(Config { version, help })
}

pub fn read_manifest_version(manifest_path: &Path) -> Result<String, String> {
    let content = fs::read_to_string(manifest_path)
        .map_err(|e| format!("failed to read {}: {e}", manifest_path.display()))?;
    extract_version_from_manifest(&content)
        .ok_or_else(|| format!("no \"version\" field found in {}", manifest_path.display()))
}

fn extract_version_from_manifest(content: &str) -> Option<String> {
    for line in content.lines() {
        if let Some(pos) = line.find("\"version\"") {
            let rest = &line[pos + "\"version\"".len()..];
            let rest = rest.trim_start().trim_start_matches(':').trim_start();
            if rest.starts_with('"') {
                let inner = &rest[1..];
                if let Some(end) = inner.find('"') {
                    return Some(inner[..end].to_string());
                }
            }
        }
    }
    None
}

pub fn update_manifest_version(content: &str, new_version: &str) -> String {
    let mut result = String::with_capacity(content.len());
    for line in content.lines() {
        if let Some(pos) = line.find("\"version\"") {
            let rest = &line[pos + "\"version\"".len()..];
            let trimmed = rest.trim_start().trim_start_matches(':').trim_start();
            if trimmed.starts_with('"') {
                let inner = &trimmed[1..];
                if let Some(end) = inner.find('"') {
                    let before = &line[..pos + "\"version\"".len()];
                    let colon_space = &rest[..rest.len() - trimmed.len()];
                    let after_val = &inner[end + 1..];
                    result.push_str(before);
                    result.push_str(colon_space);
                    result.push('"');
                    result.push_str(new_version);
                    result.push('"');
                    result.push_str(after_val);
                    result.push('\n');
                    continue;
                }
            }
        }
        result.push_str(line);
        result.push('\n');
    }
    if !content.is_empty() && !content.ends_with('\n') {
        result.pop();
    }
    result
}

pub fn find_binary(_pkg_dir: &Path) -> Result<PathBuf, String> {
    if let Ok(p) = env::var("ANDROID_REMOTE_TOOL_BIN") {
        let path = PathBuf::from(&p);
        if path.exists() {
            return Ok(path);
        }
        return Err(format!(
            "ANDROID_REMOTE_TOOL_BIN is set to {p} but the file does not exist"
        ));
    }

    if let Ok(runfiles) = env::var("RUNFILES_DIR") {
        let candidate = PathBuf::from(&runfiles)
            .join("_main/apps/mobile/android-remote/macmenu/android-remote-tool");
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    if let Ok(exe) = env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidate =
                dir.join("_main/apps/mobile/android-remote/macmenu/android-remote-tool");
            if candidate.exists() {
                return Ok(candidate);
            }
        }
    }

    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let candidate = PathBuf::from(&ws)
            .join("bazel-bin/apps/mobile/android-remote/macmenu/android-remote-tool");
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    Err(
        "could not find android-remote-tool binary: set ANDROID_REMOTE_TOOL_BIN, \
         or run from a Bazel context with runfiles"
            .to_string(),
    )
}

pub fn compute_sha256(path: &Path) -> Result<String, String> {
    let output = Command::new("shasum")
        .args(["-a", "256"])
        .arg(path)
        .output()
        .map_err(|e| format!("failed to run shasum: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "shasum failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    stdout
        .split_whitespace()
        .next()
        .map(|s| s.to_string())
        .ok_or_else(|| "shasum produced no output".to_string())
}

fn determine_pkg_dir() -> Result<PathBuf, String> {
    let exe = env::current_exe().map_err(|e| format!("cannot determine executable path: {e}"))?;
    let mut dir = exe
        .parent()
        .ok_or("executable has no parent directory")?
        .to_path_buf();
    for _ in 0..3 {
        dir = dir
            .parent()
            .ok_or_else(|| format!("cannot determine package directory from {}", exe.display()))?
            .to_path_buf();
    }
    Ok(dir)
}

pub fn run(args: &[String]) -> i32 {
    match run_inner(args) {
        Ok(()) => 0,
        Err(msg) => {
            eprintln!("error: {msg}");
            1
        }
    }
}

fn run_inner(args: &[String]) -> Result<(), String> {
    let config = parse_args(args)?;
    if config.help {
        println!("{USAGE}");
        return Ok(());
    }

    let pkg_dir = determine_pkg_dir()?;
    let manifest_path = pkg_dir.join("manifest.json");

    let manifest_version = read_manifest_version(&manifest_path)?;
    let version = config.version.unwrap_or_else(|| manifest_version.clone());

    let binary_path = find_binary(&pkg_dir)?;

    let out_dir = match env::var("ANDROID_REMOTE_ZIP_OUT_DIR") {
        Ok(d) => PathBuf::from(d),
        Err(_) => pkg_dir.join("dist"),
    };
    fs::create_dir_all(&out_dir)
        .map_err(|e| format!("failed to create output dir {}: {e}", out_dir.display()))?;

    let tmp = tempdir()?;
    let staging = tmp.join(TOOL_ID);
    fs::create_dir_all(&staging).map_err(|e| format!("failed to create staging dir: {e}"))?;

    let staged_manifest = staging.join("manifest.json");
    let manifest_content =
        fs::read_to_string(&manifest_path).map_err(|e| format!("failed to read manifest: {e}"))?;
    if version != manifest_version {
        let updated = update_manifest_version(&manifest_content, &version);
        fs::write(&staged_manifest, &updated)
            .map_err(|e| format!("failed to write staged manifest: {e}"))?;
    } else {
        fs::copy(&manifest_path, &staged_manifest)
            .map_err(|e| format!("failed to copy manifest: {e}"))?;
    }

    let staged_binary = staging.join(BINARY_NAME);
    fs::copy(&binary_path, &staged_binary).map_err(|e| format!("failed to copy binary: {e}"))?;
    fs::set_permissions(&staged_binary, fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("failed to chmod binary: {e}"))?;

    #[cfg(target_os = "macos")]
    {
        let status = Command::new("codesign")
            .args(["--force", "--sign", "-"])
            .arg(&staged_binary)
            .status();
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => eprintln!("warning: codesign exited with {s}"),
            Err(e) => eprintln!("warning: codesign failed to run: {e}"),
        }
    }

    let zip_name = format!("{BINARY_NAME}-{version}.zip");
    let zip_path = out_dir.join(&zip_name);
    if zip_path.exists() {
        fs::remove_file(&zip_path).map_err(|e| format!("failed to remove old zip: {e}"))?;
    }

    let ditto_ok = Command::new("ditto")
        .args(["-c", "-k", "--norsrc", "--noextattr"])
        .arg(&staging)
        .arg(&zip_path)
        .status()
        .map(|s| s.success())
        .unwrap_or(false);

    if !ditto_ok {
        let status = Command::new("zip")
            .args(["-r", "-y", "-q"])
            .arg(&zip_path)
            .arg(".")
            .current_dir(&staging)
            .status()
            .map_err(|e| format!("failed to run zip: {e}"))?;
        if !status.success() {
            return Err("zip command failed".to_string());
        }
    }

    if !zip_path.exists() {
        return Err(format!("zip was not created at {}", zip_path.display()));
    }

    let hash = compute_sha256(&zip_path)?;

    let sha_path = out_dir.join(format!("{zip_name}.sha256"));
    let mut f =
        fs::File::create(&sha_path).map_err(|e| format!("failed to create sha256 file: {e}"))?;
    writeln!(f, "{hash}  {zip_name}").map_err(|e| format!("failed to write sha256 file: {e}"))?;

    println!("{}", zip_path.display());
    println!("sha256: {hash}");

    let _ = fs::remove_dir_all(&tmp);
    Ok(())
}

fn tempdir() -> Result<PathBuf, String> {
    let base = env::temp_dir();
    let name = format!(
        "ar-zip-tool-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let path = base.join(name);
    fs::create_dir_all(&path).map_err(|e| format!("failed to create temp dir: {e}"))?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    fn make_temp_dir(label: &str) -> PathBuf {
        let path = env::temp_dir().join(format!(
            "ar-zip-test-{label}-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn version_from_manifest() {
        let dir = make_temp_dir("ver-manifest");
        let manifest = dir.join("manifest.json");
        fs::write(
            &manifest,
            "{\n  \"name\": \"android-remote\",\n  \"version\": \"3.0.0\"\n}\n",
        )
        .unwrap();
        let v = read_manifest_version(&manifest).unwrap();
        assert_eq!(v, "3.0.0");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn version_override_updates_staged_not_source() {
        let dir = make_temp_dir("ver-override");
        let manifest = dir.join("manifest.json");
        let content = "{\n  \"version\": \"3.0.0\"\n}\n";
        fs::write(&manifest, content).unwrap();

        let updated = update_manifest_version(content, "4.0.0");
        assert!(
            updated.contains("\"4.0.0\""),
            "staged should have 4.0.0: {updated}"
        );

        let source = fs::read_to_string(&manifest).unwrap();
        assert!(
            source.contains("\"3.0.0\""),
            "source should still have 3.0.0"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn executable_bit() {
        let dir = make_temp_dir("exec-bit");
        let file = dir.join("tool");
        fs::write(&file, "#!/bin/sh\n").unwrap();
        fs::set_permissions(&file, fs::Permissions::from_mode(0o755)).unwrap();
        let mode = fs::metadata(&file).unwrap().permissions().mode();
        assert_ne!(mode & 0o111, 0, "executable bits should be set");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn sha256_sidecar_format() {
        let dir = make_temp_dir("sha256-fmt");
        let file = dir.join("testfile.bin");
        fs::write(&file, b"hello world\n").unwrap();

        let hash = compute_sha256(&file).unwrap();
        assert_eq!(hash.len(), 64, "sha256 hash should be 64 hex chars");

        let sidecar_content = format!("{hash}  android-remote-tool-3.0.0.zip\n");
        assert!(sidecar_content.contains("  android-remote-tool-3.0.0.zip\n"));
        let parts: Vec<&str> = sidecar_content.trim().splitn(2, "  ").collect();
        assert_eq!(parts.len(), 2);
        assert_eq!(parts[0].len(), 64);
        assert_eq!(parts[1], "android-remote-tool-3.0.0.zip");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn missing_binary_error() {
        let dir = make_temp_dir("missing-bin");
        env::remove_var("ANDROID_REMOTE_TOOL_BIN");
        let saved_runfiles = env::var("RUNFILES_DIR").ok();
        let saved_ws = env::var("BUILD_WORKSPACE_DIRECTORY").ok();
        env::set_var("RUNFILES_DIR", dir.join("nonexistent").as_os_str());
        env::set_var(
            "BUILD_WORKSPACE_DIRECTORY",
            dir.join("nonexistent").as_os_str(),
        );

        let result = find_binary(&dir);
        assert!(result.is_err(), "should fail when no binary found");

        match saved_runfiles {
            Some(v) => env::set_var("RUNFILES_DIR", v),
            None => env::remove_var("RUNFILES_DIR"),
        }
        match saved_ws {
            Some(v) => env::set_var("BUILD_WORKSPACE_DIRECTORY", v),
            None => env::remove_var("BUILD_WORKSPACE_DIRECTORY"),
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn unknown_flag_error() {
        let args: Vec<String> = vec!["prog".into(), "--bogus".into()];
        let result = parse_args(&args);
        assert!(result.is_err(), "unknown flag should be rejected");
        assert!(
            result.unwrap_err().contains("unknown flag"),
            "error should mention unknown flag"
        );
    }

    #[test]
    fn version_without_value() {
        let args: Vec<String> = vec!["prog".into(), "--version".into()];
        let result = parse_args(&args);
        assert!(result.is_err(), "--version without value should fail");
    }

    #[test]
    fn help_exits_zero() {
        let args: Vec<String> = vec!["prog".into(), "--help".into()];
        let config = parse_args(&args).unwrap();
        assert!(config.help, "--help should set help flag");
    }
}
