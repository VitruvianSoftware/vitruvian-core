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
use std::process::Command;

use crate::utils::config::get_config;
use crate::utils::secrets::{load_workos_api_key, GcloudSecretFetcher};

pub fn browser_open_command_for_os(os: &str) -> &'static str {
    match os {
        "macos" | "darwin" => "open",
        "windows" | "win32" => "start",
        _ => "xdg-open",
    }
}

/// Parse `gcloud run services list --format="csv[no-heading](metadata.name,status.url)"` output
/// and extract environment -> URL mappings for `tabula-api-<env>` services.
pub fn parse_cloud_run_services_csv(csv_output: &str) -> BTreeMap<String, String> {
    let mut urls = BTreeMap::new();
    for line in csv_output.trim().lines() {
        if !line.contains("tabula-api") {
            continue;
        }
        let mut parts = line.splitn(2, ',');
        let name = parts.next().unwrap_or("").trim();
        let url = parts.next().unwrap_or("").trim();
        if name.is_empty() || url.is_empty() {
            continue;
        }
        if let Some(idx) = name.find("tabula-api-") {
            let suffix = &name[idx + "tabula-api-".len()..];
            let env_part: String = suffix
                .chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect();
            if !env_part.is_empty() {
                urls.insert(env_part, url.to_string());
            }
        }
    }
    urls
}

/// Generate WorkOS callback URLs from Cloud Run service URLs plus localhost fallback.
pub fn generate_callback_urls(cloud_run_urls: &BTreeMap<String, String>) -> Vec<String> {
    let mut callbacks: Vec<String> = cloud_run_urls
        .values()
        .map(|url| format!("{url}/api/v1/auth/callback"))
        .collect();
    callbacks.push("http://localhost:8080/api/v1/auth/callback".to_string());
    callbacks
}

/// Format callback URLs as pretty JSON matching `JSON.stringify({ redirectUris: callbackUrls }, null, 2)`.
pub fn format_redirect_uris_json(callback_urls: &[String]) -> String {
    let items: Vec<String> = callback_urls
        .iter()
        .map(|u| format!("    \"{}\"", u))
        .collect();
    format!("{{\n  \"redirectUris\": [\n{}\n  ]\n}}", items.join(",\n"))
}

/// Filter out `--env <val>` and `-e <val>` from passthrough arguments sent to `workos`.
pub fn filter_workos_passthrough_args(workos_args: &[String]) -> Vec<String> {
    let mut filtered = Vec::new();
    for (idx, arg) in workos_args.iter().enumerate() {
        if arg == "--env" || arg == "-e" {
            continue;
        }
        if idx > 0 && (workos_args[idx - 1] == "--env" || workos_args[idx - 1] == "-e") {
            continue;
        }
        filtered.push(arg.clone());
    }
    filtered
}

/// Build WorkOS headless environment variables given `WORKOS_API_KEY`.
pub fn build_workos_headless_env(api_key: &str) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    map.insert("WORKOS_API_KEY".to_string(), api_key.to_string());
    map.insert(
        "WORKOS_ACTIVE_ENVIRONMENT".to_string(),
        "headless".to_string(),
    );
    map.insert(
        "WORKOS_ENVIRONMENTS_HEADLESS_API_KEY".to_string(),
        api_key.to_string(),
    );
    map.insert(
        "WORKOS_ENVIRONMENTS_HEADLESS_NAME".to_string(),
        "dev".to_string(),
    );
    map.insert(
        "WORKOS_ENVIRONMENTS_HEADLESS_ENDPOINT".to_string(),
        "https://api.workos.com".to_string(),
    );
    map
}

