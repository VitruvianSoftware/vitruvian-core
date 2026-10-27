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

//! setup.sh in Rust: configure npm trusted publishing (OIDC) for every
//! publishable package, in one pass. See setup.sh for the why; this follows
//! it statement by statement, and the comments here only mark what the shell
//! does implicitly.

use crate::manifest;
use crate::sh::{self, errln, outln};
use std::process::{Command, Stdio};

const P: &str = "npm-trusted-publisher";

/// setup.sh's `OTP_WAIT_SECONDS="${OTP_WAIT_SECONDS:-900}"`. Kept on one line
/// in this form: the -rs test shim reads the number from here.
pub const DEFAULT_OTP_WAIT_SECONDS: &str = "900";
pub const DEFAULT_OTP_POLL_SECONDS: &str = "5";

/// Where a child's stdin comes from. Inside the main `while read ... done
/// <<EOF3` loop the script's children read the heredoc; here they read
/// nothing, which is the same thing to every npm subcommand involved.
#[derive(Clone, Copy)]
enum In {
    Inherit,
    Null,
}

impl In {
    fn stdio(self) -> Stdio {
        match self {
            In::Inherit => Stdio::inherit(),
            In::Null => Stdio::null(),
        }
    }
}

struct Ctx {
    npm: String,
    otp_wait: String,
    otp_poll: String,
    /// The script's global `_out`.
    out: Vec<u8>,
}

impl Ctx {
    fn npm(&self, args: &[&str], stdin: In) -> Command {
        let mut c = Command::new(&self.npm);
        c.args(args).stdin(stdin.stdio());
        c
    }

    /// `npm_write_with_otp`.
    fn write_with_otp(&mut self, args: &[&str]) -> bool {
        let (rc, o) = sh::capture_merged(&mut self.npm(args, In::Null));
        self.out = o;
        if rc == 0 {
            return true;
        }
        if !sh::grep_fixed(&self.out, "EOTP") {
            return false;
        }
        outln("");
        outln("npm-trusted-publisher: npm needs a one-time authentication before it");
        outln("  will accept this change. npm will print a URL below and wait --");
        outln("  open it, authenticate, and CHOOSE \"skip for the next 5 minutes\".");
        outln("  That covers every package in this run, so you only do this once.");
        outln("");
        let tty = sh::env_or("NPM_TP_TTY_PATH", "/dev/tty");
        if sh::can_access(&tty, sh::R_OK) && sh::can_access(&tty, sh::W_OK) {
            // `npm ... <"$_tty" >"$_tty" 2>&1`: open for reading, then for
            // writing (truncating), in that order; a failed open is bash's
            // redirection error and the command does not run.
            let opened = std::fs::File::open(&tty).and_then(|r| {
                std::fs::OpenOptions::new()
                    .write(true)
                    .create(true)
                    .truncate(true)
                    .open(&tty)
                    .map(|w| (r, w))
            });
            match opened.and_then(|(r, w)| w.try_clone().map(|w2| (r, w, w2))) {
                Ok((r, w, w2)) => {
                    let mut c = Command::new(&self.npm);
                    c.args(args)
                        .stdin(Stdio::from(r))
                        .stdout(Stdio::from(w))
                        .stderr(Stdio::from(w2));
                    if sh::run_inherit(&mut c) == 0 {
                        self.out.clear();
                        return true;
                    }
                }
                Err(e) => errln(&format!("{}: {}: {}", P, tty, sh::strerror(&e))),
            }
        } else if sh::run_inherit(&mut self.npm(args, In::Null)) == 0 {
            self.out.clear();
            return true;
        }
        // Poll the same call, captured again, in case the browser
        // authentication lands a moment later.
        let mut waited: i64 = 0;
        while sh::test_lt(P, &waited.to_string(), &self.otp_wait) {
            sh::sleep(&self.otp_poll);
            waited += sh::parse_int(&self.otp_poll).unwrap_or(0);
            let (rc, o) = sh::capture_merged(&mut self.npm(args, In::Null));
            self.out = o;
            if rc == 0 {
                return true;
            }
            if !sh::grep_fixed(&self.out, "EOTP") {
                return false;
            }
        }
        false
    }

    /// `$(printf '%s' "$_out" | grep -i 'npm error' | head -2 | tr '\n' ' ')`.
    fn npm_error_excerpt(&self) -> String {
        let mut s = Vec::new();
        for l in sh::grep_i_lines(&self.out, "npm error").into_iter().take(2) {
            s.extend_from_slice(l);
            s.push(b' ');
        }
        String::from_utf8_lossy(&s).into_owned()
    }
}

