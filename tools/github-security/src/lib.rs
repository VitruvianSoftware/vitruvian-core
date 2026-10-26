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

//! enable-dependency-graph: enable-dependency-graph.sh in Rust. Turn on the
//! GitHub dependency graph for VitruvianSoftware/vitruvian-core by attaching
//! an org code security configuration that enables the graph (and the
//! advanced_security gate the API demands) and leaves every other setting
//! `not_set`. Idempotent; refuses a non-public repo without typed consent;
//! asks for admin:org rather than failing on it. Same gh calls, output and
//! exit codes as the script; the wait between checks is the same `sleep 5`.

use shell_compat as sh;
use std::process::{Command, Stdio};

pub const ORG: &str = "VitruvianSoftware";
pub const REPO: &str = "vitruvian-core";
pub const CONFIG_NAME: &str = "dependency-graph-only";

/// The configuration's settings: exactly two `enabled` (the graph and the
/// advanced_security gate), every feature repo_config owns `not_set`.
pub const SETTINGS: &[(&str, &str)] = &[
    ("advanced_security", "enabled"),
    ("dependency_graph", "enabled"),
    ("dependabot_alerts", "not_set"),
    ("dependabot_security_updates", "not_set"),
    ("secret_scanning", "not_set"),
    ("secret_scanning_push_protection", "not_set"),
    ("code_scanning_default_setup", "not_set"),
    ("private_vulnerability_reporting", "not_set"),
];

const DESCRIPTION: &str = "Enables ONLY the dependency graph (prerequisite for the dependency-review gate). All other settings are not_set so repo_config/Pulumi stays the authority.";

pub struct Exit(pub i32);

fn info(msg: &str) {
    sh::out(format!("\x1b[36m\u{2192}\x1b[0m {}\n", msg).as_bytes());
}

fn ok(msg: &str) {
    sh::out(format!("\x1b[32m\u{2713}\x1b[0m {}\n", msg).as_bytes());
}

fn die(msg: &str) -> Exit {
    sh::err(format!("\x1b[31m\u{2717}\x1b[0m {}\n", msg).as_bytes());
    Exit(1)
}

fn gh(args: &[&str]) -> Command {
    let mut c = Command::new("gh");
    c.args(args);
    c
}

fn lossy(b: Vec<u8>) -> String {
    String::from_utf8_lossy(&b).into_owned()
}

/// `gh api .../dependency-graph/sbom --silent >/dev/null 2>&1`: the graph answers.
fn sbom_answers() -> bool {
    let path = format!("repos/{}/{}/dependency-graph/sbom", ORG, REPO);
    let mut c = gh(&["api", &path, "--silent"]);
    c.stdout(Stdio::null()).stderr(Stdio::null());
    sh::status(0, &mut c, true) == 0
}

/// The `x-oauth-scopes` values of `gh api -i user`, after `tr -d '\r'`, as
/// `awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}'` prints them.
pub fn scopes_from_headers(raw: &[u8]) -> Vec<u8> {
    let text: Vec<u8> = raw.iter().copied().filter(|&c| c != b'\r').collect();
    let mut out = Vec::new();
    for line in text.split(|&c| c == b'\n') {
        let mut fields = split_on(line, b": ");
        let name = fields.next().unwrap_or_default();
        if name.to_ascii_lowercase() == b"x-oauth-scopes" {
            out.extend(fields.next().unwrap_or_default());
            out.push(b'\n');
        }
    }
    out
}

/// awk's field split on a multi-character FS.
fn split_on<'a>(line: &'a [u8], sep: &'a [u8]) -> impl Iterator<Item = Vec<u8>> + 'a {
    let mut rest = Some(line);
    std::iter::from_fn(move || {
        let r = rest?;
        match r.windows(sep.len()).position(|w| w == sep) {
            Some(i) => {
                rest = Some(&r[i + sep.len()..]);
                Some(r[..i].to_vec())
            }
            None => {
                rest = None;
                Some(r.to_vec())
            }
        }
    })
}

/// `case ",${scopes// /}," in *,admin:org,*)`.
pub fn has_admin_org(scopes: &[u8]) -> bool {
    let squeezed: Vec<u8> = scopes.iter().copied().filter(|&c| c != b' ').collect();
    sh::contains(&sh::cat(&[b",", &squeezed, b","]), b",admin:org,")
}

