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

//! rules/configs.py: configuration file and schema key naming rules.

use crate::pystr::{
    basename, dollar, is_lower_alnum, is_space, lower, py_len, separated, splitlines, strip,
    strip_chars,
};
use crate::violation::{Severity, Violation};

/// `^_?[a-z0-9]+(-[a-z0-9]+)*$`
pub fn is_workflow_file_base(s: &str) -> bool {
    dollar(s, |t| {
        separated(t.strip_prefix('_').unwrap_or(t), '-', is_lower_alnum)
    })
}

/// `PULUMI_CONFIG_KEY_RE`: an optional `kebab:` namespace, then a kebab or snake key.
pub fn is_pulumi_config_key(s: &str) -> bool {
    dollar(s, |t| {
        let key = |k: &str| separated(k, '-', is_lower_alnum) || separated(k, '_', is_lower_alnum);
        match t.split_once(':') {
            Some((ns, rest)) => separated(ns, '-', is_lower_alnum) && key(rest),
            None => key(t),
        }
    })
}

/// `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
pub fn is_rfc1123(s: &str) -> bool {
    dollar(s, |t| {
        !t.is_empty()
            && t.chars().all(|c| is_lower_alnum(c) || c == '-')
            && !t.starts_with('-')
            && !t.ends_with('-')
    })
}

/// validate_config_file_name.
pub fn validate_config_file_name(file_path: &str) -> Vec<Violation> {
    let mut violations = Vec::new();
    let normalized = strip_chars(file_path, "/").replace('\\', "/");
    let file_name = basename(&normalized);
    let yaml = file_name.ends_with(".yaml") || file_name.ends_with(".yml");

    if file_name.starts_with("Pulumi.") && yaml {
        return violations;
    }

    if normalized.contains(".github/workflows") && yaml {
        let base_name = match file_name.rfind('.') {
            Some(i) => &file_name[..i],
            None => file_name,
        };
        if !is_workflow_file_base(base_name) {
            violations.push(Violation::new(
                "CFG001",
                &normalized,
                None,
                format!(
                    "GitHub Actions workflow file '{}' must use kebab-case.",
                    file_name
                ),
                Severity::Error,
                Some(format!("{}.yaml", base_name.replace('_', "-"))),
            ));
        }
    }
    violations
}

/// `re.search(r"(?:^|[-\s])run\s*:\s*[|>][-+]?", stripped)`
fn starts_run_block(stripped: &str) -> bool {
    let chars: Vec<char> = stripped.chars().collect();
    for p in 0..chars.len() {
        if chars[p..].len() < 3 || chars[p] != 'r' || chars[p + 1] != 'u' || chars[p + 2] != 'n' {
            continue;
        }
        if p != 0 && chars[p - 1] != '-' && !is_space(chars[p - 1]) {
            continue;
        }
        let mut i = p + 3;
        while i < chars.len() && is_space(chars[i]) {
            i += 1;
        }
        if i >= chars.len() || chars[i] != ':' {
            continue;
        }
        i += 1;
        while i < chars.len() && is_space(chars[i]) {
            i += 1;
        }
        if i < chars.len() && (chars[i] == '|' || chars[i] == '>') {
            return true;
        }
    }
    false
}

fn key_of(stripped: &str) -> &str {
    strip(stripped.split(':').next().unwrap_or(""))
}

/// validate_workflow_yaml_content.
pub fn validate_workflow_yaml_content(file_path: &str, content: &str) -> Vec<Violation> {
    let mut violations = Vec::new();
    let mut in_jobs = false;
    let mut jobs_indent = 0usize;
    let mut in_inputs = false;
    let mut inputs_indent = 0usize;
    let mut in_outputs = false;
    let mut outputs_indent = 0usize;
    let mut in_run_block = false;
    let mut run_block_indent = 0usize;

    for (i, raw_line) in splitlines(content).into_iter().enumerate() {
        let idx = (i + 1) as i64;
        let stripped = strip(raw_line);
        if stripped.is_empty() || stripped.starts_with('#') {
            continue;
        }
        let indent = py_len(raw_line) - py_len(raw_line.trim_start_matches(is_space));

        if in_run_block {
            if indent <= run_block_indent {
                in_run_block = false;
            } else {
                continue;
            }
        }

        if starts_run_block(stripped) {
            in_run_block = true;
            run_block_indent = indent;
            continue;
        }

        if stripped.starts_with("jobs:") {
            in_jobs = true;
            jobs_indent = indent;
            in_inputs = false;
            in_outputs = false;
            continue;
        }
        if stripped.starts_with("inputs:") {
            in_inputs = true;
            inputs_indent = indent;
            in_outputs = false;
            in_jobs = false;
            continue;
        }
        if stripped.starts_with("outputs:") {
            in_outputs = true;
            outputs_indent = indent;
            in_inputs = false;
            in_jobs = false;
            continue;
        }

        if in_jobs && indent <= jobs_indent && !stripped.starts_with("jobs:") {
            in_jobs = false;
        }
        if in_inputs && indent <= inputs_indent {
            in_inputs = false;
        }
        if in_outputs && indent <= outputs_indent {
            in_outputs = false;
        }

        if in_jobs && indent == jobs_indent + 2 && stripped.contains(':') {
            let job_key = key_of(stripped);
            if job_key.contains('_') && !job_key.starts_with("${{") && !job_key.starts_with('-') {
                violations.push(Violation::new(
                    "CFG002",
                    file_path,
                    Some(idx),
                    format!(
                        "GitHub Actions job ID '{}' uses underscores. Expected kebab-case.",
                        job_key
                    ),
                    Severity::Error,
                    Some(job_key.replace('_', "-")),
                ));
            }
        }

        if (in_inputs || in_outputs) && stripped.contains(':') {
            let expected = if in_inputs {
                inputs_indent + 2
            } else {
                outputs_indent + 2
            };
            if indent == expected || (inputs_indent == 0 && (indent == 2 || indent == 4)) {
                let param_key = key_of(stripped);
                if param_key.contains('_')
                    && !param_key.starts_with("${{")
                    && !param_key.starts_with('-')
                {
                    violations.push(Violation::new(
                        "CFG003",
                        file_path,
                        Some(idx),
                        format!(
                            "Workflow input/output key '{}' uses underscores. Expected kebab-case.",
                            param_key
                        ),
                        Severity::Error,
                        Some(param_key.replace('_', "-")),
                    ));
                }
            }
        }

        if in_jobs
            && !in_run_block
            && (stripped.starts_with("id:") || stripped.starts_with("- id:"))
        {
            let raw_id = if let Some(rest) = stripped.strip_prefix("- id:") {
                rest
            } else {
                stripped.split_once(':').map(|(_, r)| r).unwrap_or("")
            };
            let step_id = strip_chars(strip(raw_id), "\"'");
            if step_id.contains('_') && !step_id.starts_with("${{") {
                violations.push(Violation::new(
                    "CFG004",
                    file_path,
                    Some(idx),
                    format!(
                        "Step ID '{}' uses underscores. Expected kebab-case.",
                        step_id
                    ),
                    Severity::Error,
                    Some(step_id.replace('_', "-")),
                ));
            }
        }
    }
    violations
}

