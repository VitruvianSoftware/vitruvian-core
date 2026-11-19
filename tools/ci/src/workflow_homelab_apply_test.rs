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

//! Structural and behavioral checks for the homelab-tunnel workflows
//! (sentry-apply and Zitadel applies): loopback socat bindings, fail-closed
//! stack selection, stack ordering, and atomic 409 retry of preview+guard+up.

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static TMP_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn tmpdir(tag: &str) -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let d = base.join(format!(
        "homelab-apply-{tag}-{}-{}",
        std::process::id(),
        TMP_COUNTER.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn runfiles_bin(env_name: &str) -> PathBuf {
    let raw = std::env::var(env_name).unwrap_or_else(|_| panic!("{env_name} is not set"));
    let p = PathBuf::from(&raw);
    let abs = if p.is_absolute() {
        p
    } else {
        std::env::current_dir().unwrap().join(p)
    };
    assert!(abs.is_file(), "{env_name}={raw} does not exist");
    abs
}

fn write_exec(path: &Path, body: &str) {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).unwrap();
    }
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// Logical lines of `text`, joining backslash continuations.
fn logical_lines(text: &str) -> Vec<(usize, String)> {
    let raw: Vec<&str> = text.lines().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < raw.len() {
        let start = i + 1;
        let mut joined = String::new();
        loop {
            let line = raw[i].trim_end();
            if let Some(prefix) = line.strip_suffix('\\') {
                joined.push_str(prefix);
                joined.push(' ');
                i += 1;
                if i < raw.len() {
                    continue;
                }
            } else {
                joined.push_str(line);
                i += 1;
            }
            break;
        }
        out.push((start, joined));
    }
    out
}

/// Extract `(line_number, listener_spec)` for any non-comment, non-pkill line
/// running `socat` with `TCP-LISTEN:` or `OPENSSL-LISTEN:`.
fn socat_listeners(text: &str) -> Vec<(usize, String)> {
    let mut out = Vec::new();
    for (lineno, line) in logical_lines(text) {
        let trimmed = line.trim();
        if trimmed.starts_with('#') || trimmed.contains("pkill") {
            continue;
        }
        if !trimmed.contains("socat")
            || (!trimmed.contains("TCP-LISTEN:") && !trimmed.contains("OPENSSL-LISTEN:"))
        {
            continue;
        }
        for tok in trimmed.split_whitespace() {
            let clean = tok.trim_matches(|c| matches!(c, '`' | '"' | '\'' | ';' | '&'));
            if let Some(idx) = clean
                .find("TCP-LISTEN:")
                .or_else(|| clean.find("OPENSSL-LISTEN:"))
            {
                out.push((lineno, clean[idx..].to_string()));
            }
        }
    }
    out
}

fn has_loopback_bind(listener: &str) -> bool {
    listener.split(',').any(|opt| opt == "bind=127.0.0.1") || listener.contains(",bind=127.0.0.1,")
}

fn stack_select_violations(text: &str) -> Vec<(usize, String)> {
    let mut bad = Vec::new();
    for (lineno, line) in logical_lines(text) {
        let trimmed = line.trim();
        if trimmed.starts_with('#') {
            continue;
        }
        if trimmed.contains("stack init") {
            bad.push((lineno, trimmed.to_string()));
            continue;
        }
        if trimmed.contains("stack select") {
            let has_create = trimmed.split_whitespace().any(|tok| {
                tok == "-c"
                    || tok == "--create"
                    || tok.starts_with("--create=")
                    || (tok.starts_with('-') && !tok.starts_with("--") && tok.contains('c'))
            });
            if has_create {
                bad.push((lineno, trimmed.to_string()));
            }
        }
    }
    bad
}

fn collect_files(dir: &Path, suffix: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if !dir.is_dir() {
        return out;
    }
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for entry in std::fs::read_dir(&d).unwrap().flatten() {
            let p = entry.path();
            if p.is_dir() {
                stack.push(p);
            } else if p
                .file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n.ends_with(suffix))
            {
                out.push(p);
            }
        }
    }
    out.sort();
    out
}

