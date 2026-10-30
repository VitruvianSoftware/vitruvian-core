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

use std::process::{Command, Stdio};

use crate::resolve_identity;
use crate::retry_concurrent_update;

const DEV_LOCAL: &str = "infrastructure/pulumi/platform/dev-local";

pub fn command_on_path(name: &str) -> bool {
    let path_var = std::env::var("PATH").unwrap_or_default();
    for dir in path_var.split(':') {
        let d = if dir.is_empty() { "." } else { dir };
        let p = std::path::PathBuf::from(d).join(name);
        if let Ok(meta) = std::fs::metadata(&p) {
            use std::os::unix::fs::PermissionsExt;
            if meta.is_file() && meta.permissions().mode() & 0o111 != 0 {
                return true;
            }
        }
    }
    false
}

fn env_set_nonempty(name: &str) -> bool {
    std::env::var(name).map_or(false, |v| !v.is_empty())
}

fn env_default(name: &str, default: &str) {
    if !env_set_nonempty(name) {
        std::env::set_var(name, default);
    }
}

fn has_flag(args: &[String], names: &[&str]) -> bool {
    args.iter().any(|a| {
        for name in names {
            if a == *name || a.starts_with(&format!("{}=", name)) {
                return true;
            }
        }
        false
    })
}

/// //tools/gcp-token, as the pulumi_project() targets hand it over: a
/// runfiles-relative path in VITRUVIAN_GCP_TOKEN_BIN. Resolved against the
/// working directory (the runfiles tree under `bazel run`), then RUNFILES_DIR,
/// so call this before changing directory. Empty when unset or not found, which
/// leaves the plain gcloud fallback.
fn resolve_minter() -> String {
    let bin = std::env::var("VITRUVIAN_GCP_TOKEN_BIN").unwrap_or_default();
    if bin.is_empty() || bin.starts_with('/') {
        return bin;
    }
    if let Ok(cwd) = std::env::current_dir() {
        let p = cwd.join(&bin);
        if is_executable(&p.to_string_lossy()) {
            return p.to_string_lossy().into_owned();
        }
    }
    if let Ok(rf) = std::env::var("RUNFILES_DIR") {
        if !rf.is_empty() {
            let p = format!("{}/_main/{}", rf, bin);
            if is_executable(&p) {
                return p;
            }
        }
    }
    bin
}

fn inject_gcp_identity(workspace: &str, project_dir: &str, minter: &str) {
    if env_set_nonempty("GOOGLE_OAUTH_ACCESS_TOKEN")
        || env_set_nonempty("GOOGLE_APPLICATION_CREDENTIALS")
        || env_set_nonempty("CLOUDSDK_AUTH_ACCESS_TOKEN")
    {
        eprintln!(
            "\u{2192} GCP auth: ambient credentials present -- honoring them \
             (skipping the gcp-identities.tsv pin) for {}",
            project_dir
        );
        return;
    }

    let id_map = format!("{}/infrastructure/gcp-identities.tsv", workspace);
    if !std::path::Path::new(&id_map).is_file() {
        return;
    }

    let identity = resolve_identity::resolve(&id_map, project_dir);
    let (account, project) = match identity {
        Some(pair) if !pair.0.is_empty() => pair,
        _ => return,
    };

    if !command_on_path("gcloud") {
        eprintln!(
            "ERROR: {} is pinned to GCP identity '{}'",
            project_dir, account
        );
        eprintln!("(infrastructure/gcp-identities.tsv) but the gcloud CLI is not installed:");
        eprintln!("    https://cloud.google.com/sdk/docs/install");
        std::process::exit(1);
    }

    // //tools/gcp-token: local gcloud first, then (a Claude Code cloud session,
    // with no credentials of its own) a token minted over the tailnet. Without
    // the minter this is plain local gcloud. See tools/gcp-token/README.md.
    let token = if minter.starts_with('/') && is_executable(minter) {
        // stderr shown, as in pulumi-cmd.sh: the broker reports progress there.
        capture_stdout(minter, &[&account], Stdio::inherit())
    } else {
        capture_stdout_lossy(
            "gcloud",
            &[
                "auth",
                "print-access-token",
                &format!("--account={}", account),
            ],
        )
    };

    if token.is_empty() {
        eprintln!(
            "ERROR: {} is pinned to GCP identity '{}'",
            project_dir, account
        );
        eprintln!("(infrastructure/gcp-identities.tsv) but no valid credentials were found,");
        eprintln!("locally or via the tailnet broker (see the checklist above).");
        eprintln!("Log in with:  gcloud auth login {}", account);
        std::process::exit(1);
    }

    std::env::set_var("GOOGLE_OAUTH_ACCESS_TOKEN", &token);
    if !project.is_empty() && project != "-" {
        std::env::set_var("GOOGLE_CLOUD_PROJECT", &project);
        std::env::set_var("CLOUDSDK_CORE_PROJECT", &project);
    }
    eprintln!(
        "\u{2192} GCP identity: {} (project {}) for {}",
        account,
        if project.is_empty() || project == "-" {
            "unset"
        } else {
            &project
        },
        project_dir
    );
}

