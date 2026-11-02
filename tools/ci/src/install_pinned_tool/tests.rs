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

//! //tools/ci:install_pinned_tool_test. Runs the REAL binary with a fake
//! `curl` first on PATH (it copies fixtures, no network) and the real `tar`,
//! `install`, `grep` and `sha256sum`, so both install paths and the checksum
//! verification itself run for real. Ported case for case from the former
//! install-pinned-tool_test.sh, plus the cases that held the binary to the
//! script it replaced: exit codes, a nested tar member, an empty member path,
//! a checksum line that is not there, and an unwritable PATH file or HOME.

use ci_testkit::{bin, read, write, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};
use std::process::Command;

const URL: &str = "https://example.invalid/download";
const RAW: &str = "mytool_linux_amd64";

/// The fake curl: `curl ... -O <url>` copies `$FIXTURES_DIR/<basename>` into
/// the working directory, as real curl's -O names the file.
const FAKE_CURL: &str = r#"#!/usr/bin/env bash
if [ -n "${FAKE_CURL_ARGS_LOG:-}" ]; then printf '%s\n' "$*" >> "${FAKE_CURL_ARGS_LOG}"; fi
if [ -n "${FAKE_CURL_RC:-}" ] && [ "${FAKE_CURL_RC}" != "0" ]; then
  echo "curl: fake transport failure" >&2
  exit "${FAKE_CURL_RC}"
fi
url="${@: -1}"
base="${url##*/}"
if [ ! -f "${FIXTURES_DIR}/${base}" ]; then
  echo "curl: no fixture for '${base}'" >&2
  exit 22
fi
cp "${FIXTURES_DIR}/${base}" "./${base}"
"#;

struct World {
    dir: TempDir,
}

impl World {
    fn new() -> World {
        let dir = TempDir::new();
        write_exe(dir.join("bin/curl"), FAKE_CURL);
        let fx = dir.join("fixtures");
        // --raw: the asset IS the binary.
        write(fx.join(RAW), "fake-binary-bytes-for-mytool\n");
        sha256_into(&fx, RAW, &format!("{RAW}_SHA256SUMS"));
        write(
            fx.join(format!("{RAW}_BAD_SHA256SUMS")),
            format!("{}  {RAW}\n", "0".repeat(64)),
        );
        // --tar: a top-level member named after the tool.
        let stage = dir.join("stage");
        write_exe(stage.join("mytool"), "#!/bin/sh\necho fake-tar-tool\n");
        tar_into(&stage, &["mytool"], &fx.join("mytool_linux_amd64.tar.gz"));
        sha256_into(&fx, "mytool_linux_amd64.tar.gz", "mytool_checksums.txt");
        // --tar with the binary in a directory, as prometheus ships promtool.
        let nested = dir.join("nested");
        write_exe(
            nested.join("prometheus-2.45.0.linux-amd64/promtool"),
            "#!/bin/sh\necho fake-promtool\n",
        );
        write(
            nested.join("prometheus-2.45.0.linux-amd64/prometheus"),
            "server\n",
        );
        tar_into(
            &nested,
            &["prometheus-2.45.0.linux-amd64"],
            &fx.join("prometheus-2.45.0.linux-amd64.tar.gz"),
        );
        sha256_into(
            &fx,
            "prometheus-2.45.0.linux-amd64.tar.gz",
            "sha256sums.txt",
        );
        World { dir }
    }

    fn fixtures(&self) -> PathBuf {
        self.dir.join("fixtures")
    }
}

/// `$PATH` for the binary: the fake curl first, then the system tools
/// (/sbin carries sha256sum on macOS).
fn path_for(fakes: &Path) -> String {
    format!(
        "{}:{}:/sbin:/usr/sbin",
        fakes.display(),
        std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
    )
}

fn sha256_into(dir: &Path, file: &str, out: &str) {
    let o = Command::new("sha256sum")
        .arg(file)
        .current_dir(dir)
        .env("PATH", path_for(Path::new("/nonexistent")))
        .output()
        .expect("sha256sum");
    assert!(o.status.success());
    write(dir.join(out), o.stdout);
}

fn tar_into(dir: &Path, members: &[&str], out: &Path) {
    let st = Command::new("tar")
        .arg("-czf")
        .arg(out)
        .args(members)
        .current_dir(dir)
        .status()
        .expect("tar");
    assert!(st.success());
}

/// One run in a fresh scratch dir: HOME and GITHUB_PATH inside it.
struct Ran {
    out: Output,
    scratch: TempDir,
}

impl Ran {
    fn home_bin(&self, name: &str) -> PathBuf {
        self.scratch.join("home/.local/bin").join(name)
    }
    fn github_path(&self) -> String {
        read(self.scratch.join("github_path"))
    }
}

