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

//! affected-targets.sh — build + test the repo against the BuildBuddy remote,
//! skipping only the diffs that provably need no Bazel work at all.

use shell_compat::{
    capture, cat, env, env_or, env_or_empty, indent, is_file, os, out, status, subst,
};
use std::process::Command;

fn grep_ere(text: &[u8], pattern: &[u8]) -> bool {
    if pattern.is_empty() || text.is_empty() {
        return false;
    }
    let mut cmd = Command::new("grep");
    cmd.arg("-E").arg(os(pattern));
    shell_compat::status_with_input(0, &mut cmd, text, true) == 0
}

fn grep_ere_invert(text: &[u8], pattern: &[u8]) -> Vec<u8> {
    if pattern.is_empty() {
        return text.to_vec();
    }
    let mut cmd = Command::new("grep");
    cmd.arg("-Ev")
        .arg(os(pattern))
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
                Ok(o) => subst(o.stdout),
                Err(_) => Vec::new(),
            }
        }
        Err(_) => Vec::new(),
    }
}

fn grep_evc(text: &[u8], pattern: &[u8]) -> Vec<u8> {
    if pattern.is_empty() {
        return text.to_vec();
    }
    let mut cmd = Command::new("grep");
    cmd.arg("-E")
        .arg("-v")
        .arg("-c")
        .arg(os(pattern))
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
                Ok(o) => subst(o.stdout),
                Err(_) => b"0".to_vec(),
            }
        }
        Err(_) => b"0".to_vec(),
    }
}

fn grep_ere_output(text: &[u8], pattern: &[u8]) -> Vec<u8> {
    if pattern.is_empty() {
        return Vec::new();
    }
    let mut cmd = Command::new("grep");
    cmd.arg("-E")
        .arg(os(pattern))
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
                Ok(o) if o.status.success() => subst(o.stdout),
                _ => Vec::new(),
            }
        }
        Err(_) => Vec::new(),
    }
}

fn jq_str(json: &[u8], filter: &str) -> Vec<u8> {
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
                Ok(o) if o.status.success() => subst(o.stdout),
                _ => Vec::new(),
            }
        }
        Err(_) => Vec::new(),
    }
}

fn jq_lines(json: &[u8], filter: &str) -> Vec<Vec<u8>> {
    let raw = jq_str(json, filter);
    if raw.is_empty() {
        return Vec::new();
    }
    shell_compat::lines(&raw)
}

fn is_global_impact(changed_files: &[u8]) -> bool {
    if changed_files.is_empty() {
        return false;
    }
    let gi_1 = grep_ere(
        changed_files,
        b"^(MODULE\\.bazel|MODULE\\.bazel\\.lock|\\.bazelrc|\\.bazelversion|BUILD$|gazelle_python\\.yaml$)",
    );
    if gi_1 {
        return true;
    }
    let tools_lines = grep_ere_output(changed_files, b"^tools/");
    if !tools_lines.is_empty() {
        let excluded = grep_ere_invert(
            &tools_lines,
            b"^tools/(ci/|cluster/|conformance/|copybara/|deploy/|doctor/|format/|gcp-secrets/|gitops/|license/|lint/|release/|rotate-buildbuddy-key/|saas-cli/|scripts/|sync-env-secrets/|worktree/|owners/|boundaries/|pipeline/|repin$)",
        );
        if !excluded.is_empty() {
            return true;
        }
    }
    false
}

