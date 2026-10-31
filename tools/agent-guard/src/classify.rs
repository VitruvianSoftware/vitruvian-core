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

//! Verdicts, replacement targets and the classifiers. Each classifier returns
//! a Verdict (blocked) or None (allowed).

use std::cell::RefCell;
use std::collections::HashMap;
use std::process::Command;
use std::time::Duration;

use crate::gitstate::{probe_git_state, run_with_timeout, GitState};
use crate::invocations::{expand_path, skip_opts, Invocation};
use crate::paths::{
    basename, dirname, isabs, isfile, join, lexists, normpath, nul_check, read_text_replace,
    realpath,
};
use crate::pyutil::{
    chars, dollar, is_space, py_lower, py_lstrip, py_splitlines, py_strip, py_upper, split1,
    starts_at, text_lines,
};
use crate::scope::repo_root_of;

pub const GUARDRAIL: &str =
    "agent-guard is a guardrail, not a security boundary: do not route around it \
(no aliases, wrapper scripts, eval, other shells, other tools or absolute paths).";

/// One refused operation: what it was, its category, and what to use instead.
#[derive(Clone, Debug)]
pub struct Verdict {
    pub category: String,
    pub op: String,
    /// None means: there is no Bazel target for this yet.
    pub use_: Option<String>,
    /// (repo-relative file, needle) the target lives in.
    pub pending: Option<(String, Option<String>)>,
    pub note: String,
}

impl Verdict {
    pub fn message(&self, repo_root: Option<&str>) -> String {
        let mut text;
        if let Some(use_) = self.use_.as_deref().filter(|u| !u.is_empty()) {
            text = format!(
                "Blocked by agent-guard: `{}` must go through Bazel in vitruvian-core. Use `{}`.",
                self.op, use_
            );
            if let Some(p) = &self.pending {
                if !target_present(repo_root, p) {
                    text.push_str(
                        " That target is being built and is not in this checkout yet: if `bazel run` \
cannot find it, stop and tell James.",
                    );
                }
            }
        } else if self.category == "guard-config" {
            // Protecting the guard is not a missing target: say what is refused.
            text = format!("Blocked by agent-guard: `{}` is not for agents.", self.op);
        } else {
            text = format!(
                "Blocked by agent-guard: `{}` must go through a Bazel target in vitruvian-core, \
and there is no target for it yet. Stop and tell James that `{}` needs one.",
                self.op, self.op
            );
        }
        if !self.note.is_empty() {
            text.push(' ');
            text.push_str(&self.note);
        }
        text.push(' ');
        text.push_str(GUARDRAIL);
        if self.use_.as_deref().map_or(false, |u| !u.is_empty()) {
            text.push_str(" If no target fits, stop and tell James which one is missing.");
        }
        text
    }
}

fn target_present(repo_root: Option<&str>, pending: &(String, Option<String>)) -> bool {
    let Some(root) = repo_root.filter(|r| !r.is_empty()) else {
        return true;
    };
    let path = join(root, &pending.0);
    match &pending.1 {
        None => crate::paths::exists(&path),
        Some(needle) => match read_text_replace(&path) {
            Some(text) => text.contains(needle.as_str()),
            None => false,
        },
    }
}

/// A replacement target: what to run, and where it will live. Every file a
/// `pending` names must exist on main (the pending-targets test checks), or
/// every refusal naming that target wrongly says it is not built yet.
#[derive(Clone, Copy)]
pub struct Target {
    pub use_: &'static str,
    pub pending: Option<(&'static str, Option<&'static str>)>,
}

const fn t(use_: &'static str, pending: Option<(&'static str, Option<&'static str>)>) -> Target {
    Target { use_, pending }
}

pub const T_COMMIT: Target = t(
    "bazel run //tools/git:commit",
    Some(("tools/git/BUILD", Some("commit"))),
);
pub const T_PUSH: Target = t(
    "bazel run //tools/git:push",
    Some(("tools/git/BUILD", Some("push"))),
);
pub const T_SYNC: Target = t(
    "bazel run //tools/git:sync",
    Some(("tools/git/BUILD", Some("sync"))),
);
pub const T_WT_NEW: Target = t("bazel run //tools/worktree -- <branch> [base-ref]", None);
pub const T_WT_DETACH: Target = t("bazel run //tools/worktree -- --detach <ref>", None);
pub const T_WT_REMOVE: Target = t("bazel run //tools/worktree -- --remove <branch>", None);
pub const T_WT_PRUNE: Target = t(
    "bazel run //tools/worktree -- --prune (then --prune --execute)",
    None,
);
pub const T_WT_LOCK: Target = t("bazel run //tools/worktree -- --lock / --unlock", None);
pub const T_WT_DELETE_BRANCH: Target = t(
    "bazel run //tools/worktree -- --remove <branch> --delete-branch (or --prune --execute)",
    None,
);
pub const T_PR_CREATE: Target = t("bazel run //tools/agent-app -- pr-create", None);
pub const T_PR_ENQUEUE: Target = t("bazel run //tools/agent-app -- pr-enqueue <pr>", None);
pub const T_RUN_RERUN: Target = t(
    "bazel run //tools/agent-app -- run-rerun <run-id> [--failed] [--job <id>]",
    None,
);
pub const T_RUN_CANCEL: Target = t("bazel run //tools/agent-app -- run-cancel <run-id>", None);
pub const T_WORKFLOW_RUN: Target = t(
    "bazel run //tools/agent-app -- workflow-run <file.yaml> [-f k=v ...] [--ref main]",
    None,
);
pub const RUN_NOTE: &str = "Only wren's App has Actions write; any other agent: tell James.";
pub const RUN_NO_TARGET_NOTE: &str =
    "//tools/agent-app has run-rerun, run-cancel and workflow-run, but nothing \
that deletes runs or enables or disables workflows.";
pub const T_SECRET_SCAN: Target = t(
    "bazel run //tools/secret-scan",
    Some(("tools/secret-scan/BUILD", None)),
);
pub const T_ACTIONLINT: Target = t(
    "bazel run //tools/ci:actionlint",
    Some(("tools/ci/BUILD", Some("\"actionlint\""))),
);
pub const T_CACHE_GC: Target = t(
    "bazel run //tools/bazel-cache:gc (dry run; add -- --execute to delete)",
    None,
);
pub const T_FORMAT: Target = t("bazel run //tools/format (or bazel run //:tidy)", None);
pub const T_LINT: Target = t("aspect lint //<package>/...", None);
pub const T_BAZEL_TEST: Target = t("bazel test //<package>/...", None);
pub const T_BAZEL_BUILD: Target = t(
    "bazel build //<package>:<target> (or bazel run for a binary)",
    None,
);
pub const T_PULUMI: Target = t(
    "bazel run //infrastructure/pulumi/<project>:preview (and :up only as AGENTS.md allows)",
    None,
);
pub const T_GITOPS: Target = t(
    "bazel run //tools/gitops:{apply,delete,patch} (or change the manifest in git and let Argo CD sync)",
    None,
);
pub const T_HELM: Target = t(
    "bazel run //tools/gitops:helm -- <args> (or change the chart values in git)",
    None,
);

/// `V(category, op, target, note)`.
pub fn v(category: &str, op: &str, target: Option<Target>, note: &str) -> Verdict {
    Verdict {
        category: category.to_string(),
        op: op.to_string(),
        use_: target.map(|t| t.use_.to_string()),
        pending: target
            .and_then(|t| t.pending)
            .map(|(f, n)| (f.to_string(), n.map(|s| s.to_string()))),
        note: note.to_string(),
    }
}

fn vn(category: &str, op: &str) -> Option<Verdict> {
    Some(v(category, op, None, ""))
}

fn vt(category: &str, op: &str, target: Target) -> Option<Verdict> {
    Some(v(category, op, Some(target), ""))
}

/// How a Context learns a directory's git state (tests pass a fixed one).
pub type GitProbe = Box<dyn Fn(&str) -> GitState>;

pub struct Context {
    pub home: String,
    git_state: GitProbe,
    cache: RefCell<HashMap<String, GitState>>,
}

impl Context {
    pub fn new(home: &str, git_state: Option<GitProbe>) -> Self {
        Context {
            home: home.to_string(),
            git_state: git_state.unwrap_or_else(|| Box::new(probe_git_state)),
            cache: RefCell::new(HashMap::new()),
        }
    }

    pub fn state(&self, cwd: &str) -> GitState {
        if let Some(s) = self.cache.borrow().get(cwd) {
            return s.clone();
        }
        let s = (self.git_state)(cwd);
        self.cache.borrow_mut().insert(cwd.to_string(), s.clone());
        s
    }
}

thread_local! {
    /// What `installer_problem` returns while a test has replaced it (the
    /// Python tests patch it the same way), or None to really check.
    pub static INSTALLER_PROBLEM_OVERRIDE: RefCell<Option<String>> = RefCell::new(None);
}

