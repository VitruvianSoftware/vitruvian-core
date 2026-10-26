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

//! rotate_access_token.py in Rust, standard library only: the same command
//! line, the same Pulumi Cloud requests, the same `gh secret set` calls (the
//! token over stdin, never in argv or on screen), the same prompts and the
//! same output, byte for byte. Where the script dies with an uncaught
//! exception the port prints a traceback ending in the same exception class.
//! rotate_access_token_rs_parity_test.py holds the two together.

pub mod argparse;
pub mod http;
pub mod json;
pub mod pyerr;
pub mod pystr;

use std::io::{BufRead, Write};
use std::process::{Command, Stdio};

use argparse::{Kind, Opt, Parser};
use json::Value;
use pyerr::Crash;

pub const DEFAULT_API: &str = "https://api.pulumi.com";
pub const DEFAULT_REPO: &str = "VitruvianSoftware/vitruvian-core";
pub const SECRET: &str = "PULUMI_ACCESS_TOKEN";
pub const RECENT_USE_SECONDS: f64 = 300.0;
/// The first line of the script's docstring: argparse's description.
pub const DESCRIPTION: &str = "Rotate the Pulumi Cloud token CI uses, without anyone seeing it.";

/// What ends a run early: the script's `Fail` (printed as `  ✗ ...`, exit 1)
/// or an exception it does not catch.
#[derive(Debug, PartialEq)]
pub enum Stop {
    Fail(String),
    Crash(Crash),
}

impl From<Crash> for Stop {
    fn from(c: Crash) -> Stop {
        Stop::Crash(c)
    }
}

/// The module-level settings, read from the environment once, as the
/// script reads them at import.
#[derive(Clone, Debug)]
pub struct Config {
    pub api: String,
    pub repo: String,
    pub label: String,
}

impl Config {
    pub fn new(api: &str, repo: &str) -> Config {
        Config {
            api: api.to_string(),
            repo: repo.to_string(),
            label: format!("github-actions: {}", repo),
        }
    }

    pub fn from_env() -> Config {
        let api = std::env::var("PULUMI_API").unwrap_or_else(|_| DEFAULT_API.to_string());
        let repo = std::env::var("ROTATE_REPO").unwrap_or_else(|_| DEFAULT_REPO.to_string());
        Config::new(&api, &repo)
    }
}

/// One Pulumi Cloud call: (token, method, path, body) -> parsed JSON.
pub type Api<'a> = dyn FnMut(&str, &str, &str, Option<&Value>) -> Result<Value, Stop> + 'a;
/// `input(prompt)`.
pub type Ask<'a> = dyn FnMut(&str) -> Result<String, Crash> + 'a;
/// `store_secret(value, dependabot)`.
pub type Store<'a> = dyn FnMut(&Value, bool) -> Result<(), Stop> + 'a;

fn ok(msg: &str) {
    println!("  \u{2713} {}", msg);
}

fn warn(msg: &str) {
    println!("  ! {}", msg);
}

// --------------------------------------------------------------------------
// Python semantics the script leans on.
// --------------------------------------------------------------------------

/// `os.path.expanduser("~/" + rest)`.
fn expand_home(rest: &str) -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let home = home.trim_end_matches('/');
    format!("{}/{}", home, rest)
}