/// `"$1" trust github --help 2>/dev/null | grep -q -- '--allow-publish'`,
/// under `pipefail`: npm must also exit 0.
fn npm_can_trust(npm: &str) -> bool {
    let (rc, o) = sh::capture(
        Command::new(npm)
            .args(["trust", "github", "--help"])
            .stdin(Stdio::inherit()),
        false,
    );
    rc == 0 && sh::grep_fixed(&o, "--allow-publish")
}

/// `$("$npm" --version 2>/dev/null)`.
fn npm_version(npm: &str) -> String {
    let (_, o) = sh::capture(
        Command::new(npm).arg("--version").stdin(Stdio::inherit()),
        false,
    );
    String::from_utf8_lossy(&o).into_owned()
}

fn quiet_ok(npm: &str, args: &[&str], stdin: In) -> bool {
    let mut c = Command::new(npm);
    c.args(args).stdin(stdin.stdio());
    sh::run_quiet(&mut c) == 0
}

/// `mirror_for`: the MIRROR repository that publishes a manifest.
pub fn mirror_for(mf: &str) -> &'static str {
    let any = |ps: &[&str]| ps.iter().any(|p| mf.starts_with(p));
    if any(&[
        "packages/pulumi/library/ts/packages/",
        "pulumi/library/ts/packages/",
    ]) {
        "VitruvianSoftware/pulumi-library"
    } else if any(&["apps/mcp/slack/", "mcp-slack/"]) {
        "VitruvianSoftware/mcp-slack"
    } else if any(&[
        "packages/vitruvian-sdk/kits/typescript/",
        "vitruvian-sdk/kits/typescript/",
    ]) {
        "VitruvianSoftware/vitruvian-sdk"
    } else {
        ""
    }
}

/// The folders searched when no NPM_TP_PACKAGES list is given, in order;
/// only those that are directories (`[ -d ]` follows links).
pub fn search_dirs() -> Vec<String> {
    [
        "packages/pulumi/library/ts/packages",
        "pulumi/library/ts/packages",
        "apps/mcp/slack",
        "mcp-slack",
        "packages/vitruvian-sdk/kits/typescript",
        "vitruvian-sdk/kits/typescript",
    ]
    .iter()
    .filter(|d| std::path::Path::new(d).is_dir())
    .map(|d| d.to_string())
    .collect()
}