/// validate_k8s_resource_name.
pub fn validate_k8s_resource_name(file_path: &str, name: &str, line_number: i64) -> Vec<Violation> {
    let mut violations = Vec::new();
    if !is_rfc1123(name) || name.contains('_') {
        violations.push(Violation::new(
            "K8S001",
            file_path,
            Some(line_number),
            format!(
                "Kubernetes resource name '{}' violates RFC 1123 DNS subdomain standard (hyphens only, no underscores).",
                name
            ),
            Severity::Error,
            Some(lower(name).replace('_', "-")),
        ));
    }
    violations
}

/// validate_pulumi_config_key.
pub fn validate_pulumi_config_key(file_path: &str, key: &str, line_number: i64) -> Vec<Violation> {
    let mut violations = Vec::new();
    if !is_pulumi_config_key(key) {
        violations.push(Violation::new(
            "PUL001",
            file_path,
            Some(line_number),
            format!("Pulumi configuration key '{}' has invalid casing.", key),
            Severity::Warning,
            None,
        ));
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wf(content: &str) -> Vec<(String, Option<i64>)> {
        validate_workflow_yaml_content("ci.yaml", content)
            .into_iter()
            .map(|v| (v.rule_id, v.line_number))
            .collect()
    }

    #[test]
    fn job_step_and_input_keys() {
        assert_eq!(
            wf("jobs:\n  build_image:\n    runs-on: x\n"),
            [("CFG002".to_string(), Some(2))]
        );
        assert!(wf("jobs:\n  unit-test:\n    runs-on: x\n").is_empty());
        assert_eq!(
            wf("jobs:\n  t:\n    steps:\n      - id: run_test\n"),
            [("CFG004".to_string(), Some(4))]
        );
        assert!(wf("jobs:\n  b:\n    steps:\n      - id: ${{ matrix.step_id }}\n").is_empty());
        assert_eq!(
            wf("inputs:\n  github_token:\n    d: t\n"),
            [("CFG003".to_string(), Some(2))]
        );
        assert_eq!(
            wf("on:\n  workflow_dispatch:\n    inputs:\n      target_environment:\n        d: x\n"),
            [("CFG003".to_string(), Some(4))]
        );
    }

    #[test]
    fn run_blocks_are_skipped() {
        let content = "jobs:\n  test:\n    steps:\n      - id: ok\n        run: |\n          id: internal_var\n";
        assert!(wf(content).is_empty());
        assert!(starts_run_block("- run: >-"));
        assert!(starts_run_block("run : |"));
        assert!(!starts_run_block("rerun: |"));
    }

    #[test]
    fn workflow_file_names() {
        assert!(validate_config_file_name(".github/workflows/ci-preflight.yaml").is_empty());
        assert!(validate_config_file_name(".github/workflows/_deploy-cloud-run.yaml").is_empty());
        let v = validate_config_file_name(".github/workflows/ci_preflight.yml");
        assert_eq!(v[0].suggested_fix.as_deref(), Some("ci-preflight.yaml"));
        assert!(validate_config_file_name("Pulumi.dev.yaml").is_empty());
    }

    #[test]
    fn k8s_and_pulumi() {
        assert!(validate_k8s_resource_name("m.yaml", &"a".repeat(63), 1).is_empty());
        assert_eq!(
            validate_k8s_resource_name("m.yaml", "-bad", 1)[0].rule_id,
            "K8S001"
        );
        assert_eq!(
            validate_k8s_resource_name("m.yaml", "a_b", 1)[0]
                .suggested_fix
                .as_deref(),
            Some("a-b")
        );
        assert!(validate_pulumi_config_key("P.yaml", "gcp:project", 1).is_empty());
        assert!(validate_pulumi_config_key("P.yaml", "my_key", 1).is_empty());
        assert_eq!(
            validate_pulumi_config_key("P.yaml", "Bad", 1)[0].severity,
            Severity::Warning
        );
    }
}
