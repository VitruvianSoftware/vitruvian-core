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

//! publish-local: the break-glass local release PUBLISHER, a port of
//! publish-local.sh. Without GitHub Actions, it pushes the slash-form Go-module
//! tags of pulumi-library (go/pkg/<name>/vX.Y.Z) to the mirror and publishes
//! the npm packages (mcp-slack, pulumi-library ts/packages/*). Dry run unless
//! `--execute`.
//!
//! Held to the script by publish_local_rs_parity_test.py: same exit codes,
//! stdout, stderr, and the same git / gh / npm calls. The manifests and
//! package.json files are read natively (serde_json) with the semantics of
//! the script's `jq -r` filters, including jq's diagnostics and exit codes
//! for a missing file or a value of the wrong type.

use std::fmt;
use std::fs;
use std::process::{Command, Stdio};

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use shell_compat as sh;

const MIRROR_BASE: &str = "https://github.com/VitruvianSoftware";
const NPM_TOKEN_SECRET: &str = "NPM_PUBLISH_TOKEN";

// Lines of publish-local.sh the diagnostics bash prints name.
const LINE_ROOT: u32 = 80;
const LINE_CLONE: u32 = 113;
const LINE_HEAD: u32 = 116;
const LINE_LS_REMOTE: u32 = 124;
const LINE_TAG: u32 = 133;
const LINE_PUSH: u32 = 134;
const LINE_STORE_SET: u32 = 103;
const LINE_NPM_VIEW: u32 = 146;
const LINE_NPM_INSTALL: u32 = 157;
const LINE_NPM_BUILD: u32 = 158;
const LINE_NPM_PUBLISH: u32 = 159;

const USAGE: &str = "Break-glass local release publisher (GitHub Actions down).

Usage:
  bazel run //tools/release:publish-local -- <component> [--package <name>] [--execute]

  <component>    pulumi-library | mcp-slack
  --package <n>  limit to one package (a go/pkg/<n> or ts/packages/<n>); default: all
  --execute      actually publish/push. Omit for a dry run (prints the plan only).

Publish the EXPORTED bump only -- run `bazel run //tools/copybara/sync -- export <component>` first.
GoReleaser binaries (devx, homelab) and nexus-agent are manual: see
docs/operations/break-glass-deploy-runbook.md.
";

/// The Go-module tag for a package + version. The SLASH before the version is
/// mandatory: `go get` resolves a subdir module at .../go/pkg/<name> only via
/// the tag go/pkg/<name>/vX.Y.Z; a dash (go/pkg/<name>-vX.Y.Z) is an "unknown
/// revision" (the 2026-07 cloud_run bug).
pub fn go_module_tag(name: &[u8], version: &[u8]) -> Vec<u8> {
    sh::cat(&[b"go/pkg/", name, b"/v", version])
}

// ---------------------------------------------------------------------------
// JSON, as `jq -r` reads and prints it
// ---------------------------------------------------------------------------

/// A JSON value with object members in document order (jq keeps it; a
/// repeated key keeps its first position and takes the last value).
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(serde_json::Number),
    Str(String),
    Arr(Vec<Json>),
    Obj(Vec<(String, Json)>),
}

struct JsonVisitor;

impl<'de> Visitor<'de> for JsonVisitor {
    type Value = Json;
    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a JSON value")
    }
    fn visit_unit<E>(self) -> Result<Json, E> {
        Ok(Json::Null)
    }
    fn visit_none<E>(self) -> Result<Json, E> {
        Ok(Json::Null)
    }
    fn visit_bool<E>(self, v: bool) -> Result<Json, E> {
        Ok(Json::Bool(v))
    }
    fn visit_i64<E>(self, v: i64) -> Result<Json, E> {
        Ok(Json::Num(v.into()))
    }
    fn visit_u64<E>(self, v: u64) -> Result<Json, E> {
        Ok(Json::Num(v.into()))
    }
    fn visit_f64<E>(self, v: f64) -> Result<Json, E> {
        Ok(serde_json::Number::from_f64(v).map_or(Json::Null, Json::Num))
    }
    fn visit_str<E>(self, v: &str) -> Result<Json, E> {
        Ok(Json::Str(v.to_string()))
    }
    fn visit_string<E>(self, v: String) -> Result<Json, E> {
        Ok(Json::Str(v))
    }
    fn visit_seq<A: SeqAccess<'de>>(self, mut a: A) -> Result<Json, A::Error> {
        let mut v = Vec::new();
        while let Some(x) = a.next_element::<Json>()? {
            v.push(x);
        }
        Ok(Json::Arr(v))
    }
    fn visit_map<A: MapAccess<'de>>(self, mut a: A) -> Result<Json, A::Error> {
        let mut v: Vec<(String, Json)> = Vec::new();
        while let Some((k, x)) = a.next_entry::<String, Json>()? {
            match v.iter_mut().find(|(e, _)| *e == k) {
                Some(slot) => slot.1 = x,
                None => v.push((k, x)),
            }
        }
        Ok(Json::Obj(v))
    }
}

