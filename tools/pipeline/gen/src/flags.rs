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

//! Go's `flag` package as the Go tool used it: `-x` and `--x`, `-x=v`, a
//! string flag taking the next argument, parsing that stops at the first
//! non-flag or `--`, the same usage text and exit codes (0 for -h, 2 for a
//! bad flag).

use crate::gostr::quote;

#[derive(Debug, PartialEq)]
pub struct Flags {
    pub units_dir: String,
    pub format: String,
    pub tier: String,
    pub persona: String,
    pub output_file: String,
    pub check: bool,
    pub repo_root: String,
}

impl Default for Flags {
    fn default() -> Self {
        Flags {
            units_dir: String::new(),
            format: "matrix".into(),
            tier: "all".into(),
            persona: "all".into(),
            output_file: String::new(),
            check: false,
            repo_root: String::new(),
        }
    }
}

#[derive(Debug, PartialEq)]
pub enum FlagError {
    /// -h / -help: usage is printed, exit 0.
    Help,
    /// A bad flag: the message, then usage, exit 2.
    Bad(String),
}

/// (name, is_bool, default shown in usage, help), sorted by name as Go's
/// `PrintDefaults` sorts.
const DEFS: &[(&str, bool, &str, &str)] = &[
    (
        "check",
        true,
        "",
        "Verify output-file matches generated output without writing",
    ),
    (
        "format",
        false,
        "matrix",
        "Output format: matrix, workflow, json, dag",
    ),
    ("output-file", false, "", "Target file to write or check"),
    (
        "persona",
        false,
        "all",
        "Persona filter: frontend, backend, infra, platform, security, docs, all",
    ),
    ("repo-root", false, "", "Path to repository workspace root"),
    ("tier", false, "all", "Tier filter: L0, L1, L2, L3, all"),
    (
        "units-dir",
        false,
        "",
        "Directory containing .pipeline.json files",
    ),
];

/// What `flag.Usage` prints.
pub fn usage(argv0: &str) -> String {
    let mut s = format!("Usage of {argv0}:\n");
    for (name, is_bool, default, help) in DEFS {
        s.push_str(&format!("  -{name}"));
        if !is_bool {
            s.push_str(" string");
        }
        s.push_str("\n    \t");
        s.push_str(help);
        if !default.is_empty() {
            s.push_str(&format!(" (default {})", quote(default)));
        }
        s.push('\n');
    }
    s
}

fn parse_bool(v: &str) -> Option<bool> {
    match v {
        "1" | "t" | "T" | "TRUE" | "true" | "True" => Some(true),
        "0" | "f" | "F" | "FALSE" | "false" | "False" => Some(false),
        _ => None,
    }
}

pub fn parse(args: &[String]) -> Result<Flags, FlagError> {
    let mut f = Flags::default();
    let mut i = 0;
    while i < args.len() {
        let s = &args[i];
        if s.len() < 2 || !s.starts_with('-') {
            break;
        }
        let mut num_minuses = 1;
        if s.as_bytes()[1] == b'-' {
            num_minuses = 2;
            if s.len() == 2 {
                break;
            }
        }
        let name_full = &s[num_minuses..];
        if name_full.is_empty() || name_full.starts_with('-') || name_full.starts_with('=') {
            return Err(FlagError::Bad(format!("bad flag syntax: {s}")));
        }
        i += 1;
        let (name, value) = match name_full.find('=') {
            Some(eq) => (&name_full[..eq], Some(&name_full[eq + 1..])),
            None => (name_full, None),
        };
        let Some((_, is_bool, _, _)) = DEFS.iter().find(|(n, _, _, _)| *n == name) else {
            if name == "help" || name == "h" {
                return Err(FlagError::Help);
            }
            return Err(FlagError::Bad(format!(
                "flag provided but not defined: -{name}"
            )));
        };
        if *is_bool {
            f.check = match value {
                Some(v) => parse_bool(v).ok_or_else(|| {
                    FlagError::Bad(format!(
                        "invalid boolean value {} for -{name}: parse error",
                        quote(v)
                    ))
                })?,
                None => true,
            };
            continue;
        }
        let v = match value {
            Some(v) => v.to_string(),
            None => {
                if i >= args.len() {
                    return Err(FlagError::Bad(format!("flag needs an argument: -{name}")));
                }
                i += 1;
                args[i - 1].clone()
            }
        };
        match name {
            "units-dir" => f.units_dir = v,
            "format" => f.format = v,
            "tier" => f.tier = v,
            "persona" => f.persona = v,
            "output-file" => f.output_file = v,
            _ => f.repo_root = v,
        }
    }
    Ok(f)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(a: &[&str]) -> Result<Flags, FlagError> {
        parse(&a.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }

    #[test]
    fn go_flag_rules() {
        let f = p(&["--units-dir", "/u", "-check", "--format=dag"]).unwrap();
        assert_eq!(
            (f.units_dir.as_str(), f.check, f.format.as_str()),
            ("/u", true, "dag")
        );
        assert!(!p(&["-check=false"]).unwrap().check);
        assert!(!p(&["pos", "-check"]).unwrap().check);
        assert_eq!(p(&["-h"]), Err(FlagError::Help));
        assert_eq!(
            p(&["-x"]),
            Err(FlagError::Bad("flag provided but not defined: -x".into()))
        );
        assert_eq!(
            p(&["-tier"]),
            Err(FlagError::Bad("flag needs an argument: -tier".into()))
        );
    }

    #[test]
    fn usage_text() {
        let u = usage("g");
        assert!(u.starts_with("Usage of g:\n  -check\n    \tVerify"));
        assert!(u.contains("  -format string\n    \tOutput format: matrix, workflow, json, dag (default \"matrix\")\n"));
    }
}
