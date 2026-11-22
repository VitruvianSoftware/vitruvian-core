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

//! Mode 1 (`--diff <base>...<head>`): flag added code duplicating `packages/`.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::Path;

use crate::git::{self, DiffKind};
use crate::glob::AllowList;
use crate::normalize::{hash_block, is_eligible_source, normalize_lines, BLOCK_SIZE};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockHit {
    pub norm_start: usize,
    pub norm_end: usize,
    pub src_first: usize,
    pub src_last: usize,
    pub pkg_file: String,
    pub pkg_line: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MergedRange {
    pub norm_start: usize,
    pub norm_end: usize,
    pub src_first: usize,
    pub src_last: usize,
    pub pkg_matches: Vec<(String, usize)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Finding {
    pub path: String,
    pub first_line: usize,
    pub last_line: usize,
    pub pkg_matches: Vec<(String, usize)>,
    pub line_count: usize,
    pub target: String,
}

impl Finding {
    pub fn format_line(&self) -> String {
        let matched = self
            .pkg_matches
            .iter()
            .map(|(file, line)| format!("{file}:{line}"))
            .collect::<Vec<_>>()
            .join(", ");
        format!(
            "{}:{}-{} duplicates {} ({} lines). Use {} instead.",
            self.path, self.first_line, self.last_line, matched, self.line_count, self.target
        )
    }
}

#[derive(Debug, Clone)]
struct PkgLoc {
    pkg_root: String,
    file: String,
    line: usize,
}

fn push_unique_pkg_match(matches: &mut Vec<(String, usize)>, file: &str, line: usize) {
    if !matches.iter().any(|(f, _)| f == file) {
        matches.push((file.to_string(), line));
    }
}

fn is_binary_blob(bytes: &[u8]) -> bool {
    // Matches git's buffer_is_binary() heuristic (FIRST_FEW_BYTES = 8000).
    bytes.iter().take(8000).any(|&b| b == 0)
}

pub fn merge_hits(mut hits: Vec<BlockHit>) -> Vec<MergedRange> {
    if hits.is_empty() {
        return Vec::new();
    }
    hits.sort_by(|a, b| {
        (
            a.src_first,
            a.norm_start,
            a.src_last,
            &a.pkg_file,
            a.pkg_line,
        )
            .cmp(&(
                b.src_first,
                b.norm_start,
                b.src_last,
                &b.pkg_file,
                b.pkg_line,
            ))
    });

    let mut merged: Vec<MergedRange> = Vec::new();
    for hit in hits {
        if let Some(last) = merged.last_mut() {
            if hit.src_first <= last.src_last + 1 || hit.norm_start <= last.norm_end + 1 {
                last.src_last = last.src_last.max(hit.src_last);
                last.norm_end = last.norm_end.max(hit.norm_end);
                push_unique_pkg_match(&mut last.pkg_matches, &hit.pkg_file, hit.pkg_line);
                continue;
            }
        }
        merged.push(MergedRange {
            norm_start: hit.norm_start,
            norm_end: hit.norm_end,
            src_first: hit.src_first,
            src_last: hit.src_last,
            pkg_matches: vec![(hit.pkg_file, hit.pkg_line)],
        });
    }
    merged
}

pub fn parse_bazel_target_from_catalog(yaml: &str, rel_subpath: Option<&str>) -> Option<String> {
    let mut first_target: Option<String> = None;

    for doc in split_yaml_docs(yaml) {
        let (target, techdocs_subpath) = parse_single_catalog_doc(doc);
        if let Some(t) = target {
            if let (Some(rel), Some(sub)) = (rel_subpath, techdocs_subpath.as_deref()) {
                if !sub.is_empty() && (rel == sub || rel.starts_with(&format!("{sub}/"))) {
                    return Some(t);
                }
            }
            if first_target.is_none() {
                first_target = Some(t);
            }
        }
    }

    first_target
}

fn split_yaml_docs(yaml: &str) -> Vec<&str> {
    let mut docs = Vec::new();
    let mut start = 0;
    let mut offset = 0;

    for line in yaml.split_inclusive('\n') {
        let trimmed = line.trim();
        if trimmed == "---" {
            if offset > start {
                docs.push(&yaml[start..offset]);
            }
            start = offset + line.len();
        }
        offset += line.len();
    }
    if start < yaml.len() {
        docs.push(&yaml[start..]);
    }
    docs
}

fn parse_single_catalog_doc(doc: &str) -> (Option<String>, Option<String>) {
    let mut bazel_target: Option<String> = None;
    let mut techdocs_ref: Option<String> = None;

    let mut metadata_indent: Option<usize> = None;
    let mut annotations_indent: Option<usize> = None;

    for raw in doc.lines() {
        let without_cr = raw.strip_suffix('\r').unwrap_or(raw);
        let trimmed = without_cr.trim_start();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let indent = without_cr.len() - trimmed.len();

        if let Some(mi) = metadata_indent {
            if indent <= mi {
                metadata_indent = None;
                annotations_indent = None;
            }
        }
        if let Some(ai) = annotations_indent {
            if indent <= ai {
                annotations_indent = None;
            }
        }

        if let Some((raw_key, raw_val)) = trimmed.split_once(':') {
            let key = unquote_yaml(raw_key.trim());
            let val_part = raw_val.trim();

            if indent == 0 && key == "metadata" && val_part.is_empty() {
                metadata_indent = Some(indent);
                annotations_indent = None;
                continue;
            }
            if metadata_indent.is_some() && key == "annotations" && val_part.is_empty() {
                annotations_indent = Some(indent);
                continue;
            }
            if annotations_indent.is_some() {
                let val = parse_yaml_scalar(val_part);
                if key == "vitruvian.dev/bazel-target" && !val.is_empty() {
                    bazel_target = Some(val);
                } else if key == "backstage.io/techdocs-ref" && !val.is_empty() {
                    let sub = val
                        .strip_prefix("dir:./")
                        .or_else(|| val.strip_prefix("dir:"))
                        .unwrap_or(&val)
                        .trim_matches('/')
                        .to_string();
                    if sub != "." && !sub.is_empty() {
                        techdocs_ref = Some(sub);
                    }
                }
            }
        }
    }

    (bazel_target, techdocs_ref)
}

fn unquote_yaml(s: &str) -> &str {
    if s.len() >= 2
        && ((s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')))
    {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

fn parse_yaml_scalar(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() || trimmed.starts_with('#') {
        return String::new();
    }
    if let Some(rest) = trimmed.strip_prefix('"') {
        if let Some(end) = rest.find('"') {
            return rest[..end].to_string();
        }
    }
    if let Some(rest) = trimmed.strip_prefix('\'') {
        if let Some(end) = rest.find('\'') {
            return rest[..end].to_string();
        }
    }
    if let Some(idx) = trimmed.find(" #") {
        trimmed[..idx].trim().to_string()
    } else {
        trimmed.to_string()
    }
}

fn resolve_package_root(pkg_file: &str, catalogs: &BTreeMap<String, String>) -> String {
    let mut candidate = Path::new(pkg_file).parent();
    while let Some(dir) = candidate {
        let dir_str = dir.to_string_lossy();
        if dir_str == "packages" || dir_str.is_empty() {
            break;
        }
        if catalogs.contains_key(dir_str.as_ref()) {
            return dir_str.into_owned();
        }
        candidate = dir.parent();
    }

    let parts: Vec<&str> = pkg_file.split('/').collect();
    if parts.len() >= 3 {
        format!("{}/{}", parts[0], parts[1])
    } else {
        "packages".to_string()
    }
}

fn resolve_target(pkg_root: &str, pkg_file: &str, catalogs: &BTreeMap<String, String>) -> String {
    if let Some(yaml) = catalogs.get(pkg_root) {
        let rel = pkg_file
            .strip_prefix(pkg_root)
            .and_then(|s| s.strip_prefix('/'));
        if let Some(target) = parse_bazel_target_from_catalog(yaml, rel) {
            return target;
        }
    }
    pkg_root.to_string()
}

pub fn load_allow_list(
    repo_root: &Path,
    head_ref: &str,
    cli_globs: &[String],
) -> Result<AllowList, String> {
    let allow_rel = "tools/dupcheck/allow.txt";
    let patterns = match git::show_file_opt(repo_root, head_ref, allow_rel)? {
        Some(bytes) => AllowList::parse(&String::from_utf8_lossy(&bytes)),
        None => Vec::new(),
    };
    let mut list = AllowList::from_patterns(patterns);
    list.extend(cli_globs.iter().cloned());
    Ok(list)
}

pub fn run_diff(
    repo_root: &Path,
    base: &str,
    head: &str,
    cli_globs: &[String],
) -> Result<Vec<Finding>, String> {
    git::verify_commit(repo_root, base)?;
    git::verify_commit(repo_root, head)?;

    let allow_list = load_allow_list(repo_root, head, cli_globs)?;

    let mut pkg_entries = git::ls_tree(repo_root, head, Some("packages"))?;
    pkg_entries.sort_by(|a, b| a.path.cmp(&b.path));

    let mut catalog_entries = Vec::new();
    let mut source_entries = Vec::new();
    for entry in pkg_entries {
        if entry.path.ends_with("/catalog-info.yaml") {
            catalog_entries.push(entry);
        } else if is_eligible_source(&entry.path) && !allow_list.is_allowed(&entry.path) {
            source_entries.push(entry);
        }
    }

    let mut specs: Vec<&str> = Vec::with_capacity(catalog_entries.len() + source_entries.len());
    for entry in &catalog_entries {
        specs.push(&entry.oid);
    }
    for entry in &source_entries {
        specs.push(&entry.oid);
    }
    let blobs = git::cat_blobs(repo_root, &specs)?;

    let mut catalogs = BTreeMap::new();
    for (entry, bytes) in catalog_entries.iter().zip(blobs.iter()) {
        if let Some(dir) = Path::new(&entry.path).parent() {
            catalogs.insert(
                dir.to_string_lossy().into_owned(),
                String::from_utf8_lossy(bytes).into_owned(),
            );
        }
    }

    let mut block_index: HashMap<u128, Vec<PkgLoc>> = HashMap::new();
    for (entry, bytes) in source_entries
        .iter()
        .zip(blobs.iter().skip(catalog_entries.len()))
    {
        if is_binary_blob(bytes) {
            continue;
        }
        let content = String::from_utf8_lossy(bytes);
        let norm = normalize_lines(&content);
        if norm.len() < BLOCK_SIZE {
            continue;
        }
        let pkg_root = resolve_package_root(&entry.path, &catalogs);
        for window in norm.windows(BLOCK_SIZE) {
            let hash = hash_block(window);
            let locs = block_index.entry(hash).or_default();
            if !locs
                .iter()
                .any(|l| l.pkg_root == pkg_root && l.file == entry.path)
            {
                locs.push(PkgLoc {
                    pkg_root: pkg_root.clone(),
                    file: entry.path.clone(),
                    line: window[0].line_no,
                });
            }
        }
    }

    if block_index.is_empty() {
        return Ok(Vec::new());
    }

    let diff_entries = git::diff_raw(repo_root, base, head)?;
    let mut candidate_entries: Vec<git::DiffEntry> = diff_entries
        .into_iter()
        .filter(|entry| {
            git::is_regular_file_mode(&entry.dst_mode)
                && !entry.path.starts_with("packages/")
                && is_eligible_source(&entry.path)
                && !allow_list.is_allowed(&entry.path)
                && !(entry.kind != DiffKind::Added
                    && git::is_regular_file_mode(&entry.src_mode)
                    && entry.src_oid == entry.dst_oid)
        })
        .collect();
    candidate_entries.sort_by(|a, b| a.path.cmp(&b.path));

    if candidate_entries.is_empty() {
        return Ok(Vec::new());
    }

    let mut candidate_files: Vec<(String, String, Option<BTreeSet<usize>>)> = Vec::new();
    for entry in candidate_entries {
        let added_lines =
            if entry.kind == DiffKind::Added || !git::is_regular_file_mode(&entry.src_mode) {
                None
            } else {
                let set = git::diff_blob_added_lines(repo_root, &entry.src_oid, &entry.dst_oid)?;
                if set.is_empty() {
                    continue;
                }
                Some(set)
            };
        candidate_files.push((entry.path, entry.dst_oid, added_lines));
    }

    if candidate_files.is_empty() {
        return Ok(Vec::new());
    }

    let dst_oid_refs: Vec<&str> = candidate_files
        .iter()
        .map(|(_, oid, _)| oid.as_str())
        .collect();
    let changed_blobs = git::cat_blobs(repo_root, &dst_oid_refs)?;

    let mut findings = Vec::new();
    for ((path, _, added_lines_opt), bytes) in candidate_files.iter().zip(changed_blobs.iter()) {
        if is_binary_blob(bytes) {
            continue;
        }
        let content = String::from_utf8_lossy(bytes);
        let norm = normalize_lines(&content);
        if norm.len() < BLOCK_SIZE {
            continue;
        }

        let mut hits_by_pkg: BTreeMap<String, Vec<BlockHit>> = BTreeMap::new();
        for (idx, window) in norm.windows(BLOCK_SIZE).enumerate() {
            if let Some(ref added_lines) = added_lines_opt {
                if !window.iter().all(|l| added_lines.contains(&l.line_no)) {
                    continue;
                }
            }
            let hash = hash_block(window);
            let Some(locs) = block_index.get(&hash) else {
                continue;
            };
            let src_first = window[0].line_no;
            let src_last = window[BLOCK_SIZE - 1].line_no;
            let norm_start = idx;
            let norm_end = idx + BLOCK_SIZE - 1;
            for loc in locs {
                hits_by_pkg
                    .entry(loc.pkg_root.clone())
                    .or_default()
                    .push(BlockHit {
                        norm_start,
                        norm_end,
                        src_first,
                        src_last,
                        pkg_file: loc.file.clone(),
                        pkg_line: loc.line,
                    });
            }
        }

        for (pkg_root, hits) in hits_by_pkg {
            let merged = merge_hits(hits);
            if merged.is_empty() {
                continue;
            }
            let first_line = merged[0].src_first;
            let last_line = merged[merged.len() - 1].src_last;
            let line_count: usize = merged.iter().map(|r| r.src_last - r.src_first + 1).sum();
            let mut pkg_matches = Vec::new();
            for range in &merged {
                for (file, line) in &range.pkg_matches {
                    push_unique_pkg_match(&mut pkg_matches, file, *line);
                }
            }
            let target = resolve_target(&pkg_root, &pkg_matches[0].0, &catalogs);

            findings.push(Finding {
                path: path.clone(),
                first_line,
                last_line,
                pkg_matches,
                line_count,
                target,
            });
        }
    }

    Ok(findings)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hit(norm_start: usize, src_first: usize, src_last: usize, pkg_line: usize) -> BlockHit {
        hit_for(
            norm_start,
            src_first,
            src_last,
            "packages/mylib/src/lib.rs",
            pkg_line,
        )
    }

    fn hit_for(
        norm_start: usize,
        src_first: usize,
        src_last: usize,
        pkg_file: &str,
        pkg_line: usize,
    ) -> BlockHit {
        BlockHit {
            norm_start,
            norm_end: norm_start + 11,
            src_first,
            src_last,
            pkg_file: pkg_file.to_string(),
            pkg_line,
        }
    }

    #[test]
    fn merge_hits_combines_overlapping_and_adjacent_blocks() {
        let merged = merge_hits(vec![
            hit(0, 10, 21, 5),
            hit(1, 11, 22, 6),
            hit(2, 12, 23, 7),
            // Separated in raw line numbers by a comment line (24), but adjacent in norm indices.
            hit(12, 25, 36, 17),
            // Disjoint block.
            hit(30, 80, 91, 40),
        ]);
        assert_eq!(merged.len(), 2);
        assert_eq!(merged[0].src_first, 10);
        assert_eq!(merged[0].src_last, 36);
        assert_eq!(
            merged[0].pkg_matches,
            vec![("packages/mylib/src/lib.rs".to_string(), 5)]
        );
        assert_eq!(merged[1].src_first, 80);
        assert_eq!(merged[1].src_last, 91);
        assert_eq!(
            merged[1].pkg_matches,
            vec![("packages/mylib/src/lib.rs".to_string(), 40)]
        );
    }

    #[test]
    fn merge_hits_collects_all_matched_package_files() {
        let merged = merge_hits(vec![
            hit_for(0, 1, 12, "packages/mylib/src/alpha.rs", 10),
            hit_for(12, 13, 24, "packages/mylib/src/beta.rs", 20),
            hit_for(12, 13, 24, "packages/mylib/src/alpha.rs", 99),
        ]);
        assert_eq!(merged.len(), 1);
        assert_eq!(
            merged[0].pkg_matches,
            vec![
                ("packages/mylib/src/alpha.rs".to_string(), 10),
                ("packages/mylib/src/beta.rs".to_string(), 20),
            ]
        );
    }

    #[test]
    fn parses_catalog_bazel_target_single_and_multidoc() {
        let single = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pycompat
  annotations:
    github.com/project-slug: VitruvianSoftware/vitruvian-core
    vitruvian.dev/bazel-target: \"//packages/pycompat/vitruvian-pycompat:vitruvian_pycompat\"
spec:
  type: library
";
        assert_eq!(
            parse_bazel_target_from_catalog(single, None),
            Some("//packages/pycompat/vitruvian-pycompat:vitruvian_pycompat".to_string())
        );

        let multi = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-library-go
  annotations:
    backstage.io/techdocs-ref: dir:./library/go
    vitruvian.dev/bazel-target: //packages/pulumi/library/go
---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-library-ts
  annotations:
    backstage.io/techdocs-ref: dir:./library/ts
    vitruvian.dev/bazel-target: '//packages/pulumi/library/ts:lib'
";
        assert_eq!(
            parse_bazel_target_from_catalog(multi, Some("library/ts/index.ts")),
            Some("//packages/pulumi/library/ts:lib".to_string())
        );
        assert_eq!(
            parse_bazel_target_from_catalog(multi, Some("library/go/vpc.go")),
            Some("//packages/pulumi/library/go".to_string())
        );

        let missing = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: design-system-android
  annotations:
    github.com/project-slug: VitruvianSoftware/vitruvian-core
spec:
  type: library
";
        assert_eq!(parse_bazel_target_from_catalog(missing, None), None);
    }
}
