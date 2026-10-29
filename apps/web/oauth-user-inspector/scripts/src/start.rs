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

//! The container entrypoint (`dist-server/start`), the Rust successor of the
//! former `start.sh`.

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
                "❌ Error: dist-server/oauth-user-inspector-server not found. Server build may have failed."
            }
        }
    }
}

/// How the container hands off to the real server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ServerCommand {
    /// The compiled Rust server (`dist-server/oauth-user-inspector-server`).
    Native(&'static str),
    /// The legacy Node server (`node dist-server/server.js`).
    Node(&'static str),
}

/// Pick the server to exec, mirroring the former `start.sh`: prefer the native
/// binary, fall back to `node dist-server/server.js`.
pub fn select_server_command(root: &Path) -> ServerCommand {
    if root
        .join("dist-server/oauth-user-inspector-server")
        .is_file()
    {
        ServerCommand::Native("dist-server/oauth-user-inspector-server")
    } else {
        ServerCommand::Node("dist-server/server.js")
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

    let (err, what) = match select_server_command(&cwd) {
        ServerCommand::Native(bin) => (Command::new(format!("./{bin}")).exec(), bin),
        ServerCommand::Node(js) => (Command::new("node").arg(js).exec(), js),
    };
    eprintln!("failed to exec {what}: {err}");
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = env::temp_dir().join(format!("oui-start-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(d.join("dist-server")).unwrap();
        d
    }

    /// Regression: the image ships only the native binary (no server.js); the
    /// entrypoint must exec it rather than `node dist-server/server.js`, which
    /// made Cloud Run revisions fail to listen on PORT.
    #[test]
    fn prefers_native_binary_when_present() {
        let d = tmp("native");
        fs::write(d.join("dist-server/oauth-user-inspector-server"), "").unwrap();
        assert_eq!(
            select_server_command(&d),
            ServerCommand::Native("dist-server/oauth-user-inspector-server")
        );
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn falls_back_to_node_server_js() {
        let d = tmp("node");
        fs::write(d.join("dist-server/server.js"), "").unwrap();
        assert_eq!(
            select_server_command(&d),
            ServerCommand::Node("dist-server/server.js")
        );
        let _ = fs::remove_dir_all(&d);
    }
}
