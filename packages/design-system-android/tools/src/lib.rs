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

//! gen_tokens: VitruvianTokens.kt from the web design system's tokens.json.
//!
//! The Rust port of the retired gen_tokens.py, which it matched byte for
//! byte (gen_tokens_lib_test and :tokens_are_current hold it there): the
//! same Kotlin, command line, help and usage errors, and, where the script
//! would die on a token tree it cannot read, the same exception at the same
//! place (only the traceback's frames differ, since the port has no Python
//! source to point at).
//!
//! The pieces, each a part of Python the script leans on:
//!   * `argparse` - Python 3.12's argparse, shared with the repository's
//!     other ports;
//!   * `pyjson` - `json.loads`, CPython's scanner and its error messages;
//!   * `value` - the decoded values and the operations the script applies;
//!   * `pystr`, `unicode_tables` - str semantics and Python's character data;
//!   * `pyerr` - exceptions and the traceback;
//!   * `fsio` - `Path.read_text` / `Path.write_text`;
//!   * `render` - the script's own logic.

pub mod argparse;
pub mod fsio;
pub mod pyerr;
pub mod pyjson;
pub mod pystr;
pub mod render;
pub mod unicode_tables;
pub mod value;

use argparse::{Kind, Opt, Parser};
use pyerr::Exc;

/// What argparse calls the program. Python takes it from `sys.argv[0]`,
/// which is always the script, however it is launched.
pub const PROG: &str = "gen_tokens.py";

pub fn parser() -> Parser {
    let value = |name: &'static str| Opt {
        strings: vec![match name {
            "tokens" => "--tokens",
            "header" => "--header",
            _ => "--out",
        }],
        dest: name,
        kind: Kind::Value,
        help: None,
        required: true,
    };
    Parser {
        prog: PROG.into(),
        description: None,
        opts: vec![Opt::help(), value("tokens"), value("header"), value("out")],
    }
}

/// gen_tokens.py's `main()` past argument parsing.
pub fn generate(tokens: &str, header: &str, out: &str) -> Result<(), Exc> {
    let tokens = pyjson::loads(&fsio::read_text(tokens)?)?;
    let header = fsio::read_text(header)?;
    let text = render::render(&tokens, &header)?;
    fsio::write_text(out, &text)
}

/// The whole program: the exit code, having written what the script writes.
pub fn run(args: &[String]) -> i32 {
    let p = parser();
    let values = match p.parse(args, &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let get = |dest: &str| values.value(dest).unwrap_or_default().to_string();
    match generate(&get("tokens"), &get("header"), &get("out")) {
        Ok(()) => 0,
        Err(e) => {
            eprint!("{}", e.traceback());
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> std::path::PathBuf {
        let dir = std::env::temp_dir().join(format!("gen_tokens_lib_test_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        dir.join(name)
    }

    #[test]
    fn generates_the_checked_in_tokens_before_formatting() {
        // The real tokens.json renders, and every colour the theme names
        // comes out as a Compose literal.
        let tokens = include_str!("../../../design-system/src/tokens.json");
        let tokens = pyjson::loads(&pystr::ps(tokens)).unwrap();
        let text = render::render(&tokens, &pystr::ps("// header\n")).unwrap();
        let text = pystr::backslashreplace(&text);
        assert!(text.starts_with("// header\n\n// GENERATED FILE - DO NOT EDIT.\n"));
        assert_eq!(
            text.matches(" = Color(0x").count(),
            2 * render::SEMANTIC_COLORS.len()
        );
        assert!(text.ends_with("public const val GLASS_BLUR_RADIUS: Float = 16f\n"));
    }

    #[test]
    fn missing_tokens_file_is_a_file_not_found() {
        let e = generate(
            "/definitely/not/here.json",
            "h",
            &tmp("o").to_string_lossy(),
        )
        .unwrap_err();
        assert_eq!(e.class, "FileNotFoundError");
    }

    #[test]
    fn unencodable_text_leaves_an_empty_file() {
        let out = tmp("out.kt");
        std::fs::write(&out, "old").unwrap();
        let e = fsio::write_text(&out.to_string_lossy(), &[0x61, 0xD800]).unwrap_err();
        assert_eq!(e.class, "UnicodeEncodeError");
        assert_eq!(std::fs::read(&out).unwrap(), b"");
    }

    #[test]
    fn usage_errors_exit_2() {
        let exit = parser().parse(&[], &|_, _| Ok(())).unwrap_err();
        assert_eq!(exit.code, 2);
        assert!(exit.stderr.ends_with(
            "gen_tokens.py: error: the following arguments are required: --tokens, --header, --out\n"
        ));
    }
}
