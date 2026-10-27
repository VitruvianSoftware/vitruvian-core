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

//! rehearse.py: a rehearsal of the catalog, served on this Mac, for the
//! checks by hand. A key made for the run signs each list; typing a
//! scenario's name changes what is served.

use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::argparse::{Kind, Opt, Parser};
use crate::crypto::sha256;
use crate::http::{self, Request, Response};
use crate::json::{self, Value};
use crate::pyerr::{self, Crash, Res};
use crate::zip::ZipWriter;
use crate::{argparse, py, pypath, pystr, signing, timefmt};

pub const SCENARIOS: [(&str, &str); 8] = [
    ("install", "version 0.1.0 is listed: Install"),
    ("update", "version 0.2.0 is listed: Update available"),
    ("not-ours", "the list is signed with another key"),
    ("mismatch", "0.2.0 is listed with the checksum of 0.1.0"),
    ("not-the-tool", "0.3.0 is listed; its zip holds 0.2.0"),
    ("slip", "0.2.0's zip also holds ../escaped.txt"),
    (
        "unreachable",
        "0.2.0 is listed at an address that answers 404",
    ),
    (
        "rollback",
        "the first list served, signed and older than the last",
    ),
];

const DESCRIPTION: &str = "A rehearsal of the catalog, served on this Mac, for the checks by hand.";

/// Files by path, in the order Python's dict holds them.
pub type Files = Vec<(String, Vec<u8>)>;

fn executable(path: &Path) -> bool {
    use std::os::unix::ffi::OsStrExt;
    extern "C" {
        fn access(
            path: *const std::os::raw::c_char,
            mode: std::os::raw::c_int,
        ) -> std::os::raw::c_int;
    }
    let Ok(c) = std::ffi::CString::new(path.as_os_str().as_bytes()) else {
        return false;
    };
    // SAFETY: access reads the NUL-terminated path we pass and nothing else.
    unsafe { access(c.as_ptr(), 1) == 0 }
}

/// `sorted(Path(folder).rglob("*"))`: everything under `folder`, ordered
/// as pathlib orders paths, by their parts.
fn rglob(folder: &Path) -> Vec<PathBuf> {
    fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for e in entries.flatten() {
            let p = e.path();
            out.push(p.clone());
            let is_dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
            if is_dir {
                walk(&p, out);
            }
        }
    }
    let mut out = Vec::new();
    walk(folder, &mut out);
    out.sort_by(|a, b| {
        let pa: Vec<_> = a.components().map(|c| c.as_os_str().to_owned()).collect();
        let pb: Vec<_> = b.components().map(|c| c.as_os_str().to_owned()).collect();
        pa.cmp(&pb)
    });
    out
}

/// `tool_zip(folder, version, extra)`: the tool zipped as the catalog asks,
/// its manifest's version set.
pub fn tool_zip(folder: &Path, version: &str, extra: &[(&str, &[u8])]) -> Res<Vec<u8>> {
    let mut archive = ZipWriter::new(false);
    for path in rglob(folder) {
        if path.is_dir() || path.components().any(|c| c.as_os_str() == "__pycache__") {
            continue;
        }
        let name = path
            .strip_prefix(folder)
            .unwrap_or(&path)
            .to_string_lossy()
            .into_owned();
        let shown = path.to_string_lossy().into_owned();
        let mut data = pyerr::read_bytes(&shown)?;
        if name == "vitruvian-tool.json" {
            let mut manifest = json::loads_bytes(&data)?;
            match &mut manifest {
                Value::Dict(d) => d.insert("version", Value::Str(version.into())),
                other => {
                    return Err(Crash::new(
                        "TypeError",
                        format!(
                            "'{}' object does not support item assignment",
                            other.type_name()
                        ),
                    ))
                }
            }
            data = json::dumps(&manifest, Some(2), true).into_bytes();
        }
        let mode: u32 = if executable(&path) {
            0o100755
        } else {
            0o100644
        };
        archive.writestr(&name, &data, 3, mode << 16);
    }
    for (name, data) in extra {
        archive.writestr(name, data, 3, 0o100644 << 16);
    }
    Ok(archive.finish())
}

