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

/// The `deps:` each caller passes with a tool (empty when it passes none).
fn caller_deps() -> std::collections::BTreeMap<String, String> {
    let mut deps = std::collections::BTreeMap::new();
    for dir in [".github/workflows", ".github/actions"] {
        for e in fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            let f = if p.is_dir() { p.join("action.yml") } else { p };
            if !f.exists() {
                continue;
            }
            let text = read(&f);
            let lines: Vec<&str> = text.lines().collect();
            for (i, l) in lines.iter().enumerate() {
                if l.trim().trim_start_matches("- ") != USES {
                    continue;
                }
                let near: Vec<&str> = lines[i + 1..].iter().take(4).map(|n| n.trim()).collect();
                let tool = near.iter().find_map(|n| n.strip_prefix("tool: ")).unwrap();
                let d = near
                    .iter()
                    .find_map(|n| n.strip_prefix("deps: "))
                    .unwrap_or("");
                deps.insert(tool.trim().to_string(), d.trim().to_string());
            }
        }
    }
    deps
}

/// The std-only crates the action's `deps` input may name, at their paths.
const DEP_SOURCES: &[&str] = &[
    "tools/ci/src/transient_lib/lib.rs",
    "tools/gitops/appset-render/src",
];

/// A copy of the sources the step reads, laid out as in a checkout.
fn workspace(tools: &BTreeSet<String>) -> PathBuf {
    let ws = tmp();
    let copy = |rel: &str| {
        let dst = ws.join(rel);
        fs::create_dir_all(dst.parent().unwrap()).unwrap();
        fs::copy(rel, &dst).unwrap_or_else(|e| panic!("copy {rel}: {e}"));
    };
    copy("tools/shell-compat/src/lib.rs");
    for d in DEP_SOURCES {
        if Path::new(d).is_dir() {
            for e in fs::read_dir(d).unwrap() {
                copy(&e.unwrap().path().display().to_string());
            }
        } else {
            copy(d);
        }
    }
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
    run_step_deps(script, tool, "", ws, runner_temp, shim)
}

fn run_step_deps(
    script: &str,
    tool: &str,
    deps: &str,
    ws: &Path,
    runner_temp: &Path,
    shim: &Path,
) -> Step {
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
        .env("DEPS", deps)
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
    // A tool that names itself in a message (as bash names $0, e.g. "<path>:
    // line 49: git: command not found") does so by the path it was run from,
    // which differs between the two builds by construction.
    let me = bin.display().to_string();
    let scrub = |b: &[u8]| text(b).replace(&me, "<bin>");
    (o.status.code(), scrub(&o.stdout), scrub(&o.stderr))
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
    let deps = caller_deps();
    for t in &tools {
        let s = run_step_deps(&script, t, &deps[t], &ws, &runner_temp, &shim);
        assert!(
            s.out.status.success(),
            "building {t} failed ({:?})\nstdout:\n{}\nstderr:\n{}",
            s.out.status,
            text(&s.out.stdout),
            text(&s.out.stderr)
        );
        assert!(
            text(&s.out.stdout).lines().any(|l| l.starts_with("rustc ")),
            "{t}: the step must log `rustc --version`:\n{}",
            text(&s.out.stdout)
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

/// The `run: |` block of the step whose `- name:` line is at `name`, dedented.
fn run_block(lines: &[&str], name: usize) -> String {
    let run = (name..lines.len())
        .find(|&i| lines[i].trim() == "run: |")
        .expect("the step has a `run: |` block");
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
    body.iter()
        .map(|l| format!("{}\n", l.get(pad..).unwrap_or("")))
        .collect()
}

/// The lines of the step whose `- name:` line is at `name`.
fn step_lines<'a>(lines: &[&'a str], name: usize) -> Vec<&'a str> {
    let key = indent(lines[name]);
    let mut v = vec![lines[name]];
    v.extend(
        lines[name + 1..]
            .iter()
            .take_while(|l| l.trim().is_empty() || indent(l) > key)
            .copied(),
    );
    v
}

