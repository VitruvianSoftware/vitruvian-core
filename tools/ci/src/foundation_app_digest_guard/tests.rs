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

//! Black-box tests for //tools/ci:foundation_app_digest_guard, the deploy
//! guard foundation-app-deploy.yaml runs before `pulumi up`: it exports each
//! `<app>=<digest>` as `<APP>_IMAGE_DIGEST` to $GITHUB_ENV and FAILS CLOSED
//! when a workload enabled in Pulumi.production.yaml has no digest, because
//! that apply would strip the image off a live service. Runs the REAL binary
//! the way the workflow does (`guard "$APP_IMAGE_DIGESTS" Pulumi.production.yaml`
//! from the leaf directory). Ported case for case from the former
//! foundation-app-digest-guard_test.sh, plus the exports, the exact ::error::
//! line, and the inputs the script failed closed on.

use ci_testkit::{assert_has, bin, read, write, Output, Run, TempDir};

const THREE: &str = "config:
  gcp-app-infra:oauth-user-inspector_workload_enabled: \"true\"
  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"
  gcp-app-infra:mcp-slack_workload_enabled: \"true\"
";

struct Leaf {
    dir: TempDir,
}

impl Leaf {
    fn new(pulumi: &str) -> Leaf {
        let dir = TempDir::new();
        write(dir.join("Pulumi.production.yaml"), pulumi);
        write(dir.join("env"), "");
        Leaf { dir }
    }

    /// As the workflow step: cwd is the leaf, GITHUB_ENV is set.
    fn run(&self, digests: &str) -> Output {
        Run::new(&bin("BIN"))
            .cwd(self.dir.path())
            .env("GITHUB_ENV", self.dir.join("env"))
            .args([digests, "Pulumi.production.yaml"])
            .go()
    }

    fn env(&self) -> String {
        read(self.dir.join("env"))
    }
}

fn error_line(missing: &str) -> String {
    format!(
        "::error::workload enabled but no image digest supplied for:{missing} — deploying would render an EMPTY image and strip it off the live service. Pass app_image_digests as '<app>=<ref>'.\n"
    )
}

// --- the shell suite, case for case ------------------------------------------

#[test]
fn every_enabled_workload_has_a_digest_passes() {
    let l = Leaf::new(THREE);
    let o = l.run("oauth-user-inspector=sha256:aaa,mcp-slack=sha256:bbb");
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        o.stdout,
        "exporting OAUTH_USER_INSPECTOR_IMAGE_DIGEST\nexporting MCP_SLACK_IMAGE_DIGEST\ndigest guard: OK\n"
    );
    assert_eq!(
        l.env(),
        "OAUTH_USER_INSPECTOR_IMAGE_DIGEST=sha256:aaa\nMCP_SLACK_IMAGE_DIGEST=sha256:bbb\n"
    );
}

#[test]
fn an_empty_digest_is_refused_like_a_missing_one() {
    // `app=${{ needs.x.outputs.digest }}` with an empty output: the key is
    // there but there is no image. The script passed this; it must not.
    let l = Leaf::new(THREE);
    let o = l.run("oauth-user-inspector=,mcp-slack=sha256:bbb");
    assert_eq!(o.code, 1, "{o:?}");
    assert_eq!(
        o.stdout,
        format!(
            "exporting MCP_SLACK_IMAGE_DIGEST\n{}",
            error_line("oauth-user-inspector")
        )
    );
    assert_eq!(
        l.env(),
        "MCP_SLACK_IMAGE_DIGEST=sha256:bbb\n",
        "nothing exported for the empty one"
    );
}

#[test]
fn a_whitespace_only_digest_is_refused_and_not_exported() {
    // A YAML `|` block leaves `app=` followed by a newline; a stray space is
    // no image either. Both are refused, and neither is exported.
    for digests in [
        "oauth-user-inspector=\n,mcp-slack=sha256:bbb",
        "oauth-user-inspector= ,mcp-slack=sha256:bbb",
    ] {
        let l = Leaf::new(THREE);
        let o = l.run(digests);
        assert_eq!(o.code, 1, "{digests:?}: {o:?}");
        assert!(
            o.stdout.ends_with(&error_line("oauth-user-inspector")),
            "{digests:?}: {}",
            o.stdout
        );
        assert!(
            !l.env().contains("OAUTH_USER_INSPECTOR_IMAGE_DIGEST"),
            "{digests:?}: exported: {}",
            l.env()
        );
    }
}

