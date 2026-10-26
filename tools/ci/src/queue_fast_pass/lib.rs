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

//! queue-fast-pass.sh — has this exact code already passed this check on its
//! pull request, or did the merge queue already pass it on main? (#2841)

use shell_compat::{capture, cat, env, env_or_empty, err, out, subst};
use std::process::Command;

fn log(msg: &[u8]) {
    err(&cat(&[b"queue-fast-pass: ", msg, b"\n"]));
}

fn emit(line: &[u8]) {
    out(&cat(&[line, b"\n"]));
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&cat(&[line, b"\n"]))
                });
        }
    }
}

fn finish(verdict: &[u8], reason: &[u8], run_id: &[u8]) -> i32 {
    emit(&cat(&[b"verdict=", verdict]));
    emit(&cat(&[b"run=", run_id]));
    emit(&cat(&[b"reason=", reason]));
    log(&cat(&[verdict, b": ", reason]));
    0
}

fn is_hex(s: &[u8]) -> bool {
    !s.is_empty() && s.len() >= 40 && s.len() <= 64 && s.iter().all(|&c| c.is_ascii_hexdigit())
}

fn is_valid_check_name(s: &[u8]) -> bool {
    if s.is_empty() {
        return false;
    }
    let first = s[0];
    if !(first.is_ascii_lowercase() || first.is_ascii_digit()) {
        return false;
    }
    s.iter()
        .all(|&c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
}

fn is_workflow_path(s: &[u8]) -> bool {
    let prefix = b".github/workflows/";
    if !s.starts_with(prefix) {
        return false;
    }
    let rest = &s[prefix.len()..];
    if rest.is_empty() {
        return false;
    }
    // Must end in .yml or .yaml
    let ends_yml = rest.ends_with(b".yml");
    let ends_yaml = rest.ends_with(b".yaml");
    if !ends_yml && !ends_yaml {
        return false;
    }
    // Characters before the extension must be [A-Za-z0-9._-]
    let name_end = if ends_yaml {
        rest.len() - 5
    } else {
        rest.len() - 4
    };
    let name = &rest[..name_end];
    if name.is_empty() {
        return false;
    }
    name.iter()
        .all(|&c| c.is_ascii_alphanumeric() || c == b'.' || c == b'_' || c == b'-')
}

fn has_nonzero_hex(s: &[u8]) -> bool {
    s.iter()
        .any(|&c| c != b'0' && c.is_ascii_hexdigit() && c != b'\n')
}

fn basename_of_path(p: &[u8]) -> Vec<u8> {
    match p.iter().rposition(|&c| c == b'/') {
        Some(i) => p[i + 1..].to_vec(),
        None => p.to_vec(),
    }
}

fn gh_api(path: &[u8]) -> Option<Vec<u8>> {
    let r = capture(
        0,
        Command::new("gh")
            .arg("api")
            .arg(shell_compat::os(path))
            .stderr(std::process::Stdio::null()),
    );
    if r.ok() {
        Some(r.stdout)
    } else {
        None
    }
}

fn jq_raw(json: &[u8], filter: &str) -> Option<Vec<u8>> {
    let mut cmd = Command::new("jq");
    cmd.arg("-r")
        .arg(filter)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                let _ = stdin.write_all(json);
            }
            match child.wait_with_output() {
                Ok(o) if o.status.success() => Some(subst(o.stdout)),
                _ => None,
            }
        }
        Err(_) => None,
    }
}

fn jq_raw_with_args(json: &[u8], args: &[(&str, &[u8])], filter: &str) -> Option<Vec<u8>> {
    let mut cmd = Command::new("jq");
    cmd.arg("-r");
    for (name, val) in args {
        cmd.arg("--arg");
        cmd.arg(*name);
        cmd.arg(shell_compat::os(val));
    }
    cmd.arg(filter)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                let _ = stdin.write_all(json);
            }
            match child.wait_with_output() {
                Ok(o) if o.status.success() => Some(subst(o.stdout)),
                _ => None,
            }
        }
        Err(_) => None,
    }
}

fn jq_er_with_args(json: &[u8], args: &[(&str, &[u8])], filter: &str) -> Option<Vec<u8>> {
    let mut cmd = Command::new("jq");
    cmd.arg("-er");
    for (name, val) in args {
        cmd.arg("--arg");
        cmd.arg(*name);
        cmd.arg(shell_compat::os(val));
    }
    cmd.arg(filter)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                let _ = stdin.write_all(json);
            }
            match child.wait_with_output() {
                Ok(o) if o.status.success() => Some(subst(o.stdout)),
                _ => None,
            }
        }
        Err(_) => None,
    }
}

