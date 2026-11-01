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

//! Runs the build step of .github/actions/build-ci-tool, exactly as written
//! in that file, for every tool a workflow or composite action asks it to
//! build. Bazel's rustc stands in for the runner's.
//!
//! The release gates, the digests, the cache pruner and the notifier run on
//! jobs with no Bazel, so this build is the only one their CI runs ever see.
//! If a tool gains a crate dependency, or the step's rustc lines drift from
//! the crate layout, this fails in presubmit instead of on a release.
//!
//! Each binary it builds is then run next to the Bazel-built one with the
//! same empty environment, and the two must answer the same way.

use std::collections::BTreeSet;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
use std::sync::atomic::{AtomicUsize, Ordering};

const ACTION: &str = ".github/actions/build-ci-tool/action.yml";
const USES: &str = "uses: ./.github/actions/build-ci-tool";

fn tmp() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let p = base.join(format!(
        "build-ci-tool-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = fs::remove_dir_all(&p);
    fs::create_dir_all(&p).unwrap();
    fs::canonicalize(&p).unwrap()
}

fn read(p: impl AsRef<Path>) -> String {
    let p = p.as_ref();
    fs::read_to_string(p).unwrap_or_else(|e| panic!("read {}: {e}", p.display()))
}

fn indent(l: &str) -> usize {
    l.len() - l.trim_start().len()
}

/// The `run: |` block of the step with `id: build`, dedented: the script
/// GitHub hands to bash.
fn build_script(action: &str) -> String {
    let lines: Vec<&str> = action.lines().collect();
    let id = lines
        .iter()
        .position(|l| l.trim() == "id: build")
        .expect("build-ci-tool has a step with id: build");
    let run = (id..lines.len())
        .find(|&i| lines[i].trim() == "run: |")
        .expect("the build step has a `run: |` block");
    let key = indent(lines[run]);
    let body: Vec<&str> = lines[run + 1..]
        .iter()
        .take_while(|l| l.trim().is_empty() || indent(l) > key)
        .copied()
        .collect();
    let pad = body
        .iter()
        .filter(|l| !l.trim().is_empty())
        .map(|l| indent(l))
        .min()
        .expect("the run block is not empty");
    let mut s = String::new();
    for l in body {
        s.push_str(if l.len() >= pad { &l[pad..] } else { "" });
        s.push('\n');
    }
    s
}

/// Every `tool:` a workflow or composite action passes to build-ci-tool,
/// with the file that asks for it.
fn callers() -> Vec<(String, String)> {
    let mut found = Vec::new();
    for dir in [".github/workflows", ".github/actions"] {
        let mut files = Vec::new();
        for e in fs::read_dir(dir).unwrap_or_else(|e| panic!("{dir}: {e}")) {
            let p = e.unwrap().path();
            if p.is_dir() {
                let a = p.join("action.yml");
                if a.exists() {
                    files.push(a);
                }
            } else if p.extension().map_or(false, |x| x == "yaml" || x == "yml") {
                files.push(p);
            }
        }
        for f in files {
            let text = read(&f);
            let lines: Vec<&str> = text.lines().collect();
            for (i, l) in lines.iter().enumerate() {
                if l.trim().trim_start_matches("- ") != USES {
                    continue;
                }
                let tool = lines[i + 1..]
                    .iter()
                    .take(4)
                    .find_map(|n| n.trim().strip_prefix("tool: "))
                    .unwrap_or_else(|| {
                        panic!("{}:{}: build-ci-tool without `tool:`", f.display(), i + 1)
                    });
                found.push((
                    tool.trim().to_string(),
                    format!("{}:{}", f.display(), i + 1),
                ));
            }
        }
    }
    found
}

/// A copy of the sources the step reads, laid out as in a checkout.
fn workspace(tools: &BTreeSet<String>) -> PathBuf {
    let ws = tmp();
    let copy = |rel: &str| {
        let dst = ws.join(rel);
        fs::create_dir_all(dst.parent().unwrap()).unwrap();
        fs::copy(rel, &dst).unwrap_or_else(|e| panic!("copy {rel}: {e}"));
    };
    copy("tools/shell-compat/src/lib.rs");
    for t in tools {
        copy(&format!("tools/ci/src/{t}/lib.rs"));
        copy(&format!("tools/ci/src/{t}/main.rs"));
    }
    ws
}

/// A directory holding a `rustc` that runs Bazel's, first on PATH.
fn rustc_shim() -> PathBuf {
    let real = fs::canonicalize(std::env::var("REAL_RUSTC").expect("REAL_RUSTC is set by BUILD"))
        .expect("REAL_RUSTC exists");
    let dir = tmp();
    let shim = dir.join("rustc");
    fs::write(
        &shim,
        format!("#!/bin/sh\nexec '{}' \"$@\"\n", real.display()),
    )
    .unwrap();
    fs::set_permissions(&shim, fs::Permissions::from_mode(0o755)).unwrap();
    dir
}

struct Step {
    out: Output,
    github_output: String,
}

fn run_step(script: &str, tool: &str, ws: &Path, runner_temp: &Path, shim: &Path) -> Step {
    let gho = tmp().join("github_output");
    fs::write(&gho, "").unwrap();
    let path = format!(
        "{}:{}",
        shim.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    // GitHub runs a `shell: bash` step as `bash -e {0}` (the script sets
    // -uo pipefail itself).
    let out = Command::new("bash")
        .arg("-e")
        .arg("-c")
        .arg(script)
        .env("TOOL", tool)
        .env("GITHUB_WORKSPACE", ws)
        .env("RUNNER_TEMP", runner_temp)
        .env("GITHUB_OUTPUT", &gho)
        .env("PATH", path)
        .current_dir(ws)
        .output()
        .expect("run bash");
    Step {
        out,
        github_output: read(&gho),
    }
}

fn text(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// Runs a binary with nothing in its environment but an empty PATH: no gh,
/// no token, no GitHub variables. Every tool answers that deterministically.
fn bare(bin: &Path, cwd: &Path) -> (Option<i32>, String, String) {
    let empty = tmp();
    let o = Command::new(bin)
        .env_clear()
        .env("PATH", &empty)
        .current_dir(cwd)
        .output()
        .unwrap_or_else(|e| panic!("run {}: {e}", bin.display()));
    (o.status.code(), text(&o.stdout), text(&o.stderr))
}

#[test]
fn every_tool_a_workflow_builds_compiles_with_the_actions_own_rustc_lines() {
    let script = build_script(&read(ACTION));
    let callers = callers();
    assert!(
        !callers.is_empty(),
        "no workflow uses {ACTION}; this test would prove nothing"
    );
    let tools: BTreeSet<String> = callers.iter().map(|(t, _)| t.clone()).collect();
    for (t, at) in &callers {
        assert!(
            Path::new(&format!("tools/ci/src/{t}/main.rs")).exists(),
            "{at}: tool `{t}` has no tools/ci/src/{t}/main.rs in this test's data \
             (add the tool to build_ci_tool_test's data in tools/ci/BUILD)"
        );
    }

    let ws = workspace(&tools);
    let runner_temp = tmp();
    let shim = rustc_shim();
    // One RUNNER_TEMP for every tool, as in a job that builds two of them.
    for t in &tools {
        let s = run_step(&script, t, &ws, &runner_temp, &shim);
        assert!(
            s.out.status.success(),
            "building {t} failed ({:?})\nstdout:\n{}\nstderr:\n{}",
            s.out.status,
            text(&s.out.stdout),
            text(&s.out.stderr)
        );
        let built = runner_temp.join("ci-tools").join(t);
        assert_eq!(
            s.github_output,
            format!("path={}\n", built.display()),
            "the step's only output is the binary's path"
        );
        let mode = fs::metadata(&built).unwrap().permissions().mode();
        assert!(mode & 0o111 != 0, "{} is not executable", built.display());

        // Same answer as the Bazel-built binary, from the same empty start.
        let bazel_bin = PathBuf::from(format!("tools/ci/{t}"));
        if bazel_bin.exists() {
            let cwd = tmp();
            let bazel = fs::canonicalize(&bazel_bin).unwrap();
            assert_eq!(
                bare(&built, &cwd),
                bare(&bazel, &cwd),
                "{t}: the rustc build and the Bazel build disagree on an empty environment"
            );
        }
    }
}

#[test]
fn every_tool_under_test_is_one_a_workflow_builds() {
    // The binaries in this test's data are the ones the parity check above
    // compares. A tool still listed here that no workflow builds any more is
    // dead weight; one a workflow builds but missing here goes unchecked.
    let listed: BTreeSet<String> = std::env::var("TOOLS")
        .expect("TOOLS is set by BUILD")
        .split_whitespace()
        .map(String::from)
        .collect();
    let built: BTreeSet<String> = callers().into_iter().map(|(t, _)| t).collect();
    assert_eq!(
        listed, built,
        "TOOLS in tools/ci/BUILD vs tools the workflows build"
    );
}

#[test]
fn a_tool_name_that_is_not_a_plain_directory_name_is_refused_before_rustc() {
    let script = build_script(&read(ACTION));
    let ws = tmp();
    let runner_temp = tmp();
    // A rustc that records being called: it must never be.
    let shim = tmp();
    let called = shim.join("called");
    fs::write(
        shim.join("rustc"),
        format!("#!/bin/sh\ntouch '{}'\nexit 0\n", called.display()),
    )
    .unwrap();
    fs::set_permissions(shim.join("rustc"), fs::Permissions::from_mode(0o755)).unwrap();
    for bad in [
        "",
        "../release_hold",
        "release-hold",
        "Release_Hold",
        "a b",
        "x;y",
    ] {
        let s = run_step(&script, bad, &ws, &runner_temp, &shim);
        assert_eq!(s.out.status.code(), Some(1), "tool {bad:?} must be refused");
        assert!(
            text(&s.out.stdout).contains("::error::build-ci-tool: tool must be a directory name"),
            "tool {bad:?}: no ::error annotation:\n{}",
            text(&s.out.stdout)
        );
        assert!(!called.exists(), "tool {bad:?} reached rustc");
        assert_eq!(s.github_output, "", "tool {bad:?} must not set an output");
    }
}

#[test]
fn a_failed_build_fails_the_step_and_sets_no_output() {
    let script = build_script(&read(ACTION));
    let tools: BTreeSet<String> = ["release_hold".to_string()].into_iter().collect();
    let ws = workspace(&tools);
    // Break the tool's source in the copy: rustc must fail and the step too.
    fs::write(
        ws.join("tools/ci/src/release_hold/lib.rs"),
        "this is not rust\n",
    )
    .unwrap();
    let runner_temp = tmp();
    let shim = rustc_shim();
    let s = run_step(&script, "release_hold", &ws, &runner_temp, &shim);
    assert!(!s.out.status.success(), "a failed rustc must fail the step");
    assert_eq!(s.github_output, "", "no path output for a failed build");
}

#[test]
fn a_notifier_that_cannot_build_still_reaches_ntfy() {
    // notify-ci-issues is what reports CI failures, so its own failed build
    // must be reported some other way: a step that posts to ntfy directly.
    let wf = read(".github/workflows/notify-ci-issues.yaml");
    let lines: Vec<&str> = wf.lines().collect();
    let name = lines
        .iter()
        .position(|l| l.trim() == "- name: Tell ntfy the notifier could not be built")
        .expect("notify-ci-issues.yaml has the build-failure fallback step");
    let step: Vec<&str> = lines[name..]
        .iter()
        .take_while(|l| !l.trim().is_empty())
        .copied()
        .collect();
    assert!(
        step.iter()
            .any(|l| l.trim() == "if: ${{ failure() && steps.notify-bin.outcome == 'failure' }}"),
        "the fallback runs exactly when the notifier's build failed:\n{}",
        step.join("\n")
    );
    let build_id = lines
        .iter()
        .position(|l| l.trim() == "id: notify-bin")
        .expect("the notifier's build step has id notify-bin");
    assert!(build_id < name, "the fallback comes after the build step");

    // Run its script with a fake curl that records its arguments.
    let run = (name..lines.len())
        .find(|&i| lines[i].trim() == "run: |")
        .expect("the fallback has a `run: |` block");
    let key = indent(lines[run]);
    let body: Vec<&str> = lines[run + 1..]
        .iter()
        .take_while(|l| l.trim().is_empty() || indent(l) > key)
        .copied()
        .collect();
    let pad = body
        .iter()
        .filter(|l| !l.trim().is_empty())
        .map(|l| indent(l))
        .min()
        .unwrap();
    let script: String = body
        .iter()
        .map(|l| format!("{}\n", l.get(pad..).unwrap_or("")))
        .collect();

    let dir = tmp();
    let log = dir.join("curl.argv");
    fs::write(
        dir.join("curl"),
        format!(
            "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\" >> '{}'; done\n",
            log.display()
        ),
    )
    .unwrap();
    fs::set_permissions(dir.join("curl"), fs::Permissions::from_mode(0o755)).unwrap();
    let url = "https://github.com/o/r/actions/runs/42";
    let o = Command::new("bash")
        .arg("-e")
        .arg("-c")
        .arg(&script)
        .env(
            "PATH",
            format!(
                "{}:{}",
                dir.display(),
                std::env::var("PATH").unwrap_or_default()
            ),
        )
        .env("RUN_URL", url)
        .env("NTFY_PASSWORD", "pw")
        .output()
        .unwrap();
    assert!(o.status.success(), "fallback failed: {}", text(&o.stderr));
    let argv = read(&log);
    for want in [
        "-fsS",
        "github-actions:pw",
        "https://ntfy.ipv1337.dev",
        &format!(
            "{{\"topic\":\"vitruvian-alerts\",\"title\":\"[ci] notify-ci-issues cannot build\",\"message\":\"rustc could not build tools/ci/src/notify_ci_issues, so CI failures are not being sent. {url}\",\"priority\":5,\"tags\":[\"red_circle\",\"notify-ci-issues\"],\"click\":\"{url}\"}}"
        ),
    ] {
        assert!(argv.lines().any(|l| l == want), "curl was not given {want:?}:\n{argv}");
    }
}
