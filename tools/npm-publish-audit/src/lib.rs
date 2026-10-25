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

//! npm-publish-audit: check.sh in Rust.
//!
//! Compares every PUBLIC npm package in this repo against what is actually on
//! the registry, and fails if any is behind or would fail provenance
//! verification. See check.sh for why this exists; this port keeps its
//! behaviour exactly: the same manifests in the same order, the same lines on
//! the same streams, the same exit codes (0 all current, 1 something behind,
//! 2 setup error), and the same `npm view` calls.
//!
//! Where the script leans on bash or python3, the port reproduces what they
//! do rather than what they mean: `$(...)` drops trailing newlines, `read -r`
//! splits Python's printed line on whitespace (so a name with a space shifts
//! the fields, exactly as in the script), `printf '%-56s'` pads by bytes, and
//! values print as Python's `str()` would (see [`pyjson`]).
//!
//! Known divergences, none reachable from a well-formed manifest:
//! - a manifest that is not valid JSON (or not an object) is skipped, as in
//!   the script, but the stderr note is one line rather than a Python
//!   traceback (whose frames name the local Python's stdlib paths). A
//!   manifest that cannot be OPENED gets Python's exact traceback;
//! - a failed `cd` reports on stderr in this tool's words, not bash's;
//! - `npm view` gets an empty stdin; in the script it inherits the rest of
//!   the manifest list (a here-document), which real npm never reads;
//! - `sort` is byte order; the script's `sort` follows the locale's collation
//!   (identical under the C locale, which CI and Bazel tests use).

pub mod pyjson;
pub mod sh;

use pyjson::Py;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

/// Publishing roots, in the order the script searches them.
pub const SEARCH_DIRS: &[&str] = &[
    "packages/pulumi/library/ts/packages",
    "pulumi/library/ts/packages",
    "apps/mcp/slack",
    "mcp-slack",
    // The Vitruvian SDK's TypeScript kit, published from the vitruvian-sdk mirror.
    "packages/vitruvian-sdk/kits/typescript",
    "vitruvian-sdk/kits/typescript",
];

/// The fields `print(d.get("name",""), d.get("version",""), private)` puts
/// on one line, split back out the way `read -r name version private` does.
pub fn manifest_fields(d: &Py) -> (String, String, String) {
    let name = d.get("name").map(Py::py_str).unwrap_or_default();
    let version = d.get("version").map(Py::py_str).unwrap_or_default();
    let private = d.get("private").map(Py::truthy).unwrap_or(false);
    let line = format!(
        "{} {} {}",
        name,
        version,
        if private { "true" } else { "false" }
    );
    let f = sh::read_fields(&line, 3);
    (f[0].clone(), f[1].clone(), f[2].clone())
}

/// The script's first snippet: `print(r)` for a string `repository`,
/// `print(r.get("url") or "")` for an object, `""` otherwise.
pub fn repository_url(d: &Py) -> String {
    let s = match d.get("repository") {
        Some(Py::Str(s)) => s.clone(),
        Some(r @ Py::Dict(_)) => match r.get("url") {
            Some(u) if u.truthy() => u.py_str(),
            _ => String::new(),
        },
        _ => String::new(),
    };
    sh::strip_trailing_newlines(&s)
}

/// The second snippet: `r.get("directory") or ""` for an object, else `""`.
pub fn repository_directory(d: &Py) -> String {
    let s = match d.get("repository") {
        Some(r @ Py::Dict(_)) => match r.get("directory") {
            Some(v) if v.truthy() => v.py_str(),
            _ => String::new(),
        },
        _ => String::new(),
    };
    sh::strip_trailing_newlines(&s)
}

/// The `repository.directory` a manifest must declare, from the script's
/// `case "$mf"`; empty for "no requirement".
pub fn expected_directory(mf: &str) -> String {
    if mf.starts_with("packages/pulumi/library/ts/packages/")
        || mf.starts_with("pulumi/library/ts/packages/")
    {
        format!("ts/packages/{}", sh::basename(&sh::dirname(mf)))
    } else if mf.starts_with("packages/vitruvian-sdk/kits/typescript/")
        || mf.starts_with("vitruvian-sdk/kits/typescript/")
    {
        // The mirror's root is packages/vitruvian-sdk, so the kit is kits/typescript there.
        "kits/typescript".to_string()
    } else {
        String::new()
    }
}

