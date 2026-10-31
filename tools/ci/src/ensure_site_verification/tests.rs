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

//! Black-box tests for //tools/ci:ensure_site_verification, the per-env
//! Google Site Verification self-verify step in _deploy-cloud-run.yaml.
//!
//! The binary runs with its real curl against an in-process mock of the Site
//! Verification API, Cloudflare and Google DoH on 127.0.0.1, which enforces
//! the real contract: insert fails until the verification TXT exists in the
//! (mock) zone, DoH only "propagates" records the zone holds, ownership is
//! caller-scoped (the GET is 200 only once THIS caller self-verified), and the
//! WRITE calls 403 unless x-goog-user-project pins the caller's own project
//! (the #948 regression). The binary needs jq at run time, as the script did:
//! the rust_test supplies the hermetic one through JQ_BIN.

use ci_testkit::{bin, write, Output, Run, TempDir};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

const CALLER: &str = "oauth-user-inspector-deploy@prj-d-test-1234.iam.gserviceaccount.com";
const WANT_TXT: &str = "google-site-verification=tok-abc-123";
const QUOTA_403: &str =
    "Site Verification API has not been used in project 715357066805 before or it is disabled";

#[derive(Default, Debug)]
struct State {
    caller_verified: bool,
    owners: Vec<String>,
    cf_records: Vec<String>,
    cf_comments: Vec<String>,
    sv_get: usize,
    sv_gettoken: usize,
    sv_insert: usize,
    sv_update: usize,
    cf_create: usize,
}

impl State {
    fn fresh() -> State {
        State {
            owners: vec!["james@example.test".into()],
            cf_records: vec!["v=spf1 -all".into()],
            ..State::default()
        }
    }
}

fn pct_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(if b[i] == b'+' { b' ' } else { b[i] });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn query(q: &str, key: &str) -> Option<String> {
    q.split('&').find_map(|kv| {
        let (k, v) = kv.split_once('=')?;
        (pct_decode(k) == key).then(|| pct_decode(v))
    })
}

fn json_str(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The first string value of `"key"` in a JSON text (enough for the flat
/// bodies the binary sends).
fn json_field(body: &str, key: &str) -> Option<String> {
    let at = body.find(&format!("\"{key}\""))? + key.len() + 2;
    let rest = &body[at..];
    let start = rest.find('"')? + 1;
    let mut out = String::new();
    let mut chars = rest[start..].chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => out.push(chars.next()?),
            '"' => return Some(out),
            c => out.push(c),
        }
    }
    None
}

struct Req {
    method: String,
    path: String,
    query: String,
    headers: Vec<(String, String)>,
    body: String,
}

impl Req {
    fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

fn read_req(stream: &mut TcpStream) -> Option<Req> {
    let mut r = BufReader::new(stream.try_clone().ok()?);
    let mut line = String::new();
    r.read_line(&mut line).ok()?;
    let mut parts = line.split_whitespace();
    let method = parts.next()?.to_string();
    let target = parts.next()?.to_string();
    let mut headers = Vec::new();
    loop {
        let mut h = String::new();
        r.read_line(&mut h).ok()?;
        let h = h.trim_end();
        if h.is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            headers.push((k.trim().to_string(), v.trim().to_string()));
        }
    }
    let mut req = Req {
        method,
        path: String::new(),
        query: String::new(),
        headers,
        body: String::new(),
    };
    if req
        .header("expect")
        .map_or(false, |v| v.eq_ignore_ascii_case("100-continue"))
    {
        let _ = stream.write_all(b"HTTP/1.1 100 Continue\r\n\r\n");
    }
    let n: usize = req
        .header("content-length")
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    let mut body = vec![0; n];
    r.read_exact(&mut body).ok()?;
    req.body = String::from_utf8_lossy(&body).into_owned();
    let (p, q) = target.split_once('?').unwrap_or((&target, ""));
    req.path = p.to_string();
    req.query = q.to_string();
    Some(req)
}

fn resource(s: &State) -> String {
    let owners: Vec<String> = s.owners.iter().map(|o| json_str(o)).collect();
    format!(
        r#"{{"id":"dns%3A%2F%2Fexample.test","site":{{"identifier":"example.test","type":"INET_DOMAIN"}},"owners":[{}]}}"#,
        owners.join(",")
    )
}

