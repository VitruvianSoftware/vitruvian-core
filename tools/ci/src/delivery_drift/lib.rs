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

//! delivery-drift — report delivery units whose last successful delivery is
//! BEHIND main, i.e. work that should have shipped and did not (#1842).
//! `bazel run //tools/ci:delivery_drift`.
//!
//! Affectedness is not reimplemented here: each unit is judged by the SAME
//! decision engine the delivery orchestrator runs (//tools/ci:deploy_affected,
//! found in this binary's runfiles; DEPLOY_AFFECTED_BIN overrides it), with
//! the same per-unit metadata. The base is the unit's last-delivered commit,
//! read from its app's delivery-<app>.yaml run history, and it is judged at the
//! head of that workflow's newest FINISHED push run (see find_judged_commit).
//!
//! Verdict: OK (exit 0), NOTHING_CHECKED (exit 0; every unit skipped -- not a
//! pass), DRIFT (exit 1; a unit is behind or UNKNOWN). Exit 2 is a setup error
//! and writes no verdict. Env: REPO, WORKFLOW_FILE, LEGACY_WORKFLOW_FILE
//! (default delivery.yaml; empty disables), BRANCH (main), RUN_SCAN_LIMIT
//! (5000), DRIFT_PAGE_SIZE (100), DRIFT_RECENT_RUNS (50), DRIFT_RESULT_FILE
//! (appends conclusion=/title=/checked=/skipped=), DRIFT_SUMMARY_FILE
//! (Markdown summary), DRIFT_IGNORE_IN_FLIGHT, BAZEL, GH.

use shell_compat::{capture, cat, env, env_or, env_or_empty, err, mktemp_dir, out, status, subst};
use std::collections::HashMap;
use std::process::Command;

mod json {
    //! A small strict JSON reader: enough for the GraphQL run pages and the
    //! `.delivery.json` metadata, so the checker needs no python3 at runtime.
    //! Anything malformed is an error, which callers treat as a failed read.

    #[derive(Debug, Clone, PartialEq)]
    pub enum Value {
        Null,
        Bool(bool),
        /// The number's literal text (printed as-is, as Python prints an int).
        Num(String),
        Str(String),
        Arr(Vec<Value>),
        Obj(Vec<(String, Value)>),
    }

    impl Value {
        /// `d.get(key)` on an object; None for a missing key or a non-object.
        pub fn get(&self, key: &str) -> Option<&Value> {
            match self {
                Value::Obj(kv) => kv.iter().rev().find(|(k, _)| k == key).map(|(_, v)| v),
                _ => None,
            }
        }

        /// Python truthiness.
        pub fn truthy(&self) -> bool {
            match self {
                Value::Null => false,
                Value::Bool(b) => *b,
                Value::Num(n) => n
                    .trim_start_matches('-')
                    .chars()
                    .any(|c| ('1'..='9').contains(&c)),
                Value::Str(s) => !s.is_empty(),
                Value::Arr(a) => !a.is_empty(),
                Value::Obj(o) => !o.is_empty(),
            }
        }

        /// What Python's `"%s" % v` prints for a scalar.
        pub fn py_str(&self) -> String {
            match self {
                Value::Null => "None".into(),
                Value::Bool(true) => "True".into(),
                Value::Bool(false) => "False".into(),
                Value::Num(n) => n.clone(),
                Value::Str(s) => s.clone(),
                other => format!("{other:?}"),
            }
        }
    }

    pub fn parse(text: &[u8]) -> Result<Value, String> {
        let s = std::str::from_utf8(text).map_err(|e| e.to_string())?;
        let mut p = Parser {
            b: s.as_bytes(),
            i: 0,
        };
        p.ws();
        let v = p.value(0)?;
        p.ws();
        if p.i != p.b.len() {
            return Err(format!("trailing data at byte {}", p.i));
        }
        Ok(v)
    }

