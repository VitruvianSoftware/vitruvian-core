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

//! `seal-backstage-mcp-token` and `backstage-mcp-probe`: manage and verify the
//! static read-only service token used by unattended agents to query Backstage's
//! MCP server. Plaintext tokens are never printed, passed on argv, or committed.

use std::fs;
use std::io::Write;
use std::os::unix::ffi::OsStringExt;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Stdio;

use serde_json::Value;
use shell_compat as sc;

use super::common::*;
use super::seal::has_sealed_value;

const NAMESPACE: &str = "backstage";
const SECRET_NAME: &str = "backstage-mcp-agent-token";
const SECRET_KEY: &str = "token";
const TOKEN_STORE_REL: &str =
    "tools/sync-env-secrets/secrets/agent-tokens/BACKSTAGE_MCP_AGENT_TOKEN";
const DEFAULT_MCP_URL: &str = "https://backstage.vitruviansoftware.dev/api/mcp-actions/v1";

struct TempDirGuard(PathBuf);

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn trim_trailing_newlines(mut raw: Vec<u8>) -> Vec<u8> {
    while matches!(raw.last(), Some(b'\n' | b'\r')) {
        raw.pop();
    }
    raw
}

/// Validates that a token meets Backstage's static externalAccess constraints
/// (`>= 8` chars, non-whitespace ASCII graphic bytes only).
pub fn validate_token(token: &[u8]) -> Result<(), String> {
    if token.len() < 8 {
        return Err(format!(
            "token is too short ({} bytes; expected at least 8)",
            token.len()
        ));
    }
    if !token.iter().all(|b| b.is_ascii_graphic()) {
        return Err("token must contain only non-whitespace printable ASCII characters".into());
    }
    Ok(())
}

/// Resolves the MCP token: environment variable first, then the local store file.
pub fn resolve_token_from(env_val: Option<&[u8]>, store_path: &Path) -> Result<Vec<u8>, String> {
    if let Some(raw) = env_val {
        let trimmed = trim_trailing_newlines(raw.to_vec());
        if !trimmed.is_empty() {
            validate_token(&trimmed)
                .map_err(|e| format!("BACKSTAGE_MCP_AGENT_TOKEN env var invalid: {e}"))?;
            return Ok(trimmed);
        }
    }
    match fs::read(store_path) {
        Ok(raw) => {
            let trimmed = trim_trailing_newlines(raw);
            if trimmed.is_empty() {
                return Err(format!(
                    "token file {} is empty; remove it and re-run `bazel run //tools/gitops:seal-backstage-mcp-token`",
                    store_path.display()
                ));
            }
            validate_token(&trimmed).map_err(|e| {
                format!(
                    "token file {} is invalid: {e}",
                    store_path.display()
                )
            })?;
            Ok(trimmed)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Err(format!(
            "no BACKSTAGE_MCP_AGENT_TOKEN found in environment or at {} (run `bazel run //tools/gitops:seal-backstage-mcp-token` first)",
            store_path.display()
        )),
        Err(e) => Err(format!("cannot read {}: {e}", store_path.display())),
    }
}

fn workspace_store_path() -> PathBuf {
    match sc::env("BUILD_WORKSPACE_DIRECTORY") {
        Some(dir) if !dir.is_empty() => PathBuf::from(sc::os(&dir)).join(TOKEN_STORE_REL),
        _ => PathBuf::from(TOKEN_STORE_REL),
    }
}

fn write_token_file(path: &Path, token: &[u8]) -> Res<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| {
            warn(format!("ERROR: cannot create {}: {e}", parent.display()).as_bytes());
            1
        })?;
        let _ = fs::set_permissions(parent, fs::Permissions::from_mode(0o700));
    }
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .map_err(|e| {
            warn(format!("ERROR: cannot create {}: {e}", path.display()).as_bytes());
            1
        })?;
    f.write_all(token).map_err(|e| {
        warn(format!("ERROR: cannot write {}: {e}", path.display()).as_bytes());
        1
    })?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|e| {
        warn(format!("ERROR: cannot chmod 600 {}: {e}", path.display()).as_bytes());
        1
    })?;
    Ok(())
}

