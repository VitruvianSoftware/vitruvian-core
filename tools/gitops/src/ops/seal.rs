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
//! seal_headplane_secret.sh, seal_zitadel_login_cookie_secret.sh,
//! seal_arc_github_app.sh, seal_alert_pagerduty.sh and
//! seal_pagerduty_readonly.sh. Each value goes to
//! kubectl or kubeseal on stdin, never on a command line, and is never printed.

use std::os::unix::ffi::{OsStrExt, OsStringExt};
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
// seal-alert-heartbeat: the healthchecks.io ping URL for the Watchdog
// dead-man's switch (alertmanager-ntfy-bridge /heartbeat)
// ---------------------------------------------------------------------------

/// An https URL, nothing else: the bridge GETs it every ~5 minutes.
pub fn is_heartbeat_url(v: &[u8]) -> bool {
    v.starts_with(b"https://")
        && v.len() > b"https://".len()
        && !v.iter().any(|c| c.is_ascii_whitespace())
}

pub fn alert_heartbeat(args: &[Vec<u8>]) -> i32 {
    code(alert_heartbeat_run(args))
}

fn alert_heartbeat_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(54)?;
    let k = kctx();
    let (ns, secret, key) = ("monitoring", "alertmanager-heartbeat", "ping-url");
    let out = out_path(secret);
    let mut apply = false;
    let mut url = Vec::new();
    for a in args {
        if a == b"--apply" {
            apply = true;
        } else if a.starts_with(b"-") {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown flag '",
                    a,
                    b"' (expected the ping URL and/or --apply)",
                ]),
            );
        } else {
            url = a.clone();
        }
    }
    if url.is_empty() {
        // Prompted, so the URL stays out of shell history.
        url = read_prompt("healthchecks.io ping URL (https://hc-ping.com/...): ")?;
    }
    if !is_heartbeat_url(&url) {
        return die(
            2,
            b"ERROR: expected an https:// ping URL with no spaces (copy it from the check's page on healthchecks.io).",
        );
    }
    need_tools(&["kubectl", "kubeseal"], false)?;
    cd_workspace(88)?;
    write_new(95, &out, LICENSE_HEADER.as_bytes())?;
    let st = seal_value(116, &k, ns, secret, key, &url, &out);
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

// ---------------------------------------------------------------------------
// seal_alert_pagerduty.sh
// ---------------------------------------------------------------------------

/// The PagerDuty services Alertmanager routes to, by `pagerduty_service`
/// label. Each must be a `services` entry in
/// infrastructure/pulumi/platform/pagerduty/Pulumi.production.yaml (which
/// exports `<key>IntegrationKey`) and a `pagerduty-<key>` receiver reading
/// /etc/alertmanager/pagerduty/<key> in
/// gitops/argocd/platform/prometheus/applicationset.yaml.
pub const PAGERDUTY_SERVICES: &[&str] = &["cluster", "data", "apps"];

const PAGERDUTY_USAGE: &[u8] = b"usage: bazel run //infrastructure/pulumi/platform/pagerduty:stack -- output --json --show-secrets --stack production \\\n         | bazel run //tools/gitops:seal-alert-pagerduty [-- --apply]";

/// An Events API v2 integration key: 32 lower-case letters and digits.
fn valid_integration_key(k: &str) -> bool {
    k.len() == 32
        && k.bytes()
            .all(|c| c.is_ascii_digit() || c.is_ascii_lowercase())
}

