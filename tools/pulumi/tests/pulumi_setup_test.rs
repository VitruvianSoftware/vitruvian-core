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

//! //tools/pulumi:pulumi-setup (every pulumi_project() :setup target) with
//! stub `pulumi`, `go` and `gh`. The former pulumi_setup.sh had no suite of
//! its own; these cases pin its behaviour, including the parity gaps fixed
//! in the cutover (marked "gap").

mod common;
use common::*;
use std::path::PathBuf;

const PULUMI: &str = r#"#!/usr/bin/env bash
echo "$*" >>"$PULUMI_LOG"
case "$*" in
  whoami) echo alice; exit "${WHOAMI_RC:-0}" ;;
  "stack --show-name") echo dev; exit "${SHOW_RC:-0}" ;;
  "stack ls") echo STACKLS-OUT; echo STACKLS-ERR >&2; exit "${LS_RC:-0}" ;;
  "stack select "*) exit "${SELECT_RC:-0}" ;;
  "stack init "*) exit "${INIT_RC:-0}" ;;
  login) exit "${LOGIN_RC:-0}" ;;
esac
exit 0
"#;

const GO: &str =
    "#!/usr/bin/env bash\necho \"gowork=$GOWORK $*\" >>\"$GO_LOG\"\nexit \"${GO_RC:-0}\"\n";

const GH: &str = r#"#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$1 $2" in
  "variable set") echo "gh-set $3=$5"; exit "${GH_SET_RC:-0}" ;;
  "repo view") printf '%s' "${GH_OWNER-}"; exit "${GH_VIEW_RC:-0}" ;;
  "variable list") echo "PULUMI_APP_ID  123"; exit 0 ;;
  "secret list") echo "APP_PRIVATE_KEY"; [ -n "${GH_NO_TOKEN:-}" ] || echo "PULUMI_ACCESS_TOKEN"; exit 0 ;;
esac
exit 0
"#;

struct Fx {
    d: PathBuf,
    ws: PathBuf,
    stubs: PathBuf,
}

struct Res {
    rc: i32,
    out: String,
    err: String,
    pulumi: String,
    go: String,
    gh: String,
}

impl Fx {
    fn new(with_gh: bool) -> Fx {
        let d = tempdir("pulumi-setup");
        let ws = d.join("ws");
        std::fs::create_dir_all(ws.join("infra/app")).unwrap();
        std::fs::create_dir_all(ws.join("infrastructure/pulumi/platform/repo-config")).unwrap();
        let stubs = d.join("stubs");
        write_exec(&stubs.join("pulumi"), PULUMI);
        write_exec(&stubs.join("go"), GO);
        if with_gh {
            write_exec(&stubs.join("gh"), GH);
        }
        Fx { d, ws, stubs }
    }

    fn run(&self, dir: &str, stdin: &str, env: &[(&str, &str)]) -> Res {
        use std::io::Write;
        let mut c = cmd(
            &bin("PULUMI_SETUP_BIN"),
            &format!("{}:/usr/bin:/bin", self.stubs.display()),
        );
        c.env("BUILD_WORKSPACE_DIRECTORY", &self.ws)
            .env("PULUMI_LOG", self.d.join("pulumi.log"))
            .env("GO_LOG", self.d.join("go.log"))
            .env("GH_LOG", self.d.join("gh.log"))
            .arg(dir)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        for (k, v) in env {
            c.env(k, v);
        }
        let mut child = c.spawn().unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(stdin.as_bytes())
            .unwrap();
        let o = child.wait_with_output().unwrap();
        Res {
            rc: code(&o),
            out: stdout(&o),
            err: stderr(&o),
            pulumi: read(&self.d.join("pulumi.log")),
            go: read(&self.d.join("go.log")),
            gh: read(&self.d.join("gh.log")),
        }
    }
}

