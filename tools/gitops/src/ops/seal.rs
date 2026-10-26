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

//! The seal tools that write one SealedSecret into
//! gitops/argocd/platform/sealed-secrets-manifests: seal_alert_ntfy.sh,
//! seal_headplane_secret.sh, seal_zitadel_login_cookie_secret.sh and
//! seal_arc_github_app.sh. Each value goes to kubectl on stdin, never on a
//! command line, and is never printed.

use std::os::unix::fs::PermissionsExt;

use shell_compat as sc;

use super::common::*;

fn out_path(secret: &str) -> Vec<u8> {
    format!("{}/{}.sealedsecret.yaml", SEALED_DIR, secret).into_bytes()
}

/// The tail every `--apply`-capable seal tool shares.
fn apply_or_next(
    k: &[u8],
    out: &[u8],
    ns: &str,
    secret: &str,
    apply: bool,
    applied_msg: &str,
) -> Res<i32> {
    if apply {
        let st = run(0, &mut kubectl(k, &[b"apply", b"-f", out]), false);
        if st != 0 {
            return Err(st);
        }
        say(format!("{} {}/{}", applied_msg, ns, secret).as_bytes());
    } else {
        say(&sc::cat(&[
            b"next: commit ",
            out,
            b" (ArgoCD applies it), or re-run with --apply to apply now",
        ]));
    }
    Ok(0)
}

fn sealed_msg(out: &[u8], ns: &str, secret: &str, key: &str) -> Vec<u8> {
    sc::cat(&[
        "\u{2713} sealed \u{2192} ".as_bytes(),
        out,
        format!(" (SealedSecret {}/{}, key {})", ns, secret, key).as_bytes(),
    ])
}

fn code(r: Res<i32>) -> i32 {
    match r {
        Ok(c) | Err(c) => c,
    }
}

// ---------------------------------------------------------------------------
// seal_alert_ntfy.sh
// ---------------------------------------------------------------------------

pub fn alert_ntfy(args: &[Vec<u8>]) -> i32 {
    code(alert_ntfy_run(args))
}

fn alert_ntfy_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(54)?;
    let k = kctx();
    let (ns, secret, key) = ("monitoring", "alertmanager-ntfy-endpoint", "ntfy-password");
    let out = out_path(secret);
    let mut apply = false;
    let mut password = Vec::new();
    for a in args {
        if a == b"--apply" {
            apply = true;
        } else if a.starts_with(b"-") {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown flag '",
                    a,
                    b"' (expected the password and/or --apply)",
                ]),
            );
        } else {
            password = a.clone();
        }
    }
    if password.is_empty() {
        password = read_prompt("ntfy webhook password: ")?;
    }
    if password.is_empty() {
        return die(2, b"ERROR: password must not be empty.");
    }
    need_tools(&["kubectl", "kubeseal"], false)?;
    cd_workspace(88)?;
    write_new(95, &out, LICENSE_HEADER.as_bytes())?;
    let st = seal_value(116, &k, ns, secret, key, &password, &out);
    if st != 0 {
        return Err(st);
    }
    say(&sealed_msg(&out, ns, secret, key));
    apply_or_next(
        &k,
        &out,
        ns,
        secret,
        apply,
        "\u{2713} applied \u{2014} the sealed-secrets controller will materialize",
    )
}

// ---------------------------------------------------------------------------
// seal_headplane_secret.sh
// ---------------------------------------------------------------------------

pub fn headplane(args: &[Vec<u8>]) -> i32 {
    code(headplane_run(args))
}

fn headplane_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(35)?;
    let k = kctx();
    let (ns, secret, key) = ("headscale", "headplane-secret", "cookie-secret");
    let out = out_path(secret);
    let mut apply = false;
    for a in args {
        if a == b"--apply" {
            apply = true;
        } else if a.starts_with(b"-") {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown flag '",
                    a,
                    b"' (expected --apply or nothing).",
                ]),
            );
        } else {
            return die(
                2,
                b"ERROR: this target takes no positional arguments (the secret is auto-generated).",
            );
        }
    }
    need_tools(&["kubectl", "kubeseal", "openssl"], false)?;
    cd_workspace(59)?;
    // headplane 0.5.x requires server.cookie_secret to be exactly 32 characters.
    let (st, secret_value) = openssl_alnum(63, "48", 32);
    if st != 0 {
        return Err(st);
    }
    let n = sc::char_len(&secret_value);
    if n != 32 {
        return die(
            1,
            format!(
                "ERROR: failed to generate a 32-char secret (got {} chars).",
                n
            )
            .as_bytes(),
        );
    }
    write_new(72, &out, LICENSE_HEADER.as_bytes())?;
    let st = seal_value(93, &k, ns, secret, key, &secret_value, &out);
    if st != 0 {
        return Err(st);
    }
    say(&sealed_msg(&out, ns, secret, key));
    apply_or_next(
        &k,
        &out,
        ns,
        secret,
        apply,
        "\u{2713} applied \u{2014} the sealed-secrets controller will materialize",
    )
}

