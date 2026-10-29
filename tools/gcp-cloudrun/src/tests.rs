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

use super::*;
use std::path::{Path, PathBuf};

/// A throwaway workspace: the identity map above and one app with two stacks.
fn workspace(tag: &str) -> PathBuf {
    let root = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let ws = root.join(format!("ws-{}-{}", tag, std::process::id()));
    let infra = ws.join("apps/web/oauth-user-inspector/infra/app");
    std::fs::create_dir_all(&infra).unwrap();
    std::fs::create_dir_all(ws.join("infrastructure")).unwrap();
    std::fs::write(ws.join(IDENTITY_MAP), MAP).unwrap();
    std::fs::write(
        infra.join("Pulumi.development.yaml"),
        "config:\n  gcp:project: prj-d-bu1-oss-floating-648a\n",
    )
    .unwrap();
    std::fs::write(
        infra.join("Pulumi.production.yaml"),
        "config:\n  gcp:project: prj-p-bu1-oss-floating-16e0\n",
    )
    .unwrap();
    ws
}

const MAP: &str = "\
# comment line
# infra_dir   account   gcp_project   purpose
infrastructure/pulumi/accounts/personal   james.nguyen@gmail.com   personal-llc   Personal stuff here

apps/web/oauth-user-inspector/infra/app   sa-oauth-deploy-dev@prj-d-bu1-oss-floating-648a.iam.gserviceaccount.com   prj-d-bu1-oss-floating-648a   WIF: x
-   james@nocentre.net   -   reference only
infrastructure/pulumi/foundation/gcp-org   sa-terraform-org@prj-c-cicd-1.iam.gserviceaccount.com   -   WIF: y
";

fn v(xs: &[&str]) -> Vec<String> {
    xs.iter().map(|s| s.to_string()).collect()
}

fn args(xs: &[&str]) -> Args {
    parse_args(&v(xs)).expect("args parse")
}

// --- identity map -------------------------------------------------------------

#[test]
fn parses_rows_and_skips_comments_blanks_and_reference_rows() {
    let rows = parse_identity_map(MAP);
    let dirs: Vec<&str> = rows.iter().map(|r| r.infra_dir.as_str()).collect();
    assert_eq!(
        dirs,
        [
            "infrastructure/pulumi/accounts/personal",
            "apps/web/oauth-user-inspector/infra/app",
            "infrastructure/pulumi/foundation/gcp-org"
        ]
    );
}

#[test]
fn looks_up_project_by_infra_dir() {
    let rows = parse_identity_map(MAP);
    let r = lookup(&rows, "apps/web/oauth-user-inspector/infra/app/").unwrap();
    assert_eq!(r.project, "prj-d-bu1-oss-floating-648a");
    assert!(lookup(&rows, "apps/web/nope/infra/app").is_none());
}

#[test]
fn resolve_by_app_uses_the_identity_map_project() {
    let ws = workspace("map");
    let a = args(&["--app", "oauth-user-inspector", "--service", "s"]);
    let r = resolve(&ws, &a).expect("resolve");
    assert_eq!(r.project, "prj-d-bu1-oss-floating-648a");
    assert_eq!(
        r.account, DEFAULT_OPERATOR_ACCOUNT,
        "SA row mints as the operator"
    );
    let a = args(&[
        "--infra",
        "infrastructure/pulumi/foundation/gcp-org",
        "--service",
        "s",
    ]);
    assert!(resolve(&ws, &a).is_err(), "a '-' project is refused");
    let a = args(&["--app", "nope", "--service", "s"]);
    assert!(resolve(&ws, &a).is_err());
}

#[test]
fn service_account_rows_mint_as_the_operator() {
    let sa = "sa-x@p.iam.gserviceaccount.com";
    assert_eq!(operator_account(Some(sa), None), DEFAULT_OPERATOR_ACCOUNT);
    assert_eq!(operator_account(None, None), DEFAULT_OPERATOR_ACCOUNT);
}

#[test]
fn user_account_rows_mint_as_that_user() {
    assert_eq!(
        operator_account(Some("james@nocentre.net"), None),
        "james@nocentre.net"
    );
}

