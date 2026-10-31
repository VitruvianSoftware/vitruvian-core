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

//! create-app: one-time GitHub App Manifest-flow bootstrap.

use std::io::Write;
use std::process::{Command, Stdio};

use crate::tools::{command_on_path, exit_code};

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

fn capture_stdout_raw(program: &str, args: &[&str]) -> Option<String> {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
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

fn prompt_read_secret(prompt: &str) -> Option<String> {
    let tty = stdin_is_tty();
    // Saved BEFORE echo goes off, so Ctrl-C (or a kill) at the prompt can
    // put the terminal back as it was instead of leaving it silent.
    let guard = if tty { term::EchoGuard::save() } else { None };
    if tty {
        let _ = std::io::stderr().write_all(prompt.as_bytes());
        let _ = std::io::stderr().flush();
        let _ = Command::new("stty")
            .arg("-echo")
            .stdin(Stdio::inherit())
            .stderr(Stdio::null())
            .status();
    }
    let mut line = String::new();
    let result = std::io::stdin().read_line(&mut line);
    if guard.is_some() {
        drop(guard);
    } else if tty {
        let _ = Command::new("stty")
            .arg("echo")
            .stdin(Stdio::inherit())
            .stderr(Stdio::null())
            .status();
    }
    println!();
    match result {
        Ok(0) => None,
        // `read -rs` with the default IFS strips surrounding blanks.
        Ok(_) => Some(
            line.trim_end_matches('\n')
                .trim_end_matches('\r')
                .trim_matches(|c: char| c == ' ' || c == '\t')
                .to_string(),
        ),
        Err(_) => None,
    }
}

/// Terminal settings saved and put back around the hidden token prompt,
/// with the C library std already links (no crate).
mod term {
    use std::os::raw::c_int;
    use std::ptr::{addr_of, addr_of_mut};

    extern "C" {
        fn tcgetattr(fd: c_int, t: *mut u8) -> c_int;
        fn tcsetattr(fd: c_int, action: c_int, t: *const u8) -> c_int;
        fn signal(sig: c_int, handler: usize) -> usize;
        fn raise(sig: c_int) -> c_int;
    }

    const TCSANOW: c_int = 0;
    const SIG_DFL: usize = 0;
    const SIG_IGN: usize = 1;
    const SIG_ERR: usize = usize::MAX;
    /// SIGHUP, SIGINT, SIGQUIT, SIGTERM: the same numbers on macOS and Linux.
    const SIGNALS: [c_int; 4] = [1, 2, 3, 15];

    /// stdin's `struct termios`, as opaque bytes (72 on macOS, 60 on glibc;
    /// this is larger and 8-aligned), so no field layout is assumed. Written
    /// once before any handler is installed, then only read.
    static mut SAVED: [u64; 32] = [0; 32];

    /// Put stdin's terminal back, then die of the same signal with its
    /// default action, so the exit still reads as an interrupt. tcsetattr,
    /// signal and raise are all async-signal-safe.
    extern "C" fn on_signal(sig: c_int) {
        // SAFETY: SAVED was fully written before this handler was installed.
        unsafe {
            tcsetattr(0, TCSANOW, addr_of!(SAVED) as *const u8);
            signal(sig, SIG_DFL);
            raise(sig);
        }
    }

    pub struct EchoGuard {
        prev: [Option<usize>; 4],
    }

    impl EchoGuard {
        /// None when stdin's settings cannot be read (not a terminal).
        pub fn save() -> Option<EchoGuard> {
            // SAFETY: SAVED is larger than struct termios; nothing reads it
            // until a handler is installed below.
            if unsafe { tcgetattr(0, addr_of_mut!(SAVED) as *mut u8) } != 0 {
                return None;
            }
            let mut prev = [None; 4];
            for (slot, &sig) in prev.iter_mut().zip(SIGNALS.iter()) {
                // SAFETY: installing a handler that only calls
                // async-signal-safe functions.
                let p = unsafe { signal(sig, on_signal as usize) };
                if p == SIG_IGN {
                    // An ignored signal (e.g. run in the background) stays ignored.
                    unsafe { signal(sig, SIG_IGN) };
                } else if p != SIG_ERR {
                    *slot = Some(p);
                }
            }
            Some(EchoGuard { prev })
        }
    }

    impl Drop for EchoGuard {
        fn drop(&mut self) {
            // SAFETY: SAVED holds what tcgetattr returned in save().
            unsafe { tcsetattr(0, TCSANOW, addr_of!(SAVED) as *const u8) };
            for (p, &sig) in self.prev.iter().zip(SIGNALS.iter()) {
                if let Some(h) = p {
                    unsafe { signal(sig, *h) };
                }
            }
        }
    }
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

fn json_field(obj: &crate::json::Value, key: &str) -> String {
    match obj.get(key) {
        Some(crate::json::Value::Null) | None => String::new(),
        Some(v) => v.py_str(),
    }
}

fn open_browser(path: &str) {
    if command_on_path("open") {
        let _ = Command::new("open").arg(path).status();
    } else if command_on_path("xdg-open") {
        let _ = Command::new("xdg-open").arg(path).status();
    } else {
        eprintln!("! Could not find 'open' or 'xdg-open'. Open this file in a browser manually:");
        eprintln!("    {}", path);
    }
}

/// The manifest `code` from the redirect's request line, as
/// `sed -n 's/.*[?&]code=\([^ &]*\).*/\1/p'` extracts it: the LAST `code=`
/// that follows a `?` or `&`, up to the next space or `&`. Empty when absent.
pub fn extract_code(request_line: &str) -> String {
    let b = request_line.as_bytes();
    let mut found = None;
    let mut i = 0;
    while let Some(off) = request_line[i..].find("code=") {
        let at = i + off;
        if at > 0 && (b[at - 1] == b'?' || b[at - 1] == b'&') {
            found = Some(at + 5);
        }
        i = at + 1;
    }
    match found {
        Some(start) => {
            let rest = &request_line[start..];
            let end = rest
                .find(|c: char| c == ' ' || c == '&')
                .unwrap_or(rest.len());
            rest[..end].to_string()
        }
        None => String::new(),
    }
}

/// The longest manifest code accepted. GitHub's are about 20 characters.
pub const MAX_CODE_LEN: usize = 128;

/// The code is spliced into the `gh api` request path, so only
/// `[A-Za-z0-9_-]`, 1 to MAX_CODE_LEN long, is allowed: no `/`, `..`, `?`,
/// `%`, spaces or control characters that could change the request.
pub fn is_valid_code(code: &str) -> bool {
    !code.is_empty()
        && code.len() <= MAX_CODE_LEN
        && code
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// `mktemp "${TMPDIR:-/tmp}/pulumi-create-app.XXXXXX"` + `.html`: a random
/// name, created exclusively (an existing file or symlink at the path is
/// never written through), mode 0600.
pub fn create_html_file(content: &str) -> std::io::Result<String> {
    use std::os::unix::fs::OpenOptionsExt;
    let dir = crate::tools::env_nonempty("TMPDIR").unwrap_or_else(|| "/tmp".to_string());
    let dir = dir.trim_end_matches('/');
    let mut last_err = None;
    for _ in 0..100 {
        let path = format!("{}/pulumi-create-app.{}.html", dir, random_suffix());
        match std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(mut f) => {
                f.write_all(content.as_bytes())?;
                return Ok(path);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => last_err = Some(e),
            Err(e) => return Err(e),
        }
    }
    Err(last_err.unwrap_or_else(|| std::io::Error::other("no free temp name")))
}

/// Six characters from [A-Za-z0-9], seeded from /dev/urandom (falling back to
/// the clock and pid when it cannot be read).
fn random_suffix() -> String {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut bytes = [0u8; 6];
    let ok = std::fs::File::open("/dev/urandom")
        .and_then(|mut f| std::io::Read::read_exact(&mut f, &mut bytes))
        .is_ok();
    if !ok {
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
            ^ ((std::process::id() as u128) << 32);
        for (k, b) in bytes.iter_mut().enumerate() {
            *b = (t >> (k * 8)) as u8;
        }
    }
    bytes
        .iter()
        .map(|b| CHARS[(*b as usize) % CHARS.len()] as char)
        .collect()
}

/// A gh write the shell runs bare under `set -euo pipefail`: its exit status
/// (127 when gh cannot be started), with `input` on stdin when given.
fn gh_write(args: &[&str], input: Option<&str>) -> i32 {
    let mut c = Command::new("gh");
    c.args(args);
    if input.is_some() {
        c.stdin(Stdio::piped());
    }
    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return 127,
        Err(_) => return 126,
    };
    if let (Some(text), Some(mut stdin)) = (input, child.stdin.take()) {
        let _ = stdin.write_all(text.as_bytes());
    }
    match child.wait() {
        Ok(st) => exit_code(st),
        Err(_) => 1,
    }
}

pub fn run(args: &[String]) -> i32 {
    // --- Prerequisites -------------------------------------------------------
    if !command_on_path("gh") {
        eprintln!(
            "! gh CLI not found. Install it: https://cli.github.com/ — then 'gh auth login'."
        );
        return 1;
    }
    // No jq check: the shell needed jq to read the conversion response; this
    // parses the JSON itself.
    if !run_ok("gh", &["auth", "status"]) {
        eprintln!("! gh is not authenticated. Run 'gh auth login' (needs admin:org / repo scope) and retry.");
        return 1;
    }
    println!("This bootstrap opens your browser once to create the App. Run it on a");
    println!("browser-capable machine (or use the paste fallback below if you are remote).");
    println!("----------------------------------------------------------------------");

    // --- Determine the target owner ------------------------------------------
    let mut owner = args.first().cloned().unwrap_or_default();
    if owner.is_empty() {
        let default_owner =
            capture_stdout_ok("gh", &["api", "user", "--jq", ".login"]).unwrap_or_default();
        let input = prompt_read(&format!(
            "GitHub org or user to own the App [{}]: ",
            default_owner
        ))
        .unwrap_or_default();
        owner = if input.is_empty() {
            default_owner
        } else {
            input
        };
    }
    if owner.is_empty() {
        eprintln!(
            "! No owner determined. Pass one explicitly: bazel run //tools/pulumi:create-app -- <org>."
        );
        return 1;
    }

    let (new_app_url, is_org) = if run_ok("gh", &["api", &format!("orgs/{}", owner)]) {
        println!("\u{2713} Target '{}' is an organization.", owner);
        (
            format!(
                "https://github.com/organizations/{}/settings/apps/new",
                owner
            ),
            true,
        )
    } else {
        println!("\u{2713} Target '{}' treated as a personal account.", owner);
        ("https://github.com/settings/apps/new".to_string(), false)
    };
    let _ = is_org;

    // --- Build the App manifest ----------------------------------------------
    let redirect_url = "http://localhost:8723/cb";
    let manifest = format!(
        r#"{{
  "name": "{owner}-pulumi",
  "url": "https://github.com/{owner}",
  "redirect_url": "{redirect_url}",
  "public": false,
  "default_permissions": {{
    "administration": "write",
    "contents": "read",
    "variables": "write",
    "issues": "write",
    "dependabot_secrets": "write"
  }},
  "default_events": []
}}"#,
        owner = owner,
        redirect_url = redirect_url
    );

    // --- Write an auto-submitting browser form -------------------------------
    let html_content = format!(
        r#"<!doctype html>
<html>
  <body onload="document.getElementById('f').submit()">
    <p>Submitting GitHub App manifest for <strong>{owner}</strong>…</p>
    <p>If nothing happens, click the button below.</p>
    <form id="f" method="post" action="{url}">
      <input type="hidden" name="manifest" value='{manifest}'>
      <button type="submit">Create GitHub App</button>
    </form>
    <script>document.getElementById('f').submit()</script>
  </body>
</html>
"#,
        owner = owner,
        url = new_app_url,
        manifest = manifest,
    );

    let html_path = match create_html_file(&html_content) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("! Could not write HTML file: {}", e);
            return 1;
        }
    };

    struct HtmlCleanup<'a>(&'a str);
    impl<'a> Drop for HtmlCleanup<'a> {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(self.0);
        }
    }
    let _cleanup = HtmlCleanup(&html_path);

    println!();
    println!("Opening the GitHub App creation page in your browser\u{2026}");
    open_browser(&html_path);
    println!("In the browser: review the pre-filled permissions and click 'Create GitHub App'.");

    // --- Capture the one-time manifest 'code' --------------------------------
    let mut code = String::new();
    if command_on_path("nc") && command_on_path("timeout") {
        println!();
        println!("Listening on localhost:8723 for the redirect (best-effort)\u{2026}");
        if let Some(raw) = capture_stdout_raw("timeout", &["60", "nc", "-l", "8723"]) {
            if let Some(first_line) = raw.lines().next() {
                code = extract_code(first_line);
            }
        }
    }
    if code.is_empty() {
        println!();
        println!("After clicking 'Create GitHub App', your browser lands on a localhost URL");
        println!(
            "that won't load \u{2014} copy the 'code=' value from the address bar and paste it here."
        );
        code = prompt_read("code: ").unwrap_or_default();
    }
    if code.is_empty() {
        eprintln!("! No code captured; cannot complete App creation. Re-run and paste the code.");
        return 1;
    }
    if !is_valid_code(&code) {
        // Not echoed back: it may hold terminal control characters.
        eprintln!(
            "! That is not a GitHub App manifest code: it must be 1-{} letters, digits, '_' or '-'.",
            MAX_CODE_LEN
        );
        eprintln!("  Nothing was sent to GitHub. Re-run and paste the 'code=' value from the address bar.");
        return 1;
    }

    // --- Exchange the code for App credentials -------------------------------
    println!();
    println!("Exchanging the code for App credentials\u{2026}");
    let conversion_output = Command::new("gh")
        .args([
            "api",
            "--method",
            "POST",
            &format!("/app-manifests/{}/conversions", code),
        ])
        .stdout(Stdio::piped())
        // `CONVERSION="$(gh api ...)"`: gh's own error stays on stderr.
        .stderr(Stdio::inherit())
        .output();
    let conversion_output = match conversion_output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => {
            eprintln!(
                "! Failed to exchange the code (the code may have expired or is invalid \u{2014}"
            );
            eprintln!("  re-run and paste a fresh code).");
            return 1;
        }
    };

    let conversion = match crate::json::loads(&conversion_output) {
        Ok(v) => v,
        Err(_) => {
            eprintln!(
                "! Failed to exchange the code (the code may have expired or is invalid \u{2014}"
            );
            eprintln!("  re-run and paste a fresh code).");
            return 1;
        }
    };

    let app_id = json_field(&conversion, "id");
    let app_slug = json_field(&conversion, "slug");
    let app_pem = json_field(&conversion, "pem");
    let app_client_id = json_field(&conversion, "client_id");

    if app_id.is_empty() || app_id == "null" || app_pem.is_empty() || app_pem == "null" {
        eprintln!("! Conversion did not return an App id/pem (the code may have expired). Re-run.");
        return 1;
    }
    println!(
        "\u{2713} Created GitHub App '{}' (id: {}).",
        app_slug, app_id
    );

    // --- Set org-level credentials -------------------------------------------
    println!();
    println!(
        "Setting org-level credentials on '{}' (App ID as a variable, key as a secret)\u{2026}",
        owner
    );

    let rc = gh_write(
        &[
            "variable",
            "set",
            "PULUMI_APP_ID",
            "--org",
            &owner,
            "--visibility",
            "all",
            "--body",
            &app_id,
        ],
        None,
    );
    if rc != 0 {
        return rc;
    }
    // printf '%s' "$APP_PEM" | gh secret set ...: under pipefail, gh's status.
    let rc = gh_write(
        &[
            "secret",
            "set",
            "APP_PRIVATE_KEY",
            "--org",
            &owner,
            "--visibility",
            "all",
        ],
        Some(&app_pem),
    );
    if rc != 0 {
        return rc;
    }

    println!("\u{2713} Set PULUMI_APP_ID (variable) and APP_PRIVATE_KEY (secret).");

    if !app_client_id.is_empty() {
        let rc = gh_write(
            &[
                "variable",
                "set",
                "PULUMI_APP_CLIENT_ID",
                "--org",
                &owner,
                "--visibility",
                "all",
                "--body",
                &app_client_id,
            ],
            None,
        );
        if rc != 0 {
            return rc;
        }
        println!("\u{2713} Set PULUMI_APP_CLIENT_ID (variable).");
    } else {
        eprintln!(
            "! Conversion returned no client_id. Read it from 'gh api /apps/{} --jq .client_id'",
            app_slug
        );
        eprintln!(
            "  and set it with: gh variable set PULUMI_APP_CLIENT_ID --org {} --visibility all --body <id>",
            owner
        );
    }

    // --- Pulumi Cloud access token -------------------------------------------
    println!();
    let pulumi_token = prompt_read_secret("Pulumi Cloud access token (leave empty to set later): ")
        .unwrap_or_default();
    if !pulumi_token.is_empty() {
        let rc = gh_write(
            &[
                "secret",
                "set",
                "PULUMI_ACCESS_TOKEN",
                "--org",
                &owner,
                "--visibility",
                "all",
            ],
            Some(&pulumi_token),
        );
        if rc != 0 {
            return rc;
        }
        println!("\u{2713} Set PULUMI_ACCESS_TOKEN (secret).");
    } else {
        println!("! Skipped PULUMI_ACCESS_TOKEN. Set it later (CI needs it for Pulumi state):");
        println!(
            "    printf '%s' '<token>' | gh secret set PULUMI_ACCESS_TOKEN --org \"{}\" --visibility all",
            owner
        );
    }

    // --- Install the App -----------------------------------------------------
    println!();
    println!(
        "Done. Install the App on '{}' (and the repos that should opt in):",
        owner
    );
    println!("    https://github.com/apps/{}/installations/new", app_slug);
    println!(
        "Then per repo, run 'bazel run //infrastructure/pulumi/platform/repo-config:setup' to"
    );
    println!("enable preview-on-PR / apply-on-merge.");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_code_matches_sed() {
        assert_eq!(extract_code("GET /cb?code=abc123 HTTP/1.1"), "abc123");
        assert_eq!(extract_code("GET /cb?state=x&code=abc HTTP/1.1"), "abc");
        assert_eq!(extract_code("GET /cb?code=abc&state=x HTTP/1.1"), "abc");
        // sed's greedy `.*` takes the LAST [?&]code=, and only after ? or &.
        assert_eq!(extract_code("GET /cb?xcode=bad&code=good HTTP/1.1"), "good");
        assert_eq!(extract_code("GET /cb?code=one&code=two HTTP/1.1"), "two");
        assert_eq!(extract_code("GET /cb?xcode=bad HTTP/1.1"), "");
        assert_eq!(extract_code("GET /cb HTTP/1.1"), "");
        assert_eq!(extract_code("GET /cb?code= HTTP/1.1"), "");
    }

    #[test]
    fn code_validation() {
        assert!(is_valid_code("abc123"));
        assert!(is_valid_code("A-b_9"));
        assert!(is_valid_code(&"a".repeat(MAX_CODE_LEN)));
        assert!(!is_valid_code(&"a".repeat(MAX_CODE_LEN + 1)));
        for bad in [
            "", "../x", "a/b", "a?b", "a b", "a%2Fb", "a.b", "a\nb", "\u{e9}",
        ] {
            assert!(!is_valid_code(bad), "{bad:?}");
        }
    }

    #[test]
    fn html_file_is_created_exclusively() {
        let dir = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
        let dir = format!("{}/create-app-excl-{}", dir, std::process::id());
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::env::set_var("TMPDIR", &dir);
        let a = create_html_file("<a>").unwrap();
        let b = create_html_file("<b>").unwrap();
        assert_ne!(a, b);
        assert_eq!(std::fs::read_to_string(&a).unwrap(), "<a>");
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(&a).unwrap().permissions().mode() & 0o777,
            0o600
        );
        // create_new never opens an existing path, symlink or not.
        let victim = format!("{dir}/victim");
        std::fs::write(&victim, "keep").unwrap();
        let link = format!("{dir}/link.html");
        std::os::unix::fs::symlink(&victim, &link).unwrap();
        let err = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&link);
        assert!(err.is_err());
        assert_eq!(std::fs::read_to_string(&victim).unwrap(), "keep");
    }
}
