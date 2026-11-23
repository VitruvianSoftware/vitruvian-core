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