    struct Parser<'a> {
        b: &'a [u8],
        i: usize,
    }

    impl Parser<'_> {
        fn ws(&mut self) {
            while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\t' | b'\n' | b'\r') {
                self.i += 1;
            }
        }

        fn eat(&mut self, lit: &str) -> Result<(), String> {
            if self.b[self.i..].starts_with(lit.as_bytes()) {
                self.i += lit.len();
                Ok(())
            } else {
                Err(format!("expected {lit} at byte {}", self.i))
            }
        }

        fn value(&mut self, depth: usize) -> Result<Value, String> {
            if depth > 256 {
                return Err("nested too deeply".into());
            }
            match self.b.get(self.i) {
                None => Err("unexpected end".into()),
                Some(b'n') => self.eat("null").map(|_| Value::Null),
                Some(b't') => self.eat("true").map(|_| Value::Bool(true)),
                Some(b'f') => self.eat("false").map(|_| Value::Bool(false)),
                Some(b'"') => self.string().map(Value::Str),
                Some(b'[') => {
                    self.i += 1;
                    let mut out = Vec::new();
                    self.ws();
                    if self.b.get(self.i) == Some(&b']') {
                        self.i += 1;
                        return Ok(Value::Arr(out));
                    }
                    loop {
                        self.ws();
                        out.push(self.value(depth + 1)?);
                        self.ws();
                        match self.b.get(self.i) {
                            Some(b',') => self.i += 1,
                            Some(b']') => {
                                self.i += 1;
                                return Ok(Value::Arr(out));
                            }
                            _ => return Err(format!("bad array at byte {}", self.i)),
                        }
                    }
                }
                Some(b'{') => {
                    self.i += 1;
                    let mut out = Vec::new();
                    self.ws();
                    if self.b.get(self.i) == Some(&b'}') {
                        self.i += 1;
                        return Ok(Value::Obj(out));
                    }
                    loop {
                        self.ws();
                        if self.b.get(self.i) != Some(&b'"') {
                            return Err(format!("expected a key at byte {}", self.i));
                        }
                        let k = self.string()?;
                        self.ws();
                        self.eat(":")?;
                        self.ws();
                        let v = self.value(depth + 1)?;
                        out.push((k, v));
                        self.ws();
                        match self.b.get(self.i) {
                            Some(b',') => self.i += 1,
                            Some(b'}') => {
                                self.i += 1;
                                return Ok(Value::Obj(out));
                            }
                            _ => return Err(format!("bad object at byte {}", self.i)),
                        }
                    }
                }
                Some(c) if *c == b'-' || c.is_ascii_digit() => self.number(),
                Some(_) => Err(format!("unexpected byte at {}", self.i)),
            }
        }

        fn number(&mut self) -> Result<Value, String> {
            let start = self.i;
            if self.b.get(self.i) == Some(&b'-') {
                self.i += 1;
            }
            let digits = |p: &mut Self| {
                let s = p.i;
                while p.i < p.b.len() && p.b[p.i].is_ascii_digit() {
                    p.i += 1;
                }
                p.i > s
            };
            if !digits(self) {
                return Err(format!("bad number at byte {start}"));
            }
            if self.b.get(self.i) == Some(&b'.') {
                self.i += 1;
                if !digits(self) {
                    return Err(format!("bad number at byte {start}"));
                }
            }
            if matches!(self.b.get(self.i), Some(b'e' | b'E')) {
                self.i += 1;
                if matches!(self.b.get(self.i), Some(b'+' | b'-')) {
                    self.i += 1;
                }
                if !digits(self) {
                    return Err(format!("bad number at byte {start}"));
                }
            }
            Ok(Value::Num(
                String::from_utf8_lossy(&self.b[start..self.i]).into_owned(),
            ))
        }

        fn hex4(&mut self) -> Result<u32, String> {
            let h = self
                .b
                .get(self.i..self.i + 4)
                .and_then(|h| std::str::from_utf8(h).ok())
                .and_then(|h| u32::from_str_radix(h, 16).ok())
                .ok_or_else(|| format!("bad \\u escape at byte {}", self.i))?;
            self.i += 4;
            Ok(h)
        }

        fn string(&mut self) -> Result<String, String> {
            self.i += 1; // opening quote
            let mut out = String::new();
            loop {
                let start = self.i;
                while self.i < self.b.len() && self.b[self.i] != b'"' && self.b[self.i] != b'\\' {
                    if self.b[self.i] < 0x20 {
                        return Err(format!("control character in string at byte {}", self.i));
                    }
                    self.i += 1;
                }
                out.push_str(
                    std::str::from_utf8(&self.b[start..self.i]).map_err(|e| e.to_string())?,
                );
                match self.b.get(self.i) {
                    None => return Err("unterminated string".into()),
                    Some(b'"') => {
                        self.i += 1;
                        return Ok(out);
                    }
                    _ => {
                        self.i += 1;
                        let c = *self.b.get(self.i).ok_or("unterminated escape")?;
                        self.i += 1;
                        match c {
                            b'"' => out.push('"'),
                            b'\\' => out.push('\\'),
                            b'/' => out.push('/'),
                            b'b' => out.push('\u{8}'),
                            b'f' => out.push('\u{c}'),
                            b'n' => out.push('\n'),
                            b'r' => out.push('\r'),
                            b't' => out.push('\t'),
                            b'u' => {
                                let hi = self.hex4()?;
                                let cp = if (0xD800..0xDC00).contains(&hi)
                                    && self.b[self.i..].starts_with(b"\\u")
                                {
                                    self.i += 2;
                                    let lo = self.hex4()?;
                                    if !(0xDC00..0xE000).contains(&lo) {
                                        return Err("bad surrogate pair".into());
                                    }
                                    0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                                } else {
                                    hi
                                };
                                // A lone surrogate: Python keeps it; we cannot in a
                                // String, so it becomes U+FFFD.
                                out.push(char::from_u32(cp).unwrap_or('\u{FFFD}'));
                            }
                            _ => return Err(format!("bad escape at byte {}", self.i - 1)),
                        }
                    }
                }
            }
        }
    }
}

fn log(msg: &[u8]) {
    err(&cat(&[b"delivery-drift: ", msg, b"\n"]));
}

const DELIVERY_QUERY: &[u8] =
    b"attr(tags, \"\\bdelivery\\b\", (//... except //apps/desktop/nexus-agent/macos/...))";

const RUNS_QUERY: &str = r#"query($id: ID!, $n: Int!, $after: String) {
  node(id: $id) { ... on Workflow { runs(first: $n, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { databaseId checkSuite { branch { name } commit { oid }
      checkRuns(first: 100, filterBy: {conclusions: [SUCCESS]}) { nodes { name } } } } } } } }"#;

struct PageCache {
    dir: Vec<u8>,
    wf_ids: HashMap<Vec<u8>, Vec<u8>>,
}

impl PageCache {
    fn new(dir: Vec<u8>) -> Self {
        Self {
            dir,
            wf_ids: HashMap::new(),
        }
    }

    fn page_path(&self, wf: &[u8], page: usize) -> std::path::PathBuf {
        let name = cat(&[wf, b".", page.to_string().as_bytes()]);
        let full = cat(&[&self.dir, b"/", &name]);
        shell_compat::path(&full).to_path_buf()
    }

    fn wf_id(&mut self, wf: &[u8], gh: &[u8], repo: &[u8]) -> Option<Vec<u8>> {
        if let Some(id) = self.wf_ids.get(wf) {
            return Some(id.clone());
        }
        let r = capture(
            178,
            Command::new(shell_compat::os(gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    repo,
                    b"/actions/workflows/",
                    wf,
                ])))
                .arg("--jq")
                .arg(".node_id"),
        );
        if !r.ok() {
            return None;
        }
        let id = subst(r.stdout);
        if id.is_empty() {
            return None;
        }
        self.wf_ids.insert(wf.to_vec(), id.clone());
        Some(id)
    }

    fn fetch_page(
        &mut self,
        wf: &[u8],
        page: usize,
        gh: &[u8],
        repo: &[u8],
        page_size: &[u8],
    ) -> bool {
        let p = self.page_path(wf, page);
        if p.exists() && std::fs::metadata(&p).map(|m| m.len() > 0).unwrap_or(false) {
            return true;
        }
        let node_id = match self.wf_id(wf, gh, repo) {
            Some(id) => id,
            None => return false,
        };
        let mut after = Vec::new();
        if page > 1 {
            let prev = self.page_path(wf, page - 1);
            if let Ok(content) = std::fs::read(&prev) {
                for line in content.split(|&c| c == b'\n') {
                    if line.starts_with(b"next\t") {
                        after = line[5..].to_vec();
                        break;
                    }
                }
            }
        }
        let mut args: Vec<Vec<u8>> = vec![
            b"api".to_vec(),
            b"graphql".to_vec(),
            b"-f".to_vec(),
            cat(&[b"query=", RUNS_QUERY.as_bytes()]),
            b"-f".to_vec(),
            cat(&[b"id=", &node_id]),
            b"-F".to_vec(),
            cat(&[b"n=", page_size]),
        ];
        if !after.is_empty() {
            args.push(b"-f".to_vec());
            args.push(cat(&[b"after=", &after]));
        }
        let mut cmd = Command::new(shell_compat::os(gh));
        for a in &args {
            cmd.arg(shell_compat::os(a));
        }
        let r = capture(186, &mut cmd);
        if !r.ok() {
            return false;
        }
        let raw = subst(r.stdout);
        let parsed = match page_lines(&raw) {
            Some(p) => p,
            None => return false,
        };
        let part = cat(&[p.to_string_lossy().as_bytes(), b".part"]);
        if shell_compat::write_file(&part, &parsed, 0o644).is_err() {
            return false;
        }
        std::fs::rename(shell_compat::path(&part), &p).is_ok()
    }
}

