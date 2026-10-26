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

//! check-version-maps: the export version maps in copy.bara.sky must match
//! what this repo publishes. A port of check-version-maps.sh -- the bash
//! wrapper and the Python it runs -- with the same arguments, output, exit
//! codes (0 in sync, 1 drift or a missing entry, 2 unparseable) and the same
//! `--fix` rewrite.
//!
//! What Python did implicitly is done here on purpose: `open().read()`
//! translates `\r\n` and `\r` to `\n`; `re`'s `\s` is Unicode whitespace;
//! `os.path.join` restarts at an absolute part; a dict keeps the position of
//! a key's first occurrence and the value of its last (JSON is read through
//! serde into an order-keeping value, since serde_json's own map sorts);
//! `%s` of a version that is not a string prints Python's `str()` of it;
//! `glob("**")` skips hidden directories and follows directory symlinks.
//! A file Python could not read or parse (a traceback, exit 1) is exit 1
//! here too, with a one-line message instead of the traceback.

use std::collections::BTreeSet;
use std::fmt;
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};

// ---------------------------------------------------------------------------
// JSON as Python's json.load returns it: dicts keep insertion order.
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
pub enum PyJson {
    Null,
    Bool(bool),
    Int(i128),
    Float(f64),
    Str(String),
    List(Vec<PyJson>),
    Dict(Vec<(String, PyJson)>),
}

