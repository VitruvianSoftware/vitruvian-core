// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! The live-context hooks.
//!
//! - `PreInvocation` (`bin/inject_live_context.rs`): tells the model the live
//!   Git and GitHub state, plus the user's response contract.
//! - `Stop` (`bin/verify_response_shape.rs`): checks the reply against the
//!   contract, logs a verdict and, in "enforce" mode, bounces it once.
//!
//! The crate uses only the standard library, so `../rust-hook.sh` can build it
//! with a bare `rustc` wherever the plugin is installed.

pub mod json;

use json::{obj, Map, Value};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const DEFAULT_RESPONSE_CONTRACT: &str = "RESPONSE CONTRACT: Scale to the question.\n\
- Simple or factual question: one or two sentences. No headers, no sections.\n\
- Substantive work: GIST first (one or two plain sentences, answer first, no jargon), then DETAIL (how it works, evidence, caveats).\n\
- SURPRISE first: if a finding contradicts what the user expects, or they may have missed it, it goes at the very top.\n\
- CONFIDENCE: mark what you verified versus what you assumed. Never present a guess as a fact.\n\
- CHOICES: give your pick and a one-line why. Alternatives only if they would change the decision.\n\
- DIAGRAM only when it earns its place: a workflow, pipeline, state machine or genuinely complex topic.\n\
- NEXT only when the user must do or decide something, or there is a concrete follow-up. Otherwise end after the detail. Never write 'Nothing needed from you.'";

pub const DEFAULT_REPO: &str = "VitruvianSoftware/vitruvian-core";

/// How old the sidecar's snapshot may be before the hook stops trusting it.
pub const SNAPSHOT_MAX_AGE_MS: f64 = 120_000.0;

/// Said instead of a PR list when GitHub could not be asked.
pub const GITHUB_UNKNOWN: &str = "GitHub state unavailable this turn (gh query failed or timed out).\nTreat all remembered PR/issue status as STALE and re-query before reporting it.";

/// Said instead of the branch line when Git could not be asked.
pub const GIT_UNKNOWN: &str = "LIVE GIT WORKSPACE: unknown this turn (git could not be read for this workspace). Check with git before stating branch or working-tree status.";

const GIT_TIMEOUT: Duration = Duration::from_millis(1500);
const GH_TIMEOUT: Duration = Duration::from_millis(3000);

const FILLER_PHRASES: &[&str] = &[
    "nothing needed from you",
    "nothing for you",
    "no action needed",
    "no action required",
    "no action is needed",
    "no action is required",
    "nothing needed",
    "nothing is needed",
    "nothing else needed",
    "nothing else is needed",
];

/// Resolves the live-context state directory from `STATE_DIR`, `ANTIGRAVITY_APP_DATA_DIR`, or `HOME`.
pub fn resolve_state_dir() -> Option<PathBuf> {
    if let Ok(dir) = env::var("STATE_DIR") {
        if !dir.is_empty() {
            return Some(PathBuf::from(dir));
        }
    }
    if let Ok(app_data) = env::var("ANTIGRAVITY_APP_DATA_DIR") {
        if !app_data.is_empty() {
            return Some(Path::new(&app_data).join("live-context-state"));
        }
    }
    if let Ok(home) = env::var("HOME") {
        if !home.is_empty() {
            return Some(
                Path::new(&home)
                    .join(".gemini")
                    .join("antigravity")
                    .join("live-context-state"),
            );
        }
    }
    None
}

// ---- JavaScript coercions -------------------------------------------------
// The hooks replaced Node.js scripts; these keep their reading of odd input.

/// `String(v)` for a value that is not null or undefined.
fn js_string(v: &Value) -> String {
    match v {
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(_) => v.to_string(),
        Value::String(s) => s.clone(),
        Value::Array(a) => a
            .iter()
            .map(|x| {
                if x.is_null() {
                    String::new()
                } else {
                    js_string(x)
                }
            })
            .collect::<Vec<_>>()
            .join(","),
        Value::Object(_) => "[object Object]".to_string(),
    }
}

/// `String(v ?? fallback)`.
fn js_string_or(v: Option<&Value>, fallback: &str) -> String {
    match v {
        Some(v) if !v.is_null() => js_string(v),
        _ => fallback.to_string(),
    }
}

/// `Number(v ?? fallback)`.
fn js_number_or(v: Option<&Value>, fallback: f64) -> f64 {
    match v {
        None | Some(Value::Null) => fallback,
        Some(Value::Bool(b)) => f64::from(u8::from(*b)),
        Some(Value::Number(n)) => *n,
        Some(Value::String(s)) => {
            let t = js_trim(s);
            if t.is_empty() {
                0.0
            } else {
                t.parse::<f64>().unwrap_or(f64::NAN)
            }
        }
        Some(Value::Array(a)) if a.is_empty() => 0.0,
        Some(Value::Array(a)) if a.len() == 1 => js_number_or(Some(&a[0]), 0.0),
        Some(_) => f64::NAN,
    }
}

/// JavaScript truthiness.
fn js_truthy(v: Option<&Value>) -> bool {
    match v {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => *n != 0.0 && !n.is_nan(),
        Some(Value::String(s)) => !s.is_empty(),
        Some(_) => true,
    }
}

/// `String.prototype.trim`.
fn js_trim(s: &str) -> &str {
    s.trim_matches(|c: char| c.is_whitespace() || c == '\u{FEFF}')
}

/// The last `n` UTF-16 code units of `s`, as `s.slice(-n)` would give.
fn js_slice_tail(s: &str, n: usize) -> String {
    let units: Vec<u16> = s.encode_utf16().collect();
    String::from_utf16_lossy(&units[units.len().saturating_sub(n)..])
}

/// The first `n` UTF-16 code units of `s`, as `s.slice(0, n)` would give.
fn js_slice_head(s: &str, n: usize) -> String {
    let units: Vec<u16> = s.encode_utf16().take(n).collect();
    String::from_utf16_lossy(&units)
}

/// A value in a template literal: `${v}`.
fn val_to_string(v: Option<&Value>) -> String {
    match v {
        Some(v) => js_string(v),
        None => "undefined".to_string(),
    }
}

// ---- The PreInvocation message -------------------------------------------

