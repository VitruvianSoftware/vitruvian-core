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

//! pr-comment: pr-comment.sh in Rust. Renders the preview bot's sticky PR
//! comment for a status and creates or updates it through `gh api` -- the
//! same body, gh calls, output and exit codes as the script.

use crate::common::{discarded, echo, prog_name, unbound};
use shell_compat::{cat, err, out, subst};
use std::process::{Command, Stdio};

const USAGE: &str = "Usage: {PROG} --pr <number> --app <name> --status <status> [options]

Required:
  --pr <number>              Pull Request number
  --app <name>               Application name (e.g. tabula)
  --status <status>          Status: provisioning | ready | failed | teardown

Options:
  --preview-url <url>        Live preview environment URL
  --service-name <name>      Cloud Run service name or K8s namespace
  --db-branch <name>         Neon database branch name
  --repo <owner/repo>        GitHub repository (default: VitruvianSoftware/vitruvian-core)
  --dry-run                  Simulate comment rendering and API calls
  -h, --help                 Show this help message
";

fn usage(code: i32) -> i32 {
    let mut parts = USAGE.splitn(2, "{PROG}");
    let head = parts.next().unwrap_or("");
    let tail = parts.next().unwrap_or("");
    out(&cat(&[head.as_bytes(), &prog_name(), tail.as_bytes()]));
    code
}

/// `date -u +"%Y-%m-%d %H:%M:%S UTC"` for `secs` since the epoch.
pub fn utc_timestamp(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02} UTC",
        y,
        m,
        d,
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    )
}

fn now() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    utc_timestamp(secs)
}

/// The comment body for `status` (None for a status the script rejects),
/// without the trailing newline `$(...)` strips.
pub fn render(
    status: &[u8],
    app: &[u8],
    pr: &[u8],
    preview_url: &[u8],
    service_name: &[u8],
    db_branch: &[u8],
    timestamp: &[u8],
) -> Option<Vec<u8>> {
    let marker = cat(&[b"<!-- vitruvian-preview-bot: ", app, b" -->"]);
    let body = match status {
        b"provisioning" => cat(&[
            "### ⏳ Ephemeral Preview Environment Provisioning\nThe preview environment for **".as_bytes(),
            app,
            b"** is currently being built and deployed.\n\n- **PR:** #",
            pr,
            b"\n- **Timestamp:** ",
            timestamp,
            b"\n- **Status:** Provisioning in progress...\n\n",
            &marker,
        ]),
        b"ready" => cat(&[
            "### 🚀 Ephemeral Preview Environment Ready\n\n| Resource | Details |\n|---|---|\n| **Application** | `".as_bytes(),
            app,
            b"` |\n| **Preview URL** | [",
            preview_url,
            b"](",
            preview_url,
            b") |\n| **Compute Service** | `",
            service_name,
            b"` |\n| **Database Branch** | `",
            db_branch,
            "` (Neon copy-on-write) |\n| **Access Gating** | 🔒 Zero-Trust SSO (`@vitruviansoftware.dev`) |\n| **Status** | ✅ Healthy (HTTP 200) |\n| **TTL** | ⏱️ 24 hours (Auto-teardown on PR close or reaper) |\n\n*Last updated: ".as_bytes(),
            timestamp,
            b"*\n\n",
            &marker,
        ]),
        b"failed" => cat(&[
            "### ❌ Ephemeral Preview Provisioning Failed\nProvisioning for **".as_bytes(),
            app,
            b"** failed during rollout. Please inspect the CI workflow logs.\n\n- **PR:** #",
            pr,
            b"\n- **Timestamp:** ",
            timestamp,
            b"\n\n",
            &marker,
        ]),
        b"teardown" => cat(&[
            "### 🧹 Ephemeral Preview Environment Destroyed\nThe ephemeral preview environment for **".as_bytes(),
            app,
            b"** has been torn down.\n\n- **PR:** #",
            pr,
            b"\n- **Cloud Run Service:** Deleted\n- **Neon DB Branch:** Deleted\n- **Timestamp:** ",
            timestamp,
            b"\n\n",
            &marker,
        ]),
        _ => return None,
    };
    // $(...) strips every trailing newline: the variables at the end may
    // end in some.
    Some(subst(cat(&[&body, b"\n"])))
}

/// pr-comment.sh's command line; the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    match main(args) {
        Ok(()) => 0,
        Err(c) => c,
    }
}

fn os(b: &[u8]) -> &std::ffi::OsStr {
    shell_compat::os(b)
}

