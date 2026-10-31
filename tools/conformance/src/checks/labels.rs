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

//! CHECK: every Bazel label a workflow or composite action names resolves.
//!
//! A label in `.github/` is a string nothing else reads until the job runs.
//! A renamed or deleted target leaves the workflow calling a label that no
//! longer exists, and every presubmit stays green: actionlint does not know
//! Bazel, and the lane that runs the label may be path-filtered, main-only or
//! release-only. Two planted strings proved it (`//tools/conformance:check-rs`
//! in conformance-check.yaml, `home-speaker:publish-rs` in ci.yaml).
//!
//! What counts as a reference: a label inside a `bazel|bazelisk <verb>` command
//! (build, test, run, query, cquery, aquery, coverage), and a YAML value that
//! is a label and nothing else (`target: //pkg:name`, an input to a reusable
//! workflow). Prose, comments and other tools' `//` (sed, jq, URLs) are not.
//! External labels (`@repo//...`) are left alone.
//!
//! How they are resolved: ONE `bazel query --keep_going` over the whole set.
//! Parsing BUILD files instead would miss every target a macro declares (the
//! `*_typecheck_test`, `publish-tool` and `pkg` targets in the workflows today
//! are all macro output), so a parse would need an allowlist that rots.
//!
//! Where it runs: tidy-check (`bazel run //tools/conformance:workflow-labels`),
//! not `//tools/conformance:check`. The query is NOT cheap on a fresh output
//! base: loading the ~60 named packages loads their .bzl files, which fetches
//! the external repositories they come from (grpc, gazelle, the pip and npm
//! hubs and more; about 19 on a clean runner). In conformance-check that took
//! the step from ~45s to ~3m and made a required check depend on those
//! fetches. tidy-check has already run `//:tidy` over the whole graph by then,
//! so every one of them is fetched and the query costs seconds.
//!
//! A fetch or load failure is still possible, so it is reported as such: a
//! label counts as missing only when Bazel says "no such target" or "no such
//! package ... BUILD file not found"; anything else is an infrastructure
//! failure, worded so nobody goes looking for a renamed target that exists.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;

use crate::Context;

const VERBS: &[&str] = &[
    "build", "test", "run", "query", "cquery", "aquery", "coverage",
];

/// One label a workflow names, with where it was found.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct LabelRef {
    pub line: usize,
    pub label: String,
}

/// What a collected reference asks Bazel for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Ref {
    /// `//pkg:name` (normalized), resolved by bazel query.
    Target(String),
    /// `//pkg/...`: the directory must exist.
    Recursive(String),
    /// `//pkg:all`, `//pkg:*`: the package must exist.
    Package(String),
}

fn is_label_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '/' | '+' | '-' | '~' | ':')
}

fn is_boundary(c: char) -> bool {
    c.is_whitespace() || matches!(c, '"' | '\'' | '(' | ',' | '=')
}

/// Every label-shaped token in `text`: a `//` at a word boundary, read up to
/// the first character a label cannot hold. A token followed by `$` or `{` is
/// templated (`//apps/${{ inputs.app }}:x`) and skipped, as is one that runs
/// into another `/` or `:` construct of a URL (`https://...` never matches: its
/// `//` follows a `:`).
pub(crate) fn labels_in(text: &str) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i + 1 < chars.len() {
        if chars[i] == '/' && chars[i + 1] == '/' && (i == 0 || is_boundary(chars[i - 1])) {
            let start = i;
            let mut j = i + 2;
            while j < chars.len() && is_label_char(chars[j]) {
                j += 1;
            }
            let templated = j < chars.len() && matches!(chars[j], '$' | '{');
            let tok: String = chars[start..j].iter().collect();
            if !templated {
                out.push(tok);
            }
            i = j.max(i + 2);
        } else {
            i += 1;
        }
    }
    out
}

/// Drop a trailing shell/YAML comment (` # ...`) from a line.
fn strip_trailing_comment(line: &str) -> &str {
    let bytes = line.as_bytes();
    for i in 1..bytes.len() {
        if bytes[i] == b'#' && (bytes[i - 1] == b' ' || bytes[i - 1] == b'\t') {
            return &line[..i];
        }
    }
    line
}

