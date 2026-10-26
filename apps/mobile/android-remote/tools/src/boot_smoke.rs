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
use std::thread;
use std::time::{Duration, Instant};

pub fn rlocation(runfile: &str) -> Option<PathBuf> {
    if let Ok(runfiles_dir) = env::var("RUNFILES_DIR") {
        let candidate = PathBuf::from(&runfiles_dir).join(runfile);
        if candidate.is_file() {
            return Some(candidate);
        }
    }

    if let Ok(manifest_file) = env::var("RUNFILES_MANIFEST_FILE") {
        if let Ok(content) = fs::read_to_string(&manifest_file) {
            let prefix = format!("{} ", runfile);
            for line in content.lines() {
                if let Some(rest) = line.strip_prefix(&prefix) {
                    let p = PathBuf::from(rest);
                    if p.is_file() {
                        return Some(p);
                    }
                }
            }
        }
    }

    None
}

pub fn find_adb_path<F: Fn(&Path) -> bool>(is_executable: F) -> Option<PathBuf> {
    if let Ok(adb) = env::var("ADB") {
        let p = PathBuf::from(&adb);
        if is_executable(&p) {
            return Some(p);
        }
    }

    if let Ok(path_var) = env::var("PATH") {
        for dir in env::split_paths(&path_var) {
            let candidate = dir.join("adb");
            if is_executable(&candidate) {
                return Some(candidate);
            }
        }
    }

    let home = env::var("HOME").unwrap_or_default();
    let candidates: Vec<PathBuf> = vec![
        env::var("ANDROID_HOME")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|s| PathBuf::from(s).join("platform-tools/adb")),
        env::var("ANDROID_SDK_ROOT")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|s| PathBuf::from(s).join("platform-tools/adb")),
        if !home.is_empty() {
            Some(PathBuf::from(&home).join("Library/Android/sdk/platform-tools/adb"))
        } else {
            None
        },
        if !home.is_empty() {
            Some(PathBuf::from(&home).join("Android/Sdk/platform-tools/adb"))
        } else {
            None
        },
        Some(PathBuf::from(
            "/opt/homebrew/share/android-commandlinetools/platform-tools/adb",
        )),
        Some(PathBuf::from("/usr/local/bin/adb")),
        Some(PathBuf::from("/opt/homebrew/bin/adb")),
    ]
    .into_iter()
    .flatten()
    .collect();

    for candidate in candidates {
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }

    None
}

pub fn parse_device_list(output: &str) -> Vec<String> {
    output
        .lines()
        .filter_map(|line| {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[1] == "device" && parts[0] != "List" {
                Some(parts[0].to_string())
            } else {
                None
            }
        })
        .collect()
}