// ---------------------------------------------------------------------------
// seal_zitadel_login_cookie_secret.sh
// ---------------------------------------------------------------------------

pub fn zitadel(args: &[Vec<u8>]) -> i32 {
    code(zitadel_run(args))
}

/// `grep -qE "^[[:space:]]+KEY: Ag[A-Za-z0-9+/=]{200,}$"`: the key carries
/// a real ciphertext (a SealedSecret with an EMPTY payload still passes
/// `kubeseal --validate`).
pub fn has_sealed_value(text: &[u8], key: &str) -> bool {
    let want = sc::cat(&[key.as_bytes(), b": Ag"]);
    text.split(|&c| c == b'\n').any(|line| {
        let body = line
            .iter()
            .position(|c| !c.is_ascii_whitespace() || *c == b'\n');
        let lead = match body {
            Some(i) if i > 0 => i,
            _ => return false,
        };
        let rest = &line[lead..];
        rest.starts_with(&want)
            && rest[want.len()..].len() >= 200
            && rest[want.len()..]
                .iter()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'/' | b'='))
    })
}

fn zitadel_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(44)?;
    let k = kctx();
    let (ns, secret, key) = (
        "zitadel",
        "zitadel-login-session-cookie",
        "ZITADEL_SESSION_COOKIE_SECRET",
    );
    let out = out_path(secret);
    if !args.is_empty() {
        return die(
            2,
            b"ERROR: this target takes no arguments (the secret is generated, never typed).",
        );
    }
    need_tools(&["kubectl", "kubeseal", "openssl"], false)?;
    cd_workspace(64)?;
    let (st, value) = openssl_alnum(69, "96", 48);
    if st != 0 {
        return Err(st);
    }
    let n = sc::char_len(&value);
    if n != 48 {
        return die(
            1,
            format!(
                "ERROR: failed to generate a 48-char secret (got {} chars).",
                n
            )
            .as_bytes(),
        );
    }
    write_new(78, &out, LICENSE_HEADER.as_bytes())?;
    let st = seal_value(99, &k, ns, secret, key, &value, &out);
    if st != 0 {
        return Err(st);
    }
    let text = std::fs::read(sc::path(&out)).unwrap_or_default();
    if !has_sealed_value(&text, key) {
        return die(
            1,
            &sc::cat(&[
                b"ERROR: ",
                &out,
                format!(" has no sealed value under {} -- do not commit it.", key).as_bytes(),
            ]),
        );
    }
    let (cns, cname) = controller();
    let mut validate = kubeseal(
        &k,
        &[
            b"--validate",
            b"--controller-namespace",
            &cns,
            b"--controller-name",
            &cname,
        ],
    );
    match std::fs::File::open(sc::path(&out)) {
        Ok(f) => {
            validate.stdin(f);
        }
        Err(e) => {
            sc::redirect_error(113, &out, &e);
            return Err(1);
        }
    }
    let st = run(112, &mut validate, false);
    if st != 0 {
        return Err(st);
    }
    say(&sealed_msg(&out, ns, secret, key));
    say(&sc::cat(&[
        b"next: commit ",
        &out,
        b"; Argo CD applies it and the login pods roll",
    ]));
    Ok(0)
}

// ---------------------------------------------------------------------------
// seal_arc_github_app.sh
// ---------------------------------------------------------------------------

pub fn arc_github_app(args: &[Vec<u8>]) -> i32 {
    code(arc_run(args))
}

/// `stat -c '%a'` (GNU) / `stat -f '%Lp'` (BSD): the permission bits in
/// octal, no leading zero.
fn mode_string(p: &[u8]) -> Option<String> {
    std::fs::metadata(sc::path(p))
        .ok()
        .map(|m| format!("{:o}", m.permissions().mode() & 0o7777))
}

