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

//! check_downloads.py: fetches each new or changed entry of the catalog and
//! checks it, as the app would before it offers the tool, and then some.

use std::io::Read;
use std::path::Path;
use std::time::{Duration, Instant};

use crate::argparse::{Kind, Opt, Parser};
use crate::crypto::sha256;
use crate::here::TempDir;
use crate::json::{self, Value};
use crate::pyerr::{self, Crash, Res};
use crate::{http, py, pypath, rules};

// The first line of the script's docstring, which stops mid-sentence.
const DESCRIPTION: &str =
    "Fetches each new or changed entry of the catalog and checks it, as the app";

/// What fetches a download: `fetch(url, size)`.
pub type Fetch<'a> = dyn Fn(&Value, &Value) -> Res<Option<Vec<u8>>> + 'a;
/// What validates a folder: `(status, what it said)`.
pub type Validate<'a> = dyn Fn(&Path) -> Res<(i32, String)> + 'a;

/// `fetch(url, size)`: the bytes, or None past `size` bytes or on error.
pub fn fetch(url: &Value, size: &Value) -> Res<Option<Vec<u8>>> {
    let url = match url {
        Value::Str(s) => s.clone(),
        other => {
            return Err(Crash::new(
                "AttributeError",
                format!("'{}' object has no attribute 'timeout'", other.type_name()),
            ))
        }
    };
    let size = match size {
        Value::Int(n) if *n >= 0 => *n as usize,
        Value::Int(_) => 0,
        other => {
            return Err(Crash::new(
                "TypeError",
                format!(
                    "unsupported operand type(s) for +: '{}' and 'int'",
                    other.type_name()
                ),
            ))
        }
    };
    let data = http::fetch(&url, size.saturating_add(1))?;
    Ok(data.filter(|d| d.len() <= size))
}

/// `validate(tool, folder)`: runs `vitruvian-tool validate` on the folder.
pub fn validate(tool: &str, folder: &Path) -> Res<(i32, String)> {
    let mut child = std::process::Command::new(tool)
        .arg("validate")
        .arg(folder)
        .stdin(std::process::Stdio::inherit())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| Crash::os(&e, tool))?;
    let mut out_pipe = child.stdout.take().unwrap();
    let mut err_pipe = child.stderr.take().unwrap();
    let out_reader = std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = out_pipe.read_to_end(&mut b);
        b
    });
    let err_reader = std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = err_pipe.read_to_end(&mut b);
        b
    });
    let deadline = Instant::now() + Duration::from_secs(120);
    let status = loop {
        if let Some(s) = child.try_wait().map_err(|e| Crash::os(&e, tool))? {
            break s;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(Crash::new(
                "subprocess.TimeoutExpired",
                format!(
                    "Command '['{}', 'validate', '{}']' timed out after 120 seconds",
                    tool,
                    folder.display()
                ),
            ));
        }
        std::thread::sleep(Duration::from_millis(5));
    };
    let out = out_reader.join().unwrap_or_default();
    let err = err_reader.join().unwrap_or_default();
    let text = |b: &[u8]| -> Res<String> {
        Ok(pyerr::universal_newlines(&pyerr::decode_utf8_py(b, false)?))
    };
    let code = match status.code() {
        Some(c) => c,
        None => {
            use std::os::unix::process::ExitStatusExt;
            -status.signal().unwrap_or(0)
        }
    };
    Ok((code, text(&out)? + &text(&err)?))
}

fn download<'a>(entry: &'a Value, key: &str) -> Res<&'a Value> {
    py::path(entry, &["download", key])
}

