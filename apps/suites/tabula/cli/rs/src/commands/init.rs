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

use std::fs;
use std::path::Path;

use crate::utils::config::{config_file_path, Config};

pub const VALID_ENVIRONMENTS: &[&str] = &["development", "staging", "production"];
pub const VALID_REGIONS: &[&str] = &["us-central1", "us-east1", "europe-west1", "asia-east1"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InitAnswers {
    pub project_id: String,
    pub environment: String,
    pub region: String,
    pub database_url: Option<String>,
    pub created_at: String,
}

impl Default for InitAnswers {
    fn default() -> Self {
        Self {
            project_id: "tabula-dev".to_string(),
            environment: "development".to_string(),
            region: "us-central1".to_string(),
            database_url: None,
            created_at: "2026-01-01T00:00:00.000Z".to_string(),
        }
    }
}

pub fn init_config_at(
    base_dir: &Path,
    force: bool,
    answers: &InitAnswers,
    neon_api_key_present: bool,
) -> Result<String, String> {
    if answers.project_id.trim().is_empty() {
        return Err("Project ID is required".to_string());
    }
    let config_file = config_file_path(base_dir);
    if config_file.exists() && !force {
        return Ok("⚠ Configuration already exists. Use --force to overwrite.".to_string());
    }

    let config_dir = base_dir.join(".tabula");
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)
            .map_err(|e| format!("Failed to create configuration: {e}"))?;
    }

    let config = Config {
        version: Some("0.1.0".to_string()),
        project_id: answers.project_id.clone(),
        environment: Some(answers.environment.clone()),
        region: answers.region.clone(),
        database_url: answers.database_url.clone().filter(|s| !s.is_empty()),
        created_at: Some(answers.created_at.clone()),
        ..Config::default()
    };

    fs::write(&config_file, config.to_json_pretty())
        .map_err(|e| format!("Failed to create configuration: {e}"))?;

    let mut lines = vec![
        "Configuration created successfully".to_string(),
        "\n✓ TabCLI initialized".to_string(),
        format!("Config saved to: {}", config_file.display()),
        "\nNext steps:".to_string(),
    ];
    if !neon_api_key_present {
        lines.push("  1. Authenticate with Neon: tabcli auth neon".to_string());
        lines.push("  2. Run: tabcli config list".to_string());
    } else {
        lines.push("  1. Run: tabcli config list".to_string());
    }
    lines.push("  3. Set secrets: tabcli secrets set <KEY>".to_string());
    lines.push("  4. Initialize database: tabcli db init".to_string());

    Ok(lines.join("\n"))
}

pub fn run_init_command(args: &[String]) -> Result<String, String> {
    if args.iter().any(|a| a == "--help" || a == "-h") {
        return Ok(
            "Usage: tabcli init [options]\n\nInitialize Tabula configuration\n\nOptions:\n  -f, --force  Overwrite existing configuration"
                .to_string(),
        );
    }
    let force = args.iter().any(|a| a == "-f" || a == "--force");
    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    let neon_present = std::env::var("NEON_API_KEY")
        .map(|v| !v.is_empty())
        .unwrap_or(false);
    init_config_at(&cwd, force, &InitAnswers::default(), neon_present)
}
