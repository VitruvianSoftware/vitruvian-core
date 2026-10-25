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

//! //tools/landed in Rust: did this work actually land on main?
//!
//! The same answers as landed.sh (`:landed-sh`), with the same git and gh
//! calls, messages and exit codes; see landed.sh for why the question needs
//! more than `git merge-base --is-ancestor` in a squash-only repository.
//!
//!   landed <pr-number|#pr|branch|commit-sha>
//!   landed --branch <local-branch>          safe to delete this local branch?
//!   landed --remote-branch <branch>         ...this branch on origin?

use std::io::Write;
use std::process::{Command, Stdio};

pub struct Env {
    pub repo: String,
    pub base: String,
    pub no_fetch: bool,
}

fn env_or(name: &str, default: &str) -> String {
    match std::env::var(name) {
        Ok(v) if !v.is_empty() => v,
        _ => default.to_string(),
    }
}

impl Env {
    pub fn from_process() -> Self {
        Env {
            repo: env_or("LANDED_REPO", "VitruvianSoftware/vitruvian-core"),
            base: env_or("LANDED_BASE", "origin/main"),
            no_fetch: env_or("LANDED_NO_FETCH", "0") == "1",
        }
    }
}

/// An early exit with its code; messages are already printed.
pub struct Exit(pub i32);

fn info(msg: &str) {
    let _ = std::io::stdout().write_all(format!("\x1b[36m→\x1b[0m {msg}\n").as_bytes());
}

fn ok(msg: &str) -> Exit {
    let _ = std::io::stdout().write_all(format!("\x1b[32m✓\x1b[0m {msg}\n").as_bytes());
    Exit(0)
}

fn die(msg: &str) -> Exit {
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().write_all(format!("\x1b[31m✗\x1b[0m {msg}\n").as_bytes());
    Exit(1)
}

