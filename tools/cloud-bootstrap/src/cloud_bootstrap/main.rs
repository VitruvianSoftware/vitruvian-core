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

//! cloud-bootstrap: make a Claude Code *cloud* sandbox into a working
//! vitruvian-core development machine: the repo's CLI tooling, plus exactly the
//! credentials the session's PROFILE is allowed to hold.
//!
//!   bazel run //tools/cloud-bootstrap                 # install + authenticate
//!   bazel run //tools/cloud-bootstrap:whoami          # report (gate; non-zero if incomplete)
//!   bazel run //tools/cloud-bootstrap:profiles        # list the profiles
//!
//! A cloud session starts as a bare Ubuntu box with git/go/node/rustc but no
//! bazel, no gh, no gcloud, no pulumi, and no credentials for any of them.
//!
//! THE PROFILE IS THE BLAST-RADIUS BOUNDARY. $VITRUVIAN_PROFILE selects rows
//! of profiles.tsv, and those rows (not this tool, not the agent) decide which
//! CLIs are installed and which secrets the session may materialise. The only
//! credential the environment needs is $PULUMI_ACCESS_TOKEN: it opens a Pulumi
//! ESC environment for a short-lived GCP token (the org forbids
//! service-account keys) that can read the profile's secrets from Secret
//! Manager and nothing else. See tools/cloud-bootstrap/README.md.
//!
//! Best-effort by design: `up`, `install` and `auth` exit 0 on every failure
//! path (a bootstrap hiccup must never block the session) and say loudly what
//! went wrong. `whoami` is the opposite: non-zero when a profile is not fully
//! satisfied, so it is usable as a gate.
//!
//! Standard library only, and one crate, so it builds with a single plain
//! `rustc` call where Bazel does not exist yet.

mod creds;
mod install;
mod manifest;
mod sh;

use std::ffi::OsString;
use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use creds::AuthState;
use sh::which;

pub fn warn(msg: &str) {
    eprintln!("cloud-bootstrap: {msg}");
}

pub fn note(msg: &str) {
    eprintln!("  {msg}");
}

pub fn err_bytes(b: &[u8]) {
    let _ = std::io::stderr().lock().write_all(b);
}

fn out(s: &str) {
    let mut o = std::io::stdout().lock();
    let _ = o.write_all(s.as_bytes());
    let _ = o.flush();
}

const USAGE: &str = "Usage: bazel run //tools/cloud-bootstrap[:<subcommand>] -- [flags]

Subcommands (each bazel target bakes one in as the first argument):
  up         install the profiles' CLIs and establish their credentials (default)
  install    CLIs only
  auth       credentials only
  whoami     report what this session has; non-zero if a profile is unsatisfied
  profiles   list the profiles declared in profiles.tsv

Flags:
  --profile <list>  override $VITRUVIAN_PROFILE for this run (comma-separated)
  --force           run against a local checkout (normally cloud sessions only)
";

/// Everything the run reads from its environment, plus the state it builds.
pub struct Ctx {
    pub min_credential_len: usize,
    pub gcloud_bin: OsString,
    pub install_dir: PathBuf,
    pub state_dir: PathBuf,
    pub bashrc: PathBuf,
    pub session_env: PathBuf,
    pub ws: PathBuf,
    pub profiles_file: PathBuf,
    pub cache_setup: PathBuf,
    pub esc_sa: String,
    pub pulumi_bin: OsString,
    pub esc_retries: u32,
    pub esc_retry_delay: Duration,
    pub esc_retry_delay_raw: String,

    pub auth_state: AuthState,
    /// The identity ambient for the session: the FIRST listed profile that has
    /// one wins (order the list to choose it).
    pub primary_account: String,
    pub esc_token_file: Option<PathBuf>,
    /// Every VAR=secret already materialised, in order.
    pub claimed: Vec<(String, String)>,
    pub profile_list: Vec<String>,
    /// Union of the listed profiles' tools; empty means none ("-").
    pub tools_all: Vec<String>,
}

