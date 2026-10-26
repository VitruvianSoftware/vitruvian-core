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

//! deploy-affected.sh — decide whether a push to main affects an app's
//! deployable artifacts, using the Bazel graph (target-determinator) instead
//! of directory path globs.

use shell_compat::{
    capture, cat, env, env_or_empty, err, indent, is_file, mktemp_dir, os, out, status, subst,
};
use std::process::Command;

const TD_VERSION: &str = "v0.34.0";
const TD_SHA256: &str = "115e1c63d39e2cd0d0b011c9fadc80f059f021176a4ae0de2232cdd83b1f8011";

fn emit(value: &[u8], reason: &[u8], class: &[u8]) -> i32 {
    out(&cat(&[
        b"deploy-affected: affected=",
        value,
        b" (",
        reason,
        b")\n",
    ]));
    if class == b"degraded" {
        out(&cat(&[
            b"::warning title=deploy-gate-fallback::deploy gate degraded -- failing OPEN to deploy (",
            reason,
            b")\n",
        ]));
        if let Some(summary_path) = env("GITHUB_STEP_SUMMARY") {
            if !summary_path.is_empty() {
                let data = cat(&[
                    b"### \xe2\x9a\xa0 deploy-gate fallback (degraded)\n\n",
                    b"- reason: ", reason, b"\n",
                    b"- consequence: deployed without graph attribution (fail-open, idempotent blue-green)\n",
                    b"- if this recurs, the gate fast path is broken (see #503): check tools/ci/td-lib.sh\n",
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
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&cat(&[b"affected=", value, b"\n"]))
                });
        }
    }
    if value == b"true" || value == b"false" {
        0
    } else {
        1
    }
}