const GIT_READ_ONLY: &[&str] = &[
    "status",
    "log",
    "diff",
    "show",
    "fetch",
    "rev-parse",
    "ls-files",
    "ls-tree",
    "ls-remote",
    "grep",
    "blame",
    "annotate",
    "shortlog",
    "describe",
    "rev-list",
    "merge-base",
    "cat-file",
    "for-each-ref",
    "show-ref",
    "name-rev",
    "whatchanged",
    "range-diff",
    "diff-tree",
    "diff-files",
    "diff-index",
    "check-ignore",
    "check-attr",
    "check-ref-format",
    "count-objects",
    "var",
    "version",
    "help",
    "format-patch",
    "archive",
    "verify-commit",
    "verify-tag",
    "show-branch",
    "cherry",
    "merge-tree",
    "fsck",
    "column",
    "difftool",
    "restore",
    "get-tar-commit-id",
    "check-mailmap",
    "show-index",
    "unpack-file",
];
const GIT_GLOBAL_WITH_ARG: &[&str] = &[
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--super-prefix",
    "--config-env",
    "--exec-path",
    "--list-cmds",
];

fn inl(list: &[&str], a: &str) -> bool {
    list.contains(&a)
}

pub fn has(args: &[String], flags: &[&str]) -> bool {
    args.iter().any(|a| {
        flags
            .iter()
            .any(|f| a == f || (f.starts_with("--") && a.starts_with(&format!("{}=", f))))
    })
}

pub fn short_cluster_has(args: &[String], letters: &str) -> bool {
    args.iter().any(|a| {
        a.starts_with('-')
            && !a.starts_with("--")
            && a.chars().count() > 1
            && a[1..].chars().any(|c| letters.contains(c))
    })
}

pub fn positionals(args: &[String], with_arg: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--" {
            out.extend_from_slice(&args[i + 1..]);
            break;
        }
        if a.starts_with('-') && a != "-" {
            if inl(with_arg, a) {
                i += 2;
                continue;
            }
            i += 1;
            continue;
        }
        out.push(a.clone());
        i += 1;
    }
    out
}

const FETCH_WITH_ARG: &[&str] = &[
    "--depth",
    "--deepen",
    "--shallow-since",
    "--shallow-exclude",
    "--negotiation-tip",
    "--refmap",
    "--upload-pack",
    "-j",
    "--jobs",
    "-o",
    "--server-option",
    "--recurse-submodules-default",
    "--submodule-prefix",
    "--filter",
    "-s",
    "--strategy",
    "-X",
    "--strategy-option",
];

/// What makes this fetch (or pull) write a ref it names, or "" if nothing does.
fn fetch_into_named_ref(vargs: &[String], config: &[String]) -> String {
    for c in config {
        let key = py_lower(split1(c, '=').0);
        if key.starts_with("remote.") || key.starts_with("url.") {
            return format!("-c {}", key);
        }
    }
    for (i, a) in vargs.iter().enumerate() {
        if a == "--refmap" && i + 1 < vargs.len() && !vargs[i + 1].is_empty() {
            return "--refmap".into();
        }
        if let Some(rest) = a.strip_prefix("--refmap=") {
            if !rest.is_empty() {
                return "--refmap".into();
            }
        }
    }
    if has(vargs, &["--multiple", "--all"]) {
        return String::new(); // every argument is a remote or group, none is a refspec
    }
    let pos = positionals(vargs, FETCH_WITH_ARG);
    for spec in pos.iter().skip(1) {
        let stripped = spec.trim_start_matches('+');
        if let (_, Some(dst)) = split1(stripped, ':') {
            if !dst.is_empty() {
                return spec.clone();
            }
        }
    }
    String::new()
}

