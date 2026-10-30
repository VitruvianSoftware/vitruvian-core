// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Rust port of `apps/web/oauth-user-inspector/scripts/deploy.sh`.

use std::process::Command;

pub const SERVICE_NAME: &str = "oauth-user-inspector";
pub const DEFAULT_REGION: &str = "us-central1";
pub const REQUIRED_SERVICES: &[&str] = &[
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "containerregistry.googleapis.com",
    "secretmanager.googleapis.com",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeployConfig {
    pub project_id: String,
    pub region: String,
    pub service_name: String,
}

pub fn resolve_deploy_config<F>(
    args: &[String],
    get_default_project: F,
) -> Result<DeployConfig, String>
where
    F: FnOnce() -> Option<String>,
{
    let project_id = match args.get(1).map(|s| s.trim()).filter(|s| !s.is_empty()) {
        Some(p) => p.to_string(),
        None => get_default_project()
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .ok_or_else(|| "Unable to determine GCP project ID".to_string())?,
    };
    let region = args
        .get(2)
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .unwrap_or(DEFAULT_REGION)
        .to_string();

    Ok(DeployConfig {
        project_id,
        region,
        service_name: SERVICE_NAME.to_string(),
    })
}

pub fn compute_service_account(project_number: &str) -> String {
    format!(
        "{}-compute@developer.gserviceaccount.com",
        project_number.trim()
    )
}

fn capture_gcloud(args: &[&str]) -> Option<String> {
    let out = Command::new("gcloud").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn run_gcloud(args: &[&str]) -> bool {
    Command::new("gcloud")
        .args(args)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn run(args: &[String]) -> i32 {
    let cfg =
        match resolve_deploy_config(args, || capture_gcloud(&["config", "get-value", "project"])) {
            Ok(c) => c,
            Err(e) => {
                eprintln!("{e}");
                return 1;
            }
        };

    println!("🚀 Deploying OAuth User Inspector to Google Cloud Run");
    println!("Project: {}", cfg.project_id);
    println!("Region: {}", cfg.region);
    println!("Service: {}", cfg.service_name);

    println!("📋 Enabling required Google Cloud APIs...");
    for svc in REQUIRED_SERVICES {
        if !run_gcloud(&["services", "enable", svc]) {
            return 1;
        }
    }

    println!("🔐 Setting up Secret Manager permissions...");
    let Some(project_number) = capture_gcloud(&[
        "projects",
        "describe",
        &cfg.project_id,
        "--format=value(projectNumber)",
    ]) else {
        return 1;
    };
    let cloud_run_sa = compute_service_account(&project_number);
    let member = format!("serviceAccount:{cloud_run_sa}");
    if !run_gcloud(&[
        "projects",
        "add-iam-policy-binding",
        &cfg.project_id,
        &format!("--member={member}"),
        "--role=roles/secretmanager.secretAccessor",
    ]) {
        println!("⚠️  Permission may already exist");
    }

    println!("🔨 Building and deploying with Cloud Build...");
    if !run_gcloud(&["builds", "submit", "--config", "cloudbuild.yaml"]) {
        return 1;
    }

    println!("✅ Deployment complete!");
    println!("🌐 Your service will be available at:");
    if !run_gcloud(&[
        "run",
        "services",
        "describe",
        &cfg.service_name,
        &format!("--region={}", cfg.region),
        "--format=value(status.url)",
    ]) {
        return 1;
    }

    0
}