/// Formats live local Git state and GitHub open/merged pull requests into a concise context block.
pub fn format_live_git_summary(
    git: Option<&Map>,
    github: Option<&Map>,
    include_git: bool,
    include_github: bool,
) -> String {
    let mut sections = Vec::new();

    if include_git {
        if let Some(g) = git {
            if js_truthy(g.get("branch")) || js_truthy(g.get("headSha")) {
                let branch = if js_truthy(g.get("branch")) {
                    js_string(&g["branch"])
                } else {
                    "detached".to_string()
                };
                let sha = if js_truthy(g.get("headSha")) {
                    format!(" ({})", js_string(&g["headSha"]))
                } else {
                    String::new()
                };
                let dirty = js_number_or(g.get("dirtyCount"), 0.0);
                let dirty_desc = if dirty > 0.0 {
                    let plural = if dirty == 1.0 { "" } else { "s" };
                    let files_suffix = match g.get("dirtyFiles").and_then(|v| v.as_array()) {
                        Some(arr) if !arr.is_empty() => {
                            let names: Vec<String> = arr
                                .iter()
                                .take(5)
                                .map(|x| {
                                    if x.is_null() {
                                        String::new()
                                    } else {
                                        js_string(x)
                                    }
                                })
                                .collect();
                            format!(": {}", names.join(", "))
                        }
                        _ => String::new(),
                    };
                    format!(
                        "{} uncommitted file{plural}{files_suffix}",
                        Value::Number(dirty)
                    )
                } else {
                    "clean working tree".to_string()
                };
                sections.push(format!(
                    "LIVE GIT WORKSPACE: branch {branch}{sha} · {dirty_desc}"
                ));
            }
        }
    }

    if include_github {
        if let Some(gh) = github {
            let repo = if js_truthy(gh.get("repo")) {
                js_string(&gh["repo"])
            } else {
                DEFAULT_REPO.to_string()
            };
            if js_truthy(gh.get("unavailable")) {
                sections.push(GITHUB_UNKNOWN.to_string());
            } else {
                let open_lines = match gh.get("openPrs").and_then(|v| v.as_array()) {
                    Some(arr) if !arr.is_empty() => arr
                        .iter()
                        .map(|pr| {
                            let num = val_to_string(pr.get("number"));
                            let draft = if js_truthy(pr.get("isDraft")) {
                                " [draft]"
                            } else {
                                ""
                            };
                            let title = val_to_string(pr.get("title"));
                            format!("  #{num}{draft} {title}")
                        })
                        .collect::<Vec<_>>()
                        .join("\n"),
                    _ => "  (none)".to_string(),
                };

                let merged_lines = match gh.get("mergedPrs").and_then(|v| v.as_array()) {
                    Some(arr) if !arr.is_empty() => arr
                        .iter()
                        .map(|pr| {
                            let num = val_to_string(pr.get("number"));
                            let title = val_to_string(pr.get("title"));
                            let suffix = if js_truthy(pr.get("mergedAt")) {
                                format!("  (merged {})", js_string(&pr["mergedAt"]))
                            } else {
                                String::new()
                            };
                            format!("  #{num} {title}{suffix}")
                        })
                        .collect::<Vec<_>>()
                        .join("\n"),
                    _ => "  (none)".to_string(),
                };

                let issue_count = match gh.get("openIssues") {
                    Some(v) if !v.is_null() => js_string(v),
                    _ => "?".to_string(),
                };

                sections.push(format!(
                    "LIVE {repo} state, fetched just now — this SUPERSEDES any PR/issue status stated earlier in this conversation. Do not restate status from earlier turns; if something you are about to report is not reflected here, re-query it.\n\nOPEN PRs:\n{open_lines}\n\nRECENTLY MERGED PRs (last 10):\n{merged_lines}\n\nOPEN issues: {issue_count}"
                ));
            }
        }
    }

    js_trim(&sections.join("\n\n")).to_string()
}

/// Builds the Antigravity `PreInvocation` JSON output payload.
pub fn build_ephemeral_context_payload(
    git: Option<&Map>,
    github: Option<&Map>,
    settings: Option<&Map>,
) -> Value {
    build_payload(git, github, settings, false)
}

fn build_payload(
    git: Option<&Map>,
    github: Option<&Map>,
    settings: Option<&Map>,
    git_unknown: bool,
) -> Value {
    let empty = Map::new();
    let s = settings.unwrap_or(&empty);
    let inject_git = s.get("injectGit") != Some(&Value::Bool(false));
    let inject_github = s.get("injectGitHub") != Some(&Value::Bool(false));
    let inject_contract = s.get("injectContract") != Some(&Value::Bool(false));
    let contract_text = js_trim(&js_string_or(
        s.get("contractText"),
        DEFAULT_RESPONSE_CONTRACT,
    ))
    .to_string();

    let mut blocks = Vec::new();
    if inject_git && git_unknown {
        blocks.push(GIT_UNKNOWN.to_string());
    }
    if inject_git || inject_github {
        let live_summary = format_live_git_summary(
            Some(git.unwrap_or(&empty)),
            Some(github.unwrap_or(&empty)),
            inject_git && !git_unknown,
            inject_github,
        );
        if !live_summary.is_empty() {
            blocks.push(live_summary);
        }
    }

    if inject_contract && !contract_text.is_empty() {
        blocks.push(contract_text);
    }

    if blocks.is_empty() {
        return Value::Object(Map::new());
    }

    obj([(
        "injectSteps",
        Value::Array(vec![obj([(
            "ephemeralMessage",
            Value::from(blocks.join("\n\n---\n\n")),
        )])]),
    )])
}

// ---- Asking git and gh ----------------------------------------------------

/// Runs a program and returns its stdout if it exits 0 within `timeout`.
///
/// Signature of the probe the hook uses, so tests can stand in for git and gh:
/// `(program, args, working directory, timeout)`.
pub type Runner<'a> = dyn Fn(&str, &[&str], Option<&Path>, Duration) -> Option<String> + Sync + 'a;

/// The real [`Runner`]: spawns the program, kills it at the deadline.
pub fn run_command(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
    timeout: Duration,
) -> Option<String> {
    let mut cmd = Command::new(program);
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    let mut child = cmd.spawn().ok()?;
    let mut stdout = child.stdout.take()?;
    let reader = thread::spawn(move || {
        let mut out = String::new();
        let _ = stdout.read_to_string(&mut out);
        out
    });
    let deadline = Instant::now() + timeout;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let out = reader.join().ok()?;
                return status.success().then_some(out);
            }
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(10)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
        }
    }
}

