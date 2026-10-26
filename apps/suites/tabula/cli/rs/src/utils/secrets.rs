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

use std::collections::BTreeMap;
use std::process::{Command, Stdio};

use crate::utils::config::Config;

pub trait SecretFetcher {
    fn fetch_secret(&self, project_id: &str, secret_name: &str) -> Option<String>;
}

pub struct GcloudSecretFetcher;

impl SecretFetcher for GcloudSecretFetcher {
    fn fetch_secret(&self, project_id: &str, secret_name: &str) -> Option<String> {
        let output = Command::new("gcloud")
            .args([
                "secrets",
                "versions",
                "access",
                "latest",
                &format!("--secret={secret_name}"),
                &format!("--project={project_id}"),
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .ok()?;
        if !output.status.success() {
            return None;
        }
        let val = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if val.is_empty() {
            None
        } else {
            Some(val)
        }
    }
}

pub fn get_project_id<'a>(config: &'a Config, env: &str) -> &'a str {
    if let Some(env_cfg) = config.environments.get(env) {
        if !env_cfg.project_id.is_empty() {
            return env_cfg.project_id.as_str();
        }
    }
    config.project_id.as_str()
}

pub fn load_workos_api_key(
    config: &Config,
    env: &str,
    env_vars: &mut BTreeMap<String, String>,
    fetcher: &dyn SecretFetcher,
) -> Option<String> {
    if let Some(existing) = env_vars.get("WORKOS_API_KEY") {
        if !existing.is_empty() {
            return Some(existing.clone());
        }
    }
    let project_id = get_project_id(config, env);
    if let Some(key) = fetcher.fetch_secret(project_id, "WORKOS_API_KEY") {
        env_vars.insert("WORKOS_API_KEY".to_string(), key.clone());
        return Some(key);
    }
    eprintln!("\n⚠️  WORKOS_API_KEY not found in environment or Secret Manager.");
    eprintln!("WorkOS operations will likely fail.");
    None
}

pub fn load_workos_client_id(
    config: &Config,
    env: &str,
    env_vars: &mut BTreeMap<String, String>,
    fetcher: &dyn SecretFetcher,
) -> Option<String> {
    if let Some(existing) = env_vars.get("WORKOS_CLIENT_ID") {
        if !existing.is_empty() {
            return Some(existing.clone());
        }
    }
    let project_id = get_project_id(config, env);
    if let Some(client_id) = fetcher.fetch_secret(project_id, "WORKOS_CLIENT_ID") {
        env_vars.insert("WORKOS_CLIENT_ID".to_string(), client_id.clone());
        return Some(client_id);
    }
    eprintln!("\n⚠️  WORKOS_CLIENT_ID not found in environment or Secret Manager.");
    eprintln!("WorkOS integration might fail.");
    None
}

pub fn load_neon_api_key(
    config: &Config,
    env: &str,
    env_vars: &mut BTreeMap<String, String>,
    fetcher: &dyn SecretFetcher,
) -> Option<String> {
    if let Some(existing) = env_vars.get("NEON_API_KEY") {
        if !existing.is_empty() {
            return Some(existing.clone());
        }
    }
    let project_id = get_project_id(config, env);
    if let Some(api_key) = fetcher.fetch_secret(project_id, "NEON_API_KEY") {
        env_vars.insert("NEON_API_KEY".to_string(), api_key.clone());
        return Some(api_key);
    }
    if let Some(ref cfg_key) = config.neon_api_key {
        if !cfg_key.is_empty() {
            env_vars.insert("NEON_API_KEY".to_string(), cfg_key.clone());
            return Some(cfg_key.clone());
        }
    }
    eprintln!("\n⚠️  NEON_API_KEY not found in environment, config, or Secret Manager.");
    eprintln!("Terraform operations involving Neon will likely fail.");
    eprintln!("Run \"tabcli auth neon\" or export NEON_API_KEY manually.\n");
    None
}

pub fn load_upstash_credentials(
    config: &Config,
    env: &str,
    env_vars: &mut BTreeMap<String, String>,
    fetcher: &dyn SecretFetcher,
) -> bool {
    let has_email = env_vars
        .get("UPSTASH_EMAIL")
        .map(|s| !s.is_empty())
        .unwrap_or(false);
    let has_key = env_vars
        .get("UPSTASH_API_KEY")
        .map(|s| !s.is_empty())
        .unwrap_or(false);
    if has_email && has_key {
        return true;
    }

    let project_id = get_project_id(config, env);
    if !has_email {
        if let Some(email) = fetcher.fetch_secret(project_id, "UPSTASH_EMAIL") {
            env_vars.insert("UPSTASH_EMAIL".to_string(), email);
        }
    }
    if !has_key {
        if let Some(key) = fetcher.fetch_secret(project_id, "UPSTASH_API_KEY") {
            env_vars.insert("UPSTASH_API_KEY".to_string(), key);
        }
    }

    let final_email = env_vars
        .get("UPSTASH_EMAIL")
        .map(|s| !s.is_empty())
        .unwrap_or(false);
    let final_key = env_vars
        .get("UPSTASH_API_KEY")
        .map(|s| !s.is_empty())
        .unwrap_or(false);
    if !final_email || !final_key {
        eprintln!("\n⚠️  Upstash credentials not found in environment or Secret Manager.");
        eprintln!("Terraform operations involving Upstash will likely fail.");
        eprintln!("Use \"tabcli infra secrets set UPSTASH_EMAIL/UPSTASH_API_KEY\" to set them.\n");
        return false;
    }
    true
}
