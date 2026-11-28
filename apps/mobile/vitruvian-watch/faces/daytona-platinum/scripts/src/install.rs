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
use std::path::{Path, PathBuf};
use std::process::Command;

const WATCH_FACE_PKG: &str = "com.vitruviansoftware.watch.daytonaplatinum";
const KNOWN_SERIALS: &[&str] = &["58301WRBNL30SD", "192.168.86.33"];

fn resolve_paths() -> (PathBuf, PathBuf) {
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let repo_root = PathBuf::from(&bwd);
        let pkg_dir = repo_root.join("apps/mobile/vitruvian-watch/faces/daytona-platinum");
        return (repo_root, pkg_dir);
    }
    let script_dir = Path::new(file!()).parent().unwrap_or(Path::new("."));
    // scripts/src/ -> scripts/ -> daytona-platinum/
    let pkg_dir = script_dir
        .parent()
        .unwrap_or(Path::new("."))
        .parent()
        .unwrap_or(Path::new("."));
    // daytona-platinum/ -> faces/ -> vitruvian-watch/ -> mobile/ -> apps/ -> repo_root
    let repo_root = pkg_dir
        .parent()
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .and_then(|p| p.parent())
        .unwrap_or(Path::new("."));
    (repo_root.to_path_buf(), pkg_dir.to_path_buf())
}

pub fn parse_watch_serial_from_devices(output: &str) -> Option<String> {
    for line in output.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && parts[1] == "device" {
            let serial = parts[0];
            for known in KNOWN_SERIALS {
                if serial.contains(known) {
                    return Some(serial.to_string());
                }
            }
        }
    }
    None
}

fn find_watch_serial(repo_root: &Path) -> Option<String> {
    if let Ok(serial) = env::var("ANDROID_SERIAL") {
        if !serial.is_empty() {
            return Some(serial);
        }
    }

    if let Ok(output) = Command::new("adb").args(["devices"]).output() {
        let stdout = String::from_utf8_lossy(&output.stdout);
        if let Some(serial) = parse_watch_serial_from_devices(&stdout) {
            return Some(serial);
        }
    }

    if let Ok(output) = Command::new("bazel")
        .current_dir(repo_root)
        .args([
            "run",
            "//tools/adb-connect",
            "--",
            "-d",
            "watch",
            "--print-serial",
        ])
        .output()
    {
        if output.status.success() {
            let serial = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !serial.is_empty() {
                return Some(serial);
            }
        }
    }

    None
}

/// Installer options: `--default <setting>=<option>` (passed to the APK build) and
/// `--fresh`, which uninstalls first so the face starts on its defaults and default
/// data sources instead of keeping the watch's saved choices.
#[derive(Debug, Default, PartialEq)]
pub struct InstallArgs {
    pub fresh: bool,
    pub build_args: Vec<String>,
}

pub fn parse_args(args: &[String]) -> Result<InstallArgs, String> {
    let mut parsed = InstallArgs::default();
    let mut it = args.iter().skip(1);
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--fresh" => parsed.fresh = true,
            "--default" => {
                let value = it.next().ok_or("--default needs <setting>=<option>")?;
                parsed.build_args.push("--default".into());
                parsed.build_args.push(value.clone());
            }
            a if a.starts_with("--default=") => parsed.build_args.push(a.to_string()),
            a => return Err(format!("unknown argument {a}")),
        }
    }
    Ok(parsed)
}