/// One GraphQL page of runs as
///   run<TAB><id><TAB><head sha><TAB><branch><TAB><job>\x1f<job>...
///   next<TAB><cursor of the next page, empty on the last page>
/// None on an API error, a malformed answer or a missing field.
fn page_lines(raw: &[u8]) -> Option<Vec<u8>> {
    use json::Value;
    let d = json::parse(raw).ok()?;
    if d.get("errors").map_or(false, Value::truthy) {
        return None;
    }
    let runs = d.get("data")?.get("node")?.get("runs")?;
    let Value::Arr(nodes) = runs.get("nodes")? else {
        return None;
    };
    // `x or {}`: a falsy value reads as absent.
    let or_none = |v: Option<&Value>| v.filter(|v| v.truthy()).cloned();
    let mut out = Vec::new();
    for r in nodes {
        if !matches!(r, Value::Obj(_)) {
            return None;
        }
        let cs = or_none(r.get("checkSuite"));
        if let Some(c) = &cs {
            if !matches!(c, Value::Obj(_)) {
                return None;
            }
        }
        let field = |outer: &str, inner: &str| -> String {
            cs.as_ref()
                .and_then(|c| or_none(c.get(outer)))
                .and_then(|o| or_none(o.get(inner)))
                .map(|v| v.py_str())
                .unwrap_or_default()
        };
        let mut jobs: Vec<String> = Vec::new();
        if let Some(cr) = cs.as_ref().and_then(|c| or_none(c.get("checkRuns"))) {
            match or_none(cr.get("nodes")) {
                None => {}
                Some(Value::Arr(items)) => {
                    for c in &items {
                        match c.get("name") {
                            Some(Value::Str(n)) => jobs.push(n.clone()),
                            _ => return None,
                        }
                    }
                }
                Some(_) => return None,
            }
        }
        let id = r.get("databaseId")?.py_str();
        out.extend_from_slice(
            format!(
                "run\t{}\t{}\t{}\t{}\n",
                id,
                field("commit", "oid"),
                field("branch", "name"),
                jobs.join("\x1f")
            )
            .as_bytes(),
        );
    }
    let info = runs.get("pageInfo")?;
    let next = if info.get("hasNextPage")?.truthy() {
        info.get("endCursor")?.py_str()
    } else {
        String::new()
    };
    out.extend_from_slice(format!("next\t{next}\n").as_bytes());
    Some(out)
}

/// A unit's `.delivery.json`, as the checker reads it.
struct Meta {
    name: String,
    first_env: String,
    app: String,
    extra: String,
    exclude: String,
    targets: String,
}

fn read_meta(path: &[u8]) -> Option<Meta> {
    use json::Value;
    let d = json::parse(&std::fs::read(shell_compat::path(path)).ok()?).ok()?;
    if !matches!(d, Value::Obj(_)) {
        return None;
    }
    let s = |v: Option<&Value>| {
        v.filter(|v| v.truthy())
            .map(|v| v.py_str())
            .unwrap_or_default()
    };
    let list = |key: &str, sep: &str| -> Option<String> {
        match d.get(key).filter(|v| v.truthy()) {
            None => Some(String::new()),
            Some(Value::Arr(items)) => {
                let mut parts = Vec::new();
                for i in items {
                    match i {
                        Value::Str(x) => parts.push(x.clone()),
                        _ => return None,
                    }
                }
                Some(parts.join(sep))
            }
            Some(_) => None,
        }
    };
    let first_env = match d.get("environments").filter(|v| v.truthy()) {
        None => String::new(),
        Some(Value::Arr(e)) => e[0].py_str(),
        Some(_) => return None,
    };
    Some(Meta {
        name: d.get("name")?.py_str(),
        first_env,
        app: s(d.get("app")),
        extra: list("extra_paths", "|")?,
        exclude: list("exclude_paths", "|")?,
        targets: list("graph_targets", " ")?,
    })
}

/// Where the decision engine is when DEPLOY_AFFECTED_BIN does not say: the
/// //tools/ci:deploy_affected binary in this program's runfiles. Call it
/// before anything changes the working directory (argv[0] may be relative).
/// Returns an absolute path.
pub fn default_engine() -> Option<Vec<u8>> {
    use std::os::unix::ffi::OsStrExt;
    let set = |n: &str| env(n).map_or(false, |v| !v.is_empty());
    let prog = std::env::current_exe()
        .ok()
        .map(|p| p.as_os_str().as_bytes().to_vec())
        .unwrap_or_default();
    if !set("RUNFILES_DIR") && !set("RUNFILES_MANIFEST_FILE") {
        let dir = cat(&[&prog, b".runfiles"]);
        let manifest = cat(&[&prog, b".runfiles_manifest"]);
        if shell_compat::is_dir(&dir) {
            std::env::set_var("RUNFILES_DIR", shell_compat::os(&dir));
        } else if shell_compat::is_file(&manifest) {
            std::env::set_var("RUNFILES_MANIFEST_FILE", shell_compat::os(&manifest));
        } else {
            return None;
        }
    }
    let rf = runfiles::Runfiles::create().ok()?;
    let p = runfiles::rlocation!(rf, "_main/tools/ci/deploy_affected")?;
    let p = std::fs::canonicalize(p).ok()?;
    Some(p.as_os_str().as_bytes().to_vec())
}

#[derive(Clone)]
struct LastDelivered {
    sha: Vec<u8>,
    state: Vec<u8>,
    runs: usize,
}

