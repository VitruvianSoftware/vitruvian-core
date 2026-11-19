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

//! Integration tests for //tools/pulumi:refuse-destructive-plan.

mod common;
use common::*;
use std::path::PathBuf;

fn run_guard(args: &[&str], json_body: Option<&str>) -> std::process::Output {
    let d = tempdir("plan-guard");
    let mut c = cmd(&bin("REFUSE_DESTRUCTIVE_PLAN_BIN"), "/usr/bin:/bin");
    if let Some(body) = json_body {
        let plan_path: PathBuf = d.join("plan.json");
        std::fs::write(&plan_path, body).unwrap();
        c.args(args).arg(plan_path);
    } else {
        c.args(args);
    }
    run(c)
}

#[test]
fn safe_plan_exits_0() {
    let body = r#"{
  "steps": [
    {"op": "same", "urn": "urn:pulumi:production::sentry::pulumi:pulumi:Stack::sentry-production"},
    {"op": "create", "urn": "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-new"},
    {"op": "update", "urn": "urn:pulumi:production::sentry::sentry:index/sentryTeam:SentryTeam::team-vitruvian"}
  ],
  "changeSummary": {"create": 1, "update": 1, "same": 1}
}"#;
    let o = run_guard(&["sentry production"], Some(body));
    assert_eq!(code(&o), 0, "stderr: {}", stderr(&o));
    assert!(
        stdout(&o).contains("non-destructive (3 step(s) checked; 0 delete/replace)"),
        "stdout: {}",
        stdout(&o)
    );
}

#[test]
fn delete_step_exits_1_and_lists_resource() {
    let body = r#"{
  "steps": [
    {"op": "same", "urn": "urn:pulumi:production::sentry::pulumi:pulumi:Stack::sentry-production"},
    {"op": "delete", "urn": "urn:pulumi:production::sentry::sentry:index/sentryProject:SentryProject::project-backstage", "oldState": {"type": "sentry:index/sentryProject:SentryProject"}}
  ],
  "changeSummary": {"delete": 1, "same": 1}
}"#;
    let o = run_guard(&["sentry production"], Some(body));
    let err = stderr(&o);
    assert_eq!(code(&o), 1);
    assert!(
        err.contains("::error::Refusing to apply sentry production"),
        "err: {err}"
    );
    assert!(
        err.contains("error: Refusing to apply sentry production"),
        "err: {err}"
    );
    assert!(
        err.contains("- delete: sentry:index/sentryProject:SentryProject project-backstage"),
        "err: {err}"
    );
}

#[test]
fn replace_steps_exit_1_and_list_resources() {
    let body = r#"{
  "steps": [
    {"op": "create-replacement", "urn": "urn:pulumi:production::vitruvian-sentry-pagerduty::sentry:index/alert:Alert::alert-backstage", "newState": {"type": "sentry:index/alert:Alert"}},
    {"op": "replace", "urn": "urn:pulumi:production::vitruvian-sentry-pagerduty::sentry:index/alert:Alert::alert-backstage"},
    {"op": "delete-replaced", "urn": "urn:pulumi:production::vitruvian-sentry-pagerduty::sentry:index/alert:Alert::alert-backstage", "oldState": {"type": "sentry:index/alert:Alert"}}
  ]
}"#;
    let o = run_guard(&["sentry-pagerduty production"], Some(body));
    let err = stderr(&o);
    assert_eq!(code(&o), 1);
    assert!(
        err.contains("- create-replacement: sentry:index/alert:Alert alert-backstage"),
        "err: {err}"
    );
    assert!(
        err.contains("- replace: sentry:index/alert:Alert alert-backstage"),
        "err: {err}"
    );
    assert!(
        err.contains("- delete-replaced: sentry:index/alert:Alert alert-backstage"),
        "err: {err}"
    );
}

#[test]
fn fails_closed_on_missing_or_malformed_plan() {
    let o = run_guard(&["sentry production", "/nonexistent/plan.json"], None);
    assert_eq!(code(&o), 1);

    for bad in [
        "",
        "{}",
        r#"{"steps": null}"#,
        "not-json",
        r#"{"steps":[{"op":"\u+073ame","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[{"op":"\u-073ame","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[{"op":"\u07","urn":"urn:pulumi:p::s::t::n"}]}"#,
    ] {
        let o = run_guard(&["sentry production"], Some(bad));
        assert_eq!(code(&o), 1, "expected fail-closed for {bad:?}");
        assert!(stderr(&o).contains("Refusing to apply sentry production"));
    }
}

#[test]
fn rejects_duplicate_json_keys_even_when_winning_duplicate_looks_safe() {
    for dup in [
        // Safe key first (would pass a first-key-wins parser if duplicate check is disabled).
        r#"{"steps":[{"op":"same","op":"delete","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[{"op":"same","\u006fp":"delete","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[],"steps":[{"op":"delete","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[{"op":"same","urn":"urn:pulumi:p::s::t::n"}],"changeSummary":{"same":1},"changeSummary":{"delete":1}}"#,
        // Destructive key first / safe key last (would pass a last-key-wins parser if disabled).
        r#"{"steps":[{"op":"delete","op":"same","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[{"op":"delete","\u006fp":"same","urn":"urn:pulumi:p::s::t::n"}]}"#,
        r#"{"steps":[{"op":"delete","urn":"urn:pulumi:p::s::t::n"}],"steps":[]}"#,
        r#"{"steps":[{"op":"same","urn":"urn:pulumi:p::s::t::n"}],"changeSummary":{"delete":1,"delete":0}}"#,
    ] {
        let o = run_guard(&["sentry production"], Some(dup));
        let err = stderr(&o);
        assert_eq!(code(&o), 1, "expected duplicate-key refusal for {dup:?}");
        assert!(
            err.contains("duplicate JSON object key"),
            "expected duplicate-key error message for {dup:?}, got: {err}"
        );
    }
}

#[test]
fn does_not_print_secret_inputs_or_config_on_failure() {
    let body = r#"{
  "config": {"sentry:token": "CANARY_SECRET_TOKEN_DO_NOT_PRINT"},
  "steps": [
    {
      "op": "delete",
      "urn": "urn:pulumi:production::sentry::sentry:index/sentryKey:SentryKey::key-backstage",
      "oldState": {
        "type": "sentry:index/sentryKey:SentryKey",
        "inputs": {"secret": "CANARY_SECRET_INPUT_DO_NOT_PRINT"},
        "outputs": {"dsnSecret": "CANARY_SECRET_OUTPUT_DO_NOT_PRINT"}
      }
    }
  ]
}"#;
    let o = run_guard(&["sentry production"], Some(body));
    assert_eq!(code(&o), 1);
    let combined = format!("{}{}", stdout(&o), stderr(&o));
    for canary in [
        "CANARY_SECRET_TOKEN_DO_NOT_PRINT",
        "CANARY_SECRET_INPUT_DO_NOT_PRINT",
        "CANARY_SECRET_OUTPUT_DO_NOT_PRINT",
    ] {
        assert!(!combined.contains(canary), "secret leaked: {combined}");
    }
}

#[test]
fn bad_cli_usage_exits_2() {
    for args in [&[][..], &["only-one"][..], &["", "/tmp/p.json"][..]] {
        let o = run_guard(args, None);
        assert_eq!(code(&o), 2, "args: {args:?}");
        assert!(stderr(&o).contains("usage: refuse-destructive-plan"));
    }
}
