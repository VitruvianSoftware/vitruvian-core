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

//! //tools/ci:ensure_site_verification — automated Google domain-ownership
//! self-verification for Cloud Run DomainMappings.

// `capture` is for the one `$(... 2>/dev/null)`; every other `$(...)` lets
// the command's stderr reach the log, as `capture_stdout` does.
use shell_compat::{
    capture, capture_stdout, cat, env, env_or, env_or_empty, err, mktemp_dir, os, out, subst,
};
use std::process::Command;

fn log(msg: &[u8]) {
    out(&cat(&[b"ensure-site-verification: ", msg, b"\n"]));
}

fn log_err(msg: &[u8]) {
    err(&cat(&[b"ensure-site-verification: ", msg, b"\n"]));
}

/// cfg_get: read a flat `<namespace>:<key>: value` YAML line where the
/// namespace is a wildcard (it is per-app and NOT derivable from the project).
fn cfg_get(file: &[u8], key: &[u8]) -> Vec<u8> {
    let content = match std::fs::read(shell_compat::path(file)) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    // Match: optional leading whitespace, one or more word-like chars (the
    // namespace), colon, the key, colon, optional whitespace, then the value.
    // Equivalent to: sed -n 's/^[[:space:]]*[A-Za-z0-9_.-]\{1,\}:<key>:[[:space:]]*//p'
    for line in content.split(|&c| c == b'\n') {
        let trimmed = {
            let mut s = line;
            while s.first().map_or(false, |&c| c == b' ' || c == b'\t') {
                s = &s[1..];
            }
            s
        };
        // Find the namespace:key: prefix.
        let mut i = 0;
        // Consume namespace chars: [A-Za-z0-9_.-]+
        while i < trimmed.len() {
            let c = trimmed[i];
            if c.is_ascii_alphanumeric() || c == b'_' || c == b'.' || c == b'-' {
                i += 1;
            } else {
                break;
            }
        }
        if i == 0 {
            continue;
        }
        // Expect ':'
        if i >= trimmed.len() || trimmed[i] != b':' {
            continue;
        }
        i += 1;
        // Match the key exactly
        if trimmed.len() < i + key.len() {
            continue;
        }
        if &trimmed[i..i + key.len()] != key {
            continue;
        }
        i += key.len();
        // Expect ':'
        if i >= trimmed.len() || trimmed[i] != b':' {
            continue;
        }
        i += 1;
        // Skip whitespace after the colon
        while i < trimmed.len() && (trimmed[i] == b' ' || trimmed[i] == b'\t') {
            i += 1;
        }
        // The value is the rest of the line, with surrounding quotes stripped.
        let mut val = trimmed[i..].to_vec();
        // Strip trailing whitespace
        while val
            .last()
            .map_or(false, |&c| c == b' ' || c == b'\t' || c == b'\r')
        {
            val.pop();
        }
        // tr -d '"' | tr -d "'"
        val.retain(|&c| c != b'"' && c != b'\'');
        return val;
    }
    Vec::new()
}

/// Check if a file contains a line matching `<namespace>:customDomain:`.
fn has_custom_domain_line(file: &[u8]) -> bool {
    let content = match std::fs::read(shell_compat::path(file)) {
        Ok(c) => c,
        Err(_) => return false,
    };
    // grep -qE '^[[:space:]]*[^#[:space:]]+:customDomain:'
    for line in content.split(|&c| c == b'\n') {
        let trimmed = {
            let mut s = line;
            while s.first().map_or(false, |&c| c == b' ' || c == b'\t') {
                s = &s[1..];
            }
            s
        };
        if trimmed.is_empty() || trimmed[0] == b'#' {
            continue;
        }
        if shell_compat::contains(trimmed, b":customDomain:") {
            // Verify the prefix is non-whitespace, non-comment chars
            let colon_pos = trimmed
                .windows(b":customDomain:".len())
                .position(|w| w == b":customDomain:");
            if let Some(pos) = colon_pos {
                if pos > 0 {
                    let prefix = &trimmed[..pos];
                    if prefix.iter().all(|&c| c != b' ' && c != b'\t' && c != b'#') {
                        return true;
                    }
                }
            }
        }
    }
    false
}

struct WorkDir {
    path: Vec<u8>,
}

impl WorkDir {
    fn new() -> Option<Self> {
        mktemp_dir().ok().map(|p| Self { path: p })
    }

    fn file(&self, name: &[u8]) -> Vec<u8> {
        cat(&[&self.path, b"/", name])
    }
}