fn last_delivered(
    cache: &mut PageCache,
    wf: &[u8],
    prefix: &[u8],
    branch: &[u8],
    gh: &[u8],
    repo: &[u8],
    page_size: &[u8],
    run_scan_limit: usize,
) -> LastDelivered {
    let ps: usize = std::str::from_utf8(page_size)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(100);
    let max_pages = (run_scan_limit + ps - 1) / ps;
    let mut total_runs: usize = 0;

    let mut page = 0usize;
    loop {
        page += 1;
        if !cache.fetch_page(wf, page, gh, repo, page_size) {
            return LastDelivered {
                sha: Vec::new(),
                state: b"error".to_vec(),
                runs: total_runs,
            };
        }
        let p = cache.page_path(wf, page);
        let content = match std::fs::read(&p) {
            Ok(c) => c,
            Err(_) => {
                return LastDelivered {
                    sha: Vec::new(),
                    state: b"error".to_vec(),
                    runs: total_runs,
                };
            }
        };
        let mut page_runs = 0usize;
        let mut next_cursor = Vec::new();
        let mut hit: Option<Vec<u8>> = None;
        for line in content.split(|&c| c == b'\n') {
            if line.is_empty() {
                continue;
            }
            if line.starts_with(b"next\t") {
                next_cursor = line[5..].to_vec();
                continue;
            }
            if !line.starts_with(b"run\t") {
                continue;
            }
            page_runs += 1;
            // run<TAB>id<TAB>sha<TAB>branch<TAB>jobs(\x1f-separated)
            let fields: Vec<&[u8]> = line.splitn(5, |&c| c == b'\t').collect();
            if fields.len() < 5 {
                continue;
            }
            let run_branch = fields[3];
            if run_branch != branch {
                continue;
            }
            let sha = fields[2];
            let jobs_raw = fields[4];
            if hit.is_none()
                && jobs_raw
                    .split(|&c| c == 0x1f)
                    .any(|j| j.starts_with(prefix))
            {
                hit = Some(sha.to_vec());
            }
        }
        total_runs += page_runs;
        if let Some(sha) = hit {
            return LastDelivered {
                sha,
                state: b"found".to_vec(),
                runs: total_runs,
            };
        }
        if next_cursor.is_empty() {
            return LastDelivered {
                sha: Vec::new(),
                state: b"absent".to_vec(),
                runs: total_runs,
            };
        }
        if page >= max_pages {
            return LastDelivered {
                sha: Vec::new(),
                state: b"capped".to_vec(),
                runs: total_runs,
            };
        }
    }
}

fn why_unknown(name: &[u8], env_name: &[u8], wf: &[u8], ld: &LastDelivered, run_scan_limit: usize) {
    match ld.state.as_slice() {
        b"error" => log(&cat(&[
            name,
            b": could not read the run history of ",
            wf,
            b" -- UNKNOWN (nothing inferred from a failed read)",
        ])),
        b"capped" => log(&cat(&[
            name,
            b": no successful ",
            env_name,
            b" delivery in the newest ",
            ld.runs.to_string().as_bytes(),
            b" runs of ",
            wf,
            b", and its history goes back further (RUN_SCAN_LIMIT=",
            run_scan_limit.to_string().as_bytes(),
            b") -- UNKNOWN",
        ])),
        _ => log(&cat(&[
            name,
            b": no successful ",
            env_name,
            b" delivery in the whole history of ",
            wf,
            b" (",
            ld.runs.to_string().as_bytes(),
            b" runs) -- UNKNOWN",
        ])),
    }
}

/// `read -r a b c d` with the default IFS: whitespace-separated, leading and
/// trailing whitespace dropped, the last variable taking the rest.
fn read4(line: &[u8]) -> [Vec<u8>; 4] {
    let ws = |c: &u8| *c == b' ' || *c == b'\t' || *c == b'\n';
    let mut out: [Vec<u8>; 4] = Default::default();
    let mut rest = line;
    for (i, slot) in out.iter_mut().enumerate() {
        while rest.first().map_or(false, ws) {
            rest = &rest[1..];
        }
        if i == 3 {
            let mut end = rest.len();
            while end > 0 && ws(&rest[end - 1]) {
                end -= 1;
            }
            *slot = rest[..end].to_vec();
            break;
        }
        let n = rest.iter().position(ws).unwrap_or(rest.len());
        *slot = rest[..n].to_vec();
        rest = &rest[n..];
    }
    out
}

struct JudgedCommit {
    state: Vec<u8>,
    sha: Vec<u8>,
    why: Vec<u8>,
}

