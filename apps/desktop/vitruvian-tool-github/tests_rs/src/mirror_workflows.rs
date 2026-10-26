// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn make_scratch(prefix: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let id = std::process::id();
    let seq = COUNTER.fetch_add(1, Ordering::Relaxed);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = base.join(format!("{prefix}-{id}-{ts}-{seq}"));
    fs::create_dir_all(&dir).expect("cannot create scratch dir");
    dir
}

#[derive(Debug, Clone, Default)]
pub struct Step {
    pub id: Option<String>,
    pub name: Option<String>,
    pub uses: Option<String>,
    pub run: Option<String>,
    pub with: HashMap<String, String>,
}

#[derive(Debug, Clone, Default)]
pub struct Job {
    pub permissions: HashMap<String, String>,
    pub steps: Vec<Step>,
}

#[derive(Debug, Clone, Default)]
pub struct Workflow {
    pub permissions: HashMap<String, String>,
    pub jobs: HashMap<String, Job>,
}

fn indent_level(line: &str) -> usize {
    line.len() - line.trim_start().len()
}

fn strip_yaml_quotes(s: &str) -> String {
    let t = s.trim();
    if (t.starts_with('"') && t.ends_with('"')) || (t.starts_with('\'') && t.ends_with('\'')) {
        return t[1..t.len() - 1].to_string();
    }
    let without_comment = if let Some(idx) = t.find(" #") {
        t[..idx].trim_end()
    } else {
        t
    };
    without_comment.to_string()
}

fn parse_inline_map(
    lines: &[&str],
    start: usize,
    base_indent: usize,
) -> (HashMap<String, String>, usize) {
    let mut map = HashMap::new();
    let mut i = start;
    while i < lines.len() {
        let line = lines[i];
        if line.trim().is_empty() || line.trim().starts_with('#') {
            i += 1;
            continue;
        }
        let ind = indent_level(line);
        if ind <= base_indent {
            break;
        }
        let trimmed = line.trim();
        if let Some(colon_pos) = trimmed.find(':') {
            let key = trimmed[..colon_pos].trim().to_string();
            let val = trimmed[colon_pos + 1..].trim().to_string();
            if !val.is_empty() {
                map.insert(key, strip_yaml_quotes(&val));
            }
        }
        i += 1;
    }
    (map, i)
}

fn collect_multiline_block(lines: &[&str], start: usize, base_indent: usize) -> (String, usize) {
    let mut block = String::new();
    let mut i = start;
    while i < lines.len() {
        let line = lines[i];
        if line.trim().is_empty() {
            block.push('\n');
            i += 1;
            continue;
        }
        let ind = indent_level(line);
        if ind <= base_indent {
            break;
        }
        if !block.is_empty() {
            block.push('\n');
        }
        let stripped = if line.len() > base_indent + 2 {
            &line[base_indent + 2..]
        } else {
            line.trim()
        };
        block.push_str(stripped);
        i += 1;
    }
    (block, i)
}