/// `json.loads(raw)` on response bytes: UTF-8/16/32 as the start suggests.
pub fn decode_json(body: &[u8]) -> Result<Value, Crash> {
    let units = |b: &[u8], n: usize, be: bool| -> Vec<u32> {
        b.chunks(n)
            .filter(|c| c.len() == n)
            .map(|c| {
                c.iter().enumerate().fold(0u32, |acc, (i, x)| {
                    let shift = if be { (n - 1 - i) * 8 } else { i * 8 };
                    acc | (*x as u32) << shift
                })
            })
            .collect()
    };
    let utf16 = |b: &[u8], be: bool, what: &str| -> Result<String, Crash> {
        String::from_utf16(
            &units(b, 2, be)
                .iter()
                .map(|u| *u as u16)
                .collect::<Vec<_>>(),
        )
        .map_err(|_| bad(what))
    };
    let utf32 = |b: &[u8], be: bool, what: &str| -> Result<String, Crash> {
        units(b, 4, be)
            .iter()
            .map(|u| char::from_u32(*u))
            .collect::<Option<String>>()
            .ok_or_else(|| bad(what))
    };
    let text = if body.starts_with(&[0, 0, 0xFE, 0xFF]) || body.starts_with(&[0xFF, 0xFE, 0, 0]) {
        utf32(&body[4..], body[0] == 0, "utf-32")?
    } else if body.starts_with(&[0xFE, 0xFF]) || body.starts_with(&[0xFF, 0xFE]) {
        utf16(&body[2..], body[0] == 0xFE, "utf-16")?
    } else if let Some(rest) = body.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
        String::from_utf8(rest.to_vec()).map_err(|_| bad("utf-8"))?
    } else if body.len() >= 4 && body[0] == 0 {
        if body[1] != 0 {
            utf16(body, true, "utf-16-be")?
        } else {
            utf32(body, true, "utf-32-be")?
        }
    } else if body.len() >= 4 && body[1] == 0 {
        if body[2] != 0 || body[3] != 0 {
            utf16(body, false, "utf-16-le")?
        } else {
            utf32(body, false, "utf-32-le")?
        }
    } else if body.len() == 2 && (body[0] == 0 || body[1] == 0) {
        utf16(body, body[0] == 0, "utf-16")?
    } else {
        String::from_utf8(body.to_vec()).map_err(|_| bad("utf-8"))?
    };
    json::loads(&text).map_err(|e| Crash::new("json.decoder.JSONDecodeError", e.to_string()))
}

fn bad(codec: &str) -> Crash {
    Crash::new(
        "UnicodeDecodeError",
        format!("'{}' codec can't decode bytes", codec),
    )
}

fn number(v: &Value) -> Option<f64> {
    match v {
        Value::Bool(_) | Value::Int(_) | Value::Float(_) => v.as_f64(),
        _ => None,
    }
}

/// `a == b` on two JSON values.
pub fn py_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Null, Value::Null) => true,
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Int(x), Value::Int(y)) => {
            Value::Int(x.clone()).py_repr() == Value::Int(y.clone()).py_repr()
        }
        (Value::Arr(x), Value::Arr(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| py_eq(p, q))
        }
        (Value::Obj(x), Value::Obj(y)) => {
            let (x, y) = (json::dedup(x), json::dedup(y));
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| y.iter().any(|(k2, v2)| k == k2 && py_eq(v, v2)))
        }
        _ => match (number(a), number(b)) {
            (Some(x), Some(y)) => x == y,
            _ => false,
        },
    }
}

/// `v[:10]` on a value, then `str()` of it, as an f-string shows it.
fn head10(v: &Value) -> Result<String, Crash> {
    match v {
        Value::Str(s) => Ok(s.chars().take(10).collect()),
        Value::Arr(items) => Ok(Value::Arr(items.iter().take(10).cloned().collect()).py_str()),
        Value::Obj(_) => Err(Crash::new("TypeError", "unhashable type: 'slice'")),
        other => Err(Crash::new(
            "TypeError",
            format!("'{}' object is not subscriptable", other.type_name()),
        )),
    }
}

/// `sorted(items, key=lambda t: t["created"])`, stable.
fn sort_by_created(items: Vec<Value>) -> Result<Vec<Value>, Crash> {
    let mut keyed = Vec::new();
    for t in items {
        let k = pyerr::index(&t, "created")?;
        keyed.push((k, t));
    }
    if keyed.len() >= 2 {
        let all_str = keyed.iter().all(|(k, _)| matches!(k, Value::Str(_)));
        let all_num = keyed.iter().all(|(k, _)| number(k).is_some());
        if !all_str && !all_num {
            // Python stops at the first pair it cannot order; the pair it
            // names may differ, the class does not.
            let (a, b) = keyed
                .windows(2)
                .map(|w| (&w[0].0, &w[1].0))
                .find(|(a, b)| {
                    !(matches!((a, b), (Value::Str(_), Value::Str(_)))
                        || (number(a).is_some() && number(b).is_some()))
                })
                .unwrap_or((&keyed[0].0, &keyed[1].0));
            return Err(Crash::new(
                "TypeError",
                format!(
                    "'<' not supported between instances of '{}' and '{}'",
                    b.type_name(),
                    a.type_name()
                ),
            ));
        }
        keyed.sort_by(|(a, _), (b, _)| match (a, b) {
            // str ordering is by code point, which is UTF-8 byte order.
            (Value::Str(x), Value::Str(y)) => x.cmp(y),
            _ => number(a)
                .unwrap()
                .partial_cmp(&number(b).unwrap())
                .unwrap_or(std::cmp::Ordering::Equal),
        });
    }
    Ok(keyed.into_iter().map(|(_, t)| t).collect())
}