fn arc_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(40)?;
    let k = kctx();
    let app_id = sc::env_or("ARC_APP_ID", b"5387602");
    let inst_id = sc::env_or("ARC_INSTALLATION_ID", b"173186413");
    let (ns, secret) = ("arc-runners", "vitruvian-arc-github-app");
    let mut apply = false;
    for a in args {
        if a == b"--apply" {
            apply = true;
        } else {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown argument '",
                    a,
                    b"' (expected --apply or nothing).",
                ]),
            );
        }
    }
    need_tools(&["kubectl", "kubeseal", "openssl"], false)?;
    cd_workspace(63)?;
    let key = sc::env_or(
        "ARC_APP_KEY",
        b"tools/sync-env-secrets/agent-keys/vitruvian-arc.pem",
    );
    let out = out_path(secret);
    if !sc::is_readable(&key) {
        return die(
            1,
            &sc::cat(&[
                b"ERROR: no key at ",
                &key,
                b". Run 'bazel run //tools/sync-env-secrets:agent-keys-pull' (Bitwarden unlocked) first.",
            ]),
        );
    }
    let mode = mode_string(&key).unwrap_or_default();
    if mode != "600" {
        return die(
            1,
            &sc::cat(&[
                b"ERROR: ",
                &key,
                format!(" is mode {}; expected 600. Nothing was sealed.", mode).as_bytes(),
            ]),
        );
    }
    if run_quiet(
        76,
        cmd("openssl", &[b"rsa", b"-in", &key, b"-check", b"-noout"]),
    ) != 0
    {
        return die(
            1,
            &sc::cat(&[
                b"ERROR: ",
                &key,
                b" is not a valid RSA private key. Nothing was sealed.",
            ]),
        );
    }
    let tmp = match sc::mktemp_file(&sc::cat(&[&sc::tmpdir(), b"/tmp.XXXXXXXXXX"])) {
        Ok(t) => t,
        Err(e) => {
            sc::err(format!("mktemp: {}\n", sc::strerror(&e)).as_bytes());
            return Err(1);
        }
    };
    let r = arc_seal(&k, &tmp, &out, ns, secret, &app_id, &inst_id, &key);
    if r.is_err() {
        let _ = std::fs::remove_file(sc::path(&tmp));
        return r;
    }
    say(&sc::cat(&[
        "\u{2713} sealed \u{2192} ".as_bytes(),
        &out,
        format!(" (SealedSecret {}/{}: App ", ns, secret).as_bytes(),
        &app_id,
        b", installation ",
        &inst_id,
        b")",
    ]));
    if apply {
        let st = run(103, &mut kubectl(&k, &[b"apply", b"-f", &out]), false);
        if st != 0 {
            return Err(st);
        }
        say(format!(
            "\u{2713} applied: the sealed-secrets controller will materialize {}/{}",
            ns, secret
        )
        .as_bytes());
    } else {
        say(&sc::cat(&[
            b"next: commit ",
            &out,
            b" (ArgoCD applies it), or re-run with --apply to apply now",
        ]));
    }
    Ok(0)
}

#[allow(clippy::too_many_arguments)]
fn arc_seal(
    k: &[u8],
    tmp: &[u8],
    out: &[u8],
    ns: &str,
    secret: &str,
    app_id: &[u8],
    inst_id: &[u8],
    key: &[u8],
) -> Res<i32> {
    // `sed -n '2,20p' "${BASH_SOURCE[0]}"`: the script's license header.
    write_new(84, tmp, LICENSE_HEADER.as_bytes())?;
    let o = append_to(85, tmp)?;
    let create = kubectl(
        k,
        &[
            b"create",
            b"secret",
            b"generic",
            secret.as_bytes(),
            b"-n",
            ns.as_bytes(),
            b"--dry-run=client",
            b"-o",
            b"yaml",
            &sc::cat(&[b"--from-literal=github_app_id=", app_id]),
            &sc::cat(&[b"--from-literal=github_app_installation_id=", inst_id]),
            &sc::cat(&[b"--from-file=github_app_private_key=", key]),
        ],
    );
    let st = pipeline(89, vec![create, kubeseal_yaml(k)], None, Some(o));
    if st != 0 {
        return Err(st);
    }
    let text = std::fs::read(sc::path(tmp)).unwrap_or_default();
    if !sc::contains(&text, b"github_app_private_key:") {
        return die(
            1,
            b"ERROR: kubeseal produced no sealed key. Nothing was written.",
        );
    }
    mv(91, tmp, out)?;
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sealed_value_shape() {
        let good = format!("spec:\n  encryptedData:\n    K: Ag{}\n", "A".repeat(200));
        assert!(has_sealed_value(good.as_bytes(), "K"));
        let short = format!("    K: Ag{}\n", "A".repeat(199));
        assert!(!has_sealed_value(short.as_bytes(), "K"));
        let unindented = format!("K: Ag{}\n", "A".repeat(300));
        assert!(!has_sealed_value(unindented.as_bytes(), "K"));
        let bad_char = format!("    K: Ag{}*\n", "A".repeat(300));
        assert!(!has_sealed_value(bad_char.as_bytes(), "K"));
        assert!(!has_sealed_value(b"    K: \"\"\n", "K"));
    }
}