#[test]
fn one_enabled_workload_missing_its_digest_is_refused() {
    let l = Leaf::new(THREE);
    let o = l.run("oauth-user-inspector=sha256:aaa");
    assert_eq!(o.code, 1, "{o:?}");
    // stdout, like the script's echo: the runner turns it into an annotation.
    assert_eq!(
        o.stdout,
        format!(
            "exporting OAUTH_USER_INSPECTOR_IMAGE_DIGEST\n{}",
            error_line("mcp-slack")
        )
    );
}

#[test]
fn no_digests_at_all_reports_every_enabled_workload() {
    let l = Leaf::new(THREE);
    let o = l.run("");
    assert_eq!(o.code, 1);
    assert_eq!(o.stdout, error_line("oauth-user-inspector mcp-slack"));
    assert_eq!(l.env(), "", "nothing to export");
}

#[test]
fn a_digest_for_a_disabled_workload_does_not_excuse_an_enabled_one() {
    let l = Leaf::new(THREE);
    let o = l.run("mcp-slack=sha256:bbb,zitadel-apps=sha256:ccc");
    assert_eq!(o.code, 1);
    assert_has(
        &o.stdout,
        &error_line("oauth-user-inspector"),
        "error names only the enabled one",
    );
}

#[test]
fn no_workloads_enabled_passes() {
    let l = Leaf::new("config:\n  gcp-app-infra:zitadel-apps_workload_enabled: \"false\"\n");
    let o = l.run("");
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(o.stdout, "digest guard: OK\n");
}

#[test]
fn an_extra_digest_for_an_app_not_in_the_file_is_harmless() {
    let l = Leaf::new(THREE);
    let o = l.run("oauth-user-inspector=sha256:aaa,mcp-slack=sha256:bbb,unrelated-app=sha256:zzz");
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &l.env(),
        "UNRELATED_APP_IMAGE_DIGEST=sha256:zzz\n",
        "still exported",
    );
}

// --- the export contract -----------------------------------------------------

#[test]
fn exports_are_appended_and_skip_empty_names_or_digests() {
    let l = Leaf::new(THREE);
    write(l.dir.join("env"), "EARLIER=1\n");
    let o = l.run(",oauth-user-inspector=sha256:a=b,,x=,=y,mcp-slack=sha256:c,");
    assert_eq!(o.code, 0, "{o:?}");
    // The digest is everything after the FIRST `=`.
    assert_eq!(
        l.env(),
        "EARLIER=1\nOAUTH_USER_INSPECTOR_IMAGE_DIGEST=sha256:a=b\nMCP_SLACK_IMAGE_DIGEST=sha256:c\n"
    );
}

#[test]
fn a_pair_without_equals_exports_itself_and_still_counts_as_missing() {
    // `${pair%%=*}` and `${pair#*=}` are both the pair when it has no `=`.
    let l = Leaf::new("config:\n  ns:ok-app_workload_enabled: \"true\"\n");
    let o = l.run("ok-app");
    assert_eq!(o.code, 1, "{o:?}");
    assert_eq!(l.env(), "OK_APP_IMAGE_DIGEST=ok-app\n");
    assert_has(&o.stdout, &error_line("ok-app"), "no `ok-app=`, so missing");
}

#[test]
fn only_the_first_line_of_the_digests_is_exported() {
    let l = Leaf::new("config:\n  ns:ok-app_workload_enabled: \"true\"\n");
    let o = l.run("ok-app=1\nz=2");
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(l.env(), "OK_APP_IMAGE_DIGEST=1\n");
}

// --- failing closed ------------------------------------------------------------