fn run_with(w: &World, args: &[&str], tweak: impl FnOnce(Run, &Path) -> Run) -> Ran {
    let scratch = TempDir::new();
    std::fs::create_dir_all(scratch.join("home")).unwrap();
    write(scratch.join("github_path"), "");
    let r = Run::new(&bin("BIN"))
        .cwd(scratch.path())
        .env("PATH", path_for(&w.dir.join("bin")))
        .env("HOME", scratch.join("home"))
        .env("GITHUB_PATH", scratch.join("github_path"))
        .env("FIXTURES_DIR", w.fixtures())
        .args(args);
    let r = tweak(r, scratch.path());
    let out = r
        .go_within(std::time::Duration::from_secs(60))
        .expect("install-pinned-tool hung");
    Ran { out, scratch }
}

fn run(w: &World, args: &[&str]) -> Ran {
    run_with(w, args, |r, _| r)
}

fn raw_args() -> Vec<String> {
    vec![
        URL.into(),
        RAW.into(),
        format!("{RAW}_SHA256SUMS"),
        RAW.into(),
        "mytool".into(),
        "--raw".into(),
    ]
}

fn strs(v: &[String]) -> Vec<&str> {
    v.iter().map(|s| s.as_str()).collect()
}

fn is_exec(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

// --- the shell suite, case for case ------------------------------------------

#[test]
fn raw_happy_path() {
    let w = World::new();
    let r = run(&w, &strs(&raw_args()));
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(
        is_exec(&r.home_bin("mytool")),
        "--raw: binary installed and executable"
    );
    assert_eq!(read(r.home_bin("mytool")), "fake-binary-bytes-for-mytool\n");
    let want = format!("{}\n", r.scratch.join("home/.local/bin").display());
    assert_eq!(
        r.github_path(),
        want,
        "GITHUB_PATH gains ~/.local/bin, once"
    );
    assert_eq!(
        r.out.stdout,
        format!("{RAW}: OK\ninstall-pinned-tool: installed mytool from {URL}/{RAW}\n"),
        "sha256sum -c's verdict, then the install line"
    );
}

#[test]
fn tar_happy_path() {
    let w = World::new();
    let r = run(
        &w,
        &[
            URL,
            "mytool_linux_amd64.tar.gz",
            "mytool_checksums.txt",
            "mytool_linux_amd64.tar.gz",
            "mytool",
            "--tar",
        ],
    );
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(is_exec(&r.home_bin("mytool")));
    assert!(read(r.home_bin("mytool")).contains("fake-tar-tool"));
}

#[test]
fn checksum_mismatch_fails_closed_and_installs_nothing() {
    let w = World::new();
    let mut a = raw_args();
    a[2] = format!("{RAW}_BAD_SHA256SUMS");
    let r = run(&w, &strs(&a));
    assert_ne!(r.out.code, 0, "a checksum mismatch must fail");
    assert!(!r.home_bin("mytool").exists(), "nothing installed");
    assert_eq!(r.github_path(), "", "nothing put on PATH");
}

#[test]
fn transport_failure_propagates_curls_status() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args()), |r, _| r.env("FAKE_CURL_RC", "22"));
    assert_eq!(r.out.code, 22, "set -e exits with curl's own status");
    assert!(!r.home_bin("mytool").exists());
}

#[test]
fn retry_policy_is_backoff_under_a_cap() {
    // A fixed --retry-delay turns off curl's exponential backoff; it gave up
    // after ~6s of GitHub-releases 500s on 2026-09-25 and failed the queue.
    let w = World::new();
    let log = w.dir.join("curl-args.log");
    let r = run_with(&w, &strs(&raw_args()), |r, _| {
        r.env("FAKE_CURL_ARGS_LOG", &log)
    });
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    let calls = read(&log);
    let lines: Vec<&str> = calls.lines().collect();
    assert_eq!(
        lines,
        vec![
            format!("-fsSL --retry 6 --retry-all-errors --retry-max-time 180 --max-time 120 -O {URL}/{RAW}"),
            format!("-fsSL --retry 6 --retry-all-errors --retry-max-time 180 --max-time 120 -O {URL}/{RAW}_SHA256SUMS"),
        ],
        "asset then checksums, each with the full retry policy and no --retry-delay"
    );
}

#[test]
fn wrong_arg_count_exits_2() {
    let w = World::new();
    assert_eq!(run(&w, &["only", "one", "arg"]).out.code, 2);
    let mut eight = raw_args();
    eight.push("member".into());
    eight.push("extra".into());
    let r = run(&w, &strs(&eight));
    assert_eq!(r.out.code, 2);
    assert!(
        r.out.stderr.starts_with("usage: install-pinned-tool"),
        "{}",
        r.out.stderr
    );
}

