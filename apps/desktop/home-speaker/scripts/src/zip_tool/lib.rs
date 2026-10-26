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
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

const TOOL_ID: &str = "com.vitruviansoftware.vitruvian.home-speaker";
const BINARY_NAME: &str = "home-speaker-tool";

#[derive(Debug)]
pub struct Config {
    pub version_override: Option<String>,
    pub show_help: bool,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut version_override = None;
    let mut show_help = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                show_help = true;
                i += 1;
            }
            "--version" => {
                if i + 1 >= args.len() {
                    return Err("--version requires a value".to_string());
                }
                version_override = Some(args[i + 1].clone());
                i += 2;
            }
            other => {
                return Err(format!("unknown flag: {other}"));
            }
        }
    }
    Ok(Config {
        version_override,
        show_help,
    })
}

pub fn read_manifest_version(manifest_path: &Path) -> Result<String, String> {
    let content = fs::read_to_string(manifest_path)
        .map_err(|e| format!("cannot read {}: {e}", manifest_path.display()))?;
    parse_version_from_manifest(&content)
        .ok_or_else(|| format!("no \"version\" field in {}", manifest_path.display()))
}

fn parse_version_from_manifest(content: &str) -> Option<String> {
    let needle = "\"version\"";
    let mut search = content.as_bytes();
    while let Some(pos) = find_subsequence(search, needle.as_bytes()) {
        let after = &search[pos + needle.len()..];
        let rest = std::str::from_utf8(after).ok()?;
        let rest = rest.trim_start();
        if let Some(rest) = rest.strip_prefix(':') {
            let rest = rest.trim_start();
            if let Some(rest) = rest.strip_prefix('"') {
                if let Some(end) = rest.find('"') {
                    return Some(rest[..end].to_string());
                }
            }
        }
        search = &search[pos + needle.len()..];
    }
    None
}