/// Returns (verdict, effective cwd).
pub fn classify_git(inv: &Invocation, ctx: &Context) -> (Option<Verdict>, String) {
    let args = &inv.argv[1..];
    let mut cwd = inv.cwd.clone();
    let mut config: Vec<String> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if !a.starts_with('-') {
            break;
        }
        let (name, eq) = split1(a, '=');
        let val = match eq {
            Some(v) => v.to_string(),
            None => args.get(i + 1).cloned().unwrap_or_default(),
        };
        if name == "-c" || name == "--config-env" {
            config.push(val.clone());
        }
        if name == "-C" || name == "--work-tree" {
            cwd = expand_path(&val, &cwd, &ctx.home);
        } else if name == "--git-dir" {
            let gd = expand_path(&val, &cwd, &ctx.home);
            cwd = if basename(&gd) == ".git" {
                dirname(&gd)
            } else {
                gd
            };
        }
        if inl(GIT_GLOBAL_WITH_ARG, name) && !a.contains('=') {
            i += 2;
        } else {
            i += 1;
        }
    }
    let rest = &args[i.min(args.len())..];
    if rest.is_empty() {
        return (None, cwd);
    }
    let verb = rest[0].as_str();
    let vargs: Vec<String> = rest[1..].to_vec();
    let op = format!("git {}", verb);
    let first = vargs.first().map(|s| s.as_str());
    let r = |v: Option<Verdict>| (v, cwd.clone());
    if inl(&["--version", "--help", "-h", "version", "help"], verb)
        || vargs.iter().any(|a| a == "--help")
        || (vargs.len() == 1 && vargs[0] == "-h")
    {
        return r(None);
    }
    if verb == "fetch" || verb == "pull" {
        let hijack = fetch_into_named_ref(&vargs, &config);
        if !hijack.is_empty() {
            return r(Some(v(
                "git-other",
                &format!("git {} {}", verb, hijack),
                None,
                "A fetch that names where it writes (a `src:dst` refspec, `--refmap`, or a \
`-c remote.*`/`url.*` override) can move origin/main, and agent-guard's hook \
runs the guard from origin/main. `git fetch`, `git fetch origin` and \
`git fetch origin main` are fine.",
            )));
        }
    }
    if inl(GIT_READ_ONLY, verb) {
        return r(None);
    }
    if verb == "add" || verb == "rm" || verb == "mv" {
        if verb == "add" {
            let st = ctx.state(&cwd);
            if st.in_progress() {
                let paths = positionals(&vargs, &["--chmod", "--pathspec-from-file"]);
                let bulk = has(
                    &vargs,
                    &[
                        "-A",
                        "--all",
                        "-u",
                        "--update",
                        "--pathspec-from-file",
                        "-p",
                        "--patch",
                        "-i",
                        "--interactive",
                    ],
                );
                if !paths.is_empty() && !bulk {
                    let absolute: Vec<String> =
                        paths.iter().map(|p| realpath(&join(&cwd, p))).collect();
                    let conflicted: Vec<String> = st.unmerged.iter().map(|p| realpath(p)).collect();
                    if absolute.iter().all(|p| conflicted.contains(p)) {
                        return r(None);
                    }
                }
                return r(Some(v(
                    "git-commit",
                    &op,
                    Some(T_COMMIT),
                    "While a merge, rebase or cherry-pick is in progress you may `git add` the conflicted files by name; that is all.",
                )));
            }
        }
        return r(vt("git-commit", &op, T_COMMIT));
    }
    if verb == "commit" {
        let st = ctx.state(&cwd);
        if st.merge {
            return r(Some(v(
                "git-commit",
                "git commit",
                Some(T_COMMIT),
                "A merge is in progress (MERGE_HEAD): //tools/git:commit concludes it once the conflicts are resolved and added.",
            )));
        }
        return r(vt("git-commit", &op, T_COMMIT));
    }
    if verb == "push" {
        return r(vt("git-push", &op, T_PUSH));
    }
    if verb == "pull" {
        if has(&vargs, &["--ff-only"])
            && !has(&vargs, &["--rebase", "-r", "--no-ff"])
            && ctx.state(&cwd).primary
        {
            return r(None);
        }
        return r(Some(v(
            "git-history",
            &op,
            Some(T_SYNC),
            "Only `git pull --ff-only` in the primary checkout is allowed directly.",
        )));
    }
    if verb == "rebase" {
        if has(&vargs, &["--show-current-patch"]) {
            return r(None);
        }
        if first.map_or(false, |f| inl(&["--continue", "--abort", "--skip"], f))
            && ctx.state(&cwd).rebase
        {
            return r(None);
        }
        return r(vt("git-history", &op, T_SYNC));
    }
    if verb == "merge" {
        if first.map_or(false, |f| f == "--continue" || f == "--abort") && ctx.state(&cwd).merge {
            return r(None);
        }
        return r(vt("git-history", &op, T_SYNC));
    }
    if verb == "cherry-pick" {
        if first.map_or(false, |f| f == "--continue" || f == "--abort")
            && ctx.state(&cwd).cherry_pick
        {
            return r(None);
        }
        return r(vn("git-history", &op));
    }
    if inl(
        &[
            "reset",
            "revert",
            "am",
            "bisect",
            "replace",
            "filter-branch",
            "filter-repo",
        ],
        verb,
    ) {
        return r(vn("git-history", &op));
    }
    if verb == "stash" {
        if first.map_or(false, |f| f == "list" || f == "show") {
            return r(None);
        }
        return r(Some(v(
            "git-stash",
            "git stash",
            None,
            "git stash is shared by every worktree, so it is banned outright: commit work in progress with \
`bazel run //tools/git:commit` on your branch, or work in a separate worktree.",
        )));
    }
    if verb == "tag" {
        let write = has(
            &vargs,
            &[
                "-d",
                "--delete",
                "-a",
                "--annotate",
                "-s",
                "--sign",
                "-m",
                "--message",
                "-F",
                "--file",
                "-f",
                "--force",
                "-u",
                "--local-user",
            ],
        );
        let listing = has(
            &vargs,
            &[
                "-l",
                "--list",
                "-n",
                "--contains",
                "--no-contains",
                "--points-at",
                "--merged",
                "--no-merged",
                "-v",
                "--verify",
            ],
        );
        let pos = positionals(
            &vargs,
            &[
                "--contains",
                "--no-contains",
                "--points-at",
                "--merged",
                "--no-merged",
                "--sort",
                "--format",
                "-n",
                "-m",
                "-F",
                "-u",
            ],
        );
        if !write && (listing || pos.is_empty()) {
            return r(None);
        }
        return r(Some(v(
            "git-history",
            "git tag",
            None,
            "Releases are tagged by release-please, not by hand.",
        )));
    }
    if verb == "branch" {
        let write_long = has(
            &vargs,
            &[
                "--delete",
                "--move",
                "--copy",
                "--force",
                "--set-upstream-to",
                "--unset-upstream",
                "--edit-description",
                "--track",
                "--no-track",
                "--create-reflog",
                "--recurse-submodules",
            ],
        );
        let write_short = short_cluster_has(&vargs, "dDmMcCfut");
        if write_long || write_short {
            if has(&vargs, &["-d", "-D", "--delete"]) || short_cluster_has(&vargs, "dD") {
                return r(vt("git-branch", "git branch -d", T_WT_DELETE_BRANCH));
            }
            return r(vt("git-branch", &op, T_WT_NEW));
        }
        let listing = has(
            &vargs,
            &[
                "-l",
                "--list",
                "-a",
                "--all",
                "-r",
                "--remotes",
                "--show-current",
            ],
        ) || short_cluster_has(&vargs, "lar");
        let pos = positionals(
            &vargs,
            &[
                "--contains",
                "--no-contains",
                "--merged",
                "--no-merged",
                "--points-at",
                "--sort",
                "--format",
                "--abbrev",
                "--color",
            ],
        );
        if !pos.is_empty() && !listing {
            return r(vt("git-branch", "git branch <name>", T_WT_NEW));
        }
        return r(None);
    }
    if verb == "checkout" {
        let no_p: Vec<String> = vargs.iter().filter(|a| *a != "-p").cloned().collect();
        if has(&vargs, &["-b", "-B", "--orphan"]) || short_cluster_has(&no_p, "bB") {
            return r(vt("git-branch", "git checkout -b", T_WT_NEW));
        }
        if has(&vargs, &["--detach"]) {
            return r(vt("git-branch", "git checkout --detach", T_WT_DETACH));
        }
        if vargs.iter().any(|a| a == "--")
            || has(&vargs, &["-p", "--patch", "--pathspec-from-file"])
        {
            return r(None);
        }
        let pos = positionals(&vargs, &["--conflict"]);
        if pos.is_empty() {
            return r(None);
        }
        for p in &pos {
            if lexists(&join(&cwd, p)) {
                return r(None); // restoring a file
            }
        }
        return r(Some(v(
            "git-branch",
            "git checkout <branch>",
            Some(T_WT_NEW),
            "Switching branches in a shared checkout breaks other sessions; each branch gets its own worktree. \
To restore files, use `git checkout -- <path>` or `git restore <path>`.",
        )));
    }
    if verb == "switch" {
        return r(Some(v(
            "git-branch",
            "git switch",
            Some(T_WT_NEW),
            "Switching branches in a shared checkout breaks other sessions; each branch gets its own worktree.",
        )));
    }
    if verb == "worktree" {
        let sub = first.unwrap_or("");
        if sub == "list" || sub.is_empty() {
            return r(None);
        }
        if sub == "add" {
            if has(&vargs, &["--detach", "-d"]) {
                return r(vt("git-worktree", "git worktree add --detach", T_WT_DETACH));
            }
            return r(vt("git-worktree", "git worktree add", T_WT_NEW));
        }
        if sub == "remove" {
            return r(vt("git-worktree", "git worktree remove", T_WT_REMOVE));
        }
        if sub == "prune" {
            return r(vt("git-worktree", "git worktree prune", T_WT_PRUNE));
        }
        if sub == "lock" || sub == "unlock" {
            return r(vt(
                "git-worktree",
                &format!("git worktree {}", sub),
                T_WT_LOCK,
            ));
        }
        return r(vn("git-worktree", &format!("git worktree {}", sub)));
    }
    if verb == "config" {
        let sub = first.unwrap_or("");
        if sub == "get" || sub == "list" {
            return r(None);
        }
        if has(
            &vargs,
            &[
                "--get",
                "--get-all",
                "--get-regexp",
                "--get-urlmatch",
                "-l",
                "--list",
                "--get-color",
                "--get-colorbool",
            ],
        ) {
            return r(None);
        }
        let write = has(
            &vargs,
            &[
                "--unset",
                "--unset-all",
                "--add",
                "--replace-all",
                "--edit",
                "-e",
                "--rename-section",
                "--remove-section",
            ],
        ) || inl(
            &["set", "unset", "edit", "rename-section", "remove-section"],
            sub,
        );
        let pos = positionals(
            &vargs,
            &["--file", "-f", "--blob", "--type", "--default", "--comment"],
        );
        if !write && pos.len() == 1 {
            return r(None);
        }
        return r(vn("git-other", "git config (write)"));
    }
    if verb == "remote" {
        let sub = first.unwrap_or("");
        if inl(&["", "-v", "--verbose", "show", "get-url"], sub) {
            return r(None);
        }
        return r(vn("git-other", &format!("git remote {}", sub)));
    }
    if verb == "apply" {
        // Applying a patch to the working tree is like editing files: allowed.
        // Applying it to the index is staging, which //tools/git:commit owns.
        if has(&vargs, &["--index", "--cached", "-3", "--3way"]) {
            return r(vt("git-commit", "git apply --index", T_COMMIT));
        }
        return r(None);
    }
    if verb == "clean" {
        if (has(&vargs, &["-n", "--dry-run"]) || short_cluster_has(&vargs, "n"))
            && !has(&vargs, &["-i", "--interactive"])
        {
            return r(None);
        }
        return r(Some(v(
            "git-other",
            "git clean",
            None,
            "`git clean -n` (dry run) is allowed.",
        )));
    }
    if verb == "reflog" {
        let sub = first.unwrap_or("");
        if inl(&["", "show", "exists", "list"], sub) || sub.starts_with('-') {
            return r(None);
        }
        return r(vn("git-other", &format!("git reflog {}", sub)));
    }
    if verb == "notes" {
        if first.map_or(true, |f| f == "list" || f == "show") {
            return r(None);
        }
        return r(vn("git-other", "git notes"));
    }
    if verb == "submodule" {
        if first.map_or(true, |f| f == "status" || f == "summary") {
            return r(None);
        }
        return r(vn("git-other", &format!("git submodule {}", vargs[0])));
    }
    if verb == "lfs" {
        if first.map_or(true, |f| inl(&["ls-files", "status", "env", "version"], f)) {
            return r(None);
        }
        return r(vn("git-other", &format!("git lfs {}", vargs[0])));
    }
    if verb == "sparse-checkout" {
        if first == Some("list") {
            return r(None);
        }
        return r(vn("git-other", "git sparse-checkout"));
    }
    if verb == "symbolic-ref" {
        if positionals(&vargs, &[]).len() <= 1 && !has(&vargs, &["-d", "--delete"]) {
            return r(None);
        }
        return r(vn("git-other", "git symbolic-ref (write)"));
    }
    if verb == "hash-object" && !has(&vargs, &["-w"]) {
        return r(None);
    }
    r(vn("git-other", &op))
}

const GH_READ_SUBS: &[&str] = &[
    "view",
    "list",
    "status",
    "diff",
    "checks",
    "get",
    "check",
    "verify",
    "item-list",
    "field-list",
    "token",
    "watch",
    "download",
    "search",
];

fn gh_strip(args: &[String]) -> (Vec<String>, Option<String>) {
    let mut out = Vec::new();
    let mut repo = None;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if (a == "-R" || a == "--repo") && i + 1 < args.len() {
            repo = Some(args[i + 1].clone());
            i += 2;
            continue;
        }
        if let Some(r) = a.strip_prefix("--repo=") {
            repo = Some(r.to_string());
            i += 1;
            continue;
        }
        if a.starts_with("-R") && a.chars().count() > 2 {
            repo = Some(a[2..].to_string());
            i += 1;
            continue;
        }
        out.push(a.clone());
        i += 1;
    }
    (out, repo)
}

/// `_GH_URL_RE.search(s)`: `(?i)github\.com[/:]([^/\s]+)/([^/\s#?]+)` -> (owner, name).
pub fn gh_url(s: &str) -> Option<(String, String)> {
    let t = chars(s);
    let mut p = 0;
    while p < t.len() {
        if crate::pyutil::ci_starts_at(&t, p, "github")
            && starts_at(&t, p + 6, ".")
            && crate::pyutil::ci_starts_at(&t, p + 7, "com")
        {
            let mut i = p + 10;
            if i < t.len() && (t[i] == '/' || t[i] == ':') {
                i += 1;
                let g1 = i;
                while i < t.len() && t[i] != '/' && !is_space(t[i]) {
                    i += 1;
                }
                if i > g1 && i < t.len() && t[i] == '/' {
                    let owner_end = i;
                    i += 1;
                    let g2 = i;
                    while i < t.len()
                        && !(t[i] == '/' || is_space(t[i]) || t[i] == '#' || t[i] == '?')
                    {
                        i += 1;
                    }
                    if i > g2 {
                        return Some((
                            t[g1..owner_end].iter().collect(),
                            t[g2..i].iter().collect(),
                        ));
                    }
                }
            }
        }
        p += 1;
    }
    None
}