#[test]
fn bad_mode_exits_2() {
    let w = World::new();
    let r = run(
        &w,
        &[URL, "asset", "checksums", "pattern", "name", "--bogus-mode"],
    );
    assert_eq!(r.out.code, 2);
    assert!(r
        .out
        .stderr
        .contains("mode must be --tar or --raw, got '--bogus-mode'"));
}

#[test]
fn missing_github_path_fails_like_bash() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args()), |r, _| r.env_remove("GITHUB_PATH"));
    assert_eq!(r.out.code, 1, "the script's ${{GITHUB_PATH:?}} exited 1");
    assert!(
        r.out.stderr.contains("GITHUB_PATH must be set"),
        "{}",
        r.out.stderr
    );
    assert!(
        !r.home_bin("mytool").exists(),
        "fails before downloading anything"
    );
}

// --- parity with the retired script ------------------------------------------

#[test]
fn empty_github_path_fails_like_unset() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args()), |r, _| r.env("GITHUB_PATH", ""));
    assert_eq!(r.out.code, 1);
    assert!(r.out.stderr.contains("GITHUB_PATH must be set"));
}

#[test]
fn nested_member_lands_as_bin_name() {
    let w = World::new();
    let r = run(
        &w,
        &[
            URL,
            "prometheus-2.45.0.linux-amd64.tar.gz",
            "sha256sums.txt",
            "prometheus-2.45.0.linux-amd64.tar.gz",
            "promtool",
            "--tar",
            "prometheus-2.45.0.linux-amd64/promtool",
        ],
    );
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(read(r.home_bin("promtool")).contains("fake-promtool"));
    assert!(
        !r.home_bin("prometheus").exists(),
        "only the named member is extracted"
    );
}

#[test]
fn empty_member_path_means_bin_name() {
    let w = World::new();
    let r = run(
        &w,
        &[
            URL,
            "mytool_linux_amd64.tar.gz",
            "mytool_checksums.txt",
            "mytool_linux_amd64.tar.gz",
            "mytool",
            "--tar",
            "",
        ],
    );
    assert_eq!(r.out.code, 0, "${{7:-$BIN_NAME}}: {}", r.out.all());
    assert!(read(r.home_bin("mytool")).contains("fake-tar-tool"));
}

#[test]
fn checksum_pattern_matching_no_line_fails_closed() {
    let w = World::new();
    let mut a = raw_args();
    a[3] = "no-such-asset-name".into();
    let r = run(&w, &strs(&a));
    assert_ne!(r.out.code, 0, "no checksum line is not a pass");
    assert!(!r.home_bin("mytool").exists());
    assert_eq!(r.github_path(), "");
}

#[test]
fn checksum_pattern_selects_only_its_line() {
    // The listing names two assets; only the selected line is verified, so a
    // bad line for another asset does not fail this one.
    let w = World::new();
    let fx = w.fixtures();
    let good = read(fx.join(format!("{RAW}_SHA256SUMS")));
    write(
        fx.join("multi_SHA256SUMS"),
        format!("{}  other_asset\n{good}", "f".repeat(64)),
    );
    let mut a = raw_args();
    a[2] = "multi_SHA256SUMS".into();
    a[3] = format!(" {RAW}$");
    let r = run(&w, &strs(&a));
    assert_eq!(r.out.code, 0, "{}", r.out.all());
    assert!(is_exec(&r.home_bin("mytool")));
}

#[test]
fn unwritable_github_path_fails() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args()), |r, scratch| {
        let d = scratch.join("github_path_dir");
        std::fs::create_dir_all(&d).unwrap();
        r.env("GITHUB_PATH", d)
    });
    assert_ne!(
        r.out.code,
        0,
        "a tool later steps cannot find on PATH is not installed: {}",
        r.out.all()
    );
}

#[test]
fn uncreatable_install_dir_fails() {
    let w = World::new();
    let r = run_with(&w, &strs(&raw_args()), |r, scratch| {
        let home = scratch.join("home-is-a-file");
        write(&home, "not a directory\n");
        r.env("HOME", home)
    });
    assert_ne!(r.out.code, 0, "{}", r.out.all());
    assert_eq!(r.github_path(), "");
}

#[test]
fn downloads_stay_out_of_the_working_directory() {
    let w = World::new();
    let r = run(&w, &strs(&raw_args()));
    assert_eq!(r.out.code, 0);
    assert!(
        !r.scratch.join(RAW).exists(),
        "the asset is fetched into a private temp dir"
    );
    assert!(!r.scratch.join(format!("{RAW}_SHA256SUMS")).exists());
}
