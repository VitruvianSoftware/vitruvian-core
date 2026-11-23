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

//! Standard-library-only jq 1.8 compatibility primitives for Rust CLI ports:
//! exact decimal numbers, order-preserving JSON objects, stream parsing with
//! jq 1.8 parse-error diagnostics, jq total ordering (`sort`/`sort_by`/`group_by`/`unique`),
//! `jq` / `-c` / `-r` / `-S` writers, `tostring`, jq 1.8 error wording and
//! truncation, and jq 1.8 stream exit-status semantics.

pub mod error;
pub mod format;
pub mod order;
pub mod parse;
pub mod run;
pub mod value;

pub use error::{
    cannot_index_number, cannot_index_string, cannot_iterate, format_parse_error,
    format_runtime_error,
};
pub use format::{
    compact, compact_sorted, dump_string, dump_trunc, format_value, interpolate, pretty,
    pretty_sorted, raw, raw_compact, raw_sorted, tostring, uri_encode, OutputOptions,
};
pub use order::{compare, group_by, jq_eq, sort, sort_by, unique, unique_by};
pub use parse::{parse_one, parse_stream, parse_stream_str, StreamItem};
pub use run::{each, one, run, Produced, RunOptions, RunResult};
pub use value::{Number, Value};
