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

//! Black-box guard for //tools/ci:tabula_deploy_preflight. The property that
//! matters is the fail-open invariant: `unchanged=true` ONLY on a confident
//! match; every error path deploys. A regression that failed CLOSED would skip
//! a real deploy, an outage-class bug, so each error path is pinned.

use ci_testkit::{assert_has, bin, read, write, write_exe, Output, Run, TempDir};
use std::path::PathBuf;

// Serves `gcloud run services describe --format=json` from FAKE_JSON (a file),
// logs its argv, and simulates the exit-0 reauth error and a non-zero exit.
const FAKE_GCLOUD: &str = r#"#!/usr/bin/env bash
echo "$*" >> "${FAKE_ARGV:-/dev/null}"
if [ "${FAKE_GCLOUD_AUTHFAIL:-0}" = "1" ]; then
  echo "ERROR: (gcloud.run.services.describe) Reauthentication failed." >&2
  exit 0
fi
if [ "${FAKE_GCLOUD_RC:-0}" != "0" ]; then
  echo "ERROR: boom" >&2; exit "${FAKE_GCLOUD_RC}"
fi
cat "$FAKE_JSON"
"#;

// Prints FAKE_DESIRED, or fails when FAKE_REVNAME_RC is set. Logs its argv,
// cwd and GOWORK.
const FAKE_REVNAME: &str = r#"#!/usr/bin/env bash
echo "$* | cwd=$(pwd -P) | GOWORK=${GOWORK:-}" >> "${FAKE_ARGV:-/dev/null}"
if [ "${FAKE_REVNAME_RC:-0}" != "0" ]; then echo "revname: boom" >&2; exit "${FAKE_REVNAME_RC}"; fi
printf '%s\n' "${FAKE_DESIRED:-}"
"#;

const DESIRED: &str = "tabula-api-development-de662165-1b062f";
const OTHER: &str = "tabula-api-development-aaaa1111-bbbbbb";

struct Fx {
    work: TempDir,
    app: PathBuf,
    gcloud: PathBuf,
    revname: PathBuf,
    json: PathBuf,
}