impl Ctx {
    fn from_env() -> Ctx {
        let home = sh::lossy(&sh::env_or_empty("HOME"));
        // The workspace: where `bazel run` was invoked, else the project dir
        // the Claude Code hook names, else the checkout the launcher lives in.
        let ws = sh::path(&{
            let mut w = sh::env_or_empty("BUILD_WORKSPACE_DIRECTORY");
            if w.is_empty() {
                w = sh::env_or_empty("CLAUDE_PROJECT_DIR");
            }
            if w.is_empty() {
                w = sh::env_or_empty("CLOUD_BOOTSTRAP_WORKSPACE");
            }
            if w.is_empty() {
                w = sh::path_str(&std::env::current_dir().unwrap_or_default()).into_bytes();
            }
            w
        });
        let state_dir = sh::path(&sh::env_or(
            "CLOUD_BOOTSTRAP_STATE_DIR",
            &format!("{home}/.config/vitruvian-core/cloud"),
        ));
        let profiles_default = sh::path_str(&ws.join("tools/cloud-bootstrap/profiles.tsv"));
        // A path, not a `bazel run` target: this runs inside a SessionStart
        // hook, where starting a Bazel server to configure Bazel would cost
        // ~25s and nest an invocation inside the one the agent is about to make.
        let cache_default = sh::path_str(&ws.join("tools/remote/setup.sh"));
        let delay_raw = sh::env_str("VITRUVIAN_ESC_RETRY_DELAY", "5");
        Ctx {
            min_credential_len: sh::env_str("MIN_CREDENTIAL_LEN", "20")
                .trim()
                .parse()
                .unwrap_or(20),
            gcloud_bin: sh::os(&sh::env_or("GCLOUD_BIN", "gcloud")).to_os_string(),
            install_dir: sh::path(&sh::env_or("CLOUD_BOOTSTRAP_INSTALL_DIR", "/usr/local/bin")),
            session_env: state_dir.join("session.env"),
            state_dir,
            bashrc: sh::path(&sh::env_or(
                "CLOUD_BOOTSTRAP_BASHRC",
                &format!("{home}/.bashrc"),
            )),
            profiles_file: sh::path(&sh::env_or("CLOUD_BOOTSTRAP_PROFILES", &profiles_default)),
            cache_setup: sh::path(&sh::env_or("CLOUD_BOOTSTRAP_CACHE_SETUP", &cache_default)),
            ws,
            esc_sa: sh::env_str(
                "VITRUVIAN_ESC_SA",
                "sa-pulumi-esc@prj-b-cicd-e096.iam.gserviceaccount.com",
            ),
            pulumi_bin: sh::os(&sh::env_or("PULUMI_BIN", "pulumi")).to_os_string(),
            esc_retries: sh::env_str("VITRUVIAN_ESC_RETRIES", "3")
                .trim()
                .parse()
                .unwrap_or(3),
            esc_retry_delay: creds::parse_delay(&delay_raw),
            esc_retry_delay_raw: delay_raw,
            auth_state: AuthState::None,
            primary_account: String::new(),
            esc_token_file: None,
            claimed: Vec::new(),
            profile_list: Vec::new(),
            tools_all: Vec::new(),
        }
    }

    fn load(&self, name: &str) -> Option<manifest::Profile> {
        manifest::load(&self.profiles_file, name)
    }

    /// establish_credentials: authenticate and materialise EVERY listed
    /// profile, each with its own identity, in list order.
    fn establish_credentials(&mut self) {
        for name in self.profile_list.clone() {
            let Some(p) = self.load(&name) else { continue };
            self.authenticate(&name, &p);
            self.materialise_secrets(&name, &p);
        }
        // AFTER every profile has claimed what it is entitled to.
        self.scrub_undeclared();
        self.wire_session_env();
        // AFTER wire_session_env, which puts a Secret-Manager-sourced
        // BUILDBUDDY_API_KEY in scope.
        self.configure_build_cache();
    }

