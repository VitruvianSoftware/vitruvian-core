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

//! relevant_paths — decide whether a commit's diff warrants running the heavy
//! CI work, or whether it is docs/gitops-only and the heavy steps can be skipped.
//!
//! Emits `relevant=true|false` to $GITHUB_OUTPUT (and stdout). This is a CI
//! *lead-time* optimisation ONLY; it is never the safety floor:
//!
//!   * It FAILS SAFE. Any uncertainty -- missing diff base, a diff we cannot
//!     compute -- yields relevant=true (run the heavy work). The only way to
//!     get relevant=false is a successfully-computed, non-empty diff in which
//!     EVERY changed file is docs/gitops/markdown.
//!
//! A required status check (build-test / tidy-check) calls this from its first
//! step and then gates the heavy steps on the output, so the check ALWAYS
//! reports a status (it just finishes green in seconds when relevant=false) and
//! never leaves a merge-queue PR stuck "pending".
//!
//! Workflows call this through the ./.github/actions/changed-paths-gate action,
//! which fills these in for the event at hand; do not call the tool directly
//! from a workflow.
//!
//! Environment (at least one of the first two must be provided):
//!   BASE_REF     github.base_ref, e.g. "main" (PR lane). Diff base is computed
//!                as the merge-base of origin/$BASE_REF and HEAD.
//!   BEFORE_REV   explicit before-revision (push/merge_group lanes). Used
//!                directly as the diff base when set.
//!   IGNORE_REGEX (optional) ERE matching paths that cannot affect the CALLING
//!                lane's work. Defaults to the docs/gitops/markdown set that
//!                suits the Bazel build lanes.
//!
//!                A caller MUST narrow this when the default set is not inert for
//!                it. license-check is the worked example: addlicense does NOT
//!                ignore gitops/ (gitops manifests carry MIT headers today) and
//!                //tools/license:check is a `bazel run` sh_binary with no
//!                sh_test, so `bazel test //...` -- and therefore the nightly
//!                periodic-full-sweep -- never covers it. Skipping license-check
//!                on a gitops-only diff would let an unlicensed gitops file dodge
//!                a REQUIRED check permanently, with no backstop to catch it.

use shell_compat::{capture, cat, env, env_or, env_or_empty, indent, out, subst};
use std::process::Command;

const DEFAULT_IGNORE: &[u8] =
    b"^(gitops/|docs/|\\.agents/(agents|skills|rules)/|apps/web/vitruviansoftware-dev/)|\\.(\
md|png|jpg|jpeg|svg|txt)$|(^|/)(catalog-info\\.yaml|OWNERS|CODEOWNERS)$";

fn emit(value: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"relevant-paths: relevant=",
        value,
        b" (",
        reason,
        b")\n",
    ]));
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(&cat(&[b"relevant=", value, b"\n"]))
                });
        }
    }
    0
}

fn grep_evc(text: &[u8], pattern: &[u8]) -> Vec<u8> {
    let mut cmd = Command::new("grep");
    cmd.arg("-E")
        .arg("-v")
        .arg("-c")
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
                Ok(o) => subst(o.stdout),
                _ => b"0".to_vec(),
            }
        }
        Err(_) => b"0".to_vec(),
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let mut before_rev = env_or_empty("BEFORE_REV");
    let base_ref = env_or_empty("BASE_REF");

    if !before_rev.is_empty() {
        let r = capture(
            0,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(shell_compat::os(&cat(&[&before_rev, b"^{commit}"]))),
        );
        if !r.ok() {
            return emit(
                b"true",
                &cat(&[
                    b"BEFORE_REV '",
                    &before_rev,
                    b"' does not resolve to a commit -> run",
                ]),
            );
        }
    } else if !base_ref.is_empty() {
        let r = capture(
            0,
            Command::new("git")
                .arg("merge-base")
                .arg(shell_compat::os(&cat(&[b"origin/", &base_ref])))
                .arg("HEAD"),
        );
        if r.ok() {
            before_rev = subst(r.stdout);
        } else {
            return emit(
                b"true",
                &cat(&[
                    b"could not compute merge-base against origin/",
                    &base_ref,
                    b" -> run",
                ]),
            );
        }
    } else {
        return emit(b"true", b"neither BEFORE_REV nor BASE_REF is set -> run");
    }

    let diff_r = capture(
        0,
        Command::new("git")
            .arg("diff")
            .arg("--name-only")
            .arg(shell_compat::os(&before_rev))
            .arg("HEAD"),
    );
    if !diff_r.ok() {
        return emit(
            b"true",
            &cat(&[b"could not compute diff vs ", &before_rev, b" -> run"]),
        );
    }
    let changed_files = subst(diff_r.stdout);
    if changed_files.is_empty() {
        return emit(
            b"true",
            &cat(&[b"no changed files detected vs ", &before_rev, b" -> run"]),
        );
    }

    out(&cat(&[
        b"relevant-paths: changed files vs ",
        &before_rev,
        b":\n",
    ]));
    out(&indent(&changed_files));
    out(b"\n");

    let ignore_regex = env_or("IGNORE_REGEX", DEFAULT_IGNORE);
    let non_ignored = grep_evc(&changed_files, &ignore_regex);
    let count: i64 = std::str::from_utf8(&non_ignored)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);

    if count == 0 {
        return emit(
            b"false",
            &cat(&[
                b"every changed file matches '",
                &ignore_regex,
                b"' -> skip heavy work",
            ]),
        );
    }

    emit(
        b"true",
        &cat(&[
            &non_ignored,
            b" changed file(s) outside '",
            &ignore_regex,
            b"' -> run",
        ]),
    )
}
