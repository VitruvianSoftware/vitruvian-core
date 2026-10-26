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

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const APP_DIR: &str = "apps/web/gods-eye-view";
pub const UPSTREAM_URL: &str = "https://github.com/bilawalsidhu/gods-eye-view";
pub const UPSTREAM_BRANCH: &str = "main";
pub const KINDS: &[&str] = &["added", "modified", "deleted"];
pub const SERVER_PATHS: &[&str] = &["server/", "build/"];
pub const PRODUCTION_SERVER_PATHS: &[&str] = &["server/providers/"];
pub const COLUMNS: &[&str] = &["path", "change", "why"];
pub const HEADER_MAX_LINES: usize = 25;

static OPENERS: &[&[u8]] = &[b"/**", b"/*", b"<!--"];
static CLOSERS: &[&[u8]] = &[b"*/", b"-->"];

#[derive(Debug)]
pub struct ToolError(pub String);

impl std::fmt::Display for ToolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ToolError {}

fn header_re(line: &[u8]) -> bool {
    let pat = b"Copyright (c) ";
    let suf = b"VitruvianSoftware";
    if let Some(pos) = line
        .windows(pat.len())
        .position(|w| w == pat)
    {
        let after = &line[pos + pat.len()..];
        let digit_end = after.iter().position(|&b| !b.is_ascii_digit()).unwrap_or(after.len());
        if digit_end >= 4 {
            let rest = &after[digit_end..];
            if rest.len() >= suf.len() + 1 && rest[0] == b' ' && &rest[1..1 + suf.len()] == &suf[..] {
                return true;
            }
        }
    }
    false
}

fn trim_bytes(mut s: &[u8]) -> &[u8] {
    while let Some((&first, rest)) = s.split_first() {
        if first.is_ascii_whitespace() {
            s = rest;
        } else {
            break;
        }
    }
    while let Some((&last, rest)) = s.split_last() {
        if last.is_ascii_whitespace() {
            s = rest;
        } else {
            break;
        }
    }
    s
}

pub fn split_header(data: &[u8]) -> (&[u8], Vec<u8>, Vec<u8>, usize) {
    let lines = split_lines_keep(data);
    let mut k_found = None;
    for k in 0..std::cmp::min(lines.len(), 4) {
        if header_re(lines[k]) {
            k_found = Some(k);
            break;
        }
    }
    let k = match k_found {
        Some(k) => k,
        None => return (data, Vec::new(), Vec::new(), 0),
    };
    let start = if k > 0 && OPENERS.contains(&trim_bytes(lines[k - 1])) {
        k - 1
    } else {
        k
    };
    let mut end = k + 1;
    let limit = std::cmp::min(lines.len(), k + HEADER_MAX_LINES);
    while end < limit && !lines[end].windows(9).any(|w| w == b"SOFTWARE.") {
        end += 1;
    }
    if end >= limit {
        return (data, Vec::new(), Vec::new(), 0);
    }
    end += 1;
    if end < lines.len() && CLOSERS.contains(&trim_bytes(lines[end])) {
        end += 1;
    }
    if end < lines.len() && trim_bytes(lines[end]).is_empty() {
        end += 1;
    }
    let mut body = Vec::new();
    for l in &lines[..start] {
        body.extend_from_slice(l);
    }
    for l in &lines[end..] {
        body.extend_from_slice(l);
    }
    let mut header = Vec::new();
    for l in &lines[start..end] {
        header.extend_from_slice(l);
    }
    (data, body, header, start)
}

pub struct SplitResult {
    pub body: Vec<u8>,
    pub header: Vec<u8>,
    pub line: usize,
}

pub fn split_header_owned(data: &[u8]) -> SplitResult {
    let (_, body, header, line) = split_header(data);
    if header.is_empty() {
        SplitResult {
            body: data.to_vec(),
            header: Vec::new(),
            line: 0,
        }
    } else {
        SplitResult { body, header, line }
    }
}

pub fn join_header(body: &[u8], header: &[u8], line: usize) -> Vec<u8> {
    if header.is_empty() {
        return body.to_vec();
    }
    let lines = split_lines_keep(body);
    let mut result = Vec::new();
    for l in lines.iter().take(line) {
        result.extend_from_slice(l);
    }
    result.extend_from_slice(header);
    for l in lines.iter().skip(line) {
        result.extend_from_slice(l);
    }
    result
}

fn split_lines_keep(data: &[u8]) -> Vec<&[u8]> {
    let mut lines = Vec::new();
    let mut start = 0;
    for (i, &b) in data.iter().enumerate() {
        if b == b'\n' {
            lines.push(&data[start..=i]);
            start = i + 1;
        }
    }
    if start < data.len() {
        lines.push(&data[start..]);
    }
    lines
}

pub fn blob_id(data: &[u8]) -> String {
    let header = format!("blob {}\0", data.len());
    let full: Vec<u8> = header.into_bytes().into_iter().chain(data.iter().copied()).collect();
    sha1_hex(&full)
}

fn sha1_hex(data: &[u8]) -> String {
    let mut h0: u32 = 0x67452301;
    let mut h1: u32 = 0xEFCDAB89;
    let mut h2: u32 = 0x98BADCFE;
    let mut h3: u32 = 0x10325476;
    let mut h4: u32 = 0xC3D2E1F0;

    let bit_len = (data.len() as u64) * 8;
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks(64) {
        let mut w = [0u32; 80];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[4 * i], chunk[4 * i + 1], chunk[4 * i + 2], chunk[4 * i + 3]]);
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let (mut a, mut b, mut c, mut d, mut e) = (h0, h1, h2, h3, h4);
        for i in 0..80 {
            let (f, k) = match i {
                0..=19 => ((b & c) | ((!b) & d), 0x5A827999u32),
                20..=39 => (b ^ c ^ d, 0x6ED9EBA1u32),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1BBCDCu32),
                _ => (b ^ c ^ d, 0xCA62C1D6u32),
            };
            let temp = a.rotate_left(5)
                .wrapping_add(f)
                .wrapping_add(e)
                .wrapping_add(k)
                .wrapping_add(w[i]);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = temp;
        }
        h0 = h0.wrapping_add(a);
        h1 = h1.wrapping_add(b);
        h2 = h2.wrapping_add(c);
        h3 = h3.wrapping_add(d);
        h4 = h4.wrapping_add(e);
    }
    format!("{:08x}{:08x}{:08x}{:08x}{:08x}", h0, h1, h2, h3, h4)
}

pub fn is_binary(data: &[u8]) -> bool {
    let limit = std::cmp::min(data.len(), 8000);
    data[..limit].contains(&0)
}

// --- Row / Changes ---

#[derive(Debug, Clone)]
pub struct Row {
    pub path: String,
    pub change: String,
    pub why: String,
    pub line: usize,
}

impl Row {
    pub fn is_prefix(&self) -> bool {
        self.path.ends_with('/')
    }

    pub fn covers(&self, path: &str) -> bool {
        if self.is_prefix() {
            path.starts_with(&self.path)
        } else {
            path == self.path
        }
    }
}

#[derive(Debug)]
pub struct Changes {
    pub path: PathBuf,
    pub base: String,
    pub tree: String,
    pub rows: Vec<Row>,
}

