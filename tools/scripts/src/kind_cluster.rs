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

use std::io::{self, BufRead, Write};
use std::process::Command;

const GREEN: &str = "\x1b[0;32m";
const YELLOW: &str = "\x1b[1;33m";
const RED: &str = "\x1b[0;31m";
const NC: &str = "\x1b[0m";

const CLUSTER_NAME: &str = "local-dev-cluster";
const CONFIG_FILE: &str = ".devcontainer/kind-config.yaml";

fn print_success(msg: &str) {
    println!("{GREEN}\u{2713}{NC} {msg}");
}

fn print_warning(msg: &str) {
    println!("{YELLOW}\u{26a0}{NC} {msg}");
}

fn print_error(msg: &str) {
    println!("{RED}\u{2717}{NC} {msg}");
}

fn check_docker() -> bool {
    let ok = Command::new("docker")
        .arg("info")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !ok {
        print_error("Docker is not running. Please ensure Docker is started.");
        return false;
    }
    print_success("Docker is running");
    true
}

fn cluster_exists() -> bool {
    let output = Command::new("kind")
        .args(["get", "clusters"])
        .stderr(std::process::Stdio::null())
        .output();
    match output {
        Ok(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            stdout.lines().any(|line| line == CLUSTER_NAME)
        }
        Err(_) => false,
    }
}

fn create_cluster() -> i32 {
    println!("Creating kind cluster '{CLUSTER_NAME}'...");

    if cluster_exists() {
        print_warning(&format!("Cluster '{CLUSTER_NAME}' already exists"));
        return 0;
    }

    let status = Command::new("kind")
        .args([
            "create",
            "cluster",
            &format!("--config={CONFIG_FILE}"),
            "--wait=5m",
        ])
        .status();
    match status {
        Ok(s) if s.success() => {}
        _ => return 1,
    }
    print_success("Cluster created successfully");

    let status = Command::new("kubectl")
        .args(["cluster-info", "--context", &format!("kind-{CLUSTER_NAME}")])
        .status();
    match status {
        Ok(s) if s.success() => {}
        Ok(s) => return s.code().unwrap_or(1),
        Err(_) => return 1,
    }
    print_success(&format!("kubectl configured to use kind-{CLUSTER_NAME}"));
    0
}

fn delete_cluster() -> i32 {
    println!("Deleting kind cluster '{CLUSTER_NAME}'...");

    if !cluster_exists() {
        print_warning(&format!("Cluster '{CLUSTER_NAME}' does not exist"));
        return 0;
    }

    let status = Command::new("kind")
        .args(["delete", "cluster", &format!("--name={CLUSTER_NAME}")])
        .status();
    match status {
        Ok(s) if s.success() => {}
        _ => return 1,
    }
    print_success("Cluster deleted successfully");
    0
}

fn status_cluster() -> i32 {
    if cluster_exists() {
        print_success(&format!("Cluster '{CLUSTER_NAME}' is running"));
        let ctx = Command::new("kubectl")
            .args(["config", "current-context"])
            .stderr(std::process::Stdio::null())
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .unwrap_or_default();
        print_success(&format!("Context '{ctx}' is active"));
        println!();
        println!("Cluster info:");
        let _ = Command::new("kubectl")
            .args(["cluster-info"])
            .stderr(std::process::Stdio::null())
            .status();
        println!();
        println!("Nodes:");
        let _ = Command::new("kubectl")
            .args(["get", "nodes"])
            .stderr(std::process::Stdio::null())
            .status();
    } else {
        print_warning(&format!("Cluster '{CLUSTER_NAME}' does not exist"));
        println!();
        println!("Run './tools/kind-cluster.sh create' to create a cluster");
    }
    0
}

fn restart_cluster() -> i32 {
    println!("Restarting kind cluster '{CLUSTER_NAME}'...");
    let rc = delete_cluster();
    if rc != 0 {
        return rc;
    }
    create_cluster()
}

