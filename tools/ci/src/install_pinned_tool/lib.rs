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

//! //tools/ci:install_pinned_tool — download a pinned CI-tool release asset,
//! verify it against the sha256 that tools/tools.lock.json records for that
//! exact URL, and install it to ~/.local/bin for the rest of the job.
//!
//! The expected hash comes from the repo, never from the release (#4183): a
//! checksum file published next to the binary only proves the download was not
//! corrupted, since whoever can replace the binary can replace its checksum
//! too. Here a version bump has to change tools/tools.lock.json, so reviewers
//! see the new hash. A URL the lock does not pin, under the tool named by
//! `bin-name`, is refused before anything is downloaded.

use shell_compat::{cat, env, env_or_empty, err, mktemp_dir, os, out, path, status};
use std::process::Command;

const USAGE: &[u8] =
    b"usage: install-pinned-tool <lock-file> <base-url> <asset> <bin-name> --tar|--raw [member-path]\n";

pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.len() < 5 || args.len() > 6 {
        err(USAGE);
        return 2;
    }

    let lock_file = &args[0];
    let base_url = &args[1];
    let asset = &args[2];
    let bin_name = &args[3];
    let mode = &args[4];

    // An empty member path means the bin name too.
    let member_path = match args.get(5) {
        Some(m) if !m.is_empty() => m.clone(),
        _ => bin_name.clone(),
    };

    match mode.as_slice() {
        b"--tar" | b"--raw" => {}
        _ => {
            err(&cat(&[
                b"install-pinned-tool: mode must be --tar or --raw, got '",
                mode,
                b"'\n",
            ]));
            return 2;
        }
    }

    let github_path = match env("GITHUB_PATH") {
        Some(v) if !v.is_empty() => v,
        _ => {
            err(b"install-pinned-tool: GITHUB_PATH: GITHUB_PATH must be set \xe2\x80\x94 this script is meant to run as a GitHub Actions step\n");
            return 1;
        }
    };

    let asset_url = cat(&[base_url, b"/", asset]);
    let expected = match pinned_sha256(lock_file, bin_name, &asset_url, mode, &member_path) {
        Ok(h) => h,
        Err(msg) => {
            err(&cat(&[b"::error::install-pinned-tool: ", &msg, b"\n"]));
            return 1;
        }
    };

    let work = match mktemp_dir() {
        Ok(d) => d,
        Err(e) => {
            err(&cat(&[
                b"install-pinned-tool: mktemp failed: ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            return 1;
        }
    };

    let result = run_inner(
        &work,
        &asset_url,
        asset,
        &expected,
        lock_file,
        bin_name,
        mode,
        &member_path,
        &github_path,
    );

    let _ = std::fs::remove_dir_all(path(&work));
    result
}

/// The sha256 the lock pins for `url` under the tool `bin_name`, after
/// checking the entry agrees with how the caller means to install it.
fn pinned_sha256(
    lock_file: &[u8],
    bin_name: &[u8],
    url: &[u8],
    mode: &[u8],
    member_path: &[u8],
) -> Result<Vec<u8>, Vec<u8>> {
    let text = std::fs::read(path(lock_file))
        .map_err(|e| cat(&[b"cannot read ", lock_file, b": ", e.to_string().as_bytes()]))?;
    let lock =
        json::parse(&text).map_err(|e| cat(&[lock_file, b" is not valid JSON: ", e.as_bytes()]))?;
    let bin = String::from_utf8_lossy(bin_name).into_owned();
    let tool = lock.get(&bin).ok_or_else(|| {
        cat(&[
            lock_file,
            b" pins no tool named '",
            bin_name,
            b"'. Add its release assets, with their sha256, before installing it.",
        ])
    })?;
    let binaries = match tool.get("binaries") {
        Some(json::Value::Array(b)) => b,
        _ => {
            return Err(cat(&[
                lock_file,
                b": '",
                bin_name,
                b"' has no binaries list",
            ]))
        }
    };
    let url_s = String::from_utf8_lossy(url).into_owned();
    let entry = binaries
        .iter()
        .find(|b| b.str("url") == Some(url_s.as_str()))
        .ok_or_else(|| {
            let mut pinned: Vec<u8> = Vec::new();
            for b in binaries {
                if let Some(u) = b.str("url") {
                    pinned.extend_from_slice(b"\n  pinned: ");
                    pinned.extend_from_slice(u.as_bytes());
                }
            }
            cat(&[
                url,
                b" is not pinned in ",
                lock_file,
                b" under '",
                bin_name,
                b"', so it is not installed. To change the version, add the new assets with \
                  sha256 values you computed from the downloads (the release's own checksum \
                  file is not an independent source).",
                &pinned,
            ])
        })?;
    let kind = entry.str("kind").unwrap_or("");
    let want_kind = if mode == b"--tar" { "archive" } else { "file" };
    if kind != want_kind {
        return Err(cat(&[
            lock_file,
            b" pins ",
            url,
            b" as kind '",
            kind.as_bytes(),
            b"', but ",
            mode,
            b" installs kind '",
            want_kind.as_bytes(),
            b"'",
        ]));
    }
    if mode == b"--tar" {
        let file = entry.str("file").unwrap_or("");
        if file.as_bytes() != member_path {
            return Err(cat(&[
                lock_file,
                b" says the binary in ",
                url,
                b" is '",
                file.as_bytes(),
                b"', but this step extracts '",
                member_path,
                b"'",
            ]));
        }
    }
    let sha = entry.str("sha256").unwrap_or("");
    if sha.len() != 64
        || !sha
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
    {
        return Err(cat(&[
            lock_file,
            b": the sha256 for ",
            url,
            b" is not 64 lowercase hex digits: '",
            sha.as_bytes(),
            b"'",
        ]));
    }
    Ok(sha.as_bytes().to_vec())
}

fn run_inner(
    work: &[u8],
    asset_url: &[u8],
    asset: &[u8],
    expected: &[u8],
    lock_file: &[u8],
    bin_name: &[u8],
    mode: &[u8],
    member_path: &[u8],
    github_path: &[u8],
) -> i32 {
    let asset_path = cat(&[work, b"/", asset]);

    let rc = status(
        118,
        Command::new("curl")
            .current_dir(os(work))
            .arg("-fsSL")
            .arg("--retry")
            .arg("6")
            .arg("--retry-all-errors")
            .arg("--retry-max-time")
            .arg("180")
            .arg("--max-time")
            .arg("120")
            .arg("-O")
            .arg(os(asset_url)),
        false,
    );
    if rc != 0 {
        return rc;
    }

    let sha_r = shell_compat::capture_stdout(128, Command::new("sha256sum").arg(os(&asset_path)));
    if sha_r.status != 0 {
        return sha_r.status;
    }
    let actual = {
        let first = shell_compat::first_line(&sha_r.stdout);
        match first.iter().position(|&c| c == b' ') {
            Some(i) => first[..i].to_vec(),
            None => first,
        }
    };
    if actual != expected {
        err(&cat(&[
            b"::error::install-pinned-tool: checksum mismatch for ",
            asset_url,
            b": ",
            lock_file,
            b" pins ",
            expected,
            b", the download is ",
            &actual,
            b". Nothing installed.\n",
        ]));
        return 1;
    }
    out(&cat(&[
        asset,
        b": OK (sha256 pinned in ",
        lock_file,
        b")\n",
    ]));

    let home = env_or_empty("HOME");
    let local_bin = cat(&[&home, b"/.local/bin"]);
    if let Err(e) = shell_compat::mkdir_p(&local_bin) {
        err(&cat(&[
            b"install-pinned-tool: mkdir -p ",
            &local_bin,
            b": ",
            e.to_string().as_bytes(),
            b"\n",
        ]));
        return 1;
    }

    match mode {
        b"--tar" => {
            let depth = member_path.iter().filter(|&&c| c == b'/').count();
            let rc = status(
                136,
                Command::new("tar")
                    .arg("-xzf")
                    .arg(os(&asset_path))
                    .arg("-C")
                    .arg(os(&local_bin))
                    .arg(format!("--strip-components={}", depth))
                    .arg(os(member_path)),
                false,
            );
            if rc != 0 {
                return rc;
            }
        }
        b"--raw" => {
            let dest = cat(&[&local_bin, b"/", bin_name]);
            let rc = status(
                140,
                Command::new("install")
                    .arg("-m")
                    .arg("0755")
                    .arg(os(&asset_path))
                    .arg(os(&dest)),
                false,
            );
            if rc != 0 {
                return rc;
            }
        }
        _ => unreachable!(),
    }

    // A step that cannot put the tool on PATH fails, rather than reporting an
    // install later steps cannot use.
    let appended = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(path(github_path))
        .and_then(|mut f| {
            use std::io::Write;
            f.write_all(&cat(&[&local_bin, b"\n"]))
        });
    if let Err(e) = appended {
        err(&cat(&[
            b"install-pinned-tool: ",
            github_path,
            b": ",
            e.to_string().as_bytes(),
            b"\n",
        ]));
        return 1;
    }

    out(&cat(&[
        b"install-pinned-tool: installed ",
        bin_name,
        b" from ",
        asset_url,
        b"\n",
    ]));
    0
}

/// Just enough JSON to read tools/tools.lock.json. The callers build this
/// crate with a bare rustc and no crates, so there is no serde here.
mod json {
    // Bool's payload and numbers are parsed only to be skipped.
    #[allow(dead_code)]
    #[derive(Debug)]
    pub enum Value {
        Null,
        Bool(bool),
        Num,
        Str(String),
        Array(Vec<Value>),
        Object(Vec<(String, Value)>),
    }

    impl Value {
        pub fn get(&self, key: &str) -> Option<&Value> {
            match self {
                Value::Object(m) => m.iter().find(|(k, _)| k == key).map(|(_, v)| v),
                _ => None,
            }
        }
        pub fn str(&self, key: &str) -> Option<&str> {
            match self.get(key) {
                Some(Value::Str(s)) => Some(s),
                _ => None,
            }
        }
    }

    pub fn parse(b: &[u8]) -> Result<Value, String> {
        let mut p = P { b, i: 0, depth: 0 };
        let v = p.value()?;
        p.ws();
        if p.i != b.len() {
            return Err(format!("trailing data at byte {}", p.i));
        }
        Ok(v)
    }

    struct P<'a> {
        b: &'a [u8],
        i: usize,
        depth: usize,
    }

    impl P<'_> {
        fn ws(&mut self) {
            while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\t' | b'\n' | b'\r') {
                self.i += 1;
            }
        }
        fn fail<T>(&self, what: &str) -> Result<T, String> {
            Err(format!("{what} at byte {}", self.i))
        }
        fn lit(&mut self, s: &[u8], v: Value) -> Result<Value, String> {
            if self.b[self.i..].starts_with(s) {
                self.i += s.len();
                Ok(v)
            } else {
                self.fail("unexpected token")
            }
        }
        fn value(&mut self) -> Result<Value, String> {
            self.ws();
            match self.b.get(self.i) {
                None => self.fail("unexpected end"),
                Some(b'{') => self.nested(|p| p.object()),
                Some(b'[') => self.nested(|p| p.array()),
                Some(b'"') => Ok(Value::Str(self.string()?)),
                Some(b't') => self.lit(b"true", Value::Bool(true)),
                Some(b'f') => self.lit(b"false", Value::Bool(false)),
                Some(b'n') => self.lit(b"null", Value::Null),
                Some(c) if *c == b'-' || c.is_ascii_digit() => {
                    while self.i < self.b.len()
                        && matches!(
                            self.b[self.i],
                            b'-' | b'+' | b'.' | b'e' | b'E' | b'0'..=b'9'
                        )
                    {
                        self.i += 1;
                    }
                    Ok(Value::Num)
                }
                Some(_) => self.fail("unexpected character"),
            }
        }
        fn nested(
            &mut self,
            f: impl FnOnce(&mut Self) -> Result<Value, String>,
        ) -> Result<Value, String> {
            self.depth += 1;
            if self.depth > 64 {
                return self.fail("nested too deep");
            }
            let v = f(self);
            self.depth -= 1;
            v
        }
        fn object(&mut self) -> Result<Value, String> {
            self.i += 1;
            let mut m = Vec::new();
            self.ws();
            if self.b.get(self.i) == Some(&b'}') {
                self.i += 1;
                return Ok(Value::Object(m));
            }
            loop {
                self.ws();
                if self.b.get(self.i) != Some(&b'"') {
                    return self.fail("expected a string key");
                }
                let k = self.string()?;
                self.ws();
                if self.b.get(self.i) != Some(&b':') {
                    return self.fail("expected ':'");
                }
                self.i += 1;
                let v = self.value()?;
                m.push((k, v));
                self.ws();
                match self.b.get(self.i) {
                    Some(b',') => self.i += 1,
                    Some(b'}') => {
                        self.i += 1;
                        return Ok(Value::Object(m));
                    }
                    _ => return self.fail("expected ',' or '}'"),
                }
            }
        }
        fn array(&mut self) -> Result<Value, String> {
            self.i += 1;
            let mut a = Vec::new();
            self.ws();
            if self.b.get(self.i) == Some(&b']') {
                self.i += 1;
                return Ok(Value::Array(a));
            }
            loop {
                a.push(self.value()?);
                self.ws();
                match self.b.get(self.i) {
                    Some(b',') => self.i += 1,
                    Some(b']') => {
                        self.i += 1;
                        return Ok(Value::Array(a));
                    }
                    _ => return self.fail("expected ',' or ']'"),
                }
            }
        }
        fn hex4(&mut self) -> Result<u32, String> {
            let h = self.b.get(self.i..self.i + 4).ok_or("short \\u escape")?;
            let s = std::str::from_utf8(h).map_err(|_| "bad \\u escape")?;
            let n = u32::from_str_radix(s, 16)
                .map_err(|_| format!("bad \\u escape at byte {}", self.i))?;
            self.i += 4;
            Ok(n)
        }
        fn string(&mut self) -> Result<String, String> {
            self.i += 1;
            let mut s: Vec<u8> = Vec::new();
            loop {
                match self.b.get(self.i) {
                    None => return self.fail("unterminated string"),
                    Some(b'"') => {
                        self.i += 1;
                        return String::from_utf8(s).map_err(|_| "string is not UTF-8".to_string());
                    }
                    Some(b'\\') => {
                        self.i += 1;
                        let c = *self.b.get(self.i).ok_or("unterminated escape")?;
                        self.i += 1;
                        let ch = match c {
                            b'"' => '"',
                            b'\\' => '\\',
                            b'/' => '/',
                            b'b' => '\u{8}',
                            b'f' => '\u{c}',
                            b'n' => '\n',
                            b'r' => '\r',
                            b't' => '\t',
                            b'u' => {
                                let hi = self.hex4()?;
                                let cp = if (0xD800..0xDC00).contains(&hi) {
                                    if self.b.get(self.i..self.i + 2) != Some(b"\\u") {
                                        return self.fail("lone surrogate");
                                    }
                                    self.i += 2;
                                    let lo = self.hex4()?;
                                    if !(0xDC00..0xE000).contains(&lo) {
                                        return self.fail("bad surrogate pair");
                                    }
                                    0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
                                } else {
                                    hi
                                };
                                char::from_u32(cp).ok_or("bad code point")?
                            }
                            _ => return self.fail("bad escape"),
                        };
                        let mut buf = [0u8; 4];
                        s.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                    }
                    Some(&c) if c < 0x20 => return self.fail("control character in string"),
                    Some(&c) => {
                        s.push(c);
                        self.i += 1;
                    }
                }
            }
        }
    }
}