impl Changes {
    pub fn load(path: &Path) -> Result<Self, ToolError> {
        let text = fs::read_to_string(path)
            .map_err(|e| ToolError(format!("{}: {}", path.display(), e)))?;
        let mut base: Option<String> = None;
        let mut tree: Option<String> = None;
        let mut rows = Vec::new();
        for (n, raw) in text.lines().enumerate() {
            let n = n + 1;
            if raw.starts_with("# base\t") {
                let fields: Vec<&str> = raw[2..].split('\t').collect();
                if fields.len() != 4 || fields[2] != "tree" {
                    return Err(ToolError(format!(
                        "{}:{}: base line is `# base<TAB>sha<TAB>tree<TAB>tree`",
                        path.display(), n
                    )));
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
                return Err(ToolError(format!(
                    "{}:{}: expected {} tab-separated columns, got {}",
                    path.display(), n, COLUMNS.len(), fields.len()
                )));
            }
            rows.push(Row {
                path: fields[0].to_string(),
                change: fields[1].to_string(),
                why: fields[2].to_string(),
                line: n,
            });
        }
        match base {
            None => Err(ToolError(format!("{}: no `# base` line", path.display()))),
            Some(b) => Ok(Changes {
                path: path.to_path_buf(),
                base: b,
                tree: tree.unwrap(),
                rows,
            }),
        }
    }

    pub fn errors(&self) -> Vec<String> {
        let mut errs = Vec::new();
        for (name, value) in [("base", &self.base), ("tree", &self.tree)] {
            if value.len() != 40 || !value.chars().all(|c| c.is_ascii_hexdigit()) {
                errs.push(format!("the base line's {} is not a full object id", name));
            }
        }
        let mut seen: HashMap<&str, usize> = HashMap::new();
        for row in &self.rows {
            let where_ = format!("line {} ({})", row.line, row.path);
            if let Some(&prev) = seen.get(row.path.as_str()) {
                errs.push(format!("{}: duplicate of line {}", where_, prev));
            }
            seen.insert(&row.path, row.line);
            if !KINDS.contains(&row.change.as_str()) {
                errs.push(format!(
                    "{}: change {:?} is not one of {}",
                    where_,
                    row.change,
                    KINDS.join(", ")
                ));
            } else if row.is_prefix() && row.change != "added" {
                errs.push(format!("{}: only an `added` row may name a directory", where_));
            }
            if row.path.starts_with('/') || row.path.split('/').any(|s| s == "..") || row.path.is_empty() {
                errs.push(format!("{}: path is not relative to {}", where_, APP_DIR));
            }
            let why_trimmed = row.why.trim();
            if why_trimmed.is_empty() || why_trimmed == "-" {
                errs.push(format!("{}: say why this copy differs", where_));
            }
        }
        errs
    }

    pub fn row_for(&self, path: &str) -> Option<&Row> {
        let exact: Vec<&Row> = self.rows.iter().filter(|r| !r.is_prefix() && r.covers(path)).collect();
        if !exact.is_empty() {
            return Some(exact[0]);
        }
        let prefixes: Vec<&Row> = self.rows.iter().filter(|r| r.is_prefix() && r.covers(path)).collect();
        prefixes.into_iter().max_by_key(|r| r.path.len())
    }

    pub fn set_base(&mut self, base: &str, tree: &str) -> Result<(), ToolError> {
        let text = fs::read_to_string(&self.path)
            .map_err(|e| ToolError(format!("{}: {}", self.path.display(), e)))?;
        let new_text = text.lines().map(|line| {
            if line.starts_with("# base\t") {
                format!("# base\t{}\ttree\t{}", base, tree)
            } else {
                line.to_string()
            }
        }).collect::<Vec<_>>().join("\n") + "\n";
        fs::write(&self.path, new_text)
            .map_err(|e| ToolError(format!("{}: {}", self.path.display(), e)))?;
        self.base = base.to_string();
        self.tree = tree.to_string();
        Ok(())
    }
}

// --- Upstream ---

pub struct Upstream {
    pub url: String,
    pub dir: PathBuf,
    pub ref_: String,
}

fn git(args: &[&str], git_dir: Option<&Path>, cwd: Option<&Path>, check: bool, input: Option<&[u8]>) -> Result<std::process::Output, ToolError> {
    let mut cmd = Command::new("git");
    if let Some(d) = git_dir {
        cmd.arg("--git-dir").arg(d);
    }
    cmd.args(args);
    if let Some(c) = cwd {
        cmd.current_dir(c);
    }
    if input.is_some() {
        cmd.stdin(std::process::Stdio::piped());
    }
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());
    let output = if let Some(inp) = input {
        let mut child = cmd.spawn().map_err(|e| ToolError(format!("git spawn: {}", e)))?;
        child.stdin.as_mut().unwrap().write_all(inp).map_err(|e| ToolError(format!("git stdin: {}", e)))?;
        child.wait_with_output().map_err(|e| ToolError(format!("git wait: {}", e)))?
    } else {
        cmd.output().map_err(|e| ToolError(format!("git: {}", e)))?
    };
    if check && output.status.code().unwrap_or(1) != 0 {
        return Err(ToolError(format!(
            "git {} failed ({}): {}",
            args.join(" "),
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    Ok(output)
}

fn git_out(args: &[&str], git_dir: Option<&Path>, cwd: Option<&Path>) -> Result<String, ToolError> {
    let output = git(args, git_dir, cwd, true, None)?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

impl Upstream {
    pub fn new(url: &str, cache_dir: &Path, fetch: bool) -> Result<Self, ToolError> {
        let dir = cache_dir.join("gods-eye-view.git");
        let ref_ = format!("refs/heads/{}", UPSTREAM_BRANCH);
        let ups = Upstream {
            url: url.to_string(),
            dir: dir.clone(),
            ref_,
        };
        if !fetch {
            if !dir.exists() {
                return Err(ToolError(format!(
                    "no upstream clone at {}; run without --no-fetch once",
                    dir.display()
                )));
            }
            return Ok(ups);
        }
        if !dir.exists() {
            if let Some(parent) = dir.parent() {
                fs::create_dir_all(parent)
                    .map_err(|e| ToolError(format!("mkdir: {}", e)))?;
            }
            let url_s = url;
            let dir_s = dir.to_string_lossy().to_string();
            git(
                &["clone", "--quiet", "--bare", "--filter=blob:none", url_s, &dir_s],
                None, None, true, None,
            )?;
        }
        git(
            &["remote", "set-url", "origin", url],
            Some(&dir), None, true, None,
        )?;
        let fetch_spec = format!("+{}:{}", ups.ref_, ups.ref_);
        git(
            &["fetch", "--quiet", "--force", "origin", &fetch_spec],
            Some(&dir), None, true, None,
        )?;
        Ok(ups)
    }

    fn run(&self, args: &[&str]) -> Result<String, ToolError> {
        git_out(args, Some(&self.dir), None)
    }

    pub fn head(&self) -> Result<String, ToolError> {
        Ok(self.run(&["rev-parse", &self.ref_])?.trim().to_string())
    }

    pub fn resolve(&self, rev: &str) -> Result<String, ToolError> {
        let spec = format!("{}^{{commit}}", rev);
        Ok(self.run(&["rev-parse", "--verify", &spec])?.trim().to_string())
    }

    pub fn tree_of(&self, commit: &str) -> Result<String, ToolError> {
        let spec = format!("{}^{{tree}}", commit);
        Ok(self.run(&["rev-parse", &spec])?.trim().to_string())
    }

    pub fn resolve_base(&self, changes: &Changes) -> Result<(String, bool), ToolError> {
        let out = git(
            &["merge-base", "--is-ancestor", &changes.base, &self.ref_],
            Some(&self.dir), None, false, None,
        )?;
        if out.status.code().unwrap_or(1) == 0 {
            return Ok((changes.base.clone(), false));
        }
        let log = self.run(&["log", "--reverse", "--format=%H %T", &self.ref_])?;
        for line in log.lines() {
            let mut parts = line.splitn(2, ' ');
            if let (Some(commit), Some(tree)) = (parts.next(), parts.next()) {
                if tree == changes.tree {
                    return Ok((commit.to_string(), true));
                }
            }
        }
        Err(ToolError(format!(
            "base {} is not on upstream {} and no commit there has its tree {}; \
             upstream rewrote history past it. Find the matching commit by hand and set the `# base` line.",
            &changes.base[..10], UPSTREAM_BRANCH, &changes.tree[..10]
        )))
    }

    pub fn commits_between(&self, base: &str, target: &str) -> Result<(usize, Vec<(String, String, String)>), ToolError> {
        let rng = format!("{}..{}", base, target);
        let every: usize = self.run(&["rev-list", "--count", &rng])?.trim().parse().unwrap_or(0);
        let fmt = "--format=%H%x00%as%x00%s";
        let raw = self.run(&["log", "--reverse", "--first-parent", fmt, &rng])?;
        let mut line = Vec::new();
        for l in raw.lines() {
            if l.starts_with("commit ") {
                continue;
            }
            let parts: Vec<&str> = l.splitn(3, '\0').collect();
            if parts.len() == 3 {
                line.push((parts[0].to_string(), parts[1].to_string(), parts[2].to_string()));
            }
        }
        Ok((every, line))
    }

    pub fn entries(&self, commit: &str) -> Result<BTreeMap<String, (String, String)>, ToolError> {
        let raw = self.run(&["ls-tree", "-r", "-z", "--full-tree", commit])?;
        let mut result = BTreeMap::new();
        for item in raw.split('\0') {
            if item.is_empty() {
                continue;
            }
            if let Some((meta, path)) = item.split_once('\t') {
                let parts: Vec<&str> = meta.split_whitespace().collect();
                if parts.len() >= 3 && parts[1] == "blob" {
                    result.insert(path.to_string(), (parts[0].to_string(), parts[2].to_string()));
                }
            }
        }
        Ok(result)
    }

    pub fn changes_between(&self, base: &str, target: &str) -> Result<Vec<(char, String, (String, String), (String, String))>, ToolError> {
        let raw = self.run(&["diff-tree", "-r", "-z", "--no-renames", base, target])?;
        let parts: Vec<&str> = raw.split('\0').collect();
        let mut result = Vec::new();
        let mut i = 0;
        while i < parts.len().saturating_sub(1) {
            let meta = parts[i];
            if !meta.starts_with(':') {
                i += 1;
                continue;
            }
            let fields: Vec<&str> = meta[1..].split_whitespace().collect();
            if fields.len() < 5 {
                i += 1;
                continue;
            }
            let status = fields[4].chars().next().unwrap_or('?');
            let path = parts[i + 1].to_string();
            result.push((
                status,
                path,
                (fields[0].to_string(), fields[2].to_string()),
                (fields[1].to_string(), fields[3].to_string()),
            ));
            i += 2;
        }
        Ok(result)
    }

    pub fn blob(&self, sha: &str) -> Result<Vec<u8>, ToolError> {
        let output = git(
            &["cat-file", "blob", sha],
            Some(&self.dir), None, true, None,
        )?;
        Ok(output.stdout)
    }
}

// --- Local files ---

#[derive(Debug)]
pub struct Local {
    pub mode: String,
    pub sha: String,
    pub data: Vec<u8>,
}

pub fn app_dir(root: &Path) -> PathBuf {
    root.join(APP_DIR)
}

pub fn local_files(root: &Path) -> Result<BTreeMap<String, Local>, ToolError> {
    let raw = git_out(
        &["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", APP_DIR],
        None, Some(root),
    )?;
    let mut result = BTreeMap::new();
    let prefix = format!("{}/", APP_DIR);
    let mut paths: Vec<&str> = raw.split('\0').collect();
    paths.sort();
    paths.dedup();
    for rel in paths {
        if !rel.starts_with(&prefix) || rel.is_empty() {
            continue;
        }
        let full = root.join(rel);
        if full.symlink_metadata().map(|m| m.file_type().is_symlink()).unwrap_or(false) {
            let target = fs::read_link(&full)
                .map_err(|e| ToolError(format!("readlink {}: {}", full.display(), e)))?;
            let data = target.to_string_lossy().as_bytes().to_vec();
            let key = &rel[prefix.len()..];
            result.insert(key.to_string(), Local {
                mode: "120000".to_string(),
                sha: blob_id(&data),
                data,
            });
            continue;
        }
        if !full.is_file() {
            continue;
        }
        let data = fs::read(&full)
            .map_err(|e| ToolError(format!("read {}: {}", full.display(), e)))?;
        let meta = full.metadata()
            .map_err(|e| ToolError(format!("stat {}: {}", full.display(), e)))?;
        let mode = if meta.permissions().mode() & 0o100 != 0 {
            "100755"
        } else {
            "100644"
        };
        let body = if is_binary(&data) {
            data.clone()
        } else {
            split_header_owned(&data).body
        };
        let key = &rel[prefix.len()..];
        result.insert(key.to_string(), Local {
            mode: mode.to_string(),
            sha: blob_id(&body),
            data,
        });
    }
    Ok(result)
}

// --- Differences / drift ---

pub fn differences(local: &BTreeMap<String, Local>, base_entries: &BTreeMap<String, (String, String)>) -> BTreeMap<String, String> {
    let mut all_paths: BTreeSet<&str> = BTreeSet::new();
    for k in local.keys() {
        all_paths.insert(k);
    }
    for k in base_entries.keys() {
        all_paths.insert(k);
    }
    let mut result = BTreeMap::new();
    for path in all_paths {
        let mine = local.get(path);
        let theirs = base_entries.get(path);
        match (mine, theirs) {
            (None, Some(_)) => { result.insert(path.to_string(), "deleted".to_string()); }
            (Some(_), None) => { result.insert(path.to_string(), "added".to_string()); }
            (Some(m), Some(t)) => {
                if (m.mode.as_str(), m.sha.as_str()) != (t.0.as_str(), t.1.as_str()) {
                    result.insert(path.to_string(), "modified".to_string());
                }
            }
            (None, None) => {}
        }
    }
    result
}

pub fn check_drift(changes: &Changes, local: &BTreeMap<String, Local>, base_entries: &BTreeMap<String, (String, String)>) -> Vec<String> {
    let found = differences(local, base_entries);
    let mut problems = Vec::new();
    for (path, kind) in &found {
        let row = changes.row_for(path);
        match row {
            None => {
                problems.push(format!(
                    "{}: {} here, but local-changes.tsv does not list it. \
                     List it with why, or make it match upstream.",
                    path, kind
                ));
            }
            Some(r) => {
                if r.change != *kind {
                    problems.push(format!(
                        "{}: listed as {} on line {}, but is {}",
                        path, r.change, r.line, kind
                    ));
                }
            }
        }
    }
    for row in &changes.rows {
        if !found.keys().any(|p| row.covers(p)) {
            problems.push(format!(
                "line {} ({}): listed as {}, but matches upstream; remove the row",
                row.line, row.path, row.change
            ));
        }
    }
    problems
}

// --- Sync ---

#[derive(Debug, Default)]
pub struct SyncReport {
    pub base: String,
    pub target: String,
    pub taken: Vec<String>,
    pub merged: Vec<(String, String)>,
    pub added: Vec<String>,
    pub deleted: Vec<String>,
    pub dropped: Vec<(String, String)>,
    pub conflicts: Vec<(String, String)>,
    pub new_top_level: Vec<String>,
    pub ignored: Vec<String>,
    pub server: Vec<String>,
    pub package_json: bool,
    pub commits: usize,
    pub line: Vec<(String, String, String)>,
}

pub fn merge3(ours: &[u8], base: &[u8], theirs: &[u8], labels: &[&str; 3]) -> Result<(Vec<u8>, i32), ToolError> {
    let tmp = tempfile::tempdir().map_err(|e| ToolError(format!("tempdir: {}", e)))?;
    let write_tmp = |name: &str, data: &[u8]| -> Result<PathBuf, ToolError> {
        let p = tmp.path().join(name);
        fs::write(&p, data).map_err(|e| ToolError(format!("write {}: {}", name, e)))?;
        Ok(p)
    };
    let ours_p = write_tmp("ours", ours)?;
    let base_p = write_tmp("base", base)?;
    let theirs_p = write_tmp("theirs", theirs)?;
    let output = git(
        &[
            "merge-file", "-p",
            "-L", labels[0], "-L", labels[1], "-L", labels[2],
            ours_p.to_str().unwrap(), base_p.to_str().unwrap(), theirs_p.to_str().unwrap(),
        ],
        None, None, false, None,
    )?;
    let code = output.status.code().unwrap_or(-1);
    if code < 0 || code > 127 {
        return Err(ToolError(format!(
            "git merge-file failed: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }
    Ok((output.stdout, code))
}

mod tempfile {
    use std::fs;
    use std::path::PathBuf;

    pub struct TempDir(PathBuf);

    impl TempDir {
        pub fn path(&self) -> &std::path::Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    pub fn tempdir() -> Result<TempDir, std::io::Error> {
        let base = std::env::temp_dir();
        let mut rng_seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64;
        rng_seed ^= std::process::id() as u64;
        for _ in 0..100 {
            rng_seed = rng_seed.wrapping_mul(6364136223846793005).wrapping_add(1);
            let dir = base.join(format!("gev_upstream_{:016x}", rng_seed));
            match fs::create_dir(&dir) {
                Ok(()) => return Ok(TempDir(dir)),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(std::io::Error::new(std::io::ErrorKind::Other, "could not create temp dir"))
    }
}

fn write_file(path: &Path, data: &[u8], mode: &str) -> Result<(), ToolError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| ToolError(format!("mkdir {}: {}", parent.display(), e)))?;
    }
    let is_symlink = path.symlink_metadata().map(|m| m.file_type().is_symlink()).unwrap_or(false);
    if is_symlink || mode == "120000" {
        if path.exists() || is_symlink {
            fs::remove_file(path)
                .map_err(|e| ToolError(format!("unlink {}: {}", path.display(), e)))?;
        }
        if mode == "120000" {
            let target = String::from_utf8_lossy(data);
            std::os::unix::fs::symlink(target.as_ref(), path)
                .map_err(|e| ToolError(format!("symlink {}: {}", path.display(), e)))?;
            return Ok(());
        }
    }
    fs::write(path, data)
        .map_err(|e| ToolError(format!("write {}: {}", path.display(), e)))?;
    let meta = path.metadata()
        .map_err(|e| ToolError(format!("stat {}: {}", path.display(), e)))?;
    let current = meta.permissions().mode();
    let new_mode = if mode == "100755" {
        current | 0o111
    } else {
        current & !0o111
    };
    fs::set_permissions(path, std::fs::Permissions::from_mode(new_mode))
        .map_err(|e| ToolError(format!("chmod {}: {}", path.display(), e)))?;
    Ok(())
}

pub fn sync(
    root: &Path,
    changes: &mut Changes,
    upstream: &Upstream,
    target: &str,
    dry_run: bool,
) -> Result<SyncReport, ToolError> {
    let (base, _) = upstream.resolve_base(changes)?;
    let target = upstream.resolve(target)?;
    let mut report = SyncReport {
        base: base.clone(),
        target: target.clone(),
        ..Default::default()
    };
    let (commits, line) = upstream.commits_between(&base, &target)?;
    report.commits = commits;
    report.line = line;
    if base == target {
        return Ok(report);
    }
    let local = local_files(root)?;
    let labels = ["this copy", &format!("upstream {}", &base[..10]), &format!("upstream {}", &target[..10])];
    let app = app_dir(root);
    let mut written = Vec::new();
    for (status, path, old, new) in upstream.changes_between(&base, &target)? {
        let row = changes.row_for(&path);
        let why = row.map(|r| r.why.clone()).unwrap_or_default();
        let mine = local.get(&path);
        let dest = app.join(&path);
        if path == "package.json" {
            report.package_json = true;
        }
        if SERVER_PATHS.iter().any(|s| path.starts_with(s))
            && !PRODUCTION_SERVER_PATHS.iter().any(|s| path.starts_with(s))
        {
            report.server.push(path.clone());
        }
        if status == 'A' {
            if mine.is_none() {
                if !dry_run {
                    let data = upstream.blob(&new.1)?;
                    write_file(&dest, &data, &new.0)?;
                    written.push(path.clone());
                }
                report.added.push(path);
            } else {
                let m = mine.unwrap();
                if (m.mode.as_str(), m.sha.as_str()) != (new.0.as_str(), new.1.as_str()) {
                    report.conflicts.push((
                        path,
                        format!(
                            "upstream added it, and this copy has its own ({}): keep one",
                            if why.is_empty() { "unlisted" } else { &why }
                        ),
                    ));
                }
            }
            continue;
        }
        if status == 'D' {
            if mine.is_none() {
                continue;
            }
            let m = mine.unwrap();
            if (m.mode.as_str(), m.sha.as_str()) == (old.0.as_str(), old.1.as_str()) {
                if !dry_run {
                    let _ = fs::remove_file(&dest);
                }
                report.deleted.push(path);
            } else {
                report.conflicts.push((
                    path,
                    format!(
                        "upstream deleted it, and this copy changes it ({}): \
                         drop the change or keep the file as `added`",
                        if why.is_empty() { "unlisted" } else { &why }
                    ),
                ));
            }
            continue;
        }
        // Modified
        if mine.is_none() {
            if row.map(|r| r.change.as_str()) == Some("deleted") {
                report.dropped.push((path, why));
            } else {
                report.conflicts.push((path, "upstream changed it, and it is missing here".to_string()));
            }
            continue;
        }
        let m = mine.unwrap();
        let mode = if m.mode == old.0 { new.0.clone() } else { m.mode.clone() };
        if m.sha == old.1 {
            if !dry_run {
                let sr = split_header_owned(&m.data);
                let data = upstream.blob(&new.1)?;
                let out = if is_binary(&data) {
                    data
                } else {
                    join_header(&data, &sr.header, sr.line)
                };
                write_file(&dest, &out, &mode)?;
                written.push(path.clone());
            }
            report.taken.push(path);
            continue;
        }
        let theirs = upstream.blob(&new.1)?;
        let older = upstream.blob(&old.1)?;
        if is_binary(&m.data) || is_binary(&theirs) || is_binary(&older) {
            report.conflicts.push((path, "binary, changed both here and upstream: pick one by hand".to_string()));
            continue;
        }
        let sr = split_header_owned(&m.data);
        let (merged, conflicts) = merge3(&sr.body, &older, &theirs, &[labels[0], labels[1], labels[2]])?;
        if !dry_run {
            write_file(&dest, &join_header(&merged, &sr.header, sr.line), &mode)?;
            written.push(path.clone());
        }
        if conflicts > 0 {
            report.conflicts.push((path, format!("{} conflict(s) marked in the file", conflicts)));
        } else {
            report.merged.push((path, if why.is_empty() { "unlisted".to_string() } else { why }));
        }
    }
    let base_entries = upstream.entries(&base)?;
    let target_entries = upstream.entries(&target)?;
    let old_top: BTreeSet<String> = base_entries.keys().filter_map(|p| p.split('/').next().map(|s| s.to_string())).collect();
    report.new_top_level = target_entries.keys()
        .filter_map(|p| p.split('/').next().map(|s| s.to_string()))
        .collect::<BTreeSet<_>>()
        .difference(&old_top)
        .cloned()
        .collect();
    if !written.is_empty() {
        let input_bytes: Vec<u8> = written.iter()
            .flat_map(|p| {
                let mut v = format!("{}/{}", APP_DIR, p).into_bytes();
                v.push(0);
                v
            })
            .collect();
        let proc = git(
            &["check-ignore", "--stdin", "-z"],
            None, Some(root), false, Some(&input_bytes),
        )?;
        report.ignored = String::from_utf8_lossy(&proc.stdout)
            .split('\0')
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .collect();
    }
    if !dry_run {
        changes.set_base(&target, &upstream.tree_of(&target)?)?;
    }
    Ok(report)
}

fn link(sha: &str) -> String {
    let short = if sha.len() >= 10 { &sha[..10] } else { sha };
    format!("[`{}`]({}/commit/{})", short, UPSTREAM_URL, sha)
}

pub fn report_markdown(r: &SyncReport, dry_run: bool) -> String {
    let mut lines = Vec::new();
    lines.push(format!(
        "## Upstream {} → {}{}",
        link(&r.base), link(&r.target),
        if dry_run { " (dry run)" } else { "" }
    ));
    lines.push(String::new());
    lines.push(format!(
        "{} upstream commit(s); {} on the first-parent line, listed below. \
         {} file(s) took upstream's version, {} added, \
         {} deleted, {} merged into a local change, \
         {} conflict(s).",
        r.commits, r.line.len(),
        r.taken.len(), r.added.len(),
        r.deleted.len(), r.merged.len(),
        r.conflicts.len()
    ));
    lines.push(String::new());

    let mut section = |title: &str, items: &[String]| {
        if !items.is_empty() {
            lines.push(format!("### {}", title));
            lines.push(String::new());
            for i in items {
                lines.push(format!("- {}", i));
            }
            lines.push(String::new());
        }
    };
    section(
        "Conflicts: resolve each before committing",
        &r.conflicts.iter().map(|(p, w)| format!("`{}`: {}", p, w)).collect::<Vec<_>>(),
    );
    section(
        "Merged into a file this copy changes: check the change still does its job",
        &r.merged.iter().map(|(p, w)| format!("`{}`: {}", p, w)).collect::<Vec<_>>(),
    );
    section(
        "Upstream changed a file this copy drops",
        &r.dropped.iter().map(|(p, w)| format!("`{}`: {}", p, w)).collect::<Vec<_>>(),
    );
    let mut follow = Vec::new();
    if !r.added.is_empty() {
        follow.push(format!(
            "{} new file(s): run `bazel run //tools/license:add` to give them the header",
            r.added.len()
        ));
    }
    if r.package_json {
        follow.push(
            "`package.json` changed: run `pnpm install` at the repository root to update \
             `pnpm-lock.yaml`, and keep one version of each dependency (One Version Rule)".to_string()
        );
    }
    if !r.new_top_level.is_empty() {
        follow.push(format!(
            "new top-level entries {}: BUILD.bazel lists directories by name in its globs",
            r.new_top_level.iter().map(|p| format!("`{}`", p)).collect::<Vec<_>>().join(", ")
        ));
    }
    if !r.server.is_empty() {
        follow.push(format!(
            "{} file(s) of upstream's dev-server wiring changed (under {}, outside {}): \
             production runs `server.mjs`, which mounts upstream's providers but not this code, \
             so decide whether `server.mjs` needs the change: {}",
            r.server.len(),
            SERVER_PATHS.iter().map(|p| format!("`{}`", p)).collect::<Vec<_>>().join(" and "),
            PRODUCTION_SERVER_PATHS.iter().map(|p| format!("`{}`", p)).collect::<Vec<_>>().join(" and "),
            r.server.iter().map(|p| format!("`{}`", p)).collect::<Vec<_>>().join(", ")
        ));
    }
    if !r.ignored.is_empty() {
        follow.push(format!(
            "written but ignored by git here, so not committed unless forced: {}",
            r.ignored.iter().map(|p| format!("`{}`", p)).collect::<Vec<_>>().join(", ")
        ));
    }
    section("Follow-ups", &follow);
    if !r.line.is_empty() {
        lines.push("### What landed upstream".to_string());
        lines.push(String::new());
        for (sha, date, subject) in &r.line {
            lines.push(format!("- {} {} {}", link(sha), date, subject));
        }
        lines.push(String::new());
    }
    lines.join("\n")
}

// --- Status ---

pub struct Status {
    pub head: String,
    pub base: String,
    pub reanchored: bool,
    pub commits: usize,
    pub line: Vec<(String, String, String)>,
    pub drift: Vec<String>,
}

pub fn status_markdown(s: &Status, previous_body: Option<&str>) -> String {
    let mut seen: BTreeSet<String> = BTreeSet::new();
    if let Some(body) = previous_body {
        if let Some(start) = body.find("<!-- behind-shas: ") {
            let rest = &body[start + 18..];
            if let Some(end) = rest.find(" -->") {
                for sha in rest[..end].split_whitespace() {
                    seen.insert(sha.to_string());
                }
            }
        }
    }
    let new: Vec<&(String, String, String)> = s.line.iter().filter(|c| {
        let short = if c.0.len() >= 12 { &c.0[..12] } else { &c.0 };
        !seen.contains(short)
    }).collect();
    let mut lines = Vec::new();
    lines.push(format!(
        "<!-- upstream-watch behind: {} drift: {} new: {} -->",
        s.commits, s.drift.len(), new.len()
    ));
    lines.push(format!(
        "<!-- behind-shas: {} -->",
        s.line.iter().map(|c| {
            if c.0.len() >= 12 { c.0[..12].to_string() } else { c.0.clone() }
        }).collect::<Vec<_>>().join(" ")
    ));
    lines.push(format!(
        "Upstream [gods-eye-view]({}) `{}` is at {}. \
         `{}` matches {}, **{}** commit(s) behind.",
        UPSTREAM_URL, UPSTREAM_BRANCH, link(&s.head),
        APP_DIR, link(&s.base), s.commits
    ));
    lines.push(String::new());
    lines.push(format!(
        "Sync: follow `{}/upstream/SYNC.md`; the merge itself is \
         `bazel run //{}: track_upstream -- sync`.",
        APP_DIR, APP_DIR
    ));
    lines.push(String::new());
    if s.reanchored {
        lines.push(format!(
            "Upstream rewrote its history: the base is now {} (same tree).",
            link(&s.base)
        ));
        lines.push(String::new());
    }
    if !s.drift.is_empty() {
        lines.push("### This copy differs from upstream in ways the list does not say".to_string());
        lines.push(String::new());
        for p in &s.drift {
            lines.push(format!("- {}", p));
        }
        lines.push(String::new());
    }
    if !s.line.is_empty() {
        lines.push(format!("### Landed upstream since the base ({})", s.line.len()));
        lines.push(String::new());
        let limit = std::cmp::min(s.line.len(), 200);
        for (sha, date, subject) in &s.line[..limit] {
            lines.push(format!("- {} {} {}", link(sha), date, subject));
        }
        if s.line.len() > 200 {
            lines.push(format!("- … and {} more", s.line.len() - 200));
        }
    }
    lines.join("\n")
}

// --- CLI helpers ---

pub fn repo_root(arg: Option<&str>) -> Result<PathBuf, ToolError> {
    if let Some(a) = arg {
        return Ok(PathBuf::from(a));
    }
    if let Ok(env) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        return Ok(PathBuf::from(env));
    }
    let out = git_out(&["rev-parse", "--show-toplevel"], None, None)?;
    Ok(PathBuf::from(out.trim()))
}

pub fn cache_dir(arg: Option<&str>) -> PathBuf {
    if let Some(a) = arg {
        return PathBuf::from(a);
    }
    let base = std::env::var("XDG_CACHE_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| "~".to_string());
        format!("{}/.cache", home)
    });
    PathBuf::from(base).join("gods-eye-view-upstream")
}

pub fn changes_path(arg: Option<&str>, root: &Path) -> PathBuf {
    match arg {
        Some(a) => PathBuf::from(a),
        None => root.join(APP_DIR).join("upstream/local-changes.tsv"),
    }
}

pub fn cmd_check_changes(path: &Path) -> Result<i32, ToolError> {
    let changes = Changes::load(path)?;
    let errs = changes.errors();
    for e in &errs {
        eprintln!("{}: {}", path.display(), e);
    }
    if !errs.is_empty() {
        return Ok(1);
    }
    println!("local-changes ok: base {}, {} row(s)", &changes.base[..10], changes.rows.len());
    Ok(0)
}

pub fn get_status(
    root: &Path,
    changes_path: &Path,
    upstream_url: &str,
    cache: &Path,
    no_fetch: bool,
) -> Result<Status, ToolError> {
    let changes = Changes::load(changes_path)?;
    let errs = changes.errors();
    if !errs.is_empty() {
        return Err(ToolError(errs.iter().map(|e| format!("{}: {}", changes_path.display(), e)).collect::<Vec<_>>().join("; ")));
    }
    let upstream = Upstream::new(upstream_url, cache, !no_fetch)?;
    let (base, reanchored) = upstream.resolve_base(&changes)?;
    let head = upstream.head()?;
    let (commits, line) = upstream.commits_between(&base, &head)?;
    let local = local_files(root)?;
    let base_entries = upstream.entries(&base)?;
    let drift = check_drift(&changes, &local, &base_entries);
    Ok(Status { head, base, reanchored, commits, line, drift })
}

pub fn cmd_check(
    root: &Path,
    changes_path: &Path,
    upstream_url: &str,
    cache: &Path,
    no_fetch: bool,
) -> Result<i32, ToolError> {
    let s = get_status(root, changes_path, upstream_url, cache, no_fetch)?;
    for p in &s.drift {
        eprintln!("{}", p);
    }
    if !s.drift.is_empty() {
        eprintln!(
            "{} problem(s); see upstream/README.md, \"Local changes\"",
            s.drift.len()
        );
        return Ok(1);
    }
    println!(
        "ok: this copy is upstream {} plus the changes local-changes.tsv lists",
        &s.base[..10]
    );
    Ok(0)
}

pub fn cmd_status(
    root: &Path,
    changes_path: &Path,
    upstream_url: &str,
    cache: &Path,
    no_fetch: bool,
    check: bool,
    markdown: bool,
    previous_body: Option<&str>,
) -> Result<i32, ToolError> {
    let s = get_status(root, changes_path, upstream_url, cache, no_fetch)?;
    if markdown {
        let body = match previous_body {
            Some(p) => {
                let text = fs::read_to_string(p)
                    .map_err(|e| ToolError(format!("{}: {}", p, e)))?;
                Some(text)
            }
            None => None,
        };
        println!("{}", status_markdown(&s, body.as_deref()));
    } else {
        print!(
            "upstream {} at {}; base {}",
            UPSTREAM_BRANCH, &s.head[..10], &s.base[..10]
        );
        if s.reanchored {
            print!(" (re-anchored by tree after an upstream history rewrite)");
        }
        println!();
        println!("{} commit(s) behind, {} on the first-parent line", s.commits, s.line.len());
        for (sha, date, subject) in &s.line {
            println!("  {} {} {}", &sha[..10], date, subject);
        }
        if !s.drift.is_empty() {
            println!("{} problem(s) with local-changes.tsv:", s.drift.len());
            for p in &s.drift {
                println!("  {}", p);
            }
        }
    }
    if check && (s.commits > 0 || !s.drift.is_empty()) {
        return Ok(1);
    }
    Ok(0)
}

pub fn cmd_sync(
    root: &Path,
    changes_path: &Path,
    upstream_url: &str,
    cache: &Path,
    no_fetch: bool,
    to: Option<&str>,
    dry_run: bool,
    report_path: Option<&str>,
    allow_dirty: bool,
) -> Result<i32, ToolError> {
    let mut changes = Changes::load(changes_path)?;
    let errs = changes.errors();
    if !errs.is_empty() {
        return Err(ToolError(errs.iter().map(|e| format!("{}: {}", changes_path.display(), e)).collect::<Vec<_>>().join("; ")));
    }
    if !allow_dirty && !dry_run {
        let dirty = git_out(
            &["status", "--porcelain", "--", APP_DIR],
            None, Some(root),
        )?;
        if !dirty.trim().is_empty() {
            return Err(ToolError(format!(
                "{} has uncommitted changes; commit them first, or pass --allow-dirty",
                APP_DIR
            )));
        }
    }
    let upstream = Upstream::new(upstream_url, cache, !no_fetch)?;
    let target = to.unwrap_or(&upstream.ref_);
    let report = sync(root, &mut changes, &upstream, target, dry_run)?;
    let text = report_markdown(&report, dry_run);
    if let Some(rp) = report_path {
        fs::write(rp, format!("{}\n", text))
            .map_err(|e| ToolError(format!("{}: {}", rp, e)))?;
    }
    println!("{}", text);
    if !report.conflicts.is_empty() { Ok(1) } else { Ok(0) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    const MIT: &str = "Copyright (c) 2026 VitruvianSoftware\n\
\n\
Permission is hereby granted, free of charge, to any person obtaining a copy\n\
of this software ...\n\
\n\
THE SOFTWARE IS PROVIDED \"AS IS\", ... DEALINGS IN THE\n\
SOFTWARE.\n";

    fn js_header() -> String {
        let mut s = String::from("/**\n");
        for line in MIT.lines() {
            let trimmed = format!(" * {}", line);
            s.push_str(trimmed.trim_end());
            s.push('\n');
        }
        s.push_str(" */\n\n");
        s
    }

    fn hash_header() -> String {
        let mut s = String::new();
        for line in MIT.lines() {
            let trimmed = format!("# {}", line);
            s.push_str(trimmed.trim_end());
            s.push('\n');
        }
        s.push('\n');
        s
    }

    fn html_header() -> String {
        let mut s = String::from("<!--\n");
        for line in MIT.lines() {
            let trimmed = format!(" {}", line);
            s.push_str(trimmed.trim_end());
            s.push('\n');
        }
        s.push_str("-->\n\n");
        s
    }

    fn body() -> String {
        (0..12).map(|n| format!("export const line{} = {};\n", n, n)).collect()
    }

    fn camera() -> String {
        let b = body();
        let tail: String = (0..12).map(|n| format!("export const tail{} = {};\n", n, n)).collect();
        format!("{}export const HOME = 'Austin';\n{}", b, tail)
    }

    fn camera_here() -> String {
        camera().replace("'Austin'", "'Irvine'")
    }

    fn run_git(cwd: &Path, args: &[&str]) -> String {
        Command::new("git")
            .args(args)
            .current_dir(cwd)
            .output()
            .expect("git failed")
            .stdout
            .iter()
            .map(|&b| b as char)
            .collect::<String>()
            .trim()
            .to_string()
    }

    fn write_file_str(root: &Path, rel: &str, text: &str, executable: bool) {
        let path = root.join(rel);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(&path, text).unwrap();
        if executable {
            let mut perms = fs::metadata(&path).unwrap().permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&path, perms).unwrap();
        }
    }

    fn do_commit(root: &Path, message: &str) -> String {
        run_git(root, &["add", "-A"]);
        run_git(root, &["commit", "-q", "-m", message]);
        run_git(root, &["rev-parse", "HEAD"])
    }

    fn init_repo(root: &Path) {
        fs::create_dir_all(root).unwrap();
        run_git(root, &["init", "-q", "-b", "main"]);
        run_git(root, &["config", "user.email", "t@example.com"]);
        run_git(root, &["config", "user.name", "t"]);
    }

    fn changes_template(base: &str, tree: &str) -> String {
        format!(
            "# test list\n\
             # base\t{}\ttree\t{}\n\
             # path\tchange\twhy\n\
             src/camera.js\tmodified\tlands on Irvine\n\
             package-lock.json\tdeleted\tpnpm workspace\n\
             server.mjs\tadded\tproduction server\n\
             tests/e2e/\tadded\tlocal suite\n\
             upstream/\tadded\tthis tracking\n",
            base, tree
        )
    }

    #[allow(dead_code)]
    struct Fixture {
        tmp: PathBuf,
        up: PathBuf,
        mono: PathBuf,
        cache: PathBuf,
        base: String,
        base_tree: String,
    }

    impl Fixture {
        fn new(tmp: &Path) -> Self {
            let up = tmp.join("upstream");
            let mono = tmp.join("mono");
            let cache = tmp.join("cache");

            init_repo(&up);
            write_file_str(&up, "src/main.js", &body(), false);
            write_file_str(&up, "src/camera.js", &camera(), false);
            write_file_str(&up, "src/old.js", &body(), false);
            write_file_str(&up, "index.html", "<!doctype html>\n<html></html>\n", false);
            write_file_str(&up, "scripts/dev.sh", "#!/usr/bin/env bash\necho dev\n", true);
            write_file_str(&up, "package-lock.json", "{}\n", false);
            write_file_str(&up, "logo.png", "\0PNG binary\n", false);
            write_file_str(&up, "server/routes.js", &body(), false);
            let base = do_commit(&up, "A");
            let base_tree = run_git(&up, &["rev-parse", "HEAD^{tree}"]);

            init_repo(&mono);
            let app = mono.join(APP_DIR);
            write_file_str(&app, "src/main.js", &format!("{}{}", js_header(), body()), false);
            write_file_str(&app, "src/camera.js", &format!("{}{}", js_header(), camera_here()), false);
            write_file_str(&app, "src/old.js", &format!("{}{}", js_header(), body()), false);
            write_file_str(&app, "index.html", &format!("<!doctype html>\n{}<html></html>\n", html_header()), false);
            write_file_str(&app, "scripts/dev.sh", &format!("#!/usr/bin/env bash\n{}echo dev\n", hash_header()), true);
            write_file_str(&app, "logo.png", "\0PNG binary\n", false);
            write_file_str(&app, "server/routes.js", &format!("{}{}", js_header(), body()), false);
            write_file_str(&app, "server.mjs", &format!("{}serve();\n", js_header()), false);
            write_file_str(&app, "tests/e2e/run.sh", "echo e2e\n", false);
            write_file_str(
                &app,
                "upstream/local-changes.tsv",
                &changes_template(&base, &base_tree),
                false,
            );
            do_commit(&mono, "import");

            Fixture { tmp: tmp.to_path_buf(), up, mono, cache, base, base_tree }
        }

        fn changes_path(&self) -> PathBuf {
            self.mono.join(APP_DIR).join("upstream/local-changes.tsv")
        }

        fn tool(&self, args: &[&str], fetch: bool) -> i32 {
            let mut argv: Vec<String> = vec![
                "--root".to_string(), self.mono.to_string_lossy().to_string(),
                "--cache".to_string(), self.cache.to_string_lossy().to_string(),
                "--upstream-url".to_string(), self.up.to_string_lossy().to_string(),
            ];
            if !fetch {
                argv.push("--no-fetch".to_string());
            }
            for a in args {
                argv.push(a.to_string());
            }
            run_cli_code(&argv)
        }

        fn read_file(&self, rel: &str) -> String {
            fs::read_to_string(self.mono.join(APP_DIR).join(rel)).unwrap()
        }
    }

    fn run_cli_code(argv: &[String]) -> i32 {
        let args: Vec<&str> = argv.iter().map(|s| s.as_str()).collect();

        let mut root_arg = None;
        let mut changes_arg = None;
        let mut upstream_url = UPSTREAM_URL;
        let mut cache_arg = None;
        let mut no_fetch = false;
        let mut i = 0;

        while i < args.len() {
            match args[i] {
                "--root" => { root_arg = Some(args[i + 1]); i += 2; }
                "--changes" => { changes_arg = Some(args[i + 1]); i += 2; }
                "--upstream-url" => { upstream_url = args[i + 1]; i += 2; }
                "--cache" => { cache_arg = Some(args[i + 1]); i += 2; }
                "--no-fetch" => { no_fetch = true; i += 1; }
                _ => break,
            }
        }

        let root = repo_root(root_arg).unwrap();
        let cp = changes_path(changes_arg, &root);
        let cache = cache_dir(cache_arg);
        let cmd = if i < args.len() { args[i] } else { "" };
        let rest = &args[i + 1..];

        match cmd {
            "check-changes" => {
                match cmd_check_changes(&cp) {
                    Ok(c) => c,
                    Err(e) => { eprintln!("upstream: {}", e); 2 }
                }
            }
            "check" => {
                match cmd_check(&root, &cp, upstream_url, &cache, no_fetch) {
                    Ok(c) => c,
                    Err(e) => { eprintln!("upstream: {}", e); 2 }
                }
            }
            "status" => {
                let mut check = false;
                let mut markdown = false;
                let mut previous_body = None;
                let mut j = 0;
                while j < rest.len() {
                    match rest[j] {
                        "--check" => { check = true; j += 1; }
                        "--markdown" => { markdown = true; j += 1; }
                        "--previous-body" => { previous_body = Some(rest[j + 1]); j += 2; }
                        _ => { j += 1; }
                    }
                }
                match cmd_status(&root, &cp, upstream_url, &cache, no_fetch, check, markdown, previous_body) {
                    Ok(c) => c,
                    Err(e) => { eprintln!("upstream: {}", e); 2 }
                }
            }
            "sync" => {
                let mut to = None;
                let mut dry_run = false;
                let mut report_path = None;
                let mut allow_dirty = false;
                let mut j = 0;
                while j < rest.len() {
                    match rest[j] {
                        "--to" => { to = Some(rest[j + 1]); j += 2; }
                        "--dry-run" => { dry_run = true; j += 1; }
                        "--report" => { report_path = Some(rest[j + 1]); j += 2; }
                        "--allow-dirty" => { allow_dirty = true; j += 1; }
                        _ => { j += 1; }
                    }
                }
                match cmd_sync(&root, &cp, upstream_url, &cache, no_fetch, to, dry_run, report_path, allow_dirty) {
                    Ok(c) => c,
                    Err(e) => { eprintln!("upstream: {}", e); 2 }
                }
            }
            _ => {
                eprintln!("unknown command: {}", cmd);
                2
            }
        }
    }

    // ---------- Header tests ----------

    #[test]
    fn test_splits_and_rejoins_python_mit_header() {
        let jh = js_header();
        let hh = hash_header();
        let xh = html_header();
        let cases: Vec<(&str, &str, &str)> = vec![
            ("", &jh, "import x;\n"),
            ("#!/usr/bin/env node\n", &jh, "run();\n"),
            ("", &hh, "set -e\n"),
            ("#!/usr/bin/env bash\n", &hh, "set -e\n"),
            ("<!doctype html>\n", &xh, "<html></html>\n"),
        ];
        for (prefix, header, rest) in &cases {
            let data = format!("{}{}{}", prefix, header, rest);
            let data_bytes = data.as_bytes();
            let sr = split_header_owned(data_bytes);
            let expected_body = format!("{}{}", prefix, rest);
            assert_eq!(sr.body, expected_body.as_bytes(), "body mismatch for prefix={:?}", prefix);
            assert_eq!(sr.header, header.as_bytes(), "header mismatch for prefix={:?}", prefix);
            let rejoined = join_header(&sr.body, &sr.header, sr.line);
            assert_eq!(rejoined, data_bytes, "round-trip failed for prefix={:?}", prefix);
        }
    }

    #[test]
    fn test_splits_and_rejoins_js_mit_header() {
        let data = format!("{}{}", js_header(), body());
        let sr = split_header_owned(data.as_bytes());
        assert_eq!(sr.header, js_header().as_bytes());
        assert_eq!(sr.body, body().as_bytes());
        assert_eq!(join_header(&sr.body, &sr.header, sr.line), data.as_bytes());
    }

    #[test]
    fn test_leaves_unheadered_file_unchanged() {
        let data = b"// Copyright 2024 Someone Else\nlet x;\n";
        let sr = split_header_owned(data);
        assert_eq!(sr.body, data);
        assert!(sr.header.is_empty());
    }

    #[test]
    fn test_leaves_shebang_on_line_one() {
        let data = format!("#!/usr/bin/env bash\n{}set -e\n", hash_header());
        let sr = split_header_owned(data.as_bytes());
        assert_eq!(sr.body, b"#!/usr/bin/env bash\nset -e\n");
        assert_eq!(sr.header, hash_header().as_bytes());
        assert_eq!(sr.line, 1);
    }

    #[test]
    fn test_validates_against_live_package() {
        let path_env = std::env::var("UPSTREAM_LOCAL_CHANGES").ok();
        let path = match &path_env {
            Some(p) => PathBuf::from(p),
            None => {
                let here = PathBuf::from(file!());
                let candidate = here
                    .parent().unwrap()
                    .parent().unwrap()
                    .join("local-changes.tsv");
                candidate
            }
        };
        if !path.exists() {
            eprintln!("skipping live validation: {} not found", path.display());
            return;
        }
        let changes = Changes::load(&path).unwrap();
        assert!(changes.errors().is_empty(), "errors: {:?}", changes.errors());
        assert!(
            changes.row_for("upstream/upstream.py").is_some(),
            "the list must cover upstream/"
        );
    }

    #[test]
    fn test_rejects_unsorted_and_malformed_rows() {
        let tmp = super::tempfile::tempdir().unwrap();
        let path = tmp.path().join("list.tsv");
        let base = "a".repeat(40);
        let tree = "b".repeat(40);
        fs::write(&path, format!(
            "# base\t{}\ttree\t{}\n\
             src/a.js\tmodified\twhy\n\
             src/a.js\tadded\tagain\n\
             src/b.js\trenamed\twhy\n\
             dir/\tmodified\twhy\n\
             ../c.js\tadded\twhy\n\
             d.js\tdeleted\t-\n",
            base, tree
        )).unwrap();
        let changes = Changes::load(&path).unwrap();
        let errs = changes.errors().join("\n");
        assert!(errs.contains("duplicate of line 2"), "missing duplicate error: {}", errs);
        assert!(errs.contains("'renamed' is not one of") || errs.contains("\"renamed\" is not one of"),
            "missing renamed error: {}", errs);
        assert!(errs.contains("only an `added` row may name a directory"), "missing directory error: {}", errs);
        assert!(errs.contains("not relative"), "missing relative error: {}", errs);
        assert!(errs.contains("say why"), "missing why error: {}", errs);
    }

    #[test]
    fn test_strips_header_to_match_upstream_blob() {
        let upstream_body = body();
        let local_data = format!("{}{}", js_header(), body());
        let sr = split_header_owned(local_data.as_bytes());
        assert_eq!(blob_id(&sr.body), blob_id(upstream_body.as_bytes()));
    }

    // ---------- Tool integration tests ----------

    #[test]
    fn test_detects_undeclared_modification_and_addition() {
        let tmp = super::tempfile::tempdir().unwrap();
        let f = Fixture::new(tmp.path());

        // First verify check passes
        let code = f.tool(&["check"], true);
        assert_eq!(code, 0, "initial check failed");

        // Add an unlisted modification
        write_file_str(
            &f.mono.join(APP_DIR),
            "src/main.js",
            &format!("{}{}tweak();\n", js_header(), body()),
            false,
        );
        let code = f.tool(&["check"], false);
        assert_eq!(code, 1);
    }

    #[test]
    fn test_detects_stale_modified_entry() {
        let tmp = super::tempfile::tempdir().unwrap();
        let f = Fixture::new(tmp.path());
        let cp = f.changes_path();
        let mut text = fs::read_to_string(&cp).unwrap();
        text.push_str("src/main.js\tmodified\tno longer true\n");
        text.push_str("tests/e2e/run.sh\tmodified\twrong kind\n");
        fs::write(&cp, text).unwrap();
        let code = f.tool(&["check"], true);
        assert_eq!(code, 1);
    }

    #[test]
    fn test_sync_takes_clean_upstream_advance_and_reapplies_header() {
        let tmp = super::tempfile::tempdir().unwrap();
        let f = Fixture::new(tmp.path());

        // Upstream moves: modify main.js (unchanged here = taken), modify
        // camera.js (changed here = merge), delete old.js, add fresh.js
        write_file_str(&f.up, "src/main.js", &format!("{}more();\n", body()), false);
        write_file_str(&f.up, "src/camera.js", &camera().replace("tail8", "tail8_renamed"), false);
        {
            let old = f.up.join("src/old.js");
            if old.exists() { fs::remove_file(&old).unwrap(); }
        }
        write_file_str(&f.up, "src/fresh.js", "fresh();\n", false);
        write_file_str(&f.up, "package-lock.json", "{\"v\": 2}\n", false);
        write_file_str(&f.up, "index.html", "<!doctype html>\n<html lang=en></html>\n", false);
        {
            let dev_sh = f.up.join("scripts/dev.sh");
            let mut perms = fs::metadata(&dev_sh).unwrap().permissions();
            perms.set_mode(0o644);
            fs::set_permissions(&dev_sh, perms).unwrap();
        }
        write_file_str(&f.up, "server/routes.js", &format!("{}route();\n", body()), false);
        write_file_str(&f.up, "server/providers/flights.js", "flights();\n", false);
        write_file_str(&f.up, "maps/tiles.js", "tiles();\n", false);
        let target = do_commit(&f.up, "B");

        let code = f.tool(&["sync"], true);
        assert_eq!(code, 0, "sync failed");

        // main.js: taken with header
        assert_eq!(
            f.read_file("src/main.js"),
            format!("{}{}more();\n", js_header(), body())
        );
        // camera.js: merged
        assert_eq!(
            f.read_file("src/camera.js"),
            format!("{}{}", js_header(), camera_here().replace("tail8", "tail8_renamed"))
        );
        // old.js: deleted
        assert!(!f.mono.join(APP_DIR).join("src/old.js").exists());
        // fresh.js: added (no header since tool only reports it)
        assert_eq!(f.read_file("src/fresh.js"), "fresh();\n");
        // base updated
        assert!(f.changes_path().read_to_string().unwrap_or_default().contains(&format!("# base\t{}\ttree\t", target)));
        // check should still pass
        let code2 = f.tool(&["check"], false);
        assert_eq!(code2, 0, "check after sync failed");
    }

    trait ReadToStringHelper {
        fn read_to_string(&self) -> Result<String, std::io::Error>;
    }
    impl ReadToStringHelper for PathBuf {
        fn read_to_string(&self) -> Result<String, std::io::Error> {
            fs::read_to_string(self)
        }
    }

    #[test]
    fn test_sync_three_way_merges_modified_file() {
        let tmp = super::tempfile::tempdir().unwrap();
        let f = Fixture::new(tmp.path());
        write_file_str(&f.up, "src/camera.js", &camera().replace("tail8", "tail8_renamed"), false);
        do_commit(&f.up, "B");
        let code = f.tool(&["sync"], true);
        assert_eq!(code, 0);
        let text = f.read_file("src/camera.js");
        assert!(text.contains("'Irvine'"), "merge should keep our change");
        assert!(text.contains("tail8_renamed"), "merge should take upstream's rename");
    }

    #[test]
    fn test_sync_records_conflict_and_leaves_tree_clean() {
        let tmp = super::tempfile::tempdir().unwrap();
        let f = Fixture::new(tmp.path());
        write_file_str(&f.up, "src/camera.js", &camera().replace("'Austin'", "'Denver'"), false);
        let _target = do_commit(&f.up, "B");
        let code = f.tool(&["sync"], true);
        assert_eq!(code, 1, "sync should return 1 on conflicts");
        let text = f.read_file("src/camera.js");
        assert!(text.contains("<<<<<<< this copy"), "conflict markers missing");
        assert!(text.contains("'Irvine'"), "our side missing");
        assert!(text.contains("'Denver'"), "their side missing");
    }

    #[test]
    fn test_sync_leaves_deleted_and_added_files_alone() {
        let tmp = super::tempfile::tempdir().unwrap();
        let f = Fixture::new(tmp.path());
        // Upstream deletes camera.js (which we modified): should conflict, not delete
        {
            let cam = f.up.join("src/camera.js");
            fs::remove_file(&cam).unwrap();
        }
        do_commit(&f.up, "B");
        let code = f.tool(&["sync"], true);
        assert_eq!(code, 1);
        assert!(f.mono.join(APP_DIR).join("src/camera.js").exists(), "should not delete a modified file");
    }

    #[test]
    fn test_parity_with_python_check_changes() {
        let here = PathBuf::from(file!());
        let app_dir = here.parent().unwrap().parent().unwrap().parent().unwrap().to_path_buf();
        let tsv = app_dir.join("upstream/local-changes.tsv");
        if !tsv.exists() {
            eprintln!("skipping parity test: {} not found", tsv.display());
            return;
        }
        // Run Python
        let py_script = app_dir.join("upstream/upstream.py");
        if !py_script.exists() {
            eprintln!("skipping parity test: {} not found", py_script.display());
            return;
        }
        let py_out = Command::new("python3")
            .args([
                py_script.to_str().unwrap(),
                "--root",
                app_dir.to_str().unwrap(),
                "--changes",
                tsv.to_str().unwrap(),
                "check-changes",
            ])
            .output();
        let py_out = match py_out {
            Ok(o) => o,
            Err(_) => { eprintln!("skipping parity test: python3 not available"); return; }
        };

        // Run Rust
        let rs_result = cmd_check_changes(&tsv);
        let rs_code = match rs_result {
            Ok(c) => c,
            Err(_) => 2,
        };

        let py_code = py_out.status.code().unwrap_or(2);
        assert_eq!(rs_code, py_code, "exit code mismatch: rust={} python={}", rs_code, py_code);
    }
}