#[test]
fn happy_path_already_logged_in_and_selected() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "", &[]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(
        r.out.starts_with("Pulumi setup for infra/app\n"),
        "{}",
        r.out
    );
    assert!(r.out.contains("\u{2713} pulumi and go are installed."));
    assert!(
        r.out
            .contains("\u{2713} Already logged in to Pulumi as 'alice'."),
        "{}",
        r.out
    );
    assert!(
        r.out.contains("\u{2713} Stack already selected: dev."),
        "{}",
        r.out
    );
    assert!(r.out.contains("! GITHUB_TOKEN is NOT set."), "{}", r.out);
    assert!(r.out.contains(
        "Next steps:\n      bazel run //infra/app:preview\n      bazel run //infra/app:up\n"
    ));
    assert!(r
        .out
        .ends_with("Done. This helper is safe to re-run any time.\n"));
    assert_eq!(r.go, "gowork=off mod tidy\n");
}

#[test]
fn github_token_is_acknowledged_not_printed() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "", &[("GITHUB_TOKEN", "ghp_secret")]);
    assert!(r
        .out
        .contains("\u{2713} GITHUB_TOKEN is set in the environment (value not shown)."));
    assert!(!r.out.contains("ghp_secret") && !r.err.contains("ghp_secret"));
}

#[test]
fn missing_pulumi_and_go_both_reported_exit_1() {
    let fx = Fx::new(false);
    std::fs::remove_file(fx.stubs.join("pulumi")).unwrap();
    std::fs::remove_file(fx.stubs.join("go")).unwrap();
    let r = fx.run("infra/app", "", &[]);
    assert_eq!(r.rc, 1);
    assert!(r.err.contains("! pulumi CLI not found."), "{}", r.err);
    assert!(r.err.contains("! go toolchain not found."), "{}", r.err);
    assert!(
        r.err.contains("Install the missing tool(s) above"),
        "{}",
        r.err
    );
}

#[test]
fn not_logged_in_runs_login() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "", &[("WHOAMI_RC", "1")]);
    assert_eq!(r.rc, 0);
    assert!(r.pulumi.lines().any(|l| l == "login"), "{}", r.pulumi);
}

#[test]
fn stack_prompt_selects_existing() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "  prod  \n", &[("SHOW_RC", "1")]);
    assert_eq!(r.rc, 0);
    assert!(
        r.out.contains("Available stacks:\nSTACKLS-OUT\n"),
        "{}",
        r.out
    );
    assert!(r.pulumi.contains("stack select prod\n"), "{}", r.pulumi);
    assert!(r.out.contains("\u{2713} Selected existing stack 'prod'."));
}

#[test]
fn stack_prompt_defaults_to_dev_and_creates_it() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "", &[("SHOW_RC", "1"), ("SELECT_RC", "1")]);
    assert_eq!(r.rc, 0);
    assert!(r.pulumi.contains("stack init dev\n"), "{}", r.pulumi);
    assert!(r.out.contains("\u{2713} Created and selected stack 'dev'."));
}

#[test]
fn stack_ls_failure_prints_none_yet() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "dev\n", &[("SHOW_RC", "1"), ("LS_RC", "1")]);
    assert!(r.out.contains("  (none yet)"), "{}", r.out);
}

// gap: `pulumi stack ls 2>/dev/null` -- its stderr is not shown.
#[test]
fn gap_stack_ls_stderr_is_suppressed() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "dev\n", &[("SHOW_RC", "1")]);
    assert!(!r.err.contains("STACKLS-ERR"), "{}", r.err);
}

// gap: under `set -e` a failing step exits with THAT step's status, not 1.
#[test]
fn gap_go_mod_tidy_exit_code_propagates() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "", &[("GO_RC", "3")]);
    assert_eq!(r.rc, 3);
    assert!(!r.out.contains("go.sum is up to date"));
}

#[test]
fn gap_login_exit_code_propagates() {
    let fx = Fx::new(false);
    let r = fx.run("infra/app", "", &[("WHOAMI_RC", "1"), ("LOGIN_RC", "4")]);
    assert_eq!(r.rc, 4);
}

#[test]
fn gap_stack_init_exit_code_propagates() {
    let fx = Fx::new(false);
    let r = fx.run(
        "infra/app",
        "",
        &[("SHOW_RC", "1"), ("SELECT_RC", "1"), ("INIT_RC", "5")],
    );
    assert_eq!(r.rc, 5);
}

// --- repo-config: adoption note and the CI/CD opt-in ------------------------

