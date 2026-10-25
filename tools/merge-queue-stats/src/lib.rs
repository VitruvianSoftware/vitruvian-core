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

//! merge_queue_stats.py in Rust, standard library only: the same command
//! line, the same GitHub requests, the same report. The parity test
//! (merge_queue_stats_rs_parity_test.py) holds the two together.

pub mod argparse;
pub mod http;
pub mod json;
pub mod pyerr;
pub mod pystr;
pub mod pytime;
pub mod stats;

use std::io::Write;
use std::process::Command;

use argparse::{Kind, Opt, Parser};
use json::Value;
use pyerr::Crash;
use stats::Time;

pub const DEFAULT_API: &str = "https://api.github.com";

pub const QUERY: &str = "
query($q: String!, $after: String) {
  search(query: $q, type: ISSUE, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number
        mergedAt
        timelineItems(first: 100, itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT]) {
          nodes {
            __typename
            ... on AddedToMergeQueueEvent { createdAt }
            ... on RemovedFromMergeQueueEvent { createdAt reason actor { login } }
          }
        }
      }
    }
  }
}
";

/// What stops a fetch: an error the script catches and reports (URLError,
/// RuntimeError, KeyError), or one it does not.
#[derive(Debug)]
pub enum Fail {
    Caught(String),
    Crash(Crash),
}

impl From<Crash> for Fail {
    fn from(c: Crash) -> Fail {
        if c.class == "KeyError" {
            Fail::Caught(c.msg)
        } else {
            Fail::Crash(c)
        }
    }
}

/// `json.load` on a response: bytes in whichever UTF the start suggests.
fn decode_json(body: &[u8]) -> Result<Value, Crash> {
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
    let bad = |what: &str| {
        Crash::new(
            "UnicodeDecodeError",
            format!("'{}' codec can't decode bytes", what),
        )
    };
    let text = if body.starts_with(&[0, 0, 0xFE, 0xFF]) || body.starts_with(&[0xFF, 0xFE, 0, 0]) {
        let be = body[0] == 0;
        utf32(&units(&body[4..], 4, be)).ok_or_else(|| bad("utf-32"))?
    } else if body.starts_with(&[0xFE, 0xFF]) || body.starts_with(&[0xFF, 0xFE]) {
        let be = body[0] == 0xFE;
        String::from_utf16(
            &units(&body[2..], 2, be)
                .iter()
                .map(|u| *u as u16)
                .collect::<Vec<_>>(),
        )
        .map_err(|_| bad("utf-16"))?
    } else if let Some(rest) = body.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
        String::from_utf8(rest.to_vec()).map_err(|_| bad("utf-8"))?
    } else if body.len() >= 4 && body[0] == 0 {
        if body[1] != 0 {
            String::from_utf16(
                &units(body, 2, true)
                    .iter()
                    .map(|u| *u as u16)
                    .collect::<Vec<_>>(),
            )
            .map_err(|_| bad("utf-16-be"))?
        } else {
            utf32(&units(body, 4, true)).ok_or_else(|| bad("utf-32-be"))?
        }
    } else if body.len() >= 4 && body[1] == 0 {
        if body[2] != 0 || body[3] != 0 {
            String::from_utf16(
                &units(body, 2, false)
                    .iter()
                    .map(|u| *u as u16)
                    .collect::<Vec<_>>(),
            )
            .map_err(|_| bad("utf-16-le"))?
        } else {
            utf32(&units(body, 4, false)).ok_or_else(|| bad("utf-32-le"))?
        }
    } else if body.len() == 2 && (body[0] == 0 || body[1] == 0) {
        let be = body[0] == 0;
        String::from_utf16(
            &units(body, 2, be)
                .iter()
                .map(|u| *u as u16)
                .collect::<Vec<_>>(),
        )
        .map_err(|_| bad("utf-16"))?
    } else {
        String::from_utf8(body.to_vec()).map_err(|_| bad("utf-8"))?
    };
    json::loads(&text).map_err(|e| Crash::new("json.decoder.JSONDecodeError", e.to_string()))
}

fn utf32(units: &[u32]) -> Option<String> {
    units.iter().map(|u| char::from_u32(*u)).collect()
}

