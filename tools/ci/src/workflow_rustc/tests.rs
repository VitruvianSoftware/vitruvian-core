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

// --- no step installs Rust ------------------------------------------------------

/// Package managers whose `install` (or `add`) could pull in a distro Rust.
const MANAGERS: &[&str] = &[
    "apt", "apt-get", "aptitude", "dnf", "yum", "microdnf", "zypper", "apk", "brew", "snap",
];

/// A package name that is Rust's compiler or tooling (`rustc`, `rustc-1.80`,
/// `cargo`, `rustup`, `rust`, `rust-all`...), with any `=version`, `:arch`
/// or `@version` suffix removed first.
fn is_rust_package(tok: &str) -> bool {
    let name = tok.split(['=', ':', '@']).next().unwrap_or("");
    name == "rust"
        || name.starts_with("rust-")
        || name.starts_with("rustc")
        || name.starts_with("cargo")
        || name.starts_with("rustup")
}

/// `1.75.0`, or `1.75.0-<target triple>`: a toolchain pinned to one release.
fn is_exact_version(tok: &str) -> bool {
    let v = tok.split('-').next().unwrap_or("");
    let parts: Vec<&str> = v.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
}

/// Why one shell command (already split from its neighbours) installs Rust,
/// if it does.
fn command_installs_rust(cmd: &str) -> Option<&'static str> {
    let toks: Vec<String> = cmd
        .split_whitespace()
        .map(|t| t.trim_matches(|c| c == '"' || c == '\'').to_string())
        .filter(|t| !t.is_empty())
        .collect();
    if matches!(toks.first().map(String::as_str), Some("echo" | "printf")) {
        return None;
    }
    if toks.iter().any(|t| {
        t.contains("sh.rustup.rs")
            || t.contains("rustup-init")
            || t.contains("static.rust-lang.org/rustup")
    }) {
        return Some("bootstraps rustup");
    }
    if let Some(i) = toks.iter().position(|t| MANAGERS.contains(&t.as_str())) {
        let rest = &toks[i + 1..];
        if let Some(j) = rest.iter().position(|t| t == "install" || t == "add") {
            if rest[j + 1..]
                .iter()
                .any(|t| !t.starts_with('-') && is_rust_package(t))
            {
                return Some("installs a Rust package with a package manager");
            }
        }
    }
    if let Some(i) = toks.iter().position(|t| t == "rustup") {
        let rest = &toks[i + 1..];
        let after = match rest.first().map(String::as_str) {
            Some("toolchain") if rest.get(1).map(String::as_str) == Some("install") => &rest[2..],
            Some("install") => &rest[1..],
            _ => &[][..],
        };
        // --profile takes a value; it is not a toolchain name.
        let mut prev_flag = false;
        for t in after {
            if t.starts_with('-') {
                prev_flag = matches!(
                    t.as_str(),
                    "--profile" | "-c" | "--component" | "-t" | "--target"
                );
                continue;
            }
            if prev_flag {
                prev_flag = false;
                continue;
            }
            if !is_exact_version(t) {
                return Some("installs a rustup toolchain that is not one exact release");
            }
        }
    }
    None
}

/// Every place in `text` (a workflow, an action, or any file beside them)
/// that installs Rust: `(line number, why, the logical line)`.
///
/// Lines ending in `\` are joined with the next, so `apt-get install -y \`
/// then `rustc` on its own line is one command. Comment lines are skipped.
/// Each logical line is split into commands at `;`, `&&`, `||`, `|`, `&` and
/// subshell brackets, so `apt-get update && apt-get install rustc` is caught
/// and `rustc --version; apt-get install jq` is not.
fn rust_installs(text: &str) -> Vec<(usize, &'static str, String)> {
    let mut out = Vec::new();
    let lines: Vec<&str> = text.lines().collect();
    let mut i = 0;
    while i < lines.len() {
        let start = i;
        let mut logical = String::new();
        loop {
            let l = lines[i].trim_end();
            if let Some(cont) = l.strip_suffix('\\') {
                logical.push_str(cont);
                logical.push(' ');
                i += 1;
                if i < lines.len() {
                    continue;
                }
            } else {
                logical.push_str(l);
                i += 1;
            }
            break;
        }
        let trimmed = logical.trim_start();
        if trimmed.starts_with('#') {
            continue;
        }
        if trimmed.trim_start_matches("- ").starts_with("uses:") {
            let action = trimmed.to_ascii_lowercase();
            if ["rust-toolchain", "setup-rust", "actions-rs/", "rustup"]
                .iter()
                .any(|a| action.contains(a))
            {
                out.push((
                    start + 1,
                    "uses an action that installs Rust",
                    logical.trim().to_string(),
                ));
            }
            continue;
        }
        let flat: String = logical
            .chars()
            .map(|c| {
                if matches!(c, ';' | '&' | '|' | '(' | ')' | '{' | '}' | '`') {
                    ';'
                } else {
                    c
                }
            })
            .collect();
        for cmd in flat.split(';') {
            if let Some(why) = command_installs_rust(cmd) {
                out.push((start + 1, why, logical.trim().to_string()));
                break;
            }
        }
    }
    out
}