fn grep_m1_e(pattern: &[u8], text: &[u8]) -> Option<Vec<u8>> {
    let mut cmd = Command::new("grep");
    cmd.arg("-m1")
        .arg("-E")
        .arg(shell_compat::os(pattern))
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());
    match cmd.spawn() {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                use std::io::Write;
                let _ = stdin.write_all(text);
            }
            match child.wait_with_output() {
                Ok(o) if o.status.success() => Some(subst(o.stdout)),
                _ => None,
            }
        }
        Err(_) => None,
    }
}

fn get_tree_hash() -> Vec<u8> {
    let r = capture(
        0,
        Command::new("git")
            .arg("rev-parse")
            .arg("--verify")
            .arg("--quiet")
            .arg("HEAD^{tree}")
            .stderr(std::process::Stdio::null()),
    );
    if r.ok() {
        subst(r.stdout)
    } else {
        Vec::new()
    }
}

fn get_head_sha() -> Vec<u8> {
    let r = capture(
        0,
        Command::new("git")
            .arg("rev-parse")
            .arg("--verify")
            .arg("--quiet")
            .arg("HEAD")
            .stderr(std::process::Stdio::null()),
    );
    if r.ok() {
        subst(r.stdout)
    } else {
        Vec::new()
    }
}

fn do_lookup(repo: &[u8], marker: &[u8], check: &[u8], workflow_path: &[u8]) -> i32 {
    let api_path = cat(&[
        b"repos/",
        repo,
        b"/actions/artifacts?name=",
        marker,
        b"&per_page=30",
    ]);
    let found = match gh_api(&api_path) {
        Some(f) => f,
        None => return finish(b"miss", b"could not list artifacts", b""),
    };

    let jq_filter = concat!(
        "[.artifacts[]?",
        " | select(.name == $name and .expired == false)",
        " | select(.workflow_run.id != null)",
        " | select(.workflow_run.head_repository_id == .workflow_run.repository_id)]",
        " | sort_by(.created_at) | reverse | .[].workflow_run.id"
    );
    let runs = match jq_raw_with_args(&found, &[("name", marker)], jq_filter) {
        Some(r) => r,
        None => return finish(b"miss", b"could not read the artifact list", b""),
    };

    if runs.is_empty() {
        return finish(
            b"miss",
            &cat(&[b"no earlier run passed ", check, b" on this exact tree"]),
            b"",
        );
    }

    let mut why = b"no matching run".to_vec();
    for id_line in shell_compat::lines(&runs) {
        if id_line.is_empty() {
            continue;
        }
        let id_s = std::str::from_utf8(&id_line).unwrap_or("");
        if id_s.parse::<u64>().is_err() {
            continue;
        }

        let run_path = cat(&[b"repos/", repo, b"/actions/runs/", &id_line]);
        let run_json = match gh_api(&run_path) {
            Some(r) => r,
            None => {
                why = cat(&[b"could not read run ", &id_line]);
                continue;
            }
        };

        let jq_validate = concat!(
            "if .event != \"pull_request\" then \"run \\(.id) is a \\(.event) run, not a pull_request run\"",
            " elif .conclusion != \"success\" then \"run \\(.id) concluded \\(.conclusion // \"nothing yet\")\"",
            " elif .head_repository.full_name != $repo then \"run \\(.id) came from a fork\"",
            " elif $path != \"\" and .path != $path then \"run \\(.id) is of \\(.path), not \\($path)\"",
            " else \"\" end"
        );
        let bad = match jq_raw_with_args(
            &run_json,
            &[("repo", repo), ("path", workflow_path)],
            jq_validate,
        ) {
            Some(b) => b,
            None => {
                why = cat(&[b"could not read run ", &id_line]);
                continue;
            }
        };

        if bad.is_empty() {
            return finish(
                b"hit",
                &cat(&[
                    b"run ",
                    &id_line,
                    b" passed ",
                    check,
                    b" on this exact tree",
                ]),
                &id_line,
            );
        }
        why = bad;
    }

    finish(b"miss", &why, b"")
}

