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

//! Rust port of `flash.sh`: flash the ESP32-S3 images to a serial port.
//!
//! Two layouts, same as the shell script: a *bundle* (`firmware.bin`, `bootloader.bin`
//! and `partitions.bin` sitting beside the tool -- the release zip, or Bazel runfiles)
//! is written with `esptool`; otherwise (or when no esptool is available) the project
//! is uploaded through PlatformIO.
//!
//! This file is self-contained (std only) so the release zip can ship it: see
//! `main.rs`, which pulls it in with `#[path]`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub trait Runner {
    /// Run to completion with inherited stdio; returns the exit code.
    fn status(&self, program: &str, args: &[String]) -> Result<i32, String>;
    /// True when the command exits 0 (output discarded).
    fn succeeds(&self, program: &str, args: &[String]) -> bool;
}

pub struct RealRunner;

impl Runner for RealRunner {
    fn status(&self, program: &str, args: &[String]) -> Result<i32, String> {
        let st = Command::new(program)
            .args(args)
            .status()
            .map_err(|e| format!("failed to run {}: {}", program, e))?;
        Ok(st.code().unwrap_or(1))
    }
    fn succeeds(&self, program: &str, args: &[String]) -> bool {
        Command::new(program)
            .args(args)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct FlashArgs {
    pub port: Option<String>,
    pub help: bool,
}

pub fn parse_args(args: &[String]) -> Result<FlashArgs, String> {
    let mut result = FlashArgs::default();
    for a in args {
        match a.as_str() {
            "-h" | "--help" => {
                result.help = true;
                return Ok(result);
            }
            other => {
                if result.port.is_none() && !other.starts_with('-') {
                    result.port = Some(other.to_string());
                } else {
                    return Err(format!("unexpected argument: {}", other));
                }
            }
        }
    }
    Ok(result)
}

pub fn usage() -> &'static str {
    "Usage: flash [/dev/cu.usbmodemXXXX]\nFlashes ESP32-S3 firmware to the specified port, or auto-detects if omitted."
}

/// `ls /dev/cu.usbmodem* /dev/ttyACM* | head -n 1`: usbmodem ports first, then ttyACM,
/// each group in name order.
pub fn detect_port(dev_dir: &Path) -> Option<String> {
    let names: Vec<String> = fs::read_dir(dev_dir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.file_name().to_string_lossy().to_string())
        .collect();
    for prefix in ["cu.usbmodem", "ttyACM"] {
        let mut m: Vec<&String> = names.iter().filter(|n| n.starts_with(prefix)).collect();
        m.sort();
        if let Some(first) = m.first() {
            return Some(dev_dir.join(first).to_string_lossy().to_string());
        }
    }
    None
}

/// First of `candidates` holding all three images -- the "bundle" layout.
pub fn find_bundle_dir(candidates: &[PathBuf]) -> Option<PathBuf> {
    candidates
        .iter()
        .find(|d| {
            ["firmware.bin", "bootloader.bin", "partitions.bin"]
                .iter()
                .all(|f| d.join(f).is_file())
        })
        .cloned()
}

fn on_path(path: &str, name: &str) -> bool {
    path.split(':')
        .filter(|d| !d.is_empty())
        .any(|d| Path::new(d).join(name).is_file())
}

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|x| x.to_string()).collect()
}

/// `esptool`, else `uvx esptool`, else `python3 -m esptool`.
pub fn find_esptool(path: &str, r: &dyn Runner) -> Option<Vec<String>> {
    if on_path(path, "esptool") {
        Some(s(&["esptool"]))
    } else if on_path(path, "uvx") {
        Some(s(&["uvx", "esptool"]))
    } else if r.succeeds("python3", &s(&["-m", "esptool", "--help"])) {
        Some(s(&["python3", "-m", "esptool"]))
    } else {
        None
    }
}

