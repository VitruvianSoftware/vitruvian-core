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

//! workflow-run checks its inputs in the real binary, before any token.
//!
//! The unit tests prove each input rule; these prove `workflow-run` calls
//! them. Run as wren (the one app with Actions write) with an empty key folder
//! and `GH_BIN=false`, the binary always stops at the token step at the
//! latest, so nothing can be started. A refused input must stop it earlier,
//! naming the rule; "could not mint" means the input got through.

use std::path::PathBuf;
use std::process::Command;

fn runfile(var: &str) -> PathBuf {
    let rel = std::env::var(var).unwrap_or_else(|_| panic!("{var} is set by the BUILD rule"));
    std::env::current_dir().unwrap().join(rel)
}

fn scratch(name: &str) -> PathBuf {
    let d = PathBuf::from(std::env::var("TEST_TMPDIR").unwrap()).join(name);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// `workflow-run --agent wren <args>` as a person would start it: none of the
/// test's TEST_* variables (which unlock agent-app's test overrides), no key.
/// With `bazel_run`, from a checkout holding the committed allow-list, as
/// `bazel run` does; otherwise from runfiles.
fn workflow_run(args: &[&str], bazel_run: bool, tag: &str) -> String {
    let keys = scratch(&format!("{tag}-keys"));
    let home = scratch(&format!("{tag}-home"));
    let mut c = Command::new(runfile("AGENT_APP_BIN"));
    c.args(["workflow-run", "--agent", "wren"])
        .args(args)
        .env_clear()
        .env("PATH", std::env::var_os("PATH").unwrap_or_default())
        .env("HOME", &home)
        .env("AGENT_REGISTRY", runfile("AGENT_REGISTRY_TSV"))
        .env("AGENT_KEY_DIR", &keys)
        .env("GH_BIN", "false")
        .env("GITHUB_API_URL", "http://127.0.0.1:9");
    if bazel_run {
        let ws = scratch(&format!("{tag}-checkout"));
        let dir = ws.join("tools/agent-app");
        std::fs::create_dir_all(&dir).unwrap();
        for (var, name) in [
            ("WORKFLOW_ALLOWLIST_TXT", "workflow-allowlist.txt"),
            ("AGENT_PERMISSIONS_TSV", "permissions.tsv"),
            ("AGENT_REGISTRY_TSV", "agents.tsv"),
        ] {
            std::fs::copy(runfile(var), dir.join(name)).unwrap();
        }
        c.env("BUILD_WORKSPACE_DIRECTORY", &ws)
            .env("BUILD_WORKING_DIRECTORY", &ws);
    }
    let o = c.output().expect("agent-app starts");
    assert_ne!(o.status.code(), Some(0), "with no key it must fail");
    String::from_utf8_lossy(&o.stderr).into_owned()
}

fn refused_before_minting(args: &[&str], want: &str) {
    for bazel_run in [false, true] {
        let tag = format!("{}-{}", args.join("_").replace(['/', '='], "-"), bazel_run);
        let err = workflow_run(args, bazel_run, &tag);
        assert!(
            !err.contains("could not mint"),
            "{args:?} got past the input check (bazel_run={bazel_run}):\n{err}"
        );
        assert!(
            err.contains(want),
            "{args:?} (bazel_run={bazel_run}): want {want:?}:\n{err}"
        );
    }
}

#[test]
fn allow_destructive_refused_on_foundation_app_deploy() {
    refused_before_minting(
        &["foundation-app-deploy.yaml", "-f", "allow-destructive=true"],
        "only foundation-proj-deploy.yaml may be started with allow-destructive",
    );
}

#[test]
fn working_directory_refused_on_foundation_proj_deploy() {
    refused_before_minting(
        &[
            "foundation-proj-deploy.yaml",
            "--raw-field",
            "working-directory=x",
        ],
        "it chooses which Pulumi project the run applies",
    );
}

/// The control: a good re-run gets through every input rule and stops only
/// because there is no key, so the refusals above are the rules, not a
/// missing file.
#[test]
fn good_rerun_reaches_the_token_step() {
    for bazel_run in [false, true] {
        let err = workflow_run(
            &[
                "foundation-proj-deploy.yaml",
                "-f",
                "environment=development",
                "-f",
                "business-unit=business_unit_1",
                "-f",
                "allow-destructive=true",
            ],
            bazel_run,
            &format!("good-{bazel_run}"),
        );
        assert!(
            err.contains("could not mint a token for the wren app; the workflow was NOT started"),
            "bazel_run={bazel_run}:\n{err}"
        );
    }
}
