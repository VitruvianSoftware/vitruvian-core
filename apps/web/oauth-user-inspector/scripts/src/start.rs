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

//! Rust port of `apps/web/oauth-user-inspector/start.sh`.

use std::env;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BuildCheckError {
    MissingDist,
    MissingDistServer,
    MissingServerJs,
}

impl BuildCheckError {
    pub fn message(&self) -> &'static str {
        match self {
            BuildCheckError::MissingDist => {
                "❌ Error: dist directory (frontend) not found. Frontend build may have failed."
            }
            BuildCheckError::MissingDistServer => {
                "❌ Error: dist-server directory not found. Server build may have failed."
            }
            BuildCheckError::MissingServerJs => {
                "❌ Error: dist-server/server.js not found. Server build may have failed."
            }
        }
    }
}

pub fn resolve_env_or_default<'a>(val: Option<&'a str>, default: &'a str) -> &'a str {
    match val {
        Some(v) if !v.is_empty() => v,
        _ => default,
    }
}

pub fn validate_build_dirs(root: &Path) -> Result<(), BuildCheckError> {
    if !root.join("dist").is_dir() {
        return Err(BuildCheckError::MissingDist);
    }
    if !root.join("dist-server").is_dir() {
        return Err(BuildCheckError::MissingDistServer);
    }
    if !root
        .join("dist-server/oauth-user-inspector-server")
        .is_file()
        && !root.join("dist-server/server.js").is_file()
    {
        return Err(BuildCheckError::MissingServerJs);
    }
    Ok(())
}

fn capture_trimmed(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program).args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    Some(
        String::from_utf8_lossy(&output.stdout)
            .trim_end_matches(&['\r', '\n'][..])
            .to_string(),
    )
}

fn run_ls_la(target: Option<&str>) {
    let mut cmd = Command::new("ls");
    cmd.arg("-la");
    if let Some(t) = target {
        cmd.arg(t);
    }
    let _ = cmd.status();
}

pub fn run(_args: &[String]) -> i32 {
    println!("🚀 Starting OAuth User Inspector");
    let Some(node_ver) = capture_trimmed("node", &["--version"]) else {
        return 1;
    };
    println!("Node version: {node_ver}");
    let Some(npm_ver) = capture_trimmed("npm", &["--version"]) else {
        return 1;
    };
    println!("NPM version: {npm_ver}");
    let cwd = env::current_dir().unwrap_or_default();
    println!("Working directory: {}", cwd.display());

    let node_env_raw = env::var("NODE_ENV").ok();
    let port_raw = env::var("PORT").ok();
    println!(
        "Environment: {}",
        resolve_env_or_default(node_env_raw.as_deref(), "development")
    );
    println!(
        "Port: {}",
        resolve_env_or_default(port_raw.as_deref(), "8080")
    );

    if let Err(err) = validate_build_dirs(&cwd) {
        println!("{}", err.message());
        match err {
            BuildCheckError::MissingDist | BuildCheckError::MissingDistServer => run_ls_la(None),
            BuildCheckError::MissingServerJs => run_ls_la(Some("dist-server/")),
        }
        return 1;
    }

    println!("✅ Build files found, starting server...");
    println!("Contents of dist/ (frontend):");
    run_ls_la(Some("dist/"));
    println!("Contents of dist-server/ (backend):");
    run_ls_la(Some("dist-server/"));

    let err = Command::new("node").arg("dist-server/server.js").exec();
    eprintln!("failed to exec node dist-server/server.js: {err}");
    1
}