/// The Secret, as JSON for kubeseal's stdin, built from the PagerDuty stack's
/// `pulumi stack output --json --show-secrets`. Err names what is wrong, never
/// a key's value.
pub fn pagerduty_secret_json(outputs: &[u8], ns: &str, secret: &str) -> Result<String, String> {
    let text =
        std::str::from_utf8(outputs).map_err(|_| "stack outputs are not UTF-8".to_string())?;
    let v = crate::json::loads(text).map_err(|_| "stack outputs are not JSON".to_string())?;
    let mut data = Vec::new();
    for svc in PAGERDUTY_SERVICES {
        let name = format!("{}IntegrationKey", svc);
        match v.get(&name) {
            Some(crate::json::Value::Str(k)) if valid_integration_key(k) => {
                data.push(format!(
                    "\"{}\":\"{}\"",
                    svc,
                    super::crypto::b64encode(k.as_bytes())
                ));
            }
            Some(crate::json::Value::Str(k)) if k == "[secret]" => {
                return Err(format!(
                    "{} is masked: pass --show-secrets to pulumi stack output",
                    name
                ));
            }
            Some(crate::json::Value::Str(_)) => {
                return Err(format!("{} is not a 32-character Events API v2 key", name));
            }
            Some(_) => return Err(format!("{} is not a string", name)),
            None => {
                return Err(format!(
                    "{} missing from the stack outputs (has the stack applied that service yet?)",
                    name
                ))
            }
        }
    }
    Ok(format!(
        "{{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"type\":\"Opaque\",\"metadata\":{{\"name\":\"{}\",\"namespace\":\"{}\"}},\"data\":{{{}}}}}",
        secret,
        ns,
        data.join(",")
    ))
}

pub fn alert_pagerduty(args: &[Vec<u8>]) -> i32 {
    code(alert_pagerduty_run(args))
}

fn alert_pagerduty_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(line!())?;
    let k = kctx();
    let (ns, secret) = ("monitoring", "alertmanager-pagerduty-keys");
    let out = out_path(secret);
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
                    b"' (expected --apply or nothing).\n",
                    PAGERDUTY_USAGE,
                ]),
            );
        }
    }
    if sc::stdin_is_tty() {
        return die(
            2,
            &sc::cat(&[
                b"ERROR: pipe the PagerDuty stack outputs in on stdin.\n",
                PAGERDUTY_USAGE,
            ]),
        );
    }
    let mut outputs = Vec::new();
    if std::io::Read::read_to_end(&mut std::io::stdin(), &mut outputs).is_err() {
        return die(1, b"ERROR: could not read stdin.");
    }
    let manifest = match pagerduty_secret_json(&outputs, ns, secret) {
        Ok(m) => m,
        Err(e) => {
            return die(
                1,
                &sc::cat(&[b"ERROR: ", e.as_bytes(), b". Nothing was sealed."]),
            )
        }
    };
    need_tools(&["kubectl", "kubeseal"], false)?;
    cd_workspace(line!())?;
    let tmp = sc::cat(&[&out, b".tmp"]);
    write_new(line!(), &tmp, LICENSE_HEADER.as_bytes())?;
    let o = append_to(line!(), &tmp)?;
    let st = feed(line!(), kubeseal_yaml(&k), manifest.as_bytes(), Some(o));
    let text = std::fs::read(sc::path(&tmp)).unwrap_or_default();
    if st != 0
        || !PAGERDUTY_SERVICES
            .iter()
            .all(|svc| has_sealed_value(&text, svc))
    {
        let _ = std::fs::remove_file(sc::path(&tmp));
        return die(
            1,
            b"ERROR: kubeseal did not seal every key. Nothing was written.",
        );
    }
    mv(line!(), &tmp, &out)?;
    say(&sc::cat(&[
        "\u{2713} sealed \u{2192} ".as_bytes(),
        &out,
        format!(
            " (SealedSecret {}/{}, keys {})",
            ns,
            secret,
            PAGERDUTY_SERVICES.join(", ")
        )
        .as_bytes(),
    ]));
    apply_or_next(
        &k,
        &out,
        ns,
        secret,
        apply,
        "\u{2713} applied \u{2014} the sealed-secrets controller will materialize",
    )
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

    fn outputs(keys: &[(&str, &str)]) -> Vec<u8> {
        let items: Vec<String> = keys
            .iter()
            .map(|(k, v)| format!("\"{}\": \"{}\"", k, v))
            .collect();
        format!(
            "{{\"escalationPolicyId\": \"PS9GPWM\", {}}}",
            items.join(", ")
        )
        .into_bytes()
    }

    const KEY: &str = "0123456789abcdef0123456789abcdef";

    #[test]
    fn pagerduty_secret_carries_every_service_key_base64() {
        let o = outputs(&[
            ("clusterIntegrationKey", KEY),
            ("dataIntegrationKey", KEY),
            ("appsIntegrationKey", KEY),
            ("sentryIntegrationKey", KEY),
        ]);
        let j = pagerduty_secret_json(&o, "monitoring", "alertmanager-pagerduty-keys").unwrap();
        let v = crate::json::loads(&j).unwrap();
        assert!(matches!(v.get("kind"), Some(crate::json::Value::Str(s)) if s == "Secret"));
        let data = v.get("data").unwrap();
        for svc in PAGERDUTY_SERVICES {
            match data.get(svc) {
                Some(crate::json::Value::Str(b)) => {
                    assert_eq!(
                        super::super::crypto::b64decode(b.as_bytes()).unwrap(),
                        KEY.as_bytes()
                    )
                }
                other => panic!("{}: {:?}", svc, other.map(|x| x.type_name())),
            }
        }
        // Sentry's key is not Alertmanager's business: it stays out.
        assert!(data.get("sentry").is_none());
        assert!(!j.contains(KEY), "the raw key must not appear unencoded");
    }

    #[test]
    fn pagerduty_secret_refuses_missing_masked_or_malformed_keys() {
        let all = |apps: &str| {
            outputs(&[
                ("clusterIntegrationKey", KEY),
                ("dataIntegrationKey", KEY),
                ("appsIntegrationKey", apps),
            ])
        };
        let missing = outputs(&[("clusterIntegrationKey", KEY), ("dataIntegrationKey", KEY)]);
        let e = pagerduty_secret_json(&missing, "n", "s").unwrap_err();
        assert!(e.contains("appsIntegrationKey missing"), "{}", e);
        let e = pagerduty_secret_json(&all("[secret]"), "n", "s").unwrap_err();
        assert!(e.contains("--show-secrets"), "{}", e);
        let e = pagerduty_secret_json(&all("short"), "n", "s").unwrap_err();
        assert!(e.contains("32-character") && !e.contains("short"), "{}", e);
        assert!(pagerduty_secret_json(b"not json", "n", "s").is_err());
    }

    #[test]
    fn heartbeat_url_shape() {
        assert!(is_heartbeat_url(
            b"https://hc-ping.com/0f9d3e1a-1111-2222-3333-444455556666"
        ));
        assert!(!is_heartbeat_url(b"http://hc-ping.com/abc"));
        assert!(!is_heartbeat_url(b"https://"));
        assert!(!is_heartbeat_url(b"https://hc-ping.com/abc def"));
        assert!(!is_heartbeat_url(b"https://hc-ping.com/abc\n"));
        assert!(!is_heartbeat_url(b""));
    }
}

