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

//! Tests for ./.github/actions/build-ci-tool, the one place a workflow or
//! composite action compiles a tools/ci Rust tool with the runner's rustc
//! (steps that run before Bazel is set up, or without it).
//!
//! The build step's `run:` block is read out of action.yml and run VERBATIM
//! under `bash --noprofile --norc -eo pipefail`, as GitHub runs it, with the
//! Bazel toolchain's own rustc first on PATH, for every tool any workflow
//! asks it to build. Each result is then run beside the Bazel-built
//! //tools/ci:<tool> on the same input and must answer the same. So a change
//! to those command lines, or a tool that stops building from lib.rs +
//! main.rs + shell_compat alone, fails here rather than in a lane.
//!
//! It also holds the wiring the old llvm-cache-key-test workflow checked: the
//! LLVM cache composites derive the key with //tools/ci:llvm_cache_key and
//! move the toolchain with //tools/ci:llvm_cache_stage, and nothing pins the
//! content-hash folder Bazel extracts into (#2242, #2456).

use ci_testkit::{read, workflow_job_text, write, Output, Run, TempDir};
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

const ACTION: &str = ".github/actions/build-ci-tool/action.yml";

/// Every tool a workflow or action builds through build-ci-tool. The BUILD
/// file gives this test each one's sources and Bazel binary (BIN_<tool>).
const TOOLS: &[&str] = &[
    "agent_fast_lane",
    "llvm_cache_key",
    "llvm_cache_stage",
    "queue_fast_pass",
    "queue_runner_watch",
    "relevant_paths",
];

/// The scripts these tools replaced; nothing may run them any more.
const RETIRED: &[&str] = &[
    "tools/ci/agent-fast-lane.sh",
    "tools/ci/llvm-cache-key.sh",
    "tools/ci/llvm-cache-stage.sh",
    "tools/ci/queue-fast-pass.sh",
    "tools/ci/queue-runner-watch.sh",
    "tools/ci/relevant-paths.sh",
];

fn workspace() -> PathBuf {
    std::fs::canonicalize(".").unwrap()
}

/// The `run: |` block of the step with `id: <id>`, dedented.
fn run_block(yaml: &str, id: &str) -> String {
    let lines: Vec<&str> = yaml.lines().collect();
    let at = lines
        .iter()
        .position(|l| l.trim() == format!("id: {id}"))
        .unwrap_or_else(|| panic!("no step with id {id}"));
    let start = lines[at..]
        .iter()
        .position(|l| l.trim() == "run: |")
        .map(|i| at + i + 1)
        .expect("the step has a `run: |` block");
    let indent = lines[start].len() - lines[start].trim_start().len();
    let mut out = String::new();
    for l in &lines[start..] {
        if !l.trim().is_empty() && l.len() - l.trim_start().len() < indent {
            break;
        }
        out.push_str(l.get(indent..).unwrap_or(""));
        out.push('\n');
    }
    out
}

fn build_script() -> String {
    run_block(&std::fs::read_to_string(ACTION).unwrap(), "build")
}

/// The Bazel toolchain's rustc, from runfiles (RUSTC is a rootpath).
fn toolchain_rustc() -> PathBuf {
    let rel = std::env::var("RUSTC").expect("RUSTC (the BUILD file passes the toolchain's rustc)");
    std::fs::canonicalize(&rel).unwrap_or_else(|e| panic!("rustc at {rel}: {e}"))
}

struct Step {
    out: Output,
    github_output: String,
}

impl Step {
    fn bin(&self) -> PathBuf {
        let line = self
            .github_output
            .lines()
            .find_map(|l| l.strip_prefix("bin="))
            .unwrap_or_else(|| {
                panic!(
                    "no bin= in GITHUB_OUTPUT: {:?} {:?}",
                    self.github_output, self.out
                )
            });
        PathBuf::from(line)
    }
}