/// Reads branch, HEAD and the dirty files of the repository at `workspace`.
/// `None` when it is not a repository or git did not answer in time.
pub fn probe_git(workspace: &Path, run: &Runner<'_>) -> Option<Map> {
    let (branch, sha, status) = thread::scope(|s| {
        let branch = s.spawn(|| {
            run(
                "git",
                &["rev-parse", "--abbrev-ref", "HEAD"],
                Some(workspace),
                GIT_TIMEOUT,
            )
        });
        let sha = s.spawn(|| {
            run(
                "git",
                &["rev-parse", "--short", "HEAD"],
                Some(workspace),
                GIT_TIMEOUT,
            )
        });
        let status = s.spawn(|| {
            run(
                "git",
                &["status", "--porcelain"],
                Some(workspace),
                GIT_TIMEOUT,
            )
        });
        (
            branch.join().ok().flatten(),
            sha.join().ok().flatten(),
            status.join().ok().flatten(),
        )
    });
    let sha = sha?;
    let status = status?;
    let branch = branch.unwrap_or_default();
    let branch = branch.trim();
    // `--abbrev-ref` prints HEAD when detached; the summary says "detached".
    let branch = if branch == "HEAD" { "" } else { branch };
    let lines: Vec<&str> = status.lines().filter(|l| !l.trim().is_empty()).collect();
    // Porcelain v1 lines are "XY path": the path starts at column 3.
    let files: Vec<Value> = lines
        .iter()
        .take(8)
        .map(|l| Value::from(l.get(3..).unwrap_or("").trim()))
        .collect();
    Some(
        [
            ("branch", Value::from(branch)),
            ("headSha", Value::from(sha.trim())),
            ("dirtyCount", Value::from(lines.len())),
            ("dirtyFiles", Value::Array(files)),
        ]
        .into_iter()
        .collect(),
    )
}

/// Asks `gh` for the open and recently merged PRs and the open issue count.
/// Any failure gives `{repo, unavailable: true}`, never an empty PR list.
pub fn probe_github(repo: &str, run: &Runner<'_>) -> Map {
    let (open, merged, issues) = thread::scope(|s| {
        let gh = |args: Vec<&'static str>| {
            move || {
                let mut full: Vec<&str> = vec![args[0], args[1], "--repo", repo];
                full.extend_from_slice(&args[2..]);
                run("gh", &full, None, GH_TIMEOUT)
            }
        };
        let open = s.spawn(gh(vec![
            "pr",
            "list",
            "--state",
            "open",
            "--limit",
            "20",
            "--json",
            "number,title,isDraft",
        ]));
        let merged = s.spawn(gh(vec![
            "pr",
            "list",
            "--state",
            "merged",
            "--limit",
            "10",
            "--json",
            "number,title,mergedAt",
        ]));
        let issues = s.spawn(gh(vec![
            "issue", "list", "--state", "open", "--limit", "100", "--json", "number",
        ]));
        (
            open.join().ok().flatten(),
            merged.join().ok().flatten(),
            issues.join().ok().flatten(),
        )
    });
    let parse_list = |out: Option<String>| -> Option<Vec<Value>> {
        let out = out?;
        let text = if out.trim().is_empty() { "[]" } else { &out };
        match json::parse(text) {
            Ok(Value::Array(a)) => Some(a),
            _ => None,
        }
    };
    let mut gh = Map::new();
    gh.insert("repo", repo);
    match (parse_list(open), parse_list(merged), parse_list(issues)) {
        (Some(open), Some(merged), Some(issues)) => {
            gh.insert("openPrs", Value::Array(open));
            gh.insert("mergedPrs", Value::Array(merged));
            gh.insert("openIssues", issues.len());
        }
        _ => gh.insert("unavailable", true),
    }
    gh
}

/// When the snapshot was written, in milliseconds since the epoch. The panel
/// writes `updatedAt`; `updatedAtMs` is accepted too.
pub fn snapshot_updated_ms(snapshot: &Map) -> Option<f64> {
    ["updatedAtMs", "updatedAt"]
        .iter()
        .filter_map(|k| snapshot.get(k).and_then(Value::as_f64))
        .find(|ms| *ms > 0.0)
}

/// Whether the snapshot is young enough to serve as "live" state.
pub fn snapshot_is_fresh(snapshot: &Map, now_ms: f64) -> bool {
    match snapshot_updated_ms(snapshot) {
        // A little slack for a clock that moved backwards; never years.
        Some(ms) => {
            let age = now_ms - ms;
            (-5_000.0..=SNAPSHOT_MAX_AGE_MS).contains(&age)
        }
        None => false,
    }
}

fn now_ms() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as f64)
        .unwrap_or(0.0)
}

fn read_json_obj(dir: Option<&Path>, name: &str) -> Map {
    dir.and_then(|d| fs::read_to_string(d.join(name)).ok())
        .and_then(|raw| json::parse_object(&raw))
        .unwrap_or_default()
}

/// Writes `value` to `path` through a temporary file, so a reader never sees
/// half of it.
fn write_atomically(path: &Path, value: &Value) {
    let Some(dir) = path.parent() else { return };
    if fs::create_dir_all(dir).is_err() {
        return;
    }
    let tmp = dir.join(format!(
        ".{}.{}.tmp",
        path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("snapshot"),
        std::process::id()
    ));
    if fs::write(&tmp, format!("{}\n", value.to_string_pretty())).is_ok()
        && fs::rename(&tmp, path).is_err()
    {
        let _ = fs::remove_file(&tmp);
    }
}

/// The workspace the conversation is about: the first of `workspacePaths`.
fn workspace_from_payload(payload: &Map) -> Option<PathBuf> {
    let first = payload
        .get("workspacePaths")
        .and_then(Value::as_array)
        .and_then(|a| a.first())
        .and_then(Value::as_str)?;
    let path = first.strip_prefix("file://").unwrap_or(first);
    (!path.is_empty()).then(|| PathBuf::from(path))
}

