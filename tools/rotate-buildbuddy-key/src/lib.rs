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

//! rotate-buildbuddy-key: the guided BuildBuddy API-key rotation (issue
//! #456), a port of rotate.sh. Automates the non-secret steps and prompts the
//! operator for the two that need a human (mint the new key, revoke the old
//! one). The new value is read without echo and handed to `gh secret set` on
//! its stdin -- never printed, logged, or put on a command line -- and
//! dropped straight after.
//!
//! Held to the script by rotate_buildbuddy_key_rs_parity_test.py: same exit
//! codes, stdout, stderr, prompts, and gh / open / sleep calls.

use std::fs;
use std::process::{Command, Stdio};

use shell_compat as sh;

const REPO: &str = "VitruvianSoftware/vitruvian-core";
const SECRET: &str = "BUILDBUDDY_API_KEY";
const CONSOLE: &str = "https://app.buildbuddy.io/settings/org/api-keys";

const LINE_SECRET_SET: u32 = 109;
const LINE_SECRET_SET_DEPENDABOT: u32 = 110;
const LINE_SLEEP: u32 = 124;

/// The colours, set when stdout is a terminal (`[ -t 1 ]`), empty otherwise.
pub struct Style {
    pub bold: &'static str,
    pub dim: &'static str,
    pub reset: &'static str,
    pub green: &'static str,
    pub yellow: &'static str,
    pub cyan: &'static str,
    pub red: &'static str,
}

impl Style {
    pub fn new(tty: bool) -> Style {
        if tty {
            Style {
                bold: "\x1b[1m",
                dim: "\x1b[2m",
                reset: "\x1b[0m",
                green: "\x1b[32m",
                yellow: "\x1b[33m",
                cyan: "\x1b[36m",
                red: "\x1b[31m",
            }
        } else {
            Style {
                bold: "",
                dim: "",
                reset: "",
                green: "",
                yellow: "",
                cyan: "",
                red: "",
            }
        }
    }
}

/// `case "${reply:-}" in y|Y|yes|YES)`.
pub fn is_yes(reply: &[u8]) -> bool {
    matches!(reply, b"y" | b"Y" | b"yes" | b"YES")
}

/// `grep -qE '^[[:space:]]*(buildbuddyApiKey[[:space:]]*:|secure:)'` on
/// one line: a committed key value, not a comment that names it.
pub fn commits_key(line: &[u8]) -> bool {
    let is_space = |c: &u8| matches!(c, b' ' | b'\t' | b'\n' | b'\x0b' | b'\x0c' | b'\r');
    let rest: &[u8] = {
        let n = line.iter().take_while(|c| is_space(c)).count();
        &line[n..]
    };
    if rest.starts_with(b"secure:") {
        return true;
    }
    if let Some(after) = rest.strip_prefix(b"buildbuddyApiKey".as_slice()) {
        let n = after.iter().take_while(|c| is_space(c)).count();
        return after[n..].starts_with(b":");
    }
    false
}

/// What `case "${st}" in completed/success) ... completed/*) ...` decides.
#[derive(Debug, PartialEq)]
pub enum Poll {
    Green,
    Failed,
    Pending,
}

pub fn classify(st: &[u8]) -> Poll {
    if st == b"completed/success" {
        Poll::Green
    } else if st.starts_with(b"completed/") {
        Poll::Failed
    } else {
        Poll::Pending
    }
}

struct Ui {
    s: Style,
}

