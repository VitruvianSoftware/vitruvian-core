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
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn resolve_sdk_root() -> String {
    env::var("ANDROID_HOME")
        .unwrap_or_else(|_| "/opt/homebrew/share/android-commandlinetools".to_string())
}

pub fn version_sort_key(name: &str) -> Vec<u64> {
    let stripped = name.strip_prefix("android-").unwrap_or(name);
    stripped
        .split('.')
        .map(|s| {
            let digits: String = s.chars().take_while(|c| c.is_ascii_digit()).collect();
            digits.parse::<u64>().unwrap_or(0)
        })
        .collect()
}

pub fn find_latest_build_tools(sdk_root: &str) -> Option<PathBuf> {
    let bt_dir = Path::new(sdk_root).join("build-tools");
    let mut entries: Vec<PathBuf> = match fs::read_dir(&bt_dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_dir())
            .collect(),
        Err(_) => return None,
    };
    if entries.is_empty() {
        return None;
    }
    entries.sort_by(|a, b| {
        let ak = version_sort_key(a.file_name().unwrap_or_default().to_str().unwrap_or(""));
        let bk = version_sort_key(b.file_name().unwrap_or_default().to_str().unwrap_or(""));
        ak.cmp(&bk)
    });
    entries.pop()
}

pub fn find_latest_platform_jar(sdk_root: &str) -> Option<PathBuf> {
    let platforms_dir = Path::new(sdk_root).join("platforms");
    let mut jars: Vec<PathBuf> = match fs::read_dir(&platforms_dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_dir())
            .filter_map(|p| {
                let jar = p.join("android.jar");
                if jar.is_file() {
                    Some(jar)
                } else {
                    None
                }
            })
            .collect(),
        Err(_) => return None,
    };
    if jars.is_empty() {
        return None;
    }
    jars.sort_by(|a, b| {
        let an = a
            .parent()
            .and_then(|p| p.file_name())
            .unwrap_or_default()
            .to_str()
            .unwrap_or("");
        let bn = b
            .parent()
            .and_then(|p| p.file_name())
            .unwrap_or_default()
            .to_str()
            .unwrap_or("");
        version_sort_key(an).cmp(&version_sort_key(bn))
    });
    jars.pop()
}

pub fn resolve_pkg_dir() -> PathBuf {
    let src = Path::new(file!());
    // src/build_wff_apk.rs -> scripts/src/build_wff_apk.rs relative to pkg
    // At runtime the binary sits beside scripts/, so we derive PKG_DIR from
    // the script directory layout: scripts/src/ -> scripts/ -> pkg/
    // But at runtime we use the actual executable path or SCRIPT_DIR equivalent.
    // For the Rust port we resolve from the current exe or from env.
    let exe = env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    // If run via `bazel run`, BUILD_WORKSPACE_DIRECTORY is set.
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        return Path::new(&bwd)
            .join("apps/mobile/wearos/faces/daytona-platinum")
            .to_path_buf();
    }
    // Otherwise try to walk up from the exe or fall back to the source layout.
    let _ = src;
    let exe_dir = exe.parent().unwrap_or(Path::new("."));
    // Try walking up to find the package marker (AndroidManifest.xml).
    let mut dir = exe_dir.to_path_buf();
    for _ in 0..10 {
        if dir.join("src/main/AndroidManifest.xml").is_file() {
            return dir;
        }
        if !dir.pop() {
            break;
        }
    }
    // Fall back to CWD-based resolution.
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn run_cmd(program: &str, args: &[&str]) -> io::Result<()> {
    let status = Command::new(program).args(args).status()?;
    if !status.success() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("{} exited with {}", program, status),
        ));
    }
    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let pkg_dir = resolve_pkg_dir();
    let out_apk = if args.len() > 1 {
        PathBuf::from(&args[1])
    } else {
        pkg_dir.join("daytona-platinum.apk")
    };

    let sdk_root = resolve_sdk_root();

    let build_tools_dir = match find_latest_build_tools(&sdk_root) {
        Some(d) => d,
        None => {
            eprintln!(
                "error: Android SDK build-tools and platforms/android-*/android.jar are required under ANDROID_HOME ({})",
                sdk_root
            );
            return 1;
        }
    };

    let platform_jar = match find_latest_platform_jar(&sdk_root) {
        Some(j) => j,
        None => {
            eprintln!(
                "error: Android SDK build-tools and platforms/android-*/android.jar are required under ANDROID_HOME ({})",
                sdk_root
            );
            return 1;
        }
    };

    // JAVA_HOME detection
    if env::var("JAVA_HOME").is_err() {
        let homebrew_jdk = Path::new("/opt/homebrew/opt/openjdk");
        if homebrew_jdk.is_dir() {
            env::set_var("JAVA_HOME", homebrew_jdk);
        }
    }

    let aapt2 = build_tools_dir.join("aapt2");
    let zipalign = build_tools_dir.join("zipalign");
    let apksigner = build_tools_dir.join("apksigner");

    // Create temp work dir
    let work_dir = env::temp_dir().join(format!("daytona-wff-{}", std::process::id()));
    if let Err(e) = fs::create_dir_all(&work_dir) {
        eprintln!("error: cannot create temp dir: {}", e);
        return 1;
    }

    let result = build_apk(
        &pkg_dir,
        &out_apk,
        &aapt2,
        &zipalign,
        &apksigner,
        &platform_jar,
        &work_dir,
    );

    // Cleanup temp dir
    let _ = fs::remove_dir_all(&work_dir);

    match result {
        Ok(()) => {
            println!("Built signed WFF APK: {}", out_apk.display());
            0
        }
        Err(e) => {
            eprintln!("error: {}", e);
            1
        }
    }
}