/// Executes the PreInvocation hook.
///
/// Git state is read from the conversation's workspace every turn; it is
/// local and fast. GitHub state comes from the panel's snapshot only while
/// that is under [`SNAPSHOT_MAX_AGE_MS`] old and for the configured repo;
/// otherwise the hook asks `gh` itself and refreshes the snapshot. When
/// neither works the message says the state is unknown: an old or missing
/// snapshot must never read as "no open PRs".
pub fn run_inject_live_context(
    payload: &str,
    state_dir: Option<&Path>,
    now_ms: f64,
    run: &Runner<'_>,
) -> String {
    let payload = json::parse_object(payload).unwrap_or_default();
    let settings = read_json_obj(state_dir, "settings.json");
    let snapshot = read_json_obj(state_dir, "snapshot.json");
    let fresh = snapshot_is_fresh(&snapshot, now_ms);
    let inject_git = settings.get("injectGit") != Some(&Value::Bool(false));
    let inject_github = settings.get("injectGitHub") != Some(&Value::Bool(false));
    let repo = settings
        .get("repo")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|r| !r.is_empty())
        .unwrap_or(DEFAULT_REPO)
        .to_string();
    let workspace = workspace_from_payload(&payload);

    let snapshot_git = snapshot.get("git").and_then(Value::as_object);
    let snapshot_github = snapshot.get("github").and_then(Value::as_object);
    // The cached GitHub state is usable only if fresh, for this repo, and a
    // real answer (it has a PR list, or says it is unavailable).
    let cached_github = snapshot_github.filter(|gh| {
        fresh
            && gh
                .get("repo")
                .and_then(Value::as_str)
                .unwrap_or(DEFAULT_REPO)
                == repo
            && (gh.get("openPrs").and_then(Value::as_array).is_some()
                || js_truthy(gh.get("unavailable")))
    });

    let need_github = inject_github && cached_github.is_none();
    let (live_git, live_github) = thread::scope(|s| {
        let git = s.spawn(|| match (&workspace, inject_git) {
            (Some(ws), true) => probe_git(ws, run),
            _ => None,
        });
        let gh = s.spawn(|| need_github.then(|| probe_github(&repo, run)));
        (git.join().ok().flatten(), gh.join().ok().flatten())
    });

    let git: Option<Map> = match live_git {
        Some(g) => Some(g),
        // No workspace in the payload: the panel's reading, if fresh.
        None if workspace.is_none() && fresh => snapshot_git.cloned(),
        None => None,
    };
    let git_unknown = inject_git && git.is_none();

    let github: Option<Map> = match &live_github {
        Some(gh) => Some(gh.clone()),
        None => cached_github.cloned(),
    };

    // Share a good answer with the panel and the next turns.
    if let (Some(gh), Some(dir)) = (&live_github, state_dir) {
        if !js_truthy(gh.get("unavailable")) {
            let mut next = Map::new();
            next.insert("updatedAt", now_ms);
            next.insert(
                "git",
                git.clone()
                    .map(Value::Object)
                    .or_else(|| snapshot_git.cloned().map(Value::Object))
                    .unwrap_or_else(|| Value::Object(Map::new())),
            );
            next.insert("github", Value::Object(gh.clone()));
            write_atomically(&dir.join("snapshot.json"), &Value::Object(next));
        }
    }

    build_payload(git.as_ref(), github.as_ref(), Some(&settings), git_unknown).to_string()
}

/// [`run_inject_live_context`] with the real clock and the real git and gh.
pub fn run_inject_live_context_now(payload: &str, state_dir: Option<&Path>) -> String {
    run_inject_live_context(payload, state_dir, now_ms(), &run_command)
}

// ---- The Stop check -------------------------------------------------------

fn strip_fenced_code_blocks(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(start) = rest.find("```") {
        out.push_str(&rest[..start]);
        let after_open = &rest[start + 3..];
        if let Some(end) = after_open.find("```") {
            rest = &after_open[end + 3..];
        } else {
            out.push_str(&rest[start..]);
            return out;
        }
    }
    out.push_str(rest);
    out
}

fn strip_inline_code_and_quotes(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let closing = match c {
            '`' => Some('`'),
            '"' => Some('"'),
            '\'' => Some('\''),
            '\u{201c}' => Some('\u{201d}'),
            _ => None,
        };
        if let Some(close_ch) = closing {
            if let Some(rel_end) = chars[i + 1..].iter().position(|&ch| ch == close_ch) {
                i += 1 + rel_end + 1;
                continue;
            }
        }
        out.push(c);
        i += 1;
    }
    out
}

fn has_word_boundary_after(haystack_lower: &str, needle: &str) -> bool {
    let mut rest = haystack_lower;
    while let Some(idx) = rest.find(needle) {
        let after = &rest[idx + needle.len()..];
        let next_ch = after.chars().next();
        let is_word_char = next_ch
            .map(|c| c.is_ascii_alphanumeric() || c == '_')
            .unwrap_or(false);
        if !is_word_char {
            return true;
        }
        rest = &rest[idx + needle.len()..];
    }
    false
}

fn contains_diagram_marker(msg: &str) -> bool {
    let lower = msg.to_ascii_lowercase();
    lower.contains("show_widget")
        || has_word_boundary_after(&lower, "```mermaid")
        || has_word_boundary_after(&lower, "<agent-embed")
}

#[derive(Debug, Clone, PartialEq)]
pub struct ContractCheckResult {
    pub exempt: bool,
    pub chars: usize,
    pub has_filler: bool,
    pub has_diagram: Option<bool>,
    pub long_no_diagram: bool,
    pub final_line: String,
    pub failures: Vec<String>,
    pub valid: bool,
}

/// Checks an assistant reply against the response shape contract.
pub fn check_response_contract(
    message: &str,
    min_chars: Option<usize>,
    diagram_min_chars: Option<usize>,
) -> ContractCheckResult {
    check_contract(
        message,
        min_chars.map_or(300.0, |n| n as f64),
        diagram_min_chars.map_or(2600.0, |n| n as f64),
    )
}

/// The check with JavaScript's numeric thresholds: `NaN` exempts nothing.
fn check_contract(message: &str, min_chars: f64, diagram_min_chars: f64) -> ContractCheckResult {
    let msg = js_trim(message);
    let chars = msg.encode_utf16().count();

    if (chars as f64) < min_chars {
        return ContractCheckResult {
            exempt: true,
            chars,
            has_filler: false,
            has_diagram: None,
            long_no_diagram: false,
            final_line: String::new(),
            failures: Vec::new(),
            valid: true,
        };
    }

    let has_diagram = if (chars as f64) >= diagram_min_chars {
        Some(contains_diagram_marker(msg))
    } else {
        None
    };
    let long_no_diagram = has_diagram == Some(false);

    let without_code = strip_fenced_code_blocks(msg);
    let raw_last_line = without_code
        .lines()
        .map(js_trim)
        .filter(|l| !l.is_empty())
        .next_back()
        .unwrap_or("")
        .to_string();

    let stripped_last_line = strip_inline_code_and_quotes(&raw_last_line).to_ascii_lowercase();
    let has_filler = FILLER_PHRASES
        .iter()
        .any(|phrase| stripped_last_line.contains(phrase));

    let mut failures = Vec::new();
    if has_filler {
        failures.push(
            "closes with an empty 'nothing needed' line -- end after the detail instead; only add a next step when there is a real one"
                .to_string(),
        );
    }

    let valid = failures.is_empty();
    ContractCheckResult {
        exempt: false,
        chars,
        has_filler,
        has_diagram,
        long_no_diagram,
        final_line: raw_last_line,
        failures,
        valid,
    }
}

fn format_iso8601_now() -> String {
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = dur.as_secs() as i64;
    let millis = dur.subsec_millis();

    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    let hour = rem / 3600;
    let minute = (rem % 3600) / 60;
    let second = rem % 60;

    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm)
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u32;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };

    format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z")
}

