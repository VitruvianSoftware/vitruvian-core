// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust verification suites and reference tools for `packages/vitruvian-sdk`.

pub mod conformance_suite;
pub mod go_template;
pub mod guide;
pub mod init;
pub mod mirror_workflows;
pub mod protocol_examples;
pub mod reference_tool;
pub mod reference_tool_2;
pub mod release_version;
pub mod samples;
pub mod schema;
pub mod swift_template;

use std::env;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Component, Path, PathBuf};

/// Lexical `os.path.abspath(path)`.
pub fn lexical_abspath(path: &Path) -> PathBuf {
    let joined = if path.is_absolute() {
        path.to_path_buf()
    } else {
        env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(path)
    };
    let mut out = PathBuf::new();
    for comp in joined.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Checks whether `path` is a regular file with executable permissions (`os.access(p, os.X_OK)`).
pub fn is_executable(path: &Path) -> bool {
    fs::metadata(path).is_ok_and(|m| m.is_file() && (m.permissions().mode() & 0o111) != 0)
}

/// Resolves the `packages/vitruvian-sdk` directory from Bazel runfiles, workspace root, or cwd.
pub fn find_package_dir() -> Result<PathBuf, String> {
    let mut candidates = Vec::new();
    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !ws.is_empty() {
            candidates.push(PathBuf::from(ws).join("packages").join("vitruvian-sdk"));
        }
    }
    if let Ok(cwd) = env::current_dir() {
        candidates.push(cwd.join("packages").join("vitruvian-sdk"));
        candidates.push(cwd);
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(rf) = env::var(var) {
            if !rf.is_empty() {
                let rf_path = PathBuf::from(rf);
                candidates.push(rf_path.join("_main").join("packages").join("vitruvian-sdk"));
                candidates.push(rf_path.join("packages").join("vitruvian-sdk"));
            }
        }
    }
    candidates
        .into_iter()
        .find(|cand| {
            cand.join("protocol/manifest.schema.json").is_file()
                || cand.join("release-please-config.json").is_file()
                || cand.join(".github/workflows/release.yml").is_file()
                || cand.join("Package.swift").is_file()
                || cand
                    .join("conformance/reference-tool/vitruvian-tool.json")
                    .is_file()
        })
        .ok_or_else(|| "could not locate packages/vitruvian-sdk directory".to_string())
}

/// Resolves a `$(rootpath ...)` or relative path in Bazel runfiles or workspace.
pub fn resolve_runfile(path: &str) -> PathBuf {
    let direct = lexical_abspath(Path::new(path));
    if direct.exists() {
        return direct;
    }
    if let Some(inside) = path.strip_prefix("external/") {
        if let Ok(cwd) = env::current_dir() {
            if let Some(parent) = cwd.parent() {
                let cand = parent.join(inside);
                if cand.exists() {
                    return cand;
                }
            }
        }
        for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
            if let Ok(rf) = env::var(var) {
                if !rf.is_empty() {
                    let cand = PathBuf::from(rf).join(inside);
                    if cand.exists() {
                        return cand;
                    }
                }
            }
        }
    }
    if let Some(inside) = path.strip_prefix("../") {
        for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
            if let Ok(rf) = env::var(var) {
                if !rf.is_empty() {
                    let cand = PathBuf::from(rf).join(inside);
                    if cand.exists() {
                        return cand;
                    }
                }
            }
        }
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(rf) = env::var(var) {
            if !rf.is_empty() {
                let rf_path = PathBuf::from(rf);
                for cand in [rf_path.join("_main").join(path), rf_path.join(path)] {
                    if cand.exists() {
                        return cand;
                    }
                }
            }
        }
    }
    direct
}

/// Resolves Bazel's hermetic Node binary from `VITRUVIAN_NODE`, matching `samples_test.py`.
pub fn hermetic_node(path: &str) -> Option<PathBuf> {
    let mut candidates = vec![lexical_abspath(Path::new(path))];
    if let Some(inside) = path.strip_prefix("external/") {
        if let Ok(cwd) = env::current_dir() {
            if let Some(runfiles) = cwd.parent() {
                candidates.push(runfiles.join(inside));
            }
        }
        if let Ok(rf) = env::var("RUNFILES_DIR") {
            if !rf.is_empty() {
                candidates.push(PathBuf::from(rf).join(inside));
            }
        }
        if let Ok(ts) = env::var("TEST_SRCDIR") {
            if !ts.is_empty() {
                candidates.push(PathBuf::from(ts).join(inside));
            }
        }
    }
    candidates.into_iter().find(|cand| is_executable(cand))
}

