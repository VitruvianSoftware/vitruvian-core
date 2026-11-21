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

use std::collections::BTreeSet;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TreeEntry {
    pub oid: String,
    pub path: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiffKind {
    Added,
    Modified,
    Renamed,
    Deleted,
    TypeChanged,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiffEntry {
    pub src_mode: String,
    pub dst_mode: String,
    pub src_oid: String,
    pub dst_oid: String,
    pub kind: DiffKind,
    pub path: String,
}

pub fn is_regular_file_mode(mode: &str) -> bool {
    mode == "100644" || mode == "100755"
}

fn git_cmd(repo_root: &Path) -> Command {
    let mut cmd = Command::new("git");
    cmd.current_dir(repo_root)
        .args(["-c", "color.ui=never", "-c", "core.quotepath=false"])
        .stdin(Stdio::null());
    cmd
}

pub fn verify_commit(repo_root: &Path, git_ref: &str) -> Result<(), String> {
    let target = format!("{git_ref}^{{commit}}");
    let out = git_cmd(repo_root)
        .args(["rev-parse", "--verify", "-q", &target])
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
    let mut cmd = git_cmd(repo_root);
    cmd.args(["ls-tree", "-r", "-z", git_ref]);
    if let Some(prefix) = path_prefix {
        cmd.arg("--").arg(prefix);
    }
    let out = cmd
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

    let mut child = git_cmd(repo_root)
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
    let exists = git_cmd(repo_root)
        .args(["cat-file", "-e", &spec])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| format!("failed to run git cat-file -e: {e}"))?;
    if !exists.success() {
        return Ok(None);
    }

    let out = git_cmd(repo_root)
        .args(["cat-file", "-p", &spec])
        .output()
        .map_err(|e| format!("failed to run git cat-file -p {spec}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!("git cat-file -p {spec} failed: {}", stderr.trim()));
    }
    Ok(Some(out.stdout))
}

pub fn diff_raw(repo_root: &Path, base: &str, head: &str) -> Result<Vec<DiffEntry>, String> {
    let range = format!("{base}...{head}");
    let out = git_cmd(repo_root)
        .args([
            "-c",
            "diff.renames=true",
            "diff",
            "--no-color",
            "--no-ext-diff",
            "--raw",
            "--no-abbrev",
            "-z",
            &range,
        ])
        .output()
        .map_err(|e| format!("failed to run git diff --raw {range}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!("git diff --raw {range} failed: {}", stderr.trim()));
    }
    Ok(parse_diff_raw_z(&out.stdout))
}

pub fn parse_diff_raw_z(raw: &[u8]) -> Vec<DiffEntry> {
    let mut entries = Vec::new();
    let mut fields = raw.split(|&b| b == 0);
    while let Some(meta_bytes) = fields.next() {
        if meta_bytes.is_empty() {
            continue;
        }
        let meta = String::from_utf8_lossy(meta_bytes);
        let meta = meta.strip_prefix(':').unwrap_or(&meta);
        let mut parts = meta.split_whitespace();
        let Some(src_mode) = parts.next() else {
            continue;
        };
        let Some(dst_mode) = parts.next() else {
            continue;
        };
        let Some(src_oid) = parts.next() else {
            continue;
        };
        let Some(dst_oid) = parts.next() else {
            continue;
        };
        let Some(status) = parts.next() else {
            continue;
        };

        let kind = if status.starts_with('R') {
            DiffKind::Renamed
        } else if status.starts_with('C') || status.starts_with('A') {
            DiffKind::Added
        } else if status.starts_with('M') {
            DiffKind::Modified
        } else if status.starts_with('D') {
            DiffKind::Deleted
        } else if status.starts_with('T') {
            DiffKind::TypeChanged
        } else {
            DiffKind::Other
        };

        let path_bytes = if status.starts_with('R') || status.starts_with('C') {
            let _src_path = fields.next();
            let Some(dst_path) = fields.next() else {
                break;
            };
            dst_path
        } else {
            let Some(p) = fields.next() else {
                break;
            };
            p
        };

        entries.push(DiffEntry {
            src_mode: src_mode.to_string(),
            dst_mode: dst_mode.to_string(),
            src_oid: src_oid.to_string(),
            dst_oid: dst_oid.to_string(),
            kind,
            path: String::from_utf8_lossy(path_bytes).into_owned(),
        });
    }
    entries
}

pub fn diff_blob_added_lines(
    repo_root: &Path,
    src_oid: &str,
    dst_oid: &str,
) -> Result<BTreeSet<usize>, String> {
    let out = git_cmd(repo_root)
        .args([
            "diff",
            "--no-color",
            "--no-ext-diff",
            "--unified=0",
            src_oid,
            dst_oid,
        ])
        .output()
        .map_err(|e| format!("failed to run git diff {src_oid} {dst_oid}: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(format!(
            "git diff {src_oid} {dst_oid} failed: {}",
            stderr.trim()
        ));
    }
    let text = String::from_utf8_lossy(&out.stdout);
    Ok(parse_hunk_added_lines(&text))
}

pub fn parse_hunk_added_lines(diff: &str) -> BTreeSet<usize> {
    let mut added = BTreeSet::new();
    for raw in diff.lines() {
        let line = raw.strip_suffix('\r').unwrap_or(raw);
        if line.starts_with("@@ ") {
            if let Some((start, count)) = parse_hunk_plus_range(line) {
                if count > 0 {
                    for ln in start..(start + count) {
                        added.insert(ln);
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
    fn parses_hunk_added_lines_and_skips_deletions_and_binary() {
        let diff = "\
diff --git a/1111111 b/2222222
index 1111111..2222222 100644
--- a/1111111
+++ b/2222222
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
";
        let lines: Vec<usize> = parse_hunk_added_lines(diff).into_iter().collect();
        assert_eq!(lines, vec![5, 12, 13, 14]);

        let bin = "\
diff --git a/1111111 b/2222222
index 1111111..2222222 100644
Binary files a/1111111 and b/2222222 differ
";
        assert!(parse_hunk_added_lines(bin).is_empty());
    }

    #[test]
    fn parses_diff_raw_z_with_special_paths_and_renames() {
        let mut raw = Vec::new();
        raw.extend_from_slice(
            b":000000 100644 0000000000000000000000000000000000000000 aaaa A\0apps/my space.rs\0",
        );
        raw.extend_from_slice(b":100644 100644 bbbb cccc M\0apps/with\ttab.rs\0");
        raw.extend_from_slice(
            b":100644 000000 dddd 0000000000000000000000000000000000000000 D\0apps/gone.rs\0",
        );
        raw.extend_from_slice(b":100644 100644 eeee eeee R100\0apps/old.rs\0apps/new.rs\0");
        raw.extend_from_slice(
            b":100644 100644 ffff 1234 R075\0apps/old \"q\".rs\0apps/new \"q\".rs\0",
        );

        let entries = parse_diff_raw_z(&raw);
        assert_eq!(entries.len(), 5);
        assert_eq!(entries[0].kind, DiffKind::Added);
        assert_eq!(entries[0].path, "apps/my space.rs");
        assert_eq!(entries[1].kind, DiffKind::Modified);
        assert_eq!(entries[1].path, "apps/with\ttab.rs");
        assert_eq!(entries[2].kind, DiffKind::Deleted);
        assert_eq!(entries[2].path, "apps/gone.rs");
        assert_eq!(entries[3].kind, DiffKind::Renamed);
        assert_eq!(entries[3].path, "apps/new.rs");
        assert_eq!(entries[3].src_oid, entries[3].dst_oid);
        assert_eq!(entries[4].kind, DiffKind::Renamed);
        assert_eq!(entries[4].path, "apps/new \"q\".rs");
        assert_eq!(entries[4].src_oid, "ffff");
        assert_eq!(entries[4].dst_oid, "1234");
    }
}