fn lossy(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// setup.sh. Returns the exit code.
pub fn main(args: &[String]) -> i32 {
    if sh::cd_workspace(P).is_err() {
        return 1;
    }
    let mut npm = sh::env_or("NPM", "npm");
    let delay = sh::env_or("DELAY_SECONDS", "2");
    let workflow_file = sh::env_or("WORKFLOW_FILE", "release.yml");
    let otp_wait = sh::env_or("OTP_WAIT_SECONDS", DEFAULT_OTP_WAIT_SECONDS);
    let otp_poll = sh::env_or("OTP_POLL_SECONDS", DEFAULT_OTP_POLL_SECONDS);
    let (mut dry_run, mut no_login, mut harden) = (false, false, false);
    for a in args {
        match a.as_str() {
            "--dry-run" => dry_run = true,
            "--harden" => harden = true,
            "--no-login" => no_login = true,
            _ => {
                errln(&format!("{}: unknown flag: {}", P, a));
                return 2;
            }
        }
    }

    if sh::command_v(&npm).is_none() {
        errln("npm-trusted-publisher: npm not on PATH");
        return 2;
    }
    // Probe for the CAPABILITY (`--allow-publish`), and pick an npm that has it.
    if sh::env_set("NPM_EXPLICIT") || npm != "npm" {
        if !npm_can_trust(&npm) {
            errln(&format!(
                "{}: {} ({}) does not support",
                P,
                npm,
                npm_version(&npm)
            ));
            errln("  `npm trust github --allow-publish`. Upgrade it, or unset NPM to let this");
            errln("  script pick a capable npm from PATH.");
            return 2;
        }
    } else {
        let cands = sh::words(&sh::type_ap("npm").join("\n"));
        let picked = cands.iter().find(|c| npm_can_trust(c)).cloned();
        let picked = match picked {
            Some(p) => p,
            None => {
                errln("npm-trusted-publisher: no npm on PATH supports `trust github --allow-publish`.");
                errln("  Found:");
                for c in &cands {
                    errln(&format!("    {} ({})", c, npm_version(c)));
                }
                errln("  Upgrade npm (>= 11.19.0 is known good), or set NPM=/path/to/npm.");
                return 2;
            }
        };
        let first = sh::command_v("npm").unwrap_or_default();
        if picked != first {
            outln(&format!(
                "{}: using {} ({});",
                P,
                picked,
                npm_version(&picked)
            ));
            outln(&format!(
                "  the first npm on PATH ({}) lacks --allow-publish.",
                first
            ));
        }
        npm = picked;
    }

    // ensure_login
    if !quiet_ok(&npm, &["whoami"], In::Inherit) {
        if no_login {
            errln("npm-trusted-publisher: not logged in and --no-login was passed.");
            errln("  Run: npm login");
            return 2;
        }
        // `(: </dev/tty)`: actually OPEN it; NPM_TP_TTY_OK is the test seam.
        if !sh::env_set("NPM_TP_TTY_OK") && std::fs::File::open("/dev/tty").is_err() {
            errln("npm-trusted-publisher: the npm CLI is not logged in, and there is no");
            errln("  terminal to authenticate on. Run `npm login` first, then re-run.");
            return 2;
        }
        outln("npm-trusted-publisher: the npm CLI is not logged in -- starting `npm login`.");
        outln("  It opens your browser; authenticate there. Nothing is typed or stored here.");
        if sh::run_inherit(Command::new(&npm).arg("login")) != 0 {
            errln("npm-trusted-publisher: `npm login` did not complete.");
            return 2;
        }
        if !quiet_ok(&npm, &["whoami"], In::Inherit) {
            errln("npm-trusted-publisher: still not authenticated after `npm login`.");
            return 2;
        }
    }
    let (_, who) = sh::capture(
        Command::new(&npm).arg("whoami").stdin(Stdio::inherit()),
        false,
    );
    outln(&format!("{}: authenticated as {}", P, lossy(&who)));

    let mut ctx = Ctx {
        npm: npm.clone(),
        otp_wait,
        otp_poll,
        out: Vec::new(),
    };

    // The caller's list, when there is one: every row checked first.
    let list_path = std::env::var("NPM_TP_PACKAGES").unwrap_or_default();
    let mut listed: Vec<u8> = Vec::new();
    let mut list_data: Vec<u8> = Vec::new();
    if !list_path.is_empty() {
        if !sh::can_access(&list_path, sh::R_OK) {
            errln(&format!(
                "{}: NPM_TP_PACKAGES={} cannot be read",
                P, list_path
            ));
            return 2;
        }
        list_data = match std::fs::read(&list_path) {
            Ok(d) => d,
            Err(e) => {
                errln(&format!(
                    "{}: {}: read error: {}",
                    P,
                    list_path,
                    sh::strerror(&e)
                ));
                Vec::new()
            }
        };
        for line in sh::read_loop_lines(&list_data) {
            let f = sh::read_tab_fields(line, 4);
            if f[0].is_empty() {
                continue;
            }
            let mf = lossy(&f[0]);
            if f[1].is_empty() || f[2].is_empty() || !f[3].is_empty() {
                errln(&format!("{}: {}: the row for {} is not", P, list_path, mf));
                errln("  manifest<TAB>owner/repo<TAB>workflow file");
                return 2;
            }
            if !std::path::Path::new(&mf).is_file() {
                errln(&format!(
                    "{}: {} names {}, which is not there",
                    P, list_path, mf
                ));
                return 2;
            }
            listed.extend_from_slice(&f[0]);
            listed.push(b'\n');
        }
        if listed.is_empty() {
            errln(&format!("{}: {} names no packages", P, list_path));
            return 2;
        }
    }

    // `manifests`, then the heredoc adds its own final newline.
    let mut manifests: Vec<u8> = if !listed.is_empty() {
        listed.clone()
    } else {
        let dirs = search_dirs();
        if dirs.is_empty() {
            Vec::new()
        } else {
            sh::find_manifests(&dirs).join("\n").into_bytes()
        }
    };
    if manifests.is_empty() {
        errln("npm-trusted-publisher: found no package manifests -- the layout moved");
        return 2;
    }
    manifests.push(b'\n');

    let (mut configured, mut skipped, mut failed, mut unpublished) = (0u64, 0u64, 0u64, 0u64);
    for mf_b in sh::read_loop_lines(&manifests) {
        if mf_b.is_empty() {
            continue;
        }
        let mf = lossy(mf_b);
        let line = match manifest::load_dict(&mf) {
            Ok(d) => manifest::name_private_line(&d),
            Err(e) => {
                errln(&e);
                Vec::new()
            }
        };
        let f = sh::read_fields(&line, 2);
        let name = lossy(&f[0]);
        if name.is_empty() || f[1] != b"false" {
            continue;
        }
        if !quiet_ok(&npm, &["view", &name, "version"], In::Null) {
            outln(&format!(
                "  -- {} is not on the registry yet; publish it once, then re-run",
                name
            ));
            unpublished += 1;
            continue;
        }
        if harden {
            if dry_run {
                outln(&format!("  DRY_RUN {} -> mfa=publish", name));
                configured += 1;
                continue;
            }
            if ctx.write_with_otp(&["access", "set", "mfa=publish", &name]) {
                outln(&format!(
                    "  + {} -> mfa=publish (2FA required, tokens cannot bypass)",
                    name
                ));
                configured += 1;
            } else {
                errln(&format!("  ✗ {} -- {}", name, ctx.npm_error_excerpt()));
                failed += 1;
                if sh::grep_fixed(&ctx.out, "EOTP") {
                    break;
                }
            }
            let rc = sh::sleep(&delay);
            if rc != 0 {
                return rc;
            }
            continue;
        }

        let (repo, workflow) = if !listed.is_empty() {
            (
                lossy(&sh::awk_tab_field(&list_data, &mf, 2)),
                lossy(&sh::awk_tab_field(&list_data, &mf, 3)),
            )
        } else {
            (mirror_for(&mf).to_string(), workflow_file.clone())
        };
        if repo.is_empty() {
            errln(&format!(
                "  ?? {} -- no mirror mapping for {}; skipping",
                name, mf
            ));
            failed += 1;
            continue;
        }

        // Already configured? `npm trust list "$name" 2>/dev/null | grep -q "$workflow"`
        // under pipefail: npm must succeed AND a line must match.
        let (rc, listing) = sh::capture(&mut ctx.npm(&["trust", "list", &name], In::Null), false);
        if sh::grep_q_bre(&listing, &workflow) && rc == 0 {
            outln(&format!("  ok {} (already configured)", name));
            skipped += 1;
            continue;
        }

        if dry_run {
            outln(&format!("  DRY_RUN {} -> {} {}", name, repo, workflow));
            configured += 1;
            continue;
        }

        let ok = ctx.write_with_otp(&[
            "trust",
            "github",
            &name,
            "--repo",
            &repo,
            "--file",
            &workflow,
            "--allow-publish",
            "--yes",
        ]);
        if ok {
            outln(&format!("  + {} -> {} {}", name, repo, workflow));
            configured += 1;
        } else if sh::lines(&ctx.out).iter().any(|l| {
            let l = l.to_ascii_lowercase();
            sh::contains(&l, b"already exists")
                || sh::contains(&l, b"already configured")
                || sh::contains(&l, b"duplicate")
        }) {
            outln(&format!("  ok {} (already configured)", name));
            skipped += 1;
        } else if sh::grep_fixed(&ctx.out, "EOTP") {
            errln(&format!(
                "  ✗ {} -- gave up waiting for two-factor authentication.",
                name
            ));
            errln("    Complete the browser authentication, then re-run; configured");
            errln("    packages are skipped, so it resumes where it stopped.");
            failed += 1;
            break;
        } else {
            errln(&format!("  ✗ {} -- {}", name, ctx.npm_error_excerpt()));
            failed += 1;
        }
        let rc = sh::sleep(&delay);
        if rc != 0 {
            return rc;
        }
    }

    if harden {
        outln(&format!(
            "npm-trusted-publisher: {} set to mfa=publish, {} failed, {} not yet on the registry.",
            configured, failed, unpublished
        ));
    } else {
        outln(&format!(
            "npm-trusted-publisher: {} configured, {} already set, {} failed, {} not yet on the registry.",
            configured, skipped, failed, unpublished
        ));
    }
    if unpublished > 0 {
        errln(&format!(
            "  The {} unpublished package(s) cannot be configured until they exist on npm.",
            unpublished
        ));
        errln("  Trusted publishing attaches to a PACKAGE, so each needs one first publish.");
    }
    if failed > 0 {
        errln("  Re-run after fixing; already-configured packages are skipped, so this is safe to repeat.");
        return 1;
    }
    outln("  Verify with: bazel run //tools/npm-publish-audit:check");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_wait_matches_the_script() {
        assert_eq!(DEFAULT_OTP_WAIT_SECONDS, "900");
        assert_eq!(DEFAULT_OTP_POLL_SECONDS, "5");
    }

    #[test]
    fn mirrors() {
        assert_eq!(
            mirror_for("pulumi/library/ts/packages/a/package.json"),
            "VitruvianSoftware/pulumi-library"
        );
        assert_eq!(
            mirror_for("mcp-slack/package.json"),
            "VitruvianSoftware/mcp-slack"
        );
        assert_eq!(
            mirror_for("vitruvian-sdk/kits/typescript/package.json"),
            "VitruvianSoftware/vitruvian-sdk"
        );
        assert_eq!(mirror_for("somewhere/package.json"), "");
    }
}
