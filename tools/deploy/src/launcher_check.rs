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

//! launcher-check: the `<name>_launcher_test` every cloud_run_deploy() emits.
//!
//! Runs the app's real `:deploy` target the way `bazel run` does (from the
//! runfiles tree, with the flags the macro baked in) and checks it reaches the
//! Rust sequencer and drives pulumi-cmd. Nothing real is touched: pulumi-cmd
//! is a stub that only logs, put at the very runfiles path the target is
//! configured with (VITRUVIAN_PULUMI_CMD_BIN, which the test gets from the
//! same `env` as the :deploy target), and PATH holds nothing but a `gcloud` stub (plus `bash` and `cat`), so no
//! real pulumi, gcloud or curl can run. `--phase candidate` with a fixed
//! `--stable-revision` never needs gcloud at all.
//!
//! argv: <rootpath of :deploy> <the macro's baked args...>

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

fn write_exec(path: &Path, body: &str) {
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let (deploy, baked) = argv
        .split_first()
        .expect("usage: launcher-check <:deploy rootpath> <baked args...>");
    let flag = |f: &str| -> String {
        let i = baked
            .iter()
            .position(|a| a == f)
            .unwrap_or_else(|| panic!("{f} is not among the baked args {baked:?}"));
        baked[i + 1].clone()
    };
    let service = flag("--service");
    let pulumi_dir = flag("--pulumi-dir");

    // Under `bazel test` (and `bazel run`) the working directory is the
    // runfiles tree, which mirrors the workspace for every data file, so it
    // stands in for BUILD_WORKSPACE_DIRECTORY (--custom-smoke-script-file).
    let cwd = std::env::current_dir().unwrap();
    let deploy = cwd.join(deploy);
    let tmp = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("launcher-check-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    let bin = tmp.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    let log_line = "#!/bin/sh\nprintf '%s\\n' \"$*\" >>\"$0.log\"\n";
    // The pulumi-cmd path the target is configured with: it must name a real
    // file in the runfiles tree (a mis-wired label or path fails here), and
    // the run below gets that same relative path, resolved against a copy of
    // the tree where it is a stub. Nothing points the sequencer at the stub
    // but that configured path.
    let configured = std::env::var("VITRUVIAN_PULUMI_CMD_BIN").expect(
        "VITRUVIAN_PULUMI_CMD_BIN is not set: the macro must give the test the target's env",
    );
    assert!(
        Path::new(&configured).is_relative() && cwd.join(&configured).is_file(),
        "the :deploy target's VITRUVIAN_PULUMI_CMD_BIN={configured:?} is not a file in its runfiles"
    );
    assert_eq!(
        Path::new(&configured).file_name().and_then(|n| n.to_str()),
        Some("pulumi-cmd"),
        "the :deploy target's VITRUVIAN_PULUMI_CMD_BIN={configured:?} is not //tools/pulumi:pulumi-cmd"
    );
    let fake_root = tmp.join("runfiles").join("_main");
    let pulumi_cmd = fake_root.join(&configured);
    std::fs::create_dir_all(pulumi_cmd.parent().unwrap()).unwrap();
    write_exec(&pulumi_cmd, &format!("{log_line}exit 0\n"));
    // bash (for a launcher that is a shell script) and cat (the sequencer
    // reads --custom-smoke-script-file with it): neither reaches anything
    // real, since nothing else is on PATH.
    for tool in ["bash", "cat"] {
        if let Some(p) = ["/bin", "/usr/bin"]
            .iter()
            .map(|d| Path::new(d).join(tool))
            .find(|p| p.is_file())
        {
            std::os::unix::fs::symlink(p, bin.join(tool)).unwrap();
        }
    }
    let gcloud = bin.join("gcloud");
    write_exec(&gcloud, &format!("{log_line}exit 1\n"));

    let mut c = Command::new(&deploy);
    // RUNFILES_DIR is left unset: the sequencer's fallback to it would find
    // the real pulumi-cmd.
    c.env_clear()
        .current_dir(&fake_root)
        .env("PATH", &bin)
        .env("HOME", &tmp)
        .env("BUILD_WORKSPACE_DIRECTORY", &cwd)
        .env("VITRUVIAN_PULUMI_CMD_BIN", &configured)
        .args(baked)
        .args([
            "--env",
            "development",
            "--project",
            "prj-launcher-check",
            "--image-digest",
            "example.invalid/app@sha256:0000000000000000000000000000000000000000000000000000000000000000",
            "--phase",
            "candidate",
            "--stable-revision",
            "rev-stable",
        ])
        .stdin(Stdio::null());
    let o = c
        .output()
        .unwrap_or_else(|e| panic!("could not start {}: {e}", deploy.display()));
    let rc = o.status.code().unwrap_or(-1);
    let stderr = String::from_utf8_lossy(&o.stderr);
    let calls =
        std::fs::read_to_string(format!("{}.log", pulumi_cmd.display())).unwrap_or_default();
    let gcloud_calls =
        std::fs::read_to_string(format!("{}.log", gcloud.display())).unwrap_or_default();

    let mut failures = Vec::new();
    if rc != 0 {
        failures.push(format!("the :deploy launcher exited {rc}, want 0"));
    }
    let done = format!("cloud-run: phase 'candidate' complete for {service}-development.");
    if !stderr.contains(&done) {
        failures.push(format!("stderr lacks {done:?}"));
    }
    let select = format!("{pulumi_dir} stack select development");
    let up = format!("{pulumi_dir} up --stack development --yes");
    let lines: Vec<&str> = calls.lines().collect();
    if lines.first() != Some(&select.as_str()) {
        failures.push(format!("first pulumi-cmd call is not {select:?}"));
    }
    if !lines.iter().any(|l| l.starts_with(&up)) {
        failures.push(format!("no pulumi-cmd call starting {up:?}"));
    }
    if !gcloud_calls.is_empty() {
        failures.push("gcloud was called; this check must never reach it".to_string());
    }
    if failures.is_empty() {
        println!(
            "ok: {} reached the sequencer and drove pulumi-cmd",
            deploy.display()
        );
        return;
    }
    eprintln!("launcher-check FAILED for {}:", deploy.display());
    for f in &failures {
        eprintln!("  - {f}");
    }
    eprintln!("--- stderr ---\n{stderr}--- pulumi-cmd calls ---\n{calls}");
    std::process::exit(1);
}
