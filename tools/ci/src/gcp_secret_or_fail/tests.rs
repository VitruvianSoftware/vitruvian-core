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

//! Black-box tests for //tools/ci:gcp_secret_or_fail, which deploy workflows
//! call as `VALUE="$(gcp_secret_or_fail <secret-id> <project> [context])"`.
//! Runs the REAL binary with a fake `gcloud` first on PATH (hermetic: no
//! network, no credentials). Ported case for case from the former
//! gcp-secret-or-fail_test.sh: its six secret_or_fail() cases, which sourced
//! the script, are driven here through the binary by making the fake gcloud
//! exit and print what each case fed the function; its two main() cases are
//! unchanged in substance.

use ci_testkit::{assert_has, assert_lacks, bin, read, write_exe, Output, Run, TempDir};

/// Exits $FAKE_RC (default 0), printing $FAKE_STDOUT to stdout and
/// $FAKE_STDERR to stderr, and logs its argv to $FAKE_ARGV.
const FAKE_GCLOUD: &str = r#"#!/usr/bin/env bash
printf '%s\n' "$*" >"$FAKE_ARGV"
[ -n "${FAKE_STDERR:-}" ] && printf '%s\n' "$FAKE_STDERR" >&2
[ -n "${FAKE_STDOUT:-}" ] && printf '%s\n' "$FAKE_STDOUT"
exit "${FAKE_RC:-0}"
"#;

struct Case {
    out: Output,
    argv: String,
}

fn fetch(args: &[&str], rc: i32, stdout: &str, stderr: &str) -> Case {
    let t = TempDir::new();
    let fake = t.join("bin");
    write_exe(fake.join("gcloud"), FAKE_GCLOUD);
    let argv = t.join("argv");
    let out = Run::new(&bin("BIN"))
        .path_first(&fake)
        .env("FAKE_ARGV", &argv)
        .env("FAKE_RC", rc.to_string())
        .env("FAKE_STDOUT", stdout)
        .env("FAKE_STDERR", stderr)
        .args(args)
        .go();
    Case {
        out,
        argv: read(&argv),
    }
}

const PERM_DENIED: &str =
    "ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: caller lacks permission";

// Shell (pure) case 1: "rc=0 with a value returns it".
#[test]
fn rc0_with_value_returns_it() {
    let c = fetch(
        &["DATABASE_URL", "prj-x", "some context"],
        0,
        "sekrit-value",
        "",
    );
    assert_eq!(c.out.code, 0, "{}", c.out.all());
    // Exactly the value: no trailing newline, nothing else, so `$(...)` and
    // `::add-mask::` get the secret and only the secret.
    assert_eq!(c.out.stdout, "sekrit-value");
    assert_eq!(c.out.stderr, "");
}

// Shell (pure) case 2: "rc=0 with an empty value fails closed".
#[test]
fn rc0_with_empty_value_fails_closed() {
    let c = fetch(&["DATABASE_URL", "prj-x", ""], 0, "", "");
    assert_eq!(
        c.out.code,
        1,
        "an empty secret must never be handed back\n{}",
        c.out.all()
    );
    assert_eq!(c.out.stdout, "");
    assert_has(
        &c.out.stderr,
        "::error::secret DATABASE_URL could not be read from prj-x",
        "error",
    );
}

// Shell (pure) case 3: "nonzero rc fails closed" (regardless of stderr).
#[test]
fn nonzero_rc_fails_closed() {
    let c = fetch(
        &[
            "CLOUDFLARE_API_TOKEN",
            "prj-y",
            "deploy SA needs secretAccessor",
        ],
        1,
        "",
        PERM_DENIED,
    );
    assert_eq!(c.out.code, 1, "{}", c.out.all());
    assert_eq!(c.out.stdout, "");
    // A value on stdout must not be handed back when gcloud failed either.
    let c = fetch(&["X", "prj-x"], 1, "partial-value", "");
    assert_eq!(
        c.out.code,
        1,
        "nonzero rc with a value must still fail\n{}",
        c.out.all()
    );
    assert_eq!(c.out.stdout, "");
}