/// `call`: one API request, its JSON back.
fn call(
    api: &str,
    tok: &str,
    method: &str,
    path: &str,
    body: Option<&Value>,
) -> Result<Value, Fail> {
    let url = format!("{}{}", api, path);
    let data = body.map(|b| json::dumps(b).into_bytes());
    let headers = [
        ("Authorization", format!("Bearer {}", tok)),
        ("Accept", "application/vnd.github+json".to_string()),
        ("X-GitHub-Api-Version", "2022-11-28".to_string()),
    ];
    let req = http::Request {
        method,
        url: &url,
        headers: &headers,
        body: data.as_deref(),
        timeout: 60,
    };
    match http::send(&req) {
        Ok(bytes) => Ok(decode_json(&bytes)?),
        Err(http::Error::Url(m)) => Err(Fail::Caught(m)),
        Err(http::Error::Value(m)) => Err(Fail::Crash(Crash::new("ValueError", m))),
        Err(http::Error::Invalid(class, m)) => Err(Fail::Crash(Crash::new(class, m))),
    }
}

fn stamp(t: Time) -> String {
    pytime::format(t.micros, "%Y-%m-%dT%H:%M:%SZ")
}

/// `urllib.parse.quote` with its default safe "/".
fn quote(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || b"_.-~/".contains(&b) {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

fn obj(items: Vec<(&str, Value)>) -> Value {
    Value::Obj(items.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

pub fn fetch_pulls(
    api: &str,
    tok: &str,
    repo: &str,
    since: Time,
    until: Time,
) -> Result<Vec<Value>, Fail> {
    let query = format!(
        "repo:{} is:pr base:main updated:{}..{}",
        repo,
        stamp(since),
        stamp(until)
    );
    let mut pulls = Vec::new();
    let mut after = Value::Null;
    loop {
        let body = obj(vec![
            ("query", Value::Str(QUERY.into())),
            (
                "variables",
                obj(vec![
                    ("q", Value::Str(query.clone())),
                    ("after", after.clone()),
                ]),
            ),
        ]);
        let data = call(api, tok, "POST", "/graphql", Some(&body))?;
        let errors = pyerr::get_or(&data, "errors", Value::Null)?;
        if errors.truthy() {
            return Err(Fail::Caught(errors.py_str()));
        }
        let page = pyerr::index(&pyerr::index(&data, "data")?, "search")?;
        for n in pyerr::iterate(&pyerr::index(&page, "nodes")?)? {
            if n.truthy() {
                pulls.push(n);
            }
        }
        let info = pyerr::index(&page, "pageInfo")?;
        if !pyerr::index(&info, "hasNextPage")?.truthy() {
            return Ok(pulls);
        }
        after = pyerr::index(&info, "endCursor")?;
    }
}

pub fn fetch_runs(
    api: &str,
    tok: &str,
    repo: &str,
    since: Time,
    until: Time,
) -> Result<Vec<Value>, Fail> {
    let created = quote(&format!("{}..{}", stamp(since), stamp(until)));
    let mut runs = Vec::new();
    for status in ["failure", "timed_out"] {
        let mut page = 1;
        loop {
            let path = format!(
                "/repos/{}/actions/runs?branch=main&event=push&status={}&created={}&per_page=100&page={}",
                repo, status, created, page
            );
            let data = call(api, tok, "GET", &path, None)?;
            runs.extend(pyerr::iterate(&pyerr::index(&data, "workflow_runs")?)?);
            if pyerr::len(&pyerr::index(&data, "workflow_runs")?)? < 100 {
                break;
            }
            page += 1;
        }
    }
    Ok(runs)
}

pub fn fetch_reverts(
    api: &str,
    tok: &str,
    repo: &str,
    since: Time,
    until: Time,
) -> Result<Vec<String>, Fail> {
    let mut reverts = Vec::new();
    let mut page = 1;
    loop {
        let path = format!(
            "/repos/{}/commits?sha=main&since={}&until={}&per_page=100&page={}",
            repo,
            stamp(since),
            stamp(until),
            page
        );
        let data = call(api, tok, "GET", &path, None)?;
        for c in pyerr::iterate(&data)? {
            let message = pyerr::index(&pyerr::index(&c, "commit")?, "message")?;
            if pyerr::as_str(&message, "startswith")?.starts_with("Revert ") {
                reverts.push(pystr::first_line(pyerr::as_str(&message, "splitlines")?));
            }
        }
        if pyerr::len(&data)? < 100 {
            return Ok(reverts);
        }
        page += 1;
    }
}

/// `token()`: GH_TOKEN, GITHUB_TOKEN, else `gh auth token`, else "".
pub fn token() -> Result<String, Crash> {
    for name in ["GH_TOKEN", "GITHUB_TOKEN"] {
        if let Ok(v) = std::env::var(name) {
            if !v.is_empty() {
                return Ok(v);
            }
        }
    }
    match Command::new("gh").args(["auth", "token"]).output() {
        Ok(out) if out.status.success() => {
            let text = String::from_utf8(out.stdout).map_err(|_| {
                Crash::new("UnicodeDecodeError", "'utf-8' codec can't decode gh output")
            })?;
            Ok(pystr::strip(&text).to_string())
        }
        _ => Ok(String::new()),
    }
}

fn parser(prog: String) -> Parser {
    Parser {
        prog,
        description: Some("How is main's merge queue doing over a window of days?".into()),
        opts: vec![
            Opt::help(),
            Opt {
                strings: vec!["--since"],
                dest: "since",
                kind: Kind::Value,
                help: Some("UTC date or datetime, e.g. 2026-10-05".into()),
                required: true,
            },
            Opt {
                strings: vec!["--until"],
                dest: "until",
                kind: Kind::Value,
                help: Some("UTC date or datetime (default: now)".into()),
                required: false,
            },
            Opt {
                strings: vec!["--repo"],
                dest: "repo",
                kind: Kind::Value,
                help: None,
                required: false,
            },
        ],
    }
}

fn prog_name(argv0: &str) -> String {
    match argv0.rfind('/') {
        Some(i) => argv0[i + 1..].to_string(),
        None => argv0.to_string(),
    }
}

fn crash(c: &Crash) -> i32 {
    let _ = std::io::stdout().flush();
    eprint!("{}", c.traceback());
    1
}

/// `main()`: the exit code, having printed what the script prints.
pub fn run(argv: &[String]) -> i32 {
    let prog = prog_name(
        argv.first()
            .map(String::as_str)
            .unwrap_or("merge_queue_stats.py"),
    );
    let p = parser(prog);
    let convert = |dest: &str, value: &str| -> Result<(), &'static str> {
        if dest == "since" || dest == "until" {
            stats::day(value).map(|_| ()).map_err(|_| "day")
        } else {
            Ok(())
        }
    };
    let values = match p.parse(&argv[1.min(argv.len())..], &convert) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let since = stats::day(values.value("since").unwrap()).unwrap();
    let until = match values.value("until") {
        Some(u) => stats::day(u).unwrap(),
        None => Time::utc(pytime::now()),
    };
    let repo = values
        .value("repo")
        .unwrap_or("VitruvianSoftware/vitruvian-core")
        .to_string();
    let api = std::env::var("GITHUB_API_URL").unwrap_or_else(|_| DEFAULT_API.to_string());
    let tok = match token() {
        Ok(t) => t,
        Err(c) => return crash(&c),
    };
    if tok.is_empty() {
        eprintln!("merge-queue-stats: no token (GH_TOKEN, GITHUB_TOKEN or gh auth token)");
        return 2;
    }
    let fetched = fetch_pulls(&api, &tok, &repo, since, until).and_then(|pulls| {
        let runs = fetch_runs(&api, &tok, &repo, since, until)?;
        let reverts = fetch_reverts(&api, &tok, &repo, since, until)?;
        Ok((pulls, runs, reverts))
    });
    let (pulls, runs, reverts) = match fetched {
        Ok(t) => t,
        Err(Fail::Caught(m)) => {
            eprintln!("merge-queue-stats: could not read GitHub: {}", m);
            return 2;
        }
        Err(Fail::Crash(c)) => return crash(&c),
    };
    match stats::report(&repo, since, until, &pulls, &runs, &reverts) {
        Ok(text) => {
            print!("{}", text);
            0
        }
        Err(c) => crash(&c),
    }
}
