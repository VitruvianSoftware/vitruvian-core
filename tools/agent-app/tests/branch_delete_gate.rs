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

//! branch-delete finds its landed gate however agent-app is started.
//!
//! The gate is `//tools/landed`, a build output. On 2026-11-01
//! `bazel run //tools/agent-app -- branch-delete` looked for it in the source
//! checkout (`$BUILD_WORKSPACE_DIRECTORY/tools/landed/landed.sh`), which no
//! longer has one since landed became Rust, and refused every branch.
//!
//! These run the real binary with no key, so it always stops at the token
//! step, before it asks GitHub anything: nothing can be deleted. Reaching that
//! step proves the gate was found; "nothing was deleted" before it, naming the
//! gate, is the bug.

use std::path::{Path, PathBuf};
use std::process::Command;

fn agent_app() -> PathBuf {
    let rel = std::env::var("AGENT_APP_BIN").expect("AGENT_APP_BIN is set by the BUILD rule");
    std::env::current_dir().unwrap().join(rel)
}

fn registry() -> PathBuf {
    let rel =
        std::env::var("AGENT_REGISTRY_TSV").expect("AGENT_REGISTRY_TSV is set by the BUILD rule");
    std::env::current_dir().unwrap().join(rel)
}

fn scratch(name: &str) -> PathBuf {
    let d = PathBuf::from(std::env::var("TEST_TMPDIR").unwrap()).join(name);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Runs `branch-delete --agent wren <branch>` the way a person would: none of
/// the test's own runfiles or TEST_* variables (which unlock agent-app's test
/// overrides), and an empty key folder.
fn branch_delete(workspace: Option<&Path>, tag: &str) -> String {
    let keys = scratch(&format!("{tag}-keys"));
    let home = scratch(&format!("{tag}-home"));
    let mut c = Command::new(agent_app());
    c.args([
        "branch-delete",
        "--agent",
        "wren",
        "no-such-branch-for-a-test",
    ])
    .env_clear()
    .env("PATH", std::env::var_os("PATH").unwrap_or_default())
    .env("HOME", &home)
    .env("AGENT_REGISTRY", registry())
    .env("AGENT_KEY_DIR", &keys)
    .env("GH_BIN", "/nonexistent/gh")
    .env("GITHUB_API_URL", "http://127.0.0.1:9");
    if let Some(ws) = workspace {
        // What `bazel run` sets.
        c.env("BUILD_WORKSPACE_DIRECTORY", ws)
            .env("BUILD_WORKING_DIRECTORY", ws);
    }
    let o = c.output().expect("agent-app starts");
    assert_ne!(o.status.code(), Some(0), "with no key it must fail");
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn assert_gate_found(stderr: &str) {
    assert!(
        !stderr.contains("cannot read") && !stderr.contains("cannot find"),
        "branch-delete could not find its landed gate:\n{stderr}"
    );
    assert!(
        stderr.contains("could not mint a token for the wren app; nothing was deleted"),
        "expected to stop at the token step:\n{stderr}"
    );
}

/// `bazel run //tools/agent-app -- branch-delete ...`: the checkout has no
/// built gate in it, which is exactly the case that broke.
#[test]
fn finds_the_gate_under_bazel_run() {
    let checkout = scratch("checkout");
    std::fs::create_dir_all(checkout.join("tools/landed")).unwrap();
    assert_gate_found(&branch_delete(Some(&checkout), "run"));
}

/// Started straight from runfiles (another tool's data, or the agent-app.sh
/// launcher), with no `bazel run` around it.
#[test]
fn finds_the_gate_from_runfiles() {
    assert_gate_found(&branch_delete(None, "runfiles"));
}
