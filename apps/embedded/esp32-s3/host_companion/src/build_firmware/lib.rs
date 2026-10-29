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

//! Rust port of `build_firmware.sh`: compile the ESP32-S3 firmware with PlatformIO
//! and copy the three flashable images to the paths Bazel asked for. This is the
//! body of the `//apps/embedded/esp32-s3:firmware` genrule.
//!
//! THE GENRULE'S ENVIRONMENT IS NOT YOUR SHELL'S. Bazel hands a `local`-tagged
//! action only `PATH=/bin:/usr/bin:/usr/local/bin` and `TMPDIR`, and the execroot
//! has no `.git`. So this tool:
//!   * derives the home directory from the passwd database, never from `HOME`/`USER`;
//!   * does NOT stamp version/grade/commit -- that is `publish`'s job, outside Bazel.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Everything this tool needs from the outside world, injectable for tests.
pub trait Runner {
    /// Run a command to completion with inherited stdio; returns its exit code.
    fn status(
        &self,
        program: &str,
        args: &[String],
        env: &[(String, String)],
    ) -> Result<i32, String>;
    /// True when the command exits 0 (output discarded).
    fn succeeds(&self, program: &str, args: &[String], env: &[(String, String)]) -> bool;
    /// Run a command and return its trimmed stdout (`None` if it failed to run or exited non-zero).
    fn capture(&self, program: &str, args: &[String]) -> Option<String>;
    /// Value of an environment variable of the calling process.
    fn var(&self, name: &str) -> Option<String>;
    /// Directories prepended to PATH (where `uv tool install platformio` and Homebrew put `pio`).
    fn tool_dirs(&self, user_home: &str) -> String {
        format!("{}/.local/bin:/opt/homebrew/bin:/usr/local/bin", user_home)
    }
}

pub struct RealRunner;

