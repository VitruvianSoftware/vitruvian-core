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

//! The Go tool's main_test.go, ported, plus the exact output of each path.

use super::*;
use std::path::PathBuf;
use std::sync::Mutex;

/// Tests that read or set the environment take this lock.
static ENV: Mutex<()> = Mutex::new(());

struct FakeRunner {
    codes: Vec<i32>,
    calls: usize,
    captured: Vec<Vec<Vec<u8>>>,
    images: Vec<Vec<u8>>,
}

impl FakeRunner {
    fn new(codes: &[i32]) -> FakeRunner {
        FakeRunner {
            codes: codes.to_vec(),
            calls: 0,
            captured: vec![],
            images: vec![],
        }
    }
    fn args(&self, i: usize) -> Vec<String> {
        self.captured[i]
            .iter()
            .map(|a| String::from_utf8_lossy(a).into_owned())
            .collect()
    }
}

impl Runner for FakeRunner {
    fn run(&mut self, image: &[u8], docker_args: &[Vec<u8>]) -> Result<i32, Vec<u8>> {
        self.calls += 1;
        self.captured.push(docker_args.to_vec());
        self.images.push(image.to_vec());
        let idx = (self.calls - 1).min(self.codes.len() - 1);
        Ok(self.codes[idx])
    }
}

struct ErrRunner;

impl Runner for ErrRunner {
    fn run(&mut self, _: &[u8], _: &[Vec<u8>]) -> Result<i32, Vec<u8>> {
        Err(b"exec: \"docker\": executable file not found in $PATH".to_vec())
    }
}

fn v(args: &[&str]) -> Vec<Vec<u8>> {
    args.iter().map(|a| a.as_bytes().to_vec()).collect()
}

fn go(args: &[&str], r: &mut dyn Runner, sleeps: &mut Vec<i32>) -> (i32, String, String) {
    let (mut o, mut e) = (Vec::new(), Vec::new());
    let mut sleeper = |s: i32| sleeps.push(s);
    let code = run(&v(args), r, &mut sleeper, &mut o, &mut e);
    (
        code,
        String::from_utf8(o).unwrap(),
        String::from_utf8(e).unwrap(),
    )
}

fn go1(args: &[&str], r: &mut dyn Runner) -> (i32, String, String) {
    go(args, r, &mut vec![])
}

struct Workspace(PathBuf);