/// The text after each `bazel <flags> <verb>` in `line`, up to the next shell
/// command separator (`;`, `|`, `&`). Startup flags and `"${cache[@]}"`-style
/// expansions before the verb are skipped.
pub(crate) fn bazel_command_args(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = line;
    loop {
        let found = ["bazel ", "bazelisk ", "ibazel "]
            .iter()
            .filter_map(|w| {
                let mut from = 0;
                while let Some(p) = rest[from..].find(w) {
                    let at = from + p;
                    let ok = at == 0
                        || rest[..at].chars().last().is_some_and(|c| {
                            c.is_whitespace() || matches!(c, ';' | '&' | '|' | '(' | '`' | '"')
                        });
                    if ok {
                        return Some((at, w.len()));
                    }
                    from = at + w.len();
                }
                None
            })
            .min();
        let Some((at, wlen)) = found else { break };
        // `echo bazel test //x` prints a command, it does not run one.
        let before = &rest[..at];
        let cmd_start = before
            .rfind([';', '&', '|', '(', '`'])
            .map(|p| p + 1)
            .unwrap_or(0);
        let printed = {
            let lead = before[cmd_start..].trim_start();
            lead.starts_with("echo ") || lead.starts_with("printf ")
        };
        let after = &rest[at + wlen..];
        let end = after.find([';', '|', '&']).unwrap_or(after.len());
        let segment = &after[..end];
        let mut words = segment.split_whitespace();
        let verb =
            words.find(|w| !(w.starts_with('-') || w.starts_with('$') || w.starts_with("\"$")));
        if !printed && verb.is_some_and(|v| VERBS.contains(&v)) {
            // For `run`, what follows `--` is the program's own arguments,
            // not targets (`bazel run //tools/x -- //some:label`). For
            // build/test/query, `--` only ends the flags; targets follow.
            let args: Vec<&str> = if verb == Some("run") {
                words.take_while(|w| *w != "--").collect()
            } else {
                words.collect()
            };
            out.push(args.join(" "));
        }
        rest = &after[end..];
        if rest.is_empty() {
            break;
        }
        rest = &rest[1..];
    }
    out
}

/// Every first-party label `content` (a workflow or action file) references.
pub(crate) fn collect_refs(content: &str) -> Vec<LabelRef> {
    // Join `\` continuations so a multi-line `bazel test \` keeps its labels.
    let mut logical: Vec<(usize, String)> = Vec::new();
    let mut buf = String::new();
    let mut start = 0;
    for (idx, raw) in content.lines().enumerate() {
        let line = raw.trim_end_matches('\r');
        if buf.is_empty() {
            start = idx + 1;
        }
        if let Some(body) = line.trim_end().strip_suffix('\\') {
            buf.push_str(body);
            buf.push(' ');
            continue;
        }
        buf.push_str(line);
        logical.push((start, std::mem::take(&mut buf)));
    }
    if !buf.is_empty() {
        logical.push((start, buf));
    }

    let mut out = Vec::new();
    for (line_no, line) in logical {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') {
            continue;
        }
        let code = strip_trailing_comment(&line);
        for args in bazel_command_args(code) {
            for label in labels_in(&args) {
                out.push(LabelRef {
                    line: line_no,
                    label,
                });
            }
        }
        // `key: //pkg:name` -- a label as the whole YAML value.
        let body = trimmed.trim_start_matches("- ");
        if let Some((key, value)) = body.split_once(": ") {
            if !key.contains(' ') && !key.is_empty() {
                let v = strip_trailing_comment(value)
                    .trim()
                    .trim_matches(|c| c == '"' || c == '\'');
                // One label, or several separated by spaces (`targets: //a:b //c:d`).
                let toks: Vec<&str> = v.split_whitespace().collect();
                if !toks.is_empty()
                    && toks.iter().all(|t| {
                        t.starts_with("//") && labels_in(t).first().map(String::as_str) == Some(*t)
                    })
                {
                    for t in toks {
                        out.push(LabelRef {
                            line: line_no,
                            label: t.to_string(),
                        });
                    }
                }
            }
        }
    }
    out.sort_by(|a, b| (a.line, &a.label).cmp(&(b.line, &b.label)));
    out.dedup();
    out
}

/// What a raw label asks for, or None for one that names the whole repo.
pub(crate) fn classify(raw: &str) -> Option<Ref> {
    if raw == "//" || raw == "//..." {
        return None;
    }
    if let Some(pkg) = raw.strip_suffix("/...") {
        return Some(Ref::Recursive(pkg.trim_start_matches("//").to_string()));
    }
    let label = raw.trim_end_matches(['.', ':']);
    let body = label.strip_prefix("//")?;
    let (pkg, name) = match body.split_once(':') {
        Some((p, n)) => (p, n.to_string()),
        None => (body, body.rsplit('/').next().unwrap_or(body).to_string()),
    };
    if pkg.ends_with('/') || name.is_empty() {
        return Some(Ref::Target(label.to_string()));
    }
    if matches!(name.as_str(), "all" | "*" | "all-targets") {
        return Some(Ref::Package(pkg.to_string()));
    }
    Some(Ref::Target(format!("//{}:{}", pkg, name)))
}