/// A describe document whose status.traffic is `traffic` (raw JSON array).
fn describe(traffic: &str) -> String {
    format!(r#"{{"metadata": {{"name": "svc"}}, "status": {{"traffic": {traffic}}}}}"#)
}

/// One revision at 100%, or no traffic at all for "".
fn live(name: &str) -> String {
    if name.is_empty() {
        describe("[]")
    } else {
        describe(&format!(
            r#"[{{"revisionName": "{name}", "percent": 100}}]"#
        ))
    }
}

impl Fx {
    fn new() -> Fx {
        let work = TempDir::new();
        let app = work.join("app");
        write(app.join("Pulumi.development.yaml"), "");
        // A space in the path: GCLOUD_BIN is one quoted program, never split.
        let gcloud = work.join("bin dir/fake-gcloud");
        write_exe(&gcloud, FAKE_GCLOUD);
        let revname = work.join("fake-revname");
        write_exe(&revname, FAKE_REVNAME);
        let json = work.join("describe.json");
        Fx {
            work,
            app,
            gcloud,
            revname,
            json,
        }
    }

    fn out(&self) -> PathBuf {
        self.work.join("out")
    }

    fn base(&self) -> Run {
        let _ = std::fs::remove_file(self.out());
        Run::new(&bin("BIN"))
            .env("GITHUB_OUTPUT", self.out())
            .env("DEPLOY_ENV", "development")
            .env("GCP_PROJECT_ID", "prj-d")
            .env("GCP_REGION", "us-central1")
            .env("SERVICE_NAME", "tabula-api")
            .env("IMAGE_DIGEST", "img@sha256:deadbeef12")
            .env("PULUMI_DIR", &self.app)
            .env("CONFIG_FILE", "Pulumi.development.yaml")
            .env("GCLOUD_BIN", &self.gcloud)
            .env("REVNAME", &self.revname)
            .env("FAKE_JSON", &self.json)
    }

    /// Runs with `describe_json` served and `envs` set; returns (output,
    /// the unchanged= value written to GITHUB_OUTPUT).
    fn run(&self, describe_json: &str, envs: &[(&str, &str)]) -> (Output, String) {
        write(&self.json, describe_json);
        let mut r = self.base();
        for (k, v) in envs {
            r = r.env(k, v);
        }
        let o = r.go();
        (o, unchanged(&read(self.out())))
    }
}

fn unchanged(gh_output: &str) -> String {
    gh_output
        .lines()
        .filter_map(|l| l.strip_prefix("unchanged="))
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn matching_names_skip() {
    let fx = Fx::new();
    let (o, got) = fx.run(&live(DESIRED), &[("FAKE_DESIRED", DESIRED)]);
    assert_eq!(got, "true", "{o:?}");
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        &format!("preflight[development]: unchanged=true \u{2014} live already serves the desired revision ({DESIRED})"),
        "skip line",
    );
}

#[test]
fn different_names_deploy() {
    let fx = Fx::new();
    let (o, got) = fx.run(&live(DESIRED), &[("FAKE_DESIRED", OTHER)]);
    assert_eq!(got, "false");
    assert_has(
        &o.stdout,
        &format!("desired ({OTHER}) != live ({DESIRED})"),
        "reason",
    );
    assert_has(
        &o.stdout,
        &format!("desired={OTHER} live={DESIRED}"),
        "comparison line",
    );
}

#[test]
fn empty_live_first_deploy_deploys() {
    let fx = Fx::new();
    let (o, got) = fx.run(&live(""), &[("FAKE_DESIRED", DESIRED)]);
    assert_eq!(got, "false");
    assert_has(
        &o.stdout,
        "no revision carries traffic (first-ever deploy for tabula-api-development",
        "reason",
    );
}

#[test]
fn revname_failure_deploys() {
    let fx = Fx::new();
    let (o, got) = fx.run(
        &live("x"),
        &[("FAKE_DESIRED", ""), ("FAKE_REVNAME_RC", "1")],
    );
    assert_eq!(got, "false");
    assert_eq!(o.code, 0);
    assert_has(
        &o.stderr,
        "preflight[development]: could not compute the desired revision name:\n  revname: boom",
        "diagnostic",
    );
    assert_has(
        &o.stdout,
        "desired-name computation failed (rc=1)",
        "reason",
    );
}

#[test]
fn an_empty_desired_name_deploys() {
    let fx = Fx::new();
    let (o, got) = fx.run(&live(""), &[("FAKE_DESIRED", "")]);
    assert_eq!(got, "false");
    assert_has(
        &o.stderr,
        "could not compute the desired revision name:",
        "header even with no tool stderr",
    );
    assert_has(
        &o.stdout,
        "desired-name computation failed (rc=0)",
        "reason",
    );
}

#[test]
fn gcloud_non_zero_deploys() {
    let fx = Fx::new();
    let (o, got) = fx.run(
        &live("x"),
        &[("FAKE_DESIRED", "x"), ("FAKE_GCLOUD_RC", "1")],
    );
    assert_eq!(got, "false");
    assert_has(
        &o.stderr,
        "could not read the live revision:\n  ERROR: boom",
        "diagnostic",
    );
    assert_has(&o.stdout, "live-revision read failed (rc=1)", "reason");
}

#[test]
fn gcloud_exit_zero_reauth_error_deploys() {
    let fx = Fx::new();
    let (o, got) = fx.run(
        &live("x"),
        &[("FAKE_DESIRED", "x"), ("FAKE_GCLOUD_AUTHFAIL", "1")],
    );
    assert_eq!(got, "false");
    assert_has(&o.stdout, "live-revision read failed (rc=0)", "reason");
}

#[test]
fn different_config_hash_deploys() {
    let fx = Fx::new();
    let (_, got) = fx.run(
        &live("tabula-api-development-de662165-999999"),
        &[("FAKE_DESIRED", DESIRED)],
    );
    assert_eq!(got, "false");
}

#[test]
fn failed_zero_percent_candidate_listed_first_deploys() {
    // A failed candidate at 0% behind the candidate tag, listed first, has the
    // desired name. It is not live: skipping would leave the old revision
    // serving and report the deploy green.
    let fx = Fx::new();
    let traffic = format!(
        r#"[{{"tag":"candidate","revisionName":"{DESIRED}","url":"https://c"}},{{"revisionName":"{OTHER}","percent":100}}]"#
    );
    let (_, got) = fx.run(&describe(&traffic), &[("FAKE_DESIRED", DESIRED)]);
    assert_eq!(got, "false");
}

#[test]
fn desired_serving_100_behind_a_zero_percent_entry_skips() {
    let fx = Fx::new();
    let traffic = format!(
        r#"[{{"tag":"candidate","revisionName":"{OTHER}","percent":0}},{{"revisionName":"{DESIRED}","percent":100}}]"#
    );
    let (_, got) = fx.run(&describe(&traffic), &[("FAKE_DESIRED", DESIRED)]);
    assert_eq!(got, "true");
}

#[test]
fn nothing_carrying_traffic_deploys() {
    let fx = Fx::new();
    let (_, got) = fx.run(
        &describe(r#"[{"tag":"candidate","revisionName":"x","percent":0}]"#),
        &[("FAKE_DESIRED", "x")],
    );
    assert_eq!(got, "false");
}

#[test]
fn split_traffic_sums_per_revision_and_ties_go_to_the_first_listed() {
    let fx = Fx::new();
    // DESIRED 30+30 beats OTHER 40.
    let traffic = format!(
        r#"[{{"revisionName":"{OTHER}","percent":40}},{{"revisionName":"{DESIRED}","percent":30}},{{"revisionName":"{DESIRED}","percent":30}}]"#
    );
    assert_eq!(
        fx.run(&describe(&traffic), &[("FAKE_DESIRED", DESIRED)]).1,
        "true"
    );
    // 50/50: the first listed (OTHER) is live, so DESIRED deploys.
    let tie = format!(
        r#"[{{"revisionName":"{OTHER}","percent":50}},{{"revisionName":"{DESIRED}","percent":50}}]"#
    );
    assert_eq!(
        fx.run(&describe(&tie), &[("FAKE_DESIRED", DESIRED)]).1,
        "false"
    );
}

#[test]
fn unparseable_describe_json_deploys() {
    let fx = Fx::new();
    let (_, got) = fx.run("not json", &[("FAKE_DESIRED", "x")]);
    assert_eq!(got, "false");
}

#[test]
fn calls_revname_and_gcloud_with_the_scripts_arguments() {
    let fx = Fx::new();
    let argv = fx.work.join("argv");
    fx.run(
        &live(DESIRED),
        &[
            ("FAKE_DESIRED", DESIRED),
            ("FAKE_ARGV", &argv.to_string_lossy()),
            ("GCP_REGION", ""),
        ],
    );
    let log = read(&argv);
    assert_has(
        &log,
        &format!(
            "--config Pulumi.development.yaml --digest img@sha256:deadbeef12 | cwd={} | GOWORK=off\n",
            fx.app.display()
        ),
        "revname runs in PULUMI_DIR with GOWORK=off",
    );
    assert_has(
        &log,
        "run services describe tabula-api-development --project prj-d --region us-central1 --format=json\n",
        "gcloud describe (GCP_REGION defaults to us-central1)",
    );
}

#[test]
fn revname_is_word_split_like_the_scripts_unquoted_expansion() {
    let fx = Fx::new();
    let argv = fx.work.join("argv");
    let (_, got) = fx.run(
        &live(DESIRED),
        &[
            ("FAKE_DESIRED", DESIRED),
            ("FAKE_ARGV", &argv.to_string_lossy()),
            ("REVNAME", &format!("{} extra-arg", fx.revname.display())),
        ],
    );
    assert_eq!(got, "true");
    assert_has(
        &read(&argv),
        "extra-arg --config Pulumi.development.yaml",
        "split REVNAME",
    );
}

#[test]
fn a_missing_pulumi_dir_deploys() {
    let fx = Fx::new();
    let (o, got) = fx.run(
        &live(DESIRED),
        &[
            ("FAKE_DESIRED", DESIRED),
            ("PULUMI_DIR", "/nonexistent/app"),
        ],
    );
    assert_eq!(got, "false");
    assert_has(&o.stdout, "PULUMI_DIR /nonexistent/app not found", "reason");
}

#[test]
fn every_required_variable_is_required() {
    let fx = Fx::new();
    write(&fx.json, live(DESIRED));
    for v in [
        "DEPLOY_ENV",
        "GCP_PROJECT_ID",
        "SERVICE_NAME",
        "IMAGE_DIGEST",
        "PULUMI_DIR",
        "CONFIG_FILE",
    ] {
        let o = fx.base().env("FAKE_DESIRED", DESIRED).env(v, "").go();
        assert_eq!(o.code, 1, "{v} empty: {o:?}");
        assert_eq!(read(fx.out()), "", "{v} empty: nothing may be emitted");
    }
}

#[test]
fn bazel_run_acts_from_the_callers_directory() {
    // A relative PULUMI_DIR resolves against BUILD_WORKING_DIRECTORY, as the
    // script's `cd` did from the caller's cwd.
    let fx = Fx::new();
    write(&fx.json, live(DESIRED));
    let elsewhere = TempDir::new();
    let o = fx
        .base()
        .cwd(elsewhere.path())
        .env("BUILD_WORKING_DIRECTORY", fx.work.path())
        .env("PULUMI_DIR", "app")
        .env("FAKE_DESIRED", DESIRED)
        .go();
    assert_eq!(unchanged(&read(fx.out())), "true", "{o:?}");
}
