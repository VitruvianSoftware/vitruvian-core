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

//! //tools/ci:workflow_rustc_test. CI jobs that set up no Bazel build their
//! tools/ci binary from the checkout with the runner's `rustc`. This runs every
//! one of those command lines exactly as the workflow or composite action
//! writes it, with the Bazel toolchain's real rustc first on PATH, so a line
//! that no longer compiles (a new crate dependency, a moved file, a typo in an
//! --extern) fails here instead of in the job that needs the tool.
//!
//! A "block" is a run of consecutive lines whose first word is `rustc`. Each
//! block runs in its own `$RUNNER_TEMP` with `bash -euo pipefail`, from the
//! runfiles root standing in for `$GITHUB_WORKSPACE`, and must leave an
//! executable at `$RUNNER_TEMP/<name>`. Every such block in a listed file
//! must be expected below, and every expectation must be found, so a line
//! cannot be dropped, renamed or added without this test noticing.

use std::path::{Path, PathBuf};
use std::process::Command;

/// (file, the binary its block writes to `$RUNNER_TEMP`), in file order.
const EXPECT: &[(&str, &str)] = &[
    // //tools/gomod:check lives outside tools/ci/src, so it does not fit
    // .github/actions/build-ci-tool (which //tools/ci:build_ci_tool_test
    // covers); its three lines stay inline in ci.yaml.
    (".github/workflows/ci.yaml", "tidy"),
];

/// Only blocks that build one of these are this test's business; a listed
/// file may carry other rustc blocks (ci.yaml's homelab test, supply-chain's
/// osv-scan) that other targets own.
const SOURCES: &[&str] = &["tools/ci/src/", "tools/gomod/src/"];

