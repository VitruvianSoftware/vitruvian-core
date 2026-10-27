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

use std::path::Path;
use std::process::{Command, Stdio};

use crate::utils::config::{get_config_from, save_config_to};

/// Build the Google Secret Manager upsert command used by `tabcli auth neon`.
pub fn build_gsm_store_neon_key_command(api_key: &str, project_id: &str) -> String {
    format!(
        "printf '%s' \"{api_key}\" | gcloud secrets create NEON_API_KEY --data-file=- --project={project_id} 2>/dev/null || printf '%s' \"{api_key}\" | gcloud secrets versions add NEON_API_KEY --data-file=- --project={project_id}"
    )
}

/// Apply post-verification Neon API Key persistence rules:
/// - If stored in GSM, remove `neonApiKey` from local `.tabula/config.json` if present.
/// - If not stored in GSM, save `neonApiKey` into local `.tabula/config.json`.
pub fn persist_verified_neon_api_key(
    base_dir: &Path,
    api_key: &str,
    stored_in_gsm: bool,
) -> Result<Option<String>, String> {
    let mut config = get_config_from(base_dir)?;
    if !stored_in_gsm {
        config.neon_api_key = Some(api_key.to_string());
        save_config_to(base_dir, &config)?;
        Ok(Some(
            "⚠ Stored API Key in local configuration (GSM unavailable)".to_string(),
        ))
    } else if config.neon_api_key.is_some() {
        config.neon_api_key = None;
        save_config_to(base_dir, &config)?;
        Ok(Some(
            "✓ Removed API Key from local configuration".to_string(),
        ))
    } else {
        Ok(None)
    }
}

pub fn run_auth_command(args: &[String]) -> Result<String, String> {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        return Ok(
            "Usage: tabcli auth <command>\n\nManage authentication for external services\n\nCommands:\n  neon    Authenticate with Neon (Serverless Postgres)\n  gcloud  Authenticate with Google Cloud Platform"
                .to_string(),
        );
    }

    match args[0].as_str() {
        "neon" => {
            let api_key = std::env::var("NEON_API_KEY").unwrap_or_default();
            if api_key.is_empty() {
                return Err(
                    "Authentication failed. Please check your API Key (set NEON_API_KEY)."
                        .to_string(),
                );
            }
            let status = Command::new("npx")
                .args(["neonctl", "me"])
                .env("NEON_API_KEY", &api_key)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map_err(|_| "Authentication failed. Please check your API Key.".to_string())?;
            if !status.success() {
                return Err("Authentication failed. Please check your API Key.".to_string());
            }
            let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
            if let Ok(mut cfg) = get_config_from(&cwd) {
                if cfg.neon_api_key.is_none() {
                    cfg.neon_api_key = Some(api_key);
                    let _ = save_config_to(&cwd, &cfg);
                }
            }
            Ok("Already authenticated with Neon!".to_string())
        }
        "gcloud" => {
            let check = Command::new("gcloud")
                .arg("--version")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            match check {
                Ok(s) if s.success() => {}
                Ok(_) => return Err("gcloud CLI check failed".to_string()),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                    return Err(
                        "gcloud CLI is not installed or not in PATH.\nPlease install Google Cloud SDK first."
                            .to_string(),
                    );
                }
                Err(e) => {
                    return Err(format!("An error occurred while checking gcloud: {e}"));
                }
            }

            let step1 = Command::new("gcloud")
                .args(["auth", "login"])
                .status()
                .map_err(|_| "❌ Authentication failed".to_string())?;
            if !step1.success() {
                return Err("❌ Authentication failed".to_string());
            }
            let step2 = Command::new("gcloud")
                .args(["auth", "application-default", "login"])
                .status()
                .map_err(|_| "❌ Authentication failed".to_string())?;
            if !step2.success() {
                return Err("❌ Authentication failed".to_string());
            }
            Ok("✅ Successfully authenticated with Google Cloud!".to_string())
        }
        other => Err(format!("Unknown auth subcommand: {other}")),
    }
}
