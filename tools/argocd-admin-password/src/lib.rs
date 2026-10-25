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

//! argocd-admin-password sync: pin the dev-local Argo CD `admin` password to
//! the value held in Bitwarden. A port of sync.sh -- same environment, same
//! calls to bw, kubectl, htpasswd and pulumi, same output and exit codes --
//! with the script's jq done in Rust (src/jq.rs, through serde) and its
//! `openssl rand`, `base64 -d` and `date -u` done natively.
//!
//! `set -e` is followed step by step: a failing `item="$(item_json)"`, item
//! creation pipeline, `hash` pipeline or `pulumi config set` ends the run
//! with that step's status (pipefail: the rightmost failure), after the
//! EXIT trap's clean-up of the temporary htpasswd file.

pub mod jq;

use std::io::Write;
use std::process::{Command, Stdio};

use serde::Serialize;
use shell_compat as sh;

pub const ITEM: &str = "argocd admin (dev-local)";
pub const URL: &str = "https://argocd.lab.ipv1337.dev";
pub const PROJECT_DIR: &str = "infrastructure/pulumi/platform/dev-local";
const NOTES: &str =
    "Managed by //tools/argocd-admin-password. Change the password here, then re-run :sync and pulumi up.";

/// How the run ends: an exit status, after the EXIT trap.
pub struct Exit(pub i32);

fn prog() -> Vec<u8> {
    std::env::args_os()
        .next()
        .map(std::os::unix::ffi::OsStringExt::into_vec)
        .unwrap_or_default()
}

/// bash's own diagnostic: `<script>: line N: <msg>`.
fn bash_diag(line: u32, msg: &[u8]) {
    sh::err(&sh::cat(&[
        &prog(),
        format!(": line {}: ", line).as_bytes(),
        msg,
        b"\n",
    ]));
}

fn die(msg: &str) -> Exit {
    sh::err(format!("argocd-admin-password: {}\n", msg).as_bytes());
    Exit(1)
}

fn echo(s: &str) {
    sh::out(format!("{}\n", s).as_bytes());
}

/// `cd`'s logical path: `.` and empty components dropped, `..` taken
/// lexically, as bash's cd computes $PWD.
fn logical(p: &[u8]) -> Vec<u8> {
    let mut parts: Vec<&[u8]> = Vec::new();
    for c in p.split(|&b| b == b'/') {
        match c {
            b"" | b"." => {}
            b".." => {
                parts.pop();
            }
            c => parts.push(c),
        }
    }
    let mut out = Vec::new();
    for c in parts {
        out.push(b'/');
        out.extend_from_slice(c);
    }
    if out.is_empty() {
        out.push(b'/');
    }
    out
}

/// The EXIT trap's file: removed whenever the run ends, once it exists.
struct Trap(Option<Vec<u8>>);

impl Drop for Trap {
    fn drop(&mut self) {
        if let Some(p) = self.0.take() {
            let _ = std::fs::remove_file(sh::path(&p));
        }
    }
}

/// A command's stdout and status with its stderr discarded, as
/// `cmd 2>/dev/null | ...` gives the next stage (a command that cannot start
/// says so to /dev/null and exits 127).
fn quiet_stdout(cmd: &mut Command) -> (Vec<u8>, i32) {
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    match cmd.output() {
        Ok(o) => (o.stdout, sh::status_code(o.status)),
        Err(e) => (Vec::new(), sh::spawn_failure_status(&e)),
    }
}

/// `item_json`: `bw list items --search "$ITEM" 2>/dev/null | jq -c ...`.
/// Ok(lines of compact JSON), or Err(status) when the pipeline failed.
fn item_json() -> Result<Vec<u8>, i32> {
    let (out, bw_rc) = quiet_stdout(Command::new("bw").args(["list", "items", "--search", ITEM]));
    let f = jq::select_item(ITEM);
    let r = jq::run(&out, &f, jq::dump_compact);
    sh::err(r.stderr.as_bytes());
    let rc = if r.status != 0 { r.status } else { bw_rc };
    if rc != 0 {
        return Err(rc);
    }
    Ok(sh::subst(r.stdout.into_bytes()))
}

