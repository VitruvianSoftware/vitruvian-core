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

//! CHECK `NODETOOLCACHE`: every top-level `actions/setup-node` workflow step
//! restores via `./.github/actions/node-toolcache`, ties its version to `.nvmrc`,
//! sets no literal `node-version`, and saves caches only on `refs/heads/main`
//! under key prefix `node-toolcache-v1`.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use crate::canonical::canonical_node_exact;
use crate::Context;

const GROUP: &str = "nodetoolcache";
const COMPOSITE_REL: &str = ".github/actions/node-toolcache/action.yml";
const COMPOSITE_USES: &str = "./.github/actions/node-toolcache";
const KEY_PREFIX: &str = "node-toolcache-v1";

const STEP_KEYS: &[&str] = &[
    "name:",
    "id:",
    "if:",
    "uses:",
    "run:",
    "with:",
    "env:",
    "shell:",
    "continue-on-error:",
    "working-directory:",
    "timeout-minutes:",
];

#[derive(Debug, Default)]
struct ParsedStep {
    line_no: usize,
    uses: String,
    if_expr: Option<String>,
    with: BTreeMap<String, String>,
}

fn indent(line: &str) -> usize {
    line.bytes().take_while(|&b| b == b' ').count()
}

fn strip_comment(s: &str) -> &str {
    let (mut single, mut double) = (false, false);
    let bytes = s.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        match b {
            b'\'' if !double => single = !single,
            b'"' if !single => double = !double,
            b'#' if !single && !double && (i == 0 || bytes[i - 1] == b' ') => {
                return s[..i].trim_end();
            }
            _ => {}
        }
    }
    s.trim_end()
}