    /// The `whoami` report, on stdout; false when a profile is unsatisfied.
    fn report(&self) -> bool {
        let mut ok = true;
        let list = if self.profile_list.is_empty() {
            "<unset>".to_string()
        } else {
            self.profile_list.join(" ")
        };
        out(&format!(
            "\nvitruvian-core cloud session — profile(s): {list}\n\ntools\n"
        ));
        for key in &self.tools_all {
            if sh::has(key) {
                let r = sh::capture(Command::new(key).arg("--version"));
                let first = sh::lines(&r.stdout).first().map(|l| sh::lossy(l));
                let ver = first.filter(|v| !v.is_empty());
                out(&format!(
                    "  ✓ {key:<10} {}\n",
                    ver.unwrap_or_else(|| "installed".to_string())
                ));
            } else {
                out(&format!("  ✗ {key:<10} not installed\n"));
                ok = false;
            }
        }

        // Reported on the BEHAVIOUR (is a plain `bazel` pointed at the cache?)
        // and as "configured", not "working": a wrong key fails silently, so
        // this line cannot promise more. Never part of the gate.
        if self.tools_all.iter().any(|t| t == "bazel") {
            if sh::file_contains(&self.ws.join("user.bazelrc"), b"--config=remotecache") {
                out(&format!(
                    "  ✓ {:<10} BuildBuddy configured for plain bazel (cache only)\n",
                    "cache"
                ));
            } else {
                out(&format!(
                    "  – {:<10} not configured — every build is cold and local\n",
                    "cache"
                ));
            }
        }

        // Per profile: which identity holds which credentials.
        for name in &self.profile_list {
            let Some(p) = self.load(name) else { continue };
            out(&format!("\n{name} — {}\n", p.purpose));

            if p.sa_account == "-" {
                out("  identity   – none (holds no credentials by design)\n");
            } else if self.gcloud_has_active(&p.sa_account) {
                let primary = if p.sa_account == self.primary_account {
                    " [primary]"
                } else {
                    ""
                };
                out(&format!(
                    "  identity   ✓ {} (project {}){primary}\n",
                    p.sa_account, p.sa_project
                ));
            } else if sh::non_empty(&self.state_dir.join(format!("esc-token-{name}"))) {
                // The keyless identity is a token file, never an activated
                // gcloud account, so the check above cannot see it.
                out(&format!(
                    "  identity   ✓ {} via Pulumi ESC (keyless; token used at session start)\n",
                    self.esc_sa
                ));
            } else {
                out(&format!(
                    "  identity   ✗ {} — not authenticated\n",
                    p.sa_account
                ));
                let last_error = self.state_dir.join("esc-last-error");
                if sh::non_empty(&last_error) {
                    let text = std::fs::read(&last_error).unwrap_or_default();
                    let why = sh::lines(&text)
                        .first()
                        .map(|l| sh::lossy(l))
                        .unwrap_or_default();
                    out(&format!("             why: {why}\n"));
                    out("             fix: bash tools/cloud-bootstrap/cloud-bootstrap.sh auth   (re-runs the ESC step)\n");
                } else if !sh::env_or_empty("PULUMI_ACCESS_TOKEN").is_empty() {
                    out("             PULUMI_ACCESS_TOKEN is set but the ESC step has not run or left no record; run: bash tools/cloud-bootstrap/cloud-bootstrap.sh auth\n");
                }
                ok = false;
            }

            if p.secrets == "-" {
                out("  creds      – none\n");
                continue;
            }
            for pair in manifest::words(&p.secrets) {
                let (var, secret) = manifest::split_pair(&pair);
                let val = if var.is_empty() {
                    Vec::new()
                } else {
                    sh::env_or_empty(&var)
                };
                // The LENGTH is the useful signal, and it leaks nothing.
                if self.is_credential(&val) {
                    out(&format!(
                        "  creds      ✓ {var:<22} set ({} bytes)\n",
                        sh::char_len(&val)
                    ));
                } else if !val.is_empty() {
                    out(&format!(
                        "  creds      ✗ {var:<22} placeholder only ({} bytes; {secret} never resolved)\n",
                        sh::char_len(&val)
                    ));
                    ok = false;
                } else {
                    out(&format!(
                        "  creds      ✗ {var:<22} missing (secret {secret})\n"
                    ));
                    ok = false;
                }
            }
        }
        out("\n");
        ok
    }

    /// `gcloud auth list --filter=... --format=value(account) | grep -q .`
    fn gcloud_has_active(&self, account: &str) -> bool {
        if which(&self.gcloud_bin).is_none() {
            return false;
        }
        let r = sh::capture(
            Command::new(&self.gcloud_bin)
                .args(["auth", "list"])
                .arg(format!("--filter=status:ACTIVE account:{account}"))
                .arg("--format=value(account)"),
        );
        r.ok && sh::lines(&r.stdout).iter().any(|l| !l.is_empty())
    }
}

fn valid_profile_name(n: &str) -> bool {
    !n.is_empty()
        && n.bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}