pub fn run_workos_command(args: &[String]) -> Result<String, String> {
    if args.first().map(String::as_str) == Some("--help")
        || args.first().map(String::as_str) == Some("-h")
    {
        return Ok(
            "Usage: tabcli workos [options] [command]\n\nWorkOS CLI wrapper with automatic authentication\n\nOptions:\n  -e, --env <environment>  Environment to use (dev/staging/prod) (default: \"dev\")\n\nCommands:\n  sync-redirects           Display WorkOS redirect URIs that need to be configured"
                .to_string(),
        );
    }

    if args.first().map(String::as_str) == Some("sync-redirects") {
        let sub_args = &args[1..];
        let as_json = sub_args.iter().any(|a| a == "--json");
        let open_browser = sub_args.iter().any(|a| a == "--open");

        let config = get_config().map_err(|_| {
            "Configuration not found. Please run \"tabcli init\" first.".to_string()
        })?;

        let output = Command::new("gcloud")
            .args([
                "run",
                "services",
                "list",
                "--project",
                &config.project_id,
                "--format=csv[no-heading](metadata.name,status.url)",
            ])
            .output()
            .map_err(|_| {
                "Failed to fetch Cloud Run services. Make sure gcloud is configured.".to_string()
            })?;
        if !output.status.success() {
            return Err(
                "Failed to fetch Cloud Run services. Make sure gcloud is configured.".to_string(),
            );
        }

        let csv = String::from_utf8_lossy(&output.stdout);
        let cloud_run_urls = parse_cloud_run_services_csv(&csv);
        if cloud_run_urls.is_empty() {
            return Ok(
                "No Cloud Run API services found.\nMake sure you have deployed your API services first."
                    .to_string(),
            );
        }

        let callbacks = generate_callback_urls(&cloud_run_urls);
        if as_json {
            return Ok(format_redirect_uris_json(&callbacks));
        }

        let mut lines = vec![
            "🔍 Fetching Cloud Run service URLs...\n".to_string(),
            "✓ Found Cloud Run services:\n".to_string(),
        ];
        for (env, url) in &cloud_run_urls {
            lines.push(format!("  {env:<10} {url}"));
        }
        lines.push(String::new());
        lines.push("📋 Redirect URIs to configure in WorkOS:\n".to_string());
        lines.push("Copy and paste these into your WorkOS Dashboard > Redirects:\n".to_string());
        for u in &callbacks {
            lines.push(format!("  {u}"));
        }
        lines.push(String::new());
        lines.push("━".repeat(60));
        lines.push(String::new());
        lines.push(
            "⚠️  WorkOS does not support programmatic redirect URI configuration.".to_string(),
        );
        lines.push("   You must add these manually in the WorkOS Dashboard.".to_string());
        lines.push(String::new());
        lines.push("   Dashboard: https://dashboard.workos.com/redirects".to_string());
        lines.push(String::new());

        if open_browser {
            lines.push("🌐 Opening WorkOS Dashboard...".to_string());
            let open_cmd = browser_open_command_for_os(std::env::consts::OS);
            let _ = Command::new(open_cmd)
                .arg("https://dashboard.workos.com/redirects")
                .spawn();
        } else {
            lines.push("   Use --open to open the dashboard in your browser.".to_string());
        }

        return Ok(lines.join("\n"));
    }

    // Passthrough to WorkOS CLI
    let config = get_config()
        .map_err(|_| "Configuration not found. Please run \"tabcli init\" first.".to_string())?;
    let mut env_name = "dev".to_string();
    for (idx, a) in args.iter().enumerate() {
        if (a == "--env" || a == "-e") && idx + 1 < args.len() {
            env_name = args[idx + 1].clone();
        }
    }

    let mut env_vars: BTreeMap<String, String> = std::env::vars().collect();
    let fetcher = GcloudSecretFetcher;
    let api_key = load_workos_api_key(&config, &env_name, &mut env_vars, &fetcher)
        .ok_or_else(|| "Failed to load WORKOS_API_KEY. Cannot proceed.".to_string())?;

    for (k, v) in build_workos_headless_env(&api_key) {
        env_vars.insert(k, v);
    }

    let filtered_args = filter_workos_passthrough_args(args);
    println!("Running: workos {}\n", filtered_args.join(" "));

    let status = Command::new("workos")
        .args(&filtered_args)
        .envs(&env_vars)
        .status()
        .map_err(|e| format!("Failed to spawn workos: {e}"))?;
    if !status.success() {
        return Err(format!(
            "workos exited with status {}",
            status.code().unwrap_or(1)
        ));
    }
    Ok(String::new())
}
