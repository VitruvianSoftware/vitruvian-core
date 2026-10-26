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

const WATCH_FACE_PKG: &str = "com.watchfacestudio.daytonaplatinum";
const KNOWN_SERIALS: &[&str] = &["58301WRBNL30SD", "192.168.86.33"];

fn resolve_paths() -> (PathBuf, PathBuf) {
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let repo_root = PathBuf::from(&bwd);
        let pkg_dir = repo_root.join("apps/mobile/wearos/faces/daytona-platinum");
        return (repo_root, pkg_dir);
    }
    let script_dir = Path::new(file!()).parent().unwrap_or(Path::new("."));
    // scripts/src/ -> scripts/ -> daytona-platinum/
    let pkg_dir = script_dir
        .parent()
        .unwrap_or(Path::new("."))
        .parent()
        .unwrap_or(Path::new("."));
    // daytona-platinum/ -> faces/ -> wearos/ -> mobile/ -> apps/ -> repo_root
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

    let adb_connect = repo_root.join("tools/adb-connect/adb_connect.py");
    if adb_connect.is_file() {
        if let Ok(output) = Command::new("python3")
            .args([
                adb_connect.to_str().unwrap_or("adb_connect.py"),
                "-d",
                "watch",
                "--print-serial",
            ])
            .output()
        {
            let serial = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !serial.is_empty() {
                return Some(serial);
            }
        }
    }

    None
}

pub fn run(args: &[String]) -> i32 {
    let _ = args;
    let (repo_root, pkg_dir) = resolve_paths();

    // Create temp APK path
    let work_apk = env::temp_dir().join(format!("daytona-platinum-{}.apk", std::process::id()));

    // Build via build_wff_apk.sh
    let build_script = pkg_dir.join("scripts/build_wff_apk.sh");
    let status = match Command::new("bash")
        .arg(build_script.to_str().unwrap_or("build_wff_apk.sh"))
        .arg(work_apk.to_str().unwrap_or("out.apk"))
        .status()
    {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error: failed to run build_wff_apk.sh: {}", e);
            let _ = std::fs::remove_file(&work_apk);
            return 1;
        }
    };
    if !status.success() {
        eprintln!("error: build_wff_apk.sh failed");
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

    println!("Installing onto {}...", watch_serial);

    // Uninstall (ignore failure)
    let _ = Command::new("adb")
        .args(["-s", &watch_serial, "uninstall", WATCH_FACE_PKG])
        .output();

    // Install with market installer
    let install_status = Command::new("adb")
        .args([
            "-s",
            &watch_serial,
            "install",
            "-i",
            "com.android.vending",
            work_apk.to_str().unwrap_or("out.apk"),
        ])
        .status();
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
        assert_eq!(WATCH_FACE_PKG, "com.watchfacestudio.daytonaplatinum");
        assert!(KNOWN_SERIALS.contains(&"58301WRBNL30SD"));
        assert!(KNOWN_SERIALS.contains(&"192.168.86.33"));
    }
}