/// `entry(manifest, version, url, data)`.
pub fn entry(manifest: &Value, version: &str, url: &str, data: &[u8]) -> Res<Value> {
    let contributes = py::get_or(manifest, "contributes", Value::Dict(json::Dict::new()))?;
    let mut commands = Vec::new();
    for c in py::get_or(&contributes, "commands", Value::List(vec![]))?.py_iter()? {
        commands.push(json::dict(vec![
            ("id", c.at("id")?.clone()),
            ("title", c.at("title")?.clone()),
        ]));
    }
    let contributes = py::get_or(manifest, "contributes", Value::Dict(json::Dict::new()))?;
    let mut panels = Vec::new();
    for p in py::get_or(&contributes, "panels", Value::List(vec![]))?.py_iter()? {
        panels.push(p.at("placement")?.clone());
    }
    Ok(json::dict(vec![
        ("id", manifest.at("id")?.clone()),
        ("name", manifest.at("name")?.clone()),
        ("publisher", manifest.at("publisher")?.clone()),
        ("summary", manifest.at("description")?.clone()),
        ("version", json::s(version)),
        ("protocol", manifest.at("protocol")?.clone()),
        ("minimumAppVersion", json::s("0.0.0")),
        (
            "source",
            json::s("https://github.com/VitruvianSoftware/vitruvian-sdk"),
        ),
        (
            "download",
            json::dict(vec![
                ("url", json::s(url)),
                ("sha256", json::s(sha256::hexdigest(data))),
                ("size", Value::Int(data.len() as i128)),
            ]),
        ),
        ("uses", py::get_or(manifest, "uses", Value::List(vec![]))?),
        ("commands", Value::List(commands)),
        ("panels", Value::List(panels)),
    ]))
}

/// `build(folder, base, private, scenario, when)`: what the server serves.
pub fn build(folder: &Path, base: &str, private: &str, scenario: &str, when: i64) -> Res<Files> {
    let manifest = json::loads(&pyerr::read_text(
        &folder.join("vitruvian-tool.json").to_string_lossy(),
    )?)?;
    let old = tool_zip(folder, "0.1.0", &[])?;
    let new = tool_zip(folder, "0.2.0", &[])?;
    let slip = tool_zip(folder, "0.2.0", &[("../escaped.txt", b"x")])?;
    let u = |p: &str| format!("{}{}", base, p);
    let mut mismatch = entry(
        &manifest,
        "0.2.0",
        &u("/downloads/reference-0.2.0.zip"),
        &new,
    )?;
    if let Value::Dict(d) = &mut mismatch {
        d.insert(
            "download",
            json::dict(vec![
                ("url", json::s(u("/downloads/reference-0.2.0.zip"))),
                ("sha256", json::s(sha256::hexdigest(&old))),
                ("size", Value::Int(new.len() as i128)),
            ]),
        );
    }
    let tools: Vec<(&str, Value)> = vec![
        (
            "install",
            entry(
                &manifest,
                "0.1.0",
                &u("/downloads/reference-0.1.0.zip"),
                &old,
            )?,
        ),
        (
            "update",
            entry(
                &manifest,
                "0.2.0",
                &u("/downloads/reference-0.2.0.zip"),
                &new,
            )?,
        ),
        (
            "not-ours",
            entry(
                &manifest,
                "0.2.0",
                &u("/downloads/reference-0.2.0.zip"),
                &new,
            )?,
        ),
        ("mismatch", mismatch),
        (
            "not-the-tool",
            entry(
                &manifest,
                "0.3.0",
                &u("/downloads/reference-0.2.0.zip"),
                &new,
            )?,
        ),
        (
            "slip",
            entry(
                &manifest,
                "0.2.0",
                &u("/downloads/reference-0.2.0-slip.zip"),
                &slip,
            )?,
        ),
        (
            "unreachable",
            entry(&manifest, "0.2.0", &u("/downloads/missing.zip"), &new)?,
        ),
    ];
    let chosen = tools
        .into_iter()
        .find(|(k, _)| *k == scenario)
        .map(|(_, v)| v)
        .ok_or_else(|| Crash::key_error(scenario))?;
    let listed = json::dict(vec![
        ("version", Value::Int(1)),
        ("generated", json::s(timefmt::format(when))),
        ("tools", Value::List(vec![chosen])),
    ]);
    let data = (json::dumps(&listed, Some(2), true) + "\n").into_bytes();
    let key = if scenario == "not-ours" {
        signing::new_key().map_err(|e| Crash::os(&e, "/dev/urandom"))?
    } else {
        private.to_string()
    };
    let sig = signing::sign(&data, &key).map_err(|m| Crash::new("ValueError", m))?;
    Ok(vec![
        ("/downloads/reference-0.1.0.zip".into(), old),
        ("/downloads/reference-0.2.0.zip".into(), new),
        ("/downloads/reference-0.2.0-slip.zip".into(), slip),
        ("/tools.json".into(), data),
        ("/tools.json.sig".into(), sig),
    ])
}

