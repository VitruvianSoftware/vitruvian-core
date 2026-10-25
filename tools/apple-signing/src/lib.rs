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

//! apple-signing: the Developer ID certificate and notary API key that sign
//! and notarize the Vitruvian app, set up from the shell. A port of
//! apple-signing.sh: the same subcommands, the same calls to openssl, gh, bw,
//! xcrun, security, curl and mv, the same output, files and exit codes.
//!
//! What the script did with python3 is done here through serde: reading
//! `bw status` and `bw list`, and writing the Bitwarden items -- in the exact
//! text Python's `json.dumps` writes (", " and ": " separators, non-ASCII as
//! \uXXXX), since that text is what reaches `bw encode`. Its `openssl rand`
//! and `base64` are done natively. Where Python would have stopped with a
//! traceback (bw answering something that is not JSON) this prints one line
//! instead and carries on the same way.
//!
//! `set -e` is followed step by step: a step that fails ends the run with its
//! status (pipefail: the rightmost failure of a pipeline).

use std::fs;
use std::io::Write;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::process::{Command, Stdio};

use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use shell_compat as sh;

/// How a run ends early: an exit status.
pub struct Exit(pub i32);

type R<T = ()> = Result<T, Exit>;

const USAGE: &str = "bazel run //tools/apple-signing -- csr
bazel run //tools/apple-signing -- secrets <KEY_ID> <ISSUER_ID> <AuthKey_*.p8>
bazel run //tools/apple-signing -- check
bazel run //tools/apple-signing -- notary-status [SUBMISSION_ID]
";

const SECRETS: [&str; 5] = [
    "SIGNING_CERT_P12",
    "SIGNING_CERT_PASSWORD",
    "NOTARY_API_KEY_P8",
    "NOTARY_KEY_ID",
    "NOTARY_ISSUER_ID",
];

// ---------------------------------------------------------------------------
// JSON: Python's json.load (order kept) and json.dumps (its exact text).
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum PyJson {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    List(Vec<PyJson>),
    Dict(Vec<(String, PyJson)>),
}

impl<'de> Deserialize<'de> for PyJson {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct V;
        impl<'de> Visitor<'de> for V {
            type Value = PyJson;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("any JSON value")
            }
            fn visit_unit<E: de::Error>(self) -> Result<PyJson, E> {
                Ok(PyJson::Null)
            }
            fn visit_bool<E: de::Error>(self, b: bool) -> Result<PyJson, E> {
                Ok(PyJson::Bool(b))
            }
            fn visit_i64<E: de::Error>(self, n: i64) -> Result<PyJson, E> {
                Ok(PyJson::Num(n as f64))
            }
            fn visit_u64<E: de::Error>(self, n: u64) -> Result<PyJson, E> {
                Ok(PyJson::Num(n as f64))
            }
            fn visit_f64<E: de::Error>(self, n: f64) -> Result<PyJson, E> {
                Ok(PyJson::Num(n))
            }
            fn visit_str<E: de::Error>(self, s: &str) -> Result<PyJson, E> {
                Ok(PyJson::Str(s.to_string()))
            }
            fn visit_string<E: de::Error>(self, s: String) -> Result<PyJson, E> {
                Ok(PyJson::Str(s))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<PyJson, A::Error> {
                let mut v = Vec::new();
                while let Some(x) = a.next_element::<PyJson>()? {
                    v.push(x);
                }
                Ok(PyJson::List(v))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<PyJson, A::Error> {
                let mut items: Vec<(String, PyJson)> = Vec::new();
                while let Some((k, v)) = a.next_entry::<String, PyJson>()? {
                    if let Some(slot) = items.iter_mut().find(|(ek, _)| *ek == k) {
                        slot.1 = v;
                    } else {
                        items.push((k, v));
                    }
                }
                Ok(PyJson::Dict(items))
            }
        }
        d.deserialize_any(V)
    }
}

/// `json.load(sys.stdin)`: one document, surrounding whitespace allowed.
pub fn py_load(b: &[u8]) -> Result<PyJson, String> {
    serde_json::from_slice::<PyJson>(b).map_err(|e| e.to_string())
}

/// A string as `json.dumps` writes it (ensure_ascii).
pub fn py_dumps_str(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            '\u{8}' => o.push_str("\\b"),
            '\u{c}' => o.push_str("\\f"),
            ' '..='~' => o.push(c),
            c => {
                let mut buf = [0u16; 2];
                for u in c.encode_utf16(&mut buf) {
                    o.push_str(&format!("\\u{:04x}", u));
                }
            }
        }
    }
    o.push('"');
    o
}

/// One Bitwarden field: `{"name": ..., "value": ..., "type": N}`.
pub struct Field<'a> {
    pub name: &'a str,
    pub value: &'a str,
    pub kind: u8,
}

fn dumps_fields(fields: &[Field]) -> String {
    let parts: Vec<String> = fields
        .iter()
        .map(|f| {
            format!(
                "{{\"name\": {}, \"value\": {}, \"type\": {}}}",
                py_dumps_str(f.name),
                py_dumps_str(f.value),
                f.kind
            )
        })
        .collect();
    format!("[{}]", parts.join(", "))
}

