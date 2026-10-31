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

//! //tools/pulumi:pulumi-cmd (the wrapper behind every pulumi_project()
//! :preview/:up/... target and //tools/deploy:cloud-run) against a stub
//! `pulumi` that logs its environment and argv.
//!
//! Cases 1-14 are ported 1:1 from the former pulumi_cmd_test.sh (15 checks:
//! case 14 runs twice). The rest are new: the two parity gaps fixed in the
//! cutover, and behaviour the shell suite never covered.

mod common;
use common::*;
use std::path::{Path, PathBuf};

const PULUMI_STUB: &str = r#"#!/usr/bin/env bash
n=0
[ -f "$STUB_COUNT" ] && n="$(cat "$STUB_COUNT")"
n=$((n + 1))
echo "$n" >"$STUB_COUNT"
echo "invocation $n: backend=${PULUMI_BACKEND_URL:-unset} gcp_token=${GOOGLE_OAUTH_ACCESS_TOKEN:-unset} gcp_project=${GOOGLE_CLOUD_PROJECT:-unset} kubeconfig=${KUBECONFIG:-unset} gowork=${GOWORK:-unset} pwd=$PWD args=$*" >>"$STUB_LOG"
if [ "${STUB_FAIL:-0}" -eq 1 ] && [ "$n" -le "${STUB_FAIL_TIMES:-999}" ]; then
    echo "simulated error: ${STUB_MSG:-failed}" >&2
    exit 23
fi
exit 0
"#;

struct Fx {
    d: PathBuf,
    ws: PathBuf,
    stubs: PathBuf,
}

impl Fx {
    fn new() -> Fx {
        let d = tempdir("pulumi-cmd");
        let ws = d.join("ws");
        for p in [
            "tabula/infra/web",
            "infra/minted",
            "infrastructure/pulumi/platform/dev-local",
        ] {
            std::fs::create_dir_all(ws.join(p)).unwrap();
        }
        std::fs::write(ws.join("infrastructure/gcp-identities.tsv"), "").unwrap();
        let stubs = d.join("stubs");
        write_exec(&stubs.join("pulumi"), PULUMI_STUB);
        Fx { d, ws, stubs }
    }

    fn path(&self) -> String {
        format!("{}:/usr/bin:/bin", self.stubs.display())
    }

    fn pin(&self, row: &str) {
        std::fs::write(self.ws.join("infrastructure/gcp-identities.tsv"), row).unwrap();
    }

    fn gcloud_stub(&self) {
        write_exec(
            &self.stubs.join("gcloud"),
            "#!/usr/bin/env bash\necho \"$*\" >>\"$GCLOUD_LOG\"\necho \"${GCLOUD_TOKEN-gcloud-token}\"\n",
        );
    }

    /// A command for the wrapper with the stub log/count wired up; returns
    /// it with the log and count paths.
    fn cmd(&self, dir: &str, args: &[&str]) -> (std::process::Command, PathBuf, PathBuf) {
        let n = std::fs::read_dir(&self.d).unwrap().count();
        let log = self.d.join(format!("log.{n}"));
        let count = self.d.join(format!("count.{n}"));
        std::fs::write(&log, "").unwrap();
        std::fs::write(&count, "").unwrap();
        let mut c = cmd(&bin("PULUMI_CMD_BIN"), &self.path());
        c.env("BUILD_WORKSPACE_DIRECTORY", &self.ws)
            .env("HOME", self.d.join("home"))
            .env("STUB_COUNT", &count)
            .env("STUB_LOG", &log)
            .env("GCLOUD_LOG", self.d.join("gcloud.log"))
            .env("PULUMI_CONFLICT_RETRY_DELAY", "0")
            .arg(dir)
            .args(args);
        (c, log, count)
    }
}

struct Res {
    rc: i32,
    n: u32,
    log: String,
    err: String,
}

fn exec(c: std::process::Command, log: &Path, count: &Path) -> Res {
    let o = run(c);
    Res {
        rc: code(&o),
        n: read(count).trim().parse().unwrap_or(0),
        log: read(log),
        err: stderr(&o),
    }
}