#[test]
fn every_socat_listener_in_workflows_binds_loopback() {
    // Fixture checks so the scanner cannot pass trivially.
    let bad = socat_listeners(
        "sudo socat TCP-LISTEN:443,reuseaddr,fork TCP:\"${HOMELAB_GATEWAY}\" &\n\
         sudo socat OPENSSL-LISTEN:443,reuseaddr,fork,cert=/etc/auth-internal-ck.pem,verify=0 \\\n  TCP:\"${ZITADEL_GATEWAY}\" &",
    );
    assert_eq!(bad.len(), 2);
    assert!(bad.iter().all(|(_, spec)| !has_loopback_bind(spec)));

    let good = socat_listeners(
        "sudo socat TCP-LISTEN:443,bind=127.0.0.1,reuseaddr,fork TCP:\"${HOMELAB_GATEWAY}\" &\n\
         sudo socat OPENSSL-LISTEN:443,bind=127.0.0.1,reuseaddr,fork,cert=/etc/auth-internal-ck.pem,verify=0 \\\n  TCP:\"${ZITADEL_GATEWAY}\" &",
    );
    assert_eq!(good.len(), 2);
    assert!(good.iter().all(|(_, spec)| has_loopback_bind(spec)));

    let root = std::env::current_dir().unwrap();
    let mut files = collect_files(&root.join(".github/workflows"), ".yaml");
    files.extend(collect_files(&root.join(".github/actions"), "action.yml"));

    let mut total_listeners = 0usize;
    let mut non_loopback = Vec::new();
    let mut per_file_counts = std::collections::BTreeMap::new();

    for path in files {
        let rel = path.strip_prefix(&root).unwrap().display().to_string();
        let text = std::fs::read_to_string(&path).unwrap();
        let found = socat_listeners(&text);
        if !found.is_empty() {
            per_file_counts.insert(rel.clone(), found.len());
            total_listeners += found.len();
            for (lineno, spec) in found {
                if !has_loopback_bind(&spec) {
                    non_loopback.push(format!("{rel}:{lineno}: {spec}"));
                }
            }
        }
    }

    assert!(
        total_listeners >= 5,
        "expected >= 5 socat listeners across sentry-apply and zitadel workflows, got {total_listeners} ({per_file_counts:?})"
    );
    for (wf, expected) in [
        (".github/workflows/sentry-apply.yaml", 2usize),
        (".github/workflows/_zitadel-apps-apply.yaml", 1usize),
        (".github/workflows/zitadel-apps-relay-apply.yaml", 1usize),
        (
            ".github/workflows/zitadel-apps-mcp-slack-apply.yaml",
            1usize,
        ),
    ] {
        assert_eq!(
            per_file_counts.get(wf).copied().unwrap_or(0),
            expected,
            "{wf} listener count mismatch: {per_file_counts:?}"
        );
    }
    assert!(
        non_loopback.is_empty(),
        "socat listeners missing bind=127.0.0.1:\n{}",
        non_loopback.join("\n")
    );
}

#[test]
fn sentry_apply_selects_existing_stacks_without_create_flag() {
    // Fixture checks.
    assert_eq!(
        stack_select_violations(
            "pulumi stack select -c production\npulumi stack select production --create\n"
        )
        .len(),
        2
    );
    assert!(stack_select_violations("pulumi stack select production\n").is_empty());

    let root = std::env::current_dir().unwrap();
    let text = std::fs::read_to_string(root.join(".github/workflows/sentry-apply.yaml")).unwrap();
    let select_count = logical_lines(&text)
        .into_iter()
        .filter(|(_, l)| !l.trim().starts_with('#') && l.contains("stack select"))
        .count();
    assert_eq!(
        select_count, 2,
        "expected two stack select lines in sentry-apply.yaml"
    );

    let bad = stack_select_violations(&text);
    assert!(
        bad.is_empty(),
        "sentry-apply.yaml must not auto-create missing stacks:\n{bad:?}"
    );
}