/// The secure note bw_note pipes to `bw encode`, as Python prints it.
pub fn note_doc(name: &str, notes: &str, fields: &[Field]) -> String {
    format!(
        "{{\"type\": 2, \"name\": {}, \"secureNote\": {{\"type\": 0}}, \"notes\": {}, \"fields\": {}}}\n",
        py_dumps_str(name),
        py_dumps_str(notes),
        dumps_fields(fields)
    )
}

/// `any(i["name"]==name for i in json.load(stdin))`: Ok(found), or Err when
/// Python would have raised before deciding.
pub fn has_item(doc: &PyJson, name: &str) -> Result<bool, String> {
    let items: Vec<PyJson> = match doc {
        PyJson::List(v) => v.clone(),
        PyJson::Dict(items) => items.iter().map(|(k, _)| PyJson::Str(k.clone())).collect(),
        PyJson::Str(s) => s.chars().map(|c| PyJson::Str(c.to_string())).collect(),
        _ => return Err("TypeError: object is not iterable".into()),
    };
    for i in items {
        match i {
            PyJson::Dict(kv) => match kv.iter().find(|(k, _)| k == "name") {
                Some((_, PyJson::Str(n))) if n == name => return Ok(true),
                Some(_) => {}
                None => return Err("KeyError: 'name'".into()),
            },
            _ => return Err("TypeError: indices must be integers".into()),
        }
    }
    Ok(false)
}

// ---------------------------------------------------------------------------
// Running things
// ---------------------------------------------------------------------------

fn prog() -> Vec<u8> {
    std::env::args_os()
        .next()
        .map(std::os::unix::ffi::OsStringExt::into_vec)
        .unwrap_or_default()
}

fn bash_diag(line: u32, msg: &[u8]) {
    sh::err(&sh::cat(&[
        &prog(),
        format!(": line {}: ", line).as_bytes(),
        msg,
        b"\n",
    ]));
}

fn die(msg: &str) -> Exit {
    sh::err(format!("apple-signing: {}\n", msg).as_bytes());
    Exit(1)
}

fn echo(s: &str) {
    sh::out(format!("{}\n", s).as_bytes());
}

fn usage() -> Exit {
    sh::err(USAGE.as_bytes());
    Exit(2)
}

fn cmd(prog: &str, args: &[&[u8]]) -> Command {
    let mut c = Command::new(prog);
    for a in args {
        c.arg(sh::os(a));
    }
    c
}

/// Run with stdout captured, stderr ours: (stdout, status).
fn capture(line: u32, mut c: Command) -> (Vec<u8>, i32) {
    c.stdin(Stdio::inherit());
    let r = sh::capture_stdout(line, &mut c);
    (r.stdout, r.status)
}

