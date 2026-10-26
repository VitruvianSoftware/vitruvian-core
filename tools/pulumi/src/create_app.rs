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

//! create-app.sh in Rust: one-time GitHub App Manifest-flow bootstrap.

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
    if stdin_is_tty() {
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
    if stdin_is_tty() {
        let _ = Command::new("stty")
            .arg("echo")
            .stdin(Stdio::inherit())
            .stderr(Stdio::null())
            .status();
    }
    println!();
    match result {
        Ok(0) => None,
        Ok(_) => Some(
            line.trim_end_matches('\n')
                .trim_end_matches('\r')
                .to_string(),
        ),
        Err(_) => None,
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
        let _ = Command::new("open")
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    } else if command_on_path("xdg-open") {
        let _ = Command::new("xdg-open")
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    } else {
        eprintln!("! Could not find 'open' or 'xdg-open'. Open this file in a browser manually:");
        eprintln!("    {}", path);
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
    if !command_on_path("jq") {
        eprintln!("! jq not found. Install it: https://jqlang.github.io/jq/ — then re-run.");
        return 1;
    }
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
    let tmpdir = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
    let html_path = format!("{}/pulumi-create-app.{}.html", tmpdir, std::process::id());
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

    if let Err(e) = std::fs::write(&html_path, &html_content) {
        eprintln!("! Could not write HTML file: {}", e);
        return 1;
    }

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
                if let Some(start) = first_line.find("code=") {
                    let rest = &first_line[start + 5..];
                    let end = rest
                        .find(|c: char| c == ' ' || c == '&')
                        .unwrap_or(rest.len());
                    code = rest[..end].to_string();
                }
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
        .stderr(Stdio::piped())
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

    if !Command::new("gh")
        .args([
            "variable",
            "set",
            "PULUMI_APP_ID",
            "--org",
            &owner,
            "--visibility",
            "all",
            "--body",
            &app_id,
        ])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        return 1;
    }

    let status = Command::new("gh")
        .args([
            "secret",
            "set",
            "APP_PRIVATE_KEY",
            "--org",
            &owner,
            "--visibility",
            "all",
        ])
        .stdin(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .and_then(|mut child| {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(app_pem.as_bytes());
            }
            child.wait()
        });
    if !status.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    println!("\u{2713} Set PULUMI_APP_ID (variable) and APP_PRIVATE_KEY (secret).");

    if !app_client_id.is_empty() {
        if !Command::new("gh")
            .args([
                "variable",
                "set",
                "PULUMI_APP_CLIENT_ID",
                "--org",
                &owner,
                "--visibility",
                "all",
                "--body",
                &app_client_id,
            ])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            return 1;
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
        let status = Command::new("gh")
            .args([
                "secret",
                "set",
                "PULUMI_ACCESS_TOKEN",
                "--org",
                &owner,
                "--visibility",
                "all",
            ])
            .stdin(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .and_then(|mut child| {
                if let Some(mut stdin) = child.stdin.take() {
                    let _ = stdin.write_all(pulumi_token.as_bytes());
                }
                child.wait()
            });
        if !status.map(|s| s.success()).unwrap_or(false) {
            return 1;
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
