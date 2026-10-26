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

//! Security checks ported from check.sh: checkout credentials, dependabot
//! actions coverage, GitHub Actions SHA pins, gitleaks allowlist paths, and
//! agent-guard review paths.

use crate::Context;
use std::collections::{BTreeSet, HashSet};
use std::fs;
use std::path::Path;
use std::process::Command;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Walk a directory tree, pruning the same directories the Python helpers do.
/// Returns relative paths (relative to `root`) with `/` separators.
fn walk_files_pruned(root: &str, start: &str) -> Vec<String> {
    let skip: HashSet<&str> = [
        ".git",
        "node_modules",
        ".cache",
        "dist",
        "build-output",
        ".claude",
        ".pio",
        "testdata",
    ]
    .iter()
    .copied()
    .collect();
    let mut out = Vec::new();
    walk_rec(Path::new(start), Path::new(root), &skip, &mut out);
    out
}

fn walk_rec(dir: &Path, root: &Path, skip: &HashSet<&str>, out: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    let mut sorted: Vec<fs::DirEntry> = entries.filter_map(|e| e.ok()).collect();
    sorted.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
    for entry in sorted {
        let name = match entry.file_name().into_string() {
            Ok(s) => s,
            Err(_) => continue,
        };
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            if skip.contains(name.as_str()) || name.starts_with("bazel-") {
                continue;
            }
            walk_rec(&entry.path(), root, skip, out);
        } else if ft.is_file() {
            if let Ok(rel) = entry.path().strip_prefix(root) {
                out.push(rel.to_string_lossy().replace('\\', "/"));
            }
        }
    }
}

/// List workflow files (.yaml and .yml) in the workflows directory, sorted.
fn sorted_workflow_files(wf_dir: &str) -> Vec<String> {
    let dir = Path::new(wf_dir);
    let mut files = Vec::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.ends_with(".yaml") || name.ends_with(".yml") {
                let path = entry.path().to_string_lossy().to_string();
                files.push(path);
            }
        }
    }
    files.sort();
    files
}

/// Check if a string is a valid 40-character lowercase hex SHA.
fn is_sha40(s: &str) -> bool {
    s.len() == 40
        && s.bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
}

// ---------------------------------------------------------------------------
// check_checkout_credentials
// ---------------------------------------------------------------------------