fn run_full_sweep(reason: &[u8], class: &[u8], bb_key: &[u8]) -> ! {
    if class == b"expected" {
        out(&cat(&[
            b"::notice::affected-targets: full //... sweep (",
            reason,
            b")\n",
        ]));
    } else {
        out(&cat(&[
            b"::warning title=affected-selection-fallback::affected-targets fast path degraded -- full //... sweep (",
            reason,
            b")\n",
        ]));
        if let Some(summary_path) = env("GITHUB_STEP_SUMMARY") {
            if !summary_path.is_empty() {
                let data = cat(&[
                    b"### \xe2\x9a\xa0 affected-selection fallback (degraded)\n\n",
                    b"- reason: ",
                    reason,
                    b"\n",
                    b"- consequence: this run paid a full `//...` sweep instead of affected targets\n",
                    b"- if this recurs across runs, the fast path is broken (see #503): check the TD pin in `tools/ci/td-lib.sh` and the runner platform\n",
                ]);
                let _ = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(shell_compat::path(&summary_path))
                    .and_then(|mut f| {
                        use std::io::Write;
                        f.write_all(&data)
                    });
            }
        }
    }
    let remote_config = cat(&[b"--config=remote"]);
    let remote_header = cat(&[b"--remote_header=x-buildbuddy-api-key=", bb_key]);
    status(
        0,
        Command::new("bazel")
            .arg("build")
            .arg(os(&remote_config))
            .arg(os(&remote_header))
            .arg("//..."),
        false,
    );
    status(
        0,
        Command::new("bazel")
            .arg("test")
            .arg(os(&remote_config))
            .arg(os(&remote_header))
            .arg("//..."),
        false,
    );
    std::process::exit(0);
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let bb_key = env_or_empty("BUILDBUDDY_API_KEY");
    let base_ref = env_or_empty("BASE_REF");
    let mut before_rev = env_or_empty("BEFORE_REV");
    let forced_push = env_or("FORCED_PUSH", b"false");

    // --- 1. before-revision ---
    if forced_push == b"true" {
        run_full_sweep(
            b"forced push -- no trustworthy diff base",
            b"expected",
            &bb_key,
        );
    }

    if !before_rev.is_empty() {
        let r = capture(
            0,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(os(&cat(&[&before_rev, b"^{commit}"]))),
        );
        if !r.ok() {
            run_full_sweep(
                &cat(&[
                    b"BEFORE_REV '",
                    &before_rev,
                    b"' does not resolve to a commit",
                ]),
                b"expected",
                &bb_key,
            );
        }
        out(&cat(&[
            b"affected-targets: before-rev (explicit) = ",
            &before_rev,
            b"\n",
        ]));
    } else if !base_ref.is_empty() {
        let r = capture(
            0,
            Command::new("git")
                .arg("merge-base")
                .arg(os(&cat(&[b"origin/", &base_ref])))
                .arg("HEAD"),
        );
        if !r.ok() {
            run_full_sweep(
                &cat(&[b"could not compute merge-base against origin/", &base_ref]),
                b"degraded",
                &bb_key,
            );
        }
        before_rev = subst(r.stdout);
        out(&cat(&[
            b"affected-targets: before-rev (merge-base) = ",
            &before_rev,
            b"\n",
        ]));
    } else {
        run_full_sweep(
            b"neither BEFORE_REV nor BASE_REF is set",
            b"degraded",
            &bb_key,
        );
    }

    // --- 2. global-impact guard ---
    let diff_r = capture(
        0,
        Command::new("git")
            .arg("diff")
            .arg("--name-only")
            .arg(os(&before_rev))
            .arg("--"),
    );
    let changed_files = subst(diff_r.stdout);
    if changed_files.is_empty() {
        out(&cat(&[
            b"affected-targets: no changed files detected vs ",
            &before_rev,
            b"; nothing to do.\n",
        ]));
        return 0;
    }
    out(b"affected-targets: changed files:\n");
    out(&indent(&changed_files));
    out(b"\n");

    // --- docs/metadata-only fast path ---
    let non_doc = grep_evc(
        &changed_files,
        b"^(gitops/|docs/|\\.agents/(agents|skills|rules)/|apps/web/vitruviansoftware-dev/)|\\.(\
md|png|jpg|jpeg|svg|txt)$|(^|/)(catalog-info\\.yaml|OWNERS|CODEOWNERS)$",
    );
    let non_doc_count: i64 = std::str::from_utf8(&non_doc)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    if non_doc_count == 0 {
        out(b"::notice::affected-targets: all changed files are docs/gitops/markdown/metadata-only \xe2\x86\x92 nothing to build or test.\n");
        return 0;
    }

    if is_global_impact(&changed_files) {
        run_full_sweep(
            b"global-impact file changed (MODULE.bazel/lockfile/.bazelrc/.bazelversion/tools/**/root BUILD/gazelle_python.yaml)",
            b"expected",
            &bb_key,
        );
    }

    // --- 3. Change detection plan via //tools/pipeline:plan ---
    let rdeps_map = env_or_empty("RDEPS_MAP");
    let plan_budget_sec: i64 = std::str::from_utf8(&env_or("PLAN_BUDGET_SEC", b"120"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(120);

    let mut plan_base = before_rev.clone();
    let map_max_behind: i64 = std::str::from_utf8(&env_or("MAP_MAX_BEHIND", b"9"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(9);

    if !rdeps_map.is_empty() && is_file(&rdeps_map) {
        let map_commit = jq_str(
            &std::fs::read(shell_compat::path(&rdeps_map)).unwrap_or_default(),
            ".commit // \"\"",
        );
        let base_sha_r = capture(
            0,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(os(&cat(&[&before_rev, b"^{commit}"]))),
        );
        let base_sha = subst(base_sha_r.stdout);

        let is_hex40 = map_commit.len() == 40 && map_commit.iter().all(|&b| b.is_ascii_hexdigit());

        if is_hex40 && !base_sha.is_empty() && map_commit != base_sha {
            let anc = status(
                0,
                Command::new("git")
                    .arg("merge-base")
                    .arg("--is-ancestor")
                    .arg(os(&map_commit))
                    .arg(os(&base_sha)),
                true,
            );
            if anc != 0 {
                out(&cat(&[
                    b"affected-targets: dependency map is for ",
                    &map_commit[..12.min(map_commit.len())],
                    b", not an ancestor of the diff base -- not used\n",
                ]));
            } else {
                let behind_r = capture(
                    0,
                    Command::new("git")
                        .arg("rev-list")
                        .arg("--count")
                        .arg(os(&cat(&[&map_commit, b"..", &base_sha]))),
                );
                let behind: i64 = std::str::from_utf8(&subst(behind_r.stdout))
                    .ok()
                    .and_then(|s| s.trim().parse().ok())
                    .unwrap_or(0);
                if behind > map_max_behind {
                    out(&cat(&[
                        b"affected-targets: dependency map is ",
                        behind.to_string().as_bytes(),
                        b" commits behind the diff base (limit ",
                        map_max_behind.to_string().as_bytes(),
                        b") -- not used\n",
                    ]));
                } else {
                    let gi_diff_r = capture(
                        0,
                        Command::new("git")
                            .arg("diff")
                            .arg("--name-only")
                            .arg(os(&map_commit))
                            .arg(os(&base_sha))
                            .arg("--"),
                    );
                    let gi_files = subst(gi_diff_r.stdout);
                    if is_global_impact(&gi_files) {
                        out(&cat(&[
                            b"affected-targets: a global-impact file changed since the dependency map at ",
                            &map_commit[..12.min(map_commit.len())],
                            b" -- not used\n",
                        ]));
                    } else {
                        plan_base = map_commit.clone();
                        out(&cat(&[
                            b"affected-targets: no dependency map for the diff base yet; using the one from ",
                            behind.to_string().as_bytes(),
                            b" commit(s) back (",
                            &map_commit[..12.min(map_commit.len())],
                            b") and treating everything changed since then as changed\n",
                        ]));
                    }
                }
            }
        }
    }

    let plan_err_file = shell_compat::mktemp_file(b"plan-err.XXXXXX").unwrap_or_default();

    let mut plan_args: Vec<Vec<u8>> = Vec::new();
    plan_args.push(cat(&[b"--base=", &plan_base]));
    plan_args.push(b"--head=HEAD".to_vec());
    plan_args.push(b"--format=json".to_vec());
    if !rdeps_map.is_empty() {
        plan_args.push(cat(&[b"--rdeps-map=", &rdeps_map]));
    }

    let plan_bin = env_or_empty("PLAN_BIN");
    let plan_start = std::time::Instant::now();
    let plan_output;

    if !plan_bin.is_empty() && is_file(&plan_bin) {
        let mut cmd = Command::new(os(&plan_bin));
        for a in &plan_args {
            cmd.arg(os(a));
        }
        cmd.arg(os(&cat(&[
            b"--repo-root=",
            &shell_compat::path_bytes(&std::env::current_dir().unwrap_or_default()),
        ])));
        let r = capture(0, &mut cmd);
        let _ = std::fs::write(shell_compat::path(&plan_err_file), &r.stderr);
        plan_output = subst(r.stdout);
    } else {
        let mut cmd = Command::new("bazel");
        cmd.arg("run").arg("//tools/pipeline:plan").arg("--");
        for a in &plan_args {
            cmd.arg(os(a));
        }
        let r = capture(0, &mut cmd);
        let _ = std::fs::write(shell_compat::path(&plan_err_file), &r.stderr);
        plan_output = subst(r.stdout);
    }

    let plan_secs = plan_start.elapsed().as_secs();

    if plan_output.is_empty() {
        out(&cat(&[
            b"affected-targets: planner produced no plan after ",
            plan_secs.to_string().as_bytes(),
            b"s; last lines of its output:\n",
        ]));
        let tail_r = capture(
            0,
            Command::new("tail")
                .arg("-n")
                .arg("30")
                .arg(os(&plan_err_file)),
        );
        out(&subst(tail_r.stdout));
        out(b"\n");
        run_full_sweep(
            b"change detection plan failed -- fail-closed fallback",
            b"degraded",
            &bb_key,
        );
    }

    let is_docs_only = jq_str(&plan_output, ".is_docs_only // false");
    let is_full_sweep = jq_str(&plan_output, ".is_global_impact // false");
    let plan_source = jq_str(&plan_output, ".plan_source // \"\"");
    let targets = jq_lines(&plan_output, ".targets[]?");
    let affected_packages = jq_lines(&plan_output, ".affected_packages[]?");

    out(&cat(&[
        b"affected-targets: plan took ",
        plan_secs.to_string().as_bytes(),
        b"s (source: ",
        if plan_source.is_empty() {
            b"none" as &[u8]
        } else {
            &plan_source
        },
        b")\n",
    ]));

    // Show planner stderr lines about the dependency map.
    if let Ok(plan_err_content) = std::fs::read(shell_compat::path(&plan_err_file)) {
        let filtered = grep_ere_output(
            &plan_err_content,
            b"(no dependency map for|dependency map not used)",
        );
        if !filtered.is_empty() {
            out(&filtered);
            out(b"\n");
        }
    }

    let plan_source_note = jq_str(&plan_output, ".plan_source_note // empty");
    if !plan_source_note.is_empty() {
        out(&cat(&[b"affected-targets: ", &plan_source_note, b"\n"]));
    }

    if plan_source == b"rdeps-map" && plan_secs as i64 > plan_budget_sec {
        out(&cat(&[
            b"::warning title=affected-selection-slow::affected-targets: the plan used the dependency map but still took ",
            plan_secs.to_string().as_bytes(),
            b"s (budget ",
            plan_budget_sec.to_string().as_bytes(),
            b"s)\n",
        ]));
    }

    if is_docs_only == b"true" {
        out(b"::notice::affected-targets: all changed files are docs/gitops/markdown-only \xe2\x86\x92 nothing to build or test.\n");
        return 0;
    }

    if is_full_sweep == b"true" || targets.is_empty() {
        run_full_sweep(
            b"full sweep required by change detection plan",
            b"expected",
            &bb_key,
        );
    }

    let remote_config = cat(&[b"--config=remote"]);
    let remote_header = cat(&[b"--remote_header=x-buildbuddy-api-key=", &bb_key]);

    let mut final_targets = targets.clone();
    let mut test_args: Vec<Vec<u8>> = Vec::new();

    if plan_source == b"rdeps-map" {
        if affected_packages.is_empty() {
            run_full_sweep(
                b"dependency-map plan lists no changed packages",
                b"degraded",
                &bb_key,
            );
        }

        let mut pkg_set: Vec<Vec<u8>> = Vec::new();
        for p in &affected_packages {
            let mut entry = p.clone();
            if !entry.ends_with(b":all") {
                entry.extend_from_slice(b":all");
            }
            pkg_set.push(entry);
        }

        let mut kept: Vec<Vec<u8>> = Vec::new();
        for t in &targets {
            let label_pkg = if let Some(idx) = t.iter().position(|&b| b == b':') {
                cat(&[&t[..idx], b":all"])
            } else {
                cat(&[t.as_slice(), b":all"])
            };
            if pkg_set.iter().any(|p| *p == label_pkg) {
                continue;
            }
            kept.push(t.clone());
        }

        final_targets = kept;
        for p in &affected_packages {
            final_targets.push(p.clone());
        }

        test_args.push(b"--build_tests_only".to_vec());
    }

    out(&cat(&[
        b"affected-targets: executing ",
        final_targets.len().to_string().as_bytes(),
        b" affected test targets:\n",
    ]));
    for t in &final_targets {
        out(&cat(&[b"  ", t, b"\n"]));
    }

    let mut cmd = Command::new("bazel");
    cmd.arg("test")
        .arg(os(&remote_config))
        .arg(os(&remote_header));
    for a in &test_args {
        cmd.arg(os(a));
    }
    for t in &final_targets {
        cmd.arg(os(t));
    }
    let rc = status(0, &mut cmd, false);

    if rc == 4 && plan_source == b"rdeps-map" {
        run_full_sweep(
            b"no tests left in the changed packages",
            b"expected",
            &bb_key,
        );
    }

    rc
}
