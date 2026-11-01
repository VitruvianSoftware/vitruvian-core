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

//! //tools/ci:actionlint, in Rust: actionlint.sh's two steps -- the pinned
//! actionlint (with the pinned shellcheck, at warning level, over the `run:`
//! blocks) and //tools/ci:require_pinned_actions -- the same messages and the same
//! exit codes: 0 clean, 1 something to fix, 2 the check could not run.
//!
//! The pinned tools come from $ACTIONLINT, $SHELLCHECK and $PIN_CHECK when
//! set, else from runfiles. `--help` prints the script's own header,
//! compiled in.

use shell_compat::{
    cat, env, err, os, out, path, spawn_failure_status, status, status_code, strerror, subst,
};
use std::os::unix::ffi::OsStringExt;
use std::process::{Command, Stdio};

/// actionlint.sh, for its header (the --help text).
pub const SCRIPT: &str = "\
# actionlint.sh — the required `actionlint` check, run locally.
#
# Usage:
#   bazel run //tools/ci:actionlint                  # every workflow, as CI checks them
#   bazel run //tools/ci:actionlint -- <file>...     # just these workflow files
#
# The same two steps as .github/workflows/actionlint.yaml: actionlint (pinned in
# tools/tools.lock.json at the workflow's ACTIONLINT_VERSION) with shellcheck at
# warning level over the `run:` blocks, then the check that every outside
# action is pinned to a commit SHA (//tools/ci:require_pinned_actions).
#
# One difference: CI uses the shellcheck preinstalled on its runner; this uses
# the pinned one from aspect_rules_lint, so a finding new to one shellcheck
# release can show up on one side only.
#
# Exit codes: 0 clean, 1 something to fix, 2 the check could not run.

set -euo pipefail
";

pub const RUNFILES_ACTIONLINT: &str = "multitool/tools/actionlint/actionlint";
pub const RUNFILES_SHELLCHECK: &str = "multitool/tools/shellcheck/shellcheck";
pub const RUNFILES_PIN_CHECK: &str = "_main/tools/ci/require_pinned_actions";

/// `sed -n '/^# actionlint.sh/,/^set -euo/p' | sed '$d' | sed 's/^# \{0,1\}//'`
/// over `script`.
pub fn help_text(script: &str) -> Vec<u8> {
    let mut picked: Vec<&str> = Vec::new();
    let mut inside = false;
    let body = script.strip_suffix('\n').unwrap_or(script);
    for line in body.split('\n') {
        if !inside {
            if line.starts_with("# actionlint.sh") {
                inside = true;
                picked.push(line);
            }
        } else {
            picked.push(line);
            if line.starts_with("set -euo") {
                inside = false;
            }
        }
    }
    picked.pop();
    let mut o = Vec::new();
    for l in picked {
        let l = l
            .strip_prefix('#')
            .map_or(l, |r| r.strip_prefix(' ').unwrap_or(r));
        o.extend_from_slice(l.as_bytes());
        o.push(b'\n');
    }
    o
}

fn prog() -> Vec<u8> {
    std::env::args_os()
        .next()
        .map(OsStringExt::into_vec)
        .unwrap_or_default()
}

/// `$PWD` as bash has it: the inherited value when it is an absolute path
/// naming the current directory, else the physical one.
pub fn logical_pwd() -> Vec<u8> {
    use std::os::unix::fs::MetadataExt;
    let cwd = std::env::current_dir()
        .map(|p| p.into_os_string().into_vec())
        .unwrap_or_default();
    if let Some(p) = env("PWD") {
        if p.first() == Some(&b'/') {
            if let (Ok(a), Ok(b)) = (std::fs::metadata(path(&p)), std::fs::metadata(path(&cwd))) {
                if a.dev() == b.dev() && a.ino() == b.ino() {
                    return p;
                }
            }
        }
    }
    cwd
}

/// `${NAME:-<runfiles location>}`.
fn tool(name: &str, rf: &Option<runfiles::Runfiles>, rloc: &str) -> Vec<u8> {
    match env(name) {
        Some(v) if !v.is_empty() => v,
        _ => rf
            .as_ref()
            .and_then(|r| runfiles::rlocation!(r, rloc))
            .map(|p| p.into_os_string().into_vec())
            .unwrap_or_default(),
    }
}

/// The file arguments made absolute against where `bazel run` was started
/// (flags and absolute paths as they are).
pub fn resolve_args(args: &[Vec<u8>], base: &[u8]) -> Vec<Vec<u8>> {
    args.iter()
        .map(|a| {
            if a.first() == Some(&b'-') || a.first() == Some(&b'/') {
                a.clone()
            } else {
                cat(&[base, b"/", a])
            }
        })
        .collect()
}