fn exe(path: &Path, body: &str) {
    fs::write(path, body).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn a_rustc_that_succeeds_without_a_binary_fails_the_step() {
    // A swallowed rustc error (or any build that leaves nothing behind) must
    // not hand on a path: the caller would run a missing file AFTER this step
    // reported success, and the `if: failure()` fallbacks would never fire.
    let script = build_script(&read(ACTION));
    let tools: BTreeSet<String> = ["release_hold".to_string()].into_iter().collect();
    let ws = workspace(&tools);
    let shim = tmp();
    exe(
        &shim.join("rustc"),
        "#!/bin/sh\n[ \"$1\" = --version ] && { echo 'rustc 9.9.9-fake'; exit 0; }\nexit 0\n",
    );
    let runner_temp = tmp();
    let s = run_step(&script, "release_hold", &ws, &runner_temp, &shim);
    assert_eq!(s.out.status.code(), Some(1), "{:?}", s.out);
    assert!(
        text(&s.out.stdout).contains("::error::build-ci-tool: rustc reported success but"),
        "no ::error annotation:\n{}",
        text(&s.out.stdout)
    );
    assert!(
        text(&s.out.stdout).contains("rustc 9.9.9-fake"),
        "version not logged"
    );
    assert_eq!(s.github_output, "", "no path output without a binary");
}

#[test]
fn a_broken_main_rs_fails_the_step_and_sets_no_output() {
    let script = build_script(&read(ACTION));
    let tools: BTreeSet<String> = ["release_hold".to_string()].into_iter().collect();
    let ws = workspace(&tools);
    fs::write(
        ws.join("tools/ci/src/release_hold/main.rs"),
        "fn main() { nope }\n",
    )
    .unwrap();
    let s = run_step(&script, "release_hold", &ws, &tmp(), &rustc_shim());
    assert!(
        !s.out.status.success(),
        "a failed main.rs build must fail the step"
    );
    assert_eq!(s.github_output, "", "no path output for a failed build");
}

#[test]
fn every_caller_runs_the_variable_its_build_step_sets() {
    // A run line reading a misnamed variable passes actionlint and exits 127
    // on a runner. For each build-ci-tool step id, every env var set from its
    // `path` output must be read as "$VAR" or "${VAR}" in the same file.
    let mut checked = 0;
    for dir in [".github/workflows", ".github/actions"] {
        for e in fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            let f = if p.is_dir() { p.join("action.yml") } else { p };
            if !f.exists() {
                continue;
            }
            let text = read(&f);
            let lines: Vec<&str> = text.lines().collect();
            for (i, l) in lines.iter().enumerate() {
                if l.trim().trim_start_matches("- ") != USES {
                    continue;
                }
                let id = lines[..i]
                    .iter()
                    .rev()
                    .take(4)
                    .find_map(|n| n.trim().strip_prefix("id: "))
                    .unwrap_or_else(|| {
                        panic!(
                            "{}:{}: a build-ci-tool step needs an id",
                            f.display(),
                            i + 1
                        )
                    });
                let output = format!("${{{{ steps.{id}.outputs.path }}}}");
                let vars: Vec<&str> = lines
                    .iter()
                    .filter_map(|l| {
                        let (k, v) = l.trim().split_once(": ")?;
                        (v == output).then_some(k)
                    })
                    .collect();
                assert!(!vars.is_empty(), "{}: nothing reads {output}", f.display());
                for v in vars {
                    let used =
                        text.contains(&format!("\"${v}\"")) || text.contains(&format!("${{{v}}}"));
                    assert!(
                        used,
                        "{}: {v} is set from {output} but no run line reads \"${v}\" or ${{{v}}}",
                        f.display()
                    );
                    checked += 1;
                }
            }
        }
    }
    assert!(checked >= 8, "only {checked} callers checked");
}

/// Bazel's jq (from $JQ_BIN, an exec path the runfiles tree spells `../`).
fn jq() -> PathBuf {
    let raw = std::env::var("JQ_BIN").expect("JQ_BIN is set by BUILD");
    let rel = match raw.strip_prefix("external/") {
        Some(rest) => format!("../{rest}"),
        None => raw,
    };
    fs::canonicalize(&rel).unwrap_or_else(|e| panic!("JQ_BIN={rel}: {e}"))
}

/// A fake gh for the beta gate's fallback. `pr list` logs each argument on
/// its own line, then answers like gh: $FAKE_JSON (what GitHub returns)
/// filtered through the step's OWN `--jq` expression with Bazel's jq, so the
/// filter's logic is what is tested, not its spelling. `pr merge` is logged.
const FALLBACK_GH: &str = r#"#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "pr list")
    for a in "$@"; do printf '%s\n' "$a"; done >> "$GH_ARGV"
    [ -n "${FAKE_LIST_RC:-}" ] && { echo "gh: boom (HTTP 502)" >&2; exit "$FAKE_LIST_RC"; }
    expr=""; prev=""
    for a in "$@"; do [ "$prev" = --jq ] && expr="$a"; prev="$a"; done
    [ -n "$expr" ] || { echo "fake gh: no --jq" >&2; exit 98; }
    printf '%s' "$FAKE_JSON" | "$JQ" -r "$expr"
    ;;
  "pr merge") exit "${FAKE_MERGE_RC:-0}" ;;
  *) echo "unexpected gh $*" >&2; exit 99 ;;