struct State {
    when: i64,
    first: Option<Files>,
    files: Files,
}

/// `Rehearsal`: what is served now, switched by scenario.
pub struct Rehearsal {
    folder: PathBuf,
    base: String,
    private: String,
    state: Mutex<State>,
}

fn merge(files: &Files, over: &Files) -> Files {
    let mut out = files.clone();
    for (k, v) in over {
        match out.iter_mut().find(|(ok, _)| ok == k) {
            Some(slot) => slot.1 = v.clone(),
            None => out.push((k.clone(), v.clone())),
        }
    }
    out
}

impl Rehearsal {
    pub fn new(folder: PathBuf, base: String, private: String, now: i64) -> Res<Rehearsal> {
        let r = Rehearsal {
            folder,
            base,
            private,
            state: Mutex::new(State {
                when: now,
                first: None,
                files: Vec::new(),
            }),
        };
        r.switch("install")?;
        Ok(r)
    }

    pub fn switch(&self, scenario: &str) -> Res<()> {
        let mut st = self.state.lock().unwrap();
        let files = if scenario == "rollback" {
            merge(&st.files, st.first.as_ref().unwrap())
        } else {
            st.when += 1;
            let files = build(&self.folder, &self.base, &self.private, scenario, st.when)?;
            if st.first.is_none() {
                st.first = Some(
                    files
                        .iter()
                        .filter(|(k, _)| k == "/tools.json" || k == "/tools.json.sig")
                        .cloned()
                        .collect(),
                );
            }
            files
        };
        st.files = files;
        Ok(())
    }

    pub fn respond(&self, request: &Request) -> Response {
        let data = {
            let st = self.state.lock().unwrap();
            st.files
                .iter()
                .find(|(k, _)| *k == request.path)
                .map(|(_, v)| v.clone())
        };
        let data = match data {
            None => return http::error_response(404, None),
            Some(d) => d,
        };
        let etag = format!("\"{}\"", &sha256::hexdigest(&data)[..16]);
        if request.header("If-None-Match") == Some(etag.as_str()) {
            return Response {
                code: 304,
                headers: vec![("ETag".into(), etag)],
                body: Vec::new(),
            };
        }
        Response {
            code: 200,
            headers: vec![
                ("ETag".into(), etag),
                ("Content-Length".into(), data.len().to_string()),
            ],
            body: data,
        }
    }
}