impl Ui {
    fn ok(&self, m: &str) {
        sh::out(format!("  {}✓{} {}\n", self.s.green, self.s.reset, m).as_bytes());
    }
    fn ok_b(&self, m: &[u8]) {
        sh::out(&sh::cat(&[
            format!("  {}✓{} ", self.s.green, self.s.reset).as_bytes(),
            m,
            b"\n",
        ]));
    }
    fn warn(&self, m: &str) {
        sh::out(format!("  {}!{} {}\n", self.s.yellow, self.s.reset, m).as_bytes());
    }
    fn err(&self, m: &str) {
        sh::err(format!("  {}✗{} {}\n", self.s.red, self.s.reset, m).as_bytes());
    }
    fn err_b(&self, m: &[u8]) {
        sh::err(&sh::cat(&[
            format!("  {}✗{} ", self.s.red, self.s.reset).as_bytes(),
            m,
            b"\n",
        ]));
    }
    fn auto(&self, m: &[u8]) {
        sh::out(&sh::cat(&[
            format!("{}[auto]{} ", self.s.dim, self.s.reset).as_bytes(),
            m,
            b"\n",
        ]));
    }
    fn step(&self, m: &str) {
        sh::out(
            format!(
                "\n{}──{} {}{}{}\n",
                self.s.cyan, self.s.reset, self.s.bold, m, self.s.reset
            )
            .as_bytes(),
        );
    }
    fn you(&self, m: &str) {
        sh::out(format!("{}[you]{}  {}\n", self.s.yellow, self.s.reset, m).as_bytes());
    }
    /// `ask`: the prompt, one `read -r` line; yes or not. Called only where
    /// errexit is off, so end of input is just "no" (or what was read).
    fn ask(&self, m: &str) -> bool {
        sh::out(format!("{}?{} {} [y/N] ", self.s.cyan, self.s.reset, m).as_bytes());
        let (line, _) = sh::read_stdin_line();
        is_yes(&sh::read_trim(&line))
    }
    /// `pause`: the prompt and a `read -r _`, whose failure at end of input
    /// ends the script (errexit) with status 1.
    fn pause(&self, m: &str) -> Result<(), i32> {
        sh::out(format!("{}↵{} {}", self.s.cyan, self.s.reset, m).as_bytes());
        match sh::read_stdin_line() {
            (_, true) => Ok(()),
            (_, false) => Err(1),
        }
    }
}

/// `"$(cmd 2>/dev/null)"`, stdin inherited: stdout and status.
fn quiet_capture(c: &mut Command) -> (i32, Vec<u8>) {
    c.stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    match c.output() {
        Ok(o) => (sh::status_code(o.status), o.stdout),
        Err(e) => (sh::spawn_failure_status(&e), Vec::new()),
    }
}

/// `cmd >/dev/null 2>&1`: the status.
fn quiet_status(c: &mut Command) -> i32 {
    c.stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    match c.status() {
        Ok(st) => sh::status_code(st),
        Err(e) => sh::spawn_failure_status(&e),
    }
}

fn gh(args: &[&str]) -> Command {
    let mut c = Command::new("gh");
    c.args(args);
    c
}

/// `pwd`: $PWD when it names the current directory, else the resolved path.
fn pwd() -> Vec<u8> {
    let cwd = std::env::current_dir().ok();
    if let (Some(p), Some(cwd)) = (sh::env("PWD"), cwd.as_ref()) {
        if p.starts_with(b"/") {
            if let (Ok(a), Ok(b)) = (fs::canonicalize(sh::path(&p)), fs::canonicalize(cwd)) {
                if a == b {
                    return p;
                }
            }
        }
    }
    cwd.map(|c| sh::path_bytes(&c)).unwrap_or_default()
}

/// The whole tool; the exit status.
pub fn run() -> i32 {
    match rotate(Ui {
        s: Style::new(sh::stdout_is_tty()),
    }) {
        Ok(()) => 0,
        Err(code) => code,
    }
}

