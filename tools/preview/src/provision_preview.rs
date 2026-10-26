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

//! provision-preview: provision-preview.sh in Rust. Branches the database
//! (through the neon-branch tool next to it), deploys the compute (gcloud
//! or kubectl), smokes it with curl and prints the preview's JSON -- the same
//! commands, log lines, output and exit codes as the script.
//!
//! Where the script runs `${SCRIPT_DIR}/neon-branch.sh`, the port runs
//! `neon-branch` from its own directory: the Rust tool its rust_binary target
//! carries in `data` (the script's sh_binary carries the script).

use crate::common::{captured, echo, inherited, log, pipeline, prog, prog_name, unbound};
use crate::jq::{self, one, J};
use shell_compat::{cat, err, out, subst};
use std::process::Command;

const USAGE: &str = "Usage: {PROG} --app <name> --pr <number> [options]

Required:
  --app <name>               Application name (e.g. tabula-api, oauth-user-inspector)
  --pr <number>              Pull Request number (e.g. 142)

Options:
  --image-digest <ref>       Container image digest (sha256:...)
  --mode <cloud-run|k8s>     Compute mode (default: cloud-run)
  --project <id>             GCP Project ID (env: GCP_PROJECT_ID)
  --region <region>          GCP Region (default: us-central1)
  --neon-project-id <id>     Neon Project ID for Postgres branching
  --smoke-path <path>        Path for candidate health check (default: /health)
  --domain-base <domain>     Base preview domain (default: preview.vitruviansoftware.dev)
  --dry-run                  Simulate provisioning without making changes
  -h, --help                 Show this help message
";

fn usage(code: i32) -> i32 {
    let mut parts = USAGE.splitn(2, "{PROG}");
    let head = parts.next().unwrap_or("");
    let tail = parts.next().unwrap_or("");
    out(&cat(&[head.as_bytes(), &prog_name(), tail.as_bytes()]));
    code
}

type R<T> = Result<T, i32>;

fn check(st: i32) -> R<()> {
    if st == 0 {
        Ok(())
    } else {
        Err(st)
    }
}

/// The directory the neon-branch tool is looked up in: where this binary
/// was started from (`$(dirname "${BASH_SOURCE[0]}")`), made absolute;
/// the executable's own directory when it was found on PATH.
fn tool_dir() -> Vec<u8> {
    let p = prog();
    let dir = if p.contains(&b'/') {
        shell_compat::dirname(&p)
    } else {
        std::env::current_exe()
            .ok()
            .and_then(|e| e.parent().map(shell_compat::path_bytes))
            .unwrap_or_else(|| b".".to_vec())
    };
    if dir.starts_with(b"/") {
        return dir;
    }
    let cwd = std::env::current_dir()
        .map(|d| shell_compat::path_bytes(&d))
        .unwrap_or_default();
    if dir == b"." {
        cwd
    } else {
        cat(&[&cwd, b"/", dir.strip_prefix(b"./").unwrap_or(&dir)])
    }
}

/// provision-preview.sh's command line; the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    match main(args) {
        Ok(()) => 0,
        Err(c) => c,
    }
}

fn os(b: &[u8]) -> &std::ffi::OsStr {
    shell_compat::os(b)
}

