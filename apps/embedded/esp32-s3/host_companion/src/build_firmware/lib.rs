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
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn find_pio() -> Option<PathBuf> {
    if let Ok(pio_bin) = env::var("PIO_BIN") {
        let p = PathBuf::from(&pio_bin);
        if p.exists() {
            return Some(p);
        }
        return None;
    }

    if let Some(path) = which("pio") {
        return Some(path);
    }

    let home = env::var("HOME").unwrap_or_default();
    if !home.is_empty() {
        let candidate = PathBuf::from(&home)
            .join(".platformio")
            .join("penv")
            .join("bin")
            .join("pio");
        if candidate.exists() {
            return Some(candidate);
        }
    }

    None
}

fn which(name: &str) -> Option<PathBuf> {
    let path_var = env::var("PATH").unwrap_or_default();
    for dir in path_var.split(':') {
        let candidate = PathBuf::from(dir).join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

pub struct BuildConfig {
    pub out_tar_gz: PathBuf,
    pub project_dir: Option<PathBuf>,
}

pub fn parse_args(args: &[String]) -> Result<BuildConfig, String> {
    if args.is_empty() {
        return Err("Usage: build_firmware <out_tar_gz> [--project-dir <dir>]".into());
    }
    let mut out_tar_gz = None;
    let mut project_dir = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--project-dir" | "--project_dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--project-dir requires an argument".into());
                }
                project_dir = Some(PathBuf::from(&args[i]));
            }
            "-h" | "--help" => {
                return Err("Usage: build_firmware <out_tar_gz> [--project-dir <dir>]".into());
            }
            other => {
                if out_tar_gz.is_none() {
                    out_tar_gz = Some(PathBuf::from(other));
                } else {
                    return Err(format!("unexpected argument: {}", other));
                }
            }
        }
        i += 1;
    }

    Ok(BuildConfig {
        out_tar_gz: out_tar_gz.ok_or("missing <out_tar_gz> argument")?,
        project_dir,
    })
}

pub fn build_firmware(config: &BuildConfig) -> Result<(), String> {
    let pio = find_pio();
    let tmp = env::temp_dir().join("esp32-s3-build");
    let _ = fs::remove_dir_all(&tmp);
    fs::create_dir_all(&tmp).map_err(|e| format!("create temp dir: {}", e))?;

    let fw_bin = tmp.join("firmware.bin");
    let part_bin = tmp.join("partitions.bin");
    let boot_bin = tmp.join("bootloader.bin");

    if let Some(ref pio_path) = pio {
        eprintln!("=== Building ESP32-S3 Firmware ===");

        let mut cmd = Command::new(pio_path);
        cmd.arg("run").arg("-e").arg("esp32-s3-devkitc-1");
        if let Some(ref dir) = config.project_dir {
            cmd.arg("-d").arg(dir);
        }

        let status = cmd
            .status()
            .map_err(|e| format!("failed to run pio: {}", e))?;
        if !status.success() {
            return Err("PlatformIO build failed".into());
        }

        let build_dir = config
            .project_dir
            .as_deref()
            .unwrap_or(Path::new("."))
            .join(".pio/build/esp32s3");

        for (name, dest) in [
            ("firmware.bin", &fw_bin),
            ("partitions.bin", &part_bin),
            ("bootloader.bin", &boot_bin),
        ] {
            let src = build_dir.join(name);
            if !src.exists() {
                return Err(format!("{} not found after build", name));
            }
            fs::copy(&src, dest).map_err(|e| format!("copy {}: {}", name, e))?;
        }
    } else {
        eprintln!("=== PlatformIO not found; creating placeholder firmware ===");
        for (name, dest) in [
            ("firmware.bin", &fw_bin),
            ("partitions.bin", &part_bin),
            ("bootloader.bin", &boot_bin),
        ] {
            let mut f = fs::File::create(dest).map_err(|e| format!("create {}: {}", name, e))?;
            f.write_all(format!("PLACEHOLDER:{}\n", name).as_bytes())
                .map_err(|e| format!("write {}: {}", name, e))?;
        }
    }

    create_tar_gz(&config.out_tar_gz, &tmp)?;

    eprintln!("=== Firmware Build Successful ===");
    Ok(())
}