/// `_GH_API_REPO_RE.match(s)`: `^/?repos/([^/\s]+)/([^/\s?]+)`.
fn gh_api_repo(s: &str) -> Option<(String, String)> {
    let t = chars(s);
    let mut i = 0;
    if t.first() == Some(&'/') {
        i = 1;
    }
    if !starts_at(&t, i, "repos/") {
        return None;
    }
    i += 6;
    let g1 = i;
    while i < t.len() && t[i] != '/' && !is_space(t[i]) {
        i += 1;
    }
    if i == g1 || i >= t.len() || t[i] != '/' {
        return None;
    }
    let e1 = i;
    i += 1;
    let g2 = i;
    while i < t.len() && t[i] != '/' && t[i] != '?' && !is_space(t[i]) {
        i += 1;
    }
    if i == g2 {
        return None;
    }
    Some((t[g1..e1].iter().collect(), t[g2..i].iter().collect()))
}

/// The owner/name a gh command explicitly targets, or None if it names none.
pub fn gh_target_repo(args: &[String]) -> Option<String> {
    let (rest, repo) = gh_strip(args);
    let drop_git = |n: String| n.strip_suffix(".git").map(|s| s.to_string()).unwrap_or(n);
    if let Some(repo) = repo.filter(|r| !r.is_empty()) {
        if let Some((o, n)) = gh_url(&repo) {
            return Some(format!("{}/{}", o, drop_git(n)));
        }
        let parts: Vec<&str> = repo.split('/').filter(|p| !p.is_empty()).collect();
        if parts.len() >= 2 {
            return Some(format!(
                "{}/{}",
                parts[parts.len() - 2],
                parts[parts.len() - 1]
            ));
        }
        return Some(repo);
    }
    for a in &rest {
        if let Some((o, n)) = gh_url(a) {
            return Some(format!("{}/{}", o, drop_git(n)));
        }
    }
    if rest.first().map(|s| s.as_str()) == Some("api") {
        for a in &rest[1..] {
            if let Some((owner, name)) = gh_api_repo(a) {
                if owner.starts_with('{')
                    || owner.starts_with(':')
                    || name.starts_with('{')
                    || name.starts_with(':')
                {
                    return None; // {owner}/{repo}: the current directory's repo
                }
                return Some(format!("{}/{}", owner, name));
            }
        }
    }
    None
}

pub fn is_vitruvian_core_slug(slug: &str) -> bool {
    py_lower(slug) == "vitruviansoftware/vitruvian-core"
}

/// `_MUTATION_RE.search(q)`: `(^|[\s{}])mutation(\s|\(|\{|$)`.
fn has_mutation(q: &str) -> bool {
    let t = chars(q);
    let mut from = 0;
    while let Some(at) = crate::pyutil::find_str(&t, "mutation", from) {
        from = at + 1;
        let before_ok = at == 0 || is_space(t[at - 1]) || t[at - 1] == '{' || t[at - 1] == '}';
        let e = at + 8;
        let after_ok =
            e == t.len() || is_space(t[e]) || t[e] == '(' || t[e] == '{' || dollar(&t, e);
        if before_ok && after_ok {
            return true;
        }
    }
    false
}

/// The query text of `gh api graphql`, None if it cannot be read.
fn graphql_query_text(args: &[String], cwd: &str) -> Option<String> {
    let mut texts = Vec::new();
    let mut found = false;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        let mut val: Option<String> = None;
        if inl(&["-f", "-F", "--field", "--raw-field"], a) && i + 1 < args.len() {
            val = Some(args[i + 1].clone());
            i += 2;
        } else if a.starts_with("--field=") || a.starts_with("--raw-field=") {
            val = split1(a, '=').1.map(|s| s.to_string());
            i += 1;
        } else if a.starts_with("-f") || a.starts_with("-F") {
            val = if a.chars().count() > 2 {
                Some(a[2..].to_string())
            } else {
                None
            };
            i += 1;
        } else if a == "--input" {
            return None;
        } else {
            i += 1;
        }
        if let Some(v) = val.filter(|v| !v.is_empty()) {
            if let Some(q) = v.strip_prefix("query=") {
                found = true;
                let mut q = q.to_string();
                if let Some(src) = q.strip_prefix('@') {
                    if src == "-" {
                        return None;
                    }
                    let path = join(cwd, src);
                    nul_check(&path);
                    q = read_text_replace(&path)?;
                }
                texts.push(q);
            }
        }
    }
    if !found {
        return Some(String::new());
    }
    Some(texts.join("\n"))
}

fn classify_gh_api(args: &[String], cwd: &str) -> Option<Verdict> {
    let mut method: Option<String> = None;
    let mut fields = false;
    let mut has_input = false;
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if (a == "-X" || a == "--method") && i + 1 < args.len() {
            method = Some(py_upper(&args[i + 1]));
            i += 2;
            continue;
        }
        let ac = chars(a);
        if a.starts_with("--method=") {
            method = Some(py_upper(split1(a, '=').1.unwrap_or("")));
        } else if a.starts_with("-X") && ac.len() > 2 {
            method = Some(py_upper(&a[2..]));
        } else if inl(&["-f", "-F", "--field", "--raw-field"], a)
            || a.starts_with("--field=")
            || a.starts_with("--raw-field=")
            || (ac.len() >= 3 && ac[0] == '-' && (ac[1] == 'f' || ac[1] == 'F') && ac[2] != '\n')
        {
            fields = true;
        } else if a == "--input" || a.starts_with("--input=") {
            has_input = true;
        }
        i += 1;
    }
    let pos = positionals(
        args,
        &[
            "-X",
            "--method",
            "-f",
            "-F",
            "--field",
            "--raw-field",
            "-H",
            "--header",
            "--input",
            "-q",
            "--jq",
            "-t",
            "--template",
            "--cache",
            "--hostname",
            "-p",
            "--preview",
        ],
    );
    let endpoint = pos.first().map(|s| s.as_str()).unwrap_or("");
    if endpoint == "graphql" {
        return match graphql_query_text(args, cwd) {
            None => Some(v(
                "gh-api",
                "gh api graphql",
                None,
                "agent-guard could not read the query (stdin or --input), so it cannot tell a read from a mutation; \
pass the query inline with -f query=... to run a read.",
            )),
            Some(q) if has_mutation(&q) => vn("gh-api", "gh api graphql mutation"),
            Some(_) => None,
        };
    }
    match method.as_deref() {
        None => {
            // gh switches to POST when fields or --input are given, unless -X GET.
            if fields || has_input {
                return vn("gh-api", "gh api (POST)");
            }
            None
        }
        Some("GET") | Some("HEAD") => None,
        Some(m) => vn("gh-api", &format!("gh api -X {}", m)),
    }
}

pub fn classify_gh(inv: &Invocation) -> Option<Verdict> {
    let (args, _repo) = gh_strip(&inv.argv[1..]);
    if args.is_empty()
        || inl(&["--version", "version", "help", "--help", "-h"], &args[0])
        || args.iter().any(|a| a == "--help")
    {
        return None;
    }
    let group = args[0].as_str();
    let sub = args.get(1).map(|s| s.as_str()).unwrap_or("");
    if group == "api" {
        return classify_gh_api(&args[1..], &inv.cwd);
    }
    if group == "pr" {
        if inl(&["view", "list", "checks", "diff", "status", ""], sub) {
            return None;
        }
        if sub == "create" {
            return vt("gh-pr", "gh pr create", T_PR_CREATE);
        }
        if sub == "merge" {
            return Some(v(
                "gh-pr",
                "gh pr merge",
                Some(T_PR_ENQUEUE),
                "It arms auto-merge through the merge queue; never --admin.",
            ));
        }
        if inl(&["edit", "comment", "ready"], sub) {
            return Some(v(
                "gh-pr",
                &format!("gh pr {}", sub),
                None,
                &format!(
                    "`bazel run //tools/agent-app -- pr-{}` is planned but not built yet.",
                    sub
                ),
            ));
        }
        if sub == "checkout" {
            return vt("git-branch", "gh pr checkout", T_WT_NEW);
        }
        return vn("gh-pr", &format!("gh pr {}", sub));
    }
    if group == "issue" {
        // Issues are allowed (and logged): they are notes, not repo changes.
        if sub == "delete" || sub == "transfer" {
            return vn("gh-other", &format!("gh issue {}", sub));
        }
        return None;
    }
    if group == "run" {
        if inl(&["view", "list", "watch", "download", ""], sub) {
            return None;
        }
        if sub == "rerun" {
            return Some(v("gh-run", "gh run rerun", Some(T_RUN_RERUN), RUN_NOTE));
        }
        if sub == "cancel" {
            return Some(v("gh-run", "gh run cancel", Some(T_RUN_CANCEL), RUN_NOTE));
        }
        return Some(v(
            "gh-run",
            &format!("gh run {}", sub),
            None,
            RUN_NO_TARGET_NOTE,
        ));
    }
    if group == "workflow" {
        if inl(&["view", "list", ""], sub) {
            return None;
        }
        if sub == "run" {
            return Some(v(
                "gh-run",
                "gh workflow run",
                Some(T_WORKFLOW_RUN),
                &format!(
                    "It starts only workflows in tools/agent-app/workflow-allowlist.txt, in this repository. {}",
                    RUN_NOTE
                ),
            ));
        }
        return Some(v(
            "gh-run",
            &format!("gh workflow {}", sub),
            None,
            RUN_NO_TARGET_NOTE,
        ));
    }
    if inl(&["search", "browse", "status", "completion"], group) {
        return None;
    }
    if group == "auth" {
        if sub == "status" || sub == "token" {
            return None;
        }
        return vn("gh-other", &format!("gh auth {}", sub));
    }
    if group == "repo" && (sub == "view" || sub == "list") {
        return None;
    }
    if group == "release" && inl(&["view", "list", "download"], sub) {
        return None;
    }
    if (group == "config" || group == "variable") && (sub == "get" || sub == "list") {
        return None;
    }
    if inl(GH_READ_SUBS, sub) || sub.is_empty() {
        return None;
    }
    vn("gh-other", &format!("gh {} {}", group, sub))
}

