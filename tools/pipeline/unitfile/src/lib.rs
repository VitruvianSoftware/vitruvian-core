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

//! //tools/pipeline/unitfile in Rust: reads pipeline_unit() declarations
//! straight out of BUILD files, without running Bazel.
//!
//! Two tools need the same answer: the presubmit planner
//! (//tools/pipeline/plan) decides which units a change affects, and
//! //tools/pipeline/verifiedrun runs them. One reader, used by both, cannot
//! drift. The Go package (unitfile.go, scan.go) stays for the Go workflow
//! generator (//tools/pipeline/gen); this crate gives the same units and the
//! same errors, word for word.
//!
//! The rule it holds to: a unit is either read completely or it is an error
//! that names the file and the unit. It never returns a unit with attributes
//! quietly missing.
//!
//! [`gocompat`] holds what the Rust ports of the Go pipeline tools need to
//! behave like the Go originals: `%q` quoting, path cleaning, Go's flag
//! parser, `os/exec` errors and `encoding/json`.

use std::collections::BTreeMap;
use std::fs;
use std::io::Read;

pub mod gocompat;
mod scan;

use gocompat::oserr;
use gocompat::path;
use gocompat::quote::quote;
use scan::Value;

/// Defaults for attributes a declaration leaves out.
pub const DEFAULT_TIER: &str = "L1";
pub const DEFAULT_RUNNER: &str = "ubuntu-26.04";
pub const DEFAULT_PERSONA: &str = "all";
pub const DEFAULT_TIMEOUT_MINUTES: i64 = 20;

/// One pipeline_unit() declaration as written in a BUILD file.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Unit {
    pub name: String,
    pub package: String,
    /// Absolute labels: ":x" in package p is "//p:x".
    pub test_targets: Vec<String>,
    pub tier: String,
    pub runner: String,
    pub persona: String,
    pub timeout_minutes: i64,
    pub depends_on: Vec<String>,
    pub needs_emulator: bool,
    /// Empty when the declaration has none (Go's nil map).
    pub env: BTreeMap<String, String>,
    pub artifacts: BTreeMap<String, String>,
    pub build_flags: Vec<String>,
    /// Where the call starts in its BUILD file.
    pub line: usize,
}

/// Reads every pipeline_unit() call in the text of one BUILD file. `pkg` is
/// the file's package, "" for the repository root.
pub fn parse(content: &str, pkg: &str) -> Result<Vec<Unit>, String> {
    parse_bytes(content.as_bytes(), pkg)
}