fn create_tar_gz(out: &Path, dir: &Path) -> Result<(), String> {
    let status = Command::new("tar")
        .arg("-czf")
        .arg(out)
        .arg("-C")
        .arg(dir)
        .arg("firmware.bin")
        .arg("partitions.bin")
        .arg("bootloader.bin")
        .status()
        .map_err(|e| format!("tar: {}", e))?;
    if !status.success() {
        return Err("tar -czf failed".into());
    }
    Ok(())
}

pub fn tar_gz_contents(path: &Path) -> Result<Vec<String>, String> {
    let output = Command::new("tar")
        .arg("-tzf")
        .arg(path)
        .output()
        .map_err(|e| format!("tar -tzf: {}", e))?;
    if !output.status.success() {
        return Err("tar -tzf failed".into());
    }
    let text = String::from_utf8_lossy(&output.stdout);
    Ok(text.lines().map(|l| l.to_string()).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn test_placeholder_mode() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = env::temp_dir().join("test_build_fw_placeholder");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();
        let out = tmp.join("firmware.tar.gz");

        env::set_var("PIO_BIN", "/nonexistent/pio");

        let config = BuildConfig {
            out_tar_gz: out.clone(),
            project_dir: None,
        };

        let result = build_firmware(&config);
        env::remove_var("PIO_BIN");

        assert!(result.is_ok(), "placeholder build failed: {:?}", result);
        assert!(out.exists(), "tar.gz not created");

        let contents = tar_gz_contents(&out).unwrap();
        assert!(
            contents.iter().any(|f| f.contains("firmware.bin")),
            "missing firmware.bin in {:?}",
            contents
        );
        assert!(
            contents.iter().any(|f| f.contains("partitions.bin")),
            "missing partitions.bin in {:?}",
            contents
        );
        assert!(
            contents.iter().any(|f| f.contains("bootloader.bin")),
            "missing bootloader.bin in {:?}",
            contents
        );

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_fake_pio_bin() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let tmp = env::temp_dir().join("test_build_fw_fakepio");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let fake_pio = tmp.join("fake_pio.sh");
        let proj = tmp.join("project");
        let build_out = proj.join(".pio/build/esp32s3");
        fs::create_dir_all(&build_out).unwrap();

        for name in ["firmware.bin", "partitions.bin", "bootloader.bin"] {
            fs::write(build_out.join(name), format!("FAKE:{}", name)).unwrap();
        }

        fs::write(&fake_pio, "#!/bin/sh\nexit 0\n").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&fake_pio, fs::Permissions::from_mode(0o755)).unwrap();
        }

        env::set_var("PIO_BIN", fake_pio.to_str().unwrap());

        let out = tmp.join("firmware.tar.gz");
        let config = BuildConfig {
            out_tar_gz: out.clone(),
            project_dir: Some(proj),
        };

        let result = build_firmware(&config);
        env::remove_var("PIO_BIN");

        assert!(result.is_ok(), "fake pio build failed: {:?}", result);
        assert!(out.exists());

        let contents = tar_gz_contents(&out).unwrap();
        assert!(contents.iter().any(|f| f.contains("firmware.bin")));
        assert!(contents.iter().any(|f| f.contains("partitions.bin")));
        assert!(contents.iter().any(|f| f.contains("bootloader.bin")));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_parse_args_minimal() {
        let args = vec!["out.tar.gz".to_string()];
        let config = parse_args(&args).unwrap();
        assert_eq!(config.out_tar_gz, PathBuf::from("out.tar.gz"));
        assert!(config.project_dir.is_none());
    }

    #[test]
    fn test_parse_args_with_project_dir() {
        let args = vec![
            "out.tar.gz".to_string(),
            "--project-dir".to_string(),
            "/my/project".to_string(),
        ];
        let config = parse_args(&args).unwrap();
        assert_eq!(config.project_dir, Some(PathBuf::from("/my/project")));
    }

    #[test]
    fn test_parse_args_empty() {
        assert!(parse_args(&[]).is_err());
    }
}