fn first_sub(args: &[String], with_arg: &[&str]) -> String {
    positionals(args, with_arg)
        .into_iter()
        .next()
        .unwrap_or_default()
}

fn version_only(args: &[String]) -> bool {
    args.first().map_or(false, |a| {
        inl(
            &[
                "--version",
                "-version",
                "-V",
                "version",
                "--help",
                "-h",
                "help",
            ],
            a,
        )
    }) || (args.len() == 1 && args[0] == "-v")
}

const GO_READ: &[&str] = &["version", "env", "list", "doc", "help", "tool"];
const NODE_PROGS: &[&str] = &[
    "npm", "pnpm", "npx", "yarn", "bun", "bunx", "corepack", "pnpx",
];
const NODE_READ: &[&str] = &[
    "view", "info", "show", "v", "ls", "list", "la", "ll", "why", "outdated", "help", "config",
    "get", "root", "bin", "prefix", "search", "explain", "audit", "docs", "repo", "bugs",
    "licenses", "store", "whoami", "ping", "doctor", "query", "pkg",
];
const LINTERS: &[&str] = &[
    "gofmt",
    "goimports",
    "golangci-lint",
    "ruff",
    "black",
    "isort",
    "flake8",
    "pylint",
    "mypy",
    "eslint",
    "prettier",
    "biome",
    "oxlint",
    "stylelint",
    "markdownlint",
    "markdownlint-cli2",
    "yamllint",
    "swiftformat",
    "swift-format",
    "swiftlint",
    "ktlint",
    "ktfmt",
    "shfmt",
    "buildifier",
    "buildozer",
    "clang-format",
    "rustfmt",
    "taplo",
    "shellcheck",
];
const FORMATTERS: &[&str] = &[
    "gofmt",
    "goimports",
    "black",
    "isort",
    "prettier",
    "swiftformat",
    "swift-format",
    "ktfmt",
    "shfmt",
    "buildifier",
    "clang-format",
    "rustfmt",
    "taplo",
];
const KUBECTL_READ: &[&str] = &[
    "get",
    "describe",
    "logs",
    "log",
    "top",
    "explain",
    "api-resources",
    "api-versions",
    "version",
    "auth",
    "events",
    "wait",
    "diff",
    "cluster-info",
    "kustomize",
    "port-forward",
    "completion",
    "plugin",
    "options",
    "help",
    "",
];
const HELM_READ: &[&str] = &[
    "template",
    "lint",
    "list",
    "ls",
    "status",
    "get",
    "history",
    "show",
    "inspect",
    "search",
    "version",
    "env",
    "repo",
    "dependency",
    "dep",
    "help",
    "verify",
    "completion",
    "",
];
const PULUMI_READ: &[&str] = &["version", "whoami", "about", "help", "logs", "plugin", ""];