fn find_subsequence(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

pub fn determine_pkg_dir() -> Result<PathBuf, String> {
    let exe = env::current_exe().map_err(|e| format!("cannot determine exe path: {e}"))?;
    let mut dir = exe.parent().ok_or("exe has no parent")?.to_path_buf();
    // Walk up from scripts/src/zip_tool -> scripts/src -> scripts -> <pkg_dir>
    for _ in 0..3 {
        dir = dir
            .parent()
            .ok_or_else(|| format!("cannot find pkg_dir from {}", exe.display()))?
            .to_path_buf();
    }
    Ok(dir)
}

pub fn find_binary(pkg_dir: &Path) -> Result<PathBuf, String> {
    if let Ok(val) = env::var("HOME_SPEAKER_TOOL_BIN") {
        let p = PathBuf::from(&val);
        if p.exists() {
            return Ok(p);
        }
        return Err(format!("HOME_SPEAKER_TOOL_BIN={val} does not exist"));
    }

    let runfiles_rel = Path::new("_main/apps/desktop/home-speaker/home-speaker-tool");
    if let Ok(rd) = env::var("RUNFILES_DIR") {
        let candidate = PathBuf::from(&rd).join(runfiles_rel);
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    if let Ok(exe) = env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            let candidate = exe_dir.join(runfiles_rel);
            if candidate.exists() {
                return Ok(candidate);
            }
        }
    }

    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let candidate =
            PathBuf::from(&ws).join("bazel-bin/apps/desktop/home-speaker/home-speaker-tool");
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    let bazel_bin = pkg_dir
        .parent()
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .map(|root| root.join("bazel-bin/apps/desktop/home-speaker/home-speaker-tool"));
    if let Some(candidate) = bazel_bin {
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    Err("cannot find home-speaker-tool binary: set HOME_SPEAKER_TOOL_BIN or run from a Bazel context".to_string())
}

pub fn stage_files(
    version_override: Option<&str>,
    manifest_version: &str,
    pkg_dir: &Path,
    binary_path: &Path,
    staging_dir: &Path,
) -> Result<(), String> {
    let tool_dir = staging_dir.join(TOOL_ID);
    fs::create_dir_all(&tool_dir).map_err(|e| format!("cannot create staging dir: {e}"))?;

    let src_manifest = pkg_dir.join("manifest.json");
    let dst_manifest = tool_dir.join("manifest.json");
    if let Some(ver) = version_override {
        if ver != manifest_version {
            let content = fs::read_to_string(&src_manifest)
                .map_err(|e| format!("cannot read manifest: {e}"))?;
            let updated = content.replace(
                &format!("\"version\": \"{manifest_version}\""),
                &format!("\"version\": \"{ver}\""),
            );
            fs::write(&dst_manifest, updated)
                .map_err(|e| format!("cannot write staged manifest: {e}"))?;
        } else {
            fs::copy(&src_manifest, &dst_manifest)
                .map_err(|e| format!("cannot copy manifest: {e}"))?;
        }
    } else {
        fs::copy(&src_manifest, &dst_manifest).map_err(|e| format!("cannot copy manifest: {e}"))?;
    }

    let dst_binary = tool_dir.join(BINARY_NAME);
    fs::copy(binary_path, &dst_binary).map_err(|e| format!("cannot copy binary: {e}"))?;
    fs::set_permissions(&dst_binary, fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("cannot chmod binary: {e}"))?;

    let icon_src = pkg_dir.join("icon.svg");
    if icon_src.exists() {
        let icon_dst = tool_dir.join("icon.svg");
        fs::copy(&icon_src, &icon_dst).map_err(|e| format!("cannot copy icon.svg: {e}"))?;
    }

    codesign_if_macos(&dst_binary);

    Ok(())
}

fn codesign_if_macos(binary: &Path) {
    #[cfg(target_os = "macos")]
    {
        let status = Command::new("codesign")
            .args(["--force", "--sign", "-"])
            .arg(binary)
            .status();
        match status {
            Ok(s) if !s.success() => {
                eprintln!("warning: codesign exited with {}", s.code().unwrap_or(-1));
            }
            Err(e) => {
                eprintln!("warning: codesign failed: {e}");
            }
            _ => {}
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        let _ = binary;
    }
}

fn create_zip(staging_dir: &Path, zip_path: &Path) -> Result<(), String> {
    let tool_dir = staging_dir.join(TOOL_ID);
    let ditto = Command::new("ditto")
        .args(["-c", "-k", "--norsrc", "--noextattr"])
        .arg(&tool_dir)
        .arg(zip_path)
        .status();
    match ditto {
        Ok(s) if s.success() => return Ok(()),
        _ => {}
    }

    let status = Command::new("zip")
        .args(["-r", "-y", "-q"])
        .arg(zip_path)
        .arg(".")
        .current_dir(&tool_dir)
        .status()
        .map_err(|e| format!("cannot run zip: {e}"))?;
    if !status.success() {
        return Err(format!(
            "zip failed with exit code {}",
            status.code().unwrap_or(-1)
        ));
    }
    Ok(())
}

pub fn compute_sha256(path: &Path) -> Result<String, String> {
    let output = Command::new("shasum")
        .args(["-a", "256"])
        .arg(path)
        .output()
        .map_err(|e| format!("cannot run shasum: {e}"))?;
    if !output.status.success() {
        return Err("shasum failed".to_string());
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let hash = stdout
        .split_whitespace()
        .next()
        .ok_or("shasum produced no output")?
        .to_string();
    if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(format!("unexpected shasum output: {stdout}"));
    }
    Ok(hash)
}

fn print_help() {
    println!("Usage: zip-tool [--version <ver>] [-h|--help]");
    println!();
    println!("Packages the HomeSpeaker tool binary into a versioned zip.");
    println!();
    println!("Options:");
    println!("  --version <ver>  Override the version from manifest.json");
    println!("  -h, --help       Show this help message");
    println!();
    println!("Environment:");
    println!("  HOME_SPEAKER_ZIP_OUT_DIR  Output directory (default: <pkg_dir>/dist)");
    println!("  HOME_SPEAKER_TOOL_BIN     Path to the tool binary");
}

pub fn run(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    if config.show_help {
        print_help();
        return 0;
    }

    let pkg_dir = match determine_pkg_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    let manifest_path = pkg_dir.join("manifest.json");
    let manifest_version = match read_manifest_version(&manifest_path) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    let version = config
        .version_override
        .as_deref()
        .unwrap_or(&manifest_version);

    let binary_path = match find_binary(&pkg_dir) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    let out_dir = env::var("HOME_SPEAKER_ZIP_OUT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| pkg_dir.join("dist"));

    if let Err(e) = fs::create_dir_all(&out_dir) {
        eprintln!("error: cannot create output dir: {e}");
        return 1;
    }

    let tmp_dir = match tempdir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("error: cannot create temp dir: {e}");
            return 1;
        }
    };

    if let Err(e) = stage_files(
        config.version_override.as_deref(),
        &manifest_version,
        &pkg_dir,
        &binary_path,
        &tmp_dir,
    ) {
        eprintln!("error: {e}");
        let _ = fs::remove_dir_all(&tmp_dir);
        return 1;
    }

    let zip_name = format!("{BINARY_NAME}-{version}.zip");
    let zip_path = out_dir.join(&zip_name);
    if zip_path.exists() {
        let _ = fs::remove_file(&zip_path);
    }

    if let Err(e) = create_zip(&tmp_dir, &zip_path) {
        eprintln!("error: {e}");
        let _ = fs::remove_dir_all(&tmp_dir);
        return 1;
    }

    let _ = fs::remove_dir_all(&tmp_dir);

    let hash = match compute_sha256(&zip_path) {
        Ok(h) => h,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    let sidecar = format!("{zip_path}.sha256", zip_path = zip_path.display());
    let sidecar_content = format!("{hash}  {zip_name}\n");
    if let Err(e) = fs::write(&sidecar, &sidecar_content) {
        eprintln!("error: cannot write sha256 sidecar: {e}");
        return 1;
    }

    println!("{}", zip_path.display());
    println!("sha256: {hash}");
    0
}

fn tempdir() -> Result<PathBuf, std::io::Error> {
    let base = env::temp_dir();
    let pid = std::process::id();
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = base.join(format!("hs-zip-tool-{pid}-{ts}"));
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    fn make_temp(label: &str) -> PathBuf {
        let base = env::temp_dir();
        let pid = std::process::id();
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let dir = base.join(format!("hs-zip-test-{label}-{pid}-{ts}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn cleanup(dir: &Path) {
        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn version_from_manifest() {
        let tmp = make_temp("ver-manifest");
        let manifest = tmp.join("manifest.json");
        fs::write(
            &manifest,
            r#"{"name": "home-speaker", "version": "1.2.3", "description": "test"}"#,
        )
        .unwrap();
        let ver = read_manifest_version(&manifest).unwrap();
        assert_eq!(ver, "1.2.3");
        cleanup(&tmp);
    }

    #[test]
    fn version_override_does_not_touch_source() {
        let tmp = make_temp("ver-override");
        let pkg = tmp.join("pkg");
        fs::create_dir_all(&pkg).unwrap();
        let manifest = pkg.join("manifest.json");
        fs::write(&manifest, r#"{"name": "test", "version": "1.0.0"}"#).unwrap();
        let bin_src = tmp.join("fake-binary");
        fs::write(&bin_src, "fake").unwrap();

        let staging = tmp.join("stage");
        fs::create_dir_all(&staging).unwrap();
        stage_files(Some("2.0.0"), "1.0.0", &pkg, &bin_src, &staging).unwrap();

        let staged_manifest = staging.join(TOOL_ID).join("manifest.json");
        let staged_content = fs::read_to_string(&staged_manifest).unwrap();
        assert!(
            staged_content.contains("\"version\": \"2.0.0\""),
            "staged manifest should have version 2.0.0, got: {staged_content}"
        );
        let source_content = fs::read_to_string(&manifest).unwrap();
        assert!(
            source_content.contains("\"version\": \"1.0.0\""),
            "source manifest should still have 1.0.0, got: {source_content}"
        );
        cleanup(&tmp);
    }

    #[test]
    fn executable_bit() {
        let tmp = make_temp("exec-bit");
        let pkg = tmp.join("pkg");
        fs::create_dir_all(&pkg).unwrap();
        fs::write(pkg.join("manifest.json"), r#"{"version": "0.1.0"}"#).unwrap();
        let bin_src = tmp.join("fake-binary");
        fs::write(&bin_src, "fake").unwrap();

        let staging = tmp.join("stage");
        fs::create_dir_all(&staging).unwrap();
        stage_files(None, "0.1.0", &pkg, &bin_src, &staging).unwrap();

        let staged_binary = staging.join(TOOL_ID).join(BINARY_NAME);
        let mode = fs::metadata(&staged_binary).unwrap().permissions().mode();
        assert!(
            mode & 0o111 != 0,
            "binary should be executable, mode is {mode:#o}"
        );
        cleanup(&tmp);
    }

    #[test]
    fn icon_svg_staged() {
        let tmp = make_temp("icon-svg");
        let pkg = tmp.join("pkg");
        fs::create_dir_all(&pkg).unwrap();
        fs::write(pkg.join("manifest.json"), r#"{"version": "0.1.0"}"#).unwrap();
        fs::write(pkg.join("icon.svg"), "<svg/>").unwrap();
        let bin_src = tmp.join("fake-binary");
        fs::write(&bin_src, "fake").unwrap();

        let staging = tmp.join("stage");
        fs::create_dir_all(&staging).unwrap();
        stage_files(None, "0.1.0", &pkg, &bin_src, &staging).unwrap();

        let staged_icon = staging.join(TOOL_ID).join("icon.svg");
        assert!(staged_icon.exists(), "icon.svg should be staged");
        assert_eq!(fs::read_to_string(&staged_icon).unwrap(), "<svg/>");
        cleanup(&tmp);
    }

    #[test]
    fn sha256_sidecar_format() {
        let tmp = make_temp("sha256-sidecar");
        let test_file = tmp.join("test.bin");
        fs::write(&test_file, "hello world\n").unwrap();

        let hash = compute_sha256(&test_file).unwrap();
        assert_eq!(hash.len(), 64);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));

        let sidecar_content = format!("{hash}  test.bin\n");
        assert!(sidecar_content.ends_with('\n'));
        assert!(sidecar_content.contains("  test.bin"));
        cleanup(&tmp);
    }

    #[test]
    fn missing_binary_error() {
        let tmp = make_temp("miss-bin");
        env::remove_var("HOME_SPEAKER_TOOL_BIN");
        let saved_runfiles = env::var("RUNFILES_DIR").ok();
        let saved_ws = env::var("BUILD_WORKSPACE_DIRECTORY").ok();
        env::remove_var("RUNFILES_DIR");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");

        let result = find_binary(&tmp);
        assert!(result.is_err(), "should fail when no binary found");
        let err = result.unwrap_err();
        assert!(
            err.contains("cannot find"),
            "error should mention 'cannot find': {err}"
        );

        if let Some(v) = saved_runfiles {
            env::set_var("RUNFILES_DIR", v);
        }
        if let Some(v) = saved_ws {
            env::set_var("BUILD_WORKSPACE_DIRECTORY", v);
        }
        cleanup(&tmp);
    }

    #[test]
    fn unknown_flag_error() {
        let args: Vec<String> = vec!["prog".into(), "--bogus".into()];
        let result = parse_args(&args);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(
            err.contains("unknown flag"),
            "error should say 'unknown flag': {err}"
        );
    }

    #[test]
    fn version_without_value() {
        let args: Vec<String> = vec!["prog".into(), "--version".into()];
        let result = parse_args(&args);
        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(
            err.contains("requires a value"),
            "error should say 'requires a value': {err}"
        );
    }
}