// ---------------------------------------------------------------------------
// seal-headscale-key-exporter: a Headscale API key of its own for
// headscale-key-exporter (gitops/argocd/platform/headscale/), minted inside
// the headscale pod and sealed in one go, so the key is never on screen, on
// a command line or on disk.
// ---------------------------------------------------------------------------

/// What `headscale apikeys create` prints: `<7-char prefix>.<secret>`, both
/// URL-safe (letters, digits, `_`, `-`). v0.26.1's secret is 32 characters.
pub fn is_api_key(v: &[u8]) -> bool {
    let url_safe = |s: &[u8]| {
        s.iter()
            .all(|c| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'-')
    };
    match api_key_prefix(v) {
        Some(prefix) => {
            let secret = &v[prefix.len() + 1..];
            url_safe(prefix) && secret.len() >= 16 && url_safe(secret)
        }
        None => false,
    }
}

/// The 7-character prefix Headscale lists a key by (`headscale apikeys
/// list`), safe to print: it identifies the key without being it.
pub fn api_key_prefix(v: &[u8]) -> Option<&[u8]> {
    let dot = v.iter().position(|c| *c == b'.')?;
    if dot == 7 && v[dot + 1..].iter().all(|c| *c != b'.') {
        Some(&v[..dot])
    } else {
        None
    }
}

/// A Headscale duration such as 365d, 8760h or 90d: digits then one unit.
pub fn is_duration(v: &[u8]) -> bool {
    match v.split_last() {
        Some((unit, digits)) => {
            !digits.is_empty()
                && digits.iter().all(u8::is_ascii_digit)
                && matches!(unit, b'd' | b'h' | b'm')
        }
        None => false,
    }
}

pub fn headscale_key_exporter(args: &[Vec<u8>]) -> i32 {
    code(headscale_key_exporter_run(args))
}

