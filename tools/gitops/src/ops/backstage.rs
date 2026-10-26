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

//! seal_argocd_backstage_token.sh: mint the read-only ArgoCD project-role
//! token the Backstage ArgoCD cards use and seal it, never printing it or
//! putting it on a command line. The JSON the script built and read with
//! python3 is built here as python's `json.dumps` writes it (the request
//! bodies are compared byte for byte by the parity test) and read with
//! serde_json.

use std::process::Stdio;

use shell_compat as sc;

use super::common::*;
use super::jq::{self, J};

/// The text of a byte string as python sees an argv element or environment
/// value: UTF-8, with each undecodable byte as a lone surrogate
/// (surrogateescape).
fn py_chars(b: &[u8]) -> Vec<u32> {
    let mut out = Vec::new();
    let mut rest = b;
    while !rest.is_empty() {
        match std::str::from_utf8(rest) {
            Ok(s) => {
                out.extend(s.chars().map(|c| c as u32));
                break;
            }
            Err(e) => {
                let ok = e.valid_up_to();
                out.extend(
                    std::str::from_utf8(&rest[..ok])
                        .unwrap_or("")
                        .chars()
                        .map(|c| c as u32),
                );
                let bad = e.error_len().unwrap_or(rest.len() - ok);
                for &x in &rest[ok..ok + bad] {
                    out.push(0xDC00 + x as u32);
                }
                rest = &rest[ok + bad..];
            }
        }
    }
    out
}

/// A string literal as python's `json.dumps` writes it (ensure_ascii: every
/// character outside space..~ escaped).
pub fn py_json_str(b: &[u8]) -> String {
    let mut o = String::from("\"");
    for c in py_chars(b) {
        match c {
            0x22 => o.push_str("\\\""),
            0x5c => o.push_str("\\\\"),
            0x0a => o.push_str("\\n"),
            0x0d => o.push_str("\\r"),
            0x09 => o.push_str("\\t"),
            0x08 => o.push_str("\\b"),
            0x0c => o.push_str("\\f"),
            0x20..=0x7e => o.push(char::from_u32(c).unwrap_or('?')),
            c if c > 0xffff => {
                let v = c - 0x10000;
                o.push_str(&format!(
                    "\\u{:04x}\\u{:04x}",
                    0xd800 + (v >> 10),
                    0xdc00 + (v & 0x3ff)
                ));
            }
            c => o.push_str(&format!("\\u{:04x}", c)),
        }
    }
    o.push('"');
    o
}

/// What python's `print(x)` writes for a value `json.load` returned.
fn py_print(v: &J) -> String {
    match v {
        J::Str(s) => s.clone(),
        J::Null => "None".into(),
        J::Bool(true) => "True".into(),
        J::Bool(false) => "False".into(),
        J::Num(n) => n.to_string(),
        other => jq::pretty(other).trim_end().to_string(),
    }
}

/// `json.load(sys.stdin)` on a document that must be a JSON object; the
/// message python would die with otherwise.
fn py_load_object(input: &[u8]) -> Result<J, String> {
    match serde_json::from_slice::<J>(input) {
        Ok(v @ J::Obj(_)) => Ok(v),
        Ok(other) => {
            let t = match other {
                J::Arr(_) => "list",
                J::Str(_) => "str",
                J::Num(_) => "int",
                J::Bool(_) => "bool",
                _ => "NoneType",
            };
            Err(format!(
                "AttributeError: '{}' object has no attribute 'get'",
                t
            ))
        }
        Err(e) => Err(format!("json.decoder.JSONDecodeError: {}", e)),
    }
}

fn py_die(msg: &str) -> i32 {
    sc::err(
        format!(
            "Traceback (most recent call last):\n  File \"<string>\", line 1, in <module>\n{}\n",
            msg
        )
        .as_bytes(),
    );
    1
}

/// `dict.get(key, "")`.
fn py_get(v: &J, key: &str) -> J {
    match v {
        J::Obj(m) => m
            .iter()
            .find(|(k, _)| k == key)
            .map_or(J::Str(String::new()), |(_, x)| x.clone()),
        _ => J::Str(String::new()),
    }
}