fn is_executable(path: &str) -> bool {
    if let Ok(meta) = std::fs::metadata(path) {
        use std::os::unix::fs::PermissionsExt;
        meta.is_file() && meta.permissions().mode() & 0o111 != 0
    } else {
        false
    }
}

fn capture_stdout_lossy(cmd: &str, args: &[&str]) -> String {
    capture_stdout(cmd, args, Stdio::null())
}

/// `$(cmd args...)`: stdout captured (trailing newlines trimmed), stderr as given.
fn capture_stdout(cmd: &str, args: &[&str], stderr: Stdio) -> String {
    let output = Command::new(cmd)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(stderr)
        .output();
    match output {
        Ok(o) if o.status.success() => {
            let s = String::from_utf8_lossy(&o.stdout).to_string();
            s.trim_end_matches('\n').to_string()
        }
        _ => String::new(),
    }
}

fn qualify_stack_args(args: &mut Vec<String>) {
    let org = match std::env::var("PULUMI_ORG") {
        Ok(o) if !o.is_empty() => o,
        _ => return,
    };
    let backend = std::env::var("PULUMI_BACKEND_URL").unwrap_or_default();
    if !(backend.starts_with("https://") || backend.starts_with("http://")) {
        return;
    }

    let n = args.len();
    let mut i = 0;
    let mut new_args = Vec::with_capacity(n);
    let mut want_stack_value = false;

    while i < n {
        let a = &args[i];
        if want_stack_value {
            if a.contains('/') {
                new_args.push(a.clone());
            } else {
                new_args.push(format!("{}/{}", org, a));
            }
            want_stack_value = false;
            i += 1;
            continue;
        }
        match a.as_str() {
            "--stack" | "-s" => {
                want_stack_value = true;
                new_args.push(a.clone());
            }
            _ if a.starts_with("--stack=") || a.starts_with("-s=") => {
                let eq_pos = a.find('=').unwrap();
                let flag = &a[..eq_pos];
                let val = &a[eq_pos + 1..];
                if val.contains('/') {
                    new_args.push(a.clone());
                } else {
                    new_args.push(format!("{}={}/{}", flag, org, val));
                }
            }
            _ => {
                new_args.push(a.clone());
            }
        }
        i += 1;
    }
    *args = new_args;
}

