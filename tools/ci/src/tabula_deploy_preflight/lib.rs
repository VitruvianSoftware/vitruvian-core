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

//! tabula-deploy-preflight.sh — decide whether an env's deploy can be SKIPPED
//! because the live service already serves the exact desired state.

use shell_compat::{capture, cat, env, env_or, grep_q_line_start, indent, out, subst};
use std::process::Command;

fn gh_output(line: &[u8]) {
    if let Some(p) = env("GITHUB_OUTPUT") {
        if !p.is_empty() {
            let _ = std::fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(shell_compat::path(&p))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(line)?;
                    f.write_all(b"\n")
                });
        }
    }
}

fn deploy(deploy_env: &[u8], reason: &[u8]) -> i32 {
    out(&cat(&[
        b"preflight[",
        deploy_env,
        b"]: unchanged=false \xe2\x80\x94 ",
        reason,
        b"\n",
    ]));
    gh_output(b"unchanged=false");
    0
}

fn skip(deploy_env: &[u8], desired: &[u8]) -> i32 {
    out(&cat(&[
        b"preflight[",
        deploy_env,
        b"]: unchanged=true \xe2\x80\x94 live already serves the desired revision (",
        desired,
        b")\n",
    ]));
    gh_output(b"unchanged=true");
    0
}

fn require(name: &str) -> Result<Vec<u8>, i32> {
    match env(name) {
        Some(v) if !v.is_empty() => Ok(v),
        _ => {
            shell_compat::err(&cat(&[name.as_bytes(), b" is required but not set\n"]));
            Err(1)
        }
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let deploy_env = match require("DEPLOY_ENV") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let gcp_project_id = match require("GCP_PROJECT_ID") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let service_name = match require("SERVICE_NAME") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let image_digest = match require("IMAGE_DIGEST") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let pulumi_dir = match require("PULUMI_DIR") {
        Ok(v) => v,
        Err(_) => return 1,
    };
    let config_file = match require("CONFIG_FILE") {
        Ok(v) => v,
        Err(_) => return 1,
    };

    let gcp_region = env_or("GCP_REGION", b"us-central1");
    let gcloud_bin = env_or("GCLOUD_BIN", b"gcloud");
    let revname = env_or("REVNAME", b"go run ./cmd/revname");

    if std::env::set_current_dir(shell_compat::path(&pulumi_dir)).is_err() {
        return deploy(
            &deploy_env,
            &cat(&[b"PULUMI_DIR ", &pulumi_dir, b" not found"]),
        );
    }

    // --- desired: what a deploy WOULD produce ---
    let revname_parts = shell_compat::ifs_split(&revname);
    if revname_parts.is_empty() {
        return deploy(&deploy_env, b"REVNAME is empty");
    }
    let mut cmd = Command::new(shell_compat::os(&revname_parts[0]));
    for p in &revname_parts[1..] {
        cmd.arg(shell_compat::os(p));
    }
    cmd.arg("--config")
        .arg(shell_compat::os(&config_file))
        .arg("--digest")
        .arg(shell_compat::os(&image_digest))
        .env("GOWORK", "off");
    let r = capture(77, &mut cmd);
    let desired = subst(r.stdout);
    if r.status != 0 || desired.is_empty() {
        if !r.stderr.is_empty() {
            shell_compat::err(&cat(&[
                b"preflight[",
                &deploy_env,
                b"]: could not compute the desired revision name:\n",
            ]));
            shell_compat::err(&indent(&r.stderr));
        }
        return deploy(
            &deploy_env,
            &cat(&[
                b"desired-name computation failed (rc=",
                r.status.to_string().as_bytes(),
                b")",
            ]),
        );
    }

    // --- live: what is serving now ---
    let gcloud_parts = shell_compat::ifs_split(&gcloud_bin);
    if gcloud_parts.is_empty() {
        return deploy(&deploy_env, b"GCLOUD_BIN is empty");
    }
    let svc = cat(&[&service_name, b"-", &deploy_env]);
    let mut gcmd = Command::new(shell_compat::os(&gcloud_parts[0]));
    for p in &gcloud_parts[1..] {
        gcmd.arg(shell_compat::os(p));
    }
    gcmd.arg("run")
        .arg("services")
        .arg("describe")
        .arg(shell_compat::os(&svc))
        .arg("--project")
        .arg(shell_compat::os(&gcp_project_id))
        .arg("--region")
        .arg(shell_compat::os(&gcp_region))
        .arg("--format=value(status.traffic[0].revisionName)");
    let gr = capture(91, &mut gcmd);
    let live = subst(gr.stdout);

    if gr.status != 0 || grep_q_line_start(&gr.stderr, b"ERROR:") {
        if !gr.stderr.is_empty() {
            shell_compat::err(&cat(&[
                b"preflight[",
                &deploy_env,
                b"]: could not read the live revision:\n",
            ]));
            shell_compat::err(&indent(&gr.stderr));
        }
        return deploy(
            &deploy_env,
            &cat(&[
                b"live-revision read failed (rc=",
                gr.status.to_string().as_bytes(),
                b")",
            ]),
        );
    }

    if live.is_empty() {
        return deploy(
            &deploy_env,
            &cat(&[b"no live revision (first-ever deploy for ", &svc, b")"]),
        );
    }

    out(&cat(&[
        b"preflight[",
        &deploy_env,
        b"]: desired=",
        &desired,
        b" live=",
        &live,
        b"\n",
    ]));

    if desired == live {
        return skip(&deploy_env, &desired);
    }
    deploy(
        &deploy_env,
        &cat(&[b"desired (", &desired, b") != live (", &live, b")"]),
    )
}