/// `base64 -d` of valid input; at the first byte that is not base64 it
/// stops, says so, and keeps what it had (GNU's behaviour).
pub fn b64_decode(input: &[u8]) -> (Vec<u8>, bool) {
    fn val(c: u8) -> Option<u32> {
        match c {
            b'A'..=b'Z' => Some((c - b'A') as u32),
            b'a'..=b'z' => Some((c - b'a') as u32 + 26),
            b'0'..=b'9' => Some((c - b'0') as u32 + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let mut out = Vec::new();
    let mut acc = 0u32;
    let mut bits = 0;
    let mut padded = false;
    for &c in input {
        if c == b'\n' {
            continue;
        }
        if c == b'=' {
            padded = true;
            continue;
        }
        match val(c) {
            Some(v) if !padded => {
                acc = (acc << 6) | v;
                bits += 6;
                if bits >= 8 {
                    bits -= 8;
                    out.push((acc >> bits) as u8);
                    acc &= (1 << bits) - 1;
                }
            }
            _ => return (out, false),
        }
    }
    (out, true)
}

pub fn b64_encode(input: &[u8]) -> Vec<u8> {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::new();
    for ch in input.chunks(3) {
        let b = [ch[0], *ch.get(1).unwrap_or(&0), *ch.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(T[(n >> 18) as usize & 63]);
        out.push(T[(n >> 12) as usize & 63]);
        out.push(if ch.len() > 1 {
            T[(n >> 6) as usize & 63]
        } else {
            b'='
        });
        out.push(if ch.len() > 2 {
            T[n as usize & 63]
        } else {
            b'='
        });
    }
    out
}

/// `openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32`.
fn random_password() -> Vec<u8> {
    use std::io::Read;
    let mut buf = [0u8; 36];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    }
    let mut p: Vec<u8> = b64_encode(&buf)
        .into_iter()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    p.truncate(32);
    p
}

#[derive(Serialize)]
struct Uri<'a> {
    uri: &'a str,
}

#[derive(Serialize)]
struct Login<'a> {
    username: &'a str,
    password: &'a str,
    uris: Vec<Uri<'a>>,
}

#[derive(Serialize)]
struct Item<'a> {
    #[serde(rename = "type")]
    kind: u8,
    name: &'a str,
    notes: &'a str,
    login: Login<'a>,
}

/// `jq -nc --arg n "$ITEM" --arg p "$seed" --arg u "$URL" '{...}'`: what jq
/// writes, which differs from serde_json only in escaping DEL.
pub fn item_doc(password: &str) -> String {
    let item = Item {
        kind: 1,
        name: ITEM,
        notes: NOTES,
        login: Login {
            username: "admin",
            password,
            uris: vec![Uri { uri: URL }],
        },
    };
    let s = serde_json::to_string(&item).unwrap_or_default();
    format!("{}\n", s.replace('\u{7f}', "\\u007f"))
}

/// Run `cmd` with `input` on stdin and its stdout captured (stderr ours).
fn feed(line: u32, cmd: &mut Command, input: &[u8], stdout_null: bool) -> (Vec<u8>, i32) {
    cmd.stdin(Stdio::piped())
        .stdout(if stdout_null {
            Stdio::null()
        } else {
            Stdio::piped()
        })
        .stderr(Stdio::inherit());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            sh::err(&sh::spawn_diag(line, cmd, &e));
            return (Vec::new(), sh::spawn_failure_status(&e));
        }
    };
    if let Some(mut sin) = child.stdin.take() {
        let _ = sin.write_all(input);
    }
    match child.wait_with_output() {
        Ok(o) => (o.stdout, sh::status_code(o.status)),
        Err(_) => (Vec::new(), 1),
    }
}

