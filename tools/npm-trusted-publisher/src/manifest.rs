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

//! The `python3 -c` snippets the scripts read package.json with.

use crate::pyjson::{self, Py};

/// The line Python's traceback ends with for a failed `open(mf)`, e.g.
/// `FileNotFoundError: [Errno 2] No such file or directory: 'x'`.
pub fn os_error(e: &std::io::Error, path: &str) -> String {
    let errno = e.raw_os_error().unwrap_or(0);
    let class = match errno {
        2 => "FileNotFoundError",
        13 | 1 => "PermissionError",
        20 => "NotADirectoryError",
        21 => "IsADirectoryError",
        _ => "OSError",
    };
    format!(
        "{}: [Errno {}] {}: {}",
        class,
        errno,
        crate::sh::strerror(e),
        pyjson::str_repr(path)
    )
}

/// Python's `type(v).__name__`.
pub fn type_name(v: &Py) -> &'static str {
    match v {
        Py::None => "NoneType",
        Py::Bool(_) => "bool",
        Py::Int(_) => "int",
        Py::Float(_) => "float",
        Py::Str(_) => "str",
        Py::List(_) => "list",
        Py::Dict(_) => "dict",
    }
}

/// `d = json.load(open(mf))`, then a dict is required (every snippet calls
/// `d.get`). The error is the line Python's traceback would end with, as far
/// as it can be reproduced.
pub fn load_dict(mf: &str) -> Result<Py, String> {
    let bytes = std::fs::read(mf).map_err(|e| os_error(&e, mf))?;
    let text =
        String::from_utf8(bytes).map_err(|e| format!("UnicodeDecodeError: {}: {}", mf, e))?;
    let d =
        pyjson::loads(&text).map_err(|e| format!("json.decoder.JSONDecodeError: {}: {}", mf, e))?;
    if !d.is_dict() {
        return Err(format!(
            "AttributeError: '{}' object has no attribute 'get'",
            type_name(&d)
        ));
    }
    Ok(d)
}

/// `print(d.get("name",""), str(bool(d.get("private",False))).lower())`.
pub fn name_private_line(d: &Py) -> Vec<u8> {
    let name = d.get("name").map_or(String::new(), Py::py_str);
    let private = d.get("private").map_or(false, Py::truthy);
    format!("{} {}\n", name, if private { "true" } else { "false" }).into_bytes()
}

/// `print(json.load(open(mf))["name"])`.
pub fn name_of(d: &Py) -> String {
    d.get("name").map_or(String::new(), Py::py_str)
}

/// bootstrap.sh's `unresolvable_deps`: one `name -> spec (field)` line per
/// dependency a consumer could not resolve (pnpm-internal `catalog:` /
/// `workspace:`, or path-based `file:` / `link:`). Err is Python's
/// AttributeError for a dependency field that is a truthy non-object.
pub fn unresolvable_deps(d: &Py) -> Result<Vec<String>, String> {
    let mut bad = Vec::new();
    for field in ["dependencies", "peerDependencies", "optionalDependencies"] {
        let v = match d.get(field) {
            Some(v) if v.truthy() => v,
            _ => continue,
        };
        let items = match v {
            Py::Dict(items) => items,
            other => {
                return Err(format!(
                    "AttributeError: '{}' object has no attribute 'items'",
                    type_name(other)
                ))
            }
        };
        for (name, spec) in items {
            if let Py::Str(spec) = spec {
                let proto = spec.split(':').next().unwrap_or("");
                if ["catalog", "workspace", "file", "link"].contains(&proto) {
                    bad.push(format!("{} -> {} ({})", name, spec, field));
                }
            }
        }
    }
    Ok(bad)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn name_private_matches_python_print() {
        let d = pyjson::loads(r#"{"name":"@v/a","private":"false"}"#).unwrap();
        assert_eq!(name_private_line(&d), b"@v/a true\n");
        let d = pyjson::loads(r#"{"name":null}"#).unwrap();
        assert_eq!(name_private_line(&d), b"None false\n");
        let d = pyjson::loads(r#"{"private":0}"#).unwrap();
        assert_eq!(name_private_line(&d), b" false\n");
    }

    #[test]
    fn deps_in_file_order() {
        let d = pyjson::loads(r#"{"optionalDependencies":{"z":"link:../z"},"dependencies":{"b":"workspace:^1","a":"^1","c":"catalog:","n":1},"peerDependencies":0}"#).unwrap();
        assert_eq!(
            unresolvable_deps(&d).unwrap(),
            [
                "b -> workspace:^1 (dependencies)",
                "c -> catalog: (dependencies)",
                "z -> link:../z (optionalDependencies)"
            ]
        );
        let d = pyjson::loads(r#"{"dependencies":["x"]}"#).unwrap();
        assert_eq!(
            unresolvable_deps(&d).unwrap_err(),
            "AttributeError: 'list' object has no attribute 'items'"
        );
    }
}