fn headscale_key_exporter_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(54)?;
    let k = kctx();
    let (ns, secret, key) = ("headscale", "headscale-key-exporter", "api-key");
    let out = out_path(secret);
    let mut apply = false;
    let mut expiration: Vec<u8> = b"365d".to_vec();
    let mut it = args.iter();
    while let Some(a) = it.next() {
        if a == b"--apply" {
            apply = true;
        } else if a == b"--expiration" {
            match it.next() {
                Some(v) if is_duration(v) => expiration = v.clone(),
                _ => {
                    return die(
                        2,
                        b"ERROR: --expiration needs a duration such as 365d or 8760h.",
                    )
                }
            }
        } else {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown argument '",
                    a,
                    b"' (expected --expiration <duration> and/or --apply)",
                ]),
            );
        }
    }
    need_tools(&["kubectl", "kubeseal"], false)?;
    let pod = super::headscale::headscale_pod(&k)?;
    let mint = kubectl(
        &k,
        &[
            b"-n",
            b"headscale",
            b"exec",
            b"-c",
            b"headscale",
            &pod,
            b"--",
            b"headscale",
            b"apikeys",
            b"create",
            b"--expiration",
            &expiration,
        ],
    );
    // stdout is the key; headscale's own warnings go to stderr as usual.
    let (st, minted) = capture(0, mint);
    let api_key = sc::read_trim(&minted);
    if st != 0 {
        return die(
            st,
            b"ERROR: headscale apikeys create failed; nothing sealed.",
        );
    }
    if !is_api_key(&api_key) {
        return die(
            1,
            b"ERROR: headscale apikeys create did not print a key in the expected <prefix>.<secret> form; nothing sealed. If it minted one anyway, find the newest with bazel run //tools/gitops:headscale-apikey-list and expire it with :headscale-apikey-expire -- --prefix <prefix>.",
        );
    }
    let prefix = api_key_prefix(&api_key).unwrap_or_default().to_vec();
    // From here a live key exists. Any failure must say which one, so it can
    // be expired rather than left valid and unrecorded.
    let orphaned = |st: i32| -> Res<i32> {
        die(
            st,
            &sc::cat(&[
                b"ERROR: sealing failed after minting API key ",
                &prefix,
                b"; it is live but recorded nowhere. Expire it: bazel run //tools/gitops:headscale-apikey-expire -- --prefix ",
                &prefix,
            ]),
        )
    };
    if let Err(st) = cd_workspace(88) {
        return orphaned(st);
    }
    if let Err(st) = write_new(95, &out, LICENSE_HEADER.as_bytes()) {
        return orphaned(st);
    }
    let st = seal_value(116, &k, ns, secret, key, &api_key, &out);
    if st != 0 {
        return orphaned(st);
    }
    say(&sealed_msg(&out, ns, secret, key));
    say(&sc::cat(&[
        b"minted Headscale API key ",
        &prefix,
        b", expiring in ",
        &expiration,
        b". Once the exporter reports up=1 on it, expire the key it replaces (bazel run //tools/gitops:headscale-apikey-list, then :headscale-apikey-expire -- --prefix <old prefix>) and update the key table in gitops/argocd/platform/headscale/README.md.",
    ]));
    apply_or_next(
        &k,
        &out,
        ns,
        secret,
        apply,
        "\u{2713} applied \u{2014} the sealed-secrets controller will materialize",
    )
}

#[cfg(test)]
mod headscale_key_exporter_tests {
    use super::*;

    #[test]
    fn api_key_shape() {
        assert!(is_api_key(b"TWRIQB0.abcdefghijklmnopqrstuvwxyz012345"));
        assert!(is_api_key(b"4mP_vv5.ab-cd_efghijklmnopqrstuvwxyz0123"));
        assert!(!is_api_key(b""));
        assert!(!is_api_key(b"short"));
        // A 20+ character token that is not a key: no prefix dot.
        assert!(!is_api_key(b"abcdefghijklmnopqrstuvwxyz"));
        assert!(!is_api_key(b"has a space in it, so not a key"));
        assert!(!is_api_key(b"2026-11-15T00:00:00Z WRN An updated version"));
        // Wrong prefix length, two dots, a short or non-URL-safe secret.
        assert!(!is_api_key(b"TWRIQB.abcdefghijklmnopqrstuvwxyz012345"));
        assert!(!is_api_key(b"TWRIQB0.abcdefghij.klmnopqrstuvwxyz012"));
        assert!(!is_api_key(b"TWRIQB0.abc"));
        assert!(!is_api_key(b"TWRIQB0.abcdefghijklmnop/qrstuvwxyz"));
    }

