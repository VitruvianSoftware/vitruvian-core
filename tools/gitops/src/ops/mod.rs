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

//! The tools/gitops shell scripts in Rust, one module per script, behind one
//! dispatcher: `gitops-cli TOOL ARGS...` runs TOOL as `bash TOOL.sh ARGS...`
//! would. A link or copy of the binary named after a tool runs that tool
//! (`seal-alert-ntfy ARGS...`), which is how the parity test calls it. Each
//! `bazel run` target is the same binary with the tool (and subcommand)
//! baked into its args.

pub mod backstage;
pub mod bw_backup;
pub mod cicd_smoke;
pub mod common;
pub mod crypto;
pub mod gitops_cmd;
pub mod headscale;
pub mod jq;
pub mod ntfy;
pub mod rotate_otel;
pub mod seal;

/// Each tool: its name and the script it ports.
pub const TOOLS: &[(&str, &str)] = &[
    ("gitops-cmd", "gitops-cmd.sh"),
    ("seal-alert-ntfy", "seal_alert_ntfy.sh"),
    (
        "seal-argocd-backstage-token",
        "seal_argocd_backstage_token.sh",
    ),
    ("seal-headplane-secret", "seal_headplane_secret.sh"),
    (
        "seal-zitadel-login-cookie-secret",
        "seal_zitadel_login_cookie_secret.sh",
    ),
    ("sealed-secrets-keys", "sealed_secrets_keys.sh"),
    ("argocd-secret", "argocd-secret.sh"),
    ("ntfy-bootstrap-users", "ntfy_bootstrap_users.sh"),
    ("ntfy-manage-users", "ntfy_manage_users.sh"),
    ("headscale-ops", "headscale_ops.sh"),
    (
        "rotate-github-otel-webhook-secret",
        "rotate_github_otel_webhook_secret.sh",
    ),
    ("cicd-telemetry-smoke", "cicd_telemetry_smoke.sh"),
    ("seal-arc-github-app", "seal_arc_github_app.sh"),
];

/// Run tool `name` with the script's arguments; None for an unknown name.
pub fn run_tool(name: &[u8], args: &[Vec<u8>]) -> Option<i32> {
    Some(match name {
        b"gitops-cmd" => gitops_cmd::main(args),
        b"seal-alert-ntfy" => seal::alert_ntfy(args),
        b"seal-argocd-backstage-token" => backstage::main(args),
        b"seal-headplane-secret" => seal::headplane(args),
        b"seal-zitadel-login-cookie-secret" => seal::zitadel(args),
        b"sealed-secrets-keys" => bw_backup::sealed_secrets_keys(args),
        b"argocd-secret" => bw_backup::argocd_secret(args),
        b"ntfy-bootstrap-users" => ntfy::bootstrap(args),
        b"ntfy-manage-users" => ntfy::manage(args),
        b"headscale-ops" => headscale::main(args),
        b"rotate-github-otel-webhook-secret" => rotate_otel::main(args),
        b"cicd-telemetry-smoke" => cicd_smoke::main(args),
        b"seal-arc-github-app" => seal::arc_github_app(args),
        _ => return None,
    })
}

fn usage() -> String {
    let mut s = String::from("usage: gitops-cli TOOL [ARGS...]\ntools:\n");
    for (name, script) in TOOLS {
        s.push_str(&format!("  {:<34} (tools/gitops/{})\n", name, script));
    }
    s
}

/// The binary's entry point: `argv0` picks the tool when it is named after
/// one; otherwise the first argument does.
pub fn main(argv0: &[u8], args: &[Vec<u8>]) -> i32 {
    let base = match argv0.iter().rposition(|&c| c == b'/') {
        Some(i) => &argv0[i + 1..],
        None => argv0,
    };
    if let Some(code) = run_tool(base, args) {
        return code;
    }
    match args.first() {
        Some(name) => match run_tool(name, &args[1..]) {
            Some(code) => code,
            None => {
                shell_compat::err(
                    format!(
                        "gitops-cli: unknown tool '{}'\n{}",
                        String::from_utf8_lossy(name),
                        usage()
                    )
                    .as_bytes(),
                );
                2
            }
        },
        None => {
            shell_compat::err(usage().as_bytes());
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tool_names_are_unique_and_kebab_case() {
        let mut seen = std::collections::HashSet::new();
        for (name, script) in TOOLS {
            assert!(seen.insert(*name), "duplicate tool {}", name);
            assert!(name
                .bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-'));
            assert!(script.ends_with(".sh"));
        }
        assert_eq!(TOOLS.len(), 13);
        assert!(run_tool(b"no-such-tool", &[]).is_none());
    }
}