impl<'de> Deserialize<'de> for Json {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Json, D::Error> {
        d.deserialize_any(JsonVisitor)
    }
}

impl Json {
    fn type_name(&self) -> &'static str {
        match self {
            Json::Null => "null",
            Json::Bool(_) => "boolean",
            Json::Num(_) => "number",
            Json::Str(_) => "string",
            Json::Arr(_) => "array",
            Json::Obj(_) => "object",
        }
    }

    /// `.key`: a member of an object, null on null; an error on anything else.
    fn field(&self, key: &str) -> Result<Json, String> {
        match self {
            Json::Obj(m) => Ok(m
                .iter()
                .find(|(k, _)| k == key)
                .map_or(Json::Null, |(_, v)| v.clone())),
            Json::Null => Ok(Json::Null),
            other => Err(format!(
                "Cannot index {} with string \"{}\"",
                other.type_name(),
                key
            )),
        }
    }

    fn truthy(&self) -> bool {
        !matches!(self, Json::Null | Json::Bool(false))
    }

    /// What `jq -r` prints for the value (without the trailing newline).
    pub fn raw(&self) -> String {
        match self {
            Json::Str(s) => s.clone(),
            _ => {
                let mut out = String::new();
                self.pretty(&mut out, 0);
                out
            }
        }
    }

    fn pretty(&self, out: &mut String, depth: usize) {
        let pad = |out: &mut String, d: usize| {
            for _ in 0..d {
                out.push_str("  ");
            }
        };
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Num(n) => out.push_str(&n.to_string()),
            Json::Str(s) => out.push_str(&json_string(s)),
            Json::Arr(v) if v.is_empty() => out.push_str("[]"),
            Json::Obj(v) if v.is_empty() => out.push_str("{}"),
            Json::Arr(v) => {
                out.push_str("[\n");
                for (i, x) in v.iter().enumerate() {
                    pad(out, depth + 1);
                    x.pretty(out, depth + 1);
                    out.push_str(if i + 1 < v.len() { ",\n" } else { "\n" });
                }
                pad(out, depth);
                out.push(']');
            }
            Json::Obj(v) => {
                out.push_str("{\n");
                for (i, (k, x)) in v.iter().enumerate() {
                    pad(out, depth + 1);
                    out.push_str(&json_string(k));
                    out.push_str(": ");
                    x.pretty(out, depth + 1);
                    out.push_str(if i + 1 < v.len() { ",\n" } else { "\n" });
                }
                pad(out, depth);
                out.push('}');
            }
        }
    }
}

/// A JSON string literal the way jq writes one (DEL escaped too).
fn json_string(s: &str) -> String {
    serde_json::to_string(s)
        .unwrap_or_default()
        .replace('\u{7f}', "\\u007f")
}