fn body() -> Result<(), Exit> {
    if sh::which(b"gh").is_none() {
        return Err(die("the GitHub CLI (gh) is required."));
    }

    // --- 0. already enabled? ------------------------------------------------
    if sbom_answers() {
        ok(&format!(
            "Dependency graph is already enabled for {}/{} \u{2014} nothing to do.",
            ORG, REPO
        ));
        return Ok(());
    }
    info(&format!(
        "Dependency graph is OFF for {}/{} (the SBOM endpoint does not answer).",
        ORG, REPO
    ));

    // --- 0b. visibility gate --------------------------------------------------
    let repo_path = format!("repos/{}/{}", ORG, REPO);
    let ran = sh::capture(0, &mut gh(&["api", &repo_path, "--jq", ".visibility"]));
    let failed = !ran.ok();
    let mut vis = ran.stdout;
    if failed {
        vis.extend_from_slice(b"unknown\n");
    }
    let visibility = lossy(sh::subst(vis));
    info(&format!("repository visibility: {}", visibility));
    if visibility != "public" {
        sh::out(format!("\x1b[33m!\x1b[0m {} is {}, not public.\n", REPO, visibility).as_bytes());
        sh::out(
            b"     This creates a code security configuration with advanced_security=enabled,\n\
              \x20    which on a private repository enables GitHub Advanced Security and BILLS\n\
              \x20    PER ACTIVE COMMITTER. It cannot be omitted: the API rejects a config that\n\
              \x20    enables any GHAS feature without it, and it cannot be set to not_set.\n\
              \x20    Consider the granular SKUs instead (advanced_security=code_security).\n",
        );
        if !sh::stdin_is_tty() {
            return Err(die(
                "refusing to enable a billable feature non-interactively. Re-run from a terminal to confirm.",
            ));
        }
        sh::out(b"     Type EXACTLY \"i accept the billing\" to continue: ");
        let mut tty = match std::fs::File::open("/dev/tty") {
            Ok(t) => t,
            Err(e) => {
                sh::redirect_error(83, b"/dev/tty", &e);
                return Err(Exit(1));
            }
        };
        let confirm = sh::read_trim(&sh::read_line_raw(&mut tty).0);
        if confirm != b"i accept the billing" {
            return Err(die("aborted \u{2014} nothing was changed."));
        }
    }

    // --- 1. make sure we hold admin:org --------------------------------------
    let ran = sh::capture(0, &mut gh(&["api", "-i", "user"]));
    if !ran.ok() {
        // The pipeline's status, under set -e.
        return Err(Exit(ran.status));
    }
    let scopes = sh::subst(scopes_from_headers(&ran.stdout));
    let shown = if scopes.is_empty() {
        "<none>".to_string()
    } else {
        lossy(scopes.clone())
    };
    info(&format!("current token scopes: {}", shown));
    if has_admin_org(&scopes) {
        ok("admin:org already granted.");
    } else {
        info("admin:org is required to manage an org code security configuration.");
        if !sh::stdin_is_tty() {
            return Err(die(
                "no TTY to authorise with. Re-run this target from an interactive shell:\n     bazel run //tools/github-security:enable-dependency-graph",
            ));
        }
        info("requesting the extra scope now (a browser/device prompt will appear)...");
        if sh::status(
            0,
            &mut gh(&["auth", "refresh", "-h", "github.com", "-s", "admin:org"]),
            false,
        ) != 0
        {
            return Err(die("scope upgrade declined or failed; cannot continue."));
        }
        ok("admin:org granted.");
    }

    // --- 2. find or create the surgical configuration ------------------------
    let configs = format!("orgs/{}/code-security/configurations", ORG);
    let select = format!(".[] | select(.name==\"{}\") | .id", CONFIG_NAME);
    let ran = sh::capture(0, &mut gh(&["api", &configs, "--jq", &select]));
    let mut config_id = lossy(sh::first_line(&ran.stdout));
    if !config_id.is_empty() {
        ok(&format!(
            "reusing existing configuration {} (id={}).",
            CONFIG_NAME, config_id
        ));
    } else {
        info(&format!(
            "creating configuration {} (dependency_graph only, everything else not_set)...",
            CONFIG_NAME
        ));
        let mut args: Vec<String> = vec!["api".into(), "-X".into(), "POST".into(), configs.clone()];
        args.push("-f".into());
        args.push(format!("name={}", CONFIG_NAME));
        args.push("-f".into());
        args.push(format!("description={}", DESCRIPTION));
        for (k, v) in SETTINGS {
            args.push("-f".into());
            args.push(format!("{}={}", k, v));
        }
        args.push("--jq".into());
        args.push(".id".into());
        let mut c = Command::new("gh");
        c.args(&args);
        let ran = sh::capture_stdout(0, &mut c);
        if !ran.ok() {
            return Err(die("could not create the configuration."));
        }
        config_id = lossy(sh::subst(ran.stdout));
        ok(&format!("created configuration id={}.", config_id));
    }

    // --- 3. attach it to this repository only --------------------------------
    let ran = sh::capture_stdout(0, &mut gh(&["api", &repo_path, "--jq", ".id"]));
    if !ran.ok() {
        return Err(Exit(ran.status));
    }
    let repo_id = lossy(sh::subst(ran.stdout));
    info(&format!(
        "attaching configuration {} to {} (id={})...",
        config_id, REPO, repo_id
    ));
    let attach = format!(
        "orgs/{}/code-security/configurations/{}/attach",
        ORG, config_id
    );
    let ids = format!("selected_repository_ids[]={}", repo_id);
    let mut c = gh(&[
        "api",
        "-X",
        "POST",
        &attach,
        "-f",
        "scope=selected",
        "-F",
        &ids,
    ]);
    c.stdout(Stdio::null());
    if sh::status(0, &mut c, false) != 0 {
        return Err(die("could not attach the configuration."));
    }

    // --- 4. verify -------------------------------------------------------------
    info("waiting for the graph to come online...");
    for _ in 0..30 {
        if sbom_answers() {
            ok("Dependency graph is ENABLED and answering.");
            sh::out(
                b"\nNext: restore the dependency-review job in .github/workflows/supply-chain.yaml\n\
                  and add \"dependency-review\" to the required-check list in\n\
                  infrastructure/pulumi/platform/repo_config/main.go. Both carry a comment\n\
                  pointing back here.\n",
            );
            return Ok(());
        }
        let st = sh::status(0, Command::new("sleep").arg("5"), false);
        if st != 0 {
            return Err(Exit(st));
        }
    }
    Err(die(&format!(
        "attached, but the graph is still not answering after ~150s. Check\n   https://github.com/{}/{}/settings/security_analysis",
        ORG, REPO
    )))
}

