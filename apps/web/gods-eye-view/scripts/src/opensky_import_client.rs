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

use serde_json::Value;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenSkyCredentials {
    pub client_id: String,
    pub client_secret: String,
}

pub fn parse_credentials(json_str: &str) -> Result<OpenSkyCredentials, String> {
    let raw: Value =
        serde_json::from_str(json_str).map_err(|e| format!("Invalid JSON: {}", e))?;

    let client_id = raw
        .get("clientId")
        .or_else(|| raw.get("client_id"))
        .and_then(Value::as_str)
        .map(|s| s.trim().to_string())
        .unwrap_or_default();

    let client_secret = raw
        .get("clientSecret")
        .or_else(|| raw.get("client_secret"))
        .and_then(Value::as_str)
        .map(|s| s.trim().to_string())
        .unwrap_or_default();

    if client_id.is_empty() || client_secret.is_empty() {
        return Err("credentials file is missing client id or client secret".into());
    }

    Ok(OpenSkyCredentials {
        client_id,
        client_secret,
    })
}

/// `path` as the caller meant it: `bazel run` starts the binary in its
/// runfiles, so a relative path is taken from `working_dir`
/// (BUILD_WORKING_DIRECTORY, the folder `bazel run` was typed in) when set.
pub fn from_working_dir(path: &str, working_dir: Option<&str>) -> PathBuf {
    let path = PathBuf::from(path);
    match working_dir {
        Some(dir) if !dir.is_empty() && path.is_relative() => PathBuf::from(dir).join(path),
        _ => path,
    }
}

pub fn resolve_credentials_path(explicit: Option<&str>) -> Result<PathBuf, String> {
    let working_dir = std::env::var("BUILD_WORKING_DIRECTORY").ok();
    if let Some(path) = explicit {
        if !path.is_empty() {
            return Ok(from_working_dir(path, working_dir.as_deref()));
        }
    }
    if let Ok(env_path) = std::env::var("OPENSKY_CREDENTIALS_FILE") {
        if !env_path.is_empty() {
            return Ok(from_working_dir(&env_path, working_dir.as_deref()));
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        let default =
            PathBuf::from(home).join(".config/gods-eye-view/opensky-credentials.json");
        if default.exists() {
            return Ok(default);
        }
    }
    Err(
        "usage: opensky-import-client /path/to/credentials.json\n\
         or set OPENSKY_CREDENTIALS_FILE"
            .into(),
    )
}

pub fn run_with_executor<F>(args: &[String], exec: F) -> Result<(), String>
where
    F: Fn(&str, &[&str]) -> Result<String, String>,
{
    let explicit = args.first().map(String::as_str);
    let cred_path = resolve_credentials_path(explicit)?;

    if !cred_path.exists() {
        return Err(format!(
            "credentials file not found: {}",
            cred_path.display()
        ));
    }

    let json_str = std::fs::read_to_string(&cred_path)
        .map_err(|e| format!("Cannot read {}: {}", cred_path.display(), e))?;
    let creds = parse_credentials(&json_str)?;

    exec(
        "security",
        &[
            "add-generic-password",
            "-U",
            "-s",
            "opensky-network",
            "-a",
            "client_id",
            "-w",
            &creds.client_id,
        ],
    )?;
    exec(
        "security",
        &[
            "add-generic-password",
            "-U",
            "-s",
            "opensky-network",
            "-a",
            "client_secret",
            "-w",
            &creds.client_secret,
        ],
    )?;

    println!("OpenSky OAuth client credentials stored in Keychain:");
    println!("  service=opensky-network account=client_id");
    println!("  service=opensky-network account=client_secret");
    Ok(())
}

fn default_executor(cmd: &str, args: &[&str]) -> Result<String, String> {
    let output = std::process::Command::new(cmd)
        .args(args)
        .output()
        .map_err(|e| format!("Failed to run {}: {}", cmd, e))?;
    if !output.status.success() {
        return Err(format!(
            "{} failed: {}",
            cmd,
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

pub fn run(args: &[String]) -> Result<(), String> {
    run_with_executor(args, default_executor)
}