#[derive(Debug, Clone, PartialEq)]
pub struct VerdictLogRecord {
    pub ts: String,
    pub conversation_id: String,
    pub mode: String,
    pub chars: usize,
    pub filler: bool,
    pub diagram: Option<bool>,
    pub long_no_diagram: bool,
    pub verdict: String,
    pub tail: String,
}

impl VerdictLogRecord {
    /// One `verdicts.jsonl` line, keys in the order the panel has always read.
    pub fn to_json(&self) -> Value {
        obj([
            ("ts", Value::from(self.ts.as_str())),
            ("conversationId", Value::from(self.conversation_id.as_str())),
            ("mode", Value::from(self.mode.as_str())),
            ("chars", Value::from(self.chars)),
            ("filler", Value::from(self.filler)),
            ("diagram", Value::from(self.diagram)),
            ("longNoDiagram", Value::from(self.long_no_diagram)),
            ("verdict", Value::from(self.verdict.as_str())),
            ("tail", Value::from(self.tail.as_str())),
        ])
    }
}

#[derive(Debug, Clone)]
pub struct StopEvaluationResult {
    pub output: Value,
    pub bounced: bool,
    pub log_record: Option<VerdictLogRecord>,
}

/// Evaluates an Antigravity `Stop` hook event.
pub fn evaluate_stop_shape(
    stop_event: &Map,
    mode_opt: Option<&str>,
    min_chars: Option<usize>,
    diagram_min_chars: Option<usize>,
    now_iso: Option<&str>,
) -> StopEvaluationResult {
    evaluate_stop(
        stop_event,
        mode_opt,
        min_chars.map_or(300.0, |n| n as f64),
        diagram_min_chars.map_or(2600.0, |n| n as f64),
        now_iso,
    )
}

fn allow() -> Value {
    obj([("decision", Value::from("allow"))])
}

fn evaluate_stop(
    stop_event: &Map,
    mode_opt: Option<&str>,
    min_chars: f64,
    diagram_min_chars: f64,
    now_iso: Option<&str>,
) -> StopEvaluationResult {
    let mode = if mode_opt == Some("enforce") {
        "enforce"
    } else {
        "log"
    };
    let execution_num = js_number_or(stop_event.get("executionNum"), 1.0);
    let reason = js_string_or(stop_event.get("terminationReason"), "NO_TOOL_CALL");
    let stop_hook_active = stop_event.get("stopHookActive") == Some(&Value::Bool(true));

    // Never bounce more than once per turn, or on abnormal termination reasons.
    if stop_hook_active || execution_num > 1.0 || (!reason.is_empty() && reason != "NO_TOOL_CALL") {
        return StopEvaluationResult {
            output: allow(),
            bounced: false,
            log_record: None,
        };
    }

    let last_msg = js_string_or(stop_event.get("lastAssistantMessage"), "");

    let check = check_contract(&last_msg, min_chars, diagram_min_chars);
    if check.exempt {
        return StopEvaluationResult {
            output: allow(),
            bounced: false,
            log_record: None,
        };
    }

    let msg_trimmed = js_trim(&last_msg);
    let tail = js_slice_tail(msg_trimmed, 120).replace('\n', " ");
    let conv_id = js_slice_head(&js_string_or(stop_event.get("conversationId"), ""), 8);
    let ts = now_iso
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .unwrap_or_else(format_iso8601_now);

    let log_record = VerdictLogRecord {
        ts,
        conversation_id: conv_id,
        mode: mode.to_string(),
        chars: check.chars,
        filler: check.has_filler,
        diagram: check.has_diagram,
        long_no_diagram: check.long_no_diagram,
        verdict: if check.valid { "pass" } else { "block" }.to_string(),
        tail,
    };

    if !check.valid && mode == "enforce" {
        return StopEvaluationResult {
            output: obj([
                ("decision", Value::from("continue")),
                (
                    "reason",
                    Value::from(format!(
                        "RESPONSE CONTRACT: {}. Revise once; keep the evidence, cut the padding.",
                        check.failures.join("; ")
                    )),
                ),
            ]),
            bounced: true,
            log_record: Some(log_record),
        };
    }

    StopEvaluationResult {
        output: allow(),
        bounced: false,
        log_record: Some(log_record),
    }
}

/// The last `PLANNER_RESPONSE` in a transcript, read from the end and
/// stopping at the first line that is not JSON.
fn last_planner_response(transcript: &str) -> Option<String> {
    for line in js_trim(transcript).lines().rev() {
        let step = json::parse(line).ok()?;
        let step_type = js_string_or(step.get("type"), "").to_uppercase();
        if step_type == "PLANNER_RESPONSE" && js_truthy(step.get("content")) {
            return Some(js_string(&step["content"]));
        }
    }
    None
}

/// Runs the Stop hook against `payload` and `state_dir`.
pub fn run_verify_response_shape(payload: &str, state_dir: Option<&Path>) -> String {
    run_verify_response_shape_at(payload, state_dir, None)
}