/// Port of check_checkout_credentials (lines 3562-3683).
pub fn check_checkout_credentials(ctx: &Context) {
    if !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }

    let workflows = sorted_workflow_files(&ctx.workflows_dir);

    let mut total_count: u32 = 0;
    let mut persisted_count: u32 = 0;
    let mut exempt_count: u32 = 0;
    let mut has_checkout_failures = false;

    for wf in &workflows {
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let lines: Vec<&str> = content.lines().collect();
        let rel = ctx.rel(wf);

        for (i, line) in lines.iter().enumerate() {
            if !line.contains("actions/checkout") {
                continue;
            }
            if line.trim().starts_with('#') {
                continue;
            }

            total_count += 1;
            let line_no = i + 1;
            let step_indent = line.len() - line.trim_start().len();
            let is_dash = line.trim_start().starts_with('-');

            let base_indent = if is_dash {
                step_indent
            } else {
                let mut k = i as isize - 1;
                while k >= 0 {
                    let prev = lines[k as usize];
                    let prev_trimmed = prev.trim_start();
                    let prev_indent = prev.len() - prev_trimmed.len();
                    if prev_trimmed.starts_with("- ") && prev_indent < step_indent {
                        break;
                    }
                    k -= 1;
                }
                if k >= 0 {
                    let prev = lines[k as usize];
                    prev.len() - prev.trim_start().len()
                } else {
                    step_indent.saturating_sub(2)
                }
            };

            // Check for opt-out comment in the 4 lines above.
            let mut has_allow = false;
            let mut allow_reason = String::new();
            let start = if i >= 4 { i - 4 } else { 0 };
            for prev_idx in start..i {
                if lines[prev_idx].contains("persist-credentials: allow") {
                    has_allow = true;
                    let trimmed = lines[prev_idx].trim();
                    if let Some(after) = trimmed.split("persist-credentials: allow").nth(1) {
                        allow_reason = after
                            .trim_matches(|c: char| c == ' ' || c == '(' || c == ')' || c == '#')
                            .to_string();
                    }
                    break;
                }
            }

            // Check step block for persist-credentials.
            let mut has_persist_false = false;
            let mut has_persist_true = false;
            let mut j = i + 1;
            while j < lines.len() {
                let nl = lines[j];
                let nl_trimmed = nl.trim();
                if nl_trimmed.is_empty() || nl_trimmed.starts_with('#') {
                    j += 1;
                    continue;
                }
                let ind = nl.len() - nl_trimmed.len();
                if ind <= base_indent {
                    break;
                }
                if nl.contains("persist-credentials: false") {
                    has_persist_false = true;
                } else if nl.contains("persist-credentials: true") {
                    has_persist_true = true;
                }
                j += 1;
            }

            if has_allow {
                exempt_count += 1;
                let reason = if allow_reason.is_empty() {
                    "git push".to_string()
                } else {
                    allow_reason
                };
                ctx.emit_pin(
                    "checkout",
                    &format!("{rel}:{line_no}"),
                    "allow",
                    "false",
                    &format!("opt-out: {reason}"),
                );
            } else if has_persist_false {
                persisted_count += 1;
            } else {
                let found = if has_persist_true {
                    "true"
                } else {
                    "default (true)"
                };
                ctx.emit_fail(
                    "checkout",
                    &format!("{rel}:{line_no}"),
                    found,
                    "false",
                    "step leaves GITHUB_TOKEN in .git/config where any runner subprocess can read it",
                    "add 'with: persist-credentials: false' (or '# persist-credentials: allow' if it genuinely pushes)",
                );
                has_checkout_failures = true;
            }
        }
    }

    if !has_checkout_failures && total_count >= 50 {
        ctx.emit_ok(
            "checkout",
            ".github/workflows",
            &format!("{persisted_count}/{total_count}"),
            "false",
            &format!(
                "all {persisted_count} read-only checkouts drop ambient credentials from .git/config ({exempt_count} allowed push steps)"
            ),
        );
    }

    // Fail-closed assertion.
    if total_count < 50 {
        ctx.emit_fail(
            "checkout",
            ".github/workflows",
            &total_count.to_string(),
            ">=50",
            "too few checkout steps parsed -- parser or workflow layout may have drifted",
            "verify checkout parser in tools/conformance/check.sh",
        );
    }
}

// ---------------------------------------------------------------------------
// check_dependabot_action_coverage
// ---------------------------------------------------------------------------

/// Simple fnmatch-style pattern matching (supports `*`, `?`, `[...]`).
fn fnmatch(pattern: &str, name: &str) -> bool {
    let pat: Vec<char> = pattern.chars().collect();
    let txt: Vec<char> = name.chars().collect();
    fnmatch_rec(&pat, 0, &txt, 0)
}

fn fnmatch_rec(pat: &[char], pi: usize, txt: &[char], ti: usize) -> bool {
    if pi == pat.len() {
        return ti == txt.len();
    }
    match pat[pi] {
        '*' => {
            // Try matching zero or more characters.
            for skip in 0..=(txt.len() - ti) {
                if fnmatch_rec(pat, pi + 1, txt, ti + skip) {
                    return true;
                }
            }
            false
        }
        '?' => {
            if ti < txt.len() {
                fnmatch_rec(pat, pi + 1, txt, ti + 1)
            } else {
                false
            }
        }
        '[' => {
            if ti >= txt.len() {
                return false;
            }
            // Find closing bracket.
            let mut end = pi + 1;
            while end < pat.len() && pat[end] != ']' {
                end += 1;
            }
            if end >= pat.len() {
                return false;
            }
            let c = txt[ti];
            let class = &pat[pi + 1..end];
            let matched = class.iter().any(|&ch| ch == c);
            if matched {
                fnmatch_rec(pat, end + 1, txt, ti + 1)
            } else {
                false
            }
        }
        c => {
            if ti < txt.len() && txt[ti] == c {
                fnmatch_rec(pat, pi + 1, txt, ti + 1)
            } else {
                false
            }
        }
    }
}