fn find_judged_commit(
    wf: &[u8],
    gh: &[u8],
    repo: &[u8],
    branch: &[u8],
    head_sha: &[u8],
    drift_recent_runs: &[u8],
    ignore_in_flight: bool,
) -> JudgedCommit {
    if ignore_in_flight {
        return JudgedCommit {
            state: b"judge".to_vec(),
            sha: head_sha.to_vec(),
            why: b"main's tip (DRIFT_IGNORE_IN_FLIGHT set)".to_vec(),
        };
    }
    let r = capture(
        333,
        Command::new(shell_compat::os(gh))
            .arg("run")
            .arg("list")
            .arg("--repo")
            .arg(shell_compat::os(repo))
            .arg("--workflow")
            .arg(shell_compat::os(wf))
            .arg("--branch")
            .arg(shell_compat::os(branch))
            .arg("--event")
            .arg("push")
            .arg("--limit")
            .arg(shell_compat::os(drift_recent_runs))
            .arg("--json")
            .arg("databaseId,status,headSha,conclusion")
            .arg("--jq")
            // r##: the filter itself ends in `"`, which would close an r#"..."#.
            .arg(r##".[] | "\(.databaseId) \(.status) \(.headSha) \(.conclusion)""##),
    );
    if !r.ok() {
        return JudgedCommit {
            state: b"unknown".to_vec(),
            sha: b"-".to_vec(),
            why: cat(&[b"could not read the recent runs of `", wf, b"`"]),
        };
    }
    let raw = subst(r.stdout);

    // Check for waiting runs (approval gate)
    for line in shell_compat::lines(&raw) {
        let [id, run_status, _, _] = read4(&line);
        let (id, run_status) = (id.as_slice(), run_status.as_slice());
        if run_status == b"waiting" {
            return JudgedCommit {
                state: b"skip".to_vec(),
                sha: b"-".to_vec(),
                why: cat(&[
                    b"run ",
                    id,
                    b" of `",
                    wf,
                    b"` is waiting on an approval (it will deliver once approved)",
                ]),
            };
        }
    }

    // Find newest finished, non-cancelled run
    let mut in_flight: u64 = 0;
    let mut passed_over: u64 = 0;
    let mut found_sha = Vec::new();
    let mut found_id = Vec::new();
    let mut found_conclusion = Vec::new();
    for line in shell_compat::lines(&raw) {
        let [id, run_status, sha, conclusion] = read4(&line);
        if id.is_empty() {
            continue;
        }
        let (id, run_status, sha, conclusion) = (
            id.as_slice(),
            run_status.as_slice(),
            sha.as_slice(),
            conclusion.as_slice(),
        );

        if run_status != b"completed" {
            in_flight += 1;
            continue;
        }
        match conclusion {
            b"cancelled" | b"skipped" | b"stale" => {
                passed_over += 1;
                continue;
            }
            _ => {
                found_sha = sha.to_vec();
                found_id = id.to_vec();
                found_conclusion = conclusion.to_vec();
                break;
            }
        }
    }

    if found_sha.is_empty() {
        return JudgedCommit {
            state: b"skip".to_vec(),
            sha: b"-".to_vec(),
            why: cat(&[
                b"no finished push run among the newest ",
                drift_recent_runs,
                b" of `",
                wf,
                b"` (",
                in_flight.to_string().as_bytes(),
                b" in flight, ",
                passed_over.to_string().as_bytes(),
                b" cancelled)",
            ]),
        };
    }

    let conc_display = if found_conclusion.is_empty() {
        b"no conclusion".to_vec()
    } else {
        found_conclusion.clone()
    };
    let mut why = cat(&[
        b"newest finished run of `",
        wf,
        b"` (",
        &found_id,
        b", ",
        &conc_display,
        b") at `",
        &found_sha[..std::cmp::min(8, found_sha.len())],
        b"`",
    ]);
    if in_flight > 0 {
        why = cat(&[
            &why,
            b"; ",
            in_flight.to_string().as_bytes(),
            b" newer still in flight",
        ]);
    }
    if passed_over > 0 {
        why = cat(&[
            &why,
            b"; ",
            passed_over.to_string().as_bytes(),
            b" newer cancelled",
        ]);
    }

    // Check if sha is in local checkout
    let rc = status(
        371,
        Command::new("git")
            .arg("rev-parse")
            .arg("--verify")
            .arg("--quiet")
            .arg(shell_compat::os(&cat(&[&found_sha, b"^{commit}"])))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null()),
        true,
    );
    if rc != 0 {
        let r2 = capture(
            374,
            Command::new(shell_compat::os(gh))
                .arg("api")
                .arg(shell_compat::os(&cat(&[
                    b"repos/",
                    repo,
                    b"/compare/",
                    head_sha,
                    b"...",
                    &found_sha,
                ])))
                .arg("--jq")
                .arg(".status"),
        );
        let relation = if r2.ok() {
            subst(r2.stdout)
        } else {
            Vec::new()
        };
        return match relation.as_slice() {
            b"ahead" | b"identical" => JudgedCommit {
                state: b"judge".to_vec(),
                sha: head_sha.to_vec(),
                why: cat(&[&why, b", newer than this checkout: judged at the checkout"]),
            },
            _ => JudgedCommit {
                state: b"unknown".to_vec(),
                sha: b"-".to_vec(),
                why: cat(&[
                    &why,
                    b", which is not in this checkout (GitHub compare: ",
                    if relation.is_empty() {
                        b"no answer"
                    } else {
                        &relation
                    },
                    b")",
                ]),
            },
        };
    }

    JudgedCommit {
        state: b"judge".to_vec(),
        sha: found_sha,
        why,
    }
}

/// The engine's stdout+stderr for one range. Its exit status is ignored, as
/// the script's `|| true` did: the verdict is read from what it printed. An
/// engine that cannot be started reads as a degraded gate (not checked),
/// never as "nothing affects it".
fn ask_engine(
    engine: &[u8],
    extra: &[u8],
    exclude: &[u8],
    targets: &[u8],
    before: &[u8],
    after: &[u8],
) -> Vec<u8> {
    let mut cmd = Command::new(shell_compat::os(engine));
    cmd.env("EXTRA_PATH_REGEX", shell_compat::os(extra))
        .env("EXCLUDE_PATH_REGEX", shell_compat::os(exclude))
        .env("DEPLOY_TARGETS", shell_compat::os(targets))
        .env("BEFORE_REV", shell_compat::os(before))
        .env("AFTER_REV", shell_compat::os(after))
        .env("GITHUB_OUTPUT", "/dev/null")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped());
    match cmd.output() {
        Ok(o) => {
            let mut out = o.stdout;
            out.extend_from_slice(&o.stderr);
            subst(out)
        }
        Err(e) => cat(&[
            b"deploy gate degraded: could not start the engine ",
            engine,
            b": ",
            shell_compat::strerror(&e).as_bytes(),
        ]),
    }
}

/// Removes the page cache however the run ends (the script's EXIT trap).
struct RemoveOnDrop(Vec<u8>);

impl Drop for RemoveOnDrop {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(shell_compat::path(&self.0));
    }
}

/// `bazel run` entry: the engine defaults to the one in our runfiles.
pub fn run(args: &[Vec<u8>]) -> i32 {
    run_with_engine(args, default_engine())
}