    #[test]
    fn prefix_is_the_part_headscale_lists() {
        assert_eq!(
            api_key_prefix(b"TWRIQB0.abcdefghijklmnopqrstuvwxyz012345"),
            Some(&b"TWRIQB0"[..])
        );
        assert_eq!(api_key_prefix(b"nodothere"), None);
    }

    #[test]
    fn duration_shape() {
        for ok in [&b"365d"[..], b"8760h", b"90m"] {
            assert!(is_duration(ok), "{}", String::from_utf8_lossy(ok));
        }
        for bad in [&b""[..], b"d", b"365", b"1y", b"-1d", b"36 5d"] {
            assert!(!is_duration(bad), "{}", String::from_utf8_lossy(bad));
        }
    }
}

// ---------------------------------------------------------------------------
// seal-pagerduty-readonly: the read-only PagerDuty REST API key, sealed once
// for each in-cluster reader (pagerduty-exporter, Backstage's PagerDuty plugin)
// ---------------------------------------------------------------------------

/// Where the read-only key goes: (namespace, Secret, key). One SealedSecret
/// each, because a SealedSecret only decrypts in the namespace it names.
pub const PAGERDUTY_READONLY_TARGETS: &[(&str, &str, &str)] = &[
    ("monitoring", "pagerduty-exporter", "api-token"),
    ("backstage", "backstage-pagerduty", "api-token"),
];

/// A PagerDuty REST API key: 20 URL-safe characters (letters, digits, `_`,
/// `-`, `+`). An Events API routing key (32 lower-case characters) is the
/// common mix-up, and it cannot read the API, so it is refused.
pub fn is_pagerduty_api_key(v: &[u8]) -> bool {
    v.len() == 20
        && v.iter()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'-' | b'+'))
}

pub fn pagerduty_readonly(args: &[Vec<u8>]) -> i32 {
    code(pagerduty_readonly_run(args))
}

fn pagerduty_readonly_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(line!())?;
    let k = kctx();
    let mut apply = false;
    for a in args {
        if a == b"--apply" {
            apply = true;
        } else {
            // Never take the key as an argument: it would sit in the
            // process list and the shell history.
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unexpected argument '",
                    a,
                    b"': pipe the key on stdin (only --apply is a flag)",
                ]),
            );
        }
    }
    let key = read_prompt("read-only PagerDuty API key: ")?;
    if !is_pagerduty_api_key(&key) {
        return die(
            2,
            b"ERROR: that is not a PagerDuty REST API key (20 letters, digits, _ - +). An Events API routing key will not work here.",
        );
    }
    need_tools(&["kubectl", "kubeseal"], false)?;
    cd_workspace(line!())?;
    for (ns, secret, field) in PAGERDUTY_READONLY_TARGETS {
        let out = out_path(secret);
        write_new(line!(), &out, LICENSE_HEADER.as_bytes())?;
        let st = seal_value(line!(), &k, ns, secret, field, &key, &out);
        if st != 0 {
            return Err(st);
        }
        say(&sealed_msg(&out, ns, secret, field));
        apply_or_next(
            &k,
            &out,
            ns,
            secret,
            apply,
            "\u{2713} applied \u{2014} the sealed-secrets controller will materialize",
        )?;
    }
    Ok(0)
}

#[cfg(test)]
mod pagerduty_readonly_tests {
    use super::*;

    #[test]
    fn accepts_a_rest_api_key() {
        assert!(is_pagerduty_api_key(b"u+AbCdEf_12345-xyZ90"));
    }

    #[test]
    fn refuses_what_is_not_a_rest_api_key() {
        for bad in [
            &b""[..],
            b"short",
            b"0123456789abcdef0123456789abcdef", // an Events API routing key
            b"u+AbCdEf_12345-xyZ9 ",             // whitespace
            b"u+AbCdEf_12345-xyZ9/",             // not URL-safe
            b"u+AbCdEf_12345-xyZ901",            // 21 characters
        ] {
            assert!(
                !is_pagerduty_api_key(bad),
                "{:?}",
                String::from_utf8_lossy(bad)
            );
        }
    }