/// Port of check_dependabot_action_coverage (lines 3692-3804).
pub fn check_dependabot_action_coverage(ctx: &Context) {
    let dep_yml = format!("{}/.github/dependabot.yml", ctx.root);
    if !Path::new(&dep_yml).is_file() {
        return;
    }

    let content = match fs::read_to_string(&dep_yml) {
        Ok(c) => c,
        Err(_) => return,
    };

    // Parse configured directories for github-actions ecosystem.
    let mut configured_dirs: Vec<String> = Vec::new();
    let mut in_actions = false;
    let mut in_dirs = false;
    for line in content.lines() {
        let s = line.trim();
        if s.is_empty() || s.starts_with('#') {
            continue;
        }
        if s.contains("package-ecosystem:") {
            in_actions = s.contains("github-actions");
            in_dirs = false;
            continue;
        }
        if in_actions {
            if s.starts_with("- package-ecosystem:") {
                in_actions = false;
                in_dirs = false;
                continue;
            }
            if s.starts_with("directory:") {
                let d = s.split("directory:").nth(1).unwrap_or("").trim();
                let d = d.trim_matches(|c: char| c == '"' || c == '\'');
                configured_dirs.push(d.to_string());
            } else if s.starts_with("directories:") {
                in_dirs = true;
            } else if in_dirs {
                if s.starts_with('-') {
                    let d = s[1..].trim().trim_matches(|c: char| c == '"' || c == '\'');
                    configured_dirs.push(d.to_string());
                } else if s
                    .chars()
                    .next()
                    .map_or(false, |c| c.is_alphanumeric() || c == '_' || c == '-')
                    && s.contains(':')
                {
                    in_dirs = false;
                }
            }
        }
    }

    if configured_dirs.is_empty() {
        ctx.emit_fail(
            "dependabot_actions",
            ".github/dependabot.yml",
            "missing",
            "configured",
            "no directories configured under package-ecosystem: github-actions",
            "add directories: list to .github/dependabot.yml",
        );
        return;
    }

    // Walk the repo for workflow and composite action directories.
    let mut workflow_dirs: BTreeSet<String> = BTreeSet::new();
    let all_files = walk_files_pruned(&ctx.root, &ctx.root);
    for f in &all_files {
        let parts: Vec<&str> = f.rsplitn(2, '/').collect();
        if parts.len() < 2 {
            continue;
        }
        let filename = parts[0];
        let dir_path = parts[1];
        let dir_basename = dir_path.rsplit('/').next().unwrap_or(dir_path);
        let parent_of_dir = {
            let p = Path::new(dir_path);
            p.parent()
                .and_then(|pp| pp.file_name())
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default()
        };

        if filename.ends_with(".yml") || filename.ends_with(".yaml") {
            if dir_basename == "workflows" && parent_of_dir == ".github" {
                workflow_dirs.insert(dir_path.to_string());
            } else if filename == "action.yml" || filename == "action.yaml" {
                workflow_dirs.insert(dir_path.to_string());
            } else if dir_path.contains("packages/pulumi/examples") && dir_basename == "build" {
                workflow_dirs.insert(dir_path.to_string());
            }
        }
    }

    let mut has_failures = false;
    let mut covered_count: u32 = 0;

    for d in &workflow_dirs {
        let target = format!("/{}", d.trim_start_matches('/'));
        let is_covered = if d == ".github/workflows" && configured_dirs.contains(&"/".to_string()) {
            true
        } else {
            configured_dirs.iter().any(|p| fnmatch(p, &target))
        };
        if is_covered {
            covered_count += 1;
        } else {
            let target_dir = format!("/{}", d.trim_start_matches('/'));
            ctx.emit_fail(
                "dependabot_actions",
                d,
                "uncovered",
                "dependabot.yml",
                "workflow directory not covered in .github/dependabot.yml",
                &format!("add '{target_dir}' to directories: in .github/dependabot.yml"),
            );
            has_failures = true;
        }
    }

    let total = workflow_dirs.len() as u32;
    if !has_failures && total > 0 {
        ctx.emit_ok(
            "dependabot_actions",
            ".github/dependabot.yml",
            &format!("{covered_count}/{total}"),
            "all covered",
            &format!(
                "all {total} workflow and composite action directories are covered by Dependabot"
            ),
        );
    }
}