impl Drop for WorkDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(shell_compat::path(&self.path));
    }
}

/// sv_call: call the Site Verification API; the body lands in `resp_file`.
/// Returns the HTTP code curl printed and curl's own exit status: where the
/// script ran it under `set -e`, a curl that failed outright ended the run
/// with that status.
fn sv_call(
    method: &[u8],
    url: &[u8],
    body: &[u8],
    token: &[u8],
    quota_project: &[u8],
    resp_file: &[u8],
) -> (Vec<u8>, i32) {
    let mut args: Vec<Vec<u8>> = vec![
        b"-sS".to_vec(),
        b"-o".to_vec(),
        resp_file.to_vec(),
        b"-w".to_vec(),
        b"%{http_code}".to_vec(),
        b"-X".to_vec(),
        method.to_vec(),
        b"-H".to_vec(),
        cat(&[b"Authorization: Bearer ", token]),
        b"-H".to_vec(),
        b"Content-Type: application/json".to_vec(),
    ];
    if !quota_project.is_empty() {
        args.push(b"-H".to_vec());
        args.push(cat(&[b"x-goog-user-project: ", quota_project]));
    }
    if !body.is_empty() {
        args.push(b"-d".to_vec());
        args.push(body.to_vec());
    }
    args.push(url.to_vec());
    let mut cmd = Command::new("curl");
    for a in &args {
        cmd.arg(os(a));
    }
    let r = capture_stdout(0, &mut cmd);
    (subst(r.stdout), r.status)
}

/// cf_call: call the Cloudflare API. Returns http_code.
fn cf_call(method: &[u8], url: &[u8], body: &[u8], token: &[u8], resp_file: &[u8]) -> Vec<u8> {
    let mut args: Vec<Vec<u8>> = vec![
        b"-sS".to_vec(),
        b"-o".to_vec(),
        resp_file.to_vec(),
        b"-w".to_vec(),
        b"%{http_code}".to_vec(),
        b"-X".to_vec(),
        method.to_vec(),
        b"-H".to_vec(),
        cat(&[b"Authorization: Bearer ", token]),
        b"-H".to_vec(),
        b"Content-Type: application/json".to_vec(),
    ];
    if !body.is_empty() {
        args.push(b"-d".to_vec());
        args.push(body.to_vec());
    }
    args.push(url.to_vec());
    let mut cmd = Command::new("curl");
    for a in &args {
        cmd.arg(os(a));
    }
    let r = capture_stdout(0, &mut cmd);
    subst(r.stdout)
}

/// Read a jq expression from a file.
fn jq_file(file: &[u8], expr: &str) -> Vec<u8> {
    let r = capture_stdout(0, Command::new("jq").arg("-r").arg(expr).arg(os(file)));
    subst(r.stdout)
}

/// Read a jq expression from a file with --arg.
fn jq_file_arg(file: &[u8], expr: &str, argname: &str, argval: &[u8]) -> Vec<u8> {
    let r = capture_stdout(
        0,
        Command::new("jq")
            .arg("-r")
            .arg("--arg")
            .arg(argname)
            .arg(os(argval))
            .arg(expr)
            .arg(os(file)),
    );
    subst(r.stdout)
}

