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

//! Bazel queries (query.go) and the dependency map (rdepsmap.go, #2465).
//!
//! Answering "which tests depend on these packages?" live means a cold
//! `bazel query`: minutes on a fresh runner. The answer only changes when
//! main changes, so a push to main computes it once and saves it keyed by
//! that commit; a PR's plan looks the answer up in that map. A package the
//! map has never seen falls back to the live query, and a new test in a
//! changed package is caught by selecting any unit whose package contains a
//! changed package (see the engine).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use serde::Serialize;
use unitfile::gocompat::exec::{self, Cmd, Ctx, ExecError, Io};
use unitfile::gocompat::json::{self, Dec};
use unitfile::gocompat::oserr;
use unitfile::gocompat::quote::quote;

use crate::{check_global_impact, QueryRunner, RevGraph};

/// Bumped whenever the map's meaning changes.
pub const RDEPS_MAP_SCHEMA: i64 = 1;

/// Which non-manual tests transitively depend on each main-repo package, at
/// one commit.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct RdepsMap {
    pub schema: i64,
    pub commit: String,
    /// Every main-repo package at commit; None is Go's nil slice.
    pub packages: Option<Vec<String>>,
    /// Package ("apps/x") to the tests that depend on it; packages with no
    /// dependent test are absent.
    pub tests: Option<BTreeMap<String, Vec<String>>>,
}

/// `lines[...]` of a string, each trimmed, empty ones dropped.
pub fn non_empty_lines(s: &str) -> Vec<String> {
    s.split('\n')
        .map(exec::go_trim)
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect()
}

/// The final n lines of s.
pub fn last_lines(s: &str, n: usize) -> String {
    let lines: Vec<&str> = s.trim_end_matches('\n').split('\n').collect();
    let start = lines.len().saturating_sub(n);
    lines[start..].join("\n")
}

/// The query that finds every test affected by a set of packages. Manual
/// tests are excluded (an explicit target ignores the manual tag), and `:*`
/// is used instead of `:all` so tests that read a package's files count.
pub fn build_test_rdeps_query(packages: &[String]) -> String {
    let targets: Vec<String> = packages
        .iter()
        .map(|p| format!("{}:*", p.strip_suffix(":all").unwrap_or(p)))
        .collect();
    format!(
        "kind(\".*_test|.*_suite|service_test\", rdeps(//..., set({}))) except attr(tags, \"manual\", //...)",
        targets.join(" ")
    )
}

/// The ERROR lines of a --keep_going query that are not confined to an
/// external repo. Unrecognised lines count as internal.
pub fn internal_query_errors(stderr: &str, repo_root: &str) -> Vec<String> {
    let mut bad = Vec::new();
    for line in stderr.split('\n') {
        let Some(msg) = exec::go_trim(line).strip_prefix("ERROR: ") else {
            continue;
        };
        if msg.starts_with("Evaluation of query") && msg.contains("errors were encountered") {
            continue;
        }
        if msg.starts_with('/') {
            let root = format!("{}/", repo_root.strip_suffix('/').unwrap_or(repo_root));
            if repo_root.is_empty() || msg.starts_with(&root) {
                bad.push(line.to_string());
            }
        } else if msg.contains("'//") || msg.contains(" //") {
            bad.push(line.to_string());
        } else if msg.contains("'@") {
        } else {
            bad.push(line.to_string());
        }
    }
    bad
}

fn bazel(repo_root: &str, args: &[&str]) -> Cmd {
    let mut c = Cmd::new("bazel", args);
    c.dir = repo_root.to_string();
    c.stdout = Io::Capture;
    c.stderr = Io::Capture;
    c
}

fn labels(stdout: &[u8]) -> Vec<String> {
    let text = String::from_utf8_lossy(stdout);
    let mut out: Vec<String> = exec::go_trim(&text)
        .split('\n')
        .map(exec::go_trim)
        .filter(|l| !l.is_empty() && l.starts_with("//"))
        .map(String::from)
        .collect();
    out.sort();
    out
}

/// Runs real `bazel query` commands.
pub struct BazelQueryRunner<'a> {
    pub ctx: &'a Ctx,
}

impl QueryRunner for BazelQueryRunner<'_> {
    fn query_test_rdeps(
        &self,
        repo_root: &str,
        packages: &[String],
    ) -> Result<Vec<String>, String> {
        if packages.is_empty() {
            return Ok(Vec::new());
        }
        let expr = build_test_rdeps_query(packages);
        let c = bazel(
            repo_root,
            &["query", &expr, "--output=label", "--keep_going"],
        );
        let (r, out) = exec::run(&c, self.ctx);
        if let Err(e) = r {
            let stderr = String::from_utf8_lossy(&out.stderr);
            if e == ExecError::ExitCode(3) {
                let bad = internal_query_errors(&stderr, repo_root);
                if !bad.is_empty() {
                    return Err(format!(
                        "bazel query was partial and some errors are in this repo, so tests may be missing: {}",
                        bad.join("\n")
                    ));
                }
            } else {
                return Err(format!(
                    "bazel query failed: {e}: {}",
                    last_lines(&stderr, 15)
                ));
            }
        }
        Ok(labels(&out.stdout))
    }
}