/// `date -u +%Y-%m-%dT%H:%M:%SZ`.
pub fn utc_now() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    utc(secs)
}

pub fn utc(secs: i64) -> String {
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    // Howard Hinnant's civil_from_days.
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        y,
        m,
        d,
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    )
}

fn pulumi_get(key: &str) -> Vec<u8> {
    let (out, _) =
        quiet_stdout(Command::new("pulumi").args(["config", "get", key, "--stack", "local"]));
    sh::subst(out)
}

/// `pulumi config set <flag> <key> --stack local -- <value> >/dev/null`.
fn pulumi_set(line: u32, flag: &str, key: &str, value: &[u8]) -> i32 {
    let mut cmd = Command::new("pulumi");
    cmd.args(["config", "set", flag, key, "--stack", "local", "--"])
        .arg(sh::os(value))
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit());
    sh::status(line, &mut cmd, false)
}

/// The whole script. Returns the exit status.
pub fn run() -> i32 {
    let mut trap = Trap(None);
    match body(&mut trap) {
        Ok(()) => 0,
        Err(Exit(code)) => code,
    }
}

fn body(trap: &mut Trap) -> Result<(), Exit> {
    // SESS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/vitruvian-core/bw-session"
    let home = sh::env("HOME");
    let cache = if sh::env_set_nonempty("XDG_CACHE_HOME") {
        sh::env_or_empty("XDG_CACHE_HOME")
    } else {
        match &home {
            Some(h) => sh::cat(&[h, b"/.cache"]),
            None => {
                bash_diag(52, b"HOME: unbound variable");
                return Err(Exit(1));
            }
        }
    };
    let sess_cache = sh::cat(&[&cache, b"/vitruvian-core/bw-session"]);

    // cd "${BUILD_WORKSPACE_DIRECTORY:?...}/$PROJECT_DIR"
    if !sh::env_set_nonempty("BUILD_WORKSPACE_DIRECTORY") {
        bash_diag(
            56,
            // bash removes the word's quotes before printing it.
            b"BUILD_WORKSPACE_DIRECTORY: run via bazel run //tools/argocd-admin-password:sync",
        );
        return Err(Exit(1));
    }
    let target = sh::cat(&[
        &sh::env_or_empty("BUILD_WORKSPACE_DIRECTORY"),
        b"/",
        PROJECT_DIR.as_bytes(),
    ]);
    let old_pwd = match sh::env("PWD") {
        Some(p) if p.starts_with(b"/") => p,
        _ => std::env::current_dir()
            .map(|d| sh::path_bytes(&d))
            .unwrap_or_else(|_| b"/".to_vec()),
    };
    if let Err(e) = std::env::set_current_dir(sh::path(&target)) {
        bash_diag(
            56,
            &sh::cat(&[b"cd: ", &target, b": ", sh::strerror(&e).as_bytes()]),
        );
        return Err(Exit(1));
    }
    let pwd = if target.starts_with(b"/") {
        logical(&target)
    } else {
        logical(&sh::cat(&[&old_pwd, b"/", &target]))
    };
    std::env::set_var("PWD", sh::os(&pwd));

    let config = std::fs::read("Pulumi.local.yaml").unwrap_or_default();
    if !sh::contains(&config, b"argocd_enabled") {
        let here = String::from_utf8_lossy(&pwd).into_owned();
        return Err(die(&format!(
            "no Pulumi.local.yaml with argocd_enabled in {} (worktree?). Run this from the main checkout.",
            here
        )));
    }

    if !sh::env_set_nonempty("PULUMI_BACKEND_URL") {
        std::env::set_var("PULUMI_BACKEND_URL", "https://api.pulumi.com");
    }
    if !sh::env_set_nonempty("KUBECONFIG") {
        match &home {
            Some(h) => {
                std::env::set_var("KUBECONFIG", sh::os(&sh::cat(&[h, b"/.kube/cluster.yaml"])))
            }
            None => {
                bash_diag(61, b"HOME: unbound variable");
                return Err(Exit(1));
            }
        }
    }
    std::env::set_var("GOWORK", "off");

    if !sh::env_set_nonempty("BW_SESSION") && sh::is_readable(&sess_cache) {
        match std::fs::read(sh::path(&sess_cache)) {
            Ok(v) => std::env::set_var("BW_SESSION", sh::os(&sh::subst(v))),
            Err(e) => {
                sh::err(&sh::cat(&[
                    b"cat: ",
                    &sess_cache,
                    b": ",
                    sh::strerror(&e).as_bytes(),
                    b"\n",
                ]));
                return Err(Exit(1));
            }
        }
    }

    let (status_out, _) = quiet_stdout(Command::new("bw").arg("status"));
    let st = jq::run(&status_out, jq::status, jq::raw);
    sh::err(st.stderr.as_bytes());
    if sh::subst(st.stdout.into_bytes()) != b"unlocked" {
        return Err(die(
            "Bitwarden is locked. Run: bazel run //tools/sync-env-secrets:unlock",
        ));
    }
    let _ = Command::new("bw")
        .arg("sync")
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();

    let mut item = item_json().map_err(Exit)?;
    if item.is_empty() {
        let (enc, _) = quiet_stdout(Command::new("kubectl").args([
            "-n",
            "argocd",
            "get",
            "secret",
            "argocd-initial-admin-secret",
            "-o",
            "jsonpath={.data.password}",
        ]));
        let (decoded, ok) = b64_decode(&enc);
        if !ok {
            sh::err(b"base64: invalid input\n");
        }
        let mut seed = sh::subst(decoded);
        let src;
        if !seed.is_empty() {
            src = "the current live password (argocd-initial-admin-secret)";
        } else {
            seed = random_password();
            src = "a new random password";
        }
        let doc = item_doc(&String::from_utf8_lossy(&seed));
        let (encoded, enc_rc) = feed(79, Command::new("bw").arg("encode"), doc.as_bytes(), false);
        let (_, create_rc) = feed(
            79,
            Command::new("bw").args(["create", "item"]),
            &encoded,
            true,
        );
        let rc = if create_rc != 0 { create_rc } else { enc_rc };
        if rc != 0 {
            return Err(Exit(rc));
        }
        echo(&format!(
            "Created Bitwarden item \"{}\" from {}.",
            ITEM, src
        ));
        item = item_json().map_err(Exit)?;
        if item.is_empty() {
            return Err(die("created the Bitwarden item but cannot read it back"));
        }
    }

    // password="$(jq -r '.login.password // empty' <<<"$item")"
    let mut here = item.clone();
    here.push(b'\n');
    let pw = jq::run(&here, jq::password, jq::raw);
    sh::err(pw.stderr.as_bytes());
    if pw.status != 0 {
        return Err(Exit(pw.status));
    }
    let password = sh::subst(pw.stdout.into_bytes());
    if password.is_empty() {
        return Err(die(&format!("Bitwarden item \"{}\" has no password", ITEM)));
    }

    let current_hash = pulumi_get("argocd_admin_password_bcrypt");
    let current_mtime = pulumi_get("argocd_admin_password_mtime");
    if !current_hash.is_empty() && !current_mtime.is_empty() {
        let tmp = match sh::mktemp_file(&sh::cat(&[&sh::tmpdir(), b"/tmp.XXXXXXXXXX"])) {
            Ok(p) => p,
            Err(e) => {
                sh::err(format!("mktemp: {}\n", sh::strerror(&e)).as_bytes());
                return Err(Exit(1));
            }
        };
        trap.0 = Some(tmp.clone());
        if let Err(e) = sh::write_file(&tmp, &sh::cat(&[b"admin:", &current_hash, b"\n"]), 0o600) {
            sh::redirect_error(92, &tmp, &e);
            return Err(Exit(1));
        }
        let mut v = Command::new("htpasswd");
        v.arg("-vi").arg(sh::os(&tmp)).arg("admin");
        v.stdout(Stdio::null()).stderr(Stdio::null());
        if sh::status_with_input(93, &mut v, &password, true) == 0 {
            echo(&format!(
                "Already in sync: the stack config hash matches Bitwarden (mtime {}). Nothing to do.",
                String::from_utf8_lossy(&current_mtime)
            ));
            return Ok(());
        }
    }

    // hash="$(printf '%s' "$password" | htpasswd -niBC 10 "" | tr -d ':\n' | sed 's/^\$2y/$2a/')"
    let (out, rc) = feed(
        101,
        Command::new("htpasswd").args(["-niBC", "10", ""]),
        &password,
        false,
    );
    if rc != 0 {
        return Err(Exit(rc));
    }
    let mut hash: Vec<u8> = out
        .into_iter()
        .filter(|&c| c != b':' && c != b'\n')
        .collect();
    if hash.starts_with(b"$2y") {
        hash.splice(0..3, b"$2a".iter().copied());
    }
    let hash = sh::subst(hash);
    if !hash.starts_with(b"$2a$10$") {
        return Err(die("unexpected bcrypt output"));
    }
    let mtime = utc_now();
    let rc = pulumi_set(105, "--secret", "argocd_admin_password_bcrypt", &hash);
    if rc != 0 {
        return Err(Exit(rc));
    }
    let rc = pulumi_set(
        106,
        "--plaintext",
        "argocd_admin_password_mtime",
        mtime.as_bytes(),
    );
    if rc != 0 {
        return Err(Exit(rc));
    }
    echo(&format!(
        "Stack config updated (mtime {}). Apply with:",
        mtime
    ));
    echo(&format!(
        "  bazel run //{}:preview   then   bazel run //{}:up",
        PROJECT_DIR, PROJECT_DIR
    ));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_round_trip_and_stop_at_garbage() {
        assert_eq!(b64_decode(b"aGVsbG8=\n"), (b"hello".to_vec(), true));
        assert_eq!(b64_decode(b"aGVsbG8"), (b"hello".to_vec(), true));
        assert_eq!(b64_decode(b""), (Vec::new(), true));
        assert_eq!(b64_decode(b"aGVs*bG8="), (b"hel".to_vec(), false));
        assert_eq!(b64_encode(b"hello"), b"aGVsbG8=".to_vec());
        assert_eq!(b64_encode(b"hi!"), b"aGkh".to_vec());
    }

    #[test]
    fn random_passwords_are_32_alphanumerics() {
        // 200 draws: a stray `+` or `/` would get through one draw in three.
        for _ in 0..200 {
            let p = random_password();
            assert_eq!(p.len(), 32);
            assert!(p.iter().all(u8::is_ascii_alphanumeric), "{:?}", p);
        }
        assert_ne!(random_password(), random_password());
    }

    #[test]
    fn the_item_jq_would_write() {
        assert_eq!(
            item_doc("p\u{7f}\"x"),
            "{\"type\":1,\"name\":\"argocd admin (dev-local)\",\"notes\":\"Managed by //tools/argocd-admin-password. Change the password here, then re-run :sync and pulumi up.\",\"login\":{\"username\":\"admin\",\"password\":\"p\\u007f\\\"x\",\"uris\":[{\"uri\":\"https://argocd.lab.ipv1337.dev\"}]}}\n"
        );
    }

    #[test]
    fn utc_dates() {
        assert_eq!(utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(utc(951782400), "2000-02-29T00:00:00Z");
        assert_eq!(utc(1792886400 + 3723), "2026-10-25T01:02:03Z");
    }

    #[test]
    fn logical_paths() {
        assert_eq!(logical(b"/a//b/./c/../d/"), b"/a/b/d".to_vec());
        assert_eq!(logical(b"/"), b"/".to_vec());
    }
}
