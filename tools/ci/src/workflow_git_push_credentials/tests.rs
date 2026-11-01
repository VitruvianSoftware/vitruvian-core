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

//! //tools/ci:workflow_git_push_credentials_test -- a workflow that checks
//! out with `persist-credentials: false` leaves git with no credentials, so a
//! bare `git push` dies with "could not read Username". Every workflow that
//! pushes this way must first give git a credential (`gh auth setup-git`, or a
//! ~/.git-credentials file) or push to an explicit URL. site-sync-downloads
//! shipped without it and failed its first run.
//!
//! Ported from the former tools/ci/workflow-git-push-credentials_test.sh; the
//! rule is the same four greps over each workflow file, by hand. The fixture
//! tests below are new: the shell guard had none, so it could not show it
//! would ever fail.

use std::path::{Path, PathBuf};

/// `grep -Eq 'git push[^|]* origin'`: on some line, " origin" follows a
/// `git push` with no `|` between them.
fn pushes_to_origin(text: &str) -> bool {
    text.lines().any(|line| {
        let mut rest = line;
        while let Some(i) = rest.find("git push") {
            let after = &rest[i + "git push".len()..];
            let span = after.split('|').next().unwrap_or("");
            if span.contains(" origin") {
                return true;
            }
            rest = after;
        }
        false
    })
}

/// `grep -Eq 'gh auth setup-git|\.git-credentials|credential\.helper|extraheader'`
fn configures_credentials(text: &str) -> bool {
    [
        "gh auth setup-git",
        ".git-credentials",
        "credential.helper",
        "extraheader",
    ]
    .iter()
    .any(|n| text.contains(n))
}

/// The workflows (by file name) that push to origin without credentials.
fn offenders(files: &[PathBuf]) -> Vec<String> {
    let mut bad = Vec::new();
    for wf in files {
        let text = std::fs::read_to_string(wf).unwrap_or_default();
        if !text.contains("persist-credentials: false") {
            continue;
        }
        // A second checkout that keeps an App token's credentials is fine.
        if text.contains("persist-credentials: allow") {
            continue;
        }
        // Only a push to the named remote needs stored credentials.
        if !pushes_to_origin(&text) {
            continue;
        }
        let name = wf.file_name().unwrap().to_string_lossy().into_owned();
        if configures_credentials(&text) {
            println!("  ✓ {name}");
        } else {
            bad.push(name);
        }
    }
    bad
}

/// `.github/workflows/*.y*ml` under `root`, sorted.
fn workflows(root: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(root.join(".github/workflows"))
        .unwrap()
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            let n = p.file_name().unwrap().to_string_lossy();
            n.ends_with(".yaml") || n.ends_with(".yml")
        })
        .collect();
    v.sort();
    v
}

#[test]
fn every_workflow_that_pushes_to_origin_has_git_credentials() {
    // The runfiles tree, from //:workflow_files (every .github/workflows/*.yaml).
    // The shell globbed *.y*ml; the repo has no .yml workflow today, and a new
    // one would not be in the filegroup, so this would not see it.
    let root = std::env::current_dir().unwrap();
    let files = workflows(&root);
    assert!(
        files.len() > 20,
        "only {} workflows in the runfiles: is //:workflow_files in data?",
        files.len()
    );
    let bad = offenders(&files);
    assert!(
        bad.is_empty(),
        "pushes to origin with no git credentials configured: {}",
        bad.join(", ")
    );
}

fn fixture(name: &str, body: &str) -> Vec<String> {
    let dir = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("push-creds-{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join(".github/workflows")).unwrap();
    std::fs::write(
        dir.join(".github/workflows").join(format!("{name}.yaml")),
        body,
    )
    .unwrap();
    offenders(&workflows(&dir))
}

const CHECKOUT: &str =
    "      - uses: actions/checkout@x\n        with:\n          persist-credentials: false\n";

#[test]
fn a_push_to_origin_without_credentials_fails() {
    let body = format!("{CHECKOUT}      - run: git push origin HEAD:refs/heads/x\n");
    assert_eq!(
        fixture("bare-push", &body),
        vec!["bare-push.yaml".to_string()]
    );
}

#[test]
fn each_way_of_giving_git_a_credential_passes() {
    for (i, setup) in [
        "gh auth setup-git",
        "echo x > ~/.git-credentials",
        "git config credential.helper store",
        "git config http.https://github.com/.extraheader x",
    ]
    .iter()
    .enumerate()
    {
        let body =
            format!("{CHECKOUT}      - run: |\n          {setup}\n          git push origin x\n");
        assert!(
            fixture(&format!("cred-{i}"), &body).is_empty(),
            "{setup} was not accepted"
        );
    }
}

#[test]
fn what_needs_no_stored_credential_passes() {
    // A push to an explicit URL, a pipe before "origin", a kept App token
    // checkout, and a checkout that keeps its credentials.
    let cases = [
        format!("{CHECKOUT}      - run: git push https://x-access-token:$T@github.com/o/r HEAD\n"),
        format!("{CHECKOUT}      - run: git push --dry-run | tee origin.log\n"),
        format!("{CHECKOUT}          persist-credentials: allow\n      - run: git push origin x\n"),
        "      - uses: actions/checkout@x\n      - run: git push origin x\n".to_string(),
    ];
    for (i, body) in cases.iter().enumerate() {
        assert!(
            fixture(&format!("ok-{i}"), body).is_empty(),
            "case {i} flagged:\n{body}"
        );
    }
}
