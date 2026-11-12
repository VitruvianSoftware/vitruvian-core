// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

pub const UPSTREAM_URL: &str = "https://github.com/vorssaint/vorssaint-utils";
pub const UPSTREAM_BRANCH: &str = "main";
pub const IMPORT_COMMIT: &str = "05ee8be1f69849d0f219d44f32de932bba1a3454";
pub const APP_DIR: &str = "apps/desktop/vitruvian";
pub const LEDGER: &str = "apps/desktop/vitruvian/upstream/ledger.tsv";

pub const UPSTREAM_ONLY: &[&str] = &[
    ".github/",
    "README.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "SUPPORT.md",
    "CHANGELOG.md",
    "docs/AI-CONTRIBUTIONS.md",
    "docs/assets/",
    "docs/demo.gif",
    "ReleaseAssets/",
    "Resources/Brand/",
];

pub const FORK_RETIRED: &[&str] = &[
    "Resources/Brand/make_placeholder_brand.py",
    "Tests/PreferenceCleanupTests.sh",
    "Tests/UninstallSpacesTests.sh",
    "Tests/generate_sources.py",
    "Tests/mutation_checks.py",
];

pub const STATUSES: &[&str] = &["pending", "ported", "skipped"];
pub const COLUMNS: &[&str] = &["sha", "patch_id", "date", "status", "ref", "subject"];

pub const LEDGER_PREAMBLE: &str = "\
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware
#
# Upstream vorssaint-utils commits since the import, oldest first, and what this
# fork did with each. `bazel run //apps/desktop/vitruvian:track_upstream -- triage`
# adds new commits; set status and ref by hand when you port or skip one.
#   status: pending | ported | skipped
#   ref:    ported -> the PR that ported it (#1234); skipped -> why; pending -> -
# See UPSTREAM.md, \"Tracking and porting upstream\".
";

pub const BRAND_SUBSTITUTIONS: &[(&str, &str)] = &[
    ("com.vorssaint.utils", "com.vitruviansoftware.vitruvian"),
    ("com.vorssaint.", "com.vitruviansoftware.vitruvian."),
    ("Vorssaint", "Vitruvian"),
    ("vorssaint", "vitruvian"),
    ("VORSSAINT", "VITRUVIAN"),
];

pub fn fork_split(path: &str) -> Option<&'static str> {
    match path {
        "Sources/Vorssaint/Core/Defaults.swift" => Some(
            "Core/DefaultsKey.swift (the keys), Core/Preferences.swift (each \
             setting's type and default) and Core/Defaults.swift (registration)",
        ),
        _ => None,
    }
}

pub fn git(
    args: &[&str],
    cwd: Option<&Path>,
    git_dir: Option<&Path>,
    check: bool,
    input: Option<&[u8]>,
) -> Result<std::process::Output, String> {
    let mut cmd = Command::new("git");
    if let Some(gd) = git_dir {
        cmd.arg("--git-dir").arg(gd);
    }
    cmd.args(args);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    if input.is_some() {
        cmd.stdin(Stdio::piped());
    }
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = cmd
        .spawn()
        .map_err(|e| format!("git {} spawn failed: {}", args.join(" "), e))?;
    if let Some(bytes) = input {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(bytes);
        }
    }
    let proc = child
        .wait_with_output()
        .map_err(|e| format!("git {} wait failed: {}", args.join(" "), e))?;
    if check && !proc.status.success() {
        let code = proc.status.code().unwrap_or(-1);
        let stderr = String::from_utf8_lossy(&proc.stderr).trim().to_string();
        return Err(format!(
            "git {} failed ({}): {}",
            args.join(" "),
            code,
            stderr
        ));
    }
    Ok(proc)
}

pub fn out(args: &[&str], cwd: Option<&Path>, git_dir: Option<&Path>) -> Result<String, String> {
    let proc = git(args, cwd, git_dir, true, None)?;
    Ok(String::from_utf8_lossy(&proc.stdout).to_string())
}

// --- Brand ----------------------------------------------------------------------

fn is_notice_line(line: &str) -> bool {
    line.contains("SPDX-License-Identifier")
        || line.contains("Copyright (C)")
        || line.contains("Copyright ©")
}

fn is_token_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | ':' | '/' | '-')
}

fn is_protected_token(token: &str) -> bool {
    let lower = token.to_ascii_lowercase();
    if lower.contains("vorssaint-utils")
        || lower.contains("github.com/vorssaint")
        || lower.contains("githubusercontent.com/vorssaint")
    {
        return true;
    }
    for tld in ["com", "net", "org", "io", "dev"] {
        let needle = format!("vorssaint.{}", tld);
        if let Some(idx) = lower.find(&needle) {
            let after = idx + needle.len();
            if after == lower.len()
                || !lower.as_bytes()[after].is_ascii_alphanumeric()
                    && lower.as_bytes()[after] != b'_'
            {
                return true;
            }
        }
    }
    false
}

fn substitute_brand(text: &str) -> String {
    let mut s = text.to_string();
    for (old, new) in BRAND_SUBSTITUTIONS {
        s = s.replace(old, new);
    }
    s
}

pub fn to_fork_line(line: &str) -> String {
    if is_notice_line(line) {
        return line.to_string();
    }
    let mut result = String::with_capacity(line.len());
    let chars: Vec<(usize, char)> = line.char_indices().collect();
    let mut i = 0;
    let mut last_byte = 0;
    while i < chars.len() {
        if is_token_char(chars[i].1) {
            let start_byte = chars[i].0;
            let mut j = i + 1;
            while j < chars.len() && is_token_char(chars[j].1) {
                j += 1;
            }
            let end_byte = if j < chars.len() {
                chars[j].0
            } else {
                line.len()
            };
            let token = &line[start_byte..end_byte];
            if is_protected_token(token) {
                result.push_str(&substitute_brand(&line[last_byte..start_byte]));
                // Trim trailing punctuation not part of protected URL if needed,
                // wait: PROTECTED_RE is [\w.:/-]*(?:...)[\w./-]*, so `:` is allowed before,
                // and `[\w./-]*` after.
                result.push_str(token);
                last_byte = end_byte;
            }
            i = j;
        } else {
            i += 1;
        }
    }
    result.push_str(&substitute_brand(&line[last_byte..]));
    result
}

pub fn to_fork(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for line in text.split_inclusive('\n') {
        out.push_str(&to_fork_line(line));
    }
    out
}

pub fn to_fork_bytes(data: Option<&[u8]>) -> Vec<u8> {
    let bytes = data.unwrap_or(&[]);
    let text = String::from_utf8_lossy(bytes);
    to_fork(&text).into_bytes()
}

pub fn brand_review(text: &str) -> Vec<(usize, String)> {
    let mut found = Vec::new();
    for (idx, line) in text.split_inclusive('\n').enumerate() {
        let lower = line.to_ascii_lowercase();
        if lower.contains("vorssaint") && !is_notice_line(line) {
            found.push((idx + 1, line.trim_end_matches('\n').to_string()));
        }
    }
    found
}

// --- Ledger ---------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LedgerRow {
    pub sha: String,
    pub patch_id: String,
    pub date: String,
    pub status: String,
    pub r#ref: String,
    pub subject: String,
    pub line: Option<usize>,
}

#[derive(Debug, Clone)]
pub struct Ledger {
    pub base: String,
    pub tree: String,
    pub rows: Vec<LedgerRow>,
}

impl Ledger {
    pub fn load(path: &Path) -> Result<Self, String> {
        let text = fs::read_to_string(path).map_err(|e| format!("{}: {}", path.display(), e))?;
        let mut base = None;
        let mut tree = None;
        let mut rows = Vec::new();
        for (idx, raw) in text.lines().enumerate() {
            let n = idx + 1;
            if let Some(rest) = raw.strip_prefix("# base\t") {
                let fields: Vec<&str> = raw[2..].split('\t').collect();
                if fields.len() != 4 || fields[2] != "tree" {
                    let _ = rest;
                    return Err(format!(
                        "{}:{}: base line is `# base<TAB>sha<TAB>tree<TAB>tree`",
                        path.display(),
                        n
                    ));
                }
                base = Some(fields[1].to_string());
                tree = Some(fields[3].to_string());
                continue;
            }
            if raw.trim().is_empty() || raw.starts_with('#') {
                continue;
            }
            let fields: Vec<&str> = raw.split('\t').collect();
            if fields.len() != COLUMNS.len() {
                return Err(format!(
                    "{}:{}: expected {} tab-separated columns, got {}",
                    path.display(),
                    n,
                    COLUMNS.len(),
                    fields.len()
                ));
            }
            rows.push(LedgerRow {
                sha: fields[0].to_string(),
                patch_id: fields[1].to_string(),
                date: fields[2].to_string(),
                status: fields[3].to_string(),
                r#ref: fields[4].to_string(),
                subject: fields[5].to_string(),
                line: Some(n),
            });
        }
        let Some(base) = base else {
            return Err(format!("{}: no `# base` line", path.display()));
        };
        let tree = tree.unwrap_or_default();
        Ok(Self { base, tree, rows })
    }