/// The runfiles the script's init block finds: $RUNFILES_DIR,
/// $RUNFILES_MANIFEST_FILE, or the program's own `.runfiles` tree or
/// manifest -- and nothing else (not $TEST_SRCDIR, not an enclosing
/// `*.runfiles` directory, which the Rust library would also try).
fn script_runfiles() -> Option<runfiles::Runfiles> {
    let set = |n: &str| env(n).map_or(false, |v| !v.is_empty());
    if !set("RUNFILES_DIR") && !set("RUNFILES_MANIFEST_FILE") {
        let me = cat(&[&prog(), b".runfiles"]);
        let manifest = cat(&[&prog(), b".runfiles_manifest"]);
        let exe_manifest = cat(&[&prog(), b".exe.runfiles_manifest"]);
        if shell_compat::is_dir(&me) {
            std::env::set_var("RUNFILES_DIR", os(&me));
        } else if shell_compat::is_file(&manifest) {
            std::env::set_var("RUNFILES_MANIFEST_FILE", os(&manifest));
        } else if shell_compat::is_file(&exe_manifest) {
            std::env::set_var("RUNFILES_MANIFEST_FILE", os(&exe_manifest));
        } else {
            return None;
        }
    }
    runfiles::Runfiles::create().ok()
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let rf = script_runfiles();
    let actionlint = tool("ACTIONLINT", &rf, RUNFILES_ACTIONLINT);
    let shellcheck = tool("SHELLCHECK", &rf, RUNFILES_SHELLCHECK);
    let pin_check = tool("PIN_CHECK", &rf, RUNFILES_PIN_CHECK);

    if let Some(a) = args.first() {
        if a == b"-h" || a == b"--help" {
            out(&help_text(SCRIPT));
            return 0;
        }
    }

    for t in [&actionlint, &shellcheck, &pin_check] {
        if t.is_empty() || !shell_compat::is_file(t) {
            err(b"actionlint: cannot find the pinned tools; nothing was checked. Run it as: bazel run //tools/ci:actionlint\n");
            return 2;
        }
    }

    let here = match env("BUILD_WORKSPACE_DIRECTORY") {
        Some(v) if !v.is_empty() => v,
        _ => {
            let mut c = Command::new("git");
            c.args(["rev-parse", "--show-toplevel"])
                .stdout(Stdio::piped())
                .stderr(Stdio::null());
            let (mut o, rc) = match c.output() {
                Ok(o) => (o.stdout, status_code(o.status)),
                Err(e) => (Vec::new(), spawn_failure_status(&e)),
            };
            if rc != 0 {
                o.extend(logical_pwd());
                o.push(b'\n');
            }
            subst(o)
        }
    };
    if !here.is_empty() {
        if let Err(e) = std::env::set_current_dir(path(&here)) {
            err(&cat(&[
                &prog(),
                b": line 75: cd: ",
                &here,
                b": ",
                strerror(&e).as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    }
    let base = match env("BUILD_WORKING_DIRECTORY") {
        Some(v) if !v.is_empty() => v,
        _ => here.clone(),
    };
    let files = resolve_args(args, &base);

    let mut rc = {
        let mut c = Command::new(os(&actionlint));
        c.arg("-shellcheck").arg(os(&shellcheck));
        if shell_compat::stdout_is_tty() {
            c.arg("-color");
        }
        for f in &files {
            c.arg(os(f));
        }
        let opts = match env("SHELLCHECK_OPTS") {
            Some(v) if !v.is_empty() => v,
            _ => b"--severity=warning".to_vec(),
        };
        c.env("SHELLCHECK_OPTS", os(&opts));
        status(94, &mut c, false)
    };
    match rc {
        0 => {}
        1 => err(b"actionlint: the findings above fail the required actionlint check. Fix them, then run this again.\n"),
        n => {
            err(format!("actionlint: actionlint could not run (exit {}); nothing was checked.\n", n).as_bytes());
            return 2;
        }
    }
    let pin_rc = status(99, &mut Command::new(os(&pin_check)), false);
    if pin_rc != 0 {
        rc = 1;
    }
    if rc == 0 {
        out(b"actionlint: workflows pass actionlint and every outside action is pinned to a commit SHA.\n");
    }
    rc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_is_the_script_header() {
        let h = String::from_utf8(help_text(SCRIPT)).unwrap();
        assert!(h.starts_with("actionlint.sh — the required `actionlint` check, run locally.\n"));
        assert!(h.contains("\nUsage:\n"));
        assert!(
            h.ends_with("Exit codes: 0 clean, 1 something to fix, 2 the check could not run.\n\n")
        );
        assert!(!h.contains("set -euo"));
    }

    #[test]
    fn help_range_rules() {
        let s = "x\n# actionlint.sh a\n#b\n#  c\nplain\nset -euo pipefail\n# actionlint.sh again\n";
        assert_eq!(
            help_text(s),
            b"actionlint.sh a\nb\n c\nplain\nset -euo pipefail\n"
        );
    }

    #[test]
    fn args_are_made_absolute() {
        let a = vec![
            b"-verbose".to_vec(),
            b"/abs.yaml".to_vec(),
            b"rel.yaml".to_vec(),
            b"".to_vec(),
        ];
        assert_eq!(
            resolve_args(&a, b"/w"),
            vec![
                b"-verbose".to_vec(),
                b"/abs.yaml".to_vec(),
                b"/w/rel.yaml".to_vec(),
                b"/w/".to_vec()
            ]
        );
    }
}