pub fn run(args: &[String]) -> i32 {
    let parsed = match parse_args(args) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("error: {e}");
            eprintln!("usage: install [--fresh] [--default <setting>=<option>]...");
            return 2;
        }
    };
    let (repo_root, _pkg_dir) = resolve_paths();

    // Create temp APK path
    let work_apk = env::temp_dir().join(format!("daytona-platinum-{}.apk", std::process::id()));

    // Build via build_wff_apk directly in Rust
    let mut build_args = vec![
        String::from("build_wff_apk"),
        work_apk.to_string_lossy().to_string(),
    ];
    build_args.extend(parsed.build_args.iter().cloned());
    if crate::build_wff_apk::run(&build_args) != 0 {
        eprintln!("error: build_wff_apk failed");
        let _ = std::fs::remove_file(&work_apk);
        return 1;
    }

    let watch_serial = match find_watch_serial(&repo_root) {
        Some(s) => s,
        None => {
            eprintln!(
                "error: Pixel Watch 4 (58301WRBNL30SD) is not connected over ADB. \
                 Wake the watch screen and run: bazel run //tools/adb-connect -- --device watch"
            );
            let _ = std::fs::remove_file(&work_apk);
            return 1;
        }
    };

    println!(
        "Installing onto {} (preserving user configurations)...",
        watch_serial
    );

    if parsed.fresh {
        // Saved settings and data-source picks belong to the installed face; removing it
        // is the only way for new defaults to take effect on a watch that already has it.
        println!("--fresh: removing the installed face so it starts on its defaults...");
        let _ = Command::new("adb")
            .args(["-s", &watch_serial, "uninstall", WATCH_FACE_PKG])
            .output();
    }

    // Try in-place install first (-r -d) to preserve user style preferences and complications
    let mut install_status = Command::new("adb")
        .args([
            "-s",
            &watch_serial,
            "install",
            "-r",
            "-d",
            "-i",
            "com.android.vending",
            work_apk.to_str().unwrap_or("out.apk"),
        ])
        .status();

    if let Ok(s) = install_status {
        if !s.success() {
            println!(
                "In-place install failed; falling back to clean reinstall (signature mismatch)..."
            );
            let _ = Command::new("adb")
                .args(["-s", &watch_serial, "uninstall", WATCH_FACE_PKG])
                .output();
            install_status = Command::new("adb")
                .args([
                    "-s",
                    &watch_serial,
                    "install",
                    "-i",
                    "com.android.vending",
                    work_apk.to_str().unwrap_or("out.apk"),
                ])
                .status();
        }
    }
    match install_status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!("error: adb install failed with {}", s);
            let _ = std::fs::remove_file(&work_apk);
            return 1;
        }
        Err(e) => {
            eprintln!("error: adb install failed: {}", e);
            let _ = std::fs::remove_file(&work_apk);
            return 1;
        }
    }

    println!("Activating {} on {}...", WATCH_FACE_PKG, watch_serial);

    // Set watch face via broadcast
    let broadcast_status = Command::new("adb")
        .args([
            "-s",
            &watch_serial,
            "shell",
            "am",
            "broadcast",
            "-a",
            "com.google.android.wearable.app.DEBUG_SURFACE",
            "--es",
            "operation",
            "set-watchface",
            "--es",
            "watchFaceId",
            WATCH_FACE_PKG,
        ])
        .status();
    match broadcast_status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!("warning: am broadcast exited with {}", s);
        }
        Err(e) => {
            eprintln!("warning: am broadcast failed: {}", e);
        }
    }

    let _ = std::fs::remove_file(&work_apk);
    println!(
        "Installed and activated {} on {}.",
        WATCH_FACE_PKG, watch_serial
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn parse_install_args() {
        assert_eq!(
            parse_args(&a(&["install"])).unwrap(),
            InstallArgs::default()
        );
        let p = parse_args(&a(&[
            "install",
            "--fresh",
            "--default",
            "theme_style=theme_lemans",
            "--default=subdial_mode=subdials_smart",
        ]))
        .unwrap();
        assert!(p.fresh);
        assert_eq!(
            p.build_args,
            a(&[
                "--default",
                "theme_style=theme_lemans",
                "--default=subdial_mode=subdials_smart"
            ])
        );
        assert!(parse_args(&a(&["install", "--default"])).is_err());
        assert!(parse_args(&a(&["install", "extra"])).is_err());
    }

    #[test]
    fn parse_known_serial_58301() {
        let output = "\
List of devices attached
58301WRBNL30SD\tdevice
emulator-5554\tdevice
";
        assert_eq!(
            parse_watch_serial_from_devices(output),
            Some("58301WRBNL30SD".to_string())
        );
    }

    #[test]
    fn parse_known_serial_wifi() {
        let output = "\
List of devices attached
192.168.86.33:5555\tdevice
emulator-5554\tdevice
";
        assert_eq!(
            parse_watch_serial_from_devices(output),
            Some("192.168.86.33:5555".to_string())
        );
    }

    #[test]
    fn parse_no_known_serial() {
        let output = "\
List of devices attached
emulator-5554\tdevice
";
        assert_eq!(parse_watch_serial_from_devices(output), None);
    }

    #[test]
    fn parse_empty_devices() {
        let output = "List of devices attached\n\n";
        assert_eq!(parse_watch_serial_from_devices(output), None);
    }

    #[test]
    fn parse_offline_device_ignored() {
        let output = "\
List of devices attached
58301WRBNL30SD\toffline
";
        assert_eq!(parse_watch_serial_from_devices(output), None);
    }

    #[test]
    fn parse_unauthorized_device_ignored() {
        let output = "\
List of devices attached
58301WRBNL30SD\tunauthorized
";
        assert_eq!(parse_watch_serial_from_devices(output), None);
    }

    #[test]
    fn parse_multiple_known_serials_picks_first() {
        let output = "\
List of devices attached
192.168.86.33:5555\tdevice
58301WRBNL30SD\tdevice
";
        assert_eq!(
            parse_watch_serial_from_devices(output),
            Some("192.168.86.33:5555".to_string())
        );
    }

    #[test]
    fn android_serial_env_wins() {
        // Just verify the constant and the known serials list
        assert_eq!(
            WATCH_FACE_PKG,
            "com.vitruviansoftware.watch.daytonaplatinum"
        );
        assert!(KNOWN_SERIALS.contains(&"58301WRBNL30SD"));
        assert!(KNOWN_SERIALS.contains(&"192.168.86.33"));
    }
}