#[test]
fn account_override_wins() {
    let sa = "sa-x@p.iam.gserviceaccount.com";
    assert_eq!(
        operator_account(Some(sa), Some("me@example.com")),
        "me@example.com"
    );
    assert_eq!(
        operator_account(Some("a@b.c"), Some("me@example.com")),
        "me@example.com"
    );
}

#[test]
fn reads_gcp_project_from_a_pulumi_stack() {
    let yaml =
        "config:\n  gcp:region: us-central1\n  gcp:project: prj-d-bu1-oss-floating-648a  # dev\n";
    assert_eq!(
        pulumi_stack_project(yaml).as_deref(),
        Some("prj-d-bu1-oss-floating-648a")
    );
    assert_eq!(pulumi_stack_project("config:\n  gcp:region: x\n"), None);
    assert_eq!(normalize_env("dev"), "development");
    assert_eq!(normalize_env("prod"), "production");
    assert_eq!(normalize_env("nonproduction"), "nonproduction");
}

#[test]
fn resolve_with_env_reads_the_stack_and_defaults_the_account() {
    let a = args(&[
        "--app",
        "oauth-user-inspector",
        "--env",
        "prod",
        "--service",
        "s",
    ]);
    let r = resolve(&workspace("env"), &a).expect("resolve");
    assert_eq!(r.project, "prj-p-bu1-oss-floating-16e0");
    assert_eq!(r.account, DEFAULT_OPERATOR_ACCOUNT);
}

// --- argument checks ------------------------------------------------------------

#[test]
fn rejects_bad_arguments() {
    for bad in [
        vec!["--service", "s"],                                 // no location
        vec!["--app", "a"],                                     // no target
        vec!["--app", "a", "--project", "p", "--service", "s"], // two locations
        vec!["--project", "p", "--env", "dev", "--service", "s"],
        vec!["--project", "p", "--service", "s\" OR true"], // filter injection
        vec!["--project", "p", "--service", "s", "--since", "3 hours"],
        vec!["--project", "p", "--service", "s", "--limit", "all"],
        vec!["--project", "p", "--service", "s", "--bogus"],
        vec!["--project", "p", "--revision", "--log-http"], // a name that is a flag
        vec!["--project", "p", "--service", "-s"],
        vec!["--project", "1p", "--service", "s"],
        vec!["--project", "p", "--service", "s", "--since", "3\u{e9}"], // used to panic
        vec!["--project", "p", "--service", "s", "--since", ""],
    ] {
        assert!(parse_args(&v(&bad)).is_err(), "should reject {:?}", bad);
    }
}

// --- argv construction ----------------------------------------------------------

#[test]
fn service_mode_describes_lists_revisions_and_reads_logs() {
    let a = args(&["--project", "prj-1", "--service", "svc", "--since", "6h"]);
    let cmds = plan(&a, "prj-1").unwrap();
    let got: Vec<Vec<String>> = cmds.iter().map(|c| c.argv().to_vec()).collect();
    assert_eq!(
        got[0],
        v(&[
            "run",
            "services",
            "describe",
            "svc",
            "--project=prj-1",
            "--region=us-central1"
        ])
    );
    assert_eq!(
        got[1],
        v(&[
            "run",
            "revisions",
            "list",
            "--service=svc",
            "--project=prj-1",
            "--region=us-central1"
        ])
    );
    assert_eq!(
        &got[2][..3],
        &v(&[
            "logging",
            "read",
            "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"svc\""
        ])[..]
    );
    assert!(got[2].contains(&"--freshness=6h".to_string()));
    assert!(got[2].contains(&"--project=prj-1".to_string()));
    assert_eq!(got.len(), 3);
}

#[test]
fn revision_mode_describes_the_revision_and_reads_its_logs() {
    let a = args(&[
        "--project",
        "prj-1",
        "--revision",
        "svc-00007-abc",
        "--region",
        "europe-west1",
    ]);
    let got: Vec<Vec<String>> = plan(&a, "prj-1")
        .unwrap()
        .iter()
        .map(|c| c.argv().to_vec())
        .collect();
    assert_eq!(got.len(), 2);
    assert_eq!(
        got[0],
        v(&[
            "run",
            "revisions",
            "describe",
            "svc-00007-abc",
            "--project=prj-1",
            "--region=europe-west1"
        ])
    );
    assert_eq!(
        got[1][2],
        "resource.type=\"cloud_run_revision\" AND resource.labels.revision_name=\"svc-00007-abc\""
    );
    assert!(got[1].contains(&"--freshness=3h".to_string()));
}