fn main(args: &[Vec<u8>]) -> R<()> {
    let mut app: Vec<u8> = Vec::new();
    let mut pr: Vec<u8> = Vec::new();
    let mut image_digest: Vec<u8> = Vec::new();
    let mut mode: Vec<u8> = b"cloud-run".to_vec();
    let mut gcp_project = shell_compat::env_or_empty("GCP_PROJECT_ID");
    let mut region = shell_compat::env_or("GCP_REGION", b"us-central1");
    let mut neon_project_id = shell_compat::env_or_empty("NEON_PROJECT_ID");
    let mut smoke_path: Vec<u8> = b"/health".to_vec();
    let mut domain_base: Vec<u8> = b"preview.vitruviansoftware.dev".to_vec();
    let mut dry_run = false;

    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_slice();
        let (slot, line): (&mut Vec<u8>, u32) = match a {
            b"--app" => (&mut app, 44),
            b"--pr" => (&mut pr, 45),
            b"--image-digest" => (&mut image_digest, 46),
            b"--mode" => (&mut mode, 47),
            b"--project" => (&mut gcp_project, 48),
            b"--region" => (&mut region, 49),
            b"--neon-project-id" => (&mut neon_project_id, 50),
            b"--smoke-path" => (&mut smoke_path, 51),
            b"--domain-base" => (&mut domain_base, 52),
            b"--dry-run" => {
                dry_run = true;
                i += 1;
                continue;
            }
            b"-h" | b"--help" => return Err(usage(0)),
            _ => {
                err(&cat(&[b"ERROR: Unknown option: ", a, b"\n"]));
                return Err(usage(1));
            }
        };
        match args.get(i + 1) {
            Some(v) => *slot = v.clone(),
            None => return Err(unbound(line)),
        }
        i += 2;
    }

    if app.is_empty() || pr.is_empty() {
        err(b"ERROR: --app and --pr are required\n");
        return Err(usage(1));
    }
    if !dry_run && mode == b"cloud-run" {
        if image_digest.is_empty() {
            err(b"ERROR: --image-digest is required in cloud-run mode\n");
            return Err(1);
        }
        if gcp_project.is_empty() {
            err(b"ERROR: --project or GCP_PROJECT_ID is required\n");
            return Err(1);
        }
    }

    let service_name = cat(&[&app, b"-pr-", &pr]);
    let branch_name = service_name.clone();
    let preview_hostname = cat(&[b"pr-", &pr, b".", &app, b".", &domain_base]);
    let preview_url = cat(&[b"https://", &preview_hostname]);
    let rule = b"============================================================" as &[u8];

    log(&[rule]);
    log(&["🚀 Ephemeral Preview Provisioning Engine".as_bytes()]);
    log(&[b"  Application:   ", &app]);
    log(&[b"  PR Number:     #", &pr]);
    log(&[b"  Mode:          ", &mode]);
    log(&[b"  Service Name:  ", &service_name]);
    log(&[b"  Preview Host:  ", &preview_hostname]);
    log(&[rule]);

    // Step 1: the Neon branch.
    let mut database_url: Vec<u8> = Vec::new();
    if !neon_project_id.is_empty() {
        log(&[
            "📦 Step 1: Provisioning Neon Postgres Branch '".as_bytes(),
            &branch_name,
            b"'...",
        ]);
        if dry_run {
            database_url =
                b"postgresql://neondb_owner:mock@ep-mock.neon.tech/neondb?sslmode=require".to_vec();
            log(&[b"   [DRY-RUN] Neon Branch simulated: ", &database_url]);
        } else {
            let tool = cat(&[&tool_dir(), b"/neon-branch"]);
            let mut c = Command::new(os(&tool));
            c.arg("create")
                .arg("--project-id")
                .arg(os(&neon_project_id))
                .arg("--branch-name")
                .arg(os(&branch_name))
                .args(["--format", "json"]);
            let (st, o) = captured(100, &mut c);
            check(st)?;
            let neon_out = subst(o);
            let r = jq::run(
                &echo(&neon_out),
                true,
                &|v: &J| one(v.index("database_url")),
            );
            err(&r.stderr);
            check(r.status)?;
            database_url = subst(r.stdout);
            let r = jq::run(&echo(&neon_out), true, &|v: &J| one(v.index("host")));
            err(&r.stderr);
            log(&["   ✓ Neon Branch ready: ".as_bytes(), &subst(r.stdout)]);
        }
    } else {
        log(&["⏩ Step 1: No Neon Project ID specified; skipping database branching.".as_bytes()]);
    }

    // Step 2: compute.
    let mut service_uri: Vec<u8> = Vec::new();
    if mode == b"cloud-run" {
        log(&[
            "☁️ Step 2: Deploying Cloud Run v2 service '".as_bytes(),
            &service_name,
            b"' in '",
            &region,
            b"'...",
        ]);
        if dry_run {
            service_uri = cat(&[b"https://", &service_name, b"-preview-uc.a.run.app"]);
            log(&[
                b"   [DRY-RUN] Cloud Run Service simulated at ",
                &service_uri,
            ]);
        } else {
            let mut env_vars = cat(&[
                b"NODE_ENV=preview,PREVIEW_PR_NUMBER=",
                &pr,
                b",API_URL=",
                &preview_url,
            ]);
            if !database_url.is_empty() {
                env_vars = cat(&[&env_vars, b",DATABASE_URL=", &database_url]);
            }
            let mut c = Command::new("gcloud");
            c.args(["run", "deploy"])
                .arg(os(&service_name))
                .arg("--project")
                .arg(os(&gcp_project))
                .arg("--region")
                .arg(os(&region))
                .arg("--image")
                .arg(os(&image_digest))
                .arg("--set-env-vars")
                .arg(os(&env_vars))
                .args(["--allow-unauthenticated", "--port", "8080", "--quiet"]);
            check(inherited(123, &mut c))?;
            let mut c = Command::new("gcloud");
            c.args(["run", "services", "describe"])
                .arg(os(&service_name))
                .arg("--project")
                .arg(os(&gcp_project))
                .arg("--region")
                .arg(os(&region))
                .args(["--format", "value(status.url)"]);
            let (st, o) = captured(125, &mut c);
            check(st)?;
            service_uri = subst(o);
            log(&[
                "   ✓ Cloud Run Service deployed at ".as_bytes(),
                &service_uri,
            ]);
        }
    } else if mode == b"k8s" {
        let ns = cat(&[b"pr-", &pr]);
        log(&[
            "☸️ Step 2: Provisioning Kubernetes namespace '".as_bytes(),
            &ns,
            b"'...",
        ]);
        service_uri = cat(&[b"https://pr-", &pr, b".", &app, b".lab.ipv1337.dev"]);
        if dry_run {
            log(&[
                b"   [DRY-RUN] Kubernetes Deployment simulated at ",
                &service_uri,
            ]);
        } else {
            let mut left = Command::new("kubectl");
            left.args(["create", "namespace"]).arg(os(&ns)).args([
                "--dry-run=client",
                "-o",
                "yaml",
            ]);
            let mut right = Command::new("kubectl");
            right.args(["apply", "-f", "-"]);
            check(pipeline(134, &mut left, &mut right))?;
            if !database_url.is_empty() {
                let mut left = Command::new("kubectl");
                left.args([
                    "create",
                    "secret",
                    "generic",
                    "app-db-secrets",
                    "--namespace",
                ])
                .arg(os(&ns))
                .arg(os(&cat(&[b"--from-literal=DATABASE_URL=", &database_url])))
                .args(["--dry-run=client", "-o", "yaml"]);
                let mut right = Command::new("kubectl");
                right.args(["apply", "-f", "-"]);
                check(pipeline(136, &mut left, &mut right))?;
            }
        }
    }

    // Step 3: smoke.
    log(&["🔍 Step 3: Running Candidate Health Smoke Check...".as_bytes()]);
    if dry_run {
        log(&[
            b"   [DRY-RUN] Smoke check HTTP GET ",
            &service_uri,
            &smoke_path,
            b" -> 200 OK",
        ]);
    } else {
        let target = cat(&[
            service_uri.strip_suffix(b"/").unwrap_or(&service_uri),
            &smoke_path,
        ]);
        log(&[b"   Pinging ", &target, b"..."]);
        let mut c = Command::new("curl");
        c.args(["-s", "-o", "/dev/null", "-w", "%{http_code}"])
            .arg(os(&target));
        let (st, mut o) = captured(149, &mut c);
        if st != 0 {
            o.extend_from_slice(b"000\n");
        }
        let code = subst(o);
        if code != b"200" && code != b"301" && code != b"302" {
            log(&[
                "   ⚠️ Warning: Candidate smoke returned HTTP ".as_bytes(),
                &code,
                b"; check service logs",
            ]);
        } else {
            log(&["   ✓ Candidate smoke passed (HTTP ".as_bytes(), &code, b")"]);
        }
    }

    // Step 4: the result.
    log(&["✅ Step 4: Preview Environment Ready!".as_bytes()]);
    if shell_compat::which(b"jq").is_some() {
        let has_db = !database_url.is_empty();
        let v = J::Obj(vec![
            ("app".to_string(), jq::arg(&app)),
            ("pr_number".to_string(), jq::arg(&pr)),
            ("service_name".to_string(), jq::arg(&service_name)),
            ("service_url".to_string(), jq::arg(&service_uri)),
            ("preview_url".to_string(), jq::arg(&preview_url)),
            (
                "database_branch".to_string(),
                if has_db {
                    jq::arg(&branch_name)
                } else {
                    J::Null
                },
            ),
            (
                "database_url".to_string(),
                if has_db {
                    jq::arg(&database_url)
                } else {
                    J::Null
                },
            ),
            ("status".to_string(), J::str("ready")),
        ]);
        out(&cat(&[jq::pretty(&v).as_bytes(), b"\n"]));
    } else {
        let (db_branch_val, db_url_val) = if database_url.is_empty() {
            (b"null".to_vec(), b"null".to_vec())
        } else {
            (
                cat(&[b"\"", &branch_name, b"\""]),
                cat(&[b"\"", &database_url, b"\""]),
            )
        };
        out(&cat(&[
            b"{\n  \"app\": \"",
            &app,
            b"\",\n  \"pr_number\": \"",
            &pr,
            b"\",\n  \"service_name\": \"",
            &service_name,
            b"\",\n  \"service_url\": \"",
            &service_uri,
            b"\",\n  \"preview_url\": \"",
            &preview_url,
            b"\",\n  \"database_branch\": ",
            &db_branch_val,
            b",\n  \"database_url\": ",
            &db_url_val,
            b",\n  \"status\": \"ready\"\n}\n",
        ]));
    }
    Ok(())
}
