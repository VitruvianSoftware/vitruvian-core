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
use std::path::{Path, PathBuf};
use std::process::Command;

const TAG_PREFIX: &str = "esp32-s3-v";
const BETA_TAG: &str = "esp32-s3-beta-latest";
const PKG: &str = "apps/embedded/esp32-s3";

#[derive(Debug, Clone)]
pub struct PublishConfig {
    pub workspace_dir: PathBuf,
    pub grade: String,
    pub sha: String,
    pub tag: String,
    pub version: String,
    pub firmware_tar: PathBuf,
    pub dry_run: bool,
    pub is_beta: bool,
}

pub fn resolve_config() -> Result<PublishConfig, String> {
    let workspace_dir = env::var("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .or_else(|_| {
            let output = Command::new("git")
                .args(["rev-parse", "--show-toplevel"])
                .output()
                .map_err(|e| format!("git: {}", e))?;
            if output.status.success() {
                Ok(PathBuf::from(
                    String::from_utf8_lossy(&output.stdout).trim(),
                ))
            } else {
                Ok(env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
            }
        })
        .unwrap_or_else(|_: String| PathBuf::from("."));

    let grade = env::var("GRADE").unwrap_or_else(|_| "beta".into());
    let dry_run = env::var("DRY_RUN")
        .map(|v| v == "true" || v == "1")
        .unwrap_or(false);

    let sha = env::var("GITHUB_SHA").unwrap_or_else(|_| {
        Command::new("git")
            .args(["rev-parse", "HEAD"])
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_else(|| "0000000000000000000000000000000000000000".into())
    });
    let short_sha = &sha[..7.min(sha.len())];

    let manifest_version = read_manifest_version(&workspace_dir)?;

    let is_beta = grade == "beta";
    let (tag, version) = match grade.as_str() {
        "beta" => {
            let tag = env::var("TAG").unwrap_or_else(|_| BETA_TAG.into());
            let version = format!("{}-beta.{}", manifest_version, short_sha);
            (tag, version)
        }
        "production" => {
            let tag = env::var("RELEASE_TAG").unwrap_or_default();
            if tag.is_empty() {
                return Err(format!(
                    "publish: GRADE=production needs RELEASE_TAG={}X.Y.Z; refusing to guess",
                    TAG_PREFIX
                ));
            }
            if !tag.starts_with(TAG_PREFIX) {
                return Err(format!(
                    "publish: RELEASE_TAG={} is not an {}* release",
                    tag, TAG_PREFIX
                ));
            }
            let version = tag.strip_prefix(TAG_PREFIX).unwrap().to_string();
            (tag, version)
        }
        _ => {
            return Err(format!(
                "publish: unknown GRADE={} (beta|production)",
                grade
            ));
        }
    };

    let firmware_tar = env::var("FIRMWARE_TAR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            workspace_dir.join(format!("bazel-bin/{}/esp32_s3_firmware.tar.gz", PKG))
        });

    Ok(PublishConfig {
        workspace_dir,
        grade,
        sha,
        tag,
        version,
        firmware_tar,
        dry_run,
        is_beta,
    })
}

fn read_manifest_version(workspace_dir: &Path) -> Result<String, String> {
    let manifest_path = workspace_dir
        .join(PKG)
        .join(".release-please-manifest.json");
    if !manifest_path.exists() {
        return Ok("0.0.0".into());
    }
    let content =
        fs::read_to_string(&manifest_path).map_err(|e| format!("read manifest: {}", e))?;
    let key = format!("\"{}\"", PKG);
    for line in content.lines() {
        if let Some(pos) = line.find(&key) {
            let rest = &line[pos + key.len()..];
            if let Some(colon) = rest.find(':') {
                let after = &rest[colon + 1..];
                let trimmed = after
                    .trim()
                    .trim_end_matches([',', '}'])
                    .trim()
                    .trim_matches('"');
                if !trimmed.is_empty() {
                    return Ok(trimmed.to_string());
                }
            }
        }
    }
    Ok("0.0.0".into())
}

