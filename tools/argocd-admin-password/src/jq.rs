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

//! The three jq programs sync.sh runs, implemented as thin filters over
//! `vitruvian_jq` (matching jq 1.8.2):
//!
//!   jq -r .status                                         (bw status)
//!   jq -c --arg n "$ITEM" '[.[] | select(.name==$n)][0] // empty'
//!   jq -r '.login.password // empty'

pub use vitruvian_jq::{
    compact as dump_compact, dump_string, dump_trunc, one, pretty, raw, run, Produced, RunOptions,
    RunResult as Run, Value as Jv,
};

/// `.status`.
pub fn status(v: &Jv) -> Produced {
    one(v.index("status"))
}

/// `[.[] | select(.name==$n)][0] // empty`.
pub fn select_item(n: &str) -> impl Fn(&Jv) -> Produced + '_ {
    move |v: &Jv| {
        let items = match v.iterate_redacted() {
            Ok(xs) => xs,
            Err(e) => return (Vec::new(), Some(e)),
        };
        let mut first = None;
        for x in items {
            let name = match x.index("name") {
                Ok(v) => v,
                Err(e) => return (Vec::new(), Some(e)),
            };
            if name.is_str(n) && first.is_none() {
                first = Some(x);
            }
        }
        match first {
            Some(x) if x.truthy() => (vec![x], None),
            _ => (Vec::new(), None),
        }
    }
}