/// `curl ARGS` (fed `body` on stdin when given), its stdout read here as the
/// python that followed it in the pipeline did; curl's status and output.
fn curl(line: u32, args: &[&[u8]], body: Option<&[u8]>) -> (i32, Vec<u8>) {
    let c = cmd("curl", args);
    match body {
        Some(b) => {
            let mut c = c;
            c.stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::inherit());
            let mut ch = match c.spawn() {
                Ok(ch) => ch,
                Err(e) => {
                    sc::err(&sc::spawn_diag(line, &c, &e));
                    return (sc::spawn_failure_status(&e), Vec::new());
                }
            };
            if let Some(mut sin) = ch.stdin.take() {
                use std::io::Write;
                let _ = sin.write_all(b);
            }
            match ch.wait_with_output() {
                Ok(o) => (sc::status_code(o.status), o.stdout),
                Err(_) => (1, Vec::new()),
            }
        }
        None => output(line, c, false),
    }
}

pub fn main(args: &[Vec<u8>]) -> i32 {
    match run_main(args) {
        Ok(c) | Err(c) => c,
    }
}

fn run_main(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(48)?;
    let k = kctx();
    let (ns, secret, key, project, role) = (
        "backstage",
        "argocd-backstage-token",
        "ARGOCD_TOKEN",
        "platform-project",
        "backstage",
    );
    let url = sc::env_or("ARGOCD_SERVER_URL", b"https://argocd.lab.ipv1337.dev");
    let out = format!("{}/{}.sealedsecret.yaml", SEALED_DIR, secret).into_bytes();

    let mut apply = false;
    let mut expires_in: Vec<u8> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_slice() {
            b"--apply" => apply = true,
            b"--expires-in" => {
                i += 1;
                expires_in = param(
                    &args[i..],
                    1,
                    67,
                    "--expires-in needs a duration, e.g. 8760h",
                )?;
            }
            other => {
                return die(
                    2,
                    &sc::cat(&[
                        b"ERROR: unknown argument '",
                        other,
                        b"' (expected --apply and/or --expires-in DURATION)",
                    ]),
                )
            }
        }
        i += 1;
    }
    // python3 is no longer needed: the JSON is built and read here.
    need_tools(&["kubectl", "kubeseal", "curl"], false)?;
    cd_workspace(77)?;

    let session = if sc::env_set_nonempty("ARGOCD_AUTH_TOKEN") {
        sc::env_or_empty("ARGOCD_AUTH_TOKEN")
    } else {
        let get = kubectl(
            &k,
            &[
                b"get",
                b"secret",
                b"argocd-initial-admin-secret",
                b"-n",
                b"argocd",
                b"-o",
                b"jsonpath={.data.password}",
            ],
        );
        let (_, enc) = output(87, get, true);
        let pw = match crate::ops::crypto::b64decode(&enc) {
            Ok(v) => sc::subst(v),
            Err(partial) => {
                sc::err(b"base64: invalid input\n");
                sc::subst(partial)
            }
        };
        if pw.is_empty() {
            warn(b"ERROR: no ARGOCD_AUTH_TOKEN set and argocd-initial-admin-secret is absent.");
            warn(b"       Set ARGOCD_AUTH_TOKEN=$(argocd account generate-token ...) and re-run.");
            return Err(1);
        }
        let body = format!(
            "{{\"username\": \"admin\", \"password\": {}}}\n",
            py_json_str(&pw)
        );
        let session_url = sc::cat(&[&url, b"/api/v1/session"]);
        let (curl_st, resp) = curl(
            96,
            &[
                b"-sS",
                b"-X",
                b"POST",
                &session_url,
                b"-H",
                b"Content-Type: application/json",
                b"-d",
                b"@-",
            ],
            Some(body.as_bytes()),
        );
        // SESSION="$(python3 ... | curl ... | python3 ...)": under pipefail a
        // curl failure ends the run (set -e) even when python read its empty
        // reply fine.
        let session = match py_load_object(&resp) {
            Ok(v) => sc::subst(py_print(&py_get(&v, "token")).into_bytes()),
            Err(m) => return Err(py_die(&m)),
        };
        if curl_st != 0 {
            return Err(curl_st);
        }
        session
    };
    if session.is_empty() {
        return die(
            1,
            &sc::cat(&[b"ERROR: could not authenticate to ", &url, b"."]),
        );
    }

    let get_roles = kubectl(
        &k,
        &[
            b"get",
            b"appproject",
            project.as_bytes(),
            b"-n",
            b"argocd",
            b"-o",
            b"jsonpath={.spec.roles[*].name}",
        ],
    );
    let (st, names) = output(105, get_roles, true);
    let has_role = st == 0
        && names
            .split(|&c| c == b' ' || c == b'\n')
            .any(|n| n == role.as_bytes());
    if !has_role {
        warn(
            format!(
                "ERROR: role '{}' does not exist on AppProject '{}'.",
                role, project
            )
            .as_bytes(),
        );
        warn(b"       Merge gitops/argocd/projects/platform.yaml and let app-of-projects sync,");
        warn(
            format!(
                "       then re-run. (kubectl get appproject {} -n argocd -o yaml)",
                project
            )
            .as_bytes(),
        );
        return Err(1);
    }

    let body = if expires_in.is_empty() {
        "{}".to_string()
    } else {
        format!("{{\"expiresIn\": {}}}", py_json_str(&expires_in))
    };
    let token_url = sc::cat(&[
        &url,
        format!("/api/v1/projects/{}/roles/{}/token", project, role).as_bytes(),
    ]);
    let auth = sc::cat(&[b"Authorization: Bearer ", &session]);
    let (curl_st, resp) = curl(
        118,
        &[
            b"-sS",
            b"-X",
            b"POST",
            &token_url,
            b"-H",
            &auth,
            b"-H",
            b"Content-Type: application/json",
            b"-d",
            body.as_bytes(),
        ],
        None,
    );
    let token = match py_load_object(&resp) {
        Ok(v) => {
            // sys.stderr.write(d.get("error","")[:200]): only a string gets
            // through; anything else is a TypeError.
            match py_get(&v, "error") {
                J::Str(e) => {
                    let cut: String = e.chars().take(200).collect();
                    sc::err(cut.as_bytes());
                }
                _ => return Err(py_die("TypeError: write() argument must be str")),
            }
            sc::subst(py_print(&py_get(&v, "token")).into_bytes())
        }
        Err(m) => return Err(py_die(&m)),
    };
    if curl_st != 0 {
        return Err(curl_st);
    }
    if token.is_empty() {
        return die(
            1,
            b"ERROR: token mint returned no token (see message above).",
        );
    }

    let header = format!(
        "{}#\n# Generated by `bazel run //tools/gitops:seal-argocd-backstage-token`.\n# Read-only ArgoCD project-role token for the Backstage ArgoCD cards.\n",
        LICENSE_HEADER
    );
    write_new(125, &out, header.as_bytes())?;
    let st = seal_value(149, &k, ns, secret, key, &token, &out);
    drop(token);
    if st != 0 {
        return Err(st);
    }
    say(&sc::cat(&[
        "\u{2713} minted + sealed \u{2192} ".as_bytes(),
        &out,
        format!(" (SealedSecret {}/{}, key {})", ns, secret, key).as_bytes(),
    ]));
    if apply {
        let st = run(158, &mut kubectl(&k, &[b"apply", b"-f", &out]), false);
        if st != 0 {
            return Err(st);
        }
        say(format!(
            "\u{2713} applied \u{2014} the controller will materialize {}/{}",
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_dumps_strings_like_python() {
        assert_eq!(py_json_str(b"p@ss\"w\\rd\n"), r#""p@ss\"w\\rd\n""#);
        assert_eq!(py_json_str("caf\u{e9}".as_bytes()), r#""caf\u00e9""#);
        assert_eq!(py_json_str("\u{1F600}".as_bytes()), r#""\ud83d\ude00""#);
        assert_eq!(py_json_str(b"\x7f\x01"), r#""\u007f\u0001""#);
        assert_eq!(py_json_str(b"a\xffb"), r#""a\udcffb""#);
    }

    #[test]
    fn print_like_python() {
        assert_eq!(py_print(&J::Null), "None");
        assert_eq!(py_print(&J::Str("tok".into())), "tok");
        assert_eq!(py_print(&J::Bool(true)), "True");
    }
}