/// The shell suite's run_cmd: tabula/infra/web, `--stack development --yes`,
/// CI=1, the three backend inputs set (possibly empty), retry delay 0.
fn run_cmd(
    fx: &Fx,
    subcmd: &str,
    fail: bool,
    msg: &str,
    backend: &str,
    gcp_proj: &str,
    token: &str,
    extra: &[(&str, &str)],
) -> Res {
    let (mut c, log, count) = fx.cmd(
        "tabula/infra/web",
        &[subcmd, "--stack", "development", "--yes"],
    );
    c.env("STUB_FAIL", if fail { "1" } else { "0" })
        .env("STUB_MSG", msg)
        .env("PULUMI_BACKEND_URL", backend)
        .env("GOOGLE_CLOUD_PROJECT", gcp_proj)
        .env("PULUMI_ACCESS_TOKEN", token)
        .env("CI", "1")
        .env("PULUMI_CONFLICT_MAX_ATTEMPTS", "5");
    for (k, v) in extra {
        c.env(k, v);
    }
    exec(c, &log, &count)
}

// 1. Clean execution passes immediately.
#[test]
fn t01_clean_run_single_invocation() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        false,
        "ok",
        "gs://bu2-tabula-pulumi-state-dev",
        "",
        "",
        &[],
    );
    assert_eq!((r.rc, r.n), (0, 1), "{}", r.err);
}

// 2. Errors fail fast without retrying.
#[test]
fn t02_error_fails_fast() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        true,
        "boom: unrecoverable provider error",
        "gs://bu2-tabula-pulumi-state-dev",
        "",
        "",
        &[],
    );
    assert_eq!((r.rc, r.n), (23, 1));
}

// 3. Backend URL and --non-interactive forwarded faithfully.
#[test]
fn t03_backend_and_non_interactive_forwarded() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "preview",
        false,
        "ok",
        "gs://my-custom-state-bucket",
        "",
        "",
        &[],
    );
    assert!(
        r.log.contains("backend=gs://my-custom-state-bucket"),
        "{}",
        r.log
    );
    assert!(
        r.log
            .contains("args=preview --stack development --yes --non-interactive"),
        "{}",
        r.log
    );
}

// 4. GCS backend derived from GOOGLE_CLOUD_PROJECT.
#[test]
fn t04_gcs_backend_from_project() {
    let fx = Fx::new();
    let r = run_cmd(&fx, "up", false, "ok", "", "prj-d-bu2-tabula-1234", "", &[]);
    assert!(
        r.log
            .contains("backend=gs://prj-d-bu2-tabula-1234-pulumi-state"),
        "{}",
        r.log
    );
}

// 5. PULUMI_ACCESS_TOKEN wins over a derivable GCS bucket (2026-09-02 404 regression).
#[test]
fn t05_token_wins_over_gcs() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        false,
        "ok",
        "",
        "prj-d-bu1-oss-floating-648a",
        "pul-fake-token",
        &[],
    );
    assert!(
        r.log.contains("backend=https://api.pulumi.com"),
        "{}",
        r.log
    );
}

// 6. No token and no project falls back to Pulumi Cloud.
#[test]
fn t06_default_is_pulumi_cloud() {
    let fx = Fx::new();
    let r = run_cmd(&fx, "up", false, "ok", "", "", "", &[]);
    assert!(
        r.log.contains("backend=https://api.pulumi.com"),
        "{}",
        r.log
    );
}

// 7. Explicit PULUMI_BACKEND_URL wins over everything.
#[test]
fn t07_explicit_backend_wins() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        false,
        "ok",
        "gs://explicit-override",
        "prj-d-bu1-oss-floating-648a",
        "pul-fake-token",
        &[],
    );
    assert!(
        r.log.contains("backend=gs://explicit-override"),
        "{}",
        r.log
    );
}

// 8. The account-wide 409 is retried, then succeeds.
#[test]
fn t08_conflict_retried() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx, "up", true,
        "error: [409] Conflict: You have a running update for the stack 'zitadel-apps/development'. Your organization does not support concurrent updates.",
        "gs://b", "", "", &[("STUB_FAIL_TIMES", "2")],
    );
    assert_eq!((r.rc, r.n), (0, 3), "{}", r.err);
}

