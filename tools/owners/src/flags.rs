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
//! non-flag or `--`, and the same usage text and exit codes (0 for -h, 2 for
//! a bad flag).

#[derive(Debug, Default, PartialEq)]
pub struct Flags {
    pub out: String,
    pub check: bool,
    pub coverage_check: bool,
    pub validate_only: bool,
    pub root: String,
}

#[derive(Debug, PartialEq)]
pub enum FlagError {
    /// -h / -help: usage is printed, exit 0.
    Help,
    /// A bad flag: the message, then usage, exit 2.
    Bad(String),
}

const DEFS: &[(&str, bool, &str)] = &[
    (
        "check",
        true,
        "Check that .github/CODEOWNERS matches compiled output",
    ),
    (
        "coverage-check",
        true,
        "Verify OWNERS coverage conformance across all subtrees",
    ),
    ("out", false, "Output path for compiled CODEOWNERS file"),
    (
        "root",
        false,
        "Repository root directory (defaults to current dir or workspace root)",
    ),
    (
        "validate-only",
        true,
        "Validate syntax of all OWNERS files without compiling",
    ),
];

/// What `flag.Usage` prints, sorted by flag name as `PrintDefaults` sorts.
pub fn usage(argv0: &str) -> String {
    let mut s = format!("Usage of {argv0}:\n");
    for (name, is_bool, help) in DEFS {
        s.push_str(&format!("  -{name}"));
        if !is_bool {
            s.push_str(" string");
        }
        s.push_str("\n    \t");
        s.push_str(help);
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
        let Some((_, is_bool, _)) = DEFS.iter().find(|(n, _, _)| *n == name) else {
            if name == "help" || name == "h" {
                return Err(FlagError::Help);
            }
            return Err(FlagError::Bad(format!(
                "flag provided but not defined: -{name}"
            )));
        };
        if *is_bool {
            let v = match value {
                Some(v) => parse_bool(v).ok_or_else(|| {
                    FlagError::Bad(format!(
                        "invalid boolean value {} for -{name}: parse error",
                        crate::gostr::quote(v)
                    ))
                })?,
                None => true,
            };
            match name {
                "check" => f.check = v,
                "coverage-check" => f.coverage_check = v,
                _ => f.validate_only = v,
            }
        } else {
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
            if name == "out" {
                f.out = v;
            } else {
                f.root = v;
            }
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
        let f = p(&["--root", "/r", "-check", "--out=x"]).unwrap();
        assert_eq!(
            (f.root.as_str(), f.check, f.out.as_str()),
            ("/r", true, "x")
        );
        assert!(!p(&["-check=false"]).unwrap().check);
        assert!(!p(&["pos", "-check"]).unwrap().check);
        assert!(!p(&["--", "-check"]).unwrap().check);
        assert_eq!(p(&["-h"]), Err(FlagError::Help));
        assert_eq!(
            p(&["-x"]),
            Err(FlagError::Bad("flag provided but not defined: -x".into()))
        );
        assert_eq!(
            p(&["---x"]),
            Err(FlagError::Bad("bad flag syntax: ---x".into()))
        );
        assert_eq!(
            p(&["-root"]),
            Err(FlagError::Bad("flag needs an argument: -root".into()))
        );
        assert_eq!(
            p(&["-check=maybe"]),
            Err(FlagError::Bad(
                "invalid boolean value \"maybe\" for -check: parse error".into()
            ))
        );
    }

    #[test]
    fn usage_text() {
        assert!(usage("o").starts_with("Usage of o:\n  -check\n    \tCheck that"));
        assert!(usage("o").contains("  -out string\n    \tOutput path"));
    }
}