fn sv_error_summary(resp_file: &[u8]) -> Vec<u8> {
    let r = capture(
        0,
        Command::new("jq")
            .arg("-r")
            .arg(r#".error.message // "unknown error""#)
            .arg(os(resp_file)),
    );
    if r.ok() {
        subst(r.stdout)
    } else {
        b"unparseable error body".to_vec()
    }
}

/// URL-encode a string using jq's @uri filter.
fn jq_uri_encode(value: &[u8]) -> Vec<u8> {
    let r = capture_stdout(
        0,
        Command::new("jq")
            .arg("-rn")
            .arg("--arg")
            .arg("v")
            .arg(os(value))
            .arg("$v|@uri"),
    );
    subst(r.stdout)
}

/// Build a JSON body string using jq -n.
fn jq_build(expr: &str, args: &[(&str, &[u8])]) -> Vec<u8> {
    let mut cmd = Command::new("jq");
    cmd.arg("-n");
    for (name, val) in args {
        cmd.arg("--arg").arg(*name).arg(os(val));
    }
    cmd.arg(expr);
    let r = capture_stdout(0, &mut cmd);
    subst(r.stdout)
}

fn get_verification_token(
    zone: &[u8],
    sv_base: &[u8],
    sv_token: &[u8],
    quota_project: &[u8],
    resp_file: &[u8],
) -> Option<Vec<u8>> {
    for method in &[b"DNS_TXT" as &[u8], b"DNS"] {
        let body = cat(&[
            b"{\"site\":{\"identifier\":\"",
            zone,
            b"\",\"type\":\"INET_DOMAIN\"},\"verificationMethod\":\"",
            method,
            b"\"}",
        ]);
        let url = cat(&[sv_base, b"/token"]);
        // Called as `txt="$(get_verification_token ...)" || return 1`: errexit
        // is off there, so a failed curl is just a non-200 code.
        let (code, _) = sv_call(b"POST", &url, &body, sv_token, quota_project, resp_file);
        if code == b"200" {
            let token = jq_file(resp_file, r#".token // empty"#);
            if !token.is_empty() {
                if token.starts_with(b"google-site-verification=") {
                    return Some(token);
                } else {
                    return Some(cat(&[b"google-site-verification=", &token]));
                }
            }
        }
        log_err(&cat(&[
            b"getToken(",
            method,
            b") for ",
            zone,
            b" -> HTTP ",
            &code,
            b": ",
            &sv_error_summary(resp_file),
        ]));
    }
    None
}

fn ensure_cloudflare_txt(
    zone: &[u8],
    txt: &[u8],
    cf_base: &[u8],
    cf_token: &[u8],
    resp_file: &[u8],
) -> bool {
    // Look up zone ID.
    let url = cat(&[cf_base, b"/zones?name=", zone, b"&status=active"]);
    let code = cf_call(b"GET", &url, b"", cf_token, resp_file);
    if code != b"200" {
        log_err(&cat(&[
            b"Cloudflare zone lookup for ",
            zone,
            b" -> HTTP ",
            &code,
        ]));
        return false;
    }
    let zone_id = jq_file(resp_file, r#".result[0].id // empty"#);
    if zone_id.is_empty() {
        log_err(&cat(&[
            b"Cloudflare zone ",
            zone,
            b" not found (token needs Zone.Read on it)",
        ]));
        return false;
    }

    // List existing TXT records.
    let url = cat(&[
        cf_base,
        b"/zones/",
        &zone_id,
        b"/dns_records?type=TXT&name=",
        zone,
        b"&per_page=100",
    ]);
    let code = cf_call(b"GET", &url, b"", cf_token, resp_file);
    if code != b"200" {
        log_err(&cat(&[
            b"Cloudflare TXT list for ",
            zone,
            b" -> HTTP ",
            &code,
        ]));
        return false;
    }

    // Check if our TXT is already present (compare unquoted).
    let have = jq_file_arg(
        resp_file,
        r#"[.result[].content | gsub("^\"|\"$"; "")] | any(. == $txt)"#,
        "txt",
        txt,
    );
    if have == b"true" {
        log(&cat(&[b"TXT already present on ", zone]));
        return true;
    }

    // Create the TXT record.
    let body = jq_build(
        r#"{type:"TXT", name:$name, content:$content, ttl:300, comment:"google-site-verification (Cloud Run) - do not delete; see ensure-site-verification.sh"}"#,
        &[("name", zone), ("content", txt)],
    );
    let url = cat(&[cf_base, b"/zones/", &zone_id, b"/dns_records"]);
    let code = cf_call(b"POST", &url, &body, cf_token, resp_file);
    if code != b"200" {
        let preview = std::fs::read(shell_compat::path(resp_file)).unwrap_or_default();
        let preview = if preview.len() > 400 {
            &preview[..400]
        } else {
            &preview
        };
        log_err(&cat(&[
            b"Cloudflare TXT create on ",
            zone,
            b" -> HTTP ",
            &code,
            b": ",
            preview,
        ]));
        return false;
    }
    log(&cat(&[b"created TXT on ", zone]));
    true
}

fn wait_for_txt(zone: &[u8], txt: &[u8], doh_base: &[u8]) -> bool {
    for i in 1..=24 {
        let url = cat(&[doh_base, b"/resolve?name=", zone, b"&type=TXT"]);
        let r = capture_stdout(0, Command::new("curl").arg("-sS").arg(os(&url)));
        if r.ok() {
            // Pipe through jq to check.
            let mut jq = Command::new("jq");
            jq.arg("-e")
                .arg("--arg")
                .arg("txt")
                .arg(os(txt))
                .arg(r#"[.Answer[]?.data | gsub("\""; "")] | any(. == $txt)"#)
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::null());
            let rc = shell_compat::status_with_input(0, &mut jq, &r.stdout, true);
            if rc == 0 {
                log(&cat(&[
                    b"TXT visible in public DNS (attempt ",
                    i.to_string().as_bytes(),
                    b")",
                ]));
                return true;
            }
        }
        log(&cat(&[
            b"waiting for TXT propagation on ",
            zone,
            b" (attempt ",
            i.to_string().as_bytes(),
            b"/24)...",
        ]));
        std::thread::sleep(std::time::Duration::from_secs(10));
    }
    log_err(&cat(&[b"TXT for ", zone, b" not visible after ~4min"]));
    false
}

fn verify_zone(
    zone: &[u8],
    sv_base: &[u8],
    sv_token: &[u8],
    quota_project: &[u8],
    cf_base: &[u8],
    cf_token: &[u8],
    doh_base: &[u8],
    resp_file: &[u8],
) -> Result<(), i32> {
    let txt = match get_verification_token(zone, sv_base, sv_token, quota_project, resp_file) {
        Some(t) => t,
        None => return Err(1),
    };
    if !ensure_cloudflare_txt(zone, &txt, cf_base, cf_token, resp_file) {
        return Err(1);
    }
    if !wait_for_txt(zone, &txt, doh_base) {
        return Err(1);
    }
    // Retry insert — Google's own resolvers can lag public visibility.
    for i in 1..=8 {
        for method in &[b"DNS_TXT" as &[u8], b"DNS"] {
            let url = cat(&[sv_base, b"/webResource?verificationMethod=", method]);
            let body = cat(&[
                b"{\"site\":{\"identifier\":\"",
                zone,
                b"\",\"type\":\"INET_DOMAIN\"}}",
            ]);
            // verify_zone runs as a plain command under `set -e`: a curl
            // that fails outright ends the whole run with its status.
            let (code, curl_rc) = sv_call(b"POST", &url, &body, sv_token, quota_project, resp_file);
            if curl_rc != 0 {
                return Err(curl_rc);
            }
            if code == b"200" {
                log(&cat(&[zone, b" verified (method ", method, b")"]));
                return Ok(());
            }
            log(&cat(&[
                b"insert(",
                method,
                b") ",
                zone,
                b" -> HTTP ",
                &code,
                b": ",
                &sv_error_summary(resp_file),
                b" (attempt ",
                i.to_string().as_bytes(),
                b"/8)",
            ]));
        }
        std::thread::sleep(std::time::Duration::from_secs(30));
    }
    log_err(&cat(&[
        b"verification insert for ",
        zone,
        b" did not succeed",
    ]));
    Err(1)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    // --- env setup ---
    let app_dir = {
        let v = env_or_empty("APP_DIR");
        if !v.is_empty() {
            v
        } else if shell_compat::is_dir(b"apps/web/oauth-user-inspector/infra/app") {
            b"apps/web/oauth-user-inspector/infra/app".to_vec()
        } else {
            b"oauth-user-inspector/infra/app".to_vec()
        }
    };

    let sv_base = env_or(
        "SITEVERIFY_API_BASE",
        b"https://www.googleapis.com/siteVerification/v1",
    );
    let cf_base = env_or(
        "CLOUDFLARE_API_BASE",
        b"https://api.cloudflare.com/client/v4",
    );
    let doh_base = env_or("DOH_API_BASE", b"https://dns.google");

    for tool in &[b"curl" as &[u8], b"jq"] {
        if shell_compat::which(tool).is_none() {
            log_err(&cat(&[tool, b" not found on PATH"]));
            return 1;
        }
    }

    // --- 1. Collect zones from Pulumi env files ---
    let deploy_env = env_or_empty("DEPLOY_ENV");
    let env_files: Vec<Vec<u8>> = if !deploy_env.is_empty() {
        let f = cat(&[&app_dir, b"/Pulumi.", &deploy_env, b".yaml"]);
        if !shell_compat::exists(&f) {
            log_err(&cat(&[&f, b" not found (DEPLOY_ENV=", &deploy_env, b")"]));
            return 1;
        }
        vec![f]
    } else {
        // Glob: app_dir/Pulumi.*.yaml
        let dir = shell_compat::path(&app_dir);
        let mut files = Vec::new();
        if let Ok(entries) = std::fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let name_os = entry.file_name();
                let name = name_os.as_encoded_bytes();
                if name.starts_with(b"Pulumi.")
                    && name.ends_with(b".yaml")
                    && name != b"Pulumi.yaml"
                {
                    let mut full = app_dir.clone();
                    full.push(b'/');
                    full.extend_from_slice(name);
                    files.push(full);
                }
            }
        }
        files.sort();
        files
    };

    let mut zones: Vec<Vec<u8>> = Vec::new();
    for f in &env_files {
        if !shell_compat::exists(f) {
            continue;
        }
        let dom = cfg_get(f, b"customDomain");
        if dom.is_empty() {
            if has_custom_domain_line(f) {
                log_err(&cat(&[
                    &shell_compat::basename(f),
                    b" declares a customDomain but it could not be parsed \
                     \xe2\x80\x94 refusing to report success",
                ]));
                return 1;
            }
            continue;
        }
        let zone = cfg_get(f, b"cloudflareZone");
        if zone.is_empty() {
            log_err(&cat(&[
                &shell_compat::basename(f),
                b" sets customDomain=",
                &dom,
                b" but no cloudflareZone \xe2\x80\x94 refusing to guess the zone",
            ]));
            return 1;
        }
        if !zones.iter().any(|z| z == &zone) {
            zones.push(zone.clone());
        }
        log(&cat(&[
            &shell_compat::basename(f),
            b": ",
            &dom,
            b" -> zone ",
            &zone,
        ]));
    }

    if zones.is_empty() {
        let mut msg = b"no customDomain configured".to_vec();
        if !deploy_env.is_empty() {
            msg.extend_from_slice(b" for ");
            msg.extend_from_slice(&deploy_env);
        }
        msg.extend_from_slice(b" in ");
        msg.extend_from_slice(&app_dir);
        msg.extend_from_slice(b" \xe2\x80\x94 nothing to do");
        log(&msg);
        return 0;
    }

    // Required tokens.
    let sv_token = match env("SITEVERIFY_ACCESS_TOKEN") {
        Some(t) if !t.is_empty() => t,
        _ => {
            err(b"SITEVERIFY_ACCESS_TOKEN is required (siteverification-scoped OAuth token)\n");
            return 1;
        }
    };
    let cf_token = match env("CLOUDFLARE_API_TOKEN") {
        Some(t) if !t.is_empty() => t,
        _ => {
            err(b"CLOUDFLARE_API_TOKEN is required (Zone.Read + DNS.Edit)\n");
            return 1;
        }
    };
    let quota_project = env_or_empty("SITEVERIFY_QUOTA_PROJECT");

    let workdir = match WorkDir::new() {
        Some(w) => w,
        None => {
            log_err(b"failed to create temp dir");
            return 1;
        }
    };
    let resp_file = workdir.file(b"resp");
    let _ = std::fs::write(shell_compat::path(&resp_file), b"");
    let cfresp_file = workdir.file(b"cfresp");
    let _ = std::fs::write(shell_compat::path(&cfresp_file), b"");

    // --- 2-3. Converge every zone ---
    for zone in &zones {
        let id_enc = jq_uri_encode(&cat(&[b"dns://", zone]));

        // Check if already a verified owner.
        let url = cat(&[&sv_base, b"/webResource/", &id_enc]);
        let (code, curl_rc) = sv_call(b"GET", &url, b"", &sv_token, &quota_project, &resp_file);
        if curl_rc != 0 {
            return curl_rc; // `code="$(sv_call ...)"` under set -e
        }
        if code == b"200" {
            log(&cat(&[b"already a verified owner of ", zone, b"; no-op"]));
            continue;
        }

        log(&cat(&[
            b"not yet a verified owner of ",
            zone,
            b" (GET -> HTTP ",
            &code,
            b") \xe2\x80\x94 self-verifying",
        ]));

        // `verify_zone "$zone"` under set -e: its failure ends the run.
        if let Err(rc) = verify_zone(
            zone,
            &sv_base,
            &sv_token,
            &quota_project,
            &cf_base,
            &cf_token,
            &doh_base,
            &resp_file,
        ) {
            return rc;
        }

        // Assert convergence.
        let url = cat(&[&sv_base, b"/webResource/", &id_enc]);
        let (code, curl_rc) = sv_call(b"GET", &url, b"", &sv_token, &quota_project, &resp_file);
        if curl_rc != 0 {
            return curl_rc;
        }
        if code != b"200" {
            log_err(&cat(&[
                b"webResource GET for ",
                zone,
                b" still failing after insert (HTTP ",
                &code,
                b"): ",
                &sv_error_summary(&resp_file),
            ]));
            return 1;
        }
        log(&cat(&[zone, b" converged (caller is a verified owner)"]));
    }

    log(b"done");
    0
}