    pub fn errors(&self) -> Vec<String> {
        let mut errs = Vec::new();
        let mut seen: HashMap<String, String> = HashMap::new();
        for row in &self.rows {
            let line_str = row
                .line
                .map(|l| l.to_string())
                .unwrap_or_else(|| "new".to_string());
            let short_sha = &row.sha[..10.min(row.sha.len())];
            let where_str = format!("line {} ({})", line_str, short_sha);
            if !is_hex_40(&row.sha) {
                errs.push(format!("{}: sha is not a full commit id", where_str));
            }
            if let Some(prev) = seen.get(&row.sha) {
                errs.push(format!("{}: duplicate of line {}", where_str, prev));
            }
            seen.insert(row.sha.clone(), line_str);
            if !STATUSES.contains(&row.status.as_str()) {
                errs.push(format!(
                    "{}: status '{}' is not one of {}",
                    where_str,
                    row.status,
                    STATUSES.join(", ")
                ));
            } else if row.status == "ported" && !is_valid_ported_ref(&row.r#ref) {
                errs.push(format!(
                    "{}: a ported commit's ref is the PR that ported it, like #1234",
                    where_str
                ));
            } else if row.status == "skipped"
                && (row.r#ref.trim().is_empty() || row.r#ref.trim() == "-")
            {
                errs.push(format!("{}: a skipped commit's ref says why", where_str));
            }
        }
        errs
    }

    pub fn dump(&self) -> String {
        let mut out = String::new();
        out.push_str(LEDGER_PREAMBLE);
        out.push_str(&format!("# base\t{}\ttree\t{}\n", self.base, self.tree));
        out.push_str(&format!("# {}\n", COLUMNS.join("\t")));
        for row in &self.rows {
            let cols = [
                clean_field(&row.sha),
                clean_field(&row.patch_id),
                clean_field(&row.date),
                clean_field(&row.status),
                clean_field(&row.r#ref),
                clean_field(&row.subject),
            ];
            out.push_str(&cols.join("\t"));
            out.push('\n');
        }
        out
    }
}

fn clean_field(v: &str) -> String {
    v.replace('\t', " ").replace('\n', " ")
}

fn is_hex_40(s: &str) -> bool {
    s.len() == 40
        && s.bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn is_valid_ported_ref(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    for part in s.split(',') {
        let Some(digits) = part.strip_prefix('#') else {
            return false;
        };
        if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
            return false;
        }
    }
    true
}

// --- Upstream -------------------------------------------------------------------

pub struct Upstream {
    pub url: String,
    pub dir: PathBuf,
    pub r#ref: String,
}

impl Upstream {
    pub fn new(url: &str, cache_dir: &Path, fetch: bool) -> Result<Self, String> {
        let dir = cache_dir.join("vorssaint-utils.git");
        let r#ref = format!("refs/heads/{}", UPSTREAM_BRANCH);
        if !fetch {
            if !dir.exists() {
                return Err(format!(
                    "no upstream clone at {}; run without --no-fetch once",
                    dir.display()
                ));
            }
            return Ok(Self {
                url: url.to_string(),
                dir,
                r#ref,
            });
        }
        if !dir.exists() {
            if let Some(parent) = dir.parent() {
                fs::create_dir_all(parent).map_err(|e| e.to_string())?;
            }
            git(
                &[
                    "clone",
                    "--quiet",
                    "--bare",
                    "--filter=blob:limit=512k",
                    url,
                    dir.to_str().unwrap_or(""),
                ],
                None,
                None,
                true,
                None,
            )?;
        }
        git(
            &["remote", "set-url", "origin", url],
            None,
            Some(&dir),
            true,
            None,
        )?;
        let refspec = format!("+{}:{}", r#ref, r#ref);
        git(
            &["fetch", "--quiet", "--force", "origin", &refspec],
            None,
            Some(&dir),
            true,
            None,
        )?;
        Ok(Self {
            url: url.to_string(),
            dir,
            r#ref,
        })
    }

    pub fn run(&self, args: &[&str]) -> Result<String, String> {
        out(args, None, Some(&self.dir))
    }

    pub fn head(&self) -> Result<String, String> {
        Ok(self.run(&["rev-parse", &self.r#ref])?.trim().to_string())
    }

    pub fn tree_of(&self, commit: &str) -> Result<String, String> {
        let spec = format!("{}^{{tree}}", commit);
        Ok(self.run(&["rev-parse", &spec])?.trim().to_string())
    }

    pub fn resolve_base(&self, ledger: &Ledger) -> Result<(String, bool), String> {
        let reachable = git(
            &["merge-base", "--is-ancestor", &ledger.base, &self.r#ref],
            None,
            Some(&self.dir),
            false,
            None,
        )?
        .status
        .success();
        if reachable {
            return Ok((ledger.base.clone(), false));
        }
        let log_out = self.run(&["log", "--reverse", "--format=%H %T", &self.r#ref])?;
        for line in log_out.lines() {
            let mut parts = line.split_whitespace();
            if let (Some(commit), Some(tree)) = (parts.next(), parts.next()) {
                if tree == ledger.tree {
                    return Ok((commit.to_string(), true));
                }
            }
        }
        let short_base = &ledger.base[..10.min(ledger.base.len())];
        let short_tree = &ledger.tree[..10.min(ledger.tree.len())];
        Err(format!(
            "base {} is not on upstream {} and no commit there has its tree {}; upstream rewrote history past it. Find the matching commit by hand and set the `# base` line.",
            short_base, UPSTREAM_BRANCH, short_tree
        ))
    }

    pub fn commits_since(&self, base: &str) -> Result<Vec<(String, String, String)>, String> {
        let fmt = "--format=%H%x00%as%x00%P%x00%s";
        let range = format!("{}..{}", base, self.r#ref);
        let raw = self.run(&["log", "--reverse", "--topo-order", fmt, &range])?;
        let mut result = Vec::new();
        for line in raw.lines() {
            let parts: Vec<&str> = line.splitn(4, '\0').collect();
            if parts.len() != 4 {
                continue;
            }
            let (sha, date, parents, subject) = (parts[0], parts[1], parts[2], parts[3]);
            if parents.split_whitespace().count() > 1 && self.merge_paths(sha)?.is_empty() {
                continue;
            }
            result.push((sha.to_string(), date.to_string(), subject.to_string()));
        }
        Ok(result)
    }

    pub fn is_merge(&self, commit: &str) -> Result<bool, String> {
        let out = self.run(&["rev-list", "--parents", "-n", "1", commit])?;
        Ok(out.split_whitespace().count() > 2)
    }

    pub fn merge_diff(&self, commit: &str, paths: &[String]) -> Result<String, String> {
        let mut args = vec!["show", "--remerge-diff", "--format=", commit];
        if !paths.is_empty() {
            args.push("--");
            for p in paths {
                args.push(p.as_str());
            }
        }
        self.run(&args)
    }

    pub fn merge_paths(&self, commit: &str) -> Result<Vec<String>, String> {
        let raw = self.run(&[
            "show",
            "--remerge-diff",
            "--format=",
            "--name-only",
            "-z",
            commit,
        ])?;
        Ok(raw
            .split('\0')
            .filter(|p| !p.is_empty())
            .map(|p| p.to_string())
            .collect())
    }

    pub fn patch_ids(&self, base: &str) -> Result<HashMap<String, String>, String> {
        let range = format!("{}..{}", base, self.r#ref);
        let diff = git(
            &["log", "--no-merges", "--format=%H", "-p", &range],
            None,
            Some(&self.dir),
            true,
            None,
        )?
        .stdout;
        let patch_out = git(
            &["patch-id", "--stable"],
            None,
            Some(&self.dir),
            true,
            Some(&diff),
        )?
        .stdout;
        let mut ids = HashMap::new();
        for line in String::from_utf8_lossy(&patch_out).lines() {
            let mut parts = line.split_whitespace();
            if let (Some(pid), Some(sha)) = (parts.next(), parts.next()) {
                ids.insert(sha.to_string(), pid.to_string());
            }
        }
        Ok(ids)
    }

    pub fn paths(&self, commit: &str) -> Result<Vec<String>, String> {
        if self.is_merge(commit)? {
            return self.merge_paths(commit);
        }
        let raw = self.run(&[
            "diff-tree",
            "--no-commit-id",
            "--name-only",
            "-r",
            "-z",
            "--root",
            commit,
        ])?;
        Ok(raw
            .split('\0')
            .filter(|p| !p.is_empty())
            .map(|p| p.to_string())
            .collect())
    }

    pub fn changes(&self, commit: &str) -> Result<Vec<(String, String, String)>, String> {
        let raw_str = self.run(&[
            "diff-tree",
            "--no-commit-id",
            "-r",
            "-M",
            "-z",
            "--root",
            "--name-status",
            commit,
        ])?;
        let raw: Vec<&str> = raw_str.split('\0').filter(|x| !x.is_empty()).collect();
        let mut changes = Vec::new();
        let mut i = 0;
        while i < raw.len() {
            let status = raw[i];
            let code = status.chars().next().unwrap_or('M').to_string();
            if code == "R" || code == "C" {
                if i + 2 < raw.len() {
                    changes.push((code, raw[i + 1].to_string(), raw[i + 2].to_string()));
                }
                i += 3;
            } else {
                if i + 1 < raw.len() {
                    changes.push((code, raw[i + 1].to_string(), raw[i + 1].to_string()));
                }
                i += 2;
            }
        }
        Ok(changes)
    }

    pub fn blob(&self, commit: &str, path: &str) -> Option<Vec<u8>> {
        let spec = format!("{}:{}", commit, path);
        let proc = git(
            &["cat-file", "-p", &spec],
            None,
            Some(&self.dir),
            false,
            None,
        )
        .ok()?;
        if proc.status.success() {
            Some(proc.stdout)
        } else {
            None
        }
    }

    pub fn is_binary(&self, commit: &str, path: &str) -> Result<bool, String> {
        let stat = self.run(&[
            "diff-tree",
            "--no-commit-id",
            "-r",
            "--numstat",
            "--root",
            commit,
            "--",
            path,
        ])?;
        Ok(stat.starts_with("-\t-\t"))
    }
}

pub fn upstream_only(path: &str) -> bool {
    UPSTREAM_ONLY
        .iter()
        .any(|p| path == *p || (p.ends_with('/') && path.starts_with(p)))
}

#[derive(Debug, Clone)]
pub struct UntriagedCommit {
    pub sha: String,
    pub patch_id: String,
    pub date: String,
    pub subject: String,
    pub auto_skip: bool,
}

pub struct Triage {
    pub base: String,
    pub reanchored: bool,
    pub head: String,
    pub untriaged: Vec<UntriagedCommit>,
    pub rekeyed: Vec<(usize, String)>,
    pub pending: Vec<LedgerRow>,
    pub orphaned: Vec<LedgerRow>,
}

impl Triage {
    pub fn new(upstream: &Upstream, ledger: &Ledger) -> Result<Self, String> {
        let (base, reanchored) = upstream.resolve_base(ledger)?;
        let head = upstream.head()?;
        let commits = upstream.commits_since(&base)?;
        let ids = upstream.patch_ids(&base)?;

        let mut by_sha: HashMap<&str, usize> = HashMap::new();
        let mut by_patch: HashMap<&str, usize> = HashMap::new();
        for (idx, r) in ledger.rows.iter().enumerate() {
            by_sha.insert(r.sha.as_str(), idx);
            if r.patch_id != "-" {
                by_patch.insert(r.patch_id.as_str(), idx);
            }
        }

        let mut untriaged = Vec::new();
        let mut rekeyed = Vec::new();
        let mut live = HashSet::new();

        for (sha, date, subject) in commits {
            let patch_id = ids.get(&sha).cloned().unwrap_or_else(|| "-".to_string());
            let mut row_idx = by_sha.get(sha.as_str()).copied();
            if row_idx.is_none() && patch_id != "-" {
                if let Some(&idx) = by_patch.get(patch_id.as_str()) {
                    row_idx = Some(idx);
                    rekeyed.push((idx, sha.clone()));
                }
            }
            if let Some(idx) = row_idx {
                live.insert(idx);
                continue;
            }
            let paths = upstream.paths(&sha)?;
            let auto_skip = !paths.is_empty() && paths.iter().all(|p| upstream_only(p));
            untriaged.push(UntriagedCommit {
                sha,
                patch_id,
                date,
                subject,
                auto_skip,
            });
        }

        let pending = ledger
            .rows
            .iter()
            .filter(|r| r.status == "pending")
            .cloned()
            .collect();
        let orphaned = ledger
            .rows
            .iter()
            .enumerate()
            .filter(|(idx, _)| !live.contains(idx))
            .map(|(_, r)| r.clone())
            .collect();

        Ok(Self {
            base,
            reanchored,
            head,
            untriaged,
            rekeyed,
            pending,
            orphaned,
        })
    }

    pub fn apply(&self, ledger: &mut Ledger) {
        for (idx, new_sha) in &self.rekeyed {
            if let Some(row) = ledger.rows.get_mut(*idx) {
                row.sha = new_sha.clone();
            }
        }
        if self.reanchored {
            ledger.base = self.base.clone();
        }
        for c in &self.untriaged {
            let (status, r#ref) = if c.auto_skip {
                ("skipped", "touches only upstream-only paths")
            } else {
                ("pending", "-")
            };
            ledger.rows.push(LedgerRow {
                sha: c.sha.clone(),
                patch_id: c.patch_id.clone(),
                date: c.date.clone(),
                status: status.to_string(),
                r#ref: r#ref.to_string(),
                subject: c.subject.clone(),
                line: None,
            });
        }
    }
}

// --- Path mapping ---------------------------------------------------------------

pub struct PathMap {
    pub root: PathBuf,
    pub renamed: HashMap<String, String>,
    pub deleted: HashSet<String>,
    pub at_import: HashSet<String>,
    pub current: BTreeSet<String>,
    pub by_name: HashMap<String, Vec<String>>,
    pub dir_moves: HashMap<String, String>,
}

impl PathMap {
    pub fn new(root: &Path, import_commit: &str) -> Result<Self, String> {
        let prefix = format!("{}/", APP_DIR);
        let mut renamed = HashMap::new();
        let mut deleted = HashSet::new();

        let raw_str = out(
            &[
                "diff",
                "-M50%",
                "--name-status",
                "-z",
                import_commit,
                "HEAD",
                "--",
                APP_DIR,
            ],
            Some(root),
            None,
        )?;
        let raw: Vec<&str> = raw_str.split('\0').filter(|x| !x.is_empty()).collect();
        let mut i = 0;
        while i < raw.len() {
            let status = raw[i];
            if status.starts_with('R') {
                if i + 2 < raw.len() {
                    let old = raw[i + 1].strip_prefix(&prefix).unwrap_or(raw[i + 1]);
                    let new = raw[i + 2].strip_prefix(&prefix).unwrap_or(raw[i + 2]);
                    renamed.insert(old.to_string(), new.to_string());
                }
                i += 3;
            } else {
                if status.starts_with('D') && i + 1 < raw.len() {
                    let old = raw[i + 1].strip_prefix(&prefix).unwrap_or(raw[i + 1]);
                    deleted.insert(old.to_string());
                }
                i += 2;
            }
        }

        let ls_tree = out(
            &["ls-tree", "-r", "--name-only", import_commit, "--", APP_DIR],
            Some(root),
            None,
        )?;
        let at_import: HashSet<String> = ls_tree
            .lines()
            .map(|p| p.strip_prefix(&prefix).unwrap_or(p).to_string())
            .collect();

        let ls_files = out(&["ls-files", "--", APP_DIR], Some(root), None)?;
        let current: BTreeSet<String> = ls_files
            .lines()
            .map(|p| p.strip_prefix(&prefix).unwrap_or(p).to_string())
            .collect();

        let mut by_name: HashMap<String, Vec<String>> = HashMap::new();
        for p in &current {
            let base = basename(p).to_string();
            by_name.entry(base).or_default().push(p.clone());
        }

        let mut moves: HashMap<String, BTreeMap<String, usize>> = HashMap::new();
        for (old, new) in &renamed {
            let old_dir = dirname(old).to_string();
            let new_dir = dirname(new).to_string();
            *moves
                .entry(old_dir)
                .or_default()
                .entry(new_dir)
                .or_insert(0) += 1;
        }
        let mut dir_moves = HashMap::new();
        for (d, counts) in moves {
            if let Some((best_dir, _)) = counts.into_iter().max_by_key(|(_, c)| *c) {
                dir_moves.insert(d, best_dir);
            }
        }

        Ok(Self {
            root: root.to_path_buf(),
            renamed,
            deleted,
            at_import,
            current,
            by_name,
            dir_moves,
        })
    }

    pub fn map(&self, upath: &str) -> (Option<String>, &'static str) {
        if let Some(r) = self.renamed.get(upath) {
            return (Some(r.clone()), "renamed");
        }
        if self.at_import.contains(upath) && self.current.contains(upath) {
            return (Some(upath.to_string()), "same path");
        }
        if self.at_import.contains(upath) || self.deleted.contains(upath) {
            if let Some(matches) = self.by_name.get(basename(upath)) {
                if matches.len() == 1 {
                    return (Some(matches[0].clone()), "guess: same file name");
                }
            }
            return (None, "removed or split by the refactor");
        }
        let ported_name = to_fork_line(basename(upath));
        if let Some(ported) = self.by_name.get(&ported_name) {
            if ported.len() == 1 {
                return (
                    Some(ported[0].clone()),
                    "added upstream since the import, ported earlier",
                );
            }
        }
        (
            Some(self.new_path(upath)),
            "new upstream file, placed beside its siblings",
        )
    }

    fn new_path(&self, upath: &str) -> String {
        let mut d = dirname(upath).to_string();
        let mut tail = vec![to_fork_line(basename(upath))];
        loop {
            if let Some(mapped) = self.dir_moves.get(&d) {
                if mapped.is_empty() {
                    return tail.join("/");
                }
                return format!("{}/{}", mapped, tail.join("/"));
            }
            let d_slash = format!("{}/", d);
            if d.is_empty() || self.current.iter().any(|p| p.starts_with(&d_slash)) {
                if d.is_empty() {
                    return tail.join("/");
                }
                return format!("{}/{}", d, tail.join("/"));
            }
            tail.insert(0, to_fork_line(basename(&d)));
            d = dirname(&d).to_string();
        }
    }
}

fn basename(p: &str) -> &str {
    p.rsplit('/').next().unwrap_or(p)
}

fn dirname(p: &str) -> &str {
    match p.rfind('/') {
        Some(idx) => &p[..idx],
        None => "",
    }
}

// --- Port & Swift Modifiers -----------------------------------------------------

/// Returns the byte length of leading whitespace and `@Attribute(...) ` prefixes on `line`.
pub fn attributes_prefix_len(line: &str) -> usize {
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() && (bytes[i] == b' ' || bytes[i] == b'\t') {
        i += 1;
    }
    loop {
        if i < bytes.len() && bytes[i] == b'@' {
            let mut j = i + 1;
            while j < bytes.len()
                && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_' || bytes[j] == b'.')
            {
                j += 1;
            }
            if j == i + 1 {
                break;
            }
            if j < bytes.len() && bytes[j] == b'(' {
                let mut k = j + 1;
                while k < bytes.len() && bytes[k] != b')' && bytes[k] != b'\n' {
                    k += 1;
                }
                if k < bytes.len() && bytes[k] == b')' {
                    j = k + 1;
                } else {
                    break;
                }
            }
            let ws_start = j;
            while j < bytes.len() && (bytes[j] == b' ' || bytes[j] == b'\t') {
                j += 1;
            }
            if j > ws_start {
                i = j;
                continue;
            }
        }
        break;
    }
    i
}

/// Checks if `line` starts with `PACKAGE_RE` (`^([ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*)package[ \t]+(?=\S)`).
/// If so, returns `(prefix_len, after_package_ws_len)`.
pub fn match_package_prefix(line: &str) -> Option<(usize, usize)> {
    let p_len = attributes_prefix_len(line);
    let rest = &line[p_len..];
    let after_pkg = rest.strip_prefix("package")?;
    let bytes = after_pkg.as_bytes();
    let mut ws = 0;
    while ws < bytes.len() && (bytes[ws] == b' ' || bytes[ws] == b'\t') {
        ws += 1;
    }
    if ws == 0 {
        return None;
    }
    // (?=\S) means next char exists and is not whitespace (including \n/\r)
    let next_ch = after_pkg[ws..].chars().next()?;
    if next_ch.is_whitespace() {
        return None;
    }
    Some((p_len, p_len + "package".len() + ws))
}

pub fn strip_package_line(line: &str) -> String {
    if let Some((p_len, after_len)) = match_package_prefix(line) {
        format!("{}{}", &line[..p_len], &line[after_len..])
    } else {
        line.to_string()
    }
}

pub fn strip_package(data: &[u8]) -> Vec<u8> {
    let text = String::from_utf8_lossy(data);
    let mut out = String::with_capacity(text.len());
    for line in text.split_inclusive('\n') {
        out.push_str(&strip_package_line(line));
    }
    out.into_bytes()
}

const DECL_MODIFIERS: &[&str] = &[
    "package",
    "static",
    "class",
    "final",
    "override",
    "private(set)",
    "fileprivate(set)",
    "mutating",
    "nonmutating",
    "nonisolated(unsafe)",
    "nonisolated",
    "convenience",
    "required",
    "lazy",
    "weak",
    "unowned",
    "indirect",
    "dynamic",
];

const DECL_KEYWORDS: &[&str] = &[
    "func",
    "var",
    "let",
    "struct",
    "class",
    "enum",
    "protocol",
    "typealias",
    "init",
    "subscript",
    "extension",
    "actor",
];

const TYPE_KINDS: &[&str] = &["struct", "class", "enum", "extension", "actor"];
const NAMED_TYPE_KINDS: &[&str] = &["struct", "class", "enum", "actor", "protocol", "typealias"];

/// Equivalent to `_decl_key(line)` in `upstream.py`: returns `(indent, kind, name)`.
pub fn decl_key(line: &str) -> Option<(String, String, Option<String>)> {
    let indent_len = line.len() - line.trim_start_matches([' ', '\t']).len();
    let indent = line[..indent_len].to_string();
    let mut pos = attributes_prefix_len(line);
    let bytes = line.as_bytes();

    loop {
        let rest = &line[pos..];
        let mut matched_mod = None;
        for &m in DECL_MODIFIERS {
            if let Some(after) = rest.strip_prefix(m) {
                if after.starts_with(' ') || after.starts_with('\t') {
                    // Notice: "class" can be either a modifier (`class func`, `class var`) or the decl kind (`class Foo`).
                    if m == "class" {
                        let after_ws = after.trim_start_matches([' ', '\t']);
                        let next_word: String = after_ws
                            .chars()
                            .take_while(|c| {
                                c.is_ascii_alphanumeric() || *c == '_' || *c == '(' || *c == ')'
                            })
                            .collect();
                        if !DECL_MODIFIERS.contains(&next_word.as_str())
                            && !DECL_KEYWORDS.contains(&next_word.as_str())
                        {
                            continue;
                        }
                    }
                    matched_mod = Some(m.len());
                    break;
                }
            }
        }
        if let Some(len) = matched_mod {
            pos += len;
            while pos < bytes.len() && (bytes[pos] == b' ' || bytes[pos] == b'\t') {
                pos += 1;
            }
        } else {
            break;
        }
    }

    let rest = &line[pos..];
    for &kw in DECL_KEYWORDS {
        if let Some(after) = rest.strip_prefix(kw) {
            let boundary = after
                .chars()
                .next()
                .map(|c| !c.is_ascii_alphanumeric() && c != '_')
                .unwrap_or(true);
            if !boundary {
                continue;
            }
            let after_ws = after.trim_start_matches([' ', '\t']);
            let mut chars = after_ws.chars();
            let name = if let Some(first) = chars.next() {
                if first.is_ascii_alphabetic() || first == '_' || first == '`' {
                    let mut n = String::from(first);
                    for c in chars {
                        if c.is_ascii_alphanumeric() || c == '_' || c == '`' {
                            n.push(c);
                        } else {
                            break;
                        }
                    }
                    Some(n)
                } else {
                    None
                }
            } else {
                None
            };
            return Some((indent, kw.to_string(), name));
        }
    }
    None
}

fn line_indent(line: &str) -> usize {
    line.len() - line.trim_start_matches([' ', '\t']).len()
}

fn has_access_modifier(prefix: &str) -> bool {
    // ACCESS_RE: \b(?:private|fileprivate|internal|public|open|package)\b(?!\(set\))
    for word in [
        "private",
        "fileprivate",
        "internal",
        "public",
        "open",
        "package",
    ] {
        let mut start = 0;
        while let Some(idx) = prefix[start..].find(word) {
            let abs = start + idx;
            let before_ok = abs == 0
                || !prefix.as_bytes()[abs - 1].is_ascii_alphanumeric()
                    && prefix.as_bytes()[abs - 1] != b'_';
            let after = abs + word.len();
            let after_ok = after == prefix.len()
                || !prefix.as_bytes()[after].is_ascii_alphanumeric()
                    && prefix.as_bytes()[after] != b'_';
            let not_set = !prefix[after..].starts_with("(set)");
            if before_ok && after_ok && not_set {
                return true;
            }
            start = after;
        }
    }
    false
}

fn takes_modifiers(lines: &[String], i: usize) -> bool {
    let depth = line_indent(&lines[i]);
    if depth == 0 {
        return true;
    }
    for j in (0..i).rev() {
        if !lines[j].trim().is_empty() && line_indent(&lines[j]) < depth {
            if let Some((_, kind, _)) = decl_key(&lines[j]) {
                return TYPE_KINDS.contains(&kind.as_str());
            }
            return false;
        }
    }
    false
}

fn signature_of(lines: &[String], i: usize) -> String {
    let key = decl_key(&lines[i]);
    let mut text = String::new();
    let mut balance: i32 = 0;
    for line in &lines[i..] {
        text.push_str(line);
        balance += line.matches('(').count() as i32 - line.matches(')').count() as i32;
        if balance <= 0 {
            break;
        }
    }
    if let Some((before, _)) = text.split_once('{') {
        text = before.to_string();
    }
    if let Some((_, ref kind, _)) = key {
        if kind == "var" || kind == "let" {
            if let Some((before, _)) = text.split_once('=') {
                text = before.to_string();
            }
        }
    }
    text
}

fn contains_word(haystack: &str, word: &str) -> bool {
    if word.is_empty() {
        return false;
    }
    let mut start = 0;
    while let Some(idx) = haystack[start..].find(word) {
        let abs = start + idx;
        let before_ok = abs == 0
            || !haystack.as_bytes()[abs - 1].is_ascii_alphanumeric()
                && haystack.as_bytes()[abs - 1] != b'_';
        let after = abs + word.len();
        let after_ok = after == haystack.len()
            || !haystack.as_bytes()[after].is_ascii_alphanumeric()
                && haystack.as_bytes()[after] != b'_';
        if before_ok && after_ok {
            return true;
        }
        start = after;
    }
    false
}

fn publish_used_types(lines: &mut [String], kept: &HashMap<usize, String>) {
    let mut used = String::new();
    for i in 0..lines.len() {
        if decl_key(&lines[i]).is_some() && match_package_prefix(&lines[i]).is_some() {
            if !used.is_empty() {
                used.push(' ');
            }
            used.push_str(&signature_of(lines, i));
        }
    }
    for i in 0..lines.len() {
        if kept.contains_key(&i) {
            continue;
        }
        let Some((_, kind, Some(name))) = decl_key(&lines[i]) else {
            continue;
        };
        if !NAMED_TYPE_KINDS.contains(&kind.as_str()) {
            continue;
        }
        let kind_pos = lines[i].find(&kind).unwrap_or(0);
        if has_access_modifier(&lines[i][..kind_pos]) {
            continue;
        }
        if takes_modifiers(lines, i) && contains_word(&used, &name) {
            let at = attributes_prefix_len(&lines[i]);
            let updated = format!("{}package {}", &lines[i][..at], &lines[i][at..]);
            lines[i] = updated;
        }
    }
}

/// SequenceMatcher-like longest-common-matching blocks for lines.
fn matching_blocks(a: &[String], b: &[String]) -> Vec<(usize, usize, usize)> {
    let mut blocks = Vec::new();
    find_matching_blocks(a, 0, a.len(), b, 0, b.len(), &mut blocks);
    blocks.sort_by_key(|x| (x.0, x.1));
    blocks
}

fn find_matching_blocks(
    a: &[String],
    alo: usize,
    ahi: usize,
    b: &[String],
    blo: usize,
    bhi: usize,
    out: &mut Vec<(usize, usize, usize)>,
) {
    let (mut best_i, mut best_j, mut best_size) = (alo, blo, 0);
    let mut j2len: HashMap<usize, usize> = HashMap::new();
    for i in alo..ahi {
        let mut new_j2len: HashMap<usize, usize> = HashMap::new();
        for j in blo..bhi {
            if a[i] == b[j] {
                let k = j2len.get(&j.wrapping_sub(1)).copied().unwrap_or(0) + 1;
                new_j2len.insert(j, k);
                if k > best_size {
                    best_i = i + 1 - k;
                    best_j = j + 1 - k;
                    best_size = k;
                }
            }
        }
        j2len = new_j2len;
    }
    if best_size > 0 {
        if alo < best_i && blo < best_j {
            find_matching_blocks(a, alo, best_i, b, blo, best_j, out);
        }
        out.push((best_i, best_j, best_size));
        if best_i + best_size < ahi && best_j + best_size < bhi {
            find_matching_blocks(a, best_i + best_size, ahi, b, best_j + best_size, bhi, out);
        }
    }
}

pub fn restore_package(merged: &[u8], ours: &[u8]) -> Vec<u8> {
    let ours_str = String::from_utf8_lossy(ours);
    let ours_lines: Vec<String> = ours_str
        .split_inclusive('\n')
        .map(|s| s.to_string())
        .collect();
    let ours_bare: Vec<String> = ours_lines.iter().map(|r| strip_package_line(r)).collect();

    let mut by_decl: HashMap<(String, String, Option<String>), HashSet<bool>> = HashMap::new();
    let mut by_level: HashMap<(String, String), (usize, usize)> = HashMap::new();
    for (raw, bare) in ours_lines.iter().zip(ours_bare.iter()) {
        if let Some(key) = decl_key(bare) {
            let has_pkg = bare != raw;
            let level_key = (key.0.clone(), key.1.clone());
            by_decl.entry(key).or_default().insert(has_pkg);
            let entry = by_level.entry(level_key).or_insert((0, 0));
            if has_pkg {
                entry.0 += 1;
            } else {
                entry.1 += 1;
            }
        }
    }

    let merged_str = String::from_utf8_lossy(merged);
    let mut lines: Vec<String> = merged_str
        .split_inclusive('\n')
        .map(|s| s.to_string())
        .collect();

    let mut kept: HashMap<usize, String> = HashMap::new();
    for (a, b, size) in matching_blocks(&ours_bare, &lines) {
        for k in 0..size {
            kept.insert(b + k, ours_lines[a + k].clone());
        }
    }

    let mut result = Vec::with_capacity(lines.len());
    let mut i = 0;
    while i < lines.len() {
        let mut line = lines[i].clone();
        let key = decl_key(&line);
        if let Some(k_line) = kept.get(&i) {
            line = k_line.clone();
        } else if let Some(ref k) = key {
            if match_package_prefix(&line).is_none() && takes_modifiers(&lines, i) {
                let known = by_decl.get(k);
                let (t_count, f_count) = by_level
                    .get(&(k.0.clone(), k.1.clone()))
                    .copied()
                    .unwrap_or((0, 0));
                let known_only_true = known
                    .map(|s| s.len() == 1 && s.contains(&true))
                    .unwrap_or(false);
                let kind_pos = line.find(&k.1).unwrap_or(0);
                let should_add = known_only_true
                    || (known.is_none()
                        && k.1 != "extension"
                        && !has_access_modifier(&line[..kind_pos])
                        && t_count > f_count);
                if should_add {
                    let at = attributes_prefix_len(&line);
                    line = format!("{}package {}", &line[..at], &line[at..]);
                    let mut shift_from = i + 1;
                    let mut balance =
                        line.matches('(').count() as i32 - line.matches(')').count() as i32;
                    let hanging = line.trim_end().ends_with('(');
                    let base_indent = line_indent(&line);
                    while balance > 0 && !hanging && shift_from < lines.len() {
                        let nxt = &lines[shift_from];
                        if line_indent(nxt) <= base_indent {
                            break;
                        }
                        lines[shift_from] = format!("        {}", nxt);
                        balance += lines[shift_from].matches('(').count() as i32
                            - lines[shift_from].matches(')').count() as i32;
                        shift_from += 1;
                    }
                }
            }
        }
        result.push(line);
        i += 1;
    }
    publish_used_types(&mut result, &kept);
    result.concat().into_bytes()
}

pub fn merge3(
    ours: &[u8],
    base: &[u8],
    theirs: &[u8],
    labels: (&str, &str, &str),
) -> Result<(Vec<u8>, i32), String> {
    let (merged, conflicts) = merge_file(
        &strip_package(ours),
        &strip_package(base),
        &strip_package(theirs),
        labels,
    )?;
    Ok((restore_package(&merged, ours), conflicts))
}

static MERGE_COUNTER: AtomicU64 = AtomicU64::new(0);

fn merge_file(
    ours: &[u8],
    base: &[u8],
    theirs: &[u8],
    labels: (&str, &str, &str),
) -> Result<(Vec<u8>, i32), String> {
    let id = MERGE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let tmp = env::temp_dir().join(format!("vitruvian-merge3-{}-{}", std::process::id(), id));
    fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
    let ours_p = tmp.join("ours");
    let base_p = tmp.join("base");
    let theirs_p = tmp.join("theirs");
    fs::write(&ours_p, ours).map_err(|e| e.to_string())?;
    fs::write(&base_p, base).map_err(|e| e.to_string())?;
    fs::write(&theirs_p, theirs).map_err(|e| e.to_string())?;

    let proc = git(
        &[
            "merge-file",
            "-p",
            "--diff3",
            "-L",
            labels.0,
            "-L",
            labels.1,
            "-L",
            labels.2,
            ours_p.to_str().unwrap_or(""),
            base_p.to_str().unwrap_or(""),
            theirs_p.to_str().unwrap_or(""),
        ],
        None,
        None,
        false,
        None,
    )?;
    let _ = fs::remove_dir_all(&tmp);
    let code = proc.status.code().unwrap_or(-1);
    if code < 0 {
        return Err(format!(
            "git merge-file failed: {}",
            String::from_utf8_lossy(&proc.stderr)
        ));
    }
    Ok((proc.stdout, code))
}

fn match_stored_property(line: &str) -> Option<(String, &str)> {
    // Matches STORED_RE in upstream.py:
    // [ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*(?:(?:package|public|internal|private|fileprivate|private\(set\)|fileprivate\(set\)|nonisolated(?:\(unsafe\))?|lazy|weak|unowned)[ \t]+)*(?:var|let)[ \t]+([A-Za-z_]\w*)[^{=\n]*(=|\{|$)
    let mut pos = attributes_prefix_len(line);
    let bytes = line.as_bytes();
    const STORED_MODS: &[&str] = &[
        "package",
        "public",
        "internal",
        "private(set)",
        "fileprivate(set)",
        "private",
        "fileprivate",
        "nonisolated(unsafe)",
        "nonisolated",
        "lazy",
        "weak",
        "unowned",
    ];
    loop {
        let rest = &line[pos..];
        let mut matched = None;
        for &m in STORED_MODS {
            if let Some(after) = rest.strip_prefix(m) {
                if after.starts_with(' ') || after.starts_with('\t') {
                    matched = Some(m.len());
                    break;
                }
            }
        }
        if let Some(len) = matched {
            pos += len;
            while pos < bytes.len() && (bytes[pos] == b' ' || bytes[pos] == b'\t') {
                pos += 1;
            }
        } else {
            break;
        }
    }
    let rest = &line[pos..];
    let after_kw = rest
        .strip_prefix("var")
        .or_else(|| rest.strip_prefix("let"))?;
    if !after_kw.starts_with(' ') && !after_kw.starts_with('\t') {
        return None;
    }
    let after_ws = after_kw.trim_start_matches([' ', '\t']);
    let mut chars = after_ws.chars();
    let first = chars.next()?;
    if !first.is_ascii_alphabetic() && first != '_' {
        return None;
    }
    let mut name = String::from(first);
    for c in chars {
        if c.is_ascii_alphanumeric() || c == '_' {
            name.push(c);
        } else {
            break;
        }
    }
    let tail = &after_ws[name.len()..];
    let mut term = "";
    for ch in tail.chars() {
        if ch == '=' {
            term = "=";
            break;
        } else if ch == '{' {
            term = "{";
            break;
        } else if ch == '\n' {
            break;
        }
    }
    Some((name, term))
}

fn spelled_out_inits(lines: &[String]) -> HashMap<String, (BTreeMap<String, usize>, String)> {
    let mut found = HashMap::new();
    for (i, line) in lines.iter().enumerate() {
        if !line.contains("Spelled out because a memberwise initializer") {
            continue;
        }
        let mut j = i + 1;
        while j < lines.len() {
            let trimmed = lines[j].trim();
            if trimmed.starts_with("package init(") || trimmed.starts_with("public init(") {
                break;
            }
            j += 1;
        }
        if j == lines.len() {
            continue;
        }
        let depth = line_indent(&lines[j]);
        let mut owner = None;
        for k in (0..j).rev() {
            if !lines[k].trim().is_empty() && line_indent(&lines[k]) < depth {
                owner = Some(k);
                break;
            }
        }
        let Some(owner_idx) = owner else {
            continue;
        };
        let Some((_, kind, Some(type_name))) = decl_key(&lines[owner_idx]) else {
            continue;
        };
        if kind != "struct" && kind != "class" {
            continue;
        }
        let mut stored = BTreeMap::new();
        for (k, k_line) in lines.iter().enumerate().skip(owner_idx + 1) {
            if !k_line.trim().is_empty() && line_indent(k_line) < depth {
                break;
            }
            if line_indent(k_line) == depth
                && !contains_word(k_line, "static")
                && !has_private_non_set_modifier(k_line)
            {
                if let Some((prop_name, term)) = match_stored_property(k_line) {
                    if term != "{" {
                        stored.insert(prop_name, k + 1);
                    }
                }
            }
        }
        found.insert(type_name, (stored, signature_of(lines, j)));
    }
    found
}

fn has_private_non_set_modifier(line: &str) -> bool {
    for word in ["private", "fileprivate"] {
        let mut start = 0;
        while let Some(idx) = line[start..].find(word) {
            let abs = start + idx;
            let before_ok = abs == 0
                || !line.as_bytes()[abs - 1].is_ascii_alphanumeric()
                    && line.as_bytes()[abs - 1] != b'_';
            let after = abs + word.len();
            let after_ok = after == line.len()
                || !line.as_bytes()[after].is_ascii_alphanumeric()
                    && line.as_bytes()[after] != b'_';
            let not_set = !line[after..].starts_with("(set)");
            if before_ok && after_ok && not_set {
                return true;
            }
            start = after;
        }
    }
    false
}

pub fn init_review(merged: &str, ours: &str) -> Vec<(usize, String, String)> {
    let ours_lines: Vec<String> = ours.split_inclusive('\n').map(|s| s.to_string()).collect();
    let merged_lines: Vec<String> = merged
        .split_inclusive('\n')
        .map(|s| s.to_string())
        .collect();
    let before = spelled_out_inits(&ours_lines);
    let mut gaps = Vec::new();
    for (name, (stored, signature)) in spelled_out_inits(&merged_lines) {
        let old = before.get(&name).map(|(s, _)| s);
        for (prop, line) in stored {
            let in_old = old.map(|m| m.contains_key(&prop)).unwrap_or(false);
            if !in_old && !has_param_in_signature(&signature, &prop) {
                gaps.push((line, name.clone(), prop));
            }
        }
    }
    gaps.sort();
    gaps
}

fn has_param_in_signature(signature: &str, prop: &str) -> bool {
    let mut start = 0;
    while let Some(idx) = signature[start..].find(prop) {
        let abs = start + idx;
        let before_ok = abs == 0
            || !signature.as_bytes()[abs - 1].is_ascii_alphanumeric()
                && signature.as_bytes()[abs - 1] != b'_';
        let after = abs + prop.len();
        let after_ws = signature[after..].trim_start_matches([' ', '\t']);
        if before_ok && after_ws.starts_with(':') {
            return true;
        }
        start = after;
    }
    false
}

pub fn extract_declared_preferences(preferences: &str) -> HashSet<String> {
    // Matches `=\s*Preference(?:<[^>]+>)?\(\s*DefaultsKey\.(\w+)`
    let mut set = HashSet::new();
    let mut rest = preferences;
    while let Some(idx) = rest.find("Preference") {
        let before = rest[..idx].trim_end();
        if before.ends_with('=') {
            let mut after = &rest[idx + "Preference".len()..];
            if after.starts_with('<') {
                if let Some(close) = after.find('>') {
                    after = &after[close + 1..];
                }
            }
            if let Some(after_paren) = after.strip_prefix('(') {
                let after_ws = after_paren.trim_start();
                if let Some(after_dk) = after_ws.strip_prefix("DefaultsKey.") {
                    let key: String = after_dk
                        .chars()
                        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                        .collect();
                    if !key.is_empty() {
                        set.insert(key);
                    }
                }
            }
        }
        rest = &rest[idx + "Preference".len()..];
    }
    set
}

fn extract_keyed_storage(line: &str) -> Option<String> {
    let idx = line.find("@AppStorage(")?;
    let after = line[idx + "@AppStorage(".len()..].trim_start();
    let after_dk = after.strip_prefix("DefaultsKey.")?;
    let key: String = after_dk
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if key.is_empty() {
        return None;
    }
    let after_key = after_dk[key.len()..].trim_start();
    if after_key.starts_with(')') {
        Some(key)
    } else {
        None
    }
}

pub fn preference_review(merged: &str, ours: &str, preferences: &str) -> Vec<(usize, String)> {
    let declared = extract_declared_preferences(preferences);
    let before: HashSet<&str> = ours.lines().collect();
    let mut found = Vec::new();
    let mut in_conflict = false;
    for (idx, line) in merged.lines().enumerate() {
        let n = idx + 1;
        if line.starts_with("<<<<<<< ") {
            in_conflict = true;
        } else if line.starts_with(">>>>>>> ") {
            in_conflict = false;
        } else if !in_conflict && !before.contains(line) {
            if let Some(key) = extract_keyed_storage(line) {
                if declared.contains(&key) {
                    found.push((n, key));
                }
            }
        }
    }
    found
}

fn matches_source_pin(line: &str) -> bool {
    if line.contains("contentsOfFile") || line.contains("\"Sources/") {
        return true;
    }
    // Or `\b(?!key)[a-z]\w*(?:Source|Code|Lines)\b\s*(?:\.\s*(?:contains|components|range|firstIndex|split)\b|\[)`
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_lowercase() {
            let before_ok =
                i == 0 || (!bytes[i - 1].is_ascii_alphanumeric() && bytes[i - 1] != b'_');
            let mut j = i + 1;
            while j < bytes.len() && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_') {
                j += 1;
            }
            if before_ok {
                let word = &line[i..j];
                if !word.starts_with("key")
                    && (word.ends_with("Source")
                        || word.ends_with("Code")
                        || word.ends_with("Lines"))
                {
                    let after_ws = line[j..].trim_start();
                    if after_ws.starts_with('[') {
                        return true;
                    }
                    if let Some(after_dot) = after_ws.strip_prefix('.') {
                        let m_ws = after_dot.trim_start();
                        for method in ["contains", "components", "range", "firstIndex", "split"] {
                            if let Some(rest) = m_ws.strip_prefix(method) {
                                let b = rest
                                    .chars()
                                    .next()
                                    .map(|c| !c.is_ascii_alphanumeric() && c != '_')
                                    .unwrap_or(true);
                                if b {
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
            i = j;
        } else {
            i += 1;
        }
    }
    false
}

pub fn pin_review(merged: &str, ours: &str) -> Vec<(usize, String)> {
    let before: HashSet<&str> = ours.lines().collect();
    let mut found = Vec::new();
    let mut in_conflict = false;
    for (idx, line) in merged.lines().enumerate() {
        let n = idx + 1;
        if line.starts_with("<<<<<<< ") {
            in_conflict = true;
        } else if line.starts_with(">>>>>>> ") {
            in_conflict = false;
        } else if !in_conflict && !before.contains(line) && matches_source_pin(line) {
            found.push((n, line.trim().to_string()));
        }
    }
    found
}

pub fn port_commit(
    upstream: &Upstream,
    pathmap: &PathMap,
    root: &Path,
    sha: &str,
    report_dir: &Path,
    allow_dirty: bool,
    dry_run: bool,
) -> Result<(Vec<String>, bool), String> {
    let app = root.join(APP_DIR);
    let short = &sha[..10.min(sha.len())];
    let subj = upstream.run(&["log", "-1", "--format=%s", sha])?;
    let mut lines = vec![format!("## {} {}", short, subj.trim()), String::new()];
    let mut clean = true;
    let parents_raw = upstream.run(&["rev-list", "--parents", "-n", "1", sha])?;
    let parent_list: Vec<&str> = parents_raw.split_whitespace().collect();
    if parent_list.len() > 2 {
        let ported: Vec<String> = upstream
            .merge_paths(sha)?
            .into_iter()
            .filter(|p| !upstream_only(p))
            .collect();
        if ported.is_empty() {
            lines.push("- merge commit: changes only upstream-only paths, nothing to port".into());
            return Ok((lines, true));
        }
        let saved = report_dir.join(format!("{}.merge.patch", short));
        let diff = upstream.merge_diff(sha, &ported)?;
        fs::write(&saved, diff).map_err(|e| e.to_string())?;
        let ported_list: Vec<String> = ported.iter().map(|p| format!("`{}`", p)).collect();
        lines.push(format!(
            "- merge commit: its own changes, beyond joining its parents, touch {}; apply them by hand (upstream patch: `{}`)",
            ported_list.join(", "),
            saved.display()
        ));
        return Ok((lines, false));
    }
    let parent = parent_list.get(1).copied();
    let label_base = format!("upstream {}^", short);
    let label_theirs = format!("upstream {}", short);
    let labels = ("vitruvian", label_base.as_str(), label_theirs.as_str());

    let changes = upstream.changes(sha)?;
    if !(allow_dirty || dry_run) {
        let mut dirty = Vec::new();
        for (status, old, new) in &changes {
            if (upstream_only(new) && upstream_only(old))
                || FORK_RETIRED.contains(&new.as_str())
                || FORK_RETIRED.contains(&old.as_str())
                || fork_split(new).is_some()
                || fork_split(old).is_some()
            {
                continue;
            }
            let (target_rel, _) = pathmap.map(if status == "A" { new } else { old });
            let Some(target_rel) = target_rel else {
                continue;
            };
            let rel = format!("{}/{}", APP_DIR, target_rel);
            if root.join(&rel).exists()
                && !out(&["status", "--porcelain", "--", &rel], Some(root), None)?
                    .trim()
                    .is_empty()
            {
                dirty.push(rel);
            }
        }
        if !dirty.is_empty() {
            return Err(format!(
                "{} has uncommitted changes; commit or stash them, or pass --allow-dirty",
                dirty.join(", ")
            ));
        }
    }

    for (status, old, new) in changes {
        if upstream_only(&new) && upstream_only(&old) {
            lines.push(format!("- `{}`: upstream-only path, not ported", new));
            continue;
        }
        if FORK_RETIRED.contains(&new.as_str()) || FORK_RETIRED.contains(&old.as_str()) {
            clean = false;
            let p_ref = parent.unwrap_or(sha);
            let patch = upstream.run(&["diff", p_ref, sha, "--", &old, &new])?;
            let saved = report_dir.join(format!("{}.patch", new.replace('/', "__")));
            fs::write(&saved, patch).map_err(|e| e.to_string())?;
            lines.push(format!(
                "- `{}`: retired in this fork, not merged; port the test it feeds as a behavioural test (upstream patch: `{}`)",
                new,
                saved.display()
            ));
            continue;
        }
        if let Some(split) = fork_split(&new).or_else(|| fork_split(&old)) {
            clean = false;
            let p_ref = parent.unwrap_or(sha);
            let patch = upstream.run(&["diff", p_ref, sha, "--", &old, &new])?;
            let saved = report_dir.join(format!("{}.patch", new.replace('/', "__")));
            fs::write(&saved, patch).map_err(|e| e.to_string())?;
            lines.push(format!(
                "- `{}`: split in this fork into {}; apply by hand (upstream patch: `{}`)",
                new,
                split,
                saved.display()
            ));
            continue;
        }
        let (target_rel, how) = if status == "A" {
            pathmap.map(&new)
        } else {
            pathmap.map(&old)
        };
        let Some(target_rel) = target_rel else {
            clean = false;
            let patch = if let Some(p_ref) = parent {
                upstream.run(&["diff", p_ref, sha, "--", &old, &new])?
            } else {
                String::new()
            };
            let saved = report_dir.join(format!("{}.patch", new.replace('/', "__")));
            fs::write(&saved, patch).map_err(|e| e.to_string())?;
            lines.push(format!(
                "- `{}`: {}; port by hand from `{}`",
                old,
                how,
                saved.display()
            ));
            continue;
        };
        let target = app.join(&target_rel);
        let rel = format!("{}/{}", APP_DIR, target_rel);
        if upstream.is_binary(sha, if status != "D" { &new } else { &old })? {
            clean = false;
            lines.push(format!(
                "- `{}` -> `{}`: binary, not applied; check it for upstream's brand, then copy it by hand",
                new, rel
            ));
            continue;
        }
        if status == "D" {
            let base = to_fork_bytes(parent.and_then(|p| upstream.blob(p, &old)).as_deref());
            if target.exists() && fs::read(&target).unwrap_or_default() == base {
                if !dry_run {
                    let _ = fs::remove_file(&target);
                }
                lines.push(format!(
                    "- `{}` -> `{}`: deleted, as upstream did",
                    old, rel
                ));
            } else if target.exists() {
                clean = false;
                lines.push(format!(
                    "- `{}` -> `{}`: upstream deleted it, but this fork's copy has diverged; decide by hand",
                    old, rel
                ));
            }
            continue;
        }

        let theirs = to_fork_bytes(upstream.blob(sha, &new).as_deref());
        let (result, before_text) = if status == "A" && !target.exists() {
            lines.push(format!("- `{}` -> `{}` ({}): added", new, rel, how));
            (theirs, String::new())
        } else {
            let base = to_fork_bytes(parent.and_then(|p| upstream.blob(p, &old)).as_deref());
            let ours = if target.exists() {
                fs::read(&target).unwrap_or_default()
            } else {
                Vec::new()
            };
            let before_text = String::from_utf8_lossy(&ours).to_string();
            let (res, conflicts) = merge3(&ours, &base, &theirs, labels)?;
            let note = if status == "R" {
                format!(
                    " (upstream renamed it to `{}`; the rename is not applied)",
                    new
                )
            } else {
                String::new()
            };
            if conflicts > 0 {
                clean = false;
                lines.push(format!(
                    "- `{}` -> `{}` ({}): {} conflict(s) to resolve{}",
                    old, rel, how, conflicts, note
                ));
            } else {
                lines.push(format!(
                    "- `{}` -> `{}` ({}): merged{}",
                    old, rel, how, note
                ));
            }
            let res_str = String::from_utf8_lossy(&res);
            for (n, owner, prop) in init_review(&res_str, &before_text) {
                clean = false;
                lines.push(format!(
                    "  - init review `{}:{}`: `{}` gained `{}`, which its spelled-out initializer does not take",
                    rel, n, owner, prop
                ));
            }
            (res, before_text)
        };

        let result_str = String::from_utf8_lossy(&result);
        let prefs_path = root
            .join(APP_DIR)
            .join("Sources/Vitruvian/Core/Preferences.swift");
        let prefs_text = fs::read_to_string(&prefs_path).unwrap_or_default();
        for (n, key) in preference_review(&result_str, &before_text, &prefs_text) {
            clean = false;
            lines.push(format!(
                "  - preference review `{}:{}`: use `@AppStorage(Preferences.{})`, which takes the declared default",
                rel, n, key
            ));
        }
        if format!("/{}", rel).contains("/Tests/") {
            for (n, text) in pin_review(&result_str, &before_text) {
                clean = false;
                lines.push(format!(
                    "  - pin review `{}:{}`: `{}` reads source text; test the behaviour instead, or leave the check out",
                    rel, n, text
                ));
            }
        }
        if !dry_run {
            if let Some(parent_dir) = target.parent() {
                fs::create_dir_all(parent_dir).map_err(|e| e.to_string())?;
            }
            fs::write(&target, &result).map_err(|e| e.to_string())?;
        }
        let before_lines: HashSet<&str> = before_text.lines().collect();
        for (n, l) in brand_review(&result_str) {
            if before_lines.contains(l.as_str()) {
                continue;
            }
            clean = false;
            lines.push(format!("  - brand review `{}:{}`: `{}`", rel, n, l.trim()));
        }
    }
    lines.push(String::new());
    Ok((lines, clean))
}

pub fn status_markdown(t: &Triage, previous_body: Option<&Path>) -> String {
    let mut seen: HashSet<String> = HashSet::new();
    if let Some(pb) = previous_body {
        if let Ok(text) = fs::read_to_string(pb) {
            if let Some(start) = text.find("<!-- untriaged-shas: ") {
                let after = &text[start + "<!-- untriaged-shas: ".len()..];
                if let Some(end) = after.find(" -->") {
                    for s in after[..end].split_whitespace() {
                        seen.insert(s.to_string());
                    }
                }
            }
        }
    }
    let new_count = t
        .untriaged
        .iter()
        .filter(|c| !seen.contains(&c.sha[..12.min(c.sha.len())]))
        .count();
    let shas: Vec<&str> = t
        .untriaged
        .iter()
        .map(|c| &c.sha[..12.min(c.sha.len())])
        .collect();
    let mut lines = vec![
        format!(
            "<!-- upstream-watch untriaged: {} pending: {} new: {} -->",
            t.untriaged.len(),
            t.pending.len(),
            new_count
        ),
        format!("<!-- untriaged-shas: {} -->", shas.join(" ")),
        format!(
            "Upstream [vorssaint-utils]({}) `{}` is at [`{}`]({}/commit/{}). The ledger (`{}`) has **{}** commit(s) to triage and **{}** pending port.",
            UPSTREAM_URL,
            UPSTREAM_BRANCH,
            &t.head[..10.min(t.head.len())],
            UPSTREAM_URL,
            t.head,
            LEDGER,
            t.untriaged.len(),
            t.pending.len()
        ),
        String::new(),
        "Triage: `bazel run //apps/desktop/vitruvian:track_upstream -- triage`, then decide each pending row (UPSTREAM.md, \"Tracking and porting upstream\").".into(),
        String::new(),
    ];
    if t.reanchored {
        lines.push(format!(
            "Upstream rewrote its history: the base moved to `{}` (same tree).",
            &t.base[..10.min(t.base.len())]
        ));
        lines.push(String::new());
    }
    if !t.untriaged.is_empty() {
        lines.push("### Not yet in the ledger".into());
        lines.push(String::new());
        for c in &t.untriaged {
            let mark = if c.auto_skip {
                " — upstream-only paths, will be skipped"
            } else {
                ""
            };
            lines.push(format!(
                "- [`{}`]({}/commit/{}) {} {}{}",
                &c.sha[..10.min(c.sha.len())],
                UPSTREAM_URL,
                c.sha,
                c.date,
                c.subject,
                mark
            ));
        }
        lines.push(String::new());
    }
    if !t.pending.is_empty() {
        lines.push(format!("### Pending port ({})", t.pending.len()));
        lines.push(String::new());
        for r in t.pending.iter().take(200) {
            lines.push(format!(
                "- [`{}`]({}/commit/{}) {} {}",
                &r.sha[..10.min(r.sha.len())],
                UPSTREAM_URL,
                r.sha,
                r.date,
                r.subject
            ));
        }
        if t.pending.len() > 200 {
            lines.push(format!(
                "- … and {} more in the ledger",
                t.pending.len() - 200
            ));
        }
    }
    lines.join("\n")
}

// --- CLI ------------------------------------------------------------------------

pub fn run_cli(args: &[String]) -> i32 {
    match run_cli_inner(args) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("upstream: {}", e);
            2
        }
    }
}

fn run_cli_inner(args: &[String]) -> Result<i32, String> {
    let mut root_arg: Option<PathBuf> = None;
    let mut ledger_arg: Option<PathBuf> = None;
    let mut upstream_url = UPSTREAM_URL.to_string();
    let mut cache_arg: Option<PathBuf> = None;
    let mut no_fetch = false;
    let mut import_commit = IMPORT_COMMIT.to_string();

    let mut subcmd = None;
    let mut sub_args = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if subcmd.is_none() {
            match args[i].as_str() {
                "--root" => {
                    i += 1;
                    root_arg = Some(PathBuf::from(args.get(i).ok_or("--root needs value")?));
                }
                "--ledger" => {
                    i += 1;
                    ledger_arg = Some(PathBuf::from(args.get(i).ok_or("--ledger needs value")?));
                }
                "--upstream-url" => {
                    i += 1;
                    upstream_url = args.get(i).ok_or("--upstream-url needs value")?.clone();
                }
                "--cache" => {
                    i += 1;
                    cache_arg = Some(PathBuf::from(args.get(i).ok_or("--cache needs value")?));
                }
                "--no-fetch" => no_fetch = true,
                "--import-commit" => {
                    i += 1;
                    import_commit = args.get(i).ok_or("--import-commit needs value")?.clone();
                }
                "check-ledger" | "status" | "triage" | "show" | "port" => {
                    subcmd = Some(args[i].clone());
                }
                other => return Err(format!("unknown argument: {}", other)),
            }
        } else {
            sub_args.push(args[i].clone());
        }
        i += 1;
    }

    let Some(cmd) = subcmd else {
        return Err("missing subcommand (check-ledger|status|triage|show|port)".into());
    };

    let root = if let Some(r) = root_arg {
        r
    } else if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        PathBuf::from(ws)
    } else {
        PathBuf::from(out(&["rev-parse", "--show-toplevel"], None, None)?.trim())
    };
    let ledger_path = ledger_arg.unwrap_or_else(|| root.join(LEDGER));
    let cache = cache_arg.unwrap_or_else(|| {
        let base = env::var("XDG_CACHE_HOME").unwrap_or_else(|_| {
            let home = env::var("HOME").unwrap_or_else(|_| ".".into());
            format!("{}/.cache", home)
        });
        PathBuf::from(base).join("vitruvian-upstream")
    });

    match cmd.as_str() {
        "check-ledger" => {
            let ledger = Ledger::load(&ledger_path)?;
            let errs = ledger.errors();
            for e in &errs {
                eprintln!("{}: {}", ledger_path.display(), e);
            }
            if !errs.is_empty() {
                return Ok(1);
            }
            let mut counts: HashMap<&str, usize> = HashMap::new();
            for r in &ledger.rows {
                *counts.entry(r.status.as_str()).or_insert(0) += 1;
            }
            let parts: Vec<String> = STATUSES
                .iter()
                .map(|s| format!("{} {}", counts.get(s).copied().unwrap_or(0), s))
                .collect();
            println!(
                "ledger ok: {} commits ({})",
                ledger.rows.len(),
                parts.join(", ")
            );
            Ok(0)
        }
        "status" => {
            let mut check = false;
            let mut markdown = false;
            let mut previous_body: Option<PathBuf> = None;
            let mut j = 0;
            while j < sub_args.len() {
                match sub_args[j].as_str() {
                    "--check" => check = true,
                    "--markdown" => markdown = true,
                    "--previous-body" => {
                        j += 1;
                        previous_body = Some(PathBuf::from(
                            sub_args.get(j).ok_or("--previous-body needs value")?,
                        ));
                    }
                    other => return Err(format!("unknown status flag: {}", other)),
                }
                j += 1;
            }
            let ledger = Ledger::load(&ledger_path)?;
            let upstream = Upstream::new(&upstream_url, &cache, !no_fetch)?;
            let t = Triage::new(&upstream, &ledger)?;
            if markdown {
                println!("{}", status_markdown(&t, previous_body.as_deref()));
            } else {
                let reanchor_note = if t.reanchored {
                    format!(" (re-anchored by tree from {})", &ledger.base[..10])
                } else {
                    String::new()
                };
                println!(
                    "upstream {} at {}; base {}{}",
                    UPSTREAM_BRANCH,
                    &t.head[..10],
                    &t.base[..10],
                    reanchor_note
                );
                if !t.rekeyed.is_empty() {
                    println!(
                        "{} ledger row(s) re-keyed by patch id after an upstream history rewrite",
                        t.rekeyed.len()
                    );
                }
                if !t.orphaned.is_empty() {
                    let shas: Vec<&str> = t.orphaned.iter().map(|r| &r.sha[..10]).collect();
                    println!(
                        "{} ledger row(s) no longer on upstream: {}",
                        t.orphaned.len(),
                        shas.join(", ")
                    );
                }
                println!(
                    "{} untriaged, {} pending",
                    t.untriaged.len(),
                    t.pending.len()
                );
                for c in &t.untriaged {
                    let mark = if c.auto_skip {
                        " (auto-skip: upstream-only paths)"
                    } else {
                        ""
                    };
                    println!("  {} {} {}{}", &c.sha[..10], c.date, c.subject, mark);
                }
            }
            if check && !t.untriaged.is_empty() {
                return Ok(1);
            }
            Ok(0)
        }
        "triage" => {
            let dry_run = sub_args.iter().any(|a| a == "--dry-run");
            let mut ledger = Ledger::load(&ledger_path)?;
            let upstream = Upstream::new(&upstream_url, &cache, !no_fetch)?;
            let t = Triage::new(&upstream, &ledger)?;
            t.apply(&mut ledger);
            let errs = ledger.errors();
            if !errs.is_empty() {
                return Err(format!("ledger would be invalid: {}", errs.join("; ")));
            }
            let added = t.untriaged.len();
            let skipped = t.untriaged.iter().filter(|c| c.auto_skip).count();
            if dry_run {
                print!("{}", ledger.dump());
            } else {
                fs::write(&ledger_path, ledger.dump()).map_err(|e| e.to_string())?;
            }
            eprintln!(
                "triage: {} added ({} skipped as upstream-only, {} pending), {} re-keyed{}",
                added,
                skipped,
                added - skipped,
                t.rekeyed.len(),
                if t.reanchored {
                    ", base re-anchored"
                } else {
                    ""
                }
            );
            Ok(0)
        }
        "show" => {
            let upstream = Upstream::new(&upstream_url, &cache, !no_fetch)?;
            let pathmap = PathMap::new(&root, &import_commit)?;
            for raw_sha in &sub_args {
                let sha = upstream
                    .run(&["rev-parse", &format!("{}^{{commit}}", raw_sha)])?
                    .trim()
                    .to_string();
                println!(
                    "{}\n",
                    upstream
                        .run(&["log", "-1", "--format=%H%n%an <%ae>%n%ad%n%n%B", &sha])?
                        .trim_end()
                );
                for (status, old, new) in upstream.changes(&sha)? {
                    if upstream_only(&new) && upstream_only(&old) {
                        println!("  {} {}  (upstream-only)", status, new);
                        continue;
                    }
                    let (target, how) = pathmap.map(if status == "A" { &new } else { &old });
                    let where_str = target
                        .map(|t| format!("{}/{}", APP_DIR, t))
                        .unwrap_or_else(|| "-".into());
                    println!("  {} {}\n      -> {}  ({})", status, new, where_str, how);
                }
                println!();
            }
            Ok(0)
        }
        "port" => {
            let mut report_dir_arg: Option<PathBuf> = None;
            let mut allow_dirty = false;
            let mut dry_run = false;
            let mut commits = Vec::new();
            let mut j = 0;
            while j < sub_args.len() {
                match sub_args[j].as_str() {
                    "--report-dir" => {
                        j += 1;
                        report_dir_arg = Some(PathBuf::from(
                            sub_args.get(j).ok_or("--report-dir needs value")?,
                        ));
                    }
                    "--allow-dirty" => allow_dirty = true,
                    "--dry-run" => dry_run = true,
                    other => commits.push(other.to_string()),
                }
                j += 1;
            }
            let upstream = Upstream::new(&upstream_url, &cache, !no_fetch)?;
            let pathmap = PathMap::new(&root, &import_commit)?;
            let report_dir = report_dir_arg.unwrap_or_else(|| {
                env::temp_dir().join(format!("vitruvian-upstream-port-{}", std::process::id()))
            });
            fs::create_dir_all(&report_dir).map_err(|e| e.to_string())?;
            let mut report = vec!["# Upstream port report".to_string(), String::new()];
            let mut all_clean = true;
            for raw_sha in &commits {
                let sha = upstream
                    .run(&["rev-parse", &format!("{}^{{commit}}", raw_sha)])?
                    .trim()
                    .to_string();
                let (lines, clean) = port_commit(
                    &upstream,
                    &pathmap,
                    &root,
                    &sha,
                    &report_dir,
                    allow_dirty,
                    dry_run,
                )?;
                report.extend(lines);
                all_clean = all_clean && clean;
            }
            let text = report.join("\n");
            let report_file = report_dir.join("report.md");
            fs::write(&report_file, &text).map_err(|e| e.to_string())?;
            println!("{}", text);
            println!("report: {}", report_file.display());
            if !all_clean {
                eprintln!(
                    "Not clean: resolve the conflicts and the items above, then build and test."
                );
                return Ok(1);
            }
            Ok(0)
        }
        _ => unreachable!(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rewrites_identifiers_and_bundle_ids() {
        assert_eq!(
            to_fork_line("import VorssaintCore\n"),
            "import VitruvianCore\n"
        );
        assert_eq!(
            to_fork_line("let id = \"com.vorssaint.utils.helper\"\n"),
            "let id = \"com.vitruviansoftware.vitruvian.helper\"\n"
        );
        assert_eq!(
            to_fork_line("let s = \"vorssaint://x\" // VORSSAINT\n"),
            "let s = \"vitruvian://x\" // VITRUVIAN\n"
        );
    }

    #[test]
    fn test_preserves_copyright_notices() {
        for line in [
            "// Copyright (C) 2026 Vorssaint\n",
            "// Copyright © 2026 Vorssaint. All rights reserved.\n",
            "// SPDX-License-Identifier: GPL-3.0-or-later — Vorssaint\n",
        ] {
            assert_eq!(to_fork_line(line), line);
            assert!(brand_review(line).is_empty());
        }
    }

    #[test]
    fn test_leaves_upstream_urls_and_flags_them_for_review() {
        for line in [
            "let u = \"https://api.github.com/repos/vorssaint/vorssaint-utils/releases\"\n",
            "let u = \"https://vorssaint.com/api/feedback\"\n",
            "let u = \"https://raw.githubusercontent.com/vorssaint/vorssaint-utils/main/x\"\n",
        ] {
            let converted = to_fork_line(line);
            assert_eq!(converted, line);
            assert_eq!(
                brand_review(&converted),
                vec![(1, line.trim_end_matches('\n').to_string())]
            );
        }
    }

    #[test]
    fn test_substitutes_around_protected_url_on_same_line() {
        let line = "let VorssaintURL = \"https://vorssaint.com/x\"\n";
        assert_eq!(
            to_fork_line(line),
            "let VitruvianURL = \"https://vorssaint.com/x\"\n"
        );
    }

    #[test]
    fn test_merge_ignores_fork_package_modifier_on_same_line() {
        let base = b"struct S {\n    static func f(_ x: Int) -> Int {\n        x\n    }\n}\n";
        let ours =
            b"package struct S {\n    package static func f(_ x: Int) -> Int {\n        x\n    }\n}\n";
        let theirs =
            b"struct S {\n    static func f(_ x: Int, _ y: Int = 0) -> Int {\n        x + y\n    }\n}\n";
        let (merged, conflicts) = merge3(ours, base, theirs, ("ours", "base", "theirs")).unwrap();
        assert_eq!(conflicts, 0);
        assert_eq!(
            merged,
            b"package struct S {\n    package static func f(_ x: Int, _ y: Int = 0) -> Int {\n        x + y\n    }\n}\n"
        );
    }

    #[test]
    fn test_merge_gives_new_sibling_package_and_leaves_private_and_local_alone() {
        let base = b"struct S {\n    let a: Int\n    func run() {\n        let x = 1\n    }\n}\n";
        let ours = b"package struct S {\n    package let a: Int\n    package func run() {\n        let x = 1\n    }\n}\n";
        let theirs = b"struct S {\n    let a: Int\n    let b: Int\n    private let secret = 0\n    func run() {\n        let a = 2\n        let y = 3\n    }\n}\n";
        let (merged, conflicts) = merge3(ours, base, theirs, ("ours", "base", "theirs")).unwrap();
        assert_eq!(conflicts, 0);
        assert_eq!(
            merged,
            b"package struct S {\n    package let a: Int\n    package let b: Int\n    private let secret = 0\n    package func run() {\n        let a = 2\n        let y = 3\n    }\n}\n"
        );
    }

    #[test]
    fn test_merge_keeps_same_named_decl_per_type() {
        let base =
            b"struct Public {\n    let id: Int\n}\nprivate struct Internal {\n    let id: Int\n}\n";
        let ours = b"package struct Public {\n    package let id: Int\n}\nprivate struct Internal {\n    let id: Int\n}\n";
        let theirs = b"struct Public {\n    let id: Int\n}\nprivate struct Internal {\n    let id: Int\n    let other: Int\n}\n";
        let (merged, conflicts) = merge3(ours, base, theirs, ("ours", "base", "theirs")).unwrap();
        assert_eq!(conflicts, 0);
        assert_eq!(
            merged,
            b"package struct Public {\n    package let id: Int\n}\nprivate struct Internal {\n    let id: Int\n    let other: Int\n}\n"
        );
    }

    #[test]
    fn test_merge_handles_leading_attributes() {
        let base = b"@MainActor final class C {\n    @Published var v = 0\n}\n";
        let ours = b"@MainActor package final class C {\n    @Published package var v = 0\n}\n";
        let theirs = b"@MainActor final class C {\n    @Published var v = 1\n}\n";
        let (merged, conflicts) = merge3(ours, base, theirs, ("ours", "base", "theirs")).unwrap();
        assert_eq!(conflicts, 0);
        assert_eq!(
            merged,
            b"@MainActor package final class C {\n    @Published package var v = 1\n}\n"
        );
    }

    #[test]
    fn test_merge_publishes_new_type_used_in_package_signature() {
        let base = b"enum E {\n    static func f() -> Int { 0 }\n}\n";
        let ours = b"package enum E {\n    package static func f() -> Int { 0 }\n}\n";
        let theirs = b"enum E {\n    enum Mode: Equatable {\n        case a\n    }\n    static func f() -> Int { 0 }\n    static func mode() -> Mode { .a }\n}\n";
        let (merged, conflicts) = merge3(ours, base, theirs, ("ours", "base", "theirs")).unwrap();
        assert_eq!(conflicts, 0);
        let text = String::from_utf8_lossy(&merged);
        assert!(text.contains("    package enum Mode: Equatable {\n"));
        assert!(text.contains("    package static func mode() -> Mode { .a }\n"));
    }

    #[test]
    fn test_merge_reindents_multiline_parameters_when_adding_package() {
        let base = b"enum E {\n    static func old() {}\n}\n";
        let ours = b"package enum E {\n    package static func old() {}\n}\n";
        let theirs = b"enum E {\n    static func old() {}\n    static func added(a: Int,\n                      b: Int) -> Int {\n        a + b\n    }\n}\n";
        let (merged, conflicts) = merge3(ours, base, theirs, ("ours", "base", "theirs")).unwrap();
        assert_eq!(conflicts, 0);
        let text = String::from_utf8_lossy(&merged);
        assert!(text.contains(
            "    package static func added(a: Int,\n                              b: Int) -> Int {\n"
        ));
    }

    #[test]
    fn test_init_review_flags_new_stored_property_missing_from_spelled_out_init() {
        let ours = "\
package struct Hold {
    package var a: Int = 0
    private var cache: Int = 0

    // Spelled out because a memberwise initializer is internal.
    package init(a: Int = 0) {
        self.a = a
    }
}
";
        let merged = ours.replace(
            "    package var a: Int = 0\n",
            "    package var a: Int = 0\n    package var b: Bool = false\n    private var other: Int = 0\n    package var computed: Int {\n        a\n    }\n",
        );
        assert_eq!(
            init_review(&merged, ours),
            vec![(3, "Hold".to_string(), "b".to_string())]
        );
    }

    #[test]
    fn test_preference_review_flags_only_new_declared_keys() {
        let prefs = "\
package enum Preferences {
    package static let known = Preference(DefaultsKey.known, default: true)
    package static let typed = Preference<[String]>(DefaultsKey.typed, default: [])
}
";
        let ours = "    @AppStorage(DefaultsKey.known) private var kept = true\n";
        let merged = [
            "    @AppStorage(DefaultsKey.known) private var kept = true",
            "    @AppStorage(DefaultsKey.known) private var added = true",
            "    @AppStorage(DefaultsKey.typed) private var alsoAdded = false",
            "    @AppStorage(DefaultsKey.unmigrated) private var fine = false",
            "    @AppStorage(Preferences.known) private var alreadyTyped: Bool",
        ]
        .join("\n");
        assert_eq!(
            preference_review(&merged, ours, prefs),
            vec![(2, "known".to_string()), (3, "typed".to_string()),]
        );
    }

    #[test]
    fn test_pin_review_flags_new_source_reads_in_tests() {
        let ours = "let ok = service.run()\n";
        let merged = "\
let ok = service.run()
let src = try String(contentsOfFile: \"Sources/Vitruvian/X.swift\")
suite.expect(switcherSource.contains(\"orderOut\"))
suite.expect(holdLines[0] == \"import AppKit\")
suite.expect(keyCode == 53)
";
        assert_eq!(
            pin_review(merged, ours),
            vec![
                (
                    2,
                    "let src = try String(contentsOfFile: \"Sources/Vitruvian/X.swift\")"
                        .to_string()
                ),
                (
                    3,
                    "suite.expect(switcherSource.contains(\"orderOut\"))".to_string()
                ),
                (
                    4,
                    "suite.expect(holdLines[0] == \"import AppKit\")".to_string()
                ),
            ]
        );
    }

    #[test]
    fn test_validates_committed_ledger() {
        let path = Path::new("apps/desktop/vitruvian/upstream/ledger.tsv");
        let ledger_path = if path.exists() {
            path.to_path_buf()
        } else {
            PathBuf::from("upstream/ledger.tsv")
        };
        if ledger_path.exists() {
            let ledger = Ledger::load(&ledger_path).unwrap();
            assert_eq!(ledger.errors(), Vec::<String>::new());
        }
    }

    #[test]
    fn test_rejects_bad_rows() {
        let tmp = env::temp_dir().join("test_vitruvian_bad_ledger.tsv");
        let sha1 = "a".repeat(40);
        let sha2 = "b".repeat(40);
        let sha3 = "c".repeat(40);
        let content = format!(
            "# base\t{}\ttree\t{}\n\
             badsha\t-\t2026-01-01\tpending\t-\tsubj\n\
             {}\t-\t2026-01-01\tported\tnopr\tsubj\n\
             {}\t-\t2026-01-01\tskipped\t-\tsubj\n\
             {}\t-\t2026-01-01\twhat\t-\tsubj\n",
            sha1, sha2, sha1, sha1, sha3
        );
        fs::write(&tmp, content).unwrap();
        let errs = Ledger::load(&tmp).unwrap().errors();
        let _ = fs::remove_file(&tmp);
        assert_eq!(errs.len(), 5);
        assert!(errs.iter().any(|e| e.contains("not a full commit id")));
        assert!(errs.iter().any(|e| e.contains("PR that ported it")));
        assert!(errs.iter().any(|e| e.contains("duplicate")));
        assert!(errs.iter().any(|e| e.contains("ref says why")));
        assert!(errs.iter().any(|e| e.contains("not one of")));
    }

    #[allow(dead_code)]
    struct GitFixture {
        tmp: PathBuf,
        up: PathBuf,
        mono: PathBuf,
        cache: PathBuf,
        base: String,
        base_tree: String,
        import_sha: String,
        ledger_path: PathBuf,
    }

    impl GitFixture {
        fn new(name: &str) -> Self {
            let tmp = env::temp_dir().join(format!(
                "vit_upstream_fixture_{}_{}",
                name,
                std::process::id()
            ));
            let _ = fs::remove_dir_all(&tmp);
            let up = tmp.join("upstream");
            let mono = tmp.join("mono");
            let cache = tmp.join("cache");
            Self::init(&up);
            Self::write(
                &up,
                "Sources/Vorssaint/Core/App.swift",
                "// Copyright (C) 2026 Vorssaint\nimport Foundation\nstruct VorssaintApp {\n    let id = \"com.vorssaint.utils\"\n    let count = 1\n}\n",
            );
            Self::write(
                &up,
                "Sources/Vorssaint/Core/Sibling.swift",
                "struct Sibling {}\n",
            );
            let base = Self::commit(&up, "initial");
            let base_tree = out(&["rev-parse", "HEAD^{tree}"], Some(&up), None)
                .unwrap()
                .trim()
                .to_string();

            Self::init(&mono);
            Self::write(
                &mono,
                &format!("{}/Sources/Vorssaint/Core/App.swift", APP_DIR),
                "// Copyright (C) 2026 Vorssaint\nimport Foundation\nstruct VorssaintApp {\n    let id = \"com.vorssaint.utils\"\n    let count = 1\n}\n",
            );
            Self::write(
                &mono,
                &format!("{}/Sources/Vorssaint/Core/Sibling.swift", APP_DIR),
                "struct Sibling {}\n",
            );
            let import_sha = Self::commit(&mono, "import");

            let old_app = mono.join(APP_DIR).join("Sources/Vorssaint/Core/App.swift");
            let old_sib = mono
                .join(APP_DIR)
                .join("Sources/Vorssaint/Core/Sibling.swift");
            let _ = fs::remove_file(&old_app);
            let _ = fs::remove_file(&old_sib);
            Self::write(
                &mono,
                &format!("{}/Sources/Vitruvian/Core/App.swift", APP_DIR),
                "// Copyright (C) 2026 Vorssaint\nimport Foundation\npackage struct VitruvianApp {\n    package let forkOnly = true\n    package let id = \"com.vitruviansoftware.vitruvian\"\n    package let count = 1\n}\n",
            );
            Self::write(
                &mono,
                &format!("{}/Sources/Vitruvian/Core/Sibling.swift", APP_DIR),
                "package struct Sibling {}\n",
            );
            let ledger_path = mono.join(LEDGER);
            Self::write(
                &mono,
                LEDGER,
                &format!("# base\t{}\ttree\t{}\n", base, base_tree),
            );
            Self::commit(&mono, "rebrand and split");

            Self {
                tmp,
                up,
                mono,
                cache,
                base,
                base_tree,
                import_sha,
                ledger_path,
            }
        }

        fn init(path: &Path) {
            fs::create_dir_all(path).unwrap();
            git(&["init", "-q", "-b", "main"], Some(path), None, true, None).unwrap();
            git(
                &["config", "user.email", "t@example.invalid"],
                Some(path),
                None,
                true,
                None,
            )
            .unwrap();
            git(
                &["config", "user.name", "Test"],
                Some(path),
                None,
                true,
                None,
            )
            .unwrap();
        }

        fn write(repo: &Path, rel: &str, text: &str) {
            let p = repo.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, text).unwrap();
        }

        fn commit(repo: &Path, msg: &str) -> String {
            git(&["add", "-A"], Some(repo), None, true, None).unwrap();
            git(&["commit", "-q", "-m", msg], Some(repo), None, true, None).unwrap();
            out(&["rev-parse", "HEAD"], Some(repo), None)
                .unwrap()
                .trim()
                .to_string()
        }
    }

    impl Drop for GitFixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.tmp);
        }
    }

    #[test]
    fn test_triage_classifies_upstream_only_and_pending() {
        let f = GitFixture::new("triage_classify");
        GitFixture::write(&f.up, "README.md", "docs\n");
        let c_docs = GitFixture::commit(&f.up, "docs only");
        GitFixture::write(
            &f.up,
            "Sources/Vorssaint/Core/App.swift",
            "// Copyright (C) 2026 Vorssaint\nimport Foundation\nstruct VorssaintApp {\n    let id = \"com.vorssaint.utils\"\n    let count = 2\n}\n",
        );
        let c_code = GitFixture::commit(&f.up, "bump count");

        let rc = run_cli(&[
            "--root".into(),
            f.mono.to_str().unwrap().into(),
            "--upstream-url".into(),
            f.up.to_str().unwrap().into(),
            "--cache".into(),
            f.cache.to_str().unwrap().into(),
            "triage".into(),
        ]);
        assert_eq!(rc, 0);

        let ledger = Ledger::load(&f.ledger_path).unwrap();
        assert_eq!(ledger.errors(), Vec::<String>::new());
        assert_eq!(ledger.rows.len(), 2);
        assert_eq!(ledger.rows[0].sha, c_docs);
        assert_eq!(ledger.rows[0].status, "skipped");
        assert_eq!(ledger.rows[1].sha, c_code);
        assert_eq!(ledger.rows[1].status, "pending");
    }

    #[test]
    fn test_triage_survives_upstream_history_rewrite() {
        let f = GitFixture::new("triage_rewrite");
        GitFixture::write(
            &f.up,
            "Sources/Vorssaint/Core/Sibling.swift",
            "struct Sibling { let x = 1 }\n",
        );
        let old_sha = GitFixture::commit(&f.up, "add x");

        run_cli(&[
            "--root".into(),
            f.mono.to_str().unwrap().into(),
            "--upstream-url".into(),
            f.up.to_str().unwrap().into(),
            "--cache".into(),
            f.cache.to_str().unwrap().into(),
            "triage".into(),
        ]);
        let mut ledger = Ledger::load(&f.ledger_path).unwrap();
        ledger.rows[0].status = "ported".into();
        ledger.rows[0].r#ref = "#99".into();
        fs::write(&f.ledger_path, ledger.dump()).unwrap();

        git(
            &[" checkout", "-q", "-B", "main", &f.base],
            Some(&f.up),
            None,
            false,
            None,
        )
        .ok();
        git(
            &["checkout", "-q", "-B", "main", &f.base],
            Some(&f.up),
            None,
            true,
            None,
        )
        .unwrap();
        git(
            &["commit", "-q", "--amend", "-m", "initial (amended message)"],
            Some(&f.up),
            None,
            true,
            None,
        )
        .unwrap();
        let new_base = out(&["rev-parse", "HEAD"], Some(&f.up), None)
            .unwrap()
            .trim()
            .to_string();
        GitFixture::write(
            &f.up,
            "Sources/Vorssaint/Core/Sibling.swift",
            "struct Sibling { let x = 1 }\n",
        );
        let new_sha = GitFixture::commit(&f.up, "add x (rebased)");
        assert_ne!(old_sha, new_sha);

        let rc = run_cli(&[
            "--root".into(),
            f.mono.to_str().unwrap().into(),
            "--upstream-url".into(),
            f.up.to_str().unwrap().into(),
            "--cache".into(),
            f.cache.to_str().unwrap().into(),
            "triage".into(),
        ]);
        assert_eq!(rc, 0);
        let ledger2 = Ledger::load(&f.ledger_path).unwrap();
        assert_eq!(ledger2.base, new_base);
        assert_eq!(ledger2.rows.len(), 1);
        assert_eq!(ledger2.rows[0].sha, new_sha);
        assert_eq!(ledger2.rows[0].status, "ported");
        assert_eq!(ledger2.rows[0].r#ref, "#99");
    }

    #[test]
    fn test_port_follows_rename_and_translates_brand() {
        let f = GitFixture::new("port_rename");
        GitFixture::write(
            &f.up,
            "Sources/Vorssaint/Core/App.swift",
            "// Copyright (C) 2026 Vorssaint\nimport Foundation\nstruct VorssaintApp {\n    let id = \"com.vorssaint.utils\"\n    let count = 2\n    let tag = \"vorssaint\"\n}\n",
        );
        let sha = GitFixture::commit(&f.up, "update app");

        let rc = run_cli(&[
            "--root".into(),
            f.mono.to_str().unwrap().into(),
            "--upstream-url".into(),
            f.up.to_str().unwrap().into(),
            "--cache".into(),
            f.cache.to_str().unwrap().into(),
            "--import-commit".into(),
            f.import_sha.clone(),
            "port".into(),
            "--report-dir".into(),
            f.tmp.join("report").to_str().unwrap().into(),
            sha,
        ]);
        assert_eq!(rc, 0);
        let merged = fs::read_to_string(
            f.mono
                .join(APP_DIR)
                .join("Sources/Vitruvian/Core/App.swift"),
        )
        .unwrap();
        assert!(merged.contains("// Copyright (C) 2026 Vorssaint\n"));
        assert!(merged.contains("package struct VitruvianApp"));
        assert!(merged.contains("package let count = 2"));
        assert!(merged.contains("package let tag = \"vitruvian\""));
        assert!(merged.contains("package let forkOnly = true"));
    }

    #[test]
    fn test_port_places_new_file_under_renamed_directory() {
        let f = GitFixture::new("port_new_file");
        GitFixture::write(
            &f.up,
            "Sources/Vorssaint/Core/VorssaintHelper.swift",
            "struct VorssaintHelper {}\n",
        );
        let sha = GitFixture::commit(&f.up, "add helper");

        let rc = run_cli(&[
            "--root".into(),
            f.mono.to_str().unwrap().into(),
            "--upstream-url".into(),
            f.up.to_str().unwrap().into(),
            "--cache".into(),
            f.cache.to_str().unwrap().into(),
            "--import-commit".into(),
            f.import_sha.clone(),
            "port".into(),
            "--report-dir".into(),
            f.tmp.join("report").to_str().unwrap().into(),
            sha,
        ]);
        assert_eq!(rc, 0);
        let placed = f
            .mono
            .join(APP_DIR)
            .join("Sources/Vitruvian/Core/VitruvianHelper.swift");
        assert!(placed.exists());
        assert_eq!(
            fs::read_to_string(&placed).unwrap(),
            "struct VitruvianHelper {}\n"
        );
    }
}