/// Run with `input` on stdin; stdout captured unless `stdout_null`.
fn feed(line: u32, mut c: Command, input: &[u8], stdout_null: bool) -> (Vec<u8>, i32) {
    c.stdin(Stdio::piped())
        .stdout(if stdout_null {
            Stdio::null()
        } else {
            Stdio::piped()
        })
        .stderr(Stdio::inherit());
    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(e) => {
            sh::err(&sh::spawn_diag(line, &c, &e));
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

/// Run with stdio inherited (stdout to /dev/null when asked): the status.
fn run_status(line: u32, mut c: Command, stdout_null: bool, quiet: bool) -> i32 {
    c.stdin(Stdio::inherit());
    if stdout_null {
        c.stdout(Stdio::null());
    }
    if quiet {
        c.stderr(Stdio::null());
    }
    sh::status(line, &mut c, quiet)
}

/// `set -e` on one step.
fn check(rc: i32) -> R {
    if rc == 0 {
        Ok(())
    } else {
        Err(Exit(rc))
    }
}

/// The rightmost failure of a pipeline's statuses (pipefail), or 0.
fn pipefail(statuses: &[i32]) -> i32 {
    statuses
        .iter()
        .rev()
        .copied()
        .find(|&s| s != 0)
        .unwrap_or(0)
}

fn is_file(p: &[u8]) -> bool {
    fs::metadata(sh::path(p))
        .map(|m| m.is_file())
        .unwrap_or(false)
}

fn exists(p: &[u8]) -> bool {
    fs::metadata(sh::path(p)).is_ok()
}

/// `[ a -ef b ]`.
fn same_file(a: &[u8], b: &[u8]) -> bool {
    match (fs::metadata(sh::path(a)), fs::metadata(sh::path(b))) {
        (Ok(x), Ok(y)) => x.dev() == y.dev() && x.ino() == y.ino(),
        _ => false,
    }
}

fn b64_encode(input: &[u8]) -> Vec<u8> {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = Vec::with_capacity(input.len() * 4 / 3 + 4);
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

/// `b64 FILE` (`base64 <FILE | tr -d '\n'`): Ok(text), or Err after bash's
/// redirection error.
fn b64_file(p: &[u8]) -> Result<Vec<u8>, ()> {
    match fs::read(sh::path(p)) {
        Ok(v) => Ok(b64_encode(&v)),
        Err(e) => {
            sh::redirect_error(53, p, &e);
            Err(())
        }
    }
}

/// `openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-32`.
pub fn random_password() -> Vec<u8> {
    use std::io::Read;
    let mut buf = [0u8; 33];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    }
    let mut p: Vec<u8> = b64_encode(&buf)
        .into_iter()
        .filter(|c| !matches!(c, b'/' | b'+' | b'='))
        .collect();
    p.truncate(32);
    p
}

/// `cut -d= -f2` of every line.
fn cut_f2(text: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for line in sh::lines(text) {
        match line.iter().position(|&c| c == b'=') {
            None => out.extend_from_slice(&line),
            Some(i) => {
                let rest = &line[i + 1..];
                let end = rest.iter().position(|&c| c == b'=').unwrap_or(rest.len());
                out.extend_from_slice(&rest[..end]);
            }
        }
        out.push(b'\n');
    }
    out
}

/// `sed -n 's/^ *<field> *= *//p' | head -1`.
fn first_field(text: &[u8], field: &[u8]) -> Vec<u8> {
    for line in sh::lines(text) {
        let mut s: &[u8] = &line;
        while s.first() == Some(&b' ') {
            s = &s[1..];
        }
        if let Some(rest) = s.strip_prefix(field) {
            let mut r = rest;
            while r.first() == Some(&b' ') {
                r = &r[1..];
            }
            if let Some(v) = r.strip_prefix(b"=") {
                let mut v = v;
                while v.first() == Some(&b' ') {
                    v = &v[1..];
                }
                return v.to_vec();
            }
        }
    }
    Vec::new()
}

struct Ctx {
    dir: Vec<u8>,
    repo: Vec<u8>,
    prefix: Vec<u8>,
}

impl Ctx {
    fn at(&self, name: &str) -> Vec<u8> {
        sh::cat(&[&self.dir, b"/", name.as_bytes()])
    }
}

/// `cert_field CN|OU`: what it prints, and the pipeline's status (openssl's,
/// under pipefail), which `set -e` acts on where the script assigns it.
fn cert_field(c: &Ctx, field: &str) -> (Vec<u8>, i32) {
    let cer = c.at("developer-id.cer");
    let (out, rc) = capture(
        57,
        cmd(
            "openssl",
            &[
                b"x509",
                b"-inform",
                b"der",
                b"-in",
                &cer,
                b"-noout",
                b"-subject",
                b"-nameopt",
                b"multiline",
            ],
        ),
    );
    let name: &[u8] = if field == "CN" {
        b"commonName"
    } else {
        b"organizationalUnitName"
    };
    (sh::subst(first_field(&out, name)), rc)
}

/// `openssl x509 -inform der -in CER -noout -enddate | cut -d= -f2`.
fn enddate(cer: &[u8]) -> (Vec<u8>, i32) {
    let (out, rc) = capture(
        128,
        cmd(
            "openssl",
            &[
                b"x509",
                b"-inform",
                b"der",
                b"-in",
                cer,
                b"-noout",
                b"-enddate",
            ],
        ),
    );
    (cut_f2(&out), rc)
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn cmd_csr(c: &Ctx) -> R {
    // mkdir -p "$DIR" && chmod 700 "$DIR": a failing mkdir is not fatal
    // (it is not the last command of the && list), a failing chmod is.
    let made = match fs::create_dir_all(sh::path(&c.dir)) {
        Ok(()) => true,
        Err(e) => {
            let d = String::from_utf8_lossy(&c.dir);
            if cfg!(target_os = "macos") {
                sh::err(format!("mkdir: {}: {}\n", d, sh::strerror(&e)).as_bytes());
            } else {
                sh::err(
                    format!(
                        "mkdir: cannot create directory '{}': {}\n",
                        d,
                        sh::strerror(&e)
                    )
                    .as_bytes(),
                );
            }
            false
        }
    };
    if made {
        if let Err(e) = fs::set_permissions(sh::path(&c.dir), fs::Permissions::from_mode(0o700)) {
            let d = String::from_utf8_lossy(&c.dir);
            if cfg!(target_os = "macos") {
                sh::err(format!("chmod: {}: {}\n", d, sh::strerror(&e)).as_bytes());
            } else {
                sh::err(
                    format!(
                        "chmod: changing permissions of '{}': {}\n",
                        d,
                        sh::strerror(&e)
                    )
                    .as_bytes(),
                );
            }
            return Err(Exit(1));
        }
    }
    let key = c.at("developer-id.key");
    let csr = c.at("developer-id.csr");
    let d = String::from_utf8_lossy(&c.dir).into_owned();
    if exists(&key) {
        return Err(die(&format!(
            "{}/developer-id.key already exists; move it away first (it may be the key of a live certificate)",
            d
        )));
    }
    // (umask 077 && openssl genrsa -out KEY 2048 2>/dev/null)
    let old = sh::umask(0o077);
    let rc = run_status(
        64,
        cmd("openssl", &[b"genrsa", b"-out", &key, b"2048"]),
        false,
        true,
    );
    sh::umask(old);
    check(rc)?;
    check(run_status(
        65,
        cmd(
            "openssl",
            &[
                b"req",
                b"-new",
                b"-key",
                &key,
                b"-out",
                &csr,
                b"-subj",
                b"/CN=Vitruvian Developer ID/O=VitruvianSoftware/C=US",
            ],
        ),
        false,
        false,
    ))?;
    echo(&format!(
        "Made {}/developer-id.key (stays on this Mac) and {}/developer-id.csr.",
        d, d
    ));
    echo("Next: upload the .csr at developer.apple.com > Certificates > + > Developer ID Application (G2),");
    echo(&format!(
        "      save the downloaded certificate as {}/developer-id.cer, then run 'secrets'.",
        d
    ));
    Ok(())
}

/// `bw_note NAME NOTES_FILE FIELDS`.
fn bw_note(name: &str, notes_file: &str, fields: &[Field]) -> R {
    let (list, list_rc) = capture(
        74,
        cmd("bw", &[b"list", b"items", b"--search", name.as_bytes()]),
    );
    let found = match py_load(&list).map_err(|e| format!("json.decoder.JSONDecodeError: {}", e)) {
        Ok(doc) => match has_item(&doc, name) {
            Ok(f) => f,
            Err(e) => {
                sh::err(format!("apple-signing: bw list: {}\n", e).as_bytes());
                false
            }
        },
        Err(e) => {
            sh::err(format!("apple-signing: bw list: {}\n", e).as_bytes());
            false
        }
    };
    if found && list_rc == 0 {
        echo(&format!(
            "    '{}' is already in Bitwarden; left as it is",
            name
        ));
        return Ok(());
    }
    // open(NOTES_FILE).read(): text, UTF-8, universal newlines.
    let (doc, py_rc) = match fs::read(notes_file) {
        Ok(b) => match String::from_utf8(b) {
            Ok(s) => (
                note_doc(name, &s.replace("\r\n", "\n").replace('\r', "\n"), fields),
                0,
            ),
            Err(_) => {
                sh::err(format!("apple-signing: {}: not UTF-8\n", notes_file).as_bytes());
                (String::new(), 1)
            }
        },
        Err(e) => {
            sh::err(format!("apple-signing: {}: {}\n", notes_file, sh::strerror(&e)).as_bytes());
            (String::new(), 1)
        }
    };
    let (enc, enc_rc) = feed(82, cmd("bw", &[b"encode"]), doc.as_bytes(), false);
    let (_, create_rc) = feed(82, cmd("bw", &[b"create", b"item"]), &enc, true);
    check(pipefail(&[py_rc, enc_rc, create_rc]))?;
    echo(&format!("    saved '{}'", name));
    Ok(())
}

fn cmd_secrets(c: &Ctx, args: &[Vec<u8>]) -> R {
    if args.len() != 3 {
        return Err(usage());
    }
    let (key_id, issuer, p8_in) = (&args[0], &args[1], &args[2]);
    let d = String::from_utf8_lossy(&c.dir).into_owned();
    if !is_file(&c.at("developer-id.key")) {
        return Err(die(&format!("no {}/developer-id.key; run 'csr' first", d)));
    }
    if !is_file(&c.at("developer-id.cer")) {
        return Err(die(&format!(
            "no {}/developer-id.cer; download the certificate from developer.apple.com",
            d
        )));
    }
    if !is_file(p8_in) {
        return Err(die(&format!(
            "no API key at {}",
            String::from_utf8_lossy(p8_in)
        )));
    }
    let (cert_pub, _) = capture(
        92,
        cmd(
            "openssl",
            &[
                b"x509",
                b"-inform",
                b"der",
                b"-in",
                &c.at("developer-id.cer"),
                b"-noout",
                b"-pubkey",
            ],
        ),
    );
    let mut rsa = cmd(
        "openssl",
        &[b"rsa", b"-in", &c.at("developer-id.key"), b"-pubout"],
    );
    rsa.stderr(Stdio::null())
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped());
    let key_pub = rsa.output().map(|o| o.stdout).unwrap_or_default();
    if cert_pub != key_pub {
        return Err(die("developer-id.cer was not issued for developer-id.key"));
    }
    let (name, rc) = cert_field(c, "CN");
    check(rc)?;
    let (team, rc) = cert_field(c, "OU");
    check(rc)?;
    let name_s = String::from_utf8_lossy(&name).into_owned();
    if !name.starts_with(b"Developer ID Application:") {
        return Err(die(&format!(
            "developer-id.cer is '{}', not a Developer ID Application certificate",
            name_s
        )));
    }
    std::env::remove_var("GH_TOKEN");
    std::env::remove_var("GITHUB_TOKEN");
    enter(&c.dir)?;
    sh::umask(0o077);

    echo("1/5 Building the certificate bundle (random password, never shown)");
    let p = random_password();
    std::env::set_var("P", sh::os(&p));
    check(run_status(
        103,
        cmd(
            "openssl",
            &[
                b"x509",
                b"-inform",
                b"der",
                b"-in",
                b"developer-id.cer",
                b"-out",
                b"developer-id.pem",
            ],
        ),
        false,
        false,
    ))?;
    check(run_status(
        105,
        cmd(
            "openssl",
            &[
                b"pkcs12",
                b"-export",
                b"-inkey",
                b"developer-id.key",
                b"-in",
                b"developer-id.pem",
                b"-name",
                &name,
                b"-out",
                b"developer-id.p12",
                b"-passout",
                b"env:P",
                b"-keypbe",
                b"PBE-SHA1-3DES",
                b"-certpbe",
                b"PBE-SHA1-3DES",
                b"-macalg",
                b"sha1",
            ],
        ),
        false,
        false,
    ))?;
    let p8 = sh::cat(&[b"AuthKey_", key_id, b".p8"]);
    if !same_file(p8_in, &p8) {
        check(run_status(107, cmd("mv", &[p8_in, &p8]), false, false))?;
    }
    if let Err(e) = sh::write_file(
        b"notary.env",
        &sh::cat(&[b"KEY_ID=", key_id, b"\nISSUER_ID=", issuer, b"\n"]),
        0o666,
    ) {
        sh::redirect_error(110, b"notary.env", &e);
        return Err(Exit(1));
    }

    echo("2/5 Checking Apple accepts the API key");
    let rc = run_status(
        113,
        cmd(
            "xcrun",
            &[
                b"notarytool",
                b"history",
                b"--key",
                &p8,
                b"--key-id",
                key_id,
                b"--issuer",
                issuer,
            ],
        ),
        true,
        false,
    );
    if rc != 0 {
        return Err(die(&format!(
            "Apple rejected the API key (key id {}, issuer {})",
            String::from_utf8_lossy(key_id),
            String::from_utf8_lossy(issuer)
        )));
    }

    echo(&format!(
        "3/5 Saving the five GitHub secrets to {}",
        String::from_utf8_lossy(&c.repo)
    ));
    let p12_b64 = b64_file(b"developer-id.p12");
    let p8_b64 = b64_file(&p8);
    let inputs: [(Result<Vec<u8>, ()>, &str); 5] = [
        (p12_b64, SECRETS[0]),
        (Ok(p.clone()), SECRETS[1]),
        (p8_b64, SECRETS[2]),
        (Ok(key_id.clone()), SECRETS[3]),
        (Ok(issuer.clone()), SECRETS[4]),
    ];
    for (input, secret) in inputs {
        let (data, first_rc) = match input {
            Ok(d) => (d, 0),
            Err(()) => (Vec::new(), 1),
        };
        let sname = sh::cat(&[&c.prefix, b"_", secret.as_bytes()]);
        let (_, rc) = feed(
            117,
            cmd("gh", &[b"secret", b"set", &sname, b"--repo", &c.repo]),
            &data,
            false,
        );
        check(pipefail(&[first_rc, rc]))?;
    }

    echo("4/5 Saving to Bitwarden (it may ask for your master password)");
    let (st, _) = capture(124, cmd("bw", &[b"status"]));
    let unlocked = match py_load(&st) {
        Ok(PyJson::Dict(items)) => match items.iter().find(|(k, _)| k == "status") {
            Some((_, PyJson::Str(s))) => s.trim_end_matches('\n') == "unlocked",
            Some(_) => false,
            None => {
                sh::err(b"apple-signing: bw status: KeyError: 'status'\n");
                false
            }
        },
        Ok(_) => {
            sh::err(b"apple-signing: bw status: TypeError: not an object\n");
            false
        }
        Err(e) => {
            sh::err(
                format!(
                    "apple-signing: bw status: json.decoder.JSONDecodeError: {}\n",
                    e
                )
                .as_bytes(),
            );
            false
        }
    };
    if !unlocked {
        let (sess, rc) = capture(125, cmd("bw", &[b"unlock", b"--raw"]));
        check(rc)?;
        std::env::set_var("BW_SESSION", sh::os(&sh::subst(sess)));
    }
    check(run_status(127, cmd("bw", &[b"sync"]), true, false))?;
    let (exp, rc) = enddate(b"developer-id.cer");
    check(rc)?;
    let expires = String::from_utf8_lossy(&sh::subst(exp)).into_owned();
    let p12_text = match b64_file(b"developer-id.p12") {
        Ok(t) => t,
        Err(()) => return Err(Exit(1)),
    };
    if let Err(e) = sh::write_file(b"p12.b64", &p12_text, 0o666) {
        sh::redirect_error(129, b"p12.b64", &e);
        return Err(Exit(1));
    }
    let p_s = String::from_utf8_lossy(&p).into_owned();
    let team_s = String::from_utf8_lossy(&team).into_owned();
    let exp_note = format!("notes = base64 of the .p12; expires {}", expires);
    bw_note(
        "Apple Developer ID Application certificate (p12)",
        "p12.b64",
        &[
            Field {
                name: "p12 password",
                value: &p_s,
                kind: 1,
            },
            Field {
                name: "team id",
                value: &team_s,
                kind: 0,
            },
            Field {
                name: "notes",
                value: &exp_note,
                kind: 0,
            },
        ],
    )?;
    let kid = String::from_utf8_lossy(key_id).into_owned();
    let iss = String::from_utf8_lossy(issuer).into_owned();
    bw_note(
        "App Store Connect API key (notary)",
        &String::from_utf8_lossy(&p8),
        &[
            Field {
                name: "key id",
                value: &kid,
                kind: 0,
            },
            Field {
                name: "issuer id",
                value: &iss,
                kind: 0,
            },
        ],
    )?;
    // cat developer-id.key developer-id.pem > keypair.pem
    let mut pair = Vec::new();
    let mut cat_rc = 0;
    for f in ["developer-id.key", "developer-id.pem"] {
        match fs::read(f) {
            Ok(b) => pair.extend(b),
            Err(e) => {
                sh::err(format!("cat: {}: {}\n", f, sh::strerror(&e)).as_bytes());
                cat_rc = 1;
            }
        }
    }
    if let Err(e) = sh::write_file(b"keypair.pem", &pair, 0o666) {
        sh::redirect_error(139, b"keypair.pem", &e);
        return Err(Exit(1));
    }
    check(cat_rc)?;
    bw_note(
        "Apple Developer ID private key + certificate (PEM)",
        "keypair.pem",
        &[
            Field {
                name: "team id",
                value: &team_s,
                kind: 0,
            },
            Field {
                name: "what",
                value: "private key then certificate, PEM",
                kind: 0,
            },
        ],
    )?;
    let _ = fs::remove_file("p12.b64");
    let _ = fs::remove_file("keypair.pem");

    echo("5/5 Installing the identity in your login keychain (for signing on this Mac)");
    if sh::which(b"security").is_some() {
        let found = run_status(
            148,
            cmd(
                "security",
                &[
                    b"find-certificate",
                    b"-c",
                    b"Developer ID Certification Authority",
                ],
            ),
            true,
            true,
        );
        if found != 0 {
            check(run_status(
                149,
                cmd(
                    "curl",
                    &[
                        b"-fsSL",
                        b"-o",
                        b"DeveloperIDG2CA.cer",
                        b"https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer",
                    ],
                ),
                false,
                false,
            ))?;
            let kc = keychain(150)?;
            check(run_status(
                150,
                cmd("security", &[b"import", b"DeveloperIDG2CA.cer", b"-k", &kc]),
                true,
                false,
            ))?;
        }
        let kc = keychain(152)?;
        let rc = run_status(
            152,
            cmd(
                "security",
                &[
                    b"import",
                    b"developer-id.p12",
                    b"-k",
                    &kc,
                    b"-P",
                    &p,
                    b"-T",
                    b"/usr/bin/codesign",
                ],
            ),
            true,
            false,
        );
        if rc != 0 {
            echo("    (already in the keychain)");
        }
    } else {
        echo("    no 'security' command: not a Mac, skipped");
    }
    std::env::remove_var("P");
    echo("");
    cmd_check(c)
}

/// `"$HOME/Library/Keychains/login.keychain-db"`.
fn keychain(line: u32) -> R<Vec<u8>> {
    match sh::env("HOME") {
        Some(h) => Ok(sh::cat(&[&h, b"/Library/Keychains/login.keychain-db"])),
        None => {
            bash_diag(line, b"HOME: unbound variable");
            Err(Exit(1))
        }
    }
}

/// `cd "$DIR"` (and $PWD for what runs next).
fn enter(dir: &[u8]) -> R {
    let old = match sh::env("PWD") {
        Some(p) if p.starts_with(b"/") => p,
        _ => std::env::current_dir()
            .map(|d| sh::path_bytes(&d))
            .unwrap_or_default(),
    };
    if let Err(e) = std::env::set_current_dir(sh::path(dir)) {
        bash_diag(
            99,
            &sh::cat(&[b"cd: ", dir, b": ", sh::strerror(&e).as_bytes()]),
        );
        return Err(Exit(1));
    }
    let full = if dir.starts_with(b"/") {
        dir.to_vec()
    } else {
        sh::cat(&[&old, b"/", dir])
    };
    std::env::set_var("PWD", sh::os(&logical(&full)));
    Ok(())
}

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

/// grep -cE "^${PREFIX}_(...)[[:space:]]" over `gh secret list`.
pub fn count_secrets(list: &[u8], prefix: &[u8]) -> usize {
    sh::lines(list)
        .iter()
        .filter(|l| {
            SECRETS.iter().any(|s| {
                let want = sh::cat(&[prefix, b"_", s.as_bytes()]);
                l.starts_with(&want)
                    && l.get(want.len()).map_or(false, |c| {
                        matches!(c, b' ' | b'\t' | b'\n' | b'\x0b' | b'\x0c' | b'\r')
                    })
            })
        })
        .count()
}

fn cmd_check(c: &Ctx) -> R {
    let mut ok = 0;
    if sh::which(b"security").is_some() {
        let (out, _) = capture(
            165,
            cmd(
                "security",
                &[b"find-identity", b"-v", b"-p", b"codesigning"],
            ),
        );
        let n = sh::lines(&out)
            .iter()
            .filter(|l| sh::contains(l, b"Developer ID Application"))
            .count();
        echo(&format!(
            "  Developer ID signing identities on this Mac: {}",
            n
        ));
    }
    let (out, _) = capture(168, cmd("gh", &[b"secret", b"list", b"--repo", &c.repo]));
    let n = count_secrets(&out, &c.prefix);
    echo(&format!(
        "  GitHub secrets set on {}: {} of 5",
        String::from_utf8_lossy(&c.repo),
        n
    ));
    if n != 5 {
        ok = 1;
    }
    let cer = c.at("developer-id.cer");
    if is_file(&cer) {
        // Inside echo's arguments a failure is not acted on.
        let (cn, _) = cert_field(c, "CN");
        let (exp, _) = enddate(&cer);
        let exp = sh::subst(
            sh::lines(&exp)
                .iter()
                .flat_map(|l| {
                    let mut v = b"expires ".to_vec();
                    v.extend_from_slice(l);
                    v.push(b'\n');
                    v
                })
                .collect(),
        );
        echo(&format!(
            "  certificate: {}, {}",
            String::from_utf8_lossy(&cn),
            String::from_utf8_lossy(&exp)
        ));
    }
    check(ok)
}

/// `. "$DIR/notary.env"` for the two lines `secrets` writes: NAME=VALUE,
/// VALUE taken as the shell would read a plain, '...' or "..." word.
pub fn read_env_file(text: &[u8]) -> Vec<(Vec<u8>, Vec<u8>)> {
    let mut out = Vec::new();
    for line in sh::lines(text) {
        let l = sh::read_trim(&line);
        if l.is_empty() || l[0] == b'#' {
            continue;
        }
        let eq = match l.iter().position(|&c| c == b'=') {
            Some(i) => i,
            None => continue,
        };
        let name = &l[..eq];
        let valid = !name.is_empty()
            && !name[0].is_ascii_digit()
            && name.iter().all(|c| c.is_ascii_alphanumeric() || *c == b'_');
        if !valid {
            continue;
        }
        let raw = &l[eq + 1..];
        let mut v = Vec::new();
        let mut i = 0;
        while i < raw.len() {
            match raw[i] {
                b'\'' => {
                    i += 1;
                    while i < raw.len() && raw[i] != b'\'' {
                        v.push(raw[i]);
                        i += 1;
                    }
                    i += 1;
                }
                b'"' => {
                    i += 1;
                    while i < raw.len() && raw[i] != b'"' {
                        if raw[i] == b'\\' && i + 1 < raw.len() && b"\"\\$`".contains(&raw[i + 1]) {
                            i += 1;
                        }
                        v.push(raw[i]);
                        i += 1;
                    }
                    i += 1;
                }
                b'\\' if i + 1 < raw.len() => {
                    v.push(raw[i + 1]);
                    i += 2;
                }
                b' ' | b'\t' => break,
                c => {
                    v.push(c);
                    i += 1;
                }
            }
        }
        out.push((name.to_vec(), v));
    }
    out
}

fn cmd_notary_status(c: &Ctx, args: &[Vec<u8>]) -> R {
    if args.len() > 1 {
        return Err(usage());
    }
    let d = String::from_utf8_lossy(&c.dir).into_owned();
    let envf = c.at("notary.env");
    if !is_file(&envf) {
        return Err(die(&format!("no {}/notary.env; run 'secrets' first", d)));
    }
    let text = fs::read(sh::path(&envf)).unwrap_or_default();
    let mut key_id = Vec::new();
    let mut issuer = Vec::new();
    for (k, v) in read_env_file(&text) {
        match k.as_slice() {
            b"KEY_ID" => key_id = v,
            b"ISSUER_ID" => issuer = v,
            _ => {}
        }
    }
    if key_id.is_empty() || issuer.is_empty() {
        return Err(die(&format!("{}/notary.env lacks KEY_ID or ISSUER_ID", d)));
    }
    let key = sh::cat(&[&c.dir, b"/AuthKey_", &key_id, b".p8"]);
    if !is_file(&key) {
        return Err(die(&format!(
            "no API key at {}",
            String::from_utf8_lossy(&key)
        )));
    }
    let auth: [&[u8]; 6] = [b"--key", &key, b"--key-id", &key_id, b"--issuer", &issuer];
    let with = |verb: &[u8], id: Option<&[u8]>| {
        let mut a: Vec<&[u8]> = vec![b"notarytool", verb];
        if let Some(id) = id {
            a.push(id);
        }
        a.extend_from_slice(&auth);
        cmd("xcrun", &a)
    };
    if args.is_empty() {
        return check(run_status(191, with(b"history", None), false, false));
    }
    let id = &args[0];
    let (info, rc) = capture(195, with(b"info", Some(id)));
    check(rc)?;
    let info = sh::subst(info);
    sh::out(&sh::cat(&[&info, b"\n"]));
    let mut status_lines: Vec<Vec<u8>> = Vec::new();
    for l in sh::lines(&sh::cat(&[&info, b"\n"])) {
        let mut s: &[u8] = &l;
        while s.first() == Some(&b' ') {
            s = &s[1..];
        }
        if let Some(v) = s.strip_prefix(b"status: ") {
            status_lines.push(v.to_vec());
        }
    }
    let status = status_lines.join(&b'\n');
    if !status.is_empty() && status != b"In Progress" {
        echo("");
        echo("Apple's report:");
        return check(run_status(200, with(b"log", Some(id)), false, false));
    }
    Ok(())
}

/// The whole command line (argv[1..]); the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    let dir = if sh::env_set_nonempty("APPLE_SIGNING_DIR") {
        sh::env_or_empty("APPLE_SIGNING_DIR")
    } else {
        match sh::env("HOME") {
            Some(h) => sh::cat(&[&h, b"/.vitruvian-signing"]),
            None => {
                bash_diag(41, b"HOME: unbound variable");
                return 1;
            }
        }
    };
    let c = Ctx {
        dir,
        repo: sh::env_or("APPLE_SIGNING_REPO", b"VitruvianSoftware/vitruvian-core"),
        prefix: sh::env_or("APPLE_SIGNING_SECRET_PREFIX", b"VITRUVIAN"),
    };
    let rest = if args.is_empty() { &[][..] } else { &args[1..] };
    let r = match args.first().map(Vec::as_slice) {
        Some(b"csr") => cmd_csr(&c),
        Some(b"secrets") => cmd_secrets(&c, rest),
        Some(b"check") => cmd_check(&c),
        Some(b"notary-status") => cmd_notary_status(&c, rest),
        _ => Err(usage()),
    };
    match r {
        Ok(()) => 0,
        Err(Exit(code)) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn python_dumps_text() {
        assert_eq!(
            py_dumps_str("a\"b\\c\n\u{7f}é😀\u{1}"),
            "\"a\\\"b\\\\c\\n\\u007f\\u00e9\\ud83d\\ude00\\u0001\""
        );
        assert_eq!(
            note_doc("N", "x\n", &[Field { name: "k", value: "v", kind: 1 }]),
            "{\"type\": 2, \"name\": \"N\", \"secureNote\": {\"type\": 0}, \"notes\": \"x\\n\", \"fields\": [{\"name\": \"k\", \"value\": \"v\", \"type\": 1}]}\n"
        );
    }

    #[test]
    fn finding_an_item_as_python_does() {
        let j = |s: &str| py_load(s.as_bytes()).unwrap();
        assert_eq!(
            has_item(&j("[{\"name\":\"a\"},{\"name\":\"b\"}]"), "b"),
            Ok(true)
        );
        assert_eq!(has_item(&j("[]"), "b"), Ok(false));
        // any() stops at the match, before a bad entry.
        assert_eq!(has_item(&j("[{\"name\":\"b\"}, 1]"), "b"), Ok(true));
        assert!(has_item(&j("[1, {\"name\":\"b\"}]"), "b").is_err());
        assert!(has_item(&j("[{\"id\":1}]"), "b").is_err());
        assert_eq!(has_item(&j("{}"), "b"), Ok(false));
        assert!(has_item(&j("{\"a\":1}"), "b").is_err());
        assert_eq!(has_item(&j("[{\"name\":1}]"), "b"), Ok(false));
    }

    #[test]
    fn counting_secrets() {
        let list = b"VITRUVIAN_SIGNING_CERT_P12\tx\nVITRUVIAN_NOTARY_KEY_ID x\nVITRUVIAN_NOTARY_KEY_IDX\t1\nOTHER_NOTARY_KEY_ID\t1\nVITRUVIAN_NOTARY_ISSUER_ID";
        assert_eq!(count_secrets(list, b"VITRUVIAN"), 2);
    }

    #[test]
    fn fields_and_cuts() {
        assert_eq!(
            first_field(
                b"subject=\n    commonName   =  Dev: X\n    commonName = Y\n",
                b"commonName"
            ),
            b"Dev: X".to_vec()
        );
        assert_eq!(
            cut_f2(b"notAfter=Oct 1 GMT\nplain\na=b=c\n"),
            b"Oct 1 GMT\nplain\nb\n".to_vec()
        );
    }

    #[test]
    fn notary_env_words() {
        let v = read_env_file(b"KEY_ID=K1\nISSUER_ID='a b'\n# c\nX=\"q\\\"r\"\n1A=no\n");
        assert_eq!(
            v,
            vec![
                (b"KEY_ID".to_vec(), b"K1".to_vec()),
                (b"ISSUER_ID".to_vec(), b"a b".to_vec()),
                (b"X".to_vec(), b"q\"r".to_vec()),
            ]
        );
    }

    #[test]
    fn passwords_are_32_without_base64_punctuation() {
        for _ in 0..200 {
            let p = random_password();
            assert_eq!(p.len(), 32);
            assert!(p.iter().all(u8::is_ascii_alphanumeric));
        }
    }
}
