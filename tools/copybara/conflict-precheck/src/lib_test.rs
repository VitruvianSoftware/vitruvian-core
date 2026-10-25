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

//! The Go tool's main_test.go, ported: label derivation, sha extraction, and
//! run() end to end against real git repos in temp dirs.

use super::*;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::Command;

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> TempDir {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let p = base.join(format!(
            "cp-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(&p).unwrap();
        TempDir(p)
    }
    fn bytes(&self) -> Vec<u8> {
        self.0.as_os_str().as_bytes().to_vec()
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn git(dir: &Path, args: &[&str]) -> String {
    let out = Command::new("git")
        .args(args)
        .current_dir(dir)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .output()
        .expect("git runs");
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap().trim().to_string()
}

fn init_repo() -> TempDir {
    let d = TempDir::new();
    git(&d.0, &["init", "-q"]);
    git(&d.0, &["config", "user.email", "test@example.com"]);
    git(&d.0, &["config", "user.name", "Test"]);
    git(&d.0, &["config", "commit.gpgsign", "false"]);
    std::fs::write(d.0.join("README.md"), "init\n").unwrap();
    git(&d.0, &["add", "."]);
    git(&d.0, &["commit", "-q", "-m", "init"]);
    d
}

fn add_commit(d: &TempDir, file: &str, content: &str, msg: &str) -> String {
    let p = d.0.join(file);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(&p, content).unwrap();
    git(&d.0, &["add", file]);
    git(&d.0, &["commit", "-q", "-m", msg]);
    git(&d.0, &["rev-parse", "HEAD"])
}

fn run_args(args: &[&[u8]]) -> (i32, String, String) {
    let args: Vec<Vec<u8>> = args.iter().map(|a| a.to_vec()).collect();
    let (mut o, mut e) = (Vec::new(), Vec::new());
    let code = run(&args, &mut o, &mut e);
    (
        code,
        String::from_utf8(o).unwrap(),
        String::from_utf8(e).unwrap(),
    )
}

#[test]
fn import_label_cases() {
    for (c, want) in [
        ("mcp-slack", "MCP_SLACK_REV_ID"),
        ("devx", "DEVX_REV_ID"),
        ("nexus-agent", "NEXUS_AGENT_REV_ID"),
        ("homelab", "HOMELAB_REV_ID"),
    ] {
        assert_eq!(import_label(c.as_bytes()), want.as_bytes());
    }
}

#[test]
fn to_upper_is_go_simple_case_mapping() {
    // ß has no single-rune upper case: Go keeps it (Rust's full mapping would give "SS").
    assert_eq!(to_upper("straße".as_bytes()), "STRAßE".as_bytes());
    assert_eq!(to_upper("ǆ".as_bytes()), "Ǆ".as_bytes());
    // Invalid UTF-8 becomes U+FFFD, as strings.Map does.
    assert_eq!(to_upper(b"a\xffb\xc3"), "A\u{FFFD}B\u{FFFD}".as_bytes());
}

#[test]
fn trim_space_is_go_trim_space() {
    assert_eq!(trim_space(b"  a b \n"), b"a b");
    assert_eq!(trim_space("\u{A0}x\u{3000}".as_bytes()), b"x");
    assert_eq!(trim_space(b" \xff "), b"\xff");
    assert_eq!(trim_space(b" \n\t"), b"");
}

#[test]
fn find_rev_is_the_go_regexp() {
    assert_eq!(find_rev(b"x\nL: abc1234\n", b"L"), b"abc1234");
    assert_eq!(find_rev(b"L: abc123\n", b"L"), b"");
    assert_eq!(find_rev(b" L: abc1234\n", b"L"), b"");
    let long = format!("L: {}", "a".repeat(45));
    assert_eq!(find_rev(long.as_bytes(), b"L"), "a".repeat(40).as_bytes());
    assert_eq!(find_rev(b"L: ABC1234\nL: 1234567zz", b"L"), b"1234567");
}

#[test]
fn latest_rev_extracts_sha() {
    let d = init_repo();
    add_commit(
        &d,
        "a.txt",
        "hello",
        "feat: something\n\nMONOREPO_REV_ID: abc1234\n",
    );
    assert_eq!(latest_rev(&d.bytes(), b"MONOREPO_REV_ID"), b"abc1234");
}

#[test]
fn latest_rev_no_label_is_empty() {
    let d = init_repo();
    add_commit(&d, "b.txt", "world", "plain commit no label");
    assert_eq!(latest_rev(&d.bytes(), b"MONOREPO_REV_ID"), b"");
}

#[test]
fn latest_rev_longer_sha() {
    let d = init_repo();
    add_commit(
        &d,
        "c.txt",
        "v",
        "sync\n\nDEVX_REV_ID: deadbeefdeadbeefdeadbeef12345678abcdef01\n",
    );
    assert_eq!(
        latest_rev(&d.bytes(), b"DEVX_REV_ID"),
        b"deadbeefdeadbeefdeadbeef12345678abcdef01"
    );
}

#[test]
fn export_no_baseline() {
    let (m, s) = (init_repo(), init_repo());
    let (code, out, _) = run_args(&[b"export", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
    assert_eq!(out, "[precheck/export] no import baseline yet — skipping\n");
}

#[test]
fn import_no_baseline() {
    let (m, s) = (init_repo(), init_repo());
    let (code, out, _) = run_args(&[b"import", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
    assert_eq!(out, "[precheck/import] no export baseline yet — skipping\n");
}

#[test]
fn export_baseline_not_reachable() {
    let (m, s) = (init_repo(), init_repo());
    add_commit(
        &m,
        "x.txt",
        "v",
        "import sync\n\nDEVX_REV_ID: deadbeef123\n",
    );
    let (code, out, _) = run_args(&[b"export", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
    assert_eq!(
        out,
        "::warning::[precheck/export] import baseline deadbeef123 not reachable in standalone — skipping\n"
    );
}

#[test]
fn import_baseline_not_reachable() {
    let (m, s) = (init_repo(), init_repo());
    add_commit(
        &s,
        "x.txt",
        "v",
        "export sync\n\nMONOREPO_REV_ID: deadbeef456\n",
    );
    let (code, _, _) = run_args(&[b"import", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
}

#[test]
fn export_genuine_standalone_commit() {
    let (m, s) = (init_repo(), init_repo());
    let base = add_commit(
        &s,
        "src.go",
        "v1",
        "feat: initial import\n\nMONOREPO_REV_ID: abc0001\n",
    );
    add_commit(
        &m,
        "z.txt",
        "v",
        &format!("import sync\n\nDEVX_REV_ID: {base}\n"),
    );
    add_commit(
        &s,
        "standalone.go",
        "new feature",
        "feat: standalone genuine change",
    );
    let (code, out, _) = run_args(&[b"export", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 1);
    assert!(out.starts_with("::error title=Copybara conflict pre-check::Refusing to export devx"));
    assert!(out.contains("Offending un-synced commit(s):\n"));
    assert!(out.ends_with(" feat: standalone genuine change\n"), "{out}");
}

#[test]
fn export_only_synced_commits() {
    let (m, s) = (init_repo(), init_repo());
    let base = add_commit(
        &s,
        "src.go",
        "v1",
        "feat: init\n\nMONOREPO_REV_ID: abc0002\n",
    );
    add_commit(
        &m,
        "z.txt",
        "v",
        &format!("import sync\n\nDEVX_REV_ID: {base}\n"),
    );
    add_commit(
        &s,
        "synced.go",
        "synced",
        "sync: from monorepo\n\nMONOREPO_REV_ID: feedbeef\n",
    );
    let (code, out, _) = run_args(&[b"export", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
    assert_eq!(
        out,
        format!(
            "[precheck/export] OK (devx) — no un-synced genuine peer changes (baseline {base}).\n"
        )
    );
}

#[test]
fn import_genuine_monorepo_commit() {
    let (m, s) = (init_repo(), init_repo());
    let base = add_commit(&m, "devx/src.go", "v1", "feat: init");
    add_commit(
        &s,
        "z.txt",
        "v",
        &format!("export sync\n\nMONOREPO_REV_ID: {base}\n"),
    );
    add_commit(
        &m,
        "devx/new.go",
        "new feature",
        "feat: genuine monorepo change",
    );
    let (code, _, _) = run_args(&[b"import", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 1);
}

#[test]
fn import_build_files_are_monorepo_only() {
    let (m, s) = (init_repo(), init_repo());
    let base = add_commit(&m, "devx/src.go", "v1", "feat: init");
    add_commit(
        &s,
        "z.txt",
        "v",
        &format!("export sync\n\nMONOREPO_REV_ID: {base}\n"),
    );
    add_commit(&m, "devx/pkg/BUILD.bazel", "x", "build: gazelle");
    add_commit(&m, "devx/BUILD", "x", "build: root");
    let (code, _, _) = run_args(&[b"import", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
}

#[test]
fn import_clean() {
    let (m, s) = (init_repo(), init_repo());
    let base = add_commit(
        &m,
        "devx/src.go",
        "v1",
        "feat: init\n\nDEVX_REV_ID: 0000001\n",
    );
    add_commit(
        &s,
        "z.txt",
        "v",
        &format!("export sync\n\nMONOREPO_REV_ID: {base}\n"),
    );
    let (code, _, _) = run_args(&[b"import", b"devx", &m.bytes(), &s.bytes()]);
    assert_eq!(code, 0);
}

#[test]
fn unknown_direction() {
    let (code, out, err) = run_args(&[b"sideways", b"devx", b"/tmp", b"/tmp"]);
    assert_eq!(code, 2);
    assert_eq!(out, "");
    assert_eq!(err, "unknown direction: sideways (use export|import)\n");
}

#[test]
fn too_few_args() {
    let (code, _, err) = run_args(&[b"export", b"devx", b"/tmp"]);
    assert_eq!(code, 2);
    assert!(err.starts_with("usage: conflict-precheck "));
}

#[test]
fn export_standalone_only_excluded() {
    let (m, s) = (init_repo(), init_repo());
    let base = add_commit(
        &s,
        "src.go",
        "v1",
        "feat: init\n\nMONOREPO_REV_ID: abc0003\n",
    );
    add_commit(
        &m,
        "z.txt",
        "v",
        &format!("import sync\n\nDEVX_REV_ID: {base}\n"),
    );
    add_commit(
        &s,
        ".github/workflows/sync.yaml",
        "wf: v1",
        "ci: update dispatch workflow",
    );
    let (code, _, _) = run_args(&[
        b"export",
        b"devx",
        &m.bytes(),
        &s.bytes(),
        b".github/workflows/sync.yaml",
    ]);
    assert_eq!(code, 0);
}