/// `check_entry(entry, fetch, validate)`: every problem with one entry's
/// download.
pub fn check_entry(entry: &Value, fetch: &Fetch, validate: &Validate) -> Res<Vec<String>> {
    let data = fetch(download(entry, "url")?, download(entry, "size")?)?;
    let data = match data {
        None => {
            return Ok(vec![
                "the download could not be fetched, or is larger than its size".into(),
            ])
        }
        Some(d) => d,
    };
    let mut problems = Vec::new();
    let size = download(entry, "size")?;
    if !json::py_eq(&Value::Int(data.len() as i128), size) {
        problems.push(format!(
            "the download is {} bytes, the entry says {}",
            data.len(),
            size.py_str()
        ));
    }
    let digest = sha256::hexdigest(&data);
    let sha = download(entry, "sha256")?;
    if !json::py_eq(&Value::Str(digest.clone()), sha) {
        problems.push(format!(
            "the download's sha256 is {}, the entry says {}",
            digest,
            sha.py_str()
        ));
    }
    if !problems.is_empty() {
        return Ok(problems);
    }
    let work = TempDir::new().map_err(|e| Crash::os(&e, "tmp"))?;
    let zip_path = work.path().join("download.zip");
    std::fs::write(&zip_path, &data).map_err(|e| pyerr::os_stop(&e, &zip_path))?;
    let problems = rules::zip_problems(&zip_path)?;
    if !problems.is_empty() {
        return Ok(problems);
    }
    let folder = work.path().join("tool");
    rules::unpack(&zip_path, &folder)?;
    let (status, said) = validate(&folder)?;
    if status != 0 {
        return Ok(vec![format!(
            "vitruvian-tool validate refused it:\n{}",
            said
        )]);
    }
    let manifest_path = folder.join("vitruvian-tool.json");
    let manifest = json::loads(&pyerr::read_text(&manifest_path.to_string_lossy())?)?;
    rules::manifest_problems(entry, &manifest)
}

fn ids(catalog: &Value) -> Res<Vec<json::Key>> {
    let mut out = Vec::new();
    for tool in py::get_or(catalog, "tools", Value::List(vec![]))?.py_iter()? {
        out.push(json::key(tool.at("id")?)?);
    }
    Ok(out)
}

/// `check(base, head, fetch, validate)`: every problem with the entries
/// `head` adds or changes.
pub fn check(base: &Value, head: &Value, fetch: &Fetch, validate: &Validate) -> Res<Vec<String>> {
    let mut found = Vec::new();
    let changed = rules::changed(base, head)?;
    let head_ids = ids(head)?;
    let removed = ids(base)?.into_iter().any(|id| !head_ids.contains(&id));
    if (!changed.is_empty() || removed) && rules::generated(head).is_some() {
        if let Some(before) = rules::generated(base) {
            if rules::generated(head).unwrap() <= before {
                found.push(format!(
                    "generated is not later than main's ({})",
                    base.at("generated")?.py_str()
                ));
            }
        }
    }
    for entry in &changed {
        for problem in check_entry(entry, fetch, validate)? {
            found.push(format!(
                "{} {}: {}",
                entry.at("id")?.py_str(),
                entry.at("version")?.py_str(),
                problem
            ));
        }
    }
    Ok(found)
}

fn opt(s: &'static str, dest: &'static str, help: &str) -> Opt {
    Opt {
        strings: vec![s],
        dest,
        kind: Kind::Value,
        help: Some(help.into()),
        required: true,
    }
}

/// `main(argv)`.
pub fn main(argv: &[String]) -> i32 {
    let p = Parser {
        prog: "check_downloads.py".into(),
        description: Some(DESCRIPTION.into()),
        opts: vec![
            Opt::help(),
            opt("--base", "base", "tools.json as it is on main"),
            opt("--head", "head", "tools.json as the pull request has it"),
            opt("--validate", "validate", "the vitruvian-tool command"),
        ],
    };
    let values = match p.parse(argv, &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let base = pypath::norm(values.value("base").unwrap_or(""));
    let head = pypath::norm(values.value("head").unwrap_or(""));
    let tool = values.value("validate").unwrap_or("").to_string();
    match run(&base, &head, &tool) {
        Ok(code) => code,
        Err(c) => pyerr::finish(&c),
    }
}

fn run(base_path: &str, head_path: &str, tool: &str) -> Res<i32> {
    let base = if Path::new(base_path).exists() {
        json::loads(&pyerr::read_text(base_path)?)?
    } else {
        json::dict(vec![("tools", Value::List(vec![]))])
    };
    let head = json::loads(&pyerr::read_text(head_path)?)?;
    for entry in rules::changed(&base, &head)? {
        println!(
            "checking {} {}: {}",
            entry.at("id")?.py_str(),
            entry.at("version")?.py_str(),
            download(&entry, "url")?.py_str()
        );
    }
    let problems = check(&base, &head, &fetch, &|folder: &Path| {
        validate(tool, folder)
    })?;
    for problem in &problems {
        println!("NOT OK   {}", problem);
    }
    if problems.is_empty() {
        println!("ok       every new or changed entry is the tool its download holds");
    }
    Ok(if problems.is_empty() { 0 } else { 1 })
}