/// `pio`, else `$HOME/.local/bin/pio`, else `uv run --with platformio platformio`.
pub fn find_pio(path: &str, home: &str) -> Option<Vec<String>> {
    if on_path(path, "pio") {
        return Some(s(&["pio"]));
    }
    let local = Path::new(home).join(".local/bin/pio");
    if !home.is_empty() && local.is_file() {
        return Some(vec![local.to_string_lossy().to_string()]);
    }
    if on_path(path, "uv") {
        return Some(s(&["uv", "run", "--with", "platformio", "platformio"]));
    }
    None
}

/// Where the tool looks, injected so tests need no real devices or tools.
pub struct Env {
    pub dev_dir: PathBuf,
    pub path: String,
    pub home: String,
    /// Directories searched, in order, for a pre-built bundle.
    pub bundle_candidates: Vec<PathBuf>,
    /// PlatformIO project used for the upload fallback.
    pub project_dir: PathBuf,
}

impl Env {
    pub fn from_process() -> Env {
        let exe_dir = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()));
        let mut bundle = vec![];
        if let Some(d) = &exe_dir {
            bundle.push(d.clone());
        }
        // `bazel run`: the images are data of this binary, in its runfiles tree.
        if let Ok(rf) = std::env::var("RUNFILES_DIR") {
            bundle.push(PathBuf::from(&rf).join("_main/apps/embedded/esp32-s3"));
        }
        if let Ok(exe) = std::env::current_exe() {
            let mut rf = exe.clone().into_os_string();
            rf.push(".runfiles");
            bundle.push(PathBuf::from(rf).join("_main/apps/embedded/esp32-s3"));
        }
        if let Ok(cwd) = std::env::current_dir() {
            bundle.push(cwd);
        }
        let project_dir = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
            Ok(ws) if !ws.is_empty() => PathBuf::from(ws).join("apps/embedded/esp32-s3"),
            _ => exe_dir.unwrap_or_else(|| PathBuf::from(".")),
        };
        Env {
            dev_dir: PathBuf::from("/dev"),
            path: std::env::var("PATH").unwrap_or_default(),
            home: std::env::var("HOME").unwrap_or_default(),
            bundle_candidates: bundle,
            project_dir,
        }
    }
}