/// Run the build step as GitHub would: its env, its working directory (the
/// workspace), RUNNER_TEMP and GITHUB_OUTPUT. `path` is the whole PATH.
fn run_step(tmp: &TempDir, workspace: &Path, tool: &str, source_root: &str, path: &str) -> Step {
    let script = tmp.join("step.sh");
    write(&script, build_script());
    let runner_temp = tmp.join("runner-temp");
    std::fs::create_dir_all(&runner_temp).unwrap();
    let gho = tmp.join("github-output");
    write(&gho, "");
    let out = Run::new(Path::new("/bin/bash"))
        .args(["--noprofile", "--norc", "-eo", "pipefail"])
        .arg(&script)
        .cwd(workspace)
        .env("TOOL", tool)
        .env("SOURCE_ROOT", source_root)
        .env("GITHUB_WORKSPACE", workspace)
        .env("RUNNER_TEMP", &runner_temp)
        .env("GITHUB_OUTPUT", &gho)
        .env("PATH", path)
        .go();
    Step {
        out,
        github_output: read(&gho),
    }
}

/// PATH with the toolchain's rustc first (as `rustc`), then the test's own.
fn path_with_rustc(tmp: &TempDir) -> String {
    let dir = tmp.join("rustc-bin");
    std::fs::create_dir_all(&dir).unwrap();
    let link = dir.join("rustc");
    if !link.exists() {
        std::os::unix::fs::symlink(toolchain_rustc(), &link).unwrap();
    }
    ci_testkit::path_with(&dir)
}

/// One invocation per tool, answered the same by both builds.
fn smoke(bin: &Path, tool: &str, cwd: &Path) -> Output {
    let r = Run::new(bin)
        .cwd(cwd)
        .env_remove("GITHUB_REPOSITORY")
        .env_remove("REPO")
        .env_remove("RUN_ID")
        .env_remove("BEFORE_REV")
        .env_remove("BASE_REF");
    match tool {
        "agent_fast_lane" => r.env("EVENT_NAME", "push"),
        "llvm_cache_key" => r.args(["Linux", "0123abcd", "/nonexistent/os-release"]),
        "llvm_cache_stage" => r.args(["live", "/nonexistent/contents"]),
        "queue_fast_pass" => r.arg("nonsense"),
        "queue_runner_watch" => r,
        "relevant_paths" => r,
        other => panic!("no smoke invocation for {other}; add one"),
    }
    .go()
}

#[test]
fn the_build_step_builds_every_tool_with_a_real_rustc_and_it_matches_bazel() {
    let ws = workspace();
    for tool in TOOLS {
        let tmp = TempDir::new();
        let path = path_with_rustc(&tmp);
        let step = run_step(&tmp, &ws, tool, "", &path);
        assert_eq!(
            step.out.code, 0,
            "{tool}: the build step failed: {:?}",
            step.out
        );
        let built = step.bin();
        assert!(built.is_file(), "{tool}: no binary at {}", built.display());
        assert!(
            built.starts_with(tmp.join("runner-temp")),
            "{tool}: built outside RUNNER_TEMP: {}",
            built.display()
        );
        let bazel = ci_testkit::bin(&format!("BIN_{tool}"));
        let cwd = TempDir::new();
        let a = smoke(&built, tool, cwd.path());
        let b = smoke(&bazel, tool, cwd.path());
        assert_eq!(
            (a.code, &a.stdout),
            (b.code, &b.stdout),
            "{tool}: the rustc build and //tools/ci:{tool} answer differently\nrustc: {a:?}\nbazel: {b:?}"
        );
    }
}