#[test]
fn sentry_apply_reconciles_sentry_before_sentry_pagerduty_and_never_retries_bare_up() {
    let root = std::env::current_dir().unwrap();
    let text = std::fs::read_to_string(root.join(".github/workflows/sentry-apply.yaml")).unwrap();

    let sentry_pos = text
        .find("working-directory: infrastructure/pulumi/platform/sentry\n")
        .expect("missing working-directory for platform/sentry");
    let pd_pos = text
        .find("working-directory: infrastructure/pulumi/platform/sentry-pagerduty\n")
        .expect("missing working-directory for platform/sentry-pagerduty");
    assert!(
        sentry_pos < pd_pos,
        "platform/sentry must run before platform/sentry-pagerduty"
    );

    let bad_lines: Vec<(usize, String)> = logical_lines(&text)
        .into_iter()
        .filter(|(_, l)| {
            let t = l.trim();
            !t.starts_with('#')
                && (t.contains("\"$retry\" pulumi up")
                    || t.contains("retry-concurrent-update pulumi up"))
        })
        .collect();
    assert!(
        bad_lines.is_empty(),
        "sentry-apply.yaml must never retry `pulumi up` without preview+plan_guard:\n{bad_lines:?}"
    );
}

fn extract_sentry_reconcile_block(workflow_text: &str) -> String {
    let lines: Vec<&str> = workflow_text.lines().collect();
    let start = lines
        .iter()
        .position(|l| l.contains("out_file=\"${RUNNER_TEMP}/pulumi-sentry-out.txt\""))
        .expect("missing pulumi-sentry-out.txt block in sentry-apply.yaml");
    let end = start
        + lines[start..]
            .iter()
            .position(|l| l.trim() == "exit \"${ec}\"")
            .expect("missing exit \"${ec}\" in sentry-apply.yaml");
    lines[start..=end].join("\n")
}

fn run_sentry_reconcile_subcase(second_preview_destructive: bool) -> (i32, Vec<String>, String) {
    let root = std::env::current_dir().unwrap();
    let wf = std::fs::read_to_string(root.join(".github/workflows/sentry-apply.yaml")).unwrap();
    let block = extract_sentry_reconcile_block(&wf);

    let d = tmpdir(if second_preview_destructive {
        "destructive-retry"
    } else {
        "safe-retry"
    });
    let runner_temp = d.join("runner_temp");
    let stubs = d.join("stubs");
    std::fs::create_dir_all(&runner_temp).unwrap();
    std::fs::create_dir_all(&stubs).unwrap();

    std::fs::copy(
        runfiles_bin("RETRY_BIN"),
        runner_temp.join("retry-concurrent-update"),
    )
    .unwrap();
    std::fs::copy(
        runfiles_bin("GUARD_BIN"),
        runner_temp.join("refuse-destructive-plan"),
    )
    .unwrap();
    if let Some(guarded_bin) = std::env::var_os("GUARDED_UP_BIN") {
        let p = PathBuf::from(&guarded_bin);
        let abs = if p.is_absolute() { p } else { root.join(p) };
        if abs.is_file() {
            std::fs::copy(abs, runner_temp.join("guarded-up")).unwrap();
        }
    }

    write_exec(
        &stubs.join("sleep"),
        "#!/usr/bin/env bash\necho \"$1\" >> \"$SLEEP_LOG\"\n",
    );
    write_exec(
        &stubs.join("pulumi"),
        r#"#!/usr/bin/env bash
set -euo pipefail
sub="${1:-}"
shift || true
case "$sub" in
  stack)
    if [ "${1:-}" = "select" ]; then
      echo "select" >> "$CALL_LOG"
      exit 0
    fi
    exit 1
    ;;
  preview)
    p=0
    [ -f "$PREVIEW_COUNT" ] && p="$(cat "$PREVIEW_COUNT")"
    p=$((p + 1))
    echo "$p" > "$PREVIEW_COUNT"
    echo "preview:$p" >> "$CALL_LOG"
    if [ "$p" -eq 1 ]; then
      cat <<'JSON'
{"steps":[{"op":"same","urn":"urn:pulumi:production::sentry::pulumi:pulumi:Stack::sentry-production"}],"changeSummary":{"same":1}}
JSON
    elif [ "${SECOND_PREVIEW_DESTRUCTIVE:-0}" = "1" ]; then
      cat <<'JSON'
{"steps":[{"op":"delete","urn":"urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-backstage","oldState":{"type":"sentry:index/sentryProject:SentryProject"}}],"changeSummary":{"delete":1}}
JSON
    else
      cat <<'JSON'
{"steps":[{"op":"same","urn":"urn:pulumi:production::sentry::pulumi:pulumi:Stack::sentry-production"},{"op":"create","urn":"urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-new"}],"changeSummary":{"same":1,"create":1}}
JSON
    fi
    exit 0
    ;;
  up)
    u=0
    [ -f "$UP_COUNT" ] && u="$(cat "$UP_COUNT")"
    u=$((u + 1))
    echo "$u" > "$UP_COUNT"
    echo "up:$u" >> "$CALL_LOG"
    if [ "$u" -eq 1 ]; then
      echo "error: [409] Conflict: concurrent update in progress" >&2
      exit 23
    fi
    echo "Updating (production):"
    exit 0
    ;;
  *)
    echo "unexpected pulumi subcommand: $sub" >&2
    exit 99
    ;;
