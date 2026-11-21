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

//! Mode 2 (`--families [--ref <commit>]`): measure duplicated Rust helper families.

use std::collections::{HashMap, HashSet};
use std::path::Path;

use crate::git;

pub const FAMILIES: &[&str] = &[
    "json",
    "argparse",
    "unicode_tables",
    "pystr",
    "http",
    "jq",
    "pyjson",
    "pyerr",
    "gostd",
    "goexec",
];

// Canonical shared-helper package prefixes excluded from copy counts (matching the
// rollout tracker's "outside packages/rust/" plus the post-rename package folders).
const SHARED_HELPER_PACKAGE_PREFIXES: &[&str] =
    &["packages/rust/", "packages/pycompat/", "packages/gocompat/"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FamilyRow {
    pub family: &'static str,
    pub copies: usize,
    pub code_lines: usize,
    pub also_in_another_copy: usize,
}

pub fn is_excluded_shared_package(path: &str) -> bool {
    SHARED_HELPER_PACKAGE_PREFIXES
        .iter()
        .any(|prefix| path.starts_with(prefix))
}

pub fn extract_family_lines(content: &str) -> Option<Vec<String>> {
    if content.contains("pub use vitruvian_") {
        return None;
    }
    let mut out = Vec::new();
    for raw in content.lines() {
        // Cut at top-level `#[cfg(test)]` modules while keeping indented field attributes.
        if raw.starts_with("#[cfg(test)]") {
            break;
        }
        let trimmed = raw.trim();
        if trimmed.is_empty() || trimmed.starts_with("//") {
            continue;
        }
        out.push(trimmed.to_string());
    }
    Some(out)
}

pub fn run_families(repo_root: &Path, git_ref: &str) -> Result<Vec<FamilyRow>, String> {
    git::verify_commit(repo_root, git_ref)?;
    let entries = git::ls_tree(repo_root, git_ref, None)?;

    let mut matches_by_family: Vec<Vec<usize>> = vec![Vec::new(); FAMILIES.len()];
    let mut selected_oids: Vec<&str> = Vec::new();

    for entry in &entries {
        if is_excluded_shared_package(&entry.path) {
            continue;
        }
        let file_name = entry.path.rsplit('/').next().unwrap_or(entry.path.as_str());
        for (fam_idx, fam) in FAMILIES.iter().enumerate() {
            if file_name.strip_suffix(".rs") == Some(*fam) {
                let blob_idx = selected_oids.len();
                selected_oids.push(&entry.oid);
                matches_by_family[fam_idx].push(blob_idx);
                break;
            }
        }
    }

    let blobs = git::cat_blobs(repo_root, &selected_oids)?;
    let mut rows = Vec::with_capacity(FAMILIES.len());

    for (fam_idx, fam) in FAMILIES.iter().enumerate() {
        let mut files_lines: Vec<Vec<String>> = Vec::new();
        for &blob_idx in &matches_by_family[fam_idx] {
            let text = String::from_utf8_lossy(&blobs[blob_idx]);
            if let Some(lines) = extract_family_lines(&text) {
                files_lines.push(lines);
            }
        }

        let mut line_file_counts: HashMap<&str, usize> = HashMap::new();
        for lines in &files_lines {
            let mut seen_in_file: HashSet<&str> = HashSet::new();
            for line in lines {
                if seen_in_file.insert(line.as_str()) {
                    *line_file_counts.entry(line.as_str()).or_insert(0) += 1;
                }
            }
        }

        let copies = files_lines.len();
        let code_lines: usize = files_lines.iter().map(Vec::len).sum();
        let also_in_another_copy: usize = files_lines
            .iter()
            .flat_map(|lines| lines.iter())
            .filter(|line| line_file_counts.get(line.as_str()).copied().unwrap_or(0) >= 2)
            .count();

        rows.push(FamilyRow {
            family: fam,
            copies,
            code_lines,
            also_in_another_copy,
        });
    }

    Ok(rows)
}

pub fn format_commas(n: usize) -> String {
    let s = n.to_string();
    let mut out = String::with_capacity(s.len() + s.len() / 3);
    for (idx, ch) in s.chars().rev().enumerate() {
        if idx > 0 && idx % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    out.chars().rev().collect()
}

fn percent(part: usize, whole: usize) -> usize {
    (part * 100).checked_div(whole).unwrap_or(0)
}

pub fn format_table(rows: &[FamilyRow]) -> String {
    let mut out = String::from(
        "| Helper | Copies | Code lines | Also in another copy |\n|---|---|---|---|\n",
    );
    let mut total_copies = 0usize;
    let mut total_lines = 0usize;
    let mut total_also = 0usize;

    for row in rows {
        total_copies += row.copies;
        total_lines += row.code_lines;
        total_also += row.also_in_another_copy;
        let pct = percent(row.also_in_another_copy, row.code_lines);
        out.push_str(&format!(
            "| `{}` | {} | {} | {} ({pct}%) |\n",
            row.family,
            format_commas(row.copies),
            format_commas(row.code_lines),
            format_commas(row.also_in_another_copy),
        ));
    }

    let total_pct = percent(total_also, total_lines);
    out.push_str(&format!(
        "| **Total** | **{}** | **{}** | **{} ({total_pct}%)** |\n",
        format_commas(total_copies),
        format_commas(total_lines),
        format_commas(total_also),
    ));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_skips_reexports_and_cuts_at_top_level_cfg_test() {
        assert!(extract_family_lines("pub use vitruvian_pycompat::json;\n").is_none());

        let src = "\
// header comment

pub struct Foo {
    #[cfg(test)]
    pub flag: bool,
}

    // indented comment
    let x = 1;
#[cfg(test)]
mod tests {
    fn hidden() {}
}
";
        let lines = extract_family_lines(src).unwrap();
        assert_eq!(
            lines,
            vec![
                "pub struct Foo {",
                "#[cfg(test)]",
                "pub flag: bool,",
                "}",
                "let x = 1;",
            ]
        );
    }

    #[test]
    fn format_table_formats_commas_and_totals() {
        let rows = vec![
            FamilyRow {
                family: "json",
                copies: 16,
                code_lines: 9246,
                also_in_another_copy: 6617,
            },
            FamilyRow {
                family: "goexec",
                copies: 2,
                code_lines: 608,
                also_in_another_copy: 608,
            },
        ];
        let table = format_table(&rows);
        assert!(table.contains("| `json` | 16 | 9,246 | 6,617 (71%) |"));
        assert!(table.contains("| **Total** | **18** | **9,854** | **7,225 (73%)** |"));
    }
}