// Shell (pure) case 4: "error message names the secret id, project, AND the caller's context".
#[test]
fn error_names_secret_project_and_context() {
    let c = fetch(
        &[
            "CLOUDFLARE_API_TOKEN",
            "prj-y",
            "deploy SA needs secretAccessor",
        ],
        1,
        "",
        "ERROR: PERMISSION_DENIED",
    );
    assert_has(
        &c.out.stderr,
        "::error::secret CLOUDFLARE_API_TOKEN could not be read from prj-y \u{2014} deploy SA needs secretAccessor\n",
        "error line",
    );
    // Without a context, no dangling separator.
    let c = fetch(&["X", "prj-x"], 1, "", "");
    assert_eq!(
        c.out.stderr,
        "::error::secret X could not be read from prj-x\n"
    );
}

// Shell (pure) case 5: "raw gcloud stderr is surfaced so a wrong secret id isn't mistaken for an IAM gap".
#[test]
fn raw_gcloud_stderr_is_surfaced() {
    let c = fetch(
        &["X", "prj-x", ""],
        1,
        "",
        "ERROR: PERMISSION_DENIED: caller lacks permission",
    );
    assert_has(
        &c.out.stderr,
        "gcloud stderr: ERROR: PERMISSION_DENIED: caller lacks permission\n",
        "raw stderr",
    );
}

// Shell (pure) case 6: "rc=0 always wins regardless of stderr content".
#[test]
fn rc0_wins_regardless_of_stderr() {
    let c = fetch(
        &["X", "prj-x", ""],
        0,
        "value-with-trailing-noise",
        "some warning printed to stderr despite rc=0",
    );
    assert_eq!(c.out.code, 0, "{}", c.out.all());
    assert_eq!(
        c.out.stdout, "value-with-trailing-noise",
        "stdout must stay clean for $(...)"
    );
}

// Shell (main) case 7: "success path returns the value with rc=0, no trap crash".
#[test]
fn main_success_path_returns_value() {
    let c = fetch(
        &["DATABASE_URL", "some-project", "test context"],
        0,
        "the-actual-secret-value",
        "",
    );
    assert_eq!(c.out.code, 0);
    assert_eq!(
        c.out.all(),
        "the-actual-secret-value",
        "2>&1 output must be the value alone"
    );
}

// Shell (main) case 8: "failure path prints the real ::error:: with rc=1, no trap crash".
#[test]
fn main_failure_path_prints_real_error() {
    let c = fetch(
        &["DATABASE_URL", "some-project", "test context"],
        1,
        "",
        PERM_DENIED,
    );
    assert_eq!(c.out.code, 1, "{}", c.out.all());
    assert_has(&c.out.all(), "::error::secret DATABASE_URL", "error");
    assert_lacks(
        &c.out.all().to_lowercase(),
        "unbound variable",
        "trap crash",
    );
}

// The workflows' call shape: exactly the gcloud invocation the script made.
#[test]
fn calls_gcloud_for_the_latest_version_of_that_secret_in_that_project() {
    let c = fetch(
        &["NEON_API_KEY", "prj-c-bu2-infra-pipeline-3d09", "seed it"],
        0,
        "v",
        "",
    );
    assert_eq!(
        c.argv,
        "secrets versions access latest --secret=NEON_API_KEY --project=prj-c-bu2-infra-pipeline-3d09\n"
    );
}

// The script died on `${2:?project required}` (exit 1); the binary prints its
// usage (exit 2). Either way: nonzero, nothing on stdout, gcloud never called.
#[test]
fn missing_project_is_a_usage_error_without_calling_gcloud() {
    for args in [&["ONLY_SECRET"][..], &[][..]] {
        let c = fetch(args, 0, "should-not-be-read", "");
        assert_ne!(c.out.code, 0, "{args:?}");
        assert_eq!(c.out.stdout, "", "{args:?}");
        assert_eq!(c.argv, "", "{args:?}: gcloud was called");
    }
}