// ---------------------------------------------------------------------------
// seal-backstage-mcp-token
// ---------------------------------------------------------------------------

pub fn seal_token(args: &[Vec<u8>]) -> i32 {
    match seal_token_run(args) {
        Ok(c) | Err(c) => c,
    }
}

fn seal_token_run(args: &[Vec<u8>]) -> Res<i32> {
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

    default_kubeconfig(0)?;
    let k = kctx();
    need_tools(&["kubectl", "kubeseal", "openssl"], false)?;
    cd_workspace(0)?;

    let store_path = Path::new(TOKEN_STORE_REL);
    let token = if store_path.exists() {
        let raw = fs::read(store_path).map_err(|e| {
            warn(format!("ERROR: cannot read {TOKEN_STORE_REL}: {e}").as_bytes());
            1
        })?;
        let trimmed = trim_trailing_newlines(raw);
        if let Err(e) = validate_token(&trimmed) {
            return die(
                1,
                format!("ERROR: existing token in {TOKEN_STORE_REL} is invalid ({e}).").as_bytes(),
            );
        }
        say(format!("reusing existing token at {TOKEN_STORE_REL}").as_bytes());
        trimmed
    } else {
        let (st, generated) = capture(0, cmd("openssl", &[b"rand", b"-hex", b"32"]));
        if st != 0 {
            return Err(st);
        }
        let trimmed = trim_trailing_newlines(generated);
        if trimmed.len() != 64 || validate_token(&trimmed).is_err() {
            return die(1, b"ERROR: failed to generate a 32-byte random token.");
        }
        write_token_file(store_path, &trimmed)?;
        say(format!("generated 32-byte token -> {TOKEN_STORE_REL} (mode 600)").as_bytes());
        trimmed
    };

    let tmp_dir_bytes = mktemp_dir_named("seal-backstage-mcp-token").map_err(|e| {
        warn(format!("ERROR: mktemp failed: {e}").as_bytes());
        1
    })?;
    let tmp_dir = PathBuf::from(sc::os(&tmp_dir_bytes));
    let _guard = TempDirGuard(tmp_dir.clone());
    let tmp_out = tmp_dir
        .join(format!("{SECRET_NAME}.sealedsecret.yaml"))
        .into_os_string()
        .into_vec();

    let header = format!(
        "{}#\n# Generated by `bazel run //tools/gitops:seal-backstage-mcp-token`.\n# Read-only static service token for unattended agent Backstage MCP access.\n",
        LICENSE_HEADER
    );
    write_new(0, &tmp_out, header.as_bytes())?;
    let st = seal_value(0, &k, NAMESPACE, SECRET_NAME, SECRET_KEY, &token, &tmp_out);
    drop(token);
    if st != 0 {
        return Err(st);
    }

    let sealed_bytes = fs::read(sc::path(&tmp_out)).unwrap_or_default();
    if !has_sealed_value(&sealed_bytes, SECRET_KEY) {
        return die(
            1,
            format!(
                "ERROR: kubeseal produced no sealed value under {SECRET_KEY} -- nothing written."
            )
            .as_bytes(),
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
    match fs::File::open(sc::path(&tmp_out)) {
        Ok(f) => {
            validate.stdin(f);
        }
        Err(e) => {
            return die(
                1,
                format!("ERROR: cannot reopen sealed manifest: {e}").as_bytes(),
            );
        }
    }
    let vst = run(0, &mut validate, false);
    if vst != 0 {
        return Err(vst);
    }

    let out = format!("{}/{}.sealedsecret.yaml", SEALED_DIR, SECRET_NAME).into_bytes();
    mv(0, &tmp_out, &out)?;
    say(&sc::cat(&[
        "\u{2713} sealed \u{2192} ".as_bytes(),
        &out,
        format!(" (SealedSecret {NAMESPACE}/{SECRET_NAME}, key {SECRET_KEY})").as_bytes(),
    ]));

    if apply {
        let ast = run(0, &mut kubectl(&k, &[b"apply", b"-f", &out]), false);
        if ast != 0 {
            return Err(ast);
        }
        say(
            format!(
                "\u{2713} applied \u{2014} the sealed-secrets controller will materialize {NAMESPACE}/{SECRET_NAME}"
            )
            .as_bytes(),
        );
    } else {
        say(&sc::cat(&[
            b"next: commit ",
            &out,
            b" (ArgoCD applies it), and push plaintext to Bitwarden from the main checkout (`bazel run //tools/sync-env-secrets:bw-push`)",
        ]));
    }
    Ok(0)
}

// ---------------------------------------------------------------------------
// backstage-mcp-probe
// ---------------------------------------------------------------------------

/// Formats a curl `-K` header line without exposing the token on argv.
pub fn curl_auth_config(token: &[u8]) -> String {
    let raw = String::from_utf8_lossy(token);
    let escaped = raw.replace('\\', "\\\\").replace('"', "\\\"");
    format!("header = \"Authorization: Bearer {escaped}\"\n")
}

/// Parses either a plain JSON-RPC body or an MCP Streamable HTTP SSE stream.
pub fn parse_mcp_body(body: &[u8]) -> Result<Value, String> {
    let text = String::from_utf8_lossy(body);
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err("empty response body".into());
    }
    if trimmed.starts_with('{') || trimmed.starts_with('[') {
        return serde_json::from_str(trimmed).map_err(|e| format!("invalid JSON response: {e}"));
    }
    let mut last_json: Option<Value> = None;
    let mut data_buf = String::new();
    for line in trimmed.lines() {
        let line = line.trim_end_matches('\r');
        if let Some(rest) = line.strip_prefix("data:") {
            let chunk = rest.trim_start();
            if !data_buf.is_empty() {
                data_buf.push('\n');
            }
            data_buf.push_str(chunk);
        } else if line.is_empty() && !data_buf.is_empty() {
            if let Ok(v) = serde_json::from_str::<Value>(data_buf.trim()) {
                last_json = Some(v);
            }
            data_buf.clear();
        }
    }
    if !data_buf.is_empty() {
        if let Ok(v) = serde_json::from_str::<Value>(data_buf.trim()) {
            last_json = Some(v);
        }
    }
    last_json.ok_or_else(|| "response was neither JSON nor an SSE data frame".into())
}

fn extract_mcp_error_text(val: &Value) -> Option<(bool, String)> {
    if let Some(err) = val.get("error") {
        let msg = err
            .get("message")
            .and_then(|v| v.as_str())
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| err.to_string());
        return Some((true, msg));
    }
    let result = val.get("result")?;
    if result.get("isError").and_then(|v| v.as_bool()) == Some(true) {
        let texts: Vec<&str> = result
            .get("content")
            .and_then(|c| c.as_array())
            .into_iter()
            .flatten()
            .filter_map(|item| item.get("text").and_then(|t| t.as_str()))
            .collect();
        let combined = if texts.is_empty() {
            result.to_string()
        } else {
            texts.join(" | ")
        };
        return Some((true, combined));
    }
    Some((false, String::new()))
}