/// The filters publish-local.sh runs with `jq -r`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Filter {
    /// `to_entries[0].value`
    FirstValue,
    /// `.KEY`
    Field(&'static str),
    /// `.KEY // false`
    FieldOrFalse(&'static str),
}

/// Apply `f` to the parsed document: Ok(the value), or Err(jq's message
/// after "jq: error (at FILE:N): " and its exit status).
pub fn apply(f: Filter, doc: &Json) -> Result<Json, (String, i32)> {
    match f {
        Filter::FirstValue => match doc {
            Json::Obj(m) => Ok(m.first().map_or(Json::Null, |(_, v)| v.clone())),
            // An array's keys are its indices.
            Json::Arr(v) => Ok(v.first().cloned().unwrap_or(Json::Null)),
            other => Err((
                format!("{} ({}) has no keys", other.type_name(), short(other)),
                5,
            )),
        },
        Filter::Field(k) => doc.field(k).map_err(|e| (e, 5)),
        Filter::FieldOrFalse(k) => match doc.field(k) {
            Ok(v) if v.truthy() => Ok(v),
            // `//` swallows the error of its left side.
            _ => Ok(Json::Bool(false)),
        },
    }
}

/// jq's abbreviated rendering of a value in an error message (compact,
/// cut at 11 bytes with "...").
fn short(v: &Json) -> String {
    let s = match v {
        Json::Str(s) => json_string(s),
        Json::Num(n) => n.to_string(),
        Json::Bool(b) => b.to_string(),
        Json::Null => "null".into(),
        _ => {
            let p = v.raw();
            p.split('\n')
                .map(str::trim_start)
                .collect::<Vec<_>>()
                .join("")
        }
    };
    if s.len() > 11 {
        let mut cut = 11;
        while !s.is_char_boundary(cut) {
            cut -= 1;
        }
        format!("{}...", &s[..cut])
    } else {
        s
    }
}

/// `"$(jq -r FILTER FILE)"`: the value's raw text with trailing newlines
/// removed, or (jq's diagnostic on stderr) its exit status.
pub fn jq_r(file: &[u8], f: Filter) -> Result<Vec<u8>, i32> {
    let data = match fs::read(sh::path(file)) {
        Ok(d) => d,
        Err(e) => {
            sh::err(&sh::cat(&[
                b"jq: error: Could not open ",
                file,
                b": ",
                sh::strerror(&e).as_bytes(),
                b"\n",
            ]));
            return Err(2);
        }
    };
    let lines = data.iter().filter(|&&c| c == b'\n').count();
    // jq runs the filter over every value in the file; the manifests and
    // package.json hold one. Whitespace only = no values, no output.
    let mut values = Vec::new();
    let mut stream = serde_json::Deserializer::from_slice(&data).into_iter::<Json>();
    loop {
        match stream.next() {
            None => break,
            Some(Ok(v)) => values.push(v),
            Some(Err(e)) => {
                for v in &values {
                    // Output produced before the parse error still prints.
                    if let Ok(x) = apply(f, v) {
                        sh::out(&sh::cat(&[x.raw().as_bytes(), b"\n"]));
                    }
                }
                sh::err(&sh::cat(&[
                    b"jq: error (at ",
                    file,
                    format!(":{}): {}\n", lines, e).as_bytes(),
                ]));
                return Err(2);
            }
        }
    }
    let mut out = Vec::new();
    for v in &values {
        match apply(f, v) {
            Ok(x) => {
                out.extend_from_slice(x.raw().as_bytes());
                out.push(b'\n');
            }
            Err((msg, code)) => {
                sh::err(&sh::cat(&[
                    b"jq: error (at ",
                    file,
                    format!(":{}): {}\n", lines, msg).as_bytes(),
                ]));
                return Err(code);
            }
        }
    }
    Ok(sh::subst(out))
}

// ---------------------------------------------------------------------------
// the tool
// ---------------------------------------------------------------------------

/// How the run ends early: the exit status (any message already printed).
type Exit = i32;

fn note(msg: &[u8]) {
    sh::err(&sh::cat(&[b"publish-local: ", msg, b"\n"]));
}

fn die(msg: &[u8]) -> Exit {
    note(msg);
    1
}

/// `"$DIR"/*/` (or with a literal suffix): the directories in `dir`, hidden
/// ones excluded, in C-locale order, each with a trailing slash as bash's
/// glob leaves it.
fn glob_dirs(dir: &[u8]) -> Vec<Vec<u8>> {
    let mut v = Vec::new();
    if let Ok(rd) = fs::read_dir(sh::path(dir)) {
        for e in rd.flatten() {
            use std::os::unix::ffi::OsStrExt;
            let n = e.file_name().as_bytes().to_vec();
            if n.starts_with(b".") {
                continue;
            }
            let p = sh::cat(&[dir, b"/", &n]);
            if sh::is_dir(&p) {
                v.push(n);
            }
        }
    }
    v.sort();
    v.into_iter()
        .map(|n| sh::cat(&[dir, b"/", &n, b"/"]))
        .collect()
}

/// `"$DIR"/*/"$NAME"`: existing paths, in glob order.
fn glob_named(dir: &[u8], name: &[u8]) -> Vec<Vec<u8>> {
    let mut v = Vec::new();
    if let Ok(rd) = fs::read_dir(sh::path(dir)) {
        for e in rd.flatten() {
            use std::os::unix::ffi::OsStrExt;
            let n = e.file_name().as_bytes().to_vec();
            if n.starts_with(b".") {
                continue;
            }
            let p = sh::cat(&[dir, b"/", &n, b"/", name]);
            if fs::symlink_metadata(sh::path(&p)).is_ok() {
                v.push((n, p));
            }
        }
    }
    v.sort();
    v.into_iter().map(|(_, p)| p).collect()
}

/// `cat FILE` inside a command substitution: the bytes, or cat's
/// diagnostic and a failure.
fn cat_file(p: &[u8]) -> Result<Vec<u8>, ()> {
    match fs::read(sh::path(p)) {
        Ok(d) => Ok(d),
        Err(e) => {
            sh::err(&sh::cat(&[
                b"cat: ",
                p,
                b": ",
                sh::strerror(&e).as_bytes(),
                b"\n",
            ]));
            Err(())
        }
    }
}

struct Run {
    root: Vec<u8>,
    scratch: Vec<u8>,
    package: Vec<u8>,
    execute: bool,
}

impl Run {
    /// `gh auth token 2>/dev/null || die ...` inside `$(...)`: the token; on
    /// failure die's message is printed but, being only an argument's
    /// substitution, it does not stop the script.
    fn gh_token(&self) -> Vec<u8> {
        let mut c = Command::new("gh");
        c.args(["auth", "token"])
            .stdin(Stdio::inherit())
            .stderr(Stdio::null());
        c.stdout(Stdio::piped());
        let (status, stdout) = match c.output() {
            Ok(o) => (sh::status_code(o.status), o.stdout),
            Err(_) => (127, Vec::new()),
        };
        if status != 0 {
            note(b"not logged in to GitHub -- run 'gh auth login'");
        }
        sh::subst(stdout)
    }

    fn npm_token(&self) -> Result<Vec<u8>, Exit> {
        let store = sh::cat(&[&self.root, b"/tools/sync-env-secrets/secrets"]);
        for f in glob_named(&store, NPM_TOKEN_SECRET.as_bytes()) {
            if sh::is_file(&f) {
                // The script's `{ cat "$f"; return 0; }`: errexit is off in
                // a command substitution, so a failed cat still returns 0.
                return Ok(sh::subst(cat_file(&f).unwrap_or_default()));
            }
        }
        note(b"");
        note(format!("{} isn't stored yet -- saving it now via the secret store (it prompts, then pulls -> writes -> pushes SAFELY, so it can't clobber your vault).", NPM_TOKEN_SECRET).as_bytes());
        note(b"It's a @vitruviansoftware npm AUTOMATION token: npmjs.com -> the org -> Access Tokens -> Generate -> Automation.");
        let mut c = Command::new("bash");
        c.arg(sh::os(&sh::cat(&[
            &self.root,
            b"/tools/sync-env-secrets/sync-env-secrets.sh",
        ])))
        .args(["set", "shared", NPM_TOKEN_SECRET])
        .env("BUILD_WORKSPACE_DIRECTORY", sh::os(&self.root));
        // 1>&2: the store tool's output goes to our stderr.
        match std::io::stderr().as_fd_dup() {
            Some(fd) => {
                c.stdout(fd);
            }
            None => {
                c.stdout(Stdio::inherit());
            }
        }
        if sh::status(LINE_STORE_SET, &mut c, false) != 0 {
            return Err(die(format!("could not save {}. Unlock Bitwarden (bazel run //tools/sync-env-secrets:unlock) and retry -- no partial push occurred.", NPM_TOKEN_SECRET).as_bytes()));
        }
        let p = sh::cat(&[&store, b"/shared/", NPM_TOKEN_SECRET.as_bytes()]);
        cat_file(&p).map(sh::subst).map_err(|_| 1)
    }

    fn git(&self, clone: &[u8]) -> Command {
        let mut c = Command::new("git");
        c.arg("-C").arg(sh::os(clone));
        c
    }

    fn publish_go_modules(&self) -> Result<(), Exit> {
        let mirror = format!("{}/pulumi-library.git", MIRROR_BASE);
        let clone = sh::cat(&[&self.scratch, b"/pulumi-library"]);
        note(
            format!(
                "cloning {} (shallow) to check tags + push at its HEAD",
                mirror
            )
            .as_bytes(),
        );
        let url = sh::cat(&[
            b"https://x-access-token:",
            &self.gh_token(),
            b"@github.com/VitruvianSoftware/pulumi-library.git",
        ]);
        let mut c = Command::new("git");
        c.args(["clone", "--quiet", "--depth", "1"])
            .arg(sh::os(&url))
            .arg(sh::os(&clone));
        if sh::status(LINE_CLONE, &mut c, false) != 0 {
            return Err(die(b"clone failed (does your gh token have access to VitruvianSoftware/pulumi-library?)"));
        }
        let mut c = self.git(&clone);
        c.args(["rev-parse", "HEAD"]);
        let r = sh::capture_stdout(LINE_HEAD, &mut c);
        if !r.ok() {
            return Err(r.status);
        }
        let head = sh::subst(r.stdout);
        let head9 = &head[..head.len().min(9)];
        let pkgs = sh::cat(&[&self.root, b"/packages/pulumi/library/go/pkg"]);
        for pkgdir in glob_dirs(&pkgs) {
            let name = sh::basename(&pkgdir);
            let manifest = sh::cat(&[&pkgdir, b"/.release-please-manifest.json"]);
            if !sh::is_file(&manifest) {
                continue;
            }
            if !self.package.is_empty() && self.package != name {
                continue;
            }
            let version = jq_r(&manifest, Filter::FirstValue)?;
            let tag = go_module_tag(&name, &version);
            let mut c = self.git(&clone);
            c.args(["ls-remote", "--tags"])
                .arg(&mirror)
                .arg(sh::os(&sh::cat(&[b"refs/tags/", &tag])));
            let r = sh::capture_stdout(LINE_LS_REMOTE, &mut c);
            // `| grep -q .` under pipefail: a line with a character in it,
            // AND ls-remote itself succeeded.
            let listed = r.ok() && sh::lines(&r.stdout).iter().any(|l| !l.is_empty());
            if listed {
                note(&sh::cat(&[b"skip ", &tag, b" -- already on the mirror"]));
                continue;
            }
            if !self.execute {
                sh::out(&sh::cat(&[
                    b"DRYRUN go-tag: ",
                    &tag,
                    b" -> ",
                    head9,
                    b" (mirror HEAD)\n",
                ]));
                continue;
            }
            note(&sh::cat(&[
                b"tagging ",
                &tag,
                b" at ",
                head9,
                b" and pushing",
            ]));
            let mut c = self.git(&clone);
            c.arg("tag").arg(sh::os(&tag)).arg(sh::os(&head));
            let st = sh::status(LINE_TAG, &mut c, false);
            if st != 0 {
                return Err(st);
            }
            let mut c = self.git(&clone);
            c.args(["push", "origin"]).arg(sh::os(&tag));
            let st = sh::status(LINE_PUSH, &mut c, false);
            if st != 0 {
                return Err(st);
            }
        }
        Ok(())
    }

    fn publish_npm_dir(&self, dir: &[u8], token: &[u8]) -> Result<(), Exit> {
        let pj = sh::cat(&[dir, b"/package.json"]);
        let name = jq_r(&pj, Filter::Field("name"))?;
        let version = jq_r(&pj, Filter::Field("version"))?;
        let private = jq_r(&pj, Filter::FieldOrFalse("private"))?;
        if private == b"true" {
            note(&sh::cat(&[b"skip ", &name, b" -- private:true"]));
            return Ok(());
        }
        let spec = sh::cat(&[&name, b"@", &version]);
        let mut c = Command::new("npm");
        c.arg("view")
            .arg(sh::os(&spec))
            .arg("version")
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        if sh::status(LINE_NPM_VIEW, &mut c, true) == 0 {
            note(&sh::cat(&[b"skip ", &spec, b" -- already on the registry"]));
            return Ok(());
        }
        if !self.execute {
            sh::out(&sh::cat(&[
                b"DRYRUN npm-publish: ",
                &spec,
                b" (",
                dir,
                b")\n",
            ]));
            return Ok(());
        }
        note(&sh::cat(&[b"building + publishing ", &spec]));
        let steps: [(u32, &[&str], bool); 3] = [
            (
                LINE_NPM_INSTALL,
                &["install", "--no-audit", "--no-fund"],
                false,
            ),
            (LINE_NPM_BUILD, &["run", "build", "--if-present"], false),
            (LINE_NPM_PUBLISH, &["publish", "--access", "public"], true),
        ];
        // `( cd "$dir"; ... )`: cd also sets $PWD, to the path as given (not
        // resolved), without the glob's trailing slash.
        let mut pwd = dir.to_vec();
        while pwd.len() > 1 && pwd.ends_with(b"/") {
            pwd.pop();
        }
        for (line, args, with_token) in steps {
            let mut c = Command::new("npm");
            c.args(args)
                .current_dir(sh::path(dir))
                .env("PWD", sh::os(&pwd));
            if with_token {
                c.env("NODE_AUTH_TOKEN", sh::os(token));
            }
            let st = sh::status(line, &mut c, false);
            if st != 0 {
                return Err(st);
            }
        }
        Ok(())
    }

    fn publish_npm_component(&self, kind: &str) -> Result<(), Exit> {
        let token = if self.execute {
            self.npm_token()?
        } else {
            Vec::new()
        };
        match kind {
            "mcp-slack" => {
                self.publish_npm_dir(&sh::cat(&[&self.root, b"/apps/mcp/slack"]), &token)
            }
            _ => {
                let base = sh::cat(&[&self.root, b"/packages/pulumi/library/ts/packages"]);
                for d in glob_dirs(&base) {
                    if !sh::is_file(&sh::cat(&[&d, b"/package.json"])) {
                        continue;
                    }
                    if !self.package.is_empty() && self.package != sh::basename(&d) {
                        continue;
                    }
                    self.publish_npm_dir(&d, &token)?;
                }
                Ok(())
            }
        }
    }
}

/// `exec 1>&2` for one child: a duplicate of our stderr to hand it as stdout.
trait DupFd {
    fn as_fd_dup(&self) -> Option<Stdio>;
}

impl DupFd for std::io::Stderr {
    fn as_fd_dup(&self) -> Option<Stdio> {
        use std::os::fd::AsFd;
        self.as_fd().try_clone_to_owned().ok().map(Stdio::from)
    }
}

fn usage(code: i32) -> Exit {
    sh::err(USAGE.as_bytes());
    code
}

/// The whole tool; the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    // Sourced by the unit test, the script stops here (exposing only its
    // pure helpers); run, it exits 0. The port additionally answers
    // `go_module_tag NAME VERSION`, so the same suite can test the binary.
    if sh::env("PUBLISH_LOCAL_LIB_ONLY").as_deref() == Some(b"1") {
        if args.len() == 3 && args[0] == b"go_module_tag" {
            sh::out(&sh::cat(&[&go_module_tag(&args[1], &args[2]), b"\n"]));
        }
        return 0;
    }
    let root = match sh::env("BUILD_WORKSPACE_DIRECTORY") {
        Some(r) if !r.is_empty() => r,
        _ => {
            let prog = std::env::args_os()
                .next()
                .map(|p| {
                    use std::os::unix::ffi::OsStringExt;
                    p.into_vec()
                })
                .unwrap_or_default();
            sh::err(&sh::cat(&[
                &prog,
                format!(
                    // ${VAR:?word}: the word after quote removal.
                    ": line {}: BUILD_WORKSPACE_DIRECTORY: run via bazel run, not directly\n",
                    LINE_ROOT
                )
                .as_bytes(),
            ]));
            return 1;
        }
    };
    let scratch = match sh::mktemp_dir() {
        Ok(d) => d,
        Err(e) => {
            sh::err(format!("mktemp: {}\n", sh::strerror(&e)).as_bytes());
            return 1;
        }
    };
    let code = main(root, scratch.clone(), args);
    // trap 'rm -rf "$SCRATCH"' EXIT
    let _ = fs::remove_dir_all(sh::path(&scratch));
    code
}

