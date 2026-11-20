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

//! Read-only git subprocess helpers backed by `std::process::Command`.

use std::collections::{BTreeMap, BTreeSet};
use std::io::{BufRead, BufReader, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeEntry {
    pub oid: String,
    pub path: String,
}

pub fn verify_commit(repo_root: &Path, git_ref: &str) -> Result<(), String> {
    let target = format!("{git_ref}^{{commit}}");
    let out = Command::new("git")
        .current_dir(repo_root)
        .args(["rev-parse", "--verify", "-q", &target])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("failed to run git rev-parse for {git_ref}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        let detail = stderr.trim();
        if detail.is_empty() {
            return Err(format!("unknown git commit or ref: {git_ref}"));
        }
        return Err(format!("unknown git commit or ref {git_ref}: {detail}"));
    }
    Ok(())
}

pub fn ls_tree(
    repo_root: &Path,
    git_ref: &str,
    path_prefix: Option<&str>,
) -> Result<Vec<TreeEntry>, String> {
    let mut cmd = Command::new("git");
    cmd.current_dir(repo_root)
        .args(["ls-tree", "-r", "-z", git_ref]);
    if let Some(prefix) = path_prefix {
        cmd.arg("--").arg(prefix);
    }
    let out = cmd
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("failed to run git ls-tree: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!(
            "git ls-tree failed for {git_ref}: {}",
            stderr.trim()
        ));
    }

    let mut entries = Vec::new();
    for rec in out.stdout.split(|&b| b == 0) {
        if rec.is_empty() {
            continue;
        }
        let line = String::from_utf8_lossy(rec);
        let Some((meta, path)) = line.split_once('\t') else {
            continue;
        };
        let mut parts = meta.split_whitespace();
        let _mode = parts.next();
        let kind = parts.next().unwrap_or("");
        let oid = parts.next().unwrap_or("");
        if kind == "blob" && !oid.is_empty() && !path.is_empty() {
            entries.push(TreeEntry {
                oid: oid.to_string(),
                path: path.to_string(),
            });
        }
    }
    Ok(entries)
}

/// Reads all requested git objects in a single `git cat-file --batch` call.
/// Each item in `specs` may be an OID or `<rev>:<path>`.
pub fn cat_blobs(repo_root: &Path, specs: &[&str]) -> Result<Vec<Vec<u8>>, String> {
    if specs.is_empty() {
        return Ok(Vec::new());
    }

    let mut child = Command::new("git")
        .current_dir(repo_root)
        .args(["cat-file", "--batch"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to spawn git cat-file --batch: {e}"))?;

    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| "missing stdin pipe on git cat-file".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "missing stdout pipe on git cat-file".to_string())?;
    let mut stderr_pipe = child
        .stderr
        .take()
        .ok_or_else(|| "missing stderr pipe on git cat-file".to_string())?;

    let results = std::thread::scope(|s| -> Result<Vec<Vec<u8>>, String> {
        let writer = s.spawn(move || -> Result<(), String> {
            for spec in specs {
                stdin
                    .write_all(spec.as_bytes())
                    .and_then(|_| stdin.write_all(b"\n"))
                    .map_err(|e| format!("writing to git cat-file stdin failed: {e}"))?;
            }
            stdin
                .flush()
                .map_err(|e| format!("flushing git cat-file stdin failed: {e}"))?;
            drop(stdin);
            Ok(())
        });

        let err_reader = s.spawn(move || -> String {
            let mut buf = String::new();
            let _ = stderr_pipe.read_to_string(&mut buf);
            buf
        });

        let mut reader = BufReader::new(stdout);
        let mut blobs = Vec::with_capacity(specs.len());
        let mut header = String::new();

        for spec in specs {
            header.clear();
            let n = reader
                .read_line(&mut header)
                .map_err(|e| format!("reading git cat-file header for {spec}: {e}"))?;
            if n == 0 {
                return Err(format!("unexpected EOF from git cat-file for {spec}"));
            }
            let trimmed = header.trim_end_matches(['\r', '\n']);
            if trimmed.ends_with(" missing") {
                return Err(format!("git object missing: {spec}"));
            }
            let mut fields = trimmed.split_whitespace();
            let _oid = fields.next();
            let obj_type = fields.next().unwrap_or("");
            let size_str = fields.next().unwrap_or("");
            let size: usize = size_str
                .parse()
                .map_err(|e| format!("invalid git cat-file size '{trimmed}' for {spec}: {e}"))?;
            if obj_type != "blob" {
                return Err(format!("expected blob for {spec}, got '{obj_type}'"));
            }

            let mut buf = vec![0u8; size];
            reader
                .read_exact(&mut buf)
                .map_err(|e| format!("reading git cat-file payload for {spec}: {e}"))?;
            let mut nl = [0u8; 1];
            reader
                .read_exact(&mut nl)
                .map_err(|e| format!("reading trailing newline for {spec}: {e}"))?;
            blobs.push(buf);
        }

        writer
            .join()
            .map_err(|_| "git cat-file writer thread panicked".to_string())??;
        let stderr_text = err_reader.join().unwrap_or_default();
        let status = child
            .wait()
            .map_err(|e| format!("waiting for git cat-file failed: {e}"))?;
        if !status.success() {
            return Err(format!(
                "git cat-file --batch failed ({status}): {}",
                stderr_text.trim()
            ));
        }

        Ok(blobs)
    })?;

    Ok(results)
}

pub fn show_file_opt(
    repo_root: &Path,
    git_ref: &str,
    path: &str,
) -> Result<Option<Vec<u8>>, String> {
    let spec = format!("{git_ref}:{path}");
    let exists = Command::new("git")
        .current_dir(repo_root)
        .args(["cat-file", "-e", &spec])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("failed to run git cat-file -e: {e}"))?;
    if !exists.success() {
        return Ok(None);
    }

    let out = Command::new("git")
        .current_dir(repo_root)
        .args(["cat-file", "-p", &spec])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("failed to run git cat-file -p {spec}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!("git cat-file -p {spec} failed: {}", stderr.trim()));
    }
    Ok(Some(out.stdout))
}

