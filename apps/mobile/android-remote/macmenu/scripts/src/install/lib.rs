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

//! Rust port of `apps/mobile/android-remote/macmenu/install.sh`.

use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const DEFAULT_DEST: &str = "/Applications";
pub const APP_BUNDLE_NAME: &str = "VitruvianRemote.app";
pub const APP_PROCESS_NAME: &str = "VitruvianRemote";
pub const BUNDLE_ID: &str = "com.vitruviansoftware.remote";
pub const ZIP_RUNFILES_REL: &str = "_main/apps/mobile/android-remote/macmenu/VitruvianRemote.zip";
pub const AGENT_RUNFILES_REL: &str = "_main/apps/mobile/android-remote/macagent/macagent_/macagent";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallPaths {
    pub dest_dir: PathBuf,
    pub dest_app: PathBuf,
    pub zip_path: PathBuf,
    pub agent_path: PathBuf,
}

pub fn resolve_install_paths(
    argv0: &str,
    dest_env: Option<&str>,
    runfiles_env: Option<&str>,
) -> InstallPaths {
    let dest_dir = match dest_env {
        Some(d) if !d.is_empty() => PathBuf::from(d),
        _ => PathBuf::from(DEFAULT_DEST),
    };
    let dest_app = dest_dir.join(APP_BUNDLE_NAME);
    let runfiles = match runfiles_env {
        Some(r) if !r.is_empty() => PathBuf::from(r),
        _ => PathBuf::from(format!("{argv0}.runfiles")),
    };
    let zip_path = runfiles.join(ZIP_RUNFILES_REL);
    let agent_path = runfiles.join(AGENT_RUNFILES_REL);
    InstallPaths {
        dest_dir,
        dest_app,
        zip_path,
        agent_path,
    }
}

pub fn staged_agent_dest(work_dir: &Path) -> PathBuf {
    work_dir
        .join(APP_BUNDLE_NAME)
        .join("Contents/MacOS/vitruvian-remote-agent")
}

fn is_darwin() -> bool {
    Command::new("uname")
        .arg("-s")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "Darwin")
        .unwrap_or(false)
}

fn is_app_running() -> bool {
    Command::new("pgrep")
        .args(["-xq", APP_PROCESS_NAME])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn make_work_dir() -> Result<PathBuf, String> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = env::temp_dir().join(format!("vitruvian-remote-install-{nanos}"));
    fs::create_dir_all(&dir).map_err(|e| format!("failed to create temp dir: {e}"))?;
    Ok(dir)
}

pub fn run(args: &[String]) -> i32 {
    if !is_darwin() {
        eprintln!("install.sh: Vitruvian Remote is a macOS app");
        return 1;
    }

    let argv0 = args.first().map(|s| s.as_str()).unwrap_or("install");
    let dest_env = env::var("VITRUVIAN_REMOTE_DEST").ok();
    let runfiles_env = env::var("RUNFILES_DIR").ok();
    let paths = resolve_install_paths(argv0, dest_env.as_deref(), runfiles_env.as_deref());

    if !paths.zip_path.is_file() {
        eprintln!(
            "install.sh: built app not found at {} (run via: bazel run --config=macos-app //apps/mobile/android-remote/macmenu:install)",
            paths.zip_path.display()
        );
        return 1;
    }

    let work_dir = match make_work_dir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("install.sh: {e}");
            return 1;
        }
    };

    let result = install_inner(&paths, &work_dir);
    let _ = fs::remove_dir_all(&work_dir);
    result
}

