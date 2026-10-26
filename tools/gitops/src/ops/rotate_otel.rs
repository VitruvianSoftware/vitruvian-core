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

//! rotate_github_otel_webhook_secret.sh: one fresh secret, sealed for the
//! CI collector and stored in GitHub's Actions and Dependabot stores; never
//! printed, never on a command line. Sealed to a temp file first and moved
//! into git only once GitHub has it.

use std::process::Stdio;

use shell_compat as sc;

use super::common::*;

pub fn main(args: &[Vec<u8>]) -> i32 {
    let _ = args;
    let mut tmp: Option<Vec<u8>> = None;
    let r = run_rotate(&mut tmp);
    // trap 'rm -f "$TMP"' EXIT (cleared once the file is moved into place)
    if let Some(t) = tmp {
        let _ = std::fs::remove_file(sc::path(&t));
    }
    match r {
        Ok(c) | Err(c) => c,
    }
}

fn run_rotate(tmp_slot: &mut Option<Vec<u8>>) -> Res<i32> {
    default_kubeconfig(42)?;
    let k = kctx();
    let repo = sc::env_or("GH_REPO", b"VitruvianSoftware/vitruvian-core");
    let (ns, secret, key, gh_secret) = (
        "cicd-telemetry",
        "github-otel-webhook",
        "GITHUB_WEBHOOK_SECRET",
        "OTEL_GITHUB_WEBHOOK_SECRET",
    );
    let out = format!("{}/{}.sealedsecret.yaml", SEALED_DIR, secret).into_bytes();

    need_tools(&["kubectl", "kubeseal", "gh", "openssl"], false)?;
    if run_quiet(56, cmd("gh", &[b"auth", b"status"])) != 0 {
        return die(1, b"ERROR: gh is not signed in -- run 'gh auth login'.");
    }
    cd_workspace(58)?;

    let (st, value) = capture(60, cmd("openssl", &[b"rand", b"-hex", b"32"]));
    if st != 0 {
        return Err(st);
    }
    if sc::char_len(&value) != 64 {
        return die(1, b"ERROR: could not generate a secret.");
    }

    let tmp = match sc::mktemp_file(&sc::cat(&[&sc::tmpdir(), b"/github-otel-webhook.XXXXXX"])) {
        Ok(t) => t,
        Err(e) => {
            sc::err(format!("mktemp: {}\n", sc::strerror(&e)).as_bytes());
            return Err(1);
        }
    };
    *tmp_slot = Some(tmp.clone());
    write_new(67, &tmp, LICENSE_HEADER.as_bytes())?;
    if seal_value(87, &k, ns, secret, key, &value, &tmp) != 0 {
        return die(1, b"ERROR: sealing failed -- nothing was changed.");
    }
    say(format!("\u{2713} sealed (Secret {}/{}, key {})", ns, secret, key).as_bytes());

    for store in ["actions", "dependabot"] {
        let mut set = cmd(
            "gh",
            &[b"secret", b"set", gh_secret.as_bytes(), b"--repo", &repo],
        );
        if store == "dependabot" {
            set.arg("--app").arg("dependabot");
        }
        if feed(97, set, &value, Some(Stdio::null())) != 0 {
            if store == "dependabot" {
                warn(format!("ERROR: could not store {} (dependabot). The Actions store already has the NEW secret, so the two GitHub stores now differ -- no sealed file written; re-run this tool to bring everything back in line.", gh_secret).as_bytes());
            } else {
                warn(
                    format!(
                        "ERROR: could not store {} (actions) -- nothing changed; re-run.",
                        gh_secret
                    )
                    .as_bytes(),
                );
            }
            return Err(1);
        }
        say(format!("\u{2713} stored {} ({} secrets)", gh_secret, store).as_bytes());
    }
    drop(value);

    mv(110, &tmp, &out)?;
    *tmp_slot = None;
    say(&sc::cat(&["\u{2713} wrote ".as_bytes(), &out]));
    say(b"next (in order, or GitHub and the collector disagree and deliveries are lost):");
    say(&sc::cat(&[
        b"  1. merge ",
        &out,
        b" in a PR and wait for Argo CD to sync it",
    ]));
    say(format!(
        "  2. kubectl -n {} rollout restart deploy/github-actions-collector",
        ns
    )
    .as_bytes());
    say(b"  3. run the Repo Config Apply workflow (updates the GitHub webhook)");
    say(b"  4. redeliver any failed deliveries from the webhook's delivery log");
    Ok(0)
}