pub fn pick_device(adb: &Path) -> Result<String, String> {
    if let Ok(serial) = env::var("ANDROID_SERIAL") {
        if !serial.is_empty() {
            return Ok(serial);
        }
    }

    let output = Command::new(adb)
        .arg("devices")
        .output()
        .map_err(|e| format!("failed to run adb devices: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let devices = parse_device_list(&stdout);

    match devices.len() {
        0 => Err("ERROR: no attached device. Boot an emulator or plug in a phone.".to_string()),
        1 => Ok(devices[0].clone()),
        n => {
            let list = devices.join("\n");
            Err(format!(
                "ERROR: {} devices attached; set ANDROID_SERIAL to choose one:\n{}",
                n, list
            ))
        }
    }
}

pub fn logcat_contains_displayed(logcat: &str, pkg: &str, activity: &str) -> Option<String> {
    let pattern = format!("Displayed {}/{}", pkg, activity);
    for line in logcat.lines() {
        if line.contains(&pattern) {
            return Some(line.to_string());
        }
    }
    None
}

pub fn crash_buffer_has_pkg(crash_text: &str, pkg: &str) -> bool {
    let pattern = format!("Process: {}", pkg);
    crash_text.contains(&pattern)
}

fn adb_cmd(adb: &Path, serial: &str) -> Command {
    let mut cmd = Command::new(adb);
    cmd.args(["-s", serial]);
    cmd
}

fn capture_evidence(adb: &Path, serial: &str, outdir: &Path) {
    let logcat_file = outdir.join("logcat.txt");
    if let Ok(output) = adb_cmd(adb, serial).args(["logcat", "-d"]).output() {
        let _ = fs::write(&logcat_file, &output.stdout);
    }

    let crash_file = outdir.join("crash.txt");
    if let Ok(output) = adb_cmd(adb, serial)
        .args(["logcat", "-b", "crash", "-d"])
        .output()
    {
        let _ = fs::write(&crash_file, &output.stdout);
    }

    let _ = adb_cmd(adb, serial)
        .args(["shell", "screencap", "-p", "/sdcard/boot_smoke.png"])
        .output();
    let _ = adb_cmd(adb, serial)
        .args(["pull", "/sdcard/boot_smoke.png"])
        .arg(outdir.join("screen.png"))
        .output();
    let _ = adb_cmd(adb, serial)
        .args(["shell", "rm", "-f", "/sdcard/boot_smoke.png"])
        .output();
}

fn is_file_executable(p: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(p) {
            return meta.is_file() && (meta.permissions().mode() & 0o111 != 0);
        }
        false
    }
    #[cfg(not(unix))]
    {
        p.is_file()
    }
}

pub fn run(_args: &[String]) -> i32 {
    let pkg = match env::var("APP_PACKAGE") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            eprintln!("ERROR: APP_PACKAGE must be set by the BUILD rule");
            return 1;
        }
    };
    let activity = match env::var("APP_ACTIVITY") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            eprintln!("ERROR: APP_ACTIVITY must be set by the BUILD rule");
            return 1;
        }
    };
    let launch_timeout_s: u64 = env::var("LAUNCH_TIMEOUT_S")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(90);
    let settle_s: u64 = env::var("SETTLE_S")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5);

    let apk_runfile = match env::var("APK") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            eprintln!("ERROR: APK env var must be set by the BUILD rule");
            return 1;
        }
    };

    let apk = match rlocation(&apk_runfile) {
        Some(p) if p.is_file() => p,
        Some(p) => {
            eprintln!("ERROR: cannot read the APK at '{}'", p.display());
            return 1;
        }
        None => {
            eprintln!("ERROR: cannot locate the APK runfile '{}'", apk_runfile);
            return 1;
        }
    };

    let adb = match find_adb_path(is_file_executable) {
        Some(p) => p,
        None => {
            eprintln!(
                "ERROR: no adb found.\n\n\
                 This test drives a real device or emulator, so it needs the platform-tools\n\
                 adb and a device already attached.\n\n\
                 If you are seeing this in CI, check FIRST whether the test ran remotely --\n\
                 a remote executor has neither adb nor the emulator, however healthy the\n\
                 runner's own device is. The target carries \"no-remote\" for that reason.\n\n\
                 Locally, Bazel scrubs PATH for tests, so pass the environment through\n\
                 explicitly:\n\n\
                   bazel test //mobile/android/remote:boot_smoke \\\n\
                     --test_env=ANDROID_HOME --test_env=PATH --test_output=all\n\n\
                 In CI the android-emulator composite action puts adb on the default PATH\n\
                 and boots a device before this runs."
            );
            return 1;
        }
    };

    let serial = match pick_device(&adb) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{}", e);
            return 1;
        }
    };
    println!("device: {}", serial);

    let outdir = env::var("TEST_UNDECLARED_OUTPUTS_DIR")
        .or_else(|_| env::var("TMPDIR"))
        .unwrap_or_else(|_| "/tmp".to_string());
    let outdir = PathBuf::from(&outdir);
    let _ = fs::create_dir_all(&outdir);

    struct EvidenceGuard<'a> {
        adb: &'a Path,
        serial: &'a str,
        outdir: &'a Path,
    }
    impl<'a> Drop for EvidenceGuard<'a> {
        fn drop(&mut self) {
            capture_evidence(self.adb, self.serial, self.outdir);
        }
    }
    let _guard = EvidenceGuard {
        adb: &adb,
        serial: &serial,
        outdir: &outdir,
    };

    println!("waiting for the device to finish booting");
    let _ = adb_cmd(&adb, &serial).arg("wait-for-device").status();

    let boot_deadline = Instant::now() + Duration::from_secs(launch_timeout_s);
    loop {
        if let Ok(output) = adb_cmd(&adb, &serial)
            .args(["shell", "getprop", "sys.boot_completed"])
            .output()
        {
            let val = String::from_utf8_lossy(&output.stdout)
                .trim()
                .replace('\r', "");
            if val == "1" {
                break;
            }
        }
        if Instant::now() >= boot_deadline {
            eprintln!(
                "ERROR: device never reported sys.boot_completed within {}s",
                launch_timeout_s
            );
            return 1;
        }
        thread::sleep(Duration::from_secs(2));
    }

    let _ = adb_cmd(&adb, &serial).args(["uninstall", &pkg]).output();

    println!("installing {}", apk.display());
    let install_status = adb_cmd(&adb, &serial)
        .args(["install", "-r"])
        .arg(&apk)
        .status();
    match install_status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!(
                "ERROR: adb install failed with exit code {}",
                s.code().unwrap_or(-1)
            );
            return 1;
        }
        Err(e) => {
            eprintln!("ERROR: failed to run adb install: {}", e);
            return 1;
        }
    }

    let _ = adb_cmd(&adb, &serial)
        .args(["logcat", "-b", "all", "-c"])
        .output()
        .or_else(|_| adb_cmd(&adb, &serial).args(["logcat", "-c"]).output());

    println!("launching {}/{}", pkg, activity);
    let _ = adb_cmd(&adb, &serial)
        .args([
            "shell",
            "am",
            "start",
            "-n",
            &format!("{}/{}", pkg, activity),
        ])
        .status();

    println!("waiting for the first frame");
    let logcat_file = outdir.join("logcat.txt");
    let crash_file = outdir.join("crash.txt");
    let frame_deadline = Instant::now() + Duration::from_secs(launch_timeout_s);
    let mut displayed = String::new();

    while Instant::now() < frame_deadline {
        if let Ok(output) = adb_cmd(&adb, &serial).args(["logcat", "-d"]).output() {
            let logcat = String::from_utf8_lossy(&output.stdout);
            let _ = fs::write(&logcat_file, &output.stdout);
            if let Some(line) = logcat_contains_displayed(&logcat, &pkg, &activity) {
                displayed = line;
                break;
            }
        }

        if let Ok(output) = adb_cmd(&adb, &serial)
            .args(["logcat", "-b", "crash", "-d"])
            .output()
        {
            let crash_text = String::from_utf8_lossy(&output.stdout);
            let _ = fs::write(&crash_file, &output.stdout);
            if crash_buffer_has_pkg(&crash_text, &pkg) {
                eprintln!("ERROR: {} crashed before drawing its first frame:", pkg);
                for (i, line) in crash_text.lines().enumerate() {
                    if i >= 40 {
                        break;
                    }
                    eprintln!("{}", line);
                }
                return 1;
            }
        }

        thread::sleep(Duration::from_secs(2));
    }

    if displayed.is_empty() {
        eprintln!(
            "ERROR: {}/{} never drew a frame within {}s.",
            pkg, activity, launch_timeout_s
        );
        eprintln!("Last 60 logcat lines:");
        if let Ok(content) = fs::read_to_string(&logcat_file) {
            let lines: Vec<&str> = content.lines().collect();
            let start = lines.len().saturating_sub(60);
            for line in &lines[start..] {
                eprintln!("{}", line);
            }
        }
        return 1;
    }

    if let Some(pos) = displayed.find("ActivityTaskManager: ") {
        println!(
            "first frame: {}",
            &displayed[pos + "ActivityTaskManager: ".len()..]
        );
    } else {
        println!("first frame: {}", displayed);
    }

    println!("settling for {}s", settle_s);
    thread::sleep(Duration::from_secs(settle_s));

    if let Ok(output) = adb_cmd(&adb, &serial)
        .args(["logcat", "-b", "crash", "-d"])
        .output()
    {
        let crash_text = String::from_utf8_lossy(&output.stdout);
        let _ = fs::write(&crash_file, &output.stdout);
        if crash_buffer_has_pkg(&crash_text, &pkg) {
            eprintln!("ERROR: {} crashed during startup:", pkg);
            for (i, line) in crash_text.lines().enumerate() {
                if i >= 40 {
                    break;
                }
                eprintln!("{}", line);
            }
            return 1;
        }
    }

    let pid_output = adb_cmd(&adb, &serial)
        .args(["shell", "pidof", &pkg])
        .output();
    let pid = match pid_output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim().replace('\r', ""),
        Err(_) => String::new(),
    };

    if pid.is_empty() {
        eprintln!(
            "ERROR: {} is no longer running {}s after launch,",
            pkg, settle_s
        );
        eprintln!("       and left nothing in the crash buffer. Last 60 logcat lines:");
        if let Ok(content) = fs::read_to_string(&logcat_file) {
            let lines: Vec<&str> = content.lines().collect();
            let start = lines.len().saturating_sub(60);
            for line in &lines[start..] {
                eprintln!("{}", line);
            }
        }
        return 1;
    }

    println!(
        "ok: {} drew its first frame and is still running (pid {})",
        pkg, pid
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::{Mutex, MutexGuard};

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn lock_env() -> MutexGuard<'static, ()> {
        ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner())
    }

    #[test]
    fn rlocation_via_runfiles_dir() {
        let _g = lock_env();
        let dir = env::temp_dir().join("boot_smoke_test_rlocation");
        let _ = fs::create_dir_all(&dir);
        let target = dir.join("my_runfile.txt");
        fs::write(&target, "content").unwrap();

        env::set_var("RUNFILES_DIR", dir.to_str().unwrap());
        let result = rlocation("my_runfile.txt");
        env::remove_var("RUNFILES_DIR");

        assert_eq!(result, Some(target));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rlocation_via_manifest() {
        let _g = lock_env();
        let dir = env::temp_dir().join("boot_smoke_test_manifest");
        let _ = fs::create_dir_all(&dir);
        let real_file = dir.join("real.apk");
        fs::write(&real_file, "apk data").unwrap();

        let manifest = dir.join("manifest.txt");
        fs::write(&manifest, format!("some/runfile {}", real_file.display())).unwrap();

        env::remove_var("RUNFILES_DIR");
        env::set_var("RUNFILES_MANIFEST_FILE", manifest.to_str().unwrap());
        let result = rlocation("some/runfile");
        env::remove_var("RUNFILES_MANIFEST_FILE");

        assert_eq!(result, Some(real_file));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rlocation_missing_returns_none() {
        let _g = lock_env();
        env::remove_var("RUNFILES_DIR");
        env::remove_var("RUNFILES_MANIFEST_FILE");
        assert_eq!(rlocation("nonexistent"), None);
    }

    #[test]
    fn find_adb_from_adb_env() {
        let _g = lock_env();
        env::remove_var("ADB");
        let found = find_adb_path(|p| p == Path::new("/custom/adb"));
        assert_eq!(found, None);

        env::set_var("ADB", "/custom/adb");
        let found = find_adb_path(|p| p == Path::new("/custom/adb"));
        env::remove_var("ADB");
        assert_eq!(found, Some(PathBuf::from("/custom/adb")));
    }

    #[test]
    fn find_adb_from_android_home() {
        let _g = lock_env();
        env::remove_var("ADB");
        let saved_path = env::var("PATH").unwrap_or_default();
        env::set_var("PATH", "");
        env::set_var("ANDROID_HOME", "/sdk");
        env::remove_var("ANDROID_SDK_ROOT");

        let found = find_adb_path(|p| p == Path::new("/sdk/platform-tools/adb"));
        env::set_var("PATH", &saved_path);
        env::remove_var("ANDROID_HOME");

        assert_eq!(found, Some(PathBuf::from("/sdk/platform-tools/adb")));
    }

    #[test]
    fn find_adb_homebrew_fallback() {
        let _g = lock_env();
        env::remove_var("ADB");
        let saved_path = env::var("PATH").unwrap_or_default();
        env::set_var("PATH", "");
        env::remove_var("ANDROID_HOME");
        env::remove_var("ANDROID_SDK_ROOT");

        let found = find_adb_path(|p| p == Path::new("/opt/homebrew/bin/adb"));
        env::set_var("PATH", &saved_path);

        assert_eq!(found, Some(PathBuf::from("/opt/homebrew/bin/adb")));
    }

    #[test]
    fn find_adb_nothing_found() {
        let _g = lock_env();
        env::remove_var("ADB");
        let saved_path = env::var("PATH").unwrap_or_default();
        env::set_var("PATH", "");
        env::remove_var("ANDROID_HOME");
        env::remove_var("ANDROID_SDK_ROOT");
        let saved_home = env::var("HOME").unwrap_or_default();
        env::set_var("HOME", "/nonexistent");

        let found = find_adb_path(|_| false);
        env::set_var("PATH", &saved_path);
        env::set_var("HOME", &saved_home);

        assert_eq!(found, None);
    }

    #[test]
    fn parse_device_list_single() {
        let output = "List of devices attached\nemulator-5554\tdevice\n\n";
        let devices = parse_device_list(output);
        assert_eq!(devices, vec!["emulator-5554"]);
    }

    #[test]
    fn parse_device_list_multiple() {
        let output = "List of devices attached\n\
                      emulator-5554\tdevice\n\
                      192.168.1.2:5555\tdevice\n\n";
        let devices = parse_device_list(output);
        assert_eq!(devices, vec!["emulator-5554", "192.168.1.2:5555"]);
    }

    #[test]
    fn parse_device_list_empty() {
        let output = "List of devices attached\n\n";
        let devices = parse_device_list(output);
        assert!(devices.is_empty());
    }

    #[test]
    fn parse_device_list_unauthorized() {
        let output = "List of devices attached\nemulator-5554\tunauthorized\n\n";
        let devices = parse_device_list(output);
        assert!(devices.is_empty());
    }

    #[test]
    fn parse_device_list_offline_and_device() {
        let output = "List of devices attached\n\
                      ABC123\toffline\n\
                      DEF456\tdevice\n\n";
        let devices = parse_device_list(output);
        assert_eq!(devices, vec!["DEF456"]);
    }

    #[test]
    fn logcat_displayed_match() {
        let logcat = "10-01 12:00:00.000  1234  1234 I ActivityTaskManager: Displayed com.example/.MainActivity: +500ms\n\
                      10-01 12:00:01.000  1234  1234 I SomeOther: noise\n";
        let result = logcat_contains_displayed(logcat, "com.example", ".MainActivity");
        assert!(result.is_some());
        assert!(result
            .unwrap()
            .contains("Displayed com.example/.MainActivity"));
    }

    #[test]
    fn logcat_displayed_no_match() {
        let logcat = "10-01 12:00:00.000  1234  1234 I ActivityTaskManager: Displayed com.other/.Other: +500ms\n";
        assert!(logcat_contains_displayed(logcat, "com.example", ".MainActivity").is_none());
    }

    #[test]
    fn logcat_displayed_empty() {
        assert!(logcat_contains_displayed("", "com.example", ".Main").is_none());
    }

    #[test]
    fn crash_buffer_detected() {
        let crash = "10-01 12:00:00.000 E AndroidRuntime: FATAL EXCEPTION: main\n\
                     10-01 12:00:00.000 E AndroidRuntime: Process: com.example, PID: 1234\n";
        assert!(crash_buffer_has_pkg(crash, "com.example"));
    }

    #[test]
    fn crash_buffer_no_match() {
        let crash = "10-01 12:00:00.000 E AndroidRuntime: Process: com.other, PID: 1234\n";
        assert!(!crash_buffer_has_pkg(crash, "com.example"));
    }

    #[test]
    fn crash_buffer_empty() {
        assert!(!crash_buffer_has_pkg("", "com.example"));
    }

    #[test]
    fn crash_buffer_substring_matches_like_grep_f() {
        // grep -qF "Process: pkg" is a substring match, so com.example
        // matches inside com.example.sub — faithful to the shell.
        let crash = "Process: com.example.sub, PID: 1234\n";
        assert!(crash_buffer_has_pkg(crash, "com.example"));
    }
}