pub fn parse_workflow(text: &str) -> Workflow {
    let lines: Vec<&str> = text.lines().collect();
    let mut wf = Workflow::default();
    let mut i = 0;

    while i < lines.len() {
        let line = lines[i];
        let trimmed = line.trim();

        if trimmed.is_empty() || trimmed.starts_with('#') {
            i += 1;
            continue;
        }

        let ind = indent_level(line);

        if ind == 0 && trimmed.starts_with("permissions:") {
            let val = trimmed.strip_prefix("permissions:").unwrap().trim();
            if val.is_empty() {
                i += 1;
                let (map, next) = parse_inline_map(&lines, i, 0);
                wf.permissions = map;
                i = next;
            } else {
                i += 1;
            }
            continue;
        }

        if ind == 0 && trimmed == "jobs:" {
            i += 1;
            while i < lines.len() {
                let jline = lines[i];
                if jline.trim().is_empty() || jline.trim().starts_with('#') {
                    i += 1;
                    continue;
                }
                let jind = indent_level(jline);
                if jind == 0 && !jline.trim().is_empty() {
                    break;
                }
                if jind == 2 && jline.trim().ends_with(':') {
                    let job_name = jline.trim().trim_end_matches(':').to_string();
                    i += 1;
                    let mut job = Job::default();
                    while i < lines.len() {
                        let kline = lines[i];
                        if kline.trim().is_empty() || kline.trim().starts_with('#') {
                            i += 1;
                            continue;
                        }
                        let kind = indent_level(kline);
                        if kind <= 2 {
                            break;
                        }
                        let ktrimmed = kline.trim();

                        if kind == 4 && ktrimmed.starts_with("permissions:") {
                            let pval = ktrimmed.strip_prefix("permissions:").unwrap().trim();
                            if pval.is_empty() {
                                i += 1;
                                let (map, next) = parse_inline_map(&lines, i, 4);
                                job.permissions = map;
                                i = next;
                            } else {
                                i += 1;
                            }
                            continue;
                        }

                        if kind == 4 && ktrimmed == "steps:" {
                            i += 1;
                            while i < lines.len() {
                                let sline = lines[i];
                                if sline.trim().is_empty() {
                                    i += 1;
                                    continue;
                                }
                                let sind = indent_level(sline);
                                if sind <= 4 && !sline.trim().is_empty() {
                                    break;
                                }
                                let strimmed = sline.trim();
                                if strimmed.starts_with("- ") {
                                    let mut step = Step::default();
                                    let first_content = strimmed.strip_prefix("- ").unwrap();
                                    let step_base_indent = sind;

                                    if let Some(colon_pos) = first_content.find(':') {
                                        let key = first_content[..colon_pos].trim();
                                        let val = first_content[colon_pos + 1..].trim();
                                        match key {
                                            "uses" => step.uses = Some(strip_yaml_quotes(val)),
                                            "id" => step.id = Some(strip_yaml_quotes(val)),
                                            "name" => step.name = Some(strip_yaml_quotes(val)),
                                            "run" => {
                                                if val == "|" {
                                                    i += 1;
                                                    let (block, next) = collect_multiline_block(
                                                        &lines,
                                                        i,
                                                        step_base_indent + 2,
                                                    );
                                                    step.run = Some(block);
                                                    i = next;
                                                    job.steps.push(step);
                                                    continue;
                                                } else {
                                                    step.run = Some(strip_yaml_quotes(val));
                                                }
                                            }
                                            _ => {}
                                        }
                                    }
                                    i += 1;

                                    while i < lines.len() {
                                        let pline = lines[i];
                                        if pline.trim().is_empty() {
                                            i += 1;
                                            continue;
                                        }
                                        let pind = indent_level(pline);
                                        if pind <= step_base_indent {
                                            break;
                                        }
                                        if pind == step_base_indent + 2
                                            && pline.trim().starts_with("- ")
                                        {
                                            break;
                                        }
                                        let ptrimmed = pline.trim();

                                        if pind == step_base_indent + 2 {
                                            if let Some(colon_pos) = ptrimmed.find(':') {
                                                let key = ptrimmed[..colon_pos].trim();
                                                let val = ptrimmed[colon_pos + 1..].trim();
                                                match key {
                                                    "uses" => {
                                                        step.uses = Some(strip_yaml_quotes(val))
                                                    }
                                                    "id" => step.id = Some(strip_yaml_quotes(val)),
                                                    "name" => {
                                                        step.name = Some(strip_yaml_quotes(val))
                                                    }
                                                    "run" => {
                                                        if val == "|" {
                                                            i += 1;
                                                            let (block, next) =
                                                                collect_multiline_block(
                                                                    &lines,
                                                                    i,
                                                                    step_base_indent + 2,
                                                                );
                                                            step.run = Some(block);
                                                            i = next;
                                                            continue;
                                                        } else if !val.is_empty() {
                                                            step.run = Some(strip_yaml_quotes(val));
                                                        }
                                                    }
                                                    "with" => {
                                                        if val.is_empty() {
                                                            i += 1;
                                                            let (map, next) = parse_inline_map(
                                                                &lines,
                                                                i,
                                                                step_base_indent + 2,
                                                            );
                                                            step.with = map;
                                                            i = next;
                                                            continue;
                                                        }
                                                    }
                                                    _ => {}
                                                }
                                            }
                                            i += 1;
                                        } else {
                                            i += 1;
                                        }
                                    }

                                    job.steps.push(step);
                                } else {
                                    i += 1;
                                }
                            }
                            continue;
                        }

                        i += 1;
                    }
                    wf.jobs.insert(job_name, job);
                } else {
                    i += 1;
                }
            }
            continue;
        }

        i += 1;
    }

    wf
}

