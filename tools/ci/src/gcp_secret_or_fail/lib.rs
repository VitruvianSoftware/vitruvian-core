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

//! //tools/ci:gcp_secret_or_fail — fetch a GCP Secret Manager secret's latest
//! version, or fail loudly with actionable context. Prints only the value on
//! stdout, so workflows capture it with `VALUE="$(bazel-bin/.../gcp_secret_or_fail
//! <secret-id> <project> [context])"` (_deploy-cloud-run.yaml,
//! tabula-data-stack.yaml). Replaces gcp-secret-or-fail.sh.
//!
//! WHY an explicit exit-code check, not just an empty-string check: gcloud can
//! exit 0 while still printing ERROR to stderr, and a genuinely missing secret
//! returns PERMISSION_DENIED, not NOT_FOUND, so reading the WRONG secret id is
//! indistinguishable from an IAM gap unless the raw gcloud stderr is surfaced.

use shell_compat::{capture, cat, err, out, subst};
use std::process::Command;

/// Pure decision function: returns `(value, 0)` on success, or `(empty, 1)`
/// on failure (printing the error to stderr).
pub fn secret_or_fail(
    rc: i32,
    value: &[u8],
    stderr_content: &[u8],
    secret_id: &[u8],
    project: &[u8],
    context: &[u8],
) -> (Vec<u8>, i32) {
    if rc != 0 || value.is_empty() {
        let ctx_part = if !context.is_empty() {
            cat(&[b" \xe2\x80\x94 ", context])
        } else {
            Vec::new()
        };
        err(&cat(&[
            b"::error::secret ",
            secret_id,
            b" could not be read from ",
            project,
            &ctx_part,
            b"\n",
        ]));
        if !stderr_content.is_empty() {
            err(&cat(&[b"gcloud stderr: ", stderr_content, b"\n"]));
        }
        return (Vec::new(), 1);
    }
    (value.to_vec(), 0)
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.is_empty() || (args.len() < 2) {
        err(b"usage: gcp-secret-or-fail <secret-id> <project> [context-message]\n");
        return 2;
    }
    let secret_id = &args[0];
    let project = &args[1];
    let context = if args.len() >= 3 { &args[2] } else { &b""[..] };

    let r = capture(
        72,
        Command::new("gcloud")
            .arg("secrets")
            .arg("versions")
            .arg("access")
            .arg("latest")
            .arg(shell_compat::os(&cat(&[b"--secret=", secret_id])))
            .arg(shell_compat::os(&cat(&[b"--project=", project]))),
    );
    let value = subst(r.stdout);
    let stderr_content = subst(r.stderr);

    let (val, rc) = secret_or_fail(
        r.status,
        &value,
        &stderr_content,
        secret_id,
        project,
        context,
    );
    if rc == 0 {
        out(&val);
    }
    rc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn success_returns_value() {
        let (val, rc) = secret_or_fail(0, b"sekrit-value", b"", b"DB_URL", b"prj-x", b"");
        assert_eq!(rc, 0);
        assert_eq!(val, b"sekrit-value");
    }

    #[test]
    fn empty_value_fails_closed() {
        let (_, rc) = secret_or_fail(0, b"", b"", b"DB_URL", b"prj-x", b"");
        assert_eq!(rc, 1);
    }

    #[test]
    fn nonzero_rc_fails_closed() {
        let (_, rc) = secret_or_fail(
            1,
            b"",
            b"ERROR: PERMISSION_DENIED",
            b"CF_TOKEN",
            b"prj-y",
            b"deploy SA needs secretAccessor",
        );
        assert_eq!(rc, 1);
    }

    #[test]
    fn rc_zero_with_stderr_still_succeeds() {
        let (val, rc) = secret_or_fail(
            0,
            b"value-with-trailing-noise",
            b"some warning",
            b"X",
            b"prj-x",
            b"",
        );
        assert_eq!(rc, 0);
        assert_eq!(val, b"value-with-trailing-noise");
    }
}