pub fn diff_added_lines(
    repo_root: &Path,
    base: &str,
    head: &str,
) -> Result<BTreeMap<String, BTreeSet<usize>>, String> {
    let range = format!("{base}...{head}");
    let out = Command::new("git")
        .current_dir(repo_root)
        .args([
            "-c",
            "core.quotepath=false",
            "diff",
            "--no-ext-diff",
            "--src-prefix=a/",
            "--dst-prefix=b/",
            "--unified=0",
            &range,
        ])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("failed to run git diff {range}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!("git diff {range} failed: {}", stderr.trim()));
    }
    let text = String::from_utf8_lossy(&out.stdout);
    Ok(parse_diff_added_lines(&text))
}

pub fn parse_diff_added_lines(diff: &str) -> BTreeMap<String, BTreeSet<usize>> {
    let mut added: BTreeMap<String, BTreeSet<usize>> = BTreeMap::new();
    let mut current_file: Option<String> = None;

    for raw in diff.lines() {
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        if let Some(path) = line.strip_prefix("+++ b/") {
            current_file = Some(path.to_string());
        } else if line == "+++ /dev/null" {
            current_file = None;
        } else if line.starts_with("@@ ") {
            if let Some(ref file) = current_file {
                if let Some((start, count)) = parse_hunk_plus_range(line) {
                    if count > 0 {
                        let set = added.entry(file.clone()).or_default();
                        for ln in start..(start + count) {
                            set.insert(ln);
                        }
                    }
                }
            }
        }
    }

    added
}

fn parse_hunk_plus_range(hunk_header: &str) -> Option<(usize, usize)> {
    let after_plus = hunk_header.split(" +").nth(1)?;
    let range_token = after_plus.split([' ', '@']).next()?;
    if let Some((start_s, count_s)) = range_token.split_once(',') {
        let start = start_s.parse().ok()?;
        let count = count_s.parse().ok()?;
        Some((start, count))
    } else {
        let start = range_token.parse().ok()?;
        Some((start, 1))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_diff_hunks_and_skips_deletions() {
        let diff = "\
diff --git a/apps/a.rs b/apps/a.rs
--- a/apps/a.rs
+++ b/apps/a.rs
@@ -3,2 +5 @@
-old1
-old2
+new5
@@ -10,0 +12,3 @@
+a12
+a13
+a14
@@ -20,2 +25,0 @@
-del1
-del2
diff --git a/apps/gone.rs b/apps/gone.rs
deleted file mode 100644
--- a/apps/gone.rs
+++ /dev/null
@@ -1,4 +0,0 @@
-gone
";
        let map = parse_diff_added_lines(diff);
        assert_eq!(map.len(), 1);
        let lines: Vec<usize> = map["apps/a.rs"].iter().copied().collect();
        assert_eq!(lines, vec![5, 12, 13, 14]);
    }
}