/// Classify one invocation. Returns (verdict, the directory that sets its scope).
pub fn classify_tool(inv: &Invocation, ctx: &Context) -> (Option<Verdict>, String) {
    let prog = inv.prog();
    let args: &[String] = &inv.argv[1..];
    let cwd = inv.cwd.clone();
    let here = |v: Option<Verdict>| (v, cwd.clone());

    if prog == "git" {
        return classify_git(inv, ctx);
    }
    if prog == "gh" {
        return here(classify_gh(inv));
    }
    if inl(&["bazel", "bazelisk", "aspect", "ibazel"], prog) {
        return here(classify_bazel(args, &cwd, &ctx.home));
    }

    if prog == "go" {
        let sub = args.first().map(|s| s.as_str()).unwrap_or("");
        if version_only(args) || inl(GO_READ, sub) {
            return here(None);
        }
        if sub == "mod" && args.len() > 1 && inl(&["why", "graph", "verify", "help"], &args[1]) {
            return here(None);
        }
        if sub == "test" || sub == "vet" {
            return here(vt("go", &format!("go {}", sub), T_BAZEL_TEST));
        }
        if inl(&["build", "run", "install"], sub) {
            return here(vt("go", &format!("go {}", sub), T_BAZEL_BUILD));
        }
        if sub == "fmt" {
            return here(vt("go", "go fmt", T_FORMAT));
        }
        if inl(&["mod", "get", "work"], sub) {
            let first_two: Vec<String> = args.iter().take(2).cloned().collect();
            return here(vt(
                "go",
                &format!("go {}", first_two.join(" ")),
                t(
                    "bazel run //tools/gomod:tidy (and bazel run //:gazelle for BUILD files)",
                    None,
                ),
            ));
        }
        return here(vn("go", &format!("go {}", sub)));
    }

    if prog == "swift" || prog == "swiftc" {
        let sub = args.first().map(|s| s.as_str()).unwrap_or("");
        if version_only(args) {
            return here(None);
        }
        if prog == "swift"
            && sub == "package"
            && args.len() > 1
            && inl(
                &["describe", "dump-package", "show-dependencies", "--help"],
                &args[1],
            )
        {
            return here(None);
        }
        if sub == "test" {
            return here(vt(
                "swift",
                "swift test",
                t("bazel test //apps/desktop/<app>:<Tests> (macOS-only targets are tagged manual)", None),
            ));
        }
        let ps = format!("{} {}", prog, sub);
        let ps = py_strip(&ps);
        if inl(&["build", "run", "package"], sub) || prog == "swiftc" {
            return here(vt("swift", ps, T_BAZEL_BUILD));
        }
        if sub == "format" || sub == "lint" {
            return here(vt("lint", &format!("swift {}", sub), T_FORMAT));
        }
        return here(vn("swift", ps));
    }

    if prog == "xcodebuild" {
        if args.iter().any(|a| {
            inl(
                &[
                    "-version",
                    "-showsdks",
                    "-list",
                    "-help",
                    "-usage",
                    "-showBuildSettings",
                    "-showdestinations",
                ],
                a,
            )
        }) {
            return here(None);
        }
        return here(vt(
            "xcode",
            "xcodebuild",
            t(
                "bazel build / bazel test the app's targets (--config=macos-app for .app bundles)",
                None,
            ),
        ));
    }
    if prog == "xcrun" {
        let tool_args = skip_opts(args, &["--sdk", "-sdk", "--toolchain", "-toolchain"]);
        let tool = tool_args.first().map(|s| s.as_str()).unwrap_or("");
        if inl(&["notarytool", "stapler", "altool"], tool) {
            return here(vt(
                "xcode",
                &format!("xcrun {}", tool),
                t(
                    "bazel run //tools/desktop-package (packaging and notarization targets)",
                    None,
                ),
            ));
        }
        if inl(&["xcodebuild", "swift", "swiftc"], tool) {
            let mut argv = vec![tool.to_string()];
            argv.extend_from_slice(&tool_args[1..]);
            let sub = Invocation::new(argv, &cwd, inv.redirects.clone());
            return classify_tool(&sub, ctx);
        }
        return here(None);
    }

    if inl(NODE_PROGS, prog) {
        let sub = first_sub(
            args,
            &[
                "--prefix",
                "-C",
                "--dir",
                "--filter",
                "-F",
                "--workspace",
                "-w",
                "--cwd",
            ],
        );
        let sub = sub.as_str();
        let runner = inl(&["npx", "bunx", "pnpx"], prog);
        if version_only(args) || (!runner && inl(NODE_READ, sub)) {
            return here(None);
        }
        if runner || inl(&["exec", "dlx", "x", "create"], sub) {
            let op = if runner {
                prog.to_string()
            } else {
                format!("{} {}", prog, sub)
            };
            return here(vt(
                "node",
                &op,
                t("a Bazel target (bazel run //<package>:<binary>); tools on PATH come from bazel run //tools:bazel_env", None),
            ));
        }
        if inl(
            &[
                "test",
                "t",
                "tst",
                "run",
                "run-script",
                "rum",
                "urn",
                "start",
                "build",
                "lint",
                "typecheck",
                "dev",
            ],
            sub,
        ) || ((prog == "yarn" || prog == "bun")
            && !inl(NODE_READ, sub)
            && !inl(&["install", "add", "remove", "upgrade", "up", "i"], sub))
        {
            return here(vt(
                "node",
                &format!("{} {}", prog, sub),
                t(
                    "bazel test //<package>:<test> or bazel run //<package>:<binary>",
                    None,
                ),
            ));
        }
        if inl(
            &[
                "install",
                "i",
                "ci",
                "add",
                "remove",
                "rm",
                "uninstall",
                "un",
                "update",
                "up",
                "upgrade",
                "dedupe",
                "prune",
                "rebuild",
                "link",
                "unlink",
                "import",
                "patch",
                "patch-commit",
                "install-test",
                "it",
                "",
            ],
            sub,
        ) {
            return here(Some(v(
                "node",
                &format!("{} {}", prog, if sub.is_empty() { "install" } else { sub }),
                None,
                "Bazel (rules_js) installs node_modules itself when you bazel build or bazel test.",
            )));
        }
        if inl(
            &[
                "publish",
                "pack",
                "version",
                "deprecate",
                "dist-tag",
                "unpublish",
                "owner",
                "access",
                "token",
                "login",
                "logout",
                "adduser",
            ],
            sub,
        ) {
            return here(Some(v(
                "node",
                &format!("{} {}", prog, sub),
                None,
                "Packages are published by the release pipeline.",
            )));
        }
        return here(vn("node", &format!("{} {}", prog, sub)));
    }

    if prog == "cargo" {
        let sub = first_sub(
            args,
            &["--manifest-path", "-p", "--package", "-Z", "--config", "-C"],
        );
        let sub = sub.as_str();
        if version_only(args)
            || inl(
                &[
                    "metadata",
                    "tree",
                    "search",
                    "help",
                    "locate-project",
                    "pkgid",
                    "read-manifest",
                    "verify-project",
                ],
                sub,
            )
        {
            return here(None);
        }
        if inl(&["test", "t", "bench", "check", "c", "clippy"], sub) {
            return here(vt("cargo", &format!("cargo {}", sub), T_BAZEL_TEST));
        }
        if inl(&["build", "b", "run", "r", "install", "doc", "d"], sub) {
            return here(vt("cargo", &format!("cargo {}", sub), T_BAZEL_BUILD));
        }
        if sub == "fmt" {
            return here(vt("lint", "cargo fmt", T_FORMAT));
        }
        if sub == "publish" {
            return here(Some(v(
                "cargo",
                "cargo publish",
                None,
                "Crates are published by release-please and the release pipeline.",
            )));
        }
        return here(vn("cargo", &format!("cargo {}", sub)));
    }

    if prog == "gradle" || prog == "gradlew" {
        if version_only(args) {
            return here(None);
        }
        return here(vt(
            "gradle",
            prog,
            t(
                "bazel build //apps/mobile/<app>:app (Android is built with Bazel)",
                None,
            ),
        ));
    }

    if prog == "pytest" || prog == "py.test" {
        if version_only(args) {
            return here(None);
        }
        return here(vt("pytest", "pytest", T_BAZEL_TEST));
    }
    if inl(LINTERS, prog) {
        if version_only(args) {
            return here(None);
        }
        if inl(FORMATTERS, prog) {
            return here(vt("lint", prog, T_FORMAT));
        }
        return here(vt("lint", prog, T_LINT));
    }
    if prog == "actionlint" {
        if version_only(args) {
            return here(None);
        }
        return here(vt("actionlint", "actionlint", T_ACTIONLINT));
    }
    if prog == "gitleaks" {
        if version_only(args) {
            return here(None);
        }
        return here(vt("secret-scan", "gitleaks", T_SECRET_SCAN));
    }

    if prog == "pulumi" {
        let with = ["-C", "--cwd", "-s", "--stack"];
        let sub = first_sub(args, &with);
        let sub = sub.as_str();
        if version_only(args) || inl(PULUMI_READ, sub) {
            return here(None);
        }
        let pos = positionals(args, &with);
        if sub == "stack"
            && (pos.len() < 2
                || inl(
                    &["ls", "output", "history", "export", "graph", "tag"],
                    &pos[1],
                ))
            && (pos.len() < 3 || pos[1] != "tag" || pos[2] == "ls" || pos[2] == "get")
        {
            return here(None);
        }
        if sub == "config" && (pos.len() < 2 || pos[1] == "get") {
            return here(None);
        }
        return here(Some(v(
            "iac",
            &format!("pulumi {}", sub),
            Some(T_PULUMI),
            "Pulumi runs only through the wrappers, which inject the right identity.",
        )));
    }
    if prog == "terraform" || prog == "tofu" {
        let sub = first_sub(args, &["-chdir"]);
        let sub = sub.as_str();
        if version_only(args)
            || inl(
                &[
                    "version",
                    "show",
                    "output",
                    "validate",
                    "fmt",
                    "providers",
                    "graph",
                    "help",
                    "",
                ],
                sub,
            )
        {
            return here(None);
        }
        if sub == "plan" || sub == "init" {
            return here(None);
        }
        return here(vn("iac", &format!("{} {}", prog, sub)));
    }

    if inl(&["kubectl", "kubecolor", "oc"], prog) {
        let sub = first_sub(
            args,
            &[
                "-n",
                "--namespace",
                "--context",
                "--kubeconfig",
                "-l",
                "--selector",
                "-o",
                "--output",
                "-c",
                "--container",
                "--cluster",
                "--user",
                "-f",
                "--filename",
            ],
        );
        let sub = sub.as_str();
        if inl(KUBECTL_READ, sub) || version_only(args) {
            return here(None);
        }
        if sub == "rollout" {
            let pos = positionals(args, &["-n", "--namespace", "--context", "--kubeconfig"]);
            if pos.len() > 1 && (pos[1] == "status" || pos[1] == "history") {
                return here(None);
            }
        }
        if sub == "config" {
            let pos = positionals(args, &["--kubeconfig"]);
            if pos.len() < 2
                || inl(
                    &[
                        "view",
                        "get-contexts",
                        "current-context",
                        "get-clusters",
                        "get-users",
                        "use-context",
                        "use",
                    ],
                    &pos[1],
                )
            {
                return here(None);
            }
        }
        if inl(&["apply", "delete", "patch", "replace", "create"], sub) {
            return here(vt("kubectl", &format!("kubectl {}", sub), T_GITOPS));
        }
        return here(Some(v(
            "kubectl",
            &format!("kubectl {}", sub),
            None,
            &format!(
                "The cluster is changed through git (GitOps); there is no target for `kubectl {}`.",
                sub
            ),
        )));
    }
    if prog == "helm" {
        let sub = first_sub(
            args,
            &["-n", "--namespace", "--kube-context", "--kubeconfig"],
        );
        let sub = sub.as_str();
        if version_only(args) || inl(HELM_READ, sub) {
            if inl(&["repo", "dependency", "dep"], sub) {
                let pos = positionals(args, &["-n", "--namespace"]);
                if pos.len() > 1 && inl(&["update", "build", "add", "remove", "rm"], &pos[1]) {
                    return here(vt("helm", &format!("helm {} {}", sub, pos[1]), T_HELM));
                }
            }
            return here(None);
        }
        return here(vt("helm", &format!("helm {}", sub), T_HELM));
    }

    if prog == "rm" {
        return classify_rm(inv, ctx);
    }
    if prog == "find" && args.iter().any(|a| a == "-delete") {
        if let Some(r) = args.iter().find(|a| !a.starts_with('-')) {
            let p = expand_path(r, &cwd, &ctx.home);
            if is_bazel_cache_path(&p) {
                return (
                    Some(v(
                        "bazel-cache",
                        "find -delete on a Bazel cache",
                        Some(T_CACHE_GC),
                        "",
                    )),
                    p,
                );
            }
        }
    }
    here(None)
}

pub fn classify_bazel(args: &[String], cwd: &str, home: &str) -> Option<Verdict> {
    for a in args {
        if a.starts_with("--output_user_root") || a.starts_with("--output_base") {
            return Some(v(
                "bazel-cache",
                "bazel --output_user_root/--output_base",
                Some(t(
                    "bazel run //tools/worktree -- <branch> (it pins a per-worktree output root in user.bazelrc)",
                    None,
                )),
                "A one-off output root leaves an orphaned 5-10 GB cache behind.",
            ));
        }
    }
    let cmd = first_sub(args, &[]);
    if cmd == "clean"
        && args
            .iter()
            .any(|a| a == "--expunge" || a == "--expunge_async")
    {
        return vt("bazel-cache", "bazel clean --expunge", T_CACHE_GC);
    }
    if cmd == "run" {
        return classify_installer_run(args, cwd, home);
    }
    None
}

const AGENT_INSTALL_FLAGS: &[&str] = &["--check", "--dry-run", "--help", "-h"];