impl<'de> Deserialize<'de> for PyJson {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        struct V;
        impl<'de> Visitor<'de> for V {
            type Value = PyJson;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("any JSON value")
            }
            fn visit_unit<E: de::Error>(self) -> Result<PyJson, E> {
                Ok(PyJson::Null)
            }
            fn visit_bool<E: de::Error>(self, b: bool) -> Result<PyJson, E> {
                Ok(PyJson::Bool(b))
            }
            fn visit_i64<E: de::Error>(self, n: i64) -> Result<PyJson, E> {
                Ok(PyJson::Int(n as i128))
            }
            fn visit_u64<E: de::Error>(self, n: u64) -> Result<PyJson, E> {
                Ok(PyJson::Int(n as i128))
            }
            fn visit_f64<E: de::Error>(self, n: f64) -> Result<PyJson, E> {
                Ok(PyJson::Float(n))
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
                    // A repeated key keeps its first position, last value.
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

impl PyJson {
    fn get(&self, key: &str) -> Option<&PyJson> {
        match self {
            PyJson::Dict(items) => items.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    /// Python truthiness.
    fn truthy(&self) -> bool {
        match self {
            PyJson::Null => false,
            PyJson::Bool(b) => *b,
            PyJson::Int(n) => *n != 0,
            PyJson::Float(f) => *f != 0.0,
            PyJson::Str(s) => !s.is_empty(),
            PyJson::List(v) => !v.is_empty(),
            PyJson::Dict(v) => !v.is_empty(),
        }
    }

    /// `str(x)`, which is what `%s` prints.
    pub fn py_str(&self) -> String {
        match self {
            PyJson::Str(s) => s.clone(),
            other => other.py_repr(),
        }
    }

    /// `repr(x)`.
    pub fn py_repr(&self) -> String {
        match self {
            PyJson::Null => "None".into(),
            PyJson::Bool(true) => "True".into(),
            PyJson::Bool(false) => "False".into(),
            PyJson::Int(n) => n.to_string(),
            PyJson::Float(f) => py_float_repr(*f),
            PyJson::Str(s) => py_repr_str(s),
            PyJson::List(v) => {
                let parts: Vec<String> = v.iter().map(PyJson::py_repr).collect();
                format!("[{}]", parts.join(", "))
            }
            PyJson::Dict(v) => {
                let parts: Vec<String> = v
                    .iter()
                    .map(|(k, x)| format!("{}: {}", py_repr_str(k), x.py_repr()))
                    .collect();
                format!("{{{}}}", parts.join(", "))
            }
        }
    }
}

/// Python's `repr(float)`: the shortest round-trip digits, fixed between
/// 1e-4 and 1e16, scientific (two-digit exponent at least) outside.
pub fn py_float_repr(f: f64) -> String {
    if f.is_nan() {
        return "nan".into();
    }
    if f.is_infinite() {
        return if f > 0.0 { "inf".into() } else { "-inf".into() };
    }
    if f == 0.0 {
        return if f.is_sign_negative() {
            "-0.0".into()
        } else {
            "0.0".into()
        };
    }
    let e = format!("{:e}", f);
    let (mant, exp) = e.split_once('e').unwrap_or((&e, "0"));
    let exp: i32 = exp.parse().unwrap_or(0);
    let neg = mant.starts_with('-');
    let digits: String = mant.chars().filter(|c| c.is_ascii_digit()).collect();
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    if (-4..16).contains(&exp) {
        let point = exp + 1;
        if point <= 0 {
            out.push_str("0.");
            for _ in 0..(-point) {
                out.push('0');
            }
            out.push_str(&digits);
        } else {
            let p = point as usize;
            if digits.len() <= p {
                out.push_str(&digits);
                for _ in 0..(p - digits.len()) {
                    out.push('0');
                }
                out.push_str(".0");
            } else {
                out.push_str(&digits[..p]);
                out.push('.');
                out.push_str(&digits[p..]);
            }
        }
    } else {
        out.push_str(&digits[..1]);
        if digits.len() > 1 {
            out.push('.');
            out.push_str(&digits[1..]);
        }
        out.push('e');
        out.push(if exp < 0 { '-' } else { '+' });
        out.push_str(&format!("{:02}", exp.abs()));
    }
    out
}

fn printable(c: char) -> bool {
    if c == ' ' {
        return true;
    }
    if c.is_control() || py_space(c) {
        return false;
    }
    !matches!(c as u32, 0xAD | 0x600..=0x605 | 0x61C | 0x6DD | 0x70F | 0x180E | 0x200B..=0x200F
        | 0x202A..=0x202E | 0x2060..=0x2064 | 0x2066..=0x206F | 0xFEFF | 0xFFF9..=0xFFFB
        | 0xE000..=0xF8FF | 0xF0000..=0x10FFFF)
}

/// Python's `repr(str)`.
pub fn py_repr_str(s: &str) -> String {
    let quote = if s.contains('\'') && !s.contains('"') {
        '"'
    } else {
        '\''
    };
    let mut out = String::new();
    out.push(quote);
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c == quote => {
                out.push('\\');
                out.push(c);
            }
            c if !printable(c) => {
                let cp = c as u32;
                if cp < 0x100 {
                    out.push_str(&format!("\\x{:02x}", cp));
                } else if cp < 0x10000 {
                    out.push_str(&format!("\\u{:04x}", cp));
                } else {
                    out.push_str(&format!("\\U{:08x}", cp));
                }
            }
            c => out.push(c),
        }
    }
    out.push(quote);
    out
}

// ---------------------------------------------------------------------------
// Python's str and os.path behaviours
// ---------------------------------------------------------------------------

/// `\s` in a `str` pattern: Unicode whitespace, which for Python also takes
/// in the four information separators U+001C..U+001F.
pub fn py_space(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

/// `open(f).read()`: text mode, UTF-8, universal newlines.
pub fn universal_newlines(s: &str) -> String {
    s.replace("\r\n", "\n").replace('\r', "\n")
}

/// `os.path.join(a, b)`.
pub fn py_join(a: &str, b: &str) -> String {
    if b.starts_with('/') {
        b.to_string()
    } else if a.is_empty() || a.ends_with('/') {
        format!("{}{}", a, b)
    } else {
        format!("{}/{}", a, b)
    }
}

fn py_join3(a: &str, b: &str, c: &str) -> String {
    py_join(&py_join(a, b), c)
}

/// `%-Ns`: left-justified to N characters.
fn ljust(s: &str, n: usize) -> String {
    let len = s.chars().count();
    if len >= n {
        s.to_string()
    } else {
        format!("{}{}", s, " ".repeat(n - len))
    }
}

/// `re.sub(r"/v\d+$", "", key)`. `$` also matches just before a final
/// newline, and only one match is possible.
pub fn strip_major(key: &str) -> String {
    let (body, nl) = match key.strip_suffix('\n') {
        Some(b) => (b, "\n"),
        None => (key, ""),
    };
    let try_strip = |s: &str| -> Option<usize> {
        let digits = s.chars().rev().take_while(|c| c.is_ascii_digit()).count();
        if digits == 0 {
            return None;
        }
        let head = &s[..s.len() - digits];
        head.strip_suffix("/v").map(|h| h.len())
    };
    // The end of the string first (the leftmost match wins, but at most one
    // of the two positions can match: a match before the newline needs the
    // newline to follow it, one at the end needs a digit last).
    if nl.is_empty() {
        if let Some(n) = try_strip(key) {
            return key[..n].to_string();
        }
        return key.to_string();
    }
    if let Some(n) = try_strip(body) {
        return format!("{}{}", &body[..n], nl);
    }
    key.to_string()
}

// ---------------------------------------------------------------------------
// The two regexes over copy.bara.sky
// ---------------------------------------------------------------------------

/// `re.search(re.escape(name) + r'\s*=\s*\{(.*?)\n\}', src, re.S)`: the char
/// span of the group (start, end), or None.
pub fn find_map(src: &[char], name: &str) -> Option<(usize, usize)> {
    let pat: Vec<char> = name.chars().collect();
    if pat.is_empty() {
        return None;
    }
    let n = src.len();
    let mut i = 0;
    while i + pat.len() <= n {
        if src[i..i + pat.len()] == pat[..] {
            let mut j = i + pat.len();
            while j < n && py_space(src[j]) {
                j += 1;
            }
            if j < n && src[j] == '=' {
                j += 1;
                while j < n && py_space(src[j]) {
                    j += 1;
                }
                if j < n && src[j] == '{' {
                    let start = j + 1;
                    let mut k = start;
                    while k + 1 < n {
                        if src[k] == '\n' && src[k + 1] == '}' {
                            return Some((start, k));
                        }
                        k += 1;
                    }
                }
            }
        }
        i += 1;
    }
    None
}

/// One `"([^"]+)"\s*:\s*"([^"]+)"` match: (start, end, key, value), in chars.
type Pair = (usize, usize, String, String);

/// `re.finditer(r'"([^"]+)"\s*:\s*"([^"]+)"', blk)`.
pub fn find_pairs(blk: &[char]) -> Vec<Pair> {
    let n = blk.len();
    let mut out = Vec::new();
    let mut p = 0;
    while p < n {
        if let Some(m) = pair_at(blk, p) {
            p = m.1;
            out.push(m);
        } else {
            p += 1;
        }
    }
    out
}

fn quoted_at(blk: &[char], p: usize) -> Option<(usize, String)> {
    let n = blk.len();
    if p >= n || blk[p] != '"' {
        return None;
    }
    let mut q = p + 1;
    while q < n && blk[q] != '"' {
        q += 1;
    }
    if q >= n || q == p + 1 {
        return None;
    }
    Some((q + 1, blk[p + 1..q].iter().collect()))
}

fn pair_at(blk: &[char], p: usize) -> Option<Pair> {
    let n = blk.len();
    let (mut j, key) = quoted_at(blk, p)?;
    while j < n && py_space(blk[j]) {
        j += 1;
    }
    if j >= n || blk[j] != ':' {
        return None;
    }
    j += 1;
    while j < n && py_space(blk[j]) {
        j += 1;
    }
    let (end, val) = quoted_at(blk, j)?;
    Some((p, end, key, val))
}

/// `dict(re.findall(...))`: first position, last value.
pub fn to_dict(pairs: &[Pair]) -> Vec<(String, String)> {
    let mut d: Vec<(String, String)> = Vec::new();
    for (_, _, k, v) in pairs {
        if let Some(slot) = d.iter_mut().find(|(ek, _)| ek == k) {
            slot.1 = v.clone();
        } else {
            d.push((k.clone(), v.clone()));
        }
    }
    d
}

// ---------------------------------------------------------------------------
// Files
// ---------------------------------------------------------------------------

/// What made Python stop with a traceback.
#[derive(Debug)]
pub struct Crash(pub String);

fn read_text(path: &str) -> Result<String, Crash> {
    let bytes = fs::read(path).map_err(|e| Crash(format!("cannot read {}: {}", path, e)))?;
    let s =
        String::from_utf8(bytes).map_err(|_| Crash(format!("cannot read {}: not UTF-8", path)))?;
    Ok(universal_newlines(&s))
}

fn load_json(path: &str) -> Result<PyJson, Crash> {
    let text = read_text(path)?;
    serde_json::from_str::<PyJson>(&text)
        .map_err(|e| Crash(format!("cannot parse {}: {}", path, e)))
}

fn exists(path: &str) -> bool {
    !path.contains('\0') && fs::metadata(path).is_ok()
}

fn lexists(path: &str) -> bool {
    !path.contains('\0') && fs::symlink_metadata(path).is_ok()
}

/// `d.get("version")` on a package.json (a non-dict top level is an
/// AttributeError in Python).
fn ts_version(path: &str) -> Result<PyJson, Crash> {
    match load_json(path)? {
        d @ PyJson::Dict(_) => Ok(d.get("version").cloned().unwrap_or(PyJson::Null)),
        _ => Err(Crash(format!("{}: top level is not an object", path))),
    }
}

/// `list(json.load(open(mf)).values())[0]`.
fn go_version(path: &str) -> Result<PyJson, Crash> {
    match load_json(path)? {
        PyJson::Dict(items) => items
            .into_iter()
            .next()
            .map(|(_, v)| v)
            .ok_or_else(|| Crash(format!("{}: empty manifest", path))),
        _ => Err(Crash(format!("{}: top level is not an object", path))),
    }
}

/// `glob.glob(os.path.join(root, "**", "package.json"), recursive=True)`.
pub fn glob_package_jsons(root: &str) -> Vec<String> {
    let mut out = Vec::new();
    // `**` matching no directory: os.path.join(root, "") then the name.
    let top = py_join(root, "");
    if lexists(&py_join(&top, "package.json")) {
        out.push(py_join(&top, "package.json"));
    }
    let mut stack: Vec<(String, String)> = vec![(root.to_string(), String::new())];
    while let Some((dir, rel)) = stack.pop() {
        let listing = if dir.is_empty() { "." } else { dir.as_str() };
        let entries = match fs::read_dir(listing) {
            Ok(e) => e,
            Err(_) => continue,
        };
        let mut names: Vec<String> = Vec::new();
        for e in entries.flatten() {
            let name = e.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            let full = py_join(&dir, &name);
            if fs::metadata(&full).map(|m| m.is_dir()).unwrap_or(false) {
                names.push(name);
            }
        }
        for name in names {
            let full = py_join(&dir, &name);
            let rel2 = if rel.is_empty() {
                name.clone()
            } else {
                py_join(&rel, &name)
            };
            let shown = py_join(root, &rel2);
            if lexists(&py_join(&full, "package.json")) {
                out.push(py_join(&shown, "package.json"));
            }
            stack.push((full, rel2));
        }
    }
    out
}

// ---------------------------------------------------------------------------
// The check
// ---------------------------------------------------------------------------

pub struct Paths {
    pub sky: String,
    pub ts_root: String,
    pub go_root: String,
    pub ts_example: String,
}

/// What a run printed and how it ended.
#[derive(Debug, Default, PartialEq)]
pub struct Outcome {
    pub stdout: String,
    pub stderr: String,
    pub code: i32,
}

const TS_MAP: &str = "_TS_EXAMPLE_LIB_VERSIONS";
const GO_MAP: &str = "_GO_EXAMPLE_LIB_VERSIONS";
const FOUNDATION: &str = "@vitruviansoftware/foundation-";

fn parse_map(src: &[char], name: &str) -> Option<Vec<(String, String)>> {
    let (s, e) = find_map(src, name)?;
    Some(to_dict(&find_pairs(&src[s..e])))
}

/// The Python program, from `src = open(sky).read()` on.
pub fn check(p: &Paths, fix: bool) -> Outcome {
    match check_inner(p, fix) {
        Ok(o) => o,
        Err(Crash(msg)) => Outcome {
            stdout: String::new(),
            stderr: format!("check-version-maps: {}\n", msg),
            code: 1,
        },
    }
}

fn check_inner(p: &Paths, fix: bool) -> Result<Outcome, Crash> {
    let src_text = read_text(&p.sky)?;
    let src: Vec<char> = src_text.chars().collect();
    let unparsed = |name: &str| Outcome {
        stdout: String::new(),
        stderr: format!("check-version-maps: could not parse {}\n", name),
        code: 2,
    };
    let mut problems: Vec<String> = Vec::new();

    // --- TypeScript ---
    let ts = match parse_map(&src, TS_MAP) {
        Some(m) => m,
        None => return Ok(unparsed(TS_MAP)),
    };
    let mut ts_sorted = ts.clone();
    ts_sorted.sort();
    for (key, mapped) in &ts_sorted {
        let pj = py_join3(&p.ts_root, key, "package.json");
        if !exists(&pj) {
            problems.push(format!(
                "ts  {} maps to a package that does not exist ({})",
                ljust(key, 28),
                pj
            ));
            continue;
        }
        let actual = ts_version(&pj)?;
        if actual != PyJson::Str(mapped.clone()) {
            problems.push(format!(
                "ts  {} map={} repo={}",
                ljust(key, 28),
                ljust(mapped, 9),
                actual.py_str()
            ));
        }
    }

    let mut needed: BTreeSet<String> = BTreeSet::new();
    for pj in glob_package_jsons(&p.ts_example) {
        if pj.contains("node_modules") {
            continue;
        }
        let d = load_json(&pj)?;
        if !matches!(d, PyJson::Dict(_)) {
            return Err(Crash(format!("{}: top level is not an object", pj)));
        }
        for field in ["dependencies", "devDependencies"] {
            let deps = match d.get(field) {
                Some(v) if v.truthy() => v,
                _ => continue,
            };
            let items = match deps {
                PyJson::Dict(items) => items,
                _ => return Err(Crash(format!("{}: {} is not an object", pj, field))),
            };
            for (dep, spec) in items {
                if let (Some(rest), PyJson::Str(s)) = (dep.strip_prefix(FOUNDATION), spec) {
                    if s.starts_with("workspace:") {
                        needed.insert(rest.to_string());
                    }
                }
            }
        }
    }
    for miss in &needed {
        if !ts.iter().any(|(k, _)| k == miss) {
            problems.push(format!(
                "ts  {} used by the example as workspace:* but ABSENT from the map",
                ljust(miss, 28)
            ));
        }
    }

    // --- Go ---
    let go = match parse_map(&src, GO_MAP) {
        Some(m) => m,
        None => return Ok(unparsed(GO_MAP)),
    };
    let mut go_sorted = go.clone();
    go_sorted.sort();
    for (key, mapped) in &go_sorted {
        let mf = py_join3(
            &p.go_root,
            &strip_major(key),
            ".release-please-manifest.json",
        );
        if !exists(&mf) {
            problems.push(format!(
                "go  {} maps to a module with no manifest ({})",
                ljust(key, 28),
                mf
            ));
            continue;
        }
        let actual = go_version(&mf)?;
        if actual != PyJson::Str(mapped.clone()) {
            problems.push(format!(
                "go  {} map={} repo={}",
                ljust(key, 28),
                ljust(mapped, 9),
                actual.py_str()
            ));
        }
    }

    if !problems.is_empty() && fix {
        let mut src = src;
        let ts_root = p.ts_root.clone();
        let go_root = p.go_root.clone();
        rewrite(&mut src, TS_MAP, &|k| {
            let f = py_join3(&ts_root, k, "package.json");
            if exists(&f) {
                ts_version(&f).map(Some)
            } else {
                Ok(None)
            }
        })?;
        rewrite(&mut src, GO_MAP, &|k| {
            let f = py_join3(&go_root, &strip_major(k), ".release-please-manifest.json");
            if exists(&f) {
                go_version(&f).map(Some)
            } else {
                Ok(None)
            }
        })?;
        let text: String = src.iter().collect();
        fs::write(&p.sky, text.as_bytes())
            .map_err(|e| Crash(format!("cannot write {}: {}", p.sky, e)))?;
        return Ok(Outcome {
            stdout: format!(
                "check-version-maps: rewrote {} from the repo's versions.\n",
                p.sky
            ),
            stderr: String::new(),
            code: 0,
        });
    }

    if !problems.is_empty() {
        let mut e = format!(
            "check-version-maps: {} problem(s) in {}\n",
            problems.len(),
            p.sky
        );
        for pr in &problems {
            e.push_str("  ");
            e.push_str(pr);
            e.push('\n');
        }
        e.push('\n');
        e.push_str("  These maps rewrite in-tree references to PUBLISHED versions on export.\n");
        e.push_str("  A stale entry ships a mirror that cannot resolve its own dependencies.\n");
        return Ok(Outcome {
            stdout: String::new(),
            stderr: e,
            code: 1,
        });
    }

    Ok(Outcome {
        stdout: format!(
            "check-version-maps: {} ts + {} go entries all match the repo.\n",
            ts.len(),
            go.len()
        ),
        stderr: String::new(),
        code: 0,
    })
}

type Resolve<'a> = dyn Fn(&str) -> Result<Option<PyJson>, Crash> + 'a;

/// The `--fix` rewrite of one map: every pair whose repo version is truthy
/// and differs becomes `"<key>": "<str(version)>"`; layout and comments stay.
fn rewrite(src: &mut Vec<char>, name: &str, resolve: &Resolve) -> Result<(), Crash> {
    let (s, e) = match find_map(src, name) {
        Some(span) => span,
        None => return Err(Crash(format!("could not find {} again", name))),
    };
    let blk: Vec<char> = src[s..e].to_vec();
    let mut out: Vec<char> = Vec::with_capacity(blk.len());
    let mut last = 0;
    for (ms, me, k, old) in find_pairs(&blk) {
        out.extend_from_slice(&blk[last..ms]);
        let new = resolve(&k)?;
        match new {
            Some(v) if v.truthy() && v != PyJson::Str(old.clone()) => {
                out.extend(format!("\"{}\": \"{}\"", k, v.py_str()).chars());
            }
            _ => out.extend_from_slice(&blk[ms..me]),
        }
        last = me;
    }
    out.extend_from_slice(&blk[last..]);
    let mut next: Vec<char> = Vec::with_capacity(src.len() + out.len());
    next.extend_from_slice(&src[..s]);
    next.extend(out);
    next.extend_from_slice(&src[e..]);
    *src = next;
    Ok(())
}

// ---------------------------------------------------------------------------
// The bash wrapper
// ---------------------------------------------------------------------------

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var_os(name)
        .map(|v| v.to_string_lossy().into_owned())
        .filter(|v| !v.is_empty())
}

fn prog() -> String {
    std::env::args_os()
        .next()
        .map(|a| a.to_string_lossy().into_owned())
        .unwrap_or_else(|| "check-version-maps".into())
}

/// `cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"`.
fn enter_workspace() -> Result<(), String> {
    let target = match env_nonempty("BUILD_WORKSPACE_DIRECTORY") {
        Some(d) => d,
        None => {
            let out = Command::new("git")
                .args(["rev-parse", "--show-toplevel"])
                .stdin(Stdio::inherit())
                .stderr(Stdio::null())
                .output();
            match out {
                Ok(o) if o.status.success() => {
                    let mut s = o.stdout;
                    s.retain(|&c| c != 0);
                    while s.last() == Some(&b'\n') {
                        s.pop();
                    }
                    String::from_utf8_lossy(&s).into_owned()
                }
                // `pwd`: here already.
                _ => return Ok(()),
            }
        }
    };
    if target.is_empty() {
        return Ok(());
    }
    std::env::set_current_dir(&target)
        .map_err(|e| format!("{}: line 65: cd: {}: {}\n", prog(), target, strerror(&e)))
}

fn strerror(e: &std::io::Error) -> String {
    let s = e.to_string();
    match s.find(" (os error") {
        Some(i) => s[..i].to_string(),
        None => s,
    }
}

/// The whole command: arguments as given (argv[1..]).
pub fn run(args: &[String]) -> Outcome {
    let mut fix = false;
    for a in args {
        match a.as_str() {
            "--fix" => fix = true,
            "" => {}
            other => {
                return Outcome {
                    stdout: String::new(),
                    stderr: format!("check-version-maps: unknown argument {}\n", other),
                    code: 2,
                }
            }
        }
    }
    if let Err(msg) = enter_workspace() {
        return Outcome {
            stdout: String::new(),
            stderr: msg,
            code: 1,
        };
    }
    let paths = Paths {
        sky: env_nonempty("SKY").unwrap_or_else(|| "tools/copybara/copy.bara.sky".into()),
        ts_root: env_nonempty("TS_ROOT")
            .unwrap_or_else(|| "packages/pulumi/library/ts/packages".into()),
        go_root: env_nonempty("GO_ROOT").unwrap_or_else(|| "packages/pulumi/library/go/pkg".into()),
        ts_example: env_nonempty("TS_EXAMPLE")
            .unwrap_or_else(|| "packages/pulumi/examples/ts-foundation".into()),
    };
    if !Path::new(&paths.sky).is_file() {
        return Outcome {
            stdout: String::new(),
            stderr: format!("check-version-maps: {} not found\n", paths.sky),
            code: 2,
        };
    }
    check(&paths, fix)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chars(s: &str) -> Vec<char> {
        s.chars().collect()
    }

    #[test]
    fn map_regex_finds_the_block_and_skips_lookalikes() {
        let src = chars("x = _TS_EXAMPLE_LIB_VERSIONS.get(1)\n_TS_EXAMPLE_LIB_VERSIONS = {\n  \"a\": \"1\",\n}\n");
        let (s, e) = find_map(&src, TS_MAP).unwrap();
        let blk: String = src[s..e].iter().collect();
        assert_eq!(blk, "\n  \"a\": \"1\",");
        assert!(find_map(
            &chars("_TS_EXAMPLE_LIB_VERSIONS = { \"a\": \"1\" }"),
            TS_MAP
        )
        .is_none());
    }

    #[test]
    fn pairs_follow_python_findall() {
        let d = to_dict(&find_pairs(&chars(
            "\"a\" \"b\": \"c\", \"\": \"x\", \"k\":\"1\", \"k\" : \"2\"",
        )));
        assert_eq!(d, vec![("b".into(), "c".into()), ("k".into(), "2".into())]);
        // \s takes in U+001C..U+001F, as Python's does.
        let d = to_dict(&find_pairs(&chars("\"a\"\u{1c}:\u{a0}\"b\"")));
        assert_eq!(d, vec![("a".into(), "b".into())]);
    }

    #[test]
    fn join_restarts_at_an_absolute_part() {
        assert_eq!(py_join("ts", "a"), "ts/a");
        assert_eq!(py_join("ts/", "a"), "ts/a");
        assert_eq!(py_join("ts", "/etc"), "/etc");
        assert_eq!(py_join("", "a"), "a");
        assert_eq!(py_join("ts", ""), "ts/");
    }

    #[test]
    fn major_suffix_is_stripped_like_re_sub() {
        assert_eq!(strip_major("bootstrap/v2"), "bootstrap");
        assert_eq!(strip_major("bootstrap/v12"), "bootstrap");
        assert_eq!(strip_major("bootstrap/v"), "bootstrap/v");
        assert_eq!(strip_major("bootstrap/v2x"), "bootstrap/v2x");
        assert_eq!(strip_major("a/v2\n"), "a\n");
        assert_eq!(strip_major("iam"), "iam");
    }

    #[test]
    fn python_str_of_versions() {
        let j = |s: &str| serde_json::from_str::<PyJson>(s).unwrap().py_str();
        assert_eq!(j("\"1.2.3\""), "1.2.3");
        assert_eq!(j("null"), "None");
        assert_eq!(j("true"), "True");
        assert_eq!(j("12"), "12");
        assert_eq!(j("1.0"), "1.0");
        assert_eq!(j("1e20"), "1e+20");
        assert_eq!(j("0.00001"), "1e-05");
        assert_eq!(j("[1, \"a\", null]"), "[1, 'a', None]");
        assert_eq!(j("{\"b\": 1, \"a\": \"it's\"}"), "{'b': 1, 'a': \"it's\"}");
    }

    #[test]
    fn dicts_keep_first_position_last_value() {
        let v: PyJson = serde_json::from_str("{\"b\": 1, \"a\": 2, \"b\": 3}").unwrap();
        assert_eq!(
            v,
            PyJson::Dict(vec![
                ("b".into(), PyJson::Int(3)),
                ("a".into(), PyJson::Int(2))
            ])
        );
    }

    #[test]
    fn universal_newlines_translate() {
        assert_eq!(universal_newlines("a\r\nb\rc\n"), "a\nb\nc\n");
    }

    #[test]
    fn ljust_counts_characters() {
        assert_eq!(ljust("é", 3), "é  ");
        assert_eq!(ljust("abcd", 2), "abcd");
    }

    fn tree() -> (std::path::PathBuf, Paths) {
        let base = std::env::temp_dir().join(format!(
            "cvm-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let mk = |rel: &str, body: &str| {
            let p = base.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, body).unwrap();
        };
        mk("ts/bootstrap/package.json", "{\"version\":\"0.4.0\"}");
        mk("ts/network/package.json", "{\"version\":\"0.5.0\"}");
        mk(
            "go/bootstrap/.release-please-manifest.json",
            "{\"x\":\"2.1.4\"}",
        );
        mk(
            "example/package.json",
            "{\"dependencies\":{\"@vitruviansoftware/foundation-bootstrap\":\"workspace:*\",\"@vitruviansoftware/foundation-network\":\"workspace:^\"}}",
        );
        mk(
            "example/node_modules/x/package.json",
            "{\"dependencies\":{\"@vitruviansoftware/foundation-ghost\":\"workspace:*\"}}",
        );
        mk(
            "example/.hidden/package.json",
            "{\"dependencies\":{\"@vitruviansoftware/foundation-ghost\":\"workspace:*\"}}",
        );
        let s = |r: &str| base.join(r).to_string_lossy().into_owned();
        let p = Paths {
            sky: s("copy.bara.sky"),
            ts_root: s("ts"),
            go_root: s("go"),
            ts_example: s("example"),
        };
        (base, p)
    }

    #[test]
    fn in_sync_drift_and_fix() {
        let (base, p) = tree();
        fs::write(
            &p.sky,
            "_TS_EXAMPLE_LIB_VERSIONS = {\n  \"bootstrap\": \"0.4.0\",\n  \"network\": \"0.5.0\",\n}\n_GO_EXAMPLE_LIB_VERSIONS = {\n  \"bootstrap/v2\": \"2.1.4\",\n}\n",
        )
        .unwrap();
        let o = check(&p, false);
        assert_eq!(o.code, 0, "{:?}", o);
        assert_eq!(
            o.stdout,
            "check-version-maps: 2 ts + 1 go entries all match the repo.\n"
        );

        fs::write(
            &p.sky,
            "_TS_EXAMPLE_LIB_VERSIONS = {\n  \"bootstrap\": \"0.2.1\", # old\n}\n_GO_EXAMPLE_LIB_VERSIONS = {\n  \"bootstrap/v2\":   \"2.1.0\",\n  \"iam\": \"1\",\n}\n",
        )
        .unwrap();
        let o = check(&p, false);
        assert_eq!(o.code, 1);
        assert!(
            o.stderr
                .contains("ts  bootstrap                    map=0.2.1     repo=0.4.0\n"),
            "{}",
            o.stderr
        );
        assert!(o.stderr.contains("ABSENT from the map"));
        assert!(!o.stderr.contains("ghost"));
        assert!(o
            .stderr
            .contains("go  iam                          maps to a module with no manifest"));

        let o = check(&p, true);
        assert_eq!(o.code, 0);
        let fixed = fs::read_to_string(&p.sky).unwrap();
        assert_eq!(
            fixed,
            "_TS_EXAMPLE_LIB_VERSIONS = {\n  \"bootstrap\": \"0.4.0\", # old\n}\n_GO_EXAMPLE_LIB_VERSIONS = {\n  \"bootstrap/v2\": \"2.1.4\",\n  \"iam\": \"1\",\n}\n"
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn unparseable_is_exit_2() {
        let (base, p) = tree();
        fs::write(&p.sky, "nothing here\n").unwrap();
        let o = check(&p, false);
        assert_eq!(o.code, 2);
        assert_eq!(
            o.stderr,
            "check-version-maps: could not parse _TS_EXAMPLE_LIB_VERSIONS\n"
        );
        fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn unknown_argument_is_exit_2() {
        let o = run(&["--nope".to_string()]);
        assert_eq!(o.code, 2);
        assert_eq!(o.stderr, "check-version-maps: unknown argument --nope\n");
    }
}
