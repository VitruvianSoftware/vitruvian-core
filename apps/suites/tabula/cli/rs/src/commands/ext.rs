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
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::utils::extension::{
    atomic_install, default_extension_dir, read_bundle_info, read_installed_channel,
    resolve_beta_artifact, resolve_channel, write_installed_channel, InstallChannel, DEFAULT_REPO,
    DEV_LATEST_TAG, STABLE_CHANNEL_MESSAGE,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToolSpawnError {
    NotFound,
    Other(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolRunResult {
    pub error: Option<ToolSpawnError>,
    pub status: Option<i32>,
    pub stdout: String,
}

pub trait ToolRunner {
    fn spawn_inherit(&mut self, cmd: &str, args: &[String]) -> ToolRunResult;
    fn spawn_capture(&mut self, cmd: &str, args: &[String]) -> ToolRunResult;
}

pub struct StdToolRunner;

impl ToolRunner for StdToolRunner {
    fn spawn_inherit(&mut self, cmd: &str, args: &[String]) -> ToolRunResult {
        match Command::new(cmd)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()
        {
            Ok(status) => ToolRunResult {
                error: None,
                status: Some(status.code().unwrap_or(1)),
                stdout: String::new(),
            },
            Err(e) => ToolRunResult {
                error: Some(if e.kind() == ErrorKind::NotFound {
                    ToolSpawnError::NotFound
                } else {
                    ToolSpawnError::Other(e.to_string())
                }),
                status: None,
                stdout: String::new(),
            },
        }
    }

    fn spawn_capture(&mut self, cmd: &str, args: &[String]) -> ToolRunResult {
        match Command::new(cmd)
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .output()
        {
            Ok(output) => ToolRunResult {
                error: None,
                status: Some(output.status.code().unwrap_or(1)),
                stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            },
            Err(e) => ToolRunResult {
                error: Some(if e.kind() == ErrorKind::NotFound {
                    ToolSpawnError::NotFound
                } else {
                    ToolSpawnError::Other(e.to_string())
                }),
                status: None,
                stdout: String::new(),
            },
        }
    }
}

fn not_found_message(cmd: &str) -> String {
    let hint = if cmd == "gh" {
        "https://cli.github.com + 'gh auth login'"
    } else {
        cmd
    };
    format!("'{cmd}' not found on PATH — install it first ({hint}).")
}

/// Run an external tool, inheriting stdout/stderr; return helpful errors.
pub fn run_tool(cmd: &str, args: &[String]) -> Result<(), String> {
    let mut runner = StdToolRunner;
    run_tool_with(&mut runner, cmd, args)
}

pub fn run_tool_with(
    runner: &mut dyn ToolRunner,
    cmd: &str,
    args: &[String],
) -> Result<(), String> {
    let res = runner.spawn_inherit(cmd, args);
    match res.error {
        Some(ToolSpawnError::NotFound) => return Err(not_found_message(cmd)),
        Some(ToolSpawnError::Other(msg)) => return Err(msg),
        None => {}
    }
    match res.status {
        Some(0) => Ok(()),
        Some(code) => Err(format!("{} {} failed (exit {})", cmd, args.join(" "), code)),
        None => Err(format!("{} {} failed (exit null)", cmd, args.join(" "))),
    }
}

/// Run an external tool capturing stdout (stderr still inherited).
pub fn run_tool_capture(cmd: &str, args: &[String]) -> Result<String, String> {
    let mut runner = StdToolRunner;
    run_tool_capture_with(&mut runner, cmd, args)
}

pub fn run_tool_capture_with(
    runner: &mut dyn ToolRunner,
    cmd: &str,
    args: &[String],
) -> Result<String, String> {
    let res = runner.spawn_capture(cmd, args);
    match res.error {
        Some(ToolSpawnError::NotFound) => return Err(not_found_message(cmd)),
        Some(ToolSpawnError::Other(msg)) => return Err(msg),
        None => {}
    }
    match res.status {
        Some(0) => Ok(res.stdout),
        Some(code) => Err(format!("{} {} failed (exit {})", cmd, args.join(" "), code)),
        None => Err(format!("{} {} failed (exit null)", cmd, args.join(" "))),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtUpdateOptions {
    pub dir: PathBuf,
    pub repo: String,
    pub channel: Option<String>,
}

impl Default for ExtUpdateOptions {
    fn default() -> Self {
        Self {
            dir: default_extension_dir(),
            repo: DEFAULT_REPO.to_string(),
            channel: None,
        }
    }
}

pub fn parse_ext_update_options(args: &[String]) -> Result<ExtUpdateOptions, String> {
    let mut opts = ExtUpdateOptions::default();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--dir" => {
                i += 1;
                let val = args.get(i).ok_or("Missing value for --dir")?;
                opts.dir = PathBuf::from(val);
            }
            "--repo" => {
                i += 1;
                let val = args.get(i).ok_or("Missing value for --repo")?;
                opts.repo = val.clone();
            }
            "--channel" => {
                i += 1;
                let val = args.get(i).ok_or("Missing value for --channel")?;
                opts.channel = Some(val.clone());
            }
            other => {
                if let Some(v) = other.strip_prefix("--dir=") {
                    opts.dir = PathBuf::from(v);
                } else if let Some(v) = other.strip_prefix("--repo=") {
                    opts.repo = v.to_string();
                } else if let Some(v) = other.strip_prefix("--channel=") {
                    opts.channel = Some(v.to_string());
                } else {
                    return Err(format!("Unknown option for ext update: {other}"));
                }
            }
        }
        i += 1;
    }
    Ok(opts)
}

pub fn resolve_abs_path(p: &Path) -> PathBuf {
    if p.is_absolute() {
        p.to_path_buf()
    } else if let Ok(cwd) = std::env::current_dir() {
        cwd.join(p)
    } else {
        p.to_path_buf()
    }
}

pub fn execute_ext_update(
    opts: &ExtUpdateOptions,
    runner: &mut dyn ToolRunner,
) -> Result<Vec<String>, String> {
    let mut logs = Vec::new();
    let flag_normalized = opts.channel.as_ref().map(|c| c.trim().to_lowercase());
    if flag_normalized.as_deref() == Some("stable") {
        logs.push(STABLE_CHANNEL_MESSAGE.to_string());
        return Ok(logs);
    }

    let target = resolve_abs_path(&opts.dir);
    let channel: InstallChannel =
        resolve_channel(flag_normalized.as_deref(), read_installed_channel(&target))?;

    let mut tag = DEV_LATEST_TAG.to_string();
    let mut zip_name = "tabula-extension-chrome.zip".to_string();
    if channel == InstallChannel::Beta {
        let list_args = vec![
            "release".to_string(),
            "list".to_string(),
            "--repo".to_string(),
            opts.repo.clone(),
            "--limit".to_string(),
            "100".to_string(),
            "--json".to_string(),
            "tagName".to_string(),
        ];
        let list_json = run_tool_capture_with(runner, "gh", &list_args)?;
        let artifact = resolve_beta_artifact(&list_json).ok_or_else(|| {
            format!(
                "No tabula-extension-v* release found in {} — the beta channel needs at least one release cut.",
                opts.repo
            )
        })?;
        tag = artifact.tag;
        zip_name = artifact.zip_name;
    }

    let download_dir = std::env::temp_dir().join(format!(
        "tabula-ext-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    let _ = fs::create_dir_all(&download_dir);
    let staging = PathBuf::from(format!(
        "{}.staging-{}",
        target.display(),
        std::process::id()
    ));

    let result = (|| -> Result<(), String> {
        logs.push(format!(
            "Fetching {} ({}) from {}…",
            tag,
            channel.as_str(),
            opts.repo
        ));
        let dl_args = vec![
            "release".to_string(),
            "download".to_string(),
            tag.clone(),
            "--repo".to_string(),
            opts.repo.clone(),
            "--pattern".to_string(),
            zip_name.clone(),
            "--dir".to_string(),
            download_dir.display().to_string(),
            "--clobber".to_string(),
        ];
        if let Err(download_error) = run_tool_with(runner, "gh", &dl_args) {
            if channel == InstallChannel::Beta {
                return Err(format!(
                    "{download_error} — the release may still be publishing its assets; retry in a minute."
                ));
            }
            return Err(download_error);
        }

        let _ = fs::remove_dir_all(&staging);
        fs::create_dir_all(&staging).map_err(|e| e.to_string())?;

        let unzip_args = vec![
            "-o".to_string(),
            "-q".to_string(),
            download_dir.join(&zip_name).display().to_string(),
            "-d".to_string(),
            staging.display().to_string(),
        ];
        run_tool_with(runner, "unzip", &unzip_args)?;
        atomic_install(&staging, &target)?;
        write_installed_channel(&target, channel)?;

        let info = read_bundle_info(&target);
        let mut identity_parts = Vec::new();
        if let Some(ref b) = info {
            if let Some(ref v) = b.version {
                if !v.is_empty() {
                    identity_parts.push(format!("v{v}"));
                }
            }
            if let Some(ref c) = b.commit {
                if !c.is_empty() {
                    let short: String = c.chars().take(7).collect();
                    identity_parts.push(format!("({short})"));
                }
            }
        }
        let identity = if identity_parts.is_empty() {
            "build".to_string()
        } else {
            identity_parts.join(" ")
        };

        logs.push(format!(
            "✓ Installed {} {} → {}",
            channel.as_str(),
            identity,
            target.display()
        ));
        logs.push(
            "  Reload the extension to load it (banner button, or chrome://extensions → ↻)."
                .to_string(),
        );
        logs.push(format!(
            "  First time? chrome://extensions → Developer mode → \"Load unpacked\" → {}",
            target.display()
        ));
        if channel == InstallChannel::Beta {
            if let Some(ref b) = info {
                if b.commit.as_deref() == Some("dev") {
                    logs.push(
                        "  Note: this release predates identity stamping — the in-extension update banner stays off. Re-run `tabcli ext update` after the next release cut."
                            .to_string(),
                    );
                }
            }
        }
        Ok(())
    })();

    let _ = fs::remove_dir_all(&download_dir);
    let _ = fs::remove_dir_all(&staging);

    result?;
    Ok(logs)
}

pub fn run_ext_command(args: &[String]) -> Result<String, String> {
    if args.is_empty() || args[0] == "--help" || args[0] == "-h" {
        return Ok(
            "Usage: tabcli ext <command>\n\nManage the local load-unpacked dev extension install\n\nCommands:\n  path    Print the load-unpacked extension directory\n  update  Download the channel's latest build into the load-unpacked directory"
                .to_string(),
        );
    }

    match args[0].as_str() {
        "path" => {
            let mut dir = default_extension_dir();
            let mut i = 1;
            while i < args.len() {
                if args[i] == "--dir" {
                    i += 1;
                    let val = args.get(i).ok_or("Missing value for --dir")?;
                    dir = PathBuf::from(val);
                } else if let Some(v) = args[i].strip_prefix("--dir=") {
                    dir = PathBuf::from(v);
                } else {
                    return Err(format!("Unknown option for ext path: {}", args[i]));
                }
                i += 1;
            }
            Ok(resolve_abs_path(&dir).display().to_string())
        }
        "update" => {
            let opts = parse_ext_update_options(&args[1..])?;
            let mut runner = StdToolRunner;
            let logs = execute_ext_update(&opts, &mut runner)?;
            Ok(logs.join("\n"))
        }
        other => Err(format!("Unknown ext subcommand: {other}")),
    }
}