pub fn publish(config: &PublishConfig) -> Result<(), String> {
    eprintln!(
        "=== esp32-s3 publish: grade={} version={} tag={} commit={} ===",
        config.grade, config.version, config.tag, config.sha
    );

    if !config.firmware_tar.exists() {
        return Err(format!(
            "Firmware tar not found: {}",
            config.firmware_tar.display()
        ));
    }

    if config.dry_run {
        eprintln!(
            "[DRY_RUN] Would create/upload release {} with tag {}",
            config.version, config.tag
        );
        eprintln!("[DRY_RUN] Firmware tar: {}", config.firmware_tar.display());
        eprintln!(
            "=== esp32-s3 publish complete (dry run): {} ({}, {}) ===",
            config.tag, config.version, config.grade
        );
        return Ok(());
    }

    if config.is_beta {
        let check = Command::new("gh")
            .args(["release", "view", &config.tag])
            .output()
            .map_err(|e| format!("gh release view: {}", e))?;

        if !check.status.success() {
            let status = Command::new("gh")
                .args([
                    "release",
                    "create",
                    &config.tag,
                    "--prerelease",
                    "--target",
                    &config.sha,
                    "--title",
                    "ESP32-S3 Firmware (Beta Rolling Release)",
                    "--notes",
                    "Rolling pre-release built automatically from commits landing on main.",
                ])
                .current_dir(&config.workspace_dir)
                .status()
                .map_err(|e| format!("gh release create: {}", e))?;
            if !status.success() {
                return Err("Failed to create beta release".into());
            }
        }
    }

    let status = Command::new("gh")
        .args([
            "release",
            "upload",
            &config.tag,
            config.firmware_tar.to_str().unwrap_or(""),
            "--clobber",
        ])
        .current_dir(&config.workspace_dir)
        .status()
        .map_err(|e| format!("gh release upload: {}", e))?;
    if !status.success() {
        return Err("Failed to upload release assets".into());
    }

    eprintln!(
        "=== esp32-s3 publish complete: {} ({}, {}) ===",
        config.tag, config.version, config.grade
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard};

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn setup_env() -> MutexGuard<'static, ()> {
        let guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        env::remove_var("GRADE");
        env::remove_var("GITHUB_SHA");
        env::remove_var("RELEASE_TAG");
        env::remove_var("TAG");
        env::remove_var("FIRMWARE_TAR");
        env::remove_var("DRY_RUN");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
        guard
    }

    #[test]
    fn test_dry_run_beta() {
        let _g = setup_env();
        let tmp = env::temp_dir().join("test_publish_dry_beta");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let tar = tmp.join("firmware.tar.gz");
        fs::write(&tar, b"fake").unwrap();

        let config = PublishConfig {
            workspace_dir: tmp.clone(),
            grade: "beta".into(),
            sha: "abc1234567890".into(),
            tag: BETA_TAG.into(),
            version: "1.0.0-beta.abc1234".into(),
            firmware_tar: tar,
            dry_run: true,
            is_beta: true,
        };

        let result = publish(&config);
        assert!(result.is_ok(), "dry run beta failed: {:?}", result);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_dry_run_production() {
        let _g = setup_env();
        let tmp = env::temp_dir().join("test_publish_dry_prod");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let tar = tmp.join("firmware.tar.gz");
        fs::write(&tar, b"fake").unwrap();

        let config = PublishConfig {
            workspace_dir: tmp.clone(),
            grade: "production".into(),
            sha: "abc1234567890".into(),
            tag: "esp32-s3-v2.0.0".into(),
            version: "2.0.0".into(),
            firmware_tar: tar,
            dry_run: true,
            is_beta: false,
        };

        let result = publish(&config);
        assert!(result.is_ok(), "dry run production failed: {:?}", result);
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_missing_firmware_tar() {
        let _g = setup_env();
        let config = PublishConfig {
            workspace_dir: PathBuf::from("/tmp"),
            grade: "beta".into(),
            sha: "abc1234".into(),
            tag: BETA_TAG.into(),
            version: "1.0.0-beta.abc1234".into(),
            firmware_tar: PathBuf::from("/nonexistent/firmware.tar.gz"),
            dry_run: false,
            is_beta: true,
        };

        let result = publish(&config);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not found"));
    }

    #[test]
    fn test_production_missing_release_tag() {
        let _g = setup_env();
        env::set_var("GRADE", "production");
        env::set_var("BUILD_WORKSPACE_DIRECTORY", "/tmp");
        let result = resolve_config();
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("RELEASE_TAG"));
        env::remove_var("GRADE");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
    }

    #[test]
    fn test_production_wrong_tag_prefix() {
        let _g = setup_env();
        env::set_var("GRADE", "production");
        env::set_var("RELEASE_TAG", "tabula-v1.0.0");
        env::set_var("BUILD_WORKSPACE_DIRECTORY", "/tmp");
        let result = resolve_config();
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not an"));
        env::remove_var("GRADE");
        env::remove_var("RELEASE_TAG");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
    }

    #[test]
    fn test_unknown_grade() {
        let _g = setup_env();
        env::set_var("GRADE", "staging");
        env::set_var("BUILD_WORKSPACE_DIRECTORY", "/tmp");
        let result = resolve_config();
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("unknown GRADE"));
        env::remove_var("GRADE");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
    }

    #[test]
    fn test_beta_config_defaults() {
        let _g = setup_env();
        env::set_var("GRADE", "beta");
        env::set_var("GITHUB_SHA", "deadbeef1234567890abcdef");
        env::set_var("BUILD_WORKSPACE_DIRECTORY", "/tmp");
        let config = resolve_config().unwrap();
        assert!(config.is_beta);
        assert_eq!(config.tag, BETA_TAG);
        assert!(config.version.contains("beta.deadbee"));
        env::remove_var("GRADE");
        env::remove_var("GITHUB_SHA");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
    }

    #[test]
    fn test_production_config() {
        let _g = setup_env();
        env::set_var("GRADE", "production");
        env::set_var("RELEASE_TAG", "esp32-s3-v3.1.0");
        env::set_var("BUILD_WORKSPACE_DIRECTORY", "/tmp");
        let config = resolve_config().unwrap();
        assert!(!config.is_beta);
        assert_eq!(config.tag, "esp32-s3-v3.1.0");
        assert_eq!(config.version, "3.1.0");
        env::remove_var("GRADE");
        env::remove_var("RELEASE_TAG");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
    }

    #[test]
    fn test_firmware_tar_env_override() {
        let _g = setup_env();
        env::set_var("GRADE", "beta");
        env::set_var("FIRMWARE_TAR", "/custom/path/fw.tar.gz");
        env::set_var("BUILD_WORKSPACE_DIRECTORY", "/tmp");
        let config = resolve_config().unwrap();
        assert_eq!(config.firmware_tar, PathBuf::from("/custom/path/fw.tar.gz"));
        env::remove_var("GRADE");
        env::remove_var("FIRMWARE_TAR");
        env::remove_var("BUILD_WORKSPACE_DIRECTORY");
    }

    #[test]
    fn test_read_manifest_version_missing() {
        let v = read_manifest_version(Path::new("/nonexistent")).unwrap();
        assert_eq!(v, "0.0.0");
    }

    #[test]
    fn test_read_manifest_version_valid() {
        let tmp = env::temp_dir().join("test_manifest_ver");
        let _ = fs::remove_dir_all(&tmp);
        let pkg_dir = tmp.join(PKG);
        fs::create_dir_all(&pkg_dir).unwrap();
        let manifest = pkg_dir.join(".release-please-manifest.json");
        fs::write(&manifest, r#"{"apps/embedded/esp32-s3": "1.2.3"}"#).unwrap();
        let v = read_manifest_version(&tmp).unwrap();
        assert_eq!(v, "1.2.3");
        let _ = fs::remove_dir_all(&tmp);
    }
}