fn run_verify_response_shape_at(
    payload: &str,
    state_dir: Option<&Path>,
    now_iso: Option<&str>,
) -> String {
    let Ok(parsed) = json::parse(payload) else {
        return allow().to_string();
    };
    // JSON that is not an object reads as an event with no fields.
    let mut ev = parsed.as_object().cloned().unwrap_or_default();

    let settings = state_dir
        .and_then(|d| fs::read_to_string(d.join("settings.json")).ok())
        .and_then(|raw| json::parse(&raw).ok());
    let (mode, min_chars) = match &settings {
        Some(s @ Value::Object(_)) => (
            if js_truthy(s.get("mode")) {
                js_string(&s["mode"])
            } else {
                "log".to_string()
            },
            js_number_or(s.get("minChars"), 300.0),
        ),
        _ => ("log".to_string(), 300.0),
    };

    let mut last_assistant_message = js_string_or(ev.get("lastAssistantMessage"), "");
    if last_assistant_message.is_empty() {
        if let Some(tp) = ev.get("transcriptPath").and_then(Value::as_str) {
            if let Ok(content) = fs::read_to_string(tp) {
                if let Some(found) = last_planner_response(&content) {
                    last_assistant_message = found;
                }
            }
        }
    }
    ev.insert("lastAssistantMessage", last_assistant_message);

    let result = evaluate_stop(&ev, Some(&mode), min_chars, 2600.0, now_iso);

    if let (Some(log_rec), Some(dir)) = (&result.log_record, state_dir) {
        if !dir.as_os_str().is_empty() && fs::create_dir_all(dir).is_ok() {
            if let Ok(mut file) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(dir.join("verdicts.jsonl"))
            {
                let _ = writeln!(file, "{}", log_rec.to_json());
            }
        }
    }

    result.output.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;

    fn map(src: &str) -> Map {
        json::parse_object(src).expect("test JSON is an object")
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "live-context-{name}-{}-{:?}",
            std::process::id(),
            thread::current().id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn message(out: &str) -> String {
        json::parse(out).unwrap()["injectSteps"][0]["ephemeralMessage"]
            .as_str()
            .unwrap_or("")
            .to_string()
    }

    const NOW: f64 = 1_800_000_000_000.0;

    /// Answers git and gh like a healthy repository with PR #7 open.
    struct FakeTools {
        calls: Mutex<Vec<String>>,
        gh_ok: bool,
        git_ok: bool,
    }

    impl FakeTools {
        fn new(git_ok: bool, gh_ok: bool) -> Self {
            Self {
                calls: Mutex::new(Vec::new()),
                gh_ok,
                git_ok,
            }
        }
        fn gh_calls(&self) -> usize {
            self.calls
                .lock()
                .unwrap()
                .iter()
                .filter(|c| c.starts_with("gh "))
                .count()
        }
        fn run(&self, program: &str, args: &[&str], _cwd: Option<&Path>) -> Option<String> {
            let line = format!("{program} {}", args.join(" "));
            self.calls.lock().unwrap().push(line.clone());
            match program {
                "git" if self.git_ok => Some(
                    match args {
                        ["rev-parse", "--abbrev-ref", _] => "feat/x\n",
                        ["rev-parse", "--short", _] => "abc1234\n",
                        ["status", ..] => " M src/a.rs\n?? new.txt\n",
                        _ => "",
                    }
                    .to_string(),
                ),
                "gh" if self.gh_ok => Some(
                    if line.contains("--state open") && line.starts_with("gh pr") {
                        r#"[{"number":7,"title":"Live PR","isDraft":false}]"#
                    } else if line.contains("merged") {
                        r#"[{"number":6,"title":"Old PR","mergedAt":"2026-11-01T00:00:00Z"}]"#
                    } else {
                        r#"[{"number":1},{"number":2}]"#
                    }
                    .to_string(),
                ),
                _ => None,
            }
        }
    }

    fn inject(dir: &Path, payload: &str, tools: &FakeTools) -> String {
        let run = |p: &str, a: &[&str], c: Option<&Path>, _t: Duration| tools.run(p, a, c);
        run_inject_live_context(payload, Some(dir), NOW, &run)
    }

    const PAYLOAD: &str = r#"{"conversationId":"c1","workspacePaths":["/work/repo"]}"#;

    const SNAPSHOT_EMPTY: &str = r#"{"git":{"branch":"main","headSha":"old0000","dirtyCount":0},"github":{"repo":"VitruvianSoftware/vitruvian-core","openPrs":[],"mergedPrs":[],"openIssues":0}}"#;

    fn write_snapshot(dir: &Path, updated_at: f64) {
        let mut snap = map(SNAPSHOT_EMPTY);
        snap.insert("updatedAt", updated_at);
        fs::write(dir.join("snapshot.json"), Value::Object(snap).to_string()).unwrap();
    }

    #[test]
    fn stale_snapshot_is_not_served_and_failure_says_unknown() {
        // The bug: a days-old snapshot with no open PRs was injected as
        // "OPEN PRs: (none)". When gh cannot be reached either, the state is
        // unknown, and the message must say so.
        let dir = temp_dir("stale-unknown");
        write_snapshot(&dir, NOW - 3.0 * 86_400_000.0);
        let tools = FakeTools::new(false, false);
        let msg = message(&inject(&dir, PAYLOAD, &tools));
        assert!(!msg.contains("(none)"), "stale snapshot served:\n{msg}");
        assert!(msg.contains(GITHUB_UNKNOWN), "{msg}");
        assert!(msg.contains(GIT_UNKNOWN), "{msg}");
        assert!(!msg.contains("old0000"), "stale git served:\n{msg}");
        assert_eq!(tools.gh_calls(), 3);
    }

    #[test]
    fn stale_snapshot_is_refreshed_from_gh_and_git() {
        let dir = temp_dir("stale-refresh");
        write_snapshot(&dir, NOW - 121_000.0);
        let tools = FakeTools::new(true, true);
        let msg = message(&inject(&dir, PAYLOAD, &tools));
        assert!(msg.contains("  #7 Live PR"), "{msg}");
        assert!(msg.contains("OPEN issues: 2"), "{msg}");
        assert!(
            msg.contains("branch feat/x (abc1234) · 2 uncommitted files: src/a.rs, new.txt"),
            "{msg}"
        );
        // The refreshed state is written back for the panel and later turns.
        let snap = json::parse(&fs::read_to_string(dir.join("snapshot.json")).unwrap()).unwrap();
        assert_eq!(snap["updatedAt"], NOW);
        assert_eq!(snap["github"]["openPrs"][0]["number"], 7.0);
        assert_eq!(snap["git"]["headSha"], "abc1234");
    }

    #[test]
    fn missing_snapshot_never_reads_as_no_prs() {
        let dir = temp_dir("missing");
        let tools = FakeTools::new(true, false);
        let msg = message(&inject(&dir, PAYLOAD, &tools));
        assert!(!msg.contains("(none)"), "{msg}");
        assert!(msg.contains(GITHUB_UNKNOWN), "{msg}");
        // A failed gh answer is not cached: the next turn asks again.
        assert!(!dir.join("snapshot.json").exists());
    }

    #[test]
    fn fresh_snapshot_is_served_without_asking_gh() {
        let dir = temp_dir("fresh");
        write_snapshot(&dir, NOW - 30_000.0);
        let tools = FakeTools::new(true, true);
        let msg = message(&inject(&dir, PAYLOAD, &tools));
        assert_eq!(tools.gh_calls(), 0);
        assert!(msg.contains("OPEN PRs:\n  (none)"), "{msg}");
        // Git still comes from the conversation's workspace, not the panel.
        assert!(msg.contains("branch feat/x (abc1234)"), "{msg}");
    }

    #[test]
    fn snapshot_with_updated_at_ms_key_counts_as_fresh() {
        let dir = temp_dir("fresh-ms");
        let mut snap = map(SNAPSHOT_EMPTY);
        snap.insert("updatedAtMs", NOW - 1_000.0);
        fs::write(dir.join("snapshot.json"), Value::Object(snap).to_string()).unwrap();
        let tools = FakeTools::new(true, true);
        inject(&dir, PAYLOAD, &tools);
        assert_eq!(tools.gh_calls(), 0);
    }

    #[test]
    fn snapshot_for_another_repo_or_without_timestamp_is_refetched() {
        let dir = temp_dir("other-repo");
        write_snapshot(&dir, NOW - 1_000.0);
        fs::write(dir.join("settings.json"), r#"{"repo":"acme/widgets"}"#).unwrap();
        let tools = FakeTools::new(true, true);
        let msg = message(&inject(&dir, PAYLOAD, &tools));
        assert_eq!(tools.gh_calls(), 3);
        assert!(msg.contains("LIVE acme/widgets state"), "{msg}");

        let dir = temp_dir("no-timestamp");
        fs::write(dir.join("snapshot.json"), SNAPSHOT_EMPTY).unwrap();
        let tools = FakeTools::new(true, true);
        inject(&dir, PAYLOAD, &tools);
        assert_eq!(tools.gh_calls(), 3);
    }

    #[test]
    fn snapshot_from_the_future_is_not_trusted() {
        let mut snap = map(SNAPSHOT_EMPTY);
        snap.insert("updatedAt", NOW + 86_400_000.0);
        assert!(!snapshot_is_fresh(&snap, NOW));
        snap.insert("updatedAt", NOW - SNAPSHOT_MAX_AGE_MS);
        assert!(snapshot_is_fresh(&snap, NOW));
        snap.insert("updatedAt", NOW - SNAPSHOT_MAX_AGE_MS - 1.0);
        assert!(!snapshot_is_fresh(&snap, NOW));
    }

    #[test]
    fn without_a_workspace_git_comes_from_a_fresh_snapshot_only() {
        let dir = temp_dir("no-ws");
        write_snapshot(&dir, NOW - 1_000.0);
        let tools = FakeTools::new(true, true);
        let msg = message(&inject(&dir, "{}", &tools));
        assert!(msg.contains("branch main (old0000)"), "{msg}");

        write_snapshot(&dir, NOW - 500_000.0);
        let msg = message(&inject(&dir, "{}", &tools));
        assert!(msg.contains(GIT_UNKNOWN), "{msg}");
    }

    #[test]
    fn disabled_sections_are_not_probed() {
        let dir = temp_dir("disabled");
        fs::write(
            dir.join("settings.json"),
            r#"{"injectGit":false,"injectGitHub":false,"injectContract":false}"#,
        )
        .unwrap();
        let tools = FakeTools::new(true, true);
        assert_eq!(inject(&dir, PAYLOAD, &tools), "{}");
        assert!(tools.calls.lock().unwrap().is_empty());
    }

    #[test]
    fn probes_run_in_parallel() {
        // Six slow tools must finish in about one tool's time, not six.
        let dir = temp_dir("parallel");
        let started = AtomicUsize::new(0);
        let run = |p: &str, a: &[&str], _c: Option<&Path>, _t: Duration| {
            started.fetch_add(1, Ordering::SeqCst);
            thread::sleep(Duration::from_millis(200));
            FakeTools::new(true, true).run(p, a, None)
        };
        let t0 = Instant::now();
        run_inject_live_context(PAYLOAD, Some(&dir), NOW, &run);
        assert_eq!(started.load(Ordering::SeqCst), 6);
        assert!(
            t0.elapsed() < Duration::from_millis(900),
            "{:?}",
            t0.elapsed()
        );
    }

    #[test]
    fn run_command_kills_a_tool_that_hangs() {
        let t0 = Instant::now();
        let out = run_command("sleep", &["5"], None, Duration::from_millis(200));
        assert!(out.is_none());
        assert!(t0.elapsed() < Duration::from_secs(2));
        assert_eq!(
            run_command("echo", &["hi"], None, Duration::from_secs(5)).as_deref(),
            Some("hi\n")
        );
        assert!(run_command("false", &[], None, Duration::from_secs(5)).is_none());
        assert!(run_command("/no/such/tool", &[], None, Duration::from_secs(1)).is_none());
    }

    #[test]
    fn probe_git_reads_a_real_repository() {
        let dir = temp_dir("real-git");
        let ok = |args: &[&str]| {
            Command::new("git")
                .args(args)
                .current_dir(&dir)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
        };
        if !ok(&["init", "-q", "-b", "trunk"]) {
            eprintln!("git not available; skipping");
            return;
        }
        assert!(probe_git(&dir, &run_command).is_none(), "no commit yet");
        fs::write(dir.join("a.txt"), "a").unwrap();
        assert!(ok(&["add", "a.txt"]));
        assert!(ok(&[
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-qm",
            "init"
        ]));
        fs::write(dir.join("a.txt"), "b").unwrap();
        let git = probe_git(&dir, &run_command).expect("repository readable");
        assert_eq!(git.get("branch").unwrap(), &"trunk");
        assert_eq!(git.get("dirtyCount").unwrap(), &1.0);
        assert_eq!(git.get("dirtyFiles").unwrap()[0], "a.txt");
    }

    // ---- Kept from the JavaScript suite (core.test.mjs) -------------------

    #[test]
    fn formats_git_and_github_summary() {
        let git = map(
            r#"{"branch":"feat/rust","headSha":"abc1234","dirtyCount":2,"dirtyFiles":["a.rs","b.rs"]}"#,
        );
        let github = map(
            r#"{"repo":"VitruvianSoftware/vitruvian-core","openPrs":[{"number":42,"title":"Add Rust hooks","isDraft":true}],"mergedPrs":[{"number":41,"title":"Init","mergedAt":"2026-10-25"}],"openIssues":3}"#,
        );

        let summary = format_live_git_summary(Some(&git), Some(&github), true, true);
        assert!(summary.contains(
            "LIVE GIT WORKSPACE: branch feat/rust (abc1234) · 2 uncommitted files: a.rs, b.rs"
        ));
        assert!(summary.contains("  #42 [draft] Add Rust hooks"));
        assert!(summary.contains("  #41 Init  (merged 2026-10-25)"));
        assert!(summary.contains("OPEN issues: 3"));
    }

    #[test]
    fn payload_has_inject_steps_or_is_empty_when_everything_is_off() {
        let git = map(r#"{"branch":"main","headSha":"1112223","dirtyCount":0}"#);
        let github = map(r#"{"openPrs":[],"mergedPrs":[],"openIssues":0}"#);
        let settings = map(r#"{"injectGit":true,"injectGitHub":true,"injectContract":true}"#);
        let payload = build_ephemeral_context_payload(Some(&git), Some(&github), Some(&settings));
        assert_eq!(payload["injectSteps"].as_array().unwrap().len(), 1);
        let msg = payload["injectSteps"][0]["ephemeralMessage"]
            .as_str()
            .unwrap();
        assert!(msg.contains("LIVE GIT WORKSPACE: branch main"));
        assert!(msg.contains("clean working tree"));
        assert!(msg.contains("RESPONSE CONTRACT"));

        let off = map(r#"{"injectGit":false,"injectGitHub":false,"injectContract":false}"#);
        assert_eq!(
            build_ephemeral_context_payload(None, None, Some(&off)).to_string(),
            "{}"
        );
    }

    #[test]
    fn detects_filler_closing_line_and_ignores_quoted() {
        let padding = "x".repeat(320);
        let bad = format!("{padding}\nNothing needed from you.");
        let res = check_response_contract(&bad, Some(300), None);
        assert!(!res.valid);
        assert!(res.has_filler);

        let quoted = format!("{padding}\nNever write 'Nothing needed from you.' in replies.");
        let res_quoted = check_response_contract(&quoted, Some(300), None);
        assert!(res_quoted.valid);
        assert!(!res_quoted.has_filler);

        let backticked = format!("{padding}\nWe tested `Nothing needed from you.` in the suite.");
        assert!(check_response_contract(&backticked, None, None).valid);

        let short = check_response_contract("Yes, the build passed.", None, None);
        assert!(short.exempt && short.valid);
    }

    #[test]
    fn enforce_mode_bounces_once_and_log_mode_allows() {
        let padding = "x".repeat(320);
        let ev = map(&format!(
            r#"{{"conversationId":"12345678-aaaa","executionNum":1,"terminationReason":"NO_TOOL_CALL","lastAssistantMessage":"{padding}\nNo action is needed."}}"#
        ));

        let res = evaluate_stop_shape(
            &ev,
            Some("enforce"),
            Some(300),
            None,
            Some("2026-10-25T00:00:00.000Z"),
        );
        assert!(res.bounced);
        assert_eq!(res.output["decision"], "continue");
        assert!(res.output["reason"]
            .as_str()
            .unwrap()
            .starts_with("RESPONSE CONTRACT:"));
        assert_eq!(res.log_record.unwrap().verdict, "block");

        let logged = evaluate_stop_shape(&ev, Some("log"), None, None, None);
        assert!(!logged.bounced);
        assert_eq!(logged.output.to_string(), r#"{"decision":"allow"}"#);
        assert_eq!(logged.log_record.unwrap().verdict, "block");

        let mut second = ev.clone();
        second.insert("executionNum", 2);
        let again = evaluate_stop_shape(&second, Some("enforce"), None, None, None);
        assert!(!again.bounced);
        assert!(again.log_record.is_none());
        assert_eq!(again.output.to_string(), r#"{"decision":"allow"}"#);
    }

    // ---- Parity with the Node.js script the Stop hook replaced ------------

    #[test]
    fn verify_reads_settings_and_appends_a_verdict_in_script_key_order() {
        let dir = temp_dir("verify");
        fs::write(dir.join("settings.json"), r#"{"mode":"enforce"}"#).unwrap();
        let msg = format!("{}\\nNothing needed from you.", "word ".repeat(80));
        let payload =
            format!(r#"{{"conversationId":"abcdefghijkl","lastAssistantMessage":"{msg}"}}"#);
        let out =
            run_verify_response_shape_at(&payload, Some(&dir), Some("2026-11-01T00:00:00.000Z"));
        assert!(
            out.starts_with(r#"{"decision":"continue","reason":"RESPONSE CONTRACT: "#),
            "{out}"
        );
        let log = fs::read_to_string(dir.join("verdicts.jsonl")).unwrap();
        assert!(
            log.starts_with(
                r#"{"ts":"2026-11-01T00:00:00.000Z","conversationId":"abcdefgh","mode":"enforce","chars":"#
            ),
            "{log}"
        );
        assert!(log.contains(
            r#""filler":true,"diagram":null,"longNoDiagram":false,"verdict":"block","tail":""#
        ));
        assert!(log.ends_with("\"}\n"));
    }

    #[test]
    fn verify_falls_back_to_the_last_planner_response_in_the_transcript() {
        let dir = temp_dir("transcript");
        let transcript = dir.join("transcript.jsonl");
        let long = "word ".repeat(80);
        fs::write(
            &transcript,
            format!(
                "{{\"type\":\"planner_response\",\"content\":\"{long}\\nNo action needed.\"}}\n5\n{{\"type\":\"USER_INPUT\",\"content\":\"hi\"}}\n"
            ),
        )
        .unwrap();
        fs::write(dir.join("settings.json"), r#"{"mode":"enforce"}"#).unwrap();
        let payload = format!(r#"{{"transcriptPath":"{}"}}"#, transcript.display());
        let out = run_verify_response_shape(&payload, Some(&dir));
        assert!(out.contains("\"continue\""), "{out}");

        // A line that is not JSON ends the search, as in the script.
        fs::write(
            &transcript,
            format!("{{\"type\":\"PLANNER_RESPONSE\",\"content\":\"{long}\\nNo action needed.\"}}\nnot json\n"),
        )
        .unwrap();
        let out = run_verify_response_shape(&payload, Some(&dir));
        assert_eq!(out, r#"{"decision":"allow"}"#);
    }

    #[test]
    fn verify_reads_numbers_the_way_javascript_does() {
        let dir = temp_dir("numbers");
        let msg = format!("{}\\nNo action needed.", "w".repeat(100));
        let payload = format!(r#"{{"lastAssistantMessage":"{msg}","executionNum":"1"}}"#);
        // minChars 0 checks every reply; the script did not treat it as unset.
        fs::write(
            dir.join("settings.json"),
            r#"{"mode":"enforce","minChars":0}"#,
        )
        .unwrap();
        assert!(run_verify_response_shape(&payload, Some(&dir)).contains("continue"));
        // Default minChars (300) exempts the 117-character reply.
        fs::write(dir.join("settings.json"), r#"{"mode":"enforce"}"#).unwrap();
        assert!(run_verify_response_shape(&payload, Some(&dir)).contains("allow"));
        // executionNum "2" is a second pass: never bounce.
        fs::write(
            dir.join("settings.json"),
            r#"{"mode":"enforce","minChars":0}"#,
        )
        .unwrap();
        let second = payload.replace(r#""executionNum":"1""#, r#""executionNum":"2""#);
        assert!(run_verify_response_shape(&second, Some(&dir)).contains("allow"));
    }

    #[test]
    fn verify_allows_bad_input() {
        assert_eq!(
            run_verify_response_shape("", None),
            r#"{"decision":"allow"}"#
        );
        assert_eq!(
            run_verify_response_shape("not json", None),
            r#"{"decision":"allow"}"#
        );
        assert_eq!(
            run_verify_response_shape("[1]", None),
            r#"{"decision":"allow"}"#
        );
    }

    #[test]
    fn tail_and_conversation_id_are_cut_in_utf16_units() {
        assert_eq!(js_slice_head("abcdefghij", 8), "abcdefgh");
        assert_eq!(js_slice_tail("xx😀", 2), "😀");
    }
}