/// `x in extra_ids`: a list of str, compared with ==.
fn named(id: &Value, extra: &[String]) -> bool {
    matches!(id, Value::Str(s) if extra.iter().any(|e| e == s))
}

/// Today's UTC date, `date.isoformat()`.
pub fn utc_today() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    civil_date((secs / 86_400) as i64)
}

/// Days since 1970-01-01 -> YYYY-MM-DD (Howard Hinnant's algorithm).
pub fn civil_date(days: i64) -> String {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
    format!("{:04}-{:02}-{:02}", y, m, d)
}

fn now() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

// --------------------------------------------------------------------------
// The script's functions.
// --------------------------------------------------------------------------

/// `operator_token()`: $PULUMI_ACCESS_TOKEN, else `pulumi login`'s file.
pub fn operator_token(cfg: &Config) -> Result<Value, Stop> {
    if let Ok(t) = std::env::var("PULUMI_ACCESS_TOKEN") {
        if !t.is_empty() {
            return Ok(Value::Str(t));
        }
    }
    let not_signed_in = || {
        Stop::Fail(format!(
            "not signed in to {} -- run `pulumi login` first",
            cfg.api
        ))
    };
    let path = expand_home(".pulumi/credentials.json");
    // OSError, a decode error and bad JSON (both ValueError) and a missing
    // key are caught; indexing something that is not a dict is not.
    let raw = std::fs::read(&path).map_err(|_| not_signed_in())?;
    let text = String::from_utf8(raw).map_err(|_| not_signed_in())?;
    let data = json::loads(&text).map_err(|_| not_signed_in())?;
    let caught = |c: Crash| {
        if c.class == "KeyError" {
            not_signed_in()
        } else {
            Stop::Crash(c)
        }
    };
    let tokens = pyerr::index(&data, "accessTokens").map_err(caught)?;
    pyerr::index(&tokens, &cfg.api).map_err(caught)
}

/// `api(token, method, path, body)` over the network.
pub fn api_call(
    cfg: &Config,
    token: &str,
    method: &str,
    path: &str,
    body: Option<&Value>,
) -> Result<Value, Stop> {
    let url = format!("{}{}", cfg.api, path);
    let data = body.map(|b| json::dumps(b).into_bytes());
    let headers = [
        ("Authorization", format!("token {}", token)),
        ("Accept", "application/vnd.pulumi+8".to_string()),
        ("Content-Type", "application/json".to_string()),
    ];
    let req = http::Request {
        method,
        url: &url,
        headers: &headers,
        body: data.as_deref(),
        timeout: 30,
    };
    match http::send(&req) {
        Ok(raw) if raw.is_empty() => Ok(Value::Obj(vec![])),
        Ok(raw) => Ok(decode_json(&raw)?),
        Err(http::Error::Http(code)) => Err(Stop::Fail(format!(
            "Pulumi Cloud said {} to {} {}",
            code, method, path
        ))),
        Err(http::Error::Url(reason)) => Err(Stop::Fail(format!(
            "could not reach {}: {}",
            cfg.api, reason
        ))),
        Err(http::Error::Invalid(class, m)) => Err(Stop::Crash(Crash::new(class, m))),
    }
}

fn whoami(api: &mut Api, token: &Value) -> Result<Value, Stop> {
    let me = api(&token.py_str(), "GET", "/api/user", None)?;
    Ok(pyerr::index(&me, "githubLogin")?)
}