fn is_install_label(word: &str, cwd: &str) -> bool {
    // _INSTALL_LABEL_RE: (^|/)tools/agent-guard:install(_rs)?$
    let core = word.strip_suffix('\n').unwrap_or(word);
    for label in ["tools/agent-guard:install", "tools/agent-guard:install_rs"] {
        if let Some(head) = core.strip_suffix(label) {
            if head.is_empty() || head.ends_with('/') {
                return true;
            }
        }
    }
    // A label relative to the package, run from tools/agent-guard itself:
    // re.search(r"/tools/agent-guard/?$", cwd).
    [":install", "install", ":install_rs", "install_rs"].contains(&word) && {
        let c = cwd.strip_suffix('\n').unwrap_or(cwd);
        let c = c.strip_suffix('/').unwrap_or(c);
        c.ends_with("/tools/agent-guard")
    }
}

/// Only --check/--dry-run/--help, plus --uninstall alongside --dry-run.
pub fn installer_args_ok(args: &[String]) -> bool {
    if args
        .iter()
        .any(|a| !inl(AGENT_INSTALL_FLAGS, a) && a != "--uninstall")
    {
        return false;
    }
    !args.iter().any(|a| a == "--uninstall") || args.iter().any(|a| a == "--dry-run")
}

const INSTALLER_SOURCES: &[&str] = &[
    "tools/agent-guard/install.py",
    "tools/agent-guard/agent_guard.py",
    "tools/agent-guard/BUILD",
];
/// The Rust installer (:install_rs) is built from every file in these
/// folders, by glob: each file on origin/main and each file in the checkout
/// must match, so an added file counts as an edit too.
const INSTALLER_SOURCE_DIRS: &[&str] = &["tools/agent-guard/src", "tools/agent-guard/install"];

fn walk_files(root: &str, rel: &str, out: &mut Vec<String>) {
    let Ok(entries) = std::fs::read_dir(join(root, rel)) else {
        return;
    };
    for e in entries.flatten() {
        let name = e.file_name().to_string_lossy().into_owned();
        let child = format!("{}/{}", rel, name);
        // os.walk: symlinks to folders are listed, not followed.
        match e.file_type() {
            Ok(ft) if ft.is_dir() => walk_files(root, &child, out),
            Ok(_) => out.push(child),
            Err(_) => {}
        }
    }
}

/// INSTALLER_SOURCES plus every file under INSTALLER_SOURCE_DIRS on
/// origin/main or in root's checkout, sorted; None if git cannot list main's.
pub fn installer_sources(root: &str) -> Option<Vec<String>> {
    nul_check(root);
    let mut cmd = git_env_cmd();
    cmd.arg("-C")
        .arg(root)
        .args(["ls-tree", "-r", "-z", "--name-only", "origin/main", "--"])
        .args(INSTALLER_SOURCE_DIRS);
    let (ok, out) = run_with_timeout(cmd, None, Duration::from_secs(5))?;
    if !ok {
        return None;
    }
    let mut found: Vec<String> = out
        .split(|b| *b == 0)
        .filter(|p| !p.is_empty())
        .map(|p| String::from_utf8_lossy(p).into_owned())
        .collect();
    for d in INSTALLER_SOURCE_DIRS {
        walk_files(root, d, &mut found);
    }
    found.retain(|f| !INSTALLER_SOURCES.contains(&f.as_str()));
    found.sort();
    found.dedup();
    let mut all: Vec<String> = INSTALLER_SOURCES.iter().map(|s| s.to_string()).collect();
    all.extend(found);
    Some(all)
}

fn git_env_cmd() -> Command {
    let mut cmd = Command::new("git");
    for (k, _) in std::env::vars_os() {
        let ks = k.to_string_lossy();
        if ks.starts_with("GIT_") && ks != "GIT_CONFIG_NOSYSTEM" && ks != "GIT_CONFIG_GLOBAL" {
            cmd.env_remove(&k);
        }
    }
    cmd
}

/// {rel: origin/main's bytes, or None if main has no such file}, or None if git cannot say.
fn origin_main_files(root: &str, rels: &[String]) -> Option<Vec<Option<Vec<u8>>>> {
    nul_check(root);
    let mut request = String::new();
    for r in rels {
        request.push_str("origin/main:");
        request.push_str(r);
        request.push('\n');
    }
    let mut cmd = git_env_cmd();
    cmd.arg("-C").arg(root).arg("cat-file").arg("--batch");
    let (ok, out) = run_with_timeout(cmd, Some(request.as_bytes()), Duration::from_secs(5))?;
    if !ok {
        return None;
    }
    let mut pos = 0;
    let mut found = Vec::new();
    for _ in rels {
        let nl = out[pos.min(out.len())..].iter().position(|&b| b == b'\n')? + pos;
        let header: Vec<&[u8]> = out[pos..nl]
            .split(|b| b.is_ascii_whitespace() || *b == 0x0b)
            .filter(|p| !p.is_empty())
            .collect();
        pos = nl + 1;
        if header.len() == 3 && header[1] == b"blob" {
            let size: usize = std::str::from_utf8(header[2]).ok()?.trim().parse().ok()?;
            let end = (pos + size).min(out.len());
            found.push(Some(out[pos.min(out.len())..end].to_vec()));
            pos += size + 1;
        } else if header.last() == Some(&&b"missing"[..]) {
            found.push(None);
        } else {
            return None;
        }
    }
    Some(found)
}

/// `_RC_IMPORT.match(line)`: `^\s*(try-)?import\s+(\S+)` -> group 2.
fn rc_import(line: &str) -> Option<String> {
    let t = chars(line);
    let mut i = 0;
    while i < t.len() && is_space(t[i]) {
        i += 1;
    }
    if starts_at(&t, i, "try-") {
        i += 4;
    }
    if !starts_at(&t, i, "import") {
        return None;
    }
    i += 6;
    let ws = i;
    while i < t.len() && is_space(t[i]) {
        i += 1;
    }
    if i == ws {
        return None;
    }
    let g = i;
    while i < t.len() && !is_space(t[i]) {
        i += 1;
    }
    if i == g {
        return None;
    }
    Some(t[g..i].iter().collect())
}

/// Every bazelrc a `bazel run` in root reads: system, workspace (and its imports), user.
fn bazelrc_files(root: &str, home: &str) -> Vec<String> {
    fn visit(path: &str, depth: usize, root: &str, out: &mut Vec<String>) {
        let path = normpath(path);
        if depth > 8 || out.contains(&path) || !isfile(&path) {
            return;
        }
        out.push(path.clone());
        let Some(text) = read_text_replace(&path) else {
            return;
        };
        for line in py_splitlines(&text) {
            if let Some(target) = rc_import(&line) {
                let target = target.replace("%workspace%", root);
                let next = if isabs(&target) {
                    target
                } else {
                    join(root, &target)
                };
                visit(&next, depth + 1, root, out);
            }
        }
    }
    let mut out = Vec::new();
    visit("/etc/bazel.bazelrc", 0, root, &mut out);
    visit(&join(root, ".bazelrc"), 0, root, &mut out);
    if !home.is_empty() {
        visit(&join(home, ".bazelrc"), 0, root, &mut out);
    }
    out
}

/// Why an agent may not run the installer from cwd's checkout ("" if it may).
pub fn installer_problem(cwd: &str, home: &str) -> String {
    if let Some(o) = INSTALLER_PROBLEM_OVERRIDE.with(|o| o.borrow().clone()) {
        return o;
    }
    let Some(root) = repo_root_of(cwd) else {
        return "it is not run from inside a vitruvian-core checkout".into();
    };
    let sources = installer_sources(&root);
    let main = sources.as_ref().and_then(|s| origin_main_files(&root, s));
    let (Some(sources), Some(main)) = (sources, main.filter(|m| m.iter().any(|v| v.is_some())))
    else {
        return format!(
            "origin/main or its installer cannot be read in {} (fetch first)",
            root
        );
    };
    for (rel, want) in sources.iter().zip(main.iter()) {
        let have = std::fs::read(join(&root, rel)).ok();
        if &have != want {
            return format!(
                "{} in {} differs from origin/main's, so an unreviewed installer would run; \
run it from a checkout that is up to date with main",
                rel, root
            );
        }
    }
    for rc in bazelrc_files(&root, home) {
        let Some(text) = read_text_replace(&rc) else {
            continue;
        };
        for line in text_lines(&text) {
            if !py_lstrip(&line).starts_with('#')
                && (line.contains("run_under") || line.contains("script_path"))
            {
                return format!("{} sets run_under or script_path, which would run the installer as something else", rc);
            }
        }
    }
    String::new()
}

/// `bazel run //tools/agent-guard:install`: agents may install, check and dry-run.
pub fn classify_installer_run(args: &[String], cwd: &str, home: &str) -> Option<Verdict> {
    let stop = args.iter().position(|a| a == "--").unwrap_or(args.len());
    let label = args[..stop].iter().position(|a| is_install_label(a, cwd))?;
    let target_args: Vec<String> = args[label + 1..]
        .iter()
        .filter(|a| *a != "--")
        .cloned()
        .collect();
    let bazel_opts: Vec<String> = args[..label]
        .iter()
        .filter(|a| a.starts_with('-'))
        .cloned()
        .collect();
    let mut shown_parts = bazel_opts.clone();
    shown_parts.push(args[label].clone());
    if !target_args.is_empty() {
        shown_parts.push("--".into());
    }
    shown_parts.extend(target_args.iter().cloned());
    let shown = shown_parts.join(" ");
    if installer_args_ok(&target_args) && bazel_opts.is_empty() {
        let why = installer_problem(cwd, home);
        if why.is_empty() {
            return None;
        }
        return Some(v(
            "guard-config",
            &format!("bazel run {}", shown),
            None,
            &format!(
                "Agents may run the installer only as origin/main has it: {}.",
                why
            ),
        ));
    }
    if target_args
        .iter()
        .any(|a| a == "--uninstall" || a.starts_with("--mode"))
    {
        return Some(v(
            "guard-config",
            &format!("bazel run {}", shown),
            None,
            "Removing the backstop (--uninstall) and changing modes are James's, from his own \
terminal. Agents may install, check and dry-run it (`-- --uninstall --dry-run` \
shows him the change).",
        ));
    }
    Some(v(
        "guard-config",
        &format!("bazel run {}", shown),
        Some(t("bazel run //tools/agent-guard:install", None)),
        "Run it exactly so, or with `-- --check` or `-- --dry-run`: no other flags or Bazel \
options (--run_under or --script_path could run it as something else, or without \
the agent marker).",
    ))
}

