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

//! pulumi_setup.sh in Rust: guided Pulumi bootstrap for a project directory.

use std::io::Write;
use std::process::{Command, Stdio};

fn command_on_path(name: &str) -> bool {
    let path_var = std::env::var("PATH").unwrap_or_default();
    for dir in path_var.split(':') {
        let p = std::path::PathBuf::from(dir).join(name);
        if let Ok(meta) = std::fs::metadata(&p) {
            use std::os::unix::fs::PermissionsExt;
            if meta.is_file() && meta.permissions().mode() & 0o111 != 0 {
                return true;
            }
        }
    }
    false
}

fn capture_stdout_ok(program: &str, args: &[&str]) -> Option<String> {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim_end().to_string())
}

fn run_ok(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn run_inherit(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn stdin_is_tty() -> bool {
    use std::io::IsTerminal;
    std::io::stdin().is_terminal()
}

fn prompt_read(prompt: &str) -> Option<String> {
    if stdin_is_tty() {
        let _ = std::io::stderr().write_all(prompt.as_bytes());
        let _ = std::io::stderr().flush();
    }
    let mut line = String::new();
    match std::io::stdin().read_line(&mut line) {
        Ok(0) => None,
        Ok(_) => {
            let v = line.trim_end_matches('\n').trim_end_matches('\r');
            Some(v.trim_matches(|c: char| c == ' ' || c == '\t').to_string())
        }
        Err(_) => None,
    }
}

fn is_repo_config(dir: &str) -> bool {
    dir.ends_with("repo-config") || dir.ends_with("repo_config")
}

pub fn run(args: &[String]) -> i32 {
    let project_dir = match args.first() {
        Some(d) if !d.is_empty() => d.as_str(),
        _ => {
            eprintln!("usage: bazel run //<pulumi-project>:setup (dir is baked in by the macro)");
            return 1;
        }
    };

    let ws = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            eprintln!("this target must be invoked via 'bazel run', not 'bazel test'");
            return 1;
        }
    };

    let full_path = format!("{}/{}", ws, project_dir);
    if std::env::set_current_dir(&full_path).is_err() {
        eprintln!("cannot cd to {}", full_path);
        return 1;
    }

    println!("Pulumi setup for {}", project_dir);
    println!("----------------------------------------------------------------------");

    // --- Prerequisites -------------------------------------------------------
    let mut missing = 0;
    if !command_on_path("pulumi") {
        eprintln!("! pulumi CLI not found. Install it: https://www.pulumi.com/docs/install/");
        missing += 1;
    }
    if !command_on_path("go") {
        eprintln!(
            "! go toolchain not found. Install Go: https://go.dev/dl/ (Pulumi compiles the program with it)."
        );
        missing += 1;
    }
    if missing > 0 {
        eprintln!("Install the missing tool(s) above and re-run this command.");
        return 1;
    }
    println!("\u{2713} pulumi and go are installed.");

    // --- Make the standalone module build-ready ------------------------------
    std::env::set_var("GOWORK", "off");
    println!("Resolving Go dependencies (go mod tidy)\u{2026}");
    if !run_inherit("go", &["mod", "tidy"]) {
        return 1;
    }
    println!("\u{2713} go.sum is up to date.");

    // --- Login (idempotent) --------------------------------------------------
    if run_ok("pulumi", &["whoami"]) {
        let who = capture_stdout_ok("pulumi", &["whoami"]).unwrap_or_default();
        println!("\u{2713} Already logged in to Pulumi as '{}'.", who);
    } else {
        println!(
            "Logging in to Pulumi (opens a browser, or use a PULUMI_ACCESS_TOKEN / 'pulumi login --local')\u{2026}"
        );
        if !run_inherit("pulumi", &["login"]) {
            return 1;
        }
    }

    // --- Stack select / create -----------------------------------------------
    if run_ok("pulumi", &["stack", "--show-name"]) {
        let name = capture_stdout_ok("pulumi", &["stack", "--show-name"]).unwrap_or_default();
        println!("\u{2713} Stack already selected: {}.", name);
    } else {
        println!();
        println!("Available stacks:");
        if !run_inherit("pulumi", &["stack", "ls"]) {
            println!("  (none yet)");
        }
        let stack = prompt_read("Stack to select or create (e.g. dev): ").unwrap_or_default();
        let stack = if stack.is_empty() {
            "dev".to_string()
        } else {
            stack
        };
        if run_ok("pulumi", &["stack", "select", &stack]) {
            println!("\u{2713} Selected existing stack '{}'.", stack);
        } else {
            if !run_inherit("pulumi", &["stack", "init", &stack]) {
                return 1;
            }
            println!("\u{2713} Created and selected stack '{}'.", stack);
        }
    }

    // --- GitHub provider token -----------------------------------------------
    println!();
    if std::env::var("GITHUB_TOKEN")
        .map(|v| !v.is_empty())
        .unwrap_or(false)
    {
        println!("\u{2713} GITHUB_TOKEN is set in the environment (value not shown).");
    } else {
        println!("! GITHUB_TOKEN is NOT set. The GitHub provider needs it. Export a PAT/token");
        println!("  with repo + admin scope before running 'up' (it is read from the env, never stored here):");
        println!("      export GITHUB_TOKEN=<your-token>");
    }

    // --- repo-config specific ------------------------------------------------
    if is_repo_config(project_dir) {
        println!();
        println!("Adoption note (repo-config): your repository already exists, so the first");
        println!("'up' IMPORTS it into state rather than creating it. Set the owner first:");
        println!("      bazel run //{project_dir}:config -- set repoOwner <your-org-or-user>");
        println!("then preview / apply:");
        println!("      bazel run //{}:preview", project_dir);
        println!("      bazel run //{}:up", project_dir);
        println!("If the import fails, fix repoName/repoOwner (and the token's account) and retry \u{2014}");
        println!("no resource is created until the import resolves.");

        // --- Automation opt-in -----------------------------------------------
        println!();
        if !command_on_path("gh") {
            println!("! gh CLI not found \u{2014} skipping CI/CD automation opt-in. Install it");
            println!("  (https://cli.github.com/, then 'gh auth login') and re-run to enable it.");
        } else {
            println!("CI/CD automation (optional): drive repo-config from GitHub Actions via the");
            println!("shared org Pulumi App. Set the per-repo toggles the workflows gate on.");

            // Preview toggle
            let enable_preview =
                prompt_read("Enable Pulumi preview on pull requests? [y/N] ").unwrap_or_default();
            let preview_val = if enable_preview.trim().eq_ignore_ascii_case("y")
                || enable_preview.trim().eq_ignore_ascii_case("yes")
            {
                "true"
            } else {
                "false"
            };
            if run_ok(
                "gh",
                &[
                    "variable",
                    "set",
                    "REPO_CONFIG_PREVIEW_ENABLED",
                    "--body",
                    preview_val,
                ],
            ) {
                println!(
                    "\u{2713} REPO_CONFIG_PREVIEW_ENABLED={} ({}).",
                    preview_val,
                    if preview_val == "true" {
                        "preview will run on pull requests"
                    } else {
                        "preview-on-PR disabled"
                    }
                );
            } else {
                eprintln!("! Failed to set REPO_CONFIG_PREVIEW_ENABLED (gh not authenticated, or insufficient repo perms?) \u{2014} skipping.");
            }

            // Apply toggle
            let enable_apply =
                prompt_read("Enable Pulumi apply on merge (auto-up)? [y/N] ").unwrap_or_default();
            let apply_val = if enable_apply.trim().eq_ignore_ascii_case("y")
                || enable_apply.trim().eq_ignore_ascii_case("yes")
            {
                "true"
            } else {
                "false"
            };
            if run_ok(
                "gh",
                &[
                    "variable",
                    "set",
                    "REPO_CONFIG_AUTO_APPLY",
                    "--body",
                    apply_val,
                ],
            ) {
                println!(
                    "\u{2713} REPO_CONFIG_AUTO_APPLY={} ({}).",
                    apply_val,
                    if apply_val == "true" {
                        "merges to the default branch will 'up'"
                    } else {
                        "apply-on-merge disabled"
                    }
                );
            } else {
                eprintln!("! Failed to set REPO_CONFIG_AUTO_APPLY (gh not authenticated, or insufficient repo perms?) \u{2014} skipping.");
            }

            // Org-cred check (best-effort)
            let org_owner = capture_stdout_ok(
                "gh",
                &["repo", "view", "--json", "owner", "--jq", ".owner.login"],
            );
            if let Some(ref o) = org_owner {
                let org_vars =
                    capture_stdout_ok("gh", &["variable", "list", "--org", o]).unwrap_or_default();
                let org_secrets =
                    capture_stdout_ok("gh", &["secret", "list", "--org", o]).unwrap_or_default();
                if !org_vars.contains("PULUMI_APP_ID")
                    || !org_secrets.contains("APP_PRIVATE_KEY")
                    || !org_secrets.contains("PULUMI_ACCESS_TOKEN")
                {
                    println!("! Org-level Pulumi App credentials not found \u{2014} run `bazel run //tools/pulumi:create-app` once for the org.");
                } else {
                    println!("\u{2713} Org-level Pulumi App credentials (PULUMI_APP_ID / APP_PRIVATE_KEY / PULUMI_ACCESS_TOKEN) are present.");
                }
            } else {
                println!("! Could not determine the repo owner (gh not authenticated?) \u{2014} skipping the");
                println!("  org-credential check. Ensure `bazel run //tools/pulumi:create-app` has been run for the org.");
            }

            println!(
                "Reminder: the shared org App must be INSTALLED on this repo for token minting."
            );
            println!("  Install it (replace <slug>, e.g. <org>-pulumi) at:");
            println!("      https://github.com/apps/<slug>/installations/new");
        }
    } else {
        println!();
        println!("Next steps:");
        println!("      bazel run //{}:preview", project_dir);
        println!("      bazel run //{}:up", project_dir);
    }

    println!();
    println!("Done. This helper is safe to re-run any time.");
    0
}