impl Drop for Workspace {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// A temp workspace holding tools/copybara/copy.bara.sky with the
/// placeholder, selected through GITHUB_WORKSPACE.
fn setup_workspace() -> Workspace {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static N: AtomicUsize = AtomicUsize::new(0);
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let dir = base.join(format!(
        "ws-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    std::fs::create_dir_all(dir.join("tools/copybara")).unwrap();
    std::fs::write(
        dir.join("tools/copybara/copy.bara.sky"),
        "x = \"import-pr-@@PR_NUMBER@@\"\n",
    )
    .unwrap();
    std::env::set_var("BUILD_WORKSPACE_DIRECTORY", "");
    std::env::set_var("GITHUB_WORKSPACE", &dir);
    Workspace(dir)
}

#[test]
fn workflow_names() {
    assert_eq!(workflow_name(b"import", b"mcp-slack"), b"import_mcp_slack");
    assert_eq!(workflow_name(b"export", b"devx"), b"export_devx");
    assert_eq!(
        workflow_name(b"import", b"nexus-agent"),
        b"import_nexus_agent"
    );
    assert_eq!(
        workflow_name(b"import_pr", b"nexus-agent"),
        b"import_pr_nexus_agent"
    );
}

#[test]
fn exit_0_and_4_are_success() {
    let _g = ENV.lock().unwrap();
    let mut fr = FakeRunner::new(&[0]);
    let (code, out, _) = go1(&["export", "devx"], &mut fr);
    assert_eq!((code, fr.calls), (0, 1));
    assert_eq!(out, "Copybara OK (exit 0; 4 = no-op/up-to-date)\n");
    let mut fr = FakeRunner::new(&[4]);
    assert_eq!(go1(&["export", "devx"], &mut fr).0, 0);
    assert_eq!(fr.images[0], PINNED_IMAGE);
}

#[test]
fn export_failure_does_not_retry() {
    let _g = ENV.lock().unwrap();
    let mut fr = FakeRunner::new(&[1]);
    let (code, _, err) = go1(&["export", "devx"], &mut fr);
    assert_eq!((code, fr.calls), (1, 1));
    assert_eq!(err, "Copybara failed (exit 1)\n");
}

#[test]
fn import_retries_three_times_with_backoff() {
    let _g = ENV.lock().unwrap();
    let mut fr = FakeRunner::new(&[1, 1, 1]);
    let mut sleeps = vec![];
    let (code, out, err) = go(&["import", "devx"], &mut fr, &mut sleeps);
    assert_eq!((code, fr.calls), (1, 3));
    assert_eq!(sleeps, vec![10, 15]);
    assert_eq!(err, "Copybara failed (exit 1 after 3 attempts)\n");
    assert_eq!(
        out,
        "Copybara exit 1 (attempt 1/3) — retrying after re-fetch (likely a concurrent import race)\n\
         Copybara exit 1 (attempt 2/3) — retrying after re-fetch (likely a concurrent import race)\n"
    );
}

#[test]
fn import_succeeds_on_retry() {
    let _g = ENV.lock().unwrap();
    let mut fr = FakeRunner::new(&[1, 0]);
    assert_eq!(go1(&["import", "devx"], &mut fr).0, 0);
    assert_eq!(fr.calls, 2);
    let mut fr = FakeRunner::new(&[1, 4]);
    assert_eq!(go1(&["import", "devx"], &mut fr).0, 0);
}

#[test]
fn unknown_direction_is_exit_2_without_docker() {
    let mut fr = FakeRunner::new(&[0]);
    let (code, _, err) = go1(&["sideways", "devx"], &mut fr);
    assert_eq!((code, fr.calls), (2, 0));
    assert_eq!(err, "unknown direction: sideways (use export|import)\n");
}

#[test]
fn too_few_args() {
    let mut fr = FakeRunner::new(&[0]);
    let (code, _, err) = go1(&["export"], &mut fr);
    assert_eq!(code, 2);
    assert!(err.starts_with("usage: sync <export|import>"));
}

#[test]
fn docker_args_and_options() {
    let _g = ENV.lock().unwrap();
    std::env::set_var("BUILD_WORKSPACE_DIRECTORY", "/ws");
    std::env::set_var("HOME", "/home/u");
    let mut fr = FakeRunner::new(&[0]);
    go1(&["export", "devx"], &mut fr);
    assert_eq!(
        fr.args(0),
        [
            "--rm",
            "-v",
            "/ws:/usr/src/app",
            "-v",
            "/home/u/.ssh/id_rsa:/root/.ssh/id_rsa",
            "-v",
            "/home/u/.ssh/known_hosts:/root/.ssh/known_hosts",
            "-v",
            "/ws/tools/copybara/copy.bara.sky:/root/copy.bara.sky",
            "-v",
            "/home/u/.git-credentials:/root/.git-credentials",
            "-v",
            "/home/u/.gitconfig:/root/.gitconfig",
            "-e",
            "COPYBARA_CONFIG=/root/copy.bara.sky",
            "-e",
            "COPYBARA_WORKFLOW=export_devx",
            "-e",
            "COPYBARA_OPTIONS=--ignore-noop",
        ]
    );
    let mut fr = FakeRunner::new(&[0]);
    go1(
        &["export", "devx", "--options", "--force --ignore-noop"],
        &mut fr,
    );
    assert!(fr
        .args(0)
        .contains(&"COPYBARA_OPTIONS=--force --ignore-noop".to_string()));
    // A trailing --options without a value is ignored; the last one wins.
    let mut fr = FakeRunner::new(&[0]);
    go1(
        &[
            "export",
            "devx",
            "--options",
            "a",
            "--options",
            "b",
            "--options",
        ],
        &mut fr,
    );
    assert!(fr.args(0).contains(&"COPYBARA_OPTIONS=b".to_string()));
    std::env::remove_var("BUILD_WORKSPACE_DIRECTORY");
}

#[test]
fn docker_error_is_exit_1() {
    let _g = ENV.lock().unwrap();
    let (code, _, err) = go1(&["export", "devx"], &mut ErrRunner);
    assert_eq!(code, 1);
    assert_eq!(
        err,
        "docker error: exec: \"docker\": executable file not found in $PATH\n"
    );
}

#[test]
fn import_pr_missing_or_bad_pr_number() {
    let mut fr = FakeRunner::new(&[0]);
    let (code, _, err) = go1(&["import_pr", "devx"], &mut fr);
    assert_eq!((code, fr.calls), (2, 0));
    assert_eq!(
        err,
        "usage: sync import_pr <component> <pr-number> [--options \"<opts>\"]\n"
    );
    let (code, _, err) = go1(&["import_pr", "devx", "12x"], &mut fr);
    assert_eq!((code, fr.calls), (2, 0));
    assert_eq!(err, "import_pr: pr-number must be digits, got \"12x\"\n");
}

#[test]
fn import_pr_success_docker_args() {
    let _g = ENV.lock().unwrap();
    let _ws = setup_workspace();
    let mut fr = FakeRunner::new(&[0]);
    let (code, out, _) = go1(&["import_pr", "mcp-slack", "123"], &mut fr);
    assert_eq!((code, fr.calls), (0, 1));
    assert_eq!(
        out,
        "Copybara import_pr OK (exit 0; 4 = no-op) for mcp-slack PR #123\n"
    );
    let args = fr.args(0);
    assert!(args.contains(&"COPYBARA_WORKFLOW=import_pr_mcp_slack".to_string()));
    assert!(args.contains(&"COPYBARA_SOURCEREF=123".to_string()));
    assert!(args.contains(&"GITHUB_TOKEN".to_string()));
    assert!(!args.iter().any(|a| a.contains("id_rsa")), "{args:?}");
    // The resolved config was handed to docker, then removed.
    let cfg = args[4]
        .strip_suffix(":/root/copy.bara.sky")
        .unwrap()
        .to_string();
    assert!(cfg.contains("copy.bara.") && cfg.ends_with(".sky"), "{cfg}");
    assert!(!std::path::Path::new(&cfg).exists());
}

#[test]
fn import_pr_failure_and_noop() {
    let _g = ENV.lock().unwrap();
    let _ws = setup_workspace();
    let mut fr = FakeRunner::new(&[1]);
    let (code, _, err) = go1(&["import_pr", "devx", "5"], &mut fr);
    assert_eq!((code, fr.calls), (1, 1));
    assert_eq!(err, "Copybara import_pr failed (exit 1) for devx PR #5\n");
    let mut fr = FakeRunner::new(&[4]);
    assert_eq!(go1(&["import_pr", "devx", "5"], &mut fr).0, 0);
}

#[test]
fn import_pr_missing_config() {
    let _g = ENV.lock().unwrap();
    std::env::set_var("BUILD_WORKSPACE_DIRECTORY", "/nonexistent/ws/");
    let mut fr = FakeRunner::new(&[0]);
    let (code, _, err) = go1(&["import_pr", "devx", "5"], &mut fr);
    assert_eq!((code, fr.calls), (1, 0));
    assert_eq!(
        err,
        "import_pr: read /nonexistent/ws/tools/copybara/copy.bara.sky: open /nonexistent/ws/tools/copybara/copy.bara.sky: no such file or directory\n"
    );
    std::env::remove_var("BUILD_WORKSPACE_DIRECTORY");
}

#[test]
fn resolve_import_pr_config_rewrites_placeholder() {
    let _g = ENV.lock().unwrap();
    let ws = setup_workspace();
    use std::os::unix::ffi::OsStrExt;
    let path = resolve_import_pr_config(ws.0.as_os_str().as_bytes(), b"77").unwrap();
    let p = std::ffi::OsStr::from_bytes(&path);
    let data = std::fs::read_to_string(p).unwrap();
    std::fs::remove_file(p).unwrap();
    assert!(!data.contains("@@PR_NUMBER@@"));
    assert!(data.contains("import-pr-77"));
}