// ---------------------------------------------------------------------------
// check_action_sha_pins
// ---------------------------------------------------------------------------

/// Parse a `uses:` line for the action reference and version ref.
/// Returns `Some((action, ref_str))` for third-party actions, None otherwise.
fn parse_uses_line(line: &str) -> Option<(&str, &str)> {
    let trimmed = line.trim_start();
    // Strip optional leading `- `.
    let after_dash = if trimmed.starts_with("- ") {
        trimmed[2..].trim_start()
    } else if trimmed.starts_with('-') {
        trimmed[1..].trim_start()
    } else {
        trimmed
    };
    let rest = after_dash.strip_prefix("uses:")?;
    let rest = rest.trim_start();
    // Split at @ to get action and ref.
    let at_pos = rest.find('@')?;
    let action = &rest[..at_pos];
    // ref goes until whitespace or #
    let after_at = &rest[at_pos + 1..];
    let ref_end = after_at
        .find(|c: char| c.is_whitespace() || c == '#')
        .unwrap_or(after_at.len());
    let ref_str = &after_at[..ref_end];

    // Validate action looks like owner/repo (contains /).
    if !action.contains('/') {
        return None;
    }
    // Validate action characters: [A-Za-z0-9_.-/]
    if !action
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '-' || c == '/')
    {
        return None;
    }

    Some((action, ref_str))
}

