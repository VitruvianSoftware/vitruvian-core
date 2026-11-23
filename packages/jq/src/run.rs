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

//! jq 1.8 stream runner and exit-status evaluator.

use crate::error::{format_parse_error, format_runtime_error};
use crate::format::{format_value, OutputOptions};
use crate::parse::{parse_stream, StreamItem};
use crate::value::Value;

/// Outputs produced by a filter on one input value, plus the runtime error that
/// aborted further output for that input (earlier outputs still stand).
pub type Produced = (Vec<Value>, Option<String>);

/// Runner options mirroring `jq [-c] [-r] [-S] [-e]`.
#[derive(Copy, Clone, Debug, Default, PartialEq, Eq)]
pub struct RunOptions {
    pub output: OutputOptions,
    /// Mirrors `jq -e`: exit 0 if last output is truthy, 1 if `false` or `null`,
    /// 4 if no output was produced (still 5 if the last value or parser errored).
    pub exit_status: bool,
}

impl RunOptions {
    pub const fn pretty() -> Self {
        Self {
            output: OutputOptions::pretty(),
            exit_status: false,
        }
    }

    pub const fn compact() -> Self {
        Self {
            output: OutputOptions::compact(),
            exit_status: false,
        }
    }

    pub const fn raw() -> Self {
        Self {
            output: OutputOptions::raw(),
            exit_status: false,
        }
    }

    pub const fn raw_compact() -> Self {
        Self {
            output: OutputOptions::raw_compact(),
            exit_status: false,
        }
    }

    pub const fn raw_exit() -> Self {
        Self {
            output: OutputOptions::raw(),
            exit_status: true,
        }
    }

    pub const fn sorted() -> Self {
        Self {
            output: OutputOptions::sorted(),
            exit_status: false,
        }
    }

    pub const fn sorted_compact() -> Self {
        Self {
            output: OutputOptions::sorted_compact(),
            exit_status: false,
        }
    }

    pub const fn raw_sorted() -> Self {
        Self {
            output: OutputOptions::raw_sorted(),
            exit_status: false,
        }
    }
}

/// Captured stdout, stderr, and exit status from running a jq filter stream.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct RunResult {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub status: i32,
}

impl RunResult {
    pub fn stdout_string(&self) -> String {
        String::from_utf8_lossy(&self.stdout).into_owned()
    }

    pub fn stderr_string(&self) -> String {
        String::from_utf8_lossy(&self.stderr).into_owned()
    }
}

/// Lifts a single-result expression into [`Produced`].
pub fn one(res: Result<Value, String>) -> Produced {
    match res {
        Ok(v) => (vec![v], None),
        Err(e) => (Vec::new(), Some(e)),
    }
}

/// Applies `f` to each element of `items`, collecting outputs until the first error.
pub fn each(items: Result<Vec<Value>, String>, f: impl Fn(&Value) -> Produced) -> Produced {
    let items = match items {
        Ok(v) => v,
        Err(e) => return (Vec::new(), Some(e)),
    };
    let mut outs = Vec::new();
    for item in &items {
        let (o, err) = f(item);
        outs.extend(o);
        if err.is_some() {
            return (outs, err);
        }
    }
    (outs, None)
}

/// `a // empty`: keeps truthy outputs from `a` and propagates any runtime error
/// (jq `//` does not swallow errors in its left operand).
pub fn or_empty((outs, err): Produced) -> Produced {
    (outs.into_iter().filter(Value::truthy).collect(), err)
}

/// `a // b`: emits all truthy outputs of `a`, or evaluates `fallback` when `a`
/// produced no truthy values without error. A runtime error in `a` is propagated
/// without evaluating `fallback` (matching jq 1.8).
pub fn alt((outs, err): Produced, fallback: impl FnOnce() -> Produced) -> Produced {
    let truthy: Vec<Value> = outs.into_iter().filter(Value::truthy).collect();
    if err.is_some() || !truthy.is_empty() {
        (truthy, err)
    } else {
        fallback()
    }
}

/// `first(items | f)`: applies `f` to elements of `items` and short-circuits on
/// the first output value (even if `false` or `null`, without evaluating later
/// items that might error). Propagates an error from `items` or from `f` if it
/// occurs before any value is produced.
pub fn first(items: Result<Vec<Value>, String>, mut f: impl FnMut(&Value) -> Produced) -> Produced {
    let items = match items {
        Ok(v) => v,
        Err(e) => return (Vec::new(), Some(e)),
    };
    for item in &items {
        let (outs, err) = f(item);
        if let Some(v) = outs.into_iter().next() {
            return (vec![v], None);
        }
        if err.is_some() {
            return (Vec::new(), err);
        }
    }
    (Vec::new(), None)
}

