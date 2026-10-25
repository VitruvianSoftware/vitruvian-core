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

//! The command line, parsed the way Go's flag package parses it for
//! main.go's FlagSet("orchestrate", ExitOnError): -flag, --flag, -flag=v and
//! -flag v; "--" or the first non-flag argument ends the flags; -h/-help
//! prints usage and exits 0; anything else wrong prints the message and the
//! usage to stderr and exits 2.

use crate::gostd::quote;

pub struct Flags {
    pub out: String,
    pub bazel: String,
}

pub enum Outcome {
    Run(Flags),
    /// Print this to stderr and exit with the code.
    Exit(String, i32),
}

const OUT_USAGE: &str =
    "where to write the delivery manifest (relative paths resolve against the workspace root)";
const BAZEL_USAGE: &str = "the bazel binary used for discovery (env ORCHESTRATE_BAZEL)";

/// The FlagSet's default usage text.
pub fn usage(bazel_default: &str, out_default: &str) -> String {
    let mut b = String::from("Usage of orchestrate:\n");
    for (name, help, def) in [
        ("bazel", BAZEL_USAGE, bazel_default),
        ("out", OUT_USAGE, out_default),
    ] {
        b.push_str(&format!("  -{} string\n    \t{}", name, help));
        if !def.is_empty() {
            b.push_str(&format!(" (default {})", quote(def)));
        }
        b.push('\n');
    }
    b
}

pub fn parse(args: &[String], bazel_default: &str, out_default: &str) -> Outcome {
    let mut f = Flags {
        out: out_default.to_string(),
        bazel: bazel_default.to_string(),
    };
    let fail =
        |msg: String| Outcome::Exit(format!("{}\n{}", msg, usage(bazel_default, out_default)), 2);
    let mut i = 0;
    while i < args.len() {
        let s = &args[i];
        if s.len() < 2 || !s.starts_with('-') {
            break;
        }
        let mut minuses = 1;
        if s.as_bytes()[1] == b'-' {
            minuses = 2;
            if s.len() == 2 {
                break;
            }
        }
        let mut name = &s[minuses..];
        if name.is_empty() || name.starts_with('-') || name.starts_with('=') {
            return fail(format!("bad flag syntax: {}", s));
        }
        i += 1;
        let mut value = None;
        if let Some(eq) = name[1..].find('=') {
            value = Some(name[eq + 2..].to_string());
            name = &name[..eq + 1];
        }
        let slot = match name {
            "out" => &mut f.out,
            "bazel" => &mut f.bazel,
            "help" | "h" => return Outcome::Exit(usage(bazel_default, out_default), 0),
            _ => return fail(format!("flag provided but not defined: -{}", name)),
        };
        let value = match value {
            Some(v) => v,
            None if i < args.len() => {
                i += 1;
                args[i - 1].clone()
            }
            None => return fail(format!("flag needs an argument: -{}", name)),
        };
        *slot = value;
    }
    Outcome::Run(f)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Result<(String, String), (String, i32)> {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        match parse(&args, "bazel", "delivery-manifest.json") {
            Outcome::Run(f) => Ok((f.out, f.bazel)),
            Outcome::Exit(m, c) => Err((m, c)),
        }
    }

    #[test]
    fn go_flag_rules() {
        assert_eq!(run(&["--out", "x"]).unwrap().0, "x");
        assert_eq!(
            run(&["-out=y", "-bazel=b"]).unwrap(),
            ("y".into(), "b".into())
        );
        assert_eq!(run(&["--", "-out=z"]).unwrap().0, "delivery-manifest.json");
        assert_eq!(run(&["pos", "-out=z"]).unwrap().0, "delivery-manifest.json");
        assert_eq!(run(&["-h"]).unwrap_err().1, 0);
        let (m, c) = run(&["-nope"]).unwrap_err();
        assert_eq!(c, 2);
        assert!(m.starts_with(
            "flag provided but not defined: -nope\nUsage of orchestrate:\n  -bazel string\n    \t"
        ));
        assert!(run(&["-out"])
            .unwrap_err()
            .0
            .starts_with("flag needs an argument: -out\n"));
        assert!(run(&["---x"])
            .unwrap_err()
            .0
            .starts_with("bad flag syntax: ---x\n"));
    }
}