/// CACHE_RES: is path one of Bazel's output bases or caches?
pub fn is_bazel_cache_path(path: &str) -> bool {
    let t = chars(path);
    let seg_end = |e: usize| e == t.len() || t[e] == '/' || dollar(&t, e);
    let anchored = |pat: &str| {
        let mut from = 0;
        while let Some(at) = crate::pyutil::find_str(&t, pat, from) {
            from = at + 1;
            if (at == 0 || t[at - 1] == '/') && seg_end(at + pat.chars().count()) {
                return true;
            }
        }
        false
    };
    if anchored(".cache/bazel") || anchored("Library/Caches/bazel") {
        return true;
    }
    // /_bazel_[^/]+(/|$)
    let mut from = 0;
    while let Some(at) = crate::pyutil::find_str(&t, "/_bazel_", from) {
        from = at + 1;
        let e = at + 8;
        if e < t.len() && t[e] != '/' {
            return true;
        }
    }
    path.starts_with("/var/tmp/_bazel") || path.starts_with("/private/var/tmp/_bazel")
}

fn is_worktree_dir(path: &str) -> bool {
    // A linked worktree has a .git FILE; the primary has a .git directory.
    let t = chars(path);
    let mut from = 0;
    while let Some(at) = crate::pyutil::find_str(&t, "-worktrees", from) {
        from = at + 1;
        let e = at + 10;
        // -worktrees/?$
        if dollar(&t, e) || (t.get(e) == Some(&'/') && dollar(&t, e + 1)) {
            return true;
        }
        // -worktrees/[^/]+/?$
        if t.get(e) == Some(&'/') {
            let s = e + 1;
            let mut j = s;
            while j < t.len() && t[j] != '/' {
                j += 1;
            }
            for p in (s + 1..=j).rev() {
                if dollar(&t, p) || (p == j && t.get(p) == Some(&'/') && dollar(&t, p + 1)) {
                    return true;
                }
            }
        }
    }
    isfile(&join(path, ".git"))
}

pub fn classify_rm(inv: &Invocation, ctx: &Context) -> (Option<Verdict>, String) {
    let args = &inv.argv[1..];
    let recursive = has(args, &["-r", "-R", "--recursive"]) || short_cluster_has(args, "rR");
    for tgt in positionals(args, &[]) {
        let p = expand_path(&tgt, &inv.cwd, &ctx.home);
        if crate::tamper::guard_path(&p, &ctx.home) {
            if crate::tamper::protected_repo_file(&p, true).is_some() {
                return (
                    Some(v(
                        "guard-config",
                        "rm of agent-guard's hook files",
                        None,
                        &crate::tamper::hook_files_note(),
                    )),
                    p,
                );
            }
            return (
                Some(v(
                    "guard-config",
                    "rm of agent-guard files",
                    None,
                    "Changing agent-guard is James's job, from his own terminal.",
                )),
                p,
            );
        }
        if !recursive {
            continue;
        }
        if is_bazel_cache_path(&p) {
            return (
                Some(v(
                    "bazel-cache",
                    "rm -r of a Bazel cache",
                    Some(T_CACHE_GC),
                    "",
                )),
                p,
            );
        }
        if is_worktree_dir(&p) && repo_root_of(&p).is_some() {
            return (
                Some(v(
                    "git-worktree",
                    "rm -r of a worktree",
                    Some(T_WT_REMOVE),
                    "Or `bazel run //tools/worktree -- --prune`.",
                )),
                p,
            );
        }
    }
    (None, inv.cwd.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every replacement target, by name (the test below checks none is missing).
    const ALL_TARGETS: &[(&str, Target)] = &[
        ("T_COMMIT", T_COMMIT),
        ("T_PUSH", T_PUSH),
        ("T_SYNC", T_SYNC),
        ("T_WT_NEW", T_WT_NEW),
        ("T_WT_DETACH", T_WT_DETACH),
        ("T_WT_REMOVE", T_WT_REMOVE),
        ("T_WT_PRUNE", T_WT_PRUNE),
        ("T_WT_LOCK", T_WT_LOCK),
        ("T_WT_DELETE_BRANCH", T_WT_DELETE_BRANCH),
        ("T_PR_CREATE", T_PR_CREATE),
        ("T_PR_ENQUEUE", T_PR_ENQUEUE),
        ("T_RUN_RERUN", T_RUN_RERUN),
        ("T_RUN_CANCEL", T_RUN_CANCEL),
        ("T_WORKFLOW_RUN", T_WORKFLOW_RUN),
        ("T_SECRET_SCAN", T_SECRET_SCAN),
        ("T_ACTIONLINT", T_ACTIONLINT),
        ("T_CACHE_GC", T_CACHE_GC),
        ("T_FORMAT", T_FORMAT),
        ("T_LINT", T_LINT),
        ("T_BAZEL_TEST", T_BAZEL_TEST),
        ("T_BAZEL_BUILD", T_BAZEL_BUILD),
        ("T_PULUMI", T_PULUMI),
        ("T_GITOPS", T_GITOPS),
        ("T_HELM", T_HELM),
    ];

    #[test]
    fn target_list_is_complete() {
        let src = include_str!("classify.rs");
        let declared: Vec<&str> = src
            .lines()
            .filter_map(|l| l.strip_prefix("pub const T_"))
            .map(|rest| rest.split(':').next().unwrap_or(""))
            .collect();
        let listed: Vec<String> = ALL_TARGETS
            .iter()
            .map(|(n, _)| n[2..].to_string())
            .collect();
        for d in &declared {
            assert!(
                listed.iter().any(|l| l == d),
                "T_{} is not in ALL_TARGETS",
                d
            );
        }
        assert_eq!(declared.len(), ALL_TARGETS.len());
    }

    /// Every file a target's `pending` names is in the repo and still holds
    /// the target; otherwise every refusal naming it says it "is not in this
    /// checkout yet" (it did for //tools/agent-app and //tools/worktree once
    /// their scripts were deleted). The files come from
    /// //tools/agent-guard:pending_target_files, so a deleted one fails the build.
    #[test]
    fn every_pending_file_exists_and_holds_its_target() {
        let mut problems = Vec::new();
        for (name, t) in ALL_TARGETS {
            let Some((rel, needle)) = t.pending else {
                continue;
            };
            match std::fs::read_to_string(rel) {
                Err(_) => problems.push(format!(
                    "{} names {}, which is missing (or not in :pending_target_files)",
                    name, rel
                )),
                Ok(text) => {
                    if let Some(n) = needle {
                        if !text.contains(n) {
                            problems.push(format!("{}: {} no longer has {:?}", name, rel, n));
                        }
                    }
                }
            }
        }
        assert!(problems.is_empty(), "{:#?}", problems);
    }

    #[test]
    fn existing_targets_are_not_called_pending() {
        for t in [
            T_PR_CREATE,
            T_PR_ENQUEUE,
            T_RUN_RERUN,
            T_RUN_CANCEL,
            T_WORKFLOW_RUN,
            T_WT_DETACH,
            T_WT_LOCK,
        ] {
            let verdict = v("gh-pr", "x", Some(t), "");
            let msg = verdict.message(Some("/nonexistent/agent-guard-test-root"));
            assert!(!msg.contains("not in this checkout yet"), "{}", msg);
        }
    }

    #[test]
    fn regex_ports() {
        assert_eq!(
            gh_url("https://GitHub.com/O/r.git#x"),
            Some(("O".into(), "r.git".into()))
        );
        assert_eq!(gh_url("github.com/o/"), None);
        assert!(
            has_mutation("mutation{x}") && has_mutation("{mutation(") && !has_mutation("amutation")
        );
        assert!(is_bazel_cache_path("/u/.cache/bazel") && is_bazel_cache_path("/x/_bazel_j/abc"));
        assert!(
            !is_bazel_cache_path("/x/_bazel_/y")
                && is_bazel_cache_path("/private/var/tmp/_bazel_x")
        );
        assert!(is_worktree_dir("/a/b-worktrees/x/") && is_worktree_dir("/a/b-worktrees"));
        assert!(
            is_install_label("//tools/agent-guard:install", "")
                && !is_install_label("x/mytools/agent-guard:install", "")
        );
        assert_eq!(
            rc_import("  try-import %workspace%/user.bazelrc"),
            Some("%workspace%/user.bazelrc".into())
        );
    }
}