/// Every file under `dir`, recursively.
fn files_under(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for e in std::fs::read_dir(&d)
            .unwrap_or_else(|e| panic!("{}: {e}", d.display()))
            .flatten()
        {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
            } else {
                out.push(p);
            }
        }
    }
    out.sort();
    out
}

/// No workflow, composite action or file beside them installs Rust: not from a
/// distro package (apt, apt-get, dnf, brew...), not by bootstrapping rustup,
/// and not as a rustup toolchain other than one exact release. Every runner
/// ships a rustc, the homelab queue runner's pinned in its image (#4183); an
/// unpinned install is how that runner ended up on whatever rustc Ubuntu had.
#[test]
fn no_file_under_github_installs_rust() {
    let root = std::env::current_dir().unwrap();
    let files = files_under(&root.join(".github"));
    // The scan must really see the tree, not an empty data dependency.
    for want in GUARDS
        .iter()
        .chain([".github/workflows/ci.yaml", ".github/dependabot.yml"].iter())
    {
        assert!(
            files
                .iter()
                .any(|f| f.strip_prefix(&root).ok() == Some(Path::new(want))),
            "{want} is not in the scanned tree; is //:github_files in the test's data?"
        );
    }
    let mut bad = Vec::new();
    for f in &files {
        if f.extension().is_some_and(|e| e == "md") {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(f) else {
            continue;
        };
        for (line, why, cmd) in rust_installs(&text) {
            bad.push(format!(
                "{}:{line}: {why}: {cmd}",
                f.strip_prefix(&root).unwrap().display()
            ));
        }
    }
    assert!(
        bad.is_empty(),
        "steps that install Rust (#4183):\n{}",
        bad.join("\n")
    );
}

#[test]
fn the_scan_catches_every_spelling_of_a_rust_install() {
    for text in [
        "sudo apt-get install -y rustc",
        "apt install -y rustc",
        "apt-get -y install --no-install-recommends rustc",
        "sudo apt update && sudo apt install rustc-1.80",
        "sudo apt-get install -y \\\n  --no-install-recommends \\\n  rustc",
        "apt-get install -y cargo",
        "apt-get install -y rustc=1.75.0+dfsg0ubuntu1",
        "dnf install -y rust cargo",
        "brew install rustup",
        "run: sudo apt-get install -qq rustc",
        "curl --proto '=https' -sSf https://sh.rustup.rs | sh -s -- -y",
        "curl -sSfLO https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init",
        "rustup toolchain install stable",
        "rustup install nightly",
        "rustup toolchain install 1.75 --profile minimal",
        "      - uses: dtolnay/rust-toolchain@stable",
        "      - uses: actions-rs/toolchain@v1",
    ] {
        assert!(!rust_installs(text).is_empty(), "not caught: {text:?}");
    }
}

#[test]
fn the_scan_leaves_other_steps_alone() {
    for text in [
        "rustup toolchain install 1.75.0 --profile minimal",
        "rustup default 1.75.0",
        "rustup toolchain install 1.75.0-x86_64-unknown-linux-gnu",
        "sudo apt-get install -y jq shellcheck",
        "rustc --version; sudo apt-get install -y jq",
        "# an unpinned apt-get install rustc used to live here",
        "echo \"::error::apt install rustc failed\"",
        "rustc --edition 2021 -O tools/ci/src/x/main.rs -o \"$RUNNER_TEMP/x\"",
        "      - uses: actions/checkout@v4",
    ] {
        assert!(
            rust_installs(text).is_empty(),
            "flagged: {text:?}: {:?}",
            rust_installs(text)
        );
    }
}