fn main(root: Vec<u8>, scratch: Vec<u8>, args: &[Vec<u8>]) -> i32 {
    if args.is_empty() {
        return usage(1);
    }
    let component = args[0].clone();
    let mut package = Vec::new();
    let mut execute = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_slice() {
            b"--package" => {
                // `shift 2` past the end fails, and errexit ends the script
                // with no message.
                if i + 1 >= args.len() {
                    return 1;
                }
                package = args[i + 1].clone();
                i += 2;
            }
            b"--execute" => {
                execute = true;
                i += 1;
            }
            b"-h" | b"--help" => return usage(0),
            other => return die(&sh::cat(&[b"unknown argument '", other, b"'"])),
        }
    }
    if !execute {
        note(&sh::cat(&[
            b"DRY RUN (pass --execute to publish). Run 'copybara sync export ",
            &component,
            b"' first.",
        ]));
    }
    let r = Run {
        root,
        scratch,
        package,
        execute,
    };
    let res = match component.as_slice() {
        b"pulumi-library" => r
            .publish_go_modules()
            .and_then(|_| r.publish_npm_component("pulumi-library")),
        b"mcp-slack" => r.publish_npm_component("mcp-slack"),
        _ => Err(die(&sh::cat(&[
            b"unknown component '",
            &component,
            b"' (expected: pulumi-library | mcp-slack)",
        ]))),
    };
    if let Err(code) = res {
        return code;
    }
    note(if execute {
        b"done (published)."
    } else {
        b"done (dry-run)."
    });
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Json {
        serde_json::from_str(s).unwrap()
    }

    #[test]
    fn go_module_tag_is_the_slash_form() {
        let t = go_module_tag(b"cloud_run", b"0.3.0");
        assert_eq!(t, b"go/pkg/cloud_run/v0.3.0");
        assert!(!t.ends_with(b"-v0.3.0"));
        assert!(t.ends_with(b"/v0.3.0"));
    }

    #[test]
    fn first_value_keeps_document_order() {
        let d = parse(r#"{"z/b": "2.0.0", "a": "1.0.0"}"#);
        assert_eq!(apply(Filter::FirstValue, &d).unwrap().raw(), "2.0.0");
    }

    #[test]
    fn repeated_key_keeps_position_takes_last_value() {
        let d = parse(r#"{"a": 1, "b": 2, "a": 3}"#);
        assert_eq!(apply(Filter::FirstValue, &d).unwrap().raw(), "3");
    }

    #[test]
    fn first_value_of_array_and_null() {
        assert_eq!(
            apply(Filter::FirstValue, &parse("[\"x\"]")).unwrap().raw(),
            "x"
        );
        assert_eq!(
            apply(Filter::FirstValue, &parse("[]")).unwrap().raw(),
            "null"
        );
        assert_eq!(
            apply(Filter::FirstValue, &parse("null")).unwrap_err(),
            ("null (null) has no keys".to_string(), 5)
        );
    }

    #[test]
    fn empty_object_and_missing_field_are_null() {
        assert_eq!(
            apply(Filter::FirstValue, &parse("{}")).unwrap().raw(),
            "null"
        );
        assert_eq!(
            apply(Filter::Field("name"), &parse("{}")).unwrap().raw(),
            "null"
        );
    }

    #[test]
    fn alternative_false() {
        let f = Filter::FieldOrFalse("private");
        assert_eq!(apply(f, &parse("{}")).unwrap().raw(), "false");
        assert_eq!(
            apply(f, &parse(r#"{"private":null}"#)).unwrap().raw(),
            "false"
        );
        assert_eq!(
            apply(f, &parse(r#"{"private":true}"#)).unwrap().raw(),
            "true"
        );
        assert_eq!(
            apply(f, &parse(r#"{"private":"yes"}"#)).unwrap().raw(),
            "yes"
        );
        assert_eq!(apply(f, &parse("[1]")).unwrap().raw(), "false");
    }

    #[test]
    fn indexing_an_array_is_jq_error_5() {
        let e = apply(Filter::Field("name"), &parse("[1]")).unwrap_err();
        assert_eq!(
            e,
            ("Cannot index array with string \"name\"".to_string(), 5)
        );
    }

    #[test]
    fn raw_prints_like_jq() {
        let d = parse(r#"{"b":[1,{"z":1,"y":"\u007f"}],"e":[],"o":{}}"#);
        assert_eq!(
            d.raw(),
            "{\n  \"b\": [\n    1,\n    {\n      \"z\": 1,\n      \"y\": \"\\u007f\"\n    }\n  ],\n  \"e\": [],\n  \"o\": {}\n}"
        );
        assert_eq!(parse(r#""a\nb""#).raw(), "a\nb");
        assert_eq!(parse("true").raw(), "true");
    }
}