#[test]
fn revision_with_service_filters_logs_on_both() {
    let a = args(&[
        "--project",
        "prj-1",
        "--revision",
        "r-1",
        "--service",
        "svc",
    ]);
    let got = plan(&a, "prj-1").unwrap();
    assert_eq!(
        got[1].argv()[2],
        "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"svc\" AND resource.labels.revision_name=\"r-1\""
    );
}

// --- the write guard ------------------------------------------------------------

#[test]
fn every_command_the_tool_can_build_is_a_read() {
    let modes = [
        args(&["--project", "p", "--service", "s"]),
        args(&["--project", "p", "--revision", "r"]),
        args(&["--project", "p", "--revision", "r", "--service", "s"]),
    ];
    for a in &modes {
        for cmd in plan(a, "p").unwrap() {
            let argv = cmd.argv();
            let verb = if argv[0] == "logging" {
                &argv[1]
            } else {
                &argv[2]
            };
            assert!(
                ALLOWED_VERBS.contains(&verb.as_str()),
                "{:?} is not a read",
                argv
            );
            assert!(guard(argv).is_ok());
        }
    }
}

#[test]
fn guard_rejects_write_verbs() {
    for bad in [
        vec!["run", "deploy", "svc"],
        vec!["run", "services", "update", "svc", "--image=x"],
        vec!["run", "services", "update-traffic", "svc", "--to-latest"],
        vec!["run", "services", "delete", "svc"],
        vec!["run", "services", "replace", "svc.yaml"],
        vec!["run", "services", "set-iam-policy", "svc", "p.json"],
        vec!["run", "services", "add-iam-policy-binding", "svc"],
        vec!["run", "services", "remove-iam-policy-binding", "svc"],
        vec!["run", "revisions", "delete", "rev"],
        vec!["run", "jobs", "execute", "j"],
        vec!["logging", "write", "log", "msg"],
        vec!["logging", "sinks", "delete", "s"],
        vec!["projects", "delete", "p"],
        vec!["run", "services"],
        vec![],
    ] {
        assert!(guard(&v(&bad)).is_err(), "guard let through {:?}", bad);
    }
}

#[test]
fn builder_refuses_write_verbs() {
    for verb in [
        "update",
        "delete",
        "replace",
        "update-traffic",
        "set-iam-policy",
        "deploy",
    ] {
        assert!(
            gcloud(&["run", "services"], verb, &v(&["svc"])).is_err(),
            "built {}",
            verb
        );
    }
    assert!(gcloud(&["run"], "deploy", &v(&["svc"])).is_err());
}

#[test]
fn guard_refuses_credentials_on_argv() {
    assert!(guard(&v(&[
        "run",
        "services",
        "list",
        "--access-token-file=/tmp/t"
    ]))
    .is_err());
    assert!(guard(&v(&[
        "run",
        "services",
        "list",
        "--impersonate-service-account=x"
    ]))
    .is_err());
}

// --- the run loop, with a fake runner ------------------------------------------

#[derive(Default)]
struct Fake {
    minted_for: Vec<String>,
    ran: Vec<(Vec<String>, String)>,
    out: Vec<String>,
    err: Vec<String>,
    fail_mint: bool,
}

const TOKEN: &str = "ya29.SECRET-TOKEN-VALUE-0123456789abcdefghijklmnop";

impl Runner for Fake {
    fn mint_token(&mut self, account: &str) -> Result<String, String> {
        self.minted_for.push(account.to_string());
        if self.fail_mint {
            Err("no creds".into())
        } else {
            Ok(TOKEN.into())
        }
    }
    fn gcloud(&mut self, cmd: &GcloudCmd, token: &str) -> i32 {
        self.ran.push((cmd.argv().to_vec(), token.to_string()));
        0
    }
    fn say(&mut self, line: &str) {
        self.out.push(line.into());
    }
    fn warn(&mut self, line: &str) {
        self.err.push(line.into());
    }
}