fn do_queued(repo: &[u8], tree: &[u8]) -> i32 {
    let path = env_or_empty("WORKFLOW_PATH");
    if !is_workflow_path(&path) {
        return finish(b"miss", b"WORKFLOW_PATH is not a workflow file", b"");
    }

    let forced = shell_compat::env_or("FORCED_PUSH", b"false");
    if forced == b"true" {
        return finish(b"miss", b"a forced push rewrote main's history", b"");
    }

    let before = env_or_empty("PUSH_BEFORE");
    if !is_hex(&before) || !has_nonzero_hex(&before) {
        return finish(b"miss", b"no commit before this push to compare with", b"");
    }

    let head = get_head_sha();
    if head.is_empty() {
        return finish(b"miss", b"could not read HEAD", b"");
    }

    // List changed files
    let compare_path = cat(&[b"repos/", repo, b"/compare/", &before, b"...", &head]);
    let files_json = match gh_api(&compare_path) {
        Some(f) => f,
        None => return finish(b"miss", b"could not list the files this push changed", b""),
    };

    let files = match jq_er_with_args(
        &files_json,
        &[],
        "if (.files | length) >= 300 then error(\"too many\") else .files[].filename end",
    ) {
        Some(f) => f,
        None => return finish(b"miss", b"could not list the files this push changed", b""),
    };

    // Check cache key files
    let keys = shell_compat::env_or(
        "CACHE_KEY_REGEX",
        b"(^|/)(MODULE\\.bazel(\\.lock)?|\\.bazelversion|\\.bazelrc|go\\.(mod|sum|work|work\\.sum)|\\.xcode-version|\\.golangci\\.ya?ml)$",
    );
    if let Some(hit_file) = grep_m1_e(&keys, &files) {
        return finish(
            b"miss",
            &cat(&[
                &hit_file,
                b" changed, and caches keyed on it are saved only by a full run on main",
            ]),
            b"",
        );
    }

    // List merge_group runs
    let wf_basename = basename_of_path(&path);
    let runs_path = cat(&[
        b"repos/",
        repo,
        b"/actions/workflows/",
        &wf_basename,
        b"/runs?event=merge_group&status=success&per_page=30",
    ]);
    let found = match gh_api(&runs_path) {
        Some(f) => f,
        None => return finish(b"miss", b"could not list merge queue runs", b""),
    };

    let jq_filter = concat!(
        "[.workflow_runs[]?",
        " | select(.event == \"merge_group\" and .conclusion == \"success\")",
        " | select(.head_repository.full_name == $repo and .path == $path)",
        " | select(.head_commit.tree_id == $tree)]",
        " | first | .id // \"\""
    );
    let id = match jq_raw_with_args(
        &found,
        &[("tree", tree), ("repo", repo), ("path", &path)],
        jq_filter,
    ) {
        Some(i) => i,
        None => return finish(b"miss", b"could not read the merge queue runs", b""),
    };

    // Validate the id is numeric
    let id_s = std::str::from_utf8(&id).unwrap_or("");
    if id_s.parse::<u64>().is_err() {
        return finish(
            b"miss",
            &cat(&[
                b"no green merge queue run of ",
                &wf_basename,
                b" on this exact tree",
            ]),
            b"",
        );
    }

    finish(
        b"hit",
        &cat(&[
            b"merge queue run ",
            &id,
            b" passed ",
            &wf_basename,
            b" on this exact tree",
        ]),
        &id,
    )
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let mode = if !args.is_empty() {
        args[0].clone()
    } else {
        Vec::new()
    };
    let check_arg = if args.len() > 1 {
        args[1].clone()
    } else {
        Vec::new()
    };

    let check = match mode.as_slice() {
        b"tree" => {
            if check_arg.is_empty() {
                b"presubmit".to_vec()
            } else {
                check_arg.clone()
            }
        }
        b"lookup" => check_arg.clone(),
        b"queued" => b"presubmit".to_vec(),
        _ => {
            log(b"usage: queue-fast-pass.sh tree | lookup <check> | queued");
            return 2;
        }
    };

    if !is_valid_check_name(&check) {
        log(&cat(&[
            b"check name must be lowercase letters, digits and dashes, got '",
            &check,
            b"'",
        ]));
        return 2;
    }

    let tree = get_tree_hash();
    if !is_hex(&tree) {
        emit(b"tree=");
        emit(b"marker=");
        if mode == b"tree" {
            return 0;
        }
        return finish(b"miss", b"could not read the tree hash of HEAD", b"");
    }

    let marker = cat(&[b"passed-", &check, b"-", &tree]);
    emit(&cat(&[b"tree=", &tree]));
    emit(&cat(&[b"marker=", &marker]));

    if mode == b"tree" {
        return 0;
    }

    let repo = env_or_empty("GITHUB_REPOSITORY");
    if repo.is_empty() {
        return finish(b"miss", b"GITHUB_REPOSITORY is not set", b"");
    }

    if mode == b"queued" {
        return do_queued(&repo, &tree);
    }

    let workflow_path = env_or_empty("WORKFLOW_PATH");
    do_lookup(&repo, &marker, &check, &workflow_path)
}