fn err_body(msg: &str) -> String {
    format!(r#"{{"error":{{"message":{}}}}}"#, json_str(msg))
}

fn handle(req: &Req, st: &Mutex<State>) -> (u16, String) {
    let mut s = st.lock().unwrap();
    let quota_pinned = req.header("x-goog-user-project") == Some("prj-d-test-1234");
    let path = req.path.as_str();
    match req.method.as_str() {
        "GET" => {
            if pct_decode(path) == "/siteVerification/v1/webResource/dns://example.test" {
                s.sv_get += 1;
                return if s.caller_verified {
                    (200, resource(&s))
                } else {
                    (
                        404,
                        r#"{"error":{"code":404,"message":"not found"}}"#.into(),
                    )
                };
            }
            if path == "/client/v4/zones" {
                let hit = query(&req.query, "name").as_deref() == Some("example.test");
                return (
                    200,
                    if hit {
                        r#"{"result":[{"id":"zid1"}]}"#
                    } else {
                        r#"{"result":[]}"#
                    }
                    .into(),
                );
            }
            if path == "/client/v4/zones/zid1/dns_records" {
                let recs: Vec<String> = s
                    .cf_records
                    .iter()
                    .map(|c| {
                        format!(
                            r#"{{"type":"TXT","name":"example.test","content":{}}}"#,
                            json_str(c)
                        )
                    })
                    .collect();
                return (200, format!(r#"{{"result":[{}]}}"#, recs.join(",")));
            }
            if path == "/resolve" {
                if query(&req.query, "name").as_deref() == Some("example.test")
                    && query(&req.query, "type").as_deref() == Some("TXT")
                {
                    let ans: Vec<String> = s
                        .cf_records
                        .iter()
                        .map(|c| format!(r#"{{"data":{}}}"#, json_str(&format!("\"{c}\""))))
                        .collect();
                    return (200, format!(r#"{{"Answer":[{}]}}"#, ans.join(",")));
                }
                return (200, "{}".into());
            }
            (404, err_body(&format!("unknown GET {path}")))
        }
        "POST" => {
            if path == "/siteVerification/v1/token" {
                if !quota_pinned {
                    return (403, err_body(QUOTA_403));
                }
                s.sv_gettoken += 1;
                if !req.body.contains(r#""type":"INET_DOMAIN""#) {
                    return (400, err_body("bad site type"));
                }
                let m = json_field(&req.body, "verificationMethod");
                if !matches!(m.as_deref(), Some("DNS_TXT") | Some("DNS")) {
                    return (400, err_body("bad method"));
                }
                return (200, r#"{"method":"DNS_TXT","token":"tok-abc-123"}"#.into());
            }
            if path == "/siteVerification/v1/webResource" {
                if !quota_pinned {
                    return (403, err_body(QUOTA_403));
                }
                s.sv_insert += 1;
                if s.cf_records.iter().any(|c| c == WANT_TXT) {
                    s.caller_verified = true;
                    if !s.owners.iter().any(|o| o == CALLER) {
                        s.owners.push(CALLER.into());
                    }
                    return (200, resource(&s));
                }
                return (400, err_body("TXT not found"));
            }
            if path == "/client/v4/zones/zid1/dns_records" {
                s.cf_create += 1;
                let content = json_field(&req.body, "content").unwrap_or_default();
                s.cf_comments
                    .push(json_field(&req.body, "comment").unwrap_or_default());
                s.cf_records.push(content);
                return (200, r#"{"success":true}"#.into());
            }
            (404, err_body(&format!("unknown POST {path}")))
        }
        "PUT" if path.starts_with("/siteVerification/v1/webResource/") => {
            // Never issued: the real API refuses any owners-list change by a
            // service account while an external token owner exists.
            s.sv_update += 1;
            (400, err_body("You cannot unverify this site owner until all associated verification tokens are removed from your site."))
        }
        _ => (404, err_body(&format!("unknown {} {path}", req.method))),
    }
}

/// The mock on an ephemeral port; lives until the test process exits.
struct Mock {
    base: String,
    state: Arc<Mutex<State>>,
}

impl Mock {
    fn start() -> Mock {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://127.0.0.1:{}", listener.local_addr().unwrap().port());
        let state = Arc::new(Mutex::new(State::fresh()));
        let st = state.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let Some(req) = read_req(&mut stream) else {
                    continue;
                };
                let (code, body) = handle(&req, &st);
                let _ = write!(
                    stream,
                    "HTTP/1.1 {code} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
            }
        });
        Mock { base, state }
    }

    fn st(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap()
    }
}

/// The hermetic jq the rust_test passes as JQ_BIN, as a PATH entry. Unset
/// (a local `cargo`-style run) falls back to the ambient PATH.
fn tool_path() -> String {
    let ambient = std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into());
    let Ok(jq) = std::env::var("JQ_BIN") else {
        return ambient;
    };
    let jq = match jq.strip_prefix("external/") {
        Some(rest) => format!("../{rest}"),
        None => jq,
    };
    let dir = std::fs::canonicalize(&jq)
        .unwrap_or_else(|e| panic!("JQ_BIN={jq}: {e}"))
        .parent()
        .unwrap()
        .to_path_buf();
    format!("{}:{ambient}", dir.display())
}

fn app_fixture(work: &TempDir) -> PathBuf {
    let app = work.join("app");
    write(
        app.join("Pulumi.development.yaml"),
        "config:\n  oauth-user-inspector:project: prj-d-test-1234\n  oauth-user-inspector:customDomain: oauth-inspector.dev.example.test\n  oauth-user-inspector:cloudflareZone: example.test\n",
    );
    write(
        app.join("Pulumi.production.yaml"),
        "config:\n  oauth-user-inspector:project: \"prj-p-test-5678\"\n  oauth-user-inspector:customDomain: \"oauth-inspector.example.test\"\n  oauth-user-inspector:cloudflareZone: \"example.test\"\n",
    );
    // An env WITHOUT a custom domain contributes nothing.
    write(
        app.join("Pulumi.nonproduction.yaml"),
        "config:\n  oauth-user-inspector:project: prj-n-test-9999\n",
    );
    app
}

/// The binary with no credentials and no endpoints: only APP_DIR/DEPLOY_ENV.
fn bare(app: &Path, deploy_env: &str) -> Run {
    Run::new(&bin("BIN"))
        .env("PATH", tool_path())
        .env("APP_DIR", app)
        .env("DEPLOY_ENV", deploy_env)
        .env_remove("SITEVERIFY_ACCESS_TOKEN")
        .env_remove("CLOUDFLARE_API_TOKEN")
        .env_remove("SITEVERIFY_QUOTA_PROJECT")
}

/// The run as _deploy-cloud-run.yaml makes it, pointed at the mock.
fn full(m: &Mock, app: &Path, deploy_env: &str) -> Run {
    bare(app, deploy_env)
        .env("SITEVERIFY_ACCESS_TOKEN", "fake-oauth-token")
        .env("CLOUDFLARE_API_TOKEN", "fake-cf-token")
        .env("SITEVERIFY_QUOTA_PROJECT", "prj-d-test-1234")
        .env(
            "SITEVERIFY_API_BASE",
            format!("{}/siteVerification/v1", m.base),
        )
        .env("CLOUDFLARE_API_BASE", format!("{}/client/v4", m.base))
        .env("DOH_API_BASE", &m.base)
}

#[track_caller]
fn ok(o: &Output) {
    assert_eq!(o.code, 0, "want exit 0\n{}", o.all());
}

// Shell tests 1-3, in order: they share one mock's state.
#[test]
fn bootstrap_then_converged_noop_then_unscoped_scan() {
    let work = TempDir::new();
    let app = app_fixture(&work);
    let m = Mock::start();

    // 1: per-env bootstrap self-verifies the calling identity (no owner PUT).
    let o = full(&m, &app, "development").go();
    ok(&o);
    {
        let s = m.st();
        assert_eq!(s.cf_create, 1, "TXT created once");
        assert!(
            s.cf_records.iter().any(|c| c == WANT_TXT),
            "TXT content: {:?}",
            s.cf_records
        );
        assert!(
            s.cf_records.iter().any(|c| c == "v=spf1 -all"),
            "pre-existing TXT untouched"
        );
        assert!(s.caller_verified, "caller verified");
        assert_eq!(s.sv_update, 0, "NO webResource.update PUT issued");
        assert!(
            s.owners.iter().any(|o| o == "james@example.test"),
            "external owner untouched"
        );
        assert_eq!(s.cf_comments.len(), 1);
        assert!(
            s.cf_comments[0].starts_with("google-site-verification (Cloud Run) - do not delete")
        );
        assert!(
            s.cf_comments[0].len() <= 100,
            "Cloudflare caps comments at 100 chars"
        );
    }
    let all = o.all();
    assert!(
        all.contains("Pulumi.development.yaml"),
        "calling env's config read: {all}"
    );
    assert!(
        !all.contains("Pulumi.production.yaml"),
        "DEPLOY_ENV scoping: {all}"
    );
    assert!(
        all.contains("example.test verified (method DNS_TXT)"),
        "{all}"
    );
    assert!(
        all.contains("example.test converged (caller is a verified owner)"),
        "{all}"
    );
    assert!(
        o.stdout
            .trim_end()
            .ends_with("ensure-site-verification: done"),
        "{}",
        o.stdout
    );

    // 2: converged run is a pure no-op.
    let o = full(&m, &app, "development").go();
    ok(&o);
    {
        let s = m.st();
        assert_eq!(
            (s.cf_create, s.sv_gettoken, s.sv_insert, s.sv_update),
            (1, 1, 1, 0),
            "no writes on a converged run"
        );
    }
    assert!(o.all().contains("already a verified owner"), "{}", o.all());

    // 3: unscoped (no DEPLOY_ENV) scans every env, still no writes.
    let o = full(&m, &app, "").go();
    ok(&o);
    let all = o.all();
    let dev = all
        .find("Pulumi.development.yaml")
        .expect("development read");
    let prod = all.find("Pulumi.production.yaml").expect("production read");
    assert!(dev < prod, "env files in glob order: {all}");
    let s = m.st();
    assert_eq!((s.cf_create, s.sv_insert, s.sv_update), (1, 1, 0));
}

// Shell test 4.
#[test]
fn calling_env_without_custom_domain_is_a_noop_needing_no_credentials() {
    let work = TempDir::new();
    let app = app_fixture(&work);
    let o = bare(&app, "nonproduction").go();
    ok(&o);
    assert!(
        o.stdout
            .contains("no customDomain configured for nonproduction in "),
        "{}",
        o.stdout
    );
    assert!(o.stdout.contains("nothing to do"), "{}", o.stdout);
}

// Shell test 5.
#[test]
fn no_custom_domain_anywhere_is_a_noop_needing_no_credentials() {
    let work = TempDir::new();
    let empty = work.join("empty-app");
    write(
        empty.join("Pulumi.development.yaml"),
        "config:\n  oauth-user-inspector:project: prj-d-test-1234\n",
    );
    let o = bare(&empty, "").go();
    ok(&o);
    assert!(o.stdout.contains("nothing to do"), "{}", o.stdout);
}

// Shell test 6: the tabula regression.
#[test]
fn a_non_oauth_config_namespace_is_parsed() {
    let work = TempDir::new();
    let other = work.join("other-app");
    write(
        other.join("Pulumi.development.yaml"),
        "config:\n  gcp:project: prj-d-test-1234\n  tabula-app:project: prj-d-test-1234\n  tabula-app:customDomain: tabula-api.dev.example.test\n  tabula-app:cloudflareZone: example.test\n",
    );
    let m = Mock::start();
    let o = full(&m, &other, "development").go();
    ok(&o);
    assert!(
        !o.all().contains("nothing to do"),
        "took the no-op path: {}",
        o.all()
    );
    assert!(
        o.all()
            .contains("tabula-api.dev.example.test -> zone example.test"),
        "{}",
        o.all()
    );
    let s = m.st();
    assert_eq!(
        s.cf_create, 1,
        "zone resolved from the tabula-app namespace"
    );
    assert!(s.caller_verified, "caller verified for the non-oauth app");
}

// Shell test 7.
#[test]
fn an_unparseable_custom_domain_fails_loudly() {
    let work = TempDir::new();
    let weird = work.join("weird-app");
    write(
        weird.join("Pulumi.development.yaml"),
        "config:\n  some.app/v2:customDomain:\n    value: tabula-api.dev.example.test\n",
    );
    let o = bare(&weird, "development").go();
    assert_ne!(o.code, 0, "must not report success: {}", o.all());
    assert!(
        o.stderr.contains("could not be parsed"),
        "the parse failure, not the no-op: {}",
        o.all()
    );
}

// Shell test 8.
#[test]
fn a_custom_domain_without_a_zone_fails_rather_than_guessing() {
    let work = TempDir::new();
    let nozone = work.join("nozone-app");
    write(
        nozone.join("Pulumi.development.yaml"),
        "config:\n  tabula-app:customDomain: tabula-api.dev.example.test\n",
    );
    let o = bare(&nozone, "development").go();
    assert_ne!(o.code, 0, "{}", o.all());
    assert!(o.stderr.contains("refusing to guess"), "{}", o.all());
}

// --- beyond the shell suite ---

#[test]
fn a_missing_env_file_for_deploy_env_fails() {
    let work = TempDir::new();
    let app = app_fixture(&work);
    let o = bare(&app, "staging").go();
    assert_eq!(o.code, 1, "{}", o.all());
    assert!(
        o.stderr
            .contains("Pulumi.staging.yaml not found (DEPLOY_ENV=staging)"),
        "{}",
        o.stderr
    );
}

#[test]
fn credentials_are_required_once_there_is_a_zone() {
    let work = TempDir::new();
    let app = app_fixture(&work);
    let o = bare(&app, "development").go();
    assert_eq!(o.code, 1, "{}", o.all());
    assert!(
        o.stderr.contains("SITEVERIFY_ACCESS_TOKEN is required"),
        "{}",
        o.stderr
    );
    let o = bare(&app, "development")
        .env("SITEVERIFY_ACCESS_TOKEN", "t")
        .go();
    assert_eq!(o.code, 1, "{}", o.all());
    assert!(
        o.stderr.contains("CLOUDFLARE_API_TOKEN is required"),
        "{}",
        o.stderr
    );
}

// #948: the WRITE calls need the caller's own quota project. Without it
// getToken 403s, and the failed self-verification ends the run at once (the
// script ran verify_zone under set -e): no TXT, no insert, no second GET.
#[test]
fn without_the_quota_project_self_verification_fails_and_stops() {
    let work = TempDir::new();
    let app = app_fixture(&work);
    let m = Mock::start();
    let o = full(&m, &app, "development")
        .env_remove("SITEVERIFY_QUOTA_PROJECT")
        .go();
    assert_eq!(o.code, 1, "{}", o.all());
    assert!(
        o.stderr
            .contains("getToken(DNS_TXT) for example.test -> HTTP 403"),
        "{}",
        o.stderr
    );
    assert!(
        o.stderr
            .contains("getToken(DNS) for example.test -> HTTP 403"),
        "{}",
        o.stderr
    );
    assert!(
        o.stderr.contains(QUOTA_403),
        "the API's own message: {}",
        o.stderr
    );
    let s = m.st();
    assert_eq!((s.cf_create, s.sv_insert), (0, 0));
    assert_eq!(
        s.sv_get, 1,
        "no convergence GET after a failed self-verification"
    );
    assert!(
        !o.all().contains("still failing after insert"),
        "{}",
        o.all()
    );
}

// `code="$(sv_call GET ...)"` under set -e: a curl that cannot connect ends the
// run with curl's own status (7), its error in the log, before any write.
#[test]
fn an_unreachable_site_verification_api_ends_the_run_with_curls_status() {
    let work = TempDir::new();
    let app = app_fixture(&work);
    let m = Mock::start();
    let closed = {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        l.local_addr().unwrap().port()
    };
    let o = full(&m, &app, "development")
        .env(
            "SITEVERIFY_API_BASE",
            format!("http://127.0.0.1:{closed}/siteVerification/v1"),
        )
        .go();
    assert_eq!(o.code, 7, "curl's 'could not connect': {}", o.all());
    assert!(
        o.stderr.contains("curl: (7)"),
        "curl's error reaches the log: {}",
        o.stderr
    );
    assert_eq!(m.st().cf_create, 0);
}

#[test]
fn under_bazel_run_app_dir_is_relative_to_the_callers_directory() {
    let work = TempDir::new();
    app_fixture(&work);
    let m = Mock::start();
    let elsewhere = TempDir::new();
    let o = full(&m, Path::new("app"), "development")
        .cwd(elsewhere.path())
        .env("BUILD_WORKING_DIRECTORY", work.path())
        .go();
    ok(&o);
    assert!(m.st().caller_verified, "{}", o.all());
}