esac
"#;

/// The exact `gh pr list` the fallback must run, one argument a line: the
/// gate's own branch, open PRs only, and a filter that skips forks and reports
/// whether auto-merge is armed.
const FALLBACK_LIST_ARGV: &str = "pr\nlist\n--repo\no/r\n--head\nrelease-please--branches--main--components--vitruvian\n--state\nopen\n--json\nnumber,autoMergeRequest,isCrossRepository\n--jq\nmap(select(.isCrossRepository | not)) | .[0] // empty | \"\\(.number) \\(.autoMergeRequest != null)\"\n";

#[test]
fn a_beta_gate_that_cannot_run_turns_auto_merge_off() {
    let wf = read(".github/workflows/release-beta-gate.yaml");
    let lines: Vec<&str> = wf.lines().collect();
    let name = lines
        .iter()
        .position(|l| l.trim() == "- name: Turn auto-merge off when the gate could not decide")
        .expect("release-beta-gate.yaml has the auto-merge-off fallback");
    let gate = lines
        .iter()
        .position(|l| l.trim() == "- name: Gate vitruvian's release PR on the beta DMG")
        .expect("the gate step");
    let build = lines
        .iter()
        .position(|l| l.trim() == "id: gate-bin")
        .expect("the gate's build step");
    assert!(
        build < gate && gate < name,
        "build, gate, then the fallback"
    );
    let step = step_lines(&lines, name);
    assert!(
        step.iter()
            .any(|l| l.trim() == "if: ${{ failure() || cancelled() }}"),
        "the fallback runs whenever the job failed, was cancelled or timed out:\n{}",
        step.join("\n")
    );
    assert!(
        step.iter().any(|l| l.trim() == "COMPONENT: vitruvian"),
        "same component as the gate"
    );
    let script = run_block(&lines, name);
    let jq = jq();

    let run = |json: &str, extra: &[(&str, &str)]| {
        let dir = tmp();
        exe(&dir.join("gh"), FALLBACK_GH);
        let log = dir.join("gh.log");
        let argv = dir.join("gh.argv");
        fs::write(&log, "").unwrap();
        fs::write(&argv, "").unwrap();
        let mut c = Command::new("bash");
        c.arg("-e")
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
            .env("GH_LOG", &log)
            .env("GH_ARGV", &argv)
            .env("JQ", &jq)
            .env("REPO", "o/r")
            .env("COMPONENT", "vitruvian")
            .env("FAKE_JSON", json);
        for (k, v) in extra {
            c.env(k, v);
        }
        let o = c.output().unwrap();
        (o, read(&log), read(&argv))
    };
    let pr = |n: u32, armed: bool, fork: bool| {
        let am = if armed {
            r#"{"enabledAt":"2026-11-01T00:00:00Z"}"#
        } else {
            "null"
        };
        format!(r#"{{"number":{n},"autoMergeRequest":{am},"isCrossRepository":{fork}}}"#)
    };
    let merged = |log: &str| {
        log.lines()
            .filter(|l| l.starts_with("pr merge"))
            .map(String::from)
            .collect::<Vec<_>>()
    };

    // Armed: the exact lookup, then turned off, loudly.
    let (o, log, argv) = run(&format!("[{}]", pr(42, true, false)), &[]);
    assert!(o.status.success(), "{}", text(&o.stderr));
    assert_eq!(
        argv, FALLBACK_LIST_ARGV,
        "the gh pr list command, argument for argument"
    );
    assert_eq!(
        merged(&log),
        ["pr merge 42 --repo o/r --disable-auto"],
        "{log}"
    );
    assert!(text(&o.stdout)
        .contains("::error title=release-beta-gate could not run::turned auto-merge off on #42"));

    // A fork's PR on the same branch name is never the release PR: the
    // repository's own one is the one turned off.
    let (o, log, _) = run(
        &format!("[{},{}]", pr(7, true, true), pr(42, true, false)),
        &[],
    );
    assert!(o.status.success(), "{}", text(&o.stderr));
    assert_eq!(
        merged(&log),
        ["pr merge 42 --repo o/r --disable-auto"],
        "fork skipped: {log}"
    );
    let (o, log, _) = run(&format!("[{}]", pr(7, true, true)), &[]);
    assert!(o.status.success(), "{}", text(&o.stderr));
    assert_eq!(
        merged(&log),
        Vec::<String>::new(),
        "only a fork's PR: nothing to turn off: {log}"
    );

    // Already off, or no PR: nothing to do, and it says so.
    let (o, log, _) = run(&format!("[{}]", pr(42, false, false)), &[]);
    assert!(o.status.success(), "{}", text(&o.stderr));
    assert_eq!(merged(&log), Vec::<String>::new(), "not armed: {log}");
    assert!(
        text(&o.stdout).contains("Auto-merge is already off on #42."),
        "{}",
        text(&o.stdout)
    );
    let (o, log, _) = run("[]", &[]);
    assert!(o.status.success(), "{}", text(&o.stderr));
    assert_eq!(merged(&log), Vec::<String>::new(), "no PR: {log}");
    assert!(
        text(&o.stdout).contains("No open release PR on"),
        "{}",
        text(&o.stdout)
    );

    // A failed lookup or a refused disable fails the step: red, never quiet.
    let (o, _, _) = run("[]", &[("FAKE_LIST_RC", "1")]);
    assert!(!o.status.success(), "a failed lookup must fail the step");
    let (o, _, _) = run(
        &format!("[{}]", pr(42, true, false)),
        &[("FAKE_MERGE_RC", "1")],
    );
    assert!(!o.status.success(), "a refused disable must fail the step");
}

#[test]
fn a_built_file_that_is_not_executable_fails_the_step() {
    // A rustc that writes its -o file without the execute bit: there is a
    // file, but nothing a caller can run.
    let script = build_script(&read(ACTION));
    let tools: BTreeSet<String> = ["release_hold".to_string()].into_iter().collect();
    let ws = workspace(&tools);
    let shim = tmp();
    exe(
        &shim.join("rustc"),
        "#!/bin/sh\n[ \"$1\" = --version ] && { echo 'rustc 9.9.9-fake'; exit 0; }\nprev=''\nfor a in \"$@\"; do [ \"$prev\" = -o ] && o=\"$a\"; prev=\"$a\"; done\n: > \"$o\"\nchmod 644 \"$o\"\n",
    );
    let runner_temp = tmp();
    let s = run_step(&script, "release_hold", &ws, &runner_temp, &shim);
    assert!(
        runner_temp.join("ci-tools/release_hold").is_file(),
        "the shim wrote the file"
    );
    assert_eq!(s.out.status.code(), Some(1), "{:?}", s.out);
    assert!(
        text(&s.out.stdout).contains("is not an executable file"),
        "no ::error annotation:\n{}",
        text(&s.out.stdout)
    );
    assert_eq!(
        s.github_output, "",
        "no path output for a file that cannot run"
    );
}

#[test]
fn an_unknown_dep_is_refused_before_rustc() {
    let script = build_script(&read(ACTION));
    let ws = tmp();
    let shim = tmp();
    let called = shim.join("called");
    fs::write(
        shim.join("rustc"),
        format!("#!/bin/sh\ntouch '{}'\nexit 0\n", called.display()),
    )
    .unwrap();
    fs::set_permissions(shim.join("rustc"), fs::Permissions::from_mode(0o755)).unwrap();
    for bad in [
        "serde",
        "../transient_lib",
        "transient_lib shell_compat",
        "transient-lib",
    ] {
        let s = run_step_deps(&script, "go_test_with_retry", bad, &ws, &tmp(), &shim);
        assert_eq!(s.out.status.code(), Some(1), "deps {bad:?} must be refused");
        assert!(
            text(&s.out.stdout).contains("::error::build-ci-tool: unknown dep"),
            "deps {bad:?}:\n{}",
            text(&s.out.stdout)
        );
        assert!(!called.exists(), "deps {bad:?} reached rustc");
        assert_eq!(s.github_output, "");
    }
}

#[test]
fn a_dep_that_does_not_build_fails_the_step() {
    let script = build_script(&read(ACTION));
    let tools: BTreeSet<String> = ["go_test_with_retry".to_string()].into_iter().collect();
    let ws = workspace(&tools);
    fs::write(ws.join("tools/ci/src/transient_lib/lib.rs"), "not rust\n").unwrap();
    let s = run_step_deps(
        &script,
        "go_test_with_retry",
        "transient_lib",
        &ws,
        &tmp(),
        &rustc_shim(),
    );
    assert!(
        !s.out.status.success(),
        "a dep that fails to build must fail the step"
    );
    assert_eq!(s.github_output, "");
}

#[test]
fn a_tool_built_without_its_dep_fails_the_step() {
    // The caller's `deps:` is load-bearing: drop it and the lib cannot resolve
    // the crate, so the step fails rather than producing something else.
    let script = build_script(&read(ACTION));
    let tools: BTreeSet<String> = ["go_test_with_retry".to_string()].into_iter().collect();
    let ws = workspace(&tools);
    let s = run_step_deps(
        &script,
        "go_test_with_retry",
        "",
        &ws,
        &tmp(),
        &rustc_shim(),
    );
    assert!(!s.out.status.success(), "{}", text(&s.out.stderr));
}

/// The changed-paths gate, the LLVM cache composites, the merge-queue lookup,
/// the fast lanes and the queue-runner watcher (#4173): building from another
/// checkout, refusing a runner with no rustc or a binary that will not start,
/// which files each caller's checkout must hold, and the LLVM cache wiring the
/// former llvm-cache-key-test workflow checked (#2242, #2456).
mod callers_and_wiring {
    use super::{build_script, exe, read, rustc_shim, text, tmp, workspace, ACTION};
    use ci_testkit::workflow_job_text;
    use std::collections::BTreeSet;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    /// The scripts these tools replaced; nothing may run them any more.
    const RETIRED: &[&str] = &[
        "tools/ci/agent-fast-lane.sh",
        "tools/ci/llvm-cache-key.sh",
        "tools/ci/llvm-cache-stage.sh",
        "tools/ci/queue-fast-pass.sh",
        "tools/ci/queue-runner-watch.sh",
        "tools/ci/relevant-paths.sh",
    ];

    /// Run the build step as GitHub does, with SOURCE_ROOT and PATH chosen.
    fn step(
        tool: &str,
        ws: &Path,
        source_root: &str,
        path: &str,
    ) -> (std::process::Output, String) {
        let gho = tmp().join("github_output");
        std::fs::write(&gho, "").unwrap();
        let out = Command::new("/bin/bash")
            .arg("-e")
            .arg("-c")
            .arg(build_script(&read(ACTION)))
            .env("TOOL", tool)
            .env("SOURCE_ROOT", source_root)
            .env("GITHUB_WORKSPACE", ws)
            .env("RUNNER_TEMP", tmp())
            .env("GITHUB_OUTPUT", &gho)
            .env("PATH", path)
            .current_dir(ws)
            .output()
            .expect("run bash");
        let o = read(&gho);
        (out, o)
    }

    fn path_first(dir: &Path) -> String {
        format!(
            "{}:{}",
            dir.display(),
            std::env::var("PATH").unwrap_or_default()
        )
    }

    /// The fast lanes build from a checkout of the base commit: a relative
    /// source-root, resolved against the workspace like the composite's own
    /// working directory. The workspace itself holds no sources here, so the
    /// build can only have read the base copy.
    #[test]
    fn source_root_builds_from_another_checkout() {
        let tools: BTreeSet<String> = ["agent_fast_lane".to_string()].into_iter().collect();
        let base = workspace(&tools);
        let ws = tmp();
        std::os::unix::fs::symlink(&base, ws.join("base")).unwrap();
        let (out, gho) = step("agent_fast_lane", &ws, "base", &path_first(&rustc_shim()));
        assert!(
            out.status.success(),
            "{}{}",
            text(&out.stdout),
            text(&out.stderr)
        );
        let bin = PathBuf::from(gho.trim().strip_prefix("path=").expect("path= output"));
        let o = Command::new(&bin)
            .env_clear()
            .env("EVENT_NAME", "push")
            .output()
            .unwrap();
        assert!(text(&o.stdout).contains("verdict=full"), "{o:?}");
    }

    #[test]
    fn no_rustc_fails_with_an_error_naming_the_tool() {
        let ws = tmp();
        let empty = tmp();
        let (out, gho) = step("relevant_paths", &ws, "", &empty.display().to_string());
        assert_eq!(out.status.code(), Some(1), "{out:?}");
        let so = text(&out.stdout);
        // The step first tries apt (the homelab queue runner's image has no
        // Rust); with nothing on PATH that fails too, and the error names both
        // the missing rustc and the tool.
        assert!(so.contains("::error::"), "{so}");
        assert!(so.contains("no rustc on this runner"), "{so}");
        assert!(so.contains("tools/ci/src/relevant_paths"), "{so}");
        assert_eq!(gho, "", "no rustc, no path output");
    }

    /// A file that is there and executable but is not a program: the step's
    /// start check must refuse it, or the caller runs it AFTER the step
    /// reported success.
    #[test]
    fn a_binary_that_does_not_start_fails_the_step_and_sets_no_output() {
        let tools: BTreeSet<String> = ["relevant_paths".to_string()].into_iter().collect();
        let ws = workspace(&tools);
        let shim = tmp();
        exe(
            &shim.join("rustc"),
            "#!/bin/sh\n[ \"$1\" = --version ] && { echo 'rustc 9.9.9-fake'; exit 0; }\nprev=''\nfor a in \"$@\"; do [ \"$prev\" = -o ] && o=\"$a\"; prev=\"$a\"; done\nprintf 'not a program' > \"$o\"\nchmod 755 \"$o\"\n",
        );
        let (out, gho) = step("relevant_paths", &ws, "", &path_first(&shim));
        assert_eq!(out.status.code(), Some(1), "{out:?}");
        assert!(
            text(&out.stdout).contains("was built but does not run"),
            "{}",
            text(&out.stdout)
        );
        assert_eq!(gho, "", "no path output for a binary that cannot start");
    }

    /// A workspace whose one tool `probe_tool` runs `body` as its main.
    fn native_tool(body: &str) -> PathBuf {
        let ws = tmp();
        let d = ws.join("tools/ci/src/probe_tool");
        std::fs::create_dir_all(&d).unwrap();
        std::fs::create_dir_all(ws.join("tools/shell-compat/src")).unwrap();
        std::fs::copy(
            "tools/shell-compat/src/lib.rs",
            ws.join("tools/shell-compat/src/lib.rs"),
        )
        .unwrap();
        std::fs::write(d.join("lib.rs"), "pub fn run() {}\n").unwrap();
        std::fs::write(
            d.join("main.rs"),
            format!("fn main() {{ probe_tool::run(); {body} }}\n"),
        )
        .unwrap();
        ws
    }

    /// secret_scan runs git before anything else, as its script did, so on
    /// the probe's empty PATH it exits 127 itself. A native binary that ran
    /// and chose 127 has started; only env's own 127 means it did not.
    #[test]
    fn a_native_tool_that_exits_127_itself_counts_as_started() {
        let ws = native_tool("std::process::exit(127);");
        let (out, gho) = step("probe_tool", &ws, "", &path_first(&rustc_shim()));
        assert!(
            out.status.success(),
            "{}{}",
            text(&out.stdout),
            text(&out.stderr)
        );
        assert!(gho.starts_with("path="), "{gho}");
    }

    #[test]
    fn a_native_tool_that_dies_on_a_signal_fails_the_step() {
        let ws = native_tool("std::process::abort();");
        let (out, gho) = step("probe_tool", &ws, "", &path_first(&rustc_shim()));
        assert_eq!(out.status.code(), Some(1), "{out:?}");
        assert!(
            text(&out.stdout).contains("was built but does not run"),
            "{}",
            text(&out.stdout)
        );
        assert_eq!(gho, "");
    }

    // --- who uses it, and what they check out

    fn yaml_files() -> Vec<PathBuf> {
        let mut v = Vec::new();
        for e in std::fs::read_dir(".github/workflows").unwrap().flatten() {
            v.push(e.path());
        }
        for e in std::fs::read_dir(".github/actions").unwrap().flatten() {
            let a = e.path().join("action.yml");
            if a.is_file() {
                v.push(a);
            }
        }
        v.sort();
        v
    }

    /// The `tool:` values passed to build-ci-tool in one file.
    fn tools_built_in(text: &str) -> Vec<String> {
        let lines: Vec<&str> = text.lines().collect();
        let mut tools = Vec::new();
        for (i, l) in lines.iter().enumerate() {
            if l.trim() != "uses: ./.github/actions/build-ci-tool" {
                continue;
            }
            for m in &lines[i + 1..] {
                let t = m.trim();
                if t.starts_with("- ") {
                    break;
                }
                if let Some(v) = t.strip_prefix("tool: ") {
                    tools.push(v.to_string());
                }
            }
        }
        tools
    }

    #[test]
    fn no_workflow_or_action_runs_a_retired_script() {
        let mut hits = Vec::new();
        for f in yaml_files() {
            let text = std::fs::read_to_string(&f).unwrap();
            for (n, l) in text.lines().enumerate() {
                for s in RETIRED {
                    if l.contains(s) {
                        hits.push(format!("{}:{}: {}", f.display(), n + 1, l.trim()));
                    }
                }
            }
        }
        assert!(
            hits.is_empty(),
            "these scripts are gone:\n{}",
            hits.join("\n")
        );
    }

    /// A step's text and the indented `key: value` lines it carries.
    struct StepText(String);

    impl StepText {
        fn get(&self, key: &str) -> Option<String> {
            self.0.lines().find_map(|l| {
                l.trim()
                    .strip_prefix(&format!("{key}: "))
                    .map(|v| v.to_string())
            })
        }
        /// The sparse-checkout entries, or None for a full checkout.
        fn sparse(&self) -> Option<Vec<String>> {
            let lines: Vec<&str> = self.0.lines().collect();
            let i = lines
                .iter()
                .position(|l| l.trim().starts_with("sparse-checkout:"))?;
            let v = lines[i]
                .trim()
                .trim_start_matches("sparse-checkout:")
                .trim();
            if v != "|" {
                return Some(vec![v.to_string()]);
            }
            let indent = lines[i].len() - lines[i].trim_start().len();
            Some(
                lines[i + 1..]
                    .iter()
                    .take_while(|l| l.len() - l.trim_start().len() > indent && !l.trim().is_empty())
                    .map(|l| l.trim().to_string())
                    .collect(),
            )
        }
    }

    fn steps(job: &str) -> Vec<StepText> {
        let mut out: Vec<StepText> = Vec::new();
        for l in job.lines() {
            if l.starts_with("      - ") {
                out.push(StepText(String::new()));
            }
            if let Some(s) = out.last_mut() {
                s.0.push_str(l);
                s.0.push('\n');
            }
        }
        out
    }

    fn covers(entries: &[String], need: &str) -> bool {
        entries
            .iter()
            .any(|e| need == e || need.starts_with(&format!("{}/", e.trim_end_matches('/'))))
    }

    /// A sparse checkout must hold what each build needs: the build action
    /// itself in the workspace, and shell_compat plus the tool's sources in the
    /// checkout it builds from. A missing path only shows up as a failed lane.
    #[test]
    fn sparse_checkouts_hold_what_their_builds_need() {
        // Tools a composite action builds from the workspace.
        let mut via: Vec<(String, Vec<String>)> = Vec::new();
        for e in std::fs::read_dir(".github/actions").unwrap().flatten() {
            let a = e.path().join("action.yml");
            if let Ok(text) = std::fs::read_to_string(&a) {
                let t = tools_built_in(&text);
                if !t.is_empty() {
                    via.push((
                        format!(
                            "uses: ./.github/actions/{}",
                            e.file_name().to_string_lossy()
                        ),
                        t,
                    ));
                }
            }
        }
        let mut checked = 0;
        let mut bad = Vec::new();
        for e in std::fs::read_dir(".github/workflows").unwrap().flatten() {
            let text = std::fs::read_to_string(e.path()).unwrap();
            let ids: Vec<String> = ci_testkit::workflow_jobs(&text)
                .into_iter()
                .map(|j| j.id)
                .collect();
            for id in ids {
                let job = workflow_job_text(&text, &id);
                let steps = steps(&job);
                let checkout_for = |root: &str| {
                    steps.iter().find(|s| {
                        s.0.contains("uses: actions/checkout@")
                            && s.get("path").unwrap_or_default() == root
                    })
                };
                let mut needs: Vec<(String, String)> = Vec::new(); // (checkout path, file)
                for s in &steps {
                    if s.0.contains("uses: ./.github/actions/build-ci-tool") {
                        let root = s.get("source-root").unwrap_or_default();
                        let tool = s.get("tool").unwrap_or_default();
                        needs.push((
                            String::new(),
                            ".github/actions/build-ci-tool/action.yml".into(),
                        ));
                        needs.push((root.clone(), "tools/shell-compat/src/lib.rs".into()));
                        needs.push((root, format!("tools/ci/src/{tool}/lib.rs")));
                    }
                    for (uses, tools) in &via {
                        if s.0.contains(uses.as_str()) {
                            needs.push((
                                String::new(),
                                ".github/actions/build-ci-tool/action.yml".into(),
                            ));
                            needs.push((String::new(), "tools/shell-compat/src/lib.rs".into()));
                            for t in tools {
                                needs.push((String::new(), format!("tools/ci/src/{t}/lib.rs")));
                            }
                        }
                    }
                }
                for (root, file) in needs {
                    checked += 1;
                    // Fast-lane roots in presubmit come from `git show` into
                    // RUNNER_TEMP, not a checkout; that list is pinned in
                    // agent_fast_lane_test.
                    if root.starts_with("${{") {
                        continue;
                    }
                    match checkout_for(&root) {
                        None => bad.push(format!(
                            "{} job {id}: nothing is checked out at '{root}' for {file}",
                            e.path().display()
                        )),
                        Some(c) => {
                            if let Some(entries) = c.sparse() {
                                if !covers(&entries, &file) {
                                    bad.push(format!(
                                        "{} job {id}: the sparse checkout at '{root}' lacks {file} (has {entries:?})",
                                        e.path().display()
                                    ));
                                }
                            }
                        }
                    }
                }
            }
        }
        assert!(
            checked > 0,
            "found no job that builds a tool; the parser is out of date"
        );
        assert!(bad.is_empty(), "{}", bad.join("\n"));
    }

    // --- the LLVM cache wiring (formerly .github/workflows/llvm-cache-key-test.yaml)

    const RESTORE: &str = ".github/actions/llvm-cache-restore/action.yml";
    const TRIPWIRE: &str = ".github/actions/llvm-cache-tripwire/action.yml";

    /// The composite must actually use the derived key. A copy-paste of the old
    /// inline `llvm-contents-v1-...` expression would pass every key test while
    /// changing nothing in CI.
    #[test]
    fn the_restore_composite_derives_its_key_with_llvm_cache_key() {
        let a = std::fs::read_to_string(RESTORE).unwrap();
        assert!(
            a.contains("tool: llvm_cache_key"),
            "{RESTORE} no longer builds llvm_cache_key"
        );
        assert!(
            a.contains("KEY_BIN: ${{ steps.key-tool.outputs.path }}"),
            "{RESTORE} no longer runs the built key tool"
        );
        assert!(
            a.contains(r#"key=$("$KEY_BIN" "$RUNNER_OS_NAME" "$MODULE_HASH")"#),
            "{RESTORE} no longer derives its key from llvm_cache_key"
        );
        assert!(
            a.contains("key: ${{ steps.key.outputs.value }}"),
            "{RESTORE} does not cache under the derived key"
        );
        for l in a.lines() {
            let t = l.trim();
            assert!(
                !(t.starts_with("key:")
                    && t.trim_start_matches("key:")
                        .trim()
                        .starts_with("llvm-contents-")),
                "{RESTORE} hardcodes a literal cache key: {t}"
            );
        }
    }

    /// ...and nothing pins the folder Bazel extracts into (#2456): that name moves
    /// with the toolchain's definition and goes stale.
    #[test]
    fn no_file_pins_the_llvm_content_hash_folder() {
        for f in yaml_files() {
            let text = std::fs::read_to_string(&f).unwrap();
            let mut from = 0;
            while let Some(i) = text[from..].find("bazel-repo/contents/") {
                let rest = &text[from + i + "bazel-repo/contents/".len()..];
                let hex = rest.bytes().take_while(|b| b.is_ascii_hexdigit()).count();
                assert!(
                    hex < 64,
                    "{} hard-codes an LLVM content-hash folder; //tools/ci:llvm_cache_stage discovers it",
                    f.display()
                );
                from += i + 1;
            }
        }
    }

    #[test]
    fn the_restore_composite_restores_through_llvm_cache_stage_and_exports_it() {
        let a = std::fs::read_to_string(RESTORE).unwrap();
        assert!(
            a.contains("tool: llvm_cache_stage"),
            "{RESTORE} no longer builds llvm_cache_stage"
        );
        assert!(
            a.contains(r#"echo "LLVM_CACHE_STAGE_BIN=${STAGE_BIN}" >> "$GITHUB_ENV""#),
            "{RESTORE} no longer exports LLVM_CACHE_STAGE_BIN for the tripwire"
        );
        assert!(
            a.contains(r#"pin=$("$LLVM_CACHE_STAGE_BIN" restore "$STAGE" "$CONTENTS")"#),
            "{RESTORE} no longer restores through llvm_cache_stage"
        );
    }

    #[test]
    fn the_tripwire_stages_the_toolchain_with_the_exported_tool() {
        let t = std::fs::read_to_string(TRIPWIRE).unwrap();
        assert!(
            t.contains(r#"STAGE_BIN="${LLVM_CACHE_STAGE_BIN:-}""#),
            "{TRIPWIRE} no longer reads LLVM_CACHE_STAGE_BIN"
        );
        assert!(
            t.contains(r#""$STAGE_BIN" live "#),
            "{TRIPWIRE} no longer finds the live toolchain"
        );
        assert!(
            t.contains(r#""$STAGE_BIN" stage "#),
            "{TRIPWIRE} no longer stages the toolchain for saving"
        );
        let tidy = std::fs::read_to_string(".github/workflows/tidy-check.yaml").unwrap();
        assert!(
            tidy.contains(r#""$LLVM_CACHE_STAGE_BIN" live"#),
            "tidy-check no longer compares the live toolchain"
        );
    }

    /// The tripwire runs under `if: always()`; when the restore never ran there
    /// is no stage tool, so the outcome check has to come first or the step dies
    /// on an empty command instead of saying what went wrong.
    #[test]
    fn the_tripwire_checks_the_restore_ran_before_using_its_tool() {
        let t = std::fs::read_to_string(TRIPWIRE).unwrap();
        let outcome = t
            .find(r#"if [ "$RESTORE_OUTCOME" != "success" ]; then"#)
            .expect("outcome check");
        let exists = t
            .find(r#"if [ ! -x "$STAGE_BIN" ]; then"#)
            .expect("the tripwire must check the stage tool exists");
        let first_use = t.find(r#""$STAGE_BIN" "#).expect("a use of the stage tool");
        assert!(
            exists < first_use,
            "{TRIPWIRE} uses the stage tool before checking it exists"
        );
        assert!(
            outcome < first_use,
            "{TRIPWIRE} uses the stage tool before checking the restore ran"
        );
    }
}