/// The `set(...)` query expression for a group of normalized labels.
pub(crate) fn query_expr(labels: &BTreeSet<String>) -> String {
    let quoted: Vec<String> = labels.iter().map(|l| format!("\"{}\"", l)).collect();
    format!("set({})", quoted.join(" "))
}

fn workflow_and_action_files(root: &str) -> Vec<String> {
    let mut files = Vec::new();
    for dir in [
        format!("{root}/.github/workflows"),
        format!("{root}/.github/actions"),
    ] {
        walk_yaml(Path::new(&dir), &mut files);
    }
    files.sort();
    files
}

fn walk_yaml(dir: &Path, out: &mut Vec<String>) {
    let Ok(rd) = fs::read_dir(dir) else { return };
    for entry in rd.flatten() {
        let p = entry.path();
        if p.is_dir() {
            walk_yaml(&p, out);
        } else if p
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|e| e == "yml" || e == "yaml")
        {
            out.push(p.to_string_lossy().to_string());
        }
    }
}

/// How a `bazel query --keep_going` error line bears on one label.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum QueryErr {
    /// Bazel says the target or its package does not exist.
    Missing,
    /// The line is about this label's package, but for another reason
    /// (an external repository failed to fetch, a .bzl failed to load).
    Infra,
}

/// None when `line` is not an error about `label` (`//pkg:name`).
pub(crate) fn query_error_kind(line: &str, label: &str) -> Option<QueryErr> {
    if !line.contains("ERROR") {
        return None;
    }
    let pkg = label
        .trim_start_matches("//")
        .split(':')
        .next()
        .unwrap_or("");
    let pkg_q = format!("'{}'", pkg);
    if !(line.contains(label) || line.contains(&pkg_q)) {
        return None;
    }
    if line.contains(&format!("no such target '{}'", label)) {
        return Some(QueryErr::Missing);
    }
    if line.contains(&format!("no such package {}", pkg_q)) && line.contains("BUILD file not found")
    {
        return Some(QueryErr::Missing);
    }
    Some(QueryErr::Infra)
}

/// An error line for the report: no "ERROR: " prefix, and no " defined by
/// /abs/path/BUILD" (a machine path; the package already names the file).
fn tidy_error(l: &str) -> String {
    let l = match (l.find(" defined by "), l.rfind(" (did you mean")) {
        (Some(a), Some(b)) if b > a => format!("{}{}", &l[..a], &l[b..]),
        (Some(a), _) => l[..a].to_string(),
        _ => l.to_string(),
    };
    l.trim().trim_start_matches("ERROR: ").to_string()
}