/// Where the script `cd`s: BUILD_WORKSPACE_DIRECTORY, else the git toplevel,
/// else the current directory.
fn workspace_dir() -> String {
    if let Some(d) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        if !d.is_empty() {
            return d.to_string_lossy().into_owned();
        }
    }
    let git = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .stdin(Stdio::inherit())
        .stderr(Stdio::null())
        .output();
    if let Ok(o) = git {
        if o.status.success() {
            return sh::strip_trailing_newlines(&String::from_utf8_lossy(&o.stdout));
        }
    }
    std::env::current_dir()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|_| ".".to_string())
}

/// `"$NPM" view "$name" dist-tags.latest 2>/dev/null || true`, captured.
fn npm_view_latest(npm: &str, name: &str) -> String {
    match Command::new(npm)
        .args(["view", name, "dist-tags.latest"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    {
        Ok(o) => sh::strip_trailing_newlines(&String::from_utf8_lossy(&o.stdout)),
        Err(_) => String::new(),
    }
}

/// Runs the audit; returns the exit code.
pub fn run(out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let dir = workspace_dir();
    if let Err(e) = std::env::set_current_dir(&dir) {
        let _ = writeln!(err, "npm-publish-audit: cd: {}: {}", dir, sh::io_reason(&e));
        return 1;
    }
    let npm = match std::env::var("NPM") {
        Ok(v) if !v.is_empty() => v,
        _ => "npm".to_string(),
    };
    if !sh::command_exists(&npm) {
        let _ = writeln!(err, "npm-publish-audit: npm not on PATH");
        return 2;
    }

    let roots: Vec<&str> = SEARCH_DIRS
        .iter()
        .copied()
        .filter(|d| Path::new(d).is_dir())
        .collect();
    let manifests = sh::find_manifests(&roots);
    if manifests.is_empty() {
        let _ = writeln!(
            err,
            "npm-publish-audit: found no package manifests -- the layout moved"
        );
        return 2;
    }

    let mut prov_bad = 0;
    let mut behind = 0;
    let mut checked = 0;
    for mf in &manifests {
        // The script's python3 dies with a traceback and prints nothing, so
        // `read` sees an empty name and the manifest is skipped.
        let bytes = match std::fs::read(mf) {
            Ok(b) => b,
            Err(e) => {
                let _ = err.write_all(pyjson::open_error_traceback(&e, mf, 3).as_bytes());
                continue;
            }
        };
        let d = match String::from_utf8(bytes)
            .map_err(|e| e.to_string())
            .and_then(|t| pyjson::loads(&t))
        {
            Ok(d) if d.is_dict() => d,
            Ok(_) => {
                let _ = writeln!(err, "npm-publish-audit: {}: not a JSON object; skipped", mf);
                continue;
            }
            Err(e) => {
                let _ = writeln!(err, "npm-publish-audit: {}: {}; skipped", mf, e);
                continue;
            }
        };
        let (name, version, private) = manifest_fields(&d);
        if name.is_empty() || private != "false" || version.is_empty() {
            continue;
        }
        checked += 1;

        let url = repository_url(&d);
        if url.is_empty() {
            let _ = out.write_all(
                format!(
                    "  {} NO repository.url -- provenance publish will be REJECTED\n",
                    sh::pad(mf, 56)
                )
                .as_bytes(),
            );
            prov_bad += 1;
        } else {
            let want = expected_directory(mf);
            if !want.is_empty() {
                let got = repository_directory(&d);
                if got != want {
                    let shown = if got.is_empty() {
                        "<none>"
                    } else {
                        got.as_str()
                    };
                    let _ = out.write_all(
                        format!(
                            "  {} repository.directory={} want={}\n",
                            sh::pad(mf, 56),
                            shown,
                            want
                        )
                        .as_bytes(),
                    );
                    prov_bad += 1;
                }
            }
        }

        let _ = out.flush();
        let live = npm_view_latest(&npm, &name);
        if live.is_empty() {
            let _ = out.write_all(
                format!(
                    "  {} repo={} registry=NOT PUBLISHED\n",
                    sh::pad(&name, 56),
                    sh::pad(&version, 10)
                )
                .as_bytes(),
            );
            behind += 1;
        } else if live != version {
            let _ = out.write_all(
                format!(
                    "  {} repo={} registry={}  BEHIND\n",
                    sh::pad(&name, 56),
                    sh::pad(&version, 10),
                    live
                )
                .as_bytes(),
            );
            behind += 1;
        }
    }
    let _ = out.flush();

    if prov_bad > 0 {
        let _ = writeln!(
            err,
            "npm-publish-audit: {} package(s) have a repository field that will fail provenance verification.",
            prov_bad
        );
        let _ = writeln!(
            err,
            "  Trusted publishing signs each publish; npm rejects it with E422 when this does not match."
        );
        return 1;
    }
    if behind > 0 {
        let _ = writeln!(
            err,
            "npm-publish-audit: {} of {} package(s) are not on the registry at their repo version.",
            behind, checked
        );
        let _ = writeln!(
            err,
            "  A release that reported success but published nothing looks exactly like this."
        );
        let _ = writeln!(err, "  See docs/engineering/npm-trusted-publishing.md.");
        return 1;
    }
    let _ = writeln!(
        out,
        "npm-publish-audit: all {} published package(s) match the registry.",
        checked
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(j: &str) -> Py {
        pyjson::loads(j).unwrap()
    }

    #[test]
    fn fields_follow_read_splitting() {
        assert_eq!(
            manifest_fields(&d(r#"{"name":"@v/a","version":"1.0.0"}"#)),
            ("@v/a".into(), "1.0.0".into(), "false".into())
        );
        // A name with a space shifts every field, as `read` does.
        assert_eq!(
            manifest_fields(&d(r#"{"name":"a b","version":"1"}"#)),
            ("a".into(), "b".into(), "1 false".into())
        );
        // An empty name leaves the version in the name slot.
        assert_eq!(
            manifest_fields(&d(r#"{"version":"1"}"#)),
            ("1".into(), "false".into(), "".into())
        );
        assert_eq!(
            manifest_fields(&d(r#"{"name":null,"version":1.0,"private":"false"}"#)),
            ("None".into(), "1.0".into(), "true".into())
        );
    }

    #[test]
    fn repository_fields() {
        assert_eq!(repository_url(&d(r#"{"repository":"git+x"}"#)), "git+x");
        assert_eq!(repository_url(&d(r#"{"repository":{"url":""}}"#)), "");
        assert_eq!(repository_url(&d(r#"{"repository":{"url":7}}"#)), "7");
        assert_eq!(repository_url(&d(r#"{"repository":["x"]}"#)), "");
        assert_eq!(repository_url(&d(r#"{"repository":"a\n\n"}"#)), "a");
        assert_eq!(repository_directory(&d(r#"{"repository":"x"}"#)), "");
        assert_eq!(
            repository_directory(&d(r#"{"repository":{"directory":"ts/packages/a"}}"#)),
            "ts/packages/a"
        );
        assert_eq!(
            repository_directory(&d(r#"{"repository":{"directory":0}}"#)),
            ""
        );
    }

    #[test]
    fn expected_directories() {
        assert_eq!(
            expected_directory("pulumi/library/ts/packages/a/package.json"),
            "ts/packages/a"
        );
        assert_eq!(
            expected_directory("packages/pulumi/library/ts/packages/a/b/package.json"),
            "ts/packages/b"
        );
        assert_eq!(
            expected_directory("vitruvian-sdk/kits/typescript/package.json"),
            "kits/typescript"
        );
        assert_eq!(expected_directory("mcp-slack/package.json"), "");
    }
}