pub fn find_step_run<'a>(wf: &'a Workflow, job_name: &str, key: &str, value: &str) -> &'a str {
    let job = wf
        .jobs
        .get(job_name)
        .unwrap_or_else(|| panic!("release.yml has no job {job_name}"));
    for step in &job.steps {
        let matches = match key {
            "id" => step.id.as_deref() == Some(value),
            "name" => step.name.as_deref() == Some(value),
            _ => false,
        };
        if matches {
            return step
                .run
                .as_deref()
                .unwrap_or_else(|| panic!("step with {key}={value} has no run"));
        }
    }
    panic!("release.yml's {job_name} job has no step with {key} {value:?}")
}

fn run_step(script: &str, root: &Path, env: &HashMap<String, String>) -> (i32, String, String) {
    let path_env = std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".to_string());
    let output = Command::new("bash")
        .args(["--noprofile", "--norc", "-eo", "pipefail", "-c", script])
        .current_dir(root)
        .env_clear()
        .env("PATH", &path_env)
        .envs(env)
        .output()
        .expect("failed to run bash");
    let code = output.status.code().unwrap_or(-1);
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    (code, stdout, stderr)
}

fn git(root: &Path, args: &[&str]) {
    let status = Command::new("git")
        .args(["-c", "user.name=t", "-c", "user.email=t@t"])
        .args(args)
        .current_dir(root)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .expect("git failed");
    assert!(status.success(), "git {args:?} failed");
}

pub fn detect(script: &str, manifest: Option<&str>, tags: &[&str]) -> (i32, String, String) {
    let root = make_scratch("detect");

    git(&root, &["init", "-q"]);
    if let Some(m) = manifest {
        let content = format!("{{\"apps/desktop/vitruvian-tool-github\":\"{}\"}}", m);
        fs::write(root.join(".release-please-manifest.json"), &content).unwrap();
    }
    fs::write(root.join("README.md"), "x\n").unwrap();
    git(&root, &["add", "-A"]);
    git(&root, &["commit", "-q", "-m", "m"]);
    for tag in tags {
        git(&root, &["tag", tag]);
    }

    let output_file = root.join(".output");
    fs::write(&output_file, "").unwrap();

    let mut env = HashMap::new();
    env.insert(
        "GITHUB_OUTPUT".to_string(),
        output_file.to_string_lossy().to_string(),
    );

    let (code, stdout, stderr) = run_step(script, &root, &env);
    let output_content = fs::read_to_string(&output_file)
        .unwrap_or_default()
        .trim()
        .to_string();

    (code, output_content, format!("{stdout}{stderr}"))
}

pub fn detect_problems(wf: &Workflow) -> Vec<String> {
    let script = find_step_run(wf, "detect", "id", "detect");
    let mut problems = Vec::new();

    let cases: Vec<(Option<&str>, Vec<&str>, i32, &str)> = vec![
        (None, vec![], 0, ""),
        (Some("0.0.0"), vec![], 0, ""),
        (Some("1.0.0"), vec![], 0, "version=1.0.0"),
        (Some("1.0.0"), vec!["v1.0.0"], 0, ""),
        (
            Some("1.0.0"),
            vec!["vitruvian-tool-github-v1.0.0"],
            0,
            "version=1.0.0",
        ),
        (Some("1.0"), vec![], 1, ""),
    ];

    for (manifest, tags, expected_status, wanted) in &cases {
        let (got_status, got_output, printed) = detect(script, *manifest, tags);
        if got_status != *expected_status || got_output != *wanted {
            problems.push(format!(
                "detect with manifest {:?} and tags {:?}: exit {} and {:?}, \
                 want exit {} and {:?}\n{}",
                manifest, tags, got_status, got_output, expected_status, wanted, printed
            ));
        }
    }

    problems
}

const NO_CHANGES: &str = "has no section for 1.0.0";
const FIRST_CHANGELOG: &str = "# Changelog\n\n## 1.0.0 (2026-11-02)\n\n\n### Features\n\n* the GitHub tool ([#1](https://x/1))\n";
const LATER_CHANGELOG: &str = "# Changelog\n\n## [1.1.0](https://x/compare/v1.0.0...v1.1.0) (2026-12-01)\n\n\n### Features\n\n* later\n\n## [1.0.0](https://x/compare/v0.9.0...v1.0.0) (2026-11-02)\n\n\n### Bug Fixes\n\n* a fix in 1.0.0\n";