/// Counts a write refusal ONLY when it reflects an authorization denial
/// (HTTP 401/403 or permission error), rejecting validation/not-found errors.
pub fn classify_write_refusal(http_status: u16, body: &[u8]) -> Result<String, String> {
    if http_status == 403 {
        return Ok("HTTP 403 Forbidden".into());
    }
    if http_status == 401 {
        return Err("HTTP 401 Unauthorized (token was rejected, not permission-denied)".into());
    }

    let parsed = parse_mcp_body(body).map_err(|e| format!("HTTP {http_status}, {e}"))?;
    let (is_err, err_text) = extract_mcp_error_text(&parsed)
        .ok_or_else(|| format!("HTTP {http_status}: missing MCP error/result payload"))?;
    if !is_err {
        return Err("write action unexpectedly succeeded".into());
    }

    let lower = err_text.to_ascii_lowercase();
    for bad in [
        "inputerror",
        "invalid location url",
        "invalid input",
        "notfounderror",
        "400 bad request",
        "404 not found",
    ] {
        if lower.contains(bad) {
            return Err(format!(
                "refused with validation/non-auth error ({err_text}), not authorization denial"
            ));
        }
    }

    for auth_marker in [
        "notallowederror",
        "403",
        "forbidden",
        "permission",
        "not allowed",
        "restricted and cannot be delegated",
        "not included in token",
        "access is restricted",
        "unauthorized",
    ] {
        if lower.contains(auth_marker) {
            return Ok(err_text);
        }
    }

    Err(format!("refused with non-authorization error ({err_text})"))
}

