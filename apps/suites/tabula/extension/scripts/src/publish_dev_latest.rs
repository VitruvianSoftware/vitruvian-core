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

pub fn tag_from_env(val: Option<String>) -> String {
    match val {
        Some(v) if !v.is_empty() => v,
        _ => "tabula-extension-dev-latest".to_string(),
    }
}

pub fn build_info_json(sha: &str, built_at: &str, version: &str) -> String {
    format!(
        "{{\"commit\":\"{}\",\"builtAt\":\"{}\",\"version\":\"{}\"}}\n",
        sha, built_at, version
    )
}

pub fn chrome_zip_bazel_bin_path() -> &'static str {
    "bazel-bin/apps/suites/tabula/extension/tabula-extension-chrome.zip"
}

pub fn chrome_zip_bazel_target() -> &'static str {
    "//apps/suites/tabula/extension:chrome_zip"
}

fn resolve_root() -> PathBuf {
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !bwd.is_empty() {
            return PathBuf::from(bwd);
        }
    }
    if let Ok(out) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !s.is_empty() {
                return PathBuf::from(s);
            }
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn resolve_sha() -> String {
    if let Ok(sha) = env::var("GITHUB_SHA") {
        if !sha.is_empty() {
            return sha;
        }
    }
    let out = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .expect("git rev-parse HEAD");
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn utc_now() -> String {
    let out = Command::new("date")
        .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
        .output()
        .expect("date -u");
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

fn resolve_work() -> PathBuf {
    if let Ok(rt) = env::var("RUNNER_TEMP") {
        if !rt.is_empty() {
            return PathBuf::from(rt);
        }
    }
    let out = Command::new("mktemp")
        .arg("-d")
        .output()
        .expect("mktemp -d");
    PathBuf::from(String::from_utf8_lossy(&out.stdout).trim())
}

fn cmd_ok(cmd: &mut Command) -> bool {
    match cmd.status() {
        Ok(s) => s.success(),
        Err(_) => false,
    }
}

fn cmd_stdout(cmd: &mut Command) -> String {
    match cmd.output() {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        Err(_) => String::new(),
    }
}

pub fn run(_args: &[String]) -> i32 {
    let root = resolve_root();
    if env::set_current_dir(&root).is_err() {
        eprintln!("publish-dev-latest: cannot cd to {}", root.display());
        return 1;
    }

    let tag = tag_from_env(env::var("TAG").ok());
    let work = resolve_work();
    let sha = resolve_sha();

    let bb_key = env::var("BUILDBUDDY_API_KEY").unwrap_or_default();
    let target = chrome_zip_bazel_target();

    let bazel_ok = if !bb_key.is_empty() {
        cmd_ok(Command::new("bazel").args([
            "build",
            "--config=remotecache-ci",
            &format!("--remote_header=x-buildbuddy-api-key={}", bb_key),
            target,
        ]))
    } else {
        eprintln!("publish-dev-latest: no BUILDBUDDY_API_KEY — building locally");
        cmd_ok(Command::new("bazel").args(["build", target]))
    };
    if !bazel_ok {
        eprintln!("publish-dev-latest: bazel build failed");
        return 1;
    }

    let src_zip = Path::new(chrome_zip_bazel_bin_path());
    let dst_zip = work.join("tabula-extension-chrome.zip");
    if fs::copy(src_zip, &dst_zip).is_err() {
        eprintln!(
            "publish-dev-latest: cannot copy {} to {}",
            src_zip.display(),
            dst_zip.display()
        );
        return 1;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&dst_zip, fs::Permissions::from_mode(0o644));
    }

    let version = cmd_stdout(Command::new("node").args([
        "-p",
        "require('./apps/suites/tabula/extension/package.json').version",
    ]));
    if version.is_empty() {
        eprintln!("publish-dev-latest: cannot read version from package.json");
        return 1;
    }

    let built_at = utc_now();

    if env::set_current_dir(&work).is_err() {
        eprintln!("publish-dev-latest: cannot cd to {}", work.display());
        return 1;
    }

    let info = build_info_json(&sha, &built_at, &version);
    if fs::write("build-info.json", &info).is_err() {
        eprintln!("publish-dev-latest: cannot write build-info.json");
        return 1;
    }

    if !cmd_ok(Command::new("zip").args(["-q", "tabula-extension-chrome.zip", "build-info.json"])) {
        eprintln!("publish-dev-latest: zip update failed");
        return 1;
    }

    if env::set_current_dir(&root).is_err() {
        eprintln!("publish-dev-latest: cannot cd back to {}", root.display());
        return 1;
    }

    if !cmd_ok(Command::new("gh").args(["release", "view", &tag])) {
        if !cmd_ok(Command::new("gh").args([
            "release",
            "create",
            &tag,
            "--prerelease",
            "--title",
            "tabula-extension dev-latest (rolling)",
            "--notes",
            "Rolling dev bundle; assets overwritten on every main commit.",
        ])) {
            eprintln!("publish-dev-latest: gh release create failed");
            return 1;
        }
    }

    let zip_path = dst_zip.to_string_lossy().to_string();
    let info_path = work.join("build-info.json").to_string_lossy().to_string();

    if !cmd_ok(Command::new("gh").args([
        "release",
        "upload",
        &tag,
        &zip_path,
        &info_path,
        "--clobber",
    ])) {
        eprintln!("publish-dev-latest: gh release upload failed");
        return 1;
    }

    let notes = format!("commit: {} — built {}", sha, built_at);
    if !cmd_ok(Command::new("gh").args(["release", "edit", &tag, "--notes", &notes])) {
        eprintln!("publish-dev-latest: gh release edit failed");
        return 1;
    }

    0
}