/// `main(argv)`.
pub fn main(argv: &[String]) -> i32 {
    let p = Parser {
        prog: "rehearse.py".into(),
        description: Some(DESCRIPTION.into()),
        opts: vec![
            Opt::help(),
            Opt {
                strings: vec!["--port"],
                dest: "port",
                kind: Kind::Value,
                help: None,
                required: false,
            },
        ],
    };
    let int = |_: &str, v: &str| argparse::py_int(v).map(|_| ()).ok_or("int");
    let values = match p.parse(argv, &int) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let port = values
        .value("port")
        .and_then(argparse::py_int)
        .unwrap_or(8737);
    match run(port) {
        Ok(code) => code,
        Err(c) => pyerr::finish(&c),
    }
}

fn run(port: i64) -> Res<i32> {
    let ws = std::env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_else(|_| ".".into());
    let workspace = pypath::norm(&ws);
    let folder = PathBuf::from(pypath::join(
        &workspace,
        "packages/vitruvian-sdk/conformance/reference-tool",
    ));
    let base = format!("http://127.0.0.1:{}", port);
    let private = signing::new_key().map_err(|e| Crash::os(&e, "/dev/urandom"))?;
    let rehearsal = Arc::new(Rehearsal::new(
        folder,
        base.clone(),
        private.clone(),
        timefmt::now(),
    )?);
    if !(0..=65535).contains(&port) {
        return Err(Crash::new("OverflowError", "bind(): port must be 0-65535."));
    }
    let listener = std::net::TcpListener::bind(("127.0.0.1", port as u16))
        .map_err(|e| Crash::new("OSError", pyerr::os_error_plain(&e)))?;
    let served = rehearsal.clone();
    std::thread::spawn(move || {
        http::serve(
            listener,
            move |r| served.respond(r),
            |line| {
                let mut err = std::io::stderr();
                let _ = writeln!(err, "served {}", line);
            },
        )
    });
    let bundle = pypath::join(&workspace, "bazel-bin/apps/desktop/vitruvian/Vitruvian.zip");
    let public = signing::public_key_of(&private).map_err(|m| Crash::new("ValueError", m))?;
    let mut out = std::io::stdout();
    let mut say = |line: String| {
        let _ = writeln!(out, "{}", line);
        let _ = out.flush();
    };
    say(format!(
        "Serving a rehearsal catalog at {}/tools.json, signed with a key for this run only.",
        base
    ));
    say("Quit Vitruvian, then open a by-hand build (made with --define=vitruvian_sample_tool=true) pointed at it:".into());
    say(format!("  ditto -x -k {} /tmp/vitruvian", bundle));
    say(format!(
        "  open -n --env VITRUVIAN_CATALOGUE_URL={}/tools.json --env VITRUVIAN_CATALOGUE_KEY={} /tmp/vitruvian/Vitruvian.app",
        base, public
    ));
    say("Scenarios (type one and press Return; Control-D ends):".into());
    for (name, what) in SCENARIOS {
        say(format!("  {:13} {}", name, what));
    }
    say("Now serving: install".into());
    let stdin = std::io::stdin();
    let mut lock = stdin.lock();
    loop {
        let mut raw = Vec::new();
        if lock
            .read_until(b'\n', &mut raw)
            .map_err(|e| Crash::os(&e, "<stdin>"))?
            == 0
        {
            break;
        }
        let line = pyerr::decode_utf8_py(&raw, false)?;
        let name = pystr::strip(&line).to_string();
        if SCENARIOS.iter().any(|(n, _)| *n == name) {
            rehearsal.switch(&name)?;
            say(format!("Now serving: {}", name));
        } else if !name.is_empty() {
            say(format!("No scenario {}.", pystr::repr_str(&name)));
        }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scenarios_list_is_complete() {
        let names: Vec<&str> = SCENARIOS.iter().map(|(n, _)| *n).collect();
        assert_eq!(
            names,
            vec![
                "install",
                "update",
                "not-ours",
                "mismatch",
                "not-the-tool",
                "slip",
                "unreachable",
                "rollback"
            ]
        );
    }
}