/// `any(items; pred)`: evaluates `pred` across `items`, short-circuiting with
/// `true` on the first match without evaluating later items, returning `false`
/// if no item matches, or propagating the first error before a match.
pub fn any(
    items: Result<Vec<Value>, String>,
    mut pred: impl FnMut(&Value) -> Result<bool, String>,
) -> Produced {
    let items = match items {
        Ok(v) => v,
        Err(e) => return (Vec::new(), Some(e)),
    };
    for item in &items {
        match pred(item) {
            Ok(true) => return (vec![Value::Bool(true)], None),
            Ok(false) => {}
            Err(e) => return (Vec::new(), Some(e)),
        }
    }
    (vec![Value::Bool(false)], None)
}

/// Runs `filter` over the JSON stream in `input`, matching jq 1.8's stream
/// semantics and exit status:
/// - Runtime errors emit `jq: error (at <stdin>:N): ...` and processing continues.
/// - Status is `5` iff a parse error occurred OR the **last** parsed input value errored.
/// - With `opts.exit_status` (`-e`), if status would be 0, returns `4` when no output
///   was emitted, `0` if the last output is truthy, or `1` if it is `false` or `null`.
pub fn run(
    input: &[u8],
    opts: RunOptions,
    mut filter: impl FnMut(&Value) -> Produced,
) -> RunResult {
    let mut res = RunResult::default();
    let mut last_output: Option<Value> = None;
    let mut last_errored = false;
    let mut parse_errored = false;

    for item in parse_stream(input) {
        match item {
            StreamItem::Value(v, line) => {
                let (outs, err) = filter(&v);
                for o in outs {
                    res.stdout
                        .extend_from_slice(format_value(&o, opts.output).as_bytes());
                    res.stdout.push(b'\n');
                    last_output = Some(o);
                }
                if let Some(msg) = err {
                    res.stderr
                        .extend_from_slice(format_runtime_error(line, &msg).as_bytes());
                    last_errored = true;
                } else {
                    last_errored = false;
                }
            }
            StreamItem::ParseError(msg) => {
                res.stderr
                    .extend_from_slice(format_parse_error(&msg).as_bytes());
                parse_errored = true;
                break;
            }
        }
    }

    res.status = if parse_errored || last_errored {
        5
    } else if !opts.exit_status {
        0
    } else {
        match last_output {
            None => 4,
            Some(v) if v.truthy() => 0,
            Some(_) => 1,
        }
    };
    res
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn or_empty_filters_falsy_and_preserves_errors() {
        assert_eq!(
            or_empty((
                vec![
                    Value::Bool(false),
                    Value::int(1),
                    Value::Null,
                    Value::int(0)
                ],
                None
            )),
            (vec![Value::int(1), Value::int(0)], None)
        );
        assert_eq!(
            or_empty((vec![Value::Bool(false), Value::int(1)], Some("boom".into()))),
            (vec![Value::int(1)], Some("boom".into()))
        );
    }

    #[test]
    fn alt_uses_fallback_only_when_empty_and_error_free() {
        let mut called = false;
        let out = alt((vec![Value::int(1)], None), || {
            called = true;
            (vec![Value::str("fallback")], None)
        });
        assert!(!called);
        assert_eq!(out, (vec![Value::int(1)], None));

        let out = alt((vec![Value::Bool(false), Value::Null], None), || {
            called = true;
            (vec![Value::str("fallback")], None)
        });
        assert!(called);
        assert_eq!(out, (vec![Value::str("fallback")], None));

        let mut called_on_err = false;
        let out = alt((vec![Value::Null], Some("err".into())), || {
            called_on_err = true;
            (vec![Value::str("fallback")], None)
        });
        assert!(!called_on_err);
        assert_eq!(out, (vec![], Some("err".into())));
    }

    #[test]
    fn first_short_circuits_on_first_value_even_if_falsy() {
        let items = Ok(vec![
            Value::object([("a".into(), Value::Bool(false))]),
            Value::int(5),
        ]);
        assert_eq!(
            first(items, |v| one(v.index("a"))),
            (vec![Value::Bool(false)], None)
        );

        let items = Ok(vec![
            Value::int(5),
            Value::object([("a".into(), Value::int(1))]),
        ]);
        assert!(first(items, |v| one(v.index("a"))).1.is_some());
    }

    #[test]
    fn any_short_circuits_and_propagates_prior_errors() {
        let items = Ok(vec![
            Value::object([("fileName".into(), Value::str("a"))]),
            Value::str("x"),
        ]);
        assert_eq!(
            any(items, |v| Ok(v.index("fileName")?.is_str("a"))),
            (vec![Value::Bool(true)], None)
        );

        let items = Ok(vec![
            Value::str("x"),
            Value::object([("fileName".into(), Value::str("a"))]),
        ]);
        assert!(any(items, |v| Ok(v.index("fileName")?.is_str("a")))
            .1
            .is_some());

        let items = Ok(vec![Value::object([("fileName".into(), Value::str("b"))])]);
        assert_eq!(
            any(items, |v| Ok(v.index("fileName")?.is_str("a"))),
            (vec![Value::Bool(false)], None)
        );
    }
}