/// [`parse`] over the raw bytes of a file.
pub fn parse_bytes(content: &[u8], pkg: &str) -> Result<Vec<Unit>, String> {
    // Most BUILD files declare no unit; do not scan those at all.
    if !contains(content, b"pipeline_unit") {
        return Ok(Vec::new());
    }
    let calls = scan::find_calls(content, "pipeline_unit")?;
    calls.iter().map(|c| unit_from_call(c, pkg)).collect()
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

fn unit_from_call(c: &scan::Call, pkg: &str) -> Result<Unit, String> {
    let name = match c.args.get("name") {
        Some(Value::Str(s)) if !s.is_empty() => s.clone(),
        _ => {
            return Err(format!(
                "line {}: pipeline_unit(...): name must be a quoted string",
                c.line
            ))
        }
    };
    let mut u = Unit {
        name,
        package: pkg.to_string(),
        tier: DEFAULT_TIER.to_string(),
        runner: DEFAULT_RUNNER.to_string(),
        persona: DEFAULT_PERSONA.to_string(),
        timeout_minutes: DEFAULT_TIMEOUT_MINUTES,
        line: c.line,
        ..Unit::default()
    };
    let fail = |name: &str, msg: String| -> Result<Unit, String> {
        Err(format!(
            "line {}: pipeline_unit(name = {}): {msg}",
            c.line,
            quote(name)
        ))
    };

    // Go walks these attributes in map order, so which of two bad ones it
    // names first is not fixed; this names them in the order listed.
    for attr in ["tier", "runner", "persona"] {
        let Some(v) = c.args.get(attr) else { continue };
        let Value::Str(s) = v else {
            return fail(&u.name, format!("{attr} must be a quoted string"));
        };
        match attr {
            "tier" => u.tier = s.clone(),
            "runner" => u.runner = s.clone(),
            _ => u.persona = s.clone(),
        }
    }

    if let Some(v) = c.args.get("timeout_minutes") {
        let Value::Int(n) = v else {
            return fail(&u.name, "timeout_minutes must be a whole number".into());
        };
        u.timeout_minutes = *n;
    }

    if let Some(v) = c.args.get("needs_emulator") {
        let Value::Bool(b) = v else {
            return fail(&u.name, "needs_emulator must be True or False".into());
        };
        u.needs_emulator = *b;
    }

    for attr in ["test_targets", "depends_on", "build_flags"] {
        let Some(v) = c.args.get(attr) else { continue };
        let Value::List(items) = v else {
            return fail(&u.name, format!("{attr} must be a list written out in the call, [\"...\", ...]; this reader does not run Bazel, so it cannot follow a name, glob() or select()"));
        };
        let mut out = Vec::new();
        for item in items {
            let Value::Str(s) = item else {
                return fail(
                    &u.name,
                    format!("every entry of {attr} must be a quoted string"),
                );
            };
            out.push(s.clone());
        }
        match attr {
            "test_targets" => u.test_targets = out,
            "depends_on" => u.depends_on = out,
            _ => u.build_flags = out,
        }
    }

    for attr in ["env", "artifacts"] {
        let Some(v) = c.args.get(attr) else { continue };
        let Value::Dict(pairs) = v else {
            return fail(
                &u.name,
                format!("{attr} must be a dict written out in the call, {{\"...\": \"...\"}}"),
            );
        };
        let mut out = BTreeMap::new();
        for (k, val) in pairs {
            let (Value::Str(k), Value::Str(val)) = (k, val) else {
                return fail(
                    &u.name,
                    format!("every key and value of {attr} must be a quoted string"),
                );
            };
            out.insert(k.clone(), val.clone());
        }
        if attr == "env" {
            u.env = out;
        } else {
            u.artifacts = out;
        }
    }

    // The macro refuses a unit with no targets, so one that reads as empty
    // here was misread or is about to fail in Bazel. Either way it must not
    // reach the planner as "nothing to run".
    if u.test_targets.is_empty() {
        return fail(&u.name, "test_targets is missing or empty".into());
    }
    for t in u.test_targets.iter_mut() {
        if t.starts_with(':') {
            *t = format!("//{pkg}{t}");
        }
    }
    Ok(u)
}

/// `os.ReadFile`, with Go's error wording.
pub fn read_file(p: &str) -> Result<Vec<u8>, (std::io::Error, String)> {
    let mut f = fs::File::open(p).map_err(|e| {
        let msg = oserr::path_err("open", p, &e);
        (e, msg)
    })?;
    let mut b = Vec::new();
    f.read_to_end(&mut b).map_err(|e| {
        let msg = oserr::path_err("read", p, &e);
        (e, msg)
    })?;
    Ok(b)
}

/// Reads every BUILD and BUILD.bazel file under root and returns the units
/// they declare, sorted by name. Every unreadable declaration is reported,
/// each with its file, and so is a name declared twice.
pub fn discover(root: &str) -> Result<Vec<Unit>, String> {
    let mut st = Discovery {
        root: root.to_string(),
        units: Vec::new(),
        errs: Vec::new(),
        declared_in: BTreeMap::new(),
    };
    // filepath.Walk: a root that cannot be read is no units, not an error.
    if let Ok(meta) = fs::symlink_metadata(root) {
        let name = path::base(root);
        st.walk(root, &name, meta.is_dir());
    }
    if !st.errs.is_empty() {
        return Err(format!(
            "cannot read every pipeline unit:\n{}",
            st.errs.join("\n")
        ));
    }
    st.units.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(st.units)
}

struct Discovery {
    root: String,
    units: Vec<Unit>,
    errs: Vec<String>,
    declared_in: BTreeMap<String, String>,
}

impl Discovery {
    fn walk(&mut self, p: &str, name: &str, is_dir: bool) {
        if !is_dir {
            self.visit_file(p, name);
            return;
        }
        let Ok(rd) = fs::read_dir(p) else { return };
        if name == ".git" || name == "node_modules" || name == ".claude" {
            return;
        }
        // Bazel's output links at the top of the workspace. A real directory
        // deeper down may carry the prefix (tools/bazel-cache).
        if name.starts_with("bazel-") && path::dir(p) == self.root {
            return;
        }
        let mut names: Vec<String> = rd
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        for n in names {
            let child = path::join(&[p, &n]);
            if let Ok(m) = fs::symlink_metadata(&child) {
                self.walk(&child, &n, m.is_dir());
            }
        }
    }

    fn visit_file(&mut self, p: &str, name: &str) {
        if name != "BUILD" && name != "BUILD.bazel" {
            return;
        }
        let Ok(rel) = path::rel(&self.root, p) else {
            return;
        };
        let pkg = match rel.rfind('/') {
            Some(i) => rel[..i].to_string(),
            None => String::new(),
        };
        let content = match read_file(p) {
            Ok(c) => c,
            Err((_, msg)) => {
                // A BUILD file that cannot be read may hold a unit.
                self.errs.push(format!("{rel}: {msg}"));
                return;
            }
        };
        let parsed = match parse_bytes(&content, &pkg) {
            Ok(u) => u,
            Err(e) => {
                self.errs.push(format!("{rel}: {e}"));
                return;
            }
        };
        for u in parsed {
            if let Some(first) = self.declared_in.get(&u.name) {
                self.errs.push(format!(
                    "{rel}: line {}: pipeline_unit(name = {}) is already declared in {first}; unit names must be unique across the repository",
                    u.line,
                    quote(&u.name)
                ));
                continue;
            }
            self.declared_in.insert(u.name.clone(), rel.clone());
            self.units.push(u);
        }
    }
}

#[cfg(test)]
mod tests;