fn rotate(ui: Ui) -> Result<(), i32> {
    let s = &ui.s;
    sh::out(
        format!(
            "\n{}{} BuildBuddy API-key rotation {}  (issue #456)\n",
            s.bold, s.cyan, s.reset
        )
        .as_bytes(),
    );
    sh::out(
        format!(
            "{}The engineering is already done — the key is out of git and read from env.\n",
            s.dim
        )
        .as_bytes(),
    );
    sh::out(
        format!(
            "This only rotates the secret value. Old key stays live until the new one is verified.{}\n",
            s.reset
        )
        .as_bytes(),
    );

    // ---- 0. preflight ----
    ui.step("0. Preflight");
    if sh::which(b"gh").is_none() {
        ui.err("gh CLI not found — install it and re-run.");
        return Err(1);
    }
    if quiet_status(&mut gh(&["auth", "status"])) == 0 {
        let (st, mut login) = quiet_capture(&mut gh(&["api", "user", "--jq", ".login"]));
        if st != 0 {
            login.extend_from_slice(b"?\n");
        }
        ui.ok_b(&sh::cat(&[b"gh authenticated (", &sh::subst(login), b")"]));
    } else {
        ui.err("gh not authenticated — run 'gh auth login'.");
        return Err(1);
    }

    let repo_root = match sh::env("BUILD_WORKSPACE_DIRECTORY") {
        Some(r) if !r.is_empty() => r,
        _ => {
            let (st, mut out) =
                quiet_capture(Command::new("git").args(["rev-parse", "--show-toplevel"]));
            if st != 0 {
                out.extend_from_slice(&pwd());
                out.push(b'\n');
            }
            sh::subst(out)
        }
    };
    let devyaml = sh::cat(&[
        &repo_root,
        b"/infrastructure/pulumi/platform/repo_config/Pulumi.dev.yaml",
    ]);
    let committed = sh::is_file(&devyaml)
        && match fs::read(sh::path(&devyaml)) {
            Ok(d) => d.split(|&c| c == b'\n').any(commits_key),
            Err(e) => {
                sh::err(&sh::cat(&[
                    b"grep: ",
                    &devyaml,
                    b": ",
                    sh::strerror(&e).as_bytes(),
                    b"\n",
                ]));
                false
            }
        };
    if committed {
        ui.warn("repo_config/Pulumi.dev.yaml still commits a buildbuddyApiKey value — expected it de-committed (#456 code half). Continuing.");
    } else {
        ui.ok("no committed BuildBuddy key in repo_config (#456 code half is in)");
    }

    let secret_path = format!("repos/{}/actions/secrets/{}", REPO, SECRET);
    if quiet_status(&mut gh(&["api", &secret_path])) == 0 {
        let (_, updated) = quiet_capture(&mut gh(&["api", &secret_path, "--jq", ".updated_at"]));
        ui.ok_b(&sh::cat(&[
            format!("current Actions secret {} exists (", SECRET).as_bytes(),
            &sh::subst(updated),
            b")",
        ]));
    } else {
        ui.warn(&format!(
            "Actions secret {} not found — this run will create it.",
            SECRET
        ));
    }

    // ---- 1. mint the new key ----
    ui.step("1. Mint a new key in the BuildBuddy console");
    ui.you(&format!(
        "Open:            {}{}{}",
        s.bold, CONSOLE, s.reset
    ));
    ui.you(&format!(
        "Click:           {}Create new API key{} (org-level; same capabilities as the current one).",
        s.bold, s.reset
    ));
    ui.you("Copy the value.  Leave the OLD key ALIVE for now — we revoke it at the end.");
    if sh::which(b"open").is_some() && ui.ask("Open the BuildBuddy console in your browser now?") {
        quiet_status(Command::new("open").arg(CONSOLE));
    }
    ui.pause("Press Enter once you have the new key copied…")?;

    // ---- 2. set the secret ----
    ui.step("2. Store the new key (read silently — never printed or logged)");
    ui.you("Paste the new key at the prompt. Input is hidden; it goes straight to");
    ui.you("'gh secret set' over stdin (never on a command line) and is cleared after.");
    sh::out(format!("{}?{} New {} value: ", s.cyan, s.reset, SECRET).as_bytes());
    let stdin_tty = fs::File::open("/dev/stdin").ok();
    let mut key = sh::with_echo_off(stdin_tty.as_ref(), || {
        let (line, _) = sh::read_stdin_line();
        sh::read_trim(&line)
    });
    sh::out(b"\n");
    if key.is_empty() {
        ui.err("empty value — aborting; nothing changed.");
        return Err(1);
    }
    // stdin, not argv: the value never appears in the process list.
    let mut c = gh(&["secret", "set", SECRET, "--repo", REPO]);
    if sh::status_with_input(LINE_SECRET_SET, &mut c, &key, false) == 0 {
        ui.ok(&format!("set Actions secret {}", SECRET));
    }
    let mut c = gh(&[
        "secret",
        "set",
        SECRET,
        "--repo",
        REPO,
        "--app",
        "dependabot",
    ]);
    if sh::status_with_input(LINE_SECRET_SET_DEPENDABOT, &mut c, &key, false) == 0 {
        ui.ok(&format!("set Dependabot secret {}", SECRET));
    }
    // unset key
    for b in key.iter_mut() {
        *b = 0;
    }
    drop(key);
    ui.ok("secret updated in both scopes (Actions + Dependabot); local value cleared");

    // ---- 3. verify ----
    ui.step("3. Verify the new key before revoking the old one");
    ui.you("A build must authenticate to BuildBuddy RBE with the NEW key and go green.");
    if ui.ask("Re-run the latest CI on main now and wait for it to pass? (takes several minutes)") {
        let (_, runid) = quiet_capture(&mut gh(&[
            "run",
            "list",
            "--repo",
            REPO,
            "--workflow",
            "ci.yaml",
            "--branch",
            "main",
            "--limit",
            "1",
            "--json",
            "databaseId",
            "--jq",
            ".[0].databaseId",
        ]));
        let runid = sh::subst(runid);
        if !runid.is_empty() {
            ui.auto(&sh::cat(&[
                b"re-running CI run ",
                &runid,
                " with the new key…".as_bytes(),
            ]));
            let mut c = gh(&["run", "rerun"]);
            c.arg(sh::os(&runid)).args(["--repo", REPO]);
            if quiet_status(&mut c) != 0 {
                ui.warn(
                    "could not trigger rerun (permissions?) — verify a build manually instead.",
                );
            }
            ui.auto(b"polling (Ctrl-C to stop waiting; the rerun keeps going)\xe2\x80\xa6");
            for _ in 0..40 {
                let st = sh::status(LINE_SLEEP, Command::new("sleep").arg("30"), false);
                if st != 0 {
                    return Err(st);
                }
                let mut c = gh(&["run", "view"]);
                c.arg(sh::os(&runid)).args([
                    "--repo",
                    REPO,
                    "--json",
                    "status,conclusion",
                    "--jq",
                    ".status+\"/\"+(.conclusion//\"-\")",
                ]);
                let (code, mut out) = quiet_capture(&mut c);
                if code != 0 {
                    out.extend_from_slice(b"?\n");
                }
                let st = sh::subst(out);
                ui.auto(&sh::cat(&[b"CI: ", &st]));
                match classify(&st) {
                    Poll::Green => {
                        ui.ok("verification build GREEN — the new key works.");
                        break;
                    }
                    Poll::Failed => {
                        ui.err_b(&sh::cat(&[
                            b"verification build did NOT pass (",
                            &st,
                            b"). Do NOT revoke the old key; investigate.",
                        ]));
                        return Err(1);
                    }
                    Poll::Pending => {}
                }
            }
        } else {
            ui.warn("no recent CI run found to re-run — push any change or dispatch a build, then confirm it is green.");
        }
    } else {
        ui.you("Verify manually: confirm the next CI build on main is green before step 4.");
    }

    // ---- 4. revoke the old key ----
    ui.step("4. Revoke the OLD key (only after the new one is verified green)");
    ui.you(&format!(
        "Back in {}{}{}, delete the PREVIOUS key so it can no longer be used",
        s.bold, CONSOLE, s.reset
    ));
    ui.you("(the value that was in git history).");
    ui.pause("Press Enter once the old key is revoked…")?;

    ui.step("Done");
    ui.ok("BuildBuddy key rotated: new value set (Actions + Dependabot), old key revoked.");
    sh::out(
        format!(
            "  Close it out:  {}gh issue close 456 -R {} -c \"rotated + revoked; env-only, no key in git\"{}\n",
            s.dim, REPO, s.reset
        )
        .as_bytes(),
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn yes_answers() {
        for y in ["y", "Y", "yes", "YES"] {
            assert!(is_yes(y.as_bytes()), "{}", y);
        }
        for n in ["", "n", "Yes", "yy", " y"] {
            assert!(!is_yes(n.as_bytes()), "{:?}", n);
        }
    }

    #[test]
    fn committed_key_lines_only() {
        assert!(commits_key(b"  buildbuddyApiKey: abc"));
        assert!(commits_key(b"buildbuddyApiKey :x"));
        assert!(commits_key(b"\tsecure: AAAA"));
        assert!(commits_key(b"secure:"));
        assert!(!commits_key(b"# buildbuddyApiKey: comes from env"));
        assert!(!commits_key(b"  buildbuddyApiKeyX: 1"));
        assert!(!commits_key(b"  config:"));
        assert!(!commits_key(b"x secure: 1"));
    }

    #[test]
    fn poll_states() {
        assert_eq!(classify(b"completed/success"), Poll::Green);
        assert_eq!(classify(b"completed/failure"), Poll::Failed);
        assert_eq!(classify(b"completed/"), Poll::Failed);
        assert_eq!(classify(b"in_progress/-"), Poll::Pending);
        assert_eq!(classify(b"?"), Poll::Pending);
        assert_eq!(classify(b"completed"), Poll::Pending);
    }

    #[test]
    fn plain_style_when_not_a_tty() {
        let s = Style::new(false);
        assert_eq!(s.bold, "");
        assert_eq!(Style::new(true).red, "\x1b[31m");
    }
}