    #[test]
    fn each_reader_gets_its_own_sealed_secret() {
        let mut names: Vec<_> = PAGERDUTY_READONLY_TARGETS.iter().map(|t| t.1).collect();
        names.sort();
        names.dedup();
        assert_eq!(names.len(), PAGERDUTY_READONLY_TARGETS.len());
        assert!(PAGERDUTY_READONLY_TARGETS.contains(&(
            "monitoring",
            "pagerduty-exporter",
            "api-token"
        )));
        assert!(PAGERDUTY_READONLY_TARGETS.contains(&(
            "backstage",
            "backstage-pagerduty",
            "api-token"
        )));
    }
}

// ---------------------------------------------------------------------------
// seal-backstage-github-app
// ---------------------------------------------------------------------------

/// The `vitruvian-backstage` GitHub App (created 2026-11-18 to replace the
/// personal access token in `backstage-github-token`).
pub const BACKSTAGE_APP_ID: &str = "5824092";

/// A GitHub App's OAuth client id and secret, as `//tools/agent-app -- convert
/// <code> <pem> <creds.json>` writes them. GitHub App client ids start `Iv`
/// (an OAuth App's start `Ov`, and would be the wrong kind of app); client
/// secrets are 40 lower-case hex characters.
pub fn backstage_app_creds(json: &[u8]) -> Result<(String, String), String> {
    let v: serde_json::Value =
        serde_json::from_slice(json).map_err(|e| format!("credentials file is not JSON: {e}"))?;
    let get = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_owned();
    let (id, secret) = (get("client_id"), get("client_secret"));
    if !id.starts_with("Iv")
        || id.len() < 10
        || !id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.')
    {
        return Err("client_id is not a GitHub App client id (expected Iv...)".into());
    }
    if secret.len() != 40
        || !secret
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("client_secret is not 40 lower-case hex characters".into());
    }
    Ok((id, secret))
}

/// Seal the vitruvian-backstage App's id, client id, client secret and private
/// key into backstage/backstage-github-app, which Backstage's
/// `integrations.github[].apps` reads. Nothing secret goes on a command line:
/// each value reaches kubectl through a mode-600 file in a mode-700 directory
/// that is removed afterwards.
///
///   bazel run //tools/gitops:seal-backstage-github-app -- <key.pem> <creds.json> [--apply]
pub fn backstage_github_app(args: &[Vec<u8>]) -> i32 {
    code(backstage_app_run(args))
}