impl Runner for RealRunner {
    fn status(
        &self,
        program: &str,
        args: &[String],
        env: &[(String, String)],
    ) -> Result<i32, String> {
        let mut cmd = Command::new(program);
        cmd.args(args);
        for (k, v) in env {
            cmd.env(k, v);
        }
        let st = cmd
            .status()
            .map_err(|e| format!("failed to run {}: {}", program, e))?;
        Ok(st.code().unwrap_or(1))
    }
    fn succeeds(&self, program: &str, args: &[String], env: &[(String, String)]) -> bool {
        let mut cmd = Command::new(program);
        cmd.args(args)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        for (k, v) in env {
            cmd.env(k, v);
        }
        cmd.status().map(|s| s.success()).unwrap_or(false)
    }
    fn capture(&self, program: &str, args: &[String]) -> Option<String> {
        let out = Command::new(program).args(args).output().ok()?;
        if !out.status.success() {
            return None;
        }
        Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }
    fn var(&self, name: &str) -> Option<String> {
        std::env::var(name).ok()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct BuildConfig {
    pub project_dir: PathBuf,
    pub out_firmware: String,
    pub out_bootloader: String,
    pub out_partitions: String,
}

fn default_project_dir(r: &dyn Runner) -> PathBuf {
    match r.var("BUILD_WORKSPACE_DIRECTORY") {
        Some(ws) if !ws.is_empty() => PathBuf::from(ws).join("apps/embedded/esp32-s3"),
        _ => PathBuf::from("."),
    }
}

/// Same flags as the shell script (`--project_dir`, `--out_firmware`, `--out_bootloader`,
/// `--out_partitions`); the dashed spellings are accepted too.
pub fn parse_args(args: &[String], r: &dyn Runner) -> Result<BuildConfig, String> {
    let mut cfg = BuildConfig {
        project_dir: default_project_dir(r),
        out_firmware: String::new(),
        out_bootloader: String::new(),
        out_partitions: String::new(),
    };
    let mut i = 0;
    while i < args.len() {
        let flag = args[i].as_str();
        let slot: &mut String = match flag {
            "--out_firmware" | "--out-firmware" => &mut cfg.out_firmware,
            "--out_bootloader" | "--out-bootloader" => &mut cfg.out_bootloader,
            "--out_partitions" | "--out-partitions" => &mut cfg.out_partitions,
            "--project_dir" | "--project-dir" => {
                let v = args
                    .get(i + 1)
                    .ok_or_else(|| format!("{} requires an argument", flag))?;
                cfg.project_dir = PathBuf::from(v);
                i += 2;
                continue;
            }
            other => return Err(format!("Unknown argument: {}", other)),
        };
        let v = args
            .get(i + 1)
            .ok_or_else(|| format!("{} requires an argument", flag))?;
        *slot = v.clone();
        i += 2;
    }
    Ok(cfg)
}

/// The passwd-database home directory (`eval echo ~$(id -un)` in the shell script).
pub fn user_home(r: &dyn Runner) -> String {
    let user = r.capture("id", &["-un".to_string()]).unwrap_or_default();
    let home = r
        .capture(
            "sh",
            &["-c".to_string(), format!("eval echo \"~{}\"", user)],
        )
        .unwrap_or_default();
    if home.is_empty() || home.starts_with('~') {
        r.var("HOME").unwrap_or_default()
    } else {
        home
    }
}

/// The environment the PlatformIO build runs under.
pub fn build_env(r: &dyn Runner, user_home: &str) -> Vec<(String, String)> {
    let home = r
        .var("HOME")
        .filter(|h| !h.is_empty())
        .unwrap_or_else(|| user_home.to_string());
    let path = format!(
        "{}:{}",
        r.tool_dirs(user_home),
        r.var("PATH").unwrap_or_default()
    );
    let core = r
        .var("PLATFORMIO_CORE_DIR")
        .filter(|c| !c.is_empty())
        .unwrap_or_else(|| format!("{}/.platformio", user_home));
    vec![
        ("HOME".into(), home),
        ("PATH".into(), path),
        ("PLATFORMIO_CORE_DIR".into(), core),
    ]
}

fn on_path(path: &str, name: &str) -> bool {
    path.split(':')
        .filter(|d| !d.is_empty())
        .any(|d| Path::new(d).join(name).is_file())
}

/// `pio`, else `uvx --from platformio pio`, else `python3 -m platformio` -- the shell's order.
pub fn find_pio(r: &dyn Runner, env: &[(String, String)]) -> Result<Vec<String>, String> {
    let path = env
        .iter()
        .find(|(k, _)| k == "PATH")
        .map(|(_, v)| v.clone())
        .unwrap_or_default();
    let s = |v: &[&str]| v.iter().map(|x| x.to_string()).collect::<Vec<_>>();
    if on_path(&path, "pio") {
        return Ok(s(&["pio"]));
    }
    if on_path(&path, "uvx") {
        return Ok(s(&["uvx", "--from", "platformio", "pio"]));
    }
    if r.succeeds("python3", &s(&["-m", "platformio", "--version"]), env) {
        return Ok(s(&["python3", "-m", "platformio"]));
    }
    Err("PlatformIO not found. Install via: uv tool install platformio".into())
}

fn copy_out(src: &Path, dst: &str) -> Result<(), String> {
    if dst.is_empty() {
        return Ok(());
    }
    let dst = Path::new(dst);
    if let Some(parent) = dst.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {}", parent.display(), e))?;
        }
    }
    fs::copy(src, dst)
        .map_err(|e| format!("copy {} -> {}: {}", src.display(), dst.display(), e))?;
    Ok(())
}