/// The first `n` characters, as bash's `${v:0:n}`.
fn prefix(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

/// `$(cmd)`: stdout with trailing newlines removed, and whether it exited 0.
/// `quiet` sends stderr to /dev/null, as `2>/dev/null` did.
fn capture(prog: &str, args: &[&str], quiet: bool) -> (bool, String) {
    let mut c = Command::new(prog);
    c.args(args).stdin(Stdio::null()).stdout(Stdio::piped());
    c.stderr(if quiet {
        Stdio::null()
    } else {
        Stdio::inherit()
    });
    match c.output() {
        Ok(o) => {
            let mut s = String::from_utf8_lossy(&o.stdout).into_owned();
            while s.ends_with('\n') {
                s.pop();
            }
            (o.status.success(), s)
        }
        Err(_) => (false, String::new()),
    }
}

fn git(args: &[&str]) -> (bool, String) {
    capture("git", args, false)
}

fn git_quiet(args: &[&str]) -> (bool, String) {
    capture("git", args, true)
}

/// A git command whose status alone matters. Every such call in landed.sh
/// prints nothing or sends its output to /dev/null.
fn git_test(args: &[&str]) -> bool {
    Command::new("git")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// `command -v <name>`.
fn on_path(name: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    let path = std::env::var("PATH").unwrap_or_default();
    path.split(':').any(|dir| {
        let dir = if dir.is_empty() { "." } else { dir };
        let p = std::path::Path::new(dir).join(name);
        p.metadata()
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    })
}

/// `read -r a b ... <<<"$line"`: whitespace-split fields of the first line,
/// the last taking the rest.
fn read_fields(line: &str, n: usize) -> Vec<String> {
    let first = line.split('\n').next().unwrap_or("");
    let mut out = Vec::with_capacity(n);
    let mut rest = first.trim_start_matches([' ', '\t']);
    for i in 0..n {
        if i == n - 1 {
            out.push(rest.trim_end_matches([' ', '\t']).to_string());
            break;
        }
        let end = rest.find([' ', '\t']).unwrap_or(rest.len());
        out.push(rest[..end].to_string());
        rest = rest[end..].trim_start_matches([' ', '\t']);
    }
    out
}

fn first_line(s: &str) -> &str {
    s.split('\n').next().unwrap_or("")
}

pub struct Landed {
    env: Env,
}

impl Landed {
    pub fn new(env: Env) -> Self {
        Landed { env }
    }

    fn fetch_base(&self) {
        if self.env.no_fetch {
            return;
        }
        let branch = self
            .env
            .base
            .strip_prefix("origin/")
            .unwrap_or(&self.env.base);
        let _ = std::io::stdout().flush();
        let _ = Command::new("git")
            .args(["fetch", "origin", branch, "-q"])
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }

    /// Does every commit between a merged PR's head and the branch tip add
    /// nothing BASE lacks? (landed.sh's extras_on_base)
    fn extras_on_base(&self, head: &str, tip: &str) -> bool {
        let base = &self.env.base;
        if !git_test(&["merge-base", "--is-ancestor", head, tip]) {
            return false;
        }
        let (_, list) = git(&["rev-list", tip, &format!("^{head}"), &format!("^{base}")]);
        for c in list.lines() {
            let c = c.trim_matches([' ', '\t']);
            if c.is_empty() {
                continue;
            }
            let (_, parents) = git(&["rev-list", "--parents", "-n", "1", c]);
            let parents: Vec<&str> = parents.split_whitespace().collect();
            match parents.len() {
                2 => {
                    let (_, t1) = git(&["rev-parse", &format!("{c}^{{tree}}")]);
                    let (_, t2) = git(&["rev-parse", &format!("{c}^^{{tree}}")]);
                    if t1 == t2 {
                        continue;
                    }
                    let (cherry_ok, cherry) = git_quiet(&["cherry", base, c, &format!("{c}^")]);
                    if !(cherry_ok && cherry.lines().any(|l| l.starts_with('-'))) {
                        return false;
                    }
                }
                3 => {
                    let (_, merged) =
                        git_quiet(&["merge-tree", "--write-tree", parents[1], parents[2]]);
                    let (_, tree) = git(&["rev-parse", &format!("{c}^{{tree}}")]);
                    if first_line(&merged) != tree {
                        return false;
                    }
                }
                _ => return false,
            }
        }
        true
    }

    /// --branch / --remote-branch: is every commit on this branch on BASE?
    fn gate_branch(&self, br: &str, tip: &str, where_: &str) -> Exit {
        let base = &self.env.base;
        self.fetch_base();
        if !git_test(&["rev-parse", "--verify", "-q", &format!("{base}^{{commit}}")]) {
            return die(&format!(
                "{base} does not exist in this checkout, so '{br}' cannot be checked."
            ));
        }

        if git_test(&["merge-base", "--is-ancestor", tip, base]) {
            return ok(&format!(
                "{br} has no commits of its own: everything on it is already on {base}."
            ));
        }

        let (_, base_tree) = git(&["rev-parse", &format!("{base}^{{tree}}")]);
        let (merge_ok, merged) = git_quiet(&["merge-tree", "--write-tree", base, tip]);
        if merge_ok && first_line(&merged) == base_tree {
            return ok(&format!(
                "{br} is landed: merging it into {base} would change nothing (content check)."
            ));
        }

        let (ahead_ok, ahead) = git_quiet(&["rev-list", "--count", &format!("{base}..{tip}")]);
        // `$(git rev-list ... || echo '?')`: a failed count prints "?".
        let ahead = match (ahead_ok, ahead.is_empty()) {
            (true, _) => ahead,
            (false, true) => "?".to_string(),
            (false, false) => format!("{ahead}\n?"),
        };
        if on_path("gh") {
            let (_, pr_line) = capture(
                "gh",
                &[
                    "pr", "list", "--repo", &self.env.repo, "--head", br, "--state", "all", "--json",
                    "number,state,headRefOid,mergeCommit,createdAt", "-q",
                    "sort_by(.createdAt)|last|\"\\(.number) \\(.state) \\(.headRefOid) \\(.mergeCommit.oid // \"-\")\"",
                ],
                true,
            );
            let f = read_fields(&pr_line, 4);
            let (pr, state, head, squashed) = (&f[0], &f[1], &f[2], &f[3]);
            if state == "MERGED"
                && !squashed.is_empty()
                && squashed != "-"
                && git_test(&["merge-base", "--is-ancestor", squashed, base])
            {
                let head_commit = format!("{head}^{{commit}}");
                if tip == head
                    || (git_test(&["cat-file", "-e", &head_commit])
                        && git_test(&["merge-base", "--is-ancestor", tip, head]))
                {
                    return ok(&format!(
                        "{br} is landed: PR #{pr} merged as {}, and {where_} has nothing past the PR's head.",
                        prefix(squashed, 8)
                    ));
                }
                if git_test(&["cat-file", "-e", &head_commit]) && self.extras_on_base(head, tip) {
                    return ok(&format!(
                        "{br} is landed: PR #{pr} merged as {}, and what {where_} has past the PR's head is already on {base} (empty, clean merges, or patches {base} has).",
                        prefix(squashed, 8)
                    ));
                }
                return die(&format!(
                    "{br} is NOT safe to delete: PR #{pr} merged, but {where_} has commits\n   past what the PR merged (tip {}, PR head {}) that are not on {base}. Push or save them first.",
                    prefix(tip, 8),
                    prefix(head, 8)
                ));
            }
            if !pr.is_empty() && pr != "null" {
                let state = if state.is_empty() { "unknown" } else { state };
                return die(&format!(
                    "{br} is NOT landed: {ahead} commit(s) not on {base}, and PR #{pr} is {state}."
                ));
            }
        }
        die(&format!(
            "{br} is NOT landed: {ahead} commit(s) not on {base}, their changes are not on it\n   either, and no merged pull request covers them."
        ))
    }

    pub fn run(&self, args: &[String]) -> Exit {
        let base = &self.env.base;
        let repo = &self.env.repo;
        let a1 = args.first().map(String::as_str).unwrap_or("");
        let a2 = args.get(1).map(String::as_str).unwrap_or("");

        if a1 == "--branch" {
            if a2.is_empty() {
                return die("usage: landed --branch <local-branch>");
            }
            let (found, tip) = git(&[
                "rev-parse",
                "--verify",
                "-q",
                &format!("refs/heads/{a2}^{{commit}}"),
            ]);
            if !found {
                return die(&format!("no local branch '{a2}'."));
            }
            return self.gate_branch(a2, &tip, "the local branch");
        }

        if a1 == "--remote-branch" {
            if a2.is_empty() {
                return die("usage: landed --remote-branch <branch-on-origin>");
            }
            if !self.env.no_fetch
                && !git_test(&[
                    "fetch",
                    "-q",
                    "origin",
                    &format!("+refs/heads/{a2}:refs/remotes/origin/{a2}"),
                ])
            {
                return die(&format!(
                    "could not fetch '{a2}' from origin: no such branch there, or no network."
                ));
            }
            let (found, tip) = git(&[
                "rev-parse",
                "--verify",
                "-q",
                &format!("refs/remotes/origin/{a2}^{{commit}}"),
            ]);
            if !found {
                return die(&format!("no branch '{a2}' on origin."));
            }
            return self.gate_branch(a2, &tip, "the branch on origin");
        }

        let r = a1;
        if r.is_empty() {
            return die(&format!(
                "usage: landed <pr-number|branch|commit-sha>\n\n   Answers whether that work is on {base}, correctly under squash-merge."
            ));
        }
        if !on_path("gh") {
            return die("gh not on PATH (needed to resolve the PR).");
        }

        // Resolve whatever we were given down to a PR number.
        let mut pr = if let Some(n) = r.strip_prefix('#') {
            n.to_string()
        } else if r.bytes().all(|b| b.is_ascii_digit()) {
            r.to_string()
        } else {
            String::new()
        };
        if pr.is_empty() {
            pr = capture(
                "gh",
                &[
                    "pr",
                    "list",
                    "--repo",
                    repo,
                    "--head",
                    r,
                    "--state",
                    "all",
                    "--json",
                    "number,createdAt",
                    "-q",
                    "sort_by(.createdAt)|last|.number",
                ],
                true,
            )
            .1;
        }
        if pr.is_empty() || pr == "null" {
            pr = capture(
                "gh",
                &[
                    "api",
                    &format!("repos/{repo}/commits/{r}/pulls"),
                    "-q",
                    "map(select(.merged_at != null))|sort_by(.merged_at)|last|.number",
                ],
                true,
            )
            .1;
        }
        if pr.is_empty() || pr == "null" {
            return die(&format!(
                "could not resolve '{r}' to a pull request.\n\n   If it is a LOCAL-ONLY commit, that is the answer: it was never pushed, so it\n   cannot have landed. If it is a branch, it may never have had a PR opened."
            ));
        }

        // Ask GitHub for the squashed commit, then verify it locally.
        let (_, view) = capture(
            "gh",
            &[
                "pr",
                "view",
                &pr,
                "--repo",
                repo,
                "--json",
                "state,mergeCommit",
                "-q",
                "\"\\(.state) \\(.mergeCommit.oid // \"-\")\"",
            ],
            true,
        );
        let f = read_fields(&view, 2);
        let (state, squashed) = (&f[0], &f[1]);

        if state.is_empty() {
            self.fetch_base();
            let (_, local) = git_quiet(&[
                "log",
                "-1",
                "--grep",
                &format!("(#{pr})"),
                "--format=%H",
                base,
            ]);
            if !local.is_empty() {
                let e = ok(&format!(
                    "PR #{pr} is on {base} as {} (squashed) [resolved via commit log].",
                    prefix(&local, 8)
                ));
                info(&git(&["log", "-1", "--format=%s", &local]).1);
                return e;
            }
            return die(&format!("gh could not read PR #{pr} in {repo}."));
        }

        if state != "MERGED" {
            return die(&format!(
                "PR #{pr} is {state}, not MERGED -- this work is NOT on {base}.\n\n   Do not push follow-up commits to a merged PR's branch either: the repo\n   auto-deletes branches on merge, so a push silently re-creates a dangling one."
            ));
        }
        if squashed == "-" {
            return die(&format!(
                "PR #{pr} reports MERGED but exposes no merge commit, so it cannot be\n   verified against {base}. Check it by content instead."
            ));
        }

        self.fetch_base();
        let short = prefix(squashed, 8);
        if !git_test(&["cat-file", "-e", &format!("{squashed}^{{commit}}")]) {
            return die(&format!(
                "PR #{pr} squashed to {short}, which this checkout does not have.\n   Fetch and re-run; do not conclude anything from a stale {base}."
            ));
        }
        if git_test(&["merge-base", "--is-ancestor", squashed, base]) {
            let e = ok(&format!("PR #{pr} is on {base} as {short} (squashed)."));
            info(&git(&["log", "-1", "--format=%s", squashed]).1);
            return e;
        }
        die(&format!(
            "PR #{pr} says MERGED and squashed to {short}, but that commit is\n   NOT an ancestor of {base} in this checkout. Either {base} is stale, or it\n   was merged into a different base branch. Do not report this as landed."
        ))
    }
}

/// Moves into the workspace, as landed.sh's opening `cd` does.
pub fn enter_workspace() -> Result<(), Exit> {
    let dir = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(d) if !d.is_empty() => d,
        _ => {
            let (found, top) = git_quiet(&["rev-parse", "--show-toplevel"]);
            if found {
                top
            } else {
                ".".to_string()
            }
        }
    };
    std::env::set_current_dir(dir).map_err(|_| die("cannot find a workspace to run in"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_fields_is_bash_read() {
        assert_eq!(
            read_fields("42 MERGED abc def", 4),
            vec!["42", "MERGED", "abc", "def"]
        );
        assert_eq!(read_fields("  42  OPEN ", 4), vec!["42", "OPEN", "", ""]);
        assert_eq!(read_fields("", 2), vec!["", ""]);
        assert_eq!(
            read_fields("MERGED a b c\nnext", 2),
            vec!["MERGED", "a b c"]
        );
    }

    #[test]
    fn prefix_is_substring() {
        assert_eq!(prefix("0123456789", 8), "01234567");
        assert_eq!(prefix("-", 8), "-");
    }
}