/// `default_engine` is used when DEPLOY_AFFECTED_BIN is unset or empty.
pub fn run_with_engine(_args: &[Vec<u8>], default_engine: Option<Vec<u8>>) -> i32 {
    let repo = env_or("REPO", b"VitruvianSoftware/vitruvian-core");
    let workflow_file = env_or_empty("WORKFLOW_FILE");
    // LEGACY_WORKFLOW_FILE: default "delivery.yaml", empty disables
    let legacy_workflow_file = match env("LEGACY_WORKFLOW_FILE") {
        Some(v) => v,
        None => b"delivery.yaml".to_vec(),
    };
    let branch = env_or("BRANCH", b"main");
    let run_scan_limit: usize = std::str::from_utf8(&env_or("RUN_SCAN_LIMIT", b"5000"))
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5000);
    let page_size = env_or("DRIFT_PAGE_SIZE", b"100");
    let bazel = env_or("BAZEL", b"bazel");
    let gh = env_or("GH", b"gh");
    let drift_recent_runs = env_or("DRIFT_RECENT_RUNS", b"50");
    let drift_result_file = env_or_empty("DRIFT_RESULT_FILE");
    let drift_summary_file = env_or_empty("DRIFT_SUMMARY_FILE");
    let ignore_in_flight = shell_compat::env_set_nonempty("DRIFT_IGNORE_IN_FLIGHT");

    if shell_compat::which(&gh).is_none() {
        log(b"gh not found on PATH");
        return 2;
    }

    // Without the engine every unit would read as "nothing affects it", a
    // pass built on nothing: a setup error instead.
    let engine = match env("DEPLOY_AFFECTED_BIN")
        .filter(|v| !v.is_empty())
        .or(default_engine)
    {
        Some(e) => e,
        None => {
            log(b"cannot find the deploy-affected engine (//tools/ci:deploy_affected) in the runfiles; run me with bazel run //tools/ci:delivery_drift, or set DEPLOY_AFFECTED_BIN");
            return 2;
        }
    };
    if shell_compat::which(&engine).is_none() {
        log(&cat(&[
            b"the deploy-affected engine ",
            &engine,
            b" is not an executable",
        ]));
        return 2;
    }

    // --- 1. discover delivery units ---
    let r = capture(
        136,
        Command::new(shell_compat::os(&bazel))
            .arg("query")
            .arg(shell_compat::os(DELIVERY_QUERY))
            .arg("--output=label")
            .stderr(std::process::Stdio::null()),
    );
    let labels_raw = subst(r.stdout);
    if labels_raw.is_empty() {
        log(b"no delivery units declared (or bazel query failed) -- nothing to check");
        return 2;
    }
    let labels: Vec<Vec<u8>> = shell_compat::lines(&labels_raw)
        .into_iter()
        .filter(|l| !l.is_empty())
        .collect();

    // Build metadata
    let mut build_cmd = Command::new(shell_compat::os(&bazel));
    build_cmd
        .arg("build")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    for l in &labels {
        build_cmd.arg(shell_compat::os(l));
    }
    let rc = status(142, &mut build_cmd, true);
    if rc != 0 {
        log(b"bazel build of delivery metadata failed");
        return 2;
    }

    let r = capture(
        146,
        Command::new(shell_compat::os(&bazel))
            .arg("info")
            .arg("bazel-bin")
            .stderr(std::process::Stdio::null()),
    );
    if !r.ok() {
        log(b"bazel info bazel-bin failed -- cannot locate the delivery metadata");
        return 2;
    }
    let bin_dir = subst(r.stdout);

    let page_dir = match mktemp_dir() {
        Ok(d) => d,
        Err(_) => {
            log(b"failed to create temp directory");
            return 2;
        }
    };
    let _cleanup = RemoveOnDrop(page_dir.clone());
    let mut page_cache = PageCache::new(page_dir.clone());

    let head_r =
        shell_compat::capture_stdout(259, Command::new("git").arg("rev-parse").arg("HEAD"));
    if !head_r.ok() {
        // The script's `set -e` ended it here, with git's status.
        return head_r.status;
    }
    let head_sha = subst(head_r.stdout);

    // Tracking
    let mut drift_found = false;
    let mut bad: u64 = 0;
    let mut checked: u64 = 0;
    let mut skipped: u64 = 0;
    let mut checked_md = Vec::new();
    let mut skipped_md = Vec::new();
    let mut skipped_names = Vec::new();

    // Per-unit data
    struct Unit {
        name: Vec<u8>,
        first_env: Vec<u8>,
        wf: Vec<u8>,
        meta: Meta,
    }
    let mut units: Vec<Unit> = Vec::new();

    for label in &labels {
        // //pkg/sub:x.delivery_unit -> pkg/sub/x.delivery.json
        let mut rel: &[u8] = label;
        rel = rel.strip_prefix(b"@@").unwrap_or(rel);
        rel = rel.strip_prefix(b"@").unwrap_or(rel);
        rel = rel.strip_prefix(b"//").unwrap_or(rel);
        let (pkg, tgt) = match rel.iter().position(|&c| c == b':') {
            Some(colon) => (rel[..colon].to_vec(), rel[colon + 1..].to_vec()),
            None => (rel.to_vec(), rel.to_vec()),
        };
        let tgt_base = if tgt.ends_with(b".delivery_unit") {
            &tgt[..tgt.len() - 14]
        } else {
            &tgt
        };
        let meta = cat(&[&bin_dir, b"/", &pkg, b"/", tgt_base, b".delivery.json"]);
        if !shell_compat::is_file(&meta) {
            log(&cat(&[
                b"metadata missing for ",
                label,
                b" -- cannot check, treating as UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                label,
                b"`: **UNKNOWN: its metadata is missing**\n",
            ]));
            continue;
        }

        // A file that cannot be read as metadata is UNKNOWN (the script died
        // here under set -e, with no verdict at all).
        let Some(m) = read_meta(&meta) else {
            log(&cat(&[
                b"metadata for ",
                label,
                b" cannot be read -- cannot check, treating as UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                label,
                b"`: **UNKNOWN: its metadata cannot be read**\n",
            ]));
            continue;
        };
        let name = m.name.clone().into_bytes();
        let first_env = m.first_env.clone().into_bytes();
        let app = m.app.clone().into_bytes();
        if name.is_empty() {
            continue;
        }

        let wf = if !workflow_file.is_empty() {
            workflow_file.clone()
        } else if !app.is_empty() {
            cat(&[b"delivery-", &app, b".yaml"])
        } else {
            Vec::new()
        };
        if wf.is_empty() {
            log(&cat(&[
                &name,
                b": declares no app, so no workflow delivers it -- UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &name,
                b"`: **UNKNOWN: it declares no app, so no workflow delivers it**\n",
            ]));
            continue;
        }

        units.push(Unit {
            name,
            first_env,
            wf,
            meta: m,
        });
    }

    // --- judged commit cache per workflow ---
    let mut jc_cache: HashMap<Vec<u8>, JudgedCommit> = HashMap::new();

    // --- 4. per-unit check ---
    for unit in &units {
        let jc = jc_cache.entry(unit.wf.clone()).or_insert_with(|| {
            find_judged_commit(
                &unit.wf,
                &gh,
                &repo,
                &branch,
                &head_sha,
                &drift_recent_runs,
                ignore_in_flight,
            )
        });

        match jc.state.as_slice() {
            b"judge" => {}
            b"skip" => {
                log(&cat(&[&unit.name, b": ", &jc.why, b" -- not checked"]));
                skipped += 1;
                skipped_md.extend_from_slice(&cat(&[b"- `", &unit.name, b"`: ", &jc.why, b"\n"]));
                if !skipped_names.is_empty() {
                    skipped_names.extend_from_slice(b", ");
                }
                skipped_names.extend_from_slice(&unit.name);
                continue;
            }
            _ => {
                log(&cat(&[&unit.name, b": ", &jc.why, b" -- UNKNOWN"]));
                bad += 1;
                drift_found = true;
                checked += 1;
                checked_md.extend_from_slice(&cat(&[
                    b"- `",
                    &unit.name,
                    b"`: **UNKNOWN: ",
                    &jc.why,
                    b"**\n",
                ]));
                continue;
            }
        }

        let judge_sha = jc.sha.clone();
        let at = cat(&[
            b"judged at `",
            &judge_sha[..std::cmp::min(8, judge_sha.len())],
            b"`",
        ]);
        let job_prefix = cat(&[&unit.name, b"-", &unit.first_env]);

        let mut ld = last_delivered(
            &mut page_cache,
            &unit.wf,
            &job_prefix,
            &branch,
            &gh,
            &repo,
            &page_size,
            run_scan_limit,
        );

        let mut fell_back = false;
        if ld.state == b"absent"
            && !legacy_workflow_file.is_empty()
            && legacy_workflow_file != unit.wf
        {
            fell_back = true;
            ld = last_delivered(
                &mut page_cache,
                &legacy_workflow_file,
                &job_prefix,
                &branch,
                &gh,
                &repo,
                &page_size,
                run_scan_limit,
            );
            if ld.state == b"found" {
                log(&cat(&[
                    &unit.name,
                    b": no delivery in the whole history of ",
                    &unit.wf,
                    b"; last delivered by ",
                    &legacy_workflow_file,
                ]));
            }
        }

        // Only a unit that WAS looked up in the legacy history names it.
        let wf_display = if fell_back && ld.state != b"found" {
            cat(&[&unit.wf, b" or ", &legacy_workflow_file])
        } else {
            unit.wf.clone()
        };

        if ld.state != b"found" {
            why_unknown(
                &unit.name,
                &unit.first_env,
                &wf_display,
                &ld,
                run_scan_limit,
            );
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: **UNKNOWN: no delivery found in `",
                &wf_display,
                b"` (",
                &ld.state,
                b", ",
                ld.runs.to_string().as_bytes(),
                b" runs read)**\n",
            ]));
            continue;
        }

        let last_sha = ld.sha.clone();
        if last_sha == judge_sha {
            log(&cat(&[
                &unit.name,
                b": up to date (delivered ",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b") -- ",
                &jc.why,
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: up to date (delivered `",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b"`)\n",
            ]));
            continue;
        }

        // Check if last_sha contains judge_sha
        let ls_rc = status(
            438,
            Command::new("git")
                .arg("rev-parse")
                .arg("--verify")
                .arg("--quiet")
                .arg(shell_compat::os(&cat(&[&last_sha, b"^{commit}"])))
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        );
        if ls_rc != 0 {
            let r2 = capture(
                441,
                Command::new(shell_compat::os(&gh))
                    .arg("api")
                    .arg(shell_compat::os(&cat(&[
                        b"repos/",
                        &repo,
                        b"/compare/",
                        &judge_sha,
                        b"...",
                        &last_sha,
                    ])))
                    .arg("--jq")
                    .arg(".status"),
            );
            let relation = if r2.ok() {
                subst(r2.stdout)
            } else {
                Vec::new()
            };
            if relation == b"ahead" {
                log(&cat(&[
                    &unit.name,
                    b": up to date (delivered ",
                    &last_sha[..std::cmp::min(8, last_sha.len())],
                    b", newer than ",
                    &judge_sha[..std::cmp::min(8, judge_sha.len())],
                    b")",
                ]));
                checked += 1;
                checked_md.extend_from_slice(&cat(&[
                    b"- `",
                    &unit.name,
                    b"`: up to date (delivered `",
                    &last_sha[..std::cmp::min(8, last_sha.len())],
                    b"`, newer than the judged `",
                    &judge_sha[..std::cmp::min(8, judge_sha.len())],
                    b"`)\n",
                ]));
                continue;
            }
            log(&cat(&[
                &unit.name,
                b": last-delivered commit ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b" not in this checkout, and GitHub's compare says '",
                if relation.is_empty() {
                    b"no answer"
                } else {
                    &relation
                },
                b"' -- UNKNOWN",
            ]));
            bad += 1;
            drift_found = true;
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: **UNKNOWN: delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`, which is not in this checkout**\n",
            ]));
            continue;
        }

        let anc_rc = status(
            451,
            Command::new("git")
                .arg("merge-base")
                .arg("--is-ancestor")
                .arg(shell_compat::os(&judge_sha))
                .arg(shell_compat::os(&last_sha))
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null()),
            true,
        );
        if anc_rc == 0 {
            log(&cat(&[
                &unit.name,
                b": up to date (delivered ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b", which includes the judged ",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b")",
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: up to date (delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`, which includes the judged `",
                &judge_sha[..std::cmp::min(8, judge_sha.len())],
                b"`)\n",
            ]));
            continue;
        }

        // Read per-unit metadata for the engine
        let extra = unit.meta.extra.as_bytes();
        let exclude = unit.meta.exclude.as_bytes();
        let targets = unit.meta.targets.as_bytes();

        // PHASE 1 — range pre-filter
        let phase1 = ask_engine(&engine, extra, exclude, targets, &last_sha, &judge_sha);
        if shell_compat::contains(&phase1, b"deploy-gate-fallback")
            || shell_compat::contains(&phase1, b"gate degraded")
        {
            log(&cat(&[
                &unit.name,
                b": engine could not determine affectedness (gate degraded) -- NOT CHECKED",
            ]));
            skipped += 1;
            skipped_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: the affectedness engine could not tell (gate degraded)\n",
            ]));
            if !skipped_names.is_empty() {
                skipped_names.extend_from_slice(b", ");
            }
            skipped_names.extend_from_slice(&unit.name);
            continue;
        }
        if !shell_compat::contains(&phase1, b"affected=true") {
            let reason = extract_reason(&phase1, b"affected=false (");
            log(&cat(&[
                &unit.name,
                b": delivered ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"; nothing since affects it (",
                &reason,
                b")",
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`; nothing since affects it (",
                &at,
                b")\n",
            ]));
            continue;
        }

        // PHASE 2 — per-commit check
        let rev_r = capture(
            506,
            Command::new("git")
                .arg("rev-list")
                .arg("--reverse")
                .arg(shell_compat::os(&cat(&[&last_sha, b"..", &judge_sha]))),
        );
        let rev_list = subst(rev_r.stdout);
        let mut culprit = Vec::new();
        let mut culprit_why = Vec::new();
        for c in shell_compat::lines(&rev_list) {
            if c.is_empty() {
                continue;
            }
            let v = ask_engine(&engine, extra, exclude, targets, &cat(&[&c, b"^"]), &c);
            if shell_compat::contains(&v, b"deploy-gate-fallback")
                || shell_compat::contains(&v, b"gate degraded")
            {
                continue;
            }
            if shell_compat::contains(&v, b"affected=true") {
                culprit = c;
                culprit_why = extract_reason(&v, b"affected=true (");
                break;
            }
        }

        if culprit.is_empty() {
            log(&cat(&[
                &unit.name,
                b": delivered ",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"; only version-bump commits since (promote by tag, nothing to deploy)",
            ]));
            checked += 1;
            checked_md.extend_from_slice(&cat(&[
                b"- `",
                &unit.name,
                b"`: delivered `",
                &last_sha[..std::cmp::min(8, last_sha.len())],
                b"`; only version-bump commits since (",
                &at,
                b")\n",
            ]));
            continue;
        }

        // Get commit subject
        let subj_r = capture(
            523,
            Command::new("git")
                .arg("log")
                .arg("-1")
                .arg("--pretty=%s")
                .arg(shell_compat::os(&culprit)),
        );
        let subj = subst(subj_r.stdout);
        let subj_short = if subj.len() > 60 { &subj[..60] } else { &subj };

        log(&cat(&[
            b"DRIFT ",
            &unit.name,
            b": last delivered ",
            &last_sha[..std::cmp::min(8, last_sha.len())],
            b", but ",
            &culprit[..std::cmp::min(8, culprit.len())],
            b" ('",
            subj_short,
            b"') should have delivered and did not -- ",
            if culprit_why.is_empty() {
                b"no reason reported"
            } else {
                &culprit_why
            },
            b" -- judged at the ",
            &jc.why,
        ]));
        bad += 1;
        drift_found = true;
        checked += 1;
        checked_md.extend_from_slice(&cat(&[
            b"- `",
            &unit.name,
            b"`: **DRIFT: last delivered `",
            &last_sha[..std::cmp::min(8, last_sha.len())],
            b"`, but `",
            &culprit[..std::cmp::min(8, culprit.len())],
            b"` should have delivered and did not (",
            &at,
            b")**\n",
        ]));
    }

    // --- 5. verdict ---
    let total = checked + skipped;
    log(&cat(&[
        b"checked ",
        checked.to_string().as_bytes(),
        b" unit(s), not checked ",
        skipped.to_string().as_bytes(),
    ]));

    let (verdict, conclusion, title);
    if drift_found {
        verdict = b"DRIFT".to_vec();
        conclusion = b"failure".to_vec();
        title = cat(&[
            bad.to_string().as_bytes(),
            b" of ",
            total.to_string().as_bytes(),
            b" unit(s) behind main or unknown",
        ]);
    } else if checked == 0 {
        verdict = b"NOTHING_CHECKED".to_vec();
        conclusion = b"neutral".to_vec();
        title = cat(&[
            b"Nothing checked: all ",
            skipped.to_string().as_bytes(),
            b" unit(s) were skipped",
        ]);
    } else {
        verdict = b"OK".to_vec();
        conclusion = b"success".to_vec();
        title = if skipped == 0 {
            cat(&[checked.to_string().as_bytes(), b" unit(s) delivered"])
        } else {
            cat(&[
                checked.to_string().as_bytes(),
                b" unit(s) delivered; ",
                skipped.to_string().as_bytes(),
                b" not checked",
            ])
        };
    }

    if !skipped_names.is_empty() {
        log(&cat(&[b"NOT CHECKED: ", &skipped_names]));
    }

    if !drift_result_file.is_empty() {
        let data = cat(&[
            b"conclusion=",
            &conclusion,
            b"\ntitle=",
            &title,
            b"\nchecked=",
            checked.to_string().as_bytes(),
            b"\nskipped=",
            skipped.to_string().as_bytes(),
            b"\n",
        ]);
        let _ = std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(shell_compat::path(&drift_result_file))
            .and_then(|mut f| {
                use std::io::Write;
                f.write_all(&data)
            });
    }

    if !drift_summary_file.is_empty() {
        let mut summary = cat(&[
            b"**",
            &title,
            b"** (commit `",
            &head_sha[..std::cmp::min(8, head_sha.len())],
            b"`)\n\n",
        ]);
        if verdict == b"NOTHING_CHECKED" {
            summary.extend_from_slice(b"This is not a pass: no unit was judged. Every one was skipped, for the reason given below.\n\n");
        }
        if !checked_md.is_empty() {
            summary.extend_from_slice(&cat(&[
                b"### Checked (",
                checked.to_string().as_bytes(),
                b")\n",
            ]));
            summary.extend_from_slice(&checked_md);
            summary.push(b'\n');
        }
        if !skipped_md.is_empty() {
            summary.extend_from_slice(&cat(&[
                b"### Not checked (",
                skipped.to_string().as_bytes(),
                b")\n",
            ]));
            summary.extend_from_slice(&skipped_md);
            summary.push(b'\n');
        }
        if checked > 0 {
            summary.extend_from_slice(b"Each unit is judged at the newest finished delivery run of its app, not at main's tip: newer commits are still being delivered, and a later check judges them.\n");
        }
        let _ = shell_compat::write_file(&drift_summary_file, &summary, 0o644);
    }

    out(&cat(&[&verdict, b"\n"]));

    if verdict == b"DRIFT" {
        1
    } else {
        0
    }
}

/// `grep -o '<marker>.*)' | head -1`: on the first line holding the marker
/// AND a later ')', from the marker to that line's last ')'.
fn extract_reason(text: &[u8], marker: &[u8]) -> Vec<u8> {
    for line in text.split(|&c| c == b'\n') {
        let Some(pos) = line.windows(marker.len()).position(|w| w == marker) else {
            continue;
        };
        let rest = &line[pos..];
        if let Some(end) = rest[marker.len()..].iter().rposition(|&c| c == b')') {
            return rest[..marker.len() + end + 1].to_vec();
        }
    }
    Vec::new()
}