/// Finds a working `python3` executable for launching Python sample tools.
pub fn find_python3() -> String {
    if let Ok(explicit) = env::var("VITRUVIAN_PYTHON") {
        if !explicit.is_empty() {
            let resolved = resolve_runfile(&explicit);
            if is_executable(&resolved) {
                return resolved.to_string_lossy().into_owned();
            }
            return explicit;
        }
    }
    if let Ok(path_var) = env::var("PATH") {
        for dir in env::split_paths(&path_var) {
            let cand = dir.join("python3");
            if is_executable(&cand) {
                return cand.to_string_lossy().into_owned();
            }
        }
    }
    "/usr/bin/python3".to_string()
}

/// Recursively copies directory `src` to `dst`, preserving file permissions.
pub fn copy_dir_all(src: &Path, dst: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if file_type.is_dir() {
            copy_dir_all(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use conformance_rs_lib::json;

    #[test]
    fn test_schema_pattern_matching() {
        assert!(schema::matches_pattern(
            "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$",
            "com.example.tool"
        ));
        assert!(!schema::matches_pattern(
            "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$",
            "single"
        ));
        assert!(schema::matches_pattern(
            "^(?!\\.{1,2}(/|$))[^/]+(/(?!\\.{1,2}(/|$))[^/]+)*$",
            "bin/tool"
        ));
        assert!(!schema::matches_pattern(
            "^(?!\\.{1,2}(/|$))[^/]+(/(?!\\.{1,2}(/|$))[^/]+)*$",
            "../tool"
        ));
        assert!(!schema::matches_pattern(
            "^(?!\\.{1,2}(/|$))[^/]+(/(?!\\.{1,2}(/|$))[^/]+)*$",
            "/abs/tool"
        ));
    }

    #[test]
    fn test_yaml_parser_handles_block_scalar_and_mappings() {
        let sample_yaml = "\
name: Release
permissions:
  contents: read
jobs:
  detect:
    steps:
      - name: Check
        id: detect
        with:
          persist-credentials: false
        run: |
          echo hello
          echo world
";
        let val = mirror_workflows::parse_yaml(sample_yaml);
        assert_eq!(
            val.get("permissions")
                .and_then(|p| p.get("contents"))
                .and_then(|c| c.as_str()),
            Some("read")
        );
        let step = &val
            .get("jobs")
            .unwrap()
            .get("detect")
            .unwrap()
            .get("steps")
            .unwrap()
            .as_arr()
            .unwrap()[0];
        assert_eq!(
            step.get("with")
                .unwrap()
                .get("persist-credentials")
                .unwrap()
                .as_bool(),
            Some(false)
        );
        assert_eq!(
            step.get("run").unwrap().as_str(),
            Some("echo hello\necho world\n")
        );
    }

    #[test]
    fn test_mounts_under_orders_deepest_first() {
        let found = swift_template::mounts_under(Path::new("/work/t"), swift_template::TABLE);
        let mounts = "/work/t/home/Library/Developer/DVTDownloads/MetalToolchain/mounts/389a";
        assert_eq!(
            found,
            vec![format!("{mounts}/inner disk"), mounts.to_string()]
        );
    }

    #[test]
    fn test_reference_tool_1_session_in_memory() {
        let input = concat!(
            r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersions":["1","2"],"language":"en-US","dataFolder":"/tmp"}}"#,
            "\n",
            r#"{"jsonrpc":"2.0","id":2,"method":"command/run","params":{"command":"hello"}}"#,
            "\n",
            r#"{"jsonrpc":"2.0","id":1,"result":{}}"#,
            "\n",
            r#"{"jsonrpc":"2.0","method":"shutdown"}"#,
            "\n"
        );
        let mut out = Vec::new();
        let code = reference_tool::run_session(io::Cursor::new(input.as_bytes()), &mut out);
        assert_eq!(code, 0);
        let lines: Vec<String> = String::from_utf8(out)
            .unwrap()
            .lines()
            .map(String::from)
            .collect();
        assert_eq!(lines.len(), 4);
        let init_reply = json::loads(&lines[0]).unwrap();
        assert_eq!(
            init_reply
                .get("result")
                .unwrap()
                .get("protocolVersion")
                .unwrap()
                .as_str(),
            Some("1")
        );
    }
}