pub fn notes_problems(wf: &Workflow) -> Vec<String> {
    let script = find_step_run(wf, "release", "name", "Write the release notes");
    let mut problems = Vec::new();

    let cases: Vec<(&str, Option<&str>, Vec<&str>, Vec<&str>)> = vec![
        ("no CHANGELOG.md", None, vec![NO_CHANGES], vec![]),
        (
            "a first release",
            Some(FIRST_CHANGELOG),
            vec!["## Features", "the GitHub tool"],
            vec![NO_CHANGES],
        ),
        (
            "a later release",
            Some(LATER_CHANGELOG),
            vec!["## Bug Fixes", "a fix in 1.0.0"],
            vec![NO_CHANGES, "later"],
        ),
    ];

    for (name, changelog, wanted, unwanted) in &cases {
        let root = make_scratch("notes");

        if let Some(content) = changelog {
            fs::write(root.join("CHANGELOG.md"), content).unwrap();
        }

        let mut env = HashMap::new();
        env.insert(
            "RUNNER_TEMP".to_string(),
            root.to_string_lossy().to_string(),
        );
        env.insert("V".to_string(), "1.0.0".to_string());
        env.insert("ASSET".to_string(), "github-tool-1.0.0.zip".to_string());
        env.insert("ASSET_SIZE".to_string(), "1234".to_string());
        env.insert("ASSET_SHA256".to_string(), "ab".repeat(32));

        let (code, stdout, stderr) = run_step(script, &root, &env);
        if code != 0 {
            problems.push(format!("notes with {name}: exit {code}\n{stdout}{stderr}"));
            continue;
        }

        let notes_path = root.join("notes.md");
        let text = fs::read_to_string(&notes_path).unwrap_or_default();

        let always_wanted = vec![
            "the Vitruvian catalog on Settings \u{203a} Extensions".to_string(),
            format!("`size`: 1234, `sha256`: {}", "ab".repeat(32)),
        ];

        for line in always_wanted
            .iter()
            .map(|s| s.as_str())
            .chain(wanted.iter().copied())
        {
            if !text.contains(line) {
                problems.push(format!("notes with {name}: no {line:?}\n{text}"));
            }
        }
        for line in unwanted {
            if text.contains(line) {
                problems.push(format!("notes with {name}: has {line:?}\n{text}"));
            }
        }
    }

    problems
}

fn is_hex40(s: &str) -> bool {
    s.len() == 40 && s.chars().all(|c| c.is_ascii_hexdigit())
}

pub fn limit_problems(name: &str, wf: &Workflow) -> Vec<String> {
    let mut problems = Vec::new();

    let expected_top: HashMap<String, String> =
        [("contents".to_string(), "read".to_string())].into();
    if wf.permissions != expected_top {
        problems.push(format!(
            "{name}: the workflow's permissions are not contents: read"
        ));
    }

    for (job_name, job) in &wf.jobs {
        let mut writes: Vec<String> = job
            .permissions
            .iter()
            .filter(|(_, v)| v == &"write")
            .map(|(k, _)| k.clone())
            .collect();
        writes.sort();

        let allowed: Vec<String> = if name == "release.yml" && job_name == "release" {
            vec!["contents".to_string()]
        } else {
            vec![]
        };
        if writes != allowed {
            problems.push(format!(
                "{name}: job {job_name} may write {writes:?}, not {allowed:?}"
            ));
        }

        if job.permissions.contains_key("id-token") {
            problems.push(format!(
                "{name}: job {job_name} asks for an identity token; \
                 nothing here publishes to a registry"
            ));
        }

        for step in &job.steps {
            if let Some(uses) = &step.uses {
                let parts: Vec<&str> = uses.splitn(2, '@').collect();
                if parts.len() != 2 || !is_hex40(parts[1]) {
                    problems.push(format!("{name}: {uses} is not pinned to a commit"));
                }
                if uses.starts_with("actions/checkout@") {
                    let persist = step.with.get("persist-credentials");
                    if persist.map(|v| v.as_str()) != Some("false") {
                        problems.push(format!(
                            "{name}: job {job_name} checks out with its credentials kept"
                        ));
                    }
                }
            }
        }
    }

    problems
}