fn unquote(s: &str) -> &str {
    let s = s.trim();
    if s.len() >= 2
        && ((s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')))
    {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

fn is_block_scalar(v: &str) -> bool {
    matches!(v, "|" | "|-" | "|+" | ">" | ">-" | ">+")
}

fn parse_steps_from_lines(lines: &[&str]) -> Vec<Vec<ParsedStep>> {
    let mut groups: Vec<Vec<ParsedStep>> = Vec::new();
    let mut current_group: Vec<ParsedStep> = Vec::new();
    let mut step_indent: Option<usize> = None;
    let mut with_indent: Option<usize> = None;
    let mut block_indent: Option<usize> = None;
    let mut cur: Option<ParsedStep> = None;

    let flush_step = |cur: &mut Option<ParsedStep>, group: &mut Vec<ParsedStep>| {
        if let Some(s) = cur.take() {
            group.push(s);
        }
    };
    let flush_group = |cur: &mut Option<ParsedStep>,
                       group: &mut Vec<ParsedStep>,
                       groups: &mut Vec<Vec<ParsedStep>>| {
        flush_step(cur, group);
        if !group.is_empty() {
            groups.push(std::mem::take(group));
        }
    };

    for (idx, raw) in lines.iter().enumerate() {
        let line_no = idx + 1;
        let line = raw.trim_end_matches('\r');
        let s = strip_comment(line.trim_start());
        if s.is_empty() {
            continue;
        }
        let ind = indent(line);

        if let Some(bi) = block_indent {
            if ind > bi {
                continue;
            }
            block_indent = None;
        }

        if let Some(si) = step_indent {
            if ind < si {
                flush_group(&mut cur, &mut current_group, &mut groups);
                step_indent = None;
                with_indent = None;
            }
        }

        if let Some(wi) = with_indent {
            if ind <= wi {
                with_indent = None;
            }
        }

        if s == "steps:" {
            flush_group(&mut cur, &mut current_group, &mut groups);
            step_indent = None;
            with_indent = None;
            continue;
        }

        let kv = if let Some(rest) = s.strip_prefix("- ") {
            if STEP_KEYS.iter().any(|k| rest.starts_with(k))
                && (step_indent.is_none() || step_indent == Some(ind))
            {
                flush_step(&mut cur, &mut current_group);
                step_indent = Some(ind);
                with_indent = None;
                cur = Some(ParsedStep {
                    line_no,
                    ..ParsedStep::default()
                });
                rest.trim_start()
            } else {
                continue;
            }
        } else if step_indent.is_some() {
            s
        } else {
            continue;
        };

        let Some(step) = cur.as_mut() else {
            continue;
        };

        if let Some(wi) = with_indent {
            if ind > wi {
                if let Some((k, v)) = kv.split_once(':') {
                    let key = k.trim();
                    let val = v.trim();
                    if is_block_scalar(val) {
                        block_indent = Some(ind);
                    } else {
                        step.with.insert(key.to_string(), unquote(val).to_string());
                    }
                }
                continue;
            }
        }

        if let Some(v) = kv.strip_prefix("uses:") {
            step.uses = unquote(v.trim()).to_string();
        } else if let Some(v) = kv.strip_prefix("if:") {
            let v = v.trim();
            if is_block_scalar(v) {
                block_indent = Some(ind);
            } else {
                step.if_expr = Some(v.to_string());
            }
        } else if kv == "with:" || kv.starts_with("with:") {
            with_indent = Some(ind);
        } else if let Some(v) = kv.strip_prefix("run:") {
            if is_block_scalar(v.trim()) {
                block_indent = Some(ind);
            }
        } else if let Some(v) = kv.strip_prefix("env:") {
            if is_block_scalar(v.trim()) {
                block_indent = Some(ind);
            }
        }
    }

    flush_group(&mut cur, &mut current_group, &mut groups);
    groups
}

fn is_main_save_guard(expr: &str) -> bool {
    let norm = expr
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .replace('"', "'");
    let bare = norm.trim_start_matches("${{").trim_end_matches("}}").trim();
    bare.contains("github.ref == 'refs/heads/main'") && !bare.contains("||")
}

/// Validate `.github/actions/node-toolcache/action.yml`:
/// - defines a key with prefix `node-toolcache-v1`
/// - has at least one `actions/cache@` or `actions/cache/save@` step, and every
///   such save step is guarded by `github.ref == 'refs/heads/main'` without `||`
pub(crate) fn composite_problems(content: &str) -> Vec<(String, String, String)> {
    let mut problems = Vec::new();

    let has_key_prefix = content
        .lines()
        .map(|l| strip_comment(l.trim()))
        .any(|l| !l.is_empty() && l.contains(&format!("{KEY_PREFIX}-")));
    if !has_key_prefix {
        problems.push((
            "missing key prefix".to_string(),
            format!("{KEY_PREFIX}-<os>-<arch>-<version>"),
            format!("node-toolcache composite must use cache key prefix {KEY_PREFIX}"),
        ));
    }

    let lines: Vec<&str> = content.lines().collect();
    let groups = parse_steps_from_lines(&lines);
    let mut save_steps = 0usize;
    for group in &groups {
        for step in group {
            if step.uses.starts_with("actions/cache@")
                || step.uses.starts_with("actions/cache/save@")
            {
                save_steps += 1;
                if !step.if_expr.as_deref().is_some_and(is_main_save_guard) {
                    let found = step
                        .if_expr
                        .as_deref()
                        .map(|v| format!("if: {v}"))
                        .unwrap_or_else(|| "missing if:".to_string());
                    problems.push((
                        found,
                        "if: github.ref == 'refs/heads/main'".to_string(),
                        "node-toolcache save step must be guarded by github.ref == 'refs/heads/main' (save only on main)".to_string(),
                    ));
                }
            }
        }
    }

    if save_steps == 0 {
        problems.push((
            "0 save steps".to_string(),
            "actions/cache@ guarded by github.ref == 'refs/heads/main'".to_string(),
            "node-toolcache composite has no main-only actions/cache save step".to_string(),
        ));
    }

    problems
}

/// Validate one top-level workflow against `.nvmrc`'s exact Node version.
/// Returns `(setup_node_count, vec of (line_no, found, want, why))`.
pub(crate) fn workflow_problems(
    content: &str,
    expected_version: &str,
) -> (usize, Vec<(usize, String, String, String)>) {
    let lines: Vec<&str> = content.lines().collect();
    let groups = parse_steps_from_lines(&lines);
    let mut setup_count = 0usize;
    let mut problems = Vec::new();

    for group in &groups {
        for (idx, step) in group.iter().enumerate() {
            if step.uses.starts_with("actions/setup-node@") {
                setup_count += 1;
                if let Some(lit) = step.with.get("node-version") {
                    problems.push((
                        step.line_no,
                        format!("node-version: {lit}"),
                        "node-version-file: .nvmrc".to_string(),
                        "actions/setup-node must not specify a literal node-version; read from .nvmrc via node-version-file".to_string(),
                    ));
                }
                let preceded_by_composite = idx > 0 && group[idx - 1].uses == COMPOSITE_USES;
                if !preceded_by_composite {
                    problems.push((
                        step.line_no,
                        "missing ./.github/actions/node-toolcache".to_string(),
                        format!("uses: {COMPOSITE_USES} immediately before actions/setup-node"),
                        "every top-level actions/setup-node step must be immediately preceded by ./.github/actions/node-toolcache".to_string(),
                    ));
                }
            } else if step.uses == COMPOSITE_USES {
                match step.with.get("version") {
                    Some(v) if v == expected_version => {}
                    Some(v) => {
                        problems.push((
                            step.line_no,
                            format!("version: {v}"),
                            format!("version: '{expected_version}'"),
                            "node-toolcache version input does not match .nvmrc".to_string(),
                        ));
                    }
                    None => {
                        problems.push((
                            step.line_no,
                            "missing version input".to_string(),
                            format!("version: '{expected_version}'"),
                            "node-toolcache step must pass version equal to .nvmrc".to_string(),
                        ));
                    }
                }
            }
        }
    }

    (setup_count, problems)
}

pub fn check_node_toolcache(ctx: &Context) {
    let canon = match canonical_node_exact(&ctx.root) {
        Ok(v) => v,
        Err(e) => {
            ctx.emit_fail(
                GROUP,
                ".nvmrc",
                "invalid",
                "X.Y.Z",
                &e,
                "set .nvmrc to an exact Node release like 22.21.1",
            );
            return;
        }
    };

    let mut has_failures = false;

    let composite_path = format!("{}/{}", ctx.root, COMPOSITE_REL);
    match fs::read_to_string(&composite_path) {
        Ok(content) => {
            for (found, want, why) in composite_problems(&content) {
                ctx.emit_fail(
                    GROUP,
                    COMPOSITE_REL,
                    &found,
                    &want,
                    &why,
                    "keep node-toolcache-v1 key prefix and guard actions/cache save with if: github.ref == 'refs/heads/main'",
                );
                has_failures = true;
            }
        }
        Err(_) => {
            ctx.emit_fail(
                GROUP,
                COMPOSITE_REL,
                "missing",
                "composite action",
                "node-toolcache composite action is missing",
                "create .github/actions/node-toolcache/action.yml",
            );
            has_failures = true;
        }
    }

    let wf_dir = Path::new(&ctx.workflows_dir);
    let mut workflows: Vec<String> = Vec::new();
    if let Ok(rd) = fs::read_dir(wf_dir) {
        for entry in rd.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.ends_with(".yaml") || name.ends_with(".yml") {
                workflows.push(entry.path().to_string_lossy().to_string());
            }
        }
    }
    workflows.sort();

    let mut total_setup = 0usize;
    for wf in &workflows {
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let rel = ctx.rel(wf);
        let (count, probs) = workflow_problems(&content, &canon);
        total_setup += count;
        for (line_no, found, want, why) in probs {
            ctx.emit_fail(
                GROUP,
                &format!("{rel}:{line_no}"),
                &found,
                &want,
                &why,
                "precede actions/setup-node with ./.github/actions/node-toolcache (version == .nvmrc) and use node-version-file: .nvmrc",
            );
            has_failures = true;
        }
    }

    if total_setup == 0 {
        ctx.emit_fail(
            GROUP,
            ".github/workflows",
            "0 steps",
            ">=1 actions/setup-node",
            "no top-level actions/setup-node steps found — workflow parser or layout may have drifted",
            "verify top-level .github/workflows/*.yaml setup-node usage",
        );
        return;
    }

    if !has_failures {
        ctx.emit_ok(
            GROUP,
            ".github",
            &format!("{total_setup} setup-node @ {canon}"),
            &format!("{KEY_PREFIX} + main-only save"),
            "all top-level setup-node steps use node-toolcache matched to .nvmrc with main-only save",
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_root(tag: &str) -> std::path::PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("node-toolcache-test-{tag}-{nanos}"));
        fs::create_dir_all(dir.join(".github/actions/node-toolcache")).unwrap();
        fs::create_dir_all(dir.join(".github/workflows")).unwrap();
        dir
    }

    const GOOD_COMPOSITE: &str = r#"name: Node toolcache directory
runs:
  using: composite
  steps:
    - id: cache-key
      shell: bash
      run: |
        echo "key=node-toolcache-v1-${RUNNER_OS}-${node_arch}-${NODE_VERSION}" >> "$GITHUB_OUTPUT"
    - id: cache-restore
      if: github.ref != 'refs/heads/main'
      uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
      with:
        path: |
          ${{ steps.cache-key.outputs.tool-dir }}
          ${{ steps.cache-key.outputs.marker }}
        key: ${{ steps.cache-key.outputs.key }}
    - id: cache-save
      if: github.ref == 'refs/heads/main'
      uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
      with:
        path: |
          ${{ steps.cache-key.outputs.tool-dir }}
          ${{ steps.cache-key.outputs.marker }}
        key: ${{ steps.cache-key.outputs.key }}
"#;

    const GOOD_WORKFLOW: &str = r#"jobs:
  verify:
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Restore Node 22.21.1 toolcache
        uses: ./.github/actions/node-toolcache
        with:
          version: '22.21.1'
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version-file: .nvmrc
          package-manager-cache: false
"#;

    #[test]
    fn good_composite_passes() {
        assert_eq!(composite_problems(GOOD_COMPOSITE), Vec::new());
    }

    #[test]
    fn composite_rejects_unguarded_save() {
        let bad = GOOD_COMPOSITE.replace("if: github.ref == 'refs/heads/main'", "if: always()");
        let probs = composite_problems(&bad);
        assert_eq!(probs.len(), 1);
        assert!(probs[0].2.contains("refs/heads/main"));
    }

    #[test]
    fn composite_rejects_or_escape_in_save_guard() {
        let bad = GOOD_COMPOSITE.replace(
            "if: github.ref == 'refs/heads/main'",
            "if: github.ref == 'refs/heads/main' || github.event_name == 'pull_request'",
        );
        let probs = composite_problems(&bad);
        assert_eq!(probs.len(), 1);
    }

    #[test]
    fn composite_rejects_missing_key_prefix() {
        let bad = GOOD_COMPOSITE.replace("node-toolcache-v1-", "node-other-");
        let probs = composite_problems(&bad);
        assert_eq!(probs.len(), 1);
        assert!(probs[0].2.contains("node-toolcache-v1"));
    }

    #[test]
    fn good_workflow_passes() {
        let (count, probs) = workflow_problems(GOOD_WORKFLOW, "22.21.1");
        assert_eq!(count, 1);
        assert_eq!(probs, Vec::new());
    }

    #[test]
    fn workflow_rejects_missing_composite_before_setup_node() {
        let bad = r#"jobs:
  verify:
    steps:
      - uses: actions/checkout@abc
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1
        with:
          node-version-file: .nvmrc
"#;
        let (count, probs) = workflow_problems(bad, "22.21.1");
        assert_eq!(count, 1);
        assert_eq!(probs.len(), 1);
        assert!(probs[0].3.contains("node-toolcache"));
    }

    #[test]
    fn workflow_rejects_intervening_step_between_composite_and_setup_node() {
        let bad = r#"jobs:
  verify:
    steps:
      - uses: ./.github/actions/node-toolcache
        with:
          version: '22.21.1'
      - run: echo something
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1
        with:
          node-version-file: .nvmrc
"#;
        let (_, probs) = workflow_problems(bad, "22.21.1");
        assert_eq!(probs.len(), 1);
        assert!(probs[0].3.contains("immediately preceded"));
    }

    #[test]
    fn workflow_rejects_mismatched_composite_version() {
        let bad = GOOD_WORKFLOW.replace("version: '22.21.1'", "version: '22.23.5'");
        let (_, probs) = workflow_problems(&bad, "22.21.1");
        assert_eq!(probs.len(), 1);
        assert!(probs[0].3.contains(".nvmrc"));
    }

    #[test]
    fn workflow_rejects_literal_node_version() {
        let bad = GOOD_WORKFLOW.replace("node-version-file: .nvmrc", "node-version: '22.21.1'");
        let (_, probs) = workflow_problems(&bad, "22.21.1");
        assert_eq!(probs.len(), 1);
        assert!(probs[0].3.contains("literal node-version"));
    }

    #[test]
    fn check_node_toolcache_end_to_end() {
        let dir = temp_root("e2e");
        fs::write(dir.join(".nvmrc"), "22.21.1\n").unwrap();
        fs::write(
            dir.join(".github/actions/node-toolcache/action.yml"),
            GOOD_COMPOSITE,
        )
        .unwrap();
        fs::write(
            dir.join(".github/workflows/storybook-image.yaml"),
            GOOD_WORKFLOW,
        )
        .unwrap();

        let ctx = Context::for_root(dir.to_str().unwrap());
        check_node_toolcache(&ctx);
        assert!(
            !ctx.overall_fail.get(),
            "rows: {}",
            ctx.rows.get("NODETOOLCACHE")
        );
        assert_eq!(ctx.ok_count.get(), 1);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_node_exact_validates_format() {
        let dir = temp_root("exact");
        fs::write(dir.join(".nvmrc"), "v22.21.1\n").unwrap();
        assert_eq!(
            canonical_node_exact(dir.to_str().unwrap()).unwrap(),
            "22.21.1"
        );
        fs::write(dir.join(".nvmrc"), "22\n").unwrap();
        assert!(canonical_node_exact(dir.to_str().unwrap()).is_err());
        let _ = fs::remove_dir_all(&dir);
    }
}