pub fn run(args: &[String]) -> i32 {
    if args.len() < 2 {
        eprintln!("usage: pulumi-cmd <project_dir> <subcmd> [args...]");
        return 1;
    }

    let project_dir = &args[0];
    let subcmd = &args[1];
    let mut extra_args: Vec<String> = args[2..].to_vec();

    if !command_on_path("pulumi") {
        eprintln!(
            "pulumi CLI not found on PATH. Run 'bazel run //{}:setup' first,",
            project_dir
        );
        eprintln!("or install it from https://www.pulumi.com/docs/install/.");
        return 1;
    }

    let workspace = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(w) if !w.is_empty() => w,
        _ => {
            eprintln!("this target must be invoked via 'bazel run', not 'bazel test'");
            return 1;
        }
    };

    // Before the chdir below: the minter path is relative to the runfiles tree.
    let minter = resolve_minter();

    let target_dir = format!("{}/{}", workspace, project_dir);
    if std::env::set_current_dir(&target_dir).is_err() {
        eprintln!("cannot cd to {}", target_dir);
        return 1;
    }

    std::env::set_var("GOWORK", "off");

    // --- GCP identity injection ---
    inject_gcp_identity(&workspace, project_dir, &minter);

    // --- dev-local + backend resolution (combined from the two shell blocks) ---
    let is_dev_local = project_dir == DEV_LOCAL;

    if is_dev_local {
        let home = std::env::var("HOME").unwrap_or_default();
        env_default("KUBECONFIG", &format!("{}/.kube/cluster.yaml", home));
        env_default("PULUMI_BACKEND_URL", "https://api.pulumi.com");

        if !has_flag(&extra_args, &["--stack", "-s"]) {
            extra_args.insert(0, "local".to_string());
            extra_args.insert(0, "--stack".to_string());
        }
    } else if !env_set_nonempty("PULUMI_BACKEND_URL") {
        if env_set_nonempty("PULUMI_ACCESS_TOKEN") {
            std::env::set_var("PULUMI_BACKEND_URL", "https://api.pulumi.com");
        } else {
            let proj = std::env::var("GOOGLE_CLOUD_PROJECT")
                .or_else(|_| std::env::var("GCP_PROJECT_ID"))
                .unwrap_or_default();
            if !proj.is_empty() && proj != "-" {
                std::env::set_var("PULUMI_BACKEND_URL", format!("gs://{}-pulumi-state", proj));
            } else {
                std::env::set_var("PULUMI_BACKEND_URL", "https://api.pulumi.com");
            }
        }
    }

    // --- PULUMI_ORG stack qualification ---
    qualify_stack_args(&mut extra_args);

    // --- Non-interactive injection ---
    if !has_flag(&extra_args, &["--non-interactive"]) {
        let ci = env_set_nonempty("CI");
        let not_tty = !atty_stdin();
        if ci || not_tty {
            extra_args.push("--non-interactive".to_string());
        }
    }

    // --- Execute with retry ---
    let mut cmd_args = vec!["pulumi".to_string(), subcmd.clone()];
    cmd_args.extend(extra_args);
    retry_concurrent_update::retry_command(&cmd_args)
}

fn atty_stdin() -> bool {
    use std::io::IsTerminal;
    std::io::stdin().is_terminal()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn has_flag_detects_long_and_short() {
        let args: Vec<String> = vec!["--yes".into(), "--stack".into(), "dev".into()];
        assert!(has_flag(&args, &["--stack", "-s"]));
        assert!(!has_flag(&args, &["--non-interactive"]));
    }

    #[test]
    fn has_flag_detects_equals_form() {
        let args: Vec<String> = vec!["--stack=dev".into()];
        assert!(has_flag(&args, &["--stack", "-s"]));
        let args2: Vec<String> = vec!["-s=dev".into()];
        assert!(has_flag(&args2, &["--stack", "-s"]));
    }

    #[test]
    fn qualify_stack_noop_without_org() {
        std::env::remove_var("PULUMI_ORG");
        let mut args: Vec<String> = vec!["--stack".into(), "dev".into()];
        qualify_stack_args(&mut args);
        assert_eq!(args, vec!["--stack", "dev"]);
    }
}