// 9. A non-409 error fails fast, exit code preserved.
#[test]
fn t09_non_409_fails_fast() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        true,
        "error: provider mis-configured",
        "gs://b",
        "",
        "",
        &[],
    );
    assert_eq!((r.rc, r.n), (23, 1));
}

// 10. A bare 409 without the concurrency marker is not retried.
#[test]
fn t10_bare_409_not_retried() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        true,
        "error: [409] Conflict: some other conflict",
        "gs://b",
        "",
        "",
        &[],
    );
    assert_eq!((r.rc, r.n), (23, 1));
}

// 11. The retry budget is bounded; the child's exit code survives.
#[test]
fn t11_retry_budget_bounded() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        true,
        "error: [409] Conflict: does not support concurrent updates",
        "gs://b",
        "",
        "",
        &[("PULUMI_CONFLICT_MAX_ATTEMPTS", "3")],
    );
    assert_eq!((r.rc, r.n), (23, 3));
}

// --- GCP token minting (cases 12-14) ---------------------------------------
// A project pinned in gcp-identities.tsv gets its token from //tools/gcp-token,
// handed over as VITRUVIAN_GCP_TOKEN_BIN (runfiles-relative), resolved before
// the wrapper changes directory. Regression guard for #3973 / #4052.

struct Minted {
    rc: i32,
    minter_argv: String,
    gcloud_argv: String,
    log: String,
}

fn run_minted(fx: &Fx, token_bin: &str) -> Minted {
    fx.pin("infra/minted  sa-test@prj-test.iam.gserviceaccount.com  prj-test  test row\n");
    fx.gcloud_stub();
    let rf = fx.d.join("runfiles/_main");
    write_exec(
        &rf.join("tools/gcp-token/gcp-token"),
        "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" >>\"$MINTER_LOG\"\necho \"minted-token\"\n",
    );
    let minter_log = fx.d.join("minter.log");
    let _ = std::fs::remove_file(&minter_log);
    let _ = std::fs::remove_file(fx.d.join("gcloud.log"));
    let (mut c, log, count) = fx.cmd("infra/minted", &["preview"]);
    c.current_dir(&rf)
        .env("VITRUVIAN_GCP_TOKEN_BIN", token_bin)
        .env("MINTER_LOG", &minter_log)
        .env("STUB_FAIL", "0")
        .env("PULUMI_BACKEND_URL", "gs://b")
        .env("CI", "1");
    let r = exec(c, &log, &count);
    Minted {
        rc: r.rc,
        minter_argv: read(&minter_log).replace('\n', " "),
        gcloud_argv: read(&fx.d.join("gcloud.log")).trim_end().to_string(),
        log: r.log,
    }
}

// 12. A pinned identity's token comes from //tools/gcp-token (relative path).
#[test]
fn t12_relative_minter_used() {
    let fx = Fx::new();
    let m = run_minted(&fx, "tools/gcp-token/gcp-token");
    assert_eq!(m.rc, 0);
    assert_eq!(m.minter_argv, "sa-test@prj-test.iam.gserviceaccount.com ");
    assert_eq!(m.gcloud_argv, "", "gcloud must not be called");
    assert!(m.log.contains("gcp_token=minted-token"), "{}", m.log);
}

// 13. An absolute minter path works too.
#[test]
fn t13_absolute_minter_used() {
    let fx = Fx::new();
    let abs = fx.d.join("runfiles/_main/tools/gcp-token/gcp-token");
    let m = run_minted(&fx, abs.to_str().unwrap());
    assert_eq!(m.rc, 0);
    assert!(m.log.contains("gcp_token=minted-token"), "{}", m.log);
}

// 14. No minter (unset/empty, or not found) falls back to plain gcloud.
fn assert_gcloud_fallback(bin: &str) {
    let fx = Fx::new();
    let m = run_minted(&fx, bin);
    assert_eq!(m.rc, 0, "bin={bin:?}");
    assert_eq!(m.minter_argv, "", "bin={bin:?}");
    assert_eq!(
        m.gcloud_argv, "auth print-access-token --account=sa-test@prj-test.iam.gserviceaccount.com",
        "bin={bin:?}"
    );
    assert!(
        m.log.contains("gcp_token=gcloud-token"),
        "bin={bin:?}: {}",
        m.log
    );
    assert!(m.log.contains("gcp_project=prj-test"), "{}", m.log);
}

