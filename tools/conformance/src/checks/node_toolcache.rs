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
//! restores via `./.github/actions/node-toolcache`, sets `node-version-file: .nvmrc`
//! with no literal `node-version`, keeps `.github/workflows/node-toolcache.yaml`
//! present and tied to `.nvmrc`, and saves caches only on `refs/heads/main`
//! under key prefix `node-toolcache-v1`.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use crate::canonical::canonical_node_exact;
use crate::Context;

const GROUP: &str = "nodetoolcache";
const COMPOSITE_REL: &str = ".github/actions/node-toolcache/action.yml";
const COMPOSITE_USES: &str = "./.github/actions/node-toolcache";
const WARMER_REL: &str = ".github/workflows/node-toolcache.yaml";
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
    id: Option<String>,
    uses: String,
    if_expr: Option<String>,
    run: Option<String>,
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
    let mut in_run_block = false;
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
        let ind = indent(line);

        if let Some(bi) = block_indent {
            if line.trim().is_empty() {
                if in_run_block {
                    if let Some(step) = cur.as_mut() {
                        let buf = step.run.get_or_insert_with(String::new);
                        if !buf.is_empty() {
                            buf.push('\n');
                        }
                    }
                }
                continue;
            }
            if ind > bi {
                if in_run_block {
                    if let Some(step) = cur.as_mut() {
                        let buf = step.run.get_or_insert_with(String::new);
                        if !buf.is_empty() {
                            buf.push('\n');
                        }
                        buf.push_str(line);
                    }
                }
                continue;
            }
            block_indent = None;
            in_run_block = false;
        }

        let s = strip_comment(line.trim_start());
        if s.is_empty() {
            continue;
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

        if let Some(v) = kv.strip_prefix("id:") {
            step.id = Some(unquote(v.trim()).to_string());
        } else if let Some(v) = kv.strip_prefix("uses:") {
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
            let v = v.trim();
            if is_block_scalar(v) {
                block_indent = Some(ind);
                in_run_block = true;
                step.run = Some(String::new());
            } else {
                step.run = Some(v.to_string());
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

/// Exact, normalized check for the main-only save guard.
/// Accepts only `github.ref == 'refs/heads/main'` (with optional `${{ ... }}`
/// wrapper and normalized whitespace); rejects negations, `||`, `&&`, `true`, etc.
fn is_main_save_guard(expr: &str) -> bool {
    let trimmed = expr.trim();
    let unwrapped = if let Some(inner) = trimmed.strip_prefix("${{") {
        let Some(inner) = inner.strip_suffix("}}") else {
            return false;
        };
        inner.trim()
    } else {
        trimmed
    };
    let norm = unwrapped.split_whitespace().collect::<Vec<_>>().join(" ");
    norm == "github.ref == 'refs/heads/main'"
}

fn step_output_version_id(expr: &str) -> Option<&str> {
    let inner = expr.trim().strip_prefix("${{")?.strip_suffix("}}")?.trim();
    let rest = inner.strip_prefix("steps.")?;
    let id = rest.strip_suffix(".outputs.version")?;
    if !id.is_empty()
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
    {
        Some(id)
    } else {
        None
    }
}

fn step_reads_nvmrc_version(step: &ParsedStep) -> bool {
    let Some(run) = step.run.as_deref() else {
        return false;
    };
    let active: String = run
        .lines()
        .map(|l| strip_comment(l.trim()))
        .filter(|l| !l.is_empty())
        .collect::<Vec<_>>()
        .join("\n");
    active.contains(".nvmrc") && active.contains("version=") && active.contains("GITHUB_OUTPUT")
}

/// Validate `.github/actions/node-toolcache/action.yml`:
/// - defines a key with prefix `node-toolcache-v1`
/// - has at least one `actions/cache@` or `actions/cache/save@` step, and every
///   such save step is guarded by exact `github.ref == 'refs/heads/main'`
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
                        "node-toolcache save step must be guarded by exact github.ref == 'refs/heads/main' (save only on main)".to_string(),
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
                        "actions/setup-node must not specify a literal node-version; read from .nvmrc via node-version-file: .nvmrc".to_string(),
                    ));
                }
                match step.with.get("node-version-file").map(String::as_str) {
                    Some(".nvmrc") => {}
                    Some(other) => {
                        problems.push((
                            step.line_no,
                            format!("node-version-file: {other}"),
                            "node-version-file: .nvmrc".to_string(),
                            "actions/setup-node must set node-version-file: .nvmrc".to_string(),
                        ));
                    }
                    None => {
                        problems.push((
                            step.line_no,
                            "missing node-version-file".to_string(),
                            "node-version-file: .nvmrc".to_string(),
                            "actions/setup-node must set node-version-file: .nvmrc".to_string(),
                        ));
                    }
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
                        if let Some(step_id) = step_output_version_id(v) {
                            let valid_producer = group[..idx].iter().any(|prev| {
                                prev.id.as_deref() == Some(step_id)
                                    && step_reads_nvmrc_version(prev)
                            });
                            if !valid_producer {
                                problems.push((
                                    step.line_no,
                                    format!("version: {v}"),
                                    format!("version: '{expected_version}' or step reading .nvmrc"),
                                    format!("node-toolcache version references steps.{step_id}.outputs.version, but no earlier step with id '{step_id}' reads .nvmrc into GITHUB_OUTPUT"),
                                ));
                            }
                        } else {
                            problems.push((
                                step.line_no,
                                format!("version: {v}"),
                                format!("version: '{expected_version}'"),
                                "node-toolcache version input does not match .nvmrc".to_string(),
                            ));
                        }
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
    let mut warmer_found = false;
    let mut warmer_setup_count = 0usize;
    for wf in &workflows {
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let rel = ctx.rel(wf);
        let (count, probs) = workflow_problems(&content, &canon);
        total_setup += count;
        if rel == WARMER_REL {
            warmer_found = true;
            warmer_setup_count = count;
        }
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

    if !warmer_found {
        ctx.emit_fail(
            GROUP,
            WARMER_REL,
            "missing",
            "warmer workflow",
            "node-toolcache warmer workflow .github/workflows/node-toolcache.yaml is missing",
            "restore .github/workflows/node-toolcache.yaml so main keeps the Node toolcache warm",
        );
        has_failures = true;
    } else if warmer_setup_count == 0 {
        ctx.emit_fail(
            GROUP,
            WARMER_REL,
            "0 setup-node steps",
            ">=1 actions/setup-node",
            "node-toolcache warmer workflow must run node-toolcache and actions/setup-node for .nvmrc",
            "restore the node-toolcache and actions/setup-node steps in .github/workflows/node-toolcache.yaml",
        );
        has_failures = true;
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
    use std::os::unix::fs::PermissionsExt;
    use std::process::Command;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn unique_temp_dir(tag: &str) -> std::path::PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "node-toolcache-test-{tag}-{}-{id}-{nanos}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn temp_root(tag: &str) -> std::path::PathBuf {
        let dir = unique_temp_dir(tag);
        fs::create_dir_all(dir.join(".github/actions/node-toolcache")).unwrap();
        fs::create_dir_all(dir.join(".github/workflows")).unwrap();
        dir
    }

    fn repo_root() -> Option<std::path::PathBuf> {
        let candidates = [
            std::env::var("BUILD_WORKSPACE_DIRECTORY").ok(),
            std::env::var("TEST_SRCDIR")
                .ok()
                .map(|s| format!("{s}/_main")),
            Some(".".to_string()),
        ];
        candidates
            .into_iter()
            .flatten()
            .map(std::path::PathBuf::from)
            .find(|p| p.join(COMPOSITE_REL).is_file() && p.join(WARMER_REL).is_file())
    }

    fn extract_step_run(content: &str, step_id: &str) -> String {
        let lines: Vec<&str> = content.lines().collect();
        let groups = parse_steps_from_lines(&lines);
        let raw = groups
            .into_iter()
            .flatten()
            .find(|s| s.id.as_deref() == Some(step_id))
            .and_then(|s| s.run)
            .unwrap_or_else(|| panic!("missing run block for step id '{step_id}'"));
        let min_indent = raw
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(indent)
            .min()
            .unwrap_or(0);
        raw.lines()
            .map(|l| {
                if l.len() >= min_indent {
                    &l[min_indent..]
                } else {
                    l.trim_start()
                }
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn write_exec(path: &Path, script: &str) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, script).unwrap();
        let mut perms = fs::metadata(path).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(path, perms).unwrap();
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

    const GOOD_WARMER: &str = r#"jobs:
  warm:
    if: github.ref == 'refs/heads/main' && (github.event_name == 'push' || github.event_name == 'schedule' || github.event_name == 'workflow_dispatch')
    runs-on: ubuntu-26.04
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Read Node version from .nvmrc
        id: nvmrc
        run: |
          raw="$(tr -d '[:space:]' < .nvmrc)"
          version="${raw#v}"
          echo "version=${version}" >> "$GITHUB_OUTPUT"
      - name: Restore Node toolcache
        uses: ./.github/actions/node-toolcache
        with:
          version: ${{ steps.nvmrc.outputs.version }}
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
    fn is_main_save_guard_accepts_only_exact_main_ref() {
        assert!(is_main_save_guard("github.ref == 'refs/heads/main'"));
        assert!(is_main_save_guard("  github.ref   ==   'refs/heads/main' "));
        assert!(is_main_save_guard("${{ github.ref == 'refs/heads/main' }}"));

        assert!(!is_main_save_guard("!(github.ref == 'refs/heads/main')"));
        assert!(!is_main_save_guard(
            "github.ref == 'refs/heads/main' || true"
        ));
        assert!(!is_main_save_guard(
            "github.ref == 'refs/heads/main' && github.event_name == 'push'"
        ));
        assert!(!is_main_save_guard("true"));
        assert!(!is_main_save_guard("always()"));
        assert!(!is_main_save_guard("github.ref != 'refs/heads/main'"));
        assert!(!is_main_save_guard("github.ref == \"refs/heads/main\""));
    }

    #[test]
    fn composite_rejects_unguarded_save() {
        let bad = GOOD_COMPOSITE.replace("if: github.ref == 'refs/heads/main'", "if: always()");
        let probs = composite_problems(&bad);
        assert_eq!(probs.len(), 1);
        assert!(probs[0].2.contains("refs/heads/main"));
    }

    #[test]
    fn composite_rejects_negated_save_guard() {
        let bad = GOOD_COMPOSITE.replace(
            "if: github.ref == 'refs/heads/main'",
            "if: !(github.ref == 'refs/heads/main')",
        );
        let probs = composite_problems(&bad);
        assert_eq!(probs.len(), 1);
        assert!(probs[0].2.contains("refs/heads/main"));
    }

    #[test]
    fn composite_rejects_or_true_save_guard() {
        let bad = GOOD_COMPOSITE.replace(
            "if: github.ref == 'refs/heads/main'",
            "if: github.ref == 'refs/heads/main' || true",
        );
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
    fn good_warmer_passes() {
        let (count, probs) = workflow_problems(GOOD_WARMER, "22.21.1");
        assert_eq!(count, 1);
        assert_eq!(probs, Vec::new());
    }

    #[test]
    fn workflow_requires_node_version_file_nvmrc() {
        let quoted =
            GOOD_WORKFLOW.replace("node-version-file: .nvmrc", "node-version-file: '.nvmrc'");
        let (count, probs) = workflow_problems(&quoted, "22.21.1");
        assert_eq!(count, 1);
        assert_eq!(probs, Vec::new());

        let missing = GOOD_WORKFLOW.replace("          node-version-file: .nvmrc\n", "");
        let (count, probs) = workflow_problems(&missing, "22.21.1");
        assert_eq!(count, 1);
        assert_eq!(probs.len(), 1);
        assert_eq!(probs[0].2, "node-version-file: .nvmrc");

        let wrong = GOOD_WORKFLOW.replace(
            "node-version-file: .nvmrc",
            "node-version-file: package.json",
        );
        let (count, probs) = workflow_problems(&wrong, "22.21.1");
        assert_eq!(count, 1);
        assert_eq!(probs.len(), 1);
        assert_eq!(probs[0].2, "node-version-file: .nvmrc");
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
    fn workflow_rejects_step_output_not_reading_nvmrc() {
        let bad = GOOD_WARMER.replace(
            "          raw=\"$(tr -d '[:space:]' < .nvmrc)\"\n          version=\"${raw#v}\"",
            "          version=\"22.23.5\"",
        );
        let (_, probs) = workflow_problems(&bad, "22.21.1");
        assert_eq!(probs.len(), 1);
        assert!(probs[0].3.contains(".nvmrc"));
    }

    #[test]
    fn workflow_rejects_literal_node_version() {
        let bad = GOOD_WORKFLOW.replace(
            "node-version-file: .nvmrc",
            "node-version-file: .nvmrc\n          node-version: '22.21.1'",
        );
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
        fs::write(
            dir.join(".github/workflows/node-toolcache.yaml"),
            GOOD_WARMER,
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
    fn check_node_toolcache_fails_when_warmer_missing() {
        let dir = temp_root("missing-warmer");
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
        assert!(ctx.overall_fail.get());
        assert!(ctx
            .rows
            .get("NODETOOLCACHE")
            .contains("node-toolcache.yaml"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn check_node_toolcache_fails_when_warmer_has_wrong_version() {
        let dir = temp_root("wrong-warmer-ver");
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
        let bad_warmer = GOOD_WARMER.replace("${{ steps.nvmrc.outputs.version }}", "'22.23.5'");
        fs::write(
            dir.join(".github/workflows/node-toolcache.yaml"),
            bad_warmer,
        )
        .unwrap();

        let ctx = Context::for_root(dir.to_str().unwrap());
        check_node_toolcache(&ctx);
        assert!(ctx.overall_fail.get());
        assert!(ctx
            .rows
            .get("NODETOOLCACHE")
            .contains("node-toolcache.yaml"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_node_exact_validates_format() {
        let dir = temp_root("exact");
        fs::write(dir.join(".nvmrc"), "22.21.1\n").unwrap();
        assert_eq!(
            canonical_node_exact(dir.to_str().unwrap()).unwrap(),
            "22.21.1"
        );
        fs::write(dir.join(".nvmrc"), "v22.21.1\n").unwrap();
        assert_eq!(
            canonical_node_exact(dir.to_str().unwrap()).unwrap(),
            "22.21.1"
        );
        fs::write(dir.join(".nvmrc"), "vv22.21.1\n").unwrap();
        assert!(canonical_node_exact(dir.to_str().unwrap()).is_err());
        fs::write(dir.join(".nvmrc"), "22\n").unwrap();
        assert!(canonical_node_exact(dir.to_str().unwrap()).is_err());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn warmer_nvmrc_step_strips_single_v_and_rejects_vv() {
        let root = repo_root().expect("composite and warmer files in runfiles");
        let warmer = fs::read_to_string(root.join(WARMER_REL)).unwrap();
        let script = extract_step_run(&warmer, "nvmrc");

        let run_with_nvmrc = |tag: &str, content: &str| -> (bool, String) {
            let dir = unique_temp_dir(tag);
            fs::write(dir.join(".nvmrc"), content).unwrap();
            let out_file = dir.join("github_output");
            fs::write(&out_file, "").unwrap();
            let status = Command::new("bash")
                .arg("-c")
                .arg(&script)
                .current_dir(&dir)
                .env("GITHUB_OUTPUT", &out_file)
                .status()
                .unwrap();
            let out = fs::read_to_string(&out_file).unwrap();
            let _ = fs::remove_dir_all(&dir);
            (status.success(), out)
        };

        let (ok_plain, out_plain) = run_with_nvmrc("nvmrc-plain", "22.21.1\n");
        assert!(ok_plain);
        assert_eq!(out_plain.trim(), "version=22.21.1");

        let (ok_v, out_v) = run_with_nvmrc("nvmrc-v", "v22.21.1\n");
        assert!(ok_v);
        assert_eq!(out_v.trim(), "version=22.21.1");

        let (ok_vv, _) = run_with_nvmrc("nvmrc-vv", "vv22.21.1\n");
        assert!(!ok_vv, "vv22.21.1 must be rejected by warmer nvmrc step");
    }

    #[test]
    fn verify_step_harness_cleans_up_and_checks_all_binaries() {
        let root = repo_root().expect("composite and warmer files in runfiles");
        let composite = fs::read_to_string(root.join(COMPOSITE_REL)).unwrap();
        let script = extract_step_run(&composite, "verify");

        let run_verify = |tag: &str,
                          cache_hit: Option<&str>,
                          setup: &dyn Fn(&Path, &Path)|
         -> (String, bool, bool) {
            let work = unique_temp_dir(tag);
            let tool_dir = work.join("toolcache/node/22.21.1/x64");
            let marker = work.join("toolcache/node/22.21.1/x64.complete");
            let out_file = work.join("github_output");
            fs::write(&out_file, "").unwrap();
            setup(&tool_dir, &marker);

            let mut cmd = Command::new("bash");
            cmd.arg("-c")
                .arg(&script)
                .env("TOOL_DIR", &tool_dir)
                .env("MARKER", &marker)
                .env("NODE_VERSION", "22.21.1")
                .env("GITHUB_OUTPUT", &out_file);
            match cache_hit {
                Some(v) => {
                    cmd.env("CACHE_HIT", v);
                }
                None => {
                    cmd.env_remove("CACHE_HIT");
                }
            }
            let status = cmd.status().unwrap();
            assert!(status.success(), "verify script failed on case {tag}");
            let out = fs::read_to_string(&out_file).unwrap();
            let dir_exists = tool_dir.exists() || fs::symlink_metadata(&tool_dir).is_ok();
            let marker_exists = marker.exists() || fs::symlink_metadata(&marker).is_ok();
            let _ = fs::remove_dir_all(&work);
            (out.trim().to_string(), dir_exists, marker_exists)
        };

        let write_good_node = |tool_dir: &Path| {
            write_exec(
                &tool_dir.join("bin/node"),
                "#!/usr/bin/env bash\nif [ \"${1:-}\" = \"--version\" ]; then echo v22.21.1; fi\n",
            );
        };
        let write_good_npm = |tool_dir: &Path| {
            write_exec(
                &tool_dir.join("bin/npm"),
                "#!/usr/bin/env bash\nnode --version >/dev/null\necho 10.9.0\n",
            );
        };
        let write_good_corepack = |tool_dir: &Path| {
            write_exec(
                &tool_dir.join("bin/corepack"),
                "#!/usr/bin/env bash\nnode --version >/dev/null\necho 0.31.0\n",
            );
        };

        // 1. Clean miss: neither dir nor marker exists, cache-hit=false.
        let (out, d, m) = run_verify("clean-miss", Some("false"), &|_, _| {});
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        // 2. Valid cache hit: node, npm, corepack, and .complete marker all present and working.
        let (out, d, m) = run_verify("valid-hit", Some("true"), &|td, mk| {
            write_good_node(td);
            write_good_npm(td);
            write_good_corepack(td);
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=true");
        assert!(d && m);

        // 3. Dir with broken node binary and NO cache-hit flag: deletes BOTH dir and marker.
        let (out, d, m) = run_verify("broken-no-cache-hit", None, &|td, mk| {
            write_exec(&td.join("bin/node"), "#!/usr/bin/env bash\nexit 1\n");
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        // 4. Dir with .complete marker but NO node binary (cache-hit=false and cache-hit=true): deletes BOTH.
        for (tag, hit) in [
            ("marker-no-bin-miss", "false"),
            ("marker-no-bin-hit", "true"),
        ] {
            let (out, d, m) = run_verify(tag, Some(hit), &|td, mk| {
                fs::create_dir_all(td).unwrap();
                fs::write(mk, "").unwrap();
            });
            assert_eq!(out, "usable=false");
            assert!(!d && !m, "{tag}: dir={d}, marker={m}");
        }

        // 5. Standalone .complete marker with no dir and cache-hit=false: deletes marker.
        let (out, d, m) = run_verify("orphan-marker", Some("false"), &|_, mk| {
            fs::create_dir_all(mk.parent().unwrap()).unwrap();
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        // 6. Missing or failing corepack: deletes BOTH dir and marker.
        let (out, d, m) = run_verify("missing-corepack", Some("true"), &|td, mk| {
            write_good_node(td);
            write_good_npm(td);
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        let (out, d, m) = run_verify("failing-corepack", Some("true"), &|td, mk| {
            write_good_node(td);
            write_good_npm(td);
            write_exec(&td.join("bin/corepack"), "#!/usr/bin/env bash\nexit 1\n");
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        // 7. Missing or failing npm: deletes BOTH dir and marker.
        let (out, d, m) = run_verify("missing-npm", Some("true"), &|td, mk| {
            write_good_node(td);
            write_good_corepack(td);
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        let (out, d, m) = run_verify("failing-npm", Some("true"), &|td, mk| {
            write_good_node(td);
            write_exec(&td.join("bin/npm"), "#!/usr/bin/env bash\nexit 1\n");
            write_good_corepack(td);
            fs::write(mk, "").unwrap();
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);

        // 8. Valid binaries but missing .complete marker: deletes dir.
        let (out, d, m) = run_verify("missing-marker", Some("true"), &|td, _| {
            write_good_node(td);
            write_good_npm(td);
            write_good_corepack(td);
        });
        assert_eq!(out, "usable=false");
        assert!(!d && !m);
    }
}