#[test]
fn run_mints_for_the_operator_and_never_puts_the_token_on_argv_or_output() {
    let mut f = Fake::default();
    let code = run(
        &v(&[
            "--app",
            "oauth-user-inspector",
            "--service",
            "oauth-user-inspector-development",
        ]),
        &workspace("run"),
        &mut f,
    );
    assert_eq!(code, 0, "stderr: {:?}", f.err);
    assert_eq!(f.minted_for, vec![DEFAULT_OPERATOR_ACCOUNT.to_string()]);
    assert_eq!(f.ran.len(), 3);
    for (argv, token) in &f.ran {
        assert_eq!(token, TOKEN, "token is handed to the runner out of band");
        assert!(
            argv.iter().all(|a| !a.contains(TOKEN)),
            "token on argv: {:?}",
            argv
        );
        assert!(argv.contains(&"--project=prj-d-bu1-oss-floating-648a".to_string()));
    }
    assert!(
        f.out.iter().chain(&f.err).all(|l| !l.contains(TOKEN)),
        "token printed"
    );
}

#[test]
fn run_stops_before_gcloud_when_no_token() {
    let mut f = Fake {
        fail_mint: true,
        ..Default::default()
    };
    let code = run(
        &v(&["--project", "prj-1", "--service", "s"]),
        Path::new("."),
        &mut f,
    );
    assert_eq!(code, 1);
    assert!(f.ran.is_empty());
}

#[test]
fn help_and_bad_args_run_nothing() {
    let mut f = Fake::default();
    assert_eq!(run(&v(&["--help"]), Path::new("."), &mut f), 0);
    assert_eq!(run(&v(&["--service", "s"]), Path::new("."), &mut f), 2);
    assert!(f.minted_for.is_empty() && f.ran.is_empty());
}

#[test]
fn last_line_takes_the_token_after_diagnostics() {
    assert_eq!(
        last_line("note: using broker\nya29.abc\n\n").as_deref(),
        Some("ya29.abc")
    );
    assert_eq!(last_line("\n \n"), None);
}

// --- the real runner: the token file outlives nothing ------------------------

fn script(dir: &Path, name: &str, body: &str) -> PathBuf {
    use std::os::unix::fs::PermissionsExt;
    let p = dir.join(name);
    std::fs::write(&p, format!("#!/bin/sh\n{}\n", body)).unwrap();
    std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
    p
}

/// Ctrl-C reaches gcloud and this tool together. The fake gcloud sends
/// SIGINT to us (its parent) and exits as gcloud would; we must survive,
/// stop, and delete the token file. Without the signal handlers this test
/// process is killed by the SIGINT and the test fails.
#[test]
fn ctrl_c_during_gcloud_still_deletes_the_token_file() {
    let dir = workspace("sigint");
    let seen = dir.join("seen-token-file");
    let token_bin = script(&dir, "gcp-token", &format!("echo diag >&2; echo {}", TOKEN));
    let gcloud_bin = script(
        &dir,
        "gcloud",
        &format!(
            "cp \"$CLOUDSDK_AUTH_ACCESS_TOKEN_FILE\" '{seen}.content'; echo \"$CLOUDSDK_AUTH_ACCESS_TOKEN_FILE\" > '{seen}'; kill -INT $PPID; exit 130",
            seen = seen.display()
        ),
    );
    let mut r = SystemRunner::new(token_bin, gcloud_bin.display().to_string());
    let code = run(
        &v(&["--project", "prj-1", "--service", "svc"]),
        &dir,
        &mut r,
    );
    drop(r);
    assert_eq!(code, 130, "stops after the interrupted command");
    let file = std::fs::read_to_string(&seen).expect("gcloud ran once");
    assert_eq!(
        std::fs::read_to_string(format!("{}.content", seen.display())).unwrap(),
        TOKEN
    );
    assert!(
        !Path::new(file.trim()).exists(),
        "token file left behind: {}",
        file.trim()
    );
    assert!(signals::interrupted());
}

#[test]
fn sweeps_token_files_of_dead_processes_only() {
    let dir = workspace("sweep");
    let dead = dir.join("gcp-cloudrun-2147483646.token"); // above any pid_max
    let mine = dir.join(format!("gcp-cloudrun-{}.token", std::process::id()));
    let other = dir.join("gcp-cloudrun-notes.txt");
    for p in [&dead, &mine, &other] {
        std::fs::write(p, "x").unwrap();
    }
    assert_eq!(sweep_stale_token_files(&dir), 1);
    assert!(!dead.exists() && mine.exists() && other.exists());
}