esac
"#,
    );

    let call_log = d.join("calls.log");
    let sleep_log = d.join("sleeps.log");
    let preview_count = d.join("preview.count");
    let up_count = d.join("up.count");
    let gh_output = d.join("github_output");
    std::fs::write(&gh_output, "").unwrap();

    let script = format!(
        "set -euo pipefail\n\
         action=up\n\
         retry=\"${{RUNNER_TEMP}}/retry-concurrent-update\"\n\
         plan_guard=\"${{RUNNER_TEMP}}/refuse-destructive-plan\"\n\
         guarded_up=\"${{RUNNER_TEMP}}/guarded-up\"\n\
         {block}\n"
    );

    let o = Command::new("/bin/bash")
        .arg("-c")
        .arg(&script)
        .env_clear()
        .env("PATH", format!("{}:/usr/bin:/bin", stubs.display()))
        .env("RUNNER_TEMP", &runner_temp)
        .env("GITHUB_OUTPUT", &gh_output)
        .env("CALL_LOG", &call_log)
        .env("SLEEP_LOG", &sleep_log)
        .env("PREVIEW_COUNT", &preview_count)
        .env("UP_COUNT", &up_count)
        .env(
            "SECOND_PREVIEW_DESTRUCTIVE",
            if second_preview_destructive { "1" } else { "0" },
        )
        .env("PULUMI_CONFLICT_RETRY_DELAY", "1")
        .env("PULUMI_CONFLICT_MAX_DELAY", "1")
        .output()
        .expect("run extracted sentry-apply block");

    let calls: Vec<String> = std::fs::read_to_string(&call_log)
        .unwrap_or_default()
        .lines()
        .map(str::to_string)
        .collect();
    let out_file =
        std::fs::read_to_string(runner_temp.join("pulumi-sentry-out.txt")).unwrap_or_default();
    let rc = o.status.code().unwrap_or(-1);
    assert!(
        !String::from_utf8_lossy(&o.stderr).contains("command not found"),
        "harness stderr: {}",
        String::from_utf8_lossy(&o.stderr)
    );
    (rc, calls, out_file)
}

#[test]
fn sentry_apply_up_409_retries_fresh_preview_and_plan_guard_before_second_up() {
    let (rc, calls, out_file) = run_sentry_reconcile_subcase(false);
    assert_eq!(rc, 0, "expected rc=0, calls={calls:?}, out={out_file}");
    assert_eq!(
        calls,
        vec!["select", "preview:1", "up:1", "preview:2", "up:2"],
        "409 on up must trigger a fresh preview before the second up"
    );
    assert!(
        out_file.contains("1 step(s) checked"),
        "missing first guard check in out_file:\n{out_file}"
    );
    assert!(
        out_file.contains("2 step(s) checked"),
        "missing second guard check in out_file:\n{out_file}"
    );

    let (rc_bad, calls_bad, out_bad) = run_sentry_reconcile_subcase(true);
    assert_eq!(
        rc_bad, 1,
        "destructive second preview must fail closed; calls={calls_bad:?}, out={out_bad}"
    );
    assert_eq!(
        calls_bad,
        vec!["select", "preview:1", "up:1", "preview:2"],
        "up:2 must not run when the fresh preview becomes destructive"
    );
    assert!(
        out_bad.contains("Refusing to apply sentry production"),
        "expected plan-guard refusal in out_file:\n{out_bad}"
    );
}