/// The blocks of `text`, each a list of command lines.
fn blocks(text: &str) -> Vec<Vec<String>> {
    let mut out: Vec<Vec<String>> = Vec::new();
    let mut cur: Vec<String> = Vec::new();
    for line in text.lines() {
        let t = line.trim();
        if t.starts_with("rustc ") {
            cur.push(t.to_string());
        } else if !cur.is_empty() {
            out.push(std::mem::take(&mut cur));
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

/// `$(RUSTC)` is an execroot path to the toolchain's sysroot rustc
/// (`[bazel-out/<cfg>/bin/]external/<repo>/.../bin/rustc`); in the runfiles
/// tree that repo sits beside `_main`.
fn rustc() -> PathBuf {
    let r = std::env::var("RUSTC").expect("RUSTC: the rust_test must set $(RUSTC)");
    let rest = match r.find("external/") {
        Some(i) if i == 0 || r[..i].ends_with('/') => &r[i + "external/".len()..],
        _ => panic!("RUSTC={r}: expected a path under external/"),
    };
    let p = Path::new("..").join(rest);
    std::fs::canonicalize(&p).unwrap_or_else(|e| panic!("rustc at {}: {e}", p.display()))
}

fn tmpdir(tag: &str) -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let d = base.join(format!("workflow-rustc-{tag}"));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

#[test]
fn every_workflow_rustc_line_builds_its_tool() {
    let root = std::env::current_dir().unwrap();
    let rustc = rustc();
    let rustc_dir = rustc.parent().unwrap().to_path_buf();

    let mut files: Vec<&str> = EXPECT.iter().map(|(f, _)| *f).collect();
    files.dedup();

    let mut checked = 0;
    for file in files {
        let text = std::fs::read_to_string(root.join(file))
            .unwrap_or_else(|e| panic!("{file}: {e} (missing from the test's data?)"));
        let want: Vec<&str> = EXPECT
            .iter()
            .filter(|(f, _)| *f == file)
            .map(|(_, b)| *b)
            .collect();
        let found: Vec<Vec<String>> = blocks(&text)
            .into_iter()
            .filter(|b| b.iter().any(|l| SOURCES.iter().any(|s| l.contains(s))))
            .collect();
        assert_eq!(
            found.len(),
            want.len(),
            "{file}: {} rustc block(s), the test expects {} ({want:?}); update EXPECT with the workflow",
            found.len(),
            want.len()
        );
        for (block, name) in found.iter().zip(want) {
            let temp = tmpdir(name);
            let script = block.join("\n");
            let o = Command::new("bash")
                .arg("-euo")
                .arg("pipefail")
                .arg("-c")
                .arg(&script)
                .current_dir(&root)
                .env("PATH", format!("{}:/usr/bin:/bin", rustc_dir.display()))
                .env("RUNNER_TEMP", &temp)
                .env("GITHUB_WORKSPACE", &root)
                .output()
                .expect("run bash");
            assert!(
                o.status.success(),
                "{file}: the rustc lines for {name} failed ({}):\n{script}\n--- stderr\n{}",
                o.status,
                String::from_utf8_lossy(&o.stderr)
            );
            let bin = temp.join(name);
            let meta = std::fs::metadata(&bin).unwrap_or_else(|e| {
                panic!("{file}: no {} after its rustc lines: {e}", bin.display())
            });
            use std::os::unix::fs::PermissionsExt;
            assert!(
                meta.permissions().mode() & 0o111 != 0,
                "{} is not executable",
                bin.display()
            );
            checked += 1;
        }
    }
    assert_eq!(checked, EXPECT.len());
}

// --- a runner without rustc ---------------------------------------------------

/// The files whose steps check for rustc before using it. Every runner they
/// use ships one (the homelab queue runner's image since #4202), so a missing
/// rustc fails the step by name; none of them installs one with apt (#4183).
const GUARDS: &[&str] = &[
    ".github/actions/build-ci-tool/action.yml",
    ".github/workflows/actionlint.yaml",
    ".github/workflows/queue-runner-watch.yaml",
];

/// The `if ! command -v rustc ...` block of `text`, through its `fi`.
fn guard_block(file: &str, text: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let start = lines
        .iter()
        .position(|l| l.trim() == "if ! command -v rustc >/dev/null 2>&1; then")
        .unwrap_or_else(|| panic!("{file}: no rustc guard block"));
    let end = start
        + lines[start..]
            .iter()
            .position(|l| l.trim() == "fi")
            .unwrap_or_else(|| panic!("{file}: rustc guard block has no fi"));
    lines[start..=end].join("\n")
}

/// Run `block` then `echo REACHED` under `bash -eo pipefail` (GitHub's step
/// shell) with only `fakes` on PATH.
fn run_guard_on(runner_env: &str, block: &str, fakes: &Path) -> std::process::Output {
    Command::new("/bin/bash")
        .arg("-eo")
        .arg("pipefail")
        .arg("-c")
        .arg(format!("{block}\necho REACHED"))
        .env("PATH", fakes)
        .env("RUNNER_ENVIRONMENT", runner_env)
        .output()
        .expect("run bash")
}

fn exe(path: &Path, body: &str) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// No step installs rustc with apt any more: the unpinned install is what
/// #4183 removed, and a runner image without rustc must fail, not drift.
#[test]
fn no_step_installs_rustc_with_apt() {
    let root = std::env::current_dir().unwrap();
    for file in GUARDS {
        let text = std::fs::read_to_string(root.join(file)).unwrap();
        for (n, line) in text.lines().enumerate() {
            assert!(
                !(line.contains("apt-get install") && line.contains("rustc")),
                "{file}:{}: installs rustc with apt: {line}",
                n + 1
            );
        }
    }
}

/// On any runner, self-hosted included, a missing rustc fails the step by
/// name and never reaches sudo/apt.
#[test]
fn a_runner_without_rustc_fails_the_step_by_name() {
    let root = std::env::current_dir().unwrap();
    for file in GUARDS {
        let block = guard_block(file, &std::fs::read_to_string(root.join(file)).unwrap());
        for runner_env in ["self-hosted", "github-hosted", ""] {
            let fakes = tmpdir(&format!("no-rustc-{runner_env}-{}", file.replace('/', "_")));
            exe(
                &fakes.join("sudo"),
                "#!/bin/bash\necho SUDO-CALLED\nexit 0\n",
            );
            let o = run_guard_on(runner_env, &block, &fakes);
            let out = String::from_utf8_lossy(&o.stdout);
            assert_eq!(o.status.code(), Some(1), "{file} {runner_env:?}: {out}");
            assert!(
                out.contains("no rustc on this runner"),
                "{file} {runner_env:?}: {out}"
            );
            assert!(
                !out.contains("SUDO-CALLED"),
                "{file} {runner_env:?}: apt ran: {out}"
            );
            assert!(
                !out.contains("REACHED"),
                "{file} {runner_env:?}: the step went on without rustc"
            );
        }
    }
}

#[test]
fn a_runner_with_rustc_goes_on() {
    let root = std::env::current_dir().unwrap();
    for file in GUARDS {
        let block = guard_block(file, &std::fs::read_to_string(root.join(file)).unwrap());
        let fakes = tmpdir(&format!("has-rustc-{}", file.replace('/', "_")));
        exe(&fakes.join("rustc"), "#!/bin/bash\nexit 0\n");
        exe(
            &fakes.join("sudo"),
            "#!/bin/bash\necho SUDO-CALLED\nexit 0\n",
        );
        let o = run_guard_on("self-hosted", &block, &fakes);
        let out = String::from_utf8_lossy(&o.stdout);
        assert!(o.status.success(), "{file}: {out}");
        assert!(
            out.contains("REACHED") && !out.contains("SUDO-CALLED"),
            "{file}: {out}"
        );
    }
}