/// `store_secret(value, dependabot)`: `gh secret set`, the value on stdin.
pub fn store_secret(cfg: &Config, value: &Value, dependabot: bool) -> Result<(), Stop> {
    let value = match value {
        Value::Str(s) => s,
        other => {
            return Err(Stop::Crash(Crash::new(
                "TypeError",
                format!("write() argument must be str, not {}", other.type_name()),
            )))
        }
    };
    let mut args = vec!["secret", "set", SECRET, "--repo", &cfg.repo];
    if dependabot {
        args.extend(["--app", "dependabot"]);
    }
    let mut child = Command::new("gh")
        .args(&args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| Stop::Crash(Crash::os(&e, Some("gh"))))?;
    {
        let mut stdin = child.stdin.take().unwrap();
        let _ = stdin.write_all(value.as_bytes());
    }
    let out = child
        .wait_with_output()
        .map_err(|e| Stop::Crash(Crash::os(&e, None)))?;
    if !out.status.success() {
        let err = String::from_utf8(out.stderr).map_err(|_| Stop::Crash(bad("utf-8")))?;
        // text=True reads with universal newlines.
        let err = err.replace("\r\n", "\n").replace('\r', "\n");
        return Err(Stop::Fail(format!(
            "gh could not store {}: {}",
            SECRET,
            pystr::strip(&err)
        )));
    }
    Ok(())
}

/// `rotate(token)`.
pub fn rotate(
    cfg: &Config,
    token: &Value,
    api: &mut Api,
    store: &mut Store,
    today: &str,
) -> Result<(), Stop> {
    let user = whoami(api, token)?;
    ok(&format!("signed in to Pulumi Cloud as {}", user.py_str()));
    let body = Value::Obj(vec![
        (
            "description".into(),
            Value::Str(format!("{} (rotated {})", cfg.label, today)),
        ),
        ("expires".into(), Value::Int("0".into())),
    ]);
    let created = api(&token.py_str(), "POST", "/api/user/tokens", Some(&body))?;
    let new = pyerr::index(&created, "tokenValue")?;
    let id = pyerr::index(&created, "id")?;
    ok(&format!("minted a new token (id {})", id.py_str()));
    if !py_eq(&whoami(api, &new)?, &user) {
        return Err(Stop::Fail(
            "the new token signs in as a different user -- not storing it".into(),
        ));
    }
    ok("the new token works");
    for dependabot in [false, true] {
        store(&new, dependabot)?;
    }
    ok(&format!(
        "stored {} on {} (Actions and Dependabot); never printed",
        SECRET, cfg.repo
    ));
    println!(
        "\nNext: once a CI run that uses Pulumi is green, delete the old token:\n  bazel run //tools/pulumi:rotate-access-token -- --cleanup"
    );
    Ok(())
}

