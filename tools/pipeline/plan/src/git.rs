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

//! The git side: which files changed (diff.go), resolving a revision, and
//! the bit of history the earlier-map rule needs (main.go's gitRevGraph).

use unitfile::gocompat::exec::{self, Cmd, Ctx, Io};

use crate::RevGraph;

/// Parameters for the diff.
#[derive(Clone, Default)]
pub struct DiffOptions {
    pub repo_root: String,
    pub base: String,
    pub head: String,
    pub base_ref: String,
    pub base_sha: String,
    pub before_rev: String,
    pub event: String,
}

fn git_cmd(dir: &str, args: &[&str]) -> Cmd {
    let mut c = Cmd::new("git", args);
    c.dir = dir.to_string();
    c
}

/// `git merge-base <reference> HEAD`, trimmed, or None.
fn merge_base(ctx: &Ctx, dir: &str, reference: &str) -> Option<String> {
    let mut c = git_cmd(dir, &["merge-base", reference, "HEAD"]);
    c.stdout = Io::Capture;
    let (r, out) = exec::run(&c, ctx);
    if r.is_ok() {
        let base = exec::trim_space(&out.stdout);
        if !base.is_empty() {
            return Some(base);
        }
    }
    None
}

/// The base revision to diff against.
pub fn resolve_diff_base(ctx: &Ctx, o: &DiffOptions) -> String {
    if !o.base.is_empty() {
        return o.base.clone();
    }
    if !o.before_rev.is_empty() {
        return o.before_rev.clone();
    }
    if !o.base_sha.is_empty() {
        return o.base_sha.clone();
    }
    if !o.base_ref.is_empty() {
        let reference = format!("origin/{}", o.base_ref);
        return merge_base(ctx, &o.repo_root, &reference).unwrap_or(reference);
    }
    merge_base(ctx, &o.repo_root, "origin/main").unwrap_or_else(|| "HEAD~1".to_string())
}

/// `git diff --name-only` against the resolved base: the files, and the base.
pub fn extract_changed_files(ctx: &Ctx, o: &DiffOptions) -> (Result<Vec<String>, String>, String) {
    let base = resolve_diff_base(ctx, o);
    let mut args: Vec<&str> = vec!["diff", "--name-only", &base];
    if !o.head.is_empty() {
        args.push(&o.head);
    }
    args.push("--");
    let mut c = git_cmd(&o.repo_root, &args);
    c.stdout = Io::Capture;
    c.stderr = Io::Capture;
    let (r, out) = exec::run(&c, ctx);
    if let Err(e) = r {
        return (
            Err(format!(
                "git diff failed ({}): {e}: {}",
                args.join(" "),
                String::from_utf8_lossy(&out.stderr)
            )),
            base,
        );
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let files = exec::go_trim(&text)
        .split('\n')
        .map(exec::go_trim)
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect();
    (Ok(files), base)
}

/// `cmd.Output()` for git in dir: trimmed stdout, or the error text.
fn git_output(ctx: &Ctx, dir: &str, args: &[&str]) -> Result<String, String> {
    let mut c = git_cmd(dir, args);
    c.stdout = Io::Capture;
    c.stderr = Io::Capture;
    let (r, out) = exec::run(&c, ctx);
    match r {
        Ok(()) => Ok(exec::trim_space(&out.stdout)),
        Err(e) => Err(e.to_string()),
    }
}

/// Resolves rev to a full commit SHA, or "".
pub fn rev_parse(ctx: &Ctx, repo_root: &str, rev: &str) -> String {
    let spec = format!("{rev}^{{commit}}");
    git_output(ctx, repo_root, &["rev-parse", "--verify", "--quiet", &spec]).unwrap_or_default()
}

/// Answers [`RevGraph`] from the repository at `root`.
pub struct GitRevGraph<'a> {
    pub root: String,
    pub ctx: &'a Ctx,
}

impl RevGraph for GitRevGraph<'_> {
    fn is_ancestor(&self, older: &str, newer: &str) -> bool {
        git_output(
            self.ctx,
            &self.root,
            &["merge-base", "--is-ancestor", older, newer],
        )
        .is_ok()
    }

    fn commits_between(&self, older: &str, newer: &str) -> Result<i64, String> {
        let range = format!("{older}..{newer}");
        let out = git_output(self.ctx, &self.root, &["rev-list", "--count", &range])?;
        // strconv.Atoi
        let ok = !out.is_empty()
            && out
                .strip_prefix(['+', '-'])
                .unwrap_or(&out)
                .bytes()
                .all(|c| c.is_ascii_digit())
            && out.len() > usize::from(out.starts_with(['+', '-']));
        match (ok, out.parse::<i64>()) {
            (true, Ok(n)) => Ok(n),
            (true, Err(_)) => Err(format!(
                "strconv.Atoi: parsing {}: value out of range",
                unitfile::gocompat::quote::quote(&out)
            )),
            _ => Err(format!(
                "strconv.Atoi: parsing {}: invalid syntax",
                unitfile::gocompat::quote::quote(&out)
            )),
        }
    }

    fn changed_files(&self, older: &str, newer: &str) -> Result<Vec<String>, String> {
        let out = git_output(
            self.ctx,
            &self.root,
            &["diff", "--name-only", older, newer, "--"],
        )?;
        Ok(crate::query::non_empty_lines(&out))
    }
}