/// The filter for every test CI runs on its own; it must match
/// [`build_test_rdeps_query`].
pub const TEST_UNIVERSE_EXPR: &str =
    r#"kind(".*_test|.*_suite|service_test", //...) except attr(tags, "manual", //...)"#;

fn strict_query(ctx: &Ctx, repo_root: &str, expr: &str, flags: &[&str]) -> Result<String, String> {
    let mut args = vec!["query", expr];
    args.extend_from_slice(flags);
    let c = bazel(repo_root, &args);
    let (r, out) = exec::run(&c, ctx);
    if let Err(e) = r {
        return Err(format!(
            "bazel query {} failed: {e}: {}",
            quote(expr),
            last_lines(&String::from_utf8_lossy(&out.stderr), 15)
        ));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// The three strict queries behind the dependency map.
pub fn build_rdeps_map(ctx: &Ctx, repo_root: &str, commit: &str) -> Result<RdepsMap, String> {
    let tests = strict_query(ctx, repo_root, TEST_UNIVERSE_EXPR, &["--output=label"])?;
    let pkgs = strict_query(ctx, repo_root, "//...", &["--output=package"])?;
    let deps_expr = format!("deps({TEST_UNIVERSE_EXPR})");
    let dot = strict_query(
        ctx,
        repo_root,
        &deps_expr,
        &[
            "--output=graph",
            "--graph:factored=false",
            "--graph:node_limit=-1",
        ],
    )?;
    let edges = parse_graph_edges(&dot)?;
    Ok(compute_rdeps_map(
        commit,
        &non_empty_lines(&tests),
        &edges,
        &non_empty_lines(&pkgs),
    ))
}

/// Reads `bazel query --output=graph --graph:factored=false` into an
/// adjacency list. Node-only lines register the node with no edges.
pub fn parse_graph_edges(dot: &str) -> Result<HashMap<String, Vec<String>>, String> {
    let mut edges: HashMap<String, Vec<String>> = HashMap::new();
    for raw in dot.split('\n') {
        // bufio.ScanLines drops a trailing \r.
        if raw.len() > 16 * 1024 * 1024 {
            return Err("bufio.Scanner: token too long".to_string());
        }
        let line = exec::go_trim(raw.strip_suffix('\r').unwrap_or(raw));
        if !line.starts_with('"') {
            continue;
        }
        if let Some((from, to)) = line.split_once("\" -> \"") {
            let from = from.strip_prefix('"').unwrap_or(from);
            let to = to.strip_suffix('"').unwrap_or(to);
            if from.contains("\\n") || to.contains("\\n") {
                return Err(format!(
                    "factored graph node {}; query must use --graph:factored=false",
                    quote(from)
                ));
            }
            edges
                .entry(from.to_string())
                .or_default()
                .push(to.to_string());
            continue;
        }
        let node = line.trim_matches('"');
        edges.entry(node.to_string()).or_default();
    }
    Ok(edges)
}

/// The package of a main-repo label ("//a/b:c" -> "a/b"), or None.
fn main_repo_package(label: &str) -> Option<String> {
    let mut label = label.to_string();
    for p in ["@@//", "@//"] {
        if let Some(rest) = label.strip_prefix(p) {
            label = format!("//{rest}");
        }
    }
    let rest = label.strip_prefix("//")?;
    rest.split_once(':').map(|(pkg, _)| pkg.to_string())
}

/// Walks each test's transitive deps (through external repos too) and
/// records it against every main-repo package it reaches.
pub fn compute_rdeps_map(
    commit: &str,
    tests: &[String],
    edges: &HashMap<String, Vec<String>>,
    packages: &[String],
) -> RdepsMap {
    let mut by_pkg: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for test in tests {
        let mut seen: HashSet<&str> = HashSet::new();
        seen.insert(test.as_str());
        let mut stack: Vec<&str> = vec![test.as_str()];
        while let Some(n) = stack.pop() {
            if let Some(pkg) = main_repo_package(n) {
                by_pkg.entry(pkg).or_default().insert(test.clone());
            }
            if let Some(deps) = edges.get(n) {
                for d in deps {
                    if seen.insert(d.as_str()) {
                        stack.push(d.as_str());
                    }
                }
            }
        }
    }
    let tests_map = by_pkg
        .into_iter()
        .map(|(k, v)| (k, v.into_iter().collect()))
        .collect();
    let mut pk: Vec<String> = packages.to_vec();
    pk.sort();
    RdepsMap {
        schema: RDEPS_MAP_SCHEMA,
        commit: commit.to_string(),
        packages: if pk.is_empty() { None } else { Some(pk) },
        tests: Some(tests_map),
    }
}

impl RdepsMap {
    /// The tests that depend on the given packages ("//a/b:all"). None if
    /// any package is unknown to the map.
    pub fn lookup(&self, packages: &[String]) -> Option<Vec<String>> {
        let known: HashSet<&str> = self.packages.iter().flatten().map(|s| s.as_str()).collect();
        let mut set = BTreeSet::new();
        for p in packages {
            let p = p.strip_prefix("//").unwrap_or(p);
            let pkg = p.strip_suffix(":all").unwrap_or(p);
            if !known.contains(pkg) {
                return None;
            }
            if let Some(ts) = self.tests.as_ref().and_then(|t| t.get(pkg)) {
                set.extend(ts.iter().cloned());
            }
        }
        Some(set.into_iter().collect())
    }
}

fn decode_map(data: &[u8]) -> Result<RdepsMap, String> {
    let v = json::parse(data)?;
    let mut m = RdepsMap::default();
    let mut d = Dec::new();
    d.object(
        &v,
        "RdepsMap",
        "main.RdepsMap",
        &["schema", "commit", "packages", "tests"],
        |d, name, x| match name {
            "schema" => d.int(x, &mut m.schema),
            "commit" => d.string(x, &mut m.commit),
            "packages" => d.strings(x, &mut m.packages),
            _ => d.strings_map(x, &mut m.tests),
        },
    );
    d.finish().map(|_| m)
}

/// Reads a map and checks it describes `want_commit`. A missing file is
/// Ok(None); every other problem is the reason it cannot be used.
pub fn load_rdeps_map(p: &str, want_commit: &str) -> Result<Option<RdepsMap>, String> {
    let data = match unitfile::read_file(p) {
        Ok(d) => d,
        Err((e, msg)) => {
            if oserr::is_not_exist(&e) {
                return Ok(None);
            }
            return Err(msg);
        }
    };
    let m = decode_map(&data).map_err(|e| format!("parse {p}: {e}"))?;
    if m.schema != RDEPS_MAP_SCHEMA {
        return Err(format!("map schema {}, want {RDEPS_MAP_SCHEMA}", m.schema));
    }
    if want_commit.is_empty() || m.commit != want_commit {
        return Err(format!(
            "map is for commit {}, diff base is {}",
            quote(&m.commit),
            quote(want_commit)
        ));
    }
    if m.packages.as_ref().map(|p| p.is_empty()).unwrap_or(true) {
        return Err("map lists no packages".to_string());
    }
    Ok(Some(m))
}

/// The commit a map file was computed at, or "" if it is missing or
/// unreadable.
pub fn peek_rdeps_map_commit(p: &str) -> String {
    let Ok(data) = unitfile::read_file(p) else {
        return String::new();
    };
    let Ok(v) = json::parse(&data) else {
        return String::new();
    };
    let mut commit = String::new();
    let mut d = Dec::new();
    d.object(
        &v,
        "",
        "struct { Commit string \"json:\\\"commit\\\"\" }",
        &["commit"],
        |d, _, x| d.string(x, &mut commit),
    );
    if d.finish().is_err() {
        return String::new();
    }
    commit
}

/// Whether a map computed at map_commit may stand in for the missing map of
/// base_commit (#2841), and what was decided, for the log.
pub fn earlier_map_base(
    g: &dyn RevGraph,
    map_commit: &str,
    base_commit: &str,
    max_behind: i64,
) -> (bool, String) {
    let short = if map_commit.len() > 12 {
        map_commit.get(..12).unwrap_or(map_commit)
    } else {
        map_commit
    };
    if !g.is_ancestor(map_commit, base_commit) {
        return (
            false,
            format!("dependency map not used (it is for {short}, which is not an ancestor of the diff base)"),
        );
    }
    let behind = match g.commits_between(map_commit, base_commit) {
        Ok(n) => n,
        Err(e) => {
            return (
                false,
                format!("dependency map not used (cannot count commits since {short}: {e})"),
            )
        }
    };
    if behind > max_behind {
        return (
            false,
            format!("dependency map not used (it is {behind} commits behind the diff base, limit {max_behind})"),
        );
    }
    let between = match g.changed_files(map_commit, base_commit) {
        Ok(f) => f,
        Err(e) => {
            return (
                false,
                format!("dependency map not used (cannot list changes since {short}: {e})"),
            )
        }
    };
    let (global, reason) = check_global_impact(&between);
    if global {
        return (
            false,
            format!("dependency map not used (since {short}, {reason})"),
        );
    }
    (
        true,
        format!("note: dependency map is from {behind} commit(s) back ({short}); planning against that commit, so everything changed since then counts as changed"),
    )
}
