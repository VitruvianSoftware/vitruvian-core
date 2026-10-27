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

const WEAROS_PKGS: &[&str] = &["vitruvian-pulse", "remote", "home-control", "nexus-wrist"];

const ANDROID_HOME_CANDIDATES: &[&str] = &[
    "/usr/local/lib/android/sdk",
    "/opt/homebrew/share/android-commandlinetools",
];

pub fn detect_android_home() -> Option<String> {
    if let Ok(val) = env::var("ANDROID_HOME") {
        if !val.is_empty() {
            return Some(val);
        }
    }
    for cand in ANDROID_HOME_CANDIDATES {
        if Path::new(cand).join("platforms").is_dir() {
            return Some(cand.to_string());
        }
    }
    if let Ok(home) = env::var("HOME") {
        let user_sdk = format!("{}/Library/Android/sdk", home);
        if Path::new(&user_sdk).join("platforms").is_dir() {
            return Some(user_sdk);
        }
    }
    None
}

pub fn build_adb_args(serial: &str) -> Vec<String> {
    if serial.is_empty() {
        Vec::new()
    } else {
        vec!["-s".to_string(), serial.to_string()]
    }
}

fn resolve_repo_root() -> PathBuf {
    for var in [
        "BUILD_WORKSPACE_DIRECTORY",
        "GITHUB_WORKSPACE",
        "BUILD_WORKING_DIRECTORY",
    ] {
        if let Ok(bwd) = env::var(var) {
            let p = PathBuf::from(&bwd);
            if p.join("MODULE.bazel").is_file() {
                return p;
            }
        }
    }
    let exe = env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let script_dir = exe.parent().unwrap_or(Path::new("."));
    if let Some(root) = script_dir
        .ancestors()
        .find(|p| p.join("MODULE.bazel").is_file())
    {
        return root.to_path_buf();
    }
    let suite_dir = script_dir.parent().unwrap_or(Path::new("."));
    suite_dir
        .ancestors()
        .nth(3)
        .unwrap_or(Path::new("."))
        .to_path_buf()
}

fn try_adb_connect_serial(repo_root: &Path) -> Option<String> {
    let output = Command::new("bazel")
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
        .ok()?;
    if output.status.success() {
        let s = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if s.is_empty() {
            None
        } else {
            Some(s)
        }
    } else {
        None
    }
}

pub fn run(_args: &[String]) -> i32 {
    let repo_root = resolve_repo_root();

    if let Some(ah) = detect_android_home() {
        env::set_var("ANDROID_HOME", &ah);
    }

    if env::set_current_dir(&repo_root).is_err() {
        eprintln!("Error: cannot cd to {}", repo_root.display());
        return 1;
    }

    println!("==> Building all 4 Vitruvian Wear OS APKs...");
    let build_status = Command::new("bazel")
        .args([
            "build",
            "--android_platforms=@rules_android//:armeabi-v7a,@rules_android//:arm64-v8a",
            "//apps/mobile/wearos/apps/vitruvian-pulse:app",
            "//apps/mobile/wearos/apps/remote:app",
            "//apps/mobile/wearos/apps/home-control:app",
            "//apps/mobile/wearos/apps/nexus-wrist:app",
        ])
        .status();
    match build_status {
        Ok(s) if s.success() => {}
        _ => {
            eprintln!("Error: bazel build failed");
            return 1;
        }
    }

    let bin_root = match Command::new("bazel").args(["info", "bazel-bin"]).output() {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        _ => {
            eprintln!("Error: cannot determine bazel-bin");
            return 1;
        }
    };

    let serial = env::var("ANDROID_SERIAL").unwrap_or_default();
    let serial = if serial.is_empty() {
        try_adb_connect_serial(&repo_root).unwrap_or_default()
    } else {
        serial
    };
    let adb_args = build_adb_args(&serial);

    for pkg in WEAROS_PKGS {
        let apk = format!("{}/apps/mobile/wearos/apps/{}/app.apk", bin_root, pkg);
        println!("==> Installing {} ({})...", pkg, apk);
        let mut cmd = Command::new("adb");
        for a in &adb_args {
            cmd.arg(a);
        }
        cmd.args(["install", "-r", &apk]);
        match cmd.status() {
            Ok(s) if s.success() => {}
            _ => {
                eprintln!("Error: adb install failed for {}", pkg);
                return 1;
            }
        }
    }

    println!("==> All 4 Vitruvian Wear OS apps installed on watch.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adb_args_empty_serial() {
        assert!(build_adb_args("").is_empty());
    }

    #[test]
    fn adb_args_with_serial() {
        let args = build_adb_args("emulator-5554");
        assert_eq!(args, vec!["-s", "emulator-5554"]);
    }

    #[test]
    fn detect_android_home_from_env() {
        let prev = env::var("ANDROID_HOME").ok();
        env::set_var("ANDROID_HOME", "/tmp/fake-sdk");
        let result = detect_android_home();
        match prev {
            Some(v) => env::set_var("ANDROID_HOME", v),
            None => env::remove_var("ANDROID_HOME"),
        }
        assert_eq!(result, Some("/tmp/fake-sdk".to_string()));
    }

    #[test]
    fn detect_android_home_empty_env_falls_through() {
        let prev = env::var("ANDROID_HOME").ok();
        env::set_var("ANDROID_HOME", "");
        let result = detect_android_home();
        match prev {
            Some(v) => env::set_var("ANDROID_HOME", v),
            None => env::remove_var("ANDROID_HOME"),
        }
        // Result depends on filesystem; just verify it didn't return empty string
        if let Some(ref v) = result {
            assert!(!v.is_empty());
        }
    }

    #[test]
    fn wearos_pkgs_order() {
        assert_eq!(
            WEAROS_PKGS,
            &["vitruvian-pulse", "remote", "home-control", "nexus-wrist"]
        );
    }
}