/// Port of check_action_sha_pins (lines 3813-3907).
pub fn check_action_sha_pins(ctx: &Context) {
    let scan_dirs = [".github/actions", "apps", "packages"];
    let mut third_party_actions: u32 = 0;
    let mut pinned_actions: u32 = 0;
    let mut failures: Vec<(String, String)> = Vec::new();

    // Scan .github/actions, apps, packages.
    for sd in &scan_dirs {
        let target_dir = format!("{}/{sd}", ctx.root);
        if !Path::new(&target_dir).exists() {
            continue;
        }
        let files = walk_files_pruned(&ctx.root, &target_dir);
        for f in &files {
            if !(f.ends_with(".yml") || f.ends_with(".yaml") || f.ends_with(".tmpl")) {
                continue;
            }
            let full = format!("{}/{f}", ctx.root);
            let content = match fs::read_to_string(&full) {
                Ok(c) => c,
                Err(_) => continue,
            };
            for (i, line) in content.lines().enumerate() {
                if line.trim_start().starts_with('#') {
                    continue;
                }
                if let Some((act, ref_str)) = parse_uses_line(line) {
                    if act.starts_with("actions/")
                        || act.starts_with("./")
                        || act.starts_with("docker://")
                    {
                        continue;
                    }
                    third_party_actions += 1;
                    if is_sha40(ref_str) {
                        pinned_actions += 1;
                    } else {
                        failures.push((format!("{f}:{}", i + 1), format!("{act}@{ref_str}")));
                    }
                }
            }
        }
    }

    // Scan root workflows.
    let root_wf = format!("{}/.github/workflows", ctx.root);
    if Path::new(&root_wf).is_dir() {
        let mut entries: Vec<String> = Vec::new();
        if let Ok(rd) = fs::read_dir(&root_wf) {
            for entry in rd.filter_map(|e| e.ok()) {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.ends_with(".yml") || name.ends_with(".yaml") {
                    entries.push(name);
                }
            }
        }
        entries.sort();
        for name in &entries {
            let file_path = format!("{root_wf}/{name}");
            let rel = format!(".github/workflows/{name}");
            let content = match fs::read_to_string(&file_path) {
                Ok(c) => c,
                Err(_) => continue,
            };
            for (i, line) in content.lines().enumerate() {
                if line.trim_start().starts_with('#') {
                    continue;
                }
                if let Some((act, ref_str)) = parse_uses_line(line) {
                    if act.starts_with("actions/") {
                        continue;
                    }
                    third_party_actions += 1;
                    if is_sha40(ref_str) {
                        pinned_actions += 1;
                    } else {
                        failures.push((format!("{rel}:{}", i + 1), format!("{act}@{ref_str}")));
                    }
                }
            }
        }
    }

    let mut has_failures = false;
    for (loc, found) in &failures {
        ctx.emit_fail(
            "action_pins",
            loc,
            found,
            "40-char SHA",
            "unpinned third-party action",
            "pin to 40-character commit SHA with version comment (e.g. '@<sha> # vX.Y.Z')",
        );
        has_failures = true;
    }

    if !has_failures {
        ctx.emit_ok(
            "action_pins",
            "exported workflows & templates",
            &format!("{pinned_actions}/{third_party_actions}"),
            "40-char SHA",
            &format!(
                "all {third_party_actions} third-party action invocations are pinned to commit SHAs"
            ),
        );
    }
}

// ---------------------------------------------------------------------------
// check_gitleaks_allowlist_paths
// ---------------------------------------------------------------------------