fn run(args: Vec<OsString>) -> i32 {
    let sub = args
        .first()
        .map(|a| a.to_string_lossy().into_owned())
        .filter(|a| !a.is_empty())
        .unwrap_or_else(|| "up".to_string());
    let rest: Vec<String> = args
        .iter()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();

    let mut profile_override = String::new();
    let mut force = false;
    let mut i = 0;
    while i < rest.len() {
        match rest[i].as_str() {
            "--profile" => {
                profile_override = rest.get(i + 1).cloned().unwrap_or_default();
                i += 2;
            }
            "--force" => {
                force = true;
                i += 1;
            }
            "-h" | "--help" => {
                out(USAGE);
                return 0;
            }
            other => {
                warn(&format!("ignoring unknown argument '{other}'"));
                i += 1;
            }
        }
    }

    let mut ctx = Ctx::from_env();

    match sub.as_str() {
        "profiles" => {
            if !sh::is_file(&ctx.profiles_file) {
                warn(&format!(
                    "profile manifest not found: {}",
                    sh::path_str(&ctx.profiles_file)
                ));
                return 1;
            }
            out("Set VITRUVIAN_PROFILE on the cloud environment to one, or several\n");
            out("comma-separated (e.g. VITRUVIAN_PROFILE=core,homelab):\n\n");
            out(&manifest::list(&ctx.profiles_file));
            return 0;
        }
        "up" | "install" | "auth" | "whoami" => {}
        other => {
            warn(&format!(
                "unknown subcommand '{other}' (expected: up, install, auth, whoami, profiles)"
            ));
            return 2;
        }
    }

    // Cloud sessions only: a local checkout already has direnv, bazel_env and
    // real gcloud credentials, and must not have a key installed over them.
    if sub != "whoami" && !force && sh::env_or_empty("CLAUDE_CODE_REMOTE") != b"true" {
        warn("not a cloud session (CLAUDE_CODE_REMOTE != true) — nothing to do.");
        note("pass --force to run this against a local checkout anyway.");
        return 0;
    }

    if !sh::is_file(&ctx.profiles_file) {
        warn(&format!(
            "profile manifest not found: {}",
            sh::path_str(&ctx.profiles_file)
        ));
        return 0;
    }

    let mut raw = profile_override;
    for var in ["VITRUVIAN_PROFILE", "CLAUDE_PROFILE"] {
        if raw.is_empty() {
            raw = sh::lossy(&sh::env_or_empty(var));
        }
    }
    if raw.is_empty() {
        warn("VITRUVIAN_PROFILE is not set on this cloud environment — nothing bootstrapped.");
        note("There is deliberately no default: a session's capability is a choice, not a");
        note("fallback. Set it to one or more (comma-separated) of:");
        eprint!("{}", manifest::list(&ctx.profiles_file));
        return 0;
    }

    // Several profiles may be combined; each keeps its OWN identity and reads
    // only its OWN secrets. Deduped in order, and each name constrained at the
    // door: it reaches variable names and messages.
    for p in manifest::words(&raw) {
        if !valid_profile_name(&p) {
            warn(&format!(
                "invalid profile name '{p}' (letters, digits, '-' and '_' only)"
            ));
            return 0;
        }
        if ctx.profile_list.contains(&p) {
            continue;
        }
        if ctx.load(&p).is_none() {
            warn(&format!("'{p}' is not a known profile. Known profiles:"));
            eprint!("{}", manifest::list(&ctx.profiles_file));
            return 0;
        }
        ctx.profile_list.push(p);
    }
    if ctx.profile_list.is_empty() {
        warn(&format!(
            "no usable profile in '{raw}' — nothing bootstrapped."
        ));
        return 0;
    }

    for name in ctx.profile_list.clone() {
        let Some(p) = ctx.load(&name) else { continue };
        for t in manifest::words(&p.tools) {
            if t != "-" && !ctx.tools_all.contains(&t) {
                ctx.tools_all.push(t);
            }
        }
    }

    match sub.as_str() {
        "install" => {
            install::Installer::new(&ctx).install_all(&ctx.tools_all);
            0
        }
        "auth" => {
            ctx.establish_credentials();
            0
        }
        "whoami" => {
            // Re-apply the session env so the report is about the session.
            if sh::is_file(&ctx.session_env) {
                sh::source_exports(&ctx.session_env);
            }
            // `whoami` does not authenticate, so recover which identity ended
            // up ambient from gcloud itself.
            if which(&ctx.gcloud_bin).is_some() {
                let r = sh::capture(Command::new(&ctx.gcloud_bin).args([
                    "config",
                    "get-value",
                    "account",
                ]));
                let acct = sh::lossy(&sh::subst(r.stdout));
                ctx.primary_account = if acct == "(unset)" {
                    String::new()
                } else {
                    acct
                };
            }
            if ctx.report() {
                0
            } else {
                1
            }
        }
        _ => {
            warn(&format!(
                "bootstrapping profile(s): {}",
                ctx.profile_list.join(" ")
            ));
            install::Installer::new(&ctx).install_all(&ctx.tools_all);
            ctx.establish_credentials();
            ctx.report();
            // Best-effort: never block the session. `whoami` is the gate.
            0
        }
    }
}

fn main() {
    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    let best_effort = matches!(
        args.first().and_then(|a| a.to_str()).unwrap_or("up"),
        "" | "up" | "install" | "auth"
    );
    let code = match std::panic::catch_unwind(|| run(args)) {
        Ok(code) => code,
        // A bug must not block the session any more than a network blip does.
        Err(_) if best_effort => {
            warn("internal error (see above) — the session continues without the rest of the bootstrap");
            0
        }
        Err(_) => 70,
    };
    std::process::exit(code);
}