const RC: &str = "infrastructure/pulumi/platform/repo-config";

#[test]
fn repo_config_without_gh_skips_opt_in() {
    let fx = Fx::new(false);
    let r = fx.run(RC, "", &[]);
    assert_eq!(r.rc, 0);
    assert!(r.out.contains("Adoption note (repo-config)"), "{}", r.out);
    assert!(r.out.contains(&format!(
        "bazel run //{RC}:config -- set repoOwner <your-org-or-user>"
    )));
    assert!(
        r.out
            .contains("! gh CLI not found \u{2014} skipping CI/CD automation opt-in."),
        "{}",
        r.out
    );
    assert!(!r.out.contains("Next steps:"));
}

#[test]
fn repo_config_toggles_follow_answers() {
    let fx = Fx::new(true);
    let r = fx.run(RC, "YES\nn\n", &[("GH_OWNER", "acme")]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(
        r.gh.contains("variable set REPO_CONFIG_PREVIEW_ENABLED --body true\n"),
        "{}",
        r.gh
    );
    assert!(
        r.gh.contains("variable set REPO_CONFIG_AUTO_APPLY --body false\n"),
        "{}",
        r.gh
    );
    assert!(r.out.contains(
        "\u{2713} REPO_CONFIG_PREVIEW_ENABLED=true (preview will run on pull requests)."
    ));
    assert!(r
        .out
        .contains("\u{2713} REPO_CONFIG_AUTO_APPLY=false (apply-on-merge disabled)."));
    assert!(
        r.gh.contains("variable list --org acme\n") && r.gh.contains("secret list --org acme\n")
    );
    assert!(r.out.contains("\u{2713} Org-level Pulumi App credentials (PULUMI_APP_ID / APP_PRIVATE_KEY / PULUMI_ACCESS_TOKEN) are present."));
    assert!(r
        .out
        .contains("https://github.com/apps/<slug>/installations/new"));
}

// gap: `gh variable set` output is not hidden by the shell.
#[test]
fn gap_gh_variable_set_output_is_shown() {
    let fx = Fx::new(true);
    let r = fx.run(RC, "", &[("GH_OWNER", "acme")]);
    assert!(
        r.out.contains("gh-set REPO_CONFIG_PREVIEW_ENABLED=false"),
        "{}",
        r.out
    );
}

#[test]
fn gh_variable_set_failure_warns_and_continues() {
    let fx = Fx::new(true);
    let r = fx.run(RC, "", &[("GH_OWNER", "acme"), ("GH_SET_RC", "1")]);
    assert_eq!(r.rc, 0);
    assert!(
        r.err
            .contains("! Failed to set REPO_CONFIG_PREVIEW_ENABLED"),
        "{}",
        r.err
    );
    assert!(
        r.err.contains("! Failed to set REPO_CONFIG_AUTO_APPLY"),
        "{}",
        r.err
    );
}

#[test]
fn missing_org_token_is_flagged() {
    let fx = Fx::new(true);
    let r = fx.run(RC, "", &[("GH_OWNER", "acme"), ("GH_NO_TOKEN", "1")]);
    assert!(
        r.out
            .contains("! Org-level Pulumi App credentials not found"),
        "{}",
        r.out
    );
}

// gap: the shell tests `[ -n "$OWNER" ]`, so an empty answer from a
// successful `gh repo view` is "could not determine", not `--org ""`.
#[test]
fn gap_empty_owner_is_not_used() {
    let fx = Fx::new(true);
    let r = fx.run(RC, "", &[("GH_OWNER", "")]);
    assert!(
        r.out.contains("! Could not determine the repo owner"),
        "{}",
        r.out
    );
    assert!(!r.gh.contains("--org"), "{}", r.gh);
}

#[test]
fn missing_workspace_exits_1() {
    let fx = Fx::new(false);
    let mut c = cmd(
        &bin("PULUMI_SETUP_BIN"),
        &format!("{}:/usr/bin:/bin", fx.stubs.display()),
    );
    c.arg("infra/app");
    let o = run(c);
    assert_eq!(code(&o), 1);
    assert!(stderr(&o).contains("must be invoked via 'bazel run'"));
}