/// `cleanup(token, extra_ids, assume_yes, ask)`.
pub fn cleanup(
    cfg: &Config,
    token: &Value,
    extra: &[String],
    assume_yes: bool,
    api: &mut Api,
    ask: &mut Ask,
    now: f64,
) -> Result<(), Stop> {
    let listed = api(&token.py_str(), "GET", "/api/user/tokens", None)?;
    let tokens = pyerr::iterate(&pyerr::index(&listed, "tokens")?)?;
    let mut labelled = Vec::new();
    for t in &tokens {
        let desc = pyerr::get_or(t, "description", Value::Str(String::new()))?;
        if pyerr::as_str(&desc, "startswith")?.starts_with(&cfg.label) {
            labelled.push(t.clone());
        }
    }
    let labelled = sort_by_created(labelled)?;
    // Keep the newest labelled token: that is the one CI now holds.
    let mut doomed: Vec<Value> = labelled[..labelled.len().saturating_sub(1)].to_vec();
    for t in &tokens {
        if named(&pyerr::index(t, "id")?, extra) {
            doomed.push(t.clone());
        }
    }
    let mut ids = Vec::new();
    for t in &tokens {
        let id = pyerr::index(t, "id")?;
        if matches!(id, Value::Arr(_) | Value::Obj(_)) {
            return Err(Stop::Crash(Crash::new(
                "TypeError",
                format!("unhashable type: '{}'", id.type_name()),
            )));
        }
        ids.push(id);
    }
    let mut unknown: Vec<&String> = extra
        .iter()
        .filter(|e| !ids.iter().any(|id| matches!(id, Value::Str(s) if s == *e)))
        .collect();
    unknown.sort();
    unknown.dedup();
    if !unknown.is_empty() {
        let names: Vec<&str> = unknown.iter().map(|s| s.as_str()).collect();
        return Err(Stop::Fail(format!("no such token: {}", names.join(", "))));
    }
    if let Some(newest) = labelled.last() {
        if named(&pyerr::index(newest, "id")?, extra) {
            return Err(Stop::Fail(
                "that id is the newest CI token -- CI is using it".into(),
            ));
        }
    }
    if doomed.is_empty() {
        ok("nothing to delete");
        if labelled.is_empty() {
            warn(
                "no token carries the CI label yet. If an older token was CI's, pass its id with --delete-old. Your tokens:",
            );
            for t in &tokens {
                let id = pyerr::index(t, "id")?.py_str();
                let created = head10(&pyerr::index(t, "created")?)?;
                let desc = pyerr::get_or(t, "description", Value::Str(String::new()))?.py_str();
                println!("      {}  {}  {}", id, created, desc);
            }
        }
        return Ok(());
    }
    for t in &doomed {
        let id = pyerr::index(t, "id")?.py_str();
        let d = pyerr::get_or(t, "description", Value::Str(String::new()))?.py_str();
        let created = head10(&pyerr::index(t, "created")?)?;
        let desc = format!("{} ({}, created {})", id, d, created);
        if pyerr::get_or(t, "lastUsed", Value::Int("0".into()))?.truthy() {
            let last = pyerr::index(t, "lastUsed")?;
            let last = number(&last).ok_or_else(|| {
                Crash::new(
                    "TypeError",
                    format!(
                        "unsupported operand type(s) for -: 'float' and '{}'",
                        last.type_name()
                    ),
                )
            })?;
            if now - last < RECENT_USE_SECONDS {
                warn(&format!("skipping {}: used in the last few minutes", desc));
                continue;
            }
        }
        if !assume_yes {
            let answer = ask(&format!("? Delete {}? [y/N] ", desc))?;
            let answer = pystr::strip(&answer).to_lowercase();
            if answer != "y" && answer != "yes" {
                warn(&format!("kept {}", desc));
                continue;
            }
        }
        api(
            &token.py_str(),
            "DELETE",
            &format!("/api/user/tokens/{}", id),
            None,
        )?;
        ok(&format!("deleted {}", desc));
    }
    Ok(())
}

/// `input(prompt)` with stdin not a terminal: the prompt on stdout, one line
/// back without its "\n", EOFError at the end of input. On Unix sys.stdin
/// splits lines at "\n" only and leaves a "\r" in place.
pub fn input(prompt: &str) -> Result<String, Crash> {
    print!("{}", prompt);
    let _ = std::io::stdout().flush();
    let stdin = std::io::stdin();
    let line = read_line(&mut stdin.lock()).map_err(|e| Crash::os(&e, None))?;
    match line {
        None => Err(Crash::new("EOFError", "EOF when reading a line")),
        Some(raw) => String::from_utf8(raw).map_err(|_| bad("utf-8")),
    }
}

/// One line without its "\n"; None at end of input.
pub fn read_line(r: &mut dyn BufRead) -> std::io::Result<Option<Vec<u8>>> {
    let mut line = Vec::new();
    if r.read_until(b'\n', &mut line)? == 0 {
        return Ok(None);
    }
    if line.last() == Some(&b'\n') {
        line.pop();
    }
    Ok(Some(line))
}

// --------------------------------------------------------------------------
// Command line.
// --------------------------------------------------------------------------

pub fn parser(prog: String) -> Parser {
    let opt = |strings, dest, kind, help: &str, metavar| Opt {
        strings,
        dest,
        kind,
        help: Some(help.to_string()),
        required: false,
        metavar,
    };
    Parser {
        prog,
        description: Some(DESCRIPTION.into()),
        opts: vec![
            Opt::help(),
            opt(
                vec!["--cleanup"],
                "cleanup",
                Kind::Flag,
                "delete old CI tokens instead of rotating",
                None,
            ),
            opt(
                vec!["--delete-old"],
                "delete_old",
                Kind::Value,
                "also delete this token id (with --cleanup)",
                Some("ID"),
            ),
            opt(
                vec!["--yes"],
                "yes",
                Kind::Flag,
                "don't ask before deleting",
                None,
            ),
        ],
    }
}