pub fn check_workflow_labels(ctx: &Context) {
    // label -> every place it is named
    let mut targets: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut ok_count = 0usize;
    let mut file_count = 0usize;
    let mut failed = false;

    for f in workflow_and_action_files(&ctx.root) {
        let Ok(content) = fs::read_to_string(&f) else {
            continue;
        };
        let rel = ctx.rel(&f);
        let refs = collect_refs(&content);
        if !refs.is_empty() {
            file_count += 1;
        }
        for r in refs {
            let at = format!("{}:{}", rel, r.line);
            match classify(&r.label) {
                None => {}
                Some(Ref::Target(l)) => targets.entry(l).or_default().push(at),
                Some(Ref::Recursive(pkg)) => {
                    if Path::new(&format!("{}/{}", ctx.root, pkg)).is_dir() {
                        ok_count += 1;
                    } else {
                        failed = true;
                        ctx.emit_fail(
                            "labels", &at, &r.label, "an existing directory",
                            &format!("{} is not a directory, so the pattern matches nothing and the step fails (or silently tests nothing)", pkg),
                            "point the pattern at the package's current path",
                        );
                    }
                }
                Some(Ref::Package(pkg)) => {
                    let has_build = ["BUILD", "BUILD.bazel"]
                        .iter()
                        .any(|b| Path::new(&format!("{}/{}/{}", ctx.root, pkg, b)).is_file());
                    if has_build {
                        ok_count += 1;
                    } else {
                        failed = true;
                        ctx.emit_fail(
                            "labels",
                            &at,
                            &r.label,
                            "an existing package",
                            &format!("{} has no BUILD file, so it is not a Bazel package", pkg),
                            "point the label at the package's current path",
                        );
                    }
                }
            }
        }
    }

    if targets.is_empty() {
        ctx.emit_fail(
            "labels", ".github", "0 labels", ">0",
            "found no Bazel label in any workflow or action -- the collector drifted from how the workflows call Bazel, and this check is checking nothing",
            "fix collect_refs in tools/conformance/src/checks/labels.rs",
        );
        return;
    }

    let wanted: BTreeSet<String> = targets.keys().cloned().collect();
    let output = Command::new("bazel")
        .current_dir(&ctx.root)
        .args([
            "query",
            "--keep_going",
            "--output=label",
            "--noshow_progress",
        ])
        .arg(query_expr(&wanted))
        .output();
    let output = match output {
        Ok(o) => o,
        Err(e) => {
            ctx.emit_fail(
                "labels", ".github", "bazel query", "runs",
                &format!("could not run bazel to resolve {} workflow labels: {}", wanted.len(), e),
                "run this check through `bazel run //tools/conformance:check`, which has bazel on PATH",
            );
            return;
        }
    };
    let code = output.status.code().unwrap_or(-1);
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    // 0: everything resolved. 3: --keep_going finished with some labels
    // missing. Anything else means the query itself broke, and an empty
    // result must not read as "every label is missing" or as a pass.
    if code != 0 && code != 3 {
        let tail: Vec<&str> = stderr
            .lines()
            .filter(|l| l.contains("ERROR"))
            .take(3)
            .collect();
        ctx.emit_fail(
            "labels",
            ".github",
            &format!("bazel query exit {}", code),
            "0 or 3",
            &format!(
                "bazel query failed before it could resolve the workflow labels: {}",
                tail.join(" | ")
            ),
            "run the query by hand from the repo root to see why it failed",
        );
        return;
    }
    let found: BTreeSet<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();

    for (label, places) in &targets {
        if found.contains(label) {
            ok_count += 1;
            continue;
        }
        failed = true;
        let related: Vec<(QueryErr, &str)> = stderr
            .lines()
            .filter_map(|l| query_error_kind(l, label).map(|k| (k, l)))
            .collect();
        let missing = related.iter().find(|(k, _)| *k == QueryErr::Missing);
        let why = missing
            .or_else(|| related.first())
            .map(|(_, l)| tidy_error(l))
            .unwrap_or_else(|| "bazel query did not return it and named no reason".to_string());
        for at in places {
            if missing.is_some() {
                ctx.emit_fail(
                    "labels", at, label, "an existing target",
                    &format!("the workflow names a target that does not exist, so the step fails only when that lane next runs ({})", why),
                    "point the workflow at the target's current label, or restore the target",
                );
            } else {
                // Not proof the target is gone: its package failed to load
                // for another reason (a repository fetch, a broken .bzl).
                ctx.emit_fail(
                    "labels", at, label, "resolvable",
                    &format!("could not resolve this label, and Bazel did not say the target is missing -- an infrastructure or load failure, not a renamed target ({})", why),
                    "re-run the job; if it repeats, run `bazel query` on the label by hand to see the load error",
                );
            }
        }
    }

    if !failed {
        ctx.emit_ok(
            "labels",
            ".github",
            &format!("{} labels", ok_count),
            "all resolve",
            &format!(
                "every Bazel label in {} workflow and action files resolves (one bazel query)",
                file_count
            ),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn labels(content: &str) -> Vec<String> {
        collect_refs(content).into_iter().map(|r| r.label).collect()
    }

    #[test]
    fn finds_labels_in_bazel_commands() {
        let c = r#"
      - run: |
          bazel run "${cache[@]}" //tools/conformance:check
          bazel test "${cache[@]}" --config=macos-app //apps/desktop/home-speaker:HomeSpeakerTests //apps/x:y
          bazel run "${cache[@]}" //apps/desktop/home-speaker:publish-rs -- --dry-run
"#;
        assert_eq!(
            labels(c),
            vec![
                "//tools/conformance:check",
                "//apps/desktop/home-speaker:HomeSpeakerTests",
                "//apps/x:y",
                "//apps/desktop/home-speaker:publish-rs",
            ]
        );
    }

    #[test]
    fn joins_continuations_and_skips_comments() {
        let c = "      run: |\n        # bazel run //not:me\n        bazel test \\\n          //a:b \\\n          //c:d # //e:f\n";
        let refs = collect_refs(c);
        assert_eq!(
            refs.iter().map(|r| r.label.as_str()).collect::<Vec<_>>(),
            vec!["//a:b", "//c:d"]
        );
        assert_eq!(refs[0].line, 3);
    }

    #[test]
    fn ignores_other_tools_slashes() {
        let c = r#"
          echo "$(sed -n 's/^verdict=//p' f)"
          jq -r '.status // empty' x
          git clone https://x-access-token:t@github.com/o/r
          echo "see //tools:gen for details"
          bazel query 'kind(go_test, //...)'
          bazel build --@rules_go//go/config:race //apps/a/...
          bazel run //apps/${{ inputs.app }}:deploy
"#;
        assert_eq!(labels(c), vec!["//...", "//apps/a/..."]);
    }

    #[test]
    fn yaml_value_label_counts() {
        let c = "      with:\n        target: //apps/suites/tabula/api:image_push\n        description: 'e.g. //x:y'\n";
        assert_eq!(labels(c), vec!["//apps/suites/tabula/api:image_push"]);
    }

    #[test]
    fn separators_end_the_command() {
        let c = "  run: bazel run //a:b && echo //c:d; bazel test //e:f | tee //g:h\n";
        assert_eq!(labels(c), vec!["//a:b", "//e:f"]);
    }

    #[test]
    fn classify_normalizes() {
        assert_eq!(
            classify("//tools/osv-scan"),
            Some(Ref::Target("//tools/osv-scan:osv-scan".into()))
        );
        assert_eq!(classify("//:tidy"), Some(Ref::Target("//:tidy".into())));
        assert_eq!(
            classify("//tools/ci:gen."),
            Some(Ref::Target("//tools/ci:gen".into()))
        );
        assert_eq!(
            classify("//apps/cli/devx/..."),
            Some(Ref::Recursive("apps/cli/devx".into()))
        );
        assert_eq!(classify("//tools:all"), Some(Ref::Package("tools".into())));
        assert_eq!(classify("//..."), None);
        assert_eq!(classify("//"), None);
    }

    #[test]
    fn query_expr_quotes_each_label() {
        let s: BTreeSet<String> = ["//a:b", "//c:d+e"].iter().map(|s| s.to_string()).collect();
        assert_eq!(query_expr(&s), "set(\"//a:b\" \"//c:d+e\")");
    }

    #[test]
    fn run_args_after_double_dash_are_not_targets() {
        let c = "  run: bazel run //tools/x:y -- //nope:x --flag\n";
        assert_eq!(labels(c), vec!["//tools/x:y"]);
    }

    #[test]
    fn run_args_after_double_dash_across_continuation() {
        let c = "      run: |\n        bazel run \"${cache[@]}\" //tools/x:y \\\n          -- \\\n          //nope:x\n";
        assert_eq!(labels(c), vec!["//tools/x:y"]);
    }

    #[test]
    fn test_targets_after_double_dash_still_count() {
        let c = "  run: bazel test -- //a:b //c:d\n";
        assert_eq!(labels(c), vec!["//a:b", "//c:d"]);
    }

    #[test]
    fn classify_query_errors() {
        assert_eq!(
            query_error_kind("ERROR: Skipping '//a:b': no such target '//a:b': target 'b' not declared in package 'a'", "//a:b"),
            Some(QueryErr::Missing)
        );
        assert_eq!(
            query_error_kind("ERROR: Skipping '//nope:x': no such package 'nope': BUILD file not found in any of the following directories.", "//nope:x"),
            Some(QueryErr::Missing)
        );
        assert_eq!(
            query_error_kind("ERROR: /w/apps/a/BUILD:3:1: error loading package 'apps/a': no such package '@@grpc+//bazel': fetch failed", "//apps/a:t"),
            Some(QueryErr::Infra)
        );
        assert_eq!(query_error_kind("ERROR: something else", "//a:b"), None);
    }

    #[test]
    fn printed_commands_and_ibazel() {
        let c = "  run: |\n    echo bazel test //x:printed\n    echo \"run: $(bazel query //q:real)\"\n    ibazel run //w:watched\n";
        assert_eq!(labels(c), vec!["//q:real", "//w:watched"]);
    }

    #[test]
    fn several_labels_in_one_yaml_value() {
        let c = "      with:\n        targets: //a:b //c:d\n        note: //a:b and more\n";
        assert_eq!(labels(c), vec!["//a:b", "//c:d"]);
    }
}