/// Extract triple-quoted strings from `paths = ['''...''', ...]` blocks.
fn extract_gitleaks_paths(text: &str) -> Vec<String> {
    // Strip comment lines first.
    let live: String = text
        .lines()
        .filter(|l| !l.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n");

    let mut patterns = Vec::new();
    // Find `paths = [...]` blocks.
    let mut search_from = 0;
    while let Some(start) = live[search_from..].find("paths") {
        let abs_start = search_from + start;
        // Check it looks like `paths = [`
        let after_key = &live[abs_start + 5..];
        let after_key = after_key.trim_start();
        if !after_key.starts_with('=') {
            search_from = abs_start + 5;
            continue;
        }
        let after_eq = after_key[1..].trim_start();
        if !after_eq.starts_with('[') {
            search_from = abs_start + 5;
            continue;
        }
        let bracket_start = live.len() - after_eq.len();
        if let Some(bracket_end) = live[bracket_start..].find(']') {
            let block = &live[bracket_start..bracket_start + bracket_end + 1];
            // Extract triple-quoted strings.
            let mut bi = 0;
            let bchars: Vec<char> = block.chars().collect();
            while bi + 5 < bchars.len() {
                if bchars[bi] == '\'' && bchars[bi + 1] == '\'' && bchars[bi + 2] == '\'' {
                    // Find closing '''.
                    let content_start = bi + 3;
                    let mut ci = content_start;
                    while ci + 2 < bchars.len() {
                        if bchars[ci] == '\'' && bchars[ci + 1] == '\'' && bchars[ci + 2] == '\'' {
                            let pat: String = bchars[content_start..ci].iter().collect();
                            patterns.push(pat);
                            bi = ci + 3;
                            break;
                        }
                        ci += 1;
                    }
                    if ci + 2 >= bchars.len() {
                        break;
                    }
                } else {
                    bi += 1;
                }
            }
            search_from = bracket_start + bracket_end + 1;
        } else {
            break;
        }
    }
    patterns
}

/// Test whether a regex pattern (as Python `re.search` would) matches any of
/// the given file paths. Shells out to `grep -qE` to avoid reimplementing a
/// regex engine.
fn regex_matches_any_file(pattern: &str, files: &[String]) -> bool {
    if files.is_empty() {
        return false;
    }
    // Feed the file list into grep's stdin.
    let input = files.join("\n");
    let result = Command::new("grep")
        .arg("-qE")
        .arg(pattern)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .and_then(|mut child| {
            use std::io::Write;
            if let Some(ref mut stdin) = child.stdin {
                let _ = stdin.write_all(input.as_bytes());
            }
            child.wait()
        });
    match result {
        Ok(status) => status.success(),
        Err(_) => false,
    }
}

/// Port of check_gitleaks_allowlist_paths (lines 4021-4077).
pub fn check_gitleaks_allowlist_paths(ctx: &Context) {
    let toml_path = format!("{}/.gitleaks.toml", ctx.root);
    if !Path::new(&toml_path).is_file() {
        return;
    }

    let text = match fs::read_to_string(&toml_path) {
        Ok(c) => c,
        Err(_) => return,
    };

    let patterns = extract_gitleaks_paths(&text);
    let total = patterns.len();

    // Walk repo files for matching.
    let files = walk_files_pruned(&ctx.root, &ctx.root);

    let mut has_failures = false;

    for pat in &patterns {
        // Try to grep for the pattern.
        if !regex_matches_any_file(pat, &files) {
            // Determine if this is an invalid regex or just no match.
            let test = Command::new("grep")
                .arg("-qE")
                .arg(pat)
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::piped())
                .spawn()
                .and_then(|mut child| {
                    if let Some(ref mut stdin) = child.stdin {
                        use std::io::Write;
                        let _ = stdin.write_all(b"");
                    }
                    child.wait()
                });
            let found = match test {
                Ok(status) if status.code() == Some(2) => "invalid regex",
                _ => "matches no file",
            };
            ctx.emit_fail(
                "gitleaks",
                ".gitleaks.toml",
                found,
                "matches a file",
                &format!("allowlist path {pat}"),
                "point the path at where the file lives now, or delete the exemption",
            );
            has_failures = true;
        }
    }

    if !has_failures {
        ctx.emit_ok(
            "gitleaks",
            ".gitleaks.toml",
            &format!("{total} path(s)"),
            "matches a file",
            "every allowlisted path still matches a file",
        );
    }
}

// ---------------------------------------------------------------------------
// check_guard_review_paths
// ---------------------------------------------------------------------------

/// Convert a file-glob pattern (as used in guard_review.go) to a match
/// function. Handles `**` (any path), `*` (any segment), `?` (one char).
fn glob_matches(pattern: &str, path: &str) -> bool {
    let pat: Vec<char> = pattern.chars().collect();
    let txt: Vec<char> = path.chars().collect();
    glob_matches_rec(&pat, 0, &txt, 0)
}

fn glob_matches_rec(pat: &[char], pi: usize, txt: &[char], ti: usize) -> bool {
    if pi == pat.len() {
        return ti == txt.len();
    }
    // Check for `**`.
    if pi + 1 < pat.len() && pat[pi] == '*' && pat[pi + 1] == '*' {
        // `**` matches anything including `/`.
        for skip in 0..=(txt.len() - ti) {
            if glob_matches_rec(pat, pi + 2, txt, ti + skip) {
                return true;
            }
        }
        return false;
    }
    match pat[pi] {
        '*' => {
            // `*` matches anything except `/`.
            // Try matching zero or more non-/ characters.
            let mut skip = 0;
            loop {
                if glob_matches_rec(pat, pi + 1, txt, ti + skip) {
                    return true;
                }
                if ti + skip >= txt.len() || txt[ti + skip] == '/' {
                    break;
                }
                skip += 1;
            }
            false
        }
        '?' => {
            if ti < txt.len() && txt[ti] != '/' {
                glob_matches_rec(pat, pi + 1, txt, ti + 1)
            } else {
                false
            }
        }
        c => {
            if ti < txt.len() && txt[ti] == c {
                glob_matches_rec(pat, pi + 1, txt, ti + 1)
            } else {
                false
            }
        }
    }
}