pub fn build_firmware(cfg: &BuildConfig, r: &dyn Runner) -> Result<(), String> {
    let home = user_home(r);
    let env = build_env(r, &home);
    let pio = find_pio(r, &env)?;

    eprintln!("=== Building ESP32-S3 Firmware ===");
    eprintln!("Project directory: {}", cfg.project_dir.display());
    eprintln!(
        "PlatformIO core:   {}",
        env.iter()
            .find(|(k, _)| k == "PLATFORMIO_CORE_DIR")
            .map(|(_, v)| v.as_str())
            .unwrap_or("")
    );

    let mut args: Vec<String> = pio[1..].to_vec();
    args.extend([
        "run".into(),
        "-d".into(),
        cfg.project_dir.to_string_lossy().to_string(),
    ]);
    let code = r.status(&pio[0], &args, &env)?;
    if code != 0 {
        return Err(format!("PlatformIO build failed (exit {})", code));
    }

    let build_dir = cfg.project_dir.join(".pio/build/esp32s3");
    for img in ["firmware", "bootloader", "partitions"] {
        let p = build_dir.join(format!("{}.bin", img));
        if !p.is_file() {
            return Err(format!("Build finished but {} not found!", p.display()));
        }
    }
    copy_out(&build_dir.join("firmware.bin"), &cfg.out_firmware)?;
    copy_out(&build_dir.join("bootloader.bin"), &cfg.out_bootloader)?;
    copy_out(&build_dir.join("partitions.bin"), &cfg.out_partitions)?;

    eprintln!("=== Firmware Build Successful ===");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    /// Records every command; `on_status` can create build output like a real `pio run`.
    struct Fake {
        vars: HashMap<String, String>,
        calls: RefCell<Vec<(String, Vec<String>, Vec<(String, String)>)>>,
        pio_exit: i32,
        python_pio_ok: bool,
        on_status: Box<dyn Fn(&[String])>,
    }

    impl Fake {
        fn new(vars: &[(&str, &str)]) -> Self {
            Fake {
                vars: vars
                    .iter()
                    .map(|(k, v)| (k.to_string(), v.to_string()))
                    .collect(),
                calls: RefCell::new(vec![]),
                pio_exit: 0,
                python_pio_ok: false,
                on_status: Box::new(|_| {}),
            }
        }
    }

    impl Runner for Fake {
        fn status(&self, p: &str, a: &[String], e: &[(String, String)]) -> Result<i32, String> {
            self.calls
                .borrow_mut()
                .push((p.into(), a.to_vec(), e.to_vec()));
            (self.on_status)(a);
            Ok(self.pio_exit)
        }
        fn succeeds(&self, p: &str, a: &[String], e: &[(String, String)]) -> bool {
            self.calls
                .borrow_mut()
                .push((p.into(), a.to_vec(), e.to_vec()));
            self.python_pio_ok
        }
        fn capture(&self, p: &str, a: &[String]) -> Option<String> {
            match p {
                "id" => Some("builder".into()),
                "sh" => {
                    assert!(
                        a[1].contains("~builder"),
                        "passwd home must be derived for the user"
                    );
                    Some("/home/builder".into())
                }
                _ => None,
            }
        }
        fn var(&self, n: &str) -> Option<String> {
            self.vars.get(n).cloned()
        }
        // Hermetic: never pick up a real pio/uvx from the machine running the tests.
        fn tool_dirs(&self, user_home: &str) -> String {
            format!("{}/.local/bin", user_home)
        }
    }

    fn tmpdir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("bf-test-{}-{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn fake_pio_dir(root: &Path) -> String {
        let bin = root.join("bin");
        fs::create_dir_all(&bin).unwrap();
        fs::write(bin.join("pio"), "").unwrap();
        bin.to_string_lossy().to_string()
    }

    fn write_images(project: &Path, which: &[&str]) {
        let d = project.join(".pio/build/esp32s3");
        fs::create_dir_all(&d).unwrap();
        for w in which {
            fs::write(d.join(format!("{}.bin", w)), format!("IMG:{}", w)).unwrap();
        }
    }

    fn sv(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn parses_bazel_genrule_flags() {
        let f = Fake::new(&[]);
        let cfg = parse_args(
            &sv(&[
                "--project_dir",
                "apps/embedded/esp32-s3",
                "--out_firmware",
                "o/firmware.bin",
                "--out_bootloader",
                "o/bootloader.bin",
                "--out_partitions",
                "o/partitions.bin",
            ]),
            &f,
        )
        .unwrap();
        assert_eq!(cfg.project_dir, PathBuf::from("apps/embedded/esp32-s3"));
        assert_eq!(cfg.out_firmware, "o/firmware.bin");
        assert_eq!(cfg.out_bootloader, "o/bootloader.bin");
        assert_eq!(cfg.out_partitions, "o/partitions.bin");
    }

    #[test]
    fn unknown_argument_is_rejected_like_the_shell() {
        let f = Fake::new(&[]);
        let e = parse_args(&sv(&["--bogus"]), &f).unwrap_err();
        assert_eq!(e, "Unknown argument: --bogus");
        // the old Rust port took a positional tar path; that interface is gone
        assert!(parse_args(&sv(&["out.tar.gz"]), &f).is_err());
    }

    #[test]
    fn default_project_dir_is_the_package() {
        let f = Fake::new(&[("BUILD_WORKSPACE_DIRECTORY", "/ws")]);
        assert_eq!(
            parse_args(&[], &f).unwrap().project_dir,
            PathBuf::from("/ws/apps/embedded/esp32-s3")
        );
    }

    #[test]
    fn env_uses_passwd_home_and_prepends_tool_dirs() {
        // Bazel's local action env: PATH and nothing else.
        let f = Fake::new(&[("PATH", "/bin:/usr/bin:/usr/local/bin")]);
        let home = user_home(&f);
        assert_eq!(home, "/home/builder");
        let env: HashMap<_, _> = build_env(&f, &home).into_iter().collect();
        assert_eq!(env["HOME"], "/home/builder");
        assert_eq!(
            env["PATH"],
            "/home/builder/.local/bin:/bin:/usr/bin:/usr/local/bin"
        );
        assert_eq!(
            RealRunner.tool_dirs("/home/builder"),
            "/home/builder/.local/bin:/opt/homebrew/bin:/usr/local/bin"
        );
        assert_eq!(env["PLATFORMIO_CORE_DIR"], "/home/builder/.platformio");
    }

    #[test]
    fn env_respects_existing_home_and_core_dir() {
        let f = Fake::new(&[
            ("HOME", "/h"),
            ("PLATFORMIO_CORE_DIR", "/core"),
            ("PATH", "/x"),
        ]);
        let env: HashMap<_, _> = build_env(&f, "/home/builder").into_iter().collect();
        assert_eq!(env["HOME"], "/h");
        assert_eq!(env["PLATFORMIO_CORE_DIR"], "/core");
    }

    #[test]
    fn pio_lookup_order() {
        let root = tmpdir("order");
        let with_pio = fake_pio_dir(&root);
        let f = Fake::new(&[]);
        let env = |p: &str| vec![("PATH".to_string(), p.to_string())];
        assert_eq!(find_pio(&f, &env(&with_pio)).unwrap(), sv(&["pio"]));

        let uvx_dir = root.join("uvx");
        fs::create_dir_all(&uvx_dir).unwrap();
        fs::write(uvx_dir.join("uvx"), "").unwrap();
        assert_eq!(
            find_pio(&f, &env(uvx_dir.to_str().unwrap())).unwrap(),
            sv(&["uvx", "--from", "platformio", "pio"])
        );

        let mut f2 = Fake::new(&[]);
        f2.python_pio_ok = true;
        assert_eq!(
            find_pio(&f2, &env("/nonexistent")).unwrap(),
            sv(&["python3", "-m", "platformio"])
        );

        let e = find_pio(&f, &env("/nonexistent")).unwrap_err();
        assert!(e.contains("PlatformIO not found"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn builds_with_the_esp32s3_env_and_copies_the_three_images() {
        let root = tmpdir("ok");
        let project = root.join("proj");
        write_images(&project, &["firmware", "bootloader", "partitions"]);
        let f = Fake::new(&[("PATH", &fake_pio_dir(&root))]);
        let cfg = BuildConfig {
            project_dir: project.clone(),
            out_firmware: root
                .join("out/a/firmware.bin")
                .to_string_lossy()
                .to_string(),
            out_bootloader: root
                .join("out/b/bootloader.bin")
                .to_string_lossy()
                .to_string(),
            out_partitions: root
                .join("out/c/partitions.bin")
                .to_string_lossy()
                .to_string(),
        };
        build_firmware(&cfg, &f).unwrap();

        let calls = f.calls.borrow();
        let (prog, args, env) = &calls[0];
        assert_eq!(prog, "pio");
        // `pio run -d <project>` -- no `-e`: the old port passed a nonexistent env.
        assert_eq!(args, &sv(&["run", "-d", project.to_str().unwrap()]));
        assert!(!args.iter().any(|a| a == "-e"));
        assert!(env.iter().any(|(k, _)| k == "PLATFORMIO_CORE_DIR"));

        assert_eq!(
            fs::read_to_string(&cfg.out_firmware).unwrap(),
            "IMG:firmware"
        );
        assert_eq!(
            fs::read_to_string(&cfg.out_bootloader).unwrap(),
            "IMG:bootloader"
        );
        assert_eq!(
            fs::read_to_string(&cfg.out_partitions).unwrap(),
            "IMG:partitions"
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn missing_pio_fails_instead_of_writing_placeholders() {
        let root = tmpdir("nopio");
        let f = Fake::new(&[("PATH", "/nonexistent")]);
        let out = root.join("firmware.bin");
        let cfg = BuildConfig {
            project_dir: root.clone(),
            out_firmware: out.to_string_lossy().to_string(),
            out_bootloader: String::new(),
            out_partitions: String::new(),
        };
        let e = build_firmware(&cfg, &f).unwrap_err();
        assert!(e.contains("PlatformIO not found"), "{}", e);
        assert!(!out.exists(), "no placeholder image may be produced");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn failing_pio_run_fails_the_build() {
        let root = tmpdir("piofail");
        let mut f = Fake::new(&[("PATH", &fake_pio_dir(&root))]);
        f.pio_exit = 2;
        let cfg = BuildConfig {
            project_dir: root.clone(),
            out_firmware: String::new(),
            out_bootloader: String::new(),
            out_partitions: String::new(),
        };
        assert!(build_firmware(&cfg, &f)
            .unwrap_err()
            .contains("PlatformIO build failed"));
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn a_missing_image_after_the_build_is_an_error() {
        let root = tmpdir("missing");
        let project = root.join("proj");
        write_images(&project, &["firmware", "bootloader"]); // no partitions.bin
        let f = Fake::new(&[("PATH", &fake_pio_dir(&root))]);
        let out = root.join("firmware.bin");
        let cfg = BuildConfig {
            project_dir: project,
            out_firmware: out.to_string_lossy().to_string(),
            out_bootloader: String::new(),
            out_partitions: String::new(),
        };
        let e = build_firmware(&cfg, &f).unwrap_err();
        assert!(e.contains("partitions.bin not found"), "{}", e);
        assert!(
            !out.exists(),
            "nothing is copied when the build is incomplete"
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn empty_out_paths_are_skipped() {
        let root = tmpdir("skip");
        let project = root.join("proj");
        write_images(&project, &["firmware", "bootloader", "partitions"]);
        let f = Fake::new(&[("PATH", &fake_pio_dir(&root))]);
        let only = root.join("only.bin");
        let cfg = BuildConfig {
            project_dir: project,
            out_firmware: only.to_string_lossy().to_string(),
            out_bootloader: String::new(),
            out_partitions: String::new(),
        };
        build_firmware(&cfg, &f).unwrap();
        assert!(only.exists());
        let _ = fs::remove_dir_all(&root);
    }
}