pub fn load_workflow(path: &Path) -> Workflow {
    let text =
        fs::read_to_string(path).unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
    parse_workflow(&text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_simple_workflow() {
        let text = r#"
permissions:
  contents: read

jobs:
  build:
    steps:
      - uses: actions/checkout@abcdef1234567890abcdef1234567890abcdef12
        with:
          persist-credentials: false
      - name: Test
        run: echo hello
"#;
        let wf = parse_workflow(text);
        assert_eq!(wf.permissions.get("contents").unwrap(), "read");
        let job = wf.jobs.get("build").unwrap();
        assert_eq!(job.steps.len(), 2);
        assert_eq!(
            job.steps[0].uses.as_deref().unwrap(),
            "actions/checkout@abcdef1234567890abcdef1234567890abcdef12"
        );
        assert_eq!(
            job.steps[0].with.get("persist-credentials").unwrap(),
            "false"
        );
        assert_eq!(job.steps[1].name.as_deref().unwrap(), "Test");
        assert_eq!(job.steps[1].run.as_deref().unwrap(), "echo hello");
    }

    #[test]
    fn parse_multiline_run() {
        let text = r#"
permissions:
  contents: read

jobs:
  test:
    steps:
      - name: Multi
        run: |
          echo line1
          echo line2
"#;
        let wf = parse_workflow(text);
        let job = wf.jobs.get("test").unwrap();
        let run = job.steps[0].run.as_deref().unwrap();
        assert!(run.contains("echo line1"));
        assert!(run.contains("echo line2"));
    }

    #[test]
    fn parse_job_permissions() {
        let text = r#"
permissions:
  contents: read

jobs:
  release:
    permissions:
      contents: write
    steps:
      - name: Do
        run: echo ok
"#;
        let wf = parse_workflow(text);
        let job = wf.jobs.get("release").unwrap();
        assert_eq!(job.permissions.get("contents").unwrap(), "write");
    }

    #[test]
    fn is_hex40_valid() {
        assert!(is_hex40("abcdef1234567890abcdef1234567890abcdef12"));
        assert!(is_hex40("0000000000000000000000000000000000000000"));
    }

    #[test]
    fn is_hex40_invalid() {
        assert!(!is_hex40("abcdef"));
        assert!(!is_hex40("v7.0.1"));
        assert!(!is_hex40("abcdef1234567890abcdef1234567890abcdefgg"));
    }

    #[test]
    fn limit_problems_clean() {
        let text = r#"
permissions:
  contents: read

jobs:
  build:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
        with:
          persist-credentials: false
      - name: Test
        run: echo ok
"#;
        let wf = parse_workflow(text);
        let probs = limit_problems("ci.yml", &wf);
        assert!(probs.is_empty(), "unexpected problems: {probs:?}");
    }

    #[test]
    fn limit_problems_unpinned() {
        let text = r#"
permissions:
  contents: read

jobs:
  build:
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
"#;
        let wf = parse_workflow(text);
        let probs = limit_problems("ci.yml", &wf);
        assert!(probs.iter().any(|p| p.contains("not pinned to a commit")));
    }

    #[test]
    fn limit_problems_credentials_kept() {
        let text = r#"
permissions:
  contents: read

jobs:
  build:
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
"#;
        let wf = parse_workflow(text);
        let probs = limit_problems("ci.yml", &wf);
        assert!(probs.iter().any(|p| p.contains("credentials kept")));
    }

    #[test]
    fn find_step_by_id() {
        let text = r#"
permissions:
  contents: read

jobs:
  detect:
    steps:
      - id: detect
        name: A version
        run: echo found
"#;
        let wf = parse_workflow(text);
        let run = find_step_run(&wf, "detect", "id", "detect");
        assert_eq!(run, "echo found");
    }

    #[test]
    fn find_step_by_name() {
        let text = r#"
permissions:
  contents: read

jobs:
  release:
    permissions:
      contents: write
    steps:
      - name: Write the release notes
        run: echo notes
"#;
        let wf = parse_workflow(text);
        let run = find_step_run(&wf, "release", "name", "Write the release notes");
        assert_eq!(run, "echo notes");
    }
}