/// The whole tool; the process exit code.
pub fn run() -> i32 {
    match body() {
        Ok(()) => 0,
        Err(Exit(c)) => c,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn posture_is_dependency_graph_only() {
        let enabled: Vec<&str> = SETTINGS
            .iter()
            .filter(|(_, v)| *v == "enabled")
            .map(|(k, _)| *k)
            .collect();
        assert_eq!(enabled, vec!["advanced_security", "dependency_graph"]);
        assert!(SETTINGS
            .iter()
            .all(|(_, v)| *v == "enabled" || *v == "not_set"));
        assert_eq!(SETTINGS.len(), 8);
    }

    #[test]
    fn scopes_header_is_found_case_insensitively() {
        let raw = b"HTTP/2.0 200 OK\r\nX-OAuth-Scopes: gist, read:org, repo\r\nx-accepted: a\r\n";
        assert_eq!(scopes_from_headers(raw), b"gist, read:org, repo\n");
        assert_eq!(scopes_from_headers(b"x-oauth-scopes: a: b\n"), b"a\n");
        assert_eq!(scopes_from_headers(b"x-oauth-scopes:a\n"), b"");
        assert_eq!(scopes_from_headers(b"nothing\n"), b"");
    }

    #[test]
    fn admin_org_scope() {
        assert!(has_admin_org(b"gist, admin:org, repo"));
        assert!(has_admin_org(b"admin:org"));
        assert!(!has_admin_org(b"read:org, repo"));
        assert!(!has_admin_org(b"admin:orgx"));
        assert!(!has_admin_org(b""));
    }
}