fn prog_name(argv0: &str) -> String {
    match argv0.rfind('/') {
        Some(i) => argv0[i + 1..].to_string(),
        None => argv0.to_string(),
    }
}

/// `main(argv)`: the exit code, having printed what the script prints.
pub fn run(argv: &[String]) -> i32 {
    let prog = prog_name(
        argv.first()
            .map(String::as_str)
            .unwrap_or("rotate_access_token.py"),
    );
    let p = parser(prog);
    let values = match p.parse(&argv[1.min(argv.len())..], &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let extra = values.all("delete_old");
    let cleanup_mode = values.flag("cleanup");
    if !extra.is_empty() && !cleanup_mode {
        let exit = p.error("--delete-old only goes with --cleanup");
        eprint!("{}", exit.stderr);
        return exit.code;
    }
    let cfg = Config::from_env();
    let mut api = |tok: &str, method: &str, path: &str, body: Option<&Value>| {
        api_call(&cfg, tok, method, path, body)
    };
    let result = operator_token(&cfg).and_then(|token| {
        if cleanup_mode {
            cleanup(
                &cfg,
                &token,
                &extra,
                values.flag("yes"),
                &mut api,
                &mut |prompt: &str| input(prompt),
                now(),
            )
        } else {
            rotate(
                &cfg,
                &token,
                &mut api,
                &mut |v: &Value, dependabot| store_secret(&cfg, v, dependabot),
                &utc_today(),
            )
        }
    });
    match result {
        Ok(()) => 0,
        Err(Stop::Fail(msg)) => {
            let _ = std::io::stdout().flush();
            eprintln!("  \u{2717} {}", msg);
            1
        }
        Err(Stop::Crash(c)) => {
            let _ = std::io::stdout().flush();
            eprint!("{}", c.traceback());
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NEW: &str = "pul-new-token-value-0123456789";
    const OLD: &str = "pul-operator-token";

    fn s(x: &str) -> Value {
        Value::Str(x.into())
    }

    fn obj(items: Vec<(&str, Value)>) -> Value {
        Value::Obj(items.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
    }

    fn token(id: &str, desc: &str, created: &str, last_used: f64) -> Value {
        obj(vec![
            ("id", s(id)),
            ("description", s(desc)),
            ("created", s(created)),
            ("lastUsed", Value::Float(last_used)),
        ])
    }

    /// The fake Pulumi Cloud of rotate_access_token_test.py.
    struct Cloud {
        tokens: Vec<Value>,
        new_user: String,
        deleted: Vec<String>,
        created: Vec<Value>,
    }

    impl Cloud {
        fn new(tokens: Vec<Value>) -> Cloud {
            Cloud {
                tokens,
                new_user: "ipv1337".into(),
                deleted: vec![],
                created: vec![],
            }
        }

        fn call(
            &mut self,
            tok: &str,
            method: &str,
            path: &str,
            body: Option<&Value>,
        ) -> Result<Value, Stop> {
            match (method, path) {
                ("GET", "/api/user") => Ok(obj(vec![(
                    "githubLogin",
                    s(if tok == NEW {
                        &self.new_user
                    } else {
                        "ipv1337"
                    }),
                )])),
                ("POST", "/api/user/tokens") => {
                    self.created.push(body.unwrap().clone());
                    Ok(obj(vec![("id", s("new-id")), ("tokenValue", s(NEW))]))
                }
                ("GET", "/api/user/tokens") => {
                    Ok(obj(vec![("tokens", Value::Arr(self.tokens.clone()))]))
                }
                ("DELETE", p) => {
                    self.deleted.push(p.rsplit('/').next().unwrap().to_string());
                    Ok(obj(vec![]))
                }
                _ => panic!("unexpected call {} {}", method, path),
            }
        }
    }

    fn cfg() -> Config {
        Config::new("https://api.pulumi.com", DEFAULT_REPO)
    }

    fn rotate_with(cloud: &mut Cloud, gh_fails: bool) -> (Result<(), Stop>, Vec<(String, bool)>) {
        let mut stored = Vec::new();
        let r = rotate(
            &cfg(),
            &s(OLD),
            &mut |t, m, p, b| cloud.call(t, m, p, b),
            &mut |v: &Value, d| {
                stored.push((v.py_str(), d));
                if gh_fails {
                    Err(Stop::Fail(
                        "gh could not store PULUMI_ACCESS_TOKEN: nope".into(),
                    ))
                } else {
                    Ok(())
                }
            },
            "2026-10-24",
        );
        (r, stored)
    }

    fn cleanup_with(
        tokens: Vec<Value>,
        extra: &[&str],
        yes: bool,
        answer: &str,
    ) -> (Result<(), Stop>, Vec<String>) {
        let mut cloud = Cloud::new(tokens);
        let extra: Vec<String> = extra.iter().map(|x| x.to_string()).collect();
        let r = cleanup(
            &cfg(),
            &s(OLD),
            &extra,
            yes,
            &mut |t, m, p, b| cloud.call(t, m, p, b),
            &mut |_| Ok(answer.to_string()),
            1_000_000.0,
        );
        (r, cloud.deleted)
    }

    fn label(day: &str) -> String {
        format!("github-actions: {} (rotated {})", DEFAULT_REPO, day)
    }

    #[test]
    fn stores_new_token_in_both_stores_after_it_proves_it_works() {
        let mut cloud = Cloud::new(vec![]);
        let (r, stored) = rotate_with(&mut cloud, false);
        assert_eq!(r, Ok(()));
        assert_eq!(
            stored,
            vec![(NEW.to_string(), false), (NEW.to_string(), true)]
        );
        assert_eq!(
            json::dumps(&cloud.created[0]),
            format!(
                "{{\"description\": \"{}\", \"expires\": 0}}",
                label("2026-10-24")
            )
        );
    }

    #[test]
    fn does_not_store_a_token_that_signs_in_as_someone_else() {
        let mut cloud = Cloud::new(vec![]);
        cloud.new_user = "someone-else".into();
        let (r, stored) = rotate_with(&mut cloud, false);
        assert!(matches!(r, Err(Stop::Fail(m)) if m.contains("different user")));
        assert!(stored.is_empty());
    }

    #[test]
    fn gh_failure_stops_after_the_first_store() {
        let mut cloud = Cloud::new(vec![]);
        let (r, stored) = rotate_with(&mut cloud, true);
        assert!(matches!(r, Err(Stop::Fail(_))));
        assert_eq!(stored.len(), 1);
    }

    #[test]
    fn deletes_older_ci_tokens_and_keeps_the_newest() {
        let tokens = vec![
            token("b", &label("2026-06-01"), "2026-06-01", 0.0),
            token("a", &label("2026-01-01"), "2026-01-01", 0.0),
            token("c", "devcontainer", "2025-10-08", 0.0),
        ];
        assert_eq!(cleanup_with(tokens, &[], true, "").1, vec!["a"]);
    }

    #[test]
    fn never_deletes_unlabelled_tokens_unless_named() {
        let tokens = vec![token("c", "devcontainer", "2025-10-08", 0.0)];
        assert!(cleanup_with(tokens.clone(), &[], true, "").1.is_empty());
        assert_eq!(cleanup_with(tokens, &["c"], true, "").1, vec!["c"]);
    }

    #[test]
    fn refuses_the_current_ci_token_and_unknown_ids() {
        let tokens = vec![token("b", &label("2026-06-01"), "2026-06-01", 0.0)];
        let (r, deleted) = cleanup_with(tokens, &["b"], true, "");
        assert!(matches!(r, Err(Stop::Fail(m)) if m.contains("newest CI token")));
        assert!(deleted.is_empty());
        let (r, _) = cleanup_with(vec![], &["z", "nope", "z"], true, "");
        assert_eq!(r, Err(Stop::Fail("no such token: nope, z".into())));
    }

    #[test]
    fn skips_a_token_used_in_the_last_few_minutes() {
        let tokens = vec![token(
            "me",
            "Generated by pulumi login",
            "2025-10-08",
            1_000_000.0 - 10.0,
        )];
        assert!(cleanup_with(tokens, &["me"], true, "").1.is_empty());
        let tokens = vec![token("old", "x", "2025-10-08", 1_000_000.0 - 301.0)];
        assert_eq!(cleanup_with(tokens, &["old"], true, "").1, vec!["old"]);
    }

    #[test]
    fn asks_before_deleting() {
        let tokens = vec![
            token("a", &label("2026-01-01"), "2026-01-01", 0.0),
            token("b", &label("2026-06-01"), "2026-06-01", 0.0),
        ];
        assert!(cleanup_with(tokens.clone(), &[], false, "n").1.is_empty());
        assert!(cleanup_with(tokens.clone(), &[], false, "").1.is_empty());
        assert_eq!(
            cleanup_with(tokens.clone(), &[], false, " YES \r").1,
            vec!["a"]
        );
        assert_eq!(cleanup_with(tokens, &[], false, "y").1, vec!["a"]);
    }

    #[test]
    fn crashes_where_python_would() {
        let no_id = obj(vec![("created", s("2026"))]);
        let (r, _) = cleanup_with(vec![no_id], &[], true, "");
        assert!(matches!(r, Err(Stop::Crash(c)) if c.class == "KeyError"));
        let null_desc = obj(vec![("id", s("x")), ("description", Value::Null)]);
        let (r, _) = cleanup_with(vec![null_desc], &[], true, "");
        assert!(matches!(r, Err(Stop::Crash(c)) if c.class == "AttributeError"));
        let mixed = vec![
            obj(vec![
                ("id", s("a")),
                ("description", s(&label("x"))),
                ("created", Value::Int("1".into())),
            ]),
            obj(vec![
                ("id", s("b")),
                ("description", s(&label("y"))),
                ("created", s("2026")),
            ]),
        ];
        let (r, _) = cleanup_with(mixed, &[], true, "");
        assert!(matches!(r, Err(Stop::Crash(c)) if c.class == "TypeError"));
    }

    #[test]
    fn delete_old_needs_cleanup_and_help_matches_argparse() {
        let p = parser("rotate_access_token.py".into());
        let args: Vec<String> = vec!["--delete-old".into(), "x".into(), "--delete-old=y".into()];
        let v = p.parse(&args, &|_, _| Ok(())).unwrap();
        assert_eq!(v.all("delete_old"), vec!["x", "y"]);
        let code = run(&[
            "rotate_access_token.py".into(),
            "--delete-old".into(),
            "x".into(),
        ]);
        assert_eq!(code, 2);
        let usage = p.format_usage();
        assert_eq!(
            usage,
            "usage: rotate_access_token.py [-h] [--cleanup] [--delete-old ID] [--yes]\n"
        );
    }

    #[test]
    fn input_lines_end_at_newline_only() {
        let mut r = std::io::Cursor::new(b"y\rn\r\nyes\nlast".to_vec());
        let mut lines = Vec::new();
        while let Some(l) = read_line(&mut r).unwrap() {
            lines.push(String::from_utf8(l).unwrap());
        }
        assert_eq!(lines, vec!["y\rn\r", "yes", "last"]);
        assert_eq!(
            read_line(&mut std::io::Cursor::new(Vec::new())).unwrap(),
            None
        );
    }

    #[test]
    fn values_compare_and_slice_as_python_does() {
        assert!(py_eq(&Value::Int("1".into()), &Value::Float(1.0)));
        assert!(py_eq(&Value::Bool(true), &Value::Int("1".into())));
        assert!(!py_eq(&s("1"), &Value::Int("1".into())));
        assert_eq!(head10(&s("2026-10-24T01:02:03Z")).unwrap(), "2026-10-24");
        assert_eq!(head10(&s("é😀")).unwrap(), "é😀");
        assert!(head10(&Value::Int("5".into())).is_err());
        assert_eq!(civil_date(0), "1970-01-01");
        assert_eq!(civil_date(20_385), "2025-10-24");
        assert_eq!(civil_date(-1), "1969-12-31");
        assert_eq!(civil_date(11_016), "2000-02-29");
    }
}