#[test]
fn t14a_empty_minter_falls_back_to_gcloud() {
    assert_gcloud_fallback("");
}

#[test]
fn t14b_missing_minter_falls_back_to_gcloud() {
    assert_gcloud_fallback("tools/gcp-token/missing");
}

// --- New: parity gaps fixed in the cutover ----------------------------------

// The shell derives the bucket from `${GOOGLE_CLOUD_PROJECT:-${GCP_PROJECT_ID:-}}`:
// an EMPTY GOOGLE_CLOUD_PROJECT falls through to GCP_PROJECT_ID (the deploy lanes
// export GCP_PROJECT_ID).
#[test]
fn gap_empty_google_cloud_project_falls_back_to_gcp_project_id() {
    let fx = Fx::new();
    let r = run_cmd(
        &fx,
        "up",
        false,
        "ok",
        "",
        "",
        "",
        &[("GCP_PROJECT_ID", "prj-from-id")],
    );
    assert!(
        r.log.contains("backend=gs://prj-from-id-pulumi-state"),
        "{}",
        r.log
    );
}

// The shell only recognises the exact token `--non-interactive`; any other
// spelling (e.g. `--non-interactive=false`) still gets the flag appended in CI.
#[test]
fn gap_non_interactive_matches_exact_token_only() {
    let fx = Fx::new();
    let (mut c, log, count) = fx.cmd("tabula/infra/web", &["preview", "--non-interactive=false"]);
    c.env("PULUMI_BACKEND_URL", "gs://b").env("CI", "1");
    let r = exec(c, &log, &count);
    assert!(
        r.log
            .contains("args=preview --non-interactive=false --non-interactive"),
        "{}",
        r.log
    );
}

// --- New: behaviour the shell suite never covered ---------------------------

#[test]
fn explicit_non_interactive_not_duplicated() {
    let fx = Fx::new();
    let (mut c, log, count) = fx.cmd("tabula/infra/web", &["preview", "--non-interactive"]);
    c.env("PULUMI_BACKEND_URL", "gs://b").env("CI", "1");
    let r = exec(c, &log, &count);
    assert!(
        r.log.ends_with("args=preview --non-interactive\n"),
        "{}",
        r.log
    );
}

#[test]
fn runs_in_project_dir_with_gowork_off() {
    let fx = Fx::new();
    let r = run_cmd(&fx, "up", false, "ok", "gs://b", "", "", &[]);
    assert!(
        r.log
            .contains(&format!("pwd={}/tabula/infra/web ", fx.ws.display())),
        "{}",
        r.log
    );
    assert!(r.log.contains("gowork=off"), "{}", r.log);
}

#[test]
fn dev_local_pins_stack_backend_and_kubeconfig() {
    let fx = Fx::new();
    let (mut c, log, count) = fx.cmd("infrastructure/pulumi/platform/dev-local", &["preview"]);
    c.env("CI", "1");
    let r = exec(c, &log, &count);
    assert!(
        r.log.contains("backend=https://api.pulumi.com"),
        "{}",
        r.log
    );
    assert!(
        r.log.contains(&format!(
            "kubeconfig={}/home/.kube/cluster.yaml",
            fx.d.display()
        )),
        "{}",
        r.log
    );
    assert!(
        r.log
            .contains("args=preview --stack local --non-interactive"),
        "{}",
        r.log
    );
}

#[test]
fn dev_local_caller_stack_wins() {
    let fx = Fx::new();
    for flag in [vec!["--stack=other"], vec!["-s", "other"]] {
        let mut args = vec!["preview"];
        args.extend(flag.iter().copied());
        let (mut c, log, count) = fx.cmd("infrastructure/pulumi/platform/dev-local", &args);
        c.env("CI", "1");
        let r = exec(c, &log, &count);
        assert!(!r.log.contains("--stack local"), "{flag:?}: {}", r.log);
    }
}