fn grep_ere(text: &[u8], pattern: &[u8]) -> bool {
    if pattern.is_empty() {
        return false;
    }
    let mut cmd = Command::new("grep");
    cmd.arg("-E").arg(os(pattern));
    shell_compat::status_with_input(0, &mut cmd, text, true) == 0
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

fn fetch_td() -> Result<Vec<u8>, Vec<u8>> {
    if let Some(bin) = env("TD_BIN") {
        if !bin.is_empty() {
            if is_file(&bin) {
                out(&cat(&[b"td-lib: using TD_BIN override at ", &bin, b"\n"]));
                return Ok(bin);
            }
            return Err(cat(&[b"TD_BIN='", &bin, b"' is not an executable"]));
        }
    }

    let r = capture(0, Command::new("uname").arg("-s"));
    let uname_s = subst(r.stdout);
    let r2 = capture(0, Command::new("uname").arg("-m"));
    let uname_m = subst(r2.stdout);

    if uname_s != b"Linux" || uname_m != b"x86_64" {
        return Err(cat(&[
            b"no pinned target-determinator binary for ",
            &uname_s,
            b"/",
            &uname_m,
        ]));
    }

    let asset = b"target-determinator.linux.amd64";
    let tmp = mktemp_dir().map_err(|e| format!("mktemp failed: {}", e).into_bytes())?;
    let td_path = cat(&[&tmp, b"/target-determinator"]);
    let url = cat(&[
        b"https://github.com/bazel-contrib/target-determinator/releases/download/",
        TD_VERSION.as_bytes(),
        b"/",
        asset,
    ]);
    out(&cat(&[
        b"td-lib: downloading target-determinator ",
        TD_VERSION.as_bytes(),
        b" (",
        asset,
        b")...\n",
    ]));
    let rc = status(
        82,
        Command::new("curl")
            .arg("-fsSL")
            .arg("--retry")
            .arg("4")
            .arg("--retry-delay")
            .arg("2")
            .arg("--retry-all-errors")
            .arg("-o")
            .arg(os(&td_path))
            .arg(os(&url)),
        false,
    );
    if rc != 0 {
        return Err(cat(&[b"target-determinator download failed (", &url, b")"]));
    }

    let sha_file = cat(&[&td_path, b".sha256"]);
    let sha_content = cat(&[TD_SHA256.as_bytes(), b"  ", &td_path]);
    let _ = shell_compat::write_file(&sha_file, &sha_content, 0o644);

    let rc = status(
        87,
        Command::new("sha256sum")
            .arg("--check")
            .arg("--status")
            .arg(os(&sha_file)),
        true,
    );
    if rc != 0 {
        return Err(cat(&[
            b"target-determinator checksum mismatch (expected ",
            TD_SHA256.as_bytes(),
            b" for ",
            asset,
            b")",
        ]));
    }

    let _ = std::fs::set_permissions(
        shell_compat::path(&td_path),
        std::os::unix::fs::PermissionsExt::from_mode(0o755),
    );
    Ok(td_path)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let deploy_targets = env_or_empty("DEPLOY_TARGETS");
    let extra_path_regex = env_or_empty("EXTRA_PATH_REGEX");
    let exclude_path_regex = env_or_empty("EXCLUDE_PATH_REGEX");
    let before_rev = env_or_empty("BEFORE_REV");
    let after_rev = shell_compat::env_or("AFTER_REV", b"HEAD");
    let forced_push = shell_compat::env_or("FORCED_PUSH", b"false");

    if deploy_targets.is_empty() && extra_path_regex.is_empty() {
        err(b"deploy-affected: DEPLOY_TARGETS is unset (path-only mode) but EXTRA_PATH_REGEX is also empty -- refusing to run with no affected signal at all\n");
        return 1;
    }

    // 1. diff base
    if forced_push == b"true" {
        return emit(
            b"true",
            b"forced push -- no trustworthy diff base",
            b"expected",
        );
    }
    if before_rev.is_empty() {
        return emit(
            b"true",
            &cat(&[b"BEFORE_REV '' unset or does not resolve to a commit"]),
            b"expected",
        );
    }
    let r = capture(
        123,
        Command::new("git")
            .arg("rev-parse")
            .arg("--verify")
            .arg("--quiet")
            .arg(os(&cat(&[&before_rev, b"^{commit}"]))),
    );
    if !r.ok() {
        return emit(
            b"true",
            &cat(&[
                b"BEFORE_REV '",
                &before_rev,
                b"' unset or does not resolve to a commit",
            ]),
            b"expected",
        );
    }

    let diff_r = capture(
        127,
        Command::new("git")
            .arg("diff")
            .arg("--name-only")
            .arg(os(&before_rev))
            .arg(os(&after_rev))
            .arg("--"),
    );
    let changed_files = subst(diff_r.stdout);
    if changed_files.is_empty() {
        return emit(
            b"false",
            &cat(&[b"no changed files vs ", &before_rev]),
            b"expected",
        );
    }
    out(b"deploy-affected: changed files:\n");
    out(&indent(&changed_files));
    out(b"\n");

    // Release-please guard
    let range_r = capture(
        149,
        Command::new("git")
            .arg("log")
            .arg("--pretty=%s")
            .arg(os(&cat(&[&before_rev, b"..", &after_rev]))),
    );
    let range_msgs = subst(range_r.stdout);
    if !range_msgs.is_empty() {
        let non_release = grep_ere_invert(&range_msgs, b"^chore\\((main|release)\\): release");
        if non_release.is_empty() {
            let first_msg = shell_compat::first_line(&range_msgs);
            return emit(
                b"false",
                &cat(&[
                    b"every commit in ",
                    &before_rev,
                    b"..",
                    &after_rev,
                    b" is a release-please version bump ('",
                    &first_msg,
                    b"') -- skipping dev deploy (promotes via release tag)",
                ]),
                b"expected",
            );
        }
    }

    // 2. non-graph inputs
    if !extra_path_regex.is_empty() {
        let anchored = cat(&[b"^(", &extra_path_regex, b")"]);
        let matched = grep_ere_output(&changed_files, &anchored);
        let matched = if !exclude_path_regex.is_empty() && !matched.is_empty() {
            let excl = cat(&[b"^(", &exclude_path_regex, b")"]);
            grep_ere_invert(&matched, &excl)
        } else {
            matched
        };
        if !matched.is_empty() {
            let reason = if !exclude_path_regex.is_empty() {
                cat(&[
                    b"path matched ",
                    &extra_path_regex,
                    b" (excluding ",
                    &exclude_path_regex,
                    b")",
                ])
            } else {
                cat(&[b"path matched ", &extra_path_regex])
            };
            return emit(b"true", &reason, b"expected");
        }
    }

    if deploy_targets.is_empty() {
        return emit(
            b"false",
            b"no path matched (path-only mode -- DEPLOY_TARGETS unset, no graph universe to attribute against)",
            b"expected",
        );
    }

    // 3. global-impact guard
    let gi_1 = grep_ere(
        &changed_files,
        b"^(MODULE\\.bazel|MODULE\\.bazel\\.lock|\\.bazelrc|\\.bazelversion|BUILD$|gazelle_python\\.yaml$)",
    );
    let gi_2 = if !gi_1 {
        let tools_lines = grep_ere_output(&changed_files, b"^tools/");
        if !tools_lines.is_empty() {
            let excluded = grep_ere_invert(
                &tools_lines,
                b"^tools/(ci/|cluster/|conformance/|copybara/|deploy/|doctor/|format/|gcp-secrets/|gitops/|license/|lint/|release/|rotate-buildbuddy-key/|saas-cli/|scripts/|sync-env-secrets/|worktree/|owners/|boundaries/|pipeline/|repin$)",
            );
            !excluded.is_empty()
        } else {
            false
        }
    } else {
        false
    };
    if gi_1 || gi_2 {
        return emit(b"true", b"global-impact file changed", b"expected");
    }

    // 4. graph attribution
    let td = match fetch_td() {
        Ok(p) => p,
        Err(e) => {
            return emit(
                b"true",
                &cat(&[b"target-determinator unavailable (", &e, b")"]),
                b"degraded",
            );
        }
    };

    let mut td_universe = Vec::new();
    for t in shell_compat::ifs_split(&deploy_targets) {
        if !td_universe.is_empty() {
            td_universe.extend_from_slice(b" + ");
        }
        td_universe.extend_from_slice(&t);
    }

    let bb_key = env_or_empty("BUILDBUDDY_API_KEY");
    out(&cat(&[
        b"deploy-affected: computing affected deploy targets since ",
        &before_rev,
        b" (universe: ",
        &td_universe,
        b")...\n",
    ]));

    let rc = status(
        208,
        Command::new(os(&td))
            .arg("--bazel")
            .arg("bazel")
            .arg("--targets")
            .arg(os(&td_universe))
            .arg("--bazel-opts=--config=remotecache-ci")
            .arg(os(&cat(&[
                b"--bazel-opts=--remote_header=x-buildbuddy-api-key=",
                &bb_key,
            ])))
            .arg("--before-query-error-behavior=ignore-and-build-all")
            .arg(os(&before_rev))
            .stdout({
                let f = std::fs::File::create("deploy-affected.txt").unwrap();
                std::process::Stdio::from(f)
            }),
        false,
    );
    if rc != 0 {
        return emit(
            b"true",
            b"target-determinator returned non-zero",
            b"degraded",
        );
    }

    let content = std::fs::read("deploy-affected.txt").unwrap_or_default();
    if !content.is_empty() && content != b"\n" {
        out(b"deploy-affected: affected deploy target(s):\n");
        out(&indent(&content));
        return emit(
            b"true",
            b"deploy target(s) affected by the diff",
            b"expected",
        );
    }
    emit(
        b"false",
        b"no deploy target affected by the diff",
        b"expected",
    )
}