pub fn flash(args: &FlashArgs, env: &Env, r: &dyn Runner) -> Result<(), String> {
    let port = match &args.port {
        Some(p) => p.clone(),
        None => detect_port(&env.dev_dir).ok_or(
            "No ESP32-S3 serial port detected. Specify explicitly:\n  flash /dev/cu.usbmodemXXXX"
                .to_string(),
        )?,
    };

    eprintln!("==================================================");
    eprintln!("Uploading Firmware to ESP32-S3 on {}", port);
    eprintln!("==================================================");

    if let Some(dir) = find_bundle_dir(&env.bundle_candidates) {
        if let Some(esptool) = find_esptool(&env.path, r) {
            let f = |n: &str| dir.join(n).to_string_lossy().to_string();
            let mut a: Vec<String> = esptool[1..].to_vec();
            a.extend(s(&[
                "-p",
                &port,
                "-b",
                "460800",
                "--before",
                "default_reset",
                "--after",
                "hard_reset",
                "write_flash",
            ]));
            a.extend(s(&["0x0000"]));
            a.push(f("bootloader.bin"));
            a.extend(s(&["0x8000"]));
            a.push(f("partitions.bin"));
            a.extend(s(&["0x10000"]));
            a.push(f("firmware.bin"));
            return match r.status(&esptool[0], &a)? {
                0 => Ok(()),
                c => Err(format!("esptool failed (exit {})", c)),
            };
        }
    }

    // Fall back to PlatformIO upload.
    if let Some(pio) = find_pio(&env.path, &env.home) {
        let mut a: Vec<String> = pio[1..].to_vec();
        a.extend(s(&["run", "-d"]));
        a.push(env.project_dir.to_string_lossy().to_string());
        a.extend(s(&["--target", "upload", "--upload-port", &port]));
        return match r.status(&pio[0], &a)? {
            0 => Ok(()),
            c => Err(format!("PlatformIO upload failed (exit {})", c)),
        };
    }

    Err("Neither esptool nor platformio found.".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct Fake {
        calls: RefCell<Vec<(String, Vec<String>)>>,
        python_esptool_ok: bool,
        exit: i32,
    }
    impl Fake {
        fn new() -> Self {
            Fake {
                calls: RefCell::new(vec![]),
                python_esptool_ok: false,
                exit: 0,
            }
        }
    }
    impl Runner for Fake {
        fn status(&self, p: &str, a: &[String]) -> Result<i32, String> {
            self.calls.borrow_mut().push((p.into(), a.to_vec()));
            Ok(self.exit)
        }
        fn succeeds(&self, _p: &str, _a: &[String]) -> bool {
            self.python_esptool_ok
        }
    }

    fn tmpdir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("flash-test-{}-{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn touch(dir: &Path, names: &[&str]) {
        fs::create_dir_all(dir).unwrap();
        for n in names {
            fs::write(dir.join(n), "").unwrap();
        }
    }

    fn bundle(dir: &Path) {
        touch(dir, &["firmware.bin", "bootloader.bin", "partitions.bin"]);
    }

    fn env(root: &Path, path: &str) -> Env {
        Env {
            dev_dir: root.join("dev"),
            path: path.into(),
            home: root.join("home").to_string_lossy().to_string(),
            bundle_candidates: vec![root.join("bundle")],
            project_dir: root.join("proj"),
        }
    }

    fn args(port: &str) -> FlashArgs {
        FlashArgs {
            port: Some(port.into()),
            help: false,
        }
    }

    #[test]
    fn parses_port_and_help() {
        assert_eq!(
            parse_args(&s(&["/dev/x"])).unwrap().port.as_deref(),
            Some("/dev/x")
        );
        assert!(parse_args(&s(&["--help"])).unwrap().help);
        assert!(parse_args(&s(&["-h"])).unwrap().help);
        assert!(parse_args(&[]).unwrap().port.is_none());
        assert!(parse_args(&s(&["--bogus"])).is_err());
        assert!(parse_args(&s(&["/dev/a", "/dev/b"])).is_err());
    }

    #[test]
    fn autodetect_prefers_usbmodem_then_ttyacm_in_name_order() {
        let root = tmpdir("detect");
        let dev = root.join("dev");
        touch(&dev, &["ttyACM0", "cu.usbmodem2", "cu.usbmodem1", "ttyS0"]);
        assert_eq!(
            detect_port(&dev).unwrap(),
            dev.join("cu.usbmodem1").to_string_lossy()
        );
        fs::remove_file(dev.join("cu.usbmodem1")).unwrap();
        fs::remove_file(dev.join("cu.usbmodem2")).unwrap();
        assert_eq!(
            detect_port(&dev).unwrap(),
            dev.join("ttyACM0").to_string_lossy()
        );
        fs::remove_file(dev.join("ttyACM0")).unwrap();
        assert!(detect_port(&dev).is_none());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn no_port_is_an_error() {
        let root = tmpdir("noport");
        touch(&root.join("dev"), &[]);
        let f = Fake::new();
        let e = flash(&FlashArgs::default(), &env(&root, ""), &f).unwrap_err();
        assert!(e.contains("No ESP32-S3 serial port detected"));
        assert!(f.calls.borrow().is_empty());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn bundle_is_written_with_esptool_at_the_shell_offsets() {
        let root = tmpdir("esptool");
        bundle(&root.join("bundle"));
        let bin = root.join("tools");
        touch(&bin, &["esptool"]);
        let f = Fake::new();
        flash(
            &args("/dev/cu.usbmodem9"),
            &env(&root, bin.to_str().unwrap()),
            &f,
        )
        .unwrap();
        let calls = f.calls.borrow();
        assert_eq!(calls.len(), 1);
        let (prog, a) = &calls[0];
        assert_eq!(prog, "esptool");
        let b = root.join("bundle");
        let want: Vec<String> = [
            "-p",
            "/dev/cu.usbmodem9",
            "-b",
            "460800",
            "--before",
            "default_reset",
            "--after",
            "hard_reset",
            "write_flash",
            "0x0000",
            b.join("bootloader.bin").to_str().unwrap(),
            "0x8000",
            b.join("partitions.bin").to_str().unwrap(),
            "0x10000",
            b.join("firmware.bin").to_str().unwrap(),
        ]
        .iter()
        .map(|x| x.to_string())
        .collect();
        assert_eq!(a, &want);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn esptool_lookup_order() {
        let root = tmpdir("order");
        let uvx = root.join("uvx");
        touch(&uvx, &["uvx"]);
        let mut f = Fake::new();
        assert_eq!(
            find_esptool(uvx.to_str().unwrap(), &f).unwrap(),
            s(&["uvx", "esptool"])
        );
        f.python_esptool_ok = true;
        assert_eq!(
            find_esptool("", &f).unwrap(),
            s(&["python3", "-m", "esptool"])
        );
        f.python_esptool_ok = false;
        assert!(find_esptool("", &f).is_none());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn esptool_failure_is_reported() {
        let root = tmpdir("esptoolfail");
        bundle(&root.join("bundle"));
        touch(&root.join("tools"), &["esptool"]);
        let mut f = Fake::new();
        f.exit = 3;
        let e = flash(
            &args("/dev/x"),
            &env(&root, root.join("tools").to_str().unwrap()),
            &f,
        )
        .unwrap_err();
        assert!(e.contains("esptool failed"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn bundle_without_esptool_falls_back_to_pio() {
        let root = tmpdir("fallback");
        bundle(&root.join("bundle"));
        let tools = root.join("tools");
        touch(&tools, &["pio"]);
        let f = Fake::new();
        flash(&args("/dev/x"), &env(&root, tools.to_str().unwrap()), &f).unwrap();
        let calls = f.calls.borrow();
        assert_eq!(calls[0].0, "pio");
        assert_eq!(
            calls[0].1,
            s(&[
                "run",
                "-d",
                root.join("proj").to_str().unwrap(),
                "--target",
                "upload",
                "--upload-port",
                "/dev/x"
            ])
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn incomplete_bundle_uses_pio_even_with_esptool() {
        let root = tmpdir("incomplete");
        touch(&root.join("bundle"), &["firmware.bin", "bootloader.bin"]); // no partitions.bin
        touch(&root.join("tools"), &["esptool", "pio"]);
        let f = Fake::new();
        flash(
            &args("/dev/x"),
            &env(&root, root.join("tools").to_str().unwrap()),
            &f,
        )
        .unwrap();
        assert_eq!(f.calls.borrow()[0].0, "pio");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn pio_lookup_order() {
        let root = tmpdir("pioorder");
        let home = root.join("home");
        touch(&home.join(".local/bin"), &["pio"]);
        assert_eq!(
            find_pio("", home.to_str().unwrap()).unwrap(),
            vec![home.join(".local/bin/pio").to_string_lossy().to_string()]
        );
        let uv = root.join("uv");
        touch(&uv, &["uv"]);
        assert_eq!(
            find_pio(uv.to_str().unwrap(), "/nonexistent").unwrap(),
            s(&["uv", "run", "--with", "platformio", "platformio"])
        );
        assert!(find_pio("", "/nonexistent").is_none());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn neither_tool_is_an_error() {
        let root = tmpdir("neither");
        let f = Fake::new();
        let e = flash(&args("/dev/x"), &env(&root, ""), &f).unwrap_err();
        assert_eq!(e, "Neither esptool nor platformio found.");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn bundle_dir_needs_all_three_images() {
        let root = tmpdir("bd");
        touch(&root.join("a"), &["firmware.bin"]);
        bundle(&root.join("b"));
        assert_eq!(
            find_bundle_dir(&[root.join("a"), root.join("b")]),
            Some(root.join("b"))
        );
        assert_eq!(find_bundle_dir(&[root.join("a")]), None);
        let _ = fs::remove_dir_all(&root);
    }
}