/// Port of check_guard_review_paths (lines 3923-4005).
pub fn check_guard_review_paths(ctx: &Context) {
    let src_rel = "infrastructure/pulumi/platform/repo-config/guard_review.go";
    let src_path = format!("{}/{src_rel}", ctx.root);
    if !Path::new(&src_path).is_file() {
        return;
    }

    let src_content = match fs::read_to_string(&src_path) {
        Ok(c) => c,
        Err(_) => return,
    };

    // Find patterns between guard-review-paths:begin and guard-review-paths:end.
    let mut patterns: Vec<String> = Vec::new();
    if let Some(begin_pos) = src_content.find("guard-review-paths:begin") {
        if let Some(end_pos) = src_content[begin_pos..].find("guard-review-paths:end") {
            let section = &src_content[begin_pos..begin_pos + end_pos];
            for line in section.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("//") {
                    continue;
                }
                // Extract quoted strings.
                let mut search = trimmed;
                while let Some(q1) = search.find('"') {
                    let rest = &search[q1 + 1..];
                    if let Some(q2) = rest.find('"') {
                        patterns.push(rest[..q2].to_string());
                        search = &rest[q2 + 1..];
                    } else {
                        break;
                    }
                }
            }
        }
    }

    let total = patterns.len();

    if patterns.is_empty() {
        ctx.emit_fail(
            "guardreview",
            src_rel,
            "(none)",
            "matches a file",
            "no patterns found between the guard-review-paths markers: changes there would no longer need James's approval",
            "point the pattern at where the file lives now (a change to guard_review.go itself needs James)",
        );
        return;
    }

    // Walk repo files.
    let skip: HashSet<&str> = [
        ".git",
        "node_modules",
        ".cache",
        "dist",
        "build-output",
        ".pio",
    ]
    .iter()
    .copied()
    .collect();
    let mut files: Vec<String> = Vec::new();
    walk_rec(
        Path::new(&ctx.root),
        Path::new(&ctx.root),
        &skip,
        &mut files,
    );

    // Read the README for doc checks.
    let readme_path = format!("{}/tools/agent-guard/README.md", ctx.root);
    let readme = fs::read_to_string(&readme_path).unwrap_or_default();

    let mut has_failures = false;

    for p in &patterns {
        // Check if the glob matches any file.
        let matched = files.iter().any(|f| glob_matches(p, f));

        if !matched {
            // Check if the pattern is gitignored (which means the file may be absent
            // but is a valid local-only path).
            let ignored = Command::new("git")
                .args(["-C", &ctx.root, "check-ignore", "-q", p])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false);

            if !ignored {
                ctx.emit_fail(
                    "guardreview",
                    src_rel,
                    p,
                    "matches a file",
                    &format!(
                        "matches no file: changes there would no longer need James's approval"
                    ),
                    "point the pattern at where the file lives now (a change to guard_review.go itself needs James)",
                );
                has_failures = true;
            }
        }

        // Check documentation.
        let backticked = format!("`{p}`");
        if !readme.contains(&backticked) {
            ctx.emit_fail(
                "guardreview",
                "tools/agent-guard/README.md",
                p,
                "listed",
                "not listed in tools/agent-guard/README.md",
                &format!("add `{p}` to the README's \"Who may do what\" list"),
            );
            has_failures = true;
        }
    }

    if !has_failures {
        ctx.emit_ok(
            "guardreview",
            src_rel,
            &format!("{total} pattern(s)"),
            "matches a file",
            "every path that needs James's approval still names a file, and the README lists it",
        );
    }
}