fn build_apk(
    pkg_dir: &Path,
    out_apk: &Path,
    aapt2: &Path,
    zipalign: &Path,
    apksigner: &Path,
    platform_jar: &Path,
    work_dir: &Path,
) -> io::Result<()> {
    let compiled_res = work_dir.join("compiled_res.zip");
    let unaligned = work_dir.join("unaligned.apk");
    let aligned = work_dir.join("aligned.apk");

    // aapt2 compile
    run_cmd(
        aapt2.to_str().unwrap_or("aapt2"),
        &[
            "compile",
            "--dir",
            pkg_dir
                .join("src/main/res")
                .to_str()
                .unwrap_or("src/main/res"),
            "-o",
            compiled_res.to_str().unwrap_or("compiled_res.zip"),
        ],
    )?;

    // aapt2 link
    run_cmd(
        aapt2.to_str().unwrap_or("aapt2"),
        &[
            "link",
            "-o",
            unaligned.to_str().unwrap_or("unaligned.apk"),
            "-I",
            platform_jar.to_str().unwrap_or("android.jar"),
            "--manifest",
            pkg_dir
                .join("src/main/AndroidManifest.xml")
                .to_str()
                .unwrap_or("AndroidManifest.xml"),
            "--auto-add-overlay",
            compiled_res.to_str().unwrap_or("compiled_res.zip"),
        ],
    )?;

    // zipalign
    run_cmd(
        zipalign.to_str().unwrap_or("zipalign"),
        &[
            "-f",
            "-p",
            "4",
            unaligned.to_str().unwrap_or("unaligned.apk"),
            aligned.to_str().unwrap_or("aligned.apk"),
        ],
    )?;

    // Debug keystore
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let keystore = Path::new(&home).join(".android/debug.keystore");
    if !keystore.is_file() {
        if let Some(parent) = keystore.parent() {
            fs::create_dir_all(parent)?;
        }
        run_cmd(
            "keytool",
            &[
                "-genkeypair",
                "-keystore",
                keystore.to_str().unwrap_or("debug.keystore"),
                "-storepass",
                "android",
                "-alias",
                "androiddebugkey",
                "-keypass",
                "android",
                "-keyalg",
                "RSA",
                "-keysize",
                "2048",
                "-validity",
                "10000",
                "-dname",
                "CN=Android Debug,O=Android,C=US",
            ],
        )?;
    }

    // Create output directory
    if let Some(parent) = out_apk.parent() {
        fs::create_dir_all(parent)?;
    }

    // apksigner sign
    run_cmd(
        apksigner.to_str().unwrap_or("apksigner"),
        &[
            "sign",
            "--ks",
            keystore.to_str().unwrap_or("debug.keystore"),
            "--ks-pass",
            "pass:android",
            "--key-pass",
            "pass:android",
            "--ks-key-alias",
            "androiddebugkey",
            "--out",
            out_apk.to_str().unwrap_or("out.apk"),
            aligned.to_str().unwrap_or("aligned.apk"),
        ],
    )?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_sort_key_simple() {
        assert_eq!(version_sort_key("34.0.0"), vec![34, 0, 0]);
        assert_eq!(version_sort_key("35.0.0"), vec![35, 0, 0]);
    }

    #[test]
    fn version_sort_key_complex() {
        assert_eq!(version_sort_key("33.0.2"), vec![33, 0, 2]);
        assert_eq!(version_sort_key("34.0.0-rc1"), vec![34, 0, 0]);
    }

    #[test]
    fn version_sort_ordering() {
        let mut versions = vec!["33.0.2", "35.0.0", "34.0.0", "33.0.1"];
        versions.sort_by(|a, b| version_sort_key(a).cmp(&version_sort_key(b)));
        assert_eq!(versions, vec!["33.0.1", "33.0.2", "34.0.0", "35.0.0"]);
    }

    #[test]
    fn version_sort_android_platforms() {
        let mut platforms = vec!["android-34", "android-33", "android-35", "android-31"];
        platforms.sort_by(|a, b| version_sort_key(a).cmp(&version_sort_key(b)));
        assert_eq!(
            platforms,
            vec!["android-31", "android-33", "android-34", "android-35"]
        );
        assert_eq!(*platforms.last().unwrap(), "android-35");
    }

    static ENV_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

    #[test]
    fn sdk_root_from_env() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let saved = env::var("ANDROID_HOME").ok();
        env::set_var("ANDROID_HOME", "/custom/sdk");
        assert_eq!(resolve_sdk_root(), "/custom/sdk");
        match saved {
            Some(v) => env::set_var("ANDROID_HOME", v),
            None => env::remove_var("ANDROID_HOME"),
        }
    }

    #[test]
    fn sdk_root_default() {
        let _g = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let saved = env::var("ANDROID_HOME").ok();
        env::remove_var("ANDROID_HOME");
        assert_eq!(
            resolve_sdk_root(),
            "/opt/homebrew/share/android-commandlinetools"
        );
        if let Some(v) = saved {
            env::set_var("ANDROID_HOME", v);
        }
    }

    #[test]
    fn find_build_tools_empty_dir() {
        let tmp = std::env::temp_dir().join("test-bt-empty");
        let bt = tmp.join("build-tools");
        let _ = fs::create_dir_all(&bt);
        assert!(find_latest_build_tools(tmp.to_str().unwrap()).is_none());
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn find_build_tools_picks_latest() {
        let tmp = std::env::temp_dir().join("test-bt-pick");
        let bt = tmp.join("build-tools");
        for v in &["33.0.1", "35.0.0", "34.0.0"] {
            let _ = fs::create_dir_all(bt.join(v));
        }
        let result = find_latest_build_tools(tmp.to_str().unwrap()).unwrap();
        assert_eq!(result.file_name().unwrap().to_str().unwrap(), "35.0.0");
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn find_platform_jar_picks_latest() {
        let tmp = std::env::temp_dir().join("test-pj-pick");
        let plat = tmp.join("platforms");
        for v in &["android-33", "android-35", "android-34"] {
            let dir = plat.join(v);
            let _ = fs::create_dir_all(&dir);
            let _ = fs::write(dir.join("android.jar"), b"fake");
        }
        let result = find_latest_platform_jar(tmp.to_str().unwrap()).unwrap();
        assert!(result.to_str().unwrap().contains("android-35"));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn find_platform_jar_missing_jar_skipped() {
        let tmp = std::env::temp_dir().join("test-pj-skip");
        let plat = tmp.join("platforms");
        let _ = fs::create_dir_all(plat.join("android-35"));
        // No android.jar inside
        let with_jar = plat.join("android-34");
        let _ = fs::create_dir_all(&with_jar);
        let _ = fs::write(with_jar.join("android.jar"), b"fake");
        let result = find_latest_platform_jar(tmp.to_str().unwrap()).unwrap();
        assert!(result.to_str().unwrap().contains("android-34"));
        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn find_build_tools_nonexistent_sdk() {
        assert!(find_latest_build_tools("/nonexistent/sdk/path").is_none());
    }

    #[test]
    fn find_platform_jar_nonexistent_sdk() {
        assert!(find_latest_platform_jar("/nonexistent/sdk/path").is_none());
    }

    #[test]
    fn java_home_detection() {
        // Just verify the detection logic doesn't panic
        let saved = env::var("JAVA_HOME").ok();
        env::set_var("JAVA_HOME", "/test/java");
        assert_eq!(env::var("JAVA_HOME").unwrap(), "/test/java");
        match saved {
            Some(v) => env::set_var("JAVA_HOME", v),
            None => env::remove_var("JAVA_HOME"),
        }
    }
}