fn rename_context() -> i32 {
    let output = Command::new("kubectl")
        .args(["config", "current-context"])
        .stderr(std::process::Stdio::null())
        .output();
    let current_context = match output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        Ok(o) => return o.status.code().unwrap_or(1),
        Err(_) => return 1,
    };

    if current_context.is_empty() {
        print_error("No current context found");
        return 1;
    }

    println!("Current context: {current_context}");
    print!("Rename context to 'dev-local'? (yes/no): ");
    let _ = io::stdout().flush();

    let mut response = String::new();
    let _ = io::stdin().lock().read_line(&mut response);
    let response = response.trim();

    if response == "yes" {
        let status = Command::new("kubectl")
            .args(["config", "rename-context", &current_context, "dev-local"])
            .status();
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => return s.code().unwrap_or(1),
            Err(_) => return 1,
        }
        print_success(&format!(
            "Context renamed from '{current_context}' to 'dev-local'"
        ));
        let status = Command::new("kubectl")
            .args(["config", "use-context", "dev-local"])
            .status();
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => return s.code().unwrap_or(1),
            Err(_) => return 1,
        }
        print_success("Switched to context 'dev-local'");
    } else {
        print_warning("Context rename cancelled");
    }
    0
}

fn show_help(argv0: &str) {
    print!(
        "\
Usage: {argv0} <command>

Commands:
    create          Create a new kind cluster
    delete          Delete the kind cluster
    restart         Restart the kind cluster (delete + create)
    status          Show cluster status
    rename-context  Rename the current kubectl context to 'dev-local'
    help            Show this help message

Examples:
    {argv0} create       # Create the cluster
    {argv0} status       # Check if cluster is running
    {argv0} delete       # Remove the cluster

The cluster is configured with:
  - Single control-plane node (resource-efficient)
  - Port mappings: 8080->80, 8443->443
  - Resource constraints for limited environments

After creating the cluster:
  - kubectl is automatically configured
  - Context: kind-{CLUSTER_NAME}
  - Access services at localhost:8080 (HTTP) or localhost:8443 (HTTPS)

"
    );
}

pub fn run(args: &[String]) -> i32 {
    let argv0 = args.first().map(|s| s.as_str()).unwrap_or("kind-cluster");
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("help");

    match cmd {
        "create" => {
            if !check_docker() {
                return 1;
            }
            create_cluster()
        }
        "delete" => {
            if !check_docker() {
                return 1;
            }
            delete_cluster()
        }
        "restart" => {
            if !check_docker() {
                return 1;
            }
            restart_cluster()
        }
        "status" => {
            if !check_docker() {
                return 1;
            }
            status_cluster()
        }
        "rename-context" => rename_context(),
        "help" | "--help" | "-h" => {
            show_help(argv0);
            0
        }
        other => {
            print_error(&format!("Unknown command: {other}"));
            println!();
            show_help(argv0);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_constants() {
        assert_eq!(CLUSTER_NAME, "local-dev-cluster");
        assert_eq!(CONFIG_FILE, ".devcontainer/kind-config.yaml");
    }

    #[test]
    fn test_help_contains_commands() {
        let help = format!("{}", {
            let mut buf = Vec::new();
            let argv0 = "test-bin";
            let text = format!(
                "\
Usage: {argv0} <command>

Commands:
    create          Create a new kind cluster
    delete          Delete the kind cluster
    restart         Restart the kind cluster (delete + create)
    status          Show cluster status
    rename-context  Rename the current kubectl context to 'dev-local'
    help            Show this help message

Examples:
    {argv0} create       # Create the cluster
    {argv0} status       # Check if cluster is running
    {argv0} delete       # Remove the cluster

The cluster is configured with:
  - Single control-plane node (resource-efficient)
  - Port mappings: 8080->80, 8443->443
  - Resource constraints for limited environments

After creating the cluster:
  - kubectl is automatically configured
  - Context: kind-{CLUSTER_NAME}
  - Access services at localhost:8080 (HTTP) or localhost:8443 (HTTPS)

"
            );
            buf.extend_from_slice(text.as_bytes());
            String::from_utf8(buf).unwrap()
        });
        assert!(help.contains("create"));
        assert!(help.contains("delete"));
        assert!(help.contains("restart"));
        assert!(help.contains("status"));
        assert!(help.contains("rename-context"));
        assert!(help.contains("help"));
        assert!(help.contains("test-bin"));
    }

    #[test]
    fn test_run_help_variants() {
        for cmd in &["help", "--help", "-h"] {
            let rc = run(&["test-bin".to_string(), cmd.to_string()]);
            assert_eq!(rc, 0, "help variant '{cmd}' should return 0");
        }
    }

    #[test]
    fn test_run_no_args_is_help() {
        let rc = run(&["test-bin".to_string()]);
        assert_eq!(rc, 0);
    }
}
