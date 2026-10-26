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
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

const TOOLS: &[&str] = &[
    "git",
    "git-lfs",
    "gh",
    "curl",
    "jq",
    "python3",
    "node",
    "npm",
    "npx",
    "shellcheck",
    "unzip",
    "zip",
    "xz",
    "zstd",
    "gcc",
    "g++",
    "make",
    "tar",
    "gpg",
];

fn check(desc: &str, ok: bool, fail: &mut bool) {
    if ok {
        println!("  ok: {}", desc);
    } else {
        eprintln!("  FAIL: {}", desc);
        *fail = true;
    }
}

fn run_ok(cmd: &str, args: &[&str]) -> bool {
    Command::new(cmd)
        .args(args)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_ok_env(cmd: &str, args: &[&str], key: &str, val: &str) -> bool {
    Command::new(cmd)
        .args(args)
        .env(key, val)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn cmd_output(cmd: &str, args: &[&str]) -> Option<String> {
    Command::new(cmd)
        .args(args)
        .stderr(std::process::Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

pub fn read_version_id(path: &str) -> String {
    let contents = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return String::new(),
    };
    for line in contents.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("VERSION_ID=") {
            let val = rest.trim_matches('"').trim_matches('\'');
            return val.to_string();
        }
    }
    String::new()
}

fn get_id_string() -> String {
    let un = cmd_output("id", &["-un"]).unwrap_or_default();
    let uid = cmd_output("id", &["-u"]).unwrap_or_default();
    format!("{}:{}", un, uid)
}

fn command_exists(name: &str) -> bool {
    let path_var = std::env::var("PATH").unwrap_or_default();
    for dir in path_var.split(':') {
        if dir.is_empty() {
            continue;
        }
        let p = Path::new(dir).join(name);
        if p.is_file() {
            if let Ok(m) = p.metadata() {
                if m.permissions().mode() & 0o111 != 0 {
                    return true;
                }
            }
        }
    }
    false
}

fn env_or_default(key: &str, default: &str) -> String {
    match std::env::var(key) {
        Ok(v) if !v.is_empty() => v,
        _ => default.to_string(),
    }
}

pub fn run() -> i32 {
    let mut fail = false;

    let os_release_path = env_or_default("OS_RELEASE_PATH", "/etc/os-release");
    let runner_home = env_or_default("RUNNER_HOME", "/home/runner");
    let bazel_version = env_or_default("BAZEL_VERSION", "9.3.0");

    let vid = read_version_id(&os_release_path);
    check(&format!("test {} = 26.04", vid), vid == "26.04", &mut fail);

    let id_str = get_id_string();
    check(
        &format!("test {} = runner:1001", id_str),
        id_str == "runner:1001",
        &mut fail,
    );

    check("sudo -n true", run_ok("sudo", &["-n", "true"]), &mut fail);
    check(
        "sudo -n dpkg --version",
        run_ok("sudo", &["-n", "dpkg", "--version"]),
        &mut fail,
    );

    for tool in TOOLS {
        check(
            &format!("command -v {}", tool),
            command_exists(tool),
            &mut fail,
        );
    }

    let run_sh = format!("{}/run.sh", runner_home);
    check(
        &format!("test -x {}/run.sh", runner_home),
        is_executable(&run_sh),
        &mut fail,
    );

    let listener = format!("{}/bin/Runner.Listener", runner_home);
    check(
        &format!("{}/bin/Runner.Listener --version", runner_home),
        run_ok(&listener, &["--version"]),
        &mut fail,
    );

    check("command -v bazel", command_exists("bazel"), &mut fail);
    check("command -v bazelisk", command_exists("bazelisk"), &mut fail);

    check(
        &format!("env USE_BAZEL_VERSION={} bazel --version", bazel_version),
        run_ok_env("bazel", &["--version"], "USE_BAZEL_VERSION", &bazel_version),
        &mut fail,
    );

    if !fail {
        println!("parity: OK");
        0
    } else {
        eprintln!("parity: FAILED");
        1
    }
}

fn is_executable(path: &str) -> bool {
    let p = Path::new(path);
    if !p.is_file() {
        return false;
    }
    match p.metadata() {
        Ok(m) => m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn test_read_version_id_standard() {
        let dir = std::env::temp_dir().join("parity_test_vid");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("os-release");
        let mut f = fs::File::create(&path).unwrap();
        writeln!(f, "NAME=\"Ubuntu\"").unwrap();
        writeln!(f, "VERSION_ID=\"26.04\"").unwrap();
        writeln!(f, "ID=ubuntu").unwrap();
        drop(f);
        assert_eq!(read_version_id(path.to_str().unwrap()), "26.04");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_version_id_unquoted() {
        let dir = std::env::temp_dir().join("parity_test_vid_unq");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("os-release");
        let mut f = fs::File::create(&path).unwrap();
        writeln!(f, "VERSION_ID=24.04").unwrap();
        drop(f);
        assert_eq!(read_version_id(path.to_str().unwrap()), "24.04");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_read_version_id_missing_file() {
        assert_eq!(read_version_id("/nonexistent/os-release"), "");
    }

    #[test]
    fn test_read_version_id_no_field() {
        let dir = std::env::temp_dir().join("parity_test_vid_nof");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("os-release");
        let mut f = fs::File::create(&path).unwrap();
        writeln!(f, "NAME=\"Ubuntu\"").unwrap();
        writeln!(f, "ID=ubuntu").unwrap();
        drop(f);
        assert_eq!(read_version_id(path.to_str().unwrap()), "");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_command_exists_finds_sh() {
        assert!(command_exists("sh"));
    }

    #[test]
    fn test_command_exists_missing() {
        assert!(!command_exists("__nonexistent_tool_12345__"));
    }

    #[test]
    fn test_is_executable_true() {
        let dir = std::env::temp_dir().join("parity_test_exec");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("mybin");
        fs::write(&path, "#!/bin/sh\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        assert!(is_executable(path.to_str().unwrap()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_is_executable_false_no_x() {
        let dir = std::env::temp_dir().join("parity_test_noexec");
        let _ = fs::create_dir_all(&dir);
        let path = dir.join("mybin");
        fs::write(&path, "data\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        assert!(!is_executable(path.to_str().unwrap()));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_is_executable_false_missing() {
        assert!(!is_executable("/nonexistent/file"));
    }
}
