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

//! Black-box guard for the queue-runner-routing binary: the real workflows
//! pass, and every way a workflow could hand the homelab runner to a pull
//! request fails.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

const ROUTED: &str = "runs-on: ${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}";

fn binary() -> PathBuf {
    let rel = std::env::var("QUEUE_RUNNER_ROUTING_BIN").expect("set by Bazel");
    std::env::current_dir().unwrap().join(rel)
}

struct Dir(PathBuf);
impl Dir {
    fn new(tag: &str) -> Dir {
        let base = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
        let p = Path::new(&base).join(format!("qrr-{}-{}", std::process::id(), tag));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        Dir(p)
    }
}
impl Drop for Dir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn run(args: &[&Path]) -> Output {
    Command::new(binary())
        .args(args)
        .output()
        .expect("binary runs")
}

fn text(o: &Output) -> String {
    format!(
        "{}{}",
        String::from_utf8_lossy(&o.stdout),
        String::from_utf8_lossy(&o.stderr)
    )
}

/// Verdict of the binary on a directory holding one workflow with this text.
fn verdict(tag: &str, name: &str, body: &str) -> (bool, String) {
    let d = Dir::new(tag);
    std::fs::write(d.0.join(name), format!("{body}\n")).unwrap();
    let o = run(&[&d.0]);
    (o.status.success(), text(&o))
}

fn allowed(tag: &str, body: &str) {
    let (ok, t) = verdict(tag, "x.yaml", body);
    assert!(ok, "expected pass: {t}");
    assert!(t.contains("queue-runner-routing: ok"), "{t}");
}

fn refused(tag: &str, body: &str) {
    let (ok, t) = verdict(tag, "x.yaml", body);
    assert!(!ok, "expected fail, got pass: {t}");
    assert!(
        t.contains("names the homelab runner outside the one allowed rule"),
        "{t}"
    );
    assert!(
        t.contains("x.yaml:"),
        "the diagnostic names the file and line: {t}"
    );
}

#[test]
fn a_plain_hosted_job_is_allowed() {
    allowed("hosted", "jobs:\n  a:\n    runs-on: ubuntu-26.04");
}

#[test]
fn the_one_routing_rule_is_allowed() {
    allowed("rule", &format!("jobs:\n  a:\n    {ROUTED}"));
}

#[test]
fn the_rule_inside_a_list_item_is_allowed() {
    allowed("list", &format!("jobs:\n  - {ROUTED}"));
}

#[test]
fn a_comment_may_name_the_runner() {
    allowed(
        "comment",
        "# routed to vitruvian-queue when QUEUE_RUNNER is on\njobs:\n  a:\n    runs-on: ubuntu-26.04",
    );
}

#[test]
fn naming_the_runner_directly_is_refused() {
    refused("direct", "jobs:\n  a:\n    runs-on: vitruvian-queue");
}

#[test]
fn routing_without_the_event_guard_is_refused() {
    refused(
        "noguard",
        "jobs:\n  a:\n    runs-on: ${{ vars.QUEUE_RUNNER == 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}",
    );
}

#[test]
fn a_guard_that_lets_pull_requests_in_is_refused() {
    refused(
        "pr",
        "jobs:\n  a:\n    runs-on: ${{ (github.event_name == 'merge_group' || github.event_name == 'pull_request') && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}",
    );
}

#[test]
fn the_rule_without_the_fallback_check_is_refused() {
    refused(
        "nofallback",
        "jobs:\n  a:\n    runs-on: ${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}",
    );
}

#[test]
fn the_label_in_a_matrix_is_refused() {
    refused(
        "matrix",
        "jobs:\n  a:\n    strategy:\n      matrix:\n        os: [vitruvian-queue]\n    runs-on: ${{ matrix.os }}",
    );
}

#[test]
fn the_switch_used_in_an_if_is_refused() {
    refused(
        "if",
        "jobs:\n  a:\n    if: vars.QUEUE_RUNNER == 'on'\n    runs-on: ubuntu-26.04",
    );
}

#[test]
fn only_the_canary_workflow_is_exempt() {
    let body = "jobs:\n  canary:\n    runs-on: vitruvian-queue";
    let (ok, t) = verdict("canary", "queue-runner-watch.yaml", body);
    assert!(ok, "queue-runner-watch.yaml may name the runner: {t}");
    let (ok, t) = verdict("copy", "other.yaml", body);
    assert!(!ok, "the same text under another name is refused: {t}");
    // The exemption is the exact file name, not a pattern.
    for name in [
        "other-queue-runner-watch.yaml",
        "queue-runner-watch2.yaml",
        "my-watch.yaml",
    ] {
        let (ok, t) = verdict("near", name, body);
        assert!(!ok, "{name} must not share the canary's exemption: {t}");
    }
}

#[test]
fn an_empty_command_line_is_a_usage_error() {
    let o = run(&[]);
    assert_eq!(o.status.code(), Some(1), "{}", text(&o));
}

#[test]
fn every_workflow_in_the_repo_passes() {
    // Bazel passes every workflow's path, space-separated: the directory is the
    // first one's.
    let all = std::env::var("WORKFLOW_FILES").expect("set by Bazel");
    let files: Vec<&str> = all.split_whitespace().collect();
    assert!(
        files.len() > 10,
        "expected the repo's workflows, got {files:?}"
    );
    let first = std::env::current_dir().unwrap().join(files[0]);
    let dir = first.parent().unwrap();
    let o = run(&[dir]);
    assert!(o.status.success(), "the repo's workflows: {}", text(&o));
}
