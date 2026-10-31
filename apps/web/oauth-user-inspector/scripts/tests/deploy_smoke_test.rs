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

//! The custom smoke exactly as a deploy runs it: the real
//! //tools/deploy:cloud-run `--phase smoke`, given OAUTH_SMOKE -- the one
//! command (infra/app/smoke.bzl) that :deploy runs and the delivery unit passes
//! the generated workflow as `custom-smoke-script`.
//!
//! What matters is where the command runs. Under `bazel run` the deploy tool
//! starts in its runfiles tree, outside any workspace, and runs the command
//! from there with `bash -c`; only BUILD_WORKSPACE_DIRECTORY leads back to the
//! checkout. The stub `bazel` below behaves like the real one on that point --
//! outside a workspace it exits 2 with Bazel's error (from the runfiles tree the
//! real one says "should not be called from a bazel output directory"; from any
//! other non-workspace directory, "must be invoked from within a workspace") --
//! and inside one it runs the real :smoke binary. gcloud and pulumi-cmd are stubs that
//! hand the tool a candidate URL; curl and Chrome are stubs the smoke drives.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

fn runfile(var: &str) -> PathBuf {
    let p = std::env::var(var).unwrap_or_else(|_| panic!("{var} unset"));
    fs::canonicalize(&p).unwrap_or_else(|e| panic!("{var}={p}: {e}"))
}

fn stub(p: &Path, body: &str) {
    fs::write(p, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

/// OAUTH_SMOKE from infra/app/smoke.bzl: what :deploy runs and what the
/// delivery unit passes the workflow as `custom-smoke-script`.
fn smoke_command() -> String {
    std::env::var("OAUTH_SMOKE").expect("OAUTH_SMOKE unset")
}

struct Run {
    rc: i32,
    stdout: String,
    stderr: String,
    bazel_cwd: String,
}

fn deploy_smoke(name: &str, dom: &str) -> Run {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let d = base.join(format!("deploy-smoke-{name}"));
    let _ = fs::remove_dir_all(&d);
    let (ws, stubs, elsewhere) = (d.join("checkout"), d.join("stubs"), d.join("runfiles"));
    for dir in [
        &ws.join("apps/web/oauth-user-inspector/infra/app"),
        &stubs,
        &elsewhere,
    ] {
        fs::create_dir_all(dir).unwrap();
    }
    fs::write(ws.join("MODULE.bazel"), "").unwrap();

    let smoke_bin = runfile("SMOKE_BIN");
    stub(
        &stubs.join("bazel"),
        &format!(
            r#"pwd >"{log}"
d="$PWD"; while [ "$d" != / ]; do [ -f "$d/MODULE.bazel" ] && break; d=$(dirname "$d"); done
if [ "$d" = / ]; then
  echo "ERROR: Bazel 'run' must be invoked from within a workspace (below a directory having a MODULE.bazel file)." >&2
  exit 2
fi
[ "$*" = "run //apps/web/oauth-user-inspector:smoke" ] || {{ echo "unexpected: bazel $*" >&2; exit 99; }}
exec "{smoke}""#,
            log = d.join("bazel.cwd").display(),
            smoke = smoke_bin.display()
        ),
    );
    stub(
        &stubs.join("gcloud"),
        r#"echo '{"status":{"traffic":[{"tag":"candidate","url":"https://cand.example"},{"revisionName":"oauth-user-inspector-00001-abc","percent":100}]}}'"#,
    );
    stub(&stubs.join("pulumi-cmd"), "echo https://svc.example");
    stub(&stubs.join("curl"), "exit 0");
    stub(
        &stubs.join("google-chrome-stable"),
        &format!("printf '%s' '{dom}'"),
    );

    let o = Command::new(runfile("CLOUD_RUN_BIN"))
        .current_dir(&elsewhere)
        .env_clear()
        .env("PATH", format!("{}:/usr/bin:/bin", stubs.display()))
        .env("HOME", "/nonexistent")
        .env("BUILD_WORKSPACE_DIRECTORY", &ws)
        .env("VITRUVIAN_PULUMI_CMD_BIN", stubs.join("pulumi-cmd"))
        .args([
            "--phase",
            "smoke",
            "--pulumi-dir",
            "apps/web/oauth-user-inspector/infra/app",
            "--service",
            "oauth-user-inspector",
            "--env",
            "development",
            "--env-prefix",
            "OAUTH_USER_INSPECTOR",
            "--project",
            "p",
            "--region",
            "us-central1",
            "--smoke-path",
            "/",
            "--image-digest",
            "us-docker.pkg.dev/p/r/oauth@sha256:0000",
            "--custom-smoke-script",
            &smoke_command(),
        ])
        .output()
        .unwrap();
    Run {
        rc: o.status.code().unwrap_or(-1),
        stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        bazel_cwd: fs::read_to_string(d.join("bazel.cwd")).unwrap_or_default(),
    }
}

#[test]
fn the_deploy_tool_runs_the_smoke_from_the_checkout() {
    let r = deploy_smoke("ok", "<div>Select a provider</div>");
    assert_eq!(r.rc, 0, "stdout:\n{}\nstderr:\n{}", r.stdout, r.stderr);
    assert!(
        r.stderr
            .contains("cloud-run: running custom smoke against https://cand.example"),
        "{}",
        r.stderr
    );
    assert!(
        r.stdout
            .contains("Smoke-checking https://cand.example/\nSmoke OK: React app mounted.\n"),
        "{}",
        r.stdout
    );
    assert!(
        r.bazel_cwd.trim_end().ends_with("/checkout"),
        "bazel ran in {}",
        r.bazel_cwd
    );
}

#[test]
fn a_broken_frontend_fails_the_deploy_smoke() {
    let r = deploy_smoke("broken", "<div id=root></div>");
    assert_eq!(r.rc, 1, "stdout:\n{}\nstderr:\n{}", r.stdout, r.stderr);
    assert!(
        r.stdout.contains("::error::App did NOT mount"),
        "{}",
        r.stdout
    );
}