fn install_inner(paths: &InstallPaths, work_dir: &Path) -> i32 {
    let ditto_extract = Command::new("ditto")
        .args(["-x", "-k"])
        .arg(&paths.zip_path)
        .arg(work_dir)
        .status();
    if !ditto_extract.map(|s| s.success()).unwrap_or(false) {
        eprintln!("install.sh: failed to extract {}", paths.zip_path.display());
        return 1;
    }

    let staged_app = work_dir.join(APP_BUNDLE_NAME);
    if paths.agent_path.is_file() {
        let dest_agent = staged_agent_dest(work_dir);
        if let Some(parent) = dest_agent.parent() {
            let _ = fs::create_dir_all(parent);
        }
        if let Err(e) = fs::copy(&paths.agent_path, &dest_agent) {
            eprintln!("install.sh: failed to bundle agent: {e}");
            return 1;
        }
        let _ = fs::set_permissions(&dest_agent, fs::Permissions::from_mode(0o755));
        let _ = Command::new("codesign")
            .args(["--force", "--sign", "-"])
            .arg(&staged_app)
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
    }

    if is_app_running() {
        let quit_script = format!("tell application id \"{BUNDLE_ID}\" to quit");
        let quit_ok = Command::new("osascript")
            .args(["-e", &quit_script])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !quit_ok {
            let _ = Command::new("pkill")
                .args(["-x", APP_PROCESS_NAME])
                .status();
        }
        for _ in 0..20 {
            if !is_app_running() {
                break;
            }
            thread::sleep(Duration::from_millis(200));
        }
    }

    let _ = fs::remove_dir_all(&paths.dest_app);
    let ditto_copy = Command::new("ditto")
        .arg(&staged_app)
        .arg(&paths.dest_app)
        .status();
    if !ditto_copy.map(|s| s.success()).unwrap_or(false) {
        eprintln!(
            "install.sh: failed to copy app to {}",
            paths.dest_app.display()
        );
        return 1;
    }

    if !Command::new("open")
        .arg(&paths.dest_app)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        eprintln!(
            "install.sh: the app did not start; try: open {}",
            paths.dest_app.display()
        );
        return 1;
    }

    for _ in 0..25 {
        if is_app_running() {
            println!(
                "Vitruvian Remote installed at {} and running.",
                paths.dest_app.display()
            );
            println!("Look for the V icon in the menu bar. Turn on Open at Login from its menu.");
            return 0;
        }
        thread::sleep(Duration::from_millis(200));
    }

    eprintln!(
        "install.sh: the app did not start; try: open {}",
        paths.dest_app.display()
    );
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_install_paths_defaults_to_applications_and_argv0_runfiles() {
        let p = resolve_install_paths("/path/to/install", None, None);
        assert_eq!(p.dest_dir, PathBuf::from("/Applications"));
        assert_eq!(
            p.dest_app,
            PathBuf::from("/Applications/VitruvianRemote.app")
        );
        assert_eq!(
            p.zip_path,
            PathBuf::from(
                "/path/to/install.runfiles/_main/apps/mobile/android-remote/macmenu/VitruvianRemote.zip"
            )
        );
        assert_eq!(
            p.agent_path,
            PathBuf::from(
                "/path/to/install.runfiles/_main/apps/mobile/android-remote/macagent/macagent_/macagent"
            )
        );
    }

    #[test]
    fn resolve_install_paths_honors_env_overrides() {
        let p = resolve_install_paths(
            "/path/to/install",
            Some("/tmp/custom-apps"),
            Some("/tmp/custom-runfiles"),
        );
        assert_eq!(p.dest_dir, PathBuf::from("/tmp/custom-apps"));
        assert_eq!(
            p.dest_app,
            PathBuf::from("/tmp/custom-apps/VitruvianRemote.app")
        );
        assert_eq!(
            p.zip_path,
            PathBuf::from(
                "/tmp/custom-runfiles/_main/apps/mobile/android-remote/macmenu/VitruvianRemote.zip"
            )
        );
    }

    #[test]
    fn staged_agent_dest_places_binary_inside_contents_macos() {
        let dest = staged_agent_dest(Path::new("/tmp/work"));
        assert_eq!(
            dest,
            PathBuf::from("/tmp/work/VitruvianRemote.app/Contents/MacOS/vitruvian-remote-agent")
        );
    }
}