/// The fast-lane steps build from a checkout of the base commit: a relative
/// source-root, resolved against the workspace like the composite's own
/// working directory.
#[test]
fn source_root_builds_from_another_checkout() {
    let tmp = TempDir::new();
    let ws = tmp.join("ws");
    for f in [
        "tools/shell-compat/src/lib.rs",
        "tools/ci/src/agent_fast_lane/lib.rs",
        "tools/ci/src/agent_fast_lane/main.rs",
    ] {
        write(ws.join("base").join(f), std::fs::read(f).unwrap());
    }
    let path = path_with_rustc(&tmp);
    let step = run_step(&tmp, &ws, "agent_fast_lane", "base", &path);
    assert_eq!(step.out.code, 0, "{:?}", step.out);
    let o = smoke(&step.bin(), "agent_fast_lane", ws.as_path());
    assert!(o.stdout.contains("verdict=full"), "{o:?}");
}

#[test]
fn a_tool_name_that_is_not_a_crate_name_fails_before_building() {
    let ws = workspace();
    for bad in ["", "../agent_fast_lane", "agent-fast-lane", "x y"] {
        let tmp = TempDir::new();
        let path = path_with_rustc(&tmp);
        let step = run_step(&tmp, &ws, bad, "", &path);
        assert_ne!(step.out.code, 0, "accepted tool {bad:?}");
        assert!(
            step.out
                .stdout
                .contains("::error::build-ci-tool: tool must be"),
            "{bad:?}: {:?}",
            step.out
        );
        assert!(
            !step.github_output.contains("bin="),
            "{bad:?} produced a bin"
        );
    }
}

#[test]
fn no_rustc_fails_with_an_error_naming_the_tool() {
    let ws = workspace();
    let tmp = TempDir::new();
    let empty = tmp.join("empty");
    std::fs::create_dir_all(&empty).unwrap();
    let step = run_step(
        &tmp,
        &ws,
        "relevant_paths",
        "",
        &empty.display().to_string(),
    );
    assert_ne!(step.out.code, 0, "{:?}", step.out);
    assert!(
        step.out.stdout.contains("::error::build-ci-tool: no rustc"),
        "{:?}",
        step.out
    );
    assert!(
        step.out.stdout.contains("tools/ci/src/relevant_paths"),
        "{:?}",
        step.out
    );
}

#[test]
fn a_failed_compile_fails_the_step() {
    let tmp = TempDir::new();
    let ws = tmp.join("ws");
    write(
        ws.join("tools/shell-compat/src/lib.rs"),
        std::fs::read("tools/shell-compat/src/lib.rs").unwrap(),
    );
    write(
        ws.join("tools/ci/src/agent_fast_lane/lib.rs"),
        "pub fn run(: i32 {}\n",
    );
    write(
        ws.join("tools/ci/src/agent_fast_lane/main.rs"),
        std::fs::read("tools/ci/src/agent_fast_lane/main.rs").unwrap(),
    );
    let path = path_with_rustc(&tmp);
    let step = run_step(&tmp, &ws, "agent_fast_lane", "", &path);
    assert_ne!(step.out.code, 0, "a broken lib.rs built: {:?}", step.out);
    assert!(
        !step.github_output.contains("bin="),
        "a failed build still set bin="
    );
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
fn every_tool_a_workflow_builds_is_one_this_test_builds() {
    let mut used = BTreeSet::new();
    for f in yaml_files() {
        for t in tools_built_in(&std::fs::read_to_string(&f).unwrap()) {
            assert!(
                TOOLS.contains(&t.as_str()),
                "{} builds tool {t}, which this test does not build: add it to TOOLS and to the test's data and env in tools/ci/BUILD",
                f.display()
            );
            used.insert(t);
        }
    }
    let all: BTreeSet<String> = TOOLS.iter().map(|s| s.to_string()).collect();
    assert_eq!(used, all, "TOOLS lists a tool nothing builds any more");
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
        a.contains("KEY_BIN: ${{ steps.key-tool.outputs.bin }}"),
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
        a.contains(r#"echo "LLVM_CACHE_STAGE_BIN=$STAGE_BIN" >> "$GITHUB_ENV""#),
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
    let first_use = t.find(r#""$STAGE_BIN""#).expect("a use of the stage tool");
    assert!(
        outcome < first_use,
        "{TRIPWIRE} uses the stage tool before checking the restore ran"
    );
}