#[test]
fn a_name_the_guard_cannot_read_is_reported_missing_whole() {
    // No `ns:` prefix / a name outside [a-z0-9-]: the script's sed left the
    // line as it was, which no digest matches. The guard must refuse, not pass.
    for (file, digests) in [
        ("config:\n  b_workload_enabled: \"true\"\n", "b=1"),
        (
            "config:\n  ns:My_App_workload_enabled: \"true\"\n",
            "My_App=1",
        ),
    ] {
        let l = Leaf::new(file);
        let o = l.run(digests);
        assert_eq!(o.code, 1, "{file:?}: {o:?}");
        let line = file.lines().nth(1).unwrap();
        assert_has(&o.stdout, &error_line(line), "the whole line is the name");
    }
}

#[test]
fn true_must_follow_the_key_directly() {
    let l = Leaf::new(
        "config:\n  ns:x_workload_enabled: \"false\" # \"true\"\n  ns:y_workload_enabled:\"true\"\n  ns:z-1_workload_enabled:   \"true\"\r\n  a:b:c-d_workload_enabled: \"true\"\n",
    );
    let o = l.run("");
    assert_eq!(o.code, 1);
    assert_eq!(
        o.stdout,
        error_line("y z-1 c-d"),
        "x is disabled; c-d after the LAST colon"
    );
}

#[test]
fn an_unset_github_env_stops_the_guard() {
    let l = Leaf::new(THREE);
    let o = Run::new(&bin("BIN"))
        .cwd(l.dir.path())
        .args([
            "oauth-user-inspector=a,mcp-slack=b",
            "Pulumi.production.yaml",
        ])
        .go();
    assert_eq!(
        o.code, 1,
        "a digest that is never exported renders an empty image: {o:?}"
    );
    assert_has(&o.stderr, "GITHUB_ENV", "says why");
    assert!(!o.stdout.contains("digest guard: OK"), "{o:?}");
}

#[test]
fn an_unwritable_github_env_stops_the_guard() {
    let l = Leaf::new(THREE);
    let o = Run::new(&bin("BIN"))
        .cwd(l.dir.path())
        .env("GITHUB_ENV", l.dir.join("no/such/dir/env"))
        .args([
            "oauth-user-inspector=a,mcp-slack=b",
            "Pulumi.production.yaml",
        ])
        .go();
    assert_eq!(o.code, 1, "{o:?}");
    assert!(!o.stdout.contains("digest guard: OK"), "{o:?}");
}

#[test]
fn no_digests_needs_no_github_env() {
    let l = Leaf::new("config:\n  ns:x_workload_enabled: \"false\"\n");
    let o = Run::new(&bin("BIN"))
        .cwd(l.dir.path())
        .args(["", "Pulumi.production.yaml"])
        .go();
    assert_eq!(o.code, 0, "{o:?}");
}

#[test]
fn a_missing_or_empty_pulumi_file_argument_exports_nothing() {
    let l = Leaf::new(THREE);
    for args in [
        vec!["oauth-user-inspector=a"],
        vec!["oauth-user-inspector=a", ""],
    ] {
        let o = Run::new(&bin("BIN"))
            .cwd(l.dir.path())
            .env("GITHUB_ENV", l.dir.join("env"))
            .args(&args)
            .go();
        assert_eq!(o.code, 1, "{args:?}: {o:?}");
        assert_has(&o.stderr, "pulumi file required", "says why");
        assert_eq!(l.env(), "", "{args:?}: nothing exported");
    }
}

#[test]
fn an_unreadable_pulumi_file_is_refused() {
    // Deliberately stricter than the script, whose bare `$(cat ...)` read a
    // missing file as "nothing enabled" and printed OK.
    let l = Leaf::new(THREE);
    let o = Run::new(&bin("BIN"))
        .cwd(l.dir.path())
        .env("GITHUB_ENV", l.dir.join("env"))
        .args(["", "Pulumi.nope.yaml"])
        .go();
    assert_eq!(o.code, 1, "{o:?}");
    assert_has(
        &o.stdout,
        "::error::digest guard: cannot read Pulumi.nope.yaml",
        "annotated",
    );
    assert!(!o.stdout.contains("digest guard: OK"), "{o:?}");
}