#[test]
fn pulumi_org_qualifies_bare_stack_names_on_cloud_backend() {
    let fx = Fx::new();
    let (mut c, log, count) = fx.cmd(
        "tabula/infra/web",
        &[
            "preview",
            "--stack",
            "dev",
            "-s=prod",
            "--stack=acme/keep",
            "--stack",
            "x/y",
        ],
    );
    c.env("PULUMI_BACKEND_URL", "https://api.pulumi.com")
        .env("PULUMI_ORG", "vitruvian")
        .env("CI", "1");
    let r = exec(c, &log, &count);
    assert!(
        r.log.contains("args=preview --stack vitruvian/dev -s=vitruvian/prod --stack=acme/keep --stack x/y --non-interactive"),
        "{}",
        r.log
    );
}

#[test]
fn pulumi_org_ignored_on_gcs_backend() {
    let fx = Fx::new();
    let (mut c, log, count) = fx.cmd("tabula/infra/web", &["preview", "--stack", "dev"]);
    c.env("PULUMI_BACKEND_URL", "gs://b")
        .env("PULUMI_ORG", "vitruvian")
        .env("CI", "1");
    let r = exec(c, &log, &count);
    assert!(
        r.log.contains("args=preview --stack dev --non-interactive"),
        "{}",
        r.log
    );
}

#[test]
fn ambient_credentials_skip_the_pin() {
    let fx = Fx::new();
    fx.pin("tabula/infra/web  someone@example.com  prj-x  row\n");
    fx.gcloud_stub();
    for var in [
        "GOOGLE_OAUTH_ACCESS_TOKEN",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "CLOUDSDK_AUTH_ACCESS_TOKEN",
    ] {
        let (mut c, log, count) = fx.cmd("tabula/infra/web", &["preview"]);
        c.env("PULUMI_BACKEND_URL", "gs://b")
            .env(var, "ambient")
            .env("CI", "1");
        let r = exec(c, &log, &count);
        assert_eq!(r.rc, 0);
        assert!(
            r.err.contains("ambient credentials present"),
            "{var}: {}",
            r.err
        );
        assert!(
            read(&fx.d.join("gcloud.log")).is_empty(),
            "{var}: gcloud was called"
        );
    }
}

#[test]
fn pinned_identity_without_gcloud_exits_1() {
    let fx = Fx::new();
    fx.pin("tabula/infra/web  someone@example.com  prj-x  row\n");
    let (mut c, log, count) = fx.cmd("tabula/infra/web", &["preview"]);
    c.env("PULUMI_BACKEND_URL", "gs://b").env("CI", "1");
    let r = exec(c, &log, &count);
    assert_eq!((r.rc, r.n), (1, 0));
    assert!(
        r.err.contains("but the gcloud CLI is not installed"),
        "{}",
        r.err
    );
}

#[test]
fn pinned_identity_with_no_token_exits_1() {
    let fx = Fx::new();
    fx.pin("tabula/infra/web  someone@example.com  prj-x  row\n");
    fx.gcloud_stub();
    let (mut c, log, count) = fx.cmd("tabula/infra/web", &["preview"]);
    c.env("PULUMI_BACKEND_URL", "gs://b")
        .env("CI", "1")
        .env("GCLOUD_TOKEN", "");
    let r = exec(c, &log, &count);
    assert_eq!((r.rc, r.n), (1, 0));
    assert!(
        r.err
            .contains("Log in with:  gcloud auth login someone@example.com"),
        "{}",
        r.err
    );
}

#[test]
fn missing_pulumi_exits_1() {
    let fx = Fx::new();
    let mut c = cmd(&bin("PULUMI_CMD_BIN"), "/usr/bin:/bin");
    c.env("BUILD_WORKSPACE_DIRECTORY", &fx.ws)
        .args(["tabula/infra/web", "preview"]);
    let o = run(c);
    assert_eq!(code(&o), 1);
    assert!(stderr(&o)
        .contains("pulumi CLI not found on PATH. Run 'bazel run //tabula/infra/web:setup' first,"));
}

#[test]
fn missing_workspace_exits_1() {
    let fx = Fx::new();
    let mut c = cmd(&bin("PULUMI_CMD_BIN"), &fx.path());
    c.args(["tabula/infra/web", "preview"]);
    let o = run(c);
    assert_eq!(code(&o), 1);
    assert!(stderr(&o).contains("must be invoked via 'bazel run'"));
}