/// `.login.password // empty`.
pub fn password(v: &Jv) -> Produced {
    match v.index("login").and_then(|l| l.index("password")) {
        Ok(p) if p.truthy() => (vec![p], None),
        Ok(_) => (Vec::new(), None),
        Err(e) => (Vec::new(), Some(e)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_status(input: &str) -> Run {
        run(input.as_bytes(), RunOptions::raw(), status)
    }

    #[test]
    fn status_of_a_stream() {
        let r = run_status("{\"status\":\"unlocked\"} {\"status\":\"x\"}");
        assert_eq!(r.stdout_string(), "unlocked\nx\n");
        assert_eq!(r.status, 0);
        let r = run_status("{\"a\":1}\n[1]\n");
        assert_eq!(r.stdout_string(), "null\n");
        assert_eq!(
            r.stderr_string(),
            "jq: error (at <stdin>:2): Cannot index array with string (\"status\")\n"
        );
        assert_eq!(r.status, 5);
        assert_eq!(run_status("").stdout_string(), "");
    }

    #[test]
    fn jq_18_exit_status_follows_last_value() {
        let r = run_status("[1] {\"status\":\"unlocked\"}");
        assert_eq!(r.stdout_string(), "unlocked\n");
        assert_eq!(r.status, 0);
        let r = run_status("{\"status\":\"unlocked\"} [1]");
        assert_eq!(r.stdout_string(), "unlocked\n");
        assert_eq!(r.status, 5);
    }

    #[test]
    fn error_line_numbers_count_lines_fed() {
        let n = |s: &str| run_status(s).stderr_string();
        assert!(n("\"s\"\n").contains("<stdin>:1"));
        assert!(n("\n\n\"s\"").contains("<stdin>:2"));
        assert!(n("\"s\"\n\n\n").contains("<stdin>:1"));
        assert!(n("\"s\" \n").contains("<stdin>:1"));
        assert!(n("[1,\n2]\n").contains("<stdin>:2"));
        assert!(n("true").contains("<stdin>:0"));
    }

    #[test]
    fn selecting_the_item() {
        let f = select_item("argocd admin (dev-local)");
        let r = run(
            b"[{\"name\":\"x\"},null,{\"name\":\"argocd admin (dev-local)\",\"z\":1,\"b\":2},{\"name\":\"argocd admin (dev-local)\"}]",
            RunOptions::compact(),
            &f,
        );
        assert_eq!(
            r.stdout_string(),
            "{\"name\":\"argocd admin (dev-local)\",\"z\":1,\"b\":2}\n"
        );
        let r = run(b"[1]", RunOptions::compact(), &f);
        assert_eq!(
            r.stderr_string(),
            "jq: error (at <stdin>:0): Cannot index number with string (\"name\")\n"
        );
        let r = run(b"null", RunOptions::compact(), &f);
        assert_eq!(
            r.stderr_string(),
            "jq: error (at <stdin>:0): Cannot iterate over null\n"
        );
        let r = run(
            b"\"aaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
            RunOptions::compact(),
            &f,
        );
        assert_eq!(
            r.stderr_string(),
            "jq: error (at <stdin>:0): Cannot iterate over string\n"
        );
    }

    #[test]
    fn passwords() {
        let r = run(
            b"{\"login\":{\"password\":\"p\"}}\n{\"login\":null}\n{\"login\":{\"password\":false}}\n",
            RunOptions::raw(),
            password,
        );
        assert_eq!(r.stdout_string(), "p\n");
        let r = run(b"{\"login\":\"x\"}\n", RunOptions::raw(), password);
        assert_eq!(
            r.stderr_string(),
            "jq: error (at <stdin>:1): Cannot index string with string (\"password\")\n"
        );
        let r = run(
            b"{\"login\":{\"password\":{\"b\":1,\"a\":[1,2]}}}",
            RunOptions::raw(),
            password,
        );
        assert_eq!(
            r.stdout_string(),
            "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}\n"
        );
    }

    #[test]
    fn strings_escape_as_jq() {
        assert_eq!(
            dump_string("a\u{7f}\u{1}é/\"\\\n"),
            "\"a\\u007f\\u0001é/\\\"\\\\\\n\""
        );
    }

    #[test]
    fn jq_errors_never_leak_secret_values() {
        let bare_url = br#""postgres://user:SECRET-MARKER-123@host/db""#.as_slice();
        let bare_short = br#""SECRET-MARKER-123""#.as_slice();
        let num = b"42".as_slice();
        let null = b"null".as_slice();
        let arr_url = br#"["postgres://user:SECRET-MARKER-123@host/db"]"#.as_slice();
        let nested_obj = br#"{"x":"postgres://user:SECRET-MARKER-123@host/db"}"#.as_slice();
        let nested_login = br#"{"login":"postgres://user:SECRET-MARKER-123@host/db"}"#.as_slice();

        let assert_clean = |inp: &[u8], r: &Run, want_status: i32| {
            let err = r.stderr_string();
            assert_eq!(
                r.status,
                want_status,
                "input={:?}, stderr={err}",
                String::from_utf8_lossy(inp)
            );
            for needle in ["SECRET-MARKER-123", "SECRET-M", "postgres://user:"] {
                assert!(
                    !err.contains(needle),
                    "leaked {needle:?} in stderr for {:?}: {err}",
                    String::from_utf8_lossy(inp)
                );
            }
        };

        let sel = select_item(crate::ITEM);
        for (inp, want_err) in [
            (
                bare_url,
                "jq: error (at <stdin>:0): Cannot iterate over string\n",
            ),
            (
                bare_short,
                "jq: error (at <stdin>:0): Cannot iterate over string\n",
            ),
            (
                num,
                "jq: error (at <stdin>:0): Cannot iterate over number\n",
            ),
            (null, "jq: error (at <stdin>:0): Cannot iterate over null\n"),
        ] {
            let r = run(inp, RunOptions::compact(), &sel);
            assert_clean(inp, &r, 5);
            assert_eq!(r.stderr_string(), want_err);
        }
        for inp in [arr_url, nested_obj] {
            assert_clean(inp, &run(inp, RunOptions::compact(), &sel), 5);
        }

        for inp in [bare_url, bare_short, num] {
            assert_clean(inp, &run(inp, RunOptions::raw(), status), 5);
            assert_clean(inp, &run(inp, RunOptions::raw(), password), 5);
        }
        assert_clean(
            nested_login,
            &run(nested_login, RunOptions::raw(), password),
            5,
        );
        assert_clean(null, &run(null, RunOptions::raw(), status), 0);
        assert_clean(null, &run(null, RunOptions::raw(), password), 0);
    }
}
