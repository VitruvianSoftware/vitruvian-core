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

use crate::tools;
use std::path::{Path, PathBuf};

fn is_exec(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.is_file() && (m.permissions().mode() & 0o111) != 0)
        .unwrap_or(false)
}

/// Resolve `VITRUVIAN_GO_BIN` (`$(rootpath //tools/go-sdk:go)`) before `chdir`
/// moves out of the initial runfiles working directory.
fn resolve_hermetic_go() -> Option<PathBuf> {
    let raw = std::env::var("VITRUVIAN_GO_BIN").ok()?;
    if raw.is_empty() {
        return None;
    }
    let cwd = std::env::current_dir().ok();
    let mut candidates = Vec::new();
    let p = Path::new(&raw);
    if p.is_absolute() {
        candidates.push(p.to_path_buf());
    } else if let Some(ref c) = cwd {
        candidates.push(c.join(p));
        if let Some(rest) = raw.strip_prefix("external/") {
            if let Some(parent) = c.parent() {
                candidates.push(parent.join(rest));
            }
        }
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(rf) = std::env::var(var) {
            if !rf.is_empty() {
                let rf_path = PathBuf::from(rf);
                if let Some(rest) = raw.strip_prefix("external/") {
                    candidates.push(rf_path.join(rest));
                }
                if let Some(rest) = raw.strip_prefix("../") {
                    candidates.push(rf_path.join(rest));
                }
                candidates.push(rf_path.join("_main").join(&raw));
                candidates.push(rf_path.join(&raw));
            }
        }
    }
    candidates.into_iter().find(|c| is_exec(c))
}

/// Entry point (`pulumi-go-test <project_dir>`): cd to the project directory, check
/// for `go` (Bazel's hermetic SDK via `VITRUVIAN_GO_BIN` first, then `PATH`),
/// disable workspace mode and exec `go test ./...`.
pub fn run(args: &[String]) -> i32 {
    let project_dir = match args.first() {
        Some(d) if !d.is_empty() => d.as_str(),
        _ => {
            eprintln!("usage: pulumi-go-test <project_dir>");
            return 1;
        }
    };

    let hermetic_go = resolve_hermetic_go();

    if std::env::set_current_dir(project_dir).is_err() {
        eprintln!("cannot cd to {}", project_dir);
        return 1;
    }

    let go_bin = if let Some(go) = hermetic_go {
        if let Some(bin_dir) = go.parent() {
            if let Some(goroot) = bin_dir.parent() {
                std::env::set_var("GOROOT", goroot);
            }
            let cur_path = std::env::var("PATH").unwrap_or_default();
            let new_path = if cur_path.is_empty() {
                bin_dir.display().to_string()
            } else {
                format!("{}:{cur_path}", bin_dir.display())
            };
            std::env::set_var("PATH", new_path);
        }
        std::env::set_var("GOTOOLCHAIN", "local");
        go
    } else if tools::command_on_path("go") {
        PathBuf::from("go")
    } else {
        eprintln!("go toolchain not found on PATH. This target runs locally only");
        eprintln!("(tagged no-remote-exec) and needs a real 'go' install, same as");
        eprintln!("pulumi-cmd needs 'pulumi' on PATH.");
        return 1;
    };

    if std::env::var_os("GOCACHE").is_none() && std::env::var_os("HOME").is_none() {
        if let Some(tmp) = std::env::var_os("TEST_TMPDIR") {
            std::env::set_var("GOCACHE", PathBuf::from(tmp).join("gocache"));
        }
    }

    std::env::set_var("GOWORK", "off");

    use std::os::unix::process::CommandExt;
    let err = std::process::Command::new(&go_bin)
        .args(["test", "./..."])
        .exec();
    eprintln!("exec go test: {}", err);
    1
}