fn extract_catalog_items(val: &Value) -> Result<usize, String> {
    let (is_err, err_text) =
        extract_mcp_error_text(val).ok_or_else(|| "missing MCP result payload".to_string())?;
    if is_err {
        return Err(err_text);
    }
    let result = &val["result"];
    if let Some(items) = result
        .get("structuredContent")
        .and_then(|sc| sc.get("items"))
        .and_then(|i| i.as_array())
    {
        return Ok(items.len());
    }
    if let Some(text) = result
        .get("content")
        .and_then(|c| c.as_array())
        .and_then(|arr| arr.first())
        .and_then(|item| item.get("text"))
        .and_then(|t| t.as_str())
    {
        let inner: Value = serde_json::from_str(text)
            .map_err(|e| format!("catalog tool text was not JSON: {e}"))?;
        if let Some(items) = inner.get("items").and_then(|i| i.as_array()) {
            return Ok(items.len());
        }
    }
    Err("catalog tool response did not contain an items array".into())
}

fn mcp_post(url: &str, auth_cfg: Option<&Path>, payload: &str) -> Res<(u16, Vec<u8>)> {
    let mut c = cmd(
        "curl",
        &[
            b"-sS",
            b"-X",
            b"POST",
            b"-H",
            b"Content-Type: application/json",
            b"-H",
            b"Accept: application/json, text/event-stream",
            b"--data-binary",
            b"@-",
            b"-w",
            b"\n%{http_code}",
        ],
    );
    if let Some(cfg) = auth_cfg {
        c.arg("-K").arg(cfg);
    }
    c.arg(url);
    c.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(e) => {
            return die(1, format!("ERROR: failed to spawn curl: {e}").as_bytes());
        }
    };
    if let Some(mut sin) = child.stdin.take() {
        let _ = sin.write_all(payload.as_bytes());
    }
    let out = match child.wait_with_output() {
        Ok(o) => o,
        Err(e) => {
            return die(1, format!("ERROR: curl failed: {e}").as_bytes());
        }
    };
    if !out.status.success() {
        let err_s = String::from_utf8_lossy(&out.stderr);
        return die(
            1,
            format!("ERROR: HTTP request failed: {}", err_s.trim()).as_bytes(),
        );
    }

    let pos = out.stdout.iter().rposition(|&b| b == b'\n');
    let (body, code_bytes) = match pos {
        Some(i) => (&out.stdout[..i], &out.stdout[i + 1..]),
        None => (&[][..], out.stdout.as_slice()),
    };
    let code_str = String::from_utf8_lossy(code_bytes).trim().to_string();
    let status: u16 = code_str.parse().map_err(|_| {
        warn(format!("ERROR: unexpected HTTP status '{code_str}' from curl").as_bytes());
        1
    })?;
    Ok((status, body.to_vec()))
}

pub fn probe(args: &[Vec<u8>]) -> i32 {
    match probe_run(args) {
        Ok(c) | Err(c) => c,
    }
}