fn main(args: &[Vec<u8>]) -> Result<(), i32> {
    let mut pr: Vec<u8> = Vec::new();
    let mut app: Vec<u8> = Vec::new();
    let mut status: Vec<u8> = b"ready".to_vec();
    let mut preview_url: Vec<u8> = Vec::new();
    let mut service_name: Vec<u8> = Vec::new();
    let mut db_branch: Vec<u8> = Vec::new();
    let mut repo = shell_compat::env_or("GITHUB_REPOSITORY", b"VitruvianSoftware/vitruvian-core");
    let mut dry_run = false;

    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_slice();
        let (slot, line): (&mut Vec<u8>, u32) = match a {
            b"--pr" => (&mut pr, 39),
            b"--app" => (&mut app, 40),
            b"--status" => (&mut status, 41),
            b"--preview-url" => (&mut preview_url, 42),
            b"--service-name" => (&mut service_name, 43),
            b"--db-branch" => (&mut db_branch, 44),
            b"--repo" => (&mut repo, 45),
            b"--dry-run" => {
                dry_run = true;
                i += 1;
                continue;
            }
            b"-h" | b"--help" => return Err(usage(0)),
            _ => {
                err(&cat(&[b"ERROR: Unknown option: ", a, b"\n"]));
                return Err(usage(1));
            }
        };
        match args.get(i + 1) {
            Some(v) => *slot = v.clone(),
            None => return Err(unbound(line)),
        }
        i += 2;
    }

    if pr.is_empty() || app.is_empty() {
        err(b"ERROR: --pr and --app are required\n");
        return Err(usage(1));
    }

    let timestamp = now();
    let body = match render(
        &status,
        &app,
        &pr,
        &preview_url,
        &service_name,
        &db_branch,
        timestamp.as_bytes(),
    ) {
        Some(b) => b,
        None => {
            err(&cat(&[b"ERROR: Unknown status '", &status, b"'\n"]));
            return Err(1);
        }
    };

    if dry_run {
        out(b"=== DRY RUN: PR Sticky Comment Body ===\n");
        out(&echo(&body));
        out(b"========================================\n");
        return Ok(());
    }

    let marker = cat(&[b"<!-- vitruvian-preview-bot: ", &app, b" -->"]);
    let comments = cat(&[b"repos/", &repo, b"/issues/", &pr, b"/comments"]);
    let mut c = Command::new("gh");
    c.arg("api")
        .arg(os(&comments))
        .arg("--jq")
        .arg(os(&cat(&[
            b".[] | select(.body | contains(\"",
            &marker,
            b"\")) | .id",
        ])))
        .stdout(Stdio::piped());
    // `gh ... | head -n 1` under pipefail: gh's status decides.
    let r = shell_compat::capture_stdout(136, &mut c);
    if r.status != 0 {
        return Err(r.status);
    }
    let existing_id = subst(crate::jq::head1(&r.stdout));
    let field = cat(&[b"body=", &body]);
    if !existing_id.is_empty() {
        out(&cat(&[
            b"Updating existing PR comment (ID: ",
            &existing_id,
            b")...\n",
        ]));
        let mut c = Command::new("gh");
        c.args(["api", "-X", "PATCH"])
            .arg(os(&cat(&[
                b"repos/",
                &repo,
                b"/issues/comments/",
                &existing_id,
            ])))
            .arg("-f")
            .arg(os(&field));
        let st = discarded(140, &mut c);
        if st != 0 {
            return Err(st);
        }
        out("✓ PR comment updated.\n".as_bytes());
    } else {
        out(&cat(&[b"Creating new PR comment on #", &pr, b"...\n"]));
        let mut c = Command::new("gh");
        c.args(["api", "-X", "POST"])
            .arg(os(&comments))
            .arg("-f")
            .arg(os(&field));
        let st = discarded(144, &mut c);
        if st != 0 {
            return Err(st);
        }
        out("✓ PR comment created.\n".as_bytes());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamp_matches_date_u() {
        assert_eq!(utc_timestamp(0), "1970-01-01 00:00:00 UTC");
        assert_eq!(utc_timestamp(951_782_400), "2000-02-29 00:00:00 UTC");
        assert_eq!(utc_timestamp(1_792_929_845), "2026-10-25 12:04:05 UTC");
    }

    #[test]
    fn unknown_status_renders_nothing() {
        assert!(render(b"bogus", b"a", b"1", b"", b"", b"", b"t").is_none());
    }

    #[test]
    fn body_ends_with_the_marker() {
        let b = render(b"failed", b"tabula", b"7", b"", b"", b"", b"T").unwrap();
        assert!(b.ends_with(b"\n\n<!-- vitruvian-preview-bot: tabula -->"));
        assert!(b.starts_with("### ❌".as_bytes()));
    }

    #[test]
    fn trailing_newlines_in_the_app_name_are_stripped_like_bash() {
        let b = render(b"failed", b"x\n", b"7", b"", b"", b"", b"T").unwrap();
        assert!(b.ends_with(b"bot: x\n -->"));
    }
}