fn backstage_app_run(args: &[Vec<u8>]) -> Res<i32> {
    const USAGE: &[u8] = b"usage: bazel run //tools/gitops:seal-backstage-github-app -- <key.pem> <creds.json> [--apply]";
    let (ns, secret) = ("backstage", "backstage-github-app");
    let mut apply = false;
    let mut pos: Vec<Vec<u8>> = Vec::new();
    for a in args {
        if a == b"--apply" {
            apply = true;
        } else if a.starts_with(b"-") {
            return die(2, USAGE);
        } else {
            pos.push(a.clone());
        }
    }
    if pos.len() != 2 {
        return die(2, USAGE);
    }
    // Absolute before cd_workspace moves us; relative paths are the caller's.
    let abs = |p: &[u8]| -> Vec<u8> {
        let pb = std::path::Path::new(std::ffi::OsStr::from_bytes(p));
        if pb.is_absolute() {
            p.to_vec()
        } else {
            let base = std::env::var_os("BUILD_WORKING_DIRECTORY")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
            base.join(pb).into_os_string().into_vec()
        }
    };
    let (key, creds) = (abs(&pos[0]), abs(&pos[1]));
    default_kubeconfig(0)?;
    let k = kctx();
    need_tools(&["kubectl", "kubeseal", "openssl"], false)?;
    for p in [&key, &creds] {
        let mode = mode_string(p).unwrap_or_default();
        if mode != "600" {
            return die(
                1,
                &sc::cat(&[
                    b"ERROR: ",
                    p,
                    format!(" is mode '{}'; expected 600. Nothing was sealed.", mode).as_bytes(),
                ]),
            );
        }
    }
    if run_quiet(
        0,
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
    let (client_id, client_secret) =
        match backstage_app_creds(&std::fs::read(sc::path(&creds)).unwrap_or_default()) {
            Ok(c) => c,
            Err(e) => return die(1, format!("ERROR: {e}. Nothing was sealed.").as_bytes()),
        };
    let app_id = sc::env_or("BACKSTAGE_APP_ID", BACKSTAGE_APP_ID.as_bytes());
    cd_workspace(0)?;
    let out = out_path(secret);

    let dir = match mktemp_dir_named("seal-backstage-app") {
        Ok(d) => d,
        Err(e) => {
            return die(1, format!("ERROR: cannot create temp dir: {e}").as_bytes());
        }
    };
    let r = (|| -> Res<i32> {
        let put = |name: &str, val: &[u8]| -> Res<Vec<u8>> {
            let p = sc::cat(&[&dir, b"/", name.as_bytes()]);
            sc::write_secret_file_new(&p, val).map_err(|_| 1)?;
            Ok(p)
        };
        let f_id = put("id", &app_id)?;
        let f_cid = put("cid", client_id.as_bytes())?;
        let f_cs = put("cs", client_secret.as_bytes())?;
        let tmp = sc::cat(&[&dir, b"/sealed.yaml"]);
        write_new(0, &tmp, LICENSE_HEADER.as_bytes())?;
        let o = append_to(0, &tmp)?;
        let create = kubectl(
            &k,
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
                &sc::cat(&[b"--from-file=GITHUB_APP_ID=", &f_id]),
                &sc::cat(&[b"--from-file=GITHUB_APP_CLIENT_ID=", &f_cid]),
                &sc::cat(&[b"--from-file=GITHUB_APP_CLIENT_SECRET=", &f_cs]),
                &sc::cat(&[b"--from-file=GITHUB_APP_PRIVATE_KEY=", &key]),
            ],
        );
        let st = pipeline(0, vec![create, kubeseal_yaml(&k)], None, Some(o));
        if st != 0 {
            return Err(st);
        }
        let text = std::fs::read(sc::path(&tmp)).unwrap_or_default();
        for want in [
            "GITHUB_APP_ID",
            "GITHUB_APP_CLIENT_ID",
            "GITHUB_APP_CLIENT_SECRET",
            "GITHUB_APP_PRIVATE_KEY",
        ] {
            if !has_sealed_value(&text, want) {
                return die(
                    1,
                    format!("ERROR: kubeseal produced no sealed {want}. Nothing was written.")
                        .as_bytes(),
                );
            }
        }
        mv(0, &tmp, &out)?;
        Ok(0)
    })();
    let _ = std::fs::remove_dir_all(sc::path(&dir));
    r?;
    say(&sc::cat(&[
        "\u{2713} sealed \u{2192} ".as_bytes(),
        &out,
        format!(" (SealedSecret {}/{}: App ", ns, secret).as_bytes(),
        &app_id,
        b")",
    ]));
    apply_or_next(
        &k,
        &out,
        ns,
        secret,
        apply,
        "\u{2713} applied: the sealed-secrets controller will materialize",
    )
}

#[cfg(test)]
mod backstage_app_tests {
    use super::backstage_app_creds;

    #[test]
    fn accepts_github_app_credentials() {
        let j = br#"{"client_id":"Iv23liABCDEFGHIJKLMN","client_secret":"0123456789abcdef0123456789abcdef01234567"}"#;
        let (id, s) = backstage_app_creds(j).unwrap();
        assert_eq!(id, "Iv23liABCDEFGHIJKLMN");
        assert_eq!(s.len(), 40);
    }

    #[test]
    fn refuses_an_oauth_app_or_a_malformed_secret() {
        let oauth = br#"{"client_id":"Ov23liABCDEFGHIJKLMN","client_secret":"0123456789abcdef0123456789abcdef01234567"}"#;
        assert!(backstage_app_creds(oauth)
            .unwrap_err()
            .contains("GitHub App"));
        let short = br#"{"client_id":"Iv23liABCDEFGHIJKLMN","client_secret":"abc"}"#;
        assert!(backstage_app_creds(short).unwrap_err().contains("40"));
        assert!(backstage_app_creds(b"not json").is_err());
    }
}