fn probe_run(args: &[Vec<u8>]) -> Res<i32> {
    if !args.is_empty() {
        return die(
            2,
            b"ERROR: backstage-mcp-probe takes no positional arguments.",
        );
    }
    need_tools(&["curl"], false)?;

    let env_token = sc::env("BACKSTAGE_MCP_AGENT_TOKEN");
    let store_path = workspace_store_path();
    let token = match resolve_token_from(env_token.as_deref(), &store_path) {
        Ok(t) => t,
        Err(e) => return die(1, format!("ERROR: {e}").as_bytes()),
    };

    let url_bytes = sc::env_or("BACKSTAGE_MCP_URL", DEFAULT_MCP_URL.as_bytes());
    let url = String::from_utf8_lossy(&url_bytes).into_owned();

    let tmp_dir_bytes = mktemp_dir_named("backstage-mcp-probe").map_err(|e| {
        warn(format!("ERROR: mktemp failed: {e}").as_bytes());
        1
    })?;
    let tmp_dir = PathBuf::from(sc::os(&tmp_dir_bytes));
    let _guard = TempDirGuard(tmp_dir.clone());
    let cfg_path = tmp_dir.join("curl-auth.cfg");
    {
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&cfg_path)
            .map_err(|e| {
                warn(format!("ERROR: cannot create curl config: {e}").as_bytes());
                1
            })?;
        let cfg = curl_auth_config(&token);
        drop(token);
        f.write_all(cfg.as_bytes()).map_err(|e| {
            warn(format!("ERROR: cannot write curl config: {e}").as_bytes());
            1
        })?;
        let _ = fs::set_permissions(&cfg_path, fs::Permissions::from_mode(0o600));
    }

    let tools_list_req = r#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#;

    // 1. No token -> 401
    let (status, _) = mcp_post(&url, None, tools_list_req)?;
    if status != 401 {
        return die(
            1,
            format!("\u{2717} unauthenticated request returned HTTP {status}, expected 401")
                .as_bytes(),
        );
    }
    say("\u{2713} no-token request rejected (HTTP 401)".as_bytes());

    // 2. With token -> tools/list works
    let (status, body) = mcp_post(&url, Some(&cfg_path), tools_list_req)?;
    if status == 401 {
        return die(
            1,
            "\u{2717} authenticated tools/list returned HTTP 401 (server has not picked up backstage-mcp-agent-token yet)".as_bytes(),
        );
    }
    if status != 200 {
        return die(
            1,
            format!("\u{2717} authenticated tools/list returned HTTP {status}").as_bytes(),
        );
    }
    let list_json = parse_mcp_body(&body).map_err(|e| {
        warn(format!("\u{2717} authenticated tools/list parse failed: {e}").as_bytes());
        1
    })?;
    let tools_len = list_json
        .get("result")
        .and_then(|r| r.get("tools"))
        .and_then(|t| t.as_array())
        .map(|a| a.len())
        .unwrap_or(0);
    if tools_len == 0 {
        return die(
            1,
            "\u{2717} authenticated tools/list returned 0 tools (expected catalog read tools)"
                .as_bytes(),
        );
    }
    say(format!("\u{2713} authenticated tools/list returned {tools_len} tools").as_bytes());

    // 3. With token -> catalog query for kind: Component, spec.type: library returns entities
    let read_req = r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_entities","arguments":{"filter":{"kind":"Component","spec.type":"library"}}}}"#;
    let (status, body) = mcp_post(&url, Some(&cfg_path), read_req)?;
    if status != 200 {
        return die(
            1,
            format!("\u{2717} catalog library read returned HTTP {status}").as_bytes(),
        );
    }
    let read_json = parse_mcp_body(&body).map_err(|e| {
        warn(format!("\u{2717} catalog library read parse failed: {e}").as_bytes());
        1
    })?;
    let count = extract_catalog_items(&read_json).map_err(|e| {
        warn(format!("\u{2717} catalog library read failed: {e}").as_bytes());
        1
    })?;
    if count == 0 {
        return die(
            1,
            "\u{2717} catalog read (kind=Component, spec.type=library) returned 0 entities"
                .as_bytes(),
        );
    }
    say(format!(
        "\u{2713} catalog read (kind=Component, spec.type=library) returned {count} entities"
    )
    .as_bytes());

    // 4. With token -> write actions refused by authorization (not validation)
    let write_checks = [
        (
            "register_entity",
            r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"register_entity","arguments":{"location_url":"https://probe-denied.invalid/catalog-info.yaml"}}}"#,
        ),
        (
            "unregister_entity",
            r#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"unregister_entity","arguments":{"location_id":"00000000-0000-0000-0000-000000000000"}}}"#,
        ),
    ];
    for (name, payload) in write_checks {
        let (status, body) = mcp_post(&url, Some(&cfg_path), payload)?;
        match classify_write_refusal(status, &body) {
            Ok(reason) => {
                say(
                    format!("\u{2713} write action '{name}' refused by authorization ({reason})")
                        .as_bytes(),
                );
            }
            Err(err) => {
                return die(
                    1,
                    format!("\u{2717} write action '{name}' check failed: {err}").as_bytes(),
                );
            }
        }
    }

    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_token_shape() {
        assert!(validate_token(
            b"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        )
        .is_ok());
        assert!(validate_token(b"short").is_err());
        assert!(validate_token(b"has space123").is_err());
        assert!(validate_token(b"").is_err());
    }

    #[test]
    fn resolves_env_before_store_file() {
        let dir = PathBuf::from(sc::os(&mktemp_dir_named("probe-resolve-test").unwrap()));
        let _g = TempDirGuard(dir.clone());
        let store = dir.join("BACKSTAGE_MCP_AGENT_TOKEN");
        fs::write(&store, b"from-store-token\n").unwrap();

        assert_eq!(
            resolve_token_from(Some(b"from-env-token\n"), &store).unwrap(),
            b"from-env-token"
        );
        assert_eq!(
            resolve_token_from(None, &store).unwrap(),
            b"from-store-token"
        );
        assert_eq!(
            resolve_token_from(Some(b""), &store).unwrap(),
            b"from-store-token"
        );
        assert!(resolve_token_from(None, &dir.join("missing")).is_err());
    }

    #[test]
    fn parses_json_and_sse_mcp_responses() {
        let plain = br#"{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"get_entities"}]}}"#;
        let v = parse_mcp_body(plain).unwrap();
        assert_eq!(v["result"]["tools"][0]["name"], "get_entities");

        let sse = b"event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"isError\":false}}\n\n";
        let v = parse_mcp_body(sse).unwrap();
        assert_eq!(v["id"], 2);
    }

    #[test]
    fn classifies_write_refusal_strictly() {
        assert!(classify_write_refusal(403, b"").is_ok());
        assert!(classify_write_refusal(401, b"").is_err());

        let denied = br#"{"jsonrpc":"2.0","id":3,"result":{"isError":true,"content":[{"type":"text","text":"NotAllowedError: Access to target plugin 'catalog' is restricted"}]}}"#;
        assert!(classify_write_refusal(200, denied).is_ok());

        let invalid_url = br#"{"jsonrpc":"2.0","id":3,"result":{"isError":true,"content":[{"type":"text","text":"Invalid location URL: bad"}]}}"#;
        assert!(classify_write_refusal(200, invalid_url)
            .unwrap_err()
            .contains("validation"));

        let input_err = br#"{"jsonrpc":"2.0","id":3,"result":{"isError":true,"content":[{"type":"text","text":"InputError: Invalid input to action"}]}}"#;
        assert!(classify_write_refusal(200, input_err).is_err());

        let ok_write = br#"{"jsonrpc":"2.0","id":3,"result":{"isError":false,"content":[{"type":"text","text":"{}"}]}}"#;
        assert!(classify_write_refusal(200, ok_write)
            .unwrap_err()
            .contains("unexpectedly succeeded"));
    }

    #[test]
    fn formats_curl_auth_config_safely() {
        assert_eq!(
            curl_auth_config(b"abc123"),
            "header = \"Authorization: Bearer abc123\"\n"
        );
        assert_eq!(
            curl_auth_config(br#"a"b\c"#),
            "header = \"Authorization: Bearer a\\\"b\\\\c\"\n"
        );
    }
}
